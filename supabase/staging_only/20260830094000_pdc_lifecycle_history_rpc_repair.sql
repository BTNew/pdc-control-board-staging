-- STAGING ONLY 940: lifecycle-history RPC ambiguity repair.
-- Append-only successor after the applied 930 lifecycle-history migration.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-lifecycle-history-940-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260830093000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830093000' AND name='pdc_lifecycle_history')<>1
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830094000')
 THEN RAISE EXCEPTION 'PDC_940_EXACT_STAGING_930_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(p_vehicle_id uuid,p_dealer_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE uid uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); actor_role text; v public.vehicles%rowtype; h jsonb; dealer text; scoped integer;
BEGIN
 IF NOT public.pdc_lifecycle_history_enabled_82000() OR uid IS NULL OR v_actor_email='' THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 SELECT r.role::text INTO actor_role FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=v_actor_email AND r.active AND r.account_status='approved';
 IF actor_role NOT IN('viewer','operator','importer','administrator') THEN RETURN jsonb_build_object('ok',false,'code','forbidden'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id;
 IF NOT FOUND AND NOT EXISTS(SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE vehicle_id=p_vehicle_id) THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 dealer:=CASE WHEN v.source_batch_id IN('14450','37047') THEN v.source_batch_id ELSE (SELECT e.dealer_code FROM public.pdc_vehicle_lifecycle_history_events_82000 e WHERE e.vehicle_id=p_vehicle_id AND e.dealer_code IS NOT NULL ORDER BY e.event_id LIMIT 1) END;
 IF p_dealer_code IS NOT NULL AND p_dealer_code NOT IN('14450','37047') THEN RETURN jsonb_build_object('ok',false,'code','invalid_scope'); END IF;
 IF p_dealer_code IS NOT NULL AND dealer IS DISTINCT FROM p_dealer_code THEN RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied'); END IF;
 SELECT count(*) INTO scoped FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=uid AND s.normalized_email=v_actor_email AND s.environment='staging' AND s.active;
 IF scoped>0 AND (dealer IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=uid AND s.normalized_email=v_actor_email AND s.environment='staging' AND s.active AND s.dealer_code=dealer)) THEN RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied'); END IF;
 h:=public.pdc_lifecycle_history_payload_82000(p_vehicle_id);
 RETURN jsonb_build_object('ok',true,'code','lifecycle_history','data',jsonb_build_object('vehicle',jsonb_build_object('vehicle_id',p_vehicle_id,'stock_number',coalesce(v.stock_number,h->>'stock_number'),'job_card_number',coalesce(v.job_card_number,h->>'job_card_number'),'lifecycle_state',v.lifecycle_state::text,'deleted_at',v.deleted_at,'visible_on_board',v.visible_on_board),'lifecycle_history',h,'production',false,'timezone','Australia/Perth','authority','pdc_vehicle_lifecycle_history_82000'));
END $read$;

CREATE OR REPLACE FUNCTION public.disable_pdc_vehicle_lifecycle_history_82000(p_enabled boolean,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $control$
DECLARE uid uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); actor_role text;
BEGIN
 SELECT r.role::text INTO actor_role FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=v_actor_email AND r.active AND r.account_status='approved';
 IF NOT public.pdc_monitor_staging_guard() OR actor_role<>'administrator' OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 500 THEN RETURN jsonb_build_object('ok',false,'code','administrator_required'); END IF;
 INSERT INTO public.pdc_vehicle_lifecycle_history_controls_82000(enabled,reason,actor_id,actor_email) VALUES(coalesce(p_enabled,false),btrim(p_reason),uid,v_actor_email);
 INSERT INTO public.audit_events(action,table_name,actor_id,actor_email,metadata) VALUES('update','pdc_vehicle_lifecycle_history_controls_82000',uid,v_actor_email,jsonb_build_object('enabled',coalesce(p_enabled,false),'reason',btrim(p_reason),'rollback_path',true));
 RETURN jsonb_build_object('ok',true,'code',CASE WHEN p_enabled THEN 'lifecycle_history_enabled' ELSE 'lifecycle_history_disabled' END,'enabled',coalesce(p_enabled,false));
END $control$;

CREATE OR REPLACE FUNCTION public.correct_pdc_vehicle_lifecycle_history_82000(p_vehicle_id uuid,p_transition_kind text,p_corrected_at timestamptz,p_reason text,p_idempotency_key uuid,p_evidence jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $correct$
DECLARE uid uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); actor_role text; original public.pdc_vehicle_lifecycle_history_events_82000%rowtype; existing public.pdc_vehicle_lifecycle_history_events_82000%rowtype; new_id bigint; h jsonb;
BEGIN
 SELECT r.role::text INTO actor_role FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=v_actor_email AND r.active AND r.account_status='approved';
 IF NOT public.pdc_monitor_staging_guard() OR actor_role<>'administrator' OR p_vehicle_id IS NULL OR p_transition_kind NOT IN('YH','PMB','RFT') OR p_corrected_at IS NULL OR p_idempotency_key IS NULL OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 8 AND 500 OR jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object' THEN RETURN jsonb_build_object('ok',false,'code','invalid_correction'); END IF;
 SELECT * INTO existing FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE idempotency_key=p_idempotency_key;
 IF FOUND THEN RETURN jsonb_build_object('ok',true,'code','lifecycle_correction_replayed','replay',true,'event_id',existing.event_id,'vehicle_id',p_vehicle_id); END IF;
 SELECT * INTO original FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE vehicle_id=p_vehicle_id AND transition_kind=p_transition_kind AND event_kind='latch' ORDER BY event_id LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','original_lifecycle_evidence_missing'); END IF;
 INSERT INTO public.pdc_vehicle_lifecycle_history_events_82000(vehicle_id,dealer_code,stock_number,job_card_number,source_system,source_record_id,transition_kind,event_kind,occurred_at,source_table,source_reference,actor_id,actor_email,original_event_id,correction_reason,idempotency_key,evidence)
 VALUES(original.vehicle_id,original.dealer_code,original.stock_number,original.job_card_number,original.source_system,original.source_record_id,p_transition_kind,'correction',p_corrected_at,'pdc_vehicle_lifecycle_history_corrections_82000',original.event_id,uid,v_actor_email,original.event_id,btrim(p_reason),p_idempotency_key,coalesce(p_evidence,'{}'::jsonb)) RETURNING event_id INTO new_id;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','pdc_vehicle_lifecycle_history_events_82000',new_id,p_vehicle_id,uid,v_actor_email,jsonb_build_object('original_event_id',original.event_id,'occurred_at',original.occurred_at),jsonb_build_object('correction_event_id',new_id,'occurred_at',p_corrected_at),jsonb_build_object('audited_correction',true,'reason',p_reason,'evidence',coalesce(p_evidence,'{}'::jsonb)));
 h:=public.pdc_lifecycle_history_payload_82000(p_vehicle_id);
 RETURN jsonb_build_object('ok',true,'code','lifecycle_correction_recorded','replay',false,'event_id',new_id,'vehicle_id',p_vehicle_id,'lifecycle_history',h);
END $correct$;

REVOKE ALL ON FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(uuid,text),public.disable_pdc_vehicle_lifecycle_history_82000(boolean,text),public.correct_pdc_vehicle_lifecycle_history_82000(uuid,text,timestamptz,text,uuid,jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(uuid,text),public.disable_pdc_vehicle_lifecycle_history_82000(boolean,text),public.correct_pdc_vehicle_lifecycle_history_82000(uuid,text,timestamptz,text,uuid,jsonb) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830094000','pdc_lifecycle_history_rpc_repair',ARRAY[
 'Append-only successor after exact 20260830093000 lifecycle history migration',
 'Repair ambiguous actor email variable references in authenticated history, disable and correction RPCs',
 'Preserve exact dealer scope, forced RLS, audited correction, replay and reversible disable controls',
 'Production sentinel/data/remotes remain excluded'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
