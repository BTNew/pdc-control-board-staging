-- PDC-14 append-only role-history visibility policy. STAGING ONLY.
-- Approved STAGING project ref: cdsmnqxtyyoeoznmbidd.

DO $pdc14_guard$
DECLARE
  v_head record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-lane', 0));
  IF to_regclass('public.pdc_staging_environment_sentinel') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM public.pdc_staging_environment_sentinel
       WHERE singleton
         AND project_ref = 'cdsmnqxtyyoeoznmbidd'
     )
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_14_WRONG_ENVIRONMENT: staging sentinel missing';
  END IF;
  IF current_database() <> 'postgres' OR inet_server_addr() IS NULL THEN
    RAISE EXCEPTION 'PDC_14_WRONG_DATABASE';
  END IF;
  SELECT version, name INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version ~ '^[0-9]{14}$'
  ORDER BY version::bigint DESC
  LIMIT 1;
  IF v_head.version IS DISTINCT FROM '20260903160000'
     OR v_head.name IS DISTINCT FROM 'pdc14_canonical_controls' THEN
    RAISE EXCEPTION 'PDC_14_STALE_HEAD: expected 20260903160000/pdc14_canonical_controls, got %/%',
      coalesce(v_head.version, '<none>'), coalesce(v_head.name, '<none>');
  END IF;
END
$pdc14_guard$;

CREATE POLICY "PDC administrators can read role history"
ON public.pdc14_parts_coordinator_role_history
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.pdc_user_roles r
    WHERE r.auth_user_id = auth.uid()
      AND r.active
      AND lower(r.role::text) = 'administrator'
  )
);

GRANT SELECT ON public.pdc14_parts_coordinator_role_history TO authenticated;
REVOKE ALL ON public.pdc14_parts_coordinator_role_history FROM anon;

INSERT INTO supabase_migrations.schema_migrations(version, name, statements)
VALUES (
  '20260903170000',
  'pdc14_role_history_rls',
  ARRAY['pdc14_parts_coordinator_role_history has explicit Administrator-only SELECT policy; writes remain function-owner only']::text[]
);
