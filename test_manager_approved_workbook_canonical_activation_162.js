'use strict';
const assert=require('assert');
const crypto=require('crypto');
const fs=require('fs');
const path=require('path');
const root=__dirname;
const rel='supabase/staging_only/162_manager_approved_workbook_canonical_activation.sql';
const file=path.join(root,rel);
assert(fs.existsSync(file),'Migration162 SQL missing');
assert(!fs.existsSync(path.join(root,'supabase','migrations',path.basename(file))),'Migration162 must remain staging-only');
const sql=fs.readFileSync(file,'utf8').replace(/\r\n/g,'\n');
const lower=sql.toLowerCase();
const has=(x,msg)=>assert(lower.includes(x.toLowerCase()),msg||`missing ${x}`);
function body(name){
 const start=lower.search(new RegExp(`create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.${name}\\s*\\(`,'i'));
 assert(start>=0,`missing function ${name}`);const rest=sql.slice(start);const m=rest.match(/\bas\s+(\$[a-z_][a-z0-9_]*\$|\$\$)/i);
 assert(m,`missing body tag ${name}`);const from=start+m.index+m[0].length;const end=sql.indexOf(`${m[1]};`,from);assert(end>=0,`unterminated ${name}`);
 return lower.slice(start,end+m[1].length+1);
}
function ordered(s,a,b,msg){const x=s.indexOf(a.toLowerCase()),y=s.indexOf(b.toLowerCase());assert(x>=0&&y>=0&&x<y,msg||`${a} must precede ${b}`);}
function sha(rel){return crypto.createHash('sha256').update(fs.readFileSync(path.join(root,rel))).digest('hex');}

has("version='161'");has("version='157'");has("values('162','manager_approved_workbook_canonical_activation'");
has("to_regclass('public.pdc_production_environment_sentinel') is not null");
has("project_ref='cdsmnqxtyyoeoznmbidd'");
[
 'pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_admin_countersignatures','pdc_pmb_canonical_apply_authorizations',
 'pdc_pmb_canonical_apply_receipts','pdc_pmb_canonical_pair_receipts'
].forEach(t=>{has(`create table public.${t}`);has(`'${t}'`);});
has('create table public.pdc_pmb_canonical_manager_authorities');
has('create or replace function public.configure_pdc_pmb_canonical_manager_authority');
has("'authorize workbook canonical manager'");
has("'revoke workbook canonical manager'");
has("r.role='administrator'");
has('target_must_be_approved_operator');
has('revoke all on table public.pdc_pmb_canonical_manager_authorities from public,anon,authenticated,service_role');
has('pdc_pmb_workbook_reject_mutation()');has('revoke all on table public.%i from public,anon,authenticated,service_role');

const candidate=body('pdc_pmb_workbook_canonical_candidate');
[
 "p.classification='no_current_stock_manager_override_required'","p.reason_code='manager_stock_only_create_required'",
 "p.classification='terminal_identity_conflict'","p.reason_code='canonical_stock_activation_or_owner_conflict'","stock='13056899'",
 "source_system='microsoft_navision'","dealer_code in('14450','37047')",'cardinality(backend_ids)<>1',"navision_operational_location(r.normalized_data)='completed'",
 "action','create_canonical_vehicle'",'r.canonical_vehicle_id is null','cardinality(owner_ids)<>0','cardinality(vin_ids)<>0',
 'source_record_id_normalized','navision_board_activations',"action','reactivate_complete_board_purge'",'v.board_purged_at is null',
 'v.deleted_at is null',"v.lifecycle_state<>'deleted'",'v.visible_on_board','v.rft_collected_at is not null',
 "upper(btrim(coalesce(v.current_location,'')))='completed'",'v.deleted_reason is distinct from v.board_purge_reason','v.board_purged_by is null',
 'workshop_bookings','vehicle_work_items','vehicle_parts_updates','vehicle_workshop_line_adjustments','vehicle_sublet_providers','pdc_sublet_bookings',
 "a.completion_reason is distinct from 'staging board purge'",'purged_activation_binding_conflict'
].forEach(x=>assert(candidate.includes(x),`candidate guard missing ${x}`));

const manager=body('manager_approve_pdc_pmb_canonical_activation');
[
 "p_confirmation<>'manager approve canonical board activation'","r.role='operator'",'manager_operator_required','pdc_pmb_canonical_manager_authorities',
 'manager_authority_required','pdc_pmb_workbook_canonical_candidate',
 'preview_hash','pair_hash','source_hash','backend_record_version','target_vehicle_version','exact_manager_approval_replay'
].forEach(x=>assert(manager.includes(x),`Manager approval missing ${x}`));
ordered(manager,"pg_advisory_xact_lock(hashtextextended('navision-backend-store'","r.role='operator'",'Manager authority must be rechecked after candidate/identity waits');

const admin=body('administrator_countersign_pdc_pmb_canonical_activation');
[
 "p_confirmation<>'administrator countersign canonical board activation'","r.role='administrator'",'independent_manager_and_administrator_required',
 'administrator_candidate_drift','manager_approval_hash','exact_administrator_countersignature_replay'
].forEach(x=>assert(admin.includes(x),`Administrator countersignature missing ${x}`));
ordered(admin,"pg_advisory_xact_lock(hashtextextended('navision-backend-store'","r.role='administrator'",'Administrator authority must be rechecked after target waits');

const authorize=body('authorize_pdc_pmb_canonical_activation_apply');
[
 "p_confirmation<>'authorize manager approved canonical activations'",'expected_activation_count','approval_set_hash','backend_revision',
 'administrator_countersignatures_incomplete',"interval '119 minutes'",'canonical_apply_authorized'
].forEach(x=>assert(authorize.includes(x),`Authorization missing ${x}`));

const apply=body('apply_pdc_pmb_canonical_activations');
[
 "p_confirmation<>'apply manager approved canonical activations'",'exact_canonical_apply_replay','backend_revision_conflict',
 'administrator_countersignature_missing_or_not_independent','canonical_candidate_drift','canonical_frozen_count_mismatch','canonical_approval_set_hash_conflict',
 "action='reactivate_complete_board_purge'","activation_source='manual'",'reconcile_navision_operational_record',
 'pdc_162_backend_revision_postcondition_failed','pdc_162_canonical_postcondition_failed','pair_aggregate_sha256','repreview_required',
 'migration157_apply_not_bypassed','booking_mutated',"'parts_mutated',false","'work_mutated',false"
].forEach(x=>assert(apply.includes(x),`Apply missing ${x}`));
ordered(apply,"x.role='administrator'",'exact_canonical_apply_replay','Replay disclosure must require current Administrator authority');
ordered(apply,'canonical_approval_set_hash_conflict',"if m.action='reactivate_complete_board_purge'",'All pair validation must finish before operational DML');
assert(!apply.includes('insert into public.vehicle_work_items'),'Migration162 must not import workbook work');
assert(!apply.includes('insert into public.vehicle_parts_updates'),'Migration162 must not mutate Parts');
assert(!apply.includes('insert into public.workshop_bookings'),'Migration162 must not create bookings');
assert(!apply.includes('current_location='),'Migration162 direct DML must not assign location; only canonical reconciler may do so');
assert(!apply.includes('job_card_number='),'Migration162 direct DML must not assign job card');

[
 'configure_pdc_pmb_canonical_manager_authority(uuid,boolean,text)',
 'manager_approve_pdc_pmb_canonical_activation(uuid,uuid,text,text,text,uuid,integer,uuid,integer,text,text)',
 'administrator_countersign_pdc_pmb_canonical_activation(uuid,text,text,text)',
 'authorize_pdc_pmb_canonical_activation_apply(uuid,text,text,integer,text)',
 'apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text)'
].forEach(sig=>has(`grant execute on function public.${sig} to authenticated`));
assert(!/grant execute on function public\.(?:manager_approve|administrator_countersign|authorize|apply)_pdc_pmb_canonical[^;]+to service_role/i.test(lower));
assert.strictEqual(sha('supabase/staging_only/157_bounded_pmb_workbook_importer_review.sql'),'a2ad32471fdfb1104fa6f4d16f50d5bbcb441728de266f08a6a7afc9caeafaf5','Migration157 drift');
assert.strictEqual(sha('supabase/staging_only/158_pmb_email_board_purge_reactivation.sql'),'0365d20d174fa496d552d6c50041bdbbd60ef59b13a250004c503bb6776b8836','Migration158 drift');
assert.strictEqual(sha('supabase/staging_only/161_non_navision_jobcard_board_creation.sql'),'b2a447bd1412da545673713d97f3c67474bb6e8440e3db079ed96e66fa4ecc09','Migration161 drift');
console.log('Migration162 Manager-approved canonical activation contract passed');
