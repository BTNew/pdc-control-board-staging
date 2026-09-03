-- PDC-14: approve the dedicated Parts staff account with the minimum
-- operational role. STAGING ONLY; no Production target is permitted.

DO $pdc14_guard$
DECLARE
  v_head record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-lane', 0));

  IF to_regclass('public.pdc_staging_environment_sentinel') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.pdc_staging_environment_sentinel
       WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd'
     )
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_14_NON_STAGING_TARGET';
  END IF;

  SELECT version,name INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version ~ '^[0-9]{14}$'
  ORDER BY version::bigint DESC
  LIMIT 1;
  IF v_head.version IS DISTINCT FROM '20260903140000'
     OR v_head.name IS DISTINCT FROM 'navision_retention_canonical_observation_repair_20260903' THEN
    RAISE EXCEPTION 'PDC_14_PREDECESSOR_MISMATCH:%/%', v_head.version, v_head.name;
  END IF;
END
$pdc14_guard$;

CREATE TABLE public.pdc14_parts_coordinator_role_history (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_kind text NOT NULL CHECK (event_kind IN ('assignment','rollback')),
  target_user_id uuid NOT NULL,
  target_auth_user_id uuid NOT NULL,
  target_email text NOT NULL CHECK (target_email='functional@pdc.online'),
  before_role text,
  before_active boolean NOT NULL,
  before_account_status text NOT NULL,
  before_display_name text,
  before_approved_at timestamptz,
  before_rejected_at timestamptz,
  before_rejection_reason text,
  before_disabled_at timestamptz,
  before_disabled_reason text,
  before_restored_at timestamptz,
  after_role text,
  after_active boolean NOT NULL,
  after_account_status text NOT NULL,
  after_display_name text,
  after_approved_at timestamptz,
  reason text NOT NULL CHECK (length(btrim(reason)) >= 12),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc14_parts_coordinator_role_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc14_parts_coordinator_role_history FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc14_parts_coordinator_role_history FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc14_parts_coordinator_history_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  RAISE EXCEPTION 'PDC_14_HISTORY_APPEND_ONLY' USING ERRCODE='55000';
END
$$;
REVOKE ALL ON FUNCTION public.pdc14_parts_coordinator_history_append_only() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc14_parts_coordinator_history_append_only
BEFORE UPDATE OR DELETE ON public.pdc14_parts_coordinator_role_history
FOR EACH ROW EXECUTE FUNCTION public.pdc14_parts_coordinator_history_append_only();

CREATE FUNCTION public.apply_pdc14_parts_coordinator_role()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $pdc14_assign$
DECLARE
  v_before public.pdc_user_roles%ROWTYPE;
  v_after public.pdc_user_roles%ROWTYPE;
BEGIN
  SELECT * INTO v_before
  FROM public.pdc_user_roles
  WHERE lower(email)='functional@pdc.online' AND auth_user_id IS NOT NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','pdc14_target_identity_missing');
  END IF;
  IF v_before.role='operator'
     AND v_before.active
     AND v_before.account_status='approved'
     AND v_before.display_name='Parts Coordinator' THEN
    RETURN jsonb_build_object('ok',true,'code','pdc14_parts_coordinator_already_assigned','target_email',lower(v_before.email));
  END IF;

  UPDATE public.pdc_user_roles
  SET display_name='Parts Coordinator',
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
     OR v_after.active IS DISTINCT FROM true
     OR v_after.account_status IS DISTINCT FROM 'approved'
     OR v_after.display_name IS DISTINCT FROM 'Parts Coordinator' THEN
    RAISE EXCEPTION 'PDC_14_ROLE_ASSIGNMENT_POSTCONDITION_FAILED';
  END IF;

  INSERT INTO public.pdc14_parts_coordinator_role_history(
    event_kind,target_user_id,target_auth_user_id,target_email,
    before_role,before_active,before_account_status,before_display_name,before_approved_at,
    before_rejected_at,before_rejection_reason,before_disabled_at,before_disabled_reason,before_restored_at,
    after_role,after_active,after_account_status,after_display_name,after_approved_at,reason
  ) VALUES (
    'assignment',v_after.id,v_after.auth_user_id,lower(v_after.email),
    v_before.role::text,v_before.active,v_before.account_status::text,v_before.display_name,v_before.approved_at,
    v_before.rejected_at,v_before.rejection_reason,v_before.disabled_at,v_before.disabled_reason,v_before.restored_at,
    v_after.role::text,v_after.active,v_after.account_status::text,v_after.display_name,v_after.approved_at,
    'PDC-14 approved dedicated PDC Parts staff account with minimum Operator authority'
  );
  RETURN jsonb_build_object('ok',true,'code','pdc14_parts_coordinator_assigned','target_email',lower(v_after.email));
END
$pdc14_assign$;
REVOKE ALL ON FUNCTION public.apply_pdc14_parts_coordinator_role() FROM public,anon,authenticated,service_role;

-- The requested address may not exist at migration time. Keep the migration
-- deployable and the assignment owner-replayable without ever fabricating an
-- auth identity.
DO $pdc14_apply_if_present$
BEGIN
  PERFORM public.apply_pdc14_parts_coordinator_role();
END
$pdc14_apply_if_present$;

-- Reversible owner-only rollback path. No browser, authenticated, anon or
-- service_role EXECUTE grant is provided. The previous typed values are taken
-- from the immutable assignment receipt and every rollback appends a receipt.
CREATE FUNCTION public.rollback_pdc14_parts_coordinator_role(p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_receipt public.pdc14_parts_coordinator_role_history%ROWTYPE;
  v_before public.pdc_user_roles%ROWTYPE;
  v_after public.pdc_user_roles%ROWTYPE;
BEGIN
  IF length(btrim(coalesce(p_reason,''))) < 12 THEN
    RAISE EXCEPTION 'PDC_14_ROLLBACK_REASON_REQUIRED';
  END IF;
  SELECT * INTO STRICT v_receipt
  FROM public.pdc14_parts_coordinator_role_history
  WHERE event_kind='assignment' AND target_email='functional@pdc.online'
  ORDER BY recorded_at ASC
  LIMIT 1;
  SELECT * INTO STRICT v_before
  FROM public.pdc_user_roles
  WHERE id=v_receipt.target_user_id AND auth_user_id=v_receipt.target_auth_user_id
    AND lower(email)=v_receipt.target_email
  FOR UPDATE;
  IF v_before.role::text IS DISTINCT FROM v_receipt.after_role
     OR v_before.active IS DISTINCT FROM v_receipt.after_active
     OR v_before.account_status::text IS DISTINCT FROM v_receipt.after_account_status
     OR v_before.display_name IS DISTINCT FROM v_receipt.after_display_name THEN
    RAISE EXCEPTION 'PDC_14_ROLLBACK_CURRENT_STATE_MISMATCH';
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
    after_role,after_active,after_account_status,after_display_name,after_approved_at,reason
  ) VALUES (
    'rollback',v_after.id,v_after.auth_user_id,lower(v_after.email),
    v_before.role::text,v_before.active,v_before.account_status::text,v_before.display_name,v_before.approved_at,
    v_after.role::text,v_after.active,v_after.account_status::text,v_after.display_name,v_after.approved_at,
    btrim(p_reason)
  );
  RETURN jsonb_build_object('ok',true,'code','pdc14_role_rolled_back','target_email',lower(v_after.email));
END
$$;
REVOKE ALL ON FUNCTION public.rollback_pdc14_parts_coordinator_role(text) FROM public,anon,authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES(
  '20260903150000',
  'pdc14_parts_coordinator_role',
  ARRAY['PDC-14 dedicated Parts staff role assignment with immutable receipt and owner-only rollback']
);
