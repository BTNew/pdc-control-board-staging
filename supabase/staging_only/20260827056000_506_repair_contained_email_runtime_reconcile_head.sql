-- STAGING ONLY 506: repair the applied 505 reconcile poststate guard.
-- Forward-only repair; no applied migration row is rewritten and no
-- operational runtime is enabled.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-506-contained-email-runtime-reconcile-guard',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827055000' AND name='505_repair_contained_email_runtime_reconcile_guard')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827055000')<>0
     OR to_regprocedure('public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)') IS NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827056000')<>0
  THEN RAISE EXCEPTION 'PDC_506_STAGING_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.reconcile_pdc_monitor_contained_binding_504(
  p_monitor_user_id uuid,
  p_gateway_instance_id text,
  p_release_name text,
  p_source_sha text,
  p_source_tree_sha text,
  p_manifest_sha256 text,
  p_archive_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $reconcile$
DECLARE
  v_admin_id uuid:=auth.uid();
  v_admin_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_admin_count integer;
  v_actor_email text;
  v_actor_count integer;
  v_ledger_name text;
  v_ledger_statements text[];
  v_ledger_hash text;
  v_provision_source text;
  v_verify_source text;
  v_provision_hash text;
  v_verify_hash text;
  v_prior jsonb;
  v_existing public.pdc_monitor_contained_binding_reconciliations_504%rowtype;
  v_event_key text:=encode(extensions.digest(convert_to(concat_ws('|',
    'pdc-monitor-contained-binding-504','forward_reconcile',
    'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b',
    'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
    'e850c319989d98b45b95a28aa815d78e2c2e3a4b',
    '8981540501bc629e189c39c9ea8a9adf3165d397',
    'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
    '4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90',
    '503','contained'),'UTF8'),'sha256'),'hex');
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-504-contained-email-runtime-forward-reconcile',0));

  SELECT count(*) INTO v_admin_count
  FROM public.pdc_user_roles r
  JOIN auth.users u ON u.id=r.auth_user_id AND lower(coalesce(u.email,''))=v_admin_email
  WHERE r.auth_user_id=v_admin_id AND lower(r.email)=v_admin_email
    AND r.active AND r.account_status='approved' AND r.role::text='administrator';
  IF v_admin_id IS NULL OR v_admin_email='' OR v_admin_count<>1 THEN
    RAISE EXCEPTION 'PDC_504_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501';
  END IF;

  IF p_monitor_user_id<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR p_gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
     OR p_release_name<>'pdc-monitor-staging-m502-2026.08.44'
     OR p_source_sha<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     OR p_source_tree_sha<>'8981540501bc629e189c39c9ea8a9adf3165d397'
     OR p_manifest_sha256<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     OR p_archive_sha256<>'4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90'
  THEN
    RAISE EXCEPTION 'PDC_504_REVIEWED_PAIR_MISMATCH' USING errcode='22023';
  END IF;

  SELECT lower(email) INTO v_actor_email
  FROM auth.users
  WHERE id=p_monitor_user_id
    AND coalesce(raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor';
  SELECT count(*) INTO v_actor_count
  FROM public.pdc_user_roles r
  WHERE r.auth_user_id=p_monitor_user_id AND lower(r.email)=v_actor_email
    AND r.active AND r.account_status='approved' AND r.role::text='viewer';
  IF v_actor_email IS NULL OR v_actor_count<>1
     OR exists(select 1 from public.pdc_auditor_worker_identities w where w.auth_user_id=p_monitor_user_id and w.active)
     OR exists(select 1 from public.pdc_auditor_user_dealer_scopes s where s.auth_user_id=p_monitor_user_id and s.active)
     OR exists(select 1 from public.pdc_auditor_executor_identities e where e.auth_user_id=p_monitor_user_id and e.active and e.expires_at>clock_timestamp())
     OR exists(select 1 from public.pdc_auditor_service_identities_225 s where s.auth_user_id=p_monitor_user_id and s.active)
  THEN
    RAISE EXCEPTION 'PDC_504_DEDICATED_MONITOR_IDENTITY_REQUIRED' USING errcode='42501';
  END IF;

  IF (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers
      WHERE active AND revoked_at IS NULL)<>0
     OR exists(select 1 from public.monitored_mailboxes where active)
     OR exists(select 1 from public.pdc_email_monitor_pilot
               where singleton and (enabled or automatic_rule_application
                 or automatic_authenticated_jobcards or outbound_email_enabled))
  THEN
    RAISE EXCEPTION 'PDC_504_CONTAINMENT_REQUIRED' USING errcode='55000';
  END IF;

  IF (SELECT count(*) FROM supabase_migrations.schema_migrations
      WHERE version~'^[0-9]{14}$' AND version>'20260827055000')<>0
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827055000')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827054000')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827053000')<>1
  THEN
    RAISE EXCEPTION 'PDC_504_EXACT_LEDGER_HEAD_REQUIRED' USING errcode='55000';
  END IF;
  SELECT name,statements INTO v_ledger_name,v_ledger_statements
  FROM supabase_migrations.schema_migrations WHERE version='20260827053000';
  v_ledger_hash:=encode(extensions.digest(convert_to(concat_ws('|','20260827053000',v_ledger_name,
    array_to_string(v_ledger_statements,E'\x1f')),'UTF8'),'sha256'),'hex');
  SELECT regexp_replace(prosrc,'[[:space:]]+',' ','g') INTO v_provision_source
  FROM pg_proc WHERE oid='public.provision_pdc_monitor_contained_binding_503(uuid,text,text,text,text)'::regprocedure;
  SELECT regexp_replace(prosrc,'[[:space:]]+',' ','g') INTO v_verify_source
  FROM pg_proc WHERE oid='public.verify_pdc_monitor_runtime_binding_503(text,text,text,text,text,text,text)'::regprocedure;
  v_provision_hash:=encode(extensions.digest(convert_to(v_provision_source,'UTF8'),'sha256'),'hex');
  v_verify_hash:=encode(extensions.digest(convert_to(v_verify_source,'UTF8'),'sha256'),'hex');
  IF v_ledger_name IS NULL OR v_ledger_statements IS NULL
     OR position('PDC_503_ALREADY_TRANSITIONED_INPUT_DRIFT' in coalesce(v_provision_source,''))=0
     OR position('runtime_binding_mismatch' in coalesce(v_verify_source,''))=0
  THEN
    RAISE EXCEPTION 'PDC_504_PREDECESSOR_FUNCTION_OR_LEDGER_DRIFT' USING errcode='55000';
  END IF;

  v_prior:=public.provision_pdc_monitor_contained_binding_503(
    p_monitor_user_id,'pdc-monitor-staging-sales-uid509-v1',
    'pdc-monitor-staging-m502-2026.08.44',
    '37a1fc0d83e0aa311cfb40b8c1804b9840922ea9',
    '5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca');
  IF v_prior IS NULL
     OR coalesce(v_prior->>'ok','false')<>'true'
     OR v_prior->>'actor_id'<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'
     OR v_prior->>'gateway_instance_id'<>'pdc-monitor-staging-sales-uid509-v1'
     OR v_prior->>'release_name'<>'pdc-monitor-staging-m502-2026.08.44'
     OR v_prior->>'source_sha'<>'37a1fc0d83e0aa311cfb40b8c1804b9840922ea9'
     OR v_prior->>'manifest_sha256'<>'5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca'
     OR v_prior->>'migration_head'<>'503'
     OR v_prior->>'mode'<>'contained'
     OR v_prior->>'operational'<>'false'
     OR v_prior->>'production_writes'<>'false'
  THEN
    RAISE EXCEPTION 'PDC_504_PREDECESSOR_BINDING_DRIFT' USING errcode='55000';
  END IF;

  SELECT * INTO v_existing
  FROM public.pdc_monitor_contained_binding_reconciliations_504
  WHERE event_key=v_event_key;
  IF FOUND THEN
    IF v_existing.predecessor_ledger_name<>v_ledger_name
       OR v_existing.predecessor_ledger_sha256<>v_ledger_hash
       OR v_existing.predecessor_provision_function_sha256<>v_provision_hash
       OR v_existing.predecessor_verify_function_sha256<>v_verify_hash
    THEN
      RAISE EXCEPTION 'PDC_504_PREDECESSOR_DRIFT_ON_REPLAY' USING errcode='55000';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'code','pdc_monitor_contained_binding_reconciled_504',
      'idempotent',true,'reconciliation_id',v_existing.reconciliation_id,
      'actor_id',v_existing.actor_id,'gateway_instance_id',v_existing.gateway_instance_id,
      'release_name',v_existing.release_name,'source_sha',v_existing.source_sha,
      'source_tree_sha',v_existing.source_tree_sha,'archive_sha256',v_existing.archive_sha256,
      'migration_head',v_existing.migration_head,'mode',v_existing.mode,
      'operational',v_existing.operational,'activation_ready',v_existing.activation_ready,
      'writer_active',v_existing.writer_active,'planner_commissioned',v_existing.planner_commissioned,
      'production_writes',v_existing.production_writes,'rollback_available',true,
      'rollback_contract',v_existing.rollback_contract);
  END IF;

  INSERT INTO public.pdc_monitor_contained_binding_reconciliations_504(
    event_kind,actor_id,gateway_instance_id,release_name,source_sha,source_tree_sha,manifest_sha256,
    archive_sha256,migration_head,mode,predecessor_ledger_version,predecessor_ledger_name,
    predecessor_ledger_sha256,predecessor_provision_function_sha256,
    predecessor_verify_function_sha256,predecessor_markers,predecessor_actor_id,
    predecessor_gateway_instance_id,predecessor_release_name,predecessor_source_sha,
    predecessor_manifest_sha256,predecessor_binding_sha256,predecessor_operational,
    predecessor_activation_ready,predecessor_writer_active,predecessor_planner_commissioned,
    predecessor_production_writes,reconciled_by,reconciled_by_email,operational,
    activation_ready,writer_active,planner_commissioned,production_writes,rollback_contract,event_key)
  VALUES(
    'forward_reconcile',p_monitor_user_id,p_gateway_instance_id,p_release_name,p_source_sha,
    p_source_tree_sha,p_manifest_sha256,p_archive_sha256,503,'contained','20260827053000',v_ledger_name,
    v_ledger_hash,v_provision_hash,v_verify_hash,
    jsonb_build_object(
      'provision_signature','public.provision_pdc_monitor_contained_binding_503(uuid,text,text,text,text)',
      'verify_signature','public.verify_pdc_monitor_runtime_binding_503(text,text,text,text,text,text,text)',
      'provision_marker','PDC_503_ALREADY_TRANSITIONED_INPUT_DRIFT',
      'verify_marker','runtime_binding_mismatch',
      'predecessor_actor_id','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b',
      'predecessor_gateway_instance_id','pdc-monitor-staging-sales-uid509-v1',
      'predecessor_release_name','pdc-monitor-staging-m502-2026.08.44',
      'predecessor_source_sha','37a1fc0d83e0aa311cfb40b8c1804b9840922ea9',
      'predecessor_manifest_sha256','5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca'),
    p_monitor_user_id,'pdc-monitor-staging-sales-uid509-v1',
    'pdc-monitor-staging-m502-2026.08.44','37a1fc0d83e0aa311cfb40b8c1804b9840922ea9',
    '5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca',
    encode(extensions.digest(convert_to(concat_ws('|',
      'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b',
      'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
      '37a1fc0d83e0aa311cfb40b8c1804b9840922ea9',
      '5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca'),'UTF8'),'sha256'),'hex'),
    false,false,false,false,false,v_admin_id,v_admin_email,false,false,false,false,false,
    'transaction rollback only; predecessor 503 remains unchanged',v_event_key)
  RETURNING * INTO v_existing;

  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,after_data,metadata)
  VALUES('role_change','pdc_monitor_contained_binding_reconciliations_504',v_existing.reconciliation_id,
    v_admin_id,v_admin_email,
    jsonb_build_object('event_kind',v_existing.event_kind,'actor_id',v_existing.actor_id,
      'gateway_instance_id',v_existing.gateway_instance_id,'release_name',v_existing.release_name,
      'source_sha',v_existing.source_sha,'manifest_sha256',v_existing.manifest_sha256,
      'archive_sha256',v_existing.archive_sha256,'migration_head',v_existing.migration_head,
      'mode',v_existing.mode,'operational',false,'activation_ready',false,
      'writer_active',false,'planner_commissioned',false,'production_writes',false),
    jsonb_build_object('event','pdc_monitor_contained_binding_forward_reconciled_504',
      'predecessor_ledger_name',v_existing.predecessor_ledger_name,
      'predecessor_ledger_sha256',v_existing.predecessor_ledger_sha256,
      'predecessor_provision_function_sha256',v_existing.predecessor_provision_function_sha256,
      'predecessor_verify_function_sha256',v_existing.predecessor_verify_function_sha256,
      'rollback_available',true,'production_untouched',true));

  RETURN jsonb_build_object(
    'ok',true,'code','pdc_monitor_contained_binding_reconciled_504',
    'idempotent',false,'reconciliation_id',v_existing.reconciliation_id,
    'actor_id',v_existing.actor_id,'gateway_instance_id',v_existing.gateway_instance_id,
    'release_name',v_existing.release_name,'source_sha',v_existing.source_sha,
    'source_tree_sha',v_existing.source_tree_sha,'manifest_sha256',v_existing.manifest_sha256,
    'archive_sha256',v_existing.archive_sha256,
    'migration_head',v_existing.migration_head,'mode',v_existing.mode,
    'operational',false,'activation_ready',false,'writer_active',false,
    'planner_commissioned',false,'production_writes',false,'rollback_available',true,
    'rollback_contract',v_existing.rollback_contract);
END
$reconcile$;
REVOKE ALL ON FUNCTION public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text) TO authenticated;
DO $post$
BEGIN
  IF to_regprocedure('public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)') IS NULL
     OR NOT has_function_privilege('authenticated','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE')
     OR has_function_privilege('service_role','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE')
  THEN RAISE EXCEPTION 'PDC_506_RECONCILE_FUNCTION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827056000','506_repair_contained_email_runtime_reconcile_head',ARRAY[
  'Require the exact applied timestamped 505 repair ledger row and reject later timestamped drift',
  'Allow the contained 504 reconcile RPC to observe the applied 505 poststate while retaining exact 503 predecessor binding proof',
  'Preserve source tree/manifest/archive candidate binding, actor checks, immutable RLS history, idempotency and fail-closed readiness',
  'Production, mailbox, monitor, planner, scheduler, email and vehicle writes remain untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
