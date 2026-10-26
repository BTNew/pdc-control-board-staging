-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run only inside the owned disposable loopback database.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '20s';
SET LOCAL TIME ZONE 'Australia/Perth';

-- APPLY CANDIDATE MIGRATIONS HERE FOR ROLLBACK REVIEW.
DO $guard$
BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR current_database()<>'pdc_restore_check'
 THEN RAISE EXCEPTION 'Disposable loopback test database required'; END IF;
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

CREATE TEMP TABLE ou_context(actor uuid, email text, friday date, batch uuid) ON COMMIT DROP;
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
 UPDATE public.pdc_user_roles SET role='operator',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=a AND email=e;
 INSERT INTO ou_context VALUES(a,e,(date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+18),b);
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(b,'pilbara_service_open_jobcards_v1',encode(extensions.digest(b::text,'sha256'),'hex'),repeat('b',64),'rollback-base-'||b,'apply',1,1,0,1,0,0,'{}',a,e);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
 PERFORM pg_temp.ou_assert(public.workshop_is_planner_operator(),'Synthetic operator is authorized');
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

CREATE FUNCTION pg_temp.ou_bay(tag text, stage text, category text DEFAULT 'BUS_MECHANICAL') RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE b uuid:=gen_random_uuid(); sid uuid; number integer; existing uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage AND active;
 IF stage='BUS_4X4' THEN
  number:=CASE category WHEN 'BUS_ELECTRICAL' THEN 8 WHEN 'BUS_QA' THEN 7 WHEN 'BUS_ACCESSORIES' THEN 10 ELSE 4 END;
  SELECT id INTO existing FROM public.workshop_bays WHERE stage_id=sid AND bay_number=number AND code LIKE 'OU-%';
  IF existing IS NOT NULL THEN RETURN existing; END IF;
  -- Owned loopback only: relocate the copied bay number, retaining its bookings unchanged.
  UPDATE public.workshop_bays SET bay_number=1000+number WHERE stage_id=sid AND bay_number=number;
 END IF;
 INSERT INTO public.workshop_bays(id,stage_id,code,display_name,is_active)
 VALUES(b,sid,'OU-'||b,'Rollback fixture '||tag,true);
 UPDATE public.workshop_bays SET bay_number=coalesce(number,(SELECT coalesce(max(bay_number),0)+1 FROM public.workshop_bays WHERE stage_id=sid)) WHERE id=b;
 INSERT INTO ou_refs VALUES('bay-'||tag,b);
 RETURN b;
END $fn$;

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1, dept text DEFAULT '139', description text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department',dept,'operation_description',coalesce(description,'Fixture work '||stage||' line '||line_no),'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station',stage,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{}','insert','rollback_original',vid);
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 VALUES(op,'pilbara_service_open_jobcards_v1',v.stock_number,v.job_card_number,line_no,line_no,vid,p->>'operation_description',hrs,hrs,'source_explicit','review','Review',repeat('c',64),ev,dept,stage);
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
 mins:=CASE WHEN state IN('queued','planned') THEN public.workshop_capacity_duration_minutes(pdc_work_categories_private.minutes(bid,vid,sid),bay) ELSE pdc_work_categories_private.minutes(bid,vid,sid) END;
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;



-- Exercise the real r538 AFTER progress trigger and public helper with no
-- authenticated browser actor. All inserted history belongs to synthetic data.
DO $management$
DECLARE v uuid; follower_v uuid; bay uuid; b uuid; follower uuid; extra_op uuid; tech uuid:=gen_random_uuid();
 a uuid; t timestamptz; before_rows jsonb; source_before jsonb; r jsonb; line jsonb; d jsonb; history_before bigint;
BEGIN
 SELECT actor INTO a FROM ou_context;
 v:=pg_temp.ou_vehicle('management-root');follower_v:=pg_temp.ou_vehicle('management-follower');
 bay:=pg_temp.ou_bay('management-root','HOIST');
 PERFORM pg_temp.ou_operation(v,'HOIST',1);extra_op:=pg_temp.ou_operation(v,'FITTING',5,2);
 PERFORM pg_temp.ou_operation(follower_v,'HOIST',1);
 t:=((date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+182)+time '07:00') AT TIME ZONE 'Australia/Perth';
 b:=pg_temp.ou_booking('management-root',v,'HOIST',bay,t,'planned');
 UPDATE public.workshop_bookings SET status='started',actual_start_at=t,version=version+1 WHERE id=b;
 follower:=pg_temp.ou_booking('management-follower',follower_v,'HOIST',bay,t+interval '2 hours');
 INSERT INTO public.workshop_technicians(id,name,role_type,active,can_fit_stages)
 VALUES(tech,'Rollback management technician '||tech,'technician',true,ARRAY['HOIST','FITTING']);
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT b,tech,'primary',a,scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=b;
 d:=public.get_fitter_job(tech,b);
 SELECT x INTO line FROM jsonb_array_elements(d->'lines') x WHERE x->>'line_identity'='source:'||extra_op;
 PERFORM pg_temp.ou_assert(line->>'scope_hash' IS NOT NULL,'Management fixture uses authentic synthetic line identity and scope');
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO before_rows FROM public.workshop_bookings x WHERE id IN(b,follower);
 SELECT to_jsonb(x) INTO source_before FROM public.pdc_pilbara_service_operations x WHERE operation_id=extra_op;
 SELECT count(*) INTO history_before FROM public.workshop_booking_history WHERE booking_id IN(b,follower);
 PERFORM set_config('request.jwt.claims','',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','',true);
 PERFORM set_config('request.jwt.claim.email','',true);
 PERFORM pg_temp.ou_assert(auth.uid() IS NULL AND pdc_codex_intake_private.management_connection(),'Trusted management connection has no browser actor');
 -- The copied progress row retains its original named author; trigger history
 -- must correctly record the present system caller as NULL, never impersonate it.
 INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
 VALUES(b,'source:'||extra_op,line->>'scope_hash',true,'Owned management trigger fixture',tech,a);
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=360 AND status='started' AND scheduled_start_at=t AND actual_start_at=t
  AND scheduled_end_at=public.workshop_add_operational_minutes(t,360) FROM public.workshop_bookings WHERE id=b),
  'Actual progress trigger extends running root with null browser actor');
 PERFORM pg_temp.ou_assert((SELECT f.scheduled_start_at>=x.scheduled_end_at FROM public.workshop_bookings f,public.workshop_bookings x WHERE f.id=follower AND x.id=b),
  'Management progress trigger cascades planned follower');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(before_rows) old
  JOIN public.workshop_bookings x ON x.id=(old->>'id')::uuid WHERE x.updated_by IS DISTINCT FROM (old->>'updated_by')::uuid),
  'Management cascade preserves each row previous named updater');
 PERFORM pg_temp.ou_assert((SELECT count(*)=2 FROM public.audit_events
  WHERE row_id IN(b,follower) AND table_name='workshop_bookings' AND metadata->>'source'='running_growth_cascade_20261026'
   AND metadata->>'trigger_source'='cross_station_538' AND metadata->>'actor_kind'='system' AND actor_id IS NULL
   AND jsonb_typeof(before_data)='object' AND jsonb_typeof(after_data)='object' AND before_data IS DISTINCT FROM after_data)
  AND EXISTS(SELECT 1 FROM public.audit_events WHERE row_id=b AND metadata->>'source'='cross_station_538' AND actor_id IS NULL),
  'Management trigger audit explicitly records system actor and source');
 PERFORM pg_temp.ou_assert((SELECT count(*)=history_before FROM public.workshop_booking_history WHERE booking_id IN(b,follower)),
  'System reconciliation never invents a staff history actor');
 r:=public.workshop_extend_running_booking_538(b,'management_repeat_proof',NULL);
 PERFORM pg_temp.ou_assert(r->>'extended'='false','Actual public helper management retry does not double count work',r);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=source_before FROM public.pdc_pilbara_service_operations x WHERE operation_id=extra_op),
  'Management growth preserves original source line and hours');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings x ON x.id=o.id WHERE to_jsonb(x) IS DISTINCT FROM o.row_data),
  'Management proof preserves copied operational bookings');
END $management$;
SELECT jsonb_build_object('scenario','actual management progress trigger and helper','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK;
