/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const builder = require('./scripts/build_pages_runtime.js');

const STARTUP_ORDER = [
  // r441 (F52): the release auto-reload check loads first, not deferred, so it sees every save request.
  'pdc-auto-reload.js',
  'pdc-deferred-script-order.js',
  'pdc-workshop-departments.js',
  'pdc-department-filter.js',
  'canonical-entry.js',
  'pdc-estimated-hours.js',
  'vendor/supabase/supabase-2.110.5.js',
  'pdc-supabase-config.staging.js',
  'site-switcher.js',
  // r495 (F108): the Karratha Toyota (Sales) Website option runs right after the frozen shared switcher.
  'site-switcher-branches.js',
  'pdc-auth.js',
  'pdc-auth-registration.js',
  'pdc-lazy-admin-views.js',
  'email-board-data.js',
  'pdc-email-ai-v2-actions.js',
  'arb-labor-catalog.js',
  'ai-board-advisor.js',
  'navision-backend-service.js',
  'sales/navision-orders.js',
  'broome-navision-import.js',
  'navision-vin.js',
  'pdc-ai-intake-service.js',
  'workshop-eligibility.js',
  'workshop-navigation.js',
  'vehicle-requirements-guard.js',
  'pdc-email-vehicle-location-service.js',
  'pdc-ai-auditor-stage-a.js',
  'vehicle-location-lifecycle.js',
  'vehicle-modal-identity.js',
  'vehicle-locations-refresh.js',
  'vehicle-locations-refresh-ui.js',
  'workshop-data-service.js',
  'pdc-vehicle-handover.js',
  'workshop-display-identity.js',
  'workshop-booking-timing.js',
  'control-board-overview.js',
  'app.js',
  'pdc-stacked-jobcards.js',
  'pdc-ai-intake-review.js',
  'pdc-email-ai-successor-inbox.js',
  'pdc-staff-usage.js',
  'pdc-planner-capacity.js',
  'pdc-emergency-priority.js',
  'pdc-conversions.js',
  'pdc-bus-component-split.js',
  'pdc-fitters.js',
  'pdc-workshop-hours.js',
  'pdc-vehicle-sublets.js' // r494 (F107): Manage sublets per vehicle
];

function scriptTags(html) {
  return [...html.matchAll(/<script\b([^>]*)>/g)].map(match => {
    const attrs = match[1];
    const src = (attrs.match(/\bsrc="([^"]+)"/) || [])[1] || '';
    return {
      file: src.replace(/&amp;/g, '&').split('?')[0],
      deferred: /(?:^|\s)defer(?:\s|=|$)/.test(attrs),
      plain: /(?:^|\s)type="text\/plain"/.test(attrs)
    };
  });
}

test('the live board defers every startup script in the previous order and keeps the boot guard blocking', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  const tags = scriptTags(html);
  assert.deepEqual(tags.map(tag => tag.file), STARTUP_ORDER);
  assert.equal(tags[0].deferred, false);
  assert.equal(tags[1].deferred, false);
  assert.deepEqual(tags.slice(2).map(tag => tag.deferred), tags.slice(2).map(() => true));
  assert.match(html, new RegExp('styles\\.css\\?[^"]*publish-minify=' + builder.PUBLISH_ASSET_VERSION));
  assert.match(html, new RegExp('<script src="app\\.js\\?[^"]*publish-minify=' + builder.PUBLISH_ASSET_VERSION));
  for (const removed of ['data-staging-empty.js', 'scripts/stage2b_c4_browser_export.js', 'staging-browser-assessment.js']) {
    assert.equal(html.includes(removed), false, removed);
    assert.equal(fs.existsSync(removed), true, removed);
    assert.equal(builder.RUNTIME_FILES.includes(removed), true, removed);
  }
  const guard = fs.readFileSync('pdc-deferred-script-order.js', 'utf8');
  assert.match(guard, /PDC_DEFERRED_SCRIPT_ORDER = true/);
  assert.match(guard, /readyState/);
  const app = fs.readFileSync('app.js', 'utf8');
  const css = fs.readFileSync('styles.css', 'utf8');
  assert.match(app, /document\.readyState === 'loading'/);
  assert.match(app, /\nfunction init\(\)/);
  assert.match(css, /\.pdc-auth-gate \{/);
  assert.equal(builder.RUNTIME_FILES.includes('pdc-deferred-script-order.js'), true);
});

test('sales and the parked department page do not take the live board defer change', () => {
  const sales = scriptTags(fs.readFileSync('sales/index.html', 'utf8'));
  assert.ok(sales.length > 5);
  assert.equal(sales.some(tag => tag.deferred || tag.file === 'pdc-deferred-script-order.js'), false);
  const karrathaHtml = fs.readFileSync('karratha/index.html', 'utf8');
  const karratha = scriptTags(karrathaHtml);
  const executable = karratha.filter(tag => !tag.plain);
  assert.deepEqual(executable.map(tag => tag.file), ['pd135-visibility.js', 'pd135-board-loader.js']);
  assert.equal(executable.some(tag => tag.deferred), false);
  assert.equal(karrathaHtml.includes('pdc-deferred-script-order.js'), false);
});

test('staging integrity installs the minifiers before it builds a Pages artifact', () => {
  const workflow = fs.readFileSync('.github/workflows/staging-integrity.yml', 'utf8');
  const install = workflow.indexOf('npm ci --ignore-scripts');
  const legacy = workflow.indexOf('node test_legacy_website_links.js');
  const suite = workflow.indexOf('node --test test_*.js');
  assert.ok(install !== -1 && legacy !== -1 && suite !== -1);
  assert.ok(install < legacy && install < suite);
});

test('the Pages workflow installs the minifiers without adding a publish action', () => {
  const workflow = fs.readFileSync('.github/workflows/pages-runtime.yml', 'utf8');
  assert.match(workflow, /npm ci --ignore-scripts/);
  const install = workflow.indexOf('npm ci --ignore-scripts');
  const tests = workflow.indexOf('node --test test_*.js');
  const build = workflow.indexOf('node scripts/build_pages_runtime.js --output _site');
  assert.ok(install < tests && tests < build);
  const source = fs.readFileSync('scripts/build_pages_runtime.js', 'utf8');
  assert.match(source, /toplevel: false/);
  assert.match(source, /unused: false/);
  assert.match(source, /side_effects: false/);
  assert.match(source, /restructure: false/);
  assert.match(source, /Publish-time minifier is missing/);
  assert.match(source, /filename !== 'app\.js' && filename !== 'styles\.css'/);
});
