-- STAGING ONLY 427: hidden synthetic acceptance bridge for Parts STOPPAGE set/targeted clear.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-427-hidden-parts-stoppage',0));
DO $pre$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826201000' AND name='426_parts_stoppage_notification_delta_containment')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826201000') THEN RAISE EXCEPTION 'PDC_427_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
END $pre$;
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_parts_stoppage_427(p_run_id text,p_vehicle_id uuid,p_expected_vehicle_version integer,p_action text,p_reason text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $bridge$
DECLARE uid uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; registry record; act text:=lower(btrim(p_action)); result jsonb; was_visible boolean; child_key uuid;
BEGIN
 IF p_run_id<>'HERMES-TEST-RUN-20260824' OR p_vehicle_id IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL OR act NOT IN('set','clear') OR p_reason!~'^HERMES-TEST' THEN RAISE EXCEPTION 'PDC_427_SYNTHETIC_INPUT_INVALID' USING errcode='22023'; END IF;
 SELECT * INTO registry FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id AND r.actor_id=uid AND r.actor_email=v_actor_email FOR SHARE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles x WHERE x.auth_user_id=uid AND lower(x.email)=v_actor_email AND x.active AND x.account_status='approved' AND x.role='administrator') THEN RAISE EXCEPTION 'PDC_427_SYNTHETIC_SCOPE_DENIED' USING errcode='42501'; END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.stock_number<>registry.stock_number OR v.source_batch_id<>p_run_id OR v.source_system<>'hermes_overnight_synthetic' OR v.source_payload->>'contract'<>'pdc-overnight-synthetic-fleet-363/render_only' OR v.version<>p_expected_vehicle_version OR upper(v.current_location)<>'PMB' THEN RAISE EXCEPTION 'PDC_427_SYNTHETIC_VEHICLE_DRIFT' USING errcode='55000'; END IF;
 was_visible:=v.visible_on_board; PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',v.id::text,true);
 IF NOT was_visible THEN UPDATE public.vehicles SET visible_on_board=true WHERE id=v.id; END IF;
 IF act='set' THEN
  result:=public.set_pdc_parts_stoppage_376(v.id,v.version,p_idempotency_key,'set',p_reason);
 ELSE
  child_key:=extensions.uuid_generate_v5('42700000-0000-5000-8000-000000000427'::uuid,p_idempotency_key::text||':target');
  result:=public.clear_vehicle_stoppage_422(v.id,v.version,'parts',NULL,0,p_reason,child_key);
 END IF;
 IF NOT was_visible THEN UPDATE public.vehicles SET visible_on_board=false WHERE id=v.id; END IF;
 RETURN result||jsonb_build_object('acceptance_bridge','427','synthetic_visibility_restored',NOT was_visible,'caller_idempotency_key',p_idempotency_key);
END $bridge$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_parts_stoppage_427(text,uuid,integer,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_parts_stoppage_427(text,uuid,integer,text,text,uuid) TO authenticated;
DO $post$ BEGIN
 IF NOT has_function_privilege('authenticated','public.pdc_hermes_test_parts_stoppage_427(text,uuid,integer,text,text,uuid)','EXECUTE') OR has_function_privilege('anon','public.pdc_hermes_test_parts_stoppage_427(text,uuid,integer,text,text,uuid)','EXECUTE') THEN RAISE EXCEPTION 'PDC_427_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826202000','427_hidden_parts_stoppage_acceptance',ARRAY[
 'Registry-bound administrator-only HERMES-TEST bridge temporarily exposes one hidden synthetic PMB vehicle for canonical Parts STOPPAGE set and exact targeted clear',
 'Visibility is restored in the same transaction; no real vehicle, Production or notification authority is broadened'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
