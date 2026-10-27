-- Undo r579 (F192) / sort 350. Restores the two bay checks to the bodies this release replaced.
-- Does not rename a bay or edit a booking. Pin count stays 241.

SET LOCAL lock_timeout = '2s';

DO $g$
DECLARE n0 text; nq text; g0 text; gq text;
  cut text := $cut$  AND (live.reason IS NULL OR live.reason LIKE 'Waiting for Chelsea Rees # 2 on Key 411 (Fitting - PMB Bay 10) until %')
  AS ok,$cut$;
BEGIN
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r579 undo: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r579 undo: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='bay_code_identity_579' AND fault_id='F192' AND sort_order=350 AND added_in='r579')<>1 THEN
    RAISE EXCEPTION 'r579 undo: identity check missing';
  END IF;
  SELECT check_sql INTO n0 FROM pdc_ops.regression_checks WHERE check_name='pmb_bay_names_483';
  nq := replace(n0, $b$duplicate codes: $b$, $a$duplicate names: $a$);
  nq := replace(nq, $b$20/20 bays match id, code and active flag$b$, $a$20/20 bays named per Craig''s list$a$);
  nq := replace(nq, $b$wrong code or active flag: $b$, $a$wrong name: $a$);
  nq := replace(nq, $b$SELECT code FROM public.workshop_bays GROUP BY code HAVING count(*)>1$b$, $a$SELECT display_name FROM public.workshop_bays GROUP BY display_name HAVING count(*)>1$a$);
  nq := replace(nq, $b$b.is_active = (m.stage_code <> 'ELECTRICAL' OR m.bay_number <= 7)$b$, $a$(NOT b.is_active OR b.display_name=m.new_name)$a$);
  IF md5(nq) IS DISTINCT FROM '8b93e7f79791e0af4d3ba60de836275b' THEN
    RAISE EXCEPTION 'r579 undo: bay name body would not match the previous md5';
  END IF;
  UPDATE pdc_ops.regression_checks SET check_sql=nq WHERE check_name='pmb_bay_names_483';

  SELECT check_sql INTO g0 FROM pdc_ops.regression_checks WHERE check_name='close_gaps_preview_bay_label_and_tech_reason';
  gq := replace(g0, $b$'codes '||bay06.code||' '||bay06.id::text||' and '||bay10.code||' '||bay10.id::text||' active; plan bc237d9f'$b$,
    $a$pg_catalog.left(coalesce(live.reason, 'labels only; Key 248 is not still held by Chelsea on Key 411'::text)
    || ' | bay 1 ' || bay06.display_name || ' | bay 5 ' || bay10.display_name, 500)$a$);
  gq := replace(gq, '  AS ok,', cut);
  gq := replace(gq, $b$AND bay10.id = 'ff080124-3632-4a07-944c-e0fb0f45fa1b'::uuid$b$, $a$AND bay10.display_name = 'Fitting - PMB Bay 10'$a$);
  gq := replace(gq, $b$AND bay06.id = '2dfbb177-f353-4f4f-9668-6519909d418a'::uuid$b$, $a$AND bay06.display_name = 'Fitting - PMB Bay 06'$a$);
  IF md5(gq) IS DISTINCT FROM '9f468149645af4563fa18efeed061efc' THEN
    RAISE EXCEPTION 'r579 undo: close-gaps body would not match the previous md5';
  END IF;
  UPDATE pdc_ops.regression_checks SET check_sql=gq WHERE check_name='close_gaps_preview_bay_label_and_tech_reason';

  DELETE FROM pdc_ops.regression_checks WHERE check_name='bay_code_identity_579' AND fault_id='F192' AND sort_order=350 AND added_in='r579';
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_code_identity_579' OR fault_id='F192' OR sort_order=350) THEN
    RAISE EXCEPTION 'r579 undo: identity check remains';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r579 undo: pin count changed'; END IF;
END $g$;
