BEGIN;
-- Isolated rollback fixtures. No staff JWT is fabricated and no live account is borrowed.
DO $test$
DECLARE actor uuid:=gen_random_uuid(); vid uuid; bid uuid; stage uuid; bay uuid; second_bay uuid; n integer;
 start_at timestamptz; check_at timestamptz; result jsonb; ids uuid[]:='{}'; before_vehicles jsonb; before_work jsonb;
BEGIN
 INSERT INTO auth.users(id,aud,role,email,created_at,updated_at) VALUES(actor,'authenticated','authenticated','clock-rollback-'||actor||'@example.invalid',now(),now());
 SELECT s.id,y.id INTO STRICT stage,bay FROM public.workshop_stages s JOIN public.workshop_bays y ON y.stage_id=s.id
  WHERE s.code='FITTING' AND y.is_active ORDER BY y.bay_number LIMIT 1;
 SELECT id INTO STRICT second_bay FROM public.workshop_bays WHERE stage_id=stage AND is_active AND id<>bay ORDER BY bay_number LIMIT 1;
 start_at:=public.workshop_clock_next_minute(clock_timestamp()+interval '2 days');
 check_at:=public.workshop_add_operational_minutes(start_at,120);
 FOR n IN 1..4 LOOP
  vid:=gen_random_uuid(); bid:=gen_random_uuid(); ids:=array_append(ids,bid);
  INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,current_location,visible_on_board,customer_name,source_system,source_record_id,created_by,updated_by)
   VALUES(vid,'clock-rollback-'||vid,'CLOCK-'||vid,'PMB',true,'Rollback clock fixture','clock_regression',vid::text,actor,actor);
  INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required) VALUES(vid,'fitting',true);
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by)
   VALUES(vid,'manual:clock-'||vid,'manual','FITTING','Clock rollback fitting job',1,actor,actor);
  UPDATE public.vehicle_work_items SET required=true WHERE vehicle_id=vid AND public.workshop_stage_code_for_work_key(work_key)='FITTING';
  INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by)
   VALUES(bid,vid,stage,CASE WHEN n=4 THEN second_bay ELSE bay END,'planned',
    CASE WHEN n=3 THEN start_at+interval '28 days' WHEN n=2 THEN public.workshop_add_operational_minutes(start_at,60) ELSE start_at END,
    public.workshop_add_operational_minutes(CASE WHEN n=3 THEN start_at+interval '28 days' WHEN n=2 THEN public.workshop_add_operational_minutes(start_at,60) ELSE start_at END,60),60,actor,actor);
 END LOOP;
 SELECT jsonb_agg(to_jsonb(v) ORDER BY v.id) INTO before_vehicles FROM public.vehicles v WHERE source_system='clock_regression';
 SELECT jsonb_agg(to_jsonb(w) ORDER BY w.id) INTO before_work FROM public.vehicle_work_items w JOIN public.vehicles v ON v.id=w.vehicle_id WHERE v.source_system='clock_regression';
 -- A legitimate validation conflict must hold only its own bay and recover later.
 UPDATE public.vehicle_work_items SET required=false WHERE vehicle_id=(SELECT vehicle_id FROM public.workshop_bookings WHERE id=ids[1]);
 result:=public.workshop_clock_tick(true,check_at);
 IF (result->>'moved_count')::integer<>1 OR jsonb_array_length(result->'issues')<>1 THEN RAISE EXCEPTION 'Bay conflict isolation failed: %',result; END IF;
 IF (SELECT scheduled_start_at FROM public.workshop_bookings WHERE id=ids[1])<>start_at OR
 (SELECT scheduled_start_at FROM public.workshop_bookings WHERE id=ids[3])<>start_at+interval '28 days'
 THEN RAISE EXCEPTION 'Failed bay partly changed'; END IF;
 UPDATE public.vehicle_work_items SET required=true WHERE vehicle_id=(SELECT vehicle_id FROM public.workshop_bookings WHERE id=ids[1]);
 result:=public.workshop_clock_tick(true,check_at);
 IF result->>'ok'<>'true' OR (result->>'moved_count')::integer<>3 THEN RAISE EXCEPTION 'Driver did not move fixture queues: %',result; END IF;
 IF (SELECT scheduled_start_at FROM public.workshop_bookings WHERE id=ids[1])<>check_at
  OR (SELECT scheduled_start_at FROM public.workshop_bookings WHERE id=ids[3])<>public.workshop_add_operational_minutes(start_at+interval '28 days',120)
  THEN RAISE EXCEPTION 'Persisted four-week cascade wrong'; END IF;
 result:=public.workshop_clock_tick(true,check_at);
 IF (result->>'moved_count')::integer<>0 THEN RAISE EXCEPTION 'Driver replay moved twice'; END IF;
 IF before_vehicles IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(v) ORDER BY v.id) FROM public.vehicles v WHERE source_system='clock_regression')
 OR before_work IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(w) ORDER BY w.id) FROM public.vehicle_work_items w JOIN public.vehicles v ON v.id=w.vehicle_id WHERE v.source_system='clock_regression')
 THEN RAISE EXCEPTION 'Vehicle state or work completion changed'; END IF;
 IF (SELECT count(*) FROM public.workshop_clock_history WHERE booking_id=ANY(ids))<>4 THEN RAISE EXCEPTION 'Missing clock audit'; END IF;
END $test$;
SELECT 'PASS: real booking updates, multi-bay isolation, four-week cascade, replay, audit, unchanged vehicles and work state' result;
ROLLBACK;
