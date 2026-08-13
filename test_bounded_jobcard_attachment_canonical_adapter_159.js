'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migration = path.join(__dirname, 'supabase', 'staging_only', '159_bounded_jobcard_attachment_canonical_adapter.sql');
assert(fs.existsSync(migration), 'Migration159 SQL is required');
const sql = fs.readFileSync(migration, 'utf8');
const lower = sql.toLowerCase();

function body(tag) {
  const re = new RegExp(`\\$${tag}\\$([\\s\\S]*?)\\$${tag}\\$;`);
  const match = sql.match(re);
  assert(match, `Missing $${tag}$ body`);
  return match[1];
}
function has(text, token, message) {
  assert(text.includes(token), message || `Missing ${token}`);
}
function before(text, first, second, message) {
  const a = text.indexOf(first);
  const b = text.indexOf(second);
  assert(a >= 0 && b >= 0 && a < b, message || `${first} must precede ${second}`);
}

const adapter = body('adapter');
const reader = body('read');
const nested = adapter.match(/-- Every nested mutation[\s\S]*?begin([\s\S]*?)exception when others then/);
assert(nested, 'Adapter must contain a documented nested mutation subtransaction');
const atomic = nested[1];

// Exact append-only staging guard and dependency closure.
for (const token of [
  "version='158' and name='pmb_email_board_purge_reactivation'",
  "version='159'",
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  'public.pdc_production_environment_sentinel',
  'public.ai_email_intake', 'public.ai_email_attachments', 'public.monitored_mailboxes',
  'public.pdc_authenticated_email_import_receipts', 'public.pdc_authenticated_email_operation_lines'
]) has(sql, token);
assert(!lower.includes('production_ref'), 'Migration159 must not contain a production target');

// Only the new wrapper and reader are public authenticated surfaces; service role is excluded.
for (const signature of [
  'public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)',
  'public.read_pdc_jobcard_attachment_import_receipt(uuid)'
]) {
  has(sql, `revoke all on function ${signature} from public,anon,authenticated,service_role`);
  has(sql, `grant execute on function ${signature} to authenticated`);
}
assert(!/grant\s+execute[\s\S]{0,80}(submit_pdc_ai_intake_observation_pre135|pdc_auto_apply_ai_intake_activation_internal)/i.test(sql), 'Migration159 must not expose contained internal activation functions');
has(sql, 'grant execute on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) to service_role');
has(sql, 'revoke all on function public.process_email_intake_work(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role');
has(sql, 'grant execute on function public.process_email_intake_work(uuid,text,text,jsonb,text) to authenticated');
has(sql, 'revoke all on function public.get_pdc_email_intake_work_receipt(uuid,text,text) from public,anon,authenticated,service_role');
has(sql, 'grant execute on function public.get_pdc_email_intake_work_receipt(uuid,text,text) to authenticated');
assert(!/grant\s+execute\s+on\s+function\s+public\.(?!attest_pdc_provider_email_observation)[\s\S]{0,140}to\s+service_role/i.test(sql), 'Only provider attestation may be service-role executable');
for (const table of [
  'pdc_jobcard_attachment_import_receipts', 'pdc_jobcard_attachment_source_row_receipts',
  'pdc_provider_email_observations', 'pdc_email_intake_work_receipts'
]) {
  has(sql, `revoke all on table public.${table} from public,anon,authenticated,service_role`);
  has(sql, `create trigger ${table}_immutable`);
}

// Actor authority and retained server-side envelope identity.
for (const fn of [adapter, reader]) {
  has(fn, "r.role in('viewer','importer')");
  has(fn, "r.active and r.account_status='approved'");
  has(fn, 'public.pdc_monitor_stage_activation_writers');
  has(fn, 'w.active and w.revoked_at is null');
}
for (const token of [
  'select * into v_intake from public.ai_email_intake',
  'select * into v_attachment from public.ai_email_attachments',
  'select * into v_mailbox from public.monitored_mailboxes',
  'id=v_intake.monitored_mailbox_id',
  'not v_mailbox.active',
  "lower(btrim(coalesce(v_intake.recipient_mailbox,'')))<>lower(btrim(v_mailbox.mailbox_address))",
  "v_sender:=lower(btrim(coalesce(v_intake.sender_email,'')))",
  "v_subject:=btrim(coalesce(v_intake.subject,''))",
  'v_intake.received_at',
  "v_source_uid:='pdc-jc-159:'",
  "lower(coalesce(v_intake.source_hash,''))<>v_parent_hash",
  "lower(coalesce(v_attachment.source_hash,''))<>v_attachment_hash",
  'v_attachment.size_bytes not between 1 and 10485760',
  "'application/pdf'", "'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'"
]) has(adapter, token);
has(adapter, "(select count(*) from public.ai_email_attachments a", 'Selected attachment must be cardinality checked');
has(adapter, ")<>1", 'Selected attachment cardinality must be exactly one');

// Caller supplies only auth + canonical proposal/work rows; envelope fields are retained server data.
has(sql, 'p_intake_id uuid');
has(sql, 'p_attachment_id uuid');
has(sql, 'p_expected_parent_hash text');
has(sql, 'p_expected_attachment_hash text');
for (const forbiddenParam of ['p_sender_address', 'p_source_received_at', 'p_subject', 'p_source_uid', 'p_attachment_size', 'p_content_type']) {
  assert(!adapter.match(new RegExp(`\\b${forbiddenParam}\\b`)), `Wrapper must not accept ${forbiddenParam}`);
}
for (const token of [
  "array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]",
  "v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb",
  "v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2)",
  'public.pdc_monitor_exact_sender_enrollments',
  "e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')",
  "v_provider_observation.authentication is distinct from v_auth",
  "v_provider_observation.provider_authserv_id<>'mx.google.com'"
]) has(adapter, token);
has(sql, "v_authserv<>'mx.google.com'");
has(sql, "auth.role()<>'service_role'");
has(sql, "v_proposal.source_received_at>v_vehicle.board_purged_at");
has(sql, "values('804fa93bee0e630b96662762114aff45529af322fa1afd59908595932d3f9f4b','explicit PMB job-card sender')");
assert(!sql.includes('craig.watson@'), 'Exact sender address must not be committed in clear text');

// Strict bounded operation adapter: identity survives, descriptions need not be unique.
for (const token of [
  'jsonb_array_length(v_input_lines) not between 1 and 50',
  "array['description','estimated_hours','operation_no','source_row_no','work_key']::text[]",
  "line->>'operation_no' is distinct from 'OP'||ordinality::text",
  "coalesce(line->>'source_row_no','')!~'^[1-9][0-9]{0,8}$'",
  "line->>'description' is distinct from btrim(line->>'description')",
  "jsonb_typeof(line->'estimated_hours')<>'number'",
  "(line->>'estimated_hours')::numeric<=0",
  "mod((line->>'estimated_hours')::numeric,0.01)<>0",
  "'estimated_hours_source','job_card'",
  "'pitInspection','PARTS'",
  'count(distinct (x->>\'source_row_no\')::integer)',
  'count(distinct x->>\'operation_no\')',
  'is distinct from (select array_agg(x order by x) from jsonb_array_elements_text(v_required_work) x)'
]) has(adapter, token);
assert(!/count\s*\(\s*distinct\s+[^)]*description/i.test(adapter), 'Repeated descriptions must be allowed');
has(adapter, "array['cancelled','conflicts','customer_name','eta_to_kewdale','job_card_number','registration','stock_numbers','toyota_order_number','vehicle_description','vins']::text[]");
has(adapter, "jsonb_array_length(v_email_vehicle->'stock_numbers')<>1");
has(adapter, "v_email_vehicle->'conflicts'<>'[]'::jsonb");

// Replay is before freshness rejection, delegate calls, and every nested mutation.
const replay = adapter.indexOf('return public.read_pdc_jobcard_attachment_import_receipt(v_existing.receipt_id)');
assert(replay >= 0, 'Exact receipt replay missing');
assert(replay < adapter.indexOf("v_intake.duplicate_of is not null"), 'Replay must precede consumed/freshness gates');
assert(replay < adapter.indexOf('v_submit:=public.submit_pdc_ai_intake_observation'), 'Replay must precede observation');
assert(replay < adapter.indexOf('insert into public.pdc_jobcard_attachment_import_receipts'), 'Replay must precede receipt DML');
has(adapter, "return public.navision_backend_response(false,'attachment_replay_conflict')");

// Required call order and rollback-on-false semantics.
before(atomic, 'public.submit_pdc_ai_intake_observation(', 'public.import_pdc_authenticated_vehicle_email(', 'Observation/activation must precede vehicle import');
before(atomic, 'public.import_pdc_authenticated_vehicle_email(', 'public.import_pdc_authenticated_email_operations_with_hours(', 'Vehicle receipt must precede operation import');
before(atomic, 'public.import_pdc_authenticated_email_operations_with_hours(', 'insert into public.pdc_jobcard_attachment_import_receipts', 'Operations must precede adapter receipt');
assert.strictEqual((atomic.match(/raise exception 'PDC_159_NESTED_FALSE_RESULT'/g) || []).length >= 5, true, 'Every false/postcondition path must raise inside the subtransaction');
for (const result of ['v_submit', 'v_vehicle_result', 'v_hours_result']) has(atomic, `coalesce((${result}->>'ok')::boolean,false)`);
has(adapter, "if sqlerrm='PDC_159_NESTED_FALSE_RESULT'");
has(adapter, "return public.navision_backend_response(false,'atomic_attachment_import_failed')");

// Full-success-only intake merge, immutable receipt/readback, canonical drift and cardinality.
before(atomic, 'insert into public.pdc_jobcard_attachment_source_row_receipts', 'update public.ai_email_intake set', 'Intake may update only after per-row receipts');
has(atomic, "processing_result=coalesce(processing_result,'{}'::jsonb)||jsonb_build_object(");
for (const token of [
  'proposal_id uuid not null', 'canonical_import_receipt_id uuid not null',
  'attachment_size_bytes bigint not null', 'attachment_content_type text not null',
  'vehicle_version integer not null', 'backend_record_version integer not null',
  'requested_payload_sha256 text not null', 'operation_sha256 text not null',
  'estimated_hours_sum numeric(10,2) not null', 'canonical_operation_line_ids uuid[] not null',
  'source_row_no integer not null', 'operation_line_id uuid not null', 'response jsonb not null'
]) has(sql, token);
for (const token of [
  "return public.navision_backend_response(false,'canonical_receipt_drift'",
  'v_count<>v_receipt.operation_count',
  'v_hours is distinct from v_receipt.estimated_hours_sum',
  'v_ids is distinct from v_receipt.canonical_operation_line_ids',
  'v_digest is distinct from v_receipt.operation_sha256',
  "ol.estimated_hours_source<>'job_card'",
  'where receipt_id=p_receipt_id and actor_id=v_actor'
]) has(reader, token);
has(atomic, "(select count(*) from public.pdc_authenticated_email_operation_lines where source_hash=v_parent_hash)<>v_operation_count");
has(atomic, "jsonb_build_object('source','bounded_jobcard_attachment_canonical_adapter_159'");
for (const token of ["'booking_created',false", "'completion_created',false", "'location_scheduled',false"]) has(sql, token);
assert(!/\b(insert into|update|delete from)\s+public\.workshop_bookings\b/i.test(adapter), 'Wrapper must not schedule bookings');
assert(!/\b(insert into|update|delete from)\s+public\.vehicle_parts_updates\b/i.test(adapter), 'Wrapper must not mutate Parts completion');

has(lower.replace(/\r\n/g, '\n'), "values(\n    '159','bounded_jobcard_attachment_canonical_adapter'");
for (const token of [
  'create function public.process_email_intake_work(',
  "'authentication','canonical_attachment_id','canonical_document_hash','contract_version'",
  "v_payload->>'contract_version'<>'pmb-email-work-v2'",
  "v_server_hash:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex')",
  'create function public.get_pdc_email_intake_work_receipt(',
  'pdc_email_intake_work_receipts',
  "return public.navision_backend_response(false,'work_receipt_replay_conflict')",
  'return public.get_pdc_email_intake_work_receipt(p_intake_id,v_source,v_extraction_hash)'
]) has(sql, token);
console.log('Migration159 bounded job-card attachment canonical adapter contract passed');
