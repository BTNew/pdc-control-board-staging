-- STAGING ONLY 20260831461000: force the retained email/receipt
-- boundaries after the latest-100 resume repair. No data is deleted or changed.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260831461000-latest100-force-rls',0));
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831460000' AND name='latest100_resume_repair')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260831460000
  THEN RAISE EXCEPTION 'PDC_20260831461000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END
$guard$;
ALTER TABLE public.ai_email_intake ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_email_intake FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_email_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_email_attachments FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_monitor_exact_sender_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_monitor_exact_sender_enrollments FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_jobcard_attachment_import_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_jobcard_attachment_import_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_jobcard_attachment_source_row_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_jobcard_attachment_source_row_receipts FORCE ROW LEVEL SECURITY;
DO $post$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.ai_email_intake'::regclass AND relrowsecurity AND relforcerowsecurity)
     OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.ai_email_attachments'::regclass AND relrowsecurity AND relforcerowsecurity)
     OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.pdc_monitor_exact_sender_enrollments'::regclass AND relrowsecurity AND relforcerowsecurity)
     OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.pdc_jobcard_attachment_import_receipts'::regclass AND relrowsecurity AND relforcerowsecurity)
     OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.pdc_jobcard_attachment_source_row_receipts'::regclass AND relrowsecurity AND relforcerowsecurity)
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260831461000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260831461000','latest100_force_rls_successor',ARRAY[
  'Force RLS on AI Intake parent/attachment, exact sender enrollment and immutable child receipt tables',
  'Retain RPC-only parent audit and canonical importer access; no direct table SELECT or DML is granted',
  'Preserve all append-only data, sender identity, attachment_id child isolation and Production exclusion'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
