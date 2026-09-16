-- STAGING ONLY. Run after the department 138 routing migration.
-- Every fixture and attempted write rolls back. No trigger is disabled.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $test$
DECLARE
 actor uuid; actor_email text; evidence uuid; evidence_before jsonb;
 fixture uuid:=gen_random_uuid(); stock text; operation138 uuid:=gen_random_uuid();
 operation139 uuid:=gen_random_uuid(); operation_write uuid:=gen_random_uuid();
 adjustment138 uuid; adjustment139 uuid; adjustment_write uuid;
 input_line jsonb; legacy jsonb; actual jsonb; lines jsonb;
 snapshot jsonb; projected jsonb; stage text; hours numeric; description text;
 rejected boolean; checked integer:=0; before_bookings jsonb; before_progress jsonb;
 fixture_source_before jsonb;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'department138_test_requires_staging'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT r.auth_user_id,r.email INTO STRICT actor,actor_email
 FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND r.role='administrator'
  AND r.email !~* '(monitor|auditor|viewer|bot|service|import|hermes)'
 ORDER BY r.created_at,r.id LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
  'sub',actor,'email',actor_email,'role','authenticated')::text,true);

 -- Compare the new routing wrapper to the preserved hours/defaults authority.
 -- Include preparation, sublet, electrical, product-specific and unknown work.
 FOREACH description IN ARRAY ARRAY['Pre-Delivery (Commercial)','Fill with fuel',
  'PIT & WEIGH','Mine bar with lights','SUBLET vinyl floor',
  'ARB Frontier replacement fuel tank','ARB Roof Rack','Unclassified accessory'] LOOP
  FOREACH stage IN ARRAY ARRAY['FITTING','ELECTRICAL','FABRICATION','HOIST','TINT','TYRE','SUBLET','BUS_4X4','REVIEW'] LOOP
   FOREACH hours IN ARRAY ARRAY[NULL::numeric,0,1.25,3.75] LOOP
    input_line:=jsonb_build_object('department','138','description',description,
     'stage_code',stage,'estimated_hours',hours,'source_estimated_hours',hours,
     'active',true,'line_identity','test:department138');
    legacy:=public.pdc_pending_work_category_before_dept138_20260916(input_line);
    actual:=public.pdc_pending_work_category_20260912(input_line);
    IF actual->>'stage_code' IS DISTINCT FROM 'BUS_4X4'
     OR actual-ARRAY['stage_code','routing_rule'] IS DISTINCT FROM legacy-ARRAY['stage_code','routing_rule']
    THEN RAISE EXCEPTION 'department138_pending_station_or_hours_regression: % -> %',input_line,actual; END IF;
    input_line:=input_line||jsonb_build_object('department','139');
    IF public.pdc_pending_work_category_20260912(input_line)
      IS DISTINCT FROM public.pdc_pending_work_category_before_dept138_20260916(input_line)
    THEN RAISE EXCEPTION 'department139_pending_behavior_changed: %',input_line; END IF;
   END LOOP;
  END LOOP;
 END LOOP;

 SELECT o.raw_evidence_id INTO STRICT evidence FROM public.pdc_pilbara_service_operations o
 WHERE o.department='138' ORDER BY o.operation_id LIMIT 1;
 SELECT to_jsonb(e) INTO evidence_before FROM public.pdc_pilbara_service_import_rows e WHERE e.evidence_id=evidence;
 SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') INTO before_bookings FROM public.workshop_bookings b;
 SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.booking_id,p.line_identity),'[]') INTO before_progress FROM pdc_fitter_private.operation_progress p;
 stock:='D138-TEST-'||left(fixture::text,8);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,current_location,
  source_system,source_record_id,source_payload,visible_on_board,created_by,updated_by)
 VALUES(fixture,fixture,stock,'Department routing rollback fixture','PMB',
  'department138_rollback_fixture',fixture::text,jsonb_build_object('fixture',fixture),true,actor,actor);
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind)
 VALUES(fixture,'existing','department138_rollback_fixture');

 -- Insert saved choices before their source identities to model legacy records.
 -- This lets the canonical read test exercise stale locked FITTING without
 -- disabling the new write guard or modifying a real operation.
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,
  stage_code,description,estimated_hours,manual_assignment_locked,created_by,updated_by)
 VALUES(fixture,'source:'||operation138,'source','FITTING','ARB Roof Rack',3.75,true,actor,actor)
 RETURNING adjustment_id INTO adjustment138;
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,
  stage_code,description,estimated_hours,manual_assignment_locked,created_by,updated_by)
 VALUES(fixture,'source:'||operation139,'source','HOIST','Department 139 accessory',4.5,true,actor,actor)
 RETURNING adjustment_id INTO adjustment139;
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,
  repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
  source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,
  classification,semantic_hash,raw_evidence_id,department,proposed_station)
 SELECT x.id,'pilbara_service_open_jobcards_v1',stock,stock,x.line_number,x.line_number,
  fixture,x.description,1.25,1.25,'source_explicit','review','Review',
  md5(x.id::text)||md5(fixture::text),evidence,x.department,'BUS_4X4'
 FROM (VALUES
  (operation138,1,'ARB Roof Rack','138'),
  (operation139,2,'Department 139 accessory','139'),
  (operation_write,3,'Department 138 write guard','138')
 ) x(id,line_number,description,department);
 SELECT jsonb_agg(to_jsonb(o) ORDER BY o.operation_id) INTO fixture_source_before
 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=fixture;

 lines:=public.pdc_qc_operation_lines_379(fixture);
 SELECT l INTO STRICT actual FROM jsonb_array_elements(lines) l WHERE l->>'source_line_id'=operation138::text;
 IF actual->>'stage_code' IS DISTINCT FROM 'BUS_4X4'
  OR (actual->>'estimated_hours')::numeric IS DISTINCT FROM 3.75::numeric
  OR (actual->>'source_estimated_hours')::numeric IS DISTINCT FROM 1.25::numeric
  OR (actual->>'active')::boolean IS DISTINCT FROM true
  OR (actual->>'completed')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'legacy_locked_department138_projection_failed: %',actual; END IF;
 SELECT l INTO STRICT actual FROM jsonb_array_elements(lines) l WHERE l->>'source_line_id'=operation139::text;
 IF actual->>'stage_code' IS DISTINCT FROM 'HOIST'
  OR (actual->>'estimated_hours')::numeric IS DISTINCT FROM 4.5::numeric
 THEN RAISE EXCEPTION 'mixed_vehicle_department139_manual_choice_changed: %',actual; END IF;

 -- Board projection must resist the same stale adjustment as QC/details.
 snapshot:=public.get_pdc_email_vehicle_location_snapshot();
 IF snapshot->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'board_snapshot_failed'; END IF;
 FOR projected IN SELECT l FROM jsonb_array_elements(snapshot#>'{data,vehicles}') v,
  jsonb_array_elements(v->'operation_lines') l
  JOIN public.pdc_pilbara_service_operations o ON o.operation_id::text=l->>'operation_line_id'
  WHERE o.department='138'
 LOOP
  checked:=checked+1;
  IF projected->>'work_key' IS DISTINCT FROM 'bus4x4'
   OR projected->>'classification' IS DISTINCT FROM 'BUS_4X4'
  THEN RAISE EXCEPTION 'board_department138_projection_failed: %',projected; END IF;
 END LOOP;
 IF checked=0 THEN RAISE EXCEPTION 'board_department138_test_exercised_no_lines'; END IF;

 -- Guard errors must be the intended department constraint, not unrelated failures.
 rejected:=false;
 BEGIN
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,
   stage_code,description,estimated_hours,manual_assignment_locked,created_by,updated_by)
  VALUES(fixture,'source:'||operation_write,'source','FITTING','Department 138 write guard',1.25,true,actor,actor);
 EXCEPTION WHEN check_violation THEN
  IF SQLERRM<>'department_138_requires_bus_4x4' THEN RAISE; END IF;
  rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'department138_invalid_insert_accepted'; END IF;
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,
  stage_code,description,estimated_hours,manual_assignment_locked,created_by,updated_by)
 VALUES(fixture,'source:'||operation_write,'source','BUS_4X4','Department 138 write guard',1.25,true,actor,actor)
 RETURNING adjustment_id INTO adjustment_write;
 rejected:=false;
 BEGIN
  UPDATE public.vehicle_workshop_line_adjustments SET stage_code='FITTING',version=version+1
  WHERE adjustment_id=adjustment_write;
 EXCEPTION WHEN check_violation THEN
  IF SQLERRM<>'department_138_requires_bus_4x4' THEN RAISE; END IF;
  rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'department138_invalid_update_accepted'; END IF;
 UPDATE public.vehicle_workshop_line_adjustments SET active=false,stage_code='FITTING',version=version+1
 WHERE adjustment_id=adjustment_write;
 rejected:=false;
 BEGIN
  UPDATE public.vehicle_workshop_line_adjustments SET active=true,version=version+1 WHERE adjustment_id=adjustment_write;
 EXCEPTION WHEN check_violation THEN
  IF SQLERRM<>'department_138_requires_bus_4x4' THEN RAISE; END IF;
  rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'department138_invalid_reactivation_accepted'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(fixture)) l
  WHERE l->>'source_line_id'=operation_write::text AND (l->>'active')::boolean)
 THEN RAISE EXCEPTION 'removed_department138_operation_resurrected'; END IF;

 UPDATE public.vehicle_workshop_line_adjustments SET stage_code='FITTING',version=version+1 WHERE adjustment_id=adjustment139;
 SELECT l INTO STRICT actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(fixture)) l
 WHERE l->>'source_line_id'=operation139::text;
 IF actual->>'stage_code' IS DISTINCT FROM 'FITTING' OR (actual->>'estimated_hours')::numeric IS DISTINCT FROM 4.5::numeric
 THEN RAISE EXCEPTION 'department139_valid_station_update_rejected_or_altered'; END IF;
 IF fixture_source_before IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(o) ORDER BY o.operation_id)
    FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=fixture)
  OR evidence_before IS DISTINCT FROM (SELECT to_jsonb(e) FROM public.pdc_pilbara_service_import_rows e WHERE e.evidence_id=evidence)
  OR before_bookings IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') FROM public.workshop_bookings b)
  OR before_progress IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.booking_id,p.line_identity),'[]') FROM pdc_fitter_private.operation_progress p)
 THEN RAISE EXCEPTION 'department138_test_changed_source_bookings_or_progress'; END IF;
END $test$;

SELECT 'PASS: Dept138 canonical/manual/pending/board routing; Dept139 mixed-vehicle choices unchanged; hours, sources, bookings and progress preserved; invalid insert/update/reactivation rejected; all fixtures roll back' AS result;
ROLLBACK;
