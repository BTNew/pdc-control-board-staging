'use strict';
const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const start = app.indexOf('function partsQueueActionsHtml');
const end = app.indexOf('function bindPartsQueueActionButtons', start);
assert.ok(start >= 0 && end > start, 'Parts action renderer exists');
const actions = app.slice(start, end);
assert.match(actions, /class="small-button parts-ordered-button"[^>]+data-parts-ordered=/, 'Mark ordered has a dedicated class');
assert.doesNotMatch(actions, /class="[^"]*primary[^"]*"[^>]+data-parts-ordered=/, 'Mark ordered no longer inherits primary styling');
assert.match(css, /\.parts-ordered-button\[data-parts-ordered\]\s*\{[^}]*background:\s*#dcfce7;[^}]*color:\s*#14532d;/s, 'light-green accessible base style exists');
assert.match(css, /\.parts-ordered-button\[data-parts-ordered\]:hover:not\(:disabled\)/, 'hover state exists');
assert.match(css, /\.parts-ordered-button\[data-parts-ordered\]:focus-visible/, 'focus-visible state exists');
assert.match(css, /\.parts-ordered-button\[data-parts-ordered\]:disabled/, 'disabled state exists');
console.log('Parts Mark ordered dedicated presentation: PASS');
