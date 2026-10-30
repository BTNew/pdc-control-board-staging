-- r755 (F360) / sort 465. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 10:57: WPC is a physical area; after final check the car goes to WPC until Sales gives the destination,
-- then the RFT tick. 11:28, choosing between the two rules the two sessions had built: "B - but make the key number
-- show WPC please". B = the key number stays on the car through final check and becomes WPC when final check PASSES
-- (the move QC -> RFT that finalize_pdc_qc_to_rft_700 makes), freeing the number then. r830 (other session, 11:03)
-- changed it on the way INTO QC; that rule had not yet fired on any car (both WPC cars today were typed by hand).
-- Same trigger, same capture (r830b frees the number and keeps the PMB key date); only the moment changes.
-- Rollback: supabase/rollbacks/20261030113500_r755_wpc_after_final_check.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $pre755$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r755: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 465 OR fault_id = 'F360' OR added_in = 'r755') THEN RAISE EXCEPTION 'r755: sort 465 or F360 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'pdc_key_number_private.qc_key_to_wpc_830()'::regprocedure) IS DISTINCT FROM 'be4f0b1b2ffc4f3dd7f4ac3bd8f7f0c2'
     AND strpos((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_key_number_private.qc_key_to_wpc_830()'::regprocedure), $q$v_new_eff = 'QC' AND v_old_eff <> 'QC'$q$) = 0
    THEN RAISE EXCEPTION 'r755: qc_key_to_wpc_830 is not the r830 into-QC body'; END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'zzy_pdc_qc_key_wpc_830' AND tgrelid = 'public.vehicles'::regclass) IS NOT TRUE THEN RAISE EXCEPTION 'r755: r830 trigger missing'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_key_number_private.vehicle_wpc_830 WHERE cause = 'qc') THEN RAISE EXCEPTION 'r755: a car was already made WPC on the way into QC; decide those first'; END IF;
END $pre755$;

-- Final check PASSES (QC -> RFT) with a real key -> WPC. Still BEFORE and still named to run before zzz_pdc_active_key_575.
CREATE OR REPLACE FUNCTION pdc_key_number_private.qc_key_to_wpc_830()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_old_eff text := '';
  v_new_eff text := upper(btrim(coalesce(nullif(btrim(NEW.location_override), ''), NEW.current_location, '')));
BEGIN
  IF TG_OP = 'UPDATE' THEN
    v_old_eff := upper(btrim(coalesce(nullif(btrim(OLD.location_override), ''), OLD.current_location, '')));
  END IF;
  -- r755 (F360, Craig rule B): the key stays on the car through final check; it becomes WPC when final check passes
  -- (the move to RFT), which frees the number. A car going INTO QC keeps its key, so a fail still has it.
  IF v_new_eff = 'RFT' AND v_old_eff <> 'RFT'
     AND pdc_key_number_private.key_token_575(NEW.key_number) IS NOT NULL THEN
    PERFORM set_config('pdc.wpc_cause_830', 'final_check_pass', true);
    NEW.key_number := 'WPC';
  END IF;
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION pdc_key_number_private.qc_key_to_wpc_830() FROM PUBLIC, anon, authenticated;

UPDATE pdc_ops.regression_checks
   SET description = 'WPC is not a key tag (never clashes, frees the number); a car whose final check passes (QC to RFT) with a key becomes WPC (r755); the WPC start is recorded and WPC is not in the PMB key bucket.'
 WHERE check_name = 'wpc_key_830';

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('wpc_after_final_check_755', 'F360',
  'Key becomes WPC when final check passes (QC to RFT), never on the way into QC (Craig rule B, 30 Oct 11:28).',
  $chk$
SELECT strpos(f.src, $q$v_new_eff = 'RFT' AND v_old_eff <> 'RFT'$q$) > 0
   AND strpos(f.src, $q$v_new_eff = 'QC' AND v_old_eff <> 'QC'$q$) = 0
   AND NOT EXISTS (SELECT 1 FROM pdc_key_number_private.vehicle_wpc_830 w WHERE w.cause = 'qc' AND w.reverted_at IS NULL)
 AS ok, 'WPC on final check pass' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('pdc_key_number_private.qc_key_to_wpc_830()')) f
$chk$, true, 465, 'r755');

DO $post755$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('wpc_after_final_check_755','wpc_key_830','regression_checks_self_test','protected_function_md5s') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r755: % red after apply: %', r.check_name, left(r.detail, 200); END IF;
  END LOOP;
END $post755$;
