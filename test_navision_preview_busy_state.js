'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');

const start = app.indexOf('async function importNavisionVehicles()');
const end = app.indexOf('\nfunction importNavisionVehiclesLocal', start);
const preview = app.slice(start, end);
assert.ok(start >= 0 && end > start);
assert.ok(preview.indexOf('if (app.navisionPreviewInFlight === true) return;') < preview.indexOf("const input = $('#navision-paste')"), 'double click is suppressed before parsing');
assert.ok(preview.indexOf('setNavisionPreviewBusy(true);') < preview.indexOf('await navisionWaitForBusyPaint();'), 'busy state is rendered before yielding one paint');
assert.ok(preview.indexOf('await navisionWaitForBusyPaint();') < preview.indexOf('parseNavisionInput(text, options)'), 'paint occurs before parsing/heavy preview work');
assert.ok(preview.includes('try {') && preview.includes('} finally {') && preview.includes('setNavisionPreviewBusy(false);'), 'success, validation, rejection, exception and cancellation all restore busy state');
assert.ok(preview.indexOf('setNavisionPreviewBusy(false);') > preview.indexOf('enrichSharedNavisionPreviewChanges'), 'busy state covers enrichment and final render');

const updateStart = app.indexOf('function updateNavisionImportButton()');
const updateEnd = app.indexOf('\nfunction setNavisionSharedApplyBusy', updateStart);
const update = app.slice(updateStart, updateEnd);
for (const marker of [
  'app.navisionPreviewInFlight === true', "button.setAttribute('aria-busy'", 'Previewing…',
  "['navision-upload', 'navision-paste', 'navision-dealer-code']", 'applyButton.disabled = busy', 'clear.disabled = busy',
]) assert.ok(update.includes(marker), `busy renderer missing ${marker}`);
assert.ok(app.includes("Previewing Navision data. No data has been applied."));
assert.match(index, /id="navision-preview-status"[^>]+role="status"[^>]+aria-live="polite"/);
assert.match(css, /#import-navision\.is-loading[\s\S]*cursor:\s*wait/);
assert.match(css, /#import-navision\s*\{\s*min-width:\s*132px/);
assert.match(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{\s*\.navision-button-spinner\s*\{\s*animation:\s*none/);
assert.match(css, /@media\s*\(pointer:\s*coarse\)[\s\S]*min-height:\s*44px/);

console.log('Navision preview immediate busy state: PASS');
