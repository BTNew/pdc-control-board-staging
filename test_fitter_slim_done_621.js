'use strict';
// r621 (F236): fitter tablet refreshes every 5 minutes; completed items in a slim Completed group.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const src = fs.readFileSync('pdc-fitters.js', 'utf8');

test('background refresh every 5 minutes, not 10 seconds', () => {
  assert.match(src, /const FITTER_BACKGROUND_REFRESH_MS = 300000;/);
  assert.match(src, /refresh\(\{background:true\}\);\},FITTER_BACKGROUND_REFRESH_MS\);/);
  assert.doesNotMatch(src, /refresh\(\{background:true\}\);\},10000\);/);
});

test('To do first, Completed after as slim rows; card order kept', () => {
  const start = src.indexOf('function fitterLinesByDoneHtml');
  const end = src.indexOf('\n  }\n', start) + 4;
  const ctx = {}; vm.runInNewContext(src.slice(start, end) + ';this.f=fitterLinesByDoneHtml;', ctx);
  const html = ctx.f([{ id: 'a', completed: true }, { id: 'b' }, { id: 'c', completed: true }], (l, i) => `<i>${l.id}${i}</i>`);
  assert.match(html, /<h3>To do \(1\)<\/h3><div class="fitter-lines fitter-todo-list"><i>b1<\/i><\/div>/);
  assert.match(html, /Completed \(2\)<\/h3><div class="fitter-lines fitter-done-list"><i>a0<\/i><i>c2<\/i><\/div>/);
  assert.match(ctx.f([{ id: 'a' }], (l, i) => 'x'), /<h3>To do \(1\)/);
  assert.doesNotMatch(ctx.f([{ id: 'a' }], () => 'x'), /Completed/);
  assert.match(src, /\.fitter-done-list \.fitter-line>\*:not\(\.fitter-line-check\):not\(details\)\{display:none!important\}/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-fitters\.js\?[^"]*&amp;r621=2026\.10\.28\.r621(&amp;r626=2026\.10\.28\.r626)?(&amp;r627=2026\.10\.28\.r627)?(&amp;r678=2026\.10\.29\.r678)?(&amp;r740=2026\.10\.30\.r740)?(&amp;r741=2026\.10\.30\.r741)?(?:&amp;r816=2026\.11\.02\.r816)?"/);
});

test('r626 (F241): To do slimmer, Completed tight grid rows', () => {
  assert.match(src, /\.fitter-todo-list \.fitter-line\{padding:6px 10px;border-radius:8px;display:flex/);
  assert.match(src, /\.fitter-done-list\{display:grid;grid-template-columns:repeat\(auto-fill,minmax\(240px,1fr\)\)/);
  assert.match(src, /\.fitter-done-list \.fitter-line-check strong\{display:block;font-size:13px/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-fitters\.js\?[^"]*&amp;r626=2026\.10\.28\.r626(&amp;r627=2026\.10\.28\.r627)?(&amp;r678=2026\.10\.29\.r678)?(&amp;r740=2026\.10\.30\.r740)?(&amp;r741=2026\.10\.30\.r741)?(?:&amp;r816=2026\.11\.02\.r816)?"/);
});
