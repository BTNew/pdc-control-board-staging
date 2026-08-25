-- STAGING ONLY 406: use the established Sublet history action `updated` for
-- canonical provider changes; before/after rows retain the precise change.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-406-sublet-provider-history-action',0));
DO $fix$
DECLARE v_head text; v_definition text; v_corrected text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826153000'
    OR to_regprocedure('public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_406_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
  SELECT pg_get_functiondef('public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)'::regprocedure) INTO v_definition;
  v_corrected:=replace(v_definition,',''provider_updated'',to_jsonb(v_before),to_jsonb(v_after),v_after.version)',',''updated'',to_jsonb(v_before),to_jsonb(v_after),v_after.version)');
  IF v_corrected=v_definition OR position('''provider_updated''' in v_corrected)>0 THEN
    RAISE EXCEPTION 'PDC_406_HISTORY_ACTION_PATCH_ANCHOR_MISSING' USING errcode='55000';
  END IF;
  EXECUTE v_corrected;
END $fix$;
REVOKE ALL ON FUNCTION public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid) TO authenticated;
DO $post$
DECLARE d text:=pg_get_functiondef('public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)'::regprocedure);
BEGIN
  IF position('''provider_updated''' in d)>0 OR position('''updated'',to_jsonb(v_before),to_jsonb(v_after)' in replace(d,' ',''))=0
    OR has_function_privilege('public','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_406_HISTORY_ACTION_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826154500','406_sublet_provider_history_action_correction',ARRAY[
  'Use established pdc_sublet_booking_instance_history action updated for provider changes while before/after data preserves exact semantics',
  'No operational row mutation in this migration'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
