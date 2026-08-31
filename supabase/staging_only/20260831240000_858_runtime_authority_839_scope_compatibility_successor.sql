-- STAGING ONLY: exact runtime authorization compatibility successor after 857.
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-858-runtime-authority-scope',0));
DO $$ BEGIN
 IF current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831230000' AND name='857_attachment_claim_839_scope_compatibility_successor')<>1
 THEN RAISE EXCEPTION 'PDC_858_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.pdc_email_monitor_runtime_authorized_502(p_gateway_instance_id text DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $function$ SELECT (public.pdc_monitor_authenticated_active_scope_839()->>'gateway_instance_id')=btrim(coalesce(p_gateway_instance_id,'')) $function$;
REVOKE ALL ON FUNCTION public.pdc_email_monitor_runtime_authorized_502(text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_email_monitor_runtime_authorized_502(text) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831240000','858_runtime_authority_839_scope_compatibility_successor',ARRAY['Align legacy runtime authority helper with exact authenticated active 839 scope','Preserve gateway binding, RLS, UID514, outbound and Production exclusion']);
NOTIFY pgrst,'reload schema';
COMMIT;
