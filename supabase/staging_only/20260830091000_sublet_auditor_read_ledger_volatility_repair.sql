-- STAGING ONLY 901: repair the exact Sublet ledger read RPC volatility.
-- The read bridge uses FOR SHARE to bind an active vehicle snapshot; PostgreSQL
-- requires such a function to be VOLATILE even though it performs no DML.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-sublet-auditor-read-901',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$')<>'20260830090000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260830090000'
           AND name='sublet_auditor_read_ledger')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version='20260830091000')
     OR to_regprocedure('public.get_pdc_sublet_audit_ledgers(uuid,text,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_901_EXACT_STAGING_DEPENDENCY_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

ALTER FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text) VOLATILE;
REVOKE ALL ON FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text)
  FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text)
  TO authenticated;
COMMENT ON FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text) IS
  'Staging-only exact UUID/Stock/Job Card, active canonical vehicle, dealer-scoped authenticated read of Sublet instances, immutable booking history and email receipts; VOLATILE only because the active vehicle binding uses FOR SHARE; direct table SELECT remains denied.';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260830091000','sublet_auditor_read_ledger_volatility_repair',ARRAY[
    'Exact staging successor after 20260830090000/sublet_auditor_read_ledger',
    'Change only the exact Sublet ledger read RPC volatility required by its FOR SHARE binding',
    'Direct SELECT on immutable Sublet ledgers remains denied',
    'Projection-only closure; no repair RPC and no stored work-item mutation'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
