-- STAGING ONLY: complete the transaction-local canonical import context at the
-- final Board activation helper. No direct nested RPC authority is granted.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260831440000-canonical-import-activation-context',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE d text;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831430000' AND name='pdc_email_canonical_import_nested_context')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260831430000
     OR to_regprocedure('public.pdc_canonical_import_capability_context_20260831()') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260831440000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.pdc_auto_apply_generic_current_navision_enrichment_312(uuid,uuid,text,boolean)'::regprocedure) INTO d;
  IF position('pdc_canonical_import_capability_context_20260831' IN d)>0
     OR length(d)-length(replace(d,$old$
  perform 1 from public.pdc_monitor_stage_activation_writers w
    where w.user_id=p_actor_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old$,''))
        <> length($old$
  perform 1 from public.pdc_monitor_stage_activation_writers w
    where w.user_id=p_actor_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old$)
  THEN RAISE EXCEPTION 'PDC_20260831440000_ACTIVATION_HELPER_PRESTATE_DRIFT' USING errcode='55000'; END IF;
END
$guard$;

DO $replace$
DECLARE d text; n text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_auto_apply_generic_current_navision_enrichment_312(uuid,uuid,text,boolean)'::regprocedure) INTO d;
  n:=replace(d,$old$
  perform 1 from public.pdc_monitor_stage_activation_writers w
    where w.user_id=p_actor_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old$,$new$
  perform 1 from public.pdc_monitor_stage_activation_writers w
    where w.user_id=p_actor_id and w.active and w.revoked_at is null for share;
  if not found and not public.pdc_canonical_import_capability_context_20260831() then return public.navision_backend_response(false,'unauthorized'); end if;$new$);
  IF n=d OR position('pdc_canonical_import_capability_context_20260831' IN n)=0
  THEN RAISE EXCEPTION 'PDC_20260831440000_ACTIVATION_HELPER_REPLACEMENT_FAILED' USING errcode='55000'; END IF;
  EXECUTE n;
END
$replace$;

DO $post$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_auto_apply_generic_current_navision_enrichment_312(uuid,uuid,text,boolean)'::regprocedure) INTO d;
  IF position('pdc_canonical_import_capability_context_20260831' IN d)=0
     OR has_function_privilege('public','public.pdc_canonical_import_capability_context_20260831()','execute')
     OR has_function_privilege('anon','public.pdc_canonical_import_capability_context_20260831()','execute')
     OR has_function_privilege('authenticated','public.pdc_canonical_import_capability_context_20260831()','execute')
     OR has_function_privilege('service_role','public.pdc_canonical_import_capability_context_20260831()','execute')
  THEN RAISE EXCEPTION 'PDC_20260831440000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831440000','pdc_email_canonical_import_activation_context',ARRAY[
  'Carry the canonical-import context through the final generic Board activation helper',
  'Preserve existing writer authority while admitting the exact capability only from the canonical path',
  'Keep nested RPCs non-callable directly through a revoked helper function ACL',
  'Preserve Stock identity, recognised work, ambiguity, idempotent replay and no operational deletion semantics'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
