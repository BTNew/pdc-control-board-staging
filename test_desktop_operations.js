const fs = require('fs');
const assert = require('assert');

const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8') + fs.readFileSync('desktop-operations.css', 'utf8');
const htmlFiles = ['index.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];

assert.ok(app.includes("const APP_VERSION = '2026.07.14.04-email-pdf-parse';"));
assert.ok(app.includes('function workStatusLegendHtml()'));
assert.ok(app.includes('options.showDelete ?'));
assert.ok(app.includes('data-modal-cancel'));
assert.ok(app.includes('detail-danger-zone'));
assert.ok(app.includes('parts-table-wrap parts-queue-wrap'));
assert.ok(app.includes('rft-detail-actions'));
assert.ok(app.includes("/(?:test-\\d+|no-vehicles)\\.html$/i.test(path)"));
assert.ok(app.includes('window.PDC_ALLOW_LOCAL_RESET === true'));
assert.ok(app.includes('jita-icon jita-unknown'));
assert.ok(app.includes('PDC sheet · ${backEndOnlyCount} back end only'));

const partsHeaders = ['Status', 'Vehicle ID', 'Customer / vehicle', 'Kewdale ETA', 'Parts ETA', 'Blocker', 'Stage / update', 'Actions'];
for (const heading of partsHeaders) {
  assert.ok(app.includes(`<th>${heading}</th>`), `Parts heading missing: ${heading}`);
}

assert.ok(css.includes('.parts-queue-wrap'));
assert.ok(css.includes('overflow: auto !important'));
assert.ok(css.includes('#vehicle-modal .edit-actions'));
assert.ok(css.includes('position: sticky'));
assert.ok(css.includes('.workflow-floating-column-header'));
assert.ok(css.includes('.workflow-production-grid-header .workflow-column-filter'));
assert.ok(css.includes('body[data-current-view="workflow"] .workflow-board-panel { overflow: visible !important; }'));
assert.ok(app.includes('data-workflow-header-filter'));
assert.ok(app.includes('function updateWorkflowFloatingHeader()'));

for (const file of htmlFiles) {
  const html = fs.readFileSync(file, 'utf8');
  assert.ok(html.includes('desktop-operations.css?v=2026.07.14.04-email-pdf-parse'), `${file} is missing the desktop stylesheet`);
  assert.ok(!html.includes('id="workflow-sticky-filters"'), `${file} still contains the separate workflow filter toolbar`);
  assert.ok(html.includes('id="workflow-board"'), `${file} is missing the workflow board host`);
}

console.log('Desktop operations regression checks passed.');
