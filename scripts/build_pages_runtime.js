'use strict';

// This builds an artifact only. It does not change GitHub Pages settings or deploy.
// Add runtime dependencies explicitly after review; never copy the repository root.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
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
  // Department 135: frozen native PMB runtime plus reviewed isolated boundary assets.
  'karratha/ai-auditor.css',
  'karratha/ai-board-advisor.js',
  'karratha/app.js',
  'karratha/arb-labor-catalog.js',
  'karratha/assets/brand-logo.svg',
  'karratha/assets/karratha-toyota-logo.svg',
  'karratha/assets/pmb-logo.png',
  'karratha/broome-navision-import.js',
  'karratha/canonical-entry.js',
  'karratha/control-board-overview.js',
  'karratha/data-staging-empty.js',
  'karratha/deployment-manifest.json',
  'karratha/desktop-operations.css',
  'karratha/email-board-data.js',
  'karratha/favicon.svg',
  'karratha/index.html',
  'karratha/navision-backend-service.js',
  'karratha/navision-vin.js',
  'karratha/pd135-api-map.js',
  'karratha/pd135-board-loader.js',
  'karratha/pd135-navigation.js',
  'karratha/pd135-visibility.js',
  'karratha/pd135-nuvu-intake.css',
  'karratha/pd135-nuvu-intake.js',
  'karratha/pd135-nuvu-parser.js',
  'karratha/pd135-transport.js',
  'karratha/pdc-ai-auditor-stage-a.js',
  'karratha/pdc-ai-intake-review.css',
  'karratha/pdc-ai-intake-review.js',
  'karratha/pdc-ai-intake-service.js',
  'karratha/pdc-auth-registration.js',
  'karratha/pdc-auth.js',
  'karratha/pdc-book-all-stations.js',
  'karratha/pdc-bus-workflow.css',
  'karratha/pdc-bus-workflow.js',
  'karratha/pdc-completed-history.css',
  'karratha/pdc-conversions.js',
  'karratha/pdc-department-filter.js',
  'karratha/pdc-email-ai-successor-inbox.css',
  'karratha/pdc-email-ai-successor-inbox.js',
  'karratha/pdc-email-ai-v2-actions.js',
  'karratha/pdc-email-vehicle-location-service.js',
  'karratha/pdc-emergency-priority.css',
  'karratha/pdc-emergency-priority.js',
  'karratha/pdc-estimated-hours.css',
  'karratha/pdc-estimated-hours.js',
  'karratha/pdc-fitters.css',
  'karratha/pdc-fitters.js',
  'karratha/pdc-location-override.js',
  'karratha/pdc-new-vehicles.css',
  'karratha/pdc-new-vehicles.js',
  'karratha/pdc-parts-confirmation.js',
  'karratha/pdc-planner-capacity.css',
  'karratha/pdc-planner-capacity.js',
  'karratha/pdc-planner-slim.css',
  'karratha/pdc-planner-slim.js',
  'karratha/pdc-professional-polish.css',
  'karratha/pdc-qc-mobile.css',
  'karratha/pdc-qc-mobile.js',
  'karratha/pdc-qc-rework.js',
  'karratha/pdc-review-stations.css',
  'karratha/pdc-review-stations.js',
  'karratha/pdc-rft-actions.css',
  'karratha/pdc-rft-actions.js',
  'karratha/pdc-service-locations.js',
  'karratha/pdc-stacked-jobcards.css',
  'karratha/pdc-stacked-jobcards.js',
  'karratha/pdc-staff-usage.css',
  'karratha/pdc-staff-usage.js',
  'karratha/pdc-sublet-intake.js',
  'karratha/pdc-supabase-config.staging.js',
  'karratha/pdc-update-history.css',
  'karratha/pdc-update-history.js',
  'karratha/pdc-vehicle-handover.js',
  'karratha/pdc-workshop-hours.js',
  'karratha/pdc-workshop-tile-cleanup.js',
  'karratha/pdc-workshop-usability.js',
  'karratha/sales/navision-orders.js',
  'karratha/scripts/stage2b_c4_browser_export.js',
  'karratha/site-switcher.css',
  'karratha/site-switcher.js',
  'karratha/staging-browser-assessment.js',
  'karratha/styles.css',
  'karratha/vehicle-lifecycle-actions.js',
  'karratha/vehicle-location-lifecycle.js',
  'karratha/vehicle-locations-refresh-ui.js',
  'karratha/vehicle-locations-refresh.js',
  'karratha/vehicle-modal-identity.js',
  'karratha/vehicle-requirements-guard.js',
  'karratha/vendor/pdfjs/LICENSE',
  'karratha/vendor/pdfjs/pdf.min.js',
  'karratha/vendor/pdfjs/pdf.worker.min.js',
  'karratha/vendor/qz/qz-tray.js',
  'karratha/vendor/supabase/supabase-2.110.5.js',
  'karratha/vendor/xlsx/LICENSE',
  'karratha/vendor/xlsx/xlsx.full.min.js',
  'karratha/workshop-booking-timing.js',
  'karratha/workshop-data-service.js',
  'karratha/workshop-display-identity.js',
  'karratha/workshop-eligibility.js',
  'karratha/workshop-navigation.js',
  'karratha/workshop-planner.css',
  'karratha/workshop-planner.js',
  'karratha/workshop-realtime.js',
  'karratha/workshop-reference-data-service.js',
  'karratha/workshop-shared-actions.js',
  'navision-backend-service.js', 'navision-vin.js', 'no-vehicles.html',
  'pdc-ai-auditor-stage-a.js', 'pdc-ai-intake-review.css', 'pdc-ai-intake-review.js',
  'pdc-ai-intake-service.js', 'pdc-auth-registration.js', 'pdc-auth.js',
  'pdc-book-all-stations.js', 'pdc-bus-workflow.css', 'pdc-bus-workflow.js',
  'pdc-completed-history.css', 'pdc-conversion-ticks.css', 'pdc-conversions.js', 'pdc-deferred-script-order.js', 'pdc-department-filter.js', 'pdc-workshop-departments.js',
  'pdc-email-ai-successor-inbox.css', 'pdc-email-ai-successor-inbox.js',
  'pdc-email-ai-v2-actions.js', 'pdc-email-vehicle-location-service.js',
  'pdc-emergency-priority.css', 'pdc-emergency-priority.js',
  'pdc-estimated-hours.css', 'pdc-estimated-hours.js', 'pdc-fitters.css', 'pdc-fitters.js',
  'pdc-location-override.js', 'pdc-new-vehicles.css', 'pdc-new-vehicles.js', 'pdc-operation-review-slim.css',
  'pdc-parts-confirmation.js', 'pdc-planner-capacity.css', 'pdc-planner-capacity.js',
  'pdc-planner-slim.css', 'pdc-planner-slim.js', 'pdc-professional-polish.css',
  'pdc-qc-mobile.css', 'pdc-qc-mobile.js', 'pdc-qc-rework.js',
  'pdc-review-stations.css', 'pdc-review-stations.js', 'pdc-rft-actions.css',
  'pdc-rft-actions.js', 'pdc-service-locations.js', 'pdc-parts-eta.js', 'pdc-sublet-po.js', 'pdc-sublet-po-attach.js', 'pdc-operation-panels.js', 'pdc-stacked-jobcards.css',
  'pdc-stacked-jobcards.js', 'pdc-staff-usage.css', 'pdc-staff-usage.js',
  'pdc-sublet-intake.js', 'pdc-supabase-config.staging.js', 'pdc-update-history.css',
  'pdc-update-history.js', 'pdc-vehicle-handover.js', 'pdc-workshop-hours.js',
  'pdc-workshop-tile-cleanup.js', 'pdc-workshop-usability.js',
  'pd-department-navigation.js',
  'pdc-auto-reload.js',
  'sales/assets/broome-toyota-logo.png', 'sales/build-requirements.css',
  'sales/build-requirements.js', 'sales/crm-workspace.css',
  'sales/crm-workspace.js', 'sales/customer-emails.js', 'sales/dashboard-tools.js',
  'sales/email-actions.js', 'sales/finance-pipeline.css', 'sales/finance-pipeline.js',
  'sales/index.html', 'sales/navision-orders.js', 'sales/sales-accessories.css', 'sales/sales-accessories.js', 'sales/sales.css',
  'sales/sales.js', 'sales/vehicle-notes.js', 'sales/completed-vehicles.js', 'sales/zebra-labels.js',
  // The read-only browser helper stays allowlisted so it can be restored.
  // index.html no longer loads it on startup. No other scripts/ files ship.
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
// r441 (F52): the build writes version.json and tags these pages with the same
// build id, so open tabs can tell a new release has shipped and reload once.
// Karratha (Department 135) keeps its frozen runtime and is not tagged.
const BUILD_VERSION_FILE = 'version.json';
const BUILD_TAGGED_PAGES = Object.freeze(['index.html', 'sales/index.html', 'docs/bus4x4-user-guide.html']);
const AUTO_RELOAD_SCRIPT = /<script src="(?:\.\.\/)?pdc-auto-reload\.js\?v=[^"]+"><\/script>/g;
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
  if (filename.endsWith('.js') && !filename.startsWith('vendor/') && !filename.startsWith('karratha/vendor/')) {
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
  for (const prefix of ['', 'karratha/']) {
  const context = { window: {} };
  for (const filename of ['data-staging-empty.js', 'email-board-data.js']) vm.runInNewContext(buffers.get(prefix + filename).toString('utf8'), context, { timeout: 100 });
  const tracking = context.window.VEHICLE_TRACKING_DATA;
  const email = context.window.PDC_EMAIL_BOARD_DATA;
  if (!tracking || !email || !Array.isArray(tracking.vehicles) || tracking.vehicles.length || !Array.isArray(email.vehicles) || email.vehicles.length || !Array.isArray(email.reviews) || email.reviews.length || Object.keys(tracking.toyotaMatches || {}).length) throw new Error('Public fallback contains operational records');
  if (Object.keys(tracking).some(k => !['report', 'vehicles', 'toyotaMatches'].includes(k)) || Object.keys(email).some(k => !['generatedAt', 'source', 'vehicles', 'reviews'].includes(k))) throw new Error('Public fallback has unreviewed fields');
  }
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
  if (allowed.has(BUILD_VERSION_FILE)) throw new Error('version.json is generated by the build and cannot be a source file');
  for (const page of BUILD_TAGGED_PAGES) {
    const html = buffers.get(page).toString('utf8');
    if ((html.match(AUTO_RELOAD_SCRIPT) || []).length !== 1) throw new Error(`Auto-reload script must be included exactly once: ${page}`);
    if (/<meta name="pdc-build"/.test(html)) throw new Error(`Build tag must be added by the build, not the source: ${page}`);
  }
  return { sourceRoot, buffers, fileCount: buffers.size, byteCount: [...buffers.values()].reduce((n, b) => n + b.length, 0) };
}

const PUBLISH_ASSET_VERSION = '2026.10.19.01';
const PUBLISHED_SOURCE_MAPS = Object.freeze(['app.js.map', 'styles.css.map']);

function loadPublishMinifiers() {
  let terser;
  let csso;
  try {
    terser = require('terser');
    csso = require('csso');
  } catch (error) {
    throw new Error('Publish-time minifier is missing. Run npm ci before building the Pages artifact.');
  }
  if (typeof terser.minify_sync !== 'function' || typeof csso.minify !== 'function') {
    throw new Error('Publish-time minifier is missing. Run npm ci before building the Pages artifact.');
  }
  return { terser, csso };
}

function assertPublishedTextSafe(filename, text) {
  if (findPrivilegedTokens(text).length) throw new Error(`Privileged token in published asset: ${filename}; value redacted`);
}

function publishedAsset(filename, bytes) {
  if (filename !== 'app.js' && filename !== 'styles.css') return [[filename, bytes]];
  const { terser, csso } = loadPublishMinifiers();
  const source = bytes.toString('utf8');
  if (filename === 'app.js') {
    const result = terser.minify_sync({ 'app.js': source }, {
      compress: { unused: false, side_effects: false },
      mangle: { toplevel: false },
      sourceMap: { filename: 'app.js', url: 'app.js.map', includeSources: true }
    });
    if (!result || result.error || !result.code || !result.code.includes('function init(') || !result.code.includes('sourceMappingURL=app.js.map')) {
      throw new Error('Could not minify published app.js');
    }
    const map = typeof result.map === 'string' ? result.map : JSON.stringify(result.map || '');
    if (!map.includes('"sourcesContent"')) throw new Error('Could not minify published app.js');
    assertPublishedTextSafe('app.js', result.code);
    return [['app.js', Buffer.from(result.code)], ['app.js.map', Buffer.from(map)]];
  }
  const result = csso.minify(source, { filename: 'styles.css', sourceMap: true, restructure: false });
  let css = result && result.css || '';
  if (!css.includes('.pdc-auth-gate')) throw new Error('Could not minify published styles.css');
  if (!css.includes('sourceMappingURL=styles.css.map')) css += '\n/*# sourceMappingURL=styles.css.map */\n';
  const map = result.map ? result.map.toString() : '';
  if (!map.includes('"sources"')) throw new Error('Could not minify published styles.css');
  assertPublishedTextSafe('styles.css', css);
  return [['styles.css', Buffer.from(css)], ['styles.css.map', Buffer.from(map)]];
}

// Content hash of everything published (before tagging), so a merge that changes
// no published byte (docs, tests, SQL) does not reload anyone's page.
function buildIdentity(outputs) {
  const hash = crypto.createHash('sha256');
  for (const [filename, bytes] of [...outputs].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))) {
    hash.update(filename).update('\0').update(String(bytes.length)).update('\0').update(bytes);
  }
  return 'b-' + hash.digest('hex').slice(0, 20);
}

function tagBuildPage(filename, bytes, build) {
  const html = bytes.toString('utf8');
  const charset = html.match(/<meta charset="utf-8"\s*\/?>/i);
  if (!charset) throw new Error(`Cannot add the build tag (no charset meta): ${filename}`);
  const at = charset.index + charset[0].length;
  return Buffer.from(html.slice(0, at) + `<meta name="pdc-build" content="${build}">` + html.slice(at));
}

function versionFile(build, env = process.env) {
  const body = { build };
  if (/^[0-9a-f]{40}$/.test(env.GITHUB_SHA || '')) body.commit = env.GITHUB_SHA.slice(0, 12);
  return Buffer.from(JSON.stringify(body) + '\n');
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
  // Source app.js and styles.css stay unchanged. Only these published copies are minified.
  fs.mkdirSync(outputRoot, { recursive: true });
  const outputs = [];
  for (const [filename, bytes] of prepared.buffers) outputs.push(...publishedAsset(filename, bytes));
  const build = buildIdentity(outputs);
  for (const pair of outputs) if (BUILD_TAGGED_PAGES.includes(pair[0])) pair[1] = tagBuildPage(pair[0], pair[1], build);
  outputs.push([BUILD_VERSION_FILE, versionFile(build)]);
  for (const [filename, bytes] of outputs) {
    const target = path.join(outputRoot, filename);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, bytes, { flag: 'wx' });
  }
  return {
    outputRoot,
    build,
    fileCount: outputs.length,
    byteCount: outputs.reduce((total, pair) => total + pair[1].length, 0)
  };
}

if (require.main === module) {
  try {
    const args = process.argv.slice(2), sourceRoot = path.resolve(__dirname, '..');
    if (args.length === 1 && args[0] === '--validate') {
      const result = validateRuntime(sourceRoot);
      console.log(`Runtime Pages allowlist validated: ${result.fileCount} files; ${result.byteCount} bytes`);
    } else if (args.length === 2 && args[0] === '--output') {
      const result = buildRuntimeArtifact(sourceRoot, args[1]);
      console.log(`Runtime Pages artifact ready: ${result.fileCount} files; ${result.byteCount} bytes; build ${result.build}; ${result.outputRoot}`);
    } else throw new Error('Usage: node scripts/build_pages_runtime.js --validate | --output <new-or-empty-directory>');
  } catch (error) { console.error(`Runtime Pages build failed: ${error.message}`); process.exitCode = 1; }
}

module.exports = {
  ENTRY_POINTS, RUNTIME_FILES, PUBLISH_ASSET_VERSION, PUBLISHED_SOURCE_MAPS,
  BUILD_VERSION_FILE, BUILD_TAGGED_PAGES,
  safePublicPath, validateRuntime, buildRuntimeArtifact, buildIdentity, tagBuildPage, versionFile
};
