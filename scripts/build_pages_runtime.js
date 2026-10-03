'use strict';

// This builds an artifact only. It does not change GitHub Pages settings or deploy.
// Add runtime dependencies explicitly after review; never copy the repository root.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { findPrivilegedTokens } = require('./check_frontend_secrets.js');

const ENTRY_POINTS = Object.freeze([
  'index.html', 'sales/index.html', 'karratha/index.html', 'docs/bus4x4-user-guide.html',
  'no-vehicles.html', 'staging.html', 'test-50.html', 'test-75.html', 'test-100.html'
]);
const RUNTIME_FILES = Object.freeze([
  '.nojekyll',
  'ai-auditor.css', 'ai-board-advisor.js', 'app.js', 'arb-labor-catalog.js',
  'assets/pmb-logo.png', 'broome-navision-import.js', 'canonical-entry.js',
  'control-board-overview.js', 'data-staging-empty.js', 'deployment-manifest.json',
  'desktop-operations.css',
  'docs/assets/bus4x4-guide/forecasts.png', 'docs/assets/bus4x4-guide/qa-pit.png',
  'docs/assets/bus4x4-guide/stage-parts.png', 'docs/assets/bus4x4-guide/supplier-check.png',
  'docs/assets/bus4x4-guide/team.png', 'docs/bus4x4-user-guide.html',
  'email-board-data.js', 'favicon.svg', 'index.html',
  'karratha/api.js', 'karratha/app.js', 'karratha/auth.js',
  'karratha/calendar.css', 'karratha/calendar.js', 'karratha/config.js',
  'karratha/index.html', 'karratha/karratha.css', 'karratha/nuvu.js',
  'navision-backend-service.js', 'navision-vin.js', 'no-vehicles.html',
  'pdc-ai-auditor-stage-a.js', 'pdc-ai-intake-review.css', 'pdc-ai-intake-review.js',
  'pdc-ai-intake-service.js', 'pdc-auth-registration.js', 'pdc-auth.js',
  'pdc-book-all-stations.js', 'pdc-bus-workflow.css', 'pdc-bus-workflow.js',
  'pdc-completed-history.css', 'pdc-conversions.js', 'pdc-department-filter.js',
  'pdc-email-ai-successor-inbox.css', 'pdc-email-ai-successor-inbox.js',
  'pdc-email-ai-v2-actions.js', 'pdc-email-vehicle-location-service.js',
  'pdc-emergency-priority.css', 'pdc-emergency-priority.js',
  'pdc-estimated-hours.css', 'pdc-estimated-hours.js', 'pdc-fitters.css', 'pdc-fitters.js',
  'pdc-location-override.js', 'pdc-new-vehicles.css', 'pdc-new-vehicles.js',
  'pdc-parts-confirmation.js', 'pdc-planner-capacity.css', 'pdc-planner-capacity.js',
  'pdc-planner-slim.css', 'pdc-planner-slim.js', 'pdc-professional-polish.css',
  'pdc-qc-mobile.css', 'pdc-qc-mobile.js', 'pdc-qc-rework.js',
  'pdc-review-stations.css', 'pdc-review-stations.js', 'pdc-rft-actions.css',
  'pdc-rft-actions.js', 'pdc-service-locations.js', 'pdc-stacked-jobcards.css',
  'pdc-stacked-jobcards.js', 'pdc-staff-usage.css', 'pdc-staff-usage.js',
  'pdc-sublet-intake.js', 'pdc-supabase-config.staging.js', 'pdc-update-history.css',
  'pdc-update-history.js', 'pdc-vehicle-handover.js', 'pdc-workshop-hours.js',
  'pdc-workshop-tile-cleanup.js', 'pdc-workshop-usability.js',
  'pd-department-navigation.js',
  'sales/assets/broome-toyota-logo.png', 'sales/build-requirements.css',
  'sales/build-requirements.js', 'sales/crm-workspace.css',
  'sales/crm-workspace.js', 'sales/customer-emails.js', 'sales/dashboard-tools.js',
  'sales/email-actions.js', 'sales/finance-pipeline.css', 'sales/finance-pipeline.js',
  'sales/index.html', 'sales/navision-orders.js', 'sales/sales.css',
  'sales/sales.js', 'sales/zebra-labels.js',
  // Existing read-only browser helper is loaded by index.html; no other scripts ship.
  'scripts/stage2b_c4_browser_export.js',
  'site-switcher.css', 'site-switcher.js', 'staging-browser-assessment.js', 'staging.html',
  'styles.css', 'test-50.html', 'test-75.html', 'test-100.html',
  'vehicle-lifecycle-actions.js', 'vehicle-location-lifecycle.js',
  'vehicle-locations-refresh-ui.js', 'vehicle-locations-refresh.js',
  'vehicle-modal-identity.js', 'vehicle-requirements-guard.js',
  'vendor/pdfjs/LICENSE', 'vendor/pdfjs/pdf.min.js', 'vendor/pdfjs/pdf.worker.min.js',
  'vendor/qz/qz-tray.js', 'vendor/supabase/supabase-2.110.5.js',
  'vendor/xlsx/LICENSE', 'vendor/xlsx/xlsx.full.min.js',
  'workshop-booking-timing.js', 'workshop-data-service.js', 'workshop-display-identity.js',
  'workshop-eligibility.js', 'workshop-navigation.js', 'workshop-planner.css',
  'workshop-planner.js', 'workshop-realtime.js', 'workshop-reference-data-service.js',
  'workshop-shared-actions.js'
].sort());
const allowed = new Set(RUNTIME_FILES);
const forbiddenRoots = /^(?:\.git(?:hub)?|backend|data|handoffs|qa|review-evidence|runtime_release|supabase|tests|tools|work|outputs)(?:\/|$)/;

function safePublicPath(filename) {
  if (typeof filename !== 'string' || !filename || filename.includes('\\') || path.posix.normalize(filename) !== filename || filename.startsWith('/') || filename.startsWith('../')) return false;
  if (forbiddenRoots.test(filename)) return false;
  if (filename.startsWith('scripts/') && filename !== 'scripts/stage2b_c4_browser_export.js') return false;
  if (/(?:^|\/)(?:test_|browser_|\.env|.*\.(?:sql|py|ps1|zip|xlsx|csv|tsv|log|bin|enc|pem|key)$)/i.test(filename)) return false;
  return allowed.has(filename);
}

function checkedFile(sourceRoot, filename) {
  if (!safePublicPath(filename)) throw new Error(`Unapproved public artifact path: ${filename}`);
  let current = sourceRoot;
  for (const component of filename.split('/')) {
    current = path.join(current, component);
    if (fs.lstatSync(current).isSymbolicLink()) throw new Error(`Runtime symlink is not allowed: ${filename}`);
  }
  if (!fs.statSync(current).isFile()) throw new Error(`Runtime asset is not a file: ${filename}`);
  return current;
}

function localReference(sourceRoot, from, value) {
  const ref = String(value).replace(/&amp;/g, '&').split(/[?#]/)[0];
  if (!ref || /^(?:https?:|data:|mailto:|tel:|javascript:|blob:|\/)/i.test(ref) || /\$\{|[<>]/.test(ref)) return null;
  const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(from), ref));
  if (resolved === '.' || resolved.endsWith('/')) return 'index.html';
  if (resolved.startsWith('../')) throw new Error(`Runtime reference escapes the site: ${from}`);
  const absolute = path.join(sourceRoot, resolved);
  if (fs.existsSync(absolute) && fs.statSync(absolute).isDirectory()) return path.posix.join(resolved, 'index.html');
  return resolved;
}

function validateDependencies(sourceRoot, filename, text) {
  const refs = [];
  if (filename.endsWith('.html')) {
    for (const m of text.matchAll(/(?:src|href)=["']([^"']+)["']/g)) {
      const resolved = localReference(sourceRoot, filename, m[1]);
      if (resolved) refs.push(resolved);
    }
  }
  if (filename.endsWith('.css')) {
    for (const m of text.matchAll(/url\(\s*["']?([^\s"')]+)["']?\s*\)/g)) {
      const resolved = localReference(sourceRoot, filename, m[1]);
      if (resolved) refs.push(resolved);
    }
  }
  // Existing literal dependencies cover deferred planner, PDF, QZ and mobile loaders.
  // The reviewed vendor bundles use their own bundled internals, so do not treat
  // vendor-internal module examples or generated filenames as site dependencies.
  if (filename.endsWith('.js') && !filename.startsWith('vendor/')) {
    for (const m of text.matchAll(/["'`]([^"'`\r\n]+?\.(?:js|css|json|html|png|svg|woff2?)(?:\?[^"'`\r\n]*)?)["'`]/g)) {
      const literal = m[1].split('?')[0];
      if (!/^[A-Za-z0-9_.\/-]+$/.test(literal)) continue;
      const resolved = localReference(sourceRoot, filename, literal);
      if (resolved && fs.existsSync(path.join(sourceRoot, resolved))) refs.push(resolved);
    }
  }
  for (const ref of refs) if (!safePublicPath(ref)) throw new Error(`Runtime dependency is not allowlisted: ${filename} -> ${ref}`);
}

function validateEmptyFallbacks(buffers) {
  const context = { window: {} };
  for (const filename of ['data-staging-empty.js', 'email-board-data.js']) vm.runInNewContext(buffers.get(filename).toString('utf8'), context, { timeout: 100 });
  const tracking = context.window.VEHICLE_TRACKING_DATA;
  const email = context.window.PDC_EMAIL_BOARD_DATA;
  if (!tracking || !email || !Array.isArray(tracking.vehicles) || tracking.vehicles.length || !Array.isArray(email.vehicles) || email.vehicles.length || !Array.isArray(email.reviews) || email.reviews.length || Object.keys(tracking.toyotaMatches || {}).length) throw new Error('Public fallback contains operational records');
  if (Object.keys(tracking).some(k => !['report', 'vehicles', 'toyotaMatches'].includes(k)) || Object.keys(email).some(k => !['generatedAt', 'source', 'vehicles', 'reviews'].includes(k))) throw new Error('Public fallback has unreviewed fields');
}

function validateRuntime(sourceRoot) {
  sourceRoot = fs.realpathSync(path.resolve(sourceRoot));
  if (allowed.size !== RUNTIME_FILES.length) throw new Error('Duplicate runtime artifact paths');
  const buffers = new Map();
  for (const filename of RUNTIME_FILES) {
    const bytes = fs.readFileSync(checkedFile(sourceRoot, filename));
    buffers.set(filename, bytes);
    if (/\.(?:js|css|html|json)$/.test(filename)) {
      const text = bytes.toString('utf8');
      if (findPrivilegedTokens(text).length) throw new Error(`Privileged token in runtime asset: ${filename}; value redacted`);
      validateDependencies(sourceRoot, filename, text);
    }
  }
  const manifest = JSON.parse(buffers.get('deployment-manifest.json'));
  const keys = ['siteVersion', 'workshopPlannerVersion', 'salesTrackerVersion'];
  if (Object.keys(manifest).length !== keys.length || keys.some(k => typeof manifest[k] !== 'string' || !manifest[k] || manifest[k].length > 100)) throw new Error('Public deployment manifest contains unreviewed fields');
  const salesVersion = buffers.get('sales/index.html').toString('utf8').match(/src="sales\.js\?v=([^"&]+)/)?.[1];
  if (!salesVersion || manifest.salesTrackerVersion !== salesVersion) throw new Error('Sales deployment version does not match the public entry point');
  validateEmptyFallbacks(buffers);
  return { sourceRoot, buffers, fileCount: buffers.size, byteCount: [...buffers.values()].reduce((n, b) => n + b.length, 0) };
}

function buildRuntimeArtifact(sourceRoot, outputRoot) {
  const prepared = validateRuntime(sourceRoot);
  outputRoot = path.resolve(outputRoot);
  const relative = path.relative(outputRoot, prepared.sourceRoot);
  if (!relative || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) throw new Error('Artifact output cannot replace or contain the source checkout');
  if (fs.existsSync(outputRoot)) {
    if (fs.lstatSync(outputRoot).isSymbolicLink() || !fs.statSync(outputRoot).isDirectory() || fs.readdirSync(outputRoot).length) throw new Error('Artifact output must be a new or empty regular directory');
  }
  let ancestor = path.dirname(outputRoot);
  while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
  const realAncestor = fs.realpathSync(ancestor);
  if ((process.platform === 'win32' ? realAncestor.toLowerCase() !== ancestor.toLowerCase() : realAncestor !== ancestor)) throw new Error('Artifact output cannot pass through a symlink or redirected directory');
  // Do not delete or overwrite existing artifacts. A fresh destination is required.
  fs.mkdirSync(outputRoot, { recursive: true });
  for (const [filename, bytes] of prepared.buffers) {
    const target = path.join(outputRoot, filename);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, bytes, { flag: 'wx' });
  }
  return { outputRoot, fileCount: prepared.fileCount, byteCount: prepared.byteCount };
}

if (require.main === module) {
  try {
    const args = process.argv.slice(2), sourceRoot = path.resolve(__dirname, '..');
    if (args.length === 1 && args[0] === '--validate') {
      const result = validateRuntime(sourceRoot);
      console.log(`Runtime Pages allowlist validated: ${result.fileCount} files; ${result.byteCount} bytes`);
    } else if (args.length === 2 && args[0] === '--output') {
      const result = buildRuntimeArtifact(sourceRoot, args[1]);
      console.log(`Runtime Pages artifact ready: ${result.fileCount} files; ${result.byteCount} bytes; ${result.outputRoot}`);
    } else throw new Error('Usage: node scripts/build_pages_runtime.js --validate | --output <new-or-empty-directory>');
  } catch (error) { console.error(`Runtime Pages build failed: ${error.message}`); process.exitCode = 1; }
}

module.exports = { ENTRY_POINTS, RUNTIME_FILES, safePublicPath, validateRuntime, buildRuntimeArtifact };
