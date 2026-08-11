begin;
set local lock_timeout='10s';set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-155-navision-purge-order',0));
do $guard$ begin
 if not public.pdc_monitor_staging_guard() or to_regprocedure('public.purge_vehicle_from_board(uuid,integer,text)') is null
  or not exists(select 1 from supabase_migrations.schema_migrations where version='154' and name='monitor_updates_and_complete_board_purge') then
  raise exception 'PDC_MIGRATION_155_STAGING_OR_DEPENDENCY_MISMATCH';
 end if;
 if exists(select 1 from public.audit_events where action='insert' and metadata->>'source'='staging_migration_155') then
  raise exception 'PDC_MIGRATION_155_ALREADY_APPLIED';
 end if;
end $guard$;
alter function public.purge_vehicle_from_board(uuid,integer,text) rename to purge_vehicle_from_board_pre155;
revoke all on function public.purge_vehicle_from_board_pre155(uuid,integer,text) from public,anon,authenticated,service_role;
create function public.purge_vehicle_from_board(p_vehicle_id uuid,p_expected_version integer,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $purge$
declare v_result jsonb;v_deactivated integer:=0;
begin
 v_result:=public.purge_vehicle_from_board_pre155(p_vehicle_id,p_expected_version,p_reason);
 if coalesce((v_result->>'ok')::boolean,false) then
  -- The retained Navision reconcile trigger sees the vehicle tombstone first and therefore
  -- preserves this deactivation instead of immediately reactivating a live vehicle.
  update public.navision_board_activations set active=false,completed_at=coalesce(completed_at,clock_timestamp()),
    completion_reason=coalesce(completion_reason,'Staging board purge'),updated_at=clock_timestamp()
  where canonical_vehicle_id=p_vehicle_id and active;
  get diagnostics v_deactivated=row_count;
  v_result:=jsonb_set(v_result,'{data,navision_activations_deactivated}',to_jsonb(v_deactivated),true);
 end if;
 return v_result;
end
$purge$;
revoke all on function public.purge_vehicle_from_board(uuid,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.purge_vehicle_from_board(uuid,integer,text) to authenticated;
do $verify$ declare d text;begin
 select pg_get_functiondef('public.purge_vehicle_from_board(uuid,integer,text)'::regprocedure) into d;
 if position('purge_vehicle_from_board_pre155' in d)=0 or position('where canonical_vehicle_id=p_vehicle_id and active' in d)=0
  or has_function_privilege('service_role','public.purge_vehicle_from_board(uuid,integer,text)','EXECUTE')
  or not has_function_privilege('authenticated','public.purge_vehicle_from_board(uuid,integer,text)','EXECUTE') then
  raise exception 'PDC_MIGRATION_155_POSTCONDITION_FAILED';
 end if;
 insert into supabase_migrations.schema_migrations(version,name,statements) values('155','navision_activation_board_purge_order',array['deactivate Navision activation after vehicle tombstone authority']);
 insert into public.audit_events(vehicle_id,action,actor_id,actor_email,before_data,after_data,metadata)
 values(null,'insert',auth.uid(),public.current_actor_email(),null,jsonb_build_object('migration','155_navision_purge_order'),jsonb_build_object('source','staging_migration_155','environment','staging','production_unchanged',true,'reason','Deactivate Navision activation only after the vehicle tombstone is authoritative'));
end $verify$;
commit;
