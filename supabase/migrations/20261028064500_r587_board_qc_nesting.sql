-- r587 (F201) / sort 359. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Control-board eligibility reads QC lines once per vehicle and work items once per candidate row.
-- The QC wrapper already returns the cached lines. Read that table in one join.
-- Work items are the same JSON when aggregated by vehicle and stage in ctid order (0 differences on 1220 rows).
-- The snapshot JSON is compared before and after in this transaction. now() does not move, so the whole payload must match.
-- PR #498 keeps r584 / F198 / sort 356. r586 / F200 / sort 358 is the board waiter release.
-- Pin count stays 241. No new pin.
-- Undo: supabase/rollbacks/20261028064500_r587_board_qc_nesting.down.sql
SET LOCAL lock_timeout = '8s';
DO $g$
DECLARE
  awst time;
  actor record;
  def text;
  old_snap jsonb;
  new_snap jsonb;
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
    RAISE EXCEPTION 'r587: Kajel import window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r587: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r587: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r587: pin count is not 241'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=359 OR fault_id='F201' OR check_name='board_qc_nesting_587' OR added_in='r587') THEN RAISE EXCEPTION 'r587: sort 359 / F201 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=356 OR fault_id='F198' OR added_in='r584') THEN RAISE EXCEPTION 'r587: r584 preview is in the ledger'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.all_station_eligibility_20261018()')) IS DISTINCT FROM '633a0124502c70d88a552985af2c6e2e' THEN RAISE EXCEPTION 'r587: eligibility body changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()')) IS DISTINCT FROM 'f744636778e0f10128d6457605430c2f' THEN RAISE EXCEPTION 'r587: compute body changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_eligibility_snapshot()')) IS DISTINCT FROM '9207f7c1664552122775bb4a2e6d9f25' THEN RAISE EXCEPTION 'r587: eligibility wrapper changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IS DISTINCT FROM '1b8106327e68624c8f235c2e84641842' THEN RAISE EXCEPTION 'r587: board body changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r587: department 135 changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r587: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r587: Kajel apply changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r587: clock tick changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r587: QC wrapper changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379_uncached(uuid)')) IS DISTINCT FROM '97fc4caaf7b462163d35b4a3511bc487' THEN RAISE EXCEPTION 'r587: QC uncached changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.base_pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'a93005010cf96ab6eb804ef879039861' THEN RAISE EXCEPTION 'r587: QC base changed'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554' AND position('pdc_ops.eligibility_snapshot_compute_554()''))=''f744636778e0f10128d6457605430c2f''' IN check_sql)>0)<>1 THEN RAISE EXCEPTION 'r587: r554 check does not name the compute'; END IF;

  SELECT r.email, r.auth_user_id INTO actor
  FROM public.pdc_user_roles r
  WHERE r.role::text='administrator' AND r.active AND r.account_status='approved' AND r.auth_user_id IS NOT NULL
  ORDER BY r.auth_user_id LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', actor.auth_user_id, 'email', actor.email)::text, true);
  PERFORM set_config('request.jwt.claim.sub', actor.auth_user_id::text, true);
  PERFORM set_config('request.jwt.claim.email', actor.email, true);
  old_snap := pdc_ops.eligibility_snapshot_compute_554();

  SELECT pg_get_functiondef('pdc_work_categories_private.all_station_eligibility_20261018()'::regprocedure) INTO def;
  IF (length(def)-length(replace(def, old_lines, '')))/length(old_lines)<>1 THEN RAISE EXCEPTION 'r587: QC line call was not found once'; END IF;
  EXECUTE replace(def, old_lines, new_lines);

  SELECT pg_get_functiondef('pdc_ops.eligibility_snapshot_compute_554()'::regprocedure) INTO def;
  IF (length(def)-length(replace(def, old_items, '')))/length(old_items)<>1 THEN RAISE EXCEPTION 'r587: work item lookup was not found once'; END IF;
  IF (length(def)-length(replace(def, 'WITH eligibility AS MATERIALIZED (', '')))/length('WITH eligibility AS MATERIALIZED (')<>1 THEN RAISE EXCEPTION 'r587: eligibility CTE was not found once'; END IF;
  def := replace(def, 'WITH eligibility AS MATERIALIZED (', items_cte);
  def := replace(def, old_items, new_items);
  EXECUTE def;

  new_snap := pdc_ops.eligibility_snapshot_compute_554();
  IF old_snap IS DISTINCT FROM new_snap THEN RAISE EXCEPTION 'r587: snapshot changed'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.email', '', true);

  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql,
    'pdc_ops.eligibility_snapshot_compute_554()''))=''f744636778e0f10128d6457605430c2f''',
    'pdc_ops.eligibility_snapshot_compute_554()''))=''' || (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()')) || '''')
  WHERE check_name='read_once_snapshots_554'
    AND fault_id='F168'
    AND sort_order=329
    AND added_in='r554'
    AND position('pdc_ops.eligibility_snapshot_compute_554()''))=''f744636778e0f10128d6457605430c2f''' IN check_sql)>0;
END $g$;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('board_qc_nesting_587','F201','Control board QC lines are read from the cache in one join, and candidate work items are aggregated once. The eligibility wrapper stays under 8s and a second call matches.',
 $chk587$SELECT
  structure.ok
  AND timed.second_ms < 2000
  AND timed.first_ms < 8000
  AND timed.same
  AND timed.ok_shape
 AS ok,
 format('first %s ms / second %s ms / %s bytes', timed.first_ms, timed.second_ms, timed.bytes) AS detail
 FROM (
  SELECT
   (SELECT position('qc_operation_lines_cache' IN p.prosrc)>0
      AND position('public.pdc_qc_operation_lines_379(v.id) lines FROM' IN p.prosrc)=0
     FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_work_categories_private.all_station_eligibility_20261018()'))
   AND (SELECT position('work_items_587' IN p.prosrc)>0
      AND position('workshop_stage_code_for_work_key(wi.work_key)=e.stage_code' IN p.prosrc)=0
     FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()'))
   AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_qc_operation_lines_379(uuid)'))='b7f90bff12643229ff80f8ca552663a2'
   AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.get_workshop_eligibility_snapshot()'))='9207f7c1664552122775bb4a2e6d9f25'
  AS ok
 ) structure
 CROSS JOIN LATERAL (
  SELECT r.email, r.auth_user_id
  FROM public.pdc_user_roles r
  WHERE r.role::text='administrator' AND r.active AND r.account_status='approved' AND r.auth_user_id IS NOT NULL
  ORDER BY r.auth_user_id
  LIMIT 1
 ) actor
 CROSS JOIN LATERAL (
  SELECT set_config('request.jwt.claims', json_build_object('sub', actor.auth_user_id, 'email', actor.email)::text, true) AS claims
 ) primed
 CROSS JOIN LATERAL (SELECT clock_timestamp() AS t0) s0
 CROSS JOIN LATERAL (SELECT public.get_workshop_eligibility_snapshot() AS snap) a
 CROSS JOIN LATERAL (SELECT clock_timestamp() AS t1) s1
 CROSS JOIN LATERAL (SELECT public.get_workshop_eligibility_snapshot() AS snap) b
 CROSS JOIN LATERAL (
  SELECT round((extract(epoch FROM s1.t1-s0.t0)*1000)::numeric,1) AS first_ms,
         round((extract(epoch FROM clock_timestamp()-s1.t1)*1000)::numeric,1) AS second_ms,
         octet_length(b.snap::text) AS bytes,
         a.snap IS NOT DISTINCT FROM b.snap AS same,
         jsonb_typeof(b.snap->'candidates')='array' AS ok_shape,
         set_config('request.jwt.claims','', true) AS clear_claims
 ) timed$chk587$,
 true, 359, 'r587');

DO $p$
DECLARE v_md5 text;
BEGIN
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()');
  IF v_md5 = 'f744636778e0f10128d6457605430c2f' THEN RAISE EXCEPTION 'r587: compute did not change'; END IF;
  IF (SELECT position('work_items_587' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()'))=0 THEN RAISE EXCEPTION 'r587: work items CTE missing'; END IF;
  IF (SELECT position('qc_operation_lines_cache' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.all_station_eligibility_20261018()'))=0 THEN RAISE EXCEPTION 'r587: QC cache join missing'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554' AND position('eligibility_snapshot_compute_554()''))=''' || v_md5 || '''' IN check_sql)>0)<>1 THEN RAISE EXCEPTION 'r587: r554 check was not retargeted'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='board_qc_nesting_587' AND fault_id='F201' AND sort_order=359 AND added_in='r587' AND enabled)<>1 THEN RAISE EXCEPTION 'r587: check missing'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r587: pin count changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r587: QC wrapper changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r587: department 135 changed'; END IF;
END $p$;
