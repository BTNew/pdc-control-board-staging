-- r736 (F339): Craig, 30 Oct 2026 05:47 AWST: "leave those bays hidden". Hoist 01 and Tint 02 are hidden in Bay
-- Manager (F318) and bays are renamed there (Hoist 02 "Jason Ranoco", Hoist 03 "Gary", Fab 01/02 plain). The two
-- checks that froze the r483 names and active flags now assert structure (ids, numbers, codes, no duplicates, the
-- hidden set) and leave display names to Bay Manager. Staging cdsmnqxtyyoeoznmbidd only. Production never touched.
-- Rollback: supabase/rollbacks/20261030055000_r736_bay_checks_follow_bay_manager.down.sql

DO $pre736$
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r736: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'pmb_bay_names_483' AND strpos(check_sql, $a$AND b.is_active = (m.stage_code <> 'ELECTRICAL' OR m.bay_number <= 7) AS good$a$) > 0 AND strpos(check_sql, $a$(SELECT n FROM o WHERE code='TINT'),0)=2$a$) > 0) <> 1 THEN RAISE EXCEPTION 'r736: 483 anchors missing'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'fabrication_bays_14_509' AND strpos(check_sql, $a$ OR g.display_name IS DISTINCT FROM e.display_name$a$) > 0) <> 1 THEN RAISE EXCEPTION 'r736: 509 anchor missing'; END IF;
  IF (SELECT is_active FROM public.workshop_bays WHERE code = 'HOIST-BAY-01') IS DISTINCT FROM false OR (SELECT is_active FROM public.workshop_bays WHERE code = 'TINT-BAY-02') IS DISTINCT FROM false THEN RAISE EXCEPTION 'r736: Hoist 01 / Tint 02 are not hidden; this file expects them hidden'; END IF;
END $pre736$;

UPDATE pdc_ops.regression_checks
SET check_sql = replace(replace(check_sql,
   $a$AND b.is_active = (m.stage_code <> 'ELECTRICAL' OR m.bay_number <= 7) AS good$a$,
   $a$AND b.is_active = (NOT (m.stage_code = 'HOIST' AND m.bay_number = 1) AND (m.stage_code <> 'ELECTRICAL' OR m.bay_number <= 7)) AS good$a$),
   $a$(SELECT n FROM o WHERE code='TINT'),0)=2$a$, $a$(SELECT n FROM o WHERE code='TINT'),0)=1$a$),
    description = 'Dept 139 bays (r483, r509, r736): 20 bays keep id, station, bay number and code; Hoist 01 and Tint 02 are hidden in Bay Manager (Craig, 30 Oct 2026); Fab Bays 03-13 exist and are active; Bus 4x4 keeps 10 active bays, Tint 1 and Tyre 2; no two bays share a code. Display names belong to Bay Manager and are not checked. Exactly 14 fabrication bays is fabrication_bays_14_509.'
WHERE check_name = 'pmb_bay_names_483';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $a$ OR g.display_name IS DISTINCT FROM e.display_name$a$, ''),
    description = 'Fabrication has exactly 14 active bays (r509): the same ids, numbers and codes, none a sublet row. Display names belong to Bay Manager and are not checked (r736). A later fabrication bay add or hide must update this check.'
WHERE check_name = 'fabrication_bays_14_509';

DO $post736$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('pmb_bay_names_483','fabrication_bays_14_509','regression_checks_self_test') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r736: % red after apply: %', r.check_name, left(r.detail, 200); END IF;
  END LOOP;
END $post736$;
