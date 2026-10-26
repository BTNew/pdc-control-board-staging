-- r529 (F143). PREVIEW ONLY. Do not apply. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- 26 Oct 2026 06:28 AWST fault run: the red rows are check text, not the board.
-- Pin count stays 241 (no function change). New check regression_checks_self_test sort 310.
-- clock_tick_resaves_per_tick is unchanged.
-- Undo: supabase/rollbacks/20261026063000_r529_regression_check_shape.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r529: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r529: staging only'; END IF;
 PERFORM set_config('pdc.r529_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r529_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r529: pin count is not 241'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=310 OR fault_id='F143' OR check_name='regression_checks_self_test' OR added_in='r529')
 THEN RAISE EXCEPTION 'r529: already applied, or sort 310 / F143 is taken'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128' AND sort_order=301) IS DISTINCT FROM 'd876e9bd42a929e659c811c0c9e6c2ec' THEN RAISE EXCEPTION 'r529: outlook_parts_completion_514 is not the live text'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515' AND added_in='r515' AND fault_id='F129' AND sort_order=302) IS DISTINCT FROM 'ece98352be4126d5fd4ad2707157cae2' THEN RAISE EXCEPTION 'r529: outlook_internal_parts_auth_515 is not the live text'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='qa_bay_technician_527' AND added_in='r527' AND fault_id='F141' AND sort_order=308) IS DISTINCT FROM '0c94603a01970e0fbc603c5feccb8e92' THEN RAISE EXCEPTION 'r529: qa_bay_technician_527 is not the live text'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='karratha_sales_accessories_528' AND added_in='r528' AND fault_id='F142' AND sort_order=309) IS DISTINCT FROM '00b536a80f0faaf8a11cf184156df5b5' THEN RAISE EXCEPTION 'r529: karratha_sales_accessories_528 is not the live text'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450' AND added_in='r450' AND fault_id='F63' AND sort_order=249) IS DISTINCT FROM '7d6f5fdff816778f5c2c10c943ada173' THEN RAISE EXCEPTION 'r529: bus_whole_job_450 is not the live text'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495' AND added_in='r495' AND fault_id='F108' AND sort_order=295) IS DISTINCT FROM '8ff7e1e97dd9cb89ed5ff4e43ce98da9' THEN RAISE EXCEPTION 'r529: sales_branch_495 is not the live text'; END IF;
 IF (SELECT description FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495') NOT LIKE '%Broome account scope kept%' THEN RAISE EXCEPTION 'r529: sales_branch_495 description changed'; END IF;
END $g$;

-- Drop the whole-table pin totals. The case assertions stay.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $pin225$   AND (SELECT count(*) FROM pdc_ops.expected_function_md5)=225
$pin225$, '')
WHERE check_name IN ('outlook_parts_completion_514','outlook_internal_parts_auth_515')
  AND check_sql LIKE '%expected_function_md5)=225%';

-- r515 also pinned the entire r514 check text, so that equality would go red when the pin line is removed.
-- The person-hash LIKE on the r514 check stays.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $md515$   AND (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128' AND sort_order=301)
       = md5(replace((SELECT body FROM pdc_ops.r515_person_parts_prev WHERE signature='check514'),'eb02f76ec94cd0b6c824a18660432afa','8ddb1477beeb94c7879c4021cccf1d40'))
$md515$, '')
WHERE check_name='outlook_internal_parts_auth_515'
  AND sort_order=302
  AND fault_id='F129'
  AND check_sql LIKE '%r515_person_parts_prev%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $pin236$ AND (SELECT count(*) FROM pdc_ops.expected_function_md5)=236
$pin236$, '')
WHERE check_name='qa_bay_technician_527'
  AND sort_order=308
  AND fault_id='F141'
  AND check_sql LIKE '%expected_function_md5)=236%';

-- r523 relabelled before_import_rules_20261017 off r450. The other 16 r450 pins still match. Do not put that row back.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
 '(SELECT n FROM pins)=17 AND (SELECT ok FROM pins)=17',
 '(SELECT n FROM pins)=16 AND (SELECT ok FROM pins)=16 AND (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature=''pdc_work_categories_private.before_import_rules_20261017(uuid)'')=''r523'' AND (SELECT e.prosrc_md5 IS NOT DISTINCT FROM md5(p.prosrc) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.signature=''pdc_work_categories_private.before_import_rules_20261017(uuid)'')')
WHERE check_name='bus_whole_job_450'
  AND sort_order=249
  AND fault_id='F63'
  AND check_sql LIKE '%(SELECT n FROM pins)=17 AND (SELECT ok FROM pins)=17%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
 $d450$ ||'; r450 pins matching: '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)$d450$,
 $d450b$ ||'; r450 pins matching: '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)
 ||'; before_import_rules '||coalesce((SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)'),'missing')$d450b$)
WHERE check_name='bus_whole_job_450'
  AND sort_order=249
  AND check_sql LIKE '%r450 pins matching:%'
  AND check_sql NOT LIKE '%before_import_rules%';

-- CF Clint Franklin is on Karratha 14450. SL Scott Lovett may stay on Broome 37047 or move to 14450.
-- Anyone else on 14450, or CF/SL on another dealer, is still a leak.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $old495$         (SELECT count(*) FROM pdc_sales_private.account_scopes a JOIN public.salespeople s ON s.id=a.salesperson_id
           WHERE upper(btrim(s.code)) IN ('CF','SL') AND a.dealer_code<>'37047') moved_scopes$old495$,
 $new495$         (SELECT count(*) FROM pdc_sales_private.account_scopes a JOIN public.salespeople s ON s.id=a.salesperson_id
           WHERE (upper(btrim(s.code)) IN ('CF','SL') AND a.dealer_code NOT IN ('37047','14450'))
              OR (a.dealer_code='14450' AND NOT (upper(btrim(s.code)) IN ('CF','SL') AND lower(btrim(s.name)) IN ('clint franklin','scott lovett')))) leaks$new495$)
WHERE check_name='sales_branch_495'
  AND sort_order=295
  AND fault_id='F108'
  AND check_sql LIKE '%dealer_code<>''37047'') moved_scopes%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, 'moved_scopes', 'leaks')
WHERE check_name='sales_branch_495'
  AND sort_order=295
  AND check_sql LIKE '%moved_scopes%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, 'CF/SL scopes moved off Broome: ', 'CF/SL branch leaks: '),
    description = replace(description, 'Broome account scope kept', 'CF and SL Sales scope may be 37047 or 14450; 14450 on any other person is a leak')
WHERE check_name='sales_branch_495'
  AND sort_order=295
  AND description LIKE '%Broome account scope kept%';

UPDATE pdc_ops.regression_checks
SET check_sql = 'SELECT (' || substr(check_sql, 7) || $k$) AS ok, 'Karratha Sales accessories stay on dealer 14450 and the Broome importer is unchanged' AS detail$k$
WHERE check_name='karratha_sales_accessories_528'
  AND sort_order=309
  AND fault_id='F142'
  AND md5(check_sql)='00b536a80f0faaf8a11cf184156df5b5'
  AND left(check_sql, 6)='SELECT';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('regression_checks_self_test','F143','Regression checks (r529): each check exposes ok and detail, and none compares the whole pin table to a literal count',
 $chk529$SELECT
 (SELECT count(*) FROM pdc_ops.regression_checks c
   WHERE NOT (
       (c.check_sql ~* $re1$as\s+ok\M$re1$ AND c.check_sql ~* $re2$as\s+detail\M$re2$)
       OR (c.check_sql ~* $re3$\.\s*ok\M$re3$ AND c.check_sql ~* $re4$\.\s*detail\M$re4$)
     )
     OR c.check_sql ~* $re5$expected_function_md5\s*\)\s*(=|<>|!=|is\s+distinct\s+from|is\s+not\s+distinct\s+from)\s*[0-9]+$re5$
     OR c.check_sql ~* $re6$[0-9]+\s*(=|<>|!=)\s*\(\s*select\s+count\(\s*\*\s*\)\s+from\s+pdc_ops\.expected_function_md5\s*\)$re6$
 )=0 AS ok,
 coalesce((SELECT string_agg(c.check_name, ', ' ORDER BY c.sort_order, c.check_name)
   FROM pdc_ops.regression_checks c
   WHERE NOT (
       (c.check_sql ~* $re1$as\s+ok\M$re1$ AND c.check_sql ~* $re2$as\s+detail\M$re2$)
       OR (c.check_sql ~* $re3$\.\s*ok\M$re3$ AND c.check_sql ~* $re4$\.\s*detail\M$re4$)
     )
     OR c.check_sql ~* $re5$expected_function_md5\s*\)\s*(=|<>|!=|is\s+distinct\s+from|is\s+not\s+distinct\s+from)\s*[0-9]+$re5$
     OR c.check_sql ~* $re6$[0-9]+\s*(=|<>|!=)\s*\(\s*select\s+count\(\s*\*\s*\)\s+from\s+pdc_ops\.expected_function_md5\s*\)$re6$
 ), 'checks expose ok and detail, and none lock the pin total') AS detail$chk529$,
 true, 310, 'r529');

DO $p$ DECLARE y record; n text; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r529: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r529_tick') THEN RAISE EXCEPTION 'r529: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r529_frc') THEN RAISE EXCEPTION 'r529: fault_regression_check changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_sql LIKE '%expected_function_md5)=225%' OR check_sql LIKE '%expected_function_md5)=236%') THEN RAISE EXCEPTION 'r529: a total pin literal remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515' AND check_sql LIKE '%r515_person_parts_prev%') THEN RAISE EXCEPTION 'r529: r515 still freezes the r514 check text'; END IF;
 IF (SELECT left(check_sql,8) FROM pdc_ops.regression_checks WHERE check_name='karratha_sales_accessories_528') IS DISTINCT FROM 'SELECT (' THEN RAISE EXCEPTION 'r529: karratha check was not wrapped'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test' AND fault_id='F143' AND sort_order=310 AND added_in='r529' AND enabled) THEN RAISE EXCEPTION 'r529: self-test missing'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOREACH n IN ARRAY ARRAY['outlook_parts_completion_514','outlook_internal_parts_auth_515','qa_bay_technician_527','karratha_sales_accessories_528','bus_whole_job_450','sales_branch_495','regression_checks_self_test'] LOOP
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name=n) INTO y;
  IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r529: % not ok: %', n, y.detail; END IF;
 END LOOP;
 PERFORM set_config('search_path','public, extensions',true);
END $p$;
