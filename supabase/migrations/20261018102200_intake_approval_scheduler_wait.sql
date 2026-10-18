DO $repair$
DECLARE original_body text; original_acl aclitem[];
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF md5(replace(pg_get_functiondef('public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure),chr(13),''))<>'6ad4b7261794f34d21a63c07eb932419' THEN RAISE EXCEPTION 'reviewed_approval_changed'; END IF;
 SELECT prosrc,proacl INTO original_body,original_acl FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure;
 ALTER FUNCTION public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid) SET lock_timeout='30s';
 IF EXISTS(SELECT 1 FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure AND (prosrc IS DISTINCT FROM original_body OR proacl IS DISTINCT FROM original_acl)) THEN RAISE EXCEPTION 'approval_logic_or_permissions_changed'; END IF;
END $repair$;
