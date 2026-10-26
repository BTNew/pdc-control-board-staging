-- r553 (F167). Craig approved go-live 26 Oct 2026 16:16 AWST, after #530.
-- Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- The Pilbara Revolution workbook was renamed. The 14:03 AWST message has subject
-- CW PMG PD Parts Status Complete and file CW PMG PD Parts Status Complete - Job 1.xls.
-- Widen only the revolution_automated_parts_workbook name test so that subject and
-- source_file ^(CW )?PMG PD Parts Status Complete( - Job 1)?[.]xlsx?$ are accepted.
-- The Pilbara arm and the V1 arm stay byte-identical. Every other envelope check stays.
-- Codex #534-#538 stay as merged on main 249bca97, including new-addition routing.
-- The inserted newlines are LF. The rest of the body stays CRLF.
-- Pin count stays 241. The parts pin moves in place from r505.
-- outlook_pdc_auth_505 changes only that pinned prosrc md5 (length stays 7303).
-- r551 is the helper-table lockdown (ledger 20261026110756) and is not reused.
-- F165 and sort 326 were the old preview numbers and are not reused.
-- r552 / F166 / sort 327 is the open clock-step preview (#533).
-- This is r553 / F167 / sort 328.
-- Undo: supabase/rollbacks/20261027040000_r553_parts_import_cw_rename.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r553: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r553: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r553: pin count is not 241'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=328 OR fault_id='F167' OR check_name='parts_import_cw_rename' OR added_in='r553') THEN RAISE EXCEPTION 'r553: sort 328 / F167 is taken'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) IS DISTINCT FROM 'ccf492618ca11625470b691fbe029ac7' THEN RAISE EXCEPTION 'r553: parts prosrc is not the r505 body'; END IF;
 IF (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) IS DISTINCT FROM '2868827fe333373debf7b40194f5d46c' THEN RAISE EXCEPTION 'r553: parts functiondef drifted'; END IF;
 IF (SELECT position(chr(13) IN prosrc)=0 OR position('$r553body$' IN prosrc)>0 FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) THEN RAISE EXCEPTION 'r553: parts body is not the CRLF r505 body'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)' AND prosrc_md5='ccf492618ca11625470b691fbe029ac7' AND release='r505')<>1 THEN RAISE EXCEPTION 'r553: parts pin is not r505'; END IF;
 IF (SELECT length(check_sql)<>7303 OR (length(check_sql)-length(replace(check_sql,'ccf492618ca11625470b691fbe029ac7','')))/32<>1 FROM pdc_ops.regression_checks WHERE check_name='outlook_pdc_auth_505' AND fault_id='F118' AND sort_order=290 AND added_in='r505') THEN RAISE EXCEPTION 'r553: outlook_pdc_auth_505 is not the r505 check'; END IF;
END $g$;

DO $patch$
DECLARE
  v_src text;
  v_sql text;
  v_n integer;
  v_old text := E'      AND p_envelope->>''source_file'' ~ ''^PMG PD Parts Status V1 - Job 1[.]xlsx?$''),false)';
  v_new text := E'      AND p_envelope->>''source_file'' ~ ''^PMG PD Parts Status V1 - Job 1[.]xlsx?$'')\n    OR (p_envelope->>''subject''=''CW PMG PD Parts Status Complete''\n      AND p_envelope->>''source_file'' ~ ''^(CW )?PMG PD Parts Status Complete( - Job 1)?[.]xlsx?$''),false)';
BEGIN
 SELECT prosrc INTO v_src FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)');
 IF v_src IS NULL THEN RAISE EXCEPTION 'r553: parts importer missing'; END IF;
 IF (length(v_src)-length(replace(v_src, v_old, '')))/length(v_old) <> 1 THEN RAISE EXCEPTION 'r553: workbook arm is not unique'; END IF;
 v_src := replace(v_src, v_old, v_new);
 IF md5(v_src) IS DISTINCT FROM 'e56cd1f5d12205a0d72826d64cb8d1de' THEN RAISE EXCEPTION 'r553: patched prosrc md5'; END IF;
 IF position('PMG PD Parts Status Complete - Pilbara' IN v_src)=0
    OR position('^PMG PD Parts Status Complete[.]xlsx?$' IN v_src)=0
    OR position('PMG PD Parts Status V1 - Job 1' IN v_src)=0
    OR position('CW PMG PD Parts Status Complete' IN v_src)=0
    OR position('^(CW )?PMG PD Parts Status Complete( - Job 1)?[.]xlsx?$' IN v_src)=0 THEN
  RAISE EXCEPTION 'r553: a workbook arm is missing';
 END IF;
 v_sql := $sql$CREATE OR REPLACE FUNCTION public.pdc_import_job_parts_csv_20260912(p_envelope jsonb, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pdc_parts_private'
AS $r553body$$sql$ || v_src || $sql$$r553body$$sql$;
 EXECUTE v_sql;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) IS DISTINCT FROM 'e56cd1f5d12205a0d72826d64cb8d1de' THEN RAISE EXCEPTION 'r553: stored prosrc md5'; END IF;
 IF (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) IS DISTINCT FROM '76b0570ee2c788d5cacf9d01a5843ed6' THEN RAISE EXCEPTION 'r553: stored functiondef md5'; END IF;
 IF (SELECT prosecdef OR provolatile<>'v' OR proconfig::text IS DISTINCT FROM '{"search_path=pg_catalog, public, pdc_parts_private"}' OR pg_get_function_identity_arguments(oid) IS DISTINCT FROM 'p_envelope jsonb, p_rows jsonb' FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) THEN RAISE EXCEPTION 'r553: parts header changed'; END IF;

 UPDATE pdc_ops.expected_function_md5
 SET prosrc_md5='e56cd1f5d12205a0d72826d64cb8d1de',
     release='r553',
     note='r553 (F167): CW PMG PD Parts Status Complete (was ccf492618ca11625470b691fbe029ac7, r505)',
     updated_at=clock_timestamp()
 WHERE signature='public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)'
   AND prosrc_md5='ccf492618ca11625470b691fbe029ac7'
   AND release='r505';
 GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'r553: parts pin was not moved'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r553: pin count changed'; END IF;

 UPDATE pdc_ops.regression_checks
 SET check_sql=replace(check_sql, 'ccf492618ca11625470b691fbe029ac7', 'e56cd1f5d12205a0d72826d64cb8d1de')
 WHERE check_name='outlook_pdc_auth_505'
   AND fault_id='F118'
   AND sort_order=290
   AND added_in='r505'
   AND length(check_sql)=7303
   AND (length(check_sql)-length(replace(check_sql,'ccf492618ca11625470b691fbe029ac7','')))/32=1;
 GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'r553: outlook check was not updated'; END IF;
 IF (SELECT length(check_sql)<>7303
     OR position('ccf492618ca11625470b691fbe029ac7' IN check_sql)>0
     OR (length(check_sql)-length(replace(check_sql,'e56cd1f5d12205a0d72826d64cb8d1de','')))/32<>1
     FROM pdc_ops.regression_checks WHERE check_name='outlook_pdc_auth_505' AND fault_id='F118' AND sort_order=290 AND added_in='r505') THEN
  RAISE EXCEPTION 'r553: outlook check did not stay byte-identical apart from the parts md5';
 END IF;
END $patch$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('parts_import_cw_rename', 'F167',
 'Revolution workbook names: CW PMG PD Parts Status Complete - Job 1.xls is accepted, the Pilbara and V1 names are still accepted, and an unrelated subject and file are rejected. Pin count stays 241.',
 $chk553$
SELECT
  body.prosrc_md5 = 'e56cd1f5d12205a0d72826d64cb8d1de'
  AND body.def_md5 = '76b0570ee2c788d5cacf9d01a5843ed6'
  AND pins.n = 241
  AND pin.release = 'r553'
  AND pin.prosrc_md5 = 'e56cd1f5d12205a0d72826d64cb8d1de'
  AND pg_catalog.strpos(auth505.check_sql, 'ccf492618ca11625470b691fbe029ac7') = 0
  AND pg_catalog.strpos(auth505.check_sql, 'e56cd1f5d12205a0d72826d64cb8d1de') > 0
  AND pg_catalog.length(auth505.check_sql) = 7303
  AND pg_catalog.strpos(body.prosrc, 'PMG PD Parts Status Complete - Pilbara') > 0
  AND pg_catalog.strpos(body.prosrc, '^PMG PD Parts Status Complete[.]xlsx?$') > 0
  AND pg_catalog.strpos(body.prosrc, 'PMG PD Parts Status V1 - Job 1') > 0
  AND pg_catalog.strpos(body.prosrc, 'CW PMG PD Parts Status Complete') > 0
  AND pg_catalog.strpos(body.prosrc, '^(CW )?PMG PD Parts Status Complete( - Job 1)?[.]xlsx?$') > 0
  AND (
    'CW PMG PD Parts Status Complete' = 'CW PMG PD Parts Status Complete'
    AND 'CW PMG PD Parts Status Complete - Job 1.xls' ~ '^(CW )?PMG PD Parts Status Complete( - Job 1)?[.]xlsx?$'
  )
  AND NOT (
    (
      'CW PMG PD Parts Status Complete' = 'PMG PD Parts Status Complete - Pilbara'
      AND 'CW PMG PD Parts Status Complete - Job 1.xls' ~ '^PMG PD Parts Status Complete[.]xlsx?$'
    )
    OR (
      'CW PMG PD Parts Status Complete' = 'PMG PD Parts Status'
      AND 'CW PMG PD Parts Status Complete - Job 1.xls' ~ '^PMG PD Parts Status V1 - Job 1[.]xlsx?$'
    )
  )
  AND (
    'PMG PD Parts Status Complete - Pilbara' = 'PMG PD Parts Status Complete - Pilbara'
    AND 'PMG PD Parts Status Complete.xls' ~ '^PMG PD Parts Status Complete[.]xlsx?$'
  )
  AND (
    'PMG PD Parts Status' = 'PMG PD Parts Status'
    AND 'PMG PD Parts Status V1 - Job 1.xlsx' ~ '^PMG PD Parts Status V1 - Job 1[.]xlsx?$'
  )
  AND NOT (
    (
      'Workshop hours' = 'CW PMG PD Parts Status Complete'
      AND 'notes.txt' ~ '^(CW )?PMG PD Parts Status Complete( - Job 1)?[.]xlsx?$'
    )
    OR (
      'Workshop hours' = 'PMG PD Parts Status Complete - Pilbara'
      AND 'notes.txt' ~ '^PMG PD Parts Status Complete[.]xlsx?$'
    )
    OR (
      'Workshop hours' = 'PMG PD Parts Status'
      AND 'notes.txt' ~ '^PMG PD Parts Status V1 - Job 1[.]xlsx?$'
    )
  )
 AS ok,
 pg_catalog.format('prosrc %s def %s pins %s release %s', body.prosrc_md5, body.def_md5, pins.n, pin.release) AS detail
FROM (
  SELECT pg_catalog.md5(p.prosrc) AS prosrc_md5,
         pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) AS def_md5,
         p.prosrc
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')
) body
CROSS JOIN (
  SELECT count(*) AS n FROM pdc_ops.expected_function_md5
) pins
CROSS JOIN (
  SELECT prosrc_md5, release
  FROM pdc_ops.expected_function_md5
  WHERE signature = 'public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)'
) pin
CROSS JOIN (
  SELECT check_sql
  FROM pdc_ops.regression_checks
  WHERE check_name = 'outlook_pdc_auth_505'
    AND fault_id = 'F118'
    AND sort_order = 290
    AND added_in = 'r505'
) auth505
$chk553$,
 true, 328, 'r553');

DO $chk$
DECLARE v_ok boolean; v_detail text;
BEGIN
 PERFORM set_config('search_path', 'pg_catalog', true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_import_cw_rename' AND fault_id='F167' AND sort_order=328 AND added_in='r553') INTO v_ok, v_detail;
 IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'r553: parts_import_cw_rename failed: %', coalesce(v_detail, 'no row'); END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r553: pin count changed'; END IF;
END $chk$;
