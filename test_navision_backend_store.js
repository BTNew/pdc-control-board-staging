'use strict';

const fs = require('fs');
const path = require('path');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const migrationPath = path.join(__dirname, 'supabase', 'migrations', '037_shared_navision_backend_store.sql');
const sql = fs.readFileSync(migrationPath, 'utf8');
const lower = sql.toLowerCase();

const tables = [
  'navision_backend_revision',
  'navision_import_batches',
  'navision_backend_records',
  'navision_import_items',
  'navision_operation_receipts',
  'navision_rollback_items',
  'navision_backend_audit',
];
const publicFunctions = [
  'preview_navision_backend_import',
  'apply_navision_backend_import',
  'get_navision_backend_snapshot',
  'export_navision_backend_records',
  'get_navision_reconciliation_report',
  'rollback_navision_backend_import',
  'link_navision_backend_record',
];

for (const table of tables) {
  assert(lower.includes(`create table if not exists public.${table}`), `${table} must be additive`);
  assert(lower.includes(`alter table public.${table} enable row level security`), `${table} must enable RLS`);
  assert(lower.includes(`revoke all on table public.${table} from public, anon, authenticated`), `${table} must deny direct table access by default`);
}
for (const fn of publicFunctions) {
  assert(lower.includes(`create or replace function public.${fn}`), `${fn} must exist`);
  assert(lower.includes(`revoke all on function public.${fn}`), `${fn} must have explicit EXECUTE revocation`);
  assert(lower.includes(`grant execute on function public.${fn}`), `${fn} must receive an explicit business-role-gated contract grant`);
}

function functionBlock(name) {
  const start = lower.indexOf(`create or replace function public.${name}`);
  const next = lower.indexOf('create or replace function public.', start + 10);
  return lower.slice(start, next < 0 ? lower.length : next);
}
for (const name of publicFunctions) {
  const block = functionBlock(name);
  assert(block.includes('security definer'), `${name} must be SECURITY DEFINER`);
  assert(block.includes('set search_path = pg_catalog, public, extensions'), `${name} must pin search_path`);
}

assert(!/grant\s+execute[\s\S]*\s+to\s+(public|anon)\b/i.test(sql), 'No function execution may leak to PUBLIC or anon');
for (const table of tables.filter(name => name !== 'navision_backend_revision')) {
  assert(!new RegExp(`grant\\s+(select|insert|update|delete|all)[\\s\\S]*?on\\s+table\\s+public\\.${table}\\s+to\\s+authenticated`, 'i').test(sql), `${table} must not grant generic authenticated table access`);
}
assert(!/(insert\s+into|update|delete\s+from)\s+public\.vehicles\b/i.test(sql), 'Migration 037 must never mutate active operational vehicles');
assert(!/(insert\s+into|update|delete\s+from)\s+public\.vehicle_work_items\b/i.test(sql), 'Migration 037 must never mutate workflow rows');
assert(lower.includes("pg_advisory_xact_lock(hashtextextended('navision-backend-store'"), 'Apply/rollback/link operations must take the shared advisory lock');
assert(lower.includes('for update;'), 'Revision and record operations must use row locks');
assert(lower.includes('operation_kind, idempotency_key, request_hash') && lower.includes('response jsonb not null'), 'Durable response-loss receipts must retain exact responses');
assert(/classification in \('new',\s*'changed',\s*'unchanged',\s*'missing',\s*'invalid',\s*'conflict'\)/i.test(sql), 'Reconciliation classifications must be bounded');
assert(lower.includes('missing_since_batch_id'), 'Missing records must be retained historically');
assert(lower.includes('first_seen_batch_id') && lower.includes('last_seen_batch_id'), 'First/last-seen batch lineage must be stored');
assert(lower.includes('canonical_vehicle_id uuid references public.vehicles'), 'Canonical vehicle links must remain optional');
assert(lower.includes("status = 'rolled_back'"), 'Protected rollback must retain rollback state');
assert(lower.includes("alter publication supabase_realtime add table public.navision_backend_revision"), 'Realtime must publish only the non-payload revision signal');
assert(!lower.includes('alter publication supabase_realtime add table public.navision_backend_records'), 'Realtime must not expose the backend payload table');

for (const name of ['get_navision_backend_snapshot', 'export_navision_backend_records', 'get_navision_reconciliation_report']) {
  assert(!functionBlock(name).includes('raw_evidence'), `${name} must not expose raw source payloads`);
}
assert(functionBlock('preview_navision_backend_import').includes("coalesce(public.current_pdc_user_role()::text = any (array['importer', 'administrator']), false)"), 'Preview must fail closed for NULL/unapproved roles');
assert(functionBlock('apply_navision_backend_import').includes("coalesce(v_role::text = any (array['importer', 'administrator']), false)"), 'Apply must fail closed for NULL/unapproved roles');
assert(functionBlock('rollback_navision_backend_import').includes("current_pdc_user_role() is distinct from 'administrator'"), 'Rollback must fail closed for NULL/unapproved roles');
assert(functionBlock('link_navision_backend_record').includes("current_pdc_user_role() is distinct from 'administrator'"), 'Canonical linking must fail closed for NULL/unapproved roles');
assert(functionBlock('navision_backend_preview_internal').includes("jsonb_typeof(p_rows) is distinct from 'array'"), 'SQL NULL/non-array source rows must fail closed');
assert(functionBlock('get_navision_backend_snapshot').includes("case when v_role::text = any (array['importer', 'administrator'])") && functionBlock('get_navision_backend_snapshot').includes("'metadata_only'"), 'Operator snapshots must omit normalized source payloads');
assert(functionBlock('rollback_navision_backend_import').includes('v_current is distinct from v_item.after_record'), 'Rollback must reject row-level after-image drift before mutation');
assert(functionBlock('apply_navision_backend_import').includes("v_missing_index := v_missing_index + 1"), 'Missing reconciliation items must receive deterministic cursor indexes');

const readinessSql = fs.readFileSync(path.join(__dirname, 'supabase', 'migrations', '041_operational_readiness_polish.sql'), 'utf8').toLowerCase();
assert(readinessSql.includes("alter function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)\n  set statement_timeout = '120s'"), 'Shared Navision preview must receive a bounded timeout large enough for dealer reconciliation');
assert(readinessSql.includes("alter function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)\n  set statement_timeout = '120s'"), 'Shared Navision apply must receive a bounded timeout large enough for durable atomic apply');
assert(!/(insert\s+into|update|delete\s+from)\s+public\.vehicle_work_items\b/i.test(readinessSql), 'Navision timeout remediation must not mutate workflow rows');

const concurrencyHarness = fs.readFileSync(path.join(__dirname, 'scripts', 'test_navision_backend_concurrency_staging.py'), 'utf8');
assert(!concurrencyHarness.includes('snapshot_hash') && !concurrencyHarness.includes('last_batch_id'), 'Concurrency harness must only query migration-037 revision columns');
const sessionLock = concurrencyHarness.indexOf("pg_advisory_lock(hashtextextended('navision-backend-store',0))");
const baselineRead = concurrencyHarness.indexOf('select singleton,revision,updated_at');
const emptyStoreRead = concurrencyHarness.indexOf('select count(*) from public.navision_backend_records');
const applyCall = concurrencyHarness.indexOf('first = rpc(cur_a, "apply_navision_backend_import"');
assert(sessionLock >= 0 && sessionLock < baselineRead && baselineRead < emptyStoreRead && emptyStoreRead < applyCall, 'Concurrency baseline, empty-store check and apply must share one uninterrupted session-lock window');
const failureCleanup = concurrencyHarness.slice(concurrencyHarness.indexOf('    finally:'));
const rollbackA = failureCleanup.indexOf('a.rollback()');
const failedApplyUnlock = failureCleanup.indexOf('store_lock_released_after_failed_apply');
const contenderJoin = failureCleanup.indexOf('thread.join(30)');
const rollbackB = failureCleanup.indexOf('b.rollback()');
assert(rollbackA >= 0 && rollbackA < failedApplyUnlock && failedApplyUnlock < contenderJoin && contenderJoin < rollbackB, 'Failure cleanup must release A transaction, release A session lock, join contender, then roll back B');
assert(concurrencyHarness.includes('automatic cleanup refused outside the uninterrupted exclusive lock window'), 'Concurrency cleanup must fail closed without uninterrupted exclusivity');

console.log('Migration 037 additive scope, authority separation, locking, idempotency, RLS and RPC security checks passed');
