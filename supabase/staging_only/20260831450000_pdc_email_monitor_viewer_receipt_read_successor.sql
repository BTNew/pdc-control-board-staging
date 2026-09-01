-- STAGING ONLY 20260831450000: restore the exact enrolled Viewer receipt
-- read boundary and preserve attachment-scoped immutable child receipts.
-- No writer role, table DML, service_role authority, mailbox action or Production
-- path is introduced.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260831450000-viewer-receipt-read',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE d text;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260831440000' AND name='pdc_email_canonical_import_activation_context')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]+$')<>20260831440000
     OR (SELECT count(*) FROM auth.users
         WHERE id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid
           AND lower(email)='pmbcontroller+pdc-viewer-staging-20260830@gmail.com')<>1
     OR (SELECT count(*) FROM public.pdc_user_roles
         WHERE auth_user_id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid
           AND lower(email)='pmbcontroller+pdc-viewer-staging-20260830@gmail.com'
           AND role::text='viewer' AND active AND account_status='approved')<>1
     OR (SELECT count(*) FROM public.pdc_monitor_canonical_import_capabilities_20260831
         WHERE singleton AND auth_user_id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid
           AND normalized_email='pmbcontroller+pdc-viewer-staging-20260830@gmail.com'
           AND environment='staging' AND capability='canonical_attachment_import_only'
           AND active)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers
         WHERE user_id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid
           AND active AND revoked_at IS NULL)<>0
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
         FROM pg_proc p
         WHERE p.oid='public.read_pdc_jobcard_attachment_import_receipt(uuid)'::regprocedure)
         <>'8c2f4bd3ad99c5a418cac38faf898973764a929c5e9b5cf2f1906547f069a19c'
     OR to_regclass('public.pdc_jobcard_attachment_import_receipts') IS NULL
     OR to_regclass('public.pdc_jobcard_attachment_source_row_receipts') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_constraint
       WHERE conrelid='public.pdc_jobcard_attachment_import_receipts'::regclass
         AND contype='u'
         AND position('UNIQUE (ACTOR_ID, INTAKE_ID, ATTACHMENT_ID)' IN upper(pg_get_constraintdef(oid)))>0
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_constraint
       WHERE conrelid='public.pdc_jobcard_attachment_import_receipts'::regclass
         AND contype='u'
         AND position('UNIQUE (CANONICAL_SOURCE_HASH)' IN upper(pg_get_constraintdef(oid)))>0
     )
     OR EXISTS (
       SELECT 1 FROM pg_constraint
       WHERE conrelid='public.pdc_jobcard_attachment_import_receipts'::regclass
         AND position('UNIQUE (PARENT_SOURCE_HASH)' IN upper(pg_get_constraintdef(oid)))>0
     )
  THEN RAISE EXCEPTION 'PDC_20260831450000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END
$guard$;

-- The existing reader already derives all receipt data and validates the
-- authoritative Board/vehicle/work lineage. Its only missing path is the exact
-- capability-bearing Viewer, who must not be added to the writer table.
DO $replace$
DECLARE d text; n text;
BEGIN
  SELECT pg_get_functiondef('public.read_pdc_jobcard_attachment_import_receipt(uuid)'::regprocedure) INTO d;
  n:=replace(d,$old$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old$,$new$
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null;
  if not found and not exists(
    select 1 from public.pdc_monitor_canonical_import_capabilities_20260831 c
    where c.singleton and c.auth_user_id=v_actor and c.active
      and c.environment='staging' and c.capability='canonical_attachment_import_only'
  ) then return public.navision_backend_response(false,'unauthorized'); end if;$new$);
  IF n=d OR position('pdc_monitor_canonical_import_capabilities_20260831' IN n)=0
  THEN RAISE EXCEPTION 'PDC_20260831450000_READER_REPLACEMENT_FAILED' USING errcode='55000'; END IF;
  EXECUTE n;
END
$replace$;

REVOKE ALL ON FUNCTION public.read_pdc_jobcard_attachment_import_receipt(uuid)
  FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.read_pdc_jobcard_attachment_import_receipt(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.read_pdc_jobcard_attachment_import_receipt(uuid) IS
  'Staging-only actor-owned immutable child receipt reader; approved Viewer capability or existing writer binding; re-derives canonical line, identity, Board and lifecycle evidence.';

DO $post$
BEGIN
  IF (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
      FROM pg_proc p
      WHERE p.oid='public.read_pdc_jobcard_attachment_import_receipt(uuid)'::regprocedure)
      <>'a8ab506f7db7e6cefdd6da25fa1476c9f0a2435b9efba43e34f9e2510b313094'
     OR NOT has_function_privilege('authenticated','public.read_pdc_jobcard_attachment_import_receipt(uuid)','execute')
     OR has_function_privilege('public','public.read_pdc_jobcard_attachment_import_receipt(uuid)','execute')
     OR has_function_privilege('anon','public.read_pdc_jobcard_attachment_import_receipt(uuid)','execute')
     OR has_function_privilege('service_role','public.read_pdc_jobcard_attachment_import_receipt(uuid)','execute')
     OR has_table_privilege('public','public.pdc_jobcard_attachment_import_receipts','select')
     OR has_table_privilege('anon','public.pdc_jobcard_attachment_import_receipts','select')
     OR has_table_privilege('authenticated','public.pdc_jobcard_attachment_import_receipts','select')
     OR has_table_privilege('service_role','public.pdc_jobcard_attachment_import_receipts','select')
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgrelid='public.pdc_jobcard_attachment_import_receipts'::regclass
         AND tgname='pdc_jobcard_attachment_import_receipts_immutable'
         AND NOT tgisinternal AND tgenabled<>'D')
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgrelid='public.pdc_jobcard_attachment_source_row_receipts'::regclass
         AND tgname='pdc_jobcard_attachment_source_row_receipts_immutable'
         AND NOT tgisinternal AND tgenabled<>'D')
     OR (SELECT relrowsecurity FROM pg_class WHERE oid='public.pdc_monitor_canonical_import_capabilities_20260831'::regclass) IS DISTINCT FROM true
     OR (SELECT relforcerowsecurity FROM pg_class WHERE oid='public.pdc_monitor_canonical_import_capabilities_20260831'::regclass) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'PDC_20260831450000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260831450000','pdc_email_monitor_viewer_receipt_read_successor',ARRAY[
  'Restore authenticated EXECUTE on the actor-owned canonical receipt reader for the exact enrolled staging Viewer capability',
  'Admit the capability without adding a pdc_monitor_stage_activation_writers row or any writer role',
  'Preserve fixed search_path, SECURITY DEFINER owner, receipt readback, RLS, immutable triggers and direct table privilege denial',
  'Require attachment_id-scoped unique child receipts and canonical_source_hash uniqueness with no parent-only uniqueness',
  'Keep the current staging project and capability identity exact; Production sentinel and service_role runtime remain excluded'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
