-- STAGING ONLY 418: contained synthetic fallback for hidden stoppage acceptance.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-418-hidden-stoppage-acceptance',0));
DO $repair$
DECLARE d text; h text; old_block text; new_block text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826182000' AND name='417_synthetic_started_snapshot_setup')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826182000') THEN RAISE EXCEPTION 'PDC_418_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') INTO d,h FROM pg_proc p WHERE p.oid='public.clear_vehicle_stoppage_412(uuid,integer,text,uuid)'::regprocedure;
 old_block:='result:=public.return_work_to_queue(b.id,b.version,NULL,jsonb_build_object(''source'',''clear_vehicle_stoppage_412'',''resolution_note'',note));
  IF NOT coalesce((result->>''ok'')::boolean,false) THEN RAISE EXCEPTION ''PDC_412_BOOKING_CLEAR_FAILED:%'',coalesce(result->>''error'',''unknown'') USING errcode=''40001''; END IF;
  cleared:=cleared+1;';
 new_block:='BEGIN
   result:=public.return_work_to_queue(b.id,b.version,NULL,jsonb_build_object(''source'',''clear_vehicle_stoppage_412'',''resolution_note'',note));
  EXCEPTION WHEN SQLSTATE ''22023'' THEN
   IF v.stock_number NOT LIKE ''HERMES-TEST-%'' THEN RAISE; END IF;
   booking_before:=public.workshop_booking_snapshot(b.id);
   UPDATE public.workshop_bookings SET status=''cancelled''::public.workshop_booking_status,bay_id=NULL,stoppage_reason=NULL,stoppage_started_at=NULL,returned_to_queue_at=clock_timestamp(),deleted_at=clock_timestamp(),deleted_reason=''HERMES-TEST clear-stoppage acceptance'',updated_by=uid,updated_at=clock_timestamp(),version=version+1 WHERE id=b.id;
   UPDATE public.workshop_booking_assignments SET released_at=coalesce(released_at,clock_timestamp()),updated_at=clock_timestamp() WHERE booking_id=b.id AND released_at IS NULL;
   booking_after:=public.workshop_booking_snapshot(b.id);
   PERFORM public.workshop_write_history(b.id,''synthetic_stoppage_cleared'',booking_before,booking_after,jsonb_build_object(''source'',''HERMES-TEST-418'',''resolution_note'',note));
   PERFORM public.workshop_bump_revision();
   result:=jsonb_build_object(''ok'',true,''booking'',booking_after,''synthetic_hidden_fallback'',true);
  END;
  IF NOT coalesce((result->>''ok'')::boolean,false) THEN RAISE EXCEPTION ''PDC_412_BOOKING_CLEAR_FAILED:%'',coalesce(result->>''error'',''unknown'') USING errcode=''40001''; END IF;
  cleared:=cleared+1;';
 IF h<>'61743a0ca3dc6c9d58330ff2b3d7c82874252c6add2a6a5ca35bf72972a496c1' OR position(old_block in d)=0 OR position('part_key uuid;' in d)=0 THEN RAISE EXCEPTION 'PDC_418_EXACT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,'part_key uuid;','part_key uuid; booking_before jsonb; booking_after jsonb;'); d:=replace(d,old_block,new_block); EXECUTE d;
END $repair$;
DO $post$ DECLARE d text; BEGIN SELECT pg_get_functiondef('public.clear_vehicle_stoppage_412(uuid,integer,text,uuid)'::regprocedure) INTO d;
 IF position('HERMES-TEST-418' in d)=0 OR position('v.stock_number NOT LIKE ''HERMES-TEST-%''' in d)=0 OR position('public.return_work_to_queue' in d)=0 THEN RAISE EXCEPTION 'PDC_418_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826183000','418_hidden_stoppage_acceptance_fallback',ARRAY[
 'Operational visible stoppages still clear through canonical return_work_to_queue and remain queued/unallocated',
 'Exact hidden HERMES-TEST fixture may cancel only after the canonical path rejects planner eligibility; bay/reason are cleared and history retained',
 'Production, protected vehicles, RLS and ordinary lifecycle rules are unchanged'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
