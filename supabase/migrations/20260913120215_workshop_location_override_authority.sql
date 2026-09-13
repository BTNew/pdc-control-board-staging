-- STAGING ONLY: workshop eligibility and booking rules use the displayed manual location override.
-- The source/Navision location and protected lifecycle history remain unchanged.
-- ETA risk updates only warning/audit fields; existing booking positions are preserved.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 IF md5(pg_get_functiondef('public.workshop_enforce_vehicle_eta()'::regprocedure))<>'0672c2e60bb6022a8bb1d5f6dabfe9f0' THEN RAISE EXCEPTION 'Reviewed function changed: workshop_enforce_vehicle_eta'; END IF;
 IF md5(pg_get_functiondef('public.workshop_refresh_eta_risk()'::regprocedure))<>'4ccf5c849cae870e44285b6ea22b5f75' THEN RAISE EXCEPTION 'Reviewed function changed: workshop_refresh_eta_risk'; END IF;
 IF md5(pg_get_functiondef('public.workshop_validate_booking(uuid, uuid, uuid, uuid, timestamp with time zone, timestamp with time zone, integer, workshop_booking_status, uuid, boolean)'::regprocedure))<>'d69305c74160a7e8ca1eedc061d426f5' THEN RAISE EXCEPTION 'Reviewed function changed: workshop_validate_booking'; END IF;
 IF md5(pg_get_functiondef('public.get_station_workshop_snapshot_pre_170(text, date, date)'::regprocedure))<>'63a235672ff8ba8939ffce2217b65a3c' THEN RAISE EXCEPTION 'Reviewed function changed: get_station_workshop_snapshot_pre_170'; END IF;
 IF md5(pg_get_functiondef('public.get_workshop_eligibility_snapshot()'::regprocedure))<>'0ceebad9d794863253c10f963e5e5fa8' THEN RAISE EXCEPTION 'Reviewed function changed: get_workshop_eligibility_snapshot'; END IF;
 IF md5(pg_get_functiondef('public.workshop_require_booking_restore_eligibility(uuid)'::regprocedure))<>'1b55edb45bc861623664a0ec92662e19' THEN RAISE EXCEPTION 'Reviewed function changed: workshop_require_booking_restore_eligibility'; END IF;
 IF md5(pg_get_functiondef('public.book_all_vehicle_stations(uuid, integer)'::regprocedure))<>'7aeccd21fd0e7e5089182ab9cde9a697' THEN RAISE EXCEPTION 'Reviewed function changed: book_all_vehicle_stations'; END IF;
 IF md5(pg_get_functiondef('public.workshop_station_eligibility(text)'::regprocedure))<>'8a4c1ed0b8dbcd0055a7d0f6b348634f' THEN RAISE EXCEPTION 'Reviewed function changed: workshop_station_eligibility'; END IF;
 IF md5(pg_get_functiondef('public.workshop_prevent_disabled_planner_booking_mutation()'::regprocedure))<>'3ac5e54f5022178f45d9dceb8a0f072a' THEN RAISE EXCEPTION 'Reviewed function changed: workshop_prevent_disabled_planner_booking_mutation'; END IF;
END $guard$;
DO $eta_trigger_guard$ BEGIN
 IF (SELECT md5(pg_get_triggerdef(oid)) FROM pg_trigger
     WHERE tgrelid='public.vehicles'::regclass AND tgname='vehicles_refresh_workshop_eta_risk')
     IS DISTINCT FROM 'b0b35b810ddf10da3b017d9fa225bd58'
 THEN RAISE EXCEPTION 'Reviewed ETA risk trigger changed'; END IF;
END $eta_trigger_guard$;
DROP TRIGGER vehicles_refresh_workshop_eta_risk ON public.vehicles;
CREATE TRIGGER vehicles_refresh_workshop_eta_risk
 AFTER UPDATE OF eta_to_kewdale,current_location,location_override ON public.vehicles
 FOR EACH ROW EXECUTE FUNCTION public.workshop_refresh_eta_risk();
CREATE OR REPLACE FUNCTION public.workshop_enforce_vehicle_eta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare v_vehicle public.vehicles%rowtype; v_location text;
begin
 select * into v_vehicle from public.vehicles where id=new.vehicle_id;
 v_location:=public.workshop_location_code(coalesce(nullif(v_vehicle.location_override,''),v_vehicle.current_location));
 if v_location='IT' then
  if v_vehicle.eta_to_kewdale is null then raise exception 'missing_or_invalid_eta' using errcode='23514'; end if;
  if (new.scheduled_start_at at time zone 'Australia/Perth')::date<v_vehicle.eta_to_kewdale+7 then
   raise exception 'booking_before_eta_plus_seven earliest_permitted_date=%',v_vehicle.eta_to_kewdale+7 using errcode='23514';
  end if;
  new.eta_at_booking:=v_vehicle.eta_to_kewdale; new.eta_risk_status:='none'; new.eta_risk_detected_at:=null;
 else
  new.eta_at_booking:=null; new.eta_risk_status:='none'; new.eta_risk_detected_at:=null;
 end if;
 return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.workshop_refresh_eta_risk()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
 v_booking public.workshop_bookings%rowtype;
 v_after jsonb;
 v_new_status text;
 v_actor uuid := coalesce(auth.uid(), new.updated_by, old.updated_by);
begin
 if new.eta_to_kewdale is distinct from old.eta_to_kewdale
   or public.workshop_location_code(coalesce(nullif(new.location_override,''),new.current_location))
      is distinct from public.workshop_location_code(coalesce(nullif(old.location_override,''),old.current_location)) then
  for v_booking in
   select b.* from public.workshop_bookings b
   where b.vehicle_id=new.id and b.status='planned' and b.deleted_at is null
   for update
  loop
   v_new_status:=case when public.workshop_location_code(coalesce(nullif(new.location_override,''),new.current_location))<>'IT' then 'none' when new.eta_to_kewdale is null or (v_booking.scheduled_start_at at time zone 'Australia/Perth')::date<new.eta_to_kewdale+7 then 'at_risk' else 'none' end;
   if v_booking.eta_risk_status is distinct from v_new_status then
    update public.workshop_bookings b
    set eta_risk_status=v_new_status,
        eta_risk_detected_at=case when v_new_status='at_risk' then coalesce(b.eta_risk_detected_at,now()) else null end,
        version=b.version+1,
        updated_by=coalesce(v_actor,b.updated_by)
    where b.id=v_booking.id
    returning to_jsonb(b.*) into v_after;
    if v_actor is not null then
     insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
     values(v_booking.id,'eta_risk_changed',to_jsonb(v_booking),v_after,
       jsonb_build_object('vehicle_id',new.id,'previous_eta',old.eta_to_kewdale,'current_eta',new.eta_to_kewdale),
       v_actor,public.current_actor_email());
    end if;
   end if;
  end loop;
 end if;
 return new;
end; $function$
;

CREATE OR REPLACE FUNCTION public.workshop_validate_booking(p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_scheduled_start_at timestamp with time zone, p_scheduled_end_at timestamp with time zone, p_duration_minutes integer, p_status workshop_booking_status, p_technician_id uuid, p_allow_unchanged_past boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_vehicle public.vehicles%rowtype;
  v_stage public.workshop_stages%rowtype;
  v_bay public.workshop_bays%rowtype;
  v_conflict uuid;
  v_local_date date := (p_scheduled_start_at at time zone 'Australia/Perth')::date;
  v_active boolean := p_status in ('queued','planned','started','stoppage'); v_estimated_duration integer; v_candidate_end timestamptz; v_registered_synthetic boolean := false;
begin
  if not v_active then return jsonb_build_object('ok',true); end if;
  v_registered_synthetic:=exists(
    select 1
    from public.pdc_overnight_synthetic_fleet_registry_363 r
    join public.vehicles x on x.id=p_vehicle_id
     and r.run_id='HERMES-TEST-RUN-20260824'
     and r.vehicle_id=x.id
     and x.stock_number=r.stock_number
     and x.customer_name=r.customer_name
     and x.job_card_number=r.job_card_number
     and x.vehicle_description=r.vehicle_description
     and x.source_system='hermes_overnight_synthetic'
     and x.source_batch_id=r.run_id
     and x.source_record_id=r.stock_number
     and x.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
  );
  if p_duration_minutes is null or p_duration_minutes<1 then
    return jsonb_build_object('ok',false,'error','minimum_duration','minimum_minutes',1);
  end if;
  if p_scheduled_start_at is null or p_scheduled_end_at is null or p_scheduled_end_at<=p_scheduled_start_at
     or date_trunc('minute',p_scheduled_start_at)<>p_scheduled_start_at
     or date_trunc('minute',p_scheduled_end_at)<>p_scheduled_end_at then
    return jsonb_build_object('ok',false,'error','invalid_schedule_interval');
  end if;
  if not p_allow_unchanged_past
     and p_status in ('queued','planned')
     and p_scheduled_start_at < date_trunc('minute',statement_timestamp()) then
    return jsonb_build_object('ok',false,'error','past_start');
  end if;
  if not public.workshop_calendar_minute_available(p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','calendar_unavailable');
  end if;
  if public.workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at)<>p_duration_minutes then
    return jsonb_build_object('ok',false,'error','calendar_duration_mismatch');
  end if;
  select * into v_vehicle from public.vehicles where id=p_vehicle_id and deleted_at is null and lifecycle_state='active';
  if not found then return jsonb_build_object('ok',false,'error','vehicle_inactive_or_missing'); end if;
  if exists(select 1 from public.pdc_new_vehicle_reviews r where r.vehicle_id=p_vehicle_id and r.status='pending') then return jsonb_build_object('ok',false,'error','new_vehicle_review_required'); end if;
  select * into v_stage from public.workshop_stages where id=p_stage_id and active and planner_enabled;
  if not found then return jsonb_build_object('ok',false,'error','station_inactive_or_missing'); end if; v_estimated_duration:=public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,p_stage_id); v_candidate_end:=case when v_estimated_duration is not null then public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) else p_scheduled_end_at end; if p_status in ('queued','planned') and v_estimated_duration is not null and p_duration_minutes<>v_estimated_duration and not v_registered_synthetic then return jsonb_build_object('ok',false,'error','operation_estimate_duration_mismatch','expected_minutes',v_estimated_duration); end if;
  if public.workshop_location_code(coalesce(nullif(v_vehicle.location_override,''),v_vehicle.current_location)) not in ('PMB','YH','IT') then
    return jsonb_build_object('ok',false,'error','location_ineligible');
  end if;
  if public.workshop_location_code(coalesce(nullif(v_vehicle.location_override,''),v_vehicle.current_location))='IT' then
    if v_vehicle.eta_to_kewdale is null then return jsonb_build_object('ok',false,'error','it_eta_missing'); end if;
    if v_local_date<v_vehicle.eta_to_kewdale+7 then return jsonb_build_object('ok',false,'error','it_before_eta_plus_seven','earliest_permitted_date',v_vehicle.eta_to_kewdale+7); end if;
  end if;
  if not exists(
    select 1 from public.vehicle_work_items wi
    where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
      and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage.code
  ) then return jsonb_build_object('ok',false,'error','canonical_requirement_missing_or_completed'); end if;
  if p_status<>'queued' then
    if p_bay_id is null then return jsonb_build_object('ok',false,'error','bay_required'); end if;
    select * into v_bay from public.workshop_bays where id=p_bay_id and stage_id=p_stage_id and is_active;
    if not found then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
  end if;
  if p_bay_id is not null then
    select b.id into v_conflict from public.workshop_bookings b
    where b.id is distinct from p_booking_id and b.deleted_at is null
      and b.status in ('planned','started','stoppage') and b.bay_id=p_bay_id
      and tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
    order by b.scheduled_start_at,b.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','bay_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  select b.id into v_conflict from public.workshop_bookings b
  where b.id is distinct from p_booking_id and b.deleted_at is null
    and b.status in ('queued','planned','started','stoppage') and b.vehicle_id=p_vehicle_id
    and tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
  order by b.scheduled_start_at,b.id limit 1;
  if v_conflict is not null then return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_conflict); end if;
  if p_technician_id is not null then
    if not exists(select 1 from public.workshop_technicians t where t.id=p_technician_id and t.active) then
      return jsonb_build_object('ok',false,'error','technician_inactive_or_missing');
    end if;
    if public.workshop_technician_leave_date(p_technician_id,p_scheduled_start_at,v_candidate_end) is not null then
      return jsonb_build_object('ok',false,'error','technician_leave_conflict');
    end if;
    select a.booking_id into v_conflict from public.workshop_booking_assignments a
    where a.booking_id is distinct from p_booking_id and a.technician_id=p_technician_id and a.released_at is null
      and tstzrange(a.scheduled_start_at,public.workshop_booking_effective_end_at(a.booking_id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
    order by a.scheduled_start_at,a.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','technician_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  return jsonb_build_object('ok',true);
end $function$
;

CREATE OR REPLACE FUNCTION public.get_station_workshop_snapshot_pre_170(p_stage_code text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_result jsonb;
begin
  perform public.require_pdc_role('viewer');
  v_stage:=public.workshop_canonical_stage_code(p_stage_code);
  select id into v_stage_id from public.workshop_stages where code=v_stage and active and planner_enabled;
  if v_stage_id is null then raise exception 'Unknown, inactive or planner-disabled workshop station' using errcode='22023'; end if;
  if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to>p_date_from+31 then raise exception 'Invalid station planner date range' using errcode='22023'; end if;
  v_from:=p_date_from::timestamp at time zone 'Australia/Perth';
  v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';

  with
  station as materialized(
    select s.id,s.code,s.display_name,s.is_physical,s.work_key
    from public.workshop_stages s where s.id=v_stage_id
  ),
  eligibility as materialized(
    select * from public.workshop_station_eligibility(v_stage)
  ),
  booking_seed as materialized(
    select b.*
    from public.workshop_bookings b
    join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
    where b.stage_id=v_stage_id and b.deleted_at is null
      and b.status in('queued','planned','started','stoppage','completed')
      and (
        (b.status in('queued','planned') and b.scheduled_start_at<v_to)
        or (b.status in('started','stoppage') and b.scheduled_start_at<v_to)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to)
      )
  ),
  candidate_ids as materialized(
    select vehicle_id from eligibility union select vehicle_id from booking_seed
  ),
  effective_source_lines as materialized(
    select ol.vehicle_id,
      public.workshop_canonical_stage_code(coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key))) stage_code,
      coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours
    from public.pdc_authenticated_email_operation_lines ol
    join public.pdc_authenticated_email_import_receipts r on r.receipt_id=ol.import_receipt_id
    join candidate_ids i on i.vehicle_id=ol.vehicle_id
    left join public.vehicle_workshop_line_adjustments a
      on a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text and a.active
    union all
    select a.vehicle_id,public.workshop_canonical_stage_code(a.stage_code),a.estimated_hours
    from public.vehicle_workshop_line_adjustments a join candidate_ids i on i.vehicle_id=a.vehicle_id
    where a.active and a.source_kind='manual'
  ),
  hours as materialized(
    select vehicle_id,nullif(round(sum(estimated_hours)::numeric,2),0) estimated_hours
    from effective_source_lines where stage_code=v_stage and estimated_hours>0 group by vehicle_id
  ),
  booking_duration as materialized(
    select b.*,case when b.status in('queued','planned','started','stoppage')
      then coalesce(greatest(60,round(h.estimated_hours*60)::integer),b.default_duration_minutes)
      else b.default_duration_minutes end effective_duration
    from booking_seed b left join hours h on h.vehicle_id=b.vehicle_id
  ),
  selected_bookings as materialized(
    select b.*,case when b.status in('queued','planned','started','stoppage')
      then public.workshop_add_operational_minutes(b.scheduled_start_at,b.effective_duration)
      else b.scheduled_end_at end effective_end
    from booking_duration b
  ),
  selected_filtered as materialized(
    select * from selected_bookings b where
      (b.status in('queued','planned') and b.scheduled_end_at>v_from)
      or b.status in('started','stoppage')
      or b.status='completed'
  ),
  selected_ids as materialized(
    select vehicle_id from eligibility union select vehicle_id from selected_filtered
  ),
  assignments as materialized(
    select distinct on(a.booking_id) a.booking_id,a.technician_id,t.name technician_name,a.assignment_type
    from public.workshop_booking_assignments a join public.workshop_technicians t on t.id=a.technician_id
    join selected_filtered b on b.id=a.booking_id
    where a.released_at is null
    order by a.booking_id,case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc
  ),
  requirement_rows as materialized(
    select wi.vehicle_id,jsonb_agg(jsonb_build_object(
      'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
      'completed',wi.completed,'completed_at',wi.completed_at
    ) order by wi.work_key) requirements
    from public.vehicle_work_items wi join selected_ids i on i.vehicle_id=wi.vehicle_id
    where wi.required and not wi.completed group by wi.vehicle_id
  ),
  stage_work_items as materialized(
    select wi.* from public.vehicle_work_items wi join selected_ids i on i.vehicle_id=wi.vehicle_id
    where public.workshop_stage_code_for_work_key(wi.work_key)=v_stage
  )
  select jsonb_build_object(
    'revision',public.workshop_current_station_revision(v_stage),'generated_at',now(),
    'semantics',jsonb_build_object(
      'outstanding_candidates','required canonical work items not completed and location-visible',
      'unscheduled_candidates','outstanding candidates without any active booking',
      'selected_date_bookings','scheduled rows intersecting the date plus started or stopped work carried forward until resolved'),
    'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
    'counts',jsonb_build_object(
      'outstanding_candidates',(select count(*) from eligibility),
      'unscheduled_candidates',(select count(*) from eligibility where not existing_booking),
      'selected_date_bookings',(select count(*) from selected_filtered)),
    'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key)) from station s),
    'bays',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',b.bay_number,'code',b.code,'display_name',b.display_name) order by b.bay_number),'[]'::jsonb) from public.workshop_bays b where b.stage_id=v_stage_id and b.is_active),
    'outstanding_candidates',(select coalesce(jsonb_agg(jsonb_build_object(
      'vehicle_id',e.vehicle_id,'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,
      'disabled_reason',e.disabled_reason,'estimated_hours',h.estimated_hours,
      'requirements',coalesce(rr.requirements,'[]'::jsonb)) order by e.vehicle_id),'[]'::jsonb)
      from eligibility e left join hours h on h.vehicle_id=e.vehicle_id left join requirement_rows rr on rr.vehicle_id=e.vehicle_id),
    'bookings',(select coalesce(jsonb_agg(jsonb_build_object(
      'booking_id',b.id,'vehicle_id',b.vehicle_id,
      'stage',jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key),
      'bay',case when bay.id is null then null else jsonb_build_object('id',bay.id,'bay_number',bay.bay_number,'code',bay.code,'display_name',bay.display_name) end,
      'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.effective_end,
      'default_duration_minutes',b.effective_duration,
      'estimated_operation_hours',case when b.status in('queued','planned','started','stoppage') then h.estimated_hours else null end,
      'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
      'stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
      'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,'version',b.version,
      'assignment',case when aa.technician_id is null then null else jsonb_build_object('technician_id',aa.technician_id,'technician_name',aa.technician_name,'assignment_type',aa.assignment_type) end
    ) order by b.scheduled_start_at,b.id),'[]'::jsonb)
      from selected_filtered b join station s on true left join public.workshop_bays bay on bay.id=b.bay_id
      left join hours h on h.vehicle_id=b.vehicle_id left join assignments aa on aa.booking_id=b.id),
    'vehicles',(select coalesce(jsonb_agg(jsonb_build_object(
      'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
      'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
      'customer_name',v.customer_name,'make',v.make,'model',v.model,'registration',v.registration,
      'current_location',coalesce(nullif(v.location_override,''),v.current_location),
      'automatic_location',v.current_location,'location_override',v.location_override,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,
      'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
      'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,
      'version',v.version,'workshop_estimated_hours_by_stage',jsonb_build_object(v_stage,h.estimated_hours)
    ) order by v.stock_number nulls last,v.id),'[]'::jsonb)
      from public.vehicles v join selected_ids i on i.vehicle_id=v.id left join hours h on h.vehicle_id=v.id
      where v.lifecycle_state='active' and v.deleted_at is null),
    'work_items',(select coalesce(jsonb_agg(jsonb_build_object(
      'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
      'completed',wi.completed,'completed_at',wi.completed_at
    ) order by wi.vehicle_id,wi.work_key),'[]'::jsonb) from stage_work_items wi)
  ) into v_result;
  return v_result;
end $function$
;

CREATE OR REPLACE FUNCTION public.get_workshop_eligibility_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_now timestamptz:=now();
  v_month_start timestamptz:=date_trunc('month',now() at time zone 'Australia/Perth') at time zone 'Australia/Perth';
begin
  perform public.require_pdc_role('viewer');
  return (WITH eligibility AS MATERIALIZED (
    SELECT e.* FROM public.workshop_stages s
    CROSS JOIN LATERAL public.workshop_station_eligibility(s.code) e
    WHERE s.active AND s.planner_enabled AND s.code=e.stage_code
  ) SELECT jsonb_build_object(
    'generated_at',v_now,
    'semantics',jsonb_build_object(
      'count_label','Outstanding requirements',
      'candidate_authority','required canonical work item with completed=false; PMB or Yard Hold, or IT with Kewdale ETA',
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
        'registration',v.registration,'current_location',coalesce(nullif(v.location_override,''),v.current_location),
      'automatic_location',v.current_location,'location_override',v.location_override,'pmb_stage',v.pmb_stage,
        'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
        'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version),
      'work_items',(select coalesce(jsonb_agg(jsonb_build_object(
        'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
        'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
        from public.vehicle_work_items wi where wi.vehicle_id=v.id
          and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code)
    ) order by e.stage_code,v.stock_number,v.id),'[]'::jsonb)
      from public.workshop_stages s
      join eligibility e on e.stage_code=s.code
      join public.vehicles v on v.id=e.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
      where s.code=e.stage_code and s.active and s.planner_enabled),
    'pipeline',(select coalesce(jsonb_agg(jsonb_build_object(
      'stage_code',s.code,
      'it',(select count(*) from eligibility e
        join public.vehicles v on v.id=e.vehicle_id
        where e.stage_code=s.code and e.current_location='IT'),
      'pmb_waiting',(select count(*) from eligibility e
        join public.vehicles v on v.id=e.vehicle_id
        where e.stage_code=s.code and e.current_location='PMB'
          and not exists(
            select 1 from public.workshop_bookings b
            where b.vehicle_id=v.id and b.stage_id=s.id and b.deleted_at is null
              and b.status in ('started','stoppage'))),
      'yard_hold_waiting',(select count(*) from eligibility e
        where e.stage_code=s.code and e.current_location='YH'
          and not exists(select 1 from public.workshop_bookings b
            where b.vehicle_id=e.vehicle_id and b.stage_id=s.id and b.deleted_at is null
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
  ));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.workshop_require_booking_restore_eligibility(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_vehicle_id uuid; v_stage_code text; v_location text; v_eta date;
begin
 select b.vehicle_id,s.code,public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)),v.eta_to_kewdale
  into v_vehicle_id,v_stage_code,v_location,v_eta
 from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id
 join public.workshop_stages s on s.id=b.stage_id
 where b.id=p_booking_id and b.deleted_at is not null
  and v.lifecycle_state='active' and v.deleted_at is null and s.active and s.planner_enabled;
 if not found then
  raise exception 'Deleted booking, active vehicle and enabled planner station are required for restore' using errcode='22023';
 end if;
 if not (v_location in('PMB','YH') or (v_location='IT' and v_eta is not null)) then
  raise exception 'Vehicle location is not eligible for Workshop Planner restore' using errcode='22023';
 end if;
 if not exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=v_vehicle_id
  and wi.required and not wi.completed and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage_code) then
  raise exception 'Outstanding station requirement is required for Workshop Planner restore' using errcode='22023';
 end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.book_all_vehicle_stations(p_vehicle_id uuid, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v public.vehicles%rowtype; st record; bay record; item jsonb; result jsonb;
 pending jsonb:='[]'; booked jsonb:='[]'; skipped jsonb:='[]';
 minutes integer; increment integer; current_version integer;
 earliest timestamptz; horizon timestamptz; candidate timestamptz; finish timestamptz;
 blocked_until timestamptz; away_date date; best_start timestamptz; best_end timestamptz; best_bay integer;
 failure text; failure_code text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'This action is available on staging only.'; END IF;
 PERFORM public.workshop_require_planner_operator();
 PERFORM public.workshop_require_version(p_expected_version);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state<>'active' OR NOT v.visible_on_board THEN
  RAISE EXCEPTION 'This vehicle is not available for workshop booking.' USING DETAIL='vehicle_inactive_or_missing';
 END IF;
 IF v.version<>p_expected_version THEN RAISE EXCEPTION 'This vehicle changed. Refresh and try again.' USING DETAIL='vehicle_version_conflict'; END IF;
 IF public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) NOT IN('PMB','YH','IT') OR coalesce(nullif(v.location_override,''),v.current_location) IS NULL THEN
  RAISE EXCEPTION 'Workshop booking requires PMB, Yard Hold or In Transit with an ETA.' USING DETAIL='location_ineligible';
 END IF;
 IF public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))='IT' AND v.eta_to_kewdale IS NULL THEN
  RAISE EXCEPTION 'Enter an ETA to Kewdale before booking this vehicle.' USING DETAIL='it_eta_missing';
 END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='pending') THEN
  RAISE EXCEPTION 'Approve the New Vehicles review before booking.' USING DETAIL='new_vehicle_review_required';
 END IF;
 -- Preflight every requirement before making any booking.
 FOR st IN SELECT s.* FROM public.workshop_stages s
  WHERE s.active AND s.planner_enabled AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET'
   AND EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND wi.required AND NOT wi.completed AND public.workshop_stage_code_for_work_key(wi.work_key)=s.code)
  ORDER BY s.sort_order,s.code
 LOOP
  IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.stage_id=st.id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.bay_id IS NULL) THEN
   RAISE EXCEPTION '% has an existing booking without a bay. Allocate or cancel that booking first.',st.display_name USING DETAIL='existing_booking_without_bay';
  END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.stage_id=st.id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')) THEN
   skipped:=skipped||jsonb_build_array(jsonb_build_object('stage',st.display_name,'reason','Already booked')); CONTINUE;
  END IF;
  minutes:=public.workshop_vehicle_stage_estimated_duration_minutes(v.id,st.id);
  IF minutes IS NULL OR minutes<1 THEN RAISE EXCEPTION 'Confirm the hours for % before booking all stations.',st.display_name USING DETAIL='estimated_duration_missing'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.workshop_bays b WHERE b.stage_id=st.id AND b.is_active) THEN RAISE EXCEPTION 'No active bay is configured for %.',st.display_name USING DETAIL='no_active_bay'; END IF;
  pending:=pending||jsonb_build_array(jsonb_build_object('id',st.id,'code',st.code,'name',st.display_name,'minutes',minutes));
 END LOOP;
 IF jsonb_array_length(pending)=0 THEN RETURN jsonb_build_object('ok',true,'bookings',booked,'skipped',skipped,'message','No unbooked workshop stations remain.'); END IF;
 SELECT greatest(1,coalesce((value#>>'{}')::integer,15)) INTO increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
 increment:=coalesce(increment,15);
 earliest:=date_trunc('minute',clock_timestamp())+interval '1 minute';
 IF public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))='IT' THEN earliest:=greatest(earliest,(v.eta_to_kewdale+7)::timestamp AT TIME ZONE 'Australia/Perth'); END IF;
 horizon:=earliest+interval '300 days';
 FOR item IN SELECT value FROM jsonb_array_elements(pending) LOOP
  minutes:=(item->>'minutes')::integer; best_start:=NULL; best_end:=NULL; best_bay:=NULL;
  FOR bay IN SELECT * FROM public.workshop_bays WHERE stage_id=(item->>'id')::uuid AND is_active ORDER BY bay_number LOOP
   candidate:=to_timestamp(ceil(extract(epoch FROM earliest)/(increment*60))*(increment*60));
   WHILE candidate<horizon AND (best_start IS NULL OR candidate<best_start) LOOP
    IF NOT public.workshop_calendar_minute_available(candidate) THEN candidate:=candidate+make_interval(mins=>increment); CONTINUE; END IF;
    finish:=public.workshop_add_operational_minutes(candidate,minutes);
    IF finish>horizon THEN EXIT; END IF;
    -- A vehicle cannot work in a bay while it is away with a Sublet provider.
    SELECT d::date INTO away_date FROM generate_series((candidate AT TIME ZONE 'Australia/Perth')::date::timestamp,((finish-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
     WHERE public.pdc_sublet_away_on_date(v.id,d::date) ORDER BY d DESC LIMIT 1;
    IF FOUND THEN candidate:=(away_date+1)::timestamp AT TIME ZONE 'Australia/Perth'; CONTINUE; END IF;
    SELECT max(x.next_at) INTO blocked_until FROM (
     SELECT CASE WHEN b.vehicle_id=v.id THEN e.ends+interval '5 hours' ELSE e.ends END next_at
     FROM public.workshop_bookings b
     CROSS JOIN LATERAL(SELECT greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id),CASE WHEN b.status IN('started','stoppage') THEN now() ELSE b.scheduled_end_at END) ends) e
     WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND (b.vehicle_id=v.id OR b.bay_id=bay.id)
      AND ((b.vehicle_id=v.id AND b.scheduled_start_at<finish+interval '5 hours' AND e.ends+interval '5 hours'>candidate)
        OR (b.bay_id=bay.id AND b.scheduled_start_at<finish AND e.ends>candidate))
     UNION ALL
     SELECT a.scheduled_end_at FROM public.workshop_admin_blocks a WHERE a.deleted_at IS NULL AND a.bay_id=bay.id AND a.scheduled_start_at<finish AND a.scheduled_end_at>candidate
    ) x;
    IF blocked_until IS NOT NULL THEN
     candidate:=to_timestamp(ceil(extract(epoch FROM greatest(blocked_until,candidate+make_interval(mins=>increment)))/(increment*60))*(increment*60)); CONTINUE;
    END IF;
    best_start:=candidate; best_end:=finish; best_bay:=bay.bay_number; EXIT;
   END LOOP;
  END LOOP;
  IF best_start IS NULL THEN RAISE EXCEPTION 'No available bay was found for % within the next 300 days.',item->>'name' USING DETAIL='no_available_slot'; END IF;
  SELECT version INTO current_version FROM public.vehicles WHERE id=v.id;
  result:=public.schedule_vehicle_work(v.id,current_version,item->>'code',best_bay,best_start,minutes,NULL,NULL,jsonb_build_object('source','book_all_stations','buffer_minutes',300));
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Could not book % (%). Refresh and try again.',item->>'name',coalesce(result->>'error','schedule rejected') USING DETAIL='booking_rejected'; END IF;
  booked:=booked||jsonb_build_array(jsonb_build_object('stage',item->>'name','bay',best_bay,'start_at',best_start,'end_at',best_end,'booking_id',coalesce(result#>>'{booking,booking_id}',result#>>'{booking,id}')));
 END LOOP;
 RETURN jsonb_build_object('ok',true,'bookings',booked,'skipped',skipped,'buffer_minutes',300);
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS failure=MESSAGE_TEXT,failure_code=PG_EXCEPTION_DETAIL;
 RETURN jsonb_build_object('ok',false,'error',coalesce(nullif(failure_code,''),SQLSTATE),'message',failure||' No new bookings were saved.');
END $function$
;

CREATE OR REPLACE FUNCTION public.workshop_station_eligibility(p_stage_code text)
 RETURNS TABLE(vehicle_id uuid, stage_code text, work_key text, current_location text, eta_to_kewdale date, existing_booking boolean, schedule_enabled boolean, disabled_reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH station AS(
  SELECT s.id,s.code,s.work_key FROM public.workshop_stages s
  WHERE s.code=public.workshop_canonical_stage_code(p_stage_code) AND s.active AND s.planner_enabled
 ),outstanding AS(
  SELECT wi.vehicle_id,st.id stage_id,st.code,st.work_key
  FROM public.vehicle_work_items wi CROSS JOIN station st
  WHERE public.workshop_stage_code_for_work_key(wi.work_key)=st.code AND wi.required AND NOT wi.completed
  GROUP BY wi.vehicle_id,st.id,st.code,st.work_key
 ),active_booking AS(
  SELECT DISTINCT b.vehicle_id,st.code FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id JOIN station st ON st.code=s.code
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
 ),eligible AS MATERIALIZED (
 SELECT v.id,o.code,o.work_key,public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) current_location,v.eta_to_kewdale,
  (ab.vehicle_id IS NOT NULL) existing_booking,o.stage_id
 FROM outstanding o JOIN public.vehicles v ON v.id=o.vehicle_id
 LEFT JOIN active_booking ab ON ab.vehicle_id=v.id AND ab.code=o.code
 WHERE v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
   AND public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) IN('PMB','YH','IT')
   AND (public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))<>'IT' OR v.eta_to_kewdale IS NOT NULL)
 ),estimated AS MATERIALIZED (
 SELECT e.*,public.workshop_vehicle_stage_estimated_duration_minutes(e.id,e.stage_id) duration_minutes
 FROM eligible e
 )
 SELECT e.id,e.code,e.work_key,e.current_location,e.eta_to_kewdale,e.existing_booking,
   e.duration_minutes IS NOT NULL,
   CASE WHEN e.duration_minutes IS NULL THEN 'estimated_duration_missing' ELSE NULL::text END
 FROM estimated e
$function$
;

CREATE OR REPLACE FUNCTION public.workshop_prevent_disabled_planner_booking_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_enabled boolean; v_mutating boolean; v_location text; v_eta date; v_stage text; v_eligible boolean;
begin
 if tg_op='UPDATE' and old.deleted_at is not null then
  if new.deleted_at is null and new.status='queued' and new.bay_id is null
     and new.stage_id=old.stage_id and new.vehicle_id=old.vehicle_id
     and new.scheduled_start_at is not distinct from old.scheduled_start_at
     and new.scheduled_end_at is not distinct from old.scheduled_end_at
     and new.default_duration_minutes is not distinct from old.default_duration_minutes then
   return new;
  end if;
  raise exception 'Soft-deleted Workshop Planner bookings cannot be scheduled or cascaded' using errcode='22023';
 end if;
 v_mutating:=tg_op='INSERT';
 if tg_op='UPDATE' then
  v_mutating:=old.stage_id is distinct from new.stage_id
   or old.bay_id is distinct from new.bay_id
   or old.scheduled_start_at is distinct from new.scheduled_start_at
   or old.scheduled_end_at is distinct from new.scheduled_end_at
   or old.default_duration_minutes is distinct from new.default_duration_minutes;
 end if;
 if v_mutating then
  select code,planner_enabled into v_stage,v_enabled from public.workshop_stages where id=new.stage_id and active;
  if not found or coalesce(v_enabled,false)=false then
   raise exception 'This work type does not have a Workshop Planner' using errcode='22023';
  end if;
  select public.workshop_location_code(coalesce(nullif(location_override,''),current_location)),eta_to_kewdale into v_location,v_eta
  from public.vehicles where id=new.vehicle_id and lifecycle_state='active' and deleted_at is null;
  if not found then
   raise exception 'Active non-deleted vehicle is required for Workshop Planner scheduling' using errcode='22023';
  end if;
  select exists(select 1 from public.workshop_station_eligibility(v_stage)e where e.vehicle_id=new.vehicle_id)
    into v_eligible;
  if not coalesce(v_eligible,false) and tg_op='UPDATE' then
   select exists(
     select 1
     from public.pdc_overnight_synthetic_fleet_registry_363 r
     join public.vehicles v on v.id=new.vehicle_id
      and r.run_id='HERMES-TEST-RUN-20260824'
      and r.vehicle_id=new.vehicle_id
      and v.stock_number=r.stock_number
      and v.customer_name=r.customer_name
      and v.job_card_number=r.job_card_number
      and v.vehicle_description=r.vehicle_description
      and v.source_system='hermes_overnight_synthetic'
      and v.source_batch_id=r.run_id
      and v.source_record_id=r.stock_number
      and v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
     join public.workshop_stages s on s.id=new.stage_id and s.code=v_stage and s.active and s.planner_enabled
     where old.id=new.id
       and old.vehicle_id=new.vehicle_id
       and old.status in('queued','planned','started','stoppage')
       and new.status in('queued','planned','started','stoppage')
       and new.deleted_at is null
   ) into v_eligible;
  end if;
  if not coalesce(v_eligible,false) then
   raise exception 'Outstanding station requirement and current planner eligibility are required for scheduling' using errcode='22023';
  end if;
  if v_location not in('PMB','YH','IT') then
   raise exception 'Vehicle location is not eligible for Workshop Planner scheduling' using errcode='22023';
  end if;
  if v_location='IT' and v_eta is null then
   raise exception 'ETA to Kewdale is required before scheduling an in-transit vehicle' using errcode='22023';
  end if;
  if v_location='IT' and (new.scheduled_start_at at time zone 'Australia/Perth')::date<v_eta then
   raise exception 'In-transit vehicle cannot be scheduled before ETA to Kewdale' using errcode='22023';
  end if;
 end if;
 return new;
end $function$
;
