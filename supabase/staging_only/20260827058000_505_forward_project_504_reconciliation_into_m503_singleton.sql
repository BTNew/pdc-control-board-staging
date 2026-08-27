-- STAGING ONLY 505: forward-project the reviewed 504 reconciliation into
-- the frozen m503 canonical singleton. This migration is append-only and
-- creates only guarded RPC/history support; the projection occurs only via
-- the authenticated administrator RPC below.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-505-contained-email-runtime-compatibility',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_504_reconcile_sha text;
  v_503_provision_sha text;
  v_503_verify_sha text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
    INTO v_504_reconcile_sha
  FROM pg_proc p
  WHERE p.oid='public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
    INTO v_503_provision_sha
  FROM pg_proc p
  WHERE p.oid='public.provision_pdc_monitor_contained_binding_503(uuid,text,text,text,text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
    INTO v_503_verify_sha
  FROM pg_proc p
  WHERE p.oid='public.verify_pdc_monitor_runtime_binding_503(text,text,text,text,text,text,text)'::regprocedure;

  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$' AND version>'20260827057000')<>0
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260827053000' AND name='503_existing_sales_contained_monitor_commissioning')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260827054000' AND name='504_forward_reconcile_contained_email_runtime')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260827055000' AND name='505_repair_contained_email_runtime_reconcile_guard')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260827056000' AND name='506_repair_contained_email_runtime_reconcile_head')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260827057000' AND name='507_stabilize_contained_email_runtime_reconcile_lineage')<>1
     OR v_504_reconcile_sha<>'491f4c7237f4e5601f4d86975bdcb9e1dda44a58da9dc6f593f83549f2b539c4'
     OR v_503_provision_sha<>'317d87a1d8f2dc184f6db6ad4309ffbb88d77bf6976a7571f95aafc19e58f45f'
     OR v_503_verify_sha<>'428f5c220ce6aa59d5ecc8e05483a6f9992b0db36f69fa9a3c50debbe859f8a9'
     OR to_regclass('public.pdc_monitor_runtime_binding_compatibility_history_505') IS NOT NULL
     OR to_regprocedure('public.admin_forward_project_pdc_monitor_contained_binding_505(uuid)') IS NOT NULL
     OR to_regprocedure('public.admin_rollback_pdc_monitor_contained_binding_505(uuid)') IS NOT NULL
     OR to_regprocedure('public.verify_pdc_monitor_m503_compatibility_505(uuid)') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827058000')<>0
  THEN
    RAISE EXCEPTION 'PDC_505_STAGING_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000';
  END IF;
END
$guard$;

CREATE TABLE public.pdc_monitor_runtime_binding_compatibility_history_505(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind IN ('forward_project','rollback')),
  reconciliation_id uuid NOT NULL,
  binding_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  gateway_instance_id text NOT NULL,
  release_name text NOT NULL,
  source_sha text NOT NULL,
  source_tree_sha text NOT NULL,
  manifest_sha256 text NOT NULL,
  archive_sha256 text NOT NULL,
  before_binding jsonb NOT NULL,
  after_binding jsonb NOT NULL,
  operational boolean NOT NULL DEFAULT false CHECK(NOT operational),
  activation_ready boolean NOT NULL DEFAULT false CHECK(NOT activation_ready),
  writer_active boolean NOT NULL DEFAULT false CHECK(NOT writer_active),
  planner_commissioned boolean NOT NULL DEFAULT false CHECK(NOT planner_commissioned),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  performed_by uuid NOT NULL,
  performed_by_email text NOT NULL,
  rollback_contract text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE FUNCTION public.pdc_monitor_runtime_binding_compatibility_history_immutable_505()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public
AS $immutable$
BEGIN
  RAISE EXCEPTION 'PDC_505_COMPATIBILITY_HISTORY_IMMUTABLE' USING errcode='55000';
END
$immutable$;

CREATE TRIGGER pdc_monitor_runtime_binding_compatibility_history_immutable_505
BEFORE UPDATE OR DELETE ON public.pdc_monitor_runtime_binding_compatibility_history_505
FOR EACH ROW EXECUTE FUNCTION public.pdc_monitor_runtime_binding_compatibility_history_immutable_505();

ALTER TABLE public.pdc_monitor_runtime_binding_compatibility_history_505 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_monitor_runtime_binding_compatibility_history_505 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_monitor_runtime_binding_compatibility_history_505 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.admin_forward_project_pdc_monitor_contained_binding_505(
  p_reconciliation_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $forward$
DECLARE
  v_admin_id uuid:=auth.uid();
  v_admin_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_admin_count integer;
  v_rec public.pdc_monitor_contained_binding_reconciliations_504%rowtype;
  v_binding public.pdc_monitor_runtime_bindings_255%rowtype;
  v_existing public.pdc_monitor_runtime_binding_compatibility_history_505%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_event_key text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_admin_id IS NULL
     OR v_admin_email=''
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
  SELECT * INTO v_rec
  FROM public.pdc_monitor_contained_binding_reconciliations_504
  WHERE reconciliation_id=p_reconciliation_id AND singleton
  FOR UPDATE;
  IF NOT FOUND
     OR v_rec.reconciliation_id<>'0c53cb93-bda2-4d02-90db-4c1b96cc7896'::uuid THEN
    RAISE EXCEPTION 'PDC_505_RECONCILIATION_PROOF_REQUIRED' USING errcode='55000';
  END IF;
  IF v_rec.event_kind<>'forward_reconcile'
     OR v_rec.actor_id<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR v_rec.gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
     OR v_rec.release_name<>'pdc-monitor-staging-m502-2026.08.44'
     OR v_rec.source_sha<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     OR v_rec.source_tree_sha<>'8981540501bc629e189c39c9ea8a9adf3165d397'
     OR v_rec.manifest_sha256<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     OR v_rec.archive_sha256<>'4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90'
     OR v_rec.migration_head<>503 OR v_rec.mode<>'contained'
     OR v_rec.operational OR v_rec.activation_ready OR v_rec.writer_active
     OR v_rec.planner_commissioned OR v_rec.production_writes THEN
    RAISE EXCEPTION 'PDC_505_RECONCILIATION_PAIR_MISMATCH' USING errcode='55000';
  END IF;

  v_event_key:=encode(extensions.digest(convert_to(concat_ws('|',
    'pdc-monitor-contained-binding-505','forward_project',v_rec.reconciliation_id::text,
    v_rec.actor_id::text,v_rec.gateway_instance_id,v_rec.release_name,v_rec.source_sha,
    v_rec.source_tree_sha,v_rec.manifest_sha256,v_rec.archive_sha256),'UTF8'),'sha256'),'hex');
  SELECT * INTO v_existing
  FROM public.pdc_monitor_runtime_binding_compatibility_history_505
  WHERE event_key=v_event_key;
  IF FOUND THEN
    SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton;
    IF v_binding.actor_id<>v_rec.actor_id
       OR v_binding.gateway_instance_id<>v_rec.gateway_instance_id
       OR v_binding.release_name<>v_rec.release_name
       OR v_binding.source_sha<>v_rec.source_sha
       OR v_binding.manifest_sha256<>v_rec.manifest_sha256 THEN
      RAISE EXCEPTION 'PDC_505_COMPATIBILITY_CANONICAL_DRIFT' USING errcode='55000';
    END IF;
    RETURN jsonb_build_object('ok',true,'code','pdc_monitor_m503_compatibility_projected_505',
      'idempotent',true,'projection_state','pdc_505_compatibility_already_projected','history_id',v_existing.history_id,'reconciliation_id',v_rec.reconciliation_id,
      'actor_id',v_binding.actor_id,'gateway_instance_id',v_binding.gateway_instance_id,
      'release_name',v_binding.release_name,'source_sha',v_binding.source_sha,
      'manifest_sha256',v_binding.manifest_sha256,'source_tree_sha',v_rec.source_tree_sha,
      'archive_sha256',v_rec.archive_sha256,'migration_head',503,'mode','contained',
      'operational',false,'activation_ready',false,'writer_active',false,
      'planner_commissioned',false,'production_writes',false,'rollback_available',true,
      'rollback_contract','forward migration only; exact old singleton snapshot retained');
  END IF;

  SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton FOR UPDATE;
  IF NOT FOUND
     OR v_binding.actor_id<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR v_binding.gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
     OR v_binding.release_name<>'pdc-monitor-staging-m502-2026.08.44'
     OR v_binding.source_sha<>'37a1fc0d83e0aa311cfb40b8c1804b9840922ea9'
     OR v_binding.manifest_sha256<>'5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca'
     OR v_binding.semantic_planner_sha256 IS NOT NULL
     OR v_binding.semantic_planner_trust_receipt_sha256 IS NOT NULL
     OR v_binding.semantic_planner_commissioned_at IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_505_COMPATIBILITY_CANONICAL_PRESTATE_MISMATCH' USING errcode='55000';
  END IF;
  v_before:=to_jsonb(v_binding);

  UPDATE public.pdc_monitor_runtime_bindings_255
  SET source_sha=v_rec.source_sha,
      manifest_sha256=v_rec.manifest_sha256,
      provisioned_by=v_admin_id,
      provisioned_at=clock_timestamp()
  WHERE binding_id=v_binding.binding_id AND singleton
    AND actor_id=v_rec.actor_id
    AND gateway_instance_id=v_rec.gateway_instance_id
    AND release_name=v_rec.release_name
    AND source_sha='37a1fc0d83e0aa311cfb40b8c1804b9840922ea9'
    AND manifest_sha256='5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca'
    AND semantic_planner_sha256 IS NULL
    AND semantic_planner_trust_receipt_sha256 IS NULL
    AND semantic_planner_commissioned_at IS NULL
  RETURNING * INTO v_binding;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PDC_505_COMPATIBILITY_CONCURRENT_DRIFT' USING errcode='40001';
  END IF;
  v_after:=to_jsonb(v_binding);

  INSERT INTO public.pdc_monitor_runtime_binding_compatibility_history_505(
    event_key,event_kind,reconciliation_id,binding_id,actor_id,gateway_instance_id,release_name,
    source_sha,source_tree_sha,manifest_sha256,archive_sha256,before_binding,after_binding,
    operational,activation_ready,writer_active,planner_commissioned,production_writes,
    performed_by,performed_by_email,rollback_contract)
  VALUES(v_event_key,'forward_project',v_rec.reconciliation_id,v_binding.binding_id,v_rec.actor_id,
    v_binding.gateway_instance_id,v_binding.release_name,v_rec.source_sha,v_rec.source_tree_sha,
    v_rec.manifest_sha256,v_rec.archive_sha256,v_before,v_after,false,false,false,false,false,
    v_admin_id,v_admin_email,'forward migration only; exact old singleton snapshot retained')
  RETURNING * INTO v_existing;

  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','pdc_monitor_runtime_bindings_255',v_binding.binding_id,v_admin_id,v_admin_email,
    v_before,v_after,jsonb_build_object('event_type','pdc_monitor_m503_compatibility_projected_505',
      'reconciliation_id',v_rec.reconciliation_id,'actor_id',v_rec.actor_id,
      'gateway_instance_id',v_rec.gateway_instance_id,'release_name',v_rec.release_name,
      'source_sha',v_rec.source_sha,'source_tree_sha',v_rec.source_tree_sha,
      'manifest_sha256',v_rec.manifest_sha256,'archive_sha256',v_rec.archive_sha256,
      'operational',false,'activation_ready',false,'writer_active',false,
      'planner_commissioned',false,'production_writes',false,'rollback_available',true,
      'rollback_contract','forward migration only; exact old singleton snapshot retained'));

  RETURN jsonb_build_object('ok',true,'code','pdc_monitor_m503_compatibility_projected_505',
    'idempotent',false,'history_id',v_existing.history_id,'reconciliation_id',v_rec.reconciliation_id,
    'actor_id',v_binding.actor_id,'gateway_instance_id',v_binding.gateway_instance_id,
    'release_name',v_binding.release_name,'source_sha',v_binding.source_sha,
    'source_tree_sha',v_rec.source_tree_sha,'manifest_sha256',v_binding.manifest_sha256,
    'archive_sha256',v_rec.archive_sha256,'migration_head',503,'mode','contained',
    'operational',false,'activation_ready',false,'writer_active',false,
    'planner_commissioned',false,'production_writes',false,'rollback_available',true,
    'rollback_contract','forward migration only; exact old singleton snapshot retained');
END
$forward$;

CREATE FUNCTION public.admin_rollback_pdc_monitor_contained_binding_505(
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

CREATE FUNCTION public.verify_pdc_monitor_m503_compatibility_505(
  p_reconciliation_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path=pg_catalog,public,auth,extensions
AS $verify$
DECLARE
  v_admin_id uuid:=auth.uid();
  v_admin_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_admin_count integer;
  v_rec public.pdc_monitor_contained_binding_reconciliations_504%rowtype;
  v_binding public.pdc_monitor_runtime_bindings_255%rowtype;
  v_history public.pdc_monitor_runtime_binding_compatibility_history_505%rowtype;
BEGIN
  SELECT count(*) INTO v_admin_count
  FROM public.pdc_user_roles r
  JOIN auth.users u ON u.id=r.auth_user_id AND lower(coalesce(u.email,''))=v_admin_email
  WHERE r.auth_user_id=v_admin_id AND lower(r.email)=v_admin_email
    AND r.active AND r.account_status='approved' AND r.role::text='administrator';
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_admin_id IS NULL OR v_admin_count<>1 THEN
    RAISE EXCEPTION 'PDC_505_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501';
  END IF;
  SELECT * INTO v_rec FROM public.pdc_monitor_contained_binding_reconciliations_504
    WHERE reconciliation_id=p_reconciliation_id AND singleton;
  SELECT * INTO v_history FROM public.pdc_monitor_runtime_binding_compatibility_history_505
    WHERE reconciliation_id=p_reconciliation_id AND event_kind='forward_project'
    ORDER BY created_at,history_id LIMIT 1;
  SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton;
  IF NOT FOUND OR v_history.history_id IS NULL
     OR v_binding.actor_id<>v_rec.actor_id
     OR v_binding.gateway_instance_id<>v_rec.gateway_instance_id
     OR v_binding.release_name<>v_rec.release_name
     OR v_binding.source_sha<>v_rec.source_sha
     OR v_binding.manifest_sha256<>v_rec.manifest_sha256 THEN
    RETURN jsonb_build_object('ok',false,'code','pdc_monitor_m503_compatibility_not_projected_505',
      'migration_head',503,'mode','contained','operational',false,'activation_ready',false,
      'writer_active',false,'planner_commissioned',false,'production_writes',false);
  END IF;
  RETURN jsonb_build_object('ok',true,'code','pdc_monitor_m503_compatibility_verified_505',
    'history_id',v_history.history_id,'reconciliation_id',v_rec.reconciliation_id,
    'actor_id',v_binding.actor_id,'gateway_instance_id',v_binding.gateway_instance_id,
    'release_name',v_binding.release_name,'source_sha',v_binding.source_sha,
    'source_tree_sha',v_rec.source_tree_sha,'manifest_sha256',v_binding.manifest_sha256,
    'archive_sha256',v_rec.archive_sha256,'migration_head',503,'mode','contained',
    'operational',false,'activation_ready',false,'writer_active',false,
    'planner_commissioned',false,'production_writes',false,'rollback_available',true,
    'rollback_contract','forward migration only; exact old singleton snapshot retained');
END
$verify$;

REVOKE ALL ON FUNCTION public.admin_forward_project_pdc_monitor_contained_binding_505(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admin_forward_project_pdc_monitor_contained_binding_505(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_monitor_contained_binding_505(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_monitor_contained_binding_505(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.verify_pdc_monitor_m503_compatibility_505(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.verify_pdc_monitor_m503_compatibility_505(uuid) TO authenticated;

DO $post$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR to_regclass('public.pdc_monitor_runtime_binding_compatibility_history_505') IS NULL
     OR NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_monitor_runtime_binding_compatibility_history_505'::regclass)
     OR NOT has_function_privilege('authenticated','public.admin_forward_project_pdc_monitor_contained_binding_505(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.admin_forward_project_pdc_monitor_contained_binding_505(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.admin_forward_project_pdc_monitor_contained_binding_505(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.admin_rollback_pdc_monitor_contained_binding_505(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.admin_rollback_pdc_monitor_contained_binding_505(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.admin_rollback_pdc_monitor_contained_binding_505(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.verify_pdc_monitor_m503_compatibility_505(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.verify_pdc_monitor_m503_compatibility_505(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.verify_pdc_monitor_m503_compatibility_505(uuid)','EXECUTE')
     OR has_table_privilege('authenticated','public.pdc_monitor_runtime_binding_compatibility_history_505','SELECT')
     OR has_table_privilege('authenticated','public.pdc_monitor_runtime_binding_compatibility_history_505','INSERT')
     OR has_table_privilege('authenticated','public.pdc_monitor_runtime_binding_compatibility_history_505','UPDATE')
     OR has_table_privilege('authenticated','public.pdc_monitor_runtime_binding_compatibility_history_505','DELETE')
  THEN
    RAISE EXCEPTION 'PDC_505_COMPATIBILITY_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827058000','505_forward_project_504_reconciliation_into_m503_singleton',ARRAY[
  'Require the exact successful 504 reconciliation ID and exact actor/gateway/release/source/tree/manifest/archive pair',
  'Guard current timestamped 503 through 507 lineage and exact deployed predecessor/reconcile function source hashes',
  'Project only through authenticated Administrator security-definer RPC into the m503 canonical singleton',
  'Preserve the old singleton JSON snapshot in forced-RLS immutable append-only history and audit_events',
  'Provide guarded forward-only rollback RPC with exact candidate precondition and idempotency',
  'Keep contained mode fail-closed: operational, activation_ready, writer_active, planner_commissioned and production_writes false',
  'Production, mailbox, email, monitor, planner, scheduler and vehicle writes remain untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
