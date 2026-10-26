-- r553 (F167) undo. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Restores the r505 workbook arms, the r505 parts pin, and the r505 outlook check md5.
-- Pin count stays 241. Deletes parts_import_cw_rename. Does not rewrite parts rows.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r553 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r553 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r553 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) IS DISTINCT FROM 'e56cd1f5d12205a0d72826d64cb8d1de' THEN RAISE EXCEPTION 'r553 undo: parts prosrc is not r553'; END IF;
 IF (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) IS DISTINCT FROM '76b0570ee2c788d5cacf9d01a5843ed6' THEN RAISE EXCEPTION 'r553 undo: parts functiondef is not r553'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)' AND prosrc_md5='e56cd1f5d12205a0d72826d64cb8d1de' AND release='r553')<>1 THEN RAISE EXCEPTION 'r553 undo: parts pin is not r553'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='parts_import_cw_rename' AND fault_id='F167' AND sort_order=328 AND added_in='r553')<>1 THEN RAISE EXCEPTION 'r553 undo: check missing'; END IF;
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
 IF v_src IS NULL THEN RAISE EXCEPTION 'r553 undo: parts importer missing'; END IF;
 IF (length(v_src)-length(replace(v_src, v_new, '')))/length(v_new) <> 1 THEN RAISE EXCEPTION 'r553 undo: CW arm is not unique'; END IF;
 v_src := replace(v_src, v_new, v_old);
 IF md5(v_src) IS DISTINCT FROM 'ccf492618ca11625470b691fbe029ac7' THEN RAISE EXCEPTION 'r553 undo: restored prosrc md5'; END IF;
 v_sql := $sql$CREATE OR REPLACE FUNCTION public.pdc_import_job_parts_csv_20260912(p_envelope jsonb, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pdc_parts_private'
AS $r553body$$sql$ || v_src || $sql$$r553body$$sql$;
 EXECUTE v_sql;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) IS DISTINCT FROM 'ccf492618ca11625470b691fbe029ac7' THEN RAISE EXCEPTION 'r553 undo: stored prosrc md5'; END IF;
 IF (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(pg_catalog.jsonb,pg_catalog.jsonb)')) IS DISTINCT FROM '2868827fe333373debf7b40194f5d46c' THEN RAISE EXCEPTION 'r553 undo: stored functiondef md5'; END IF;

 UPDATE pdc_ops.expected_function_md5
 SET prosrc_md5='ccf492618ca11625470b691fbe029ac7',
     release='r505',
     note='r505 (F118): mailbox pdc@ + Outlook message id coalesce (was 986b89b3ca9180765fdc3f70bb7b49d5, unpinned)',
     updated_at=clock_timestamp()
 WHERE signature='public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)'
   AND prosrc_md5='e56cd1f5d12205a0d72826d64cb8d1de'
   AND release='r553';
 GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'r553 undo: parts pin was not restored'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r553 undo: pin count changed'; END IF;

 UPDATE pdc_ops.regression_checks
 SET check_sql=replace(check_sql, 'e56cd1f5d12205a0d72826d64cb8d1de', 'ccf492618ca11625470b691fbe029ac7')
 WHERE check_name='outlook_pdc_auth_505'
   AND fault_id='F118'
   AND sort_order=290
   AND added_in='r505'
   AND length(check_sql)=7303
   AND (length(check_sql)-length(replace(check_sql,'e56cd1f5d12205a0d72826d64cb8d1de','')))/32=1;
 GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'r553 undo: outlook check was not restored'; END IF;
 IF (SELECT length(check_sql)<>7303
     OR position('e56cd1f5d12205a0d72826d64cb8d1de' IN check_sql)>0
     OR (length(check_sql)-length(replace(check_sql,'ccf492618ca11625470b691fbe029ac7','')))/32<>1
     FROM pdc_ops.regression_checks WHERE check_name='outlook_pdc_auth_505' AND fault_id='F118' AND sort_order=290 AND added_in='r505') THEN
  RAISE EXCEPTION 'r553 undo: outlook check md5 was not restored';
 END IF;

 DELETE FROM pdc_ops.regression_checks
 WHERE check_name='parts_import_cw_rename'
   AND fault_id='F167'
   AND sort_order=328
   AND added_in='r553';
 GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'r553 undo: check was not deleted'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_import_cw_rename' OR fault_id='F167' OR sort_order=328 OR added_in='r553') THEN RAISE EXCEPTION 'r553 undo: check remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r553 undo: pin count changed'; END IF;
END $patch$;
