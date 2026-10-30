-- r743 (F344 follow-up) / imports plan step 3. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 07:10: "we need to really figure out a better way to do imports so it doesnt slow the whole board down";
-- 08:11 "5 yes". pdc_import_620.run_jobs already commits after every part, so the planner lock is held per part
-- (20 to 45 s), not for the whole run. What it never did was let go between parts: with a 50 minute budget it ran
-- part after part back to back, so the board's own writes queued behind it for the whole 30 minutes. This file adds a
-- three second pause after each part while work remains (about four extra minutes on an 80 step run) so planner
-- saves, fitter taps and approvals get through between parts. Steps 1 (staging table swap) and 4 (progress banner)
-- of the plan are separate releases.
-- Rollback: supabase/rollbacks/20261030085000_r743_import_breathes_between_parts.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $r743$
DECLARE v_old text; v_new text; v_def text;
  c_old text := E'    COMMIT;\n  END LOOP;\n  PERFORM pg_catalog.pg_advisory_unlock(pg_catalog.hashtextextended(''pdc_import_620.run_jobs'', 0));';
  c_new text := E'    COMMIT;\n    -- r743: let the board''s own writes through between parts; the lock above is per part, this is the gap.\n    IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN (''queued'', ''running'')) THEN PERFORM pg_catalog.pg_sleep(3); END IF;\n  END LOOP;\n  PERFORM pg_catalog.pg_advisory_unlock(pg_catalog.hashtextextended(''pdc_import_620.run_jobs'', 0));';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r743: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r743: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'pdc_import_620.run_jobs()'::regprocedure;
  IF md5(v_old) <> 'f05db04600dc405e1d1c269ad26ee5d5' THEN RAISE EXCEPTION 'r743: run_jobs is not the r620 body'; END IF;
  IF (length(v_old) - length(replace(v_old, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r743: anchor not found once'; END IF;
  v_new := replace(v_old, c_old, c_new);
  v_def := regexp_replace(pg_get_functiondef('pdc_import_620.run_jobs()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'pdc_import_620.run_jobs()'::regprocedure) <> v_new THEN RAISE EXCEPTION 'r743: readback differs'; END IF;
END $r743$;
