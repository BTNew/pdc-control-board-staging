-- STAGING ONLY 504: append-only successor for the reviewed contained Email runtime pair.
-- This migration records a forward reconciliation event; it does not enable a
-- monitor, mailbox, writer, planner, scheduler, outbound email, or vehicle path.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-504-contained-email-runtime-forward-reconcile',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR to_regprocedure('public.provision_pdc_monitor_contained_binding_503(uuid,text,text,text,text)') IS NULL
     OR to_regprocedure('public.verify_pdc_monitor_runtime_binding_503(text,text,text,text,text,text,text)') IS NULL
     OR to_regclass('public.pdc_monitor_contained_binding_reconciliations_504') IS NOT NULL
     OR to_regprocedure('public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)') IS NOT NULL
     OR to_regprocedure('public.verify_pdc_monitor_contained_binding_504(text,text,text,text,text,text,text)') IS NOT NULL
     OR to_regprocedure('public.get_pdc_monitor_contained_binding_504()') IS NOT NULL
  THEN
    RAISE EXCEPTION 'PDC_504_STAGING_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000';
  END IF;
END
$guard$;

CREATE TABLE public.pdc_monitor_contained_binding_reconciliations_504(
  reconciliation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  singleton boolean NOT NULL DEFAULT true CHECK(singleton),
  event_kind text NOT NULL CHECK(event_kind='forward_reconcile'),
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT
    CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid),
  gateway_instance_id text NOT NULL
    CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL
    CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  source_sha text NOT NULL
    CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'),
  source_tree_sha text NOT NULL
    CHECK(source_tree_sha='8981540501bc629e189c39c9ea8a9adf3165d397'),
  manifest_sha256 text NOT NULL
    CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'),
  archive_sha256 text NOT NULL
    CHECK(archive_sha256='4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90'),
  migration_head integer NOT NULL CHECK(migration_head=503),
  mode text NOT NULL CHECK(mode='contained'),
  predecessor_actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT
    CHECK(predecessor_actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid),
  predecessor_gateway_instance_id text NOT NULL
    CHECK(predecessor_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  predecessor_release_name text NOT NULL
    CHECK(predecessor_release_name='pdc-monitor-staging-m502-2026.08.44'),
  predecessor_source_sha text NOT NULL
    CHECK(predecessor_source_sha='37a1fc0d83e0aa311cfb40b8c1804b9840922ea9'),
  predecessor_manifest_sha256 text NOT NULL
    CHECK(predecessor_manifest_sha256='5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca'),
  predecessor_binding_sha256 text NOT NULL
    CHECK(predecessor_binding_sha256~'^[a-f0-9]{64}$'),
  reconciled_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  reconciled_by_email text NOT NULL,
  operational boolean NOT NULL CHECK(NOT operational),
  activation_ready boolean NOT NULL CHECK(NOT activation_ready),
  writer_active boolean NOT NULL CHECK(NOT writer_active),
  planner_commissioned boolean NOT NULL CHECK(NOT planner_commissioned),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  rollback_contract text NOT NULL CHECK(rollback_contract='reapply predecessor pair through provision_pdc_monitor_contained_binding_503'),
  event_key text NOT NULL UNIQUE CHECK(event_key~'^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

ALTER TABLE public.pdc_monitor_contained_binding_reconciliations_504 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_monitor_contained_binding_reconciliations_504 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_monitor_contained_binding_reconciliations_504 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_monitor_contained_binding_reconciliation_immutable_504()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $immutable$
BEGIN
  RAISE EXCEPTION 'PDC_504_RECONCILIATION_HISTORY_IMMUTABLE' USING errcode='55000';
END
$immutable$;
REVOKE ALL ON FUNCTION public.pdc_monitor_contained_binding_reconciliation_immutable_504() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_monitor_contained_binding_reconciliation_immutable_504
  BEFORE UPDATE OR DELETE ON public.pdc_monitor_contained_binding_reconciliations_504
  FOR EACH ROW EXECUTE FUNCTION public.pdc_monitor_contained_binding_reconciliation_immutable_504();

CREATE FUNCTION public.reconcile_pdc_monitor_contained_binding_504(
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
  v_prior jsonb;
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
  v_actor_count integer;
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

  SELECT * INTO v_existing
  FROM public.pdc_monitor_contained_binding_reconciliations_504
  WHERE event_key=v_event_key;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok',true,'code','pdc_monitor_contained_binding_reconciled_504',
      'idempotent',true,'reconciliation_id',v_existing.reconciliation_id,
      'actor_id',v_existing.actor_id,'gateway_instance_id',v_existing.gateway_instance_id,
      'release_name',v_existing.release_name,'source_sha',v_existing.source_sha,
      'source_tree_sha',v_existing.source_tree_sha,'manifest_sha256',v_existing.manifest_sha256,
      'archive_sha256',v_existing.archive_sha256,'migration_head',v_existing.migration_head,
      'mode',v_existing.mode,'operational',v_existing.operational,
      'activation_ready',v_existing.activation_ready,'writer_active',v_existing.writer_active,
      'planner_commissioned',v_existing.planner_commissioned,
      'production_writes',v_existing.production_writes,'rollback_available',true,
      'rollback_contract',v_existing.rollback_contract);
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

  -- The predecessor RPC is the authoritative binding boundary. Calling it with
  -- its exact already-reviewed pair proves actor preservation without direct
  -- table DML and makes a drifted singleton fail closed.
  v_prior:=public.provision_pdc_monitor_contained_binding_503(
    p_monitor_user_id,'pdc-monitor-staging-sales-uid509-v1',
    'pdc-monitor-staging-m502-2026.08.44',
    '37a1fc0d83e0aa311cfb40b8c1804b9840922ea9',
    '5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca');
  IF coalesce(v_prior->>'ok','false')<>'true'
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

  INSERT INTO public.pdc_monitor_contained_binding_reconciliations_504(
    event_kind,actor_id,gateway_instance_id,release_name,source_sha,source_tree_sha,
    manifest_sha256,archive_sha256,migration_head,mode,predecessor_actor_id,
    predecessor_gateway_instance_id,predecessor_release_name,predecessor_source_sha,
    predecessor_manifest_sha256,predecessor_binding_sha256,reconciled_by,
    reconciled_by_email,operational,activation_ready,writer_active,planner_commissioned,
    production_writes,rollback_contract,event_key)
  VALUES(
    'forward_reconcile',p_monitor_user_id,p_gateway_instance_id,p_release_name,p_source_sha,
    p_source_tree_sha,p_manifest_sha256,p_archive_sha256,503,'contained',
    p_monitor_user_id,'pdc-monitor-staging-sales-uid509-v1',
    'pdc-monitor-staging-m502-2026.08.44',
    '37a1fc0d83e0aa311cfb40b8c1804b9840922ea9',
    '5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca',
    encode(extensions.digest(convert_to(concat_ws('|',
      'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b',
      'pdc-monitor-staging-sales-uid509-v1',
      'pdc-monitor-staging-m502-2026.08.44',
      '37a1fc0d83e0aa311cfb40b8c1804b9840922ea9',
      '5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca'),'UTF8'),'sha256'),'hex'),
    v_admin_id,v_admin_email,false,false,false,false,false,
    'reapply predecessor pair through provision_pdc_monitor_contained_binding_503',v_event_key)
  RETURNING * INTO v_existing;

  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,after_data,metadata)
  VALUES('role_change','pdc_monitor_contained_binding_reconciliations_504',v_existing.reconciliation_id,
    v_admin_id,v_admin_email,
    jsonb_build_object('event_kind',v_existing.event_kind,'actor_id',v_existing.actor_id,
      'gateway_instance_id',v_existing.gateway_instance_id,'release_name',v_existing.release_name,
      'source_sha',v_existing.source_sha,'source_tree_sha',v_existing.source_tree_sha,
      'manifest_sha256',v_existing.manifest_sha256,'archive_sha256',v_existing.archive_sha256,
      'migration_head',v_existing.migration_head,'mode',v_existing.mode,
      'operational',false,'activation_ready',false,'writer_active',false,
      'planner_commissioned',false,'production_writes',false),
    jsonb_build_object('event','pdc_monitor_contained_binding_forward_reconciled_504',
      'predecessor_source_sha',v_existing.predecessor_source_sha,
      'predecessor_manifest_sha256',v_existing.predecessor_manifest_sha256,
      'rollback_available',true,'production_untouched',true));

  RETURN jsonb_build_object(
    'ok',true,'code','pdc_monitor_contained_binding_reconciled_504',
    'idempotent',false,'reconciliation_id',v_existing.reconciliation_id,
    'actor_id',v_existing.actor_id,'gateway_instance_id',v_existing.gateway_instance_id,
    'release_name',v_existing.release_name,'source_sha',v_existing.source_sha,
    'source_tree_sha',v_existing.source_tree_sha,'manifest_sha256',v_existing.manifest_sha256,
    'archive_sha256',v_existing.archive_sha256,'migration_head',v_existing.migration_head,
    'mode',v_existing.mode,'operational',false,'activation_ready',false,
    'writer_active',false,'planner_commissioned',false,'production_writes',false,
    'rollback_available',true,'rollback_contract',v_existing.rollback_contract);
END
$reconcile$;
REVOKE ALL ON FUNCTION public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text) TO authenticated;

CREATE FUNCTION public.verify_pdc_monitor_contained_binding_504(
  p_gateway_instance_id text,
  p_release_name text,
  p_source_sha text,
  p_manifest_sha256 text,
  p_mode text,
  p_source_tree_sha text DEFAULT NULL,
  p_archive_sha256 text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $verify$
DECLARE
  v_event public.pdc_monitor_contained_binding_reconciliations_504%rowtype;
  v_event_key text;
BEGIN
  IF p_gateway_instance_id IS NULL OR p_release_name IS NULL OR p_source_sha IS NULL
     OR p_manifest_sha256 IS NULL OR p_mode IS NULL
     OR p_gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
     OR p_release_name<>'pdc-monitor-staging-m502-2026.08.44'
     OR p_source_sha<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     OR p_manifest_sha256<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     OR p_mode<>'contained'
     OR p_source_tree_sha IS DISTINCT FROM '8981540501bc629e189c39c9ea8a9adf3165d397'
     OR p_archive_sha256 IS DISTINCT FROM '4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90'
  THEN
    RETURN jsonb_build_object('ok',false,'code','contained_reviewed_pair_mismatch',
      'operational',false,'activation_ready',false,'writer_active',false,
      'planner_commissioned',false,'production_writes',false);
  END IF;
  v_event_key:=encode(extensions.digest(convert_to(concat_ws('|',
    'pdc-monitor-contained-binding-504','forward_reconcile',
    'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b',
    'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
    'e850c319989d98b45b95a28aa815d78e2c2e3a4b',
    '8981540501bc629e189c39c9ea8a9adf3165d397',
    'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
    '4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90',
    '503','contained'),'UTF8'),'sha256'),'hex');
  SELECT * INTO v_event FROM public.pdc_monitor_contained_binding_reconciliations_504
  WHERE event_key=v_event_key ORDER BY created_at DESC,reconciliation_id DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','contained_successor_not_reconciled',
      'operational',false,'activation_ready',false,'writer_active',false,
      'planner_commissioned',false,'production_writes',false);
  END IF;
  RETURN jsonb_build_object('ok',true,'code','pdc_monitor_contained_binding_reconciled_504',
    'reconciliation_id',v_event.reconciliation_id,'actor_id',v_event.actor_id,
    'gateway_instance_id',v_event.gateway_instance_id,'release_name',v_event.release_name,
    'source_sha',v_event.source_sha,'source_tree_sha',v_event.source_tree_sha,
    'manifest_sha256',v_event.manifest_sha256,'archive_sha256',v_event.archive_sha256,
    'migration_head',v_event.migration_head,'mode',v_event.mode,
    'operational',v_event.operational,'activation_ready',v_event.activation_ready,
    'writer_active',v_event.writer_active,'planner_commissioned',v_event.planner_commissioned,
    'production_writes',v_event.production_writes,'rollback_available',true,
    'rollback_contract',v_event.rollback_contract);
END
$verify$;
REVOKE ALL ON FUNCTION public.verify_pdc_monitor_contained_binding_504(text,text,text,text,text,text,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.verify_pdc_monitor_contained_binding_504(text,text,text,text,text,text,text) TO authenticated;

CREATE FUNCTION public.get_pdc_monitor_contained_binding_504()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $read$
  SELECT coalesce((SELECT public.verify_pdc_monitor_contained_binding_504(
    e.gateway_instance_id,e.release_name,e.source_sha,e.manifest_sha256,e.mode,
    e.source_tree_sha,e.archive_sha256)
    FROM public.pdc_monitor_contained_binding_reconciliations_504 e
    ORDER BY e.created_at DESC,e.reconciliation_id DESC LIMIT 1),
    jsonb_build_object('ok',false,'code','contained_successor_not_reconciled',
      'operational',false,'activation_ready',false,'writer_active',false,
      'planner_commissioned',false,'production_writes',false));
$read$;
REVOKE ALL ON FUNCTION public.get_pdc_monitor_contained_binding_504() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_monitor_contained_binding_504() TO authenticated;

DO $post$
BEGIN
  IF (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
      WHERE oid='public.pdc_monitor_contained_binding_reconciliations_504'::regclass) IS DISTINCT FROM true
     OR EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public'
               AND tablename='pdc_monitor_contained_binding_reconciliations_504')
     OR has_table_privilege('public','public.pdc_monitor_contained_binding_reconciliations_504','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     OR has_table_privilege('anon','public.pdc_monitor_contained_binding_reconciliations_504','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     OR has_table_privilege('authenticated','public.pdc_monitor_contained_binding_reconciliations_504','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     OR has_table_privilege('service_role','public.pdc_monitor_contained_binding_reconciliations_504','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     OR NOT has_function_privilege('authenticated','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.verify_pdc_monitor_contained_binding_504(text,text,text,text,text,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.get_pdc_monitor_contained_binding_504()','EXECUTE')
     OR has_function_privilege('anon','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE')
     OR has_function_privilege('service_role','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE')
  THEN
    RAISE EXCEPTION 'PDC_504_SECURITY_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827052000','504_forward_reconcile_contained_email_runtime',ARRAY[
  'Require the exact staging project and installed contained migration-503 predecessor RPCs',
  'Append the reviewed source/tree/manifest/archive pair without rewriting the applied 503 singleton or its history',
  'Preserve the exact non-human sales actor, gateway, release, contained mode and fail-closed non-operational readiness',
  'Require administrator identity, actor role identity, no active writer/mailbox/automatic actions and exact predecessor binding proof',
  'Expose authenticated verification and idempotent replay while denying direct table DML and keeping reconciliation history immutable',
  'Retain the predecessor RPC as the explicit rollback path; do not enable monitor, mailbox, planner, scheduler, email or vehicle writes',
  'Preserve the staging sentinel and leave Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
