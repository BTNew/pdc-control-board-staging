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
DO $tests$
DECLARE f date; bay_a uuid; bay_h uuid; va uuid; vb uuid; root_id uuid; follow_id uuid; cross_id uuid;
 p jsonb; applied jsonb; again jsonb; key uuid:=gen_random_uuid(); floor_at timestamptz; t timestamptz; version_before integer;
BEGIN
 SELECT friday INTO f FROM ou_context;
 bay_a:=pg_temp.ou_bay('capacity-root','FITTING'); UPDATE public.workshop_bays SET bay_number=991 WHERE id=bay_a;
 bay_h:=pg_temp.ou_bay('capacity-cross','HOIST'); UPDATE public.workshop_bays SET bay_number=992 WHERE id=bay_h;
 va:=pg_temp.ou_vehicle('capacity-root'); PERFORM pg_temp.ou_operation(va,'FITTING',4);
 PERFORM pg_temp.ou_operation(va,'HOIST',1,2);
 vb:=pg_temp.ou_vehicle('capacity-follower'); PERFORM pg_temp.ou_operation(vb,'FITTING',2);
 root_id:=pg_temp.ou_booking('capacity-root',va,'FITTING',bay_a,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 follow_id:=pg_temp.ou_booking('capacity-follow',vb,'FITTING',bay_a,(f+time '11:00') AT TIME ZONE 'Australia/Perth');
 cross_id:=pg_temp.ou_booking('capacity-cross',va,'HOIST',bay_h,(f+time '16:00') AT TIME ZONE 'Australia/Perth');
 PERFORM pg_temp.ou_assert((public.get_workshop_capacity_configuration('FITTING')->>'ok')::boolean,'Configuration is available to an operator');
 PERFORM pg_temp.ou_assert((SELECT efficiency_percent=100 FROM public.list_workshop_bays() WHERE id=bay_a),'Legacy bay DTO includes normal efficiency');
 t:=clock_timestamp();
 p:=public.replan_workshop_capacity('FITTING',991,80);
 PERFORM pg_temp.ou_assert(true,'Full graph preview timing',jsonb_build_object('milliseconds',round(extract(epoch FROM clock_timestamp()-t)*1000,2),
  'active_bookings',(SELECT count(*) FROM pg_temp.workshop_capacity_plan)));
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true','Efficiency preview can apply',p);
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=240 AND version=1 FROM public.workshop_bookings WHERE id=root_id)
   AND (SELECT efficiency_percent=100 FROM public.workshop_bays WHERE id=bay_a),'Preview leaves bookings and bay unchanged');
 PERFORM pg_temp.ou_assert((SELECT (x->>'new_minutes')::integer=300 FROM jsonb_array_elements(p->'changes') x WHERE x->>'booking_id'=root_id::text),
   'Four base hours at eighty percent allocate five hours',p);
 PERFORM pg_temp.ou_assert((SELECT (x->>'new_start_at')::timestamptz=(f+time '12:00') AT TIME ZONE 'Australia/Perth'
    FROM jsonb_array_elements(p->'changes') x WHERE x->>'booking_id'=follow_id::text),'Later bay job follows extended root',p);
 PERFORM pg_temp.ou_assert((SELECT (x->>'new_start_at')::timestamptz=(f+1+time '08:00') AT TIME ZONE 'Australia/Perth'
    FROM jsonb_array_elements(p->'changes') x WHERE x->>'booking_id'=cross_id::text),'Cross-station handover keeps five hours and Saturday opening',p);
 t:=clock_timestamp();
 applied:=public.replan_workshop_capacity('FITTING',991,80,true,p->>'plan_hash',key);
 PERFORM pg_temp.ou_assert(true,'Three booking atomic apply timing',jsonb_build_object('milliseconds',round(extract(epoch FROM clock_timestamp()-t)*1000,2)));
 PERFORM pg_temp.ou_assert(applied->>'ok'='true' AND applied->>'applied'='true','Efficiency apply succeeds atomically',applied);
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=300 AND capacity_base_minutes=240 AND capacity_efficiency_percent=80
    FROM public.workshop_bookings WHERE id=root_id),'Applied booking retains base minutes and factor');
 again:=public.replan_workshop_capacity('FITTING',991,80,true,p->>'plan_hash',key);
 PERFORM pg_temp.ou_assert(again->>'replay'='true' AND (SELECT version=2 FROM public.workshop_bookings WHERE id=root_id),
   'Idempotent retry does not change versions',again);
 p:=public.replan_workshop_capacity('FITTING',991,80);
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true' AND jsonb_array_length(p->'changes')=0,'Repeated same efficiency does not compound or move jobs',p);
 p:=public.replan_workshop_capacity('FITTING',991,100);
 PERFORM pg_temp.ou_assert((SELECT (x->>'new_minutes')::integer=240 FROM jsonb_array_elements(p->'changes') x WHERE x->>'booking_id'=root_id::text),
  'Returning to normal restores original allocation',p);
 applied:=public.replan_workshop_capacity('FITTING',991,100,true,p->>'plan_hash',gen_random_uuid());
 PERFORM pg_temp.ou_assert(applied->>'applied'='true' AND (SELECT default_duration_minutes=240 FROM public.workshop_bookings WHERE id=root_id),
  'Normal efficiency apply does not compound',applied);
 -- A fixture-specific internal floor tests Friday/Saturday/weekend compaction
 -- without writing any real vehicle or booking. Public Apply tests above affect
 -- only these synthetic bays and the synthetic cross-station follower.
 floor_at:=(f+time '07:00') AT TIME ZONE 'Australia/Perth';
 t:=clock_timestamp();
 p:=public.workshop_capacity_plan('FITTING',null,null,floor_at);
 PERFORM pg_temp.ou_assert(true,'Close gaps full graph timing',jsonb_build_object('milliseconds',round(extract(epoch FROM clock_timestamp()-t)*1000,2)));
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true','Close gaps preview resolves safe existing graph',p);
 PERFORM pg_temp.ou_assert((SELECT final_start=(f+time '11:00') AT TIME ZONE 'Australia/Perth'
   FROM pg_temp.workshop_capacity_plan WHERE booking_id=follow_id),'Close gaps moves follower earlier on its original bay');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan WHERE changed AND final_start>original_start),
  'Close gaps never pushes a job later');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan WHERE changed AND stage_code<>'FITTING'),
  'Close gaps changes only selected planner');
 PERFORM pg_temp.ou_assert((SELECT apply_order IS NOT NULL FROM pg_temp.workshop_capacity_plan WHERE booking_id=follow_id),
  'Earlier move has a constraint-safe application order');
 PERFORM pg_temp.ou_assert((SELECT public.workshop_vehicle_stage_estimated_duration_minutes(va,stage_id)=240
    FROM public.workshop_bookings WHERE id=root_id),'Capacity edits never change quoted operation minutes');
 PERFORM pg_temp.ou_assert(public.replan_workshop_capacity('FITTING',991,0)->>'error'='invalid_capacity_request',
  'Invalid efficiency is rejected');
 PERFORM pg_temp.ou_assert(public.replan_workshop_capacity('SUBLET',1,80)->>'error'='station_unavailable',
  'Sublet never has workshop capacity');
 PERFORM pg_temp.ou_assert(public.replan_workshop_capacity('FITTING',991,80,true,'invalid',gen_random_uuid())->>'error'='stale_preview',
  'Invalid preview token is rejected');
 p:=public.replan_workshop_capacity('FITTING',991,80);
 UPDATE public.workshop_bays SET version=version+1 WHERE id=bay_a;
 applied:=public.replan_workshop_capacity('FITTING',991,80,true,p->>'plan_hash',gen_random_uuid());
 PERFORM pg_temp.ou_assert(applied->>'error'='stale_preview' AND (SELECT efficiency_percent=100 FROM public.workshop_bays WHERE id=bay_a),
   'Changed bay version invalidates review without writes',applied);
END $tests$;
DO $reservations$
DECLARE f date; a uuid; b uuid; b2 uuid; v uuid; v2 uuid; bid uuid; fixed_id uuid; tech uuid:=gen_random_uuid();
 provider uuid:=gen_random_uuid(); p jsonb; r jsonb; start_at timestamptz; end_at timestamptz; item record; before_fixed jsonb;
BEGIN
 SELECT friday,actor INTO f,a FROM ou_context;
 b:=pg_temp.ou_bay('fixed','FITTING'); UPDATE public.workshop_bays SET bay_number=995 WHERE id=b;
 v:=pg_temp.ou_vehicle('fixed-root'); PERFORM pg_temp.ou_operation(v,'FITTING',4);
 v2:=pg_temp.ou_vehicle('fixed-live'); PERFORM pg_temp.ou_operation(v2,'FITTING',1);
 bid:=pg_temp.ou_booking('fixed-root',v,'FITTING',b,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 fixed_id:=pg_temp.ou_booking('fixed-live',v2,'FITTING',b,(f+time '11:00') AT TIME ZONE 'Australia/Perth','started');
 SELECT to_jsonb(w) INTO before_fixed FROM public.workshop_bookings w WHERE id=fixed_id;
 p:=public.replan_workshop_capacity('FITTING',995,80);
 PERFORM pg_temp.ou_assert(p->>'can_apply'='false' AND p->>'error'='protected_booking','Extension cannot move a started follower',p);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(w)=before_fixed FROM public.workshop_bookings w WHERE id=fixed_id)
   AND (SELECT efficiency_percent=100 FROM public.workshop_bays WHERE id=b),'Blocked efficiency preserves fixed booking and setting');
 -- An Admin reservation inside the longer interval moves the whole job beyond it.
 b:=pg_temp.ou_bay('admin','FITTING'); UPDATE public.workshop_bays SET bay_number=996 WHERE id=b;
 v:=pg_temp.ou_vehicle('admin-root'); PERFORM pg_temp.ou_operation(v,'FITTING',4);
 bid:=pg_temp.ou_booking('admin-root',v,'FITTING',b,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT stage_id,b,'admin','Rollback capacity reservation',(f+time '11:00') AT TIME ZONE 'Australia/Perth',
  (f+time '12:00') AT TIME ZONE 'Australia/Perth',60,a,a FROM public.workshop_bays WHERE id=b;
 p:=public.replan_workshop_capacity('FITTING',996,80);
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true' AND
  (SELECT (x->>'new_start_at')::timestamptz=(f+time '12:00') AT TIME ZONE 'Australia/Perth'
    FROM jsonb_array_elements(p->'changes') x WHERE x->>'booking_id'=bid::text),'Efficiency respects full Admin reservation',p);
 -- Sublet absence falls on a continuation day, not the initial booking date.
 b:=pg_temp.ou_bay('away','FITTING'); UPDATE public.workshop_bays SET bay_number=997 WHERE id=b;
 v:=pg_temp.ou_vehicle('away-root'); PERFORM pg_temp.ou_operation(v,'FITTING',2);
 bid:=pg_temp.ou_booking('away-root',v,'FITTING',b,(f+time '14:00') AT TIME ZONE 'Australia/Perth');
 INSERT INTO public.sublet_providers(id,name,created_by,updated_by) VALUES(provider,'Rollback capacity provider '||provider,a,a);
 INSERT INTO public.pdc_sublet_booking_instances(vehicle_id,vehicle_version,provider_id,provider_name,out_date,expected_return_date,created_by,updated_by)
 VALUES(v,(SELECT version FROM public.vehicles WHERE id=v),provider,'Rollback capacity provider '||provider,f+1,f+2,a,a);
 p:=public.replan_workshop_capacity('FITTING',997,10);
 SELECT (x->>'new_start_at')::timestamptz,(x->>'new_end_at')::timestamptz INTO start_at,end_at
  FROM jsonb_array_elements(p->'changes') x WHERE x->>'booking_id'=bid::text;
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true' AND start_at>(f+1+time '12:00') AT TIME ZONE 'Australia/Perth'
  AND NOT EXISTS(SELECT 1 FROM generate_series(start_at::date,end_at::date,interval '1 day') d
    WHERE public.pdc_sublet_away_on_date(v,d::date)),'Longer job skips Sublet absence on continuation day',p);
 -- Secondary technician leave also reserves the complete date span.
 b:=pg_temp.ou_bay('leave','FITTING'); UPDATE public.workshop_bays SET bay_number=998 WHERE id=b;
 v:=pg_temp.ou_vehicle('leave-root'); PERFORM pg_temp.ou_operation(v,'FITTING',2);
 bid:=pg_temp.ou_booking('leave-root',v,'FITTING',b,(f+time '14:00') AT TIME ZONE 'Australia/Perth');
 INSERT INTO public.workshop_technicians(id,name,role_type,can_fit_stages,created_by,updated_by)
 VALUES(tech,'Rollback capacity technician '||tech,'technician',ARRAY['FITTING','HOIST'],a,a);
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT bid,tech,'secondary',a,scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=bid;
 INSERT INTO public.workshop_settings(key,value) VALUES('technician_leave',jsonb_build_array(jsonb_build_object('technician_id',tech,'date',f+1)))
 ON CONFLICT(key) DO UPDATE SET value=public.workshop_settings.value||excluded.value;
 p:=public.replan_workshop_capacity('FITTING',998,10);
 SELECT (x->>'new_start_at')::timestamptz,(x->>'new_end_at')::timestamptz INTO start_at,end_at
  FROM jsonb_array_elements(p->'changes') x WHERE x->>'booking_id'=bid::text;
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true' AND start_at>=(f+3+time '07:00') AT TIME ZONE 'Australia/Perth'
   AND public.workshop_technician_leave_date(tech,start_at,end_at) IS NULL,'Secondary technician leave is respected on continuation day',p);
 r:=public.replan_workshop_capacity('FITTING',998,10,true,p->>'plan_hash',gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'applied'='true' AND EXISTS(SELECT 1 FROM public.workshop_booking_assignments
  WHERE booking_id=bid AND technician_id=tech AND assignment_type='secondary' AND released_at IS NULL
    AND scheduled_start_at=start_at AND scheduled_end_at=end_at),'Apply preserves secondary assignment identity and new range',r);
 -- YH without Navision ETA is eligible; effective IT still obeys ETA+7.
 b:=pg_temp.ou_bay('eligibility','FITTING'); UPDATE public.workshop_bays SET bay_number=999 WHERE id=b;
 v:=pg_temp.ou_vehicle('eligibility'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 UPDATE public.vehicles SET current_location='YH',eta_to_kewdale=NULL,location_override=NULL WHERE id=v;
 bid:=pg_temp.ou_booking('eligibility',v,'FITTING',b,(f+4+time '07:00') AT TIME ZONE 'Australia/Perth');
 p:=public.replan_workshop_capacity('FITTING',999,80);
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true','Yard Hold without ETA remains eligible',p);
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=f-4 WHERE id=v;
 p:=public.workshop_capacity_plan('FITTING',null,null,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true' AND (SELECT final_start=(f+3+time '07:00') AT TIME ZONE 'Australia/Perth'
   FROM pg_temp.workshop_capacity_plan WHERE booking_id=bid),'Compaction obeys IT ETA plus seven',p);
 UPDATE public.vehicles SET location_override='Other' WHERE id=v;
 p:=public.replan_workshop_capacity('FITTING',999,80);
 PERFORM pg_temp.ou_assert(p->>'can_apply'='false' AND p->>'error'='vehicle_not_eligible','Effective Other override blocks capacity changes',p);
 UPDATE public.vehicles SET location_override=NULL WHERE id=v;
 -- Apply only the synthetic proposed left moves, retaining all regular guards.
 p:=public.workshop_capacity_plan('FITTING',null,null,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true','Fixture compaction has safe ordering',p);
 FOR item IN SELECT * FROM pg_temp.workshop_capacity_plan
   WHERE changed AND before_row->'metadata'->>'rollback_fixture'='true' ORDER BY apply_order LOOP
  UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
    default_duration_minutes=item.minutes,version=version+1 WHERE id=item.booking_id AND version=item.version;
  UPDATE public.workshop_booking_assignments SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end
    WHERE booking_id=item.booking_id AND released_at IS NULL;
 END LOOP;
 p:=public.workshop_capacity_plan('FITTING',null,null,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true' AND NOT EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan
  WHERE changed AND before_row->'metadata'->>'rollback_fixture'='true'),'Repeated compaction has no additional synthetic changes',p);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(w)=before_fixed FROM public.workshop_bookings w WHERE id=fixed_id),'Compaction never alters fixed live work');
END $reservations$;
DO $atomic_fixture$
DECLARE a uuid; f date; b uuid; v1 uuid; v2 uuid; one_id uuid; two_id uuid;
BEGIN
 SELECT actor,friday INTO a,f FROM ou_context;
 b:=pg_temp.ou_bay('atomic','FITTING'); UPDATE public.workshop_bays SET bay_number=994 WHERE id=b;
 v1:=pg_temp.ou_vehicle('atomic-one'); PERFORM pg_temp.ou_operation(v1,'FITTING',1);
 v2:=pg_temp.ou_vehicle('atomic-two'); PERFORM pg_temp.ou_operation(v2,'FITTING',1);
 one_id:=pg_temp.ou_booking('atomic-one',v1,'FITTING',b,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 two_id:=pg_temp.ou_booking('atomic-two',v2,'FITTING',b,(f+time '08:00') AT TIME ZONE 'Australia/Perth');
END $atomic_fixture$;
CREATE FUNCTION pg_temp.reject_capacity_root() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
 IF NEW.id=(SELECT id FROM ou_refs WHERE name='booking-atomic-one') AND NEW.default_duration_minutes=75 THEN
  RAISE EXCEPTION 'Deliberate synthetic failure after follower moved';
 END IF;
 RETURN NEW;
END $f$;
CREATE TRIGGER zzz_capacity_rollback_test BEFORE UPDATE ON public.workshop_bookings
 FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_capacity_root();
DO $atomic$
DECLARE p jsonb; r jsonb; old_hist bigint; one_id uuid; two_id uuid; claims text; denied boolean:=false;
BEGIN
 SELECT id INTO one_id FROM ou_refs WHERE name='booking-atomic-one';
 SELECT id INTO two_id FROM ou_refs WHERE name='booking-atomic-two';
 SELECT count(*) INTO old_hist FROM public.workshop_booking_history WHERE booking_id IN(one_id,two_id);
 p:=public.replan_workshop_capacity('FITTING',994,80);
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true' AND (SELECT apply_order=1 FROM pg_temp.workshop_capacity_plan WHERE booking_id=two_id),
   'Atomic fixture moves downstream booking before extension',p);
 r:=public.replan_workshop_capacity('FITTING',994,80,true,p->>'plan_hash',gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'error'='capacity_apply_rejected'
  AND (SELECT bool_and(version=1 AND default_duration_minutes=60) FROM public.workshop_bookings WHERE id IN(one_id,two_id))
  AND (SELECT efficiency_percent=100 FROM public.workshop_bays WHERE id=(SELECT id FROM ou_refs WHERE name='bay-atomic'))
  AND (SELECT count(*)=old_hist FROM public.workshop_booking_history WHERE booking_id IN(one_id,two_id)),
  'A later failure rolls back bay setting, prior booking and history',r);
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('anon','public.replan_workshop_capacity(text,integer,integer,boolean,text,uuid)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.workshop_capacity_plan(text,uuid,integer,timestamptz)','EXECUTE'),
  'Only the authorized public RPC can apply a capacity plan');
 PERFORM pg_temp.ou_assert((SELECT relrowsecurity FROM pg_class WHERE oid='public.workshop_capacity_receipts'::regclass)
  AND NOT has_table_privilege('authenticated','public.workshop_capacity_receipts','INSERT,UPDATE,DELETE'),
  'Idempotency receipts cannot be edited directly');
 claims:=current_setting('request.jwt.claims',true);
 PERFORM set_config('request.jwt.claims','{}',true);
 BEGIN PERFORM public.replan_workshop_capacity('FITTING',994,80);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM set_config('request.jwt.claims',claims,true);
 PERFORM pg_temp.ou_assert(denied,'Unauthenticated capacity requests are rejected');
END $atomic$;
DROP TRIGGER zzz_capacity_rollback_test ON public.workshop_bookings;

SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o FULL JOIN public.workshop_bookings b ON b.id=o.id
 WHERE o.id IS NOT NULL AND (b.id IS NULL OR to_jsonb(b) IS DISTINCT FROM o.row_data)),
 'All pre-existing bookings are unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o FULL JOIN public.vehicles v ON v.id=o.id
 WHERE o.id IS NOT NULL AND (v.id IS NULL OR to_jsonb(v) IS DISTINCT FROM o.row_data)),
 'All pre-existing vehicles are unchanged');
SELECT jsonb_build_object('count',count(*),'results',jsonb_agg(to_jsonb(r)-'evidence' ORDER BY name),
 'timing',jsonb_agg(jsonb_build_object('scenario',name,'measurement',evidence)) FILTER(WHERE name LIKE '%timing%')) result FROM ou_results r;
ROLLBACK;
