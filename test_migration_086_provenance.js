'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(
  __dirname,
  'supabase',
  'staging_only',
  '086_sublet_provider_normalisation_and_workshop_settings.sql'
);
const source = fs.readFileSync(migrationPath, 'utf8').replace(/\r\n/g, '\n');
const sha256 = crypto.createHash('sha256').update(source, 'utf8').digest('hex');

assert.strictEqual(
  sha256,
  'db05a6df1117aefe61da082f63ba6988e2ad0f98883617f66ba8ce888bee7da4',
  'migration 086 must remain byte-equivalent to its reviewed originating Git blob after newline normalization'
);
assert.match(source, /project_ref='cdsmnqxtyyoeoznmbidd'/, 'migration must remain staging-target guarded');
assert.doesNotMatch(source, /vjdtsswhroyguxyfjdkt/, 'migration must not reference production');
assert.match(source, /^begin;$/m, 'migration must remain transactional');
assert.match(source, /^commit;$/m, 'migration must retain its commit boundary');

for (const signature of [
  'sublet_provider_match_key',
  'sublet_provider_import_preview',
  'preview_navision_backend_import',
  'apply_navision_backend_import',
  'sync_navision_sublet_providers',
  'get_pdc_email_vehicle_location_snapshot',
  'add_workshop_bay',
  'set_workshop_bay_active'
]) {
  assert.match(source, new RegExp(`create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.${signature}\\s*\\(`, 'i'));
}

console.log('Migration 086 provenance checks passed');
