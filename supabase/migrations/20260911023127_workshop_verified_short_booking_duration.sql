-- STAGING only. Match real planner booking minutes to recorded job hours.
DO $$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
END $$;

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
 ), established AS(
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
 -- Recorded positive job hours are authoritative for real workshop bookings.
 -- Arbitrary shortened durations still fall through to the existing guard.
 IF NEW.default_duration_minutes<60
   AND NEW.default_duration_minutes=public.workshop_vehicle_stage_estimated_duration_minutes(NEW.vehicle_id,NEW.stage_id)
   AND EXISTS(
     SELECT 1 FROM public.vehicles v
     JOIN public.vehicle_work_items wi ON wi.vehicle_id=v.id AND wi.required AND NOT wi.completed
     JOIN public.workshop_stages s ON s.id=NEW.stage_id AND s.code=public.workshop_stage_code_for_work_key(wi.work_key)
     WHERE v.id=NEW.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
       AND s.active AND s.planner_enabled
   ) THEN RETURN NEW; END IF;
 IF NEW.default_duration_minutes<60 AND NOT (coalesce((public.pdc_qc_rework_scope_20260909(NEW.vehicle_id)->>'active')::boolean,false) AND NEW.default_duration_minutes=public.workshop_vehicle_stage_estimated_duration_minutes(NEW.vehicle_id,NEW.stage_id)) AND NOT EXISTS(
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
