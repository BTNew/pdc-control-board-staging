'use strict';
// r615 (F230): QC shows the key number and lists lowest key first.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const src = fs.readFileSync('app.js', 'utf8');
const pick = name => src.slice(src.indexOf(`function ${name}(`), src.indexOf('\n}\n', src.indexOf(`function ${name}(`)) + 3);

test('QC sorts by key number, lowest first, no key last, stable', () => {
  const ctx = { vehicleKeyNumber: v => v.k || '' };
  vm.runInNewContext(pick('qcPageKeySortValue') + pick('qcPageSortByKeyNumber') + ';this.sort=qcPageSortByKeyNumber;', ctx);
  const out = ctx.sort([{ s: 'a', k: '432' }, { s: 'b' }, { s: 'c', k: '4' }, { s: 'd', k: 'K57' }, { s: 'e' }, { s: 'f', k: '0' }]);
  assert.deepEqual(out.map(r => r.s), ['c', 'd', 'a', 'b', 'e', 'f']);
});

test('QC cards show a key badge (desktop html and phone decorator), cache bust', () => {
  assert.match(src, /qcPageSortByKeyNumber\(eligible\) : eligible; \/\/ r615/);
  assert.match(src, /class="qc-key-badge" style="\$\{QC_KEY_BADGE_STYLE\}">K\$\{escapeHtml\(vehicleKeyNumber\(vehicle\)\)\}/);
  assert.match(src, /querySelectorAll\('\.qc-phone-vehicle\[data-qc-open-vehicle\]'\)/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /app\.js\?[^"]*&amp;r615=2026\.10\.28\.r615(&amp;r619=2026\.10\.28\.r619)?(&amp;r642=2026\.10\.28\.r642)?(&amp;r679=2026\.10\.29\.r679)?(&amp;r681=2026\.10\.29\.r681)?(&amp;r687=2026\.10\.29\.r687)?(&amp;r683=2026\.10\.29\.r683)?(&amp;r692=2026\.10\.29\.r692)?(&amp;r693=2026\.10\.29\.r693)?(&amp;r698=2026\.10\.29\.r698)?(&amp;r707=2026\.10\.29\.r707)?(&amp;r710=2026\.10\.29\.r710)?"/);
});
