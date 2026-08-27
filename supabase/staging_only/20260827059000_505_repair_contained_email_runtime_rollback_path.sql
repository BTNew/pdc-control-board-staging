-- STAGING ONLY 59000: repair the already-installed 505 rollback path.
-- Forward-only repair; no migration history or compatibility history is rewritten.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-505-contained-email-runtime-compatibility',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827058000' AND name='505_forward_project_504_reconciliation_into_m503_singleton')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827058000')<>0
     OR to_regprocedure('public.admin_rollback_pdc_monitor_contained_binding_505(uuid)') IS NULL
     OR to_regclass('public.pdc_monitor_runtime_binding_compatibility_history_505') IS NULL
     OR (SELECT count(*) FROM public.pdc_monitor_runtime_binding_compatibility_history_505 WHERE event_kind='forward_project' AND reconciliation_id='0c53cb93-bda2-4d02-90db-4c1b96cc7896')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827059000')<>0
  THEN RAISE EXCEPTION 'PDC_505_ROLLBACK_REPAIR_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.admin_rollback_pdc_monitor_contained_binding_505(
  p_reconciliation_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $rollback$
DECLARE
  v_admin_id uuid:=auth.uid();
  v_admin_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_admin_count integer;
  v_forward public.pdc_monitor_runtime_binding_compatibility_history_505%rowtype;
  v_existing public.pdc_monitor_runtime_binding_compatibility_history_505%rowtype;
  v_binding public.pdc_monitor_runtime_bindings_255%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_event_key text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_admin_id IS NULL OR v_admin_email=''
     OR coalesce(auth.jwt()->>'role','')<>'authenticated' THEN
    RAISE EXCEPTION 'PDC_505_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501';
  END IF;
  SELECT count(*) INTO v_admin_count
  FROM public.pdc_user_roles r
  JOIN auth.users u ON u.id=r.auth_user_id AND lower(coalesce(u.email,''))=v_admin_email
  WHERE r.auth_user_id=v_admin_id AND lower(r.email)=v_admin_email
    AND r.active AND r.account_status='approved' AND r.role::text='administrator';
  IF v_admin_count<>1 THEN
    RAISE EXCEPTION 'PDC_505_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-505-contained-email-runtime-compatibility',0));
  SELECT * INTO v_forward
  FROM public.pdc_monitor_runtime_binding_compatibility_history_505
  WHERE reconciliation_id=p_reconciliation_id AND event_kind='forward_project'
  ORDER BY created_at,history_id LIMIT 1;
  IF NOT FOUND OR v_forward.reconciliation_id<>'0c53cb93-bda2-4d02-90db-4c1b96cc7896'::uuid
     OR v_forward.actor_id<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR v_forward.gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
     OR v_forward.release_name<>'pdc-monitor-staging-m502-2026.08.44'
     OR v_forward.source_sha<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     OR v_forward.source_tree_sha<>'8981540501bc629e189c39c9ea8a9adf3165d397'
     OR v_forward.manifest_sha256<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     OR v_forward.archive_sha256<>'4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90' THEN
    RAISE EXCEPTION 'PDC_505_COMPATIBILITY_ROLLBACK_PROOF_REQUIRED' USING errcode='55000';
  END IF;
  SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PDC_505_COMPATIBILITY_ROLLBACK_CANONICAL_PRESTATE_MISMATCH' USING errcode='55000';
  END IF;
  v_event_key:=encode(extensions.digest(convert_to(concat_ws('|',
    'pdc-monitor-contained-binding-505','rollback',p_reconciliation_id::text,v_forward.history_id::text),
    'UTF8'),'sha256'),'hex');
  SELECT * INTO v_existing
  FROM public.pdc_monitor_runtime_binding_compatibility_history_505
  WHERE event_key=v_event_key;
  IF FOUND THEN
    IF v_binding.source_sha<>'37a1fc0d83e0aa311cfb40b8c1804b9840922ea9'
       OR v_binding.manifest_sha256<>'5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca' THEN
      RAISE EXCEPTION 'PDC_505_COMPATIBILITY_ROLLBACK_CANONICAL_DRIFT' USING errcode='55000';
    END IF;
    RETURN jsonb_build_object('ok',true,'code','pdc_monitor_m503_compatibility_rolled_back_505',
      'idempotent',true,'history_id',v_existing.history_id,'reconciliation_id',p_reconciliation_id,
      'source_sha',v_binding.source_sha,'manifest_sha256',v_binding.manifest_sha256,
      'migration_head',503,'mode','contained','operational',false,'activation_ready',false,
      'writer_active',false,'planner_commissioned',false,'production_writes',false,
      'rollback_available',true,'rollback_contract','forward migration only; old singleton restored');
  END IF;
  IF v_binding.binding_id<>v_forward.binding_id
     OR v_binding.actor_id<>v_forward.actor_id
     OR v_binding.gateway_instance_id<>v_forward.gateway_instance_id
     OR v_binding.release_name<>v_forward.release_name
     OR v_binding.source_sha<>v_forward.source_sha
     OR v_binding.manifest_sha256<>v_forward.manifest_sha256
     OR v_binding.semantic_planner_sha256 IS NOT NULL
     OR v_binding.semantic_planner_trust_receipt_sha256 IS NOT NULL
     OR v_binding.semantic_planner_commissioned_at IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_505_COMPATIBILITY_ROLLBACK_PRECONDITION' USING errcode='55000';
  END IF;
  v_before:=to_jsonb(v_binding);
  UPDATE public.pdc_monitor_runtime_bindings_255
  SET actor_id=(v_forward.before_binding->>'actor_id')::uuid,
      gateway_instance_id=v_forward.before_binding->>'gateway_instance_id',
      release_name=v_forward.before_binding->>'release_name',
      source_sha=v_forward.before_binding->>'source_sha',
      manifest_sha256=v_forward.before_binding->>'manifest_sha256',
      provisioned_by=(v_forward.before_binding->>'provisioned_by')::uuid,
      provisioned_at=(v_forward.before_binding->>'provisioned_at')::timestamptz,
      semantic_planner_sha256=nullif(v_forward.before_binding->>'semantic_planner_sha256',''),
      semantic_planner_trust_receipt_sha256=nullif(v_forward.before_binding->>'semantic_planner_trust_receipt_sha256',''),
      semantic_planner_commissioned_at=nullif(v_forward.before_binding->>'semantic_planner_commissioned_at','')::timestamptz
  WHERE binding_id=v_binding.binding_id AND singleton
  RETURNING * INTO v_binding;
  v_after:=to_jsonb(v_binding);
  INSERT INTO public.pdc_monitor_runtime_binding_compatibility_history_505(
    event_key,event_kind,reconciliation_id,binding_id,actor_id,gateway_instance_id,release_name,
    source_sha,source_tree_sha,manifest_sha256,archive_sha256,before_binding,after_binding,
    operational,activation_ready,writer_active,planner_commissioned,production_writes,
    performed_by,performed_by_email,rollback_contract)
  VALUES(v_event_key,'rollback',p_reconciliation_id,v_binding.binding_id,v_forward.actor_id,
    v_forward.gateway_instance_id,v_forward.release_name,v_forward.source_sha,v_forward.source_tree_sha,
    v_forward.manifest_sha256,v_forward.archive_sha256,v_before,v_after,false,false,false,false,false,
    v_admin_id,v_admin_email,'forward migration only; old singleton restored')
  RETURNING * INTO v_existing;
  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','pdc_monitor_runtime_bindings_255',v_binding.binding_id,v_admin_id,v_admin_email,
    v_before,v_after,jsonb_build_object('event_type','pdc_monitor_m503_compatibility_rolled_back_505',
      'reconciliation_id',p_reconciliation_id,'rollback_of_history_id',v_forward.history_id,
      'operational',false,'activation_ready',false,'writer_active',false,
      'planner_commissioned',false,'production_writes',false,'production_untouched',true));
  RETURN jsonb_build_object('ok',true,'code','pdc_monitor_m503_compatibility_rolled_back_505',
    'idempotent',false,'history_id',v_existing.history_id,'reconciliation_id',p_reconciliation_id,
    'source_sha',v_binding.source_sha,'manifest_sha256',v_binding.manifest_sha256,
    'migration_head',503,'mode','contained','operational',false,'activation_ready',false,
    'writer_active',false,'planner_commissioned',false,'production_writes',false,
    'rollback_available',true,'rollback_contract','forward migration only; old singleton restored');
END
$rollback$;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_monitor_contained_binding_505(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_monitor_contained_binding_505(uuid) TO authenticated;
DO $post$
BEGIN
  IF to_regprocedure('public.admin_rollback_pdc_monitor_contained_binding_505(uuid)') IS NULL
     OR NOT has_function_privilege('authenticated','public.admin_rollback_pdc_monitor_contained_binding_505(uuid)','execute')
     OR has_function_privilege('anon','public.admin_rollback_pdc_monitor_contained_binding_505(uuid)','execute')
     OR has_function_privilege('service_role','public.admin_rollback_pdc_monitor_contained_binding_505(uuid)','execute')
  THEN RAISE EXCEPTION 'PDC_505_ROLLBACK_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827059000','505_repair_contained_email_runtime_rollback_path',ARRAY[
  'Repair only the rollback RPC control flow after the compatibility projection has succeeded',
  'Require the exact applied 58000 migration and exactly one successful 504 reconciliation history row',
  'Preserve the exact candidate proof, old singleton snapshot, immutable history and admin-only execution boundary',
  'Production, mailbox, monitor, planner, scheduler, email and vehicle writes remain untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
