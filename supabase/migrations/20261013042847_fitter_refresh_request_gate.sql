-- Staging only: restore the existing read-only fitter refresh through PostgREST.
DO $repair$
DECLARE before_def text; after_def text; before_acl aclitem[];
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging only'; END IF;
 SELECT pg_get_functiondef(oid),proacl INTO before_def,before_acl
 FROM pg_proc WHERE oid='public.pdc_check_fitter_request()'::regprocedure;
 IF md5(before_def)<>'43b9bbd971a8c5e8cca22a06394797b0'
 OR md5(pg_get_functiondef('pdc_fitter_private.authorized_request(boolean)'::regprocedure))<>'73bdc71cc1c9ef1af6bffcc4838264ba'
 THEN RAISE EXCEPTION 'Fitter permissions changed; reconcile before applying'; END IF;
 after_def:=replace(before_def,'''rpc/get_fitter_job'',''rpc/fitter_job_command''',
   '''rpc/get_fitter_job'',''rpc/get_fitter_refresh'',''rpc/fitter_job_command''');
 IF after_def=before_def THEN RAISE EXCEPTION 'Fitter refresh route patch did not match'; END IF;
 EXECUTE after_def;
 IF (SELECT proacl FROM pg_proc WHERE oid='public.pdc_check_fitter_request()'::regprocedure) IS DISTINCT FROM before_acl
 OR md5(pg_get_functiondef('pdc_fitter_private.authorized_request(boolean)'::regprocedure))<>'73bdc71cc1c9ef1af6bffcc4838264ba'
 THEN RAISE EXCEPTION 'Fitter ACL or inner authority changed'; END IF;
END $repair$;
NOTIFY pgrst,'reload schema';
