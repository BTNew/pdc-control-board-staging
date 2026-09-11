-- STAGING only. Retain the existing email reconciliation and add authoritative
-- Tune requirements; the old email-only view erased them after a line edit.
DO $$ BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.pdc_auditor_recalculate_required_work_226(p_vehicle_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE v_vehicle uuid; v_work_keys text[];
BEGIN
  FOR v_vehicle IN SELECT DISTINCT unnest(p_vehicle_ids) LOOP
    SELECT coalesce(array_agg(DISTINCT work_key),'{}'::text[]) INTO v_work_keys
    FROM (
      SELECT e.work_key FROM public.pdc_effective_operation_lines e
      WHERE e.vehicle_id=v_vehicle AND e.active AND e.work_key IS NOT NULL
      UNION
      SELECT s.work_key
      FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v_vehicle)) l
      JOIN public.workshop_stages s ON s.code=l->>'stage_code'
      WHERE l->>'source_contract'='pilbara_service_open_jobcards_v1'
        AND (l->>'active')::boolean IS TRUE
        AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
    ) effective;
    INSERT INTO public.vehicle_work_items(
      vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at
    )
    SELECT v_vehicle,work_key,true,false,null,null,null,clock_timestamp()
    FROM unnest(v_work_keys) work_key
    ON CONFLICT(vehicle_id,work_key) DO UPDATE
      SET required=true,updated_at=clock_timestamp()
      WHERE NOT public.vehicle_work_items.completed AND NOT public.vehicle_work_items.required;
    UPDATE public.vehicle_work_items wi SET required=false,updated_at=clock_timestamp()
    WHERE wi.vehicle_id=v_vehicle AND wi.required AND NOT wi.completed
      AND NOT (wi.work_key=ANY(v_work_keys));
  END LOOP;
END $function$;

-- Restore only the two verified affected approved vehicles. Source lines, saved
-- adjustments, completion state, bookings and locations are not modified.
DO $repair$
DECLARE v public.vehicles%rowtype; before_work jsonb; after_work jsonb; source_before jsonb; bookings_before jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  FOR v IN SELECT * FROM public.vehicles
    WHERE stock_number IN('12710970','13001553') AND deleted_at IS NULL
      AND lifecycle_state='active' AND visible_on_board AND qc_completed_at IS NULL
      AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=vehicles.id AND r.status='approved')
    FOR UPDATE
  LOOP
    SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) INTO before_work
    FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id;
    IF EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id AND w.required) THEN CONTINUE; END IF;
    source_before:=public.pdc_qc_operation_lines_379(v.id);
    SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb) INTO bookings_before
    FROM public.workshop_bookings b WHERE b.vehicle_id=v.id;
    PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v.id]);
    SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) INTO after_work
    FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id;
    IF source_before IS DISTINCT FROM public.pdc_qc_operation_lines_379(v.id)
      OR bookings_before IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb) FROM public.workshop_bookings b WHERE b.vehicle_id=v.id)
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(source_before) l JOIN public.workshop_stages s ON s.code=l->>'stage_code'
        WHERE l->>'source_contract'='pilbara_service_open_jobcards_v1' AND (l->>'active')::boolean
        AND NOT EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id AND w.work_key=s.work_key AND (w.required OR w.completed)))
    THEN RAISE EXCEPTION 'tune_required_work_repair_readback_failed'; END IF;
    IF after_work IS DISTINCT FROM before_work THEN
      UPDATE public.vehicles SET version=version+1,updated_at=clock_timestamp() WHERE id=v.id;
      INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,before_data,after_data,metadata)
      VALUES('update','vehicle_work_items',v.id,v.id,
        jsonb_build_object('work_items',before_work),jsonb_build_object('work_items',after_work),
        jsonb_build_object('source','tune_workshop_edit_required_work_repair_20260911',
          'stock_number',v.stock_number,'environment','staging','bookings_changed',false,
          'completion_changed',false,'source_lines_changed',false,'location_changed',false));
    END IF;
  END LOOP;
END $repair$;
