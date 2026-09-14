-- STAGING ONLY: avoid rebuilding an entire station queue for each booking move,
-- count calendar spans, and calculate an estimate once per duration lookup.
-- Scheduling order, locks, conflict checks, and source-hours rules are unchanged.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 IF md5(pg_get_functiondef('public.workshop_prevent_disabled_planner_booking_mutation()'::regprocedure))<>'d6dc3b76518a74cd126def5f363f9e1e'
 OR md5(pg_get_functiondef('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure))<>'c2f520232d76154e12e2fc55f01d4e4a'
 OR md5(pg_get_functiondef('public.workshop_station_eligibility(text)'::regprocedure))<>'cc5c7db7d002704b39f258e5371afd97'
 OR md5(pg_get_functiondef('public.workshop_calendar_minute_available(timestamptz)'::regprocedure))<>'1135597e0c937a301ebb10fbbbdc9fe2'
 OR md5(pg_get_functiondef('public.workshop_operational_minutes_between(timestamptz,timestamptz)'::regprocedure))<>'7cfebdfcd573db93640c3e1d9ba8efb6'
 THEN RAISE EXCEPTION 'Workshop validation changed; review before applying'; END IF;
END $guard$;

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
  -- This guard needs membership, not the station-wide queue or every
  -- vehicle's calculated hours. Keep the same eligibility predicates scoped
  -- to this booking's vehicle; duration validation has its separate guard.
  select exists(
    select 1 from public.vehicles v
    join public.workshop_stages s on s.id=new.stage_id and s.active and s.planner_enabled
    join public.vehicle_work_items wi on wi.vehicle_id=v.id
      and public.workshop_stage_code_for_work_key(wi.work_key)=s.code
      and wi.required and not wi.completed
    where v.id=new.vehicle_id and v.lifecycle_state='active'
      and v.deleted_at is null and v.visible_on_board
      and public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) in('PMB','YH','IT')
      and (public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))<>'IT' or v.eta_to_kewdale is not null)
  ) into v_eligible;
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

CREATE OR REPLACE FUNCTION public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id uuid, p_stage_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH exact_synthetic AS(
  SELECT e.estimated_minutes
  FROM public.pdc_overnight_synthetic_estimates_369 e
  JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.run_id=e.run_id AND r.vehicle_id=e.vehicle_id AND r.scenario_no=e.scenario_no
  JOIN public.vehicles v ON v.id=e.vehicle_id AND v.stock_number=r.stock_number
   AND v.customer_name=r.customer_name AND v.job_card_number=r.job_card_number AND v.vehicle_description=r.vehicle_description
   AND v.source_system='hermes_overnight_synthetic' AND v.source_batch_id=e.run_id AND v.source_record_id=r.stock_number
   AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
   AND v.source_payload->>'run_id'=e.run_id AND (v.source_payload->>'scenario_no')::integer=e.scenario_no
  JOIN public.workshop_stages s ON s.id=p_stage_id AND s.code=e.stage_code
  WHERE e.run_id='HERMES-TEST-RUN-20260824' AND e.vehicle_id=p_vehicle_id
    AND e.estimated_minutes BETWEEN 1 AND 59
    AND e.estimated_minutes=round(e.estimated_hours*60)::integer
    AND public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,s.code)=e.estimated_hours
  LIMIT 1
 ), established AS MATERIALIZED(
  SELECT h.hours
  FROM public.workshop_stages s
  CROSS JOIN LATERAL(SELECT public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,s.code) hours) h
  WHERE s.id=p_stage_id
 )
 SELECT CASE WHEN x.estimated_minutes IS NOT NULL THEN x.estimated_minutes
             WHEN h.hours IS NULL THEN NULL WHEN (public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>'active')::boolean THEN greatest(1,round(h.hours*60)::integer) ELSE greatest(1,round(h.hours*60)::integer) END
 FROM established h LEFT JOIN exact_synthetic x ON true
$function$
;

CREATE OR REPLACE FUNCTION public.workshop_operational_minutes_between(p_start timestamptz,p_end timestamptz)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE settings jsonb; start_time time; end_time time; windows jsonb;
 cursor_at timestamptz:=date_trunc('minute',p_start); stop_at timestamptz:=date_trunc('minute',p_end);
 day_start_at timestamptz; day_end timestamptz; local_day date; day_name text; boundaries integer[]; boundary integer;
 next_at timestamptz; day_minutes integer; total_minutes integer:=0;
BEGIN
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start OR stop_at<=cursor_at THEN RETURN 0; END IF;
 SELECT jsonb_object_agg(key,value) INTO settings FROM public.workshop_settings
 WHERE key IN('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows');
 BEGIN
  start_time:=(settings->>'day_start_time')::time; end_time:=(settings->>'day_end_time')::time;
 EXCEPTION WHEN OTHERS THEN RETURN 0; END;
 IF start_time IS NULL OR end_time IS NULL OR start_time>=end_time
 OR jsonb_typeof(settings->'working_week')<>'array'
 OR jsonb_typeof(settings->'closures')<>'array'
 OR jsonb_typeof(settings->'break_windows')<>'array'
 OR jsonb_typeof(settings->'overtime_windows')<>'array' THEN RETURN 0; END IF;
 windows:=coalesce(settings->'break_windows','[]'::jsonb)||coalesce(settings->'overtime_windows','[]'::jsonb);
 WHILE cursor_at<stop_at LOOP
  local_day:=(cursor_at AT TIME ZONE 'Australia/Perth')::date;
  day_name:=lower(to_char(local_day,'FMDay'));
  day_end:=least((local_day+1)::timestamp AT TIME ZONE 'Australia/Perth',stop_at);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(settings->'working_week') d WHERE lower(d)=day_name)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(settings->'closures') c WHERE c->>'date'=local_day::text)
  THEN cursor_at:=day_end; CONTINUE; END IF;
  day_start_at:=cursor_at; day_minutes:=0;
  BEGIN
   -- Integer-minute sampling changes only at the first minute on/after a boundary.
   SELECT array_agg(DISTINCT n ORDER BY n) INTO boundaries FROM (
    SELECT ceil(extract(epoch FROM start_time)/60)::integer n
    UNION ALL SELECT ceil(extract(epoch FROM end_time)/60)::integer
    UNION ALL SELECT 1440
    UNION ALL SELECT ceil(extract(epoch FROM b.t)/60)::integer
    FROM jsonb_array_elements(windows) w
    CROSS JOIN LATERAL(VALUES((w->>'start')::time),((w->>'end')::time)) b(t)
    WHERE (w ? 'date' AND w->>'date'=local_day::text)
       OR (NOT(w ? 'date') AND lower(coalesce(w->>'scope',w->>'day','global')) IN('global','working_day',day_name))
   ) points WHERE n IS NOT NULL;
   FOREACH boundary IN ARRAY boundaries LOOP
    next_at:=least((local_day::timestamp+make_interval(mins=>boundary)) AT TIME ZONE 'Australia/Perth',day_end);
    IF next_at<=cursor_at THEN CONTINUE; END IF;
    IF public.workshop_calendar_minute_available(cursor_at) THEN
     day_minutes:=day_minutes+floor(extract(epoch FROM next_at-cursor_at)/60)::integer;
    END IF;
    cursor_at:=next_at;
    EXIT WHEN cursor_at>=day_end;
   END LOOP;
  EXCEPTION WHEN OTHERS THEN
   -- Unusual legacy windows use the original minute oracle for this day.
   SELECT count(*)::integer INTO day_minutes
   FROM generate_series(day_start_at,day_end-interval '1 minute',interval '1 minute') m
   WHERE public.workshop_calendar_minute_available(m);
  END;
  total_minutes:=total_minutes+day_minutes;
  cursor_at:=day_end;
 END LOOP;
 RETURN total_minutes;
END $function$;
-- CREATE OR REPLACE retains the existing owner and execution grants.


-- CREATE OR REPLACE retains every existing owner and execution grant.
