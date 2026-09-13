-- STAGING ONLY. A single-vehicle scheduling gate must not materialize the
-- whole station queue and every vehicle's operation estimates.
-- Read-only predicates and gate response ordering are unchanged.
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 IF md5(pg_get_functiondef('public.workshop_candidate_schedule_gate(uuid,text,timestamptz)'::regprocedure)) <> '74d73fb6ad60c4e707d5b5beff39027b'
 THEN RAISE EXCEPTION 'Candidate gate definition changed; review before applying'; END IF;
 IF md5(pg_get_functiondef('public.workshop_station_eligibility(text)'::regprocedure)) <> 'cc5c7db7d002704b39f258e5371afd97'
 THEN RAISE EXCEPTION 'Station eligibility predicates changed; review before applying'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_candidate_schedule_gate(p_vehicle_id uuid, p_stage_code text, p_scheduled_start_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_stage_code text;
  v_candidate record;
  v_schedule_date date;
BEGIN
  v_stage_code:=public.workshop_canonical_stage_code(p_stage_code);
  -- Only this vehicle is being scheduled. The board-wide reader also computes
  -- each eligible vehicle's estimated hours; this gate never consumes them.
  -- Keep its membership and active-booking predicates identical.
  SELECT public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) current_location,
    v.eta_to_kewdale,
    EXISTS (
      SELECT 1 FROM public.workshop_bookings b
      JOIN public.workshop_stages booked_stage ON booked_stage.id=b.stage_id
      WHERE b.vehicle_id=v.id AND booked_stage.code=st.code
        AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
    ) existing_booking
  INTO v_candidate
  FROM public.vehicles v CROSS JOIN public.workshop_stages st
  WHERE v.id=p_vehicle_id
    AND st.code=v_stage_code AND st.active AND st.planner_enabled
    AND v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
    AND public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) IN('PMB','YH','IT')
    AND (public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))<>'IT' OR v.eta_to_kewdale IS NOT NULL)
    AND EXISTS (
      SELECT 1 FROM public.vehicle_work_items wi
      WHERE wi.vehicle_id=v.id AND public.workshop_stage_code_for_work_key(wi.work_key)=st.code
        AND wi.required AND NOT wi.completed
    );
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'error','vehicle_not_eligible_for_station');
  END IF;
  IF coalesce(v_candidate.existing_booking,false) THEN
    RETURN jsonb_build_object('ok',false,'error','active_booking_exists');
  END IF;
  v_schedule_date:=(p_scheduled_start_at AT TIME ZONE 'Australia/Perth')::date;
  IF public.pdc_sublet_away_on_date(p_vehicle_id,v_schedule_date) THEN
    RETURN jsonb_build_object('ok',false,'error','sublet_away','sublet_date',v_schedule_date);
  END IF;
  IF v_candidate.current_location='IT' AND v_candidate.eta_to_kewdale IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','it_eta_missing');
  END IF;
  IF v_candidate.current_location='IT'
     AND v_schedule_date<v_candidate.eta_to_kewdale+7 THEN
    RETURN jsonb_build_object(
      'ok',false,
      'error','it_before_eta_plus_seven',
      'earliest_permitted_date',v_candidate.eta_to_kewdale+7
    );
  END IF;
  RETURN jsonb_build_object(
    'ok',true,
    'earliest_permitted_date',CASE WHEN v_candidate.current_location='IT' THEN v_candidate.eta_to_kewdale+7 ELSE NULL END
  );
END;
$function$;
