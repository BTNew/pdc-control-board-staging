-- STAGING ONLY 20260901190000: carry the exact successor identity binding
-- through the retained Navision operational reconciliation helper.
-- The 1800 wrapper guard is preserved; this append-only correction closes the
-- unchanged downstream pre-709 helper that still had the legacy-only guard.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901190000-successor-pre709-identity-binding',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.reconcile_navision_operational_record_pre709(uuid,uuid,text)'::regprocedure) INTO definition;
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901180000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901190000')
     OR definition IS NULL
     OR position('IF NOT coalesce(public.pdc_monitor_authenticated_active_scope_674(NULL),false)' IN definition)=0
  THEN RAISE EXCEPTION 'PDC_20260901190000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

DO $rebind$
DECLARE definition text; old_clause text; new_clause text;
BEGIN
  SELECT pg_get_functiondef('public.reconcile_navision_operational_record_pre709(uuid,uuid,text)'::regprocedure) INTO definition;
  old_clause := $old$  IF NOT coalesce(public.pdc_monitor_authenticated_active_scope_674(NULL),false) THEN
    RETURN public.navision_backend_response(false,'monitor_identity_required');
  END IF;
$old$;
  new_clause := $new$  IF NOT (
    coalesce(public.pdc_monitor_authenticated_active_scope_674(NULL),false)
    OR (
      public.pdc_monitor_staging_guard()
      AND auth.role()='authenticated'
      AND v_uid IS NOT NULL
      AND v_email<>''
      AND EXISTS(
        SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i
        WHERE i.auth_user_id=v_uid AND i.normalized_email=v_email
          AND i.environment='staging'
          AND i.identity_purpose='pdc_email_ai_transaction_successor'
          AND i.active AND i.revoked_at IS NULL
      )
      AND EXISTS(
        SELECT 1 FROM public.pdc_user_roles r
        WHERE r.auth_user_id=v_uid AND lower(r.email)=v_email
          AND r.active AND r.account_status='approved' AND r.role::text='viewer'
      )
      AND EXISTS(
        SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
        WHERE w.user_id=v_uid AND w.active AND w.revoked_at IS NULL
      )
    )
  ) THEN
    RETURN public.navision_backend_response(false,'monitor_identity_required');
  END IF;
$new$;
  IF position(old_clause IN definition)=0 THEN RAISE EXCEPTION 'PDC_20260901190000_SOURCE_GUARD_FAILED' USING errcode='55000'; END IF;
  EXECUTE replace(definition,old_clause,new_clause);
END $rebind$;

DO $post$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.reconcile_navision_operational_record_pre709(uuid,uuid,text)'::regprocedure) INTO definition;
  IF position('pdc_email_ai_successor_runtime_identities' IN definition)=0
     OR position('pdc_monitor_stage_activation_writers' IN definition)=0
     OR position('pdc_monitor_authenticated_active_scope_674(NULL)' IN definition)=0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260901190000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260901190000','pdc_email_ai_successor_pre709_identity_binding_20260901',ARRAY[
  'Retained pre-709 Navision helper accepts the exact active successor runtime identity only when its approved Viewer role and stage-writer binding are present',
  'Legacy pdc-monitor authenticated active scope remains unchanged and still supports the existing sales monitor lane',
  'No generic DML, service-role runtime, mailbox/outbound path, Production object or RLS/FORCE RLS change is introduced'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
