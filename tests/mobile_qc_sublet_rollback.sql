-- STAGING integration test: every synthetic row and audit effect rolls back.
-- No existing vehicle, operation, booking, photo or customer tick is changed.
BEGIN;
SET LOCAL statement_timeout='90s';
SET LOCAL lock_timeout='5s';
CREATE TEMP TABLE qc_sublet_results(name text PRIMARY KEY, evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE qc_sublet_context(actor uuid,email text,vehicle uuid,one uuid,two uuid,zero_line uuid,workshop uuid,unmapped uuid,photo uuid) ON COMMIT DROP;
CREATE TEMP TABLE qc_sublet_original_vehicles AS SELECT id,to_jsonb(v) data FROM public.vehicles v;
CREATE TEMP TABLE qc_sublet_original_bookings AS SELECT id,to_jsonb(b) data FROM public.workshop_bookings b;
CREATE TEMP TABLE qc_sublet_original_ticks AS SELECT vehicle_id,line_identity,to_jsonb(c) data FROM public.pdc_qc_operation_completions_379 c;
CREATE TEMP TABLE qc_sublet_original_photos AS SELECT photo_receipt_id,to_jsonb(p) data FROM public.pdc_qc_finalization_photo_evidence_399 p;
CREATE FUNCTION pg_temp.qs_assert(pass boolean,label text,evidence jsonb DEFAULT '{}'::jsonb) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO qc_sublet_results VALUES(label,evidence);
END $f$;

DO $setup$
DECLARE actor_id uuid:=gen_random_uuid();email_address text;vid uuid:=gen_random_uuid();op1 uuid:=gen_random_uuid();op2 uuid:=gen_random_uuid();op0 uuid:=gen_random_uuid();opw uuid:=gen_random_uuid();opu uuid:=gen_random_uuid();
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING ONLY';END IF;
 email_address:='qc-sublet-rollback-'||actor_id||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(actor_id,'authenticated','authenticated',email_address,clock_timestamp(),'{"provider":"email","providers":["email"]}','{"full_name":"QC Sublet rollback fixture"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='operator',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=actor_id AND email=email_address;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor_id,'email',email_address,'role','authenticated')::text,true);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,current_location,visible_on_board,source_system,source_record_id,source_payload,created_by,updated_by)
 VALUES(vid,'qc-sublet-rollback-'||vid,'QC-SUBLET-'||substr(vid::text,1,8),'QC-TEST-JC','ROLLBACK FIXTURE','Synthetic QC vehicle','QC',false,'qc_sublet_rollback',vid::text,'{"rollback_fixture":true}',actor_id,actor_id);
 INSERT INTO public.vehicle_workshop_line_adjustments(adjustment_id,vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by)
 VALUES
 (op1,vid,'manual:'||op1,'manual','SUBLET','Same provider work',NULL,actor_id,actor_id),
 (op2,vid,'manual:'||op2,'manual','SUBLET','Same provider work',NULL,actor_id,actor_id),
 (op0,vid,'manual:'||op0,'manual','SUBLET','Zero hour provider work',0,actor_id,actor_id),
 (opw,vid,'manual:'||opw,'manual','FITTING','Workshop hours require review',NULL,actor_id,actor_id),
 (opu,vid,'manual:'||opu,'manual','UNALLOCATED_MAPPING_REVIEW','Unmapped work',0,actor_id,actor_id);
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed) VALUES(vid,'sublet',true,false);
 INSERT INTO qc_sublet_context VALUES(actor_id,email_address,vid,op1,op2,op0,opw,opu,gen_random_uuid());
 PERFORM pg_temp.qs_assert((SELECT count(*) FROM public.pdc_user_roles WHERE auth_user_id=actor_id AND role='operator' AND active AND account_status='approved')=1,'Approved operator fixture');
END $setup$;

CREATE FUNCTION pg_temp.qs_set(op uuid,complete boolean,idem uuid DEFAULT gen_random_uuid()) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE vid uuid;ver integer;line_ver integer;
BEGIN
 SELECT vehicle INTO vid FROM qc_sublet_context;
 SELECT version INTO ver FROM public.vehicles WHERE id=vid;
 SELECT coalesce((l->>'line_version')::integer,0) INTO line_ver FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vid)) l WHERE l->>'line_identity'='manual:'||op;
 RETURN public.set_pdc_qc_operation_completion_379(vid,ver,'manual:'||op,line_ver,idem,complete);
END $f$;

DO $test$
DECLARE c record;r jsonb;again jsonb;k uuid:=gen_random_uuid();ver integer;was_blocked boolean;before_notifications bigint;
BEGIN
 SELECT * INTO c FROM qc_sublet_context;
 SELECT count(*) INTO before_notifications FROM public.vehicle_notifications;
 PERFORM set_config('request.jwt.claims','{}',true);
 was_blocked:=false;
 BEGIN PERFORM pg_temp.qs_set(c.one,true); EXCEPTION WHEN insufficient_privilege THEN was_blocked:=SQLERRM='PDC_379_UNAUTHORIZED'; END;
 PERFORM pg_temp.qs_assert(was_blocked,'Unauthenticated ticks remain blocked');
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',c.actor,'email',c.email,'role','authenticated')::text,true);
 was_blocked:=false;
 BEGIN PERFORM pg_temp.qs_set(c.workshop,true);EXCEPTION WHEN invalid_parameter_value THEN was_blocked:=SQLERRM='PDC_379_LINE_HOURS_UNKNOWN';END;
 PERFORM pg_temp.qs_assert(was_blocked,'Workshop lines still require known hours');
 was_blocked:=false;
 BEGIN PERFORM pg_temp.qs_set(c.unmapped,true);EXCEPTION WHEN invalid_parameter_value THEN was_blocked:=SQLERRM='PDC_379_LINE_UNKNOWN_OR_INACTIVE';END;
 PERFORM pg_temp.qs_assert(was_blocked,'Unmapped lines remain blocked');

 SELECT version INTO ver FROM public.vehicles WHERE id=c.vehicle;
 r:=pg_temp.qs_set(c.one,true,k);
 PERFORM pg_temp.qs_assert(r->>'ok'='true' AND r#>>'{line,stage_code}'='SUBLET' AND r->>'department_complete'='false','First null-hour Sublet tick saves independently',r);
 again:=public.set_pdc_qc_operation_completion_379(c.vehicle,ver,'manual:'||c.one,0,k,true);
 PERFORM pg_temp.qs_assert(again->>'replay'='true' AND (SELECT count(*) FROM public.pdc_qc_operation_completion_history_379 WHERE vehicle_id=c.vehicle)=1,'Retry replays one audited tick');
 was_blocked:=false;
 BEGIN PERFORM public.set_pdc_qc_operation_completion_379(c.vehicle,ver,'manual:'||c.two,0,gen_random_uuid(),true);EXCEPTION WHEN serialization_failure THEN was_blocked:=SQLERRM='PDC_379_VEHICLE_VERSION_CONFLICT';END;
 PERFORM pg_temp.qs_assert(was_blocked,'Stale vehicle version remains blocked');
 SELECT version INTO ver FROM public.vehicles WHERE id=c.vehicle;
 was_blocked:=false;
 BEGIN PERFORM public.set_pdc_qc_operation_completion_379(c.vehicle,ver,'manual:'||c.one,0,gen_random_uuid(),true);EXCEPTION WHEN serialization_failure THEN was_blocked:=SQLERRM='PDC_379_LINE_VERSION_CONFLICT';END;
 PERFORM pg_temp.qs_assert(was_blocked,'Stale line version remains blocked');

 r:=pg_temp.qs_set(c.two,true);
 PERFORM pg_temp.qs_assert(r->>'ok'='true' AND r->>'department_complete'='false','Second null-hour Sublet stays distinct from duplicate description',r);
 r:=pg_temp.qs_set(c.zero_line,true);
 PERFORM pg_temp.qs_assert(r->>'ok'='true' AND r->>'department_complete'='true' AND (SELECT completed FROM public.vehicle_work_items WHERE vehicle_id=c.vehicle AND work_key='sublet'),'Zero-hour Sublet completes department only when every item is ticked',r);
 r:=pg_temp.qs_set(c.one,false);
 PERFORM pg_temp.qs_assert(r->>'ok'='true' AND r->>'department_complete'='false' AND NOT(SELECT completed FROM public.vehicle_work_items WHERE vehicle_id=c.vehicle AND work_key='sublet'),'Unticking Sublet clears department completion',r);

 -- Unknown workshop and mapping fixtures are deliberately inactive for signoff;
 -- they were never ticked, and their unknown hours are not rewritten to zero.
 UPDATE public.vehicle_workshop_line_adjustments SET active=false WHERE adjustment_id IN(c.workshop,c.unmapped);
 SELECT version INTO ver FROM public.vehicles WHERE id=c.vehicle;
 r:=public.finalize_pdc_qc_to_rft_700(c.vehicle,ver,c.photo,gen_random_uuid());
 PERFORM pg_temp.qs_assert(r->>'code'='qc_photo_receipt_required','QC photo remains mandatory');

 INSERT INTO public.pdc_qc_finalization_photo_evidence_399(photo_receipt_id,vehicle_id,uploader_id,uploader_email,idempotency_key,expected_vehicle_version,
  bucket_id,storage_path,original_filename,content_type,original_byte_length,byte_length,image_width,image_height,sha256,request_sha256,response)
 VALUES(c.photo,c.vehicle,c.actor,c.email,gen_random_uuid(),ver,'pdc-qc-evidence-staging',
  'qc-finalization/'||c.actor||'/'||c.vehicle||'/rollback-fixture.png','rollback-fixture.png','image/png',1,1,1,1,repeat('a',64),repeat('b',64),'{}');

 r:=public.finalize_pdc_qc_to_rft_700(c.vehicle,ver,c.photo,gen_random_uuid());
 PERFORM pg_temp.qs_assert(r->>'code'='qc_operation_lines_incomplete','Photo cannot bypass an unticked Sublet item',r);
 r:=pg_temp.qs_set(c.one,true);
 PERFORM pg_temp.qs_assert(r->>'department_complete'='true','Reticking Sublet restores department completion');
 PERFORM pg_temp.qs_assert((SELECT count(*) FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(c.vehicle)) l WHERE l->>'stage_code'='SUBLET' AND l->>'estimated_hours' IS NULL)=2,'Null Sublet hours are preserved');

 -- Test the trigger separately from the signoff RPC, in a nested rollback block.
 BEGIN
  UPDATE public.pdc_qc_operation_completions_379 SET completed=false,completed_at=NULL,completed_by=NULL WHERE vehicle_id=c.vehicle AND line_identity='manual:'||c.two;
  was_blocked:=false;
  BEGIN UPDATE public.vehicles SET qc_completed_at=clock_timestamp(),qc_completed_by=c.actor WHERE id=c.vehicle;
  EXCEPTION WHEN check_violation THEN was_blocked:=SQLERRM='PDC_QC_OPERATION_LINES_INCOMPLETE_OR_UNKNOWN';END;
  IF NOT was_blocked THEN RAISE EXCEPTION 'Trigger accepted an unticked Sublet';END IF;
  RAISE EXCEPTION USING errcode='PZ001',message='rollback nested trigger fixture';
 EXCEPTION WHEN SQLSTATE 'PZ001' THEN NULL;END;
 PERFORM pg_temp.qs_assert(true,'Database signoff trigger still blocks unticked Sublet');

 SELECT version INTO ver FROM public.vehicles WHERE id=c.vehicle;
 r:=public.finalize_pdc_qc_to_rft_700(c.vehicle,ver,c.photo,gen_random_uuid());
 PERFORM pg_temp.qs_assert(r->>'ok'='true' AND r->>'code'='qc_signed_off_moved_to_rft' AND
  (SELECT current_location='RFT' AND lifecycle_state='rft' AND qc_completed_at IS NOT NULL AND version=ver+2 FROM public.vehicles WHERE id=c.vehicle),
  'All checked null/zero-hour Sublet items allow photo-backed QC signoff',r);
 PERFORM pg_temp.qs_assert((SELECT count(*) FROM public.vehicle_notifications)=before_notifications,'QC ticks and signoff send no notifications');
 PERFORM pg_temp.qs_assert((SELECT count(*) FROM public.workshop_bookings WHERE vehicle_id=c.vehicle)=0,'QC Sublet ticks create no workshop bookings');
END $test$;

DO $unchanged$
BEGIN
 PERFORM pg_temp.qs_assert(NOT EXISTS(SELECT 1 FROM qc_sublet_original_vehicles o LEFT JOIN public.vehicles v ON v.id=o.id WHERE to_jsonb(v) IS DISTINCT FROM o.data),'Existing vehicle records unchanged');
 PERFORM pg_temp.qs_assert(NOT EXISTS(SELECT 1 FROM qc_sublet_original_bookings o LEFT JOIN public.workshop_bookings b ON b.id=o.id WHERE to_jsonb(b) IS DISTINCT FROM o.data),'Existing bookings unchanged');
 PERFORM pg_temp.qs_assert(NOT EXISTS(SELECT 1 FROM qc_sublet_original_ticks o LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=o.vehicle_id AND c.line_identity=o.line_identity WHERE to_jsonb(c) IS DISTINCT FROM o.data),'Existing customer QC ticks unchanged');
 PERFORM pg_temp.qs_assert(NOT EXISTS(SELECT 1 FROM qc_sublet_original_photos o LEFT JOIN public.pdc_qc_finalization_photo_evidence_399 p ON p.photo_receipt_id=o.photo_receipt_id WHERE to_jsonb(p) IS DISTINCT FROM o.data),'Existing QC photos unchanged');
 PERFORM pg_temp.qs_assert(has_function_privilege('authenticated','public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)','EXECUTE')
 AND NOT has_function_privilege('anon','public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)','EXECUTE'),'QC function access remains restricted');
END $unchanged$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT jsonb_build_object('passed',count(*),'checks',jsonb_agg(jsonb_build_object('name',name,'evidence',evidence))) AS result FROM qc_sublet_results;
ROLLBACK;
