const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const stagingConfig = fs.readFileSync('pdc-supabase-config.staging.js', 'utf8');
const nonStagingConfigTemplate = fs.readFileSync('pdc-supabase-config.example.js', 'utf8');
const stagingHtml = fs.readFileSync('staging.html', 'utf8');
const appSource = fs.readFileSync('app.js', 'utf8');

assert.match(stagingConfig, /window\.PDC_ALLOW_LOCAL_RESET\s*=\s*true\s*;/,
  'staging must explicitly permit URL-requested local vehicle-data cleanup');
assert.doesNotMatch(nonStagingConfigTemplate, /PDC_ALLOW_LOCAL_RESET/,
  'non-staging config template must never enable the staging browser cleanup gate');
assert.ok(stagingHtml.indexOf('pdc-supabase-config.staging.js') < stagingHtml.indexOf('app.js'),
  'staging config must load before app.js evaluates the cleanup request');
assert.match(stagingHtml, /pdc-supabase-config\.staging\.js\?v=2026\.07\.24\.27-clean-browser-reset/,
  'staging config cleanup gate must be cache-busted for already-open browsers');
assert.match(appSource, /has\(['"]clearLocalData['"]\)/,
  'app must recognize the explicit clearLocalData query parameter');
assert.match(appSource, /window\.PDC_ALLOW_LOCAL_RESET\s*===\s*true/,
  'live-board cleanup must remain fail-closed without the staging-only gate');
assert.match(appSource, /CRM_BACKUP_STORAGE_KEYS\.forEach\(key\s*=>\s*localStorage\.removeItem\(key\)\)/,
  'cleanup must clear the bounded operational vehicle-data key list');

const values = new Map([
  ['vehicleTrackingCoreNavisionOnlyVehicles:v1', '[{"stock":"old"}]'],
  ['vehicleTrackingCoreNavisionOnlyEdits:v1', '{"old":true}'],
  ['unrelated-key', 'keep'],
]);
const localStorage = {
  getItem: key => values.has(key) ? values.get(key) : null,
  setItem: (key, value) => values.set(key, String(value)),
  removeItem: key => values.delete(key),
};
const window = {
  location: { search: '?clearLocalData=1', pathname: '/pdc-control-board-staging/' },
  PDC_ALLOW_LOCAL_RESET: false,
};
vm.runInNewContext(stagingConfig, { window });
assert.strictEqual(window.PDC_ALLOW_LOCAL_RESET, true);
assert.strictEqual(window.PDC_SUPABASE_CONFIG.projectRef, 'cdsmnqxtyyoeoznmbidd');

const start = appSource.indexOf('function clearLocalDataFromUrl()');
const end = appSource.indexOf('recoverInterruptedStorageTransaction();', start);
assert.ok(start >= 0 && end > start, 'cleanup function must be extractable');
const cleanupFunction = appSource.slice(start, end);
vm.runInNewContext(
  `const CRM_BACKUP_STORAGE_KEYS = ${JSON.stringify([
    'vehicleTrackingCoreNavisionOnlyVehicles:v1',
    'vehicleTrackingCoreNavisionOnlyEdits:v1',
  ])};\n${cleanupFunction}\nclearLocalDataFromUrl();`,
  { window, localStorage, URLSearchParams, console },
);
assert.strictEqual(values.has('vehicleTrackingCoreNavisionOnlyVehicles:v1'), false);
assert.strictEqual(values.has('vehicleTrackingCoreNavisionOnlyEdits:v1'), false);
assert.strictEqual(values.get('unrelated-key'), 'keep');
assert.strictEqual(window.PDC_LOCAL_DATA_CLEARED, true);

console.log('PASS staging browser cleanup gate is explicit, bounded, and absent from production');
