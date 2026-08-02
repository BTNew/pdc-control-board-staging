'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '124_bulk_jc_stock_workbook_contract.sql');
const rollbackPath = path.join(__dirname, 'supabase', 'staging_only', '124_bulk_jc_stock_workbook_contract.rollback.sql');
assert(fs.existsSync(migrationPath));
assert(fs.existsSync(rollbackPath));
const sql = fs.readFileSync(migrationPath, 'utf8').replace(/\r\n/g, '\n');
const rollback = fs.readFileSync(rollbackPath, 'utf8').replace(/\r\n/g, '\n');
const lower = sql.toLowerCase();
const rollbackLower = rollback.toLowerCase();
const has = token => assert(lower.includes(token.toLowerCase()), `missing contract token: ${token}`);
const lacks = token => assert(!lower.includes(token.toLowerCase()), `forbidden contract token: ${token}`);

// Staging-only exact ledger contract.
has("project_ref='cdsmnqxtyyoeoznmbidd'");
has("version='123' and name='harden_ai_auditor_human_review_binding'");
has("values('124','bulk_jc_stock_workbook_contract'");
assert(!fs.existsSync(path.join(__dirname, 'supabase', 'migrations', '124_bulk_jc_stock_workbook_contract.sql')));

// Only a currently authenticated, active, approved Administrator can authorize/use it.
for (const token of [
  'authorize_pdc_bulk_jc_stock_workbook', "r.role='administrator'", "r.account_status='approved'",
  'r.active', 'r.auth_user_id=v_uid', 'auth.uid()', "auth.jwt()->>'email'",
  'expected_pair_count', 'expected_operation_count', 'workbook_sha256', "interval '2 hours'",
  "expires_at<=created_at+interval '2 hours'", 'invalid_authorization_binding',
]) has(token);
for (const token of ["r.role='viewer'", 'pdc_monitor_vehicle_identity_readers', 'pdc_monitor_stage_activation_writers', "interval '48 hours'", 'allow_no_current_navision_override', 'manager_override', 'craig-31-july']) lacks(token);

// Strict payload: null work_key is valid evidence, but only the authoritative allowlist is accepted.
for (const token of [
  "(o->'work_key')='null'::jsonb", "'bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','parts'",
  "'missing_authoritative_work_key'", "'partial_identity_disagreement'", "'multiple_current_identity_matches'",
  "'operational_identity_conflict'", "'operational_exact_without_current_navision'", "'no_current_match'",
  'duplicate_row', 'duplicate_jc_stock_pair', 'operation_quarantine_count',
]) has(token);
assert(!/['"]pitinspection['"]/i.test(sql), 'Pit must not be an accepted work key');
assert(!/['"]sublet['"]/i.test(sql), 'Sublet must not be an accepted work key');

// Preview quarantines instead of blocking, including the current all-null-work-key workbook.
has('blocked_count integer not null default 0 check(blocked_count=0)');
has("'blocked_count',0");
has("'applyable',v_accepted>0");
has("where reason is not null");
has('pdc_bulk_workbook_quarantine_immutable');
assert(!lower.includes('unresolved_rows_blocked'));

// Exact current Navision pair is the only accepted identity; no override/unmatched creation lane.
for (const token of [
  "source_system='microsoft_navision'", "record_status='current'", 'r.is_current',
  'v_exact=1 and v_stock_count=1 and v_jc_count=1', "classification='unique_exact_current'",
  "'approved_key_list'", 'canonical_vehicle_id', 'completed_at is null',
]) has(token);
assert(!/insert\s+into\s+public\.vehicles/i.test(sql), 'Apply must never create unmatched vehicles');
assert(!/update\s+public\.vehicles/i.test(sql), 'Apply must not rewrite operational vehicle state');
assert(!/insert\s+into\s+public\.workshop_bookings/i.test(sql));
assert(!/insert\s+into\s+public\.vehicle_parts_updates/i.test(sql), 'Apply must not create Parts state/completion');

// Apply replay and zero-accepted rejection both precede operational DML.
const applyStart = lower.indexOf('create or replace function public.apply_pdc_bulk_jc_stock_workbook');
const replay = lower.indexOf("if found then return public.navision_backend_response(true,'exact_replay'", applyStart);
const zeroAccepted = lower.indexOf("if v_preview.accepted_count=0 then return public.navision_backend_response(false,'zero_accepted_preview'", applyStart);
const operationalTokens = [
  'insert into public.navision_board_activations',
  'insert into public.pdc_authenticated_email_import_receipts',
  'insert into public.pdc_authenticated_email_operation_lines',
  'insert into public.vehicle_work_items',
];
const firstDml = Math.min(...operationalTokens.map(t => lower.indexOf(t, applyStart)).filter(i => i >= 0));
assert(applyStart >= 0 && replay > applyStart && replay < firstDml, 'exact replay must return before operational DML');
assert(zeroAccepted > replay && zeroAccepted < firstDml, 'zero accepted must return before operational DML');

// Direct bounded/idempotent/audited writes; never call the Viewer-only import function.
for (const token of [
  'insert into public.pdc_authenticated_email_operation_lines',
  'on conflict(source_hash,operation_no) do nothing',
  'insert into public.vehicle_work_items',
  'where not public.vehicle_work_items.completed and not public.vehicle_work_items.required',
  "'completed_work_reopened',false", 'insert into public.audit_events',
  'pdc_bulk_workbook_operation_identity_conflict', 'pdc_bulk_workbook_operation_readback_mismatch',
  'pdc_bulk_workbook_identity_no_longer_unique',
]) has(token);
assert(!/import_pdc_authenticated_email_operations(?:_with_hours)?\s*\(/i.test(sql), 'Administrator Apply must not call Viewer-only import RPCs');

// Aggregate-only readback, immutable receipts/quarantine, advisory locks, RLS and fixed search paths.
for (const token of [
  'read_pdc_bulk_jc_stock_workbook_receipt', 'pair_aggregate_sha256', 'operation_aggregate_sha256',
  'immutable_receipt_hash', 'pdc_bulk_workbook_apply_receipts_immutable', 'pdc_bulk_workbook_row_receipts_immutable',
  'pg_advisory_xact_lock', 'set search_path=pg_catalog,public,extensions',
]) has(token);
for (const table of ['pdc_bulk_workbook_authorizations','pdc_bulk_workbook_previews','pdc_bulk_workbook_quarantine','pdc_bulk_workbook_apply_receipts','pdc_bulk_workbook_row_receipts']) {
  has(`alter table public.${table} enable row level security`);
}
for (const signature of [
  'authorize_pdc_bulk_jc_stock_workbook(text,integer,integer)',
  'preview_pdc_bulk_jc_stock_workbook(text,jsonb)',
  'apply_pdc_bulk_jc_stock_workbook(uuid,text,text)',
  'read_pdc_bulk_jc_stock_workbook_receipt(uuid)',
]) {
  has(`revoke all on function public.${signature} from public,anon,authenticated`);
  has(`grant execute on function public.${signature} to authenticated`);
}
assert((lower.match(/security definer/g) || []).length >= 5);

// Rollback is no longer tied to a dated actor and refuses any applied package.
assert(rollbackLower.includes('bulk_apply_receipts_present_recovery_required'));
assert(rollbackLower.includes('exists(select 1 from public.pdc_bulk_workbook_apply_receipts)'));
assert(rollbackLower.includes('drop function public.authorize_pdc_bulk_jc_stock_workbook(text,integer,integer)'));
assert(!rollbackLower.includes('craig'));
assert(!rollbackLower.includes("r.role='viewer'"));

console.log('Migration 124 Administrator fail-closed bulk JC/Stock workbook contract passed');
