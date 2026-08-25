'use strict';
const assert = require('assert');
const fs = require('fs');

const css = fs.readFileSync('styles.css', 'utf8');
const start = css.indexOf('/* Compact desktop sidebar; retain accessible coarse-pointer targets. */');
assert.ok(start >= 0, 'compact desktop sidebar override exists');
const compact = css.slice(start);
assert.match(compact, /@media \(min-width: 821px\)/);
assert.match(compact, /\.app-shell \{\s*grid-template-columns: 176px minmax\(0, 1fr\) !important;/,
  'desktop sidebar column is visibly narrower than the previous 220px');
assert.match(compact, /\.sidebar \{\s*padding: 14px 10px !important;\s*gap: 10px !important;\s*overflow-x: hidden;/);
assert.match(compact, /\.sidebar \.brand \{\s*gap: 7px !important;/);
assert.match(compact, /\.sidebar \.nav \{\s*gap: 2px;\s*margin-top: 6px;/);
assert.match(compact, /\.sidebar \.nav \.nav-item \{\s*min-height: 34px;\s*padding: 7px 12px;\s*border-radius: 10px;\s*line-height: 1\.15;/);
assert.match(compact, /\.sidebar \.nav \.nav-workshop-item \{\s*gap: 7px;\s*padding-block: 6px;/);
assert.match(compact, /\.sidebar \.nav \.nav-section-label \{\s*margin: 5px 8px 1px;/);
assert.match(compact, /@media \(min-width: 821px\) and \(pointer: coarse\)[\s\S]*min-height: 44px;/,
  'coarse-pointer sidebar items retain 44px targets');
console.log('Compact desktop sidebar spacing: PASS');
