-- STAGING only: every fixture and actor context rolls back.
BEGIN;
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
DO $test$
DECLARE actor uuid; email text; v uuid:=gen_random_uuid(); v2 uuid:=gen_random_uuid(); source uuid; ro text;
 primary_tech uuid:=gen_random_uuid(); helper uuid:=gen_random_uuid(); other_tech uuid:=gen_random_uuid();
 sid uuid; bay4 uuid; bay8 uuid; booking uuid; booking2 uuid; r jsonb; replay jsonb; req uuid;
 start_at timestamptz; vv integer; old_minutes integer; before_ops text; before_existing text; denied boolean; before_team jsonb;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'Staging required'; END IF;
 SELECT auth_user_id,p.email INTO STRICT actor,email FROM public.pdc_user_roles p
 WHERE active AND account_status='approved' AND role='administrator' AND p.email!~* '(monitor|auditor|bot|service|import|hermes)' ORDER BY created_at LIMIT 1;
 SELECT id INTO sid FROM public.workshop_stages WHERE code='BUS_4X4';
 SELECT id INTO bay4 FROM public.workshop_bays WHERE stage_id=sid AND bay_number=4;
 SELECT id INTO bay8 FROM public.workshop_bays WHERE stage_id=sid AND bay_number=8;
 IF pdc_bus_private.minute_available('2026-09-28 08:00+08',bay4)
 OR pdc_bus_private.minute_available('2027-12-28 08:00+08',bay4)
 OR NOT pdc_bus_private.minute_available('2026-09-29 06:00+08',bay8)
 OR pdc_bus_private.add_minutes('2026-09-25 13:30+08',60,bay8)<>'2026-09-29 06:30+08'::timestamptz
 THEN RAISE EXCEPTION 'Dept138 weekend/holiday/full Nick shift regression'; END IF;
 IF has_function_privilege('anon','public.set_pdc_bus_booking_team(uuid,integer,uuid,uuid[],uuid,text)','EXECUTE')
 OR has_function_privilege('authenticated','pdc_bus_private.team_payload(uuid)','EXECUTE')
 OR has_table_privilege('authenticated','pdc_bus_private.helper_labour','INSERT')
 THEN RAISE EXCEPTION 'Unexpected anonymous/private access'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]')::text) INTO before_existing FROM public.workshop_bookings b;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(o) ORDER BY o.operation_id),'[]')::text) INTO before_ops FROM public.pdc_pilbara_service_operations o;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',email,'role','authenticated')::text,true);
 INSERT INTO public.workshop_technicians(id,code,name,role_type,active,created_by,updated_by)
 SELECT t,'BUS-TEAM-'||t,'Bus team rollback '||t,'technician',true,actor,actor FROM unnest(ARRAY[primary_tech,helper,other_tech]) t;
 SELECT raw_evidence_id INTO source FROM public.pdc_pilbara_service_operations WHERE department='138' LIMIT 1;
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,current_location,source_system,source_record_id,source_payload,visible_on_board,created_by,updated_by,model)
 SELECT x,x::text,'BUS-TEAM-'||x,'Bus team rollback fixture','PMB','department138_team_rollback',x::text,jsonb_build_object('fixture',x),true,actor,actor,'Toyota Coaster'
 FROM unnest(ARRAY[v,v2]) x;
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind) SELECT x,'existing','department138_team_rollback' FROM unnest(ARRAY[v,v2]) x;
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 SELECT gen_random_uuid(),'pilbara_service_open_jobcards_v1','BUS-TEAM-'||x,'BUS-TEAM-'||x,1,1,x,'Mechanical fitment',2,2,'source_explicit','review','Review',
 md5(x::text)||md5(x::text),source,'138','BUS_4X4' FROM unnest(ARRAY[v,v2]) x;
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v,v2]);
 r:=public.save_pdc_bus_workflow(v,0,gen_random_uuid(),'{"parts_readiness":{"mechanical":{"ready":true,"note":"Rollback physical check"}}}');
 IF r#>>'{planning_defaults,qa_minutes}'<>'180' OR r#>>'{booking_rules,pit_notice_calendar_confirmed}'<>'true'
 OR r#>>'{planning_calendar,verified_through}'<>'2027-12-31' THEN RAISE EXCEPTION 'Planning defaults missing %',r; END IF;
 PERFORM public.save_pdc_bus_workflow(v2,0,gen_random_uuid(),'{"parts_readiness":{"mechanical":{"ready":true,"note":"Rollback physical check"}}}');
 start_at:=date_trunc('day',now() AT TIME ZONE 'Australia/Perth') AT TIME ZONE 'Australia/Perth'+interval '320 days 6 hours';
 WHILE NOT pdc_bus_private.minute_available(start_at,bay4) LOOP start_at:=start_at+interval '1 day'; END LOOP;
 r:=public.workshop_create_booking(v,'BUS_4X4',4,start_at,120,primary_tech,'{"source":"dept138_team_rollback"}');
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Fixture booking failed %',r; END IF;
 SELECT id,version,default_duration_minutes INTO booking,vv,old_minutes FROM public.workshop_bookings WHERE vehicle_id=v;
 -- A named electrical helper cannot reserve a mechanical 14:00-15:00 hour.
 r:=public.workshop_validate_booking(NULL,v,sid,bay4,start_at+interval '7 hours 30 minutes',
 pdc_bus_private.add_minutes(start_at+interval '7 hours 30 minutes',120,bay4),120,'planned',
 (SELECT id FROM public.workshop_technicians WHERE name='Nick Darker' AND code='1747'),false);
 IF r->>'error'<>'bus_technician_shift_conflict' THEN RAISE EXCEPTION 'Nick shift escaped through mechanical bay %',r; END IF;
 IF pdc_bus_private.technician_shift_problem((SELECT id FROM public.workshop_technicians WHERE name='Gabriel Colborne'),
 bay4,start_at+interval '8 hours',start_at+interval '9 hours')->>'error'<>'bus_technician_shift_conflict'
 OR pdc_bus_private.technician_shift_problem((SELECT id FROM public.workshop_technicians WHERE name='Nick Darker' AND code='1747'),
 bay8,start_at,start_at+interval '8 hours') IS NOT NULL THEN RAISE EXCEPTION 'Electrical crew productive shift wrong'; END IF;
 req:=gen_random_uuid();
 r:=public.set_pdc_bus_booking_team(booking,vv,primary_tech,ARRAY[helper],req,'Training together in Bay4');
 IF r->>'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(r#>'{booking,helper_assignments}')<>1 THEN RAISE EXCEPTION 'Team save failed %',r; END IF;
 replay:=public.set_pdc_bus_booking_team(booking,vv,primary_tech,ARRAY[helper],req,'Training together in Bay4');
 IF replay->>'replayed'<>'true' THEN RAISE EXCEPTION 'Team retry not idempotent'; END IF;
 IF public.set_pdc_bus_booking_team(booking,vv,primary_tech,ARRAY[other_tech],req,'changed')->>'error'<>'request_conflict'
 OR public.set_pdc_bus_booking_team(booking,vv,primary_tech,ARRAY[helper],gen_random_uuid(),'stale')->>'error'<>'version_conflict'
 THEN RAISE EXCEPTION 'Team request/version guards failed'; END IF;
 SELECT version INTO vv FROM public.workshop_bookings WHERE id=booking;
 IF public.set_pdc_bus_booking_team(booking,vv,primary_tech,ARRAY[primary_tech],gen_random_uuid(),'duplicate')->>'error'<>'invalid_team'
 THEN RAISE EXCEPTION 'Duplicate team accepted'; END IF;
 IF (SELECT count(*) FROM public.workshop_bookings WHERE vehicle_id=v)<>1
 OR (SELECT bay_id FROM public.workshop_bookings WHERE id=booking)<>bay4
 OR (SELECT default_duration_minutes FROM public.workshop_bookings WHERE id=booking)<>old_minutes
 THEN RAISE EXCEPTION 'Team changed elapsed duration or duplicated physical booking'; END IF;
 IF NOT pdc_fitter_private.assigned(booking,helper)
 OR public.get_fitter_job(helper,booking)->>'ok'<>'true'
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_fitter_jobs(helper)->'jobs') j WHERE j->>'id'=booking::text)
 THEN RAISE EXCEPTION 'Helper fitter access missing'; END IF;
 -- A different bay cannot borrow the same reserved helper.
 r:=public.workshop_create_booking(v2,'BUS_4X4',2,start_at,120,other_tech,'{"source":"dept138_team_rollback"}');
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Second fixture failed %',r; END IF;
 SELECT id,version INTO booking2,vv FROM public.workshop_bookings WHERE vehicle_id=v2;
 r:=public.set_pdc_bus_booking_team(booking2,vv,other_tech,ARRAY[helper],gen_random_uuid(),'Must conflict');
 IF r->>'error'<>'technician_overlap' THEN RAISE EXCEPTION 'Helper double-booking accepted %',r; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_booking_assignments WHERE booking_id=booking2 AND technician_id=helper AND released_at IS NULL)
 THEN RAISE EXCEPTION 'Rejected team partly saved'; END IF;
 -- Reassign and resize preserve helper membership; calendar intervals stay canonical.
 SELECT version INTO vv FROM public.workshop_bookings WHERE id=booking;
 r:=public.workshop_resize_booking(booking,vv,180,'{"source":"dept138_team_rollback"}');
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Resize failed %',r; END IF;
 IF NOT pdc_fitter_private.assigned(booking,helper) OR EXISTS(
 SELECT 1 FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id
 WHERE b.id=booking AND a.released_at IS NULL AND (a.scheduled_start_at<>b.scheduled_start_at OR a.scheduled_end_at<>b.scheduled_end_at))
 THEN RAISE EXCEPTION 'Resize dropped or desynchronised helper'; END IF;
 SELECT version INTO vv FROM public.workshop_bookings WHERE id=booking;
 r:=public.workshop_move_booking(booking,vv,'BUS_4X4',4,start_at+interval '7 days',180,'{"source":"dept138_team_rollback"}');
 IF r->>'ok' IS DISTINCT FROM 'true' OR NOT pdc_fitter_private.assigned(booking,helper) THEN RAISE EXCEPTION 'Move lost team %',r; END IF;
 -- Moving an existing team into a helper's other booking must roll back completely.
 SELECT version INTO vv FROM public.workshop_bookings WHERE id=booking2;
 r:=public.workshop_move_booking(booking2,vv,'BUS_4X4',2,start_at+interval '14 days',120,'{"source":"dept138_team_rollback"}');
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Conflict fixture move failed %',r; END IF;
 SELECT version INTO vv FROM public.workshop_bookings WHERE id=booking2;
 r:=public.set_pdc_bus_booking_team(booking2,vv,other_tech,ARRAY[helper],gen_random_uuid(),'Different week');
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Non-overlapping helper rejected %',r; END IF;
 SELECT version INTO vv FROM public.workshop_bookings WHERE id=booking;
 before_team:=public.workshop_booking_snapshot(booking);denied:=false;
 BEGIN
  r:=public.workshop_move_booking(booking,vv,'BUS_4X4',4,start_at+interval '14 days',180,'{"source":"dept138_team_rollback"}');
  denied:=r->>'error'='technician_overlap';
 EXCEPTION WHEN SQLSTATE '22023' OR exclusion_violation THEN denied:=true;
 END;
 IF NOT coalesce(denied,false) OR public.workshop_booking_snapshot(booking) IS DISTINCT FROM before_team
 THEN RAISE EXCEPTION 'Conflicting team move partly saved'; END IF;
 -- Record actual helper labour independently of booking elapsed clock.
 UPDATE public.workshop_bookings SET status='started',actual_start_at=clock_timestamp()-interval '2 hours',version=version+1 WHERE id=booking;
 SELECT version,default_duration_minutes INTO vv,old_minutes FROM public.workshop_bookings WHERE id=booking;
 req:=gen_random_uuid();
 r:=public.record_pdc_bus_helper_labour(booking,vv,helper,transaction_timestamp(),30,'Lift and positioning assistance',req);
 IF r->>'ok' IS DISTINCT FROM 'true' OR r#>>'{booking,helper_labour_minutes}'<>'30'
 THEN RAISE EXCEPTION 'Helper labour failed %',r; END IF;
 replay:=public.record_pdc_bus_helper_labour(booking,vv,helper,transaction_timestamp(),30,'Lift and positioning assistance',req);
 IF replay->>'replayed'<>'true' OR (SELECT count(*) FROM pdc_bus_private.helper_labour WHERE booking_id=booking)<>1
 THEN RAISE EXCEPTION 'Helper actual retry duplicated labour'; END IF;
 IF (SELECT default_duration_minutes FROM public.workshop_bookings WHERE id=booking)<>old_minutes
 OR (SELECT actual_duration_minutes FROM public.workshop_bookings WHERE id=booking) IS NOT NULL
 THEN RAISE EXCEPTION 'Helper person-minutes altered main elapsed work'; END IF;
 SELECT version INTO vv FROM public.workshop_bookings WHERE id=booking;
 IF public.record_pdc_bus_helper_labour(booking,vv,primary_tech,transaction_timestamp(),30,'Not helper',gen_random_uuid())->>'error'<>'helper_assignment_or_work_time_invalid'
 THEN RAISE EXCEPTION 'Non-helper labour accepted'; END IF;
 IF public.record_pdc_bus_helper_labour(booking,vv,helper,clock_timestamp()-interval '1 hour',30,'Before helper assigned',gen_random_uuid())->>'error'<>'helper_assignment_or_work_time_invalid'
 THEN RAISE EXCEPTION 'Labour before helper assignment accepted'; END IF;
 -- Authenticated but unapproved users cannot write or infer operator access.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'email','no-role@example.invalid','role','authenticated')::text,true);
 denied:=false; BEGIN PERFORM public.set_pdc_bus_booking_team(booking,vv,primary_tech,ARRAY[helper],gen_random_uuid(),'no role');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'No-role user wrote team'; END IF;
 denied:=false; BEGIN PERFORM public.record_pdc_bus_helper_labour(booking,vv,helper,transaction_timestamp(),10,'no role',gen_random_uuid());
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'No-role user wrote helper labour'; END IF;
 IF before_existing IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]')::text) FROM public.workshop_bookings b WHERE vehicle_id NOT IN(v,v2))
 OR before_ops IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(o) ORDER BY o.operation_id),'[]')::text) FROM public.pdc_pilbara_service_operations o WHERE vehicle_id NOT IN(v,v2))
 THEN RAISE EXCEPTION 'Existing operational data changed'; END IF;
END $test$;
SELECT 'PASS: shared team, helper conflict, fitter access, preserved duration, resize/move, independent actuals, replay, auth, calendar and QA defaults' result;
ROLLBACK;
