'use strict';
// r707 (F317, Craig 29 Oct, standing rule): at PMB the age is days since the key number; a vehicle at PMB with a key is
// in the PMB bucket, and New to PMB is only the second list of keys under 24 hours.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
test('key first for the PMB age', () => {
  assert.match(app, /const keyFirst = vehicle\.keyAssignedAt \|\| vehicle\.key_assigned_at \|\| \(pmbVehicleHasKey\(vehicle\) \? pmbKeyAssignedTimestamp\(vehicle\) : ''\);\n  if \(keyFirst && Number\.isFinite\(parseIsoTimestamp\(keyFirst\)\?\.getTime\(\)\)\) return 'key';/);
});
test('a keyed vehicle is always in PMB; New to PMB is extra', () => {
  assert.match(app, /if \(primary === 'newpmb' && pmbVehicleHasKey\(vehicle\)\) return \['pmb', 'newpmb'\];/);
  assert.match(app, /if \(primary === 'pmb' && pmbKeyIsNew\(vehicle\)\) return \['pmb', 'newpmb'\];/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /&amp;r707=2026\.10\.29\.r707[&"]/);
});
