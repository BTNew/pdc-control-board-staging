-- STAGING ONLY 431: secure-definer predicate for narrow synthetic QC object interception.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-431-intercept-storage-predicate',0));
DO $pre$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard() OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826205000' AND name='430_admin_email_intercept_acceptance') OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826205000') THEN RAISE EXCEPTION 'PDC_431_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF; END $pre$;
CREATE OR REPLACE FUNCTION public.pdc_rft_transport_intercept_object_allowed_431(p_bucket text,p_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $allowed$
 SELECT auth.uid() IN('69846ef4-a74c-4569-9e35-376cf0837888'::uuid,'557dba7f-fd70-4b9e-aa7b-b83b717682a7'::uuid)
  AND p_bucket='pdc-qc-evidence-staging'
  AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 o JOIN public.vehicles v ON v.id=o.vehicle_id
   WHERE o.delivery_status='pending' AND o.sent_at IS NULL AND o.delivered_at IS NULL AND NOT coalesce((o.payload->>'delivery_enabled')::boolean,false)
    AND v.stock_number LIKE 'HERMES-TEST-%' AND o.payload#>>'{photo_attachment,bucket_id}'=p_bucket AND o.payload#>>'{photo_attachment,storage_path}'=p_name);
$allowed$;
REVOKE ALL ON FUNCTION public.pdc_rft_transport_intercept_object_allowed_431(text,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_rft_transport_intercept_object_allowed_431(text,text) TO authenticated;
DROP POLICY pdc_rft_transport_interceptor_read_429 ON storage.objects;
DROP POLICY pdc_rft_transport_interceptor_admin_read_430 ON storage.objects;
CREATE POLICY pdc_rft_transport_interceptor_read_431 ON storage.objects FOR SELECT TO authenticated USING(public.pdc_rft_transport_intercept_object_allowed_431(bucket_id,name));
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260826210000','431_intercept_storage_security_definer_predicate',ARRAY['Narrow security-definer predicate lets exact interceptor identities evaluate referenced synthetic QC object access without granting direct outbox table SELECT','Original outbox/receipts remain private and forced-RLS; real and Production objects remain inaccessible']);
NOTIFY pgrst,'reload schema'; COMMIT;
