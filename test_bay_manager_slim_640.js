'use strict';
// r640 (F255): Bay Manager slim rows: pencil rename, Edit hours and Hide on the right, no breaks, errors on the bay.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const js = fs.readFileSync('pdc-bay-manager.js', 'utf8');

test('no break fields; saved weeks carry no breaks', () => {
  assert.doesNotMatch(js, /data-break-start|data-break-finish|Breaks<\/th>/);
  assert.match(js, /hours\[day\] = \{ off, start, finish, breaks: \[\] \};/);
});
test('one row: name + pencil, then Edit hours and Hide bay on the right; rename inline', () => {
  assert.match(js, /class="bay-manager-pencil" data-rename title="Change name"/);
  assert.match(js, /<span class="bay-manager-row-actions"><button type="button" data-hours>/);
  assert.match(js, /data-active>\$\{bay\.is_active \? 'Hide bay' : 'Show bay'\}/);
  assert.match(js, /class="bay-manager-rename"><input type="text" name="display" maxlength="40"/);
  assert.match(js, /set_workshop_bay_display_name/); assert.match(js, /set_workshop_bay_active/);
});
test('refusals show on the bay with plain words (hide with open bookings)', () => {
  assert.match(js, /bay_in_use: 'This bay has open bookings\. Move or finish them, then hide it\.'/);
  assert.match(js, /catch \(error\) \{ bayError\(bay\.id, error\); \}/);
  const css = fs.readFileSync('pdc-bay-manager.css', 'utf8');
  assert.match(css, /\.bay-manager-row-actions \{ margin-left: auto;/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /pdc-bay-manager\.js\?[^"]*&amp;r640=2026\.10\.28\.r640"/);
  assert.match(html, /pdc-bay-manager\.css\?[^"]*&amp;r640=2026\.10\.28\.r640(?:&amp;r816=2026\.11\.02\.r816)?"/);
});
