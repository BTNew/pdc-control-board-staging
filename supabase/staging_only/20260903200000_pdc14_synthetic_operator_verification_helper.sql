-- PDC-14 bounded synthetic Operator verification support. STAGING ONLY.
-- Approved project: cdsmnqxtyyoeoznmbidd. This helper can target only the
-- IANA-reserved test identity functional.pdc.staging@example.com.

DO $guard$
DECLARE v_head record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-lane',0));
  IF to_regclass('public.pdc_staging_environment_sentinel') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.pdc_staging_environment_sentinel
       WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd'
     )
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_14_SYNTHETIC_WRONG_ENVIRONMENT';
  END IF;
  SELECT version,name INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$'
  ORDER BY version::bigint DESC
  LIMIT 1;
  IF v_head.version IS DISTINCT FROM '20260903190000'
     OR v_head.name IS DISTINCT FROM 'pdc14_role_replay_rollback_hardening' THEN
    RAISE EXCEPTION 'PDC_14_SYNTHETIC_STALE_HEAD: expected 20260903190000/pdc14_role_replay_rollback_hardening, got %/%',v_head.version,v_head.name;
  END IF;
END
$guard$;

ALTER TABLE public.pdc14_parts_coordinator_role_history
  DROP CONSTRAINT pdc14_parts_coordinator_role_history_target_email_check;
ALTER TABLE public.pdc14_parts_coordinator_role_history
  ADD CONSTRAINT pdc14_parts_coordinator_role_history_target_email_check
  CHECK (target_email IN ('functional@pdc.online','functional.pdc.staging@example.com'));
ALTER TABLE public.pdc14_parts_coordinator_role_history
  ADD COLUMN after_rejected_at timestamptz,
  ADD COLUMN after_rejection_reason text,
  ADD COLUMN after_disabled_at timestamptz,
  ADD COLUMN after_disabled_reason text,
  ADD COLUMN after_restored_at timestamptz,
  ADD COLUMN reverted_assignment_event_id uuid
    REFERENCES public.pdc14_parts_coordinator_role_history(event_id);

CREATE FUNCTION public.apply_pdc14_staging_test_operator_role()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $assign$
DECLARE
  v_before public.pdc_user_roles%ROWTYPE;
  v_after public.pdc_user_roles%ROWTYPE;
  v_event_id uuid;
  v_target_count integer;
BEGIN
  IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_14_SYNTHETIC_WRONG_ENVIRONMENT';
  END IF;
  SELECT count(*) INTO v_target_count
  FROM public.pdc_user_roles role_row
  JOIN auth.users auth_user ON auth_user.id=role_row.auth_user_id
  WHERE lower(role_row.email)='functional.pdc.staging@example.com'
    AND lower(auth_user.email)='functional.pdc.staging@example.com';
  IF v_target_count=0 THEN
    RETURN jsonb_build_object('ok',false,'code','pdc14_staging_test_identity_missing');
  ELSIF v_target_count<>1 THEN
    RAISE EXCEPTION 'PDC_14_SYNTHETIC_IDENTITY_AMBIGUOUS';
  END IF;
  SELECT role_row.* INTO STRICT v_before
  FROM public.pdc_user_roles role_row
  JOIN auth.users auth_user ON auth_user.id=role_row.auth_user_id
  WHERE lower(role_row.email)='functional.pdc.staging@example.com'
    AND lower(auth_user.email)='functional.pdc.staging@example.com'
  FOR UPDATE OF role_row;
  IF v_before.role='operator' AND v_before.active
     AND v_before.account_status='approved'
     AND v_before.display_name='PDC-14 STAGING Test Operator'
     AND v_before.approved_at IS NOT NULL
     AND v_before.rejected_at IS NULL AND v_before.rejection_reason IS NULL
     AND v_before.disabled_at IS NULL AND v_before.disabled_reason IS NULL THEN
    RETURN jsonb_build_object(
      'ok',true,
      'code','pdc14_staging_test_operator_already_assigned',
      'target_email',lower(v_before.email)
    );
  END IF;

  UPDATE public.pdc_user_roles
  SET display_name='PDC-14 STAGING Test Operator',
      role='operator',
      active=true,
      account_status='approved',
      approved_at=coalesce(approved_at,clock_timestamp()),
      rejected_at=NULL,
      rejection_reason=NULL,
      disabled_at=NULL,
      disabled_reason=NULL,
      restored_at=CASE WHEN v_before.account_status='disabled' THEN clock_timestamp() ELSE restored_at END
  WHERE id=v_before.id
  RETURNING * INTO STRICT v_after;

  IF v_after.role IS DISTINCT FROM 'operator'
     OR NOT v_after.active
     OR v_after.account_status IS DISTINCT FROM 'approved'
     OR v_after.display_name IS DISTINCT FROM 'PDC-14 STAGING Test Operator' THEN
    RAISE EXCEPTION 'PDC_14_SYNTHETIC_ROLE_ASSIGNMENT_POSTCONDITION_FAILED';
  END IF;

  INSERT INTO public.pdc14_parts_coordinator_role_history(
    event_kind,target_user_id,target_auth_user_id,target_email,
    before_role,before_active,before_account_status,before_display_name,before_approved_at,
    before_rejected_at,before_rejection_reason,before_disabled_at,before_disabled_reason,before_restored_at,
    after_role,after_active,after_account_status,after_display_name,after_approved_at,
    after_rejected_at,after_rejection_reason,after_disabled_at,after_disabled_reason,after_restored_at,reason
  ) VALUES(
    'assignment',v_after.id,v_after.auth_user_id,lower(v_after.email),
    v_before.role::text,v_before.active,v_before.account_status::text,v_before.display_name,v_before.approved_at,
    v_before.rejected_at,v_before.rejection_reason,v_before.disabled_at,v_before.disabled_reason,v_before.restored_at,
    v_after.role::text,v_after.active,v_after.account_status::text,v_after.display_name,v_after.approved_at,
    v_after.rejected_at,v_after.rejection_reason,v_after.disabled_at,v_after.disabled_reason,v_after.restored_at,
    'PDC-14 bounded synthetic STAGING verification with minimum Operator authority'
  )
  RETURNING event_id INTO v_event_id;

  RETURN jsonb_build_object(
    'ok',true,
    'code','pdc14_staging_test_operator_assigned',
    'target_email',lower(v_after.email),
    'assignment_event_id',v_event_id
  );
END
$assign$;
REVOKE ALL ON FUNCTION public.apply_pdc14_staging_test_operator_role() FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.rollback_pdc14_staging_test_operator_role(text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $rollback$
DECLARE
  p_reason alias for $1;
  v_receipt public.pdc14_parts_coordinator_role_history%ROWTYPE;
  v_before public.pdc_user_roles%ROWTYPE;
  v_after public.pdc_user_roles%ROWTYPE;
  v_target_count integer;
BEGIN
  IF length(btrim(coalesce(p_reason,'')))<12 THEN
    RAISE EXCEPTION 'PDC_14_SYNTHETIC_ROLLBACK_REASON_REQUIRED';
  END IF;
  IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_14_SYNTHETIC_WRONG_ENVIRONMENT';
  END IF;
  SELECT count(*) INTO v_target_count
  FROM public.pdc_user_roles role_row
  JOIN auth.users auth_user ON auth_user.id=role_row.auth_user_id
  WHERE lower(role_row.email)='functional.pdc.staging@example.com'
    AND lower(auth_user.email)='functional.pdc.staging@example.com';
  IF v_target_count=0 THEN
    RETURN jsonb_build_object('ok',false,'code','pdc14_staging_test_identity_missing');
  ELSIF v_target_count<>1 THEN
    RAISE EXCEPTION 'PDC_14_SYNTHETIC_IDENTITY_AMBIGUOUS';
  END IF;
  SELECT role_row.* INTO STRICT v_before
  FROM public.pdc_user_roles role_row
  JOIN auth.users auth_user ON auth_user.id=role_row.auth_user_id
  WHERE lower(role_row.email)='functional.pdc.staging@example.com'
    AND lower(auth_user.email)='functional.pdc.staging@example.com'
  FOR UPDATE OF role_row;

  SELECT assignment.* INTO v_receipt
  FROM public.pdc14_parts_coordinator_role_history assignment
  WHERE assignment.event_kind='assignment'
    AND assignment.target_email='functional.pdc.staging@example.com'
    AND assignment.target_user_id=v_before.id
    AND assignment.target_auth_user_id=v_before.auth_user_id
    AND NOT EXISTS (
      SELECT 1
      FROM public.pdc14_parts_coordinator_role_history rollback
      WHERE rollback.event_kind='rollback'
        AND rollback.reverted_assignment_event_id=assignment.event_id
    )
  ORDER BY assignment.recorded_at DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok',true,
      'code','pdc14_staging_test_operator_already_rolled_back',
      'target_email',lower(v_before.email)
    );
  END IF;

  IF v_before.role::text IS DISTINCT FROM v_receipt.after_role
     OR v_before.active IS DISTINCT FROM v_receipt.after_active
     OR v_before.account_status::text IS DISTINCT FROM v_receipt.after_account_status
     OR v_before.display_name IS DISTINCT FROM v_receipt.after_display_name
     OR v_before.approved_at IS DISTINCT FROM v_receipt.after_approved_at
     OR v_before.rejected_at IS DISTINCT FROM v_receipt.after_rejected_at
     OR v_before.rejection_reason IS DISTINCT FROM v_receipt.after_rejection_reason
     OR v_before.disabled_at IS DISTINCT FROM v_receipt.after_disabled_at
     OR v_before.disabled_reason IS DISTINCT FROM v_receipt.after_disabled_reason
     OR v_before.restored_at IS DISTINCT FROM v_receipt.after_restored_at THEN
    RAISE EXCEPTION 'PDC_14_SYNTHETIC_ROLLBACK_CURRENT_STATE_MISMATCH';
  END IF;

  UPDATE public.pdc_user_roles
  SET role=v_receipt.before_role::public.pdc_role,
      active=v_receipt.before_active,
      account_status=v_receipt.before_account_status::public.pdc_account_status,
      display_name=v_receipt.before_display_name,
      approved_at=v_receipt.before_approved_at,
      rejected_at=v_receipt.before_rejected_at,
      rejection_reason=v_receipt.before_rejection_reason,
      disabled_at=v_receipt.before_disabled_at,
      disabled_reason=v_receipt.before_disabled_reason,
      restored_at=v_receipt.before_restored_at
  WHERE id=v_receipt.target_user_id
  RETURNING * INTO STRICT v_after;

  INSERT INTO public.pdc14_parts_coordinator_role_history(
    event_kind,target_user_id,target_auth_user_id,target_email,
    before_role,before_active,before_account_status,before_display_name,before_approved_at,
    before_rejected_at,before_rejection_reason,before_disabled_at,before_disabled_reason,before_restored_at,
    after_role,after_active,after_account_status,after_display_name,after_approved_at,
    after_rejected_at,after_rejection_reason,after_disabled_at,after_disabled_reason,after_restored_at,
    reason,reverted_assignment_event_id
  ) VALUES(
    'rollback',v_after.id,v_after.auth_user_id,lower(v_after.email),
    v_before.role::text,v_before.active,v_before.account_status::text,v_before.display_name,v_before.approved_at,
    v_before.rejected_at,v_before.rejection_reason,v_before.disabled_at,v_before.disabled_reason,v_before.restored_at,
    v_after.role::text,v_after.active,v_after.account_status::text,v_after.display_name,v_after.approved_at,
    v_after.rejected_at,v_after.rejection_reason,v_after.disabled_at,v_after.disabled_reason,v_after.restored_at,
    btrim(p_reason),v_receipt.event_id
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code','pdc14_staging_test_operator_rolled_back',
    'target_email',lower(v_after.email),
    'assignment_event_id',v_receipt.event_id
  );
END
$rollback$;
REVOKE ALL ON FUNCTION public.rollback_pdc14_staging_test_operator_role(text) FROM public,anon,authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES(
  '20260903200000',
  'pdc14_synthetic_operator_verification_helper',
  ARRAY['Bounded owner-only synthetic Operator assignment and receipt-bound rollback for PDC-14 STAGING verification']::text[]
);
