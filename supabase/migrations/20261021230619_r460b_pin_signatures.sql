-- r460b (F73): the two public r460 pins were written without the 'public.' schema prefix, so protected_function_md5s
-- (which resolves signatures with search_path pg_catalog) reported them MISSING. Qualify them; md5s unchanged.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r460b: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r460b: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r460' AND signature IN ('set_pdc_vehicle_key_number_460(uuid,integer,text,uuid)','get_pdc_vehicle_key_number_460(uuid)'))<>2
    THEN RAISE EXCEPTION 'r460b: unqualified r460 pins not found'; END IF;
END $g$;
UPDATE pdc_ops.expected_function_md5 SET signature='public.'||signature, updated_at=now()
 WHERE release='r460' AND signature IN ('set_pdc_vehicle_key_number_460(uuid,integer,text,uuid)','get_pdc_vehicle_key_number_460(uuid)');
DO $g$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) AND md5(p.prosrc)=e.prosrc_md5 WHERE e.release='r460' AND e.signature LIKE '%.%')<>6
   THEN RAISE EXCEPTION 'r460b: pins do not resolve'; END IF;
END $g$;
