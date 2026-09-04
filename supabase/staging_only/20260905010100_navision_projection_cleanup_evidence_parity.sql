-- STAGING ONLY: permit durable cleanup evidence to record both passing and intentionally
-- fail-closed parity snapshots (for example, a delivered-at-dealer close guard).
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-navision-linked-location-cleanup-evidence-20260905',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v_head record;
BEGIN
  SELECT version,name INTO v_head FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_head.version IS DISTINCT FROM '20260905010000'
     OR v_head.name IS DISTINCT FROM 'navision_linked_location_projection'
     OR to_regclass('public.pdc_navision_projection_cleanup_history_20260905') IS NULL THEN
    RAISE EXCEPTION 'PDC_NAVISION_CLEANUP_EVIDENCE_PRECONDITION_FAILED:%/%',v_head.version,v_head.name USING errcode='55000';
  END IF;
END $guard$;
ALTER TABLE public.pdc_navision_projection_cleanup_history_20260905
  DROP CONSTRAINT pdc_navision_projection_cleanup_history_20260905_parity_check;
ALTER TABLE public.pdc_navision_projection_cleanup_history_20260905
  ADD CONSTRAINT pdc_navision_projection_cleanup_history_20260905_parity_object_check
  CHECK(jsonb_typeof(parity)='object');
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260905010100','navision_projection_cleanup_evidence_parity',ARRAY[
  'Cleanup history records the observed parity object rather than rejecting fail-closed lifecycle snapshots',
  'No reconciliation, vehicle, Navision, ACL, RLS, or production state is changed'
]);
COMMIT;
