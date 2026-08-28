'use strict';

const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260829050000_738_authenticated_parts_received_auditor_wrapper.sql';
const applyPath = 'scripts/apply_migration_738_staging.py';
const migration = fs.existsSync(migrationPath) ? fs.readFileSync(migrationPath, 'utf8').toLowerCase() : '';
const apply = fs.existsSync(applyPath) ? fs.readFileSync(applyPath, 'utf8').toLowerCase() : '';
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8').toLowerCase();
const app = fs.readFileSync('app.js', 'utf8').toLowerCase();

function has(text, marker, message) { assert.ok(text.includes(marker.toLowerCase()), message || `missing ${marker}`); }

assert.ok(migration, '738 migration source exists');
assert.strictEqual((migration.match(/^begin;$/gm) || []).length, 1, 'migration has one transaction start');
assert.strictEqual((migration.match(/^commit;$/gm) || []).length, 1, 'migration has one transaction end');
for (const marker of [
  "pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation'",
  'lock table supabase_migrations.schema_migrations in exclusive mode',
  "'20260829040000'",
  "'736_authoritative_rft_confirmation_toggle'",
  "'20260829050000'",
  "'cdsmnqxtyyoeoznmbidd'",
  "pdc_production_environment_sentinel",
  'pdc_auditor_actor_scope()',
  'pdc_auditor_entity_in_scope',
  "'37047'",
  "'13016925'",
  "'13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid",
  'p_vehicle_id uuid',
  'p_expected_version integer',
  'p_idempotency_key uuid',
  "auth.jwt()->>'role'",
  'unique(idempotency_key)',
  'force row level security',
  'pdc_738_append_only',
  'vehicle_version_conflict',
  'parts_not_required',
  'parts_not_ordered',
  'parts_already_received',
  'vehicle_not_exact_target',
  'dealer_scope_denied',
  'parts_receipt_idempotency_conflict',
  'before_state',
  'after_state',
  'audit_pdc_event',
  'pdc_email_vehicle_revision',
  'changed',
  'replay',
]) has(migration, marker);
assert.ok(!/grant\s+(?:insert|update|delete)\s+on\s+table/i.test(migration), 'no broad table DML grant');
assert.ok(!/require_pdc_role\s*\(\s*['"]operator/i.test(migration), 'Auditor wrapper does not grant or require operator role');
assert.ok(!/grant\s+execute[^;]+service_role/i.test(migration), 'service_role is not granted');

for (const marker of [
  "const pdc_parts_complete_rpc = 'mark_pdc_parts_received_auditor'",
  'p_idempotency_key',
  'crypto.randomuuid()',
]) has(service, marker);
for (const marker of ['service.markpartscomplete(vehicleid, expectedversion, crypto.randomuuid())', 'authenticatedpartstarget(key, vehicle)']) has(app, marker);
for (const marker of [
  'pdc-staging-migration-installation',
  '20260828_135232_8cb189',
  '20260829040000',
  'pdc_production_environment_sentinel',
  're-read',
  'committed',
]) has(apply, marker);
console.log('PDC Auditor Parts received 738 source contract passed.');
