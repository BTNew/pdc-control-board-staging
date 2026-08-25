-- STAGING ONLY 419: use the canonical deleted status for hidden synthetic fallback.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-419-hidden-stoppage-deleted',0));
DO $repair$ DECLARE d text; h text; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826183000' AND name='418_hidden_stoppage_acceptance_fallback')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826183000') THEN RAISE EXCEPTION 'PDC_419_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') INTO d,h FROM pg_proc p WHERE p.oid='public.clear_vehicle_stoppage_412(uuid,integer,text,uuid)'::regprocedure;
 IF h<>'a4429e8746fa99b9b98fee5541eeb11e2172acc93829baf478f30f95251175f9' OR position('status=''cancelled''::public.workshop_booking_status' in d)=0 THEN RAISE EXCEPTION 'PDC_419_EXACT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,'status=''cancelled''::public.workshop_booking_status','status=''deleted''::public.workshop_booking_status'); EXECUTE d;
END $repair$;
DO $post$ DECLARE d text; BEGIN SELECT pg_get_functiondef('public.clear_vehicle_stoppage_412(uuid,integer,text,uuid)'::regprocedure) INTO d;
 IF position('status=''deleted''::public.workshop_booking_status' in d)=0 OR position('status=''cancelled''::public.workshop_booking_status' in d)<>0 THEN RAISE EXCEPTION 'PDC_419_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826184000','419_hidden_stoppage_deleted_status',ARRAY[
 'Exact-SHA hidden HERMES-TEST fallback uses the existing workshop_booking_status deleted value instead of unsupported cancelled',
 'Canonical operational return-to-queue behavior is unchanged'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
