BEGIN;
CREATE TEMP TABLE edge_results(name text,result jsonb);
DO $test$
#variable_conflict use_column
DECLARE actor record; rows jsonb; x jsonb; source_rows jsonb; pre jsonb; app jsonb; readback jsonb; sh text; v uuid; details jsonb; failed boolean;
BEGIN
 SELECT i.auth_user_id,i.normalized_email INTO STRICT actor FROM public.pdc_email_ai_successor_runtime_identities i JOIN public.pdc_user_roles r ON r.auth_user_id=i.auth_user_id
 WHERE i.active AND i.revoked_at IS NULL AND i.environment='staging' AND r.active AND r.role='viewer' AND r.account_status='approved' AND i.identity_purpose='pdc_email_ai_transaction_successor';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.normalized_email,'role','authenticated')::text,true);
 x:=jsonb_build_object('department','139','stock_number','U99123456','repair_order_number','J139V5FIXTURE','original_line_number',1,'operation_description','Pre-Delivery (Commercial)',
 'source_estimated_hours',0,'proposed_station','FITTING','customer_name','Tune Only Customer','vehicle_description','Isuzu D-Max fixture','vin','JH4KA7650MC100001','parts_on_backorder_raw','Yes','purchase_order_number','PO-NEW-123',
 'workbook_sha256',repeat('a',64),'raw_row',jsonb_build_object('Dept','139','fixture',true,'parent_attachment_sha256',repeat('a',64)));
 rows:=jsonb_build_array(x);sh:=encode(extensions.digest(convert_to(rows::text,'UTF8'),'sha256'),'hex');
 pre:=public.pdc_pilbara_service_preview_v1(rows,sh,'daily-v5-new-stock-preview');
 IF pre->>'apply_allowed'<>'true' THEN RAISE EXCEPTION 'new Stock preview failed: %',pre; END IF;
 app:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,sh,'daily-v5-new-stock-apply');
 IF app->>'ok'<>'true' THEN RAISE EXCEPTION 'new Stock apply failed: %',app; END IF;
 SET CONSTRAINTS ALL IMMEDIATE;
 SELECT id INTO STRICT v FROM public.vehicles WHERE stock_number='U99123456';
 details:=public.pdc_new_vehicle_review_row(v);
 IF details->>'customer_name'<>'Tune Only Customer' OR details->>'vehicle_description'<>'Isuzu D-Max fixture' OR details->>'vin'<>'JH4KA7650MC100001' OR details->>'status'<>'pending'
 OR EXISTS(SELECT 1 FROM public.vehicles WHERE id=v AND (visible_on_board OR current_location<>'Yard Hold'))
 OR (details#>>'{operations,0,estimated_hours}')::numeric<>1 THEN RAISE EXCEPTION 'new vehicle fields/state failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vehicle_parts_updates WHERE vehicle_id=v AND parts_ordered AND NOT parts_received AND worst_eta IS NULL) THEN RAISE EXCEPTION 'new PO not orange'; END IF;
 INSERT INTO edge_results VALUES('new_external_stock',jsonb_build_object('pending',true,'hidden',true,'tune_customer',true,'tune_vehicle',true,'vin_retained',true,'one_hour_pd',true,'ordered_without_eta',true));
 -- VIN cannot bind another Stock or silently change for the same Stock.
 rows:=jsonb_build_array(x||jsonb_build_object('stock_number','U99123457'));sh:=encode(extensions.digest(convert_to(rows::text,'UTF8'),'sha256'),'hex');
 pre:=public.pdc_pilbara_service_preview_v1(rows,sh,'daily-v5-duplicate-vin-test');
 IF pre->>'apply_allowed'<>'false' THEN RAISE EXCEPTION 'duplicate VIN allowed'; END IF;
 rows:=jsonb_build_array(x,x||jsonb_build_object('original_line_number',2,'operation_description','Battery isolator','vin','JH4KA7650MC100002'));sh:=encode(extensions.digest(convert_to(rows::text,'UTF8'),'sha256'),'hex');
 pre:=public.pdc_pilbara_service_preview_v1(rows,sh,'daily-v5-conflicting-vins-test');
 IF pre->>'code'<>'conflicting_stock_vin_evidence' THEN RAISE EXCEPTION 'conflicting VIN headers allowed'; END IF;
 rows:=jsonb_build_array(x,x||jsonb_build_object('original_line_number',2,'operation_description','Battery isolator','stock_number','','customer_name','Different Customer'));sh:=encode(extensions.digest(convert_to(rows::text,'UTF8'),'sha256'),'hex');
 pre:=public.pdc_pilbara_service_preview_v1(rows,sh,'daily-v5-conflicting-customers-test');
 IF pre->>'apply_allowed'<>'false' THEN RAISE EXCEPTION 'conflicting Tune customers allowed'; END IF;
 -- Manual PO/ETA rule is unchanged unless bound to genuine Tune PO evidence.
 failed:=false;
 BEGIN INSERT INTO public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,updated_by) VALUES(v,true,true,false,actor.auth_user_id);
 EXCEPTION WHEN check_violation THEN failed:=true; END;
 IF NOT failed THEN RAISE EXCEPTION 'unbound no-ETA bypass'; END IF;
 app:=public.pdc_pilbara_service_apply_v1('b6abf3db-e027-450b-9bc6-6ea015115727','056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814','daily-v5-legacy-replay-test');
 IF app->>'replay'<>'true' OR app->>'apply_batch_id'<>'5b81f662-47ad-4e68-8c95-59c3a28c6459' THEN RAISE EXCEPTION 'old receipt replay broken'; END IF;
 -- Current linked Navision details override the blank canonical intake fields.
 SELECT id INTO v FROM public.vehicles WHERE stock_number='13070889' AND deleted_at IS NULL;
 details:=public.pdc_new_vehicle_review_row(v);
 IF details->>'customer_name'<>'The Trustee for OSBORNE TRUCK' OR details->>'vehicle_description' NOT LIKE 'HiLux%' OR details->>'details_source'<>'microsoft_navision' THEN RAISE EXCEPTION 'Navision display missing'; END IF;
 PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
 IF public.pdc_pilbara_service_preview_v1(rows,sh,'daily-v5-anon-denied-test')->>'code'<>'not_authorized' THEN RAISE EXCEPTION 'unauthorized preview allowed'; END IF;
 IF has_function_privilege('authenticated','public.pdc_tune_vehicle_details_v5(uuid)','EXECUTE') OR has_function_privilege('authenticated','public.pdc_apply_tune_vehicle_fields_v5(uuid,uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'internal helper exposed'; END IF;
 INSERT INTO edge_results VALUES('guards',jsonb_build_object('duplicate_vin_blocked',true,'conflicting_vin_blocked',true,'conflicting_customer_blocked',true,'manual_eta_rule_preserved',true,'legacy_replay',true,'navision_details',true,'unauthorized_denied',true));
END $test$;
SELECT * FROM edge_results;
ROLLBACK;
