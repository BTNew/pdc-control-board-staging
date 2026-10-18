DO $repair$
DECLARE original_body text; original_acl aclitem[];
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF md5(replace(pg_get_functiondef('public.book_all_vehicle_stations(uuid,integer)'::regprocedure),chr(13),''))<>'f8033069aea16c9c9a7e68d82ea67cf0' THEN RAISE EXCEPTION 'reviewed_book_all_changed'; END IF;
 SELECT prosrc,proacl INTO original_body,original_acl FROM pg_proc WHERE oid='public.book_all_vehicle_stations(uuid,integer)'::regprocedure;
 ALTER FUNCTION public.book_all_vehicle_stations(uuid,integer) SET lock_timeout='45s';
 IF EXISTS(SELECT 1 FROM pg_proc WHERE oid='public.book_all_vehicle_stations(uuid,integer)'::regprocedure AND (prosrc IS DISTINCT FROM original_body OR proacl IS DISTINCT FROM original_acl)) THEN RAISE EXCEPTION 'booking_logic_or_permissions_changed'; END IF;
END $repair$;
