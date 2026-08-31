-- STAGING ONLY: recoverable credential rotation for the dedicated successor owner commissioning.
-- This is for a failed one-time controller after Auth creation; it never enters runtime.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-email-ai-successor-owner-credential-rotation-20260831360000',0));
DO $guard$
BEGIN
 IF current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831350000' AND name='pdc_email_ai_successor_owner_provisioning')<>1
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260831360000')
 THEN RAISE EXCEPTION 'PDC_EMAIL_AI_SUCCESSOR_3600_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
ALTER TABLE public.pdc_email_ai_successor_provisioning_receipts DROP CONSTRAINT IF EXISTS pdc_email_ai_successor_provisioning_receipts_event_kind_check;
ALTER TABLE public.pdc_email_ai_successor_provisioning_receipts ADD CONSTRAINT pdc_email_ai_successor_provisioning_receipts_event_kind_check CHECK(event_kind IN('PROVISIONED','CREDENTIAL_ROTATED','ROLLED_BACK'));

CREATE FUNCTION public.rotate_pdc_email_ai_successor_runtime_credential(
 p_auth_user_id uuid,p_credential_digest text,p_approved_by uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $rotate$
DECLARE v_receipt public.pdc_email_ai_successor_provisioning_receipts%rowtype; v_admin public.pdc_user_roles%rowtype;
BEGIN
 IF auth.role()<>'service_role' OR NOT public.pdc_monitor_staging_guard() OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR p_credential_digest !~ '^[a-f0-9]{64}$' THEN RETURN jsonb_build_object('ok',false,'code','successor_credential_rotation_denied'); END IF;
 SELECT * INTO v_admin FROM public.pdc_user_roles WHERE auth_user_id=p_approved_by AND role::text='administrator' AND active AND account_status::text='approved';
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','successor_owner_approver_denied'); END IF;
 SELECT * INTO v_receipt FROM public.pdc_email_ai_successor_provisioning_receipts WHERE auth_user_id=p_auth_user_id AND event_kind='PROVISIONED' ORDER BY event_at DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','successor_provisioning_not_found'); END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_provisioning_receipts WHERE provisioning_id=v_receipt.provisioning_id AND event_kind='ROLLED_BACK') THEN RETURN jsonb_build_object('ok',false,'code','successor_provisioning_rolled_back'); END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_provisioning_receipts WHERE provisioning_id=v_receipt.provisioning_id AND event_kind='CREDENTIAL_ROTATED') THEN RETURN jsonb_build_object('ok',true,'code','successor_credential_already_rotated','provisioning_id',v_receipt.provisioning_id,'replay',true); END IF;
 INSERT INTO public.pdc_email_ai_successor_provisioning_receipts(provisioning_id,event_kind,auth_user_id,identity_id,normalized_email,gateway_instance_id,mailbox_scope,allowed_rpc_scope,transport_release_version,model_version,prompt_version,taxonomy_version,rule_version,action_contract_version,credential_digest,approved_by)
 SELECT provisioning_id,'CREDENTIAL_ROTATED',auth_user_id,identity_id,normalized_email,gateway_instance_id,mailbox_scope,allowed_rpc_scope,transport_release_version,model_version,prompt_version,taxonomy_version,rule_version,action_contract_version,p_credential_digest,p_approved_by FROM public.pdc_email_ai_successor_provisioning_receipts WHERE event_id=v_receipt.event_id;
 RETURN jsonb_build_object('ok',true,'code','successor_credential_rotated','provisioning_id',v_receipt.provisioning_id,'identity_id',v_receipt.identity_id,'runtime_service_role',false);
END $rotate$;
REVOKE ALL ON FUNCTION public.rotate_pdc_email_ai_successor_runtime_credential(uuid,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rotate_pdc_email_ai_successor_runtime_credential(uuid,text,uuid) TO service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260831360000','pdc_email_ai_successor_owner_credential_rotation',ARRAY[
 'Credential rotation is owner-only, staging/sentinel/3500 guarded and append-only',
 'Only the dedicated successor Auth actor can be rotated; runtime never receives owner/service credentials',
 'Rotation receipt stores digest only, no password or key material',
 'Approved successor query/plan/apply/readback scope remains unchanged and service-role runtime execution remains denied'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
