-- STAGING ONLY: keep deferred PIT as immutable evidence, not checkable QC work.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904010700-deferred-pit-qc-finalization',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_head text;
  v_gate text;
  v_final text;
  v_retest text;
  v_set text;
BEGIN
  SELECT version INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$'
  ORDER BY version::bigint DESC LIMIT 1;
  v_gate:=pg_get_functiondef('public.pdc_qc_require_all_operations_complete_379()'::regprocedure);
  v_final:=pg_get_functiondef('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)'::regprocedure);
  v_retest:=pg_get_functiondef('public.finalize_pdc_qc_retest_to_rft_747(uuid,integer,uuid,uuid,uuid)'::regprocedure);
  v_set:=pg_get_functiondef('public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure);
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_head IS DISTINCT FROM '20260904010600'
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904010700')
     OR (length(v_gate)-length(replace(v_gate,'public.pdc_qc_operation_lines_379(','')))/length('public.pdc_qc_operation_lines_379(')<>2
     OR (length(v_final)-length(replace(v_final,'public.pdc_qc_operation_lines_379(','')))/length('public.pdc_qc_operation_lines_379(')<>1
     OR (length(v_retest)-length(replace(v_retest,'public.pdc_qc_operation_lines_379(','')))/length('public.pdc_qc_operation_lines_379(')<>1
     OR (length(v_set)-length(replace(v_set,'IF v_stage IS NULL OR NOT coalesce(v_active,false) THEN','')))/length('IF v_stage IS NULL OR NOT coalesce(v_active,false) THEN')<>1
  THEN RAISE EXCEPTION 'PDC_20260904010700_STAGING_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE FUNCTION public.pdc_qc_operation_line_is_deferred_pit_10700(p_vehicle_id uuid,p_line_identity text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
  SELECT EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line_identity,'')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  )
$function$;
ALTER FUNCTION public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text) FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_qc_checkable_operation_lines_10700(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
  SELECT coalesce(jsonb_agg(line ORDER BY ordinal),'[]'::jsonb)
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY projected(line,ordinal)
  WHERE NOT public.pdc_qc_operation_line_is_deferred_pit_10700(p_vehicle_id,line->>'line_identity')
$function$;
ALTER FUNCTION public.pdc_qc_checkable_operation_lines_10700(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.pdc_qc_checkable_operation_lines_10700(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_qc_require_all_operations_complete_379()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $gate$
BEGIN
 IF NEW.qc_completed_at IS NOT NULL AND OLD.qc_completed_at IS NULL AND (
  (EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=NEW.id AND w.required AND lower(w.work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre'))
   AND jsonb_array_length(public.pdc_qc_checkable_operation_lines_10700(NEW.id))=0)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(NEW.id)) l WHERE coalesce((l->>'active')::boolean,false) AND ((l->>'estimated_hours') IS NULL OR NOT coalesce((l->>'completed')::boolean,false)))
 ) THEN RAISE EXCEPTION 'PDC_QC_OPERATION_LINES_INCOMPLETE_OR_UNKNOWN' USING errcode='23514';END IF;
 RETURN NEW;
END $gate$;
ALTER FUNCTION public.pdc_qc_require_all_operations_complete_379() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.pdc_qc_require_all_operations_complete_379() FROM public,anon,authenticated,service_role;

DO $replace$
DECLARE
  v_def text;
  v_old text:='IF v_stage IS NULL OR NOT coalesce(v_active,false) THEN';
  v_new text:='IF public.pdc_qc_operation_line_is_deferred_pit_10700(p_vehicle_id,v_line) THEN RAISE EXCEPTION ''PDC_10700_DEFERRED_PIT_NOT_CHECKABLE'' USING errcode=''22023'';END IF;'||E'\n '||'IF v_stage IS NULL OR NOT coalesce(v_active,false) THEN';
BEGIN
  v_def:=pg_get_functiondef('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)'::regprocedure);
  EXECUTE replace(v_def,'public.pdc_qc_operation_lines_379(','public.pdc_qc_checkable_operation_lines_10700(');

  v_def:=pg_get_functiondef('public.finalize_pdc_qc_retest_to_rft_747(uuid,integer,uuid,uuid,uuid)'::regprocedure);
  v_def:=replace(v_def,'lines:=public.pdc_qc_operation_lines_379(p_vehicle_id);','lines:=public.pdc_qc_checkable_operation_lines_10700(p_vehicle_id);');
  v_def:=replace(v_def,
    'IF jsonb_array_length(coalesce(lines,''[]''::jsonb))<>17 OR',
    'IF jsonb_array_length(coalesce(public.pdc_qc_operation_lines_379(p_vehicle_id),''[]''::jsonb))<>17 OR');
  EXECUTE v_def;

  v_def:=pg_get_functiondef('public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure);
  EXECUTE replace(v_def,v_old,v_new);
END $replace$;

DO $post$
DECLARE
  v_vehicle uuid:='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid;
  v_raw jsonb;
  v_checkable jsonb;
  v_final text;
  v_retest text;
  v_set text;
BEGIN
  v_raw:=public.pdc_qc_operation_lines_379(v_vehicle);
  v_checkable:=public.pdc_qc_checkable_operation_lines_10700(v_vehicle);
  v_final:=pg_get_functiondef('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)'::regprocedure);
  v_retest:=pg_get_functiondef('public.finalize_pdc_qc_retest_to_rft_747(uuid,integer,uuid,uuid,uuid)'::regprocedure);
  v_set:=pg_get_functiondef('public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure);
  IF NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_raw) l
       JOIN public.pdc_authenticated_email_operation_lines ol ON ol.vehicle_id=v_vehicle AND ol.operation_line_id=(l->>'source_line_id')::uuid
       WHERE ol.operation_no='OP9' AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
     )
     OR EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_checkable) l
       JOIN public.pdc_authenticated_email_operation_lines ol ON ol.vehicle_id=v_vehicle AND ol.operation_line_id=(l->>'source_line_id')::uuid
       WHERE regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
     )
     OR jsonb_array_length(v_raw)<>jsonb_array_length(v_checkable)+1
     OR jsonb_array_length(v_checkable)=0
     OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_checkable) l WHERE coalesce((l->>'active')::boolean,false) AND NOT coalesce((l->>'completed')::boolean,false))
     OR public.pdc_qc_gate_issues(v_vehicle) IS DISTINCT FROM ARRAY[]::text[]
     OR v_final NOT LIKE '%pdc_qc_checkable_operation_lines_10700%'
     OR v_retest NOT LIKE '%lines:=public.pdc_qc_checkable_operation_lines_10700(p_vehicle_id)%'
     OR v_retest NOT LIKE '%jsonb_array_length(coalesce(public.pdc_qc_operation_lines_379(p_vehicle_id),''[]''::jsonb))<>17%'
     OR v_set NOT LIKE '%PDC_10700_DEFERRED_PIT_NOT_CHECKABLE%'
     OR has_function_privilege('public','public.pdc_qc_checkable_operation_lines_10700(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.pdc_qc_checkable_operation_lines_10700(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.pdc_qc_checkable_operation_lines_10700(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.pdc_qc_checkable_operation_lines_10700(uuid)','EXECUTE')
     OR has_function_privilege('public','public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)','EXECUTE')
     OR has_function_privilege('anon','public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)','EXECUTE')
     OR has_function_privilege('service_role','public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.finalize_pdc_qc_retest_to_rft_747(uuid,integer,uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.finalize_pdc_qc_retest_to_rft_747(uuid,integer,uuid,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)','EXECUTE')
     OR has_function_privilege('anon','public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)','EXECUTE')
  THEN RAISE EXCEPTION 'PDC_20260904010700_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904010700','deferred_pit_qc_finalization',ARRAY[
  'Retain raw all-operation projection and immutable PIT source evidence while deriving a separate server-authoritative checkable QC projection',
  'Exclude only authenticated source lines whose normalized work_key is PITINSPECTION from the 379 trigger, 700 finalization and 747 retest finalization predicates',
  'Reject deferred PIT through the per-operation completion RPC; genuine incomplete non-PIT operations remain authoritative blockers',
  'Preserve existing RLS and grants; helper functions are private SECURITY DEFINER contracts',
  'Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
