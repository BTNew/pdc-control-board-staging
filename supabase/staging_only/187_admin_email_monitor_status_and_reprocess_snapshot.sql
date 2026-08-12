-- Staging-only: Administrator monitor dashboard snapshot and Realtime revision publication.
begin;
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='186') or exists(select 1 from supabase_migrations.schema_migrations where version='187') then raise exception 'PDC_187_GUARD_MISMATCH';end if;end $guard$;
create or replace function public.get_pdc_email_monitor_admin_snapshot(p_failed_limit integer default 25)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_status jsonb;v_failed jsonb;
begin
 perform public.require_pdc_role('administrator');
 if p_failed_limit not between 1 and 100 then raise exception 'pdc_monitor_failed_limit_invalid' using errcode='22023';end if;
 v_status:=public.get_pdc_email_monitor_status();
 select coalesce(jsonb_agg(to_jsonb(x) order by x.received_at desc nulls last,x.created_at desc),'[]'::jsonb) into v_failed from(
  select id,subject,sender_email,received_at,queue_attempts,permanent_failure,retry_class,next_attempt_at,last_error_code,error_details,provider_uid,revision_summary,created_at
  from public.ai_email_intake where status='failed' order by received_at desc nulls last,created_at desc limit p_failed_limit
 )x;
 return v_status||jsonb_build_object('failed_items',v_failed);
end $$;
revoke all on function public.get_pdc_email_monitor_admin_snapshot(integer) from public,anon,authenticated,service_role;grant execute on function public.get_pdc_email_monitor_admin_snapshot(integer) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('187','admin_email_monitor_status_and_reprocess_snapshot',array['Administrator-only monitor status and failed-intake snapshot for the AI Intake page','Existing controlled reprocess RPC remains the only UI retry mutation']);commit;
