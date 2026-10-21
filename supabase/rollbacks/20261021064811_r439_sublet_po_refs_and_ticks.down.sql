-- r439 undo (F50). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Puts back the exact-fifteen CW CSV / unchanged workbook
-- header contract, then drops the r439 check, pins, functions and the four r439 tables. Their data goes with them: GP PO refs (PMB Email
-- can re-run import_sublet_pos_439 with the same files after a re-apply), 'sublet done' ticks and their history, import receipts. Every
-- tick, untick and import is also in the PDC audit log (audit_events, table_name pdc_sublet_line_ticks_439 / pdc_service_line_po_refs_439),
-- which this undo keeps. r439 changed no line category, bay, booking or other row. Revert the PR as well.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r439 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r439 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r439 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT count(*) FROM (VALUES ('pdc_work_categories_private.sublet_line_key_439(jsonb)','099708a1aa8f0d76d148152fd2b5f965'),('pdc_work_categories_private.sublet_po_vehicle_439(uuid)','bf4f60277f69b53cbd982c7aa24b2401'),('pdc_work_categories_private.sublet_tick_role_439(uuid)','b0b6a97bf5642e1ed0796bd37ff01dac'),('pdc_codex_intake_private.revolution_service_headers_439(jsonb,jsonb)','bfda8a3acd8a08bb36f5851ead2cd5e4'),('public.get_pdc_sublet_po_board_439()','7dde7e19d31b269136a93ebecd12217a'),('public.get_pdc_sublet_lines_439(uuid)','b211d82171b565ee841c08ae9023c297'),('public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)','709b0156a11db82721e6acb40c2c947b'),('public.import_sublet_pos_439(jsonb,text,boolean)','6cc118c512e103e33bfe94118b91d8a1'),('public.pdc_sublet_line_tick_history_append_only_439()','2d7abb89fad05067312e2dfe6bf5320f'),('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)','88c75359be6f3e4802c3c1a8f8fd3e10')) e(s,m)
     JOIN pg_proc p ON p.oid=to_regprocedure(e.s) WHERE md5(p.prosrc)=e.m)<>10 THEN RAISE EXCEPTION 'r439 undo: functions are not the r439 versions; not undoing over unknown changes'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='sublet_po_category_and_ticks' AND added_in='r439') IS DISTINCT FROM '316a5c862f738c9f433ab1840fab1ff9' THEN RAISE EXCEPTION 'r439 undo: check is not the r439 version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r439')<>10 THEN RAISE EXCEPTION 'r439 undo: expected exactly 10 r439 pins'; END IF;
 IF EXISTS(SELECT 1 FROM pg_depend d WHERE d.refobjid IN (to_regclass('public.pdc_service_line_po_refs_439'),to_regclass('public.pdc_sublet_line_ticks_439'),to_regclass('public.pdc_sublet_line_tick_history_439'),to_regclass('public.pdc_sublet_po_import_receipts_439'))
      AND d.deptype='n' AND d.classid='pg_rewrite'::regclass) THEN RAISE EXCEPTION 'r439 undo: a view depends on r439 tables'; END IF;
END $g$;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_manifest_20261006(p_provenance jsonb, p_message_id text, p_filename text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $f$
 SELECT coalesce(p_provenance->>'authority'='explicit_user_request'
 AND length(p_provenance->>'user_instruction')>20
 AND p_provenance->>'company'='01' AND p_provenance->>'division'='1'
 AND pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_provenance->'authentication',p_message_id)
 AND (
  (p_provenance->>'source_kind'='revolution_automated_service_workbook'
   AND p_provenance->>'subject'='PMG PD Service Complete'
   AND p_filename ~ '^PMG PD Service Complete( - Job 1)?[.]xlsx?$'
   AND p_provenance->>'source_format'='ooxml_workbook')
  OR
  (p_provenance->>'source_kind'='revolution_automated_service_csv'
   AND p_provenance->>'subject'='CW PMB Service Complete'
   AND p_filename='.csv' AND p_provenance->>'source_format'='csv'
   AND p_provenance->'source_headers'='["Type","Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Status","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb
   AND p_provenance->>'snapshot_basis'='authenticated_revolution_email_date'
   AND p_provenance->>'source_scope_basis'='craig_20261019_fixed_company01_division1'
   AND p_provenance->>'source_snapshot_at'=p_provenance->>'producer_email_date_utc'
   AND p_provenance->>'producer_email_date_utc' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
   AND p_provenance->>'received_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
   AND abs(extract(epoch from ((p_provenance->>'received_at')::timestamptz-(p_provenance->>'producer_email_date_utc')::timestamptz)))<=300)
 ),false);
$f$;

DELETE FROM pdc_ops.expected_function_md5 WHERE release='r439';
DELETE FROM pdc_ops.regression_checks WHERE check_name='sublet_po_category_and_ticks' AND added_in='r439';
DROP TABLE public.pdc_sublet_line_tick_history_439;
DROP TABLE public.pdc_sublet_line_ticks_439;
DROP TABLE public.pdc_sublet_po_import_receipts_439;
DROP TABLE public.pdc_service_line_po_refs_439;
DROP FUNCTION public.import_sublet_pos_439(jsonb,text,boolean);
DROP FUNCTION public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid);
DROP FUNCTION public.get_pdc_sublet_lines_439(uuid);
DROP FUNCTION public.get_pdc_sublet_po_board_439();
DROP FUNCTION pdc_work_categories_private.sublet_tick_role_439(uuid);
DROP FUNCTION pdc_work_categories_private.sublet_po_vehicle_439(uuid);
DROP FUNCTION pdc_codex_intake_private.revolution_service_headers_439(jsonb,jsonb);
DROP FUNCTION pdc_work_categories_private.sublet_line_key_439(jsonb);
DROP FUNCTION public.pdc_sublet_line_tick_history_append_only_439();
DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)<>'d232aef8ffdb0506a6befe125ff1cfe0'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure)<>'97fc4caaf7b462163d35b4a3511bc487'
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r439' OR signature='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r439')
    OR to_regclass('public.pdc_service_line_po_refs_439') IS NOT NULL OR to_regclass('public.pdc_sublet_line_ticks_439') IS NOT NULL OR to_regclass('public.pdc_sublet_line_tick_history_439') IS NOT NULL OR to_regclass('public.pdc_sublet_po_import_receipts_439') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc WHERE proname IN ('sublet_line_key_439','sublet_po_vehicle_439','sublet_tick_role_439','revolution_service_headers_439','get_pdc_sublet_po_board_439','get_pdc_sublet_lines_439','set_pdc_sublet_line_tick_439','import_sublet_pos_439','pdc_sublet_line_tick_history_append_only_439'))
 THEN RAISE EXCEPTION 'r439 undo: did not fully undo'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r439 undo: clock tick changed'; END IF;
END $g$;
