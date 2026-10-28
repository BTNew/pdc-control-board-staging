'use strict';
// r613 (F228): the key-number box waits for typing to stop, so 432 is not searched (and opened) as 4.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

test('key search waits for typing to stop; Enter searches now; cache bust', () => {
  const js = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(js, /const KEY_SEARCH_WAIT_MS = 700;/);
  assert.match(js, /keyTimer = setTimeout\(queue, KEY_SEARCH_WAIT_MS\)/);
  assert.match(js, /event\.key === 'Enter'\) \{ clearTimeout\(keyTimer\); queue\(\); \}/);
  assert.doesNotMatch(js, /keyLabel\.querySelector\('input'\)\.addEventListener\('input', queue\)/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-locations-table\.js\?[^']*&r613=2026\.10\.28\.r613'/);
});
