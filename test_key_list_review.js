'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const staging = fs.readFileSync(path.join(root, 'staging.html'), 'utf8');
const production = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

for (const html of [staging, production]) {
  assert.doesNotMatch(html, /key-list-review-panel|PMB key-list staging review/, 'obsolete key-list staging review panel must not render');
  assert.doesNotMatch(html, /<script[^>]+key-list-review\.js/i, 'obsolete key-list review module must not load');
}
assert.match(staging, /id="backend" class="view"/, 'Back End Data view must remain available');
assert.match(staging, /id="backend-data-count"/, 'Back End Data status and controls must remain available');
assert.match(staging, /id="backend-data-search"/, 'Back End Data vehicle search must remain available');
assert.match(staging, /id="backend-data-refresh-shared"/, 'shared Navision refresh must remain available');

console.log('PASS obsolete key-list staging review removed while Back End Data remains intact');
