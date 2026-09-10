BEGIN;
CREATE TEMP TABLE daily_before_ops AS SELECT operation_id,to_jsonb(o) body FROM public.pdc_pilbara_service_operations o;
CREATE TEMP TABLE daily_before_vehicles AS SELECT id,visible_on_board,current_location,lifecycle_state,qc_completed_at FROM public.vehicles;
CREATE TEMP TABLE daily_before_work AS SELECT id,to_jsonb(w) body FROM public.vehicle_work_items w WHERE lower(work_key)<>'parts';
CREATE TEMP TABLE daily_before_bookings AS SELECT id,to_jsonb(b) body FROM public.workshop_bookings b;
CREATE TEMP TABLE daily_before_completions AS SELECT vehicle_id,line_identity,to_jsonb(c) body FROM public.pdc_qc_operation_completions_379 c;
CREATE TEMP TABLE daily_results(name text,result jsonb);
DO $test$
#variable_conflict use_column
DECLARE actor record; rows jsonb; rows2 jsonb; pre jsonb; applied jsonb; replay jsonb; rb jsonb; sh text; sh2 text; e record; d jsonb; p record; v uuid; qty integer; status text;
BEGIN
 SELECT i.auth_user_id,i.normalized_email INTO STRICT actor FROM public.pdc_email_ai_successor_runtime_identities i
 JOIN public.pdc_user_roles r ON r.auth_user_id=i.auth_user_id WHERE i.active AND i.revoked_at IS NULL AND i.environment='staging' AND r.active AND r.role='viewer' AND r.account_status='approved' AND i.identity_purpose='pdc_email_ai_transaction_successor';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.normalized_email,'role','authenticated')::text,true);
 IF public.pdc_tune_parts_status_v5('[{"parts_on_backorder_raw":"No","purchase_order_number":"PO-old"}]')<>'green'
 OR public.pdc_tune_parts_status_v5('[{"parts_on_backorder_raw":"Yes"}]')<>'red'
 OR public.pdc_tune_parts_status_v5('[{"parts_on_backorder_raw":"Yes","purchase_order_number":"PO-1"}]')<>'orange'
 OR public.pdc_tune_parts_status_v5('[{"parts_on_backorder_raw":"No"},{"parts_on_backorder_raw":"Yes"},{"parts_on_backorder_raw":"Yes","purchase_order_number":"PO-1"}]')<>'red'
 OR public.pdc_tune_parts_status_v5('[{}]')<>'review'
 OR public.pdc_tune_parts_status_v5('[{"parts_on_backorder_raw":"No"},{}]')<>'review'
 THEN RAISE EXCEPTION 'parts truth table failed'; END IF;
 SELECT jsonb_agg(normalized_payload||jsonb_build_object('raw_row',raw_row,'customer_name','Tune Customer '||stock_number,'vehicle_description','Tune Vehicle '||stock_number,'parts_on_backorder_raw','No') ORDER BY source_order)
 INTO rows FROM public.pdc_pilbara_service_import_rows WHERE batch_id='cc508308-ad1e-453f-a431-595bead4de2b';
 sh:=encode(extensions.digest(convert_to(rows::text,'UTF8'),'sha256'),'hex');
 pre:=public.pdc_pilbara_service_preview_v1(rows,sh,'daily-v5-full-preview-test');
 IF pre->>'apply_allowed'<>'true' OR (pre->>'accepted_lines')::integer<>1395 THEN RAISE EXCEPTION 'full preview failed: %',pre; END IF;
 replay:=public.pdc_pilbara_service_preview_v1(rows,sh,'daily-v5-full-preview-test');
 IF replay->>'preview_batch_id'<>pre->>'preview_batch_id' OR replay->>'replay'<>'true' THEN RAISE EXCEPTION 'preview replay failed'; END IF;
 applied:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,sh,'daily-v5-full-apply-test');
 IF applied->>'ok'<>'true' THEN RAISE EXCEPTION 'full apply failed: %',applied; END IF;
 SET CONSTRAINTS ALL IMMEDIATE;
 rb:=public.pdc_pmg_intake_readback_v3((applied->>'apply_batch_id')::uuid);
 IF rb->>'ok'<>'true' OR jsonb_array_length(rb->'intake_evidence')<>121 THEN RAISE EXCEPTION 'readback failed: %',rb->>'code'; END IF;
 SELECT count(*) INTO qty FROM public.pdc_tune_intake_evidence_v5 WHERE batch_id=(applied->>'apply_batch_id')::uuid;
 IF qty<>121 THEN RAISE EXCEPTION 'wrong vehicle metadata count'; END IF;
 FOR e IN SELECT h.*,v.stock_number FROM public.pdc_tune_intake_evidence_v5 h JOIN public.vehicles v ON v.id=h.vehicle_id WHERE h.batch_id=(applied->>'apply_batch_id')::uuid LOOP
  d:=public.pdc_tune_vehicle_details_v5(e.vehicle_id);
  IF d->>'details_source'='microsoft_navision' THEN
   IF d->>'customer_name' LIKE 'Tune Customer%' OR d->>'vehicle_description' LIKE 'Tune Vehicle%' THEN RAISE EXCEPTION 'Tune replaced Navision'; END IF;
  ELSE
   IF d->>'customer_name'<>'Tune Customer '||e.stock_number OR d->>'vehicle_description'<>'Tune Vehicle '||e.stock_number THEN RAISE EXCEPTION 'Tune fallback missing'; END IF;
  END IF;
  SELECT * INTO p FROM public.vehicle_parts_updates WHERE vehicle_id=e.vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1;
  IF p.parts_received IS DISTINCT FROM true OR p.parts_ordered IS DISTINCT FROM false THEN RAISE EXCEPTION 'No backorder not green'; END IF;
 END LOOP;
 replay:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,sh,'daily-v5-full-apply-test');
 IF replay->>'apply_batch_id'<>applied->>'apply_batch_id' OR replay->>'replay'<>'true' OR (SELECT count(*) FROM public.pdc_tune_intake_evidence_v5 WHERE batch_id=(applied->>'apply_batch_id')::uuid)<>121 THEN RAISE EXCEPTION 'apply replay duplicated metadata'; END IF;
 INSERT INTO daily_results VALUES('full_file',jsonb_build_object('vehicles',qty,'operations',1395,'exact_replay',true));
 -- Repeated daily export changes Parts on the same operation identities.
 SELECT id INTO STRICT v FROM public.vehicles WHERE stock_number='IS51036977' AND deleted_at IS NULL;
 FOREACH status IN ARRAY ARRAY['red','orange','green'] LOOP
  SELECT jsonb_agg(x||jsonb_build_object('customer_name','Updated Tune Customer','parts_on_backorder_raw',CASE WHEN status='green' THEN 'No' ELSE 'Yes' END,'purchase_order_number',CASE WHEN status='orange' THEN 'PO-DAILY-123' END)) INTO rows2
  FROM jsonb_array_elements(rows) x WHERE x->>'stock_number'='IS51036977';
  sh2:=encode(extensions.digest(convert_to(rows2::text,'UTF8'),'sha256'),'hex');
  pre:=public.pdc_pilbara_service_preview_v1(rows2,sh2,'daily-v5-'||status||'-preview-test');
  IF pre->>'apply_allowed'<>'true' OR (pre#>>'{operations,insert}')::integer<>0 THEN RAISE EXCEPTION 'daily metadata preview failed: %',pre; END IF;
  applied:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,sh2,'daily-v5-'||status||'-apply-test');
  IF applied->>'ok'<>'true' THEN RAISE EXCEPTION 'daily metadata apply failed: %',applied; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  SELECT * INTO p FROM public.vehicle_parts_updates WHERE vehicle_id=v ORDER BY updated_at DESC,id DESC LIMIT 1;
  IF p.parts_received IS DISTINCT FROM (status='green') OR p.parts_ordered IS DISTINCT FROM (status='orange') THEN RAISE EXCEPTION 'daily parts update failed: %',status; END IF;
  IF public.pdc_tune_vehicle_details_v5(v)->>'customer_name'<>'Updated Tune Customer' THEN RAISE EXCEPTION 'daily customer update failed'; END IF;
 END LOOP;
 INSERT INTO daily_results VALUES('parts_changes',jsonb_build_object('red',true,'orange_without_invented_eta',true,'green',true,'no_duplicate_operations',true));
 IF EXISTS(SELECT 1 FROM daily_before_ops b FULL JOIN public.pdc_pilbara_service_operations o USING(operation_id) WHERE b.body IS DISTINCT FROM to_jsonb(o)) THEN RAISE EXCEPTION 'immutable operations changed'; END IF;
 IF EXISTS(SELECT 1 FROM daily_before_vehicles b JOIN public.vehicles v USING(id) WHERE b.visible_on_board IS DISTINCT FROM v.visible_on_board OR b.current_location IS DISTINCT FROM v.current_location OR b.lifecycle_state IS DISTINCT FROM v.lifecycle_state OR b.qc_completed_at IS DISTINCT FROM v.qc_completed_at) THEN RAISE EXCEPTION 'vehicle workflow changed'; END IF;
 IF EXISTS(SELECT 1 FROM daily_before_bookings b FULL JOIN public.workshop_bookings w USING(id) WHERE b.body IS DISTINCT FROM to_jsonb(w)) THEN RAISE EXCEPTION 'booking changed'; END IF;
 IF EXISTS(SELECT 1 FROM daily_before_completions b FULL JOIN public.pdc_qc_operation_completions_379 c USING(vehicle_id,line_identity) WHERE b.body IS DISTINCT FROM to_jsonb(c)) THEN RAISE EXCEPTION 'completion changed'; END IF;
 IF EXISTS(SELECT 1 FROM daily_before_work b FULL JOIN (SELECT * FROM public.vehicle_work_items WHERE lower(work_key)<>'parts') w USING(id) WHERE b.body IS DISTINCT FROM to_jsonb(w)) THEN RAISE EXCEPTION 'work item changed'; END IF;
END $test$;
SELECT * FROM daily_results;
ROLLBACK;
