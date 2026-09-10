BEGIN;
-- Run inside a transaction and roll back: fixed calendar fixtures, no staff impersonation.
UPDATE public.workshop_settings SET value='["monday","tuesday","wednesday","thursday","friday"]' WHERE key='working_week';
UPDATE public.workshop_settings SET value='"07:00"' WHERE key='day_start_time';
UPDATE public.workshop_settings SET value='"17:00"' WHERE key='day_end_time';
UPDATE public.workshop_settings SET value='[]' WHERE key IN ('closures','break_windows','overtime_windows');
DO $test$
DECLARE rows jsonb; result jsonb; again jsonb; r jsonb; m jsonb; updated_rows jsonb; live jsonb;
BEGIN
 rows:='[{"id":"a","status":"planned","start":"2026-09-14T07:00:00+08:00","end":"2026-09-14T08:00:00+08:00","duration":60},
 {"id":"b","status":"planned","start":"2026-09-14T08:00:00+08:00","end":"2026-09-14T09:00:00+08:00","duration":60},
 {"id":"four-weeks","status":"planned","start":"2026-10-12T07:00:00+08:00","end":"2026-10-12T08:00:00+08:00","duration":60}]';
 result:=public.workshop_clock_plan(rows,'[]','2026-09-14T09:00:00+08:00');
 IF jsonb_array_length(result->'moves')<>3 OR (result#>>'{moves,0,to}')::timestamptz<>'2026-09-14T09:00:00+08:00'::timestamptz
 OR (result#>>'{moves,1,to}')::timestamptz<>'2026-09-14T10:00:00+08:00'::timestamptz
 OR (result#>>'{moves,2,to}')::timestamptz<>'2026-10-12T09:00:00+08:00'::timestamptz THEN RAISE EXCEPTION 'Whole queue delay failed: %',result; END IF;
 updated_rows:='[]';
 FOR r IN SELECT x FROM jsonb_array_elements(rows)x LOOP
  SELECT x INTO m FROM jsonb_array_elements(result->'moves')x WHERE x->>'id'=r->>'id';
  updated_rows:=updated_rows||jsonb_build_array(r||jsonb_build_object('start',m->>'to','end',m->>'end'));
 END LOOP;
 again:=public.workshop_clock_plan(updated_rows,'[]','2026-09-14T09:00:00+08:00');
 IF jsonb_array_length(again->'moves')<>0 THEN RAISE EXCEPTION 'Same-clock replay moved rows twice'; END IF;
 -- A live overrun carries to a booking four weeks away even if today's next slot is empty.
 live:='{"id":"live","status":"started","start":"2026-09-14T07:00:00+08:00","end":"2026-09-14T08:00:00+08:00","actual_start":"2026-09-14T07:00:00+08:00","duration":60}';
 rows:=jsonb_build_array(live,rows->2);
 result:=public.workshop_clock_plan(rows,'[]','2026-09-14T09:00:00+08:00');
 IF jsonb_array_length(result->'moves')<>1 OR result#>>'{moves,0,id}'<>'four-weeks' OR (result#>>'{moves,0,to}')::timestamptz<>'2026-10-12T08:00:00+08:00'::timestamptz THEN RAISE EXCEPTION 'Live delay failed: %',result; END IF;
 rows:=jsonb_build_array(live||jsonb_build_object('accounted_through',result#>>'{watermarks,0,through}'),(rows->1)||jsonb_build_object('start',result#>>'{moves,0,to}','end',result#>>'{moves,0,end}'));
 again:=public.workshop_clock_plan(rows,'[]','2026-09-14T09:00:00+08:00');
 IF jsonb_array_length(again->'moves')<>0 THEN RAISE EXCEPTION 'Live watermark replay failed'; END IF;
 again:=public.workshop_clock_plan(rows,'[]','2026-09-14T09:01:00+08:00');
 IF (again#>>'{moves,0,to}')::timestamptz<>'2026-10-12T08:01:00+08:00'::timestamptz THEN RAISE EXCEPTION 'Incremental live clock delay failed'; END IF;
 rows:='[{"id":"weekend","status":"planned","start":"2026-09-18T16:00:00+08:00","end":"2026-09-18T17:00:00+08:00","duration":60}]';
 result:=public.workshop_clock_plan(rows,'[]','2026-09-19T10:00:00+08:00');
 IF (result#>>'{moves,0,to}')::timestamptz<>'2026-09-21T07:00:00+08:00'::timestamptz THEN RAISE EXCEPTION 'Weekend floor failed'; END IF;
 UPDATE public.workshop_settings SET value='[{"date":"2026-09-21"}]' WHERE key='closures';
 result:=public.workshop_clock_plan(rows,'[]','2026-09-19T10:00:00+08:00');
 IF (result#>>'{moves,0,to}')::timestamptz<>'2026-09-22T07:00:00+08:00'::timestamptz THEN RAISE EXCEPTION 'Closure floor failed'; END IF;
 UPDATE public.workshop_settings SET value='[]' WHERE key='closures';
 UPDATE public.workshop_settings SET value='[{"start":"10:00","end":"10:30"}]' WHERE key='break_windows';
 rows:='[{"id":"break","status":"planned","start":"2026-09-14T09:00:00+08:00","end":"2026-09-14T10:00:00+08:00","duration":60}]';
 result:=public.workshop_clock_plan(rows,'[]','2026-09-14T10:05:30+08:00');
 IF (result#>>'{moves,0,to}')::timestamptz<>'2026-09-14T10:30:00+08:00'::timestamptz THEN RAISE EXCEPTION 'Break floor failed'; END IF;
 result:=public.workshop_clock_plan(rows,'[{"start":"2026-09-14T11:00:00+08:00","end":"2026-09-14T12:00:00+08:00"}]','2026-09-14T10:05:30+08:00');
 IF (result#>>'{moves,0,to}')::timestamptz<>'2026-09-14T12:00:00+08:00'::timestamptz THEN RAISE EXCEPTION 'Admin reservation failed'; END IF;
 IF has_function_privilege('authenticated','public.workshop_clock_tick(boolean,timestamptz)','EXECUTE')
 OR has_function_privilege('anon','public.workshop_clock_plan(jsonb,jsonb,timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'Private worker was exposed'; END IF;
END $test$;
SELECT 'PASS: queue, four-week cascade, replay, incremental live overrun, weekend, closure, break, Admin block, private execution' result;
ROLLBACK;
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
 result:=public.workshop_clock_tick(true,check_at);
 IF result->>'ok'<>'true' OR (result->>'moved_count')::integer<>4 THEN RAISE EXCEPTION 'Driver did not move fixture queues: %',result; END IF;
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
