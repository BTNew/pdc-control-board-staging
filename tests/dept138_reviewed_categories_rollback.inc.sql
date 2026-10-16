-- Disposable-only regression for owner-reviewed line routing; all fixtures roll back.
DO $owner_review$
DECLARE v uuid; op uuid; op2 uuid; key text; payload jsonb; r jsonb; j jsonb; claims text; blocked boolean; stock text;
BEGIN
 claims:=current_setting('request.jwt.claims',true);
 v:=pg_temp.ou_vehicle('owner-reviewed-categories');
 op:=pg_temp.ou_operation(v,'BUS_4X4',1.25,1,'138','LED Lightbar - For Bull Bar');
 op2:=pg_temp.ou_operation(v,'BUS_4X4',0,2,'138','Final vehicle readiness review');
 SELECT stock_number INTO stock FROM public.vehicles WHERE id=v;
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,manual_assignment_locked,created_by,updated_by)
 VALUES(v,'source:'||op2,'source','BUS_4X4','Final vehicle readiness review',0,true,(SELECT actor FROM ou_context),(SELECT actor FROM ou_context));
 SELECT jsonb_agg(jsonb_build_object('vehicle_id',v,'stock',stock,'vehicle_version',(SELECT version FROM public.vehicles WHERE id=v),
 'expected_line',l,'category',CASE WHEN l->>'line_identity'='source:'||op THEN 'BUS_ELECTRICAL' ELSE 'BUS_QA' END,
 'reason','Owner reviewed exact description and physical work category; original staff/source hours retained'))
 INTO payload FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l;
 key:='owner-review-test-'||v;
 PERFORM set_config('request.jwt.claims','',true);
 r:=pdc_work_categories_private.apply_owner_review(key,'Synthetic owner request to categorise Department138 existing operation lines without changing hours',payload);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Owner review applies without impersonating a staff identity',r);
 PERFORM pg_temp.ou_assert((SELECT count(*) FROM jsonb_array_elements(r->'outcomes') x WHERE x->>'outcome'='category_applied')=2,'Reviewed two exact categories applied');
 SELECT l INTO j FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'line_identity'='source:'||op;
 PERFORM pg_temp.ou_assert(j->>'work_category'='BUS_ELECTRICAL' AND (j->>'estimated_hours')::numeric=1.25,'Bullbar-mounted light correctly electrical with original hours');
 SELECT l INTO j FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'line_identity'='source:'||op2;
 PERFORM pg_temp.ou_assert(j->>'work_category'='BUS_QA' AND j->>'zero_hour_task'='true' AND (j->>'estimated_hours')::numeric=0,'Owner QA zero remains exactly zero');
 PERFORM pg_temp.ou_assert((SELECT count(*) FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v)=1,'Owner route does not create staff adjustment rows');
 r:=pdc_work_categories_private.apply_owner_review(key,'Synthetic owner request to categorise Department138 existing operation lines without changing hours',payload);
 PERFORM pg_temp.ou_assert(r->>'replay'='true','Identical request reconciles idempotently');
 blocked:=false;
 BEGIN
  PERFORM pdc_work_categories_private.apply_owner_review(key,'Different authority long enough to exercise intent binding safely',payload);
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM='idempotency_intent_mismatch';END;
 PERFORM pg_temp.ou_assert(blocked,'Changed replay authority rejected');
 blocked:=false;
 BEGIN
  PERFORM pdc_work_categories_private.apply_owner_review(key||'-stale','Synthetic owner request to categorise Department138 existing operation lines without changing hours',payload);
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM='exact_department138_line_changed';END;
 PERFORM pg_temp.ou_assert(blocked,'Stale before projection rejected atomically');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM pdc_work_categories_private.owner_review_receipts WHERE request_key=key||'-stale'),'Stale review leaves no partial receipt');
 PERFORM set_config('request.jwt.claims',claims,true);
 UPDATE public.vehicle_workshop_line_adjustments SET estimated_hours=0.25,version=version+1,updated_at=clock_timestamp() WHERE vehicle_id=v AND line_key='source:'||op2;
 SELECT l INTO j FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'line_identity'='source:'||op2;
 PERFORM pg_temp.ou_assert(j->>'work_category'='BUS_QA' AND (j->>'estimated_hours')::numeric=0.25,'Later staff hour correction preserves reviewed category and staff hours');
 r:=public.set_vehicle_work_category(v,(SELECT version FROM public.vehicles WHERE id=v),'source:'||op,'BUS_ACCESSORIES',0);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Later legitimate staff category override remains available',r);
 PERFORM pg_temp.ou_assert((SELECT l->>'work_category' FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'line_identity'='source:'||op)='BUS_ACCESSORIES','Later explicit staff category wins');
 PERFORM set_config('request.jwt.claims','',true);
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('authenticated','pdc_work_categories_private.apply_owner_review(text,text,jsonb)','EXECUTE')
 AND NOT has_function_privilege('anon','pdc_work_categories_private.apply_owner_review(text,text,jsonb)','EXECUTE'),'Management reviewer unavailable to app roles');
 PERFORM set_config('request.jwt.claims',claims,true);
END $owner_review$;
DO $owner_boundaries$
DECLARE v uuid; op uuid; payload jsonb; r jsonb; claims text; blocked boolean; bay uuid; bid uuid; t timestamptz;
BEGIN
 claims:=current_setting('request.jwt.claims',true);
 v:=pg_temp.ou_vehicle('owner-wrong-department');
 op:=pg_temp.ou_operation(v,'FITTING',1,1,'139','Non scoped fitting');
 SELECT jsonb_agg(jsonb_build_object('vehicle_id',v,'stock',(SELECT stock_number FROM public.vehicles WHERE id=v),
 'vehicle_version',(SELECT version FROM public.vehicles WHERE id=v),'expected_line',l,'category','BUS_ELECTRICAL','reason','Scope negative test'))
 INTO payload FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l;
 PERFORM set_config('request.jwt.claims','',true);blocked:=false;
 BEGIN PERFORM pdc_work_categories_private.apply_owner_review('owner-scope-negative-'||v,'Synthetic scope boundary test requiring Department138 and preserving every other department',payload);
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM='exact_department138_line_changed';END;
 PERFORM pg_temp.ou_assert(blocked,'Department139 cannot enter owner138 backfill');
 PERFORM set_config('request.jwt.claims',claims,true);
 v:=pg_temp.ou_vehicle('owner-booked-stage');op:=pg_temp.ou_operation(v,'BUS_4X4',1,1,'138','Original mechanical task');
 bay:=pg_temp.ou_bay('owner-booking','BUS_4X4');
 SELECT (friday::timestamp+interval '6 hours') AT TIME ZONE 'Australia/Perth' INTO t FROM ou_context;
 bid:=pg_temp.ou_booking('owner-booking',v,'BUS_4X4',bay,t);
 SELECT jsonb_agg(jsonb_build_object('vehicle_id',v,'stock',(SELECT stock_number FROM public.vehicles WHERE id=v),
 'vehicle_version',(SELECT version FROM public.vehicles WHERE id=v),'expected_line',l,'category','SUBLET','reason','Owner review retains reserved physical work'))
 INTO payload FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l;
 PERFORM set_config('request.jwt.claims','',true);
 r:=pdc_work_categories_private.apply_owner_review('owner-booking-negative-'||v,'Synthetic owner request with existing whole-job booking preserved without cancellation',payload);
 PERFORM pg_temp.ou_assert(r->'outcomes'->0->>'outcome'='held_booking_scope','Reserved work does not silently move to another workshop',r);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM pdc_work_categories_private.owner_line_reviews WHERE vehicle_id=v),'Held reservation creates no category override');
 PERFORM set_config('request.jwt.claims',claims,true);
END $owner_boundaries$;

