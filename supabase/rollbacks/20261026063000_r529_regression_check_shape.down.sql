-- Undo r529 (F143). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Restores the six check texts and drops regression_checks_self_test. Pin count stays 241.
-- Does not change functions. The restored checks are the 26 Oct 2026 06:28 texts.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r529 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r529 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r529 undo: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test' AND fault_id='F143' AND sort_order=310 AND added_in='r529') THEN RAISE EXCEPTION 'r529 undo: self-test is not the r529 row'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_sql LIKE '%expected_function_md5)=225%' OR check_sql LIKE '%expected_function_md5)=236%') THEN RAISE EXCEPTION 'r529 undo: pin literals already present'; END IF;
END $g$;

UPDATE pdc_ops.regression_checks
SET check_sql = 'SELECT' || substr(check_sql, 9, length(check_sql) - 8 - length($k$) AS ok, 'Karratha Sales accessories stay on dealer 14450 and the Broome importer is unchanged' AS detail$k$))
WHERE check_name='karratha_sales_accessories_528'
  AND sort_order=309
  AND fault_id='F142'
  AND left(check_sql, 8)='SELECT ('
  AND right(check_sql, length($k$) AS ok, 'Karratha Sales accessories stay on dealer 14450 and the Broome importer is unchanged' AS detail$k$))
      = $k$) AS ok, 'Karratha Sales accessories stay on dealer 14450 and the Broome importer is unchanged' AS detail$k$;

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, 'CF/SL branch leaks: ', 'CF/SL scopes moved off Broome: '),
    description = replace(description, 'CF and SL Sales scope may be 37047 or 14450; 14450 on any other person is a leak', 'Broome account scope kept')
WHERE check_name='sales_branch_495'
  AND sort_order=295
  AND description LIKE '%14450 on any other person is a leak%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $new495$         (SELECT count(*) FROM pdc_sales_private.account_scopes a JOIN public.salespeople s ON s.id=a.salesperson_id
           WHERE (upper(btrim(s.code)) IN ('CF','SL') AND a.dealer_code NOT IN ('37047','14450'))
              OR (a.dealer_code='14450' AND NOT (upper(btrim(s.code)) IN ('CF','SL') AND lower(btrim(s.name)) IN ('clint franklin','scott lovett')))) leaks$new495$,
 $old495$         (SELECT count(*) FROM pdc_sales_private.account_scopes a JOIN public.salespeople s ON s.id=a.salesperson_id
           WHERE upper(btrim(s.code)) IN ('CF','SL') AND a.dealer_code<>'37047') moved_scopes$old495$)
WHERE check_name='sales_branch_495'
  AND sort_order=295
  AND check_sql LIKE '%clint franklin%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, 'leaks', 'moved_scopes')
WHERE check_name='sales_branch_495'
  AND sort_order=295
  AND check_sql LIKE '%leaks%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
 $d450b$ ||'; r450 pins matching: '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)
 ||'; before_import_rules '||coalesce((SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)'),'missing')$d450b$,
 $d450$ ||'; r450 pins matching: '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)$d450$)
WHERE check_name='bus_whole_job_450'
  AND sort_order=249
  AND check_sql LIKE '%before_import_rules%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
 '(SELECT n FROM pins)=16 AND (SELECT ok FROM pins)=16 AND (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature=''pdc_work_categories_private.before_import_rules_20261017(uuid)'')=''r523'' AND (SELECT e.prosrc_md5 IS NOT DISTINCT FROM md5(p.prosrc) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.signature=''pdc_work_categories_private.before_import_rules_20261017(uuid)'')',
 '(SELECT n FROM pins)=17 AND (SELECT ok FROM pins)=17')
WHERE check_name='bus_whole_job_450'
  AND sort_order=249
  AND check_sql LIKE '%(SELECT n FROM pins)=16 AND (SELECT ok FROM pins)=16%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $gap236$ AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)='d07f40a33443eff357d3a9cd58503696'
 AND (SELECT count(*) FROM public.workshop_technicians$gap236$,
 $back236$ AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)='d07f40a33443eff357d3a9cd58503696'
 AND (SELECT count(*) FROM pdc_ops.expected_function_md5)=236
 AND (SELECT count(*) FROM public.workshop_technicians$back236$)
WHERE check_name='qa_bay_technician_527'
  AND sort_order=308
  AND check_sql NOT LIKE '%expected_function_md5)=236%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $gap515$   AND (SELECT prosecdef FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS TRUE
   AND (SELECT check_sql LIKE '%8ddb1477beeb94c7879c4021cccf1d40%'$gap515$,
 $back515$   AND (SELECT prosecdef FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS TRUE
   AND (SELECT count(*) FROM pdc_ops.expected_function_md5)=225
   AND (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128' AND sort_order=301)
       = md5(replace((SELECT body FROM pdc_ops.r515_person_parts_prev WHERE signature='check514'),'eb02f76ec94cd0b6c824a18660432afa','8ddb1477beeb94c7879c4021cccf1d40'))
   AND (SELECT check_sql LIKE '%8ddb1477beeb94c7879c4021cccf1d40%'$back515$)
WHERE check_name='outlook_internal_parts_auth_515'
  AND sort_order=302
  AND check_sql NOT LIKE '%expected_function_md5)=225%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $gap514$   AND NOT has_function_privilege('service_role','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
 AS ok,$gap514$,
 $back514$   AND NOT has_function_privilege('service_role','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
   AND (SELECT count(*) FROM pdc_ops.expected_function_md5)=225
 AS ok,$back514$)
WHERE check_name='outlook_parts_completion_514'
  AND sort_order=301
  AND check_sql NOT LIKE '%expected_function_md5)=225%';

DELETE FROM pdc_ops.regression_checks
WHERE check_name='regression_checks_self_test' AND added_in='r529' AND fault_id='F143' AND sort_order=310;

DO $p$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test' OR added_in='r529' OR fault_id='F143' OR sort_order=310) THEN RAISE EXCEPTION 'r529 undo: self-test still present'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514') IS DISTINCT FROM 'd876e9bd42a929e659c811c0c9e6c2ec' THEN RAISE EXCEPTION 'r529 undo: r514 check md5'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515') IS DISTINCT FROM 'ece98352be4126d5fd4ad2707157cae2' THEN RAISE EXCEPTION 'r529 undo: r515 check md5'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='qa_bay_technician_527') IS DISTINCT FROM '0c94603a01970e0fbc603c5feccb8e92' THEN RAISE EXCEPTION 'r529 undo: r527 check md5'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='karratha_sales_accessories_528') IS DISTINCT FROM '00b536a80f0faaf8a11cf184156df5b5' THEN RAISE EXCEPTION 'r529 undo: r528 check md5'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450') IS DISTINCT FROM '7d6f5fdff816778f5c2c10c943ada173' THEN RAISE EXCEPTION 'r529 undo: r450 check md5'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495') IS DISTINCT FROM '8ff7e1e97dd9cb89ed5ff4e43ce98da9' THEN RAISE EXCEPTION 'r529 undo: r495 check md5'; END IF;
 IF (SELECT description FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495') NOT LIKE '%Broome account scope kept%' THEN RAISE EXCEPTION 'r529 undo: description'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r529 undo: pin count changed'; END IF;
END $p$;
