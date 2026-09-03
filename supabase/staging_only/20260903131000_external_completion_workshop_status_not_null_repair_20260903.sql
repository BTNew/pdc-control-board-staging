-- STAGING ONLY: append-only compatibility repair for external completion.
-- The 130000 RPC assigned NULL to the current NOT NULL workshop_status
-- column. Replace that one exact statement with the existing terminal-safe
-- queued value; preserve every authority, identity and safety guard.
BEGIN;
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-external-completion-20260903131000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $repair$
DECLARE
  definition text;
  definition_hash text;
  old_fragment constant text:='workshop_status=NULL';
  new_fragment constant text:='workshop_status=''queued''';
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260903130000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903130000' AND name='external_non_navision_completion_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903131000')
     OR to_regprocedure('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)') IS NULL
     OR (SELECT attnotnull FROM pg_attribute WHERE attrelid='public.vehicles'::regclass AND attname='workshop_status') IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_131000_EXACT_STAGING_PRESTATE_REQUIRED' USING errcode='55000'; END IF;

  definition:=pg_get_functiondef('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)'::regprocedure);
  definition_hash:=encode(extensions.digest(convert_to(definition,'UTF8'),'sha256'),'hex');
  IF definition_hash<>'809731f11da081cd2f25a6ea18f6849d608f32c1b0bceceba1dea3673ef22ec4'
     OR (length(definition)-length(replace(definition,old_fragment,'')))/length(old_fragment)<>1
     OR position(new_fragment in definition)>0 THEN
    RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_131000_FUNCTION_HASH_OR_FRAGMENT_MISMATCH' USING errcode='55000';
  END IF;
  EXECUTE replace(definition,old_fragment,new_fragment);
END $repair$;

REVOKE ALL ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) TO authenticated;

DO $post$
DECLARE definition text;
BEGIN
  definition:=pg_get_functiondef('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)'::regprocedure);
  IF position('workshop_status=''queued''' in definition)=0
     OR position('workshop_status=NULL' in definition)>0
     OR position('external_non_navision_final_collection' in definition)=0
     OR position('physical_delivery_asserted' in definition)=0
     OR position('navision_backend_records' in definition)=0
     OR NOT has_function_privilege('authenticated','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
     OR has_function_privilege('anon','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
     OR has_function_privilege('service_role','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_131000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260903131000','external_completion_workshop_status_not_null_repair_20260903',ARRAY[
  'Append-only exact-hash repair after 20260903130000; the applied predecessor is not rewritten',
  'Replace the single incompatible workshop_status NULL assignment with the existing queued terminal-safe value required by the live NOT NULL schema',
  'All external/non-Navision identity, approval, version, idempotency, collection-evidence, no-delivery, RLS, ACL and outbound exclusions remain byte-for-byte unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
