-- Controlled STAGING verification only. The terminal exception is intentional and rolls back every fixture/action write.
BEGIN;
SET LOCAL statement_timeout='60s';

DO $negative$
DECLARE v_issues text[];
BEGIN
  UPDATE public.vehicle_work_items
  SET completed=false
  WHERE vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid AND work_key='fitting' AND required=true AND completed=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_103_NEGATIVE_FIXTURE_MISSING'; END IF;
  v_issues:=public.pdc_qc_gate_issues('f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid);
  IF NOT ('outstanding_required_work:FITTING'=ANY(v_issues)) THEN
    RAISE EXCEPTION 'PDC_103_NON_PIT_NEGATIVE_FAILED: %',v_issues;
  END IF;
  UPDATE public.vehicle_work_items
  SET completed=true
  WHERE vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid AND work_key='fitting';
  UPDATE public.workshop_stages SET planner_enabled=true WHERE code='PIT_INSPECTION';
  UPDATE public.vehicles SET pmb_stage='PIT_INSPECTION',pmb_bay_stage='PIT_INSPECTION',pmb_bay_number='1'
  WHERE id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid;
  INSERT INTO public.workshop_bookings(vehicle_id,stage_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by,metadata)
  SELECT 'f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid,s.id,'queued','2026-09-07 08:00:00+08'::timestamptz,'2026-09-07 09:00:00+08'::timestamptz,60,
    '8a83b715-8d79-4b0e-95b2-02b55da6e8d7'::uuid,'8a83b715-8d79-4b0e-95b2-02b55da6e8d7'::uuid,jsonb_build_object('fixture','t_73382968_rollback')
  FROM public.workshop_stages s WHERE s.code='PIT_INSPECTION';
  v_issues:=public.pdc_qc_gate_issues('f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid);
  IF v_issues IS DISTINCT FROM ARRAY[]::text[] THEN
    RAISE EXCEPTION 'PDC_104_DEFERRED_PIT_STAGE_OR_BOOKING_BLOCKED: %',v_issues;
  END IF;
END $negative$;

SET LOCAL ROLE authenticated;

DO $unauthorized$
DECLARE v_denied boolean:=false;
BEGIN
  PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000000","email":"unauthorized@example.invalid","role":"authenticated"}',true);
  BEGIN
    PERFORM public.mark_vehicle_ready_for_qc('f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid,11);
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'PDC_104_NON_OPERATOR_WAS_NOT_DENIED'; END IF;
END $unauthorized$;

SELECT set_config('request.jwt.claims','{"sub":"8a83b715-8d79-4b0e-95b2-02b55da6e8d7","email":"craig.watson@broometoyota.com.au","role":"authenticated"}',true);

DO $rpc$
DECLARE v_stale jsonb; v_success jsonb; v_row public.vehicles%rowtype;
BEGIN
  v_stale:=public.mark_vehicle_ready_for_qc('f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid,10);
  IF v_stale->>'error' IS DISTINCT FROM 'vehicle_version_conflict' THEN
    RAISE EXCEPTION 'PDC_103_STALE_VERSION_NOT_REJECTED: %',v_stale;
  END IF;
  SELECT * INTO v_row FROM public.vehicles WHERE id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid;
  IF v_row.version<>11 OR v_row.current_location<>'PMB' THEN
    RAISE EXCEPTION 'PDC_103_STALE_VERSION_MUTATED: %/%',v_row.version,v_row.current_location;
  END IF;
  v_success:=public.mark_vehicle_ready_for_qc('f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid,11);
  IF v_success->>'ok' IS DISTINCT FROM 'true' OR v_success->'vehicle'->>'current_location' IS DISTINCT FROM 'QC'
     OR (v_success->'vehicle'->>'version')::integer<>12 THEN
    RAISE EXCEPTION 'PDC_103_RPC_SUCCESS_FAILED: %',v_success;
  END IF;
  SELECT * INTO v_row FROM public.vehicles WHERE id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid;
  IF v_row.version<>12 OR v_row.current_location<>'QC' OR NOT EXISTS(
    SELECT 1 FROM public.vehicle_movements m WHERE m.vehicle_id=v_row.id AND m.from_location='PMB' AND m.to_location='QC'
      AND m.moved_by='8a83b715-8d79-4b0e-95b2-02b55da6e8d7'::uuid
  ) THEN RAISE EXCEPTION 'PDC_103_RPC_DID_NOT_PERSIST_IN_TRANSACTION'; END IF;
  IF v_success->'vehicle'->>'pmb_stage' IS NOT NULL OR v_success->'vehicle'->>'pmb_bay_stage' IS NOT NULL OR v_success->'vehicle'->>'pmb_bay_number' IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_104_DEFERRED_PIT_PLACEMENT_NOT_CLEARED: %',v_success;
  END IF;
  RAISE EXCEPTION 'PDC_104_EXPECTED_ROLLBACK: non-PIT negative, PIT stage/booking exclusion, non-operator denial, stale-version rejection and authenticated QC persistence all passed';
END $rpc$;
