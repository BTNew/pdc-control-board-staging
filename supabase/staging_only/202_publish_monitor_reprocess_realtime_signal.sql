-- Staging-only: publish Administrator Reprocess through the existing monitor-status Realtime row.
begin;
set local lock_timeout='5s';set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-202-reprocess-monitor-signal',0));
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='201') or exists(select 1 from supabase_migrations.schema_migrations where version='202') then raise exception 'PDC_202_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';end if;end $guard$;
create or replace function public.reprocess_pdc_failed_email(p_intake_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_before public.ai_email_intake%rowtype;begin
 perform public.require_pdc_role('administrator');
 select * into v_before from public.ai_email_intake where id=p_intake_id and status='failed' for update;
 if not found then raise exception 'failed_email_not_found' using errcode='P0002';end if;
 update public.ai_email_intake set status='received',permanent_failure=false,retry_class=null,next_attempt_at=clock_timestamp(),locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null,error_details=null,last_error_code=null where id=p_intake_id;
 update public.pdc_email_monitor_status set updated_at=clock_timestamp() where singleton;
 insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata) values('update','ai_email_intake',auth.uid(),public.current_actor_email(),to_jsonb(v_before),jsonb_build_object('id',p_intake_id,'status','received'),jsonb_build_object('source','administrator_monitor_reprocess','scoped_rpc',true,'monitor_status_signalled',true));
 return jsonb_build_object('ok',true,'code','email_requeued','intake_id',p_intake_id);
end $$;
revoke all on function public.reprocess_pdc_failed_email(uuid) from public,anon,authenticated,service_role;
grant execute on function public.reprocess_pdc_failed_email(uuid) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('202','publish_monitor_reprocess_realtime_signal',array['Require exact Administrator role and retain the failed row before controlled requeue','Advance the existing monitor-status Realtime row atomically with Reprocess','Preserve scoped authenticated RPC access and immutable source evidence']);
commit;
