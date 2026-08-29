-- STAGING ONLY 1010: allow explicitly synthetic staging acceptance rows through
-- lifecycle-history reads without weakening real dealer scope enforcement.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-lifecycle-history-synthetic-scope-1010',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260830100000'
    OR (SELECT count(*) FROM public.pdc_vehicle_lifecycle_history_controls_82000 WHERE enabled)<>1
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830095000' AND name='pdc_lifecycle_history_yard_hold_transition')<>1
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830101000')
 THEN RAISE EXCEPTION 'PDC_1010_EXACT_STAGING_1000_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(p_vehicle_id uuid,p_dealer_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE uid uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); actor_role text; v public.vehicles%rowtype; h jsonb; dealer text; scoped integer; synthetic boolean;
BEGIN
 IF NOT public.pdc_lifecycle_history_enabled_82000() OR uid IS NULL OR v_actor_email='' THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 SELECT r.role::text INTO actor_role FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=v_actor_email AND r.active AND r.account_status='approved';
 IF actor_role NOT IN('viewer','operator','importer','administrator') THEN RETURN jsonb_build_object('ok',false,'code','forbidden'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id;
 IF NOT FOUND AND NOT EXISTS(SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE vehicle_id=p_vehicle_id) THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 dealer:=CASE WHEN v.source_batch_id IN('14450','37047') THEN v.source_batch_id ELSE (SELECT e.dealer_code FROM public.pdc_vehicle_lifecycle_history_events_82000 e WHERE e.vehicle_id=p_vehicle_id AND e.dealer_code IS NOT NULL ORDER BY e.event_id LIMIT 1) END;
 synthetic:=coalesce(v.source_system,'')='hermes_lifecycle_history_acceptance' OR coalesce(v.source_batch_id,'') LIKE 'HERMES-TEST-%';
 IF p_dealer_code IS NOT NULL AND p_dealer_code NOT IN('14450','37047') THEN RETURN jsonb_build_object('ok',false,'code','invalid_scope'); END IF;
 IF p_dealer_code IS NOT NULL AND dealer IS DISTINCT FROM p_dealer_code THEN RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied'); END IF;
 SELECT count(*) INTO scoped FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=uid AND s.normalized_email=v_actor_email AND s.environment='staging' AND s.active;
 IF NOT synthetic AND scoped>0 AND (dealer IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=uid AND s.normalized_email=v_actor_email AND s.environment='staging' AND s.active AND s.dealer_code=dealer)) THEN RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied'); END IF;
 h:=public.pdc_lifecycle_history_payload_82000(p_vehicle_id);
 RETURN jsonb_build_object('ok',true,'code','lifecycle_history','data',jsonb_build_object('vehicle',jsonb_build_object('vehicle_id',p_vehicle_id,'stock_number',coalesce(v.stock_number,h->>'stock_number'),'job_card_number',coalesce(v.job_card_number,h->>'job_card_number'),'lifecycle_state',v.lifecycle_state::text,'deleted_at',v.deleted_at,'visible_on_board',v.visible_on_board),'lifecycle_history',h,'production',false,'timezone','Australia/Perth','authority','pdc_vehicle_lifecycle_history_82000'));
END $read$;
REVOKE ALL ON FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830101000','pdc_lifecycle_history_synthetic_scope_repair',ARRAY[
 'Exact append-only successor after 20260830100000 workshop-admin-block predecessor',
 'Permit explicitly synthetic lifecycle acceptance rows to use the authenticated history read path',
 'Retain exact authenticated dealer scope enforcement for real 14450 and 37047 rows',
 'Production sentinel/data/remotes remain excluded'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
