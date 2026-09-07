-- STAGING-only append repair: constrain the Pilbara Service snapshot path to
-- active visible vehicles and advance the atomic importer head guard.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtext('pilbara_service_snapshot_scope_and_apply_head_repair'));

DO $repair$
DECLARE
  v_head jsonb;
  v_snapshot_definition text;
  v_snapshot_updated text;
  v_apply_definition text;
  v_apply_updated text;
  v_old_membership text := 'OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id)';
  v_new_membership text := 'OR (v.lifecycle_state=''active'' AND v.visible_on_board AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id))';
  v_old_head text := E'IS DISTINCT FROM ''["20260907107000","pilbara_service_null_safe_head_guard"]''::jsonb THEN';
  v_new_head text := E'IS DISTINCT FROM ''["20260907109000","pilbara_service_snapshot_scope_and_apply_head_repair"]''::jsonb THEN';
BEGIN
  SELECT jsonb_build_array(version,name) INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$'
  ORDER BY version::bigint DESC
  LIMIT 1;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_head IS DISTINCT FROM '["20260907108000","pilbara_service_snapshot_membership_repair"]'::jsonb
     OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot_pre168()') IS NULL
     OR to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'PDC_PILBARA_SNAPSHOT_SCOPE_STAGING_OR_HEAD_MISMATCH';
  END IF;

  v_snapshot_definition:=pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure);
  IF position(v_old_membership IN v_snapshot_definition)=0
     OR position(v_new_membership IN v_snapshot_definition)>0 THEN
    RAISE EXCEPTION 'PDC_PILBARA_SNAPSHOT_SCOPE_INSERTION_POINT_MISSING';
  END IF;
  v_snapshot_updated:=replace(v_snapshot_definition,v_old_membership,v_new_membership);
  IF v_snapshot_updated=v_snapshot_definition
     OR position(v_new_membership IN v_snapshot_updated)=0 THEN
    RAISE EXCEPTION 'PDC_PILBARA_SNAPSHOT_SCOPE_REPLACEMENT_FAILED';
  END IF;

  v_apply_definition:=pg_get_functiondef('public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure);
  IF position(v_old_head IN v_apply_definition)=0
     OR position(v_new_head IN v_apply_definition)>0
     OR position('schema_head_changed' IN v_apply_definition)=0 THEN
    RAISE EXCEPTION 'PDC_PILBARA_APPLY_HEAD_INSERTION_POINT_MISSING';
  END IF;
  v_apply_updated:=replace(v_apply_definition,v_old_head,v_new_head);
  IF v_apply_updated=v_apply_definition
     OR position(v_new_head IN v_apply_updated)=0
     OR position('schema_head_changed' IN v_apply_updated)=0 THEN
    RAISE EXCEPTION 'PDC_PILBARA_APPLY_HEAD_REPLACEMENT_FAILED';
  END IF;

  EXECUTE v_snapshot_updated;
  EXECUTE v_apply_updated;
END
$repair$;

REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre168()
FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text)
FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text)
TO authenticated;

UPDATE public.pdc_email_vehicle_revision
SET revision=revision+1,updated_at=clock_timestamp()
WHERE singleton;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES(
  '20260907109000',
  'pilbara_service_snapshot_scope_and_apply_head_repair',
  ARRAY[
    'Limit Pilbara Service snapshot membership to active visible vehicles while preserving existing receipt, Sublet, RFT and fixture paths.',
    'Advance the Pilbara Service apply function atomic migration-head guard to this successor.',
    'Preserve private helper ACLs and authenticated-only apply execution without changing imported source data.'
  ]
);

NOTIFY pgrst,'reload schema';
COMMIT;
