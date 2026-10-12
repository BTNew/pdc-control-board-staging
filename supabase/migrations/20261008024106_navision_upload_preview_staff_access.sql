-- The public upload RPC is SECURITY INVOKER. Its private preview dependency
-- must remain executable by signed-in staff; the function checks approved
-- importer/administrator membership before reading any vehicle data.
DO $$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
END $$;

REVOKE ALL ON FUNCTION pdc_navision_upload_private.preview_profile(text,jsonb,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION pdc_navision_upload_private.preview_profile(text,jsonb,text,timestamptz) TO authenticated;

DO $verify$
BEGIN
 IF NOT has_function_privilege('authenticated','pdc_navision_upload_private.preview_profile(text,jsonb,text,timestamptz)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.preview_navision_upload_profile(text,jsonb,text,timestamptz)','EXECUTE')
  OR NOT has_schema_privilege('authenticated','pdc_navision_upload_private','USAGE') THEN
  RAISE EXCEPTION 'navision_upload_staff_access_missing';
 END IF;
 IF has_function_privilege('anon','pdc_navision_upload_private.preview_profile(text,jsonb,text,timestamptz)','EXECUTE')
  OR has_function_privilege('anon','public.preview_navision_upload_profile(text,jsonb,text,timestamptz)','EXECUTE') THEN
  RAISE EXCEPTION 'navision_upload_anonymous_access';
 END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='public.preview_navision_upload_profile(text,jsonb,text,timestamptz)'::regprocedure) THEN
  RAISE EXCEPTION 'navision_public_preview_must_remain_invoker';
 END IF;
END $verify$;
