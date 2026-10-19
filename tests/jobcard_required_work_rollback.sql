BEGIN;
-- DISPOSABLE LOCAL DATABASE ONLY. Synthetic actor, vehicles, operations and bays.
-- Department retry also exercises the copied backlog. Everything rolls back.
-- Run this complete file in one connection after the operation-approval migration.

SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'Australia/Perth';

DO $guard$
BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN
  RAISE EXCEPTION 'Disposable loopback database required';
 END IF;
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

-- This regression graph deliberately covers a configured Saturday shift.
-- Keep its calendar fixture independent of the deployed Monday-Friday calendar.
-- Both this setting and every synthetic record are undone by the final ROLLBACK.
UPDATE public.workshop_settings
SET value='["monday","tuesday","wednesday","thursday","friday","saturday"]'::jsonb
WHERE key='working_week';
UPDATE public.workshop_settings
SET value='[{"scope":"saturday","start":"07:00","end":"08:00"},{"scope":"saturday","start":"12:00","end":"17:00"}]'::jsonb
WHERE key='break_windows';

CREATE TEMP TABLE ou_context(actor uuid, email text, friday date, batch uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE ou_source_order;
CREATE TEMP TABLE ou_refs(name text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ou_results(name text PRIMARY KEY, status text, evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE ou_original_bookings AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b;
CREATE TEMP TABLE ou_original_vehicles AS SELECT id,to_jsonb(v) row_data FROM public.vehicles v;
CREATE TEMP TABLE ou_original_reviews AS SELECT change_id,status FROM public.pdc_tune_operation_change_reviews;

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

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1,dept text DEFAULT '139',descr text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;

 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department',dept,'operation_description',coalesce(descr,'Fixture work '||stage||' line '||line_no),'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station',stage,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{"Company":"01","Division":"1"}','insert','rollback_original',vid);
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 VALUES(op,'pilbara_service_open_jobcards_v1',v.stock_number,v.job_card_number,line_no,line_no,vid,p->>'operation_description',hrs,hrs,'source_explicit','review','Review',repeat('c',64),ev,dept,stage);
 RETURN op;
END $fn$;


DO $test$ DECLARE v uuid; v2 uuid; op uuid; n integer; copied uuid; repaired integer:=0;
BEGIN
 v:=pg_temp.ou_vehicle('requirements');
 op:=pg_temp.ou_operation(v,'ELECTRICAL',0);
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v AND work_key='electrical' AND required AND NOT completed),'Source insert creates requirement even with zero hours');
 PERFORM pg_temp.ou_assert(array_to_string(public.pdc_qc_gate_issues(v),',') LIKE '%outstanding_required_work%','Unbooked work blocks QC');
 PERFORM pg_temp.ou_assert(pdc_operation_updates_private.ensure_required_work_20261019(v)=0,'Reconciliation is idempotent');
 UPDATE public.vehicle_work_items SET completed=true WHERE vehicle_id=v AND work_key='electrical';
 PERFORM pdc_operation_updates_private.ensure_required_work_20261019(v);
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v AND completed),'Existing completion retained');
 v2:=pg_temp.ou_vehicle('missing-summary');
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile','407',true);
 op:=pg_temp.ou_operation(v2,'FITTING',1);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile','',true);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v2),'Missing-summary regression fixture');
 PERFORM pg_temp.ou_assert('unresolved_jobcard_work'=ANY(public.pdc_qc_gate_issues(v2)),'Server QC refuses missing summary');
 n:=pdc_operation_updates_private.ensure_required_work_20261019(v2);
 PERFORM pg_temp.ou_assert(n=1 AND EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v2 AND work_key='fitting' AND required),'Repair restores required summary');
 PERFORM pg_temp.ou_assert(NOT ('unresolved_jobcard_work'=ANY(public.pdc_qc_gate_issues(v2))) AND array_to_string(public.pdc_qc_gate_issues(v2),',') LIKE '%outstanding_required_work%','Repair retains outstanding QC restriction');
 v2:=pg_temp.ou_vehicle('initial-intake');
 UPDATE public.pdc_new_vehicle_reviews SET status='pending',approved_at=NULL,approved_by=NULL WHERE vehicle_id=v2;
 op:=pg_temp.ou_operation(v2,'TINT',1);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v2),'Pending intake remains gated');
 UPDATE public.pdc_new_vehicle_reviews SET status='approved',approved_at=clock_timestamp(),approved_by=(SELECT actor FROM ou_context) WHERE vehicle_id=v2;
 UPDATE public.vehicles SET visible_on_board=true WHERE id=v2;
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v2 AND work_key='tint' AND required),'Initial acceptance and visibility synchronize');
 v2:=pg_temp.ou_vehicle('unclassified');
 op:=pg_temp.ou_operation(v2,'REVIEW',0,1,'139','Synthetic unspecified work');
 PERFORM pg_temp.ou_assert('unresolved_jobcard_work'=ANY(public.pdc_qc_gate_issues(v2)),'Unclassified operations block server QC');
 FOR copied IN SELECT x.id FROM public.vehicles x
 WHERE x.deleted_at IS NULL AND x.lifecycle_state='active' AND x.visible_on_board AND x.qc_completed_at IS NULL
  AND upper(coalesce(x.current_location,'')) NOT IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
  AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=x.id AND r.status='approved')
  AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=x.id AND o.department IN('138','139'))
  AND NOT EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=x.id)
 ORDER BY x.id LIMIT 20 LOOP
  repaired:=repaired+pdc_operation_updates_private.ensure_required_work_20261019(copied);
 END LOOP;
 PERFORM pg_temp.ou_assert(repaired>0,'Copied missing summaries repair through canonical operations',jsonb_build_object('requirements',repaired));
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='pdc_classified_required_work_20261019'),'Classification completion hook installed');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'No existing booking altered');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles b USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'No existing vehicle altered');
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('authenticated','pdc_operation_updates_private.ensure_required_work_20261019(uuid)','execute'),'Browser cannot invoke reconciliation');
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT name,status FROM ou_results;
ROLLBACK;
