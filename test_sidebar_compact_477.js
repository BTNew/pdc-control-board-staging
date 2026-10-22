'use strict';
// r477 (F90): PMG sidebar compressed (spacing only) and the Parts nav item hidden behind a flag.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const css = fs.readFileSync('pdc-sidebar-compact.css', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');

test('PMG index.html loads the override last, after styles.css and every other stylesheet', () => {
  const links = [...index.matchAll(/<link rel="stylesheet" href="([^"]+)"/g)].map(m => m[1]);
  assert.match(links[links.length - 1], /^pdc-sidebar-compact\.css\?sidebar-compact=2026\.10\.22\.r477$/);
  assert.ok(links.findIndex(h => /^styles\.css/.test(h)) < links.length - 1);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-sidebar-compact\.css'/);
});

test('PMG only: Karratha and the Broome Sales site do not load it', () => {
  for (const file of ['karratha/index.html', 'sales/index.html']) assert.doesNotMatch(fs.readFileSync(file, 'utf8'), /pdc-sidebar-compact/, file);
});

test('same items, order and labels: index.html nav markup still has every item, Parts included', () => {
  const nav = index.slice(index.indexOf('<nav class="nav">'), index.indexOf('</nav>'));
  const views = [...nav.matchAll(/data-view="([^"]+)"/g)].map(m => m[1]);
  for (const v of ['dashboard', 'qc', 'fitters', 'workflow', 'planner-bus-mechanical', 'planner-hoist', 'planner-tint', 'planner-tyre', 'parts', 'sublet', 'lists'])
    assert.ok(views.includes(v), `${v} still in the nav`);
  assert.ok(views.indexOf('parts') < views.indexOf('sublet'), 'order unchanged');
  assert.match(nav, /<button type="button" class="nav-item" data-view="parts" data-short="PA">Parts<\/button>/, 'Parts button not deleted');
});

test('Parts hidden by a flag that is easy to flip back; nothing else is hidden', () => {
  assert.match(css, /html:not\(\[data-pdc-nav-parts="show"\]\) body \.sidebar \.nav \.nav-item\[data-view="parts"\] \{ display: none !important; \}/);
  const body = css.replace(/\/\*[\s\S]*?\*\//g, '');
  assert.equal((body.match(/display:\s*none/g) || []).length, 1, 'only the Parts item is hidden');
  assert.doesNotMatch(body, /visibility:\s*hidden|content\s*:/);
});

test('spacing and size only, desktop sidebar only; click targets stay at least 22 px; text stays 14 px', () => {
  const body = css.replace(/\/\*[\s\S]*?\*\//g, '');
  assert.doesNotMatch(body, /(^|[;{\s])(color|background(-color)?|border-color|order|text-transform)\s*:/, 'no colour, order or label change');
  assert.match(body, /@media \(min-width: 1201px\)/);
  for (const m of body.matchAll(/min-height:\s*(\d+)px/g)) if (Number(m[1])) assert.ok(Number(m[1]) >= 22, `min-height ${m[1]}px`);
  assert.doesNotMatch(body, /\.nav-item[^{]*\{[^}]*font-size/, 'nav item text size unchanged');
});

test('FAULT_LOG F90 and boundary pin comment', () => {
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /^\| F90 \|.*r477.*pdc-sidebar-compact\.css/m);
  assert.match(fs.readFileSync('test_karratha_release_boundary.js', 'utf8'), /r477: index\.html loads pdc-sidebar-compact\.css\?sidebar-compact=2026\.10\.22\.r477/);
});
