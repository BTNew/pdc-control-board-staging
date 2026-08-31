-- STAGING ONLY: exact active scope compatibility successor after 855.
-- The pilot was intentionally enabled by 843; this repairs the stale 839 scope predicate only.
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-856-active-scope-pilot-state',0));
DO $$ BEGIN
 IF current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831210000' AND name='855_deterministic_inbound_sender_eligibility_successor')<>1
 OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND enabled AND automatic_rule_application AND automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
 THEN RAISE EXCEPTION 'PDC_856_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.pdc_monitor_authenticated_active_scope_839()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions
AS $scope$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_binding public.pdc_monitor_runtime_bindings_255%rowtype; v_mailbox public.monitored_mailboxes%rowtype;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR lower(coalesce(current_setting('app.environment',true),''))='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_actor IS DISTINCT FROM 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR v_email<>'sales@broometoyota.com.au' OR coalesce(auth.jwt()->>'role','')<>'authenticated'
 THEN RAISE EXCEPTION 'PDC_839_AUTHENTICATED_ACTIVE_IDENTITY_REQUIRED' USING errcode='42501'; END IF;
 IF (SELECT count(*) FROM auth.users u WHERE u.id=v_actor AND lower(coalesce(u.email,''))=v_email AND coalesce(u.raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor')<>1
    OR (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role::text='importer')<>1
    OR (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND r.active)<>1
    OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL)<>1
    OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.active AND w.revoked_at IS NULL)<>1
    OR EXISTS(SELECT 1 FROM public.pdc_auditor_worker_identities w WHERE w.auth_user_id=v_actor AND w.active)
    OR EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=v_actor AND s.active)
    OR EXISTS(SELECT 1 FROM public.pdc_auditor_executor_identities e WHERE e.auth_user_id=v_actor AND e.active AND e.expires_at>clock_timestamp())
    OR EXISTS(SELECT 1 FROM public.pdc_auditor_service_identities_225 s WHERE s.auth_user_id=v_actor AND s.active)
 THEN RAISE EXCEPTION 'PDC_839_AUTHENTICATED_ACTIVE_ROLE_WRITER_REQUIRED' USING errcode='42501'; END IF;
 SELECT * INTO v_mailbox FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND active AND test_mode AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND config->>'owner_profile'='pdc-monitor' AND config->>'contains_credentials'='false' AND config->>'operational_scope'='staging';
 IF NOT FOUND OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1 THEN RAISE EXCEPTION 'PDC_839_EXACT_ACTIVE_MAILBOX_REQUIRED' USING errcode='42501'; END IF;
 IF (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND enabled AND automatic_rule_application AND automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_active_capability_controls_672 WHERE singleton AND enabled AND actor_id=v_actor AND jwt_role='authenticated' AND server_application_role='importer' AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_execution_attachment_controls_673 WHERE singleton AND enabled AND actor_id=v_actor AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND enabled AND actor_id=v_actor AND mailbox_id=v_mailbox.id AND mailbox_key='pdc_pmb_email' AND mailbox_address='pmbcontroller@gmail.com' AND provider='gmail' AND test_mode AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND enabled AND actor_id=v_actor AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
 THEN RAISE EXCEPTION 'PDC_839_ACTIVE_CONFIGURATION_REQUIRED' USING errcode='42501'; END IF;
 SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id=v_actor AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND semantic_planner_commissioned_at IS NOT NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_839_ACTIVE_RUNTIME_BINDING_REQUIRED' USING errcode='42501'; END IF;
 RETURN jsonb_build_object('actor_id',v_actor,'actor_email',v_email,'jwt_role','authenticated','server_application_role','importer','gateway_instance_id',v_binding.gateway_instance_id,'release_name',v_binding.release_name,'source_sha',v_binding.source_sha,'manifest_sha256',v_binding.manifest_sha256,'semantic_planner_sha256',v_binding.semantic_planner_sha256,'semantic_planner_trust_receipt_sha256',v_binding.semantic_planner_trust_receipt_sha256,'writer_active',true,'planner_commissioned',true,'mailbox_id',v_mailbox.id,'mailbox_active',true,'active_mailbox_count',1,'operational',true,'activation_ready',true,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'adapter_head',839);
END
$scope$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831220000','856_active_scope_enabled_pilot_compatibility_successor',ARRAY['Align exact 839 active scope with the already enabled 843 supervised staging pilot','Preserve exact actor, writer, mailbox, RLS, UID514, outbound and Production guards']);
NOTIFY pgrst,'reload schema';
COMMIT;
