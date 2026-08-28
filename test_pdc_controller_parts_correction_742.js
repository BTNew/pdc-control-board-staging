'use strict';

const assert = require('assert');
const fs = require('fs');
const migrationPath = 'supabase/staging_only/20260829090000_742_controller_parts_received_correction.sql';
const source = fs.existsSync(migrationPath) ? fs.readFileSync(migrationPath, 'utf8').toLowerCase() : '';
assert.ok(source, '742 controller correction migration exists');
for (const marker of [
  "'cdsmnqxtyyoeoznmbidd'",
  'pdc_production_environment_sentinel',
  "'20260829080000'",
  "'741_rft_transport_email_draft_regex_repair'",
  "'20260829070000'",
  "'740_rft_transport_email_draft_read_lock_repair'",
  'pdc_staging_parts_received_correction_authorizations_742',
  'pdc_staging_parts_received_correction_receipts_742',
  'force row level security',
  'pdc_742_append_only',
  "'Craig Watson authorised STAGING correction for Stock 13016925: mark Parts received once via controller receipt 20260828'",
  "'mark_parts_received_once'",
  "'13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid",
  "'13016925'",
  "'37047'",
  'p_expected_version integer',
  'p_owner_instruction text',
  'p_idempotency_key uuid',
  "auth.jwt()->>'role'",
  "r.role::text in('operator','administrator')",
  'expires_at',
  'consumed_at',
  'controller_unauthorized',
  'controller_target_mismatch',
  'vehicle_version_conflict',
  'parts_not_required',
  'parts_not_ordered',
  'parts_already_received',
  'controller_correction_replayed',
  'audit_pdc_event',
  'pdc_email_vehicle_revision',
  'changed',
  'replay',
]) assert.ok(source.includes(marker.toLowerCase()), `missing ${marker}`);
assert.ok(!/grant\s+(?:insert|update|delete)\s+on\s+table/i.test(source), 'no broad table DML grant');
assert.ok(!/pdc_auditor_user_dealer_scopes.*insert/i.test(source), 'does not grant persistent Auditor dealer scope');
assert.ok(!/grant\s+execute[^;]+service_role/i.test(source), 'service_role is not granted');
assert.ok(source.includes("grant execute on function public.apply_pdc_staging_parts_received_correction_742"), 'controller function is exposed only through its guarded RPC');
console.log('PDC controller Parts correction 742 source contract passed.');
