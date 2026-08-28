-- Staging-only migration 736: repair the audited reconciliation action enum
-- without changing any retained attachment evidence or requeue state.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-email-monitor-736',0));
do $guard$
begin
  if to_regclass('public.pdc_production_environment_sentinel') is not null
     or (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$')<>'20260829010000'
     or not exists(select 1 from supabase_migrations.schema_migrations where version='20260829010000' and name='735_email_monitor_storage_reconcile_requeue_successor')
     or to_regprocedure('public.admin_reconcile_pdc_email_attachment_storage_735(uuid,uuid,text,text,text,text)') is null
     or exists(select 1 from supabase_migrations.schema_migrations where version='20260829020000')
  then raise exception 'PDC_736_EXACT_735_PRESTATE_REQUIRED' using errcode='55000'; end if;
end
$guard$;

create or replace function public.admin_reconcile_pdc_email_attachment_storage_735(
  p_intake_id uuid,
  p_attachment_id uuid,
  p_original_storage_path text,
  p_canonical_storage_path text,
  p_outcome text,
  p_evidence_hash text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth as $body$
declare
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_target public.pdc_email_monitor_requeue_targets_735%rowtype;
  v_attachment public.ai_email_attachments%rowtype;
  v_existing public.pdc_email_monitor_storage_reconciliations_735%rowtype;
  v_safe_name text;
  v_expected_path text;
begin
  perform public.require_pdc_role('administrator');
  if v_actor is null or v_email='' or coalesce(auth.jwt()->>'role','')<>'authenticated'
     or p_outcome not in('canonical_verified','permanent_fail_closed')
     or lower(btrim(coalesce(p_evidence_hash,'')))!~'^[a-f0-9]{64}$'
  then raise exception 'PDC_735_ADMIN_RECONCILE_INPUT_INVALID' using errcode='22023'; end if;
  select * into v_target from public.pdc_email_monitor_requeue_targets_735 where intake_id=p_intake_id;
  if not found then raise exception 'PDC_735_EXACT_RECONCILE_TARGET_REQUIRED' using errcode='42501'; end if;
  select * into v_attachment from public.ai_email_attachments where id=p_attachment_id and intake_id=p_intake_id for share;
  if not found or v_attachment.source_hash is null or v_attachment.source_hash!~'^[a-f0-9]{64}$'
     or p_original_storage_path is distinct from v_attachment.storage_path
  then raise exception 'PDC_735_ATTACHMENT_EVIDENCE_BINDING_MISMATCH' using errcode='42501'; end if;
  v_safe_name:=left(nullif(regexp_replace(v_attachment.file_name,'[^A-Za-z0-9._-]+','_','g'),''),120);
  v_safe_name:=coalesce(v_safe_name,'attachment');
  v_expected_path:='pdc-email-intake-private/'||lower(v_attachment.source_hash)||'/'||v_safe_name;
  if p_outcome='canonical_verified' and (p_canonical_storage_path is distinct from v_expected_path
     or p_canonical_storage_path~'[\\%:]' or p_canonical_storage_path~'(^|/)\.\.(/|$)')
  then raise exception 'PDC_735_CANONICAL_PATH_BINDING_INVALID' using errcode='22023'; end if;
  if p_outcome='permanent_fail_closed' and p_canonical_storage_path is not null
  then raise exception 'PDC_735_PERMANENT_OUTCOME_MUST_NOT_BIND_PATH' using errcode='22023'; end if;
  select * into v_existing from public.pdc_email_monitor_storage_reconciliations_735 where attachment_id=p_attachment_id;
  if found then
    if v_existing.intake_id<>p_intake_id or v_existing.original_storage_path is distinct from p_original_storage_path
       or v_existing.canonical_storage_path is distinct from p_canonical_storage_path or v_existing.outcome<>p_outcome
       or v_existing.evidence_hash<>lower(p_evidence_hash)
    then raise exception 'PDC_735_RECONCILE_REPLAY_CONFLICT' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'code','storage_reconciliation_replayed','reconciliation_id',v_existing.reconciliation_id,'outcome',v_existing.outcome);
  end if;
  insert into public.pdc_email_monitor_storage_reconciliations_735(
    intake_id,attachment_id,original_storage_path,canonical_storage_path,source_hash,file_name,outcome,evidence_hash,actor_id,actor_email)
  values(p_intake_id,p_attachment_id,p_original_storage_path,p_canonical_storage_path,lower(v_attachment.source_hash),v_attachment.file_name,p_outcome,lower(p_evidence_hash),v_actor,v_email)
  returning * into v_existing;
  insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,after_data,metadata)
  values('update','pdc_email_monitor_storage_reconciliations_735',v_existing.reconciliation_id,v_actor,v_email,
    jsonb_build_object('intake_id',p_intake_id,'attachment_id',p_attachment_id,'outcome',p_outcome,'evidence_hash',lower(p_evidence_hash)),
    jsonb_build_object('contract','pdc_email_monitor_storage_reconcile_735','original_storage_path_retained',true,'append_only',true));
  return jsonb_build_object('ok',true,'code','storage_reconciled','reconciliation_id',v_existing.reconciliation_id,'outcome',p_outcome);
end
$body$;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
 '20260829020000','736_email_monitor_reconciliation_audit_action_repair',array[
  'Repair the audited reconciliation action to an existing audit_action enum value',
  'Preserve append-only storage evidence and exact-ID requeue custody without rewriting retained rows'
 ]
);
notify pgrst,'reload schema';
commit;
