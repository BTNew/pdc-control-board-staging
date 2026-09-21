-- STAGING ONLY. All fixtures, actor claims and mutations roll back.
BEGIN;
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
DO $test$
DECLARE actor uuid; actor_email text; viewer uuid; viewer_email text; fitter uuid; fitter_email text;
 v uuid:=gen_random_uuid(); ro text; source uuid; op uuid:=gen_random_uuid(); manual_op uuid:=gen_random_uuid(); op139 uuid:=gen_random_uuid();
 bay1 uuid; bay3 uuid; bay8 uuid; bus uuid; tech uuid; booking uuid; booking_result jsonb; fixture_start timestamptz;
 before_data text; r jsonb; replay jsonb; l jsonb; request_id uuid; line_identity text; scope_hash text;
 was_denied boolean; parts_hash text; old_confirm jsonb; i integer; d text; stage_hours numeric;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'Staging required'; END IF;
 SELECT md5(jsonb_build_array(
 (SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.workshop_bookings b),
 (SELECT jsonb_agg(to_jsonb(o) ORDER BY o.operation_id) FROM public.pdc_pilbara_service_operations o),
 (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.adjustment_id) FROM public.vehicle_workshop_line_adjustments a)
 )::text) INTO before_data;
 SELECT auth_user_id,email INTO STRICT actor,actor_email FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator'
 AND email!~* '(monitor|auditor|bot|service|import|hermes)' ORDER BY created_at LIMIT 1;
 SELECT auth_user_id,email INTO STRICT viewer,viewer_email FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='viewer' LIMIT 1;
 SELECT auth_user_id,email INTO STRICT fitter,fitter_email FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='fitter' LIMIT 1;
 SELECT id INTO bus FROM public.workshop_stages WHERE code='BUS_4X4';
 SELECT id INTO bay1 FROM public.workshop_bays WHERE stage_id=bus AND bay_number=1;
 SELECT id INTO bay3 FROM public.workshop_bays WHERE stage_id=bus AND bay_number=3;
 SELECT id INTO bay8 FROM public.workshop_bays WHERE stage_id=bus AND bay_number=8;
 tech:=gen_random_uuid();
 IF has_function_privilege('anon','public.get_pdc_bus_workflow(uuid)','EXECUTE')
 OR has_function_privilege('authenticated','pdc_bus_private.supplier_lines(uuid)','EXECUTE')
 OR has_table_privilege('authenticated','pdc_bus_private.supplier','UPDATE')
 THEN RAISE EXCEPTION 'Unexpected public access'; END IF;

 FOREACH d IN ARRAY ARRAY[NULL::text,'','139','137'] LOOP
  IF pdc_bus_private.supplier_kind(jsonb_build_object('department',d,'description','MMT Seat Covers','estimated_hours',0.01)) IS NOT NULL
  THEN RAISE EXCEPTION 'Supplier classification escaped department'; END IF;
 END LOOP;
 IF pdc_bus_private.supplier_kind('{"department":"138","description":"MMT Seat Covers","estimated_hours":0.01}')<>'early'
 OR pdc_bus_private.supplier_kind('{"department":"138","description":"Beam underbody rustproofing","estimated_hours":0.01}')<>'late'
 OR pdc_bus_private.supplier_kind('{"department":"138","description":"Unclear repair","estimated_hours":0.01}') IS NOT NULL
 OR pdc_bus_private.supplier_kind('{"department":"138","description":"SUB TANK fitting","estimated_hours":1}') IS NOT NULL
 THEN RAISE EXCEPTION 'Supplier classifier failed'; END IF;
 IF pdc_bus_private.minute_available('2026-09-21 14:30+08',bay8)
 OR pdc_bus_private.minute_available('2026-09-26 10:00+08',bay1)
 OR NOT pdc_bus_private.minute_available('2026-09-21 14:30+08',bay1)
 OR pdc_bus_private.add_minutes('2026-09-21 13:30+08',60,bay8)<>'2026-09-22 06:30+08'::timestamptz
 THEN RAISE EXCEPTION 'Shift calendar failed'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);
 INSERT INTO public.workshop_technicians(id,code,name,role_type,active,created_by,updated_by)
 VALUES(tech,'BUS-WORKFLOW-'||tech,'Bus workflow rollback technician','technician',true,actor,actor);
 ro:='BUS-WORKFLOW-'||v;
 SELECT raw_evidence_id INTO source FROM public.pdc_pilbara_service_operations WHERE department='138' LIMIT 1;
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,current_location,source_system,source_record_id,source_payload,visible_on_board,created_by,updated_by,model)
 VALUES(v,v::text,ro,'Bus workflow rollback fixture','PMB','department138_rollback_fixture',v::text,jsonb_build_object('fixture',v),true,actor,actor,'Toyota Coaster');
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind) VALUES(v,'existing','department138_rollback_fixture');
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 SELECT x.id,'pilbara_service_open_jobcards_v1',ro,ro,x.line,x.line,v,x.description,x.hours,x.hours,'source_explicit','review','Review',
 md5(x.id::text)||md5(v::text),source,x.department,x.stage
 FROM(VALUES(op,1,'MMT Seat Covers',0.01,'138','BUS_4X4'),(manual_op,2,'Normal mechanical accessory',2,'138','BUS_4X4'),
 (op139,3,'MMT Seat Covers',0.01,'139','FITTING'))x(id,line,description,hours,department,stage);
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v]);
 r:=public.get_pdc_bus_workflow(v);
 IF r->>'ok'<>'true' OR jsonb_array_length(r->'supplier_lines')<>1 THEN RAISE EXCEPTION 'Scope projection failed %',r; END IF;
 l:=r#>'{supplier_lines,0}';line_identity:=l->>'line_identity';scope_hash:=l->>'scope_hash';
 IF pdc_bus_private.booking_rule(v,bay1,NULL)->>'error'<>'bus_stage_parts_required'
 OR pdc_bus_private.booking_rule(v,bay3,NULL)->>'error'<>'bus_bay_vehicle_incompatible'
 THEN RAISE EXCEPTION 'Production gating failed'; END IF;
 r:=public.save_pdc_bus_workflow(v,0,gen_random_uuid(),'{"parts_readiness":{"mechanical":{"ready":true,"note":""}}}');
 IF r->>'error'<>'readiness_evidence_required' THEN RAISE EXCEPTION 'Readiness evidence gate failed'; END IF;
 request_id:=gen_random_uuid();
 r:=public.save_pdc_bus_workflow(v,0,request_id,'{"current_stage":"mechanical","parts_readiness":{"mechanical":{"ready":true,"note":"Physically checked stage parts"}}}');
 IF r->>'ok'<>'true' OR (r->>'version')::integer<>1 THEN RAISE EXCEPTION 'Workflow save failed %',r; END IF;
 replay:=public.save_pdc_bus_workflow(v,0,request_id,'{"current_stage":"mechanical","parts_readiness":{"mechanical":{"ready":true,"note":"Physically checked stage parts"}}}');
 IF replay->>'replayed'<>'true' OR (replay->>'version')::integer<>1 THEN RAISE EXCEPTION 'Replay did not deduplicate'; END IF;
 old_confirm:=r#>'{parts_readiness,mechanical}';
 r:=public.save_pdc_bus_workflow(v,1,gen_random_uuid(),'{"parts_readiness":{"mechanical":{"ready":true,"note":"Physically checked stage parts"}}}');
 IF r#>'{parts_readiness,mechanical}' IS DISTINCT FROM old_confirm THEN RAISE EXCEPTION 'Unchanged readiness falsely re-confirmed'; END IF;
 IF pdc_bus_private.booking_rule(v,bay1,NULL)->>'ok'<>'true' THEN RAISE EXCEPTION 'Confirmed readiness not accepted'; END IF;
 IF public.save_pdc_bus_workflow(v,0,gen_random_uuid(),'{}')->>'error'<>'stale_workflow'
 THEN RAISE EXCEPTION 'Stale workflow write accepted'; END IF;
 r:=public.set_pdc_bus_supplier_status(v,line_identity,scope_hash,0,'vendor_completed','Supplier reported fitted',gen_random_uuid());
 IF r#>>'{supplier_lines,0,status}'<>'vendor_completed' THEN RAISE EXCEPTION 'Vendor evidence save failed %',r; END IF;
 l:=(SELECT x FROM jsonb_array_elements(pdc_fitter_private.lines(v,NULL)) x WHERE x->>'line_identity'=line_identity);
 IF l->>'completed'<>'false' THEN RAISE EXCEPTION 'Vendor completion became physical completion'; END IF;
 IF public.set_pdc_bus_supplier_status(v,line_identity,scope_hash,1,'technician_verified','Inspected fitted work',gen_random_uuid(),NULL,tech)->>'error'
 <>'physical_verification_requires_assigned_started_job' THEN RAISE EXCEPTION 'Physical verification bypass'; END IF;
 IF public.set_pdc_bus_supplier_status(v,line_identity,'wrong',1,'ordered','Order reference',gen_random_uuid())->>'error'<>'supplier_scope_changed'
 THEN RAISE EXCEPTION 'Changed scope accepted'; END IF;
 IF public.set_pdc_bus_supplier_status(v,'source:'||op139,scope_hash,0,'ordered','Outside department',gen_random_uuid())->>'error'<>'supplier_scope_changed'
 THEN RAISE EXCEPTION 'Other department modified'; END IF;
 IF public.workshop_booking_capacity_duration_minutes(NULL,v,bus,bay1)<>120
 THEN RAISE EXCEPTION 'Supplier labour counted against new internal allocation'; END IF;
 -- Call the real planner mutation path. A future booking is created only within this rollback.
 fixture_start:=date_trunc('day',now() AT TIME ZONE 'Australia/Perth') AT TIME ZONE 'Australia/Perth'+interval '1 day 6 hours';
 WHILE extract(isodow FROM fixture_start AT TIME ZONE 'Australia/Perth')>5 LOOP fixture_start:=fixture_start+interval '1 day'; END LOOP;
 booking_result:=public.workshop_create_booking(v,'BUS_4X4',1,fixture_start,120,tech,'{"source":"bus_workflow_rollback"}');
 IF booking_result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Actual planner create failed %',booking_result; END IF;
 SELECT id INTO STRICT booking FROM public.workshop_bookings WHERE vehicle_id=v AND deleted_at IS NULL;
 IF (SELECT default_duration_minutes FROM public.workshop_bookings WHERE id=booking)<>120
 OR (SELECT bus_calendar_version FROM public.workshop_bookings WHERE id=booking)<>1
 THEN RAISE EXCEPTION 'Internal duration/shift basis not stored'; END IF;
 -- Only a physical check by the assigned running-job technician completes supplier work.
 UPDATE public.workshop_bookings SET status='started',actual_start_at=scheduled_start_at,version=version+1 WHERE id=booking;

 -- Fitter cannot plan or claim supplier completion; can only verify assigned running work.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',fitter,'email',fitter_email,'role','authenticated')::text,true);
 PERFORM set_config('request.path','/rpc/set_pdc_bus_supplier_status',true);
 PERFORM set_config('request.method','POST',true);
 r:=public.set_pdc_bus_supplier_status(v,line_identity,scope_hash,1,'technician_verified','Physically checked seat covers fitted',gen_random_uuid(),booking,tech);
 IF r#>>'{supplier_lines,0,status}'<>'technician_verified' THEN RAISE EXCEPTION 'Assigned physical verification failed %',r; END IF;
 l:=(SELECT x FROM jsonb_array_elements(pdc_fitter_private.lines(v,booking)) x WHERE x->>'line_identity'=line_identity);
 IF l->>'completed'<>'true' OR l->>'internal_hours'<>'0' THEN RAISE EXCEPTION 'Physical status did not project to fitter'; END IF;
 was_denied:=false;
 BEGIN PERFORM public.set_pdc_bus_supplier_status(v,line_identity,scope_hash,1,'vendor_completed','not allowed',gen_random_uuid());
 EXCEPTION WHEN insufficient_privilege THEN was_denied:=true; END;
 IF NOT was_denied THEN RAISE EXCEPTION 'Fitter could record vendor completion'; END IF;
 was_denied:=false;
 BEGIN PERFORM public.save_pdc_bus_workflow(v,2,gen_random_uuid(),'{}');
 EXCEPTION WHEN insufficient_privilege THEN was_denied:=true; END;
 IF NOT was_denied THEN RAISE EXCEPTION 'Fitter could plan'; END IF;

 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'email',viewer_email,'role','authenticated')::text,true);
 was_denied:=false;
 BEGIN PERFORM public.save_pdc_bus_workflow(v,2,gen_random_uuid(),'{}');
 EXCEPTION WHEN insufficient_privilege THEN was_denied:=true; END;
 IF NOT was_denied THEN RAISE EXCEPTION 'Viewer could write'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'email','no-role@example.invalid','role','authenticated')::text,true);
 was_denied:=false;
 BEGIN PERFORM public.save_pdc_bus_workflow(v,2,gen_random_uuid(),'{}');
 EXCEPTION WHEN insufficient_privilege THEN was_denied:=true; END;
 IF NOT was_denied THEN RAISE EXCEPTION 'Missing role could write'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);
 r:=public.save_pdc_bus_workflow(v,2,gen_random_uuid(),'{"forecasts":{"electrical_complete":"2026-09-25T06:00:00Z"},"downstream_review_acknowledged":true}');
 IF r->>'downstream_review_required'<>'true' THEN RAISE EXCEPTION 'Forecast change not flagged'; END IF;
 r:=public.save_pdc_bus_workflow(v,3,gen_random_uuid(),'{"downstream_review_acknowledged":true}');
 IF r->>'downstream_review_required'<>'false' THEN RAISE EXCEPTION 'Explicit downstream review not retained'; END IF;
 -- Stale physical-readiness evidence cannot become current just by reading.
 UPDATE pdc_bus_private.workflow SET plan=jsonb_set(plan,'{parts_readiness,mechanical,scope_hash}','"old-scope"') WHERE vehicle_id=v;
 r:=public.get_pdc_bus_workflow(v);
 IF r#>>'{parts_readiness,mechanical,ready}' IS NOT NULL OR r#>>'{parts_readiness,mechanical,review_required}'<>'true'
 THEN RAISE EXCEPTION 'Stale readiness presented as current'; END IF;
 r:=public.save_pdc_bus_workflow(v,4,gen_random_uuid(),'{"parts_readiness":{"mechanical":{"ready":true,"note":"Physically checked stage parts"}}}');
 IF r#>>'{parts_readiness,mechanical,ready}'<>'true' OR r#>>'{parts_readiness,mechanical,scope_hash}'<>pdc_bus_private.catalog_hash(v)
 THEN RAISE EXCEPTION 'Explicit scope re-confirmation failed'; END IF;
 -- Fixture operations retain source amounts; supplier separation is only projection.
 IF (SELECT source_estimated_hours FROM public.pdc_pilbara_service_operations WHERE operation_id=op)<>0.01
 OR (SELECT source_estimated_hours FROM public.pdc_pilbara_service_operations WHERE operation_id=manual_op)<>2
 THEN RAISE EXCEPTION 'Source hours were mutated'; END IF;
 IF before_data IS DISTINCT FROM (SELECT md5(jsonb_build_array(
 (SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.workshop_bookings b WHERE b.vehicle_id<>v),
 (SELECT jsonb_agg(to_jsonb(o) ORDER BY o.operation_id) FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id<>v),
 (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.adjustment_id) FROM public.vehicle_workshop_line_adjustments a WHERE a.vehicle_id<>v)
 )::text)) THEN RAISE EXCEPTION 'Real bookings, source operations or staff estimates changed'; END IF;
END $test$;
SELECT 'PASS: department boundaries, supplier interpretation, physical evidence, idempotency, stale versions, independent readiness, role denial, shift envelopes and canonical allocation' result;
ROLLBACK;
