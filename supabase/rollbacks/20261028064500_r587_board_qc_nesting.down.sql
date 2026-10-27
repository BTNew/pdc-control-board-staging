-- r587 (F201) undo. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Puts the per-vehicle QC call and the per-row work-item lookup back, and points read_once_snapshots_554 at compute md5 f744636778e0f10128d6457605430c2f.
SET LOCAL lock_timeout = '8s';
DO $g$
DECLARE
  awst time;
  def text;
  v_md5 text;
  old_lines text := $old$SELECT v.id,public.pdc_qc_operation_lines_379(v.id) lines FROM (SELECT DISTINCT id FROM eligible) v$old$;
  new_lines text := $new$SELECT v.id, coalesce(c.lines, public.pdc_qc_operation_lines_379(v.id)) lines FROM (SELECT DISTINCT id FROM eligible) v LEFT JOIN pdc_work_categories_private.qc_operation_lines_cache c ON c.vehicle_id=v.id$new$;
  old_items text := $old$'work_items',(select coalesce(jsonb_agg(jsonb_build_object(
        'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
        'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
        from public.vehicle_work_items wi where wi.vehicle_id=v.id
          and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code)$old$;
  new_items text := $new$'work_items',coalesce((select w.items from work_items_587 w where w.vehicle_id=v.id and w.stage_code=e.stage_code),'[]'::jsonb)$new$;
  items_cte text := $cte$WITH work_items_587 AS MATERIALIZED (
  SELECT wi.vehicle_id, a.stage_code, coalesce(jsonb_agg(jsonb_build_object(
    'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
    'completed',wi.completed,'completed_at',wi.completed_at) ORDER BY wi.ctid),'[]'::jsonb) AS items
  FROM public.vehicle_work_items wi
  JOIN public.workshop_stage_aliases a ON a.alias_normalized=public.workshop_normalize_identifier(wi.work_key)
  GROUP BY wi.vehicle_id, a.stage_code
), eligibility AS MATERIALIZED ($cte$;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '12:20' AND time '12:40'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r587 undo: Kajel import window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r587 undo: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r587 undo: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r587 undo: pin count is not 241'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='board_qc_nesting_587' AND fault_id='F201' AND sort_order=359 AND added_in='r587')<>1 THEN RAISE EXCEPTION 'r587 undo: F201 check is not the one row'; END IF;
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()');
  IF v_md5 IS NOT DISTINCT FROM 'f744636778e0f10128d6457605430c2f' THEN RAISE EXCEPTION 'r587 undo: compute is already the old body'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r587 undo: department 135 changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r587 undo: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r587 undo: Kajel apply changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r587 undo: clock tick changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r587 undo: QC wrapper changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379_uncached(uuid)')) IS DISTINCT FROM '97fc4caaf7b462163d35b4a3511bc487' THEN RAISE EXCEPTION 'r587 undo: QC uncached changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.base_pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'a93005010cf96ab6eb804ef879039861' THEN RAISE EXCEPTION 'r587 undo: QC base changed'; END IF;

  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql,
    'pdc_ops.eligibility_snapshot_compute_554()''))=''' || v_md5 || '''',
    'pdc_ops.eligibility_snapshot_compute_554()''))=''f744636778e0f10128d6457605430c2f''')
  WHERE check_name='read_once_snapshots_554'
    AND fault_id='F168'
    AND sort_order=329
    AND added_in='r554'
    AND position('pdc_ops.eligibility_snapshot_compute_554()''))=''' || v_md5 || '''' IN check_sql)>0;

  SELECT pg_get_functiondef('pdc_work_categories_private.all_station_eligibility_20261018()'::regprocedure) INTO def;
  IF (length(def)-length(replace(def, new_lines, '')))/length(new_lines)<>1 THEN RAISE EXCEPTION 'r587 undo: QC cache join was not found once'; END IF;
  EXECUTE replace(def, new_lines, old_lines);

  SELECT pg_get_functiondef('pdc_ops.eligibility_snapshot_compute_554()'::regprocedure) INTO def;
  IF (length(def)-length(replace(def, items_cte, '')))/length(items_cte)<>1 THEN RAISE EXCEPTION 'r587 undo: work item CTE was not found once'; END IF;
  IF (length(def)-length(replace(def, new_items, '')))/length(new_items)<>1 THEN RAISE EXCEPTION 'r587 undo: work item lookup was not found once'; END IF;
  def := replace(def, items_cte, 'WITH eligibility AS MATERIALIZED (');
  def := replace(def, new_items, old_items);
  EXECUTE def;

  DELETE FROM pdc_ops.regression_checks
  WHERE check_name='board_qc_nesting_587' AND fault_id='F201' AND sort_order=359 AND added_in='r587';

  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()')) IS DISTINCT FROM 'f744636778e0f10128d6457605430c2f' THEN RAISE EXCEPTION 'r587 undo: compute was not restored'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.all_station_eligibility_20261018()')) IS DISTINCT FROM '633a0124502c70d88a552985af2c6e2e' THEN RAISE EXCEPTION 'r587 undo: eligibility was not restored'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='board_qc_nesting_587')<>0 THEN RAISE EXCEPTION 'r587 undo: check remains'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554' AND position('pdc_ops.eligibility_snapshot_compute_554()''))=''f744636778e0f10128d6457605430c2f''' IN check_sql)>0)<>1 THEN RAISE EXCEPTION 'r587 undo: r554 check was not restored'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r587 undo: pin count changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r587 undo: department 135 changed'; END IF;
END $g$;
