-- Staging-only migration 737: bind the audited requeue function to the
-- immutable receipt table created by 735. No evidence rows are rewritten.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-email-monitor-737',0));
do $guard$
begin
  if to_regclass('public.pdc_production_environment_sentinel') is not null
     or (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$')<>'20260829020000'
     or not exists(select 1 from supabase_migrations.schema_migrations where version='20260829020000' and name='736_email_monitor_reconciliation_audit_action_repair')
     or to_regprocedure('public.admin_requeue_pdc_email_intake_735(uuid,text,text)') is null
     or to_regclass('public.pdc_email_monitor_requeue_receipts_735') is null
     or exists(select 1 from supabase_migrations.schema_migrations where version='20260829030000')
  then raise exception 'PDC_737_EXACT_736_PRESTATE_REQUIRED' using errcode='55000'; end if;
end
$guard$;

create or replace function public.admin_requeue_pdc_email_intake_735(
  p_intake_id uuid,
  p_request_key text,
  p_reason text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth as $body$
declare
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_target public.pdc_email_monitor_requeue_targets_735%rowtype;
  v_row public.ai_email_intake%rowtype;
  v_existing public.pdc_email_monitor_requeue_receipts_735%rowtype;
  v_receipt public.pdc_email_monitor_requeue_receipts_735%rowtype;
begin
  perform public.require_pdc_role('administrator');
  if v_actor is null or v_email='' or coalesce(auth.jwt()->>'role','')<>'authenticated'
     or p_request_key!~'^pdc-email-monitor-735:[0-9a-f-]{36}$'
     or length(btrim(coalesce(p_reason,''))) not between 1 and 500
  then raise exception 'PDC_735_ADMIN_REQUEUE_INPUT_INVALID' using errcode='22023'; end if;
  select * into v_target from public.pdc_email_monitor_requeue_targets_735 where intake_id=p_intake_id;
  if not found then raise exception 'PDC_735_EXACT_REQUEUE_TARGET_REQUIRED' using errcode='42501'; end if;
  select * into v_existing from public.pdc_email_monitor_requeue_receipts_735 where request_key=p_request_key;
  if found then
    if v_existing.intake_id<>p_intake_id or v_existing.actor_id<>v_actor then raise exception 'PDC_735_REQUEUE_REPLAY_CONFLICT' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'code','email_requeue_replayed','receipt_id',v_existing.receipt_id,'intake_id',p_intake_id,'status',v_existing.after_status);
  end if;
  select * into v_row from public.ai_email_intake where id=p_intake_id for update;
  if not found or v_row.status<>'failed' or v_row.permanent_failure is not true
  then raise exception 'PDC_735_FAILED_PERMANENT_TARGET_REQUIRED' using errcode='55000'; end if;
  update public.ai_email_intake
  set status='received',permanent_failure=false,retry_class=null,next_attempt_at=clock_timestamp(),
      locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null,error_details=null,last_error_code=null
  where id=p_intake_id;
  insert into public.pdc_email_monitor_requeue_receipts_735(
    intake_id,target_kind,request_key,before_status,before_permanent_failure,after_status,actor_id,actor_email,reason)
  values(p_intake_id,v_target.target_kind,p_request_key,v_row.status,v_row.permanent_failure,'received',v_actor,v_email,btrim(p_reason))
  returning * into v_receipt;
  update public.pdc_email_monitor_status set updated_at=clock_timestamp() where singleton;
  insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  values('update','ai_email_intake',v_receipt.intake_id,v_actor,v_email,
    jsonb_build_object('id',p_intake_id,'status',v_row.status,'permanent_failure',v_row.permanent_failure),
    jsonb_build_object('id',p_intake_id,'status','received','permanent_failure',false),
    jsonb_build_object('contract','pdc_email_monitor_admin_requeue_735','receipt_id',v_receipt.receipt_id,'exact_target',true,'direct_dml',false));
  return jsonb_build_object('ok',true,'code','email_requeued','receipt_id',v_receipt.receipt_id,'intake_id',p_intake_id,'status','received');
end
$body$;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
 '20260829030000','737_email_monitor_requeue_receipt_table_binding_repair',array[
  'Bind the exact-ID audited requeue function to pdc_email_monitor_requeue_receipts_735',
  'Preserve Administrator custody, Monitor least privilege, immutable evidence and direct-DML denial'
 ]
);
notify pgrst,'reload schema';
commit;
