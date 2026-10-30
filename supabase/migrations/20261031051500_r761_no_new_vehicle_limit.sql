-- r761 (F367) / sort 481. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 31 Oct 05:07: "we should let more than 15 be created in one upload, there shouldnt be a limit". The import queue
-- held an apply with more than 15 new board vehicles for an administrator (pdc_import_620.submit_finish) and the upload
-- dry run raised sanity_gate for it. From this release new cars are not limited. The gate on cars LEAVING the board
-- (more than 15 purged in one apply, pdc_import_620.apply_part) is unchanged.
-- Rollback: supabase/rollbacks/20261031051500_r761_no_new_vehicle_limit.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $r761$
DECLARE v_old text; v_new text; v_def text;
  sig regprocedure := 'pdc_import_620.submit_finish(uuid)'::regprocedure;
  a1 text := E'  IF v_job.mode = ''apply'' AND v_new > 15 THEN v_status := ''held''; v_note := format(''sanity gate: %s new board vehicles (more than 15)'', v_new); END IF;\n';
  b1 text := E'  -- r761 (F367): no limit on new board vehicles per upload; the leaving-the-board gate stays in apply_part.\n';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r761: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 481 OR fault_id = 'F367' OR added_in = 'r761') THEN RAISE EXCEPTION 'r761: sort 481 or F367 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r761: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '1b2efb3460607fd58d3eb491f05387bf' THEN RAISE EXCEPTION 'r761: submit_finish is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r761: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r761: readback differs'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('no_new_vehicle_limit_761', 'F367',
    'Upload (r761): the import queue does not hold an apply for the number of new board vehicles; the leaving-the-board gate in apply_part is still present.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.submit_finish(uuid)')), 'new board vehicles (more than 15)') = 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.apply_part(uuid,integer,boolean)')), 'pdc620_archive_gate') > 0
 AS ok, 'no limit on new cars per upload; cars leaving the board still gated' AS detail
$chk$, true, 481, 'r761');
END $r761$;
