-- STAGING ONLY: make the in-transaction migration-head comparison null-safe.
-- Required predecessor: (20260907106000, pilbara_service_atomic_head_guard).
BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '300s';
SELECT pg_advisory_xact_lock(hashtext('pdc_pilbara_service_null_safe_head_guard'));

DO $migration$
DECLARE
  v_ref text;
  v_production boolean;
  v_head jsonb;
  v_definition text;
  v_updated text;
  v_old text := E'     <> ''["20260907106000","pilbara_service_atomic_head_guard"]''::jsonb THEN';
  v_new text := E'     IS DISTINCT FROM ''["20260907107000","pilbara_service_null_safe_head_guard"]''::jsonb THEN';
BEGIN
  SELECT project_ref INTO v_ref
  FROM public.pdc_staging_environment_sentinel
  WHERE singleton;
  v_production := to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL;
  SELECT jsonb_build_array(version,name) INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version ~ '^[0-9]{14}$'
  ORDER BY version::bigint DESC
  LIMIT 1;
  IF v_ref IS DISTINCT FROM 'cdsmnqxtyyoeoznmbidd'
     OR v_production
     OR v_head IS DISTINCT FROM '["20260907106000","pilbara_service_atomic_head_guard"]'::jsonb THEN
    RAISE EXCEPTION 'STAGING predecessor/sentinel failed';
  END IF;

  v_definition := pg_get_functiondef('public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure);
  IF position(v_old IN v_definition) = 0 THEN
    RAISE EXCEPTION 'null-safe apply head-guard insertion point missing';
  END IF;
  v_updated := replace(v_definition, v_old, v_new);
  IF v_updated = v_definition
     OR v_updated NOT ILIKE '%IS DISTINCT FROM%20260907107000%pilbara_service_null_safe_head_guard%'
     OR v_updated NOT ILIKE '%schema_head_changed%' THEN
    RAISE EXCEPTION 'null-safe apply head-guard replacement failed';
  END IF;
  EXECUTE v_updated;
END
$migration$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES ('20260907107000','pilbara_service_null_safe_head_guard',ARRAY['make apply migration-head comparison null-safe'])
ON CONFLICT (version) DO UPDATE
SET name=EXCLUDED.name, statements=EXCLUDED.statements;

COMMIT;
