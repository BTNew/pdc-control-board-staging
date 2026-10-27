-- Undo r586 (F200) / sort 358. Removes the regression check only.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Does not replace a function. The parts ETA save, the stoppage place and the stoppage
-- board stay as they are, so their output stays byte-identical.
-- Department 135 stays fd05b9eef69498002ac06dd68e01cdff.
-- Kajel rows stay 9be0883b1a555f48f3c1ba9fa111c891.
-- Kajel apply stays b62fb7c29ffd2a1629f214f696e5cb14.
-- Pin count stays 241.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r586 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r586 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r586 undo: pin count is not 241'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='parts_eta_panel_only_586' AND fault_id='F200' AND sort_order=358 AND added_in='r586')<>1 THEN RAISE EXCEPTION 'r586 undo: check is not the r586 row'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r586') THEN RAISE EXCEPTION 'r586 undo: a pin was inserted'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r586 undo: department 135 changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'))
    IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r586 undo: Kajel rows validator changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)'))
    IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r586 undo: Kajel apply changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)'))
    IS DISTINCT FROM 'fa275b45be296e9021f9f4dc570f5751' THEN RAISE EXCEPTION 'r586 undo: manual parts ETA save changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_pdc_parts_eta_stoppage_board_573()'))
    IS DISTINCT FROM 'c22076cba374291befa2ea23fc59f276' THEN RAISE EXCEPTION 'r586 undo: stoppage board changed'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='parts_eta_panel_only_586' AND fault_id='F200' AND sort_order=358 AND added_in='r586';

DO $g$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='parts_eta_panel_only_586' OR fault_id='F200' OR sort_order=358 OR added_in='r586')<>0 THEN RAISE EXCEPTION 'r586 undo: check remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r586 undo: pin count changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.place_parts_eta_stoppage_573(uuid,date,text,boolean)')) IS NULL THEN RAISE EXCEPTION 'r586 undo: place function missing'; END IF;
END $g$;
