-- Craig's 23 September 2026 delegation permits authenticated Bhavesh instructions
-- for Department 138. Reuse the existing postgres-only management path and actor.
-- No grants, JWT/session impersonation, credentials, role changes, or production scope.
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR pdc_codex_intake_private.management_connection() IS NOT TRUE
 THEN RAISE EXCEPTION 'staging_management_connection_required'; END IF;
END $guard$;

-- The connector stores actual receiving-provider evidence in provenance.authentication
-- (service) or envelope.authentication (parts). Its message ID must bind that evidence
-- to this envelope. Display names, forwarded text and claimed SPF alone are insufficient.
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.bhavesh_email_authenticated_20260923(p_auth jsonb, p_message_id text)
RETURNS boolean LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog
AS $function$
 SELECT coalesce(
  jsonb_typeof(p_auth)='object'
  AND p_message_id ~ '^[a-f0-9]{10,40}$'
  AND p_auth->>'gmail_message_id'=p_message_id
  AND p_auth->>'from_address'='bhavesh.patel@pmgwa.com.au'
  AND p_auth->>'mailbox'='pmbcontroller@gmail.com'
  AND p_auth->>'to_address'='pmbcontroller@gmail.com'
  AND p_auth->>'verified_by'='gmail_receiving_provider'
  AND p_auth->>'header_from'='pmgwa.com.au'
  AND coalesce(nullif(p_auth->>'reply_to',''),'bhavesh.patel@pmgwa.com.au')='bhavesh.patel@pmgwa.com.au'
  AND lower(coalesce(p_auth->>'auto_submitted','no'))='no'
  AND p_auth->>'authentication_results' ~* '^mx[.]google[.]com;'
  AND (p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*dkim=pass[^;]*header[.](i=@|d=)pmgwa[.]com[.]au([;[:space:]]|$)'
   OR p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from=pmgwa[.]com[.]au([;[:space:]]|$)'), false);
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.bhavesh_email_authenticated_20260923(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

-- Vehicle-wide actions are authorised only when every current linked job belongs
-- to one known Tune company/division and Department 138. Unknown or mixed scope is
-- held for review. Historical/closed jobs do not vote in this check.
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(p_vehicle uuid)
RETURNS boolean LANGUAGE sql STABLE
SET search_path = pg_catalog, public, pdc_parts_private
AS $function$
 SELECT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=p_vehicle AND j.closed_at IS NULL)
 AND (SELECT count(DISTINCT (j.source_system,j.company,j.division))=1
      FROM pdc_parts_private.jobs j WHERE j.vehicle_id=p_vehicle AND j.closed_at IS NULL)
 AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j JOIN public.vehicles v ON v.id=j.vehicle_id
  WHERE j.vehicle_id=p_vehicle AND j.closed_at IS NULL AND (
   j.source_system IS DISTINCT FROM 'tune_pmg' OR nullif(btrim(j.company),'') IS NULL OR nullif(btrim(j.division),'') IS NULL
   OR j.stock_number IS DISTINCT FROM v.stock_number OR coalesce(cardinality(j.departments),0)=0
   OR EXISTS(SELECT 1 FROM unnest(j.departments) d WHERE d IS DISTINCT FROM '138')))
 AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o
  JOIN public.pdc_pilbara_service_import_rows r ON r.evidence_id=o.raw_evidence_id
  WHERE o.vehicle_id=p_vehicle AND NOT EXISTS(
   SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=o.vehicle_id
    AND j.source_system='tune_pmg' AND j.ro_number=o.repair_order_number
    AND j.company=btrim(r.raw_row->>'Company') AND j.division=btrim(r.raw_row->>'Division')
    AND j.stock_number=o.stock_number
    AND (j.closed_at IS NOT NULL OR o.department='138')));
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- The existing service importer can affect a vehicle as well as an operation.
-- Check declared/raw department, exact company/division + R/O, and current linked
-- vehicle scope both at preview and immediately before apply. New Department 138
-- vehicles remain importable; an existing conflicting/mixed job is never guessed.
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.bhavesh_service_scope_20260923(p_rows jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, public, pdc_parts_private
AS $function$
DECLARE x jsonb; v_ro text; v_stock text; v_company text; v_division text;
BEGIN
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows)<1 THEN RETURN false; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  v_ro:=upper(btrim(x->>'repair_order_number')); v_stock:=nullif(btrim(x->>'stock_number'),'');
  v_company:=nullif(btrim(x->'raw_row'->>'Company'),''); v_division:=nullif(btrim(x->'raw_row'->>'Division'),'');
  IF x->>'department' IS DISTINCT FROM '138' OR x->'raw_row'->>'Dept' IS DISTINCT FROM '138'
   OR x->'raw_row'->>'from_address' IS DISTINCT FROM 'bhavesh.patel@pmgwa.com.au'
   OR v_company IS NULL OR v_division IS NULL OR nullif(v_ro,'') IS NULL
   OR upper(btrim(x->'raw_row'->>'R/O #')) IS DISTINCT FROM v_ro THEN RETURN false; END IF;
  IF EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.source_system='tune_pmg'
    AND j.company=v_company AND j.division=v_division AND j.ro_number=v_ro AND j.closed_at IS NULL
    AND (j.stock_number IS DISTINCT FROM v_stock OR coalesce(cardinality(j.departments),0)=0
     OR EXISTS(SELECT 1 FROM unnest(j.departments) d WHERE d IS DISTINCT FROM '138')))
  OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o
    JOIN public.pdc_pilbara_service_import_rows r ON r.evidence_id=o.raw_evidence_id
    WHERE o.repair_order_number=v_ro AND btrim(r.raw_row->>'Company')=v_company AND btrim(r.raw_row->>'Division')=v_division
     AND (o.department IS DISTINCT FROM '138' OR o.stock_number IS DISTINCT FROM v_stock)
     AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=o.vehicle_id
       AND j.source_system='tune_pmg' AND j.company=v_company AND j.division=v_division AND j.ro_number=v_ro AND j.closed_at IS NOT NULL))
  OR EXISTS(SELECT 1 FROM public.vehicles v WHERE v.stock_number=v_stock AND v.deleted_at IS NULL
    AND v.lifecycle_state='active' AND v.board_purged_at IS NULL
    AND (EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL)
      OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id))
    AND (NOT pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(v.id)
      OR EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL
        AND (j.company<>v_company OR j.division<>v_division))))
  THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END $function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.bhavesh_service_scope_20260923(jsonb) FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 DROP CONSTRAINT management_email_manifests_sender_check,
 ADD CONSTRAINT management_email_manifests_sender_check CHECK (sender IN ('craig.watson@broometoyota.com.au','bhavesh.patel@pmgwa.com.au')),
 ADD CONSTRAINT management_manifest_bhavesh_authentication CHECK (
  sender IS DISTINCT FROM 'bhavesh.patel@pmgwa.com.au'
  OR pdc_codex_intake_private.bhavesh_email_authenticated_20260923(provenance->'authentication',gmail_message_id));

-- Correct the deployed double-backslash pattern, which rejected ordinary email
-- addresses. The same intended validation already exists in the confirmation RPC.
ALTER TABLE public.pdc_parts_completion_email_confirmations
 DROP CONSTRAINT person_confirmation_sender,
 ADD CONSTRAINT person_confirmation_sender CHECK (sender ~ '^[^[:space:]@]+@[a-z0-9.-]+[.][a-z]{2,}$');

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.management_authorized(p_action text, p_rows jsonb, p_source_hash text, p_idempotency_key text, p_batch_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pdc_codex_intake_private'
AS $function$
DECLARE m management_email_manifests%rowtype; b public.pdc_pilbara_service_import_batches%rowtype; actor uuid:=import_actor(); scope_rows jsonb;
BEGIN
 IF management_connection() IS NOT TRUE OR actor IS NULL OR p_action IS NULL OR p_action NOT IN('preview','apply','readback','source_readback') THEN RETURN false; END IF;
 IF p_action='preview' THEN
   IF p_batch_id IS NOT NULL OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN RETURN false; END IF;
   SELECT * INTO m FROM management_email_manifests WHERE source_hash=p_source_hash AND actor_id=actor AND revoked_at IS NULL;
   IF NOT FOUND THEN RETURN false; END IF;
   IF m.sender='bhavesh.patel@pmgwa.com.au' AND (
    NOT bhavesh_email_authenticated_20260923(m.provenance->'authentication',m.gmail_message_id)
    OR NOT bhavesh_service_scope_20260923(p_rows)) THEN RETURN false; END IF;
   RETURN p_idempotency_key IS NOT DISTINCT FROM 'codex-owner-email-preview-'||m.source_hash
    AND jsonb_array_length(p_rows)=m.source_rows
    AND encode(extensions.digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex')=m.server_rows_sha256
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE
      x->>'workbook_sha256' IS DISTINCT FROM m.workbook_sha256 OR
      x->'raw_row'->>'parent_attachment_sha256' IS DISTINCT FROM m.workbook_sha256 OR
      x->'raw_row'->>'gmail_message_id' IS DISTINCT FROM m.gmail_message_id OR
      coalesce(x->>'department','') NOT IN('138','139'));
 END IF;
 IF p_rows IS NOT NULL OR p_batch_id IS NULL THEN RETURN false; END IF;
 SELECT * INTO b FROM public.pdc_pilbara_service_import_batches WHERE batch_id=p_batch_id
 AND created_by=actor AND created_actor='codex_supabase_management:postgres:'||actor::text
 AND importer_version='pilbara_service_open_jobcards_v1' AND contract_revision='pmg_stock_v5';
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO m FROM management_email_manifests WHERE source_hash=b.source_hash AND actor_id=actor AND revoked_at IS NULL
 AND source_rows=b.source_row_count AND workbook_sha256=b.source_link->>'workbook_sha256' AND source_hash=b.source_link->>'partition_sha256';
 IF NOT FOUND THEN RETURN false; END IF;
 IF m.sender='bhavesh.patel@pmgwa.com.au' AND NOT bhavesh_email_authenticated_20260923(m.provenance->'authentication',m.gmail_message_id)
 THEN RETURN false; END IF;
 IF p_action='apply' THEN
   IF m.sender='bhavesh.patel@pmgwa.com.au' THEN
    SELECT jsonb_agg(r.normalized_payload||jsonb_build_object('raw_row',r.raw_row) ORDER BY r.source_order)
     INTO scope_rows FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=b.batch_id;
    IF jsonb_array_length(coalesce(scope_rows,'[]'))<>m.source_rows OR NOT bhavesh_service_scope_20260923(scope_rows)
    THEN RETURN false; END IF;
   END IF;
   RETURN b.batch_kind='preview' AND b.request_hash=m.server_rows_sha256
    AND b.idempotency_key='codex-owner-email-preview-'||m.source_hash
    AND p_source_hash IS NOT DISTINCT FROM m.source_hash
    AND p_idempotency_key IS NOT DISTINCT FROM 'codex-owner-email-apply-'||m.source_hash;
 END IF;
 IF p_source_hash IS NOT NULL OR p_idempotency_key IS NOT NULL OR b.batch_kind<>'apply'
 OR b.idempotency_key<>'codex-owner-email-apply-'||m.source_hash THEN RETURN false; END IF;
 RETURN EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_batches p WHERE
 p.source_hash=m.source_hash AND p.created_by=actor
 AND p.created_actor='codex_supabase_management:postgres:'||actor::text
 AND p.batch_kind='preview' AND p.contract_revision='pmg_stock_v5'
 AND p.idempotency_key='codex-owner-email-preview-'||m.source_hash AND p.request_hash=m.server_rows_sha256
 AND b.request_hash=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc_pilbara_service_apply_v1_dynamic_20260910','preview_batch_id',p.batch_id,'source_hash',m.source_hash)::text,'UTF8'),'sha256'),'hex'));
END $function$;

CREATE OR REPLACE FUNCTION public.pdc_import_job_parts_csv_20260912(p_envelope jsonb, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pdc_parts_private'
AS $function$
DECLARE rec pdc_parts_private.receipts%rowtype; j pdc_parts_private.jobs%rowtype; x record; n integer;
 a integer;b integer;p integer; outcome text;reason text; target uuid; candidates uuid[];
 snap timestamptz; received timestamptz; reqhash text; resp jsonb; kind text; bhavesh boolean:=false;
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
 ELSIF kind='user_attached_workbook' THEN
  IF p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request'
  OR nullif(p_envelope->>'attachment_id','') IS NULL OR nullif(p_envelope->>'source_file','') IS NULL
  OR length(coalesce(p_envelope->>'user_instruction',''))<20
  OR p_envelope ? 'gmail_message_id' OR p_envelope ? 'sender_verified' OR p_envelope ? 'mailbox'
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_direct_attachment_evidence'); END IF;
 ELSE RETURN jsonb_build_object('ok',false,'code','unsupported_report_origin'); END IF;
 BEGIN snap:=(p_envelope->>'snapshot_at')::timestamptz;
  received:=CASE WHEN kind IN ('gmail_csv','authorised_gmail_workbook') THEN (p_envelope->>'received_at')::timestamptz ELSE NULL END;
 EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'code','invalid_snapshot_time'); END;
 IF snap IS NULL OR snap>clock_timestamp()+interval '5 minutes'
 OR (kind IN ('gmail_csv','authorised_gmail_workbook') AND (received IS NULL OR snap>received+interval '5 minutes' OR received>clock_timestamp()+interval '5 minutes'))
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
 IF bhavesh AND (coalesce(cardinality(j.departments),0)=0
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

CREATE OR REPLACE FUNCTION public.record_pdc_person_parts_complete_20260913(p_stock text, p_gmail_message_id text, p_received_at timestamp with time zone, p_subject text, p_confirmation_text text, p_evidence_sha256 text, p_authentication jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pdc_codex_intake_private'
AS $function$
DECLARE v public.vehicles%rowtype; c public.pdc_parts_completion_email_confirmations%rowtype;
 actor uuid; status jsonb; sender text:=lower(btrim(p_authentication->>'from_address'));
 domain text; auth_result text; body text; authenticated_sender boolean;
BEGIN
 IF pdc_codex_intake_private.management_connection() IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 domain:=split_part(sender,'@',2); auth_result:=p_authentication->>'authentication_results';
 body:=lower(regexp_replace(btrim(coalesce(p_confirmation_text,'')),'[[:space:]]+',' ','g'));
 -- Authentication comes from the Gmail connector's receiving-provider header.
 -- Aligned DKIM is accepted directly; absent direct DMARC is never represented as a reported pass.
 authenticated_sender:=coalesce(auth_result ~* '^mx[.]google[.]com;' AND (
   auth_result ~* ('dkim=pass[^;]*header[.](i=@|d=)'||replace(domain,'.','\.')||'([;[:space:]]|$)')
   OR auth_result ~* ('(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from='||replace(domain,'.','\.')||'([;[:space:]]|$)')
 ),false);
 IF p_stock IS NULL OR p_stock !~ '^[0-9]{8}$' OR p_gmail_message_id IS NULL OR p_gmail_message_id !~ '^[a-f0-9]{10,40}$'
 OR p_received_at IS NULL OR p_received_at<'2026-09-12T00:00:00Z' OR p_received_at>clock_timestamp()+interval '5 minutes'
 OR p_evidence_sha256 IS NULL OR p_evidence_sha256 !~ '^[a-f0-9]{64}$'
 OR sender IS NULL OR sender !~ '^[^[:space:]@]+@[a-z0-9.-]+\.[a-z]{2,}$'
 OR sender ~* '(^|[._-])(no[._-]?reply|mailer.daemon|postmaster)(@|[._-])'
 OR p_authentication->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
 OR p_authentication->>'to_address' IS DISTINCT FROM 'pmbcontroller@gmail.com'
 OR p_authentication->>'verified_by' IS DISTINCT FROM 'gmail_receiving_provider'
 OR p_authentication->>'header_from' IS DISTINCT FROM domain OR NOT authenticated_sender
 OR p_authentication->>'human_message' IS DISTINCT FROM 'true'
 OR p_authentication->>'unquoted_affirmative' IS DISTINCT FROM 'true'
 OR coalesce(nullif(p_authentication->>'reply_to',''),sender)<>sender
 OR lower(coalesce(p_authentication->>'auto_submitted','no'))<>'no'
 OR body !~ ('^(parts complete( for)? '||p_stock||'|'||p_stock||' parts complete)[.!]?$')
 THEN RETURN jsonb_build_object('ok',false,'code','unverified_or_ambiguous_confirmation'); END IF;
 IF sender='bhavesh.patel@pmgwa.com.au'
 AND NOT pdc_codex_intake_private.bhavesh_email_authenticated_20260923(p_authentication,p_gmail_message_id)
 THEN RETURN jsonb_build_object('ok',false,'code','unverified_or_ambiguous_confirmation'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE stock_number=p_stock AND deleted_at IS NULL AND lifecycle_state='active' AND visible_on_board AND board_purged_at IS NULL FOR UPDATE;
 IF NOT FOUND OR (SELECT count(*) FROM public.vehicles WHERE stock_number=p_stock AND deleted_at IS NULL AND lifecycle_state='active' AND visible_on_board AND board_purged_at IS NULL)<>1
 THEN RETURN jsonb_build_object('ok',false,'code','vehicle_identity_requires_review'); END IF;
 IF sender='bhavesh.patel@pmgwa.com.au' AND NOT pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(v.id)
 THEN RETURN jsonb_build_object('ok',false,'code','department_138_vehicle_scope_required'); END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_parts_completion_email_confirmations WHERE gmail_message_id=p_gmail_message_id AND evidence_sha256<>p_evidence_sha256) THEN RETURN jsonb_build_object('ok',false,'code','evidence_replay_conflict'); END IF;
SELECT * INTO c FROM public.pdc_parts_completion_email_confirmations WHERE gmail_message_id=p_gmail_message_id AND vehicle_id=v.id;
 IF FOUND THEN
  IF c.vehicle_id<>v.id OR c.evidence_sha256<>p_evidence_sha256 THEN RETURN jsonb_build_object('ok',false,'code','evidence_replay_conflict'); END IF;
  RETURN jsonb_build_object('ok',true,'replay',true,'confirmation_id',c.confirmation_id,'vehicle_id',v.id,'parts_status',public.pdc_parts_flags_vehicle_20260911(v.id));
 END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_parts_completion_email_confirmations WHERE vehicle_id=v.id AND active)
 THEN RETURN jsonb_build_object('ok',true,'code','already_confirmed','vehicle_id',v.id,'parts_status',public.pdc_parts_flags_vehicle_20260911(v.id)); END IF;
 actor:=pdc_codex_intake_private.import_actor();
 INSERT INTO public.pdc_parts_completion_email_confirmations(vehicle_id,stock_number,mailbox,sender,gmail_message_id,received_at,subject,confirmation_text,evidence_sha256,authentication,recorded_by,owner_authority)
 VALUES(v.id,p_stock,'pmbcontroller@gmail.com',sender,p_gmail_message_id,p_received_at,coalesce(p_subject,''),p_confirmation_text,p_evidence_sha256,p_authentication,actor,
 'Craig ChatGPT 13 September 2026: verified person Parts Complete email confirms the exact board vehicle, overrides import flags and uses a green box with dark-green outline') RETURNING * INTO c;
 INSERT INTO public.vehicle_parts_updates(vehicle_id,parts_required,parts_received,updated_by) VALUES(v.id,true,true,actor);
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,after_data,metadata)
 VALUES('insert','pdc_parts_completion_email_confirmations',c.confirmation_id,v.id,actor,'codex-management',
 jsonb_build_object('parts_complete',true,'sender',sender,'received_at',c.received_at),
 jsonb_build_object('source','craig_authorised_person_email','gmail_message_id',p_gmail_message_id,'evidence_sha256',p_evidence_sha256,'overrides_import_flags',true,'workshop_completion_changed',false));
 PERFORM public.workshop_bump_revision();
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 status:=public.pdc_parts_flags_vehicle_20260911(v.id);
 IF status->>'colour' IS DISTINCT FROM 'green' OR status->>'person_confirmed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'confirmation_readback_failed'; END IF;
 RETURN jsonb_build_object('ok',true,'confirmation_id',c.confirmation_id,'vehicle_id',v.id,'stock_number',v.stock_number,'parts_status',status);
END $function$;
