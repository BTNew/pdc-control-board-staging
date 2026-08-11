-- Staging-only Sublet calendar return and last-booking station completion.
begin;
set local lock_timeout='10s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-172',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='171' and name='release_safety_corrections')
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>171)
     or exists(select 1 from supabase_migrations.schema_migrations where version='172')
     or to_regprocedure('public.return_pdc_sublet_booking(uuid,bigint,timestamptz)') is null
     or to_regprocedure('public.workshop_stage_code_for_work_key(text)') is null
     or to_regprocedure('public.workshop_bump_revision()') is null then
    raise exception 'PDC_172_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;
end
$guard$;

alter function public.return_pdc_sublet_booking(uuid,bigint,timestamptz)
  rename to return_pdc_sublet_booking_pre172;

create function public.return_pdc_sublet_booking(
  p_booking_id uuid,
  p_expected_version bigint,
  p_returned_at timestamptz default clock_timestamp()
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $return$
declare
  v_actor uuid:=auth.uid();
  v_vehicle_id uuid;
  v_returned_at timestamptz:=coalesce(p_returned_at,clock_timestamp());
  v_result jsonb;
  v_active_count integer:=0;
  v_completed_count integer:=0;
  v_required_count integer:=0;
  v_workshop_revision bigint;
  v_item public.vehicle_work_items%rowtype;
  v_before jsonb;
  v_after jsonb;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if not public.pdc_sublet_actor_allowed() then
    return public.navision_backend_response(false,'unauthorized');
  end if;

  select vehicle_id into v_vehicle_id
  from public.pdc_sublet_booking_instances
  where booking_id=p_booking_id;
  if not found then return public.navision_backend_response(false,'booking_not_found'); end if;

  -- The predecessor takes the same per-vehicle advisory lock. Advisory xact locks
  -- are re-entrant for this transaction, so booking return and station completion
  -- have one serialization order with create/update/return/email Sublet actions.
  perform public.pdc_lock_canonical_sublet_vehicle(v_vehicle_id);
  v_result:=public.return_pdc_sublet_booking_pre172(p_booking_id,p_expected_version,v_returned_at);
  if not coalesce((v_result->>'ok')::boolean,false) then return v_result; end if;

  select count(*) into v_active_count
  from public.pdc_sublet_booking_instances
  where vehicle_id=v_vehicle_id and status='active';

  if v_active_count=0 then
    for v_item in
      select * from public.vehicle_work_items wi
      where wi.vehicle_id=v_vehicle_id and wi.required
        and public.workshop_stage_code_for_work_key(wi.work_key)='SUBLET'
      order by wi.id for update
    loop
      v_required_count:=v_required_count+1;
      if not v_item.completed then
        v_before:=to_jsonb(v_item);
        update public.vehicle_work_items
        set completed=true,completed_by=v_actor,completed_at=v_returned_at,updated_at=clock_timestamp()
        where id=v_item.id
        returning to_jsonb(vehicle_work_items.*) into v_after;
        insert into public.audit_events(action,table_name,row_id,vehicle_id,before_data,after_data,metadata)
        values('update','vehicle_work_items',v_item.id,v_vehicle_id,v_before,v_after,
          jsonb_build_object('source','sublet_calendar_return_172','booking_id',p_booking_id,'reason','last_active_sublet_returned'));
        v_completed_count:=v_completed_count+1;
      end if;
    end loop;
    if v_completed_count>0 then v_workshop_revision:=public.workshop_bump_revision(); end if;
  else
    select count(*) into v_required_count from public.vehicle_work_items wi
    where wi.vehicle_id=v_vehicle_id and wi.required
      and public.workshop_stage_code_for_work_key(wi.work_key)='SUBLET';
  end if;

  return v_result||jsonb_build_object('data',coalesce(v_result->'data','{}'::jsonb)||jsonb_build_object(
    'remaining_active_sublets',v_active_count,
    'sublet_station_required',v_required_count>0,
    'sublet_station_completed',v_active_count=0 and v_required_count>0,
    'station_work_items_completed',v_completed_count,
    'workshop_revision',v_workshop_revision
  ));
end
$return$;

revoke all on function public.return_pdc_sublet_booking_pre172(uuid,bigint,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.return_pdc_sublet_booking(uuid,bigint,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.return_pdc_sublet_booking(uuid,bigint,timestamptz) to authenticated;

do $post$
begin
  if has_function_privilege('anon','public.return_pdc_sublet_booking(uuid,bigint,timestamptz)','EXECUTE')
     or has_function_privilege('service_role','public.return_pdc_sublet_booking(uuid,bigint,timestamptz)','EXECUTE')
     or has_function_privilege('authenticated','public.return_pdc_sublet_booking_pre172(uuid,bigint,timestamptz)','EXECUTE') then
    raise exception 'PDC_172_RETURN_RPC_ACL_INVALID' using errcode='42501';
  end if;
end
$post$;

insert into supabase_migrations.schema_migrations(version,name,statements) values('172','sublet_calendar_return_station_completion',array[
  'return checkbox uses canonical versioned Sublet return authority',
  'complete required Sublet work only after the final active canonical booking returns',
  'retain immutable booking history and audited station completion'
]);
notify pgrst,'reload schema';
commit;
