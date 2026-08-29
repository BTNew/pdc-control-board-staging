-- STAGING ONLY 772: retain .68 monitor compatibility after additive heads.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-772-monitor-compatibility-after-additive-heads',0));
DO $pre$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR v_head IS DISTINCT FROM '20260830102000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830102000' AND name='pdc_lifecycle_history_completed_snapshot')<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND minimum_uid=640 AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_current_head_compatibility_controls_766 WHERE singleton AND enabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
  THEN RAISE EXCEPTION 'PDC_768_MONITOR_COMPATIBILITY_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_766(
  p_mode text,p_gateway_instance_id text,p_release_name text,p_source_sha text,p_manifest_sha256 text,
  p_semantic_planner_sha256 text DEFAULT NULL,p_semantic_planner_trust_receipt_sha256 text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $verify$
DECLARE c public.pdc_email_monitor_current_head_compatibility_controls_766%rowtype; h text; n text;
BEGIN
  IF NOT public.pdc_monitor_authenticated_active_scope_674(p_gateway_instance_id)
     OR lower(btrim(coalesce(p_mode,'')))<>'active'
     OR p_gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
     OR p_release_name<>'pdc-monitor-staging-m502-2026.08.44'
     OR lower(p_source_sha)<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     OR lower(p_manifest_sha256)<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     OR lower(p_semantic_planner_sha256)<>'7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'
     OR lower(p_semantic_planner_trust_receipt_sha256)<>'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'
  THEN RETURN jsonb_build_object('ok',false,'code','runtime_binding_mismatch','production_writes',false); END IF;
  SELECT * INTO c FROM public.pdc_email_monitor_current_head_compatibility_controls_766 WHERE singleton AND enabled;
  SELECT version,name INTO h,n FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  IF NOT FOUND OR h !~ '^[0-9]{14}$' OR h::bigint < 20260830050000
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830050000' AND name='766_monitor_current_head_compatibility')<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND minimum_uid=640 AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.claim_pdc_email_intake_authenticated_exact_732(integer,text)'::regprocedure)<>c.canonical_contract->>'claim_sha256'
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)'::regprocedure)<>c.canonical_contract->>'provider_observation_sha256'
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb)'::regprocedure)<>c.canonical_contract->>'process_sha256'
     OR NOT has_function_privilege('authenticated',c.canonical_contract->>'claim','execute')
     OR has_function_privilege('anon',c.canonical_contract->>'claim','execute')
     OR has_function_privilege('service_role',c.canonical_contract->>'claim','execute')
     OR NOT has_function_privilege('authenticated',c.canonical_contract->>'provider_wrapper','execute')
     OR has_function_privilege('anon',c.canonical_contract->>'provider_wrapper','execute')
     OR has_function_privilege('service_role',c.canonical_contract->>'provider_wrapper','execute')
     OR NOT has_function_privilege('authenticated',c.canonical_contract->>'process','execute')
     OR has_function_privilege('anon',c.canonical_contract->>'process','execute')
     OR has_function_privilege('service_role',c.canonical_contract->>'process','execute')
  THEN RETURN jsonb_build_object('ok',false,'code','current_head_or_canonical_contract_mismatch','production_writes',false); END IF;
  RETURN jsonb_build_object('ok',true,'code','runtime_binding_verified_authenticated_766','mode','active','operational',true,'activation_ready',true,
    'actor_id',c.actor_id,'actor_email',c.actor_email,'jwt_role',c.jwt_role,'server_application_role',c.server_application_role,
    'gateway_instance_id',c.gateway_instance_id,'release_name',c.release_name,'source_sha',c.source_sha,'manifest_sha256',c.manifest_sha256,
    'semantic_planner_sha256',c.planner_sha256,'semantic_planner_trust_receipt_sha256',c.trust_receipt_sha256,
    'planner_commissioned',true,'writer_active',true,'mailbox_id','12fe383d-5c1e-5801-96e4-f67cf3e3bb57','mailbox_active',true,'active_mailbox_count',1,
    'migration_head',766,'compatibility_successor_head',766,'canonical_contract',c.canonical_contract,
    'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false);
END
$verify$;
REVOKE ALL ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830103000','772_monitor_compatibility_after_additive_heads',ARRAY[
 'Preserve the .68 authenticated monitor contract after additive staging heads at or after 766',
 'Keep canonical claim/provider/process hashes, actor, gateway, planner, UID514 and mailbox protections unchanged',
 'Keep task disabled, outbound email disabled, forced RLS and Production exclusion intact'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
