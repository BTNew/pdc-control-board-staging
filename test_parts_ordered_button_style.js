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
assert.match(actions, /const canMarkOrdered = partsHasValidAuthoritativeEta\(vehicle\);/, 'Mark ordered derives readiness from strict authoritative ETA');
assert.match(actions, /disabled aria-disabled="true"/, 'Mark ordered is disabled accessibly when ETA is missing');
assert.match(actions, /Set Parts ETA before marking ordered/, 'disabled control has a clear explanation');
assert.match(actions, /data-parts-complete=/, 'Mark received remains a separate unmodified action');
assert.match(actions, /data-parts-stoppage=/, 'Parts STOPPAGE remains a separate unmodified action');
for (const selector of [
  '.parts-ordered-button[data-parts-ordered] {',
  '.parts-ordered-button[data-parts-ordered]:hover:not(:disabled) {',
  '.parts-ordered-button[data-parts-ordered]:focus-visible {',
  '.parts-ordered-button[data-parts-ordered]:disabled {',
]) assert.ok(css.includes(selector), `missing dedicated selector ${selector}`);
assert.match(css, /\.parts-ordered-button\[data-parts-ordered\][\s\S]*?background:\s*#dcfce7;[\s\S]*?color:\s*#14532d;/);
assert.match(css, /@media\s*\(pointer:\s*coarse\)[\s\S]*?min-height:\s*44px;[\s\S]*?min-width:\s*44px;/);
const orderedStart = app.indexOf('async function markVehiclePartsOrdered');
const orderedEnd = app.indexOf('async function markVehiclePartsComplete', orderedStart);
const orderedHandler = app.slice(orderedStart, orderedEnd);
assert.match(orderedHandler, /partsHasValidAuthoritativeEta\(vehicle\)/, 'handler rejects missing/invalid authoritative ETA');
assert.match(orderedHandler, /partsHasValidAuthoritativeEta\(sharedVehicle\)/, 'handler rechecks resolved authoritative ETA');
console.log('Parts Mark ordered dedicated presentation: PASS');
