-- r688 (F298) / sort 440. Staging cdsmnqxtyyoeoznmbidd only. Applied 29 Oct 2026 07:46 AWST (Craig approved 07:44).
-- QC could not tick, photo, reject or sign off a vehicle that was put in QC by a location override
-- (e.g. 12661302 / Key 119: current_location PMB, location_override QC). The board shows the override, but every
-- QC write function checked current_location only, so each tap failed with "This operation was not saved".
-- Fix: every public QC function now checks the shown location (override first, then current_location).
-- When sign-off moves the vehicle to RFT, or reject sends it back to PMB, the override is cleared so the
-- vehicle follows the real move (same as pmb_transfer_vehicle). Originals are kept in pdc_ops.r688_function_backup.
-- None of these functions is pinned or named by a regression check. Karratha schemas are not touched.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '120s';

CREATE TEMP TABLE r688_green ON COMMIT DROP AS SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE false;
DO $pre688$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE enabled AND check_sql ~* 'qc' LOOP
    BEGIN EXECUTE r.check_sql INTO ok, detail; EXCEPTION WHEN OTHERS THEN ok := false; END;
    IF ok IS TRUE THEN INSERT INTO r688_green VALUES (r.check_name, r.check_sql); END IF;
  END LOOP;
END $pre688$;

CREATE TABLE IF NOT EXISTS pdc_ops.r688_function_backup (sig text PRIMARY KEY, def text NOT NULL, saved_at timestamptz NOT NULL DEFAULT clock_timestamp());

DO $r688$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  r record; v_def text; v_new text; v_guards integer; v_clears integer; v_total integer := 0;
  c_guard text := $p$upper\((btrim\(coalesce\()?(\w+)\.current_location(,''\)\))?\)\s*<>\s*'QC'$p$;
  c_guard_new text := $p$upper(btrim(coalesce(nullif(btrim(\2.location_override),''),\2.current_location,'')))<>'QC'$p$;
  c_move text := $p$current_location\s*=\s*'(RFT|PMB)'\s*,$p$;
  c_move_new text := $p$current_location='\1',location_override=NULL,location_override_reason=NULL,location_override_at=NULL,location_override_by=NULL,$p$;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r688: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r688: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 440 OR fault_id = 'F298' OR added_in = 'r688' OR check_name = 'qc_follows_override_688') THEN RAISE EXCEPTION 'r688: sort 440 or F298 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r688: an import job is running'; END IF;

  FOR r IN
    SELECT p.oid, p.proname, p.oid::regprocedure::text sig, p.prosrc,
           EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 e WHERE e.prosrc_md5 = md5(p.prosrc))
             OR EXISTS (SELECT 1 FROM pdc_ops.regression_checks c WHERE strpos(c.check_sql, md5(p.prosrc)) > 0) protected
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('set_pdc_qc_operation_completion_379', 'reject_pdc_qc_operation_381', 'record_pdc_qc_photo_evidence_399',
                        'get_pdc_qc_photo_receipt_414', 'finalize_pdc_qc_to_rft_399', 'finalize_pdc_qc_to_rft_700',
                        'reject_pdc_qc_vehicle_to_pmb_stoppage_767', 'record_pdc_qc_retest_photo_747', 'finalize_pdc_qc_retest_to_rft_747')
      AND p.prosrc !~ '^\s*SELECT public\.reject_pdc_qc_vehicle_to_pmb_stoppage_767\('  -- 5-arg wrapper, calls the 6-arg body
    ORDER BY 3
  LOOP
    IF r.protected THEN RAISE EXCEPTION 'r688: % is pinned or named by a check', r.sig; END IF;
    v_def := pg_get_functiondef(r.oid);
    v_guards := (SELECT count(*) FROM regexp_matches(r.prosrc, c_guard, 'g'));
    IF v_guards < 1 THEN RAISE EXCEPTION 'r688: % has no QC location guard', r.sig; END IF;
    v_new := regexp_replace(v_def, c_guard, c_guard_new, 'g');
    v_clears := 0;
    IF r.proname LIKE 'finalize%' OR r.proname = 'reject_pdc_qc_vehicle_to_pmb_stoppage_767' THEN
      v_clears := (SELECT count(*) FROM regexp_matches(r.prosrc, c_move, 'g'));
      IF v_clears <> 1 THEN RAISE EXCEPTION 'r688: % has % location moves, expected 1', r.sig, v_clears; END IF;
      v_new := regexp_replace(v_new, c_move, c_move_new, 'g');
    END IF;
    INSERT INTO pdc_ops.r688_function_backup(sig, def) VALUES (r.sig, v_def) ON CONFLICT (sig) DO NOTHING;
    EXECUTE v_new;
    RAISE NOTICE 'r688: % guards=% override_clears=%', r.sig, v_guards, v_clears;
    v_total := v_total + 1;
  END LOOP;
  IF v_total <> 9 THEN RAISE EXCEPTION 'r688: changed % functions, expected 9', v_total; END IF;

  INSERT INTO pdc_ops.regression_checks(check_name, sort_order, fault_id, added_in, enabled, description, check_sql)
  VALUES ('qc_follows_override_688', 440, 'F298', 'r688', true,
    'QC write and read functions accept a vehicle shown in QC by location override, and leaving QC clears the override.',
    $chk$
SELECT count(*) = 0 AS ok, coalesce(string_agg(p.proname, ', '), 'none') AS detail
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('set_pdc_qc_operation_completion_379', 'reject_pdc_qc_operation_381', 'record_pdc_qc_photo_evidence_399',
                    'get_pdc_qc_photo_receipt_414', 'finalize_pdc_qc_to_rft_399', 'finalize_pdc_qc_to_rft_700',
                    'reject_pdc_qc_vehicle_to_pmb_stoppage_767', 'record_pdc_qc_retest_photo_747', 'finalize_pdc_qc_retest_to_rft_747')
  AND p.prosrc !~ '^\s*SELECT public\.reject_pdc_qc_vehicle_to_pmb_stoppage_767\('
  AND (p.prosrc ~* 'upper\((btrim\(coalesce\()?\w+\.current_location(,''''\)\))?\)\s*<>\s*''QC'''
       OR p.prosrc !~* 'location_override\),''''\),\w+\.current_location'
       OR ((p.proname LIKE 'finalize%' OR p.proname LIKE 'reject_pdc_qc_vehicle%') AND p.prosrc !~* 'current_location=''(RFT|PMB)'',location_override=NULL'))
$chk$);
END $r688$;

DO $post688$
DECLARE r record; ok boolean; detail text;
BEGIN
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'qc_follows_override_688') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r688: new check red: %', detail; END IF;
  FOR r IN SELECT * FROM r688_green LOOP
    BEGIN EXECUTE r.check_sql INTO ok, detail; EXCEPTION WHEN OTHERS THEN ok := false; detail := SQLERRM; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r688: % went red: %', r.check_name, detail; END IF;
  END LOOP;
END $post688$;
