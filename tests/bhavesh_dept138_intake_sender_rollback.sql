-- Run against STAGING with the migration installed (or prepended inside this
-- transaction). All rows, receipts, status writes and test evidence roll back.
-- Header strings below are synthetic UNIT-TEST fixtures, never inbox evidence.
-- No JWT claims, session role, authorization rows or auth.users values are changed.
BEGIN;
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
DO $test$
DECLARE actor uuid; v138 uuid:=gen_random_uuid(); v139 uuid:=gen_random_uuid(); vmix uuid:=gen_random_uuid(); vu uuid:=gen_random_uuid();
 j138 uuid; j139 uuid; jm uuid; a jsonb; bad jsonb; envelope jsonb; rows jsonb; response jsonb; replay jsonb;
 service_rows jsonb; rows_digest text; workbook_hash text:=repeat('b',64); message_id text:='abcdef0123456789';
 manifest_hash text:=encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex');
 prior_ops text; prior_bookings text; vehicle_count bigint; job_count bigint; denied boolean; old_flags jsonb;
BEGIN
 IF NOT pdc_codex_intake_private.management_connection() THEN RAISE EXCEPTION 'Real staging management connection required'; END IF;
 SELECT actor_id INTO STRICT actor FROM pdc_codex_intake_private.management_email_manifests WHERE sender='craig.watson@broometoyota.com.au' ORDER BY created_at DESC LIMIT 1;
 IF EXISTS(SELECT 1 FROM public.vehicles WHERE stock_number IN ('91909001','91909002','91909003','91909004')) THEN RAISE EXCEPTION 'Fixture stock collision'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(o) ORDER BY o.operation_id),'[]')::text) INTO prior_ops FROM public.pdc_pilbara_service_operations o;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]')::text) INTO prior_bookings FROM public.workshop_bookings b;
 a:=jsonb_build_object('gmail_message_id',message_id,'from_address','bhavesh.patel@pmgwa.com.au','mailbox','pmbcontroller@gmail.com',
  'to_address','pmbcontroller@gmail.com','verified_by','gmail_receiving_provider','header_from','pmgwa.com.au',
  'authentication_results','mx.google.com; dkim=pass header.i=@pmgwa.com.au; spf=pass smtp.mailfrom=pmgwa.com.au',
  'human_message',true,'unquoted_affirmative',true,'auto_submitted','no');
 IF NOT pdc_codex_intake_private.bhavesh_email_authenticated_20260923(a,message_id)
 OR NOT pdc_codex_intake_private.bhavesh_email_authenticated_20260923(a||'{"authentication_results":"mx.google.com; dmarc=pass header.from=pmgwa.com.au"}',message_id)
 THEN RAISE EXCEPTION 'Aligned DKIM/direct DMARC rejected'; END IF;
 FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
   a||'{"from_address":"other@pmgwa.com.au"}',a||'{"gmail_message_id":"abcdef0123456780"}',a||'{"mailbox":"other@gmail.com"}',
   a||'{"authentication_results":"untrusted.example; dkim=pass header.d=pmgwa.com.au"}',
   a||'{"authentication_results":"mx.google.com; spf=pass smtp.mailfrom=pmgwa.com.au"}',
   a||'{"authentication_results":"mx.google.com; dkim=pass header.d=pmgwa.com.au.evil.example"}',
   a||'{"authentication_results":"mx.google.com; dkim=pass header.d=evil.example"}',a||'{"reply_to":"someone@pmgwa.com.au"}')) LOOP
  IF pdc_codex_intake_private.bhavesh_email_authenticated_20260923(bad,message_id) THEN RAISE EXCEPTION 'Unbound/unaligned sender accepted'; END IF;
 END LOOP;
 IF has_function_privilege('authenticated','pdc_codex_intake_private.bhavesh_email_authenticated_20260923(jsonb,text)','EXECUTE')
 OR has_function_privilege('anon','public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)','EXECUTE')
 OR has_function_privilege('service_role','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'Unexpected caller privileges'; END IF;

 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,current_location,source_system,source_record_id,source_payload,visible_on_board,created_by,updated_by,model)
 SELECT id,'BHAVESH-ROLLBACK-'||id,stock,'Synthetic intake rollback fixture','PMB','tune_pmg',stock,'{"fixture":"bhavesh_intake_rollback"}',true,actor,actor,'Toyota HiAce'
 FROM (VALUES(v138,'91909001'),(v139,'91909002'),(vmix,'91909003'),(vu,'91909004')) f(id,stock);
 INSERT INTO pdc_parts_private.jobs(vehicle_id,source_system,company,division,stock_number,ro_number,departments,service_seen_at)
 VALUES(v138,'tune_pmg','01','1','91909001','J138999901',ARRAY['138'],now()),
       (v139,'tune_pmg','01','1','91909002','J139999902',ARRAY['139'],now()),
       (vmix,'tune_pmg','01','1','91909003','J138999903',ARRAY['138','139'],now()),
       (vu,'tune_pmg','01','1','91909004','J138999904',ARRAY[]::text[],now());
 SELECT id INTO j138 FROM pdc_parts_private.jobs WHERE vehicle_id=v138;
 SELECT id INTO j139 FROM pdc_parts_private.jobs WHERE vehicle_id=v139;
 SELECT id INTO jm FROM pdc_parts_private.jobs WHERE vehicle_id=vmix;
 IF NOT pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(v138)
 OR pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(v139)
 OR pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(vmix)
 OR pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(vu)
 OR pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(gen_random_uuid())
 THEN RAISE EXCEPTION 'Vehicle scope guard failed'; END IF;
 INSERT INTO pdc_parts_private.jobs(vehicle_id,source_system,company,division,stock_number,ro_number,departments,service_seen_at,closed_at)
 VALUES(v138,'tune_pmg','01','1','91909001','J139999999',ARRAY['139'],now(),now());
 IF NOT pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(v138) THEN RAISE EXCEPTION 'Historical R/O blocked active Dept138 scope'; END IF;
 UPDATE pdc_parts_private.jobs SET closed_at=NULL WHERE vehicle_id=v138 AND ro_number='J139999999';
 IF pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(v138) THEN RAISE EXCEPTION 'Second active Dept139 R/O not detected'; END IF;
 UPDATE pdc_parts_private.jobs SET closed_at=now() WHERE vehicle_id=v138 AND ro_number='J139999999';

 service_rows:=jsonb_build_array(jsonb_build_object('department','138','stock_number','91909001','repair_order_number','J138999901','workbook_sha256',workbook_hash,
  'raw_row',jsonb_build_object('Company','01','Division','1','Dept',138,'R/O #','J138999901','from_address','bhavesh.patel@pmgwa.com.au',
  'gmail_message_id',message_id,'parent_attachment_sha256',workbook_hash)));
 IF NOT pdc_codex_intake_private.bhavesh_service_scope_20260923(service_rows)
 OR pdc_codex_intake_private.bhavesh_service_scope_20260923(jsonb_set(service_rows,'{0,department}','"139"'))
 OR pdc_codex_intake_private.bhavesh_service_scope_20260923(jsonb_set(service_rows,'{0,raw_row,Dept}','139'))
 OR pdc_codex_intake_private.bhavesh_service_scope_20260923(jsonb_set(service_rows,'{0,raw_row,Company}','"02"'))
 OR pdc_codex_intake_private.bhavesh_service_scope_20260923(jsonb_set(service_rows,'{0,stock_number}','"91909002"'))
 THEN RAISE EXCEPTION 'Service payload/current scope failed'; END IF;
 rows_digest:=encode(extensions.digest(service_rows::text,'sha256'),'hex');
 INSERT INTO pdc_codex_intake_private.management_email_manifests(source_hash,workbook_sha256,server_rows_sha256,source_rows,mailbox,sender,gmail_message_id,filename,actor_id,approval_evidence,provenance)
 VALUES(manifest_hash,workbook_hash,rows_digest,1,'pmbcontroller@gmail.com','bhavesh.patel@pmgwa.com.au',message_id,'synthetic-rollback.xlsx',actor,
  'Synthetic rollback test for owner-delegated Department 138 authority',jsonb_build_object('source_kind','gmail_attachment','authentication',a));
 denied:=false;
 BEGIN
  UPDATE pdc_codex_intake_private.management_email_manifests SET provenance='{}' WHERE source_hash=manifest_hash;
 EXCEPTION WHEN check_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unauthenticated Bhavesh manifest accepted'; END IF;
 -- The disabled actor remains disabled; an existing active actor may exercise
 -- positive preview binding. The test never enables or impersonates an account.
 IF pdc_codex_intake_private.import_actor()=actor THEN
  IF NOT pdc_codex_intake_private.management_authorized('preview',service_rows,manifest_hash,'codex-owner-email-preview-'||manifest_hash,NULL)
   OR pdc_codex_intake_private.management_authorized('preview',jsonb_set(service_rows,'{0,department}','"139"'),manifest_hash,'codex-owner-email-preview-'||manifest_hash,NULL)
   OR pdc_codex_intake_private.management_authorized('preview',service_rows,manifest_hash,'wrong-key',NULL)
  THEN RAISE EXCEPTION 'Management manifest/digest binding failed'; END IF;
 ELSE
  IF pdc_codex_intake_private.management_authorized('preview',service_rows,manifest_hash,'codex-owner-email-preview-'||manifest_hash,NULL)
  THEN RAISE EXCEPTION 'Disabled importer actor was bypassed'; END IF;
  RAISE NOTICE 'Positive management preview requires separately authorised active importer; disabled-account denial passed';
 END IF;

 SELECT count(*) INTO vehicle_count FROM public.vehicles;
 SELECT count(*) INTO job_count FROM pdc_parts_private.jobs;
 envelope:=jsonb_build_object('source_kind','gmail_csv','source_system','tune_pmg','company','01','division','1',
  'subject','PMG PD Parts Status','mailbox','pmbcontroller@gmail.com','sender','bhavesh.patel@pmgwa.com.au',
  'sender_verified',true,'authentication_results',a->>'authentication_results','authentication',a,'gmail_message_id',message_id,
  'attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'),'snapshot_at',now()-interval '2 days','received_at',now()-interval '1 day');
 rows:='[{"Dept":138,"R/O #":"J138999901","Parts Attached":1,"Parts on Backorder":1,"Backorder with PO (1=Yes, 0=No)":1}]';
 response:=public.pdc_import_job_parts_csv_20260912(envelope,rows);
 IF response->>'ok'<>'true' OR response->>'updated'<>'1' OR (SELECT backorder FROM pdc_parts_private.jobs WHERE id=j138)<>1
 THEN RAISE EXCEPTION 'Authenticated matching parts update failed %',response; END IF;
 replay:=public.pdc_import_job_parts_csv_20260912(envelope,rows);
 IF replay->>'replay'<>'true' OR replay->>'receipt_id'<>response->>'receipt_id' THEN RAISE EXCEPTION 'Replay created a new receipt'; END IF;
 response:=public.pdc_import_job_parts_csv_20260912(envelope,jsonb_set(rows,'{0,Dept}','139'));
 IF response->>'code'<>'department_138_scope_required' THEN RAISE EXCEPTION 'Dept139 payload accepted %',response; END IF;
 response:=public.pdc_import_job_parts_csv_20260912(envelope-'authentication',rows);
 IF response->>'code'<>'invalid_or_unverified_envelope' THEN RAISE EXCEPTION 'Missing authenticated evidence accepted'; END IF;
 envelope:=envelope||jsonb_build_object('attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'),'snapshot_at',now()-interval '1 day 1 hour');
 rows:=jsonb_set(jsonb_set(rows,'{0,Parts on Backorder}','0'),ARRAY['0','Backorder with PO (1=Yes, 0=No)'],'0');
 response:=public.pdc_import_job_parts_csv_20260912(envelope,rows);
 IF response->>'updated'<>'1' OR (SELECT backorder FROM pdc_parts_private.jobs WHERE id=j138)<>0
 OR public.pdc_parts_flags_vehicle_20260911(v138)->>'colour'<>'green' THEN RAISE EXCEPTION 'Backorder clearing failed %',response; END IF;
 FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
   jsonb_set(rows,'{0,R/O #}','"J138999998"'),jsonb_set(rows,'{0,R/O #}','"J138999903"'),jsonb_set(rows,'{0,Parts Attached}','"All"'))) LOOP
  response:=public.pdc_import_job_parts_csv_20260912(envelope||jsonb_build_object('attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex')),bad);
  IF response->>'updated'<>'0' OR response->>'unchanged'<>'0' THEN RAISE EXCEPTION 'Unmatched/mixed/invalid row wrote flags %',response; END IF;
 END LOOP;
 response:=public.pdc_import_job_parts_csv_20260912(envelope||jsonb_build_object('company','02','attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex')),rows);
 IF response->>'unmatched'<>'1' THEN RAISE EXCEPTION 'Cross-company R/O matched'; END IF;
 response:=public.pdc_import_job_parts_csv_20260912(envelope||jsonb_build_object('snapshot_at',now()-interval '3 days','attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex')),rows);
 IF response->>'stale'<>'1' THEN RAISE EXCEPTION 'Old snapshot accepted'; END IF;
 -- Craig's established flat envelope and Department139 route remain unchanged.
 response:=public.pdc_import_job_parts_csv_20260912((envelope-'authentication')||jsonb_build_object('sender','craig.watson@broometoyota.com.au',
   'attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex')),
   '[{"Dept":139,"R/O #":"J139999902","Parts Attached":1,"Parts on Backorder":0,"Backorder with PO (1=Yes, 0=No)":0}]');
 IF response->>'updated'<>'1' THEN RAISE EXCEPTION 'Craig legacy envelope regressed %',response; END IF;
 IF (SELECT parts_attached FROM pdc_parts_private.jobs WHERE id=jm) IS NOT NULL
 OR (SELECT backorder FROM pdc_parts_private.jobs WHERE id=j138)<>0
 OR (SELECT count(*) FROM public.vehicles)<>vehicle_count OR (SELECT count(*) FROM pdc_parts_private.jobs)<>job_count
 THEN RAISE EXCEPTION 'Unrelated data or absent job changed / board record created'; END IF;

 response:=public.record_pdc_person_parts_complete_20260913('91909002',message_id,now()-interval '1 hour','Synthetic test','parts complete for 91909002',repeat('a',64),a);
 IF response->>'code'<>'department_138_vehicle_scope_required' THEN RAISE EXCEPTION 'Person override crossed Dept139 scope %',response; END IF;
 response:=public.record_pdc_person_parts_complete_20260913('91909003',message_id,now()-interval '1 hour','Synthetic test','parts complete for 91909003',repeat('a',64),a);
 IF response->>'code'<>'department_138_vehicle_scope_required' THEN RAISE EXCEPTION 'Person override crossed mixed scope %',response; END IF;
 response:=public.record_pdc_person_parts_complete_20260913('91909001',message_id,now()-interval '1 hour','Synthetic test','parts complete for 91909001',repeat('a',64),a);
 IF response->>'ok'<>'true' OR response#>>'{parts_status,person_confirmed}'<>'true'
 THEN RAISE EXCEPTION 'Exact Dept138 person confirmation failed %',response; END IF;
 replay:=public.record_pdc_person_parts_complete_20260913('91909001',message_id,now()-interval '1 hour','Synthetic test','parts complete for 91909001',repeat('a',64),a);
 IF replay->>'replay'<>'true' THEN RAISE EXCEPTION 'Person confirmation not idempotent'; END IF;
 IF (SELECT md5(coalesce(jsonb_agg(to_jsonb(o) ORDER BY o.operation_id),'[]')::text) FROM public.pdc_pilbara_service_operations o)<>prior_ops
 OR (SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]')::text) FROM public.workshop_bookings b)<>prior_bookings
 THEN RAISE EXCEPTION 'Parts route changed operations or bookings'; END IF;
END $test$;
SELECT 'Bhavesh authentication, scope, parts, confirmation and regression tests passed; all fixtures rolled back' AS result;
ROLLBACK;
