BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_head_guard_repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'postgres_required'; END IF;
  SELECT version INTO v_head FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  IF v_head<>'20260907111000' THEN RAISE EXCEPTION 'unexpected_migration_head:%',v_head; END IF;
  IF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260907112000') THEN
    RAISE EXCEPTION 'migration_exists:20260907112000';
  END IF;
END $guard$;

DO $repair$
DECLARE
  v_name text;
  v_definition text;
  v_repaired text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'pdc_pilbara_service_classification_apply_v1',
    'pdc_pilbara_service_classification_rollback_v1'
  ] LOOP
    SELECT pg_get_functiondef(p.oid) INTO STRICT v_definition
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=v_name;

    v_repaired:=replace(
      v_definition,
      'IF v_head IS DISTINCT FROM ''["20260907110000","pilbara_service_operation_classifier_v1"]''::jsonb THEN',
      'IF v_head IS DISTINCT FROM ''["20260907112000","pilbara_service_operation_classifier_head_guard_repair"]''::jsonb THEN'
    );
    IF v_repaired=v_definition THEN
      RAISE EXCEPTION 'head_guard_not_found:%',v_name;
    END IF;
    EXECUTE v_repaired;
  END LOOP;
END $repair$;

REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_apply_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_rollback_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260907112000','pilbara_service_operation_classifier_head_guard_repair',
 ARRAY['allow the classifier private functions across the two classifier repair migration heads']
);
COMMIT;
