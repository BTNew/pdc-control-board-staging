-- r595 (F209) / sort 365. Craig approved go-live of #571 at 06:59 AWST on 28 Oct 2026.
-- Re-checked at 08:35 AWST on 28 Oct 2026. Apply outside the 12:30 window and outside :00.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
--
-- The Vehicle Locations Parts ETA cell is read-only. The date is set in the side panel,
-- which already calls set_pdc_parts_stoppage_564 and place_parts_eta_stoppage_573.
-- This file does not replace a function. Every existing function keeps its body,
-- so its output stays byte-identical.
--
-- Ledger at this apply: r594 / F208 / sort 364 is outstanding_station_hours_594.
-- r592 / F206 / sort 360 is hoist_place_after_592. r590 / F204 / sort 361 is qc_signoff_override_590.
-- r593 / F207 / sort 363 is new_to_pmb_view_593. Sort 362 stays with the Revolution preview (#575, r591 / F205).
-- r588 / F202 is the live tick grid and inserted no check. r595 / F209 / sort 365 is this release.
-- The apply refuses if 365, F209 or r595 has been taken.
-- The two clock reds from 07:24 and 07:35 are the baseline. This file does not touch the clock.
--
-- Pin count stays 241. No pin is inserted. Department 135 fitter_job_command stays
-- fd05b9eef69498002ac06dd68e01cdff. Kajel's rows validator stays
-- 9be0883b1a555f48f3c1ba9fa111c891 and the apply stays
-- b62fb7c29ffd2a1629f214f696e5cb14.
-- Undo: supabase/rollbacks/20261028084500_r595_parts_eta_panel.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r595: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r595: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r595: pin count is not 241'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=365 OR fault_id='F209' OR check_name='parts_eta_panel_only_595' OR added_in='r595') THEN RAISE EXCEPTION 'r595: sort 365 or F209 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='station_sublet_cache_585' AND fault_id='F199' AND sort_order=357 AND added_in='r585') THEN RAISE EXCEPTION 'r595: r585 / F199 sort 357 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='board_qc_nesting_587' AND fault_id='F201' AND sort_order=359 AND added_in='r587') THEN RAISE EXCEPTION 'r595: r587 / F201 sort 359 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outstanding_station_hours_594' AND fault_id='F208' AND sort_order=364 AND added_in='r594') THEN RAISE EXCEPTION 'r595: r594 / F208 sort 364 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_eta_stoppage_573' AND fault_id='F194' AND sort_order=352 AND added_in='r581') THEN RAISE EXCEPTION 'r595: r581 stoppage check is not present'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r595: department 135 changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r595: fitter command changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'))
    IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r595: Kajel rows validator changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)'))
    IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r595: Kajel apply changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)'))
    IS DISTINCT FROM 'fa275b45be296e9021f9f4dc570f5751' THEN RAISE EXCEPTION 'r595: manual parts ETA save changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_pdc_parts_eta_stoppage_board_573()'))
    IS DISTINCT FROM 'c22076cba374291befa2ea23fc59f276' THEN RAISE EXCEPTION 'r595: stoppage board changed'; END IF;
END $g$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('parts_eta_panel_only_595', 'F209',
 'Vehicle Locations Parts ETA is read in the table and set in the side panel. Place as STOPPAGE still uses the r581 function. The manual save, the stoppage board, the email ETA, Kajel''s import and department 135 stay byte-identical. Pin count stays 241 and r595 inserts no pin.',
 $chk595$
WITH pins AS (
  SELECT count(*)::int AS n FROM pdc_ops.expected_function_md5
), added AS (
  SELECT count(*)::int AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r595'
), reported_faults AS (
  SELECT
    (SELECT n FROM pins) = 241 AS pins_241,
    (SELECT n FROM added) = 0 AS no_new_pin,
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')) = 'fa275b45be296e9021f9f4dc570f5751' AS manual_save,
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.get_pdc_parts_eta_stoppage_board_573()')) = 'c22076cba374291befa2ea23fc59f276' AS stoppage_board,
    (SELECT count(*) FROM pg_catalog.pg_proc p
      WHERE p.oid = pg_catalog.to_regprocedure('public.place_parts_eta_stoppage_573(uuid,date,text,boolean)')
        AND p.prosecdef) = 1 AS place_fn,
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) = '88d31cbd6ca5ddd372e3143d5f8c013f' AS email_eta,
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) = '9be0883b1a555f48f3c1ba9fa111c891' AS kajel_rows,
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) = 'b62fb7c29ffd2a1629f214f696e5cb14' AS kajel_apply,
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff' AS dept_135
)
SELECT pins_241 AND no_new_pin AND manual_save AND stoppage_board AND place_fn AND email_eta AND kajel_rows AND kajel_apply AND dept_135 AS ok,
  'pins '||(SELECT n FROM pins)
  ||' manual '||coalesce((SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')), 'missing')
  ||' board '||coalesce((SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.get_pdc_parts_eta_stoppage_board_573()')), 'missing')
  ||' rows '||coalesce((SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')), 'missing')
  ||' apply '||coalesce((SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')), 'missing')
  ||' dept135 '||coalesce((SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')), 'missing') AS detail
FROM reported_faults
$chk595$,
true, 365, 'r595');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r595: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r595') THEN RAISE EXCEPTION 'r595: a pin was inserted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='parts_eta_panel_only_595' AND fault_id='F209' AND sort_order=365 AND added_in='r595' AND enabled)<>1 THEN RAISE EXCEPTION 'r595: check missing'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)'))
    IS DISTINCT FROM 'fa275b45be296e9021f9f4dc570f5751' THEN RAISE EXCEPTION 'r595: manual save changed'; END IF;
 PERFORM set_config('search_path','pg_catalog, public',true);
 PERFORM set_config('request.jwt.claims','',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_eta_panel_only_595' AND fault_id='F209' AND sort_order=365 AND added_in='r595') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r595: check red: %', y.detail; END IF;
END $g$;
