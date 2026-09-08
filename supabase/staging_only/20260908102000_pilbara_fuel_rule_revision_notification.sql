-- Notify live snapshot clients after the fuel/charge classification reclassification.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pilbara_fuel_rule_revision_notification_20260908',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $notify$
DECLARE
  v_head jsonb;
  v_name text;
  v_definition text;
  v_repaired text;
  v_revision_rows integer;
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
     OR v_head IS DISTINCT FROM '["20260908101000","pilbara_classifier_head_guard_repair"]'::jsonb
  THEN
    RAISE EXCEPTION 'PDC_PILBARA_REVISION_NOTIFICATION_STAGING_GUARD_FAILED' USING ERRCODE='55000';
  END IF;

  UPDATE public.pdc_email_vehicle_revision
  SET revision=revision+1,updated_at=clock_timestamp()
  WHERE singleton;
  GET DIAGNOSTICS v_revision_rows=ROW_COUNT;
  IF v_revision_rows<>1 THEN
    RAISE EXCEPTION 'PDC_PILBARA_REVISION_NOTIFICATION_CONFLICT' USING ERRCODE='55000';
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
      'IF v_head IS DISTINCT FROM ''["20260908101000","pilbara_classifier_head_guard_repair"]''::jsonb THEN',
      'IF v_head IS DISTINCT FROM ''["20260908102000","pilbara_fuel_rule_revision_notification"]''::jsonb THEN'
    );
    IF v_repaired=v_definition THEN
      RAISE EXCEPTION 'PDC_PILBARA_REVISION_HEAD_GUARD_NOT_FOUND:%',v_name USING ERRCODE='55000';
    END IF;
    EXECUTE v_repaired;
  END LOOP;
END
$notify$;

REVOKE ALL ON FUNCTION
  public.pdc_pilbara_service_classification_apply_v1(uuid,text),
  public.pdc_pilbara_service_classification_rollback_v1(uuid,text)
FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260908102000','pilbara_fuel_rule_revision_notification',ARRAY[]::text[]);
COMMIT;
