-- STAGING ONLY: PIT is retained source evidence / deferred QC, never a Workshop bay.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904010200-remove-pit-workshop-booking',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
 SELECT version INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260904010100'
    OR to_regprocedure('public.workshop_write_history(uuid,text,jsonb,jsonb,jsonb)') IS NULL
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904010200')
 THEN RAISE EXCEPTION 'PDC_20260904010200_STAGING_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

DO $apply$
DECLARE r record; before_row jsonb; after_row jsonb; actor uuid:='4087a4f3-b1bd-4c57-8426-9ed4fd64e9c6'::uuid;
BEGIN
 UPDATE public.workshop_stages SET planner_enabled=false,updated_at=clock_timestamp() WHERE code='PIT_INSPECTION' AND planner_enabled;

 FOR r IN
   SELECT b.id FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE s.code='PIT_INSPECTION' AND b.deleted_at IS NULL AND lower(b.status::text) IN ('queued','planned','started','stoppage')
   ORDER BY b.id FOR UPDATE OF b
 LOOP
   before_row:=public.workshop_booking_snapshot(r.id);
   UPDATE public.workshop_bookings SET status='deleted',deleted_at=clock_timestamp(),deleted_by=actor,
     deleted_reason='PIT removed from Workshop; retained as deferred QC source requirement',version=version+1,updated_by=actor,updated_at=clock_timestamp()
   WHERE id=r.id;
   after_row:=public.workshop_booking_snapshot(r.id);
   PERFORM public.workshop_write_history(r.id,'pit_removed_from_workshop',before_row,after_row,
     jsonb_build_object('source','20260904010200_remove_pit_workshop_booking','invented_completion',false,'source_operation_preserved',true));
 END LOOP;
 PERFORM public.workshop_bump_revision();
 PERFORM public.workshop_bump_station_revision('PIT_INSPECTION');
END $apply$;

DO $post$
BEGIN
 IF EXISTS(SELECT 1 FROM public.workshop_stages WHERE code='PIT_INSPECTION' AND planner_enabled)
    OR EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='PIT_INSPECTION' AND b.deleted_at IS NULL AND lower(b.status::text) IN ('queued','planned','started','stoppage'))
    OR NOT EXISTS(SELECT 1 FROM public.pdc_authenticated_email_operation_lines o JOIN public.vehicles v ON v.id=o.vehicle_id WHERE v.stock_number_normalized='13048501' AND o.operation_no='OP9' AND upper(o.description) LIKE '%PIT%')
 THEN RAISE EXCEPTION 'PDC_20260904010200_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904010200','remove_pit_workshop_booking',ARRAY[
 'PIT_INSPECTION planner_enabled=false and active PIT bookings cancelled without completion',
 'OP9 PIT AND WEIGH immutable source operation retained as deferred QC evidence',
 'Production untouched'
]);
COMMIT;
