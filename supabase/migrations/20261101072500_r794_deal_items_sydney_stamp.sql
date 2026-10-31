-- r794 (F403). Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 07:13 AWST: BT and KTA deal items refused on Apply: "extract stamp
-- 2026-11-01 02:00:00+00 is later than received_at; check extract_tz".
-- Caused by r781 (mine): run_other_781 told the sales importers the "Extracted on ..." stamp is Perth time. Revolution stamps it in
-- Sydney time: the file says 10:02 AM and was created 23:02 UTC (07:02 Perth); Kajel receipts agree (07:00 PM stamp, received 08:00 UTC).
-- The 05:52 upload only passed because that file was extracted the evening before.
-- Fix: run_other_781 sends extract_tz 'Australia/Sydney' (daylight saving handled by the zone).
-- Rollback: supabase/rollbacks/20261101072500_r794_deal_items_sydney_stamp.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.run_other_781()@r794pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.run_other_781()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r794$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_import_620.run_other_781()'::regprocedure;
  a1 text := $a$'extract_tz', 'Australia/Perth'$a$;
  b1 text := $a$'extract_tz', 'Australia/Sydney' /* r794 (F403): Revolution stamps in Sydney time */$a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r794: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 577 OR fault_id = 'F403' OR added_in = 'r794') THEN RAISE EXCEPTION 'r794: sort 577 or F403 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.other_uploads_781 WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r794: an upload is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '811edc9940e82f580a027a82835ede35' THEN RAISE EXCEPTION 'r794: run_other_781 is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r794: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r794: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE position(md5(v_old) IN check_sql) > 0;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('deal_items_sydney_stamp_794', 'F403',
    'Upload (r794): website deal-item uploads read the Revolution "Extracted on" stamp as Sydney time.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_other_781()')), $q$'extract_tz', 'Australia/Sydney'$q$) > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_other_781()')), $q$'extract_tz', 'Australia/Perth'$q$) = 0
 AS ok, 'deal-item stamp read in Sydney time' AS detail
$chk$, true, 577, 'r794');
END $r794$;
