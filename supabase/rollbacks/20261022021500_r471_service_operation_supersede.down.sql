-- r471 undo (F84): removes the r471 supersede mechanism and puts pdc_tune_operation_change_candidate_20260912 back byte for
-- byte (md5 cc5dee40fa5a86fc1caa3704af318744; its original source has CRLF line ends, rebuilt below from LF text). Staging
-- cdsmnqxtyyoeoznmbidd only, in a :02-:45 window. Refuses while any version is still retired: run the data undo(s) first
-- (release_log/r471/sql/*.down.sql), which put each retired board line back.
SET LOCAL lock_timeout = '2s';
-- DROP TABLE below needs ACCESS EXCLUSIVE on the tables the supersession table references; take them first, in one fixed
-- order, so a concurrent reader (vehicles -> adjustments) cannot deadlock with this undo (seen on staging 22 Oct 10:46 AWST).
LOCK TABLE public.vehicles, public.pdc_pilbara_service_operations, public.vehicle_workshop_line_adjustments, public.pdc_service_operation_supersessions_471 IN ACCESS EXCLUSIVE MODE;
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r471 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r471 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) AND md5(p.prosrc)=e.prosrc_md5 WHERE e.release='r471')<>4
    THEN RAISE EXCEPTION 'r471 undo: the r471 functions are not the pinned versions'; END IF;
 IF (SELECT count(*) FROM public.pdc_service_operation_supersessions_471)<>0 THEN RAISE EXCEPTION 'r471 undo: % version(s) still retired; run the r471 data undo first',(SELECT count(*) FROM public.pdc_service_operation_supersessions_471); END IF;
 PERFORM set_config('pdc.r471_pins_before_undo',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 PERFORM set_config('pdc.r471_tick_before_undo',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
END $g$;
DO $r$ BEGIN
 EXECUTE 'CREATE OR REPLACE FUNCTION public.pdc_tune_operation_change_candidate_20260912(vid uuid, p jsonb)'||chr(10)
  ||' RETURNS jsonb'||chr(10)||' LANGUAGE plpgsql'||chr(10)||' STABLE'||chr(10)
  ||' SET search_path TO ''pg_catalog'', ''public'', ''extensions'''||chr(10)
  ||'AS $function$'||replace($r471src$
DECLARE old public.pdc_pilbara_service_operations%rowtype; prior public.pdc_tune_operation_change_reviews%rowtype;
 base jsonb:='{}'; proposed jsonb; company_name text:=coalesce(p->'raw_row'->>'Company',p->'raw_row'->>'company','');
 division_name text:=coalesce(p->'raw_row'->>'Division',p->'raw_row'->>'division',''); matches integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.vehicles WHERE id=vid AND visible_on_board AND deleted_at IS NULL) THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vehicles WHERE id=vid AND stock_number=p->>'stock_number') THEN RETURN jsonb_build_object('conflict','stock_identity_changed'); END IF;
 SELECT count(*) INTO matches FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=vid
 AND o.repair_order_number=p->>'repair_order_number' AND o.original_line_number=(p->>'original_line_number')::integer;
 IF matches>1 THEN RETURN jsonb_build_object('conflict','ambiguous_existing_operation'); END IF;
 SELECT * INTO old FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=vid
 AND o.repair_order_number=p->>'repair_order_number' AND o.original_line_number=(p->>'original_line_number')::integer;
 IF old.operation_id IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r WHERE r.evidence_id=old.raw_evidence_id
     AND (pdc_parts_private.service_scope(r.raw_row,old.stock_number,old.repair_order_number)->>'company')=company_name
     AND (pdc_parts_private.service_scope(r.raw_row,old.stock_number,old.repair_order_number)->>'division')=division_name)
   THEN RETURN jsonb_build_object('conflict','company_division_identity_requires_review'); END IF;
   base:=jsonb_build_object('operation_description',old.operation_description,'source_estimated_hours',old.source_estimated_hours,'department',old.department,'operation_code',old.operation_code);
 END IF;
 SELECT * INTO prior FROM public.pdc_tune_operation_change_reviews q WHERE q.vehicle_id=vid AND q.company=company_name AND q.division=division_name
 AND q.repair_order_number=p->>'repair_order_number' AND q.original_line_number=(p->>'original_line_number')::integer AND q.status='approved'
 ORDER BY approved_at DESC,change_id DESC LIMIT 1;
 IF FOUND THEN base:=prior.proposed_source; END IF;
 proposed:=public.pdc_tune_operation_source_signature_20260912(p);
 RETURN jsonb_build_object('needs_review',old.operation_id IS NULL OR proposed IS DISTINCT FROM public.pdc_tune_operation_source_signature_20260912(base),
 'source_operation_id',old.operation_id,'change_kind',CASE WHEN old.operation_id IS NULL THEN 'added' ELSE 'modified' END,
 'before_source',base,'company',company_name,'division',division_name,
 'proposed_hash',encode(extensions.digest(convert_to(proposed::text,'UTF8'),'sha256'),'hex'));
END $r471src$,chr(10),chr(13)||chr(10))||'$function$';
END $r$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='service_operation_supersede_471' AND added_in='r471';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r471';
DROP FUNCTION pdc_service_supersede_private.supersede_operation_471(uuid,uuid,text,text,text,boolean);
DROP TABLE public.pdc_service_operation_supersessions_471;
DROP FUNCTION pdc_service_supersede_private.append_only_471();
DROP FUNCTION pdc_service_supersede_private.bay_code_same_line_471(text,text);
DROP SCHEMA pdc_service_supersede_private;
DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)'::regprocedure)<>'cc5dee40fa5a86fc1caa3704af318744'
    OR (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)'::regprocedure)<>'{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r471 undo: change candidate not restored byte for byte'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r471_pins_before_undo')::int-4
    OR to_regnamespace('pdc_service_supersede_private') IS NOT NULL OR to_regclass('public.pdc_service_operation_supersessions_471') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_operation_supersede_471') THEN RAISE EXCEPTION 'r471 undo: not fully removed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>current_setting('pdc.r471_tick_before_undo') THEN RAISE EXCEPTION 'r471 undo: clock tick changed'; END IF;
END $g$;
