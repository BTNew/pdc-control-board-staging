-- STAGING ONLY: carry the exact canonical capability through its nested path.
-- The caller remains the existing pdc-emails staging Viewer. The transaction-local
-- marker prevents the capability from becoming direct access to nested RPCs.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260831430000-canonical-import-nested-context',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE d text;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831420000' AND name='pdc_email_canonical_import_capability')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260831420000
     OR to_regclass('public.pdc_monitor_canonical_import_capabilities_20260831') IS NULL
     OR to_regprocedure('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)') IS NULL
     OR to_regprocedure('public.pdc_canonical_import_capability_context_20260831()') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_monitor_canonical_import_capabilities_20260831 WHERE singleton AND auth_user_id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid AND normalized_email='pmbcontroller+pdc-viewer-staging-20260830@gmail.com' AND environment='staging' AND capability='canonical_attachment_import_only' AND active)<>1
  THEN RAISE EXCEPTION 'PDC_20260831430000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) INTO d;
  IF position('pdc_monitor_canonical_import_capabilities_20260831' IN d)=0
     OR position('pdc.canonical_import_capability_20260831' IN d)>0
     OR length(d)-length(replace(d,$old$
  if not found and not exists(
    select 1 from public.pdc_monitor_canonical_import_capabilities_20260831 c
    where c.singleton and c.auth_user_id=v_actor and c.active
      and c.environment='staging' and c.capability='canonical_attachment_import_only'
  ) then return public.navision_backend_response(false,'unauthorized'); end if;$old$,''))
        <> length($old$
  if not found and not exists(
    select 1 from public.pdc_monitor_canonical_import_capabilities_20260831 c
    where c.singleton and c.auth_user_id=v_actor and c.active
      and c.environment='staging' and c.capability='canonical_attachment_import_only'
  ) then return public.navision_backend_response(false,'unauthorized'); end if;$old$)
  THEN RAISE EXCEPTION 'PDC_20260831430000_CANONICAL_PRESTATE_DRIFT' USING errcode='55000'; END IF;
END
$guard$;

CREATE FUNCTION public.pdc_canonical_import_capability_context_20260831()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT current_setting('pdc.canonical_import_capability_20260831',true)='canonical_attachment_import_only'
     AND EXISTS(SELECT 1 FROM public.pdc_monitor_canonical_import_capabilities_20260831 c
                WHERE c.singleton AND c.auth_user_id=auth.uid() AND c.active
                  AND c.environment='staging' AND c.capability='canonical_attachment_import_only')
$$;
REVOKE ALL ON FUNCTION public.pdc_canonical_import_capability_context_20260831() FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $replace$
DECLARE d text; n text; f text;
BEGIN
  SELECT pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) INTO d;
  n:=replace(d,$old$
  if not found and not exists(
    select 1 from public.pdc_monitor_canonical_import_capabilities_20260831 c
    where c.singleton and c.auth_user_id=v_actor and c.active
      and c.environment='staging' and c.capability='canonical_attachment_import_only'
  ) then return public.navision_backend_response(false,'unauthorized'); end if;$old$,$new$
  if not found and not exists(
    select 1 from public.pdc_monitor_canonical_import_capabilities_20260831 c
    where c.singleton and c.auth_user_id=v_actor and c.active
      and c.environment='staging' and c.capability='canonical_attachment_import_only'
  ) then return public.navision_backend_response(false,'unauthorized'); end if;
  perform set_config('pdc.canonical_import_capability_20260831','canonical_attachment_import_only',true);$new$);
  IF n=d OR position('set_config(''pdc.canonical_import_capability_20260831''' IN n)=0
  THEN RAISE EXCEPTION 'PDC_20260831430000_CANONICAL_CONTEXT_REPLACEMENT_FAILED' USING errcode='55000'; END IF;
  EXECUTE n;

  FOREACH f IN ARRAY ARRAY[
    'public.pdc_submit_generic_current_navision_enrichment_312(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)',
    'public.pdc_auto_apply_generic_current_navision_enrichment_312(uuid,uuid,text,boolean)',
    'public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)',
    'public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'
  ] LOOP
    SELECT pg_get_functiondef(f::regprocedure) INTO d;
    n:=replace(d,$old_id$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old_id$,$new_id$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor_id and w.active and w.revoked_at is null for share;
  if not found and not public.pdc_canonical_import_capability_context_20260831() then return public.navision_backend_response(false,'unauthorized'); end if;$new_id$);
    n:=replace(n,$old_id_inline$ perform 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=v_actor_id and w.active and w.revoked_at is null for share;
 if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old_id_inline$,$new_id_inline$ perform 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=v_actor_id and w.active and w.revoked_at is null for share;
 if not found and not public.pdc_canonical_import_capability_context_20260831() then return public.navision_backend_response(false,'unauthorized'); end if;$new_id_inline$);
    n:=replace(n,$old_param$ perform 1 from public.pdc_monitor_stage_activation_writers w
    where w.user_id=p_actor_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old_param$,$new_param$ perform 1 from public.pdc_monitor_stage_activation_writers w
    where w.user_id=p_actor_id and w.active and w.revoked_at is null for share;
  if not found and not public.pdc_canonical_import_capability_context_20260831() then return public.navision_backend_response(false,'unauthorized'); end if;$new_param$);
    n:=replace(n,$old_actor$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old_actor$,$new_actor$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found and not public.pdc_canonical_import_capability_context_20260831() then return public.navision_backend_response(false,'unauthorized'); end if;$new_actor$);
    n:=replace(n,$old_actor_indent4$
  perform 1 from public.pdc_monitor_stage_activation_writers w
    where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old_actor_indent4$,$new_actor_indent4$
  perform 1 from public.pdc_monitor_stage_activation_writers w
    where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found and not public.pdc_canonical_import_capability_context_20260831() then return public.navision_backend_response(false,'unauthorized'); end if;$new_actor_indent4$);
    IF n=d OR position('pdc_canonical_import_capability_context_20260831' IN n)=0
    THEN RAISE EXCEPTION 'PDC_20260831430000_NESTED_CONTEXT_REPLACEMENT_FAILED_%',f USING errcode='55000'; END IF;
    EXECUTE n;
  END LOOP;
END
$replace$;

DO $post$
DECLARE d text; f text;
BEGIN
  SELECT pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) INTO d;
  IF position('set_config(''pdc.canonical_import_capability_20260831''' IN d)=0
     OR has_function_privilege('public','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','execute')
     OR has_function_privilege('anon','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','execute')
     OR has_function_privilege('service_role','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','execute')
     OR NOT has_function_privilege('authenticated','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','execute')
     OR has_function_privilege('public','public.pdc_canonical_import_capability_context_20260831()','execute')
     OR has_function_privilege('anon','public.pdc_canonical_import_capability_context_20260831()','execute')
     OR has_function_privilege('authenticated','public.pdc_canonical_import_capability_context_20260831()','execute')
     OR has_function_privilege('service_role','public.pdc_canonical_import_capability_context_20260831()','execute')
  THEN RAISE EXCEPTION 'PDC_20260831430000_AUTHORITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 FOREACH f IN ARRAY ARRAY[
   'public.pdc_submit_generic_current_navision_enrichment_312(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)',
   'public.pdc_auto_apply_generic_current_navision_enrichment_312(uuid,uuid,text,boolean)',
   'public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)',
    'public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'
  ] LOOP
    SELECT pg_get_functiondef(f::regprocedure) INTO d;
    IF position('pdc_canonical_import_capability_context_20260831' IN d)=0 THEN RAISE EXCEPTION 'PDC_20260831430000_NESTED_CONTEXT_POSTCONDITION_FAILED_%',f USING errcode='55000'; END IF;
  END LOOP;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831430000','pdc_email_canonical_import_nested_context',ARRAY[
  'Carry the exact canonical-import capability through a transaction-local context into the three nested importer calls',
  'Keep nested importer RPCs inaccessible to direct callers without the canonical path context',
  'Preserve the canonical importer Stock identity, recognised work, ambiguity, idempotency and no-booking/no-completion/no-location semantics',
  'Keep the capability table forced-RLS and direct DML denied to every API role',
  'Retain disable-only Administrator rollback and all Production/service-role exclusions'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
