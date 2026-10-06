-- Adds the observed job-level Changed Recently variant; omissions never clear jobs.
-- Owner-requested Revolution parts email support, STAGING Department 138 only.
-- This automated numeric feed is never a person's physical-parts confirmation.
-- Caller remains the existing management connection; no grants/accounts change.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR pdc_codex_intake_private.management_connection() IS NOT TRUE
 THEN RAISE EXCEPTION 'staging_management_connection_required'; END IF;
 IF md5(pg_get_functiondef('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)'::regprocedure))<>'df4bd409400fd85f60bd1afb9a2729ac'
 THEN RAISE EXCEPTION 'Parts importer changed since review'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_auth jsonb,p_message_id text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog
AS $function$
 SELECT coalesce(jsonb_typeof(p_auth)='object'
  AND p_message_id ~ '^[a-f0-9]{10,40}$' AND p_auth->>'gmail_message_id'=p_message_id
  AND p_auth->>'from_address'='noreply@revolutionsoftware.com.au'
  AND p_auth->>'mailbox'='pmbcontroller@gmail.com' AND (p_auth->>'to_address'='pmbcontroller@gmail.com' OR (p_auth->>'to_address'='craig.watson@broometoyota.com.au' AND p_auth->'cc_addresses' @> '["pmbcontroller@gmail.com"]'::jsonb))
  AND p_auth->>'verified_by'='gmail_receiving_provider' AND p_auth->>'header_from'='revolutionsoftware.com.au'
  AND coalesce(nullif(p_auth->>'reply_to',''),'noreply@revolutionsoftware.com.au')='noreply@revolutionsoftware.com.au'
  AND p_auth->>'authentication_results' ~* '^mx[.]google[.]com;'
  AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*spf=pass[^;]*smtp[.]mailfrom=noreply@revolutionsoftware[.]com[.]au([;[:space:]]|$)'
  AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from=revolutionsoftware[.]com[.]au([;[:space:]]|$)',false);
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_import_job_parts_csv_20260912(p_envelope jsonb, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pdc_parts_private'
AS $function$
DECLARE rec pdc_parts_private.receipts%rowtype; j pdc_parts_private.jobs%rowtype; x record; n integer;
 a integer;b integer;p integer; outcome text;reason text; target uuid; candidates uuid[];
 snap timestamptz; received timestamptz; reqhash text; resp jsonb; kind text; bhavesh boolean:=false; revolution boolean:=false;
BEGIN
 IF pdc_codex_intake_private.management_connection() IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
 kind:=coalesce(p_envelope->>'source_kind','gmail_csv');
 IF p_envelope->>'source_system' IS DISTINCT FROM 'tune_pmg' OR nullif(p_envelope->>'company','') IS NULL OR nullif(p_envelope->>'division','') IS NULL
 OR coalesce(p_envelope->>'attachment_sha256','') !~ '^[a-f0-9]{64}$'
 OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 10000
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_report_envelope'); END IF;
 IF kind IN ('gmail_csv','authorised_gmail_workbook') THEN
  IF (kind='gmail_csv' AND p_envelope->>'subject' IS DISTINCT FROM 'PMG PD Parts Status')
  OR (kind='authorised_gmail_workbook' AND (p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request' OR length(coalesce(p_envelope->>'user_instruction',''))<20 OR nullif(p_envelope->>'subject','') IS NULL OR coalesce(p_envelope->>'source_file','') !~* '[.]xlsx$')) OR p_envelope->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
  OR coalesce(p_envelope->>'sender','') NOT IN ('craig.watson@broometoyota.com.au','bhavesh.patel@pmgwa.com.au')
  OR p_envelope->>'sender_verified' IS DISTINCT FROM 'true' OR nullif(p_envelope->>'authentication_results','') IS NULL
  OR coalesce(p_envelope->>'gmail_message_id','') !~ '^[a-f0-9]{10,40}$'
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_or_unverified_envelope'); END IF;
  bhavesh:=p_envelope->>'sender'='bhavesh.patel@pmgwa.com.au';
  IF bhavesh AND (NOT pdc_codex_intake_private.bhavesh_email_authenticated_20260923(p_envelope->'authentication',p_envelope->>'gmail_message_id')
   OR p_envelope->>'authentication_results' IS DISTINCT FROM p_envelope->'authentication'->>'authentication_results')
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_or_unverified_envelope'); END IF;
  IF bhavesh AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) z WHERE z->>'Dept' IS DISTINCT FROM '138')
  THEN RETURN jsonb_build_object('ok',false,'code','department_138_scope_required'); END IF;
 ELSIF kind='revolution_automated_parts_workbook' THEN
  revolution:=true;
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
   OR p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request'
   OR length(coalesce(p_envelope->>'user_instruction',''))<20
   OR NOT coalesce((p_envelope->>'subject'='PMG PD Parts Status Complete - Pilbara'
      AND p_envelope->>'source_file' ~ '^PMG PD Parts Status Complete[.]xlsx?$')
    OR (p_envelope->>'subject'='PMG PD Parts Status'
      AND p_envelope->>'source_file' ~ '^PMG PD Parts Status V1 - Job 1[.]xlsx?$'),false)
   OR p_envelope->>'source_format' IS DISTINCT FROM 'ooxml_workbook'
   OR p_envelope->>'company' IS DISTINCT FROM '01' OR p_envelope->>'division' IS DISTINCT FROM '1'
   OR p_envelope->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
   OR p_envelope->>'sender' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
   OR p_envelope->>'sender_verified' IS DISTINCT FROM 'true'
   OR NOT pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_envelope->'authentication',p_envelope->>'gmail_message_id')
   OR p_envelope->>'authentication_results' IS DISTINCT FROM p_envelope->'authentication'->>'authentication_results'
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_or_unverified_envelope'); END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) z WHERE z->>'Dept' IS DISTINCT FROM '138')
  THEN RETURN jsonb_build_object('ok',false,'code','department_138_scope_required'); END IF;
 ELSIF kind='user_attached_workbook' THEN
  IF p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request'
  OR nullif(p_envelope->>'attachment_id','') IS NULL OR nullif(p_envelope->>'source_file','') IS NULL
  OR length(coalesce(p_envelope->>'user_instruction',''))<20
  OR p_envelope ? 'gmail_message_id' OR p_envelope ? 'sender_verified' OR p_envelope ? 'mailbox'
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_direct_attachment_evidence'); END IF;
 ELSE RETURN jsonb_build_object('ok',false,'code','unsupported_report_origin'); END IF;
 BEGIN snap:=(p_envelope->>'snapshot_at')::timestamptz;
  received:=CASE WHEN kind IN ('gmail_csv','authorised_gmail_workbook','revolution_automated_parts_workbook') THEN (p_envelope->>'received_at')::timestamptz ELSE NULL END;
 EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'code','invalid_snapshot_time'); END;
 IF snap IS NULL OR snap>clock_timestamp()+interval '5 minutes'
 OR (kind IN ('gmail_csv','authorised_gmail_workbook','revolution_automated_parts_workbook') AND (received IS NULL OR snap>received+interval '5 minutes' OR received>clock_timestamp()+interval '5 minutes'))
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_snapshot_time'); END IF;
 reqhash:=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'source',p_envelope->>'source_system','company',p_envelope->>'company','division',p_envelope->>'division','snapshot',snap)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO rec FROM pdc_parts_private.receipts WHERE source_system=p_envelope->>'source_system'
 AND company=p_envelope->>'company' AND division=p_envelope->>'division' AND attachment_sha256=p_envelope->>'attachment_sha256';
 IF FOUND THEN
 IF rec.request_hash<>reqhash THEN RETURN jsonb_build_object('ok',false,'code','attachment_replay_conflict');END IF;
 RETURN rec.response||jsonb_build_object('replay',true);END IF;
 INSERT INTO pdc_parts_private.receipts(source_kind,mailbox,message_id,attachment_sha256,source_system,company,division,snapshot_at,received_at,request_hash,evidence)
 VALUES(kind,p_envelope->>'mailbox',p_envelope->>'gmail_message_id',p_envelope->>'attachment_sha256',p_envelope->>'source_system',p_envelope->>'company',p_envelope->>'division',snap,received,reqhash,p_envelope) RETURNING * INTO rec;
 FOR x IN SELECT value raw,ordinality::integer rowno FROM jsonb_array_elements(p_rows) WITH ORDINALITY LOOP
 target:=NULL;outcome:='invalid';reason:='invalid_flags_or_identity';
 a:=public.pdc_numeric_parts_flag_20260911(x.raw->'Parts Attached');b:=public.pdc_numeric_parts_flag_20260911(x.raw->'Parts on Backorder');p:=public.pdc_numeric_parts_flag_20260911(x.raw->'Backorder with PO (1=Yes, 0=No)');
 IF jsonb_typeof(x.raw)='object' AND nullif(btrim(x.raw->>'R/O #'),'') IS NOT NULL AND x.raw->>'Dept' IN('138','139') AND a IS NOT NULL AND b IS NOT NULL AND p IS NOT NULL AND NOT(p=1 AND b=0) THEN
 IF (SELECT count(*) FROM jsonb_array_elements(p_rows) z WHERE upper(btrim(z->>'R/O #'))=upper(btrim(x.raw->>'R/O #')))>1 THEN
 outcome:='ambiguous';reason:='duplicate_ro_rows';
 ELSE
 SELECT array_agg(j0.id) INTO candidates FROM pdc_parts_private.jobs j0 JOIN public.vehicles v ON v.id=j0.vehicle_id
 WHERE j0.source_system=rec.source_system AND j0.company=rec.company AND j0.division=rec.division
 AND j0.ro_number=upper(btrim(x.raw->>'R/O #')) AND x.raw->>'Dept'=ANY(j0.departments)
 AND j0.closed_at IS NULL AND v.deleted_at IS NULL AND v.lifecycle_state='active' AND v.visible_on_board AND v.board_purged_at IS NULL
 AND nullif(btrim(v.stock_number),'') IS NOT NULL AND j0.stock_number=btrim(v.stock_number);
 n:=coalesce(cardinality(candidates),0);
 IF n=0 THEN outcome:='unmatched';reason:='no_exact_active_board_job';
 ELSIF n>1 THEN outcome:='ambiguous';reason:='multiple_board_jobs';
 ELSE
 target:=candidates[1]; SELECT * INTO j FROM pdc_parts_private.jobs WHERE id=target FOR UPDATE;
 IF (bhavesh OR revolution) AND (coalesce(cardinality(j.departments),0)=0
  OR EXISTS(SELECT 1 FROM unnest(j.departments) d WHERE d IS DISTINCT FROM '138'))
 THEN outcome:='ambiguous';reason:='department_138_job_scope_required';
 ELSIF nullif(btrim(x.raw->>'Stock #'),'') IS NOT NULL AND btrim(x.raw->>'Stock #')<>j.stock_number THEN outcome:='ambiguous';reason:='stock_ro_conflict';
 ELSIF j.parts_snapshot_at IS NOT NULL AND snap<j.parts_snapshot_at THEN outcome:='stale';reason:='older_snapshot';
 ELSIF snap=j.parts_snapshot_at AND (j.parts_attached IS DISTINCT FROM a OR j.backorder IS DISTINCT FROM b OR j.po_flag IS DISTINCT FROM p) THEN outcome:='ambiguous';reason:='equal_snapshot_conflict';
 ELSE
 outcome:=CASE WHEN j.parts_attached=a AND j.backorder=b AND j.po_flag=p THEN 'unchanged' ELSE 'updated' END;reason:='exact_ro_match';
 UPDATE pdc_parts_private.jobs SET parts_attached=a,backorder=b,po_flag=p,parts_snapshot_at=snap,parts_imported_at=rec.imported_at,
 parts_receipt_id=rec.id,parts_origin=kind,version=version+1 WHERE id=target;
 END IF;
 END IF;
 END IF;
 ELSIF p=1 AND b=0 THEN reason:='po_without_backorder'; END IF;
 INSERT INTO pdc_parts_private.row_results(receipt_id,row_number,raw_row,job_id,outcome,reason) VALUES(rec.id,x.rowno,x.raw,target,outcome,reason);
 END LOOP;
 SELECT jsonb_build_object('ok',true,'replay',false,'receipt_id',rec.id,'source_rows',count(*),
 'matched',count(*) FILTER(WHERE rr.job_id IS NOT NULL),'updated',count(*) FILTER(WHERE rr.outcome='updated'),
 'unchanged',count(*) FILTER(WHERE rr.outcome='unchanged'),'unmatched',count(*) FILTER(WHERE rr.outcome='unmatched'),
 'ambiguous',count(*) FILTER(WHERE rr.outcome='ambiguous'),'invalid',count(*) FILTER(WHERE rr.outcome='invalid'),
 'stale',count(*) FILTER(WHERE rr.outcome='stale'),'last_successful_import_at',rec.imported_at,'snapshot_at',snap,
 'vehicles_created',0,'jobs_created',0,'operations_changed',0,'bookings_created',0) INTO resp FROM pdc_parts_private.row_results rr WHERE rr.receipt_id=rec.id;
 UPDATE pdc_parts_private.receipts SET response=resp WHERE id=rec.id;
 UPDATE pdc_parts_private.settings SET last_successful_import_at=rec.imported_at WHERE singleton;
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 PERFORM public.workshop_bump_revision();
 RETURN resp;
END $function$;

-- Synthetic authentication and vehicles below are deployment tests, not real mail.
-- The nested block rolls back EVERY fixture/receipt/revision, even on success.
DO $tests$
DECLARE actor uuid; v uuid:=gen_random_uuid(); vm uuid:=gen_random_uuid(); vh uuid:=gen_random_uuid();
 a jsonb; e jsonb; r jsonb; bad jsonb; result jsonb; first_result jsonb; job_id uuid;
 count_v bigint; count_j bigint; count_r bigint; count_c bigint;
BEGIN
 SELECT count(*) INTO count_v FROM public.vehicles;
 SELECT count(*) INTO count_j FROM pdc_parts_private.jobs;
 SELECT count(*) INTO count_r FROM pdc_parts_private.receipts;
 SELECT count(*) INTO count_c FROM public.pdc_parts_completion_email_confirmations;
 BEGIN
  SELECT actor_id INTO STRICT actor FROM pdc_codex_intake_private.management_email_manifests ORDER BY created_at DESC LIMIT 1;
  IF EXISTS(SELECT 1 FROM public.vehicles WHERE stock_number IN ('91909601','91909602','91909603')) THEN RAISE EXCEPTION 'Fixture collision'; END IF;
  INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,current_location,source_system,source_record_id,source_payload,visible_on_board,created_by,updated_by,model)
  SELECT id,'REVOLUTION-ROLLBACK-'||id,stock,'Synthetic rollback fixture','PMB','tune_pmg',stock,'{"fixture":"revolution_parts_rollback"}',visible,actor,actor,'Toyota HiAce'
  FROM (VALUES(v,'91909601',true),(vm,'91909602',true),(vh,'91909603',false)) f(id,stock,visible);
  INSERT INTO pdc_parts_private.jobs(vehicle_id,source_system,company,division,stock_number,ro_number,departments,service_seen_at)
  VALUES(v,'tune_pmg','01','1','91909601','J138999961',ARRAY['138'],now()),
        (vm,'tune_pmg','01','1','91909602','J138999962',ARRAY['138','139'],now()),
        (vh,'tune_pmg','01','1','91909603','J138999963',ARRAY['138'],now());
  SELECT id INTO STRICT job_id FROM pdc_parts_private.jobs WHERE vehicle_id=v;
  a:='{"gmail_message_id":"abcdef0123456789","from_address":"noreply@revolutionsoftware.com.au","mailbox":"pmbcontroller@gmail.com","to_address":"craig.watson@broometoyota.com.au","cc_addresses":["pmbcontroller@gmail.com"],"verified_by":"gmail_receiving_provider","header_from":"revolutionsoftware.com.au","authentication_results":"mx.google.com; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au; dmarc=pass header.from=revolutionsoftware.com.au"}';
  e:=jsonb_build_object('source_kind','revolution_automated_parts_workbook','authority','explicit_user_request','user_instruction','Synthetic owner-authorized staging Department 138 parts test',
   'source_system','tune_pmg','company','01','division','1','subject','PMG PD Parts Status','source_file','PMG PD Parts Status V1 - Job 1.xls','source_format','ooxml_workbook',
   'sender','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com','sender_verified',true,'gmail_message_id',a->>'gmail_message_id','authentication',a,'authentication_results',a->>'authentication_results',
   'attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'),'snapshot_at',now()-interval '2 days','received_at',now()-interval '1 day');
  r:='[{"Dept":138,"R/O #":"J138999961","Parts Attached":1,"Parts on Backorder":1,"Backorder with PO (1=Yes, 0=No)":1}]';
  first_result:=public.pdc_import_job_parts_csv_20260912(e,r);
  IF first_result->>'updated' IS DISTINCT FROM '1' OR (SELECT backorder FROM pdc_parts_private.jobs WHERE id=job_id)<>1 THEN RAISE EXCEPTION 'Valid report failed %',first_result; END IF;
  result:=public.pdc_import_job_parts_csv_20260912(e,r);
  IF result->>'replay' IS DISTINCT FROM 'true' OR result->>'receipt_id' IS DISTINCT FROM first_result->>'receipt_id' THEN RAISE EXCEPTION 'Replay failed'; END IF;
  result:=public.pdc_import_job_parts_csv_20260912(e,jsonb_set(r,'{0,Parts Attached}','0'));
  IF result->>'code' IS DISTINCT FROM 'attachment_replay_conflict' THEN RAISE EXCEPTION 'Conflicting replay accepted'; END IF;
  FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
   e-'authentication',jsonb_set(e,'{authentication,cc_addresses}','[]'),jsonb_set(e,'{authentication,to_address}','"other@example.com"'),e||'{"sender":"other@revolutionsoftware.com.au"}',e||'{"company":"02"}',e||'{"division":"2"}',e||'{"subject":"Other report"}',
   e||'{"source_format":"legacy_binary"}',e||'{"source_file":"other.xls"}',e||'{"authority":"email_says_import"}',e||'{"gmail_message_id":"abcdef0123456790"}',
   jsonb_set(e,'{authentication,reply_to}','"other@example.com"'),jsonb_set(e,'{authentication,from_address}','"other@revolutionsoftware.com.au"'),
   jsonb_set(e,'{authentication,authentication_results}','"mx.google.com; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au"'))) LOOP
   result:=public.pdc_import_job_parts_csv_20260912(bad,r);
   IF result->>'code' IS DISTINCT FROM 'invalid_or_unverified_envelope' THEN RAISE EXCEPTION 'Invalid evidence accepted %',result; END IF;
  END LOOP;
  FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
   a||'{"authentication_results":"untrusted.example; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au; dmarc=pass header.from=revolutionsoftware.com.au"}',
   a||'{"authentication_results":"mx.google.com; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au.evil.example; dmarc=pass header.from=revolutionsoftware.com.au"}',
   a||'{"authentication_results":"mx.google.com; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au; dmarc=pass header.from=revolutionsoftware.com.au.evil.example"}')) LOOP
   IF pdc_codex_intake_private.revolution_parts_authenticated_20261006(bad,a->>'gmail_message_id') THEN RAISE EXCEPTION 'Unaligned authentication accepted'; END IF;
  END LOOP;
  result:=public.pdc_import_job_parts_csv_20260912(e,jsonb_set(r,'{0,Dept}','139'));
  IF result->>'code' IS DISTINCT FROM 'department_138_scope_required' THEN RAISE EXCEPTION 'Department 139 accepted'; END IF;
  result:=public.pdc_import_job_parts_csv_20260912(e||jsonb_build_object('received_at',now()-interval '3 days'),r);
  IF result->>'code' IS DISTINCT FROM 'invalid_snapshot_time' THEN RAISE EXCEPTION 'Snapshot after receipt accepted'; END IF;
  e:=e||jsonb_build_object('attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'),'snapshot_at',now()-interval '1 day 1 hour');
  r:=jsonb_set(jsonb_set(r,'{0,Parts on Backorder}','0'),ARRAY['0','Backorder with PO (1=Yes, 0=No)'],'0');
  result:=public.pdc_import_job_parts_csv_20260912(e,r);
  IF result->>'updated' IS DISTINCT FROM '1' OR (SELECT backorder FROM pdc_parts_private.jobs WHERE id=job_id)<>0 THEN RAISE EXCEPTION 'Backorder clearing failed %',result; END IF;
  e:=e||jsonb_build_object('attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'));
  result:=public.pdc_import_job_parts_csv_20260912(e,jsonb_set(r,'{0,Parts Attached}','0'));
  IF result->>'ambiguous' IS DISTINCT FROM '1' THEN RAISE EXCEPTION 'Equal snapshot conflict accepted'; END IF;
  result:=public.pdc_import_job_parts_csv_20260912(e||jsonb_build_object('attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'),'snapshot_at',now()-interval '3 days'),r);
  IF result->>'stale' IS DISTINCT FROM '1' THEN RAISE EXCEPTION 'Older snapshot accepted'; END IF;
  FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
   jsonb_set(r,'{0,R/O #}','"J138999962"'),jsonb_set(r,'{0,R/O #}','"J138999963"'),jsonb_set(r,'{0,R/O #}','"J138999964"'),
   jsonb_set(r,'{0,Parts Attached}','"All"'),jsonb_set(r,ARRAY['0','Backorder with PO (1=Yes, 0=No)'],'1'),r||r)) LOOP
   result:=public.pdc_import_job_parts_csv_20260912(e||jsonb_build_object('attachment_sha256',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex')),bad);
   IF result->>'updated' IS DISTINCT FROM '0' OR result->>'unchanged' IS DISTINCT FROM '0' THEN RAISE EXCEPTION 'Mixed/hidden/unknown/invalid/duplicate row wrote flags %',result; END IF;
  END LOOP;
  IF has_function_privilege('anon','public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)','EXECUTE')
   OR has_function_privilege('authenticated','pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Unexpected public grants'; END IF;
  IF (SELECT count(*) FROM public.vehicles)<>count_v+3 OR (SELECT count(*) FROM pdc_parts_private.jobs)<>count_j+3
   OR (SELECT count(*) FROM public.pdc_parts_completion_email_confirmations)<>count_c THEN RAISE EXCEPTION 'Parts created entities/confirmation'; END IF;
  RAISE SQLSTATE 'PZ001' USING MESSAGE='revolution_parts_tests_passed';
 EXCEPTION WHEN SQLSTATE 'PZ001' THEN NULL;
 END;
 IF (SELECT count(*) FROM public.vehicles)<>count_v OR (SELECT count(*) FROM pdc_parts_private.jobs)<>count_j
  OR (SELECT count(*) FROM pdc_parts_private.receipts)<>count_r THEN RAISE EXCEPTION 'Fixture rollback failed'; END IF;
END $tests$;
