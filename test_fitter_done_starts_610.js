'use strict';
// r610 (F224): on the fitter iPad, Done on an item that was never started starts it and ticks it in one tap.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('Done falls back to Start then Done only for an unstarted item, never on retry', () => {
  const src = fs.readFileSync('pdc-fitters.js', 'utf8');
  assert.match(src, /first\.code!=='item_not_started'/);
  assert.match(src, /if\(retry \|\| action!=='line' \|\| completed!==true/, 'only a fresh Done tap, not a retry or an untick');
  assert.match(src, /p_action:'item_start',p_completed:null,p_note:null/);
  assert.match(src, /p_expected_version:started\?\.version\?\?body\.p_expected_version/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-fitters\.js\?[^"]*&amp;r610=2026\.10\.28\.r610(&amp;r621=2026\.10\.28\.r621)?(&amp;r626=2026\.10\.28\.r626)?(&amp;r627=2026\.10\.28\.r627)?"/);
});
