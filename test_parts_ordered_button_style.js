'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');

const actionStart = app.indexOf('function partsQueueActionsHtml');
const actionEnd = app.indexOf('\nfunction bindPartsQueueActionButtons', actionStart);
assert.ok(actionStart >= 0 && actionEnd > actionStart);
const actions = app.slice(actionStart, actionEnd);
assert.match(actions, /class="small-button parts-ordered-button"[^>]+data-parts-ordered=/, 'Mark ordered has the dedicated light-green class');
assert.doesNotMatch(actions, /class="[^"]*primary[^"]*"[^>]+data-parts-ordered=/, 'Mark ordered no longer inherits red primary styling');
assert.match(actions, /data-parts-complete=/, 'Mark received remains a separate unmodified action');
assert.match(actions, /data-parts-stoppage=/, 'Parts STOPPAGE remains a separate unmodified action');

for (const selector of [
  '.parts-ordered-button[data-parts-ordered] {',
  '.parts-ordered-button[data-parts-ordered]:hover:not(:disabled) {',
  '.parts-ordered-button[data-parts-ordered]:focus-visible {',
  '.parts-ordered-button[data-parts-ordered]:disabled {',
]) assert.ok(css.includes(selector), `missing dedicated selector ${selector}`);
assert.match(css, /\.parts-ordered-button\[data-parts-ordered\][\s\S]*?background:\s*#dcfce7;[\s\S]*?color:\s*#14532d;[\s\S]*?border:\s*1px solid #86efac;/);
assert.match(css, /@media\s*\(pointer:\s*coarse\)[\s\S]*?button,[\s\S]*?min-height:\s*44px;[\s\S]*?min-width:\s*44px;/);
assert.ok(!css.includes('.primary { background: #dcfce7'), 'global primary style remains unchanged');

console.log('Parts Mark ordered dedicated presentation: PASS');
