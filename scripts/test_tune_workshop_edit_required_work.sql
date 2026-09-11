-- Run against STAGING only. Every simulated edit is rolled back.
BEGIN;
DO $test$
DECLARE v uuid; a public.vehicle_workshop_line_adjustments%rowtype;
  original_lines jsonb; original_bookings jsonb; work_before jsonb; work_after jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
  SELECT id INTO STRICT v FROM public.vehicles WHERE stock_number='12710970' AND deleted_at IS NULL;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  PERFORM 1 FROM public.vehicles WHERE id=v FOR UPDATE;
  original_lines:=public.pdc_qc_operation_lines_379(v);
  SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb) INTO original_bookings FROM public.workshop_bookings b WHERE b.vehicle_id=v;
  SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) INTO work_before FROM public.vehicle_work_items w WHERE w.vehicle_id=v;
  SELECT * INTO STRICT a FROM public.vehicle_workshop_line_adjustments
  WHERE vehicle_id=v AND active AND source_kind='source' AND stage_code='FITTING' ORDER BY adjustment_id LIMIT 1;
  -- A description/hour save includes stage_code even when it stays the same.
  UPDATE public.vehicle_workshop_line_adjustments SET stage_code=stage_code WHERE adjustment_id=a.adjustment_id;
  SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) INTO work_after FROM public.vehicle_work_items w WHERE w.vehicle_id=v;
  IF work_before IS DISTINCT FROM work_after THEN RAISE EXCEPTION 'same_stage_save_changed_requirements'; END IF;
  -- Move one line, then make another edit. Other station requirements survive.
  UPDATE public.vehicle_workshop_line_adjustments SET stage_code='TINT' WHERE adjustment_id=a.adjustment_id;
  UPDATE public.vehicle_workshop_line_adjustments SET stage_code=stage_code WHERE adjustment_id=a.adjustment_id;
  IF EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v AND work_key IN('fitting','tint','electrical','fabrication','sublet') AND NOT required)
  THEN RAISE EXCEPTION 'second_edit_lost_required_work'; END IF;
  UPDATE public.vehicle_workshop_line_adjustments SET stage_code=a.stage_code WHERE adjustment_id=a.adjustment_id;
  -- Reconciliation replay must not dirty work rows or change completion fields.
  PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v]);
  PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v]);
  SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) INTO work_after FROM public.vehicle_work_items w WHERE w.vehicle_id=v;
  IF work_before IS DISTINCT FROM work_after THEN RAISE EXCEPTION 'replay_changed_work_state'; END IF;
  IF original_lines IS DISTINCT FROM public.pdc_qc_operation_lines_379(v)
    OR original_bookings IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb) FROM public.workshop_bookings b WHERE b.vehicle_id=v)
  THEN RAISE EXCEPTION 'source_completion_or_booking_changed'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: repeated saves, station moves, replay, source/completion/bookings preserved; test edits rolled back' AS result;
