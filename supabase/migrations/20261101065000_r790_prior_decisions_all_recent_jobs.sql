-- r790 (F398) / sort 574. Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 06:40 AWST: "i already uploaded this file and im doing the
-- same one, its showing changes but nothing is different on the file?"
-- revolution_prior_decisions_728 (the hours/station decisions every new row reuses, keyed by department + description) read only the
-- LAST done apply job. Since r782 sends only changed stocks, the 06:02 job held 79 stocks, so most descriptions lost their earlier
-- decision. The same file then built different rows (hours/routing provenance) and 290 cars showed as changed. It would also have
-- changed how the next import routed and held lines.
-- Fix: each description takes its decision from the most recent done apply job (last 30 days) that has it. Where the last job has the
-- description this is exactly the old answer; otherwise it is the answer the last full file gave. The migration checks both.
-- Rollback: supabase/rollbacks/20261101065000_r790_prior_decisions_all_recent_jobs.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'public.revolution_prior_decisions_728()@r790pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'public.revolution_prior_decisions_728()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $g$ BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r790: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 574 OR fault_id = 'F398' OR added_in = 'r790') THEN RAISE EXCEPTION 'r790: sort 574 or F398 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r790: an import job is running'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.revolution_prior_decisions_728()'::regprocedure) <> 'ab705c652d453fe9f48490d5304790e4' THEN RAISE EXCEPTION 'r790: not the r728 body'; END IF;
END $g$;

CREATE TEMP TABLE r790_before ON COMMIT DROP AS SELECT public.revolution_prior_decisions_728() AS d,
  (SELECT job_id FROM pdc_import_620.jobs WHERE status = 'done' AND mode = 'apply' ORDER BY created_at DESC LIMIT 1) AS last_job;

CREATE OR REPLACE FUNCTION public.revolution_prior_decisions_728()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '60s'
AS $function$
  -- r790 (F398): each description's decision comes from the most recent done apply job (30 days) that has it, not only the last job.
  WITH r AS (SELECT DISTINCT ON (k) (x.row->>'department') || '|' || upper(regexp_replace(btrim(coalesce(x.row->>'operation_description', '')), '\s+', ' ', 'g')) AS k, x.row
        FROM pdc_import_620.job_rows x JOIN pdc_import_620.jobs j ON j.job_id = x.job_id
        WHERE j.status = 'done' AND j.mode = 'apply' AND j.created_at > clock_timestamp() - interval '30 days'
        ORDER BY k, j.created_at DESC, x.ord)
  SELECT coalesce(jsonb_object_agg(k, jsonb_strip_nulls(jsonb_build_object(
    'proposed_station', row->'proposed_station', 'routing_rule', row->'routing_rule', 'routing_provenance', row->'routing_provenance',
    'routing_rule_version', row->'routing_rule_version', 'hours_provenance', row->'hours_provenance',
    'effective_estimated_hours', row->'effective_estimated_hours', 'source_estimated_hours', row->'source_estimated_hours',
    'needs_hours_review', row->'needs_hours_review', 'arb_review', row->'arb_review'))), '{}'::jsonb) FROM r
$function$;

DO $r790$
DECLARE b jsonb; a jsonb; n_lost integer; n_diff integer;
BEGIN
  SELECT d INTO b FROM r790_before;
  a := public.revolution_prior_decisions_728();
  -- Every description the last job had keeps exactly the same decision.
  SELECT count(*) INTO n_diff FROM jsonb_each(b) e WHERE a->e.key IS DISTINCT FROM e.value;
  IF n_diff <> 0 THEN RAISE EXCEPTION 'r790: % decisions from the last job changed', n_diff; END IF;
  SELECT count(*) INTO n_lost FROM jsonb_object_keys(a);
  IF n_lost <= (SELECT count(*) FROM jsonb_object_keys(b)) THEN RAISE EXCEPTION 'r790: no earlier decisions were recovered'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('prior_decisions_recent_jobs_790', 'F398',
    'Upload (r790): prior hours/station decisions come from the most recent done apply job that has each description, so a small (changed-only) import does not drop earlier decisions.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.revolution_prior_decisions_728()')), 'r790 (F398)') > 0
   AND NOT has_function_privilege('authenticated', 'public.revolution_prior_decisions_728()', 'execute')
 AS ok, 'prior decisions read from recent jobs' AS detail
$chk$, true, 574, 'r790');
  RAISE NOTICE 'r790: decisions % -> %', (SELECT count(*) FROM jsonb_object_keys(b)), n_lost;
END $r790$;
