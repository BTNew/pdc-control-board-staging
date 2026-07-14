'use strict';

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const desktopCss = fs.readFileSync(path.join(root, 'desktop-operations.css'), 'utf8');
const htmlFiles = ['index.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];
const expectedVersion = '2026.07.15.01-audit-correctness-performance';

assert.ok(app.includes(`const APP_VERSION = '${expectedVersion}';`));
assert.match(app, /function productionGridHeaderHtml\(/);
assert.match(app, /function incomingWorkChecklistHtml\(/);
assert.match(app, /data-pmb-work-transfer-key/);
assert.match(app, /function bindPmbWorkTransferSelects\(/);
assert.match(app, /movePmbVehicleToStage\(select\.dataset\.pmbWorkTransferKey, stage\)/);
assert.match(app, /class="incoming-work-checks pdc-station-strip"/);
assert.match(app, /pdc-production-grid-row/);
assert.match(app, /pdc-production-grid-static-row/);
assert.match(app, /<span>Key<\/span><span>Stock<\/span><span>Job Card<\/span><span>Customer<\/span>/);

for (const station of ['Parts', 'Tint', 'Hoist', 'Fitting', 'Fabrication', 'Electrical', 'Tyre', 'Pit Inspection']) {
  assert.ok(app.includes(`'${station}'`) || app.includes(`\`${station}`) || app.includes(`>${station}<`) || app.includes(station), `Missing full station label: ${station}`);
}

assert.doesNotMatch(app, /truncate\(\s*(?:customer|vehicleCustomerName)/i, 'Customer names must not be truncated');
assert.match(app, /<th>Status<\/th><th>Vehicle ID<\/th><th>Customer \/ vehicle<\/th><th>Kewdale ETA<\/th><th>Parts ETA<\/th><th>Blocker<\/th><th>Stage \/ update<\/th><th>Actions<\/th>/);
assert.match(app, /<th>Collected<\/th><th>Key<\/th><th>Stock<\/th><th>Job Card<\/th><th>Customer<\/th><th>Vehicle<\/th>/);
assert.match(app, /<thead><tr><th>Key<\/th><th>Stock<\/th><th>Job Card<\/th><th>Customer<\/th><th>Vehicle<\/th>/);

const v2Css = css.slice(css.indexOf('2026.07.10.22 — Production Grid V2'));
assert.ok(v2Css.length > 1000, 'Production Grid V2 CSS block is missing');
assert.match(v2Css, /--pdc-grid-template:/);
assert.match(v2Css, /--pdc-station-template:/);
assert.match(v2Css, /\.pdc-production-grid-header,[\s\S]*?grid-template-columns:\s*var\(--pdc-grid-template\)/);
assert.match(v2Css, /\.pdc-grid-stations-heading,[\s\S]*?grid-template-columns:\s*var\(--pdc-station-template\)/);
assert.match(v2Css, /\.identity-name \.vehicle-identity-value,[\s\S]*?white-space:\s*normal\s*!important/);
assert.match(v2Css, /\.incoming-work-label[\s\S]*?white-space:\s*nowrap\s*!important/);
assert.match(v2Css, /\.incoming-vehicle-card,[\s\S]*?overflow:\s*visible\s*!important/);
assert.match(desktopCss, /\.parts-queue-table\s*\{[\s\S]*?min-width:\s*1480px/);
assert.match(v2Css, /\.completed-table\s*\{[\s\S]*?width:\s*1730px\s*!important/);
assert.match(v2Css, /\.backend-data-table\s*\{[\s\S]*?width:\s*1640px\s*!important/);

for (const file of htmlFiles) {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  assert.ok(html.includes(expectedVersion), `${file} has stale cache-busting/version text`);
  assert.ok(html.includes('desktop-operations.css'), `${file} is missing the desktop operations stylesheet`);
  assert.ok(html.includes('data-view="backend"'), `${file} is missing Back End Data navigation`);
  assert.ok(html.includes('id="backend"'), `${file} is missing the Back End Data view`);
  assert.ok(html.includes('Fabrication'), `${file} is missing the full Fabrication label`);
  assert.ok(html.includes('Electrical'), `${file} is missing the full Electrical label`);
  assert.ok(html.includes('Tyre'), `${file} is missing the full Tyre label`);
  assert.ok(html.includes('Pit Inspection'), `${file} is missing the full Pit Inspection label`);
}

console.log('Production Grid V2 regression checks passed');
