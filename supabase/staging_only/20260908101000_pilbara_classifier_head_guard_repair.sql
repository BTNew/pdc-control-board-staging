-- Keep Pilbara classifier apply/rollback guards aligned after the approved rule migration.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pilbara_classifier_head_guard_repair_20260908',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $repair$
DECLARE
  v_head jsonb;
  v_name text;
  v_definition text;
  v_repaired text;
BEGIN
  SELECT jsonb_build_array(version,name) INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$'
  ORDER BY version::bigint DESC LIMIT 1;

  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_head IS DISTINCT FROM '["20260908100000","pilbara_delivery_fuel_charge_fitting_rule"]'::jsonb
  THEN
    RAISE EXCEPTION 'PDC_PILBARA_HEAD_GUARD_REPAIR_STAGING_GUARD_FAILED' USING ERRCODE='55000';
  END IF;

  FOREACH v_name IN ARRAY ARRAY[
    'pdc_pilbara_service_classification_apply_v1',
    'pdc_pilbara_service_classification_rollback_v1'
  ]
  LOOP
    SELECT pg_get_functiondef(p.oid) INTO STRICT v_definition
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=v_name;

    v_repaired:=replace(
      v_definition,
      'IF v_head IS DISTINCT FROM ''["20260907114000","pilbara_service_operation_classifier_rollback_cleanup"]''::jsonb THEN',
      'IF v_head IS DISTINCT FROM ''["20260908101000","pilbara_classifier_head_guard_repair"]''::jsonb THEN'
    );
    IF v_repaired=v_definition THEN
      RAISE EXCEPTION 'PDC_PILBARA_HEAD_GUARD_NOT_FOUND:%',v_name USING ERRCODE='55000';
    END IF;
    EXECUTE v_repaired;
  END LOOP;
END
$repair$;

REVOKE ALL ON FUNCTION
  public.pdc_pilbara_service_classification_apply_v1(uuid,text),
  public.pdc_pilbara_service_classification_rollback_v1(uuid,text)
FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260908101000','pilbara_classifier_head_guard_repair',ARRAY[]::text[]);
COMMIT;
