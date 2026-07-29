'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '115_beta_ai_auditor_foundation.sql');
assert.ok(fs.existsSync(migrationPath), 'migration 115 is missing');
const sql = fs.readFileSync(migrationPath, 'utf8').replace(/\r\n/g, '\n');
const lower = sql.toLowerCase();

function body(name, delimiter) {
  const start = lower.indexOf(`create or replace function public.${name}`);
  const end = lower.indexOf(`${delimiter};`, start);
  assert.ok(start >= 0 && end > start, `${name} body missing`);
  return lower.slice(start, end);
}
function tableDdl(name) {
  const start = lower.indexOf(`create table if not exists public.${name} (`);
  const end = lower.indexOf('\n);', start);
  assert.ok(start >= 0 && end > start, `${name} definition missing`);
  return lower.slice(start, end);
}

assert.match(lower, /^-- staging-only migration 115:/);
assert.match(lower, /version = '114'[\s\S]*contain_multi_attachment_email_import/);
assert.match(lower, /version = '115'[\s\S]*beta_ai_auditor_foundation/);
assert.match(lower, /begin;[\s\S]*commit;\s*$/);
assert.ok(lower.includes("project_ref = 'cdsmnqxtyyoeoznmbidd'"));
assert.ok(!lower.includes('service_role'), 'service-role credentials/grants are forbidden');

const tables = [
  'pdc_auditor_user_dealer_scopes', 'pdc_auditor_worker_identities',
  'pdc_auditor_booking_work_relations', 'pdc_auditor_runs', 'pdc_auditor_findings',
  'pdc_auditor_finding_occurrences', 'pdc_auditor_finding_history',
  'pdc_auditor_finding_evidence', 'pdc_auditor_risk_scores',
  'pdc_auditor_rule_config', 'pdc_auditor_report_runs', 'pdc_auditor_revision',
];
for (const table of tables) {
  const ddl = tableDdl(table);
  assert.ok(ddl.includes('dealer_code text not null'), `${table} lacks dealer_code`);
  assert.ok(ddl.includes('environment text not null'), `${table} lacks environment`);
  assert.ok(ddl.includes("environment = 'staging'"), `${table} is not staging constrained`);
}

const relation = tableDdl('pdc_auditor_booking_work_relations');
assert.ok(relation.includes('booking_id uuid not null references public.workshop_bookings(id) on delete restrict'));
assert.ok(relation.includes('work_item_id uuid not null references public.vehicle_work_items(id) on delete restrict'));
assert.ok(relation.includes("relation_kind in ('explicit_fk','authoritative_relation')"));
assert.ok(relation.includes('source_revision bigint not null'));
assert.ok(relation.includes('source_recorded_at timestamptz not null'));
assert.ok(relation.includes('recorded_at timestamptz not null'));
assert.ok(!relation.includes('on delete cascade'));
assert.ok(lower.includes('create trigger pdc_auditor_booking_work_relations_immutable before update or delete'));
assert.ok(lower.includes("'pdc_auditor_booking_work_relations'"), 'relation table missing from dealer RLS loop');
assert.ok(!/grant\s+(insert|update|delete)[\s\S]{0,100}pdc_auditor_booking_work_relations/.test(lower));
assert.ok(!/create or replace function public\.[^(]*(relation|link)[^(]*\(/.test(lower), 'relation write/link RPC is forbidden');

const actor = body('pdc_auditor_actor_scope', '$scope$');
assert.ok(actor.includes('from public.pdc_auditor_user_dealer_scopes s'));
assert.ok(actor.includes('s.auth_user_id=v_uid') && actor.includes('s.normalized_email=v_email'));
assert.ok(actor.includes("s.environment='staging' and s.active"));
assert.ok(actor.includes('if v_count <> 1 then'));
assert.ok(!actor.includes("auth.jwt()->>'dealer_code'"));
assert.ok(actor.includes("r.role::text in ('viewer','operator','administrator')"));
assert.ok(actor.includes('r.auth_user_id = v_uid'), 'role binding must require the exact auth UID');
assert.ok(!actor.includes('r.auth_user_id is null or'), 'legacy email-only roles are forbidden');

const worker = body('pdc_auditor_worker_scope', '$worker$');
assert.ok(worker.includes('auth.uid()') && worker.includes("auth.jwt()->>'email'"));
assert.ok(worker.includes('join public.pdc_auditor_user_dealer_scopes s'));
assert.ok(worker.includes('join public.pdc_user_roles r'));
assert.ok(worker.includes('r.auth_user_id=v_uid') && worker.includes("r.account_status='approved'") && worker.includes('r.active'));
assert.ok(worker.includes("r.role::text in ('operator','administrator')"));
assert.ok(!worker.includes("r.role::text in ('viewer','operator','administrator')"), 'Viewer must never be an enrolled finding worker');
assert.ok(!worker.includes("auth.jwt()->>'dealer_code'"));

for (const name of [
  'pdc_auditor_actor_scope', 'pdc_auditor_worker_scope',
  'pdc_auditor_reject_history_mutation', 'pdc_auditor_valid_timestamptz',
  'pdc_auditor_json_has_sensitive_key',
  'pdc_auditor_vehicle_dealer', 'pdc_auditor_operational_revision',
  'pdc_auditor_entity_in_scope', 'get_pdc_auditor_snapshot',
  'submit_pdc_auditor_findings', 'append_pdc_auditor_rule_config',
]) {
  const start = lower.indexOf(`create or replace function public.${name}`);
  const next = lower.indexOf('create or replace function public.', start + 1);
  const fn = lower.slice(start, next < 0 ? lower.length : next);
  assert.ok(fn.includes('security definer'), `${name} must be SECURITY DEFINER`);
  assert.ok(fn.includes('set search_path=pg_catalog,public'), `${name} search_path is unsafe`);
}

const snapshot = body('get_pdc_auditor_snapshot', '$snapshot$');
assert.ok(snapshot.includes('pdc_auditor_actor_scope()'));
assert.ok(snapshot.includes('p_page_size > 100'));
for (const marker of ['limit 100', 'limit 25', 'limit 20']) assert.ok(snapshot.includes(marker));
for (const forbidden of [
  'localstorage', 'pdcsheetvehicles', "'customer_name'", "'vin'", "'registration'",
  "'source_uid'", "'source_hash'", "'description'", "'notes'", "'reason'",
  "'before_data'", "'after_data'", "'metadata'", "'actor_email'", "'provider_email'",
  'stoppage_reason', 'candidate_work_item_ids', 'canonical_match_count',
]) assert.ok(!snapshot.includes(forbidden), `snapshot exposes/uses forbidden authority ${forbidden}`);
assert.ok(!snapshot.includes('workshop_stage_code_for_work_key'), 'booking/work inference helper is forbidden');
assert.ok(!snapshot.includes('b.metadata'), 'legacy booking metadata is forbidden authority');
assert.ok(snapshot.includes('public.pdc_auditor_vehicle_dealer(v.id)=v_dealer'));
assert.ok(snapshot.includes('public.pdc_auditor_operational_revision(v_dealer)'));
assert.ok(!snapshot.includes('v.source_batch_id=v_dealer'), 'vehicles.source_batch_id is forbidden dealer authority');
assert.ok(!snapshot.includes('rv.source_batch_id=v_dealer'), 'related vehicle source_batch_id is forbidden dealer authority');
assert.ok(snapshot.includes('string_agg(') && snapshot.includes("'sha256'"), 'relation revision must be a deterministic content hash, not max(source_revision)');
assert.ok(!snapshot.includes('max(source_revision),0) into v_relation_revision'), 'relation revision must change for lower-revision inserts and revocations');
assert.ok(snapshot.includes("c->'parameters'->'allowed_pairs'"), 'station compatibility must project its exact allowed-pair array');

for (const status of [
  'explicit_linked_active', 'exact_authoritative_linked_active',
  'legacy_no_relation_unlinked', 'linked_completed_or_inactive',
  'multiple_active_bookings_for_work_item', 'revoked_authoritative_relation_unlinked',
  'corrupt_or_ambiguous_relation_unlinked',
]) assert.ok(snapshot.includes(`'${status}'`), `missing relationship state ${status}`);
assert.ok(snapshot.includes("'linked_work_item_id',case"));
assert.ok(snapshot.includes('q.valid_relation_count=1 and q.all_relation_count=1'));
assert.ok(snapshot.includes("q.status not in ('queued','planned','started','stoppage')"));
assert.ok(snapshot.includes('q.active_booking_count_for_work>1'));
assert.ok(snapshot.includes("'scope','vehicle_level','job_specific',false,'vehicle_level',true,'inferred',false,'work_item_id',null"));
assert.ok(!snapshot.includes("'scope','job_specific'"), 'vehicle-level Parts must never be copied to work');
for (const field of [
  "'source_revisions'", "'workshop_revision'", "'pdc_email_vehicle_revision'",
  "'auditor_relation_revision'", "'auditor_config_revision'", "'response_revision'",
  "'lifecycle'", "'workshop'", "'quality'", "'location'", "'eta'", "'hours'",
  "'assignments'", "'operation_lines'", "'line_adjustments'", "'sublet'",
  "'movement_events'", "'workflow_events'", "'active_rule_configs'", "'working_calendar'",
  "'resources'", "'station_compatibility'", "'collection_completeness'", "'page_manifest'",
  "'operational_revision'", "'rule_set_hash'",
]) assert.ok(snapshot.includes(field), `snapshot contract missing ${field}`);
assert.ok(snapshot.includes("'source',case when v_calendar_config is null then 'missing_holiday_configuration' else 'auditor_rule_config' end"));
assert.ok(snapshot.includes("'holiday_configuration_status'"));
assert.ok(snapshot.includes("'timezone','australia/perth'"));
assert.ok(snapshot.includes('v_response_revision := md5('));
for (const operationalTable of [
  'workshop_booking_assignments', 'workshop_booking_history', 'vehicle_master_history',
  'pdc_authenticated_email_operation_lines', 'vehicle_workshop_line_adjustments',
  'pdc_sublet_bookings', 'navision_backend_records', 'pdc_ai_intake_proposals',
  'pdc_ai_intake_history', 'vehicle_notifications', 'vehicle_master_revision',
  'navision_backend_revision', 'pdc_ai_intake_revision',
]) assert.ok(body('pdc_auditor_operational_revision', '$operational_revision$').includes(operationalTable),
  `operational revision omits ${operationalTable}`);

const submit = body('submit_pdc_auditor_findings', '$submit$');
assert.ok(submit.includes('pdc_auditor_worker_scope(v_dealer)'));
assert.ok(submit.includes('jsonb_array_length(p_findings)>100'));
assert.ok(submit.includes('octet_length(p_findings::text)>262144'));
assert.ok(submit.includes('pdc_auditor_entity_out_of_scope'));
assert.ok(submit.includes('pdc_auditor_evidence_out_of_scope'));
assert.ok(submit.includes("lifecycle_status='resolved'"));
assert.ok(submit.includes("then 'reopened' else 'observed'"));
assert.ok(submit.includes('pdc_auditor_stale_complete_run'));
assert.ok(submit.includes("p_run->>'snapshot_complete' <> 'true'"));
assert.ok(submit.includes("p_run->>'snapshot_response_revision'"));
assert.ok(submit.includes("p_run->'snapshot_page_manifest'"));
assert.ok(submit.includes("p_run->>'rule_set_hash'"));
assert.ok(submit.includes("p_run->>'payload_hash'"));
assert.ok(submit.includes('extensions.digest'));
assert.ok(submit.includes('pdc_auditor_payload_hash_mismatch'));
assert.ok(submit.includes('pdc_auditor_snapshot_revision_mismatch'));
assert.ok(submit.includes('pdc_auditor_incomplete_snapshot'));
assert.ok(submit.includes('v_server_page := public.get_pdc_auditor_snapshot(v_after_vehicle_id,100)'), 'submission must reconstruct every declared page server-side');
assert.ok(submit.includes("(v_page->>'page_size')::integer <> 100"), 'complete worker submissions must explicitly require canonical 100-row pages');
assert.ok(submit.includes("v_server_page->'items'->0->>'vehicle_id' is distinct from v_page->>'first_vehicle_id'"), 'submission must verify canonical page boundaries');
assert.ok(submit.includes('pdc_auditor_json_has_sensitive_key(p_findings)'), 'nested sanitisation guard missing');

const allowedWrites = new Set([
  'pdc_auditor_runs', 'pdc_auditor_findings', 'pdc_auditor_finding_occurrences',
  'pdc_auditor_finding_history', 'pdc_auditor_finding_evidence',
  'pdc_auditor_risk_scores', 'pdc_auditor_revision',
]);
const writes = [...submit.matchAll(/\b(?:insert\s+into|update|delete\s+from)\s+(?:public\.)?([a-z0-9_]+)/g)].map(m => m[1]);
assert.ok(writes.length >= 8, 'submission write inventory unexpectedly small');
for (const table of writes) assert.ok(allowedWrites.has(table), `submission writes non-auditor table ${table}`);
for (const table of ['vehicles', 'vehicle_work_items', 'workshop_bookings',
  'pdc_authenticated_email_operation_lines', 'vehicle_workshop_line_adjustments']) {
  assert.ok(!new RegExp(`\\b(?:insert\\s+into|update|delete\\s+from)\\s+public\\.${table}\\b`).test(submit),
    `submission writes operational table ${table}`);
}

assert.ok(!lower.includes('grant insert on table') && !lower.includes('grant update on table') && !lower.includes('grant delete on table'));
assert.ok(lower.includes("execute format('drop policy if exists %i on public.%i'"), 'RLS replay guard missing');
assert.ok((lower.match(/on conflict\(dealer_code,environment,rule_key,config_version\) do nothing/g) || []).length === 2);
const publications = [...lower.matchAll(/alter publication\s+supabase_realtime\s+add table\s+public\.([a-z0-9_]+)/g)].map(m => m[1]);
assert.deepStrictEqual(publications, ['pdc_auditor_revision']);
const dealerAuthority = body('pdc_auditor_vehicle_dealer', '$vehicle_dealer$');
assert.ok(dealerAuthority.includes('when count(*)=1'), 'duplicate current Navision authority must fail closed even when dealer codes agree');

console.log('Beta AI auditor Stage A static contract checks passed: exact relation authority, fail-closed linkage, bounded sanitized canonical snapshot, revisions, RLS/ACL and auditor-only writes (source shape only)');
