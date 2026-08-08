const fs = require('fs');
const assert = require('assert');

const sql = fs.readFileSync('supabase/staging_only/136_clean_workbook_board_reset.sql', 'utf8');
const lower = sql.toLowerCase();
const installer = fs.readFileSync('scripts/apply_migration_136_staging.py', 'utf8');
const prepare = fs.readFileSync('scripts/prepare_pdc_staging_reset_136.py', 'utf8');
const backup = fs.readFileSync('scripts/backup_pdc_staging_reset.py', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');

for (const token of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  'pdc-staging-workbook-reset-136',
  'd89a36dce52994acf34c234a6fc988c11b3ca1aa76a11123fdbacd8d507ffaa3',
  'f9606af816433a3dcecf1bebaf41c6c4a8b206fec81679ddfafd8808524c0741',
  'f0b426579c1cb25b26f2f17637c49383aefaa928512737adc67d5a7d97ec0bd4',
  'c20548bd02ac81bb7460db9518291de4f677aef7fa66519c439ce584181f199c',
  'b624e19411f00eabf9128ea166dd75bb3c43945a2edc9ef716419ce60b6d930a',
]) assert(lower.includes(token), `missing reset binding: ${token}`);

for (const token of [
  'pg_advisory_xact_lock', 'lock table public.pdc_ai_intake_proposals',
  'for update', 'pdc_reset_136_authority_drift', 'pdc_reset_136_exception_authority_changed',
  'pdc_reset_136_vehicle_identity_drift', 'pdc_reset_136_auditor_relation_block',
]) assert(lower.includes(token), `missing concurrency/fail-closed guard: ${token}`);

for (const table of [
  'workshop_bookings', 'vehicle_workshop_line_adjustments', 'vehicle_parts_updates',
  'pdc_sublet_bookings', 'vehicle_sublet_providers',
  'pdc_authenticated_email_operation_lines', 'vehicle_work_items',
]) assert(lower.includes(`delete from public.${table}`), `reset does not clear ${table}`);

for (const protectedTable of [
  'audit_events', 'navision_backend_records', 'pdc_authenticated_email_import_receipts',
  'pdc_bulk_workbook_row_receipts', 'pdc_ai_intake_history', 'pdc_auditor_runs',
  'pdc_user_roles', 'workshop_stages', 'workshop_bays', 'workshop_technicians',
]) assert(!new RegExp(`delete\\s+from\\s+public\\.${protectedTable}\b`, 'i').test(sql), `reset deletes protected ${protectedTable}`);
assert(!/insert\s+into\s+public\.vehicles/i.test(sql), 'safe canonical vehicle identities must be reused, not duplicated');
assert(lower.includes("lifecycle_state='deleted',visible_on_board=false"));
assert(lower.includes("lifecycle_state='active',visible_on_board=true,current_location=s.target_location"));
assert(lower.includes('drop trigger navision_activation_operational_reconcile'));
assert(lower.includes('create trigger navision_activation_operational_reconcile'));

for (const token of [
  'insert into public.pdc_authenticated_email_operation_lines',
  'insert into public.vehicle_work_items',
  'true,false,null::uuid,null::timestamptz',
  'booking_created', "'completion_changed',false", "'parts_changed',false",
]) assert(lower.includes(token), `missing operation/no-side-effect contract: ${token}`);
assert(!/insert\s+into\s+public\.workshop_bookings/i.test(sql));
assert(!/insert\s+into\s+public\.vehicle_parts_updates/i.test(sql));

for (const token of [
  'job_card_number text', 'source_row_no integer', 'source_contract text',
  "'job_card_number',ol.job_card_number", "'source_ref'", 'limit 50',
]) assert(lower.includes(token), `missing Job Card line identity: ${token}`);
assert(app.includes("const jobCard = cleanNavisionText(line.job_card_number || line.jobCardNumber || '');"));
assert(app.includes("${jobCard ? `JC ${jobCard} · ` : ''}${authenticatedOperationLineLabel(line.operation_no)}"));

assert(lower.includes("v_authoritative_delivered_rft boolean"));
assert(lower.includes("='navision_delivered_dealer'"));
assert(lower.includes("and not v_authoritative_delivered_rft"));
assert(lower.includes("case when public.navision_operational_location(r.normalized_data)='completed' then 'rft'"));
assert(lower.includes("rft_fake_qc") === false, 'runtime SQL should not manufacture QC evidence');

for (const table of ['pdc_staging_reset_batches', 'pdc_staging_reset_rows']) {
  assert(lower.includes(`alter table public.${table} enable row level security`));
}
assert(lower.includes('deferrable initially deferred'));
assert(lower.includes('pdc_reset_history_immutable'));
assert(lower.includes('from public,anon,authenticated,service_role'));

for (const token of [
  'conn.rollback()', '--expected-commit', 'refusing migration 136 apply from dirty worktree',
  '--fault-inject-postcheck-failure', 'rollback leaked data or schema state',
  'exact operation mismatch', 'active stock/location/authority mismatch',
  'production_changed',
]) assert(installer.toLowerCase().includes(token), `installer missing ${token}`);
for (const token of ['repeatable read', 'authority_binding_sha256', 'accepted_payload_sha256', 'exception_reason_counts']) {
  assert(prepare.toLowerCase().includes(token), `preview builder missing ${token}`);
}
for (const token of ['information_schema.tables', 'copy', 'sha256', '"workbook"', 'manifest.json']) {
  assert(backup.toLowerCase().includes(token), `backup tool missing ${token}`);
}

console.log('Migration 136 clean workbook board reset contract passed.');
