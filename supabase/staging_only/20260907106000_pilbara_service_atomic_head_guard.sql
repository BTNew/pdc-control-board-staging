-- STAGING ONLY: hold the migration ledger stable and recheck the exact schema head inside apply.
-- Required predecessor: (20260907105000, pilbara_service_activation_security_repair).
BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '300s';
SELECT pg_advisory_xact_lock(hashtext('pdc_pilbara_service_atomic_head_guard'));

DO $migration$
DECLARE
  v_ref text;
  v_production boolean;
  v_head jsonb;
  v_definition text;
  v_updated text;
  v_old text := E'BEGIN\n  IF current_setting(''app.environment'',true)=''production''';
  v_new text := E'BEGIN\n  LOCK TABLE supabase_migrations.schema_migrations IN SHARE MODE;\n  IF (SELECT jsonb_build_array(version,name)\n      FROM supabase_migrations.schema_migrations\n      WHERE version ~ ''^[0-9]{14}$''\n      ORDER BY version::bigint DESC LIMIT 1)\n     <> ''["20260907106000","pilbara_service_atomic_head_guard"]''::jsonb THEN\n    RETURN jsonb_build_object(''ok'',false,''code'',''schema_head_changed'');\n  END IF;\n\n  IF current_setting(''app.environment'',true)=''production''';
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
     OR v_head IS DISTINCT FROM '["20260907105000","pilbara_service_activation_security_repair"]'::jsonb THEN
    RAISE EXCEPTION 'STAGING predecessor/sentinel failed';
  END IF;

  v_definition := pg_get_functiondef('public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure);
  IF position(v_old IN v_definition) = 0 THEN
    RAISE EXCEPTION 'apply function insertion point missing';
  END IF;
  v_updated := replace(v_definition, v_old, v_new);
  IF v_updated = v_definition
     OR v_updated NOT ILIKE '%LOCK TABLE supabase_migrations.schema_migrations IN SHARE MODE%'
     OR v_updated NOT ILIKE '%schema_head_changed%'
     OR v_updated NOT ILIKE '%20260907106000%pilbara_service_atomic_head_guard%' THEN
    RAISE EXCEPTION 'atomic migration-head guard replacement failed';
  END IF;
  EXECUTE v_updated;
END
$migration$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES ('20260907106000','pilbara_service_atomic_head_guard',ARRAY['lock migration ledger and recheck exact head inside apply transaction'])
ON CONFLICT (version) DO UPDATE
SET name=EXCLUDED.name, statements=EXCLUDED.statements;

COMMIT;
