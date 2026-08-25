-- STAGING ONLY 421: keep authoritative RFT vehicles in the shared vehicle snapshot.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-421-rft-shared-snapshot',0));
DO $repair$ DECLARE d text; h text; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826185000' AND name='420_hidden_stoppage_visible_bridge')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826185000') THEN RAISE EXCEPTION 'PDC_421_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') INTO d,h FROM pg_proc p WHERE p.oid='public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure;
 IF h<>'f5f49b349f0b69d64ad689a01d6b1b42a6a940ed22dd47d432c5f0cd237f221a' OR position('v.lifecycle_state=''active'' AND v.visible_on_board' in d)=0 THEN RAISE EXCEPTION 'PDC_421_EXACT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,'v.lifecycle_state=''active'' AND v.visible_on_board','v.lifecycle_state IN(''active'',''rft'') AND v.visible_on_board'); EXECUTE d;
END $repair$;
DO $post$ DECLARE d text; BEGIN SELECT pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure) INTO d;
 IF position('v.lifecycle_state IN(''active'',''rft'') AND v.visible_on_board' in d)=0 OR position('v.lifecycle_state=''active'' AND v.visible_on_board' in d)<>0 THEN RAISE EXCEPTION 'PDC_421_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826190000','421_rft_shared_vehicle_snapshot',ARRAY[
 'Exact-SHA shared snapshot includes visible authoritative lifecycle rft vehicles as well as active vehicles',
 'Deleted, completed, hidden and non-receipt rows remain excluded; Production and grants are unchanged'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
