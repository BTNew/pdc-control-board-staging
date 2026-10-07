-- Authenticated Revolution CSV reports for the isolated Department135 board.
-- Reuses the released native service/review and exact active-job parts engines.
-- Existing internal owner-manifest names are retained for engine compatibility;
-- provenance records the genuine Gmail source and never impersonates Craig.
DO $guard$ BEGIN
 IF karratha135_intake.management_connection() IS NOT TRUE
 OR public.pdc_monitor_staging_guard() IS NOT TRUE
 OR NOT EXISTS(SELECT 1 FROM karratha135_pdc.engine_release_135 WHERE singleton AND ready)
 THEN RAISE EXCEPTION 'staging_management_released_135_required'; END IF;
 IF md5(pg_get_functiondef('karratha135_intake.import_owner_attachment_20261007(text,jsonb,text,jsonb,boolean)'::regprocedure))<>'a69a575d77e5460bf36f893d06033329' THEN RAISE EXCEPTION 'native_135_adapter_changed'; END IF;
 IF md5(pg_get_functiondef('karratha135_intake.import_owner_parts_core_20261007(jsonb,jsonb)'::regprocedure))<>'c8239b6a7f4ec2ad6af9c0546df8109b' THEN RAISE EXCEPTION 'native_135_adapter_changed'; END IF;
 IF md5(pg_get_functiondef('karratha135_intake.owner_service_authorized_20261007(text,jsonb,text,text,uuid)'::regprocedure))<>'0f0fae3a7960933340c00a5f6ef9f7df' THEN RAISE EXCEPTION 'native_135_adapter_changed'; END IF;
END $guard$;

CREATE FUNCTION karratha135_intake.revolution_csv_contract_20261007(p_kind text,p_envelope jsonb)
RETURNS boolean LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
DECLARE snap timestamptz;received timestamptz;
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN('service','parts')
 OR p_envelope->>'source_kind' IS DISTINCT FROM 'revolution_automated_'||p_kind||'_csv'
 OR p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request'
 OR length(coalesce(p_envelope->>'user_instruction',''))<20
 OR p_envelope->>'source_system' IS DISTINCT FROM 'tune_pmg'
 OR p_envelope->>'source_format' IS DISTINCT FROM 'csv'
 OR p_envelope->>'company' IS DISTINCT FROM '01' OR p_envelope->>'division' IS DISTINCT FROM '1'
 OR p_envelope->>'department' IS DISTINCT FROM '135'
 OR p_envelope->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
 OR p_envelope->>'sender' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
 OR nullif(p_envelope->>'attachment_id','') IS NULL
 OR coalesce(p_envelope->>'attachment_sha256','') !~ '^[a-f0-9]{64}$'
 OR p_envelope->>'snapshot_basis' IS DISTINCT FROM 'authenticated_revolution_email_date'
 OR p_envelope->>'snapshot_at' IS DISTINCT FROM p_envelope->>'producer_email_date_utc'
 OR NOT pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_envelope->'authentication',p_envelope->>'gmail_message_id')
 THEN RETURN false; END IF;
 IF p_kind='service' THEN
  IF p_envelope->>'subject' IS DISTINCT FROM 'PMG KTA Service Complete'
  OR p_envelope->>'source_file' IS DISTINCT FROM 'PMG KTA Service Complete - Job 1.csv'
  OR p_envelope->'source_headers' IS DISTINCT FROM '["Type","Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb
  THEN RETURN false; END IF;
 ELSE
  IF p_envelope->>'subject' IS DISTINCT FROM 'PMG KTA Parts Complete'
  OR p_envelope->>'source_file' IS DISTINCT FROM 'PMG KTA Parts Complete  - Job 1.csv'
  OR p_envelope->'source_headers' IS DISTINCT FROM '["Type","Dept","R/O #","Line #","Parts Attached","Parts on Backorder","Backorder with PO (1=Yes, 0=No)","Modified Date","Modified Date"]'::jsonb
  THEN RETURN false; END IF;
 END IF;
 BEGIN snap:=(p_envelope->>'snapshot_at')::timestamptz;received:=(p_envelope->>'received_at')::timestamptz;
 EXCEPTION WHEN OTHERS THEN RETURN false; END;
 RETURN coalesce(snap IS NOT NULL AND received IS NOT NULL
 AND snap<=received+interval '5 minutes' AND snap>=received-interval '5 minutes'
 AND received<=clock_timestamp()+interval '5 minutes',false);
END $fn$;
REVOKE ALL ON FUNCTION karratha135_intake.revolution_csv_contract_20261007(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION karratha135_intake.import_revolution_parts_core_20261007(p_envelope jsonb, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'karratha135_parts'
AS $function$


DECLARE rec karratha135_parts.receipts%rowtype; j karratha135_parts.jobs%rowtype; x record; n integer;


 a integer;b integer;p integer; outcome text;reason text; target uuid; candidates uuid[];


 snap timestamptz; received timestamptz; reqhash text; resp jsonb; kind text; bhavesh boolean:=false; revolution boolean:=false;


BEGIN


 IF karratha135_intake.management_connection() IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;


 kind:=coalesce(p_envelope->>'source_kind','gmail_csv');


 IF p_envelope->>'source_system' IS DISTINCT FROM 'tune_pmg' OR nullif(p_envelope->>'company','') IS NULL OR nullif(p_envelope->>'division','') IS NULL


 OR coalesce(p_envelope->>'attachment_sha256','') !~ '^[a-f0-9]{64}$'


 OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 10000


 THEN RETURN jsonb_build_object('ok',false,'code','invalid_report_envelope'); END IF;


 IF NOT karratha135_intake.revolution_csv_contract_20261007('parts',p_envelope)
 OR karratha135_intake.owner_attachment_actor_20261007() IS NULL
 OR NOT EXISTS(SELECT 1 FROM karratha135_intake.owner_attachment_manifests_20261007 m
  WHERE m.source_hash=current_setting('k135.owner_attachment_hash',true) AND m.source_kind='parts'
  AND m.server_request_sha256=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'envelope',p_envelope)::text,'UTF8'),'sha256'),'hex'))
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) z WHERE z->>'Dept' IS DISTINCT FROM '135')
 THEN RETURN jsonb_build_object('ok',false,'code','bound_department135_revolution_source_required'); END IF;
 revolution:=true; -- Reuse the exact-one-department job guard for this scoped source.

 BEGIN snap:=(p_envelope->>'snapshot_at')::timestamptz;


  received:=CASE WHEN kind IN ('gmail_csv','authorised_gmail_workbook','revolution_automated_parts_workbook','revolution_automated_parts_csv') THEN (p_envelope->>'received_at')::timestamptz ELSE NULL END;


 EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'code','invalid_snapshot_time'); END;


 IF snap IS NULL OR snap>clock_timestamp()+interval '5 minutes'


 OR (kind IN ('gmail_csv','authorised_gmail_workbook','revolution_automated_parts_workbook','revolution_automated_parts_csv') AND (received IS NULL OR snap>received+interval '5 minutes' OR received>clock_timestamp()+interval '5 minutes'))


 THEN RETURN jsonb_build_object('ok',false,'code','invalid_snapshot_time'); END IF;


 reqhash:=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'source',p_envelope->>'source_system','company',p_envelope->>'company','division',p_envelope->>'division','snapshot',snap)::text,'UTF8'),'sha256'),'hex');


 PERFORM pg_advisory_xact_lock(hashtextextended('k135:pdc:workshop:top-level-mutation',0));


 SELECT * INTO rec FROM karratha135_parts.receipts WHERE source_system=p_envelope->>'source_system'


 AND company=p_envelope->>'company' AND division=p_envelope->>'division' AND attachment_sha256=p_envelope->>'attachment_sha256';


 IF FOUND THEN


 IF rec.request_hash<>reqhash THEN RETURN jsonb_build_object('ok',false,'code','attachment_replay_conflict');END IF;


 RETURN rec.response||jsonb_build_object('replay',true);END IF;


 INSERT INTO karratha135_parts.receipts(source_kind,mailbox,message_id,attachment_sha256,source_system,company,division,snapshot_at,received_at,request_hash,evidence)


 VALUES(kind,p_envelope->>'mailbox',p_envelope->>'gmail_message_id',p_envelope->>'attachment_sha256',p_envelope->>'source_system',p_envelope->>'company',p_envelope->>'division',snap,received,reqhash,p_envelope) RETURNING * INTO rec;


 FOR x IN SELECT value raw,ordinality::integer rowno FROM jsonb_array_elements(p_rows) WITH ORDINALITY LOOP


 target:=NULL;outcome:='invalid';reason:='invalid_flags_or_identity';


 a:=karratha135_pdc.pdc_numeric_parts_flag_20260911(x.raw->'Parts Attached');b:=karratha135_pdc.pdc_numeric_parts_flag_20260911(x.raw->'Parts on Backorder');p:=karratha135_pdc.pdc_numeric_parts_flag_20260911(x.raw->'Backorder with PO (1=Yes, 0=No)');


 IF jsonb_typeof(x.raw)='object' AND nullif(btrim(x.raw->>'R/O #'),'') IS NOT NULL AND x.raw->>'Dept' IN('135') AND a IS NOT NULL AND b IS NOT NULL AND p IS NOT NULL AND NOT(p=1 AND b=0) THEN


 IF (SELECT count(*) FROM jsonb_array_elements(p_rows) z WHERE upper(btrim(z->>'R/O #'))=upper(btrim(x.raw->>'R/O #')))>1 THEN


 outcome:='ambiguous';reason:='duplicate_ro_rows';


 ELSE


 SELECT array_agg(j0.id) INTO candidates FROM karratha135_parts.jobs j0 JOIN karratha135_pdc.vehicles v ON v.id=j0.vehicle_id


 WHERE j0.source_system=rec.source_system AND j0.company=rec.company AND j0.division=rec.division


 AND j0.ro_number=upper(btrim(x.raw->>'R/O #')) AND x.raw->>'Dept'=ANY(j0.departments)


 AND j0.closed_at IS NULL AND v.deleted_at IS NULL AND v.lifecycle_state='active' AND v.visible_on_board AND v.board_purged_at IS NULL


 AND nullif(btrim(v.stock_number),'') IS NOT NULL AND j0.stock_number=btrim(v.stock_number);


 n:=coalesce(cardinality(candidates),0);


 IF n=0 THEN outcome:='unmatched';reason:='no_exact_active_board_job';


 ELSIF n>1 THEN outcome:='ambiguous';reason:='multiple_board_jobs';


 ELSE


 target:=candidates[1]; SELECT * INTO j FROM karratha135_parts.jobs WHERE id=target FOR UPDATE;


 IF bhavesh AND (coalesce(cardinality(j.departments),0)=0


  OR EXISTS(SELECT 1 FROM unnest(j.departments) d WHERE d IS DISTINCT FROM '138'))


 THEN outcome:='ambiguous';reason:='department_138_job_scope_required';


 ELSIF revolution AND (coalesce(cardinality(j.departments),0)<>1 OR j.departments[1] IS DISTINCT FROM x.raw->>'Dept')


 THEN outcome:='ambiguous';reason:='exact_department_job_scope_required';


 ELSIF nullif(btrim(x.raw->>'Stock #'),'') IS NOT NULL AND btrim(x.raw->>'Stock #')<>j.stock_number THEN outcome:='ambiguous';reason:='stock_ro_conflict';


 ELSIF j.parts_snapshot_at IS NOT NULL AND snap<j.parts_snapshot_at THEN outcome:='stale';reason:='older_snapshot';


 ELSIF snap=j.parts_snapshot_at AND (j.parts_attached IS DISTINCT FROM a OR j.backorder IS DISTINCT FROM b OR j.po_flag IS DISTINCT FROM p) THEN outcome:='ambiguous';reason:='equal_snapshot_conflict';


 ELSE


 outcome:=CASE WHEN j.parts_attached=a AND j.backorder=b AND j.po_flag=p THEN 'unchanged' ELSE 'updated' END;reason:='exact_ro_match';


 UPDATE karratha135_parts.jobs SET parts_attached=a,backorder=b,po_flag=p,parts_snapshot_at=snap,parts_imported_at=rec.imported_at,


 parts_receipt_id=rec.id,parts_origin=kind,version=version+1 WHERE id=target;


 END IF;


 END IF;


 END IF;


 ELSIF p=1 AND b=0 THEN reason:='po_without_backorder'; END IF;


 INSERT INTO karratha135_parts.row_results(receipt_id,row_number,raw_row,job_id,outcome,reason) VALUES(rec.id,x.rowno,x.raw,target,outcome,reason);


 END LOOP;


 SELECT jsonb_build_object('ok',true,'replay',false,'receipt_id',rec.id,'source_rows',count(*),


 'matched',count(*) FILTER(WHERE rr.job_id IS NOT NULL),'updated',count(*) FILTER(WHERE rr.outcome='updated'),


 'unchanged',count(*) FILTER(WHERE rr.outcome='unchanged'),'unmatched',count(*) FILTER(WHERE rr.outcome='unmatched'),


 'ambiguous',count(*) FILTER(WHERE rr.outcome='ambiguous'),'invalid',count(*) FILTER(WHERE rr.outcome='invalid'),


 'stale',count(*) FILTER(WHERE rr.outcome='stale'),'last_successful_import_at',rec.imported_at,'snapshot_at',snap,


 'vehicles_created',0,'jobs_created',0,'operations_changed',0,'bookings_created',0) INTO resp FROM karratha135_parts.row_results rr WHERE rr.receipt_id=rec.id;


 UPDATE karratha135_parts.receipts SET response=resp WHERE id=rec.id;


 UPDATE karratha135_parts.settings SET last_successful_import_at=rec.imported_at WHERE singleton;


 UPDATE karratha135_pdc.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;


 PERFORM karratha135_pdc.workshop_bump_revision();


 RETURN resp;


END $function$
;
CREATE FUNCTION karratha135_intake.import_revolution_email_20261007(p_kind text, p_rows jsonb, p_source_hash text, p_envelope jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '120s'
AS $function$

DECLARE actor uuid; prior_ban timestamptz; req text; m karratha135_intake.owner_attachment_manifests_20261007;

 preview jsonb; applied jsonb; result jsonb; old_context text:=current_setting('k135.owner_attachment_hash',true);

BEGIN

 IF karratha135_intake.management_connection() IS NOT TRUE

  OR NOT EXISTS(SELECT 1 FROM karratha135_pdc.engine_release_135 WHERE singleton AND ready)

 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;

 IF NOT karratha135_intake.revolution_csv_contract_20261007(p_kind,p_envelope)
 OR coalesce(p_source_hash,'') !~ '^[a-f0-9]{64}$'
 OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 10000
 OR octet_length(p_rows::text)>8388608
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) r WHERE
  (p_kind='service' AND (r->>'department' IS DISTINCT FROM '135'
   OR r->'raw_row'->>'Dept' IS DISTINCT FROM '135'
   OR r->'raw_row'->>'Type' IS DISTINCT FROM 'D'
   OR r->'raw_row'->>'Company' IS DISTINCT FROM '01' OR r->'raw_row'->>'Division' IS DISTINCT FROM '1'
   OR r->>'workbook_sha256' IS DISTINCT FROM p_envelope->>'attachment_sha256'
   OR r->'raw_row'->>'parent_attachment_sha256' IS DISTINCT FROM p_envelope->>'attachment_sha256'
   OR r->'raw_row'->>'gmail_message_id' IS DISTINCT FROM p_envelope->>'gmail_message_id'
   OR r->'raw_row'->>'from_address' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
   OR r->'raw_row'->>'source_snapshot_at' IS DISTINCT FROM p_envelope->>'snapshot_at'
   OR coalesce(r->>'repair_order_number','') !~ '^[JB]135[0-9]+$'))
  OR (p_kind='parts' AND (r->>'Dept' IS DISTINCT FROM '135'
   OR r->>'parent_attachment_sha256' IS DISTINCT FROM p_envelope->>'attachment_sha256'
   OR r->>'gmail_message_id' IS DISTINCT FROM p_envelope->>'gmail_message_id'
   OR coalesce(r->>'R/O #','') !~ '^[JB]135[0-9]+$')))
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_revolution_department135_contract'); END IF;
 SELECT u.id,u.banned_until INTO actor,prior_ban FROM auth.users u WHERE lower(u.email)='codex.pmb.importer.staging@pmb.local'

  AND u.deleted_at IS NULL FOR UPDATE;

 IF actor IS NULL THEN RETURN jsonb_build_object('ok',false,'code','import_actor_unavailable'); END IF;
 IF prior_ban IS NULL OR prior_ban<=clock_timestamp() THEN RETURN jsonb_build_object('ok',false,'code','dedicated_importer_must_start_disabled'); END IF;

 req:=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'envelope',p_envelope)::text,'UTF8'),'sha256'),'hex');

 PERFORM pg_advisory_xact_lock(hashtextextended('k135:owner-attachment:'||p_source_hash,0));

 SELECT * INTO m FROM karratha135_intake.owner_attachment_manifests_20261007 WHERE source_hash=p_source_hash FOR UPDATE;

 IF FOUND AND (m.server_request_sha256<>req OR m.source_kind<>p_kind OR m.actor_id<>actor)

 THEN RETURN jsonb_build_object('ok',false,'code','source_hash_payload_conflict'); END IF;

 -- Identical original bytes are reconciled to their already-applied receipt.
 SELECT * INTO m FROM karratha135_intake.owner_attachment_manifests_20261007
 WHERE workbook_sha256=p_envelope->>'attachment_sha256' AND source_kind=p_kind
 AND ((source_kind='parts' AND receipt->>'receipt_id' IS NOT NULL)
  OR (source_kind='service' AND receipt->'apply'->>'ok'='true'))
 ORDER BY created_at LIMIT 1;
 IF FOUND THEN RETURN m.receipt||jsonb_build_object('replay',true,'original_source_hash',m.source_hash,'importer_disabled',true); END IF;
 INSERT INTO karratha135_intake.owner_attachment_manifests_20261007(source_hash,workbook_sha256,server_request_sha256,source_kind,actor_id,source_rows,provenance)

 VALUES(p_source_hash,p_envelope->>'attachment_sha256',req,p_kind,actor,jsonb_array_length(p_rows),p_envelope) ON CONFLICT DO NOTHING;

 UPDATE karratha135_intake.owner_attachment_manifests_20261007 SET enabled=true,bound_txid=txid_current(),bound_until=clock_timestamp()+interval '5 minutes' WHERE source_hash=p_source_hash;

 UPDATE auth.users SET banned_until=NULL WHERE id=actor;

 PERFORM set_config('k135.owner_attachment_hash',p_source_hash,true);

 IF p_kind='service' THEN

  PERFORM karratha135_pdc.refresh_shared_navision_135(p_rows);

  preview:=karratha135_pdc.pdc_pilbara_service_preview_v1(p_rows,p_source_hash,'k135-owner-preview-'||p_source_hash);

  IF coalesce(preview->>'ok','false')<>'true' THEN RAISE EXCEPTION 'service_preview_failed: %',preview; END IF;

  IF p_apply THEN

   IF coalesce(preview->>'apply_allowed','false')<>'true' THEN RAISE EXCEPTION 'service_apply_not_allowed: %',preview; END IF;

   applied:=karratha135_pdc.pdc_pilbara_service_apply_v1((preview->>'preview_batch_id')::uuid,p_source_hash,'k135-owner-apply-'||p_source_hash);

   IF coalesce(applied->>'ok','false')<>'true' THEN RAISE EXCEPTION 'service_apply_failed: %',applied; END IF;

  END IF;

  result:=jsonb_build_object('ok',true,'kind','service','preview',preview,'apply',applied);

 ELSE

  IF p_apply IS NOT TRUE THEN RAISE EXCEPTION 'parts preview uses a rollback transaction'; END IF;

  result:=karratha135_intake.import_revolution_parts_core_20261007(p_envelope,p_rows);

  IF coalesce(result->>'ok','false')<>'true' THEN RAISE EXCEPTION 'parts_import_failed: %',result; END IF;

 END IF;

 UPDATE karratha135_intake.owner_attachment_manifests_20261007 SET enabled=false,bound_txid=NULL,bound_until=NULL,receipt=result WHERE source_hash=p_source_hash;

 UPDATE auth.users SET banned_until=prior_ban WHERE id=actor;

 IF (SELECT banned_until FROM auth.users WHERE id=actor) IS DISTINCT FROM prior_ban THEN RAISE EXCEPTION 'importer_state_restore_failed'; END IF;

 PERFORM set_config('k135.owner_attachment_hash',coalesce(old_context,''),true);

 RETURN result||jsonb_build_object('importer_disabled',true);

END $function$
;

REVOKE ALL ON FUNCTION karratha135_intake.import_revolution_parts_core_20261007(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION karratha135_intake.import_revolution_email_20261007(text,jsonb,text,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
