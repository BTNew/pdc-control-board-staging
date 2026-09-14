-- STAGING ONLY. Bay capacity is allocation time, never a quoted operation edit.
-- Apply after workshop_bay_capacity_configuration; every patched live definition
-- is checked before replacement. No existing booking rows are backfilled.
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workshop_bays' AND column_name='efficiency_percent')
 THEN RAISE EXCEPTION 'Bay capacity configuration must be installed first'; END IF;
END $guard$;


DO $definitions$
BEGIN
 IF md5(pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,workshop_booking_status,uuid,boolean)'::regprocedure))<>'a7ab087c067e7c4ea15dc9b0cb7d3fad' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,workshop_booking_status,uuid,boolean)'; END IF;
 IF md5(pg_get_functiondef('public.workshop_booking_minimum_duration_guard_372()'::regprocedure))<>'ae5457fd58d0a9fc2fcef7a6cefa243d' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_booking_minimum_duration_guard_372()'; END IF;
 IF md5(pg_get_functiondef('public.workshop_booking_effective_duration_minutes(uuid)'::regprocedure))<>'5fcb84532a82ee8bcdabaaa1aa32acfe' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_booking_effective_duration_minutes(uuid)'; END IF;
 IF md5(pg_get_functiondef('public.pdc_tune_reconcile_booking_plan_20260913(uuid,text[],uuid)'::regprocedure))<>'a41d344994d9df412f60516144284095' THEN RAISE EXCEPTION 'Capacity integration source changed: pdc_tune_reconcile_booking_plan_20260913(uuid,text[],uuid)'; END IF;
 IF md5(pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure))<>'3af3423284f683c97378d4a4a413bc1f' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'; END IF;
 IF md5(pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamp with time zone,jsonb)'::regprocedure))<>'b6ec50b6911e2ce4caa7cf664ddc9035' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_admin_repack_planned(uuid,timestamp with time zone,jsonb)'; END IF;
 IF md5(pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure))<>'a6277d1d03fea2c102fbb69c4f496e09' THEN RAISE EXCEPTION 'Capacity integration source changed: set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'; END IF;
 IF md5(pg_get_functiondef('public.book_all_vehicle_stations(uuid,integer)'::regprocedure))<>'cb440bb0e8f9e6a01f05a56c6b146773' THEN RAISE EXCEPTION 'Capacity integration source changed: book_all_vehicle_stations(uuid,integer)'; END IF;
 IF md5(pg_get_functiondef('public.workshop_create_booking(uuid,text,integer,timestamp with time zone,integer,uuid,jsonb)'::regprocedure))<>'455f29ba05c1d3666d89c30084fdbe70' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_create_booking(uuid,text,integer,timestamp with time zone,integer,uuid,jsonb)'; END IF;
 IF md5(pg_get_functiondef('public.workshop_booking_snapshot(uuid)'::regprocedure))<>'d89d3a1b0a37031cdddf27497e221178' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_booking_snapshot(uuid)'; END IF;
 IF md5(pg_get_functiondef('public.workshop_overlay_canonical_booking_fields_397(jsonb)'::regprocedure))<>'514dfc41852a61eafc5044e881848fa1' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_overlay_canonical_booking_fields_397(jsonb)'; END IF;
 IF md5(pg_get_functiondef('public.workshop_resize_booking(uuid,integer,integer,jsonb)'::regprocedure))<>'662efe8fa01d15c792fd939966a91e2f' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_resize_booking(uuid,integer,integer,jsonb)'; END IF;
 IF md5(pg_get_functiondef('public.workshop_move_booking(uuid,integer,text,integer,timestamp with time zone,integer,jsonb)'::regprocedure))<>'32035ee4a7a513bebab16475326069a1' THEN RAISE EXCEPTION 'Capacity integration source changed: workshop_move_booking(uuid,integer,text,integer,timestamp with time zone,integer,jsonb)'; END IF;
 IF md5(pg_get_functiondef('public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)'::regprocedure))<>'7cf9b2f4846ae94b461cd726c2706019' THEN RAISE EXCEPTION 'Capacity integration source changed: cascade_workshop_schedule(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)'; END IF;
END $definitions$;

ALTER TABLE public.workshop_bookings
 ADD COLUMN capacity_base_minutes numeric,
 ADD COLUMN capacity_efficiency_percent integer,
 ADD COLUMN capacity_estimate_minutes integer,
 ADD CONSTRAINT workshop_capacity_basis_valid CHECK(
  (capacity_base_minutes IS NULL AND capacity_efficiency_percent IS NULL AND capacity_estimate_minutes IS NULL)
  OR (capacity_base_minutes IS NOT NULL AND capacity_efficiency_percent IS NOT NULL
   AND capacity_base_minutes>0 AND capacity_base_minutes<=59999 AND capacity_efficiency_percent BETWEEN 10 AND 200
   AND (capacity_estimate_minutes IS NULL OR capacity_estimate_minutes>0))
 );

CREATE FUNCTION public.workshop_capacity_duration_minutes(p_base_minutes numeric,p_bay_id uuid)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $capacity$
DECLARE efficiency integer; result numeric;
BEGIN
 IF p_base_minutes IS NULL THEN RETURN NULL; END IF;
 IF p_base_minutes<=0 OR p_base_minutes>59999 THEN RAISE EXCEPTION 'Invalid base work minutes' USING ERRCODE='22023'; END IF;
 IF p_bay_id IS NULL THEN efficiency:=100;
 ELSE
  SELECT efficiency_percent INTO efficiency FROM public.workshop_bays WHERE id=p_bay_id;
  IF efficiency IS NULL OR efficiency NOT BETWEEN 10 AND 200 THEN RAISE EXCEPTION 'Bay efficiency is unavailable' USING ERRCODE='22023'; END IF;
 END IF;
 result:=ceil(p_base_minutes*100/efficiency);
 IF result NOT BETWEEN 1 AND 59999 THEN RAISE EXCEPTION 'Adjusted duration exceeds the workshop limit' USING ERRCODE='22023'; END IF;
 RETURN result::integer;
END $capacity$;
REVOKE ALL ON FUNCTION public.workshop_capacity_duration_minutes(numeric,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.workshop_booking_capacity_base_minutes(p_booking_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $base$
 SELECT CASE WHEN b.capacity_base_minutes IS NULL THEN greatest(q.minutes,b.default_duration_minutes)::numeric
 ELSE greatest(1,b.capacity_base_minutes+CASE WHEN q.minutes IS NOT NULL AND b.capacity_estimate_minutes IS NOT NULL
  THEN q.minutes-b.capacity_estimate_minutes ELSE 0 END) END
 FROM public.workshop_bookings b
 CROSS JOIN LATERAL(SELECT public.workshop_vehicle_stage_estimated_duration_minutes(b.vehicle_id,b.stage_id) minutes) q
 WHERE b.id=p_booking_id
$base$;
REVOKE ALL ON FUNCTION public.workshop_booking_capacity_base_minutes(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.workshop_booking_capacity_duration_minutes(p_booking_id uuid,p_vehicle_id uuid,p_stage_id uuid,p_bay_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $target$
 SELECT CASE WHEN p_bay_id IS NULL AND EXISTS(
  SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id AND b.stage_id=p_stage_id)
 THEN (SELECT default_duration_minutes FROM public.workshop_bookings WHERE id=p_booking_id)
 ELSE public.workshop_capacity_duration_minutes(
  CASE WHEN EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id AND b.stage_id=p_stage_id)
   THEN public.workshop_booking_capacity_base_minutes(p_booking_id)
   ELSE public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,p_stage_id)::numeric END,p_bay_id) END
$target$;
REVOKE ALL ON FUNCTION public.workshop_booking_capacity_duration_minutes(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Only an authorized explicit resize/extend creates this transaction-local context.
-- It is bound to the exact actor, booking version, bay, and requested allocation.
-- Automatic cascades have no matching context and retain the estimate equality guard.
CREATE FUNCTION public.workshop_capacity_manual_minutes(p_booking_id uuid,p_vehicle_id uuid,p_stage_id uuid,p_bay_id uuid,p_duration integer)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $manual$
DECLARE context jsonb; b public.workshop_bookings%rowtype; minimum_minutes integer;
BEGIN
 BEGIN context:=nullif(current_setting('pdc.workshop_capacity_manual',true),'')::jsonb;
 EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
 IF context IS NULL OR context->>'actor' IS DISTINCT FROM auth.uid()::text
 OR context->>'booking' IS DISTINCT FROM p_booking_id::text
 OR context->>'duration' IS DISTINCT FROM p_duration::text THEN RETURN NULL; END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id AND vehicle_id=p_vehicle_id AND stage_id=p_stage_id
  AND bay_id IS NOT DISTINCT FROM p_bay_id AND deleted_at IS NULL AND status IN('queued','planned');
 IF NOT FOUND OR context->>'version' IS DISTINCT FROM b.version::text THEN RETURN NULL; END IF;
 minimum_minutes:=public.workshop_capacity_duration_minutes(public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,p_stage_id),p_bay_id);
 IF minimum_minutes IS NULL OR p_duration<minimum_minutes OR p_duration>59999 THEN RETURN NULL; END IF;
 RETURN p_duration;
END $manual$;
REVOKE ALL ON FUNCTION public.workshop_capacity_manual_minutes(uuid,uuid,uuid,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.workshop_capture_capacity_basis()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $capture$
DECLARE base numeric; quote integer; efficiency integer; manual integer;
BEGIN
 -- Completed/live history and its applied duration stay fixed.
 IF NEW.deleted_at IS NOT NULL OR NEW.status NOT IN('queued','planned') THEN
  IF TG_OP='UPDATE' THEN
   NEW.capacity_base_minutes:=OLD.capacity_base_minutes;
   NEW.capacity_efficiency_percent:=OLD.capacity_efficiency_percent;
   NEW.capacity_estimate_minutes:=OLD.capacity_estimate_minutes;
  END IF;
  RETURN NEW;
 END IF;
 IF TG_OP='UPDATE' AND NEW.status='queued' AND NEW.bay_id IS NULL
  AND NEW.vehicle_id=OLD.vehicle_id AND NEW.stage_id=OLD.stage_id
  AND NEW.default_duration_minutes=OLD.default_duration_minutes
  AND NEW.scheduled_start_at=OLD.scheduled_start_at AND NEW.scheduled_end_at=OLD.scheduled_end_at THEN
  NEW.capacity_base_minutes:=OLD.capacity_base_minutes;
  NEW.capacity_efficiency_percent:=OLD.capacity_efficiency_percent;
  NEW.capacity_estimate_minutes:=OLD.capacity_estimate_minutes;
  RETURN NEW;
 END IF;
 IF TG_OP='UPDATE' AND NEW.vehicle_id IS NOT DISTINCT FROM OLD.vehicle_id
  AND NEW.stage_id IS NOT DISTINCT FROM OLD.stage_id AND NEW.bay_id IS NOT DISTINCT FROM OLD.bay_id
  AND NEW.scheduled_start_at IS NOT DISTINCT FROM OLD.scheduled_start_at
  AND NEW.scheduled_end_at IS NOT DISTINCT FROM OLD.scheduled_end_at
  AND NEW.default_duration_minutes IS NOT DISTINCT FROM OLD.default_duration_minutes
  AND OLD.capacity_base_minutes IS NOT NULL
  AND coalesce((SELECT efficiency_percent FROM public.workshop_bays WHERE id=NEW.bay_id),100)=OLD.capacity_efficiency_percent THEN
  NEW.capacity_base_minutes:=OLD.capacity_base_minutes;
  NEW.capacity_efficiency_percent:=OLD.capacity_efficiency_percent;
  NEW.capacity_estimate_minutes:=OLD.capacity_estimate_minutes;
  RETURN NEW;
 END IF;
 quote:=public.workshop_vehicle_stage_estimated_duration_minutes(NEW.vehicle_id,NEW.stage_id);
 SELECT coalesce(b.efficiency_percent,100) INTO efficiency FROM (SELECT 1) one LEFT JOIN public.workshop_bays b ON b.id=NEW.bay_id;
 base:=CASE WHEN TG_OP='UPDATE' AND NEW.vehicle_id=OLD.vehicle_id AND NEW.stage_id=OLD.stage_id
  THEN public.workshop_booking_capacity_base_minutes(OLD.id) ELSE quote END;
 manual:=public.workshop_capacity_manual_minutes(NEW.id,NEW.vehicle_id,NEW.stage_id,NEW.bay_id,NEW.default_duration_minutes);
 IF manual IS NOT NULL AND manual IS DISTINCT FROM public.workshop_capacity_duration_minutes(base,NEW.bay_id) THEN
  base:=manual::numeric*efficiency/100;
 END IF;
 IF base IS NOT NULL THEN
  NEW.capacity_base_minutes:=base;
  NEW.capacity_efficiency_percent:=efficiency;
  NEW.capacity_estimate_minutes:=quote;
 END IF;
 RETURN NEW;
END $capture$;
REVOKE ALL ON FUNCTION public.workshop_capture_capacity_basis() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER workshop_booking_043_capacity_basis BEFORE INSERT OR UPDATE ON public.workshop_bookings
FOR EACH ROW EXECUTE FUNCTION public.workshop_capture_capacity_basis();

-- Existing permissions and wrapper contracts retained: workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,workshop_booking_status,uuid,boolean)
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
  if not found then return jsonb_build_object('ok',false,'error','station_inactive_or_missing'); end if; v_estimated_duration:=coalesce(public.workshop_capacity_manual_minutes(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id,p_duration_minutes),public.workshop_booking_capacity_duration_minutes(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id)); v_candidate_end:=case when p_status in ('queued','planned') and v_estimated_duration is not null then public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) else p_scheduled_end_at end; if p_status in ('queued','planned') and v_estimated_duration is not null and p_duration_minutes<>v_estimated_duration and not v_registered_synthetic then return jsonb_build_object('ok',false,'error','operation_estimate_duration_mismatch','expected_minutes',v_estimated_duration); end if;
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

-- Existing permissions and wrapper contracts retained: workshop_booking_minimum_duration_guard_372()
CREATE OR REPLACE FUNCTION public.workshop_booking_minimum_duration_guard_372()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
 IF NEW.default_duration_minutes IS NULL OR NEW.default_duration_minutes<=0 THEN
  RAISE EXCEPTION 'PDC_372_POSITIVE_DURATION_REQUIRED' USING errcode='23514';
 END IF;
 IF TG_OP='UPDATE' AND NEW.vehicle_id=OLD.vehicle_id AND NEW.stage_id=OLD.stage_id
  AND NEW.default_duration_minutes=OLD.default_duration_minutes THEN RETURN NEW; END IF;
 -- Recorded positive job hours are authoritative for real workshop bookings.
 -- Arbitrary shortened durations still fall through to the existing guard.
 IF NEW.default_duration_minutes<60
   AND NEW.default_duration_minutes=coalesce(public.workshop_capacity_manual_minutes(NEW.id,NEW.vehicle_id,NEW.stage_id,NEW.bay_id,NEW.default_duration_minutes),public.workshop_booking_capacity_duration_minutes(NEW.id,NEW.vehicle_id,NEW.stage_id,NEW.bay_id))
   AND EXISTS(
     SELECT 1 FROM public.vehicles v
     JOIN public.vehicle_work_items wi ON wi.vehicle_id=v.id AND wi.required AND NOT wi.completed
     JOIN public.workshop_stages s ON s.id=NEW.stage_id AND s.code=public.workshop_stage_code_for_work_key(wi.work_key)
     WHERE v.id=NEW.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
       AND s.active AND s.planner_enabled
   ) THEN RETURN NEW; END IF;
 IF NEW.default_duration_minutes<60 AND NOT (coalesce((public.pdc_qc_rework_scope_20260909(NEW.vehicle_id)->>'active')::boolean,false) AND NEW.default_duration_minutes=coalesce(public.workshop_capacity_manual_minutes(NEW.id,NEW.vehicle_id,NEW.stage_id,NEW.bay_id,NEW.default_duration_minutes),public.workshop_booking_capacity_duration_minutes(NEW.id,NEW.vehicle_id,NEW.stage_id,NEW.bay_id))) AND NOT EXISTS(
  SELECT 1 FROM public.pdc_overnight_synthetic_estimates_369 e
  JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.run_id=e.run_id AND r.vehicle_id=e.vehicle_id AND r.scenario_no=e.scenario_no
  JOIN public.vehicles v ON v.id=e.vehicle_id AND v.stock_number=r.stock_number AND v.customer_name=r.customer_name
   AND v.job_card_number=r.job_card_number AND v.vehicle_description=r.vehicle_description
   AND v.source_system='hermes_overnight_synthetic' AND v.source_batch_id=e.run_id AND v.source_record_id=r.stock_number
   AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
  JOIN public.workshop_stages s ON s.id=NEW.stage_id AND s.code=e.stage_code
  WHERE e.run_id='HERMES-TEST-RUN-20260824' AND e.vehicle_id=NEW.vehicle_id
    AND e.estimated_minutes=NEW.default_duration_minutes AND e.estimated_minutes BETWEEN 1 AND 59
    AND e.estimated_minutes=round(e.estimated_hours*60)::integer
    AND public.workshop_vehicle_stage_estimated_duration_minutes(NEW.vehicle_id,NEW.stage_id)=e.estimated_minutes
 ) THEN
  IF NOT EXISTS(
    SELECT 1
    FROM public.pdc_overnight_synthetic_fleet_registry_363 r
    JOIN public.vehicles v ON v.id=NEW.vehicle_id
     AND r.run_id='HERMES-TEST-RUN-20260824'
     AND r.vehicle_id=v.id
     AND v.stock_number=r.stock_number
     AND v.customer_name=r.customer_name
     AND v.job_card_number=r.job_card_number
     AND v.vehicle_description=r.vehicle_description
     AND v.source_system='hermes_overnight_synthetic'
     AND v.source_batch_id=r.run_id
     AND v.source_record_id=r.stock_number
     AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
    JOIN public.workshop_stages s ON s.id=NEW.stage_id AND s.active AND s.planner_enabled
  ) THEN
    RAISE EXCEPTION 'PDC_372_MINIMUM_DURATION_60' USING errcode='23514';
  END IF;
 END IF;
 RETURN NEW;
END $function$
;

-- Existing permissions and wrapper contracts retained: workshop_booking_effective_duration_minutes(uuid)
CREATE OR REPLACE FUNCTION public.workshop_booking_effective_duration_minutes(p_booking_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 select case when b.status in('queued','planned','started','stoppage') then
   coalesce(ceil(public.workshop_booking_capacity_base_minutes(b.id)*100/coalesce(b.capacity_efficiency_percent,100))::integer,b.default_duration_minutes)
  else b.default_duration_minutes end
 from public.workshop_bookings b where b.id=p_booking_id and b.deleted_at is null
$function$
;

-- Existing permissions and wrapper contracts retained: pdc_tune_reconcile_booking_plan_20260913(uuid,text[],uuid)
CREATE OR REPLACE FUNCTION public.pdc_tune_reconcile_booking_plan_20260913(p_vehicle_id uuid, p_stage_codes text[], p_change_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '120s'
AS $function$
#variable_conflict use_column
<<plan>>
DECLARE
 item record; prior record; n integer; minutes integer; proposed_start timestamptz;
 proposed_end timestamptz; blocked_until timestamptz; unavailable_date date;
 old_snapshot jsonb; new_snapshot jsonb; receipt jsonb:='[]'; changed boolean;
 root_change boolean; technician uuid; validation jsonb; graph_count integer;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Operation approval is available on staging only.';
 END IF;
 PERFORM public.workshop_require_planner_operator();
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.bay_id IS NOT NULL
    AND b.status IN('queued','planned','started','stoppage') AND s.code=ANY(p_stage_codes)
    AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET') THEN
  RETURN jsonb_build_object('bookings',receipt,'changed_count',0,'extended_count',0,'moved_count',0,'buffer_minutes',300);
 END IF;
 -- These are the same rows written by the existing planner. Preserve its guards
 -- and immediate overlap constraints; never hide or temporarily delete a job.
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL
  AND status IN('queued','planned','started','stoppage') ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE NOWAIT;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE NOWAIT;
 DROP TABLE IF EXISTS pg_temp.pdc_tune_cascade_plan;
 CREATE TEMP TABLE pdc_tune_cascade_plan(
  ordinal bigint PRIMARY KEY,booking_id uuid UNIQUE NOT NULL,vehicle_id uuid NOT NULL,
  stage_id uuid NOT NULL,stage_code text NOT NULL,bay_id uuid,status text NOT NULL,
  original_start timestamptz NOT NULL,original_end timestamptz NOT NULL,
  original_minutes integer NOT NULL,minutes integer NOT NULL,version integer NOT NULL,
  final_start timestamptz NOT NULL,final_end timestamptz NOT NULL,
  technicians uuid[] NOT NULL,root_change boolean NOT NULL DEFAULT false,
  changed boolean NOT NULL DEFAULT false,before_row jsonb NOT NULL
 ) ON COMMIT DROP;
 INSERT INTO pg_temp.pdc_tune_cascade_plan
  (ordinal,booking_id,vehicle_id,stage_id,stage_code,bay_id,status,original_start,original_end,
   original_minutes,minutes,version,final_start,final_end,technicians,before_row)
 SELECT row_number() OVER(ORDER BY b.scheduled_start_at,b.id),b.id,b.vehicle_id,b.stage_id,s.code,b.bay_id,b.status::text,
  b.scheduled_start_at,b.scheduled_end_at,b.default_duration_minutes,b.default_duration_minutes,b.version,
  b.scheduled_start_at,b.scheduled_end_at,
  coalesce((SELECT array_agg(DISTINCT a.technician_id) FROM public.workshop_booking_assignments a
    WHERE a.booking_id=b.id AND a.released_at IS NULL),'{}'::uuid[]),to_jsonb(b)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
  AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET';
 SELECT count(*) INTO graph_count FROM pg_temp.pdc_tune_cascade_plan;
 IF graph_count>10000 THEN RAISE EXCEPTION 'The workshop queue needs a smaller scheduling review.'
  USING DETAIL='operation_schedule_limit'; END IF;
 -- A station booking is the whole station estimate, not just the changed line.
 -- Never manufacture a booking for a newly required, unbooked station.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan
  WHERE vehicle_id=p_vehicle_id AND stage_code=ANY(p_stage_codes) AND bay_id IS NOT NULL ORDER BY ordinal
 LOOP
  IF (SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan x
    WHERE x.vehicle_id=p_vehicle_id AND x.stage_id=item.stage_id AND x.bay_id IS NOT NULL)>1 THEN
   RAISE EXCEPTION 'This station has more than one active booking. Review those bookings before approving the operation.'
    USING DETAIL='operation_schedule_multiple_station_bookings';
  END IF;
  minutes:=CASE WHEN item.status IN('queued','planned') THEN public.workshop_booking_capacity_duration_minutes(item.booking_id,p_vehicle_id,item.stage_id,item.bay_id) ELSE public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,item.stage_id) END;
  IF minutes IS NULL OR minutes<1 THEN
   RAISE EXCEPTION 'This change would leave a booked station without work. Move or remove its booking before approving.'
    USING DETAIL='operation_schedule_empty_station';
  END IF;
  -- Reducing an estimate must not shorten a job that is already in progress.
  IF item.status IN('started','stoppage') THEN minutes:=greatest(minutes,item.original_minutes); END IF;
  proposed_end:=public.workshop_add_operational_minutes(item.original_start,minutes);
  UPDATE pg_temp.pdc_tune_cascade_plan SET minutes=plan.minutes,
   root_change=(plan.minutes IS DISTINCT FROM item.original_minutes OR proposed_end IS DISTINCT FROM item.original_end)
   WHERE booking_id=item.booking_id;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan WHERE root_change) THEN
  RETURN jsonb_build_object('bookings',receipt,'changed_count',0,'extended_count',0,'moved_count',0,'buffer_minutes',300);
 END IF;
 -- Dependency order is the original queue order. Every move is to the right,
 -- so a later bay or vehicle job can never jump ahead of its predecessor.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan ORDER BY ordinal LOOP
  root_change:=item.root_change;
  SELECT max(greatest(x.final_end,CASE WHEN x.status IN('started','stoppage') THEN date_trunc('minute',clock_timestamp()) ELSE x.final_end END)
      +CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '5 hours' ELSE interval '0 minutes' END) INTO blocked_until
   FROM pg_temp.pdc_tune_cascade_plan x WHERE x.ordinal<item.ordinal AND x.changed
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  IF NOT root_change AND coalesce(blocked_until,item.original_start)<=item.original_start THEN CONTINUE; END IF;
  IF item.bay_id IS NULL THEN
   RAISE EXCEPTION 'A later job is queued without a bay. Review that booking before approving this change.'
    USING DETAIL='operation_schedule_queued_without_bay';
  END IF;
  proposed_start:=greatest(item.original_start,coalesce(blocked_until,item.original_start));
  IF item.status IN('started','stoppage') AND proposed_start>item.original_start THEN
   RAISE EXCEPTION 'A later job is already in progress or stopped. Resolve that booking before approving this change.'
    USING DETAIL='operation_schedule_protected_active_booking';
  END IF;
  minutes:=item.minutes;
  IF item.status IN('queued','planned') THEN
   minutes:=coalesce(public.workshop_booking_capacity_duration_minutes(item.booking_id,item.vehicle_id,item.stage_id,item.bay_id),minutes);
   proposed_start:=greatest(proposed_start,date_trunc('minute',clock_timestamp())+interval '1 minute');
  END IF;
  -- Once a booking moves, also respect unchanged predecessors and technician
  -- reservations. Unrelated jobs with no incoming change are left untouched.
  SELECT max(greatest(x.final_end,CASE WHEN x.status IN('started','stoppage') THEN date_trunc('minute',clock_timestamp()) ELSE x.final_end END)
     +CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '5 hours' ELSE interval '0 minutes' END) INTO blocked_until
   FROM pg_temp.pdc_tune_cascade_plan x WHERE x.ordinal<item.ordinal
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  proposed_start:=greatest(proposed_start,coalesce(blocked_until,proposed_start));
  IF item.status IN('started','stoppage') AND proposed_start>item.original_start THEN
   RAISE EXCEPTION 'The current job cannot be moved automatically. Resolve its earlier booking conflict first.'
    USING DETAIL='operation_schedule_protected_active_booking';
  END IF;
  n:=0;
  LOOP
   n:=n+1;
   IF n>1000 THEN RAISE EXCEPTION 'No safe workshop slot was found for this change.'
    USING DETAIL='operation_schedule_no_slot'; END IF;
   IF item.status IN('queued','planned') THEN
    proposed_start:=public.workshop_admin_next_operational_minute(proposed_start);
    IF proposed_start IS NULL THEN RAISE EXCEPTION 'No open workshop time was found for this change.'
     USING DETAIL='operation_schedule_calendar_unavailable'; END IF;
   END IF;
   proposed_end:=public.workshop_add_operational_minutes(proposed_start,minutes);
   SELECT max(a.scheduled_end_at) INTO blocked_until FROM public.workshop_admin_blocks a
    WHERE a.deleted_at IS NULL AND a.bay_id=item.bay_id
     AND a.scheduled_start_at<proposed_end AND a.scheduled_end_at>proposed_start;
   SELECT max(d::date) INTO unavailable_date FROM generate_series(
    (proposed_start AT TIME ZONE 'Australia/Perth')::date::timestamp,
    ((proposed_end-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
    WHERE public.pdc_sublet_away_on_date(item.vehicle_id,d::date);
   IF unavailable_date IS NOT NULL THEN
    blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
   END IF;
   FOREACH technician IN ARRAY item.technicians LOOP
    unavailable_date:=public.workshop_technician_leave_date(technician,proposed_start,proposed_end);
    IF unavailable_date IS NOT NULL THEN
     blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
    END IF;
   END LOOP;
   EXIT WHEN blocked_until IS NULL;
   IF item.status IN('started','stoppage') THEN
    RAISE EXCEPTION 'The longer current job conflicts with an Admin block, Sublet visit or technician leave. Resolve that conflict before approving.'
     USING DETAIL='operation_schedule_protected_reservation';
   END IF;
   proposed_start:=greatest(proposed_start+interval '1 minute',blocked_until);
  END LOOP;
  changed:=proposed_start IS DISTINCT FROM item.original_start OR proposed_end IS DISTINCT FROM item.original_end OR minutes IS DISTINCT FROM item.original_minutes;
  UPDATE pg_temp.pdc_tune_cascade_plan SET final_start=proposed_start,final_end=proposed_end,
   minutes=plan.minutes,changed=plan.changed
   WHERE booking_id=item.booking_id;
 END LOOP;
 -- Move downstream jobs first, vacating intervals before earlier extensions.
 -- Immediate bay, vehicle and technician exclusion constraints remain enabled.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan WHERE changed ORDER BY ordinal DESC LOOP
  old_snapshot:=public.workshop_booking_snapshot(item.booking_id);
  UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
   default_duration_minutes=item.minutes,version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
   WHERE id=item.booking_id AND version=item.version AND status::text=item.status AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'A booking changed while this operation was being approved. Refresh and try again.'
   USING ERRCODE='40001',DETAIL='operation_schedule_changed'; END IF;
  -- Retain every assignment and its identity, including secondary technicians.
  UPDATE public.workshop_booking_assignments SET scheduled_start_at=item.final_start,
   scheduled_end_at=item.final_end,updated_at=clock_timestamp()
   WHERE booking_id=item.booking_id AND released_at IS NULL;
  new_snapshot:=public.workshop_booking_snapshot(item.booking_id);
  IF (SELECT to_jsonb(b)-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes']
      FROM public.workshop_bookings b WHERE id=item.booking_id)
    IS DISTINCT FROM item.before_row-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes'] THEN
   RAISE EXCEPTION 'Operation approval changed protected booking details.' USING DETAIL='operation_schedule_readback_mismatch';
  END IF;
  PERFORM public.workshop_write_history(item.booking_id,'operation_change_schedule_updated',old_snapshot,new_snapshot,
   jsonb_build_object('source','approved_tune_operation_change','change_id',p_change_id,
    'approved_vehicle_id',p_vehicle_id,'buffer_minutes',300,'previous_duration_minutes',item.original_minutes,
    'duration_minutes',item.minutes,'moved',item.final_start IS DISTINCT FROM item.original_start));
 END LOOP;
 -- Check the final vehicle handovers against the calculated plan. General
 -- planner validation separately verifies bay, technician, ETA and calendar.
 IF EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan a JOIN pg_temp.pdc_tune_cascade_plan b
   ON a.vehicle_id=b.vehicle_id AND a.ordinal<b.ordinal
   WHERE (a.changed OR b.changed) AND a.final_end+interval '5 hours'>b.final_start) THEN
  RAISE EXCEPTION 'The vehicle needs five hours between workshop jobs.' USING DETAIL='operation_schedule_handover_conflict';
 END IF;
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan WHERE changed LOOP
  FOREACH technician IN ARRAY item.technicians LOOP
   IF public.workshop_find_technician_conflict(item.booking_id,technician,item.final_start,item.final_end) IS NOT NULL THEN
    RAISE EXCEPTION 'The revised job conflicts with another technician booking.' USING DETAIL='operation_schedule_technician_conflict';
   END IF;
  END LOOP;
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',x.booking_id,'vehicle_id',x.vehicle_id,
  'stock_number',coalesce(nullif(btrim(v.stock_number),''),'—'),'stage_code',x.stage_code,'bay_id',x.bay_id,'bay_name',coalesce(nullif(btrim(b.display_name),''),'Bay '||b.bay_number),
  'previous_start_at',x.original_start,'previous_end_at',x.original_end,'start_at',x.final_start,'end_at',x.final_end,
  'previous_estimated_hours',x.original_minutes::numeric/60,'estimated_hours',x.minutes::numeric/60,
  'status',x.status) ORDER BY x.ordinal),'[]') INTO receipt
 FROM pg_temp.pdc_tune_cascade_plan x JOIN public.vehicles v ON v.id=x.vehicle_id
 LEFT JOIN public.workshop_bays b ON b.id=x.bay_id WHERE x.changed;
 RETURN jsonb_build_object('bookings',receipt,'changed_count',jsonb_array_length(receipt),
  'extended_count',(SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan WHERE changed AND minutes>original_minutes),
  'moved_count',(SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan WHERE changed AND final_start IS DISTINCT FROM original_start),
  'buffer_minutes',300);
END $function$
;

-- Existing permissions and wrapper contracts retained: workshop_sync_vehicle_stage_booking_duration(uuid,text,text)
CREATE OR REPLACE FUNCTION public.workshop_sync_vehicle_stage_booking_duration(p_vehicle_id uuid, p_stage_code text, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 v_stage text:=public.workshop_canonical_stage_code(p_stage_code);v_booking public.workshop_bookings%rowtype;
 v_minutes integer;v_end timestamptz;v_before jsonb;v_after jsonb;v_count integer:=0;
 v_increment integer;v_from timestamptz;v_cascade jsonb;
 v_original_claims text:=current_setting('request.jwt.claims',true);v_initiator_uid uuid:=auth.uid();v_initiator_email text:=public.current_actor_email();
 v_system_actor uuid;v_system_email text;
BEGIN
 IF p_vehicle_id IS NULL OR v_stage IS NULL THEN RETURN 0;END IF;
 SELECT r.auth_user_id,r.email INTO v_system_actor,v_system_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND r.role='administrator' AND r.auth_user_id IS NOT NULL ORDER BY r.created_at,r.id LIMIT 1;
 IF v_system_actor IS NULL THEN RAISE EXCEPTION 'PDC_156_WORKSHOP_SYSTEM_ACTOR_MISSING' USING errcode='55000';END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_system_actor,'email',v_system_email,'role','authenticated')::text,true);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:estimate-sync:'||p_vehicle_id::text,0));
 LOCK TABLE public.workshop_bookings,public.workshop_booking_assignments IN EXCLUSIVE MODE;
 FOR v_booking IN SELECT b.* FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status::text IN('queued','planned','started','stoppage')
    AND public.workshop_canonical_stage_code(s.code)=v_stage ORDER BY b.scheduled_start_at,b.id FOR UPDATE OF b LOOP
  v_minutes:=CASE WHEN v_booking.status IN('queued','planned') THEN coalesce(public.workshop_booking_capacity_duration_minutes(v_booking.id,p_vehicle_id,v_booking.stage_id,v_booking.bay_id),v_booking.default_duration_minutes) ELSE coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,v_booking.stage_id),60) END;
  v_end:=public.workshop_add_operational_minutes(v_booking.scheduled_start_at,v_minutes);
  IF v_booking.default_duration_minutes IS DISTINCT FROM v_minutes OR v_booking.scheduled_end_at IS DISTINCT FROM v_end THEN
   v_before:=public.workshop_booking_snapshot(v_booking.id);
   IF v_booking.status::text<>'planned' THEN
    INSERT INTO public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
    VALUES(v_booking.id,'operation_estimate_duration_reconcile_deferred',v_before,v_before,
     jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
      'proposed_duration_minutes',v_minutes,'reason','protected_non_planned_booking_window','protected_status',v_booking.status::text,
      'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email),v_system_actor,v_system_email);
   ELSE
    SELECT coalesce((value#>>'{}')::integer,15) INTO v_increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
    v_increment:=greatest(1,coalesce(v_increment,15));
    v_from:=CASE WHEN v_booking.scheduled_start_at>clock_timestamp() THEN v_booking.scheduled_start_at ELSE
      date_trunc('minute',clock_timestamp())+
      (v_increment-mod((extract(epoch from clock_timestamp())/60)::bigint,v_increment)) * interval '1 minute' END;
    v_cascade:=public.workshop_admin_repack_planned(v_booking.bay_id,v_from,
      jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
       'operation_estimate_duration_cascade',true,'recover_overdue',v_booking.scheduled_start_at<=clock_timestamp(),
       'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email));
    v_count:=v_count+coalesce((v_cascade->>'shifted_count')::integer,0);
   END IF;
  END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RETURN v_count;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RAISE;
END $function$
;

-- Existing permissions and wrapper contracts retained: workshop_admin_repack_planned(uuid,timestamp with time zone,jsonb)
CREATE OR REPLACE FUNCTION public.workshop_admin_repack_planned(p_bay_id uuid, p_from timestamp with time zone, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_item record;
  v_start timestamptz;
  v_end timestamptz;
  v_cursor timestamptz:=p_from;
  v_block_end timestamptz;
  v_fixed_end timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_technician uuid;
  v_shifted jsonb:='[]'::jsonb;
  v_anchor_id uuid;
  v_anchor_start timestamptz;
  v_anchor_end timestamptz;
  v_guard integer;
BEGIN
  v_anchor_id:=CASE WHEN coalesce(p_metadata->>'admin_block_id','')~*'^[0-9a-f-]{36}$' THEN (p_metadata->>'admin_block_id')::uuid END;
  SELECT scheduled_start_at,scheduled_end_at INTO v_anchor_start,v_anchor_end
  FROM public.workshop_admin_blocks WHERE id=v_anchor_id AND deleted_at IS NULL;

  IF coalesce((p_metadata->>'compact_released')::boolean,false) AND v_anchor_end IS NOT NULL THEN v_cursor:=greatest(v_cursor,v_anchor_end); END IF;

  DROP TABLE IF EXISTS pg_temp.workshop_admin_repack_items;
  CREATE TEMP TABLE workshop_admin_repack_items(
    kind text NOT NULL,
    id uuid NOT NULL,
    original_start timestamptz NOT NULL,
    original_end timestamptz NOT NULL,
    duration_minutes integer NOT NULL,
    row_version integer NOT NULL,
    final_start timestamptz,
    final_end timestamptz,
    PRIMARY KEY(kind,id)
  ) ON COMMIT DROP;

  INSERT INTO workshop_admin_repack_items(kind,id,original_start,original_end,duration_minutes,row_version)
  SELECT 'admin',a.id,a.scheduled_start_at,a.scheduled_end_at,a.duration_minutes,a.version
  FROM public.workshop_admin_blocks a
  WHERE a.bay_id=p_bay_id AND a.deleted_at IS NULL AND a.id IS DISTINCT FROM v_anchor_id
    AND (a.scheduled_end_at>p_from or (coalesce((p_metadata->>'recover_overdue')::boolean,false) and a.scheduled_start_at<p_from))
  ORDER BY a.scheduled_start_at,a.id
  FOR UPDATE;
  INSERT INTO workshop_admin_repack_items(kind,id,original_start,original_end,duration_minutes,row_version)
  SELECT 'booking',b.id,b.scheduled_start_at,b.scheduled_end_at,
    coalesce(public.workshop_booking_capacity_duration_minutes(b.id,b.vehicle_id,b.stage_id,b.bay_id),b.default_duration_minutes),b.version
  FROM public.workshop_bookings b
  WHERE b.bay_id=p_bay_id AND b.status='planned' AND b.deleted_at IS NULL
    AND (b.scheduled_end_at>p_from OR (coalesce((p_metadata->>'recover_overdue')::boolean,false) AND b.scheduled_start_at<p_from))
  ORDER BY b.scheduled_start_at,b.id
  FOR UPDATE;

  FOR v_item IN
    SELECT * FROM workshop_admin_repack_items ORDER BY original_start,kind,id
  LOOP
    v_start:=case when coalesce((p_metadata->>'compact_released')::boolean,false) then v_cursor else greatest(v_item.original_start,v_cursor) end;
    v_guard:=0;
    LOOP
      v_guard:=v_guard+1;
      IF v_guard>1000 THEN RAISE EXCEPTION 'Workshop Admin cascade guard exceeded' USING errcode='54000'; END IF;
      v_end:=public.workshop_add_operational_minutes(v_start,v_item.duration_minutes);
      SELECT max(b.scheduled_end_at) INTO v_fixed_end
      FROM public.workshop_bookings b
      WHERE b.bay_id=p_bay_id AND b.deleted_at IS NULL
        AND b.status::text IN ('queued','started','stoppage')
        AND b.scheduled_start_at<v_end AND b.scheduled_end_at>v_start;
      SELECT max(o.obstacle_end) INTO v_block_end
      FROM (
        SELECT v_anchor_end obstacle_end,v_anchor_start obstacle_start
        WHERE v_anchor_id IS NOT NULL AND v_anchor_end IS NOT NULL
        UNION ALL
        SELECT x.final_end,x.final_start
        FROM workshop_admin_repack_items x
        WHERE x.kind='admin' AND x.final_start IS NOT NULL
      ) o
      WHERE o.obstacle_start<v_end AND o.obstacle_end>v_start;
      EXIT WHEN v_fixed_end IS NULL AND v_block_end IS NULL;
      v_start:=greatest(v_start,coalesce(v_fixed_end,v_start),coalesce(v_block_end,v_start));
    END LOOP;
    UPDATE workshop_admin_repack_items
    SET final_start=v_start,final_end=v_end
    WHERE kind=v_item.kind AND id=v_item.id;
    v_cursor:=greatest(v_cursor,v_end);
  END LOOP;

  -- Rightward moves vacate from the back; leftward moves vacate from the front. Rows are
  -- written. Every row was locked and its original version is checked again.
  FOR v_item IN
    SELECT * FROM workshop_admin_repack_items
    WHERE final_start IS DISTINCT FROM original_start OR final_end IS DISTINCT FROM original_end
    ORDER BY CASE WHEN final_start<original_start THEN 0 ELSE 1 END,
    CASE WHEN final_start<original_start THEN original_start END ASC,
    CASE WHEN final_start>=original_start THEN original_start END DESC,kind,id
  LOOP
    IF v_item.kind='booking' THEN
      v_before:=public.workshop_booking_snapshot(v_item.id);
      UPDATE public.workshop_bookings
      SET scheduled_start_at=v_item.final_start,scheduled_end_at=v_item.final_end,
          default_duration_minutes=v_item.duration_minutes,
          updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1
      WHERE id=v_item.id AND status='planned' AND deleted_at IS NULL AND version=v_item.row_version;
      IF NOT FOUND THEN RAISE EXCEPTION 'Concurrent planned booking version changed' USING errcode='40001'; END IF;
      SELECT a.technician_id INTO v_technician
      FROM public.workshop_booking_assignments a
      WHERE a.booking_id=v_item.id AND a.released_at IS NULL
      ORDER BY case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at DESC LIMIT 1;
      PERFORM public.workshop_upsert_primary_assignment(v_item.id,v_technician,v_item.final_start,v_item.final_end,'admin_block_cascaded');
      v_after:=public.workshop_booking_snapshot(v_item.id);
      PERFORM public.workshop_write_history(v_item.id,'admin_block_cascaded',v_before,v_after,
        coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_cascade',true));
    ELSE
      v_before:=public.workshop_admin_block_snapshot(v_item.id);
      UPDATE public.workshop_admin_blocks
      SET scheduled_start_at=v_item.final_start,scheduled_end_at=v_item.final_end,
          updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1
      WHERE id=v_item.id AND deleted_at IS NULL AND version=v_item.row_version;
      IF NOT FOUND THEN RAISE EXCEPTION 'Concurrent Admin block version changed' USING errcode='40001'; END IF;
      v_after:=public.workshop_admin_block_snapshot(v_item.id);
      INSERT INTO public.workshop_admin_block_history(
        block_id,event_type,block_version,before_data,after_data,metadata,actor_user_id,actor_email
      ) VALUES(v_item.id,'moved',(v_after->>'version')::integer,v_before,v_after,
        coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_cascade',true),auth.uid(),public.current_actor_email());
    END IF;
    v_shifted:=v_shifted||jsonb_build_array(jsonb_build_object(
      'kind',v_item.kind,'id',v_item.id,'from',v_item.original_start,'to',v_item.final_start,
      'duration_minutes',v_item.duration_minutes,'version_before',v_item.row_version,
      'version_after',v_item.row_version+1
    ));
  END LOOP;
  RETURN jsonb_build_object(
    'shifted_items',v_shifted,
    'shifted_count',jsonb_array_length(v_shifted),
    'shifted_booking_ids',coalesce((SELECT jsonb_agg(id) FROM jsonb_to_recordset(v_shifted) AS x(kind text,id uuid) WHERE kind='booking'),'[]'::jsonb),
    'shifted_admin_block_ids',coalesce((SELECT jsonb_agg(id) FROM jsonb_to_recordset(v_shifted) AS x(kind text,id uuid) WHERE kind='admin'),'[]'::jsonb)
  );
END $function$
;

-- Existing permissions and wrapper contracts retained: set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)
CREATE OR REPLACE FUNCTION public.set_workshop_stage_estimated_minutes_407(p_vehicle_id uuid, p_expected_vehicle_version integer, p_booking_id uuid, p_expected_booking_version integer, p_stage_code text, p_total_minutes integer, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_stage text:=public.workshop_canonical_stage_code(p_stage_code); v_stage_id uuid; v_bay_number integer;
  v_vehicle public.vehicles%rowtype; v_booking public.workshop_bookings%rowtype;
  v_adjustment public.vehicle_workshop_line_adjustments%rowtype; v_before_adjustment jsonb; v_after_adjustment jsonb;
  v_line_key text; v_current_minutes integer; v_manual_minutes integer:=0; v_base_minutes integer; v_delta_minutes integer; v_delta_hours numeric;
  v_authoritative_minutes integer; v_capacity_minutes integer; v_cascade jsonb; v_request jsonb; v_request_sha text; v_response jsonb; v_existing public.pdc_workshop_stage_estimate_receipts_407%rowtype; v_receipt_id uuid;
BEGIN
  IF v_actor IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_booking_id IS NULL OR p_expected_booking_version IS NULL OR v_stage IS NULL OR p_total_minutes IS NULL OR p_total_minutes NOT BETWEEN 1 AND 59999 OR p_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_stage_estimate_input');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  v_request:=jsonb_build_object('contract','pdc-workshop-stage-estimated-minutes-407','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'booking_id',p_booking_id,'expected_booking_version',p_expected_booking_version,'stage_code',v_stage,'total_minutes',p_total_minutes,'idempotency_key',p_idempotency_key,'actor_id',v_actor);
  v_request_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-407-stage-estimate-actor:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_existing FROM public.pdc_workshop_stage_estimate_receipts_407 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing.request_sha256<>v_request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN v_existing.response||jsonb_build_object('replay',true);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-407-stage-estimate-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF v_vehicle.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('current_version',v_vehicle.version)); END IF;
  SELECT id INTO v_stage_id FROM public.workshop_stages WHERE code=v_stage AND active FOR SHARE;
  IF v_stage_id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','stage_not_found'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=p_vehicle_id AND wi.required AND NOT wi.completed AND public.workshop_canonical_stage_code(wi.work_key)=v_stage FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','canonical_requirement_missing_or_completed');
  END IF;
  SELECT * INTO v_booking FROM public.workshop_bookings WHERE id=p_booking_id AND vehicle_id=p_vehicle_id AND stage_id=v_stage_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR v_booking.status::text NOT IN('queued','planned') THEN RETURN jsonb_build_object('ok',false,'code','booking_not_editable'); END IF;
  IF v_booking.version<>p_expected_booking_version THEN RETURN jsonb_build_object('ok',false,'code','version_conflict','data',jsonb_build_object('current_version',v_booking.version)); END IF;
  SELECT bay_number INTO v_bay_number FROM public.workshop_bays WHERE id=v_booking.bay_id AND is_active FOR SHARE;
  IF v_bay_number IS NULL THEN RETURN jsonb_build_object('ok',false,'code','bay_inactive_or_wrong_station'); END IF;

  v_line_key:='manual:planner-stage:'||v_stage;
  SELECT * INTO v_adjustment FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=p_vehicle_id AND line_key=v_line_key FOR UPDATE;
  IF FOUND AND v_adjustment.active THEN v_manual_minutes:=round(coalesce(v_adjustment.estimated_hours,0)*60)::integer; END IF;
  v_current_minutes:=coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,v_stage_id),0);
  v_base_minutes:=greatest(0,v_current_minutes-v_manual_minutes);
  IF p_total_minutes<v_base_minutes THEN
    RETURN jsonb_build_object('ok',false,'code','estimated_minutes_below_authenticated_work','data',jsonb_build_object('minimum_minutes',v_base_minutes));
  END IF;
  v_delta_minutes:=p_total_minutes-v_base_minutes;
  v_delta_hours:=round(v_delta_minutes::numeric/60,2);
  PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',p_vehicle_id::text,true);
  PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','407',true);
  PERFORM set_config('pdc.defer_workshop_required_work_reconcile','407',true);
  v_before_adjustment:=CASE WHEN v_adjustment.adjustment_id IS NULL THEN NULL ELSE to_jsonb(v_adjustment) END;
  IF v_delta_minutes=0 THEN
    IF v_adjustment.adjustment_id IS NOT NULL AND v_adjustment.active THEN
      UPDATE public.vehicle_workshop_line_adjustments SET active=false,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE adjustment_id=v_adjustment.adjustment_id RETURNING * INTO v_adjustment;
    END IF;
  ELSIF v_adjustment.adjustment_id IS NULL THEN
    INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,active,version,created_by,updated_by)
    VALUES(p_vehicle_id,v_line_key,'manual',v_stage,'Planner stage time adjustment',v_delta_hours,'manual_operator',true,1,v_actor,v_actor) RETURNING * INTO v_adjustment;
  ELSE
    UPDATE public.vehicle_workshop_line_adjustments SET stage_code=v_stage,description='Planner stage time adjustment',estimated_hours=v_delta_hours,correction_origin='manual_operator',active=true,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE adjustment_id=v_adjustment.adjustment_id RETURNING * INTO v_adjustment;
  END IF;
  v_after_adjustment:=CASE WHEN v_adjustment.adjustment_id IS NULL THEN NULL ELSE to_jsonb(v_adjustment) END;
  PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','',true);
  PERFORM set_config('pdc.defer_workshop_required_work_reconcile','',true);
  v_authoritative_minutes:=coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,v_stage_id),0);
  IF v_authoritative_minutes<>p_total_minutes THEN RAISE EXCEPTION 'PDC_407_CANONICAL_MINUTE_RECONCILIATION_FAILED expected %, got %',p_total_minutes,v_authoritative_minutes USING errcode='55000'; END IF;

  v_capacity_minutes:=public.workshop_booking_capacity_duration_minutes(v_booking.id,p_vehicle_id,v_stage_id,v_booking.bay_id);
  v_cascade:=public.cascade_workshop_schedule(
    'extend',
    p_booking_id,p_expected_booking_version,v_stage,v_bay_number,v_booking.scheduled_start_at,v_capacity_minutes,NULL,
    greatest(0,v_capacity_minutes-v_booking.default_duration_minutes),NULL,
    jsonb_build_object('source','stage_estimated_minutes_407','request_id',p_idempotency_key,'canonical_minutes',p_total_minutes,'base_authenticated_minutes',v_base_minutes,'manual_delta_minutes',v_delta_minutes));
  IF coalesce((v_cascade->>'ok')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'PDC_407_CASCADE_FAILED: %',v_cascade USING errcode='55000'; END IF;
  SELECT * INTO v_booking FROM public.workshop_bookings WHERE id=p_booking_id;
  IF v_booking.default_duration_minutes<>v_capacity_minutes THEN RAISE EXCEPTION 'PDC_407_BOOKING_READBACK_FAILED' USING errcode='55000'; END IF;
  v_receipt_id:=extensions.uuid_generate_v5('40700000-0000-5000-8000-000000000407'::uuid,'stage-estimate:'||v_actor::text||':'||p_idempotency_key::text);
  v_response:=jsonb_build_object('ok',true,'code','workshop_stage_estimated_minutes_saved','replay',false,'receipt_id',v_receipt_id,'vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle.version,'booking_id',p_booking_id,'booking_version',v_booking.version,'stage_code',v_stage,'base_authenticated_minutes',v_base_minutes,'manual_delta_minutes',v_delta_minutes,'total_minutes',p_total_minutes,'adjustment',v_after_adjustment,'cascade',v_cascade);
  INSERT INTO public.pdc_workshop_stage_estimate_receipts_407(receipt_id,actor_id,actor_email,vehicle_id,booking_id,stage_code,total_minutes,idempotency_key,request_sha256,request_payload,response)
  VALUES(v_receipt_id,v_actor,v_email,p_vehicle_id,p_booking_id,v_stage,p_total_minutes,p_idempotency_key,v_request_sha,v_request,v_response);
  IF v_adjustment.adjustment_id IS NOT NULL THEN
    INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    VALUES(CASE WHEN v_before_adjustment IS NULL THEN 'insert'::public.audit_action ELSE 'update'::public.audit_action END,'vehicle_workshop_line_adjustments',v_adjustment.adjustment_id,p_vehicle_id,v_actor,v_email,v_before_adjustment,v_after_adjustment,jsonb_build_object('action','set_workshop_stage_estimated_minutes_407','receipt_id',v_receipt_id,'stage_code',v_stage,'base_authenticated_minutes',v_base_minutes,'manual_delta_minutes',v_delta_minutes,'total_minutes',p_total_minutes,'booking_id',p_booking_id));
  END IF;
  RETURN v_response;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','',true);
  PERFORM set_config('pdc.defer_workshop_required_work_reconcile','',true);
  RAISE;
END $function$
;

-- Existing permissions and wrapper contracts retained: book_all_vehicle_stations(uuid,integer)
CREATE OR REPLACE FUNCTION public.book_all_vehicle_stations(p_vehicle_id uuid, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v public.vehicles%rowtype; st record; bay record; item jsonb; result jsonb;
 pending jsonb:='[]'; booked jsonb:='[]'; skipped jsonb:='[]';
 minutes integer; best_minutes integer; increment integer; current_version integer;
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
   minutes:=public.workshop_capacity_duration_minutes((item->>'minutes')::numeric,bay.id);
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
    best_start:=candidate; best_end:=finish; best_bay:=bay.bay_number; best_minutes:=minutes; EXIT;
   END LOOP;
  END LOOP;
  IF best_start IS NULL THEN RAISE EXCEPTION 'No available bay was found for % within the next 300 days.',item->>'name' USING DETAIL='no_available_slot'; END IF;
  SELECT version INTO current_version FROM public.vehicles WHERE id=v.id;
  result:=public.schedule_vehicle_work(v.id,current_version,item->>'code',best_bay,best_start,best_minutes,NULL,NULL,jsonb_build_object('source','book_all_stations','buffer_minutes',300));
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Could not book % (%). Refresh and try again.',item->>'name',coalesce(result->>'error','schedule rejected') USING DETAIL='booking_rejected'; END IF;
  booked:=booked||jsonb_build_array(jsonb_build_object('stage',item->>'name','bay',best_bay,'start_at',best_start,'end_at',best_end,'booking_id',coalesce(result#>>'{booking,booking_id}',result#>>'{booking,id}')));
 END LOOP;
 RETURN jsonb_build_object('ok',true,'bookings',booked,'skipped',skipped,'buffer_minutes',300);
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS failure=MESSAGE_TEXT,failure_code=PG_EXCEPTION_DETAIL;
 RETURN jsonb_build_object('ok',false,'error',coalesce(nullif(failure_code,''),SQLSTATE),'message',failure||' No new bookings were saved.');
END $function$
;

-- Existing permissions and wrapper contracts retained: workshop_create_booking(uuid,text,integer,timestamp with time zone,integer,uuid,jsonb)
CREATE OR REPLACE FUNCTION public.workshop_create_booking(p_vehicle_id uuid, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT 180, p_technician_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_stage_id uuid;
  v_bay_id uuid;
  v_booking_id uuid;
  v_conflict_id uuid;
  v_history_id uuid;
  v_end timestamptz;
  v_after jsonb;
  v_leave_date date;
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  p_duration_minutes := coalesce(public.workshop_booking_capacity_duration_minutes(NULL,p_vehicle_id,v_stage_id,v_bay_id),p_duration_minutes);
  v_end := public.workshop_add_operational_minutes(p_scheduled_start_at, p_duration_minutes);

  if p_technician_id is not null then
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id) then
      return jsonb_build_object('ok', false, 'error', 'technician_not_found', 'technician_id', p_technician_id);
    end if;
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id and active) then
      return jsonb_build_object('ok', false, 'error', 'technician_inactive', 'technician_id', p_technician_id);
    end if;
    select public.workshop_technician_leave_date(p_technician_id, p_scheduled_start_at, v_end) into v_leave_date;
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'technician_id', p_technician_id, 'date', v_leave_date);
    end if;
  end if;

  perform public.workshop_lock_resources(v_bay_id, p_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(null, v_bay_id, p_scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;

  if p_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(null, p_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  insert into public.workshop_bookings (
    vehicle_id,
    stage_id,
    bay_id,
    status,
    scheduled_start_at,
    scheduled_end_at,
    default_duration_minutes,
    created_by,
    updated_by
  ) values (
    p_vehicle_id,
    v_stage_id,
    v_bay_id,
    'planned',
    p_scheduled_start_at,
    v_end,
    p_duration_minutes,
    auth.uid(),
    auth.uid()
  ) returning id into v_booking_id;

  perform public.workshop_upsert_primary_assignment(v_booking_id, p_technician_id, p_scheduled_start_at, v_end, 'created');

  v_after := public.workshop_booking_snapshot(v_booking_id);
  v_history_id := public.workshop_write_history(v_booking_id, 'created', null, v_after, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after, 'history_id', v_history_id);
end;
$function$
;

-- Existing permissions and wrapper contracts retained: workshop_booking_snapshot(uuid)
CREATE OR REPLACE FUNCTION public.workshop_booking_snapshot(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with active_assignment as (
    select a.booking_id, a.technician_id, t.name as technician_name, a.assignment_type
    from public.workshop_booking_assignments a
    join public.workshop_technicians t on t.id = a.technician_id
    where a.booking_id = p_booking_id
      and a.released_at is null
    order by case when a.assignment_type = 'primary' then 0 else 1 end, a.assigned_at desc
    limit 1
  )
  select jsonb_build_object(
    'booking_id', b.id,
    'vehicle_id', b.vehicle_id,
    'vehicle', jsonb_build_object(
      'permanent_vehicle_id', v.permanent_vehicle_id,
      'stock_number', v.stock_number,
      'job_card_number', v.job_card_number,
      'customer_name', v.customer_name,
      'model', v.model
    ),
    'stage', jsonb_build_object(
      'id', s.id,
      'code', s.code,
      'display_name', s.display_name,
      'sort_order', s.sort_order
    ),
    'bay', case when bay.id is null then null else jsonb_build_object(
      'id', bay.id,
      'bay_number', bay.bay_number,
      'code', bay.code,
      'display_name', bay.display_name,
      'is_sublet_row', bay.is_sublet_row
    ) end,
    'status', b.status,
    'scheduled_start_at', b.scheduled_start_at,
    'scheduled_end_at', b.scheduled_end_at,
    'default_duration_minutes', b.default_duration_minutes,
    'capacity_base_minutes',coalesce(b.capacity_base_minutes,b.default_duration_minutes::numeric),
    'capacity_efficiency_percent',coalesce(b.capacity_efficiency_percent,100),
    'capacity_estimate_minutes',b.capacity_estimate_minutes,
    'actual_start_at', b.actual_start_at,
    'actual_end_at', b.actual_end_at,
    'actual_duration_minutes', b.actual_duration_minutes,
    'stoppage_reason', b.stoppage_reason,
    'stoppage_started_at', b.stoppage_started_at,
    'stoppage_accumulated_minutes', b.stoppage_accumulated_minutes,
    'returned_to_queue_at', b.returned_to_queue_at,
    'deleted_at', b.deleted_at,
    'deleted_reason', b.deleted_reason,
    'version', b.version,
    'assignment', case when aa.technician_id is null then null else jsonb_build_object(
      'technician_id', aa.technician_id,
      'technician_name', aa.technician_name,
      'assignment_type', aa.assignment_type
    ) end,
    'updated_at', b.updated_at,
    'created_at', b.created_at
  )
  from public.workshop_bookings b
  join public.vehicles v on v.id = b.vehicle_id
  join public.workshop_stages s on s.id = b.stage_id
  left join public.workshop_bays bay on bay.id = b.bay_id
  left join active_assignment aa on aa.booking_id = b.id
  where b.id = p_booking_id;
$function$
;

-- Existing permissions and wrapper contracts retained: workshop_overlay_canonical_booking_fields_397(jsonb)
CREATE OR REPLACE FUNCTION public.workshop_overlay_canonical_booking_fields_397(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_bookings jsonb;
BEGIN
  IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot->'bookings') IS DISTINCT FROM 'array' THEN
    RETURN p_snapshot;
  END IF;

  SELECT coalesce(jsonb_agg(
    CASE WHEN b.id IS NULL THEN item.booking ELSE item.booking||jsonb_build_object(
      'scheduled_start_at',b.scheduled_start_at,
      'scheduled_end_at',b.scheduled_end_at,
      'default_duration_minutes',b.default_duration_minutes,
      'capacity_base_minutes',coalesce(b.capacity_base_minutes,b.default_duration_minutes::numeric),
    'capacity_efficiency_percent',coalesce(b.capacity_efficiency_percent,100),
    'capacity_estimate_minutes',b.capacity_estimate_minutes,
      'status',b.status,
      'version',b.version,
      'actual_start_at',b.actual_start_at,
      'actual_end_at',b.actual_end_at,
      'stoppage_reason',b.stoppage_reason,
      'stoppage_started_at',b.stoppage_started_at,
      'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes
    ) END ORDER BY item.ordinality),'[]'::jsonb)
  INTO v_bookings
  FROM jsonb_array_elements(p_snapshot->'bookings') WITH ORDINALITY AS item(booking,ordinality)
  LEFT JOIN public.workshop_bookings b
    ON b.id=CASE
      WHEN coalesce(item.booking->>'booking_id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'booking_id')::uuid
      WHEN coalesce(item.booking->>'id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'id')::uuid
    END;

  RETURN jsonb_set(p_snapshot,'{bookings}',v_bookings,true);
END $function$
;

-- Existing permissions and wrapper contracts retained: workshop_resize_booking(uuid,integer,integer,jsonb)
CREATE OR REPLACE FUNCTION public.workshop_resize_booking(p_booking_id uuid, p_expected_version integer, p_duration_minutes integer, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_booking public.workshop_bookings%rowtype;
  v_technician_id uuid;
  v_conflict_id uuid;
  v_end timestamptz;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
  v_leave_date date;
  v_capacity_context text:=current_setting('pdc.workshop_capacity_manual',true);
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;
  perform 1 from public.vehicles where id=v_booking.vehicle_id for update;

  select technician_id into v_technician_id
  from public.workshop_booking_assignments
  where booking_id = p_booking_id and released_at is null
  order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc
  limit 1;

  v_end := public.workshop_add_operational_minutes(v_booking.scheduled_start_at, p_duration_minutes);
  perform public.workshop_lock_resources(v_booking.bay_id, v_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(p_booking_id, v_booking.bay_id, v_booking.scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;
  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, v_booking.scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  if v_technician_id is not null then
    v_leave_date := public.workshop_technician_leave_date(v_technician_id, v_booking.scheduled_start_at, v_end);
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'date', v_leave_date, 'technician_id', v_technician_id);
    end if;
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  perform set_config('pdc.workshop_capacity_manual',jsonb_build_object('actor',auth.uid(),'booking',p_booking_id,'version',p_expected_version,'duration',p_duration_minutes)::text,true);
  update public.workshop_bookings
  set scheduled_end_at = v_end,
      default_duration_minutes = p_duration_minutes,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
  perform public.workshop_upsert_primary_assignment(p_booking_id, v_technician_id, v_booking.scheduled_start_at, v_end, 'resized');

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'resized', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
EXCEPTION WHEN OTHERS THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
 RAISE;
end;
$function$
;

-- Existing permissions and wrapper contracts retained: workshop_move_booking(uuid,integer,text,integer,timestamp with time zone,integer,jsonb)
CREATE OR REPLACE FUNCTION public.workshop_move_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT NULL::integer, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_before public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_stage_id uuid;
  v_bay_id uuid;
  v_technician_id uuid;
  v_conflict_id uuid;
  v_duration integer;
  v_end timestamptz;
  v_history_id uuid;
  v_leave_date date;
  v_capacity_context text:=current_setting('pdc.workshop_capacity_manual',true);
begin
  perform public.require_pdc_role('operator');

  select * into v_before
  from public.workshop_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_before.id, 'version_conflict'));
  end if;
  perform 1 from public.vehicles where id=v_before.vehicle_id for update;

  select technician_id into v_technician_id
  from public.workshop_booking_assignments
  where booking_id = p_booking_id and released_at is null
  order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc
  limit 1;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  v_duration := CASE WHEN v_before.status IN('queued','planned') AND (v_bay_id IS DISTINCT FROM v_before.bay_id OR v_stage_id IS DISTINCT FROM v_before.stage_id) THEN public.workshop_booking_capacity_duration_minutes(p_booking_id,v_before.vehicle_id,v_stage_id,v_bay_id) ELSE coalesce(p_duration_minutes,v_before.default_duration_minutes) END;
  if v_duration <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;
  v_end := public.workshop_add_operational_minutes(p_scheduled_start_at, v_duration);

  perform public.workshop_lock_resources(v_bay_id, v_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(p_booking_id, v_bay_id, p_scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;
  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  if v_technician_id is not null then
    v_leave_date := public.workshop_technician_leave_date(v_technician_id, p_scheduled_start_at, v_end);
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'date', v_leave_date, 'technician_id', v_technician_id);
    end if;
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  perform set_config('pdc.workshop_capacity_manual',jsonb_build_object('actor',auth.uid(),'booking',p_booking_id,'version',p_expected_version,'duration',v_duration)::text,true);
  update public.workshop_bookings
  set stage_id = v_stage_id,
      bay_id = v_bay_id,
      scheduled_start_at = p_scheduled_start_at,
      scheduled_end_at = v_end,
      default_duration_minutes = v_duration,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
  perform public.workshop_upsert_primary_assignment(p_booking_id, v_technician_id, p_scheduled_start_at, v_end, 'moved');

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'moved', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
EXCEPTION WHEN OTHERS THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
 RAISE;
end;
$function$
;

-- Existing permissions and wrapper contracts retained: cascade_workshop_schedule(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)
CREATE OR REPLACE FUNCTION public.cascade_workshop_schedule(p_operation text, p_target_id uuid, p_target_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid DEFAULT NULL::uuid, p_shift_minutes integer DEFAULT 0, p_override_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_vehicle_id uuid; v_capacity_context text:=current_setting('pdc.workshop_capacity_manual',true); v_capacity_result jsonb;
begin
  if lower(btrim(coalesce(p_operation,'')))='extend' then
    select vehicle_id into v_vehicle_id from public.workshop_bookings where id=p_target_id;
  else
    v_vehicle_id:=p_target_id;
  end if;
  if exists(
    select 1
    from public.pdc_overnight_synthetic_fleet_registry_363 r
    join public.vehicles v on v.id=v_vehicle_id
     and r.run_id='HERMES-TEST-RUN-20260824'
     and r.vehicle_id=v.id
     and v.stock_number=r.stock_number
     and v.customer_name=r.customer_name
     and v.job_card_number=r.job_card_number
     and v.vehicle_description=r.vehicle_description
     and v.source_system='hermes_overnight_synthetic'
     and v.source_batch_id=r.run_id
     and v.source_record_id=r.stock_number
     and v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
  ) then
    perform set_config('pdc.hermes_test_wrapper_vehicle_365',v_vehicle_id::text,true);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  IF lower(btrim(coalesce(p_operation,'')))='extend' THEN
   perform public.workshop_require_planner_operator();
   perform set_config('pdc.workshop_capacity_manual',jsonb_build_object('actor',auth.uid(),'booking',p_target_id,'version',p_target_expected_version,'duration',p_duration_minutes)::text,true);
  END IF;
  v_capacity_result:=public.cascade_workshop_schedule_pre346(p_operation,p_target_id,p_target_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_technician_id,p_shift_minutes,p_override_reason,p_metadata);
  perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
  RETURN v_capacity_result;
EXCEPTION WHEN OTHERS THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true); RAISE;
end $function$
;
