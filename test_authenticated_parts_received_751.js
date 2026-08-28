'use strict';

const assert = require('assert');
const fs = require('fs');
const crypto = require('crypto');

const migrationPath = 'supabase/staging_only/20260829144000_751_authenticated_parts_received_contract.sql';
const controllerPath = 'scripts/apply_migration_751_staging.py';
const servicePath = 'pdc-email-vehicle-location-service.js';
const appPath = 'app.js';
const migration = fs.readFileSync(migrationPath, 'utf8');
const controller = fs.readFileSync(controllerPath, 'utf8');
const service = fs.readFileSync(servicePath, 'utf8');
const app = fs.readFileSync(appPath, 'utf8');
const lower = migration.toLowerCase();

assert.strictEqual(crypto.createHash('sha256').update(migration).digest('hex'), '7b08caa9418fde60feeafdef9f50ca8db4ef04c1101ab731043602b909630ce4');
assert.strictEqual((migration.match(/^BEGIN;$/gm) || []).length, 1, '751 has one transaction start');
assert.strictEqual((migration.match(/^COMMIT;$/gm) || []).length, 1, '751 has one transaction end');
for (const marker of [
  "'20260829143000'",
  "'750_project_recovered_stock_qc_operation_lines'",
  "'20260829144000'",
  "'pdc-authenticated-parts-received-751'",
  'mark_pdc_parts_received_authenticated_751',
  'p_vehicle_id uuid',
  'p_stock_number text',
  'p_expected_version integer',
  'p_idempotency_key uuid',
  "'administrator'",
  "'operator'",
  'pdc_user_roles',
  'pdc_auditor_user_dealer_scopes',
  'pdc_auditor_vehicle_dealer',
  'pdc_auditor_entity_in_scope',
  'vehicle_identity_mismatch',
  'canonical_identity_mismatch',
  'dealer_scope_denied',
  'vehicle_version_conflict',
  'parts_not_required',
  'parts_not_ordered',
  'parts_already_received',
  'parts_receipt_idempotency_conflict',
  'idempotency_key uuid not null unique',
  'force row level security',
  'pdc_751_append_only',
  'audit_pdc_event',
  'pdc_email_vehicle_revision',
  "set_config('pdc.parts_completion_revision_managed','on',true)",
  "not coalesce(new.parts_received,false)",
  'before_state',
  'after_state',
  'changed',
  'replayed',
  'pdc_production_environment_sentinel',
]) assert.ok(lower.includes(marker.toLowerCase()), `missing ${marker}`);
assert.ok(!/grant\s+(?:insert|update|delete)\s+on\s+table/i.test(migration), '749 has no broad table DML grant');
assert.ok(!/grant\s+execute[^;]+service_role/i.test(migration), '749 does not grant service_role');
assert.ok(lower.includes("v_role<>'administrator'"), 'non-Administrators take the dealer-scoped branch');
assert.ok(lower.includes("r.role::text in('operator','administrator')"), 'wrong roles are denied');
assert.ok(lower.includes('v_actor_dealer<>v_dealer'), 'wrong dealer is denied');
assert.ok(lower.includes('p_vehicle_id is null') && lower.includes('p_stock_number text'), 'missing UUID or Stock is denied');
assert.ok(lower.includes('vehicle_version_conflict'), 'stale expected version is denied');
assert.ok(lower.includes('parts_receipt_idempotency_conflict') && lower.includes('code\',\'replayed'), 'idempotency conflict and exact replay are distinct');
assert.ok(controller.includes("'750_project_recovered_stock_qc_operation_lines'"), 'controller re-reads the recovery head');
assert.ok(controller.includes('recovery lane is still active'), 'controller refuses an active recovery lane');
assert.ok(controller.includes('PDC_APPROVE_STAGING_MIGRATION_751'), 'controller requires explicit staging apply phrase');
assert.ok(lower.includes('revoke all on table public.pdc_authenticated_parts_received_receipts_751') && lower.includes('force row level security'), 'RLS/table privilege boundary is present');
assert.ok(controller.includes('verify-full') && !controller.includes('SUPABASE_SERVICE_ROLE_KEY'), 'controller uses the protected staging DSN only');
assert.ok(service.includes("const PDC_PARTS_COMPLETE_RPC = 'mark_pdc_parts_received_authenticated_751';"), 'client uses durable 749 RPC');
assert.ok(service.includes('p_stock_number'), 'client binds Stock identity');
assert.ok(app.includes('sharedVehicle.stock'), 'handler passes the visible Stock identity');
assert.ok(app.includes('dealer_scope_denied') && app.includes('vehicle_identity_mismatch'), 'handler exposes actionable domain failures');
console.log('751_authenticated_parts_received_contract passed.');
