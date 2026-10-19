BEGIN;
DO $guard$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'Disposable loopback database required'; END IF; END $guard$;
-- APPLY CANDIDATE MIGRATION HERE.
CREATE TEMP TABLE review_protected_bookings AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b;
SELECT pdc_operation_updates_private.remember_ai_routing_20261019('139','SYNTHETIC REVIEW WIRING','ELECTRICAL',1.5,0.99,'Synthetic reviewed wiring estimate for isolated regression only');
SELECT pdc_operation_updates_private.remember_ai_routing_20261019('139','SYNTHETIC REVIEW SUPPLIER','SUBLET',NULL,0.99,'Synthetic external supplier work for isolated regression only');
SELECT pdc_operation_updates_private.remember_ai_routing_20261019('139','SYNTHETIC REVIEW NOTE','JOB_CARD_NOTES',0,0.99,'Synthetic delivery note for isolated regression only');
SELECT pdc_operation_updates_private.remember_ai_routing_20261019('138','SYNTHETIC REVIEW STEERING','BUS_MECHANICAL',4,0.99,'Synthetic reviewed steering repair estimate for isolated regression only');
DO $checks$ DECLARE l jsonb; x jsonb; flag text; BEGIN
 l:='{"department":"139","description":"SYNTHETIC REVIEW WIRING","stage_code":"UNALLOCATED_MAPPING_REVIEW","work_category":"UNALLOCATED_MAPPING_REVIEW","estimated_hours":0,"source_estimated_hours":0,"active":true,"completed":false,"rejected":false,"line_identity":"synthetic-review-wire","job_card_number":"TEST-JOB"}';
 x:=pdc_work_categories_private.route_import_line_20261017(l,false);
 IF x->>'stage_code'<>'ELECTRICAL' OR (x->>'estimated_hours')::numeric<>1.5 OR x->>'hours_provenance'<>'ai_estimate' OR x->>'source_estimated_hours'<>'0' OR x->>'line_identity'<>l->>'line_identity' THEN RAISE EXCEPTION 'fallback_or_source_identity_failed'; END IF;
 x:=pdc_work_categories_private.route_import_line_20261017(l||'{"estimated_hours":2.75,"source_estimated_hours":2.75,"hours_provenance":"source_explicit"}',false);
 IF (x->>'estimated_hours')::numeric<>2.75 OR x->>'hours_provenance'<>'source_explicit' THEN RAISE EXCEPTION 'source_hours_not_authoritative'; END IF;
 x:=pdc_work_categories_private.route_import_line_20261017(l,true);
 IF x IS DISTINCT FROM l THEN RAISE EXCEPTION 'preserved_line_changed'; END IF;
 FOREACH flag IN ARRAY ARRAY['completed','rejected'] LOOP
  x:=l||jsonb_build_object(flag,true);
  IF pdc_work_categories_private.route_import_line_20261017(x,false) IS DISTINCT FROM x THEN RAISE EXCEPTION 'history_changed'; END IF;
 END LOOP;
 x:=l||'{"active":false}';
 IF pdc_work_categories_private.route_import_line_20261017(x,false) IS DISTINCT FROM x THEN RAISE EXCEPTION 'inactive_changed'; END IF;
 x:=l||'{"stage_code":"FITTING","work_category":"FITTING"}';
 IF pdc_work_categories_private.route_import_line_20261017(x,false) IS DISTINCT FROM x THEN RAISE EXCEPTION 'existing_non_review_zero_hour_work_changed'; END IF;
 x:=pdc_work_categories_private.route_import_line_20261017(l||'{"description":"SYNTHETIC REVIEW SUPPLIER"}',false);
 IF x->>'stage_code'<>'SUBLET' OR (x->>'estimated_hours')::numeric<>0 THEN RAISE EXCEPTION 'external_work_got_invented_hours'; END IF;
 x:=pdc_work_categories_private.route_import_line_20261017(l||'{"description":"SYNTHETIC REVIEW NOTE"}',false);
 IF x->>'stage_code'<>'JOB_CARD_NOTES' OR x->>'information_only'<>'true' THEN RAISE EXCEPTION 'notes_misrouted'; END IF;
 x:=pdc_work_categories_private.route_import_line_20261017(l||'{"department":"138","description":"SYNTHETIC REVIEW STEERING"}',false);
 IF x->>'stage_code'<>'BUS_4X4' OR x->>'work_category'<>'BUS_MECHANICAL' OR (x->>'estimated_hours')::numeric<>4 THEN RAISE EXCEPTION 'department138_route_failed'; END IF;
 x:=pdc_work_categories_private.route_import_line_20261017(l||'{"department":"138","description":"SYNTHETIC REVIEW STEERING","stage_code":"BUS_4X4","work_category":"BUS_MECHANICAL"}',false);
 IF x->>'stage_code'<>'BUS_4X4' OR x->>'work_category'<>'BUS_MECHANICAL' OR (x->>'estimated_hours')::numeric<>4 OR x->>'source_estimated_hours'<>'0' THEN RAISE EXCEPTION 'department138_zero_hour_review_failed'; END IF;
 x:=pdc_work_categories_private.route_import_line_20261017(l||'{"description":"UNRECOGNISED SYNTHETIC REVIEW"}',false);
 IF x->>'stage_code'<>'UNALLOCATED_MAPPING_REVIEW' THEN RAISE EXCEPTION 'unknown_work_guessed'; END IF;
 IF has_function_privilege('anon','pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)','execute') OR has_function_privilege('authenticated','pdc_operation_updates_private.remember_ai_routing_20261019(text,text,text,numeric,numeric,text)','execute') THEN RAISE EXCEPTION 'private_worker_exposed'; END IF;
 IF EXISTS(SELECT 1 FROM review_protected_bookings p LEFT JOIN public.workshop_bookings b USING(id) WHERE p.row_data IS DISTINCT FROM to_jsonb(b)) THEN RAISE EXCEPTION 'existing_bookings_changed'; END IF;
END $checks$;
SELECT 'PASS: 14 routing, source-hour, preservation, department and permission checks' result;
ROLLBACK;

