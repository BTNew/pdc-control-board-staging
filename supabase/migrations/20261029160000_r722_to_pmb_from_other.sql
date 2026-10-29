-- r722 (F332). Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 13:37 (13097784, Other tile): "All vehicles should" have To PMB. pmb_transfer_vehicle allowed a vehicle
-- in Other only when it had no Navision record. Now Other is allowed like Yard Hold and In Transit. A blank location
-- keeps the old non-Navision rule. QC done, RFT and collected vehicles stay refused as before.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';
DO $r722$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_def text;
  a1 text := $a$  if v_location in ('OTHER','') and ($a$;
  b1 text := $b$  if v_location = '' and ( -- r722 (F332): Other is an incoming location for every vehicle$b$;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r722: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r722: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r722: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 472 OR fault_id = 'F332' OR added_in = 'r722') THEN RAISE EXCEPTION 'r722: sort 472 or F332 is taken'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.pmb_transfer_vehicle(uuid,integer)'::regprocedure;
  IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE prosrc_md5 = md5(v_old)) THEN RAISE EXCEPTION 'r722: pinned'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r722: anchor not found once'; END IF;
  v_def := regexp_replace(pg_get_functiondef('public.pmb_transfer_vehicle(uuid,integer)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || replace(v_old, a1, b1) || substring(v_def from '\$[a-zA-Z_]*\$$');
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('to_pmb_from_other_722', 'F332', 'To PMB works from the Other tile for every vehicle (not only non-Navision).',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.pmb_transfer_vehicle(uuid,integer)')), 'r722 (F332)') > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.pmb_transfer_vehicle(uuid,integer)')), 'pmb_transfer_requires_incoming_location') > 0
 AS ok, 'To PMB from Other' AS detail
$chk$, true, 472, 'r722');
END $r722$;
