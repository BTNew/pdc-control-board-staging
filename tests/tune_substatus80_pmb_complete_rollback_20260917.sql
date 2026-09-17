DO $outer$ DECLARE n integer; checks jsonb; BEGIN
 BEGIN
 EXECUTE $fixture$CREATE TEMP TABLE ou_context(actor uuid, email text, friday date, batch uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE ou_source_order;
CREATE TEMP TABLE ou_refs(name text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ou_results(name text PRIMARY KEY, status text, evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE ou_original_bookings AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b;
CREATE TEMP TABLE ou_original_vehicles AS SELECT id,to_jsonb(v) row_data FROM public.vehicles v;

CREATE FUNCTION pg_temp.ou_assert(pass boolean, label text, evidence jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO ou_results VALUES(label,'PASS',evidence);
END $fn$;

DO $setup$
DECLARE a uuid:=gen_random_uuid(); e text; b uuid:=gen_random_uuid();
BEGIN
 e:='operation-update-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',e,clock_timestamp(),'{"provider":"email","providers":["email"]}','{"full_name":"Temporary operation update rollback fixture"}',clock_timestamp(),clock_timestamp());

 INSERT INTO ou_context VALUES(a,e,(date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+18),b);
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 contract_revision,source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(b,'pilbara_service_open_jobcards_v1',encode(extensions.digest(b::text,'sha256'),'hex'),repeat('b',64),'rollback-base-'||b,'apply','pmg_stock_v5',1,1,0,1,0,0,'{}',a,e);
END $setup$;

CREATE FUNCTION pg_temp.ou_vehicle(tag text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid:=gen_random_uuid(); stock text:='OU-'||substr(v::text,1,8); actor_id uuid;
BEGIN
 SELECT actor INTO actor_id FROM ou_context;
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,current_location,visible_on_board,
 source_system,source_record_id,source_payload,created_by,updated_by)
 VALUES(v,'operation-update-rollback-'||v,stock,'OU-JC-'||substr(v::text,1,8),'ROLLBACK FIXTURE '||tag,'Synthetic vehicle','PMB',true,
 'operation_update_rollback_20260913',v::text,'{"rollback_fixture":true}',actor_id,actor_id);
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,first_job_card,approved_at,approved_by)
 VALUES(v,'approved','OU-JC-'||substr(v::text,1,8),clock_timestamp(),actor_id);
 INSERT INTO ou_refs VALUES('vehicle-'||tag,v);
 RETURN v;
END $fn$;

CREATE FUNCTION pg_temp.ou_bay(tag text, stage text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE b uuid:=gen_random_uuid(); sid uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage AND active;
 INSERT INTO public.workshop_bays(id,stage_id,code,display_name,is_active)
 VALUES(b,sid,'OU-'||b,'Rollback fixture '||tag,true);
 INSERT INTO ou_refs VALUES('bay-'||tag,b);
 RETURN b;
END $fn$;

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department','139','operation_description','Fixture work '||stage||' line '||line_no,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station',stage,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,jsonb_build_object('Company','01','Division','1','Sub Status','80','Key Number','513','Parts Location','05C1A','source_snapshot_at','2026-09-15T04:00:00Z')||coalesce(nullif(current_setting('pdc.substatus_test_raw',true),''),'{}')::jsonb,'insert','rollback_original',vid);
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 VALUES(op,'pilbara_service_open_jobcards_v1',v.stock_number,v.job_card_number,line_no,line_no,vid,p->>'operation_description',hrs,hrs,'source_explicit','review','Review',repeat('c',64),ev,'139',stage);
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed) VALUES(vid,wk,true,false)
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true;
 RETURN op;
END $fn$;

CREATE FUNCTION pg_temp.ou_booking(tag text, vid uuid, stage text, bay uuid, start_at timestamptz, state public.workshop_booking_status DEFAULT 'planned')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE bid uuid:=gen_random_uuid(); sid uuid; mins integer; actor_id uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage;
 SELECT actor INTO actor_id FROM ou_context;
 mins:=public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid);
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;


DO $test$
DECLARE v uuid; a uuid; b uuid; pre uuid:=gen_random_uuid(); op uuid; wb uuid; f date; prior jsonb; src jsonb; part jsonb; k uuid;
BEGIN
 SELECT actor,batch,friday INTO a,b,f FROM ou_context;
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,contract_revision,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 SELECT pre,importer_version,source_hash,request_hash,'status80-preview-'||pre,'preview','pmg_stock_v5',2,2,0,1,0,0,'{}',created_by,created_actor
 FROM public.pdc_pilbara_service_import_batches WHERE batch_id=b;
 v:=pg_temp.ou_vehicle('80-positive');
 UPDATE ou_context SET batch=pre;
 op:=pg_temp.ou_operation(v,'FITTING',1,1);
 PERFORM pg_temp.ou_operation(v,'SUBLET',0,2);
 UPDATE ou_context SET batch=b;
 SELECT to_jsonb(o) INTO src FROM public.pdc_pilbara_service_operations o WHERE operation_id=op;
 wb:=pg_temp.ou_booking('80-planned',v,'FITTING',pg_temp.ou_bay('80','FITTING'),(f::text||' 08:00 Australia/Perth')::timestamptz);
 SELECT to_jsonb(w) INTO prior FROM public.workshop_bookings w WHERE id=wb;
 INSERT INTO pdc_parts_private.jobs(vehicle_id,source_system,company,division,stock_number,ro_number,departments,service_seen_at)
 SELECT v,'tune_pmg','01','1',stock_number,job_card_number,ARRAY['139'],clock_timestamp() FROM public.vehicles WHERE id=v;
 SELECT to_jsonb(j) INTO part FROM pdc_parts_private.jobs j WHERE vehicle_id=v;
 UPDATE public.pdc_new_vehicle_reviews SET status='pending',approved_at=NULL,approved_by=NULL WHERE vehicle_id=v;
 UPDATE public.vehicles SET visible_on_board=false,location_override='PMB',location_override_reason='Prior arrival' WHERE id=v;
 PERFORM pdc_codex_intake_private.capture_service_status(pre,b);
 PERFORM pg_temp.ou_assert((SELECT current_location='QC' AND visible_on_board AND workshop_status='completed' AND qc_completed_at IS NULL AND rft_transferred_at IS NULL AND location_override IS NULL FROM public.vehicles WHERE id=v),'80 sends PMB work to QC without QC signoff or RFT');
 PERFORM pg_temp.ou_assert((SELECT status='closed' AND closure_reason LIKE '%Sub Status 80%' FROM public.pdc_new_vehicle_reviews WHERE vehicle_id=v),'80 removes completed work from New Vehicles');
 PERFORM pg_temp.ou_assert((SELECT completed FROM public.vehicle_work_items WHERE vehicle_id=v AND work_key='fitting'),'PMB workshop requirement completed');
 PERFORM pg_temp.ou_assert((SELECT NOT completed FROM public.vehicle_work_items WHERE vehicle_id=v AND work_key='sublet'),'Sublet work not marked returned');
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(j)=part FROM pdc_parts_private.jobs j WHERE vehicle_id=v),'Parts record unchanged and open');
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(o)=src FROM public.pdc_pilbara_service_operations o WHERE operation_id=op),'Original operation and Tune hours unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.pdc_qc_operation_completions_379 WHERE vehicle_id=v),'Inspector checklist not ticked');
 PERFORM pg_temp.ou_assert((SELECT status='completed' AND to_jsonb(w)-ARRAY['status','version','updated_by','updated_at']=prior-ARRAY['status','version','updated_by','updated_at'] FROM public.workshop_bookings w WHERE id=wb),'Booking completed with all planned and actual times preserved');
 PERFORM pg_temp.ou_assert((SELECT count(*)=1 FROM pdc_codex_intake_private.tune_pmb_complete_receipts WHERE vehicle_id=v),'Distinct PMB completion receipt recorded');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id=v),'80 is not checkout authority');
 SELECT to_jsonb(x) INTO prior FROM public.vehicles x WHERE id=v;
 PERFORM pdc_codex_intake_private.capture_service_status(pre,b);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=prior FROM public.vehicles x WHERE id=v),'Repeated 80 does not change inspected vehicle');
 UPDATE public.vehicles SET current_location='PMB',pmb_stoppage_started_at=clock_timestamp(),pmb_stoppage_reason='QC rework' WHERE id=v;
 SELECT to_jsonb(x) INTO prior FROM public.vehicles x WHERE id=v;
 PERFORM pdc_codex_intake_private.capture_service_status(pre,b);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=prior FROM public.vehicles x WHERE id=v),'Consumed 80 cannot erase later rework');

 FOR k IN SELECT pg_temp.ou_vehicle(label) FROM unnest(ARRAY['blank','invalid','legacy99','older','conflict','stoppage','deleted','qc','99-wins','newer-sibling']) label LOOP
  SELECT to_jsonb(x) INTO prior FROM public.vehicles x WHERE id=k;
  PERFORM set_config('pdc.substatus_test_raw',CASE
   WHEN prior->>'customer_name' LIKE '%blank' THEN '{"Sub Status":""}'
   WHEN prior->>'customer_name' LIKE '%invalid' THEN '{"Sub Status":"All"}'
   WHEN prior->>'customer_name' LIKE '%legacy99' THEN '{"Sub Status":"22","Status":"99"}'
   ELSE '{}' END,true);
  UPDATE ou_context SET batch=pre;
  op:=pg_temp.ou_operation(k,'FITTING',1,1);
  UPDATE ou_context SET batch=b;
  SELECT to_jsonb(x) INTO prior FROM public.vehicles x WHERE id=k;
  IF prior->>'customer_name' LIKE '%older' OR prior->>'customer_name' LIKE '%conflict' THEN
   INSERT INTO pdc_codex_intake_private.service_job_status(company,division,ro_number,vehicle_id,stock_number,sub_status,snapshot_at,batch_id)
   SELECT '01','1',job_card_number,k,stock_number,'22',CASE WHEN customer_name LIKE '%older' THEN '2026-09-16T04:00Z' ELSE '2026-09-15T04:00Z' END::timestamptz,b FROM public.vehicles WHERE id=k;
  ELSIF prior->>'customer_name' LIKE '%stoppage' THEN
   UPDATE public.vehicles SET pmb_stoppage_started_at=clock_timestamp(),pmb_stoppage_reason='Owner hold' WHERE id=k;
  ELSIF prior->>'customer_name' LIKE '%deleted' THEN
   UPDATE public.vehicles SET deleted_at=clock_timestamp(),visible_on_board=false,lifecycle_state='deleted' WHERE id=k;
  ELSIF prior->>'customer_name' LIKE '%qc' THEN
   UPDATE public.vehicles SET current_location='QC' WHERE id=k;
  ELSIF prior->>'customer_name' LIKE '%99-wins' THEN
   INSERT INTO pdc_codex_intake_private.service_job_status(company,division,ro_number,vehicle_id,stock_number,sub_status,snapshot_at,batch_id)
   SELECT '01','1',job_card_number||'-99',k,stock_number,'99','2026-09-15T04:00Z',b FROM public.vehicles WHERE id=k;
  ELSIF prior->>'customer_name' LIKE '%newer-sibling' THEN
   INSERT INTO pdc_codex_intake_private.service_job_status(company,division,ro_number,vehicle_id,stock_number,sub_status,snapshot_at,batch_id)
   SELECT '01','1',job_card_number||'-newer',k,stock_number,'22','2026-09-16T04:00Z',b FROM public.vehicles WHERE id=k;
  END IF;
  SELECT to_jsonb(x) INTO prior FROM public.vehicles x WHERE id=k;
  PERFORM pdc_codex_intake_private.capture_service_status(pre,b);
  IF prior->>'customer_name' LIKE '%99-wins' THEN
   PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id=k) AND NOT EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_pmb_complete_receipts WHERE vehicle_id=k),'99 keeps precedence over 80');
  ELSE
   PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=prior FROM public.vehicles x WHERE id=k),'Protected case: '||(prior->>'customer_name'));
  END IF;
 END LOOP;
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles old FULL JOIN public.vehicles veh ON veh.id=old.id WHERE old.id IS NOT NULL AND to_jsonb(veh) IS DISTINCT FROM old.row_data),'All real vehicles unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings old FULL JOIN public.workshop_bookings w ON w.id=old.id WHERE old.id IS NOT NULL AND to_jsonb(w) IS DISTINCT FROM old.row_data),'All real bookings unchanged');
END $test$;
$fixture$;
 SELECT count(*) INTO n FROM ou_results WHERE status='PASS';
 SELECT jsonb_agg(to_jsonb(r) ORDER BY name) INTO checks FROM ou_results r;
 IF n<24 THEN RAISE EXCEPTION 'Insufficient assertions: %',n; END IF;
 RAISE NOTICE 'Sub Status 80 checks passed: %; rolling back all fixtures',n;
 RAISE EXCEPTION USING ERRCODE='Z0080',MESSAGE='rollback successful test fixtures';
 EXCEPTION WHEN SQLSTATE 'Z0080' THEN NULL;
 END;
 PERFORM set_config('pdc.status80_test_result',checks::text,true);
END $outer$;

