-- STAGING ONLY: authorise PDC operators for exact imported Pilbara Service vehicles.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-pilbara-workshop-cross-source-scope-20260908151000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT jsonb_build_array(version,name) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM '["20260908150000","pilbara_fitting_stage_hours_projection"]'::jsonb
     OR to_regclass('public.pdc_auditor_user_dealer_scopes') IS NULL
     OR to_regclass('public.pdc_pilbara_service_operations') IS NULL
     OR to_regprocedure('public.pdc_auditor_vehicle_dealer(uuid)') IS NULL
     OR to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)') IS NULL
     OR to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)') IS NULL
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260908151000')
  THEN RAISE EXCEPTION 'PDC_PILBARA_WORKSHOP_CROSS_SOURCE_SCOPE_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_workshop_actor_vehicle_allowed(
  p_scope jsonb,
  p_vehicle_id uuid,
  p_requested_dealer text
) RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $allowed$
DECLARE
  v_requested_dealer text:=btrim(coalesce(p_requested_dealer,''));
  v_vehicle_dealer text;
BEGIN
  IF p_scope->>'environment' IS DISTINCT FROM 'staging'
     OR coalesce(p_scope->>'role','') NOT IN ('viewer','operator','administrator')
     OR v_requested_dealer NOT IN ('14450','37047')
  THEN RETURN false; END IF;

  v_vehicle_dealer:=public.pdc_auditor_vehicle_dealer(p_vehicle_id);
  IF v_vehicle_dealer IS DISTINCT FROM v_requested_dealer THEN RETURN false; END IF;

  -- The shared PDC board is scoped to dealer 14450 but intentionally imports
  -- dealer 37047 Pilbara Service job cards. Bridge only an exact active vehicle
  -- that actually owns immutable Pilbara Service operation evidence; this does
  -- not add or broaden actor dealer-scope rows.
  RETURN p_scope->>'dealer_code'=v_vehicle_dealer
    OR (
      p_scope->>'dealer_code'='14450'
      AND v_vehicle_dealer='37047'
      AND EXISTS(
        SELECT 1 FROM public.pdc_pilbara_service_operations o
        JOIN public.vehicles v ON v.id=o.vehicle_id
        WHERE o.vehicle_id=p_vehicle_id
          AND v.lifecycle_state='active' AND v.deleted_at IS NULL
      )
    );
END
$allowed$;
REVOKE ALL ON FUNCTION public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text) FROM public,anon,authenticated,service_role;
COMMENT ON FUNCTION public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text) IS
'STAGING internal authorization predicate. Existing scoped PDC users may access their own dealer vehicles, plus exact active dealer-37047 vehicles with immutable Pilbara Service operation evidence. No actor scope is broadened.';

CREATE OR REPLACE FUNCTION public.get_vehicle_workshop_detail_scoped(p_vehicle_id uuid,p_dealer_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $detail$
DECLARE v_scope jsonb; v_dealer text; v_vehicle_dealer text;
BEGIN
  v_scope:=public.pdc_auditor_actor_scope();
  v_dealer:=btrim(coalesce(p_dealer_code,''));
  IF NOT public.pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,v_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied','data',jsonb_build_object('environment','staging','dealer_code',v_dealer));
  END IF;
  SELECT public.pdc_auditor_vehicle_dealer(v.id) INTO v_vehicle_dealer
  FROM public.vehicles v
  WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active';
  IF v_vehicle_dealer IS DISTINCT FROM v_dealer THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_dealer_scope','data',jsonb_build_object('vehicle_id',p_vehicle_id,'dealer_code',v_dealer));
  END IF;
  RETURN public.get_vehicle_workshop_detail(p_vehicle_id);
END
$detail$;
REVOKE ALL ON FUNCTION public.get_vehicle_workshop_detail_scoped(uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_vehicle_workshop_detail_scoped(uuid,text) TO authenticated;

DO $patch_batch$
DECLARE
  d text;
  old_predicate text:='OR v_scope->>''dealer_code'' IS DISTINCT FROM v_vehicle_dealer THEN';
  new_predicate text:='OR NOT public.pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,v_vehicle_dealer) THEN';
BEGIN
  d:=pg_get_functiondef('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure);
  IF position(old_predicate in d)=0
     OR (length(d)-length(replace(d,old_predicate,'')))/length(old_predicate)<>1
     OR position('pdc_pilbara_service_operations' in d)=0
     OR position('manual_operator_unknown' in d)=0
     OR position(new_predicate in d)>0
  THEN RAISE EXCEPTION 'PDC_PILBARA_WORKSHOP_BATCH_SCOPE_PATCH_PRECONDITION_FAILED' USING errcode='55000'; END IF;
  d:=replace(d,old_predicate,new_predicate);
  IF position(old_predicate in d)>0 OR position(new_predicate in d)=0
  THEN RAISE EXCEPTION 'PDC_PILBARA_WORKSHOP_BATCH_SCOPE_PATCH_FAILED' USING errcode='55000'; END IF;
  EXECUTE d;
END $patch_batch$;
REVOKE ALL ON FUNCTION public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid) TO authenticated;

DO $verify$
DECLARE detail_def text; batch_def text;
BEGIN
  detail_def:=pg_get_functiondef('public.get_vehicle_workshop_detail_scoped(uuid,text)'::regprocedure);
  batch_def:=pg_get_functiondef('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure);
  IF position('pdc_workshop_actor_vehicle_allowed' in detail_def)=0
     OR position('pdc_workshop_actor_vehicle_allowed' in batch_def)=0
     OR position('pdc_pilbara_service_operations' in batch_def)=0
     OR NOT has_function_privilege('authenticated','public.get_vehicle_workshop_detail_scoped(uuid,text)','execute')
     OR NOT has_function_privilege('authenticated','public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)','execute')
     OR has_function_privilege('authenticated','public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)','execute')
     OR has_function_privilege('anon','public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)','execute')
     OR has_function_privilege('service_role','public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)','execute')
  THEN RAISE EXCEPTION 'PDC_PILBARA_WORKSHOP_CROSS_SOURCE_SCOPE_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $verify$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260908151000','pilbara_workshop_cross_source_scope',ARRAY[
  'Authorise existing scoped PDC users for exact active dealer-37047 vehicles carrying immutable Pilbara Service operation evidence',
  'Apply the same narrow vehicle predicate to scoped Workshop detail and atomic Job Card hours save',
  'Keep actor dealer-scope rows, source evidence, adjustments, bookings and vehicles unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
