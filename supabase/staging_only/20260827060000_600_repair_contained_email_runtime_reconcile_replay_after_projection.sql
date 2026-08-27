-- STAGING ONLY 600: repair idempotent reconciliation after the 580
-- compatibility projection.  The applied 503-590 history is never rewritten.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-600-contained-email-runtime-reconcile-replay',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827053000' AND name='503_existing_sales_contained_monitor_commissioning')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827054000' AND name='504_forward_reconcile_contained_email_runtime')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827055000' AND name='505_repair_contained_email_runtime_reconcile_guard')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827056000' AND name='506_repair_contained_email_runtime_reconcile_head')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827057000' AND name='507_stabilize_contained_email_runtime_reconcile_lineage')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827058000' AND name='505_forward_project_504_reconciliation_into_m503_singleton')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827059000' AND name='505_repair_contained_email_runtime_rollback_path')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827059000')<>0
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827060000')<>0
     OR to_regprocedure('public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)') IS NULL
     OR to_regclass('public.pdc_monitor_contained_binding_reconciliations_504') IS NULL
     OR to_regclass('public.pdc_monitor_runtime_binding_compatibility_history_505') IS NULL
  THEN RAISE EXCEPTION 'PDC_600_RECONCILE_REPLAY_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000'; END IF;
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
  v_projection_count integer;
  v_event_key text:=encode(extensions.digest(convert_to(concat_ws('|',
    'pdc-monitor-contained-binding-504','forward_reconcile',
    'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b',
    'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
    'e850c319989d98b45b95a28aa815d78e2c2e3a4b',
    '8981540501bc629e189c39c9ea8a9adf3165d397',
    'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
    '4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90',
    '503','contained'),'UTF8'),'sha256'),'hex');
  v_existing public.pdc_monitor_contained_binding_reconciliations_504%rowtype;
  v_binding public.pdc_monitor_runtime_bindings_255%rowtype;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-600-contained-email-runtime-reconcile-replay',0));

  SELECT count(*) INTO v_admin_count
  FROM public.pdc_user_roles r
  JOIN auth.users u ON u.id=r.auth_user_id AND lower(coalesce(u.email,''))=v_admin_email
  WHERE r.auth_user_id=v_admin_id AND lower(r.email)=v_admin_email
    AND r.active AND r.account_status='approved' AND r.role::text='administrator';
  IF v_admin_id IS NULL OR v_admin_email='' OR coalesce(auth.jwt()->>'role','')<>'authenticated' OR v_admin_count<>1 THEN
    RAISE EXCEPTION 'PDC_600_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501';
  END IF;

  IF p_monitor_user_id<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR p_gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
     OR p_release_name<>'pdc-monitor-staging-m502-2026.08.44'
     OR p_source_sha<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     OR p_source_tree_sha<>'8981540501bc629e189c39c9ea8a9adf3165d397'
     OR p_manifest_sha256<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     OR p_archive_sha256<>'4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90'
  THEN RAISE EXCEPTION 'PDC_600_REVIEWED_PAIR_MISMATCH' USING errcode='22023'; END IF;

  SELECT lower(email) INTO v_actor_email
  FROM auth.users
  WHERE id=p_monitor_user_id AND coalesce(raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor';
  SELECT count(*) INTO v_actor_count
  FROM public.pdc_user_roles r
  WHERE r.auth_user_id=p_monitor_user_id AND lower(r.email)=v_actor_email
    AND r.active AND r.account_status='approved' AND r.role::text='viewer';
  IF v_actor_email IS NULL OR v_actor_count<>1
     OR exists(select 1 from public.pdc_auditor_worker_identities w where w.auth_user_id=p_monitor_user_id and w.active)
     OR exists(select 1 from public.pdc_auditor_user_dealer_scopes s where s.auth_user_id=p_monitor_user_id and s.active)
     OR exists(select 1 from public.pdc_auditor_executor_identities e where e.auth_user_id=p_monitor_user_id and e.active and e.expires_at>clock_timestamp())
     OR exists(select 1 from public.pdc_auditor_service_identities_225 s where s.auth_user_id=p_monitor_user_id and s.active)
  THEN RAISE EXCEPTION 'PDC_600_DEDICATED_MONITOR_IDENTITY_REQUIRED' USING errcode='42501'; END IF;

  IF (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>0
     OR exists(select 1 from public.monitored_mailboxes where active)
     OR exists(select 1 from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled))
  THEN RAISE EXCEPTION 'PDC_600_CONTAINMENT_REQUIRED' USING errcode='55000'; END IF;

  IF (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827059000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827059000')<>1
  THEN RAISE EXCEPTION 'PDC_600_EXACT_LEDGER_HEAD_REQUIRED' USING errcode='55000'; END IF;

  SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton;
  IF NOT FOUND
     OR v_binding.actor_id<>p_monitor_user_id
     OR v_binding.gateway_instance_id<>p_gateway_instance_id
     OR v_binding.release_name<>p_release_name
     OR v_binding.source_sha<>p_source_sha
     OR v_binding.manifest_sha256<>p_manifest_sha256
     OR v_binding.semantic_planner_sha256 IS NOT NULL
     OR v_binding.semantic_planner_trust_receipt_sha256 IS NOT NULL
     OR v_binding.semantic_planner_commissioned_at IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_600_CANONICAL_BINDING_MISMATCH' USING errcode='55000'; END IF;

  SELECT count(*) INTO v_projection_count
  FROM public.pdc_monitor_runtime_binding_compatibility_history_505 h
  WHERE h.event_kind='forward_project'
    AND h.reconciliation_id='0c53cb93-bda2-4d02-90db-4c1b96cc7896'::uuid
    AND h.binding_id=v_binding.binding_id
    AND h.actor_id=p_monitor_user_id
    AND h.gateway_instance_id=p_gateway_instance_id
    AND h.release_name=p_release_name
    AND h.source_sha=p_source_sha
    AND h.source_tree_sha=p_source_tree_sha
    AND h.manifest_sha256=p_manifest_sha256
    AND h.archive_sha256=p_archive_sha256
    AND NOT h.operational AND NOT h.activation_ready AND NOT h.writer_active
    AND NOT h.planner_commissioned AND NOT h.production_writes;
  IF v_projection_count<>1 THEN
    RAISE EXCEPTION 'PDC_600_COMPATIBILITY_PROJECTION_PROOF_REQUIRED' USING errcode='55000';
  END IF;

  SELECT * INTO v_existing
  FROM public.pdc_monitor_contained_binding_reconciliations_504
  WHERE event_key=v_event_key
  ORDER BY created_at DESC,reconciliation_id DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PDC_600_RECONCILIATION_HISTORY_MISSING' USING errcode='55000';
  END IF;
  IF v_existing.actor_id<>p_monitor_user_id
     OR v_existing.gateway_instance_id<>p_gateway_instance_id
     OR v_existing.release_name<>p_release_name
     OR v_existing.source_sha<>p_source_sha
     OR v_existing.source_tree_sha<>p_source_tree_sha
     OR v_existing.manifest_sha256<>p_manifest_sha256
     OR v_existing.archive_sha256<>p_archive_sha256
     OR v_existing.migration_head<>503 OR v_existing.mode<>'contained'
     OR v_existing.operational OR v_existing.activation_ready OR v_existing.writer_active
     OR v_existing.planner_commissioned OR v_existing.production_writes
  THEN RAISE EXCEPTION 'PDC_600_RECONCILIATION_PAIR_DRIFT' USING errcode='55000'; END IF;

  RETURN jsonb_build_object(
    'ok',true,'code','pdc_monitor_contained_binding_reconciled_504','idempotent',true,
    'reconciliation_id',v_existing.reconciliation_id,'actor_id',v_existing.actor_id,
    'gateway_instance_id',v_existing.gateway_instance_id,'release_name',v_existing.release_name,
    'source_sha',v_existing.source_sha,'source_tree_sha',v_existing.source_tree_sha,
    'manifest_sha256',v_existing.manifest_sha256,'archive_sha256',v_existing.archive_sha256,
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
  THEN RAISE EXCEPTION 'PDC_600_RECONCILE_REPLAY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827060000','600_repair_contained_email_runtime_reconcile_replay_after_projection',ARRAY[
  'Repair the authenticated 504 reconciliation replay after the 580 compatibility projection changed the canonical singleton source and manifest',
  'Require the exact applied 503 through 590 ledger lineage, canonical .44 binding and one exact immutable 580 forward-project history row',
  'Return the original 504 reconciliation receipt idempotently without re-invoking the already-transitioned 503 provisioning RPC',
  'Preserve authenticated-only execution, identity exclusions, forced-RLS immutable history and fail-closed contained flags',
  'Production, mailbox, monitor, planner, scheduler, email and vehicle writes remain untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
