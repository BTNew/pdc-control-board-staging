-- STAGING ONLY. Close the existing NULL-role fall-through in the shared base read.
-- The original allowed-role list, helper, row query and execution grants stay intact.
DO $guard$
DECLARE
  original_definition text;
  replacement_definition text;
  original_acl aclitem[];
  old_guard text := 'IF v_role NOT IN (''viewer'',''operator'',''importer'',''administrator'') THEN';
  new_guard text := 'IF v_role IS NULL OR v_role NOT IN (''viewer'',''operator'',''importer'',''administrator'') THEN';
BEGIN
  IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
      WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'Wrong environment: snapshot NULL-role repair is STAGING only';
  END IF;
  SELECT pg_get_functiondef(p.oid), p.proacl INTO STRICT original_definition, original_acl
    FROM pg_proc p WHERE p.oid = 'public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure;
  IF md5(original_definition) <> '30bb59d52ed30bd80350c72cf2730ba8' THEN
    RAISE EXCEPTION 'Snapshot base definition changed since independent review';
  END IF;
  IF (length(original_definition) - length(replace(original_definition, old_guard, ''))) / length(old_guard) <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one original snapshot role guard';
  END IF;
  replacement_definition := replace(original_definition, old_guard, new_guard);
  EXECUTE replacement_definition;
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = 'public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure
      AND (p.proacl IS DISTINCT FROM original_acl
        OR pg_get_functiondef(p.oid) IS DISTINCT FROM replacement_definition)
  ) THEN RAISE EXCEPTION 'Unexpected definition or execution grant change'; END IF;
END $guard$;
