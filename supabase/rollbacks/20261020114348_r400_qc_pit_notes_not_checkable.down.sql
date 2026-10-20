-- r400 undo: restores the exact r10700 bodies (md5 1eb0c057 / 60b9186e), drops the helper, pins and check.
DO $g$
DECLARE want jsonb:='{"public.pdc_qc_line_not_checkable_400(uuid,jsonb)": "eac292a1d85506a02a6b5143d979a632", "public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)": "f5981a43eeee9ddb3e029fe1f8f6a0bf", "public.pdc_qc_checkable_operation_lines_10700(uuid)": "3b2995e11939cd2dbcd4edf2fdd307d0"}'::jsonb; k text;
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'r400 undo: staging only'; END IF;
 FOR k IN SELECT jsonb_object_keys(want) LOOP
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=k::regprocedure)<>want->>k THEN RAISE EXCEPTION 'r400 undo: % is not the r400 body',k; END IF;
 END LOOP;
END $g$;
CREATE OR REPLACE FUNCTION public.pdc_qc_operation_line_is_deferred_pit_10700(p_vehicle_id uuid, p_line_identity text)
 RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line_identity,'')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  )
$function$;

CREATE OR REPLACE FUNCTION public.pdc_qc_checkable_operation_lines_10700(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT coalesce(jsonb_agg(line ORDER BY ordinal),'[]'::jsonb)
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY projected(line,ordinal)
  WHERE NOT public.pdc_qc_operation_line_is_deferred_pit_10700(p_vehicle_id,line->>'line_identity')
$function$;

DROP FUNCTION public.pdc_qc_line_not_checkable_400(uuid,jsonb);
DELETE FROM pdc_ops.regression_checks WHERE check_name='qc_checklist_has_only_tickable_lines' AND added_in='r400';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r400' AND signature IN ('public.pdc_qc_line_not_checkable_400(uuid,jsonb)','public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)','public.pdc_qc_checkable_operation_lines_10700(uuid)');
DO $p$
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)'::regprocedure)<>'1eb0c057769f8107e6c6d6f8adce87a6'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_checkable_operation_lines_10700(uuid)'::regprocedure)<>'60b9186e12175da61df9857e79fa8f46'
  OR (SELECT md5(pg_get_functiondef('public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)'::regprocedure)))<>'091c35f0d1afa2269e7c5fc0698307f3'
  OR (SELECT md5(pg_get_functiondef('public.pdc_qc_checkable_operation_lines_10700(uuid)'::regprocedure)))<>'2309543d9065657e46883a1772d64bf8'
  OR to_regprocedure('public.pdc_qc_line_not_checkable_400(uuid,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r400 undo: restore check failed'; END IF;
END $p$;
