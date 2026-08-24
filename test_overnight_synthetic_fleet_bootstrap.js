'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const migrationRel = 'supabase/staging_only/20260825000000_363_overnight_synthetic_fleet_bootstrap.sql';
const sql = fs.readFileSync(path.join(root, migrationRel), 'utf8');

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
  "running_status='stopped'",
  'gateway_instance_id IS NULL',
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
function pgJsonbText(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(pgJsonbText).join(', ')}]`;
  const keys = Object.keys(value).sort((a,b) => a.length - b.length || Buffer.compare(Buffer.from(a), Buffer.from(b)));
  return `{${keys.map(k => `${JSON.stringify(k)}: ${pgJsonbText(value[k])}`).join(', ')}}`;
}
const catalogPgHash = require('crypto').createHash('sha256').update(pgJsonbText(specs)).digest('hex');
assert.strictEqual(catalogPgHash, '0bc2791f0b79bf03018f5d3ec444441253c0aa8a994dd8a31f7bd49f20738d16',
  'executable PostgreSQL-jsonb catalog hash must match the migration constant');
for (const spec of specs) {
  for (const field of ['scenario_name','stock','customer','job_card','description','notes']) {
    assert(String(spec[field]).startsWith('HERMES-TEST'), `${field} must be HERMES-TEST-prefixed`);
  }
}

// Deterministic identities, collision closure, canonical incomplete work only.
for (const fragment of [
  'extensions.uuid_generate_v5',
  "'hermes_overnight_synthetic'",
  "v.source_batch_id IS DISTINCT FROM p_run_id",
  "v.source_record_id IS DISTINCT FROM r.stock_number",
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
  'singleton AND NOT enabled AND NOT outbound_email_enabled',
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

// Executable no-database regression model. These are behavioral negative controls,
// not marker-only checks: each hostile state must be rejected by the same contract
// the SQL implements.
function containmentClosed(state) {
  return state.pilot.length === 1
    && state.pilot[0].singleton === true
    && ['enabled', 'outbound_email_enabled', 'automatic_rule_application', 'automatic_authenticated_jobcards']
      .every(k => state.pilot[0][k] === false)
    && state.monitor.length === 1
    && state.monitor[0].singleton === true
    && state.monitor[0].running_status === 'stopped'
    && state.monitor[0].gateway_instance_id === null
    && state.mailboxes.every(x => x.active === false)
    && state.writers.every(x => !(x.active && x.revoked_at === null))
    && state.notifications.length === 0;
}
const contained = {
  pilot: [{singleton:true, enabled:false, outbound_email_enabled:false, automatic_rule_application:false, automatic_authenticated_jobcards:false}],
  monitor: [{singleton:true, running_status:'stopped', gateway_instance_id:null}],
  mailboxes: [{active:false}], writers: [{active:false, revoked_at:'contained'}], notifications: [],
};
assert(containmentClosed(contained));
for (const mutate of [
  s => { s.pilot = []; }, s => { s.pilot.push({...s.pilot[0]}); },
  s => { s.pilot[0].automatic_rule_application = true; },
  s => { s.monitor = []; }, s => { s.monitor.push({...s.monitor[0]}); },
  s => { s.monitor[0].running_status = 'running'; }, s => { s.monitor[0].gateway_instance_id = 'gateway'; },
  s => { s.mailboxes[0].active = true; }, s => { s.writers[0] = {active:true, revoked_at:null}; },
  s => { s.notifications.push({id:1}); },
]) {
  const hostile = structuredClone(contained); mutate(hostile);
  assert(!containmentClosed(hostile), 'zero/multiple/drifted containment must fail closed');
}

// PostgreSQL SHARE conflicts with ROW EXCLUSIVE, the lock acquired by INSERT,
// UPDATE and DELETE. Runtime and migration guards must lock every containment
// surface and revalidate while those transaction-scoped locks are still held.
const pgConflicts = {SHARE: new Set(['ROW EXCLUSIVE','SHARE UPDATE EXCLUSIVE','SHARE ROW EXCLUSIVE','EXCLUSIVE','ACCESS EXCLUSIVE'])};
assert(pgConflicts.SHARE.has('ROW EXCLUSIVE'));
class ContainmentTxn {
  constructor(state) { this.state=structuredClone(state); this.shareLocked=false; this.revalidations=0; }
  lockShare() { this.shareLocked=true; }
  concurrentRowMutation(mutator) { if (this.shareLocked) throw new Error('ROW EXCLUSIVE conflicts with SHARE'); mutator(this.state); }
  revalidate() { this.revalidations++; if (!containmentClosed(this.state)) throw new Error('containment drift'); }
}
const lockedTxn=new ContainmentTxn(contained); lockedTxn.lockShare(); lockedTxn.revalidate();
assert.throws(()=>lockedTxn.concurrentRowMutation(s=>{s.monitor=[];}),/conflicts/); lockedTxn.revalidate();
assert.strictEqual(lockedTxn.revalidations,2);
const unlockedTxn=new ContainmentTxn(contained); unlockedTxn.concurrentRowMutation(s=>{s.monitor=[];});
assert.throws(()=>unlockedTxn.revalidate(),/containment drift/);
for (const table of ['pdc_email_monitor_pilot','pdc_email_monitor_status','monitored_mailboxes','pdc_monitor_stage_activation_writers','vehicle_notifications']) {
  const occurrences = [...sql.matchAll(new RegExp(`LOCK TABLE public\\.${table} IN SHARE MODE`, 'g'))].length;
  assert(occurrences >= 2, `${table} must be locked by migration-time and runtime containment`);
}
assert((sql.match(/PDC_363_RUNTIME_CONTAINMENT_MISMATCH/g) || []).length >= 3,
  'runtime containment must be checked initially, before replay return, and before receipt/return');
assert(sql.includes('PDC_363_FINAL_CONTAINMENT_MISMATCH'), 'containment must be revalidated immediately before commit');

function uuidToBytes(uuid) { return Buffer.from(uuid.replace(/-/g, ''), 'hex'); }
function uuidV5(namespace, name) {
  const digest = require('crypto').createHash('sha1').update(Buffer.concat([uuidToBytes(namespace), Buffer.from(name)])).digest().subarray(0,16);
  digest[6] = (digest[6] & 0x0f) | 0x50; digest[8] = (digest[8] & 0x3f) | 0x80;
  const h = digest.toString('hex'); return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}
const namespace = '36300000-0000-5000-8000-000000000363';
const runId = 'HERMES-TEST-RUN-20260824';
const identities = specs.map(s => ({
  scenario_no:s.scenario_no, stock:s.stock,
  vehicle_id:uuidV5(namespace, `${runId}:vehicle:${s.stock}`),
  registry_id:uuidV5(namespace, `${runId}:registry:${s.scenario_no}`),
  permanent_vehicle_id:`HERMES-TEST-PERM-${String(s.scenario_no).padStart(3,'0')}`,
  work_ids:(s.work_keys || []).map(k => uuidV5(namespace, `${runId}:work:${s.stock}:${k}`)),
}));
assert.strictEqual(new Set(identities.flatMap(x => [x.vehicle_id,x.registry_id,...x.work_ids])).size,
  identities.reduce((n,x) => n + 2 + x.work_ids.length, 0), 'deterministic identities must be unique');
assert.deepStrictEqual(identities, specs.map(s => ({
  scenario_no:s.scenario_no, stock:s.stock,
  vehicle_id:uuidV5(namespace, `${runId}:vehicle:${s.stock}`), registry_id:uuidV5(namespace, `${runId}:registry:${s.scenario_no}`),
  permanent_vehicle_id:`HERMES-TEST-PERM-${String(s.scenario_no).padStart(3,'0')}`,
  work_ids:(s.work_keys || []).map(k => uuidV5(namespace, `${runId}:work:${s.stock}:${k}`)),
})), 'identity generation must be deterministic');

function sourceCollision(row) {
  const text = JSON.stringify(row).toLowerCase();
  return row.source_system_normalized === 'hermes_overnight_synthetic'
    || row.source_batch_id === runId
    || text.includes('hermes-test-') || text.includes('hermestest')
    || identities.some(i => text.includes(i.vehicle_id) || text.includes(i.registry_id)
      || text.includes(i.permanent_vehicle_id.toLowerCase()));
}
for (const collision of [
  {source_system_normalized:'hermes_overnight_synthetic'}, {source_batch_id:runId},
  {source_record_id:'HERMES-TEST-099'}, {id:identities[0].vehicle_id},
  {permanent_vehicle_id:identities[0].permanent_vehicle_id}, {normalized_alias_value:'HERMESTEST001'},
  {normalized_stock:'HERMESTEST777'}, {activated_stock_number:'HERMES-TEST-888'},
]) assert(sourceCollision(collision), `collision not detected: ${JSON.stringify(collision)}`);
assert(!sourceCollision({source_system_normalized:'microsoft_navision', source_batch_id:'real', source_record_id:'ABC123'}));
for (const fragment of [
  "source_system_normalized='hermes_overnight_synthetic'", "source_batch_id='HERMES-TEST-RUN-20260824'",
  "source_record_id ILIKE 'HERMES-TEST-%'", 'v.id=i.vehicle_id', 'v.permanent_vehicle_id=i.permanent_vehicle_id',
  "a.normalized_alias_value LIKE 'HERMESTEST%'", "t.normalized_stock LIKE 'HERMESTEST%'",
]) has(fragment, `missing namespace-wide collision closure: ${fragment}`);

function canonicalRows() {
  return specs.map((s, ix) => ({
    registry_id:identities[ix].registry_id, run_id:runId, scenario_no:s.scenario_no, scenario_name:s.scenario_name,
    request_sha256:'a'.repeat(64), spec:structuredClone(s),
    vehicle:{id:identities[ix].vehicle_id, permanent_vehicle_id:identities[ix].permanent_vehicle_id,
      stock_number:s.stock, customer_name:s.customer, job_card_number:s.job_card, vehicle_description:s.description,
      current_location:s.initial_location || 'Other', eta_to_kewdale:s.eta || null, lifecycle_state:'active', visible_on_board:true,
      deleted_at:null, board_purged_at:null, rft_collected_at:null, source_system:'hermes_overnight_synthetic',
      source_batch_id:runId, source_record_id:s.stock, completion_evidence:false},
    work_items:(s.work_keys || []).map((k,j) => ({id:identities[ix].work_ids[j], work_key:k, required:true,
      completed:false, completed_by:null, completed_at:null, notes:s.notes || 'HERMES-TEST render-only incomplete synthetic requirement'})),
  }));
}
function readbackValid(rows) {
  if (rows.length !== 20 || new Set(rows.map(r => r.scenario_no)).size !== 20) return false;
  return rows.every((r,ix) => {
    const s=specs[ix], i=identities[ix], v=r.vehicle;
    const expectedKeys=[...(s.work_keys || [])].sort();
    return r.run_id===runId && r.scenario_no===s.scenario_no && r.scenario_name===s.scenario_name
      && JSON.stringify(r.spec)===JSON.stringify(s) && r.registry_id===i.registry_id
      && v.id===i.vehicle_id && v.permanent_vehicle_id===i.permanent_vehicle_id
      && v.stock_number===s.stock && v.customer_name===s.customer && v.job_card_number===s.job_card
      && v.vehicle_description===s.description && v.lifecycle_state==='active' && v.visible_on_board===true
      && v.deleted_at===null && v.board_purged_at===null && v.rft_collected_at===null
      && v.source_system==='hermes_overnight_synthetic' && v.source_batch_id===runId && v.source_record_id===s.stock
      && v.completion_evidence===false && JSON.stringify(r.work_items.map(w=>w.work_key).sort())===JSON.stringify(expectedKeys)
      && r.work_items.every(w => w.required===true && w.completed===false && w.completed_by===null && w.completed_at===null
        && w.notes.startsWith('HERMES-TEST'));
  });
}
const canonical = canonicalRows(); assert(readbackValid(canonical));
for (const mutate of [
  r=>r.pop(), r=>r.push(structuredClone(r[0])), r=>{r[0].vehicle.visible_on_board=false;},
  r=>{r[0].vehicle.deleted_at='now';}, r=>{r[0].vehicle.source_batch_id='drift';},
  r=>{r[0].vehicle.id=identities[1].vehicle_id;}, r=>{r[0].work_items.push({id:'extra',work_key:'EVIL',required:true,completed:false,completed_by:null,completed_at:null,notes:'HERMES-TEST bad'});},
  r=>{if(r[0].work_items[0]) r[0].work_items[0].completed=true; else r[0].spec.work_keys=['EVIL'];},
  r=>{r[0].vehicle.completion_evidence=true;}, r=>{r[0].spec.stock='HERMES-TEST-999';},
]) { const hostile=structuredClone(canonical); mutate(hostile); assert(!readbackValid(hostile), 'readback drift must raise, never filter'); }
for (const fragment of ['PDC_363_READBACK_DRIFT','jsonb_array_length(v_rows)<>20', 'r.spec', "r.role IN('operator','administrator')"]) has(fragment);

function bootstrapModel(state, key, payloadHash) {
  if (!containmentClosed(state.containment)) throw new Error('containment');
  const old=state.receipts.get(key);
  if (old) { if (old.hash!==payloadHash) throw new Error('payload mismatch'); return old.response; }
  if (state.collisions.some(sourceCollision)) throw new Error('collision');
  const before={vehicles:state.vehicles.length, registry:state.registry.length, work:state.work.length,
    notifications:state.containment.notifications.length, bookings:state.bookings.length, parts:state.parts.length,
    sublets:state.sublets.length, providers:state.providers.length, email:state.email.length};
  state.vehicles.push(...canonical.map(x=>x.vehicle)); state.registry.push(...canonical); state.work.push(...canonical.flatMap(x=>x.work_items));
  if (state.injectForbidden) state.bookings.push({vehicle_id:canonical[0].vehicle.id});
  const after={vehicles:state.vehicles.length, registry:state.registry.length, work:state.work.length,
    notifications:state.containment.notifications.length, bookings:state.bookings.length, parts:state.parts.length,
    sublets:state.sublets.length, providers:state.providers.length, email:state.email.length};
  if (after.vehicles-before.vehicles!==20 || after.registry-before.registry!==20
      || after.work-before.work!==canonical.flatMap(x=>x.work_items).length || after.notifications!==before.notifications
      || ['bookings','parts','sublets','providers','email'].some(k=>after[k]!==before[k])) throw new Error('delta or forbidden side effect');
  const response={vehicle_delta:20,registry_delta:20,notification_delta:0}; state.receipts.set(key,{hash:payloadHash,response}); return response;
}
function emptyModel(extra={}) { return {containment:structuredClone(contained),collisions:[],vehicles:[],registry:[],work:[],
  bookings:[],parts:[],sublets:[],providers:[],email:[],receipts:new Map(),...extra}; }
const model=emptyModel();
const first=bootstrapModel(model,'key','same'); const replay=bootstrapModel(model,'key','same');
assert.strictEqual(replay,first); assert.strictEqual(model.vehicles.length,20);
assert.throws(()=>bootstrapModel(model,'key','changed'),/payload mismatch/);
const collisionModel=emptyModel({collisions:[{source_batch_id:runId}]});
assert.throws(()=>bootstrapModel(collisionModel,'other','same'),/collision/);
assert.throws(()=>bootstrapModel(emptyModel({injectForbidden:true}),'side-effect','same'),/forbidden side effect/);

// Protected digests must compare the identical pre-existing set, excluding the
// deterministic target IDs on both sides (including hostile pre-existing registry rows).
function protectedDigest(rows, targetIds) {
  const protectedRows=rows.filter(r=>!targetIds.has(r.id)).sort((a,b)=>a.id.localeCompare(b.id));
  return {count:protectedRows.length, hash:require('crypto').createHash('sha256').update(JSON.stringify(protectedRows)).digest('hex')};
}
const protectedRows=[{id:'protected-a',value:1},{id:identities[0].vehicle_id,value:'hostile pre-existing target'}];
const targetIds=new Set(identities.map(i=>i.vehicle_id));
const protectedBefore=protectedDigest(protectedRows,targetIds);
const protectedAfter=protectedDigest([...protectedRows.filter(r=>r.id!==identities[0].vehicle_id),...canonical.map(x=>x.vehicle)],targetIds);
assert.deepStrictEqual(protectedAfter,protectedBefore, 'same protected-row set must hash identically before and after');
assert.notDeepStrictEqual(protectedDigest(protectedRows,new Set()),protectedAfter, 'all-before/filtered-after defect must be detected');
for (const fragment of ['WHERE NOT (v.id=ANY(v_target_vehicle_ids))', 'v_target_vehicle_ids uuid[]',
  'protected_vehicle_count_before', 'protected_vehicle_count_after']) has(fragment);

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

console.log('overnight_synthetic_fleet_bootstrap source contract: PASS');
