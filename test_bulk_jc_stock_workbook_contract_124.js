'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '124_bulk_jc_stock_workbook_contract.sql');
assert(fs.existsSync(migrationPath), 'migration 124 must exist only under supabase/staging_only');
const sql = fs.readFileSync(migrationPath, 'utf8').replace(/\r\n/g, '\n');
const lower = sql.toLowerCase();

function has(token) {
  assert(lower.includes(token.toLowerCase()), `missing contract token: ${token}`);
}

// Staging and exact-ledger identity.
has("project_ref='cdsmnqxtyyoeoznmbidd'");
has("version='123' and name='harden_ai_auditor_human_review_binding'");
has("values('124','bulk_jc_stock_workbook_contract'");
assert(!fs.existsSync(path.join(__dirname, 'supabase', 'migrations', '124_bulk_jc_stock_workbook_contract.sql')));

// Dedicated, expiring, immutable authorization for exactly one approved Viewer.
for (const token of [
  'pdc_bulk_workbook_authorizations',
  'pdc_monitor_vehicle_identity_readers',
  'pdc_monitor_stage_activation_writers',
  "r.role='viewer'",
  "r.account_status='approved'",
  'v_count<>1',
  "interval '48 hours'",
  'allow_no_current_navision_override',
  'expected_quarantine_count',
  '108',
]) has(token);

// Exact input and server-canonical hash binding.
for (const token of [
  'p_workbook_sha256 text', 'p_payload jsonb',
  "jsonb_array_length(v_payload) not between 1 and 500", 'jsonb_array_length(r->\'operations\') not between 1 and 100',
  'pdc_bulk_workbook_canonical_payload_sha256',
  "extensions.digest", "'sha256'", 'claimed_workbook_sha256',
  'claimed_payload_sha256', 'preview_payload', 'authorization_id',
  "manager_override_no_current_navision_match",
  "'row_no','job_card_number','stock_number'",
  "'description','estimated_hours','estimated_hours_source','operation_no','work_key'",
  '[[:cntrl:]]', 'duplicate_row', 'duplicate_operation', 'invalid_work_key', 'invalid_hours',
]) has(token);

// Exact-pair classification and fail-closed disagreements.
for (const token of [
  "source_system='microsoft_navision'", "record_status='current'", 'r.is_current',
  "normalized_data->>'jobcardnumber'", "normalized_data->>'batch'",
  "'navision_exact'", "'quarantined'", "'partial_identity_disagreement'",
  "'multiple_current_exact_pair_matches'", "'no_current_navision_match'",
  'expected_quarantine_count', "then 'manager_override_no_current_navision_match'",
]) has(token);

// Apply/replay/receipts/read-back.
for (const token of [
  'preview_pdc_bulk_jc_stock_workbook', 'apply_pdc_bulk_jc_stock_workbook',
  'read_pdc_bulk_jc_stock_workbook_receipt',
  "status='applied'", "'exact_replay'", "'vehicles_added',0", "'operation_lines_added',0", "'estimated_hours_added',0",
  'pdc_bulk_workbook_row_receipts', 'pdc_bulk_workbook_apply_receipts',
  'pdc_bulk_workbook_quarantine', 'pdc_authenticated_email_import_receipts',
  'pdc_authenticated_email_operation_lines', 'navision_board_activations',
  "'approved_key_list'", 'canonical_vehicle_id', 'backend_record_id',
  "'booking_created',false", "'completed_work_reopened',false",
]) has(token);

// Replay must happen before operational DML in Apply.
const applyStart = lower.indexOf('create or replace function public.apply_pdc_bulk_jc_stock_workbook');
assert(applyStart >= 0);
const replay = lower.indexOf("if found then return public.navision_backend_response(true,'exact_replay'", applyStart);
const firstOperationalDml = Math.min(...[
  'insert into public.vehicles',
  'update public.vehicles',
  'insert into public.navision_board_activations',
  'insert into public.pdc_authenticated_email_import_receipts',
  'insert into public.pdc_authenticated_email_operation_lines',
].map(token => lower.indexOf(token, applyStart)).filter(index => index >= 0));
assert(replay >= 0 && replay < firstOperationalDml, 'exact replay must return before operational DML');
assert(!/insert\s+into\s+public\.workshop_bookings/i.test(sql));
assert(!/update\s+public\.workshop_bookings/i.test(sql));

// Sensitive tables are RLS-only and RPC ACLs are authenticated-only.
for (const table of [
  'pdc_bulk_workbook_authorizations', 'pdc_bulk_workbook_previews',
  'pdc_bulk_workbook_quarantine', 'pdc_bulk_workbook_row_receipts',
  'pdc_bulk_workbook_apply_receipts',
]) {
  has(`alter table public.${table} enable row level security`);
  has(`revoke all on table public.${table} from public,anon,authenticated`);
}
for (const signature of [
  'preview_pdc_bulk_jc_stock_workbook(text,jsonb)',
  'apply_pdc_bulk_jc_stock_workbook(uuid,text,text)',
  'read_pdc_bulk_jc_stock_workbook_receipt(uuid)',
]) {
  has(`revoke all on function public.${signature} from public,anon,authenticated`);
  has(`grant execute on function public.${signature} to authenticated`);
}
assert((lower.match(/security definer/g) || []).length >= 3);
assert((lower.match(/set search_path=pg_catalog,public,extensions/g) || []).length >= 3);

console.log('Migration 124 bulk JC/Stock workbook contract passed');
