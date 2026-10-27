-- r579 (F192) / sort 350. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- The two known bay reds still key on display names. Those names are now the
-- technician on the bay (Chelsea Rees, Samuel, Jamie, ...), so the checks fail
-- even though the bay id, code and active flag are right. This release retargets
-- them onto id, code and is_active. It does not rename a bay, edit a booking,
-- or move a pin. Pin count stays 241.
-- r577 is on the ledger from the rolled-back Bay Manager hours release. r578 is
-- left for #564. F191 and sort 349 stay unused for that rework. This is r579 /
-- F192 / sort 350.
-- Undo: supabase/rollbacks/20261028020000_r579_bay_code_checks.down.sql

SET LOCAL lock_timeout = '2s';

DO $g$ BEGIN
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r579: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r579: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN
    RAISE EXCEPTION 'r579: pin count is not 241';
  END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=350 OR fault_id='F192' OR added_in='r579' OR check_name='bay_code_identity_579') THEN
    RAISE EXCEPTION 'r579: sort 350 / F192 is taken';
  END IF;
  IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='pmb_bay_names_483')
       IS DISTINCT FROM '8b93e7f79791e0af4d3ba60de836275b' THEN
    RAISE EXCEPTION 'r579: pmb_bay_names_483 is not the live body';
  END IF;
  IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='close_gaps_preview_bay_label_and_tech_reason')
       IS DISTINCT FROM '9f468149645af4563fa18efeed061efc' THEN
    RAISE EXCEPTION 'r579: close-gaps check is not the live body';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)'::regprocedure)
       IS DISTINCT FROM 'bc237d9f466c45a086c251ec8c3071a7' THEN
    RAISE EXCEPTION 'r579: workshop_capacity_plan changed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='electrical_bays_7_566' AND fault_id='F180' AND sort_order=348 AND added_in='r566') THEN
    RAISE EXCEPTION 'r579: electrical_bays_7_566 is missing';
  END IF;
END $g$;

DO $u$
DECLARE
  n0 text; nq text; g0 text; gq text;
  nr record; gr record; idn record;
  cut text := $cut$  AND (live.reason IS NULL OR live.reason LIKE 'Waiting for Chelsea Rees # 2 on Key 411 (Fitting - PMB Bay 10) until %')
  AS ok,$cut$;
BEGIN
  SELECT check_sql INTO n0 FROM pdc_ops.regression_checks WHERE check_name='pmb_bay_names_483';
  nq := replace(n0, $a$(NOT b.is_active OR b.display_name=m.new_name)$a$, $b$b.is_active = (m.stage_code <> 'ELECTRICAL' OR m.bay_number <= 7)$b$);
  nq := replace(nq, $a$SELECT display_name FROM public.workshop_bays GROUP BY display_name HAVING count(*)>1$a$, $b$SELECT code FROM public.workshop_bays GROUP BY code HAVING count(*)>1$b$);
  nq := replace(nq, $a$wrong name: $a$, $b$wrong code or active flag: $b$);
  nq := replace(nq, $a$20/20 bays named per Craig''s list$a$, $b$20/20 bays match id, code and active flag$b$);
  nq := replace(nq, $a$duplicate names: $a$, $b$duplicate codes: $b$);
  IF nq = n0 OR strpos(nq, 'display_name=m.new_name')>0 OR strpos(nq, 'b.is_active = (m.stage_code <> ''ELECTRICAL'' OR m.bay_number <= 7)')=0 THEN
    RAISE EXCEPTION 'r579: bay name check was not retargeted';
  END IF;
  UPDATE pdc_ops.regression_checks SET check_sql=nq WHERE check_name='pmb_bay_names_483';

  SELECT check_sql INTO g0 FROM pdc_ops.regression_checks WHERE check_name='close_gaps_preview_bay_label_and_tech_reason';
  IF strpos(g0, cut)=0 THEN RAISE EXCEPTION 'r579: close-gaps hold clause missing'; END IF;
  gq := replace(g0, $a$AND bay06.display_name = 'Fitting - PMB Bay 06'$a$, $b$AND bay06.id = '2dfbb177-f353-4f4f-9668-6519909d418a'::uuid$b$);
  gq := replace(gq, $a$AND bay10.display_name = 'Fitting - PMB Bay 10'$a$, $b$AND bay10.id = 'ff080124-3632-4a07-944c-e0fb0f45fa1b'::uuid$b$);
  gq := replace(gq, cut, '  AS ok,');
  gq := replace(gq, $a$pg_catalog.left(coalesce(live.reason, 'labels only; Key 248 is not still held by Chelsea on Key 411'::text)
    || ' | bay 1 ' || bay06.display_name || ' | bay 5 ' || bay10.display_name, 500)$a$,
    $b$'codes '||bay06.code||' '||bay06.id::text||' and '||bay10.code||' '||bay10.id::text||' active; plan bc237d9f'$b$);
  IF gq = g0 OR strpos(gq, 'live.reason IS NULL')>0 OR strpos(gq, '2dfbb177-f353-4f4f-9668-6519909d418a')=0 THEN
    RAISE EXCEPTION 'r579: close-gaps check was not retargeted';
  END IF;
  UPDATE pdc_ops.regression_checks SET check_sql=gq WHERE check_name='close_gaps_preview_bay_label_and_tech_reason';

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES (
    'bay_code_identity_579', 'F192',
    'r579: pmb_bay_names_483 and close_gaps_preview_bay_label_and_tech_reason key on bay id, code and is_active. Elec 01-07 stay active and 08-10 stay hidden. Fitting Bay 01 and Bay 05 stay the same rows. Pin count stays 241.',
    $c$SELECT
  pg_catalog.strpos(names.check_sql, 'b.is_active = (m.stage_code <> ''ELECTRICAL'' OR m.bay_number <= 7)') > 0
  AND pg_catalog.strpos(names.check_sql, 'display_name=m.new_name') = 0
  AND pg_catalog.strpos(gaps.check_sql, '2dfbb177-f353-4f4f-9668-6519909d418a') > 0
  AND pg_catalog.strpos(gaps.check_sql, 'ff080124-3632-4a07-944c-e0fb0f45fa1b') > 0
  AND pg_catalog.strpos(gaps.check_sql, 'live.reason IS NULL') = 0
  AND bay06.id = '2dfbb177-f353-4f4f-9668-6519909d418a'::uuid
  AND bay10.id = 'ff080124-3632-4a07-944c-e0fb0f45fa1b'::uuid
  AND bay06.code = 'FITTING-BAY-01' AND bay06.is_active AND bay06.bay_number = 1
  AND bay10.code = 'FITTING-BAY-05' AND bay10.is_active AND bay10.bay_number = 5
  AND (SELECT count(*) FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
        WHERE s.code='ELECTRICAL' AND NOT b.is_sublet_row AND b.is_active) = 7
  AND (SELECT count(*) FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
        WHERE s.code='ELECTRICAL' AND b.bay_number IN (8,9,10) AND NOT b.is_active) = 3
  AS ok,
  'codes FITTING-BAY-01 and FITTING-BAY-05; Elec 01-07 active, 08-10 hidden' AS detail
FROM pdc_ops.regression_checks names
JOIN pdc_ops.regression_checks gaps ON gaps.check_name = 'close_gaps_preview_bay_label_and_tech_reason'
JOIN public.workshop_bays bay06 ON bay06.code = 'FITTING-BAY-01'
JOIN public.workshop_bays bay10 ON bay10.code = 'FITTING-BAY-05'
WHERE names.check_name = 'pmb_bay_names_483'$c$,
    true, 350, 'r579');

  PERFORM set_config('search_path', 'pg_catalog, public', true);
  PERFORM set_config('request.jwt.claims', '', true);
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='pmb_bay_names_483') INTO nr;
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='close_gaps_preview_bay_label_and_tech_reason') INTO gr;
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bay_code_identity_579') INTO idn;
  IF coalesce(nr.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r579: bay names still red: %', left(coalesce(nr.detail,''), 300); END IF;
  IF coalesce(gr.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r579: close gaps still red: %', left(coalesce(gr.detail,''), 300); END IF;
  IF coalesce(idn.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r579: identity check red: %', left(coalesce(idn.detail,''), 300); END IF;
  IF nr.detail NOT LIKE '20/20 bays match id, code and active flag%' THEN
    RAISE EXCEPTION 'r579: bay name detail: %', left(coalesce(nr.detail,''), 200);
  END IF;
  IF gr.detail NOT LIKE 'codes FITTING-BAY-01 %' THEN
    RAISE EXCEPTION 'r579: close-gaps detail: %', left(coalesce(gr.detail,''), 200);
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r579: pin count changed'; END IF;
END $u$;
