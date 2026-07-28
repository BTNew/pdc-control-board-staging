-- Staging-only migration 098: restore Control Board pipeline metrics and
-- let authorized staff explicitly move authenticated email/Navision vehicles
-- from Yard Hold/In Transit to PMB through a shared, audited mutation.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists (
       select 1 from supabase_migrations.schema_migrations where version='097'
     )
     or to_regclass('public.vehicles') is null
     or to_regclass('public.vehicle_movements') is null
     or to_regclass('public.workshop_stages') is null
     or to_regclass('public.workshop_bookings') is null
     or to_regclass('public.pdc_email_vehicle_revision') is null then
    raise exception 'PDC_MIGRATION_098_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create or replace function public.pmb_transfer_vehicle(
  p_vehicle_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $transfer$
declare
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_location text;
  v_now timestamptz:=clock_timestamp();
begin
  perform public.require_pdc_role('operator');
  if p_vehicle_id is null then
    return jsonb_build_object('ok',false,'error','invalid_vehicle');
  end if;

  select * into v_before from public.vehicles where id=p_vehicle_id for update;
  if not found then
    raise exception 'Vehicle not found' using errcode='P0002';
  end if;
  if p_expected_version is null then
    return jsonb_build_object('ok',false,'error','missing_expected_version');
  end if;
  if v_before.version<>p_expected_version then
    return jsonb_build_object('ok',false,'error','vehicle_version_conflict');
  end if;
  if v_before.lifecycle_state<>'active' or v_before.deleted_at is not null then
    return jsonb_build_object('ok',false,'error','not_in_active_lifecycle');
  end if;

  v_location:=upper(btrim(coalesce(v_before.current_location,'')));
  if v_location='PMB' then
    return jsonb_build_object('ok',true,'code','already_at_pmb','vehicle',to_jsonb(v_before));
  end if;
  if v_location not in ('YH','IT') then
    return jsonb_build_object('ok',false,'error','pmb_transfer_requires_yh_or_it');
  end if;

  update public.vehicles
  set current_location='PMB',
      visible_on_board=true,
      pmb_stage=null,
      pmb_bay_stage=null,
      pmb_bay_number=null,
      source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
        'manual_location_authority','PMB',
        'manual_location_updated_at',v_now,
        'manual_location_updated_by',public.current_actor_email()
      ),
      version=version+1,
      updated_by=auth.uid()
  where id=p_vehicle_id
  returning * into v_after;

  insert into public.vehicle_movements(
    vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,
    reason,moved_by
  ) values(
    p_vehicle_id,v_before.current_location,'PMB',v_before.pmb_stage,null,
    v_before.pmb_bay_stage,null,v_before.pmb_bay_number,null,
    'Explicit Vehicle Locations transfer to PMB Unallocated',auth.uid()
  );

  perform public.audit_pdc_event(
    'move','vehicles',p_vehicle_id,p_vehicle_id,
    to_jsonb(v_before),to_jsonb(v_after),
    jsonb_build_object('action','pmb_transfer_vehicle','from',v_before.current_location,'to','PMB')
  );

  update public.pdc_email_vehicle_revision
  set revision=revision+1,updated_at=v_now where singleton;
  if to_regclass('public.navision_backend_revision') is not null then
    update public.navision_backend_revision
    set revision=revision+1,updated_at=v_now where singleton;
  end if;

  return jsonb_build_object('ok',true,'code','transferred_to_pmb','vehicle',to_jsonb(v_after));
end;
$transfer$;

revoke all on function public.pmb_transfer_vehicle(uuid,integer) from public,anon;
grant execute on function public.pmb_transfer_vehicle(uuid,integer) to authenticated,service_role;
comment on function public.pmb_transfer_vehicle(uuid,integer) is
  'Operator-authorized, version-checked and audited explicit YH/IT to PMB transfer. PMB becomes operationally authoritative over later ordinary Navision location updates.';

create or replace function public.get_workshop_eligibility_snapshot()
returns jsonb
language plpgsql
stable security definer
set search_path=pg_catalog,public
as $snapshot$
declare
  v_now timestamptz:=now();
  v_month_start timestamptz:=date_trunc('month',now() at time zone 'Australia/Perth') at time zone 'Australia/Perth';
begin
  perform public.require_pdc_role('viewer');
  return jsonb_build_object(
    'generated_at',v_now,
    'semantics',jsonb_build_object(
      'count_label','Outstanding requirements',
      'candidate_authority','required canonical work item with completed=false; location PMB or IT with Kewdale ETA',
      'legacy_pmb_stage_authority',false,
      'pipeline_authority','canonical station eligibility plus authoritative workshop bookings'
    ),
    'stages',(select coalesce(jsonb_agg(jsonb_build_object(
      'code',s.code,'display_name',s.display_name,'work_key',s.work_key,
      'planner_enabled',s.planner_enabled,'revision',public.workshop_current_station_revision(s.code),
      'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb)
        from public.workshop_stage_aliases a where a.stage_code=s.code)
    ) order by s.sort_order),'[]'::jsonb)
      from public.workshop_stages s where s.active and s.planner_enabled),
    'candidates',(select coalesce(jsonb_agg(jsonb_build_object(
      'stage_code',e.stage_code,'work_key',e.work_key,
      'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,
      'vehicle',jsonb_build_object(
        'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
        'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
        'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'make',v.make,'model',v.model,
        'registration',v.registration,'current_location',v.current_location,'pmb_stage',v.pmb_stage,
        'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
        'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version),
      'work_items',(select coalesce(jsonb_agg(jsonb_build_object(
        'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
        'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
        from public.vehicle_work_items wi where wi.vehicle_id=v.id
          and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code)
    ) order by e.stage_code,v.stock_number,v.id),'[]'::jsonb)
      from public.workshop_stages s
      cross join lateral public.workshop_station_eligibility(s.code)e
      join public.vehicles v on v.id=e.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
      where s.code=e.stage_code and s.active and s.planner_enabled
        and upper(btrim(coalesce(v.current_location,''))) in ('PMB','IT')
        and (upper(btrim(coalesce(v.current_location,'')))='PMB' or v.eta_to_kewdale is not null)),
    'pipeline',(select coalesce(jsonb_agg(jsonb_build_object(
      'stage_code',s.code,
      'it',(select count(*) from public.workshop_station_eligibility(s.code)e
        join public.vehicles v on v.id=e.vehicle_id
        where v.lifecycle_state='active' and v.deleted_at is null
          and upper(btrim(coalesce(v.current_location,'')))='IT' and v.eta_to_kewdale is not null),
      'pmb_waiting',(select count(*) from public.workshop_station_eligibility(s.code)e
        join public.vehicles v on v.id=e.vehicle_id
        where v.lifecycle_state='active' and v.deleted_at is null
          and upper(btrim(coalesce(v.current_location,'')))='PMB'
          and not exists(
            select 1 from public.workshop_bookings b
            where b.vehicle_id=v.id and b.stage_id=s.id and b.deleted_at is null
              and b.status in ('started','stoppage'))),
      'in_bays',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='started' and b.bay_id is not null
          and v.lifecycle_state='active' and v.deleted_at is null),
      'average_bay_hours',(select coalesce(round(avg(greatest(0,
          extract(epoch from(v_now-coalesce(b.actual_start_at,b.scheduled_start_at)))/3600.0
          -coalesce(b.stoppage_accumulated_minutes,0)/60.0))::numeric,1),0)
        from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='started' and b.bay_id is not null
          and v.lifecycle_state='active' and v.deleted_at is null),
      'stoppage',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='stoppage'
          and v.lifecycle_state='active' and v.deleted_at is null),
      'completed_mtd',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='completed'
          and b.actual_end_at>=v_month_start and b.actual_end_at<=v_now and v.deleted_at is null)
    ) order by s.sort_order),'[]'::jsonb)
      from public.workshop_stages s where s.active and s.planner_enabled)
  );
end;
$snapshot$;

revoke all on function public.get_workshop_eligibility_snapshot() from public,anon;
grant execute on function public.get_workshop_eligibility_snapshot() to authenticated,service_role;
comment on function public.get_workshop_eligibility_snapshot() is
  'Viewer-readable canonical all-station candidates plus restored authoritative per-station pipeline metrics; mutations remain separately role-gated.';

commit;
