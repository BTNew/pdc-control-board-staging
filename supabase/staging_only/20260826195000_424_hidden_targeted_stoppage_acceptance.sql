-- STAGING ONLY 424: hidden synthetic acceptance bridge for targeted Workshop STOPPAGE clear.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-424-hidden-targeted-clear',0));
DO $pre$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826194000' AND name='423_stoppage_actor_email_qualification')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826194000') THEN
  RAISE EXCEPTION 'PDC_424_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
END $pre$;
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_clear_booking_stoppage_424(p_run_id text,p_vehicle_id uuid,p_expected_vehicle_version integer,p_booking_id uuid,p_expected_booking_version integer,p_resolution_note text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $bridge$
DECLARE uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; registry record; was_visible boolean; result jsonb;
BEGIN
 IF p_run_id<>'HERMES-TEST-RUN-20260824' OR p_vehicle_id IS NULL OR p_booking_id IS NULL OR p_expected_vehicle_version<1 OR p_expected_booking_version<1 OR p_idempotency_key IS NULL OR p_resolution_note!~'^HERMES-TEST' THEN
  RAISE EXCEPTION 'PDC_424_SYNTHETIC_INPUT_INVALID' USING errcode='22023'; END IF;
 SELECT * INTO registry FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id AND r.actor_id=uid AND r.actor_email=actor_email FOR SHARE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles x WHERE x.auth_user_id=uid AND lower(x.email)=actor_email AND x.active AND x.account_status='approved' AND x.role='administrator') THEN
  RAISE EXCEPTION 'PDC_424_SYNTHETIC_SCOPE_DENIED' USING errcode='42501'; END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.stock_number<>registry.stock_number OR v.source_batch_id<>p_run_id OR v.source_system<>'hermes_overnight_synthetic' OR v.source_payload->>'contract'<>'pdc-overnight-synthetic-fleet-363/render_only' OR v.version<>p_expected_vehicle_version THEN
  RAISE EXCEPTION 'PDC_424_SYNTHETIC_VEHICLE_DRIFT' USING errcode='55000'; END IF;
 was_visible:=v.visible_on_board;
 PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',p_vehicle_id::text,true);
 IF NOT was_visible THEN UPDATE public.vehicles SET visible_on_board=true WHERE id=p_vehicle_id; END IF;
 result:=public.clear_vehicle_stoppage_422(p_vehicle_id,p_expected_vehicle_version,'booking',p_booking_id,p_expected_booking_version,p_resolution_note,p_idempotency_key);
 IF NOT was_visible THEN UPDATE public.vehicles SET visible_on_board=false WHERE id=p_vehicle_id; END IF;
 IF NOT coalesce((result->>'ok')::boolean,false) THEN RETURN result; END IF;
 RETURN result||jsonb_build_object('synthetic_visibility_restored',NOT was_visible,'acceptance_bridge','424');
END $bridge$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_clear_booking_stoppage_424(text,uuid,integer,uuid,integer,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_clear_booking_stoppage_424(text,uuid,integer,uuid,integer,text,uuid) TO authenticated;
DO $post$ BEGIN
 IF NOT has_function_privilege('authenticated','public.pdc_hermes_test_clear_booking_stoppage_424(text,uuid,integer,uuid,integer,text,uuid)','EXECUTE')
  OR has_function_privilege('anon','public.pdc_hermes_test_clear_booking_stoppage_424(text,uuid,integer,uuid,integer,text,uuid)','EXECUTE') THEN RAISE EXCEPTION 'PDC_424_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826195000','424_hidden_targeted_stoppage_acceptance',ARRAY[
 'Registry-bound administrator-only HERMES-TEST bridge temporarily exposes one hidden synthetic vehicle so canonical targeted booking clear can exercise current planner eligibility',
 'Original visibility is restored in the same transaction; Production, real vehicles and operational business functions are unchanged'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
