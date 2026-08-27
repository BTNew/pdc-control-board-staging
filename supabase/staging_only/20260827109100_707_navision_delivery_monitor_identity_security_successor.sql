-- STAGING ONLY 707: close Navision Delivered - At Dealer actor spoofing.
-- This append-only successor starts at the exact live 675 ledger head. The
-- 706 lifecycle row remains preserved as an earlier applied predecessor. It
-- preserves the 700-706 lifecycle bodies and immutable evidence, but removes
-- the public three-argument delivery surface and gates the canonical import
-- route on the live authenticated pdc_email_monitor identity.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-707-navision-delivery-monitor-identity-security',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827109000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827107000' AND name='706_final_booked_synthetic_payload_identity_repair_after_673_collision')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827109000' AND name='675_authenticated_monitor_enqueue_trigger_compatibility')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827109000')
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.pdc_monitor_authenticated_active_scope_673(text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)') IS NOT NULL
     OR to_regprocedure('public.reconcile_navision_operational_record_pre707(uuid,uuid,text)') IS NOT NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NOT NULL
  THEN
    RAISE EXCEPTION 'PDC_707_EXACT_706_STAGING_PRESTATE_REQUIRED' USING errcode='55000';
  END IF;
END $pre$;

-- Keep the applied implementation as an internal, unreachable compatibility
-- helper. Its actor parameters can no longer be reached from PostgREST.
ALTER FUNCTION public.reconcile_navision_delivery_700(uuid,uuid,text)
  RENAME TO reconcile_navision_delivery_700_pre707;
REVOKE ALL ON FUNCTION public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)
  FROM public,anon,authenticated,service_role,pdc_email_monitor;

-- The only public delivery entry point has no actor parameters. It derives
-- both audit identities from the live auth context after the exact canonical
-- monitor/import binding is proved by the existing 673 scope.
CREATE FUNCTION public.reconcile_navision_delivery_700(p_backend_record_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions SET statement_timeout='120s' AS $delivery$
DECLARE
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
BEGIN
  IF NOT coalesce(public.pdc_monitor_authenticated_active_scope_673(NULL),false) THEN
    RETURN public.navision_backend_response(false,'monitor_identity_required');
  END IF;
  IF p_backend_record_id IS NULL THEN
    RETURN public.navision_backend_response(false,'invalid_input');
  END IF;
  RETURN public.reconcile_navision_delivery_700_pre707(p_backend_record_id,v_uid,v_email);
END $delivery$;
REVOKE ALL ON FUNCTION public.reconcile_navision_delivery_700(uuid)
  FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_delivery_700(uuid) TO authenticated;
COMMENT ON FUNCTION public.reconcile_navision_delivery_700(uuid) IS
  'Staging-only canonical Monitor/import delivery route. Actor identity is derived from auth.uid()/auth.jwt() and never accepted from the browser.';

-- The operational wrapper remains available only for the same canonical
-- Monitor/import identity. Supplied actor values are compatibility inputs that
-- must equal live claims; all authority and downstream audit values use the
-- server-derived identity. Delivered status always enters the one-argument
-- delivery route, so this wrapper cannot bypass the dedicated gate.
ALTER FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text)
  RENAME TO reconcile_navision_operational_record_pre707;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record_pre707(uuid,uuid,text)
  FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.reconcile_navision_operational_record(
  p_backend_record_id uuid,
  p_actor_id uuid DEFAULT NULL,
  p_actor_email text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions AS $wrapper$
DECLARE
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  b public.navision_backend_records%rowtype;
  raw_status text;
  normalized text;
BEGIN
  IF NOT coalesce(public.pdc_monitor_authenticated_active_scope_673(NULL),false) THEN
    RETURN public.navision_backend_response(false,'monitor_identity_required');
  END IF;
  IF (p_actor_id IS NOT NULL AND p_actor_id IS DISTINCT FROM v_uid)
     OR (p_actor_email IS NOT NULL AND lower(btrim(p_actor_email)) IS DISTINCT FROM v_email) THEN
    RETURN public.navision_backend_response(false,'actor_identity_mismatch');
  END IF;
  IF p_backend_record_id IS NULL THEN
    RETURN public.navision_backend_response(false,'invalid_input');
  END IF;
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
    normalized:=regexp_replace(lower(btrim(raw_status)),'[^a-z0-9]+','','g');
    IF normalized='deliveredatdealer' THEN
      RETURN public.reconcile_navision_delivery_700(p_backend_record_id);
    END IF;
  END IF;
  RETURN public.reconcile_navision_operational_record_pre707(p_backend_record_id,v_uid,v_email);
END $wrapper$;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text)
  FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) TO authenticated;
COMMENT ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) IS
  'Staging-only canonical Monitor/import compatibility wrapper. Supplied actor values must equal live claims; Delivered-at-Dealer uses the dedicated one-argument route.';

DO $post$
DECLARE
  v_delivery text;
  v_wrapper text;
BEGIN
  SELECT pg_get_functiondef('public.reconcile_navision_delivery_700(uuid)'::regprocedure) INTO v_delivery;
  SELECT pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure) INTO v_wrapper;
  IF to_regprocedure('public.reconcile_navision_delivery_700(uuid,uuid,text)') IS NOT NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record_pre707(uuid,uuid,text)') IS NULL
     OR position('pdc_monitor_authenticated_active_scope_673(NULL)' in v_delivery)=0
     OR position('auth.uid()' in v_delivery)=0
     OR position('auth.jwt()' in v_delivery)=0
     OR position('reconcile_navision_delivery_700_pre707(p_backend_record_id,v_uid,v_email)' in v_delivery)=0
     OR position('p_actor_id IS DISTINCT FROM v_uid' in v_wrapper)=0
     OR position('lower(btrim(p_actor_email)) IS DISTINCT FROM v_email' in v_wrapper)=0
     OR position('reconcile_navision_delivery_700(p_backend_record_id)' in v_wrapper)=0
     OR position('reconcile_navision_delivery_700(p_backend_record_id,' in v_wrapper)>0
     OR position('reconcile_navision_operational_record_pre707(p_backend_record_id,v_uid,v_email)' in v_wrapper)=0
     OR NOT has_function_privilege('authenticated','public.reconcile_navision_delivery_700(uuid)','execute')
     OR has_function_privilege('anon','public.reconcile_navision_delivery_700(uuid)','execute')
     OR has_function_privilege('service_role','public.reconcile_navision_delivery_700(uuid)','execute')
     OR has_function_privilege('pdc_email_monitor','public.reconcile_navision_delivery_700(uuid)','execute')
     OR NOT has_function_privilege('authenticated','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR has_function_privilege('anon','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR has_function_privilege('service_role','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR has_function_privilege('pdc_email_monitor','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR has_function_privilege('authenticated','public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)','execute')
     OR (SELECT count(*) FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE action='delivered' AND (request_payload ? 'actor_id'))<0
  THEN
    RAISE EXCEPTION 'PDC_707_SECURITY_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827109100','707_navision_delivery_monitor_identity_security_successor',ARRAY[
  'Require exact live 675 staging ledger head and Production sentinel absence; preserve 700-706 append-only history',
  'Rename the vulnerable three-argument delivery RPC to an ungranted internal predecessor and expose only a one-argument delivery RPC',
  'Derive actor ID and email from auth.uid()/auth.jwt() and require the existing exact pdc_email_monitor authenticated scope with approved importer role, active writer and runtime binding',
  'Require any compatibility actor values on reconcile_navision_operational_record to equal live claims and route Delivered - At Dealer through the dedicated one-argument RPC',
  'Remove authenticated browser direct delivery export and preserve exact status, locking, idempotency, timer, receipt, audit, history, RLS and outbound interception behavior',
  'Grant only authenticated execution for the gated public shapes; deny anon, service_role, pdc_email_monitor database role and direct predecessor execution; Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
