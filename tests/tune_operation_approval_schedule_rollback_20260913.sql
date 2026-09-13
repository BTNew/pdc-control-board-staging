-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection after the operation-approval migration.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'Australia/Perth';

DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

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
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{}','insert','rollback_original',vid);
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

CREATE FUNCTION pg_temp.ou_change(vid uuid, source_id uuid, hrs numeric, description text, new_line_no integer DEFAULT 1)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE ev uuid:=gen_random_uuid(); batch_id uuid:=gen_random_uuid(); cid uuid; a uuid; e text; v public.vehicles%rowtype; p jsonb; line_no integer;
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT actor,email INTO a,e FROM ou_context;
 IF source_id IS NOT NULL THEN SELECT original_line_number INTO STRICT line_no FROM public.pdc_pilbara_service_operations WHERE operation_id=source_id;
 ELSE line_no:=new_line_no; END IF;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department','139','operation_description',description,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station','REVIEW','hours_provenance','source_explicit','semantic_hash',encode(extensions.digest(description||hrs::text||ev::text,'sha256'),'hex'),
 'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(batch_id,'pilbara_service_open_jobcards_v1',encode(extensions.digest(batch_id::text,'sha256'),'hex'),repeat('e',64),'rollback-change-'||batch_id,'apply',1,1,0,1,0,0,'{}',a,e);
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',line_no,v.stock_number,v.job_card_number,line_no,p->>'semantic_hash',p,'{}','unchanged','operation_update_review',vid);
 PERFORM public.pdc_capture_tune_operation_changes_20260912(batch_id,batch_id);
 SELECT change_id INTO STRICT cid FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id=vid AND original_line_number=line_no AND status='pending';
 -- An unchanged repeat import must keep the same pending review/version.
 PERFORM public.pdc_capture_tune_operation_changes_20260912(batch_id,batch_id);
 IF (SELECT count(*) FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id=vid AND original_line_number=line_no AND status='pending')<>1
 OR (SELECT version FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)<>1 THEN RAISE EXCEPTION 'Repeated import duplicated or changed pending review'; END IF;
 RETURN cid;
END $fn$;

-- Cross-station graph, Admin obstacle, Friday/Saturday continuation and Sunday closure.
DO $cascade$
DECLARE a uuid; b uuid; c uuid; fit uuid; elec uuid; hoist uuid; tint uuid; op uuid; cid uuid; key uuid:=gen_random_uuid(); hash text;
 f date; sa timestamptz; mon timestamptz; r jsonb; again jsonb; changed jsonb; listj jsonb; offset_no integer:=0; listed boolean:=false;
 a_book uuid; b_book uuid; ae uuid; bh uuid; ce uuid; ct uuid;
BEGIN
 SELECT friday INTO f FROM ou_context; sa:=(f+1+time '08:00') AT TIME ZONE 'Australia/Perth'; mon:=(f+3+time '07:00') AT TIME ZONE 'Australia/Perth';
 PERFORM pg_temp.ou_assert(public.workshop_calendar_minute_available(sa)
 AND public.workshop_calendar_minute_available(sa+interval '239 minutes')
 AND NOT public.workshop_calendar_minute_available(sa-interval '1 minute')
 AND NOT public.workshop_calendar_minute_available(sa+interval '4 hours')
 AND NOT public.workshop_calendar_minute_available(sa+interval '1 day'),
 'Saturday is open only 08 to 12 and Sunday is closed');
 a:=pg_temp.ou_vehicle('chain-A'); b:=pg_temp.ou_vehicle('chain-B'); c:=pg_temp.ou_vehicle('chain-C');
 fit:=pg_temp.ou_bay('chain-fitting','FITTING'); elec:=pg_temp.ou_bay('chain-electrical','ELECTRICAL'); hoist:=pg_temp.ou_bay('chain-hoist','HOIST'); tint:=pg_temp.ou_bay('chain-tint','TINT');
 op:=pg_temp.ou_operation(a,'FITTING',8); PERFORM pg_temp.ou_operation(a,'ELECTRICAL',2,2);
 PERFORM pg_temp.ou_operation(b,'FITTING',1); PERFORM pg_temp.ou_operation(b,'HOIST',1,2);
 PERFORM pg_temp.ou_operation(c,'ELECTRICAL',1); PERFORM pg_temp.ou_operation(c,'TINT',1,2);
 a_book:=pg_temp.ou_booking('chain-A-fit',a,'FITTING',fit,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 b_book:=pg_temp.ou_booking('chain-B-fit',b,'FITTING',fit,(f+time '15:00') AT TIME ZONE 'Australia/Perth');
 ae:=pg_temp.ou_booking('chain-A-elec',a,'ELECTRICAL',elec,sa);
 bh:=pg_temp.ou_booking('chain-B-hoist',b,'HOIST',hoist,sa);
 ce:=pg_temp.ou_booking('chain-C-elec',c,'ELECTRICAL',elec,sa+interval '2h');
 ct:=pg_temp.ou_booking('chain-C-tint',c,'TINT',tint,mon);
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT stage_id,elec,'admin','Rollback fixture Admin reservation',mon,mon+interval '1h',60,actor,actor FROM public.workshop_bays,ou_context WHERE id=elec;
 cid:=pg_temp.ou_change(a,op,12,'Extended fixture fitting operation');
 PERFORM pg_temp.ou_assert((SELECT status='pending' AND change_kind='modified' FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)
 AND public.workshop_vehicle_stage_estimated_hours(a,'FITTING')=8
 AND (SELECT default_duration_minutes=480 FROM public.workshop_bookings WHERE id=a_book),'Modified import remains pending without changing hours');
 LOOP
  listj:=public.list_pdc_tune_operation_changes(offset_no,100);
  listed:=EXISTS(SELECT 1 FROM jsonb_array_elements(listj->'data'->'items') x WHERE x->>'change_id'=cid::text AND x->>'status'='pending');
  EXIT WHEN listed OR offset_no+100>=(listj->'data'->>'total')::integer OR offset_no>10000;
  offset_no:=offset_no+100;
 END LOOP;
 PERFORM pg_temp.ou_assert(listj->>'ok'='true' AND listed AND public.pdc_tune_operation_change_row_20260912(cid)->>'status'='pending',
 'Updated operation has New Vehicles readback',jsonb_build_object('change_id',cid,'total',listj->'data'->'total'));
 hash:=public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash';
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,hash,'FITTING',12,key);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Approve modified operation succeeds',r);
 PERFORM pg_temp.ou_assert(r->'data'->>'bookings_changed'='true'
 AND r->'data'->'schedule'->>'changed_count'='6'
 AND r->'data'->'schedule'->>'extended_count'='1'
 AND r->'data'->'schedule'->>'moved_count'='5'
 AND r->'data'->'schedule'->>'buffer_minutes'='300'
 AND jsonb_array_length(r->'data'->'schedule'->'bookings')=6,
 'Approval receipt identifies exact extended and moved bookings',r->'data'->'schedule');
 PERFORM pg_temp.ou_assert(public.workshop_vehicle_stage_estimated_hours(a,'FITTING')=12
 AND (SELECT default_duration_minutes=720 AND scheduled_start_at=(f+time '07:00') AT TIME ZONE 'Australia/Perth'
 AND scheduled_end_at=sa+interval '2h' FROM public.workshop_bookings WHERE id=a_book),'Approved bay extends to exact 12 hours across Saturday');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=sa+interval '2h' AND scheduled_end_at=sa+interval '3h' FROM public.workshop_bookings WHERE id=b_book),
 'Next vehicle in same bay moves after extension');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=mon+interval '1h' AND scheduled_end_at=mon+interval '3h' FROM public.workshop_bookings WHERE id=ae),
 'Same vehicle next station avoids Admin and closed Sunday');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=mon AND scheduled_end_at=mon+interval '1h' FROM public.workshop_bookings WHERE id=bh),
 'Pushed vehicle later station keeps five-hour gap');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=mon+interval '3h' AND scheduled_end_at=mon+interval '4h' FROM public.workshop_bookings WHERE id=ce)
 AND (SELECT scheduled_start_at=mon+interval '9h' AND scheduled_end_at=mon+interval '10h' FROM public.workshop_bookings WHERE id=ct),
 'Recursive vehicle chain moves later stations with five-hour gap');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings x JOIN public.workshop_admin_blocks ab ON ab.bay_id=x.bay_id AND ab.deleted_at IS NULL
 WHERE x.vehicle_id IN(a,b,c) AND x.scheduled_start_at<ab.scheduled_end_at AND x.scheduled_end_at>ab.scheduled_start_at),
 'No affected booking overlaps Admin reservation');
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO changed FROM public.workshop_bookings x WHERE vehicle_id IN(a,b,c);
 again:=public.approve_pdc_tune_operation_change_with_schedule(cid,hash,'FITTING',12,key);
 PERFORM pg_temp.ou_assert(again->>'ok'='true' AND again->>'replay'='true'
 AND changed=(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_bookings x WHERE vehicle_id IN(a,b,c)),
 'Exact approval retry replays without another extension',again);
 again:=public.approve_pdc_tune_operation_change_with_schedule(cid,hash,'FITTING',13,key);
 PERFORM pg_temp.ou_assert(again->>'ok' IS DISTINCT FROM 'true'
 AND changed=(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_bookings x WHERE vehicle_id IN(a,b,c)),
 'Changed retry cannot approve twice',again);
 PERFORM pg_temp.ou_assert((SELECT current_location='PMB' AND visible_on_board AND lifecycle_state::text='active' FROM public.vehicles WHERE id=a),
 'Approval preserves vehicle location and lifecycle');
END $cascade$;

DO $added$
DECLARE v uuid; bay uuid; booking uuid; cid uuid; r jsonb; old_hash text; f date; key uuid:=gen_random_uuid();
BEGIN
 SELECT friday INTO f FROM ou_context;
 v:=pg_temp.ou_vehicle('added'); bay:=pg_temp.ou_bay('added','FITTING'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 booking:=pg_temp.ou_booking('added',v,'FITTING',bay,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 cid:=pg_temp.ou_change(v,NULL,1.25,'Additional fixture operation',2);
 PERFORM pg_temp.ou_assert((SELECT change_kind='added' AND status='pending' FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)
 AND (SELECT count(*) FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v)=1
 AND public.workshop_vehicle_stage_estimated_hours(v,'FITTING')=1,'Added import stays outside canonical work until approved');
 old_hash:=public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash';
 UPDATE public.pdc_tune_operation_change_reviews SET version=version+1 WHERE change_id=cid;
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,old_hash,'FITTING',1.25,key);
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND r->>'code'='operation_review_changed'
 AND public.workshop_vehicle_stage_estimated_hours(v,'FITTING')=1,'Stale review cannot approve an outdated change',r);
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','FITTING',1.25,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND public.workshop_vehicle_stage_estimated_hours(v,'FITTING')=2.25
 AND (SELECT default_duration_minutes=135 AND scheduled_end_at=(f+time '09:15') AT TIME ZONE 'Australia/Perth' FROM public.workshop_bookings WHERE id=booking),
 'Added operation increases existing bay by exact 75 minutes',r);
END $added$;

-- Same arithmetic as the reported two-hour addition to a seven-hour Hoist job.
DO $hoist_addition$
DECLARE v uuid; bay uuid; cid uuid; booking uuid; r jsonb; f date;
BEGIN
 SELECT friday INTO f FROM ou_context;
 v:=pg_temp.ou_vehicle('hoist-seven-plus-two'); bay:=pg_temp.ou_bay('hoist-seven-plus-two','HOIST');
 PERFORM pg_temp.ou_operation(v,'HOIST',7);
 booking:=pg_temp.ou_booking('hoist-seven-plus-two',v,'HOIST',bay,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 cid:=pg_temp.ou_change(v,NULL,2,'Additional two-hour hoist work',2);
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','HOIST',2,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND public.workshop_vehicle_stage_estimated_hours(v,'HOIST')=9
 AND (SELECT default_duration_minutes=540 AND scheduled_end_at=(f+time '16:00') AT TIME ZONE 'Australia/Perth' FROM public.workshop_bookings WHERE id=booking),
 'Two-hour added Hoist operation increases seven-hour booking to nine',r);
END $hoist_addition$;

DO $unbooked$
DECLARE v uuid; cid uuid; r jsonb; op uuid;
BEGIN
 v:=pg_temp.ou_vehicle('unbooked'); op:=pg_temp.ou_operation(v,'HOIST',1);
 cid:=pg_temp.ou_change(v,op,3,'Unbooked extended hoist operation');
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','HOIST',3,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND public.workshop_vehicle_stage_estimated_hours(v,'HOIST')=3
 AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v),'Unbooked operation updates work without inventing booking',r);
 cid:=pg_temp.ou_change(v,NULL,0,'SUBLET fixture external work',2);
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','SUBLET',NULL,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v)
 AND EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'stage_code'='SUBLET' AND l->>'description'='SUBLET fixture external work'),
 'Sublet approval needs no workshop hours or bay',r);
END $unbooked$;

DO $started$
DECLARE v uuid; nextv uuid; bay uuid; op uuid; cid uuid; r jsonb; bid uuid; nextbid uuid; f date; before_lifecycle jsonb;
BEGIN
 SELECT friday INTO f FROM ou_context;
 v:=pg_temp.ou_vehicle('started'); nextv:=pg_temp.ou_vehicle('after-started'); bay:=pg_temp.ou_bay('started','FABRICATION');
 op:=pg_temp.ou_operation(v,'FABRICATION',1); PERFORM pg_temp.ou_operation(nextv,'FABRICATION',1);
 bid:=pg_temp.ou_booking('started',v,'FABRICATION',bay,(f+time '07:00') AT TIME ZONE 'Australia/Perth','started');
 nextbid:=pg_temp.ou_booking('after-started',nextv,'FABRICATION',bay,(f+time '08:00') AT TIME ZONE 'Australia/Perth');
 SELECT jsonb_build_array(status,actual_start_at,actual_end_at,stoppage_started_at,stoppage_accumulated_minutes,bay_id) INTO before_lifecycle FROM public.workshop_bookings WHERE id=bid;
 cid:=pg_temp.ou_change(v,op,3,'Extended started fabrication operation');
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','FABRICATION',3,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true'
 AND (SELECT default_duration_minutes=180 AND scheduled_end_at=(f+time '10:00') AT TIME ZONE 'Australia/Perth' FROM public.workshop_bookings WHERE id=bid)
 AND before_lifecycle=(SELECT jsonb_build_array(status,actual_start_at,actual_end_at,stoppage_started_at,stoppage_accumulated_minutes,bay_id) FROM public.workshop_bookings WHERE id=bid)
 AND (SELECT scheduled_start_at=(f+time '10:00') AT TIME ZONE 'Australia/Perth' FROM public.workshop_bookings WHERE id=nextbid),
 'Started booking extends without resetting actual lifecycle',r);
END $started$;

DO $protected$
DECLARE v uuid; other uuid; bay uuid; op uuid; cid uuid; r jsonb; bid uuid; otherbid uuid; f date; before_rows jsonb; before_adjustments jsonb; rejection text;
BEGIN
 SELECT friday INTO f FROM ou_context;
 v:=pg_temp.ou_vehicle('protected'); other:=pg_temp.ou_vehicle('protected-other'); bay:=pg_temp.ou_bay('protected','TYRE');
 op:=pg_temp.ou_operation(v,'TYRE',1); PERFORM pg_temp.ou_operation(other,'TYRE',1);
 bid:=pg_temp.ou_booking('protected',v,'TYRE',bay,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 otherbid:=pg_temp.ou_booking('protected-other',other,'TYRE',bay,(f+time '08:00') AT TIME ZONE 'Australia/Perth','started');
 cid:=pg_temp.ou_change(v,op,3,'Conflicting fixture tyre extension');
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO before_rows FROM public.workshop_bookings x WHERE vehicle_id IN(v,other);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY adjustment_id),'[]') INTO before_adjustments FROM public.vehicle_workshop_line_adjustments x WHERE vehicle_id=v;
 BEGIN
  r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','TYRE',3,gen_random_uuid());
  rejection:=r->>'code';
 EXCEPTION WHEN OTHERS THEN rejection:=SQLERRM;r:=jsonb_build_object('ok',false,'exception',rejection);
 END;
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND rejection IS NOT NULL
 AND before_rows=(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_bookings x WHERE vehicle_id IN(v,other))
 AND before_adjustments=(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY adjustment_id),'[]') FROM public.vehicle_workshop_line_adjustments x WHERE vehicle_id=v)
 AND (SELECT status='pending' FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)
 AND public.workshop_vehicle_stage_estimated_hours(v,'TYRE')=1,
 'Conflict with another started job fails atomically',r);
END $protected$;

DO $authorization$
DECLARE v uuid; op uuid; cid uuid; r jsonb; a uuid; e text; hash text;
BEGIN
 v:=pg_temp.ou_vehicle('authorization'); op:=pg_temp.ou_operation(v,'TINT',1);
 cid:=pg_temp.ou_change(v,op,2,'Authorization fixture tint operation');
 hash:=public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash';
 SELECT actor,email INTO a,e FROM ou_context;
 PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,hash,'TINT',2,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'code'='not_authorized','Anonymous approval is rejected',r);
 -- A unique, unregistered subject cannot inherit the approved fixture's role.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',gen_random_uuid(),'email','unapproved-operation-fixture@example.invalid')::text,true);
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,hash,'TINT',2,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'code'='not_authorized','Authenticated subject without approved role is rejected',r);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',a,'email',e)::text,true);
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,hash,'TINT',0,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'code'='invalid_operation_hours_or_station','Zero workshop hours are rejected',r);
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,hash,'TINT',1.001,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'code'='invalid_operation_hours_or_station','Unsupported hour precision is rejected',r);
 PERFORM pg_temp.ou_assert((SELECT status='pending' FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)
 AND public.workshop_vehicle_stage_estimated_hours(v,'TINT')=1
 AND NOT EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v),
 'Authorization and hours denials preserve pending canonical work');
END $authorization$;

DO $completed$
DECLARE v uuid; op uuid; cid uuid; r jsonb; a uuid; completed_v uuid;
BEGIN
 SELECT actor INTO a FROM ou_context;
 v:=pg_temp.ou_vehicle('completed-line'); op:=pg_temp.ou_operation(v,'HOIST',1); PERFORM pg_temp.ou_operation(v,'HOIST',1,2);
 cid:=pg_temp.ou_change(v,op,2,'Completed-line fixture operation');
 INSERT INTO public.pdc_qc_operation_completions_379(vehicle_id,line_identity,source_kind,source_line_id,stage_code,completed,completed_by,completed_at)
 VALUES(v,'source:'||op,'authenticated',op,'HOIST',true,a,clock_timestamp());
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','HOIST',2,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND r->>'code'='completed_or_removed_line_protected'
 AND (SELECT status='pending' FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)
 AND public.workshop_vehicle_stage_estimated_hours(v,'HOIST')=2,'Completed operation remains protected',r);
 completed_v:=pg_temp.ou_vehicle('completed-station'); op:=pg_temp.ou_operation(completed_v,'TYRE',1);
 cid:=pg_temp.ou_change(completed_v,op,2,'Completed-station fixture operation');
 UPDATE public.vehicle_work_items SET completed=true,completed_by=a,completed_at=clock_timestamp()
 WHERE vehicle_id=completed_v AND work_key=(SELECT work_key FROM public.workshop_stages WHERE code='TYRE');
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','TYRE',2,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND r->>'code'='completed_station_requires_rework_review'
 AND (SELECT status='pending' FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)
 AND public.workshop_vehicle_stage_estimated_hours(completed_v,'TYRE')=1,'Completed station requires rework review',r);
END $completed$;

DO $technicians$
DECLARE v uuid; other uuid; a uuid; op uuid; cid uuid; r jsonb; bay1 uuid; bay2 uuid; bid uuid; nextbid uuid; t1 uuid:=gen_random_uuid(); t2 uuid:=gen_random_uuid();
 f date; before_assignments jsonb;
BEGIN
 SELECT friday,actor INTO f,a FROM ou_context;
 v:=pg_temp.ou_vehicle('technician'); other:=pg_temp.ou_vehicle('technician-following');
 bay1:=pg_temp.ou_bay('technician-primary','ELECTRICAL'); bay2:=pg_temp.ou_bay('technician-following','FABRICATION');
 op:=pg_temp.ou_operation(v,'ELECTRICAL',1); PERFORM pg_temp.ou_operation(other,'FABRICATION',1);
 bid:=pg_temp.ou_booking('technician',v,'ELECTRICAL',bay1,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 nextbid:=pg_temp.ou_booking('technician-following',other,'FABRICATION',bay2,(f+time '08:00') AT TIME ZONE 'Australia/Perth');
 INSERT INTO public.workshop_technicians(id,name,role_type,can_fit_stages,created_by,updated_by) VALUES
 (t1,'Rollback primary '||t1,'technician',ARRAY['ELECTRICAL','FABRICATION'],a,a),
 (t2,'Rollback secondary '||t2,'technician',ARRAY['ELECTRICAL','FABRICATION'],a,a);
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT bid,t1,'primary',a,scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=bid;
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT bid,t2,'secondary',a,scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=bid;
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT nextbid,t2,'primary',a,scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=nextbid;
 SELECT jsonb_agg(to_jsonb(x)-ARRAY['scheduled_start_at','scheduled_end_at','updated_at'] ORDER BY id) INTO before_assignments
 FROM public.workshop_booking_assignments x WHERE booking_id IN(bid,nextbid);
 cid:=pg_temp.ou_change(v,op,3,'Extended two-technician electrical work');
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','ELECTRICAL',3,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true'
 AND (SELECT scheduled_start_at=(f+time '10:00') AT TIME ZONE 'Australia/Perth' AND scheduled_end_at=(f+time '11:00') AT TIME ZONE 'Australia/Perth' FROM public.workshop_bookings WHERE id=nextbid),
 'Shared secondary technician cascades another bay booking',r);
 PERFORM pg_temp.ou_assert(before_assignments=(SELECT jsonb_agg(to_jsonb(x)-ARRAY['scheduled_start_at','scheduled_end_at','updated_at'] ORDER BY id)
 FROM public.workshop_booking_assignments x WHERE booking_id IN(bid,nextbid))
 AND NOT EXISTS(SELECT 1 FROM public.workshop_booking_assignments x JOIN public.workshop_bookings b ON b.id=x.booking_id
 WHERE x.booking_id IN(bid,nextbid) AND (x.scheduled_start_at<>b.scheduled_start_at OR x.scheduled_end_at<>b.scheduled_end_at)),
 'Primary and secondary assignment identities persist with correct windows');
END $technicians$;

DO $past_started$
DECLARE v uuid; other uuid; bay uuid; op uuid; cid uuid; r jsonb; bid uuid; nextbid uuid; started_at timestamptz; next_start timestamptz; expected_end timestamptz;
BEGIN
 SELECT max((d::date+make_time(h,0,0)) AT TIME ZONE 'Australia/Perth') INTO started_at
 FROM generate_series(current_date-8,current_date,interval '1 day') d CROSS JOIN generate_series(7,16) h
 WHERE (d::date+make_time(h,0,0)) AT TIME ZONE 'Australia/Perth'<date_trunc('minute',clock_timestamp())
 AND public.workshop_calendar_minute_available((d::date+make_time(h,0,0)) AT TIME ZONE 'Australia/Perth');
 v:=pg_temp.ou_vehicle('past-started'); other:=pg_temp.ou_vehicle('after-past-started'); bay:=pg_temp.ou_bay('past-started','FITTING');
 op:=pg_temp.ou_operation(v,'FITTING',1); PERFORM pg_temp.ou_operation(other,'FITTING',1);
 bid:=pg_temp.ou_booking('past-started',v,'FITTING',bay,started_at,'started');
 next_start:=public.workshop_admin_next_operational_minute(greatest(date_trunc('minute',clock_timestamp())+interval '1 minute',public.workshop_add_operational_minutes(started_at,60)));
 nextbid:=pg_temp.ou_booking('after-past-started',other,'FITTING',bay,next_start);
 expected_end:=public.workshop_add_operational_minutes(started_at,180);
 cid:=pg_temp.ou_change(v,op,3,'Past-started fixture additional fitting work');
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','FITTING',3,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND started_at<clock_timestamp()
 AND (SELECT status::text='started' AND actual_start_at=started_at AND scheduled_start_at=started_at AND scheduled_end_at=expected_end AND default_duration_minutes=180 FROM public.workshop_bookings WHERE id=bid)
 AND (SELECT scheduled_start_at=public.workshop_admin_next_operational_minute(greatest(next_start,expected_end)) FROM public.workshop_bookings WHERE id=nextbid),
 'A job actually started in the past extends without a past-start validation failure',r);
END $past_started$;

DO $queued_stoppage$
DECLARE v uuid; bay uuid; op uuid; cid uuid; r jsonb; bid uuid; f date; a uuid; start_at timestamptz;
BEGIN
 SELECT friday,actor INTO f,a FROM ou_context; start_at:=(f+time '07:00') AT TIME ZONE 'Australia/Perth';
 v:=pg_temp.ou_vehicle('queued'); bay:=pg_temp.ou_bay('queued','HOIST'); op:=pg_temp.ou_operation(v,'HOIST',1);
 bid:=pg_temp.ou_booking('queued',v,'HOIST',bay,start_at,'queued');
 cid:=pg_temp.ou_change(v,op,2,'Queued fixture hoist extension');
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','HOIST',2,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true'
 AND (SELECT status::text='queued' AND default_duration_minutes=120 AND scheduled_end_at=start_at+interval '2 hours' FROM public.workshop_bookings WHERE id=bid),
 'Queued bay booking extends and remains queued',r);
 v:=pg_temp.ou_vehicle('stoppage'); bay:=pg_temp.ou_bay('stoppage','TYRE'); op:=pg_temp.ou_operation(v,'TYRE',1);
 bid:=pg_temp.ou_booking('stoppage',v,'TYRE',bay,start_at,'started');
 UPDATE public.workshop_bookings SET status='stoppage',stoppage_reason='Rollback fixture waiting for material',stoppage_started_at=start_at+interval '20 minutes',stoppage_accumulated_minutes=5
 WHERE id=bid;
 cid:=pg_temp.ou_change(v,op,2,'Stopped fixture tyre extension');
 r:=public.approve_pdc_tune_operation_change_with_schedule(cid,public.pdc_tune_operation_change_row_20260912(cid)->>'snapshot_hash','TYRE',2,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true'
 AND (SELECT status::text='stoppage' AND actual_start_at=start_at AND stoppage_started_at=start_at+interval '20 minutes'
 AND stoppage_accumulated_minutes=5 AND stoppage_reason='Rollback fixture waiting for material' AND default_duration_minutes=120
 FROM public.workshop_bookings WHERE id=bid),'Stopped booking extends and retains its stoppage history',r);
END $queued_stoppage$;

DO $final$
BEGIN
 PERFORM pg_temp.ou_assert(coalesce(current_setting('pdc.defer_workshop_adjustment_reconcile',true),'')=''
 AND coalesce(current_setting('pdc.defer_workshop_required_work_reconcile',true),'')='',
 'Reconciliation deferral flags restored after successes and denials');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings x LEFT JOIN public.workshop_bookings b USING(id) WHERE to_jsonb(b) IS DISTINCT FROM x.row_data),
 'All pre-existing bookings are unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles x LEFT JOIN public.vehicles v USING(id) WHERE to_jsonb(v) IS DISTINCT FROM x.row_data),
 'All pre-existing vehicles are unchanged');
END $final$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT name,status,evidence FROM ou_results ORDER BY name;
ROLLBACK;
