-- STAGING ONLY 433: repair the authoritative synthetic readback history column.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-433-containment-readback-column-repair',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826211000' AND name='432_current_hermes_containment_contract')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826211000') THEN
  RAISE EXCEPTION 'PDC_433_STAGING_HEAD_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.read_pdc_hermes_test_mutation_state_365(p_run_id text,p_vehicle_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_result jsonb;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' OR v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved') THEN RAISE EXCEPTION 'PDC_365_READ_UNAUTHORIZED_OR_RUN_INVALID' USING errcode='42501'; END IF;
 IF NOT public.pdc_hermes_containment_contract_432() OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365() THEN RAISE EXCEPTION 'PDC_365_READ_CONTAINMENT_DRIFT' USING errcode='55000'; END IF;
 IF p_vehicle_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id) THEN RAISE EXCEPTION 'PDC_365_READ_OUTSIDE_REGISTRY' USING errcode='42501'; END IF;
 SELECT jsonb_build_object('ok',true,'run_id',p_run_id,'vehicle_id',p_vehicle_id,'vehicles',coalesce(jsonb_agg(jsonb_build_object('scenario_no',r.scenario_no,'scenario_name',r.scenario_name,'vehicle',to_jsonb(v),'work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),'bookings',coalesce((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.created_at,b.id) FROM public.workshop_bookings b WHERE b.vehicle_id=v.id),'[]'::jsonb),'booking_assignments',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE b.vehicle_id=v.id),'[]'::jsonb),'booking_history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM public.workshop_booking_history h JOIN public.workshop_bookings b ON b.id=h.booking_id WHERE b.vehicle_id=v.id),'[]'::jsonb),'parts_overrides',coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.id) FROM public.workshop_parts_overrides o WHERE o.vehicle_id=v.id),'[]'::jsonb),'parts',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.updated_at,p.id) FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id),'[]'::jsonb),'sublets',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.created_at,s.booking_id) FROM public.pdc_sublet_booking_instances s WHERE s.vehicle_id=v.id),'[]'::jsonb),'movements',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.vehicle_movements m WHERE m.vehicle_id=v.id),'[]'::jsonb),'audit_events',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.audit_events a WHERE a.vehicle_id=v.id),'[]'::jsonb),'sublet_history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.history_id) FROM public.pdc_sublet_booking_instance_history h WHERE h.vehicle_id=v.id),'[]'::jsonb),'receipts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.receipt_id) FROM public.pdc_overnight_synthetic_mutation_receipts_365 x WHERE x.vehicle_id=v.id),'[]'::jsonb)) ORDER BY r.scenario_no),'[]'::jsonb),'protected_state',public.pdc_hermes_test_protected_digest_365(),'revisions',jsonb_build_object('pdc_email',(SELECT revision FROM public.pdc_email_vehicle_revision WHERE singleton),'workshop',(SELECT revision FROM public.workshop_revision WHERE id=1),'navision',(SELECT revision FROM public.navision_backend_revision WHERE singleton)),'notification_count',(SELECT count(*) FROM public.vehicle_notifications)) INTO v_result
 FROM public.pdc_overnight_synthetic_fleet_registry_363 r JOIN public.vehicles v ON v.id=r.vehicle_id WHERE r.run_id=p_run_id AND (p_vehicle_id IS NULL OR r.vehicle_id=p_vehicle_id);
 RETURN v_result;
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_hermes_test_mutation_state_365(text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_hermes_test_mutation_state_365(text,uuid) TO authenticated;

DO $post$
BEGIN
 IF position('jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM public.workshop_booking_history' IN pg_get_functiondef('public.read_pdc_hermes_test_mutation_state_365(text,uuid)'::regprocedure))=0
   OR position('pdc_hermes_containment_contract_432()' IN pg_get_functiondef('public.read_pdc_hermes_test_mutation_state_365(text,uuid)'::regprocedure))=0
   OR has_function_privilege('public','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_433_READBACK_OR_ACL_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826212000','433_containment_readback_column_repair',ARRAY[
 'Append-only repair after current 432 containment contract',
 'Authoritative synthetic readback uses workshop_booking_history.id while sublet history remains history_id',
 'Exact staging and Production-sentinel guards plus authenticated-only read ACL are preserved'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
