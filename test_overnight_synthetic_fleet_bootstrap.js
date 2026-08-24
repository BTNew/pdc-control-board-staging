'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const root = __dirname;
const migrationRel = 'supabase/staging_only/20260825000000_363_overnight_synthetic_fleet_bootstrap.sql';
const testRel = 'test_overnight_synthetic_fleet_bootstrap.js';
const sql = fs.readFileSync(path.join(root, migrationRel), 'utf8');
const lower = sql.toLowerCase();
const specs = JSON.parse(fs.readFileSync(path.join(root, '_overnight_evidence/synthetic-fleet-specs.json'), 'utf8'));

function has(fragment, message = `missing contract fragment: ${fragment}`) {
  assert(sql.includes(fragment), message);
}
function matches(re, message) { assert(re.test(sql), message); }

// Exact migration head, staging containment and zero-notification bootstrap guard.
for (const fragment of [
  "version='20260824230000' AND name='362_align_anderson_plugs_and_job_counts'",
  "version>'20260824230000' AND version~'^[0-9]{14}$'",
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL",
  "running_status<>'stopped'",
  'gateway_instance_id IS NOT NULL',
  'FROM public.monitored_mailboxes WHERE active',
  'FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL',
  '(SELECT count(*) FROM public.vehicle_notifications)<>0',
  'PDC_363_STAGING_TARGET_HEAD_OR_CONTAINMENT_MISMATCH',
]) has(fragment);

// Append-only registry, receipt and event history, with RLS and immutable rows.
for (const table of [
  'pdc_overnight_synthetic_fleet_registry_363',
  'pdc_overnight_synthetic_fleet_receipts_363',
  'pdc_overnight_synthetic_fleet_events_363',
]) {
  matches(new RegExp(`CREATE TABLE public\\.${table}\\b`, 'i'), `${table} must be created`);
  matches(new RegExp(`ALTER TABLE public\\.${table} ENABLE ROW LEVEL SECURITY`, 'i'), `${table} must enable RLS`);
  matches(new RegExp(`REVOKE ALL ON TABLE public\\.${table}\\s+FROM public,anon,authenticated,service_role`, 'i'), `${table} must have no direct public/API table privileges`);
  matches(new RegExp(`BEFORE UPDATE OR DELETE ON public\\.${table}`, 'i'), `${table} must reject update/delete`);
}
for (const fragment of [
  'run_id text NOT NULL', 'scenario_no integer NOT NULL', 'scenario_name text NOT NULL',
  'vehicle_id uuid NOT NULL', 'stock_number text NOT NULL', 'customer_name text NOT NULL',
  'job_card_number text NOT NULL', 'vehicle_description text NOT NULL', 'request_sha256 text NOT NULL',
  'actor_id uuid NOT NULL', 'idempotency_key uuid NOT NULL', 'response jsonb NOT NULL',
  'UNIQUE(actor_id,idempotency_key)', 'event_kind text NOT NULL',
]) has(fragment);
has('PDC_363_APPEND_ONLY');

// Authenticated, role-checked SECURITY DEFINER bootstrap/readback RPCs.
for (const fragment of [
  'public.bootstrap_pdc_hermes_test_fleet(p_run_id text,p_idempotency_key uuid,p_specs jsonb)',
  'public.read_pdc_hermes_test_fleet(p_run_id text)',
  'SECURITY DEFINER',
  "r.role='administrator' AND r.active AND r.account_status='approved'",
  'GRANT EXECUTE ON FUNCTION public.bootstrap_pdc_hermes_test_fleet(text,uuid,jsonb) TO authenticated',
  'GRANT EXECUTE ON FUNCTION public.read_pdc_hermes_test_fleet(text) TO authenticated',
]) has(fragment);
for (const signature of [
  'public.bootstrap_pdc_hermes_test_fleet(text,uuid,jsonb)',
  'public.read_pdc_hermes_test_fleet(text)',
]) {
  matches(new RegExp(`REVOKE ALL ON FUNCTION ${signature.replace(/[()]/g, '\\$&')} FROM public,anon,authenticated,service_role`, 'i'), `${signature} must revoke before narrow grant`);
  assert(!new RegExp(`GRANT EXECUTE ON FUNCTION ${signature.replace(/[()]/g, '\\$&')} TO (?:anon|service_role)`, 'i').test(sql), `${signature} must not grant anon/service_role`);
}

// Exact run, exact 20 numbered scenarios, strict prefixes and bounded render-only input.
for (const fragment of [
  "HERMES-TEST-RUN-20260824",
  "jsonb_typeof(p_specs) IS DISTINCT FROM 'array'",
  'jsonb_array_length(p_specs)<>20',
  "lpad(v_no::text,3,'0')",
  "'HERMES-TEST-'||lpad(v_no::text,3,'0')",
  "v_customer !~ '^HERMES-TEST'",
  "v_job !~ '^HERMES-TEST'",
  "v_description !~ '^HERMES-TEST'",
  "v_location NOT IN('Other','IT','YH','PMB')",
  "v_location<>'IT'",
  "v_eta<=CURRENT_DATE",
  "k<>ALL(ARRAY['scenario_no','scenario_name','stock','customer','job_card','description','initial_location','eta','work_keys','notes'])",
  "jsonb_typeof(spec->'scenario_no') IS DISTINCT FROM 'number'",
  "jsonb_typeof(spec->'work_keys') IS DISTINCT FROM 'array'",
  "v_specs_sha256<>'0bc2791f0b79bf03018f5d3ec444441253c0aa8a994dd8a31f7bd49f20738d16'",
  'PDC_363_EXACT_LOGGED_CATALOG_REQUIRED',
  "v_name~'[[:cntrl:]]'",
  'render_only',
]) has(fragment);
for (const bound of ['length(v_name) NOT BETWEEN 12 AND 120','length(v_customer) NOT BETWEEN 12 AND 120','length(v_job) NOT BETWEEN 12 AND 80','length(v_description) NOT BETWEEN 12 AND 180','length(v_notes) NOT BETWEEN 12 AND 240']) has(bound);
assert.strictEqual(specs.length, 20, 'exact logged fleet catalog must contain 20 specs');
assert.deepStrictEqual(specs.map(s => s.stock), Array.from({length: 20}, (_, i) => `HERMES-TEST-${String(i + 1).padStart(3, '0')}`));
for (const spec of specs) {
  for (const field of ['scenario_name','stock','customer','job_card','description','notes']) {
    assert(String(spec[field]).startsWith('HERMES-TEST'), `${field} must be HERMES-TEST-prefixed`);
  }
}

// Deterministic identities, collision closure, canonical incomplete work only.
for (const fragment of [
  'extensions.uuid_generate_v5',
  "'hermes_overnight_synthetic'",
  "v.source_batch_id<>p_run_id",
  "v.source_record_id<>r.stock_number",
  'stock_number_normalized',
  'pdc_vehicle_tombstones',
  'vehicle_aliases',
  'navision_backend_records',
  'navision_board_activations',
  'existing_registry_mismatch',
  'SELECT s.work_key FROM public.workshop_stages s WHERE s.active',
  "UNION SELECT 'PARTS'",
  'required,completed,completed_by,completed_at,notes',
  'true,false,NULL,NULL',
  "p_run_id||':work:'||v_stock||':'||v_work_key",
]) has(fragment);

// Exact actor/idempotency replay and transactional count/postcondition proof.
for (const fragment of [
  "'request_hash',v_request_sha256",
  'WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key',
  'v_receipt.request_sha256<>v_request_sha256',
  'PDC_363_IDEMPOTENCY_PAYLOAD_MISMATCH',
  "RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false)",
  "'replay',false",
  "'vehicle_delta',20",
  "'registry_delta',20",
  "'notification_delta',0",
  'v_after_vehicle_count-v_before_vehicle_count<>20',
  'v_after_registry_count-v_before_registry_count<>20',
  'v_after_notification_count<>v_before_notification_count',
  'v_before_notification_count<>0',
  'v_before_work_count+v_expected_work_count',
  'LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE',
  'LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE',
  'LOCK TABLE public.monitored_mailboxes IN SHARE MODE',
  'LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE',
  'LOCK TABLE public.vehicle_notifications IN SHARE MODE',
  'enabled OR outbound_email_enabled OR automatic_rule_application OR automatic_authenticated_jobcards',
  'v_protected_digest_after IS DISTINCT FROM v_protected_digest_before',
  "'protected_vehicle_digest_before',v_protected_digest_before",
  "'protected_vehicle_digest_after',v_protected_digest_after",
  '(spec->\'work_keys\')?wi.work_key',
  'EXISTS(SELECT 1 FROM public.workshop_bookings',
  'EXISTS(SELECT 1 FROM public.vehicle_parts_updates',
  'EXISTS(SELECT 1 FROM public.pdc_sublet_bookings',
  'rft_collected_at IS NOT NULL',
  'completed_at IS NOT NULL',
  'deleted_at IS NOT NULL',
]) has(fragment);

// Readback is role/run scoped and returns canonical registered state/work only.
for (const fragment of [
  "IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824'",
  "'vehicles',v_rows",
  "'work_items'",
  'JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=v.id',
  'WHERE r.run_id=p_run_id',
]) has(fragment);

// Migration ledger and PostgREST schema reload.
for (const fragment of [
  "VALUES('20260825000000','363_overnight_synthetic_fleet_bootstrap'",
  "NOTIFY pgrst,'reload schema'",
]) has(fragment);
assert(sql.trim().toUpperCase().endsWith('COMMIT;'), 'migration must commit transactionally');

// No prohibited destructive/authority/evidence operations.
for (const [re, label] of [
  [/^\s*TRUNCATE\b/im, 'TRUNCATE'], [/\bCASCADE\b/i, 'CASCADE'],
  [/ALTER\s+TABLE[\s\S]{0,100}DISABLE\s+TRIGGER/i, 'trigger disable'],
  [/UPDATE\s+public\.vehicles\b/i, 'pre-existing vehicle UPDATE'],
  [/^\s*DELETE\s+FROM\b/im, 'hard DELETE'], [/^\s*UPDATE\s+public\.(?!vehicles\b)/im, 'unrelated UPDATE'],
  [/GRANT\s+(?:ALL|INSERT|UPDATE|DELETE|TRUNCATE|REFERENCES|TRIGGER)\s+ON\s+TABLE/i, 'table DML grant'],
  [/GRANT\s+EXECUTE[\s\S]{0,100}\bservice_role\b/i, 'service-role function grant'],
  [/\b(pg_net|http_post|net\.http|send_email|email_response_drafts|ai_email_intake|ai_email_attachments|pdc_provider_email_observations)\b/i, 'external/email evidence surface'],
  [/^\s*(INSERT|UPDATE|DELETE)\s+(?:INTO\s+|FROM\s+)?public\.(workshop_stages|workshop_bays|monitored_mailboxes|pdc_monitor_stage_activation_writers)\b/im, 'reference/containment mutation'],
]) assert(!re.test(sql), `forbidden ${label} operation`);

// This exact implementation lineage may differ from its delegated base only in its two owned paths.
const base = '7d5211fa57bab61edddb1dd5e409419d7f4ba282';
const committed = cp.execFileSync('git', ['diff', '--name-only', base, 'HEAD'], { cwd: root, encoding: 'utf8' })
  .trim().split(/\r?\n/).filter(Boolean).map(p => p.replace(/\\/g, '/'));
const status = cp.execFileSync('git', ['status', '--porcelain=v1', '--untracked-files=all'], { cwd: root, encoding: 'utf8' })
  .trimEnd().split('\n').map(line => line.endsWith(String.fromCharCode(13)) ? line.slice(0, -1) : line).filter(Boolean);
const working = status.map(line => line.slice(3).replace(/\\/g, '/'));
const changed = [...new Set([...committed, ...working])].sort();
assert.deepStrictEqual(changed, [migrationRel, testRel, 'HERMES-OVERNIGHT-RUN.md', '_overnight_evidence/synthetic-fleet-specs.json'].sort(), `unexpected changed paths since ${base}: ${changed.join(', ')}`);

console.log('overnight_synthetic_fleet_bootstrap source contract: PASS');
