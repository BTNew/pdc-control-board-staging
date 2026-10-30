const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const js = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
test('Vehicle Locations opens on the PMB tile', () => {
  assert.match(js, /const DEFAULT_BUCKET = 'pmb';/);
  assert.match(js, /const state = \{ station: '', bucket: DEFAULT_BUCKET,/);
});
test('clicking Vehicle Locations in the menu resets to the PMB tile before render', () => {
  assert.match(js, /closest\?\.\('\.nav-item\[data-view="dashboard"\]'\)\) return;\s*Object\.assign\(state, \{ bucket: DEFAULT_BUCKET, stoppages: false \}\);\s*\}, true\);/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-locations-table\.js\?[^']*&r745=2026\.10\.30\.r745'/);
});
