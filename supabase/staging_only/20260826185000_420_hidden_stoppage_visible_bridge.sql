-- STAGING ONLY 420: let the hidden synthetic fixture exercise canonical queue return.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-420-hidden-stoppage-visible-bridge',0));
DO $repair$ DECLARE d text; h text; old_block text; new_block text; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826184000' AND name='419_hidden_stoppage_deleted_status')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826184000') THEN RAISE EXCEPTION 'PDC_420_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') INTO d,h FROM pg_proc p WHERE p.oid='public.clear_vehicle_stoppage_412(uuid,integer,text,uuid)'::regprocedure;
 old_block:='booking_before:=public.workshop_booking_snapshot(b.id);
   UPDATE public.workshop_bookings SET status=''deleted''::public.workshop_booking_status,bay_id=NULL,stoppage_reason=NULL,stoppage_started_at=NULL,returned_to_queue_at=clock_timestamp(),deleted_at=clock_timestamp(),deleted_reason=''HERMES-TEST clear-stoppage acceptance'',updated_by=uid,updated_at=clock_timestamp(),version=version+1 WHERE id=b.id;
   UPDATE public.workshop_booking_assignments SET released_at=coalesce(released_at,clock_timestamp()),updated_at=clock_timestamp() WHERE booking_id=b.id AND released_at IS NULL;
   booking_after:=public.workshop_booking_snapshot(b.id);
   PERFORM public.workshop_write_history(b.id,''synthetic_stoppage_cleared'',booking_before,booking_after,jsonb_build_object(''source'',''HERMES-TEST-418'',''resolution_note'',note));
   PERFORM public.workshop_bump_revision();
   result:=jsonb_build_object(''ok'',true,''booking'',booking_after,''synthetic_hidden_fallback'',true);';
 new_block:='UPDATE public.vehicles SET visible_on_board=true,version=version+1,updated_by=uid,updated_at=clock_timestamp() WHERE id=v.id;
   result:=public.return_work_to_queue(b.id,b.version,NULL,jsonb_build_object(''source'',''HERMES-TEST-420-visible-bridge'',''resolution_note'',note));
   IF NOT coalesce((result->>''ok'')::boolean,false) THEN RAISE EXCEPTION ''PDC_420_SYNTHETIC_QUEUE_RETURN_FAILED:%'',coalesce(result->>''error'',''unknown'') USING errcode=''55000''; END IF;
   UPDATE public.vehicles SET visible_on_board=false,version=version+1,updated_by=uid,updated_at=clock_timestamp() WHERE id=v.id RETURNING * INTO v;
   result:=result||jsonb_build_object(''synthetic_hidden_fallback'',true);';
 IF h<>'5180412106e45ed349b466814c99a5ee66742bce6b6c4a03625886983ee7fd65' OR position(old_block in d)=0 THEN RAISE EXCEPTION 'PDC_420_EXACT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,old_block,new_block); EXECUTE d;
END $repair$;
DO $post$ DECLARE d text; BEGIN SELECT pg_get_functiondef('public.clear_vehicle_stoppage_412(uuid,integer,text,uuid)'::regprocedure) INTO d;
 IF position('HERMES-TEST-420-visible-bridge' in d)=0 OR position('status=''deleted''' in d)<>0 OR position('public.return_work_to_queue' in d)=0 THEN RAISE EXCEPTION 'PDC_420_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826185000','420_hidden_stoppage_visible_bridge',ARRAY[
 'Hidden registered HERMES-TEST acceptance briefly enables only its own Board eligibility inside one transaction, then uses canonical return_work_to_queue and restores hidden state',
 'Operational visible stoppages remain unchanged; protected vehicles and Production are untouched'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
