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



CREATE FUNCTION pg_temp.rg_assignment(bid uuid, tech uuid, kind text DEFAULT 'secondary') RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT bid,tech,kind::public.workshop_assignment_type,auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=bid;
END $fn$;

CREATE FUNCTION pg_temp.rg_protected(kind text, bus boolean DEFAULT false) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v uuid; v2 uuid; bay uuid; bay2 uuid; b uuid; b2 uuid; t timestamptz;
 stage text:=CASE WHEN bus THEN 'BUS_4X4' ELSE 'HOIST' END; tech uuid:=gen_random_uuid(); provider uuid:=gen_random_uuid();
 mins integer:=360; before_rows jsonb; before_assignments jsonb; history_before bigint; failed boolean:=false; detail text; state text; r jsonb; label text;
BEGIN
 label:=stage||' '||kind;
 v:=pg_temp.ou_vehicle('protected-'||label);bay:=pg_temp.ou_bay('protected-'||label,stage);
 PERFORM pg_temp.ou_operation(v,stage,1,1,CASE WHEN bus THEN '138' ELSE '139' END,
  CASE WHEN bus THEN 'Coaster Bus 4x4 Conversion - 6 Speed 2.8' END);
 t:=((date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+182)+time '07:00') AT TIME ZONE 'Australia/Perth';
 IF bus THEN t:=pdc_bus_private.clock_next_minute(t,bay); END IF;
 IF kind='started' THEN
  bay2:=pg_temp.ou_bay('protected-other-'||label,'FITTING');PERFORM pg_temp.ou_operation(v,'FITTING',1,2);
  b2:=pg_temp.ou_booking('protected-other-'||label,v,'FITTING',bay2,public.workshop_add_operational_minutes(t,120),'started');
 ELSIF kind='stoppage' THEN
  v2:=pg_temp.ou_vehicle('protected-other-'||label);
  PERFORM pg_temp.ou_operation(v2,stage,1,1,CASE WHEN bus THEN '138' ELSE '139' END,
   CASE WHEN bus THEN 'Coaster Bus 4x4 Conversion - 6 Speed 2.8' END);
  IF bus THEN PERFORM pdc_work_categories_private.set_context(v2,stage,'{"work_category":"BUS_MECHANICAL"}'); END IF;
  b2:=pg_temp.ou_booking('protected-other-'||label,v2,stage,bay,public.workshop_add_operational_minutes(t,120),'started');
  PERFORM set_config('pdc.work_category','',true);
  UPDATE public.workshop_bookings SET status='stoppage',stoppage_reason='Owned copy protected fixture',
   stoppage_started_at=scheduled_start_at,version=version+1 WHERE id=b2;
 END IF;
 IF bus THEN PERFORM pdc_work_categories_private.set_context(v,stage,'{"work_category":"BUS_MECHANICAL"}'); END IF;
 b:=pg_temp.ou_booking('protected-root-'||label,v,stage,bay,t,'started');
 PERFORM set_config('pdc.work_category','',true);
 IF kind='admin' THEN
  INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
  SELECT stage_id,bay,'admin','Owned rollback block',t+interval '3 hours',t+interval '4 hours',60,auth.uid(),auth.uid() FROM public.workshop_bays WHERE id=bay;
 ELSIF kind='leave' THEN
  INSERT INTO public.workshop_technicians(id,name,role_type,active,can_fit_stages)
  VALUES(tech,'Rollback protected technician '||tech,'technician',true,ARRAY['HOIST','BUS_4X4']);
  PERFORM pg_temp.rg_assignment(b,tech,'secondary');
  -- Introduce leave after fixture assignment to verify the growth authority refuses.
  INSERT INTO public.workshop_settings(key,value) VALUES('technician_leave',jsonb_build_array(jsonb_build_object('technician_id',tech,'date',(t AT TIME ZONE 'Australia/Perth')::date)))
  ON CONFLICT(key) DO UPDATE SET value=public.workshop_settings.value||excluded.value;
 ELSIF kind='sublet' THEN
  INSERT INTO public.sublet_providers(id,name,created_by,updated_by) VALUES(provider,'Rollback provider '||provider,auth.uid(),auth.uid());
  INSERT INTO public.pdc_sublet_booking_instances(vehicle_id,vehicle_version,provider_id,provider_name,out_date,expected_return_date,created_by,updated_by)
  SELECT v,version,provider,'Rollback provider '||provider,(t AT TIME ZONE 'Australia/Perth')::date+1,
   (t AT TIME ZONE 'Australia/Perth')::date+2,auth.uid(),auth.uid() FROM public.vehicles WHERE id=v;
  mins:=1320;
 ELSIF kind='technician' THEN
  v2:=pg_temp.ou_vehicle('protected-tech-other-'||label);bay2:=pg_temp.ou_bay('protected-tech-other-'||label,'FITTING');
  PERFORM pg_temp.ou_operation(v2,'FITTING',1);
  b2:=pg_temp.ou_booking('protected-tech-other-'||label,v2,'FITTING',bay2,t+interval '2 hours','started');
  INSERT INTO public.workshop_technicians(id,name,role_type,active,can_fit_stages)
  VALUES(tech,'Rollback protected technician '||tech,'technician',true,ARRAY['HOIST','FITTING','BUS_4X4']);
  PERFORM pg_temp.rg_assignment(b,tech,'secondary');PERFORM pg_temp.rg_assignment(b2,tech,'secondary');
 END IF;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO before_rows FROM public.workshop_bookings x WHERE id IN(b,b2);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') INTO before_assignments FROM public.workshop_booking_assignments x WHERE booking_id IN(b,b2);
 SELECT count(*) INTO history_before FROM public.workshop_booking_history WHERE booking_id IN(b,b2);
 BEGIN
  r:=pdc_operation_updates_private.reconcile_running_growth_20261026(b,mins,auth.uid(),'owned_protected_fixture');
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_DETAIL,state=RETURNED_SQLSTATE;failed:=true;
 END;
 PERFORM pg_temp.ou_assert(failed AND detail=CASE WHEN kind IN('started','stoppage','technician') THEN 'operation_schedule_protected_active_booking' ELSE 'operation_schedule_protected_reservation' END,
  'Refuse genuine protected '||label,jsonb_build_object('detail',detail,'sqlstate',state));
 PERFORM pg_temp.ou_assert(before_rows=(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_bookings x WHERE id IN(b,b2))
  AND before_assignments=(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM public.workshop_booking_assignments x WHERE booking_id IN(b,b2))
  AND history_before=(SELECT count(*) FROM public.workshop_booking_history WHERE booking_id IN(b,b2)),
  'Protected refusal leaves bookings assignments and history unchanged '||label);
END $fn$;

CREATE FUNCTION pg_temp.rg_multihop() RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE a uuid; v uuid; c uuid; rootbay uuid; crossbay uuid; techbay uuid; root uuid; follower uuid; crossjob uuid; techjob uuid; tech uuid:=gen_random_uuid();
 t timestamptz; r jsonb; source_rows jsonb; before_assignments jsonb; root_before jsonb; block_start timestamptz; block_end timestamptz;
BEGIN
 a:=pg_temp.ou_vehicle('chain-root');v:=pg_temp.ou_vehicle('chain-vehicle');c:=pg_temp.ou_vehicle('chain-tech');
 rootbay:=pg_temp.ou_bay('chain-root','HOIST');crossbay:=pg_temp.ou_bay('chain-cross','FITTING');techbay:=pg_temp.ou_bay('chain-tech','ELECTRICAL');
 PERFORM pg_temp.ou_operation(a,'HOIST',1);PERFORM pg_temp.ou_operation(v,'HOIST',1);
 PERFORM pg_temp.ou_operation(v,'FITTING',1,2);PERFORM pg_temp.ou_operation(c,'ELECTRICAL',1);
 t:=((date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+182)+time '07:00') AT TIME ZONE 'Australia/Perth';
 root:=pg_temp.ou_booking('chain-root',a,'HOIST',rootbay,t,'started');
 follower:=pg_temp.ou_booking('chain-follower',v,'HOIST',rootbay,public.workshop_add_operational_minutes(t,120));
 crossjob:=pg_temp.ou_booking('chain-cross',v,'FITTING',crossbay,public.workshop_admin_next_operational_minute((SELECT scheduled_end_at+interval '1 hour' FROM public.workshop_bookings WHERE id=follower)));
 techjob:=pg_temp.ou_booking('chain-tech',c,'ELECTRICAL',techbay,public.workshop_admin_next_operational_minute((SELECT scheduled_end_at+interval '1 hour' FROM public.workshop_bookings WHERE id=crossjob)));
 INSERT INTO public.workshop_technicians(id,name,role_type,active,can_fit_stages)
 VALUES(tech,'Rollback chain secondary '||tech,'technician',true,ARRAY['FITTING','ELECTRICAL']);
 PERFORM pg_temp.rg_assignment(crossjob,tech,'secondary');PERFORM pg_temp.rg_assignment(techjob,tech,'secondary');
 -- A fixed Admin block may be skipped by a planned follower, never by moving the running root.
 block_start:=public.workshop_add_operational_minutes(t,360);block_end:=public.workshop_add_operational_minutes(block_start,60);
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT stage_id,rootbay,'admin','Owned chain block',block_start,block_end,60,auth.uid(),auth.uid() FROM public.workshop_bays WHERE id=rootbay;
 SELECT to_jsonb(x) INTO root_before FROM public.workshop_bookings x WHERE id=root;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY operation_id) INTO source_rows FROM public.pdc_pilbara_service_operations x WHERE vehicle_id IN(a,v,c);
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO before_assignments FROM public.workshop_booking_assignments x WHERE booking_id IN(crossjob,techjob);
 r:=pdc_operation_updates_private.reconcile_running_growth_20261026(root,360,auth.uid(),'owned_multihop_fixture');
 PERFORM pg_temp.ou_assert((r->>'changed_count')::int=4,'Full chain moves bay then vehicle then secondary technician',r);
 PERFORM pg_temp.ou_assert((SELECT status='started' AND actual_start_at=(root_before->>'actual_start_at')::timestamptz
  AND scheduled_start_at=t AND default_duration_minutes=360 FROM public.workshop_bookings WHERE id=root),'Running root remains anchored');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at>=block_end FROM public.workshop_bookings WHERE id=follower),'Planned bay follower skips fixed Admin interval');
 PERFORM pg_temp.ou_assert((SELECT x.scheduled_start_at>=p.scheduled_end_at+interval '1 hour' FROM public.workshop_bookings x,public.workshop_bookings p WHERE x.id=crossjob AND p.id=follower),'Cross-station vehicle keeps one-hour handover');
 PERFORM pg_temp.ou_assert((SELECT x.scheduled_start_at>=p.scheduled_end_at FROM public.workshop_bookings x,public.workshop_bookings p WHERE x.id=techjob AND p.id=crossjob),'Secondary technician follower cascades to free interval');
 PERFORM pg_temp.ou_assert((SELECT jsonb_agg(to_jsonb(x)-ARRAY['scheduled_start_at','scheduled_end_at','updated_at'] ORDER BY id)
  FROM public.workshop_booking_assignments x WHERE booking_id IN(crossjob,techjob))
  =(SELECT jsonb_agg(x-ARRAY['scheduled_start_at','scheduled_end_at','updated_at'] ORDER BY x->>'id') FROM jsonb_array_elements(before_assignments) x)
  AND NOT EXISTS(SELECT 1 FROM public.workshop_booking_assignments x JOIN public.workshop_bookings b ON b.id=x.booking_id
   WHERE x.booking_id IN(crossjob,techjob) AND (x.scheduled_start_at<>b.scheduled_start_at OR x.scheduled_end_at<>b.scheduled_end_at)),
  'Secondary assignment identities and all active ranges persist exactly');
 PERFORM pg_temp.ou_assert(source_rows=(SELECT jsonb_agg(to_jsonb(x) ORDER BY operation_id) FROM public.pdc_pilbara_service_operations x WHERE vehicle_id IN(a,v,c)),
  'Multi-hop growth preserves original source rows and hours');
 r:=pdc_operation_updates_private.reconcile_running_growth_20261026(root,30,auth.uid(),'owned_shrink_refusal_fixture');
 PERFORM pg_temp.ou_assert((r->>'changed_count')::int=0 AND (SELECT default_duration_minutes=360 FROM public.workshop_bookings WHERE id=root),'Explicit smaller demand cannot shrink a running allocation');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings x ON x.id=o.id WHERE to_jsonb(x) IS DISTINCT FROM o.row_data),'Chain leaves copied operational bookings unchanged');
END $fn$;

SAVEPOINT protected_case;
SELECT pg_temp.rg_protected('started',false);
SELECT pg_temp.rg_protected('stoppage',false);
SELECT pg_temp.rg_protected('technician',false);
SELECT pg_temp.rg_protected('admin',false);
SELECT pg_temp.rg_protected('leave',false);
SELECT pg_temp.rg_protected('sublet',false);
SELECT jsonb_build_object('scenario','Hoist genuine conflicts','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK TO protected_case;
SELECT pg_temp.rg_protected('started',true);
SELECT jsonb_build_object('scenario','Bus protected started','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK TO protected_case;
SELECT pg_temp.rg_protected('stoppage',true);
SELECT jsonb_build_object('scenario','Bus genuine conflicts','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK TO protected_case;
SELECT pg_temp.rg_multihop();
SELECT jsonb_build_object('scenario','multi-hop and Admin','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK;
