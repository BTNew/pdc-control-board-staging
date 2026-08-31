-- STAGING ONLY: one-time owner provisioning for the PDC Email AI successor.
-- The service role may call these owner functions only during commissioning;
-- it is never stored in or accepted by the successor runtime.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-email-ai-successor-owner-provisioning-20260831350000',0));
DO $guard$
BEGIN
  IF current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831340000' AND name='pdc_email_ai_successor_command_read_hardening')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260831350000')
  THEN RAISE EXCEPTION 'PDC_EMAIL_AI_SUCCESSOR_3500_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_successor_provisioning_receipts (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provisioning_id uuid NOT NULL,
  event_kind text NOT NULL CHECK(event_kind IN('PROVISIONED','ROLLED_BACK')),
  auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  identity_id uuid REFERENCES public.pdc_email_ai_successor_runtime_identities(identity_id) ON DELETE RESTRICT,
  normalized_email text NOT NULL CHECK(normalized_email=lower(btrim(normalized_email))),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-email-ai-successor-069'),
  mailbox_scope text NOT NULL CHECK(mailbox_scope='pdc-emails'),
  allowed_rpc_scope text[] NOT NULL CHECK(allowed_rpc_scope=ARRAY[
    'get_pdc_email_ai_transaction_successor_inbox_v2',
    'apply_pdc_email_ai_transaction_successor',
    'get_pdc_email_vehicle_location_snapshot',
    'get_pdc_email_ai_successor_health']::text[]),
  transport_release_version text NOT NULL CHECK(length(transport_release_version) BETWEEN 1 AND 160),
  model_version text NOT NULL CHECK(length(model_version) BETWEEN 1 AND 160),
  prompt_version text NOT NULL CHECK(length(prompt_version) BETWEEN 1 AND 160),
  taxonomy_version text NOT NULL CHECK(length(taxonomy_version) BETWEEN 1 AND 160),
  rule_version text NOT NULL CHECK(length(rule_version) BETWEEN 1 AND 160),
  action_contract_version text NOT NULL CHECK(action_contract_version='pdc-email-ai-actions-v1'),
  credential_digest text NOT NULL CHECK(credential_digest ~ '^[a-f0-9]{64}$'),
  approved_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  event_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(provisioning_id,event_kind),
  UNIQUE(auth_user_id,event_kind)
);
ALTER TABLE public.pdc_email_ai_successor_provisioning_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_provisioning_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_successor_provisioning_receipts FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_email_ai_successor_provisioning_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_EMAIL_AI_SUCCESSOR_PROVISIONING_RECEIPT_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_provisioning_immutable() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_successor_provisioning_receipt_immutable
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_successor_provisioning_receipts
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_successor_provisioning_immutable();

CREATE FUNCTION public.commission_pdc_email_ai_successor_runtime(
  p_auth_user_id uuid,
  p_normalized_email text,
  p_credential_digest text,
  p_gateway_instance_id text,
  p_mailbox_scope text,
  p_transport_release_version text,
  p_model_version text,
  p_prompt_version text,
  p_taxonomy_version text,
  p_rule_version text,
  p_action_contract_version text,
  p_approved_by uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $commission$
DECLARE
  v_existing public.pdc_email_ai_successor_provisioning_receipts%rowtype;
  v_user auth.users%rowtype;
  v_admin public.pdc_user_roles%rowtype;
  v_role_id uuid;
  v_identity_id uuid;
  v_provisioning_id uuid:=gen_random_uuid();
  v_rpc_scope text[]:=ARRAY['get_pdc_email_ai_transaction_successor_inbox_v2','apply_pdc_email_ai_transaction_successor','get_pdc_email_vehicle_location_snapshot','get_pdc_email_ai_successor_health']::text[];
BEGIN
  IF auth.role()<>'service_role'
     OR NOT public.pdc_monitor_staging_guard()
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831340000' AND name='pdc_email_ai_successor_command_read_hardening')<>1
     OR p_gateway_instance_id<>'pdc-email-ai-successor-069'
     OR p_mailbox_scope<>'pdc-emails'
     OR p_action_contract_version<>'pdc-email-ai-actions-v1'
     OR p_credential_digest !~ '^[a-f0-9]{64}$'
  THEN RETURN jsonb_build_object('ok',false,'code','successor_owner_provisioning_denied'); END IF;
  SELECT * INTO v_existing FROM public.pdc_email_ai_successor_provisioning_receipts
  WHERE event_kind='PROVISIONED' AND (auth_user_id=p_auth_user_id OR normalized_email=lower(btrim(p_normalized_email)))
  ORDER BY event_at DESC LIMIT 1;
  IF FOUND THEN
    IF v_existing.credential_digest<>lower(p_credential_digest)
       OR v_existing.gateway_instance_id<>p_gateway_instance_id
       OR v_existing.mailbox_scope<>p_mailbox_scope
    THEN RETURN jsonb_build_object('ok',false,'code','successor_provisioning_conflict'); END IF;
    RETURN jsonb_build_object('ok',true,'code','successor_already_provisioned','provisioning_id',v_existing.provisioning_id,'identity_id',v_existing.identity_id,'auth_user_id',v_existing.auth_user_id,'replay',true,'runtime_service_role',false);
  END IF;
  IF (SELECT count(*) FROM public.pdc_email_ai_successor_provisioning_receipts WHERE event_kind='PROVISIONED')>0 THEN
    RETURN jsonb_build_object('ok',false,'code','successor_provisioning_one_shot_consumed');
  END IF;
  SELECT * INTO v_user FROM auth.users WHERE id=p_auth_user_id AND lower(email)=lower(btrim(p_normalized_email));
  IF NOT FOUND OR v_user.email_confirmed_at IS NULL THEN RETURN jsonb_build_object('ok',false,'code','successor_auth_user_not_confirmed'); END IF;
  SELECT * INTO v_admin FROM public.pdc_user_roles WHERE auth_user_id=p_approved_by AND lower(email)=lower((SELECT email FROM auth.users WHERE id=p_approved_by)) AND role::text='administrator' AND active AND account_status::text='approved';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','successor_owner_approver_denied'); END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=p_auth_user_id AND role::text='administrator' AND active) THEN RETURN jsonb_build_object('ok',false,'code','successor_runtime_administrator_denied'); END IF;
  INSERT INTO public.pdc_user_roles(id,email,display_name,role,active,approved_by,approved_at,notes,created_at,updated_at,auth_user_id,account_status,full_name,registered_at)
  VALUES(gen_random_uuid(),lower(btrim(p_normalized_email)),'PDC Email AI Successor Runtime','importer',true,p_approved_by,clock_timestamp(),'Dedicated successor runtime; no human login or direct data authority',clock_timestamp(),clock_timestamp(),p_auth_user_id,'approved', 'PDC Email AI Successor Runtime',clock_timestamp())
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_role_id;
  IF v_role_id IS NULL THEN SELECT id INTO v_role_id FROM public.pdc_user_roles WHERE auth_user_id=p_auth_user_id; END IF;
  INSERT INTO public.pdc_email_ai_successor_runtime_identities(auth_user_id,normalized_email,environment,identity_purpose,gateway_instance_id,transport_release_version,model_version,prompt_version,taxonomy_version,rule_version,action_contract_version,active,approved_by)
  VALUES(p_auth_user_id,lower(btrim(p_normalized_email)),'staging','pdc_email_ai_transaction_successor',p_gateway_instance_id,p_transport_release_version,p_model_version,p_prompt_version,p_taxonomy_version,p_rule_version,p_action_contract_version,true,p_approved_by)
  RETURNING identity_id INTO v_identity_id;
  INSERT INTO public.pdc_email_ai_successor_provisioning_receipts(provisioning_id,event_kind,auth_user_id,identity_id,normalized_email,gateway_instance_id,mailbox_scope,allowed_rpc_scope,transport_release_version,model_version,prompt_version,taxonomy_version,rule_version,action_contract_version,credential_digest,approved_by)
  VALUES(v_provisioning_id,'PROVISIONED',p_auth_user_id,v_identity_id,lower(btrim(p_normalized_email)),p_gateway_instance_id,p_mailbox_scope,v_rpc_scope,p_transport_release_version,p_model_version,p_prompt_version,p_taxonomy_version,p_rule_version,p_action_contract_version,lower(p_credential_digest),p_approved_by);
  RETURN jsonb_build_object('ok',true,'code','successor_runtime_provisioned','provisioning_id',v_provisioning_id,'identity_id',v_identity_id,'auth_user_id',p_auth_user_id,'role_id',v_role_id,'gateway_instance_id',p_gateway_instance_id,'mailbox_scope',p_mailbox_scope,'allowed_rpc_scope',v_rpc_scope,'runtime_service_role',false);
END $commission$;
REVOKE ALL ON FUNCTION public.commission_pdc_email_ai_successor_runtime(uuid,text,text,text,text,text,text,text,text,text,text,uuid) FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.commission_pdc_email_ai_successor_runtime(uuid,text,text,text,text,text,text,text,text,text,text,uuid) TO service_role;

CREATE FUNCTION public.rollback_pdc_email_ai_successor_runtime(p_provisioning_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth
AS $rollback$
DECLARE v_receipt public.pdc_email_ai_successor_provisioning_receipts%rowtype; v_identity_id uuid;
BEGIN
  IF auth.role()<>'service_role' OR NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','successor_owner_rollback_denied'); END IF;
  SELECT * INTO v_receipt FROM public.pdc_email_ai_successor_provisioning_receipts WHERE provisioning_id=p_provisioning_id AND event_kind='PROVISIONED';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','successor_provisioning_not_found'); END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_provisioning_receipts WHERE provisioning_id=p_provisioning_id AND event_kind='ROLLED_BACK') THEN RETURN jsonb_build_object('ok',true,'code','successor_already_rolled_back','provisioning_id',p_provisioning_id,'replay',true); END IF;
  UPDATE public.pdc_email_ai_successor_runtime_identities SET active=false,revoked_at=clock_timestamp() WHERE identity_id=v_receipt.identity_id;
  UPDATE public.pdc_user_roles SET active=false,account_status='disabled',disabled_at=clock_timestamp(),disabled_reason='successor owner rollback' WHERE auth_user_id=v_receipt.auth_user_id AND role::text='importer';
  INSERT INTO public.pdc_email_ai_successor_provisioning_receipts(provisioning_id,event_kind,auth_user_id,identity_id,normalized_email,gateway_instance_id,mailbox_scope,allowed_rpc_scope,transport_release_version,model_version,prompt_version,taxonomy_version,rule_version,action_contract_version,credential_digest,approved_by)
  SELECT provisioning_id,'ROLLED_BACK',auth_user_id,identity_id,normalized_email,gateway_instance_id,mailbox_scope,allowed_rpc_scope,transport_release_version,model_version,prompt_version,taxonomy_version,rule_version,action_contract_version,credential_digest,approved_by FROM public.pdc_email_ai_successor_provisioning_receipts WHERE event_id=v_receipt.event_id;
  RETURN jsonb_build_object('ok',true,'code','successor_runtime_rolled_back','provisioning_id',p_provisioning_id,'runtime_service_role',false);
END $rollback$;
REVOKE ALL ON FUNCTION public.rollback_pdc_email_ai_successor_runtime(uuid) FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rollback_pdc_email_ai_successor_runtime(uuid) TO service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260831350000','pdc_email_ai_successor_owner_provisioning',ARRAY[
 'One-shot/idempotent owner-only provisioning receipt with immutable rollback event',
 'Dedicated confirmed Auth user and non-Administrator importer role are bound to exact gateway pdc-email-ai-successor-069 and mailbox pdc-emails scope',
 'Versioned transport/model/prompt/taxonomy/rules/action contract binding is recorded without credential material',
 'Provisioning and rollback functions are service_role-only; runtime query/plan/apply/readback privileges remain separate and service-role denied',
 'STAGING sentinel, migration-3400 predecessor and Production sentinel guards are enforced',
 'Rollback revokes successor identity and disables only the dedicated importer role; Auth deletion remains protected owner-controller work'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
