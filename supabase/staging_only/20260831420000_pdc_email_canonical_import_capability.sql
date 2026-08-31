-- STAGING ONLY: grant the existing pdc-emails Viewer one exact canonical importer capability.
-- This does not grant writer access, direct table DML, service-role access, or any
-- other RPC. The existing canonical importer remains the authority for all input,
-- Stock identity, recognised work keys, ambiguity, idempotency and lifecycle rules.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260831420000-canonical-import-capability',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE d text;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT version FROM supabase_migrations.schema_migrations WHERE version='20260831410000') IS NULL
     OR (SELECT name FROM supabase_migrations.schema_migrations WHERE version='20260831410000')<>'862_allow_append_only_monitor_replay_subsets'
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260831410000
     OR to_regclass('public.pdc_monitor_canonical_import_capabilities_20260831') IS NOT NULL
     OR (SELECT count(*) FROM auth.users WHERE id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid AND lower(email)='pmbcontroller+pdc-viewer-staging-20260830@gmail.com')<>1
     OR (SELECT count(*) FROM public.pdc_user_roles WHERE auth_user_id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid AND lower(email)='pmbcontroller+pdc-viewer-staging-20260830@gmail.com' AND role::text='viewer' AND active AND account_status='approved')<>1
  THEN RAISE EXCEPTION 'PDC_20260831420000_STAGING_IDENTITY_OR_HEAD_GUARD_FAILED' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) INTO d;
  IF length(d)-length(replace(d,$old$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old$,''))
       <> length($old$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old$)
  THEN RAISE EXCEPTION 'PDC_20260831420000_CANONICAL_SOURCE_DRIFT' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_monitor_canonical_import_capabilities_20260831(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  auth_user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE RESTRICT,
  normalized_email text NOT NULL UNIQUE CHECK(normalized_email=lower(btrim(normalized_email))),
  environment text NOT NULL CHECK(environment='staging'),
  capability text NOT NULL CHECK(capability='canonical_attachment_import_only'),
  active boolean NOT NULL DEFAULT true,
  granted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  disabled_at timestamptz,
  disabled_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  disable_reason text,
  CHECK((active AND disabled_at IS NULL AND disabled_by IS NULL AND disable_reason IS NULL)
     OR (NOT active AND disabled_at IS NOT NULL AND disabled_by IS NOT NULL AND length(btrim(disable_reason)) BETWEEN 3 AND 500))
);
ALTER TABLE public.pdc_monitor_canonical_import_capabilities_20260831 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_monitor_canonical_import_capabilities_20260831 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_monitor_canonical_import_capabilities_20260831 FROM public,anon,authenticated,service_role,pdc_email_monitor;
INSERT INTO public.pdc_monitor_canonical_import_capabilities_20260831(auth_user_id,normalized_email,environment,capability)
VALUES('95131ea9-647f-4461-b5b9-573d22b8824c','pmbcontroller+pdc-viewer-staging-20260830@gmail.com','staging','canonical_attachment_import_only');

-- Preserve the current importer for its already-bound writer identity, while
-- allowing only this exact capability to pass the canonical importer gate.
DO $replace$
DECLARE d text; n text;
BEGIN
  SELECT pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) INTO d;
  n:=replace(d,$old$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old$,$new$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found and not exists(
    select 1 from public.pdc_monitor_canonical_import_capabilities_20260831 c
    where c.singleton and c.auth_user_id=v_actor and c.active
      and c.environment='staging' and c.capability='canonical_attachment_import_only'
  ) then return public.navision_backend_response(false,'unauthorized'); end if;$new$);
  IF n=d OR length(n)-length(replace(n,'pdc_monitor_canonical_import_capabilities_20260831',''))=0
  THEN RAISE EXCEPTION 'PDC_20260831420000_CANONICAL_REPLACEMENT_FAILED' USING errcode='55000'; END IF;
  EXECUTE n;
END
$replace$;

REVOKE ALL ON FUNCTION public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) TO authenticated;

-- Administrator-only, disable-only rollback. It never deletes capability or
-- importer evidence and cannot reactivate the capability.
CREATE FUNCTION public.disable_pdc_monitor_canonical_import_capability_20260831(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $rollback$
DECLARE r public.pdc_monitor_canonical_import_capabilities_20260831%rowtype; a uuid:=auth.uid();
BEGIN
  IF auth.role()<>'authenticated' OR a IS NULL
     OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles u WHERE u.auth_user_id=a AND u.active AND u.account_status='approved' AND u.role::text='administrator')
     OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 500
  THEN RAISE EXCEPTION 'PDC_20260831420000_ADMIN_ROLLBACK_REQUIRED' USING errcode='42501'; END IF;
  SELECT * INTO r FROM public.pdc_monitor_canonical_import_capabilities_20260831 WHERE singleton FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_20260831420000_CAPABILITY_MISSING' USING errcode='55000'; END IF;
  IF NOT r.active THEN RETURN jsonb_build_object('ok',true,'code','canonical_import_capability_rollback_replayed','active',false); END IF;
  UPDATE public.pdc_monitor_canonical_import_capabilities_20260831
  SET active=false,disabled_at=clock_timestamp(),disabled_by=a,disable_reason=btrim(p_reason)
  WHERE singleton;
  RETURN jsonb_build_object('ok',true,'code','canonical_import_capability_rollback_applied','active',false,'capability',r.capability,'auth_user_id',r.auth_user_id);
END
$rollback$;
REVOKE ALL ON FUNCTION public.disable_pdc_monitor_canonical_import_capability_20260831(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.disable_pdc_monitor_canonical_import_capability_20260831(text) TO authenticated;

DO $post$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) INTO d;
  IF position('pdc_monitor_canonical_import_capabilities_20260831' IN d)=0
     OR position('capability=''canonical_attachment_import_only''' IN d)=0

     OR has_function_privilege('public','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('service_role','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
     OR has_table_privilege('public','public.pdc_monitor_canonical_import_capabilities_20260831','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon','public.pdc_monitor_canonical_import_capabilities_20260831','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated','public.pdc_monitor_canonical_import_capabilities_20260831','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('service_role','public.pdc_monitor_canonical_import_capabilities_20260831','SELECT,INSERT,UPDATE,DELETE')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260831420000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831420000','pdc_email_canonical_import_capability',ARRAY[
  'Grant the existing pdc-emails staging Viewer one exact canonical attachment import capability without writer access',
  'Preserve the canonical importer input, Stock identity, recognised work, ambiguity, idempotency and lifecycle guards',

  'Keep direct capability-table DML denied to every API role and retain forced RLS',
  'Retain the already-bound Monitor writer identity through the existing writer gate',
  'Provide Administrator-only disable-only rollback with no evidence deletion, service-role runtime, RLS bypass or Production path'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
