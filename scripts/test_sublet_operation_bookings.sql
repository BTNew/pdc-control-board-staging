-- Transactional fixture: all users, vehicles, operations and bookings are rolled back.
BEGIN;
DO $test$
DECLARE actor uuid:=gen_random_uuid(); vehicle uuid:=gen_random_uuid(); provider uuid;
 identity uuid; identities text[]:='{}'; result jsonb; booking uuid; version bigint; i integer;
BEGIN
 IF public.create_pdc_sublet_operation_booking(null,0,null,null,null)->>'code'<>'unauthorized' THEN RAISE EXCEPTION 'actor_guard_failed'; END IF;
 INSERT INTO auth.users(id,email) VALUES(actor,'sublet-operation-fixture@example.invalid');
 INSERT INTO public.pdc_user_roles(email,role,active) VALUES('sublet-operation-fixture@example.invalid','operator',true) ON CONFLICT(email) DO UPDATE SET role='operator',active=true,account_status='approved';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email','sublet-operation-fixture@example.invalid','role','authenticated')::text,true);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number) VALUES(vehicle,'SUBLET-FIXTURE-'||vehicle::text,'SUBLET-FIXTURE');
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed) VALUES(vehicle,'sublet',true,false);
 SELECT id INTO provider FROM public.sublet_providers WHERE active LIMIT 1;
 IF provider IS NULL THEN RAISE EXCEPTION 'provider_fixture_missing'; END IF;
 FOR i IN 1..3 LOOP
  identity:=gen_random_uuid(); identities:=array_append(identities,'manual:'||identity::text);
  INSERT INTO public.vehicle_workshop_line_adjustments(adjustment_id,vehicle_id,line_key,source_kind,stage_code,description,created_by,updated_by)
   VALUES(identity,vehicle,'manual:'||identity::text,'manual','SUBLET','Fixture requirement '||i,actor,actor);
 END LOOP;
 UPDATE public.vehicle_work_items SET required=true,completed=false WHERE vehicle_id=vehicle AND work_key='sublet';
 SELECT v.version INTO version FROM public.vehicles v WHERE id=vehicle;
 result:=public.create_pdc_sublet_operation_booking(vehicle,version,provider,current_date,current_date,'','fixture','manual:'||gen_random_uuid());
 IF result->>'code'<>'sublet_operation_not_available' THEN RAISE EXCEPTION 'unknown_requirement_accepted: %',result; END IF;
 FOR i IN 1..3 LOOP
  UPDATE public.vehicle_work_items SET required=true,completed=false WHERE vehicle_id=vehicle AND work_key='sublet';
 SELECT v.version INTO version FROM public.vehicles v WHERE id=vehicle;
  result:=public.create_pdc_sublet_operation_booking(vehicle,version,provider,current_date,current_date,'','fixture',identities[i]);
  IF NOT (result->>'ok')::boolean THEN RAISE EXCEPTION 'create_failed: %',result; END IF;
  booking:=(result#>>'{data,booking,booking_id}')::uuid;
  IF result#>>'{data,booking,operation_line_identity}'<>identities[i] THEN RAISE EXCEPTION 'identity_not_saved'; END IF;
  result:=public.create_pdc_sublet_operation_booking(vehicle,version,provider,current_date,current_date,'','fixture',identities[i]);
  IF result->>'code'<>'sublet_operation_already_booked' THEN RAISE EXCEPTION 'duplicate_accepted: %',result; END IF;
  result:=public.return_pdc_sublet_booking(booking,1,clock_timestamp());
  IF NOT (result->>'ok')::boolean THEN RAISE EXCEPTION 'return_failed: %',result; END IF;
  IF (result#>>'{data,remaining_sublet_requirements}')::integer<>3-i THEN RAISE EXCEPTION 'pending_count_failed: %',result; END IF;
  IF (result#>>'{data,sublet_station_completed}')::boolean IS DISTINCT FROM (i=3) THEN RAISE EXCEPTION 'premature_completion: %',result; END IF;
 END LOOP;
 IF (SELECT count(*) FROM public.pdc_sublet_booking_instances WHERE vehicle_id=vehicle)<>3 THEN RAISE EXCEPTION 'expected_three_bookings'; END IF;
END $test$;
ROLLBACK;
