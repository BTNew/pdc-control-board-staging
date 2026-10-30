'use strict';
// r678 (F288): the fitter iPad shows Later, not the "Send this line" / move-to-bay picker.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const src = fs.readFileSync('pdc-fitters.js', 'utf8');
test('fitter cards are built without handoff targets, so no move-to-bay picker', () => {
  assert.doesNotMatch(src, /handoffTargets: detail\?\.handoff_targets/);
  assert.match(src, /fitterLaterHtml\(line, cardState\)/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-fitters\.js\?[^"]*&amp;r678=2026\.10\.29\.r678(&amp;r740=2026\.10\.30\.r740)?"/);
});
test('a card with no targets has Later and no Send this line', () => {
  const { fitterLineCardHtml } = require('./pdc-fitters.js');
  const line = { line_identity: 'source:00000000-0000-4000-8000-000000000001', description: 'Synthetic item', stage_code: 'FITTING', hours: 1, completed: false };
  const html = fitterLineCardHtml(line, 0, { editable: true, disabled: false, note: '', open: false, stageCode: 'FITTING' });
  assert.match(html, /<summary>Later<\/summary>/);
  assert.doesNotMatch(html, /Send this line|data-fitter-handoff=/);
});
