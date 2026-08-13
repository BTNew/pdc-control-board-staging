'use strict';
const assert=require('assert');
const crypto=require('crypto');
const fs=require('fs');
const path=require('path');
const root=__dirname;
const migrationName='157_bounded_pmb_workbook_importer_review.sql';
const migrationPath=path.join(root,'supabase','staging_only',migrationName);
assert(fs.existsSync(migrationPath),'Migration157 SQL missing');
assert(!fs.existsSync(path.join(root,'supabase','migrations',migrationName)),'Migration157 must remain staging-only');
const sql=fs.readFileSync(migrationPath,'utf8').replace(/\r\n/g,'\n');
const lower=sql.toLowerCase();
const has=(s,m)=>assert(lower.includes(s.toLowerCase()),m||`missing Migration157 marker: ${s}`);
const count=s=>lower.split(s.toLowerCase()).length-1;
function body(name){
 const start=lower.search(new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`,'i'));
 assert(start>=0,`missing function ${name}`);
 const rest=sql.slice(start);const m=rest.match(/\bas\s+(\$[a-z_][a-z0-9_]*\$|\$\$)/i);assert(m,`missing body tag ${name}`);
 const from=start+m.index+m[0].length;const end=sql.indexOf(`${m[1]};`,from);assert(end>=0,`unterminated ${name}`);return lower.slice(start,end+m[1].length+1);
}
function ordered(b,a,z,label){const ai=b.indexOf(a.toLowerCase()),zi=b.indexOf(z.toLowerCase());assert(ai>=0&&zi>=0&&ai<zi,label||`${a} must precede ${z}`);}
// SQL artifact identity is content-based, not checkout-platform line-ending based.
function sha(file){return crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n')).digest('hex');}

has('begin;');has("version='156'");has("name='monitor_parts_and_complete_purge_review_remediation'");has("values('157','bounded_pmb_workbook_importer_review'");
assert(502<=600,'Migration157 must support the retained 502-pair workbook');
has('pair_count integer not null check(pair_count between 1 and 600)');
has("set local statement_timeout='600s'");
[
 'pdc_pmb_workbook_previews','pdc_pmb_workbook_pair_reviews','pdc_pmb_workbook_operation_reviews',
 'pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_apply_authorizations',
 'pdc_pmb_workbook_apply_receipts','pdc_pmb_workbook_pair_receipts'
].forEach(t=>has(`create table public.${t}`,`missing immutable table ${t}`));
has('unique(pair_id,operation_index)');assert(!sql.includes('unique(preview_id,source_hash,operation_no)'),'duplicate operation evidence must persist for quarantine');has('approval_set_hash');has("interval '24 hours'");has("interval '2 hours'");
assert(count('pdc_pmb_workbook_reject_mutation')>=3,'immutable trigger function and trigger installation required');
has("execute format('create trigger %i before update or delete on public.%i");

const scope=body('pdc_pmb_workbook_actor_scope');
has("else 'importer'");has('pdc_monitor_stage_activation_writers');
assert(!scope.includes("'viewer'"),'generic Viewer must not gain importer authority');
const classify=body('pdc_pmb_workbook_classify_identity');
[
 "p_stock='13056899'",'is_real_vehicle_stock_number','navision_backend_records',"dealer_code in('14450','37047')",
 'navision_board_activations','canonical_vehicle_id','vehicle_aliases',"alias_type_normalized='stock_number'",
 'cardinality(v_backend_ids)>1','cardinality(v_owner_ids)>1','rft_collected_at','current_location',
 'registration_identity_approval_required','no_current_stock_manager_override_required','exact_current_stock'
].forEach(x=>assert(classify.includes(x),`identity classifier missing ${x}`));

const preview=body('preview_pdc_pmb_retained_workbook');
[
 'jsonb_array_length(v_payload) not between 1 and 600','server_payload_hash_mismatch','navision_backend_revision',
 'pdc_pmb_workbook_classify_identity',"'^op([1-9]|[1-9][0-9]|100)$'",'duplicate_operation_number_within_pair',
 'unsupported_work_key','estimated_hours_out_of_range','quarantined','exact_applied_workbook_replay','a.expires_at>clock_timestamp()','preview_ready'
].forEach(x=>assert(preview.includes(x),`preview missing ${x}`));
ordered(preview,"pg_advisory_xact_lock(hashtextextended('navision-backend-store'","role='importer'",'Preview must serialize backend before definitive Importer lock');
ordered(preview,"role='importer'",'insert into public.pdc_pmb_workbook_previews','Preview evidence requires post-wait authority');

const approve=body('approve_pdc_pmb_workbook_pair_exception');
[
 "role='administrator'",'navision_backend_revision','pair_identity_drift','preview_expired_or_excluded_stock13056899',
 'registration_exact_target_required','bound_stock_target_required','exception_backend_target_forbidden','pair_approved'
].forEach(x=>assert(approve.includes(x),`approval missing ${x}`));
ordered(approve,"pg_advisory_xact_lock(hashtextextended('navision-backend-store'","role='administrator'",'Approval must lock Navision/targets before definitive Administrator authority');

const authorize=body('authorize_pdc_pmb_workbook_apply');
[
 'backend_revision_conflict','pair_approvals_incomplete','zero_applicable_pairs','approval_set_hash',
 "interval '119 minutes'",'exact_apply_authorization_replay','apply_authorization_expired_repreview_required','apply_authorized'
].forEach(x=>assert(authorize.includes(x),`authorization missing ${x}`));
ordered(authorize,"pg_advisory_xact_lock(hashtextextended('navision-backend-store'","role='administrator'",'Authorization must lock Navision/targets before definitive Administrator authority');

const apply=body('apply_pdc_pmb_retained_workbook');
[
 "pg_advisory_xact_lock(hashtextextended('navision-backend-store'",'exact_apply_replay','v_auth.expires_at<=clock_timestamp()',
 'approval_set_hash_conflict','pdc_157_pair_identity_drift','pdc_157_backend_record_version_conflict','pdc_157_vehicle_version_conflict',
 'exact_workbook_apply_replay','on conflict(source_hash,operation_no) do nothing','where not public.vehicle_work_items.completed','pair_aggregate_sha256',
 'operation_aggregate_sha256','workbook_applied','zero_add_replay'
].forEach(x=>assert(apply.includes(x),`apply missing ${x}`));
ordered(apply,"pg_advisory_xact_lock(hashtextextended('navision-backend-store'",'for update','Apply must serialize Navision before vehicle waits');
ordered(apply,'exact_apply_replay','insert into public.pdc_authenticated_email_import_receipts','Exact replay must precede operational mutation');
assert(!apply.includes('workshop_bookings'),'Workbook Apply must not schedule');
assert(!apply.includes('vehicle_parts_updates'),'Workbook Apply must not mutate Parts');
assert(!apply.includes('update public.vehicles'),'Workbook Apply must not change existing vehicle location/state');

const read=body('read_pdc_pmb_workbook_pair_verification');
['submitted_by=v_uid','pair_receipt_hash','applied_vehicle_id','applied_operation_count','pair_verification'].forEach(x=>assert(read.includes(x),`readback missing ${x}`));
[
 'preview_pdc_pmb_retained_workbook(text,text,text,jsonb)',
 'read_pdc_pmb_workbook_pair_verification(uuid,integer,integer)'
].forEach(sig=>has(`grant execute on function public.${sig} to authenticated`));
[
 'approve_pdc_pmb_workbook_pair_exception(uuid,uuid,text,text,uuid,uuid,integer,text)',
 'authorize_pdc_pmb_workbook_apply(uuid,text,text,text,integer,integer)',
 'apply_pdc_pmb_retained_workbook(uuid,text,text,text)'
].forEach(sig=>has(`grant execute on function public.${sig} to authenticated`));
assert(!/grant execute on function public\.(?:preview|read|approve|authorize|apply)_pdc_pmb[^;]+to service_role/i.test(lower),'service role must not execute Migration157 RPCs');
assert(!/grant (?:insert|update|delete|all) on (?:table )?public\.pdc_pmb_workbook_/i.test(lower),'no direct evidence mutation grants');

assert.strictEqual(sha('supabase/staging_only/124_bulk_jc_stock_workbook_contract.sql'),'ddbb9abe0e4d52a7fe9725b79002df266f08247b110bdd5b86bd979f01f74b71','Migration124 drift');
assert.strictEqual(sha('supabase/staging_only/128_stock_only_stage_mapped_workbook_import.sql'),'d0ea029b3f0fbd5a960a068fd55a32740458ddef9526a62b43249cd671cdae90','Migration128 drift');
assert.strictEqual(sha('supabase/staging_only/129_bulk_stock_only_vehicle_privacy_guard.sql'),'cb3831b8354d7868fa6a1c63a8a5a102bb0b2739df19c2c058f6b6f319b59a5b','Migration129 drift');
console.log('Migration157 bounded PMB workbook importer review contract passed');
