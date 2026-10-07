-- Department 135 uses its native copy of the PMB service/review engine.
-- The owner-file connector is management-only, hash-bound and disabled outside its transaction.
-- It grants no user role/session, email authority, browser API or PMB data access.
DO $$ BEGIN
 IF karratha135_intake.management_connection() IS NOT TRUE
  OR NOT EXISTS(SELECT 1 FROM karratha135_pdc.engine_release_135 WHERE singleton AND ready)
 THEN RAISE EXCEPTION 'Karratha staging management and released native engine required'; END IF;
END $$;
CREATE TABLE karratha135_intake.owner_attachment_manifests_20261007(
 source_hash text PRIMARY KEY CHECK(source_hash ~ '^[a-f0-9]{64}$'),
 workbook_sha256 text NOT NULL CHECK(workbook_sha256 ~ '^[a-f0-9]{64}$'),
 server_request_sha256 text NOT NULL,
 source_kind text NOT NULL CHECK(source_kind IN('service','parts')),
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 source_rows integer NOT NULL CHECK(source_rows BETWEEN 1 AND 10000),
 provenance jsonb NOT NULL,
 enabled boolean NOT NULL DEFAULT false,
 bound_txid bigint,
 bound_until timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 receipt jsonb,
 CHECK(NOT enabled OR (bound_txid IS NOT NULL AND bound_until IS NOT NULL))
);
ALTER TABLE karratha135_intake.owner_attachment_manifests_20261007 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON karratha135_intake.owner_attachment_manifests_20261007 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION karratha135_intake.owner_attachment_actor_20261007() RETURNS uuid
LANGUAGE sql STABLE SET search_path TO pg_catalog AS $$
 SELECT m.actor_id FROM karratha135_intake.owner_attachment_manifests_20261007 m
 JOIN auth.users u ON u.id=m.actor_id
 WHERE karratha135_intake.management_connection() IS TRUE
 AND m.source_hash=current_setting('k135.owner_attachment_hash',true)
 AND m.enabled AND m.bound_txid=txid_current() AND m.bound_until>clock_timestamp()
 AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
 AND lower(u.email)='codex.pmb.importer.staging@pmb.local'
$$;

CREATE FUNCTION karratha135_intake.owner_service_authorized_20261007(
 p_action text,p_rows jsonb,p_source_hash text,p_idempotency_key text,p_batch_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path TO pg_catalog AS $$
DECLARE m karratha135_intake.owner_attachment_manifests_20261007; b karratha135_pdc.pdc_pilbara_service_import_batches;
BEGIN
 IF karratha135_intake.owner_attachment_actor_20261007() IS NULL THEN RETURN false; END IF;
 SELECT * INTO m FROM karratha135_intake.owner_attachment_manifests_20261007
 WHERE source_hash=current_setting('k135.owner_attachment_hash',true) AND source_kind='service';
 IF NOT FOUND OR p_source_hash IS DISTINCT FROM m.source_hash THEN RETURN false; END IF;
 IF p_action='preview' THEN RETURN p_batch_id IS NULL AND p_idempotency_key='k135-owner-preview-'||m.source_hash
  AND jsonb_typeof(p_rows)='array' AND jsonb_array_length(p_rows)=m.source_rows
  AND encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'envelope',m.provenance)::text,'UTF8'),'sha256'),'hex')=m.server_request_sha256;
 ELSIF p_action='apply' THEN
  SELECT * INTO b FROM karratha135_pdc.pdc_pilbara_service_import_batches WHERE batch_id=p_batch_id;
  RETURN p_rows IS NULL AND b.batch_kind='preview' AND b.created_by=m.actor_id
   AND b.source_hash=m.source_hash AND b.source_link->>'workbook_sha256'=m.workbook_sha256
   AND b.idempotency_key='k135-owner-preview-'||m.source_hash
   AND p_idempotency_key='k135-owner-apply-'||m.source_hash;
 END IF;
 RETURN false;
END $$;
CREATE OR REPLACE FUNCTION karratha135_intake.authorized(p_action text, p_rows jsonb, p_source_hash text, p_idempotency_key text, p_batch_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'extensions', 'karratha135_intake'
AS $function$DECLARE
 actor uuid;
 b karratha135_pdc.pdc_pilbara_service_import_batches;
 parent_hash text;
BEGIN
 IF karratha135_intake.management_connection() IS TRUE THEN
  RETURN karratha135_intake.owner_service_authorized_20261007(p_action,p_rows,p_source_hash,p_idempotency_key,p_batch_id);
 END IF;
 actor:=karratha135_pdc.require_active_session_135();
 IF NOT EXISTS(SELECT 1 FROM karratha135_pdc.pdc_user_roles r WHERE r.auth_user_id=actor
  AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator'))
  OR p_action IS NULL OR p_action NOT IN('preview','apply','readback','source_readback') THEN RETURN false;END IF;
 IF p_action='preview' THEN
  IF p_batch_id IS NOT NULL OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array'
   OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000000
   OR octet_length(p_rows::text)>8388608
   OR lower(btrim(coalesce(p_source_hash,''))) !~ '^[a-f0-9]{64}$'
   OR length(btrim(coalesce(p_idempotency_key,''))) NOT BETWEEN 12 AND 160 THEN RETURN false;END IF;
  SELECT min(coalesce(x->>'workbook_sha256',x->'raw_row'->>'parent_attachment_sha256')) INTO parent_hash FROM jsonb_array_elements(p_rows) x;
  IF coalesce(parent_hash,'') !~ '^[a-f0-9]{64}$' OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x
   WHERE jsonb_typeof(x) IS DISTINCT FROM 'object' OR jsonb_typeof(x->'raw_row') IS DISTINCT FROM 'object'
   OR coalesce(x->>'department',x->'raw_row'->>'Dept','')<>'135'
   OR coalesce(x->>'workbook_sha256',x->'raw_row'->>'parent_attachment_sha256','')<>parent_hash
   OR (nullif(x->'raw_row'->>'parent_attachment_sha256','') IS NOT NULL AND x->'raw_row'->>'parent_attachment_sha256'<>parent_hash)
   OR (nullif(x->>'department','') IS NOT NULL AND nullif(x->'raw_row'->>'Dept','') IS NOT NULL AND x->>'department'<>x->'raw_row'->>'Dept'))
   THEN RETURN false;END IF;
  RETURN true;
 END IF;
 IF p_rows IS NOT NULL OR p_batch_id IS NULL THEN RETURN false;END IF;
 SELECT x.* INTO b FROM karratha135_pdc.pdc_pilbara_service_import_batches x WHERE x.batch_id=p_batch_id
  AND x.created_by=actor AND x.importer_version='pilbara_service_open_jobcards_v1'
  AND x.contract_revision='pmg_stock_v5';
 IF b.batch_id IS NULL OR coalesce(b.source_link->>'workbook_sha256','') !~ '^[a-f0-9]{64}$'
  OR EXISTS(SELECT 1 FROM karratha135_pdc.pdc_pilbara_service_import_rows x WHERE x.batch_id=b.batch_id
   AND coalesce(x.normalized_payload->>'department','')<>'135') THEN RETURN false;END IF;
 IF p_action='apply' THEN RETURN b.batch_kind='preview'
  AND b.source_hash=lower(btrim(coalesce(p_source_hash,'')))
  AND length(btrim(coalesce(p_idempotency_key,''))) BETWEEN 12 AND 160;END IF;
 RETURN b.batch_kind='apply' AND p_source_hash IS NULL AND p_idempotency_key IS NULL;
END
$function$
;
CREATE OR REPLACE FUNCTION karratha135_intake.import_actor()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'karratha135_intake'
AS $function$
DECLARE actor uuid;
BEGIN
 IF auth.uid() IS NOT NULL THEN RETURN auth.uid(); END IF;
 IF management_connection() IS NOT TRUE THEN RETURN NULL; END IF;
 actor:=karratha135_intake.owner_attachment_actor_20261007();
 IF actor IS NOT NULL THEN RETURN actor; END IF;
 SELECT a.auth_user_id INTO actor FROM authorizations a JOIN auth.users u ON u.id=a.auth_user_id
 WHERE a.normalized_email='codex.pmb.importer.staging@pmb.local'
 AND lower(u.email)=a.normalized_email AND u.deleted_at IS NULL
 AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
 AND a.revoked_at IS NULL;
 RETURN actor;
END $function$
;
CREATE OR REPLACE FUNCTION karratha135_pdc.refresh_shared_navision_135(p_rows jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
 actor uuid;
 stocks text[];
 src public.navision_backend_records%rowtype;
 own karratha135_pdc.navision_backend_records%rowtype;
 state karratha135_pdc.shared_navision_projection_state_135%rowtype;
 own_link uuid;
 matches integer;
 copied integer:=0;
BEGIN
 IF karratha135_intake.management_connection() IS TRUE THEN
  actor:=karratha135_intake.owner_attachment_actor_20261007();
  IF actor IS NULL OR p_rows IS NULL OR NOT karratha135_intake.owner_service_authorized_20261007(
   'preview',p_rows,current_setting('k135.owner_attachment_hash',true),
   'k135-owner-preview-'||current_setting('k135.owner_attachment_hash',true),NULL)
  THEN RAISE EXCEPTION 'bound_department135_source_required'; END IF;
 ELSE actor:=karratha135_pdc.require_active_session_135(); END IF;
 IF p_rows IS NOT NULL THEN
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array'
   OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000000
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x
      WHERE jsonb_typeof(x) IS DISTINCT FROM 'object'
       OR coalesce(x->>'department',x->'raw_row'->>'Dept','')<>'135'
       OR (x ? 'department' AND x->'raw_row' ? 'Dept'
        AND x->>'department' IS DISTINCT FROM x->'raw_row'->>'Dept'))
  THEN RAISE EXCEPTION 'invalid_department135_source' USING ERRCODE='22023'; END IF;
  SELECT array_agg(DISTINCT btrim(x->>'stock_number')) INTO stocks
   FROM jsonb_array_elements(p_rows) x
   WHERE karratha135_pdc.is_real_vehicle_stock_number(x->>'stock_number');
 ELSE
  -- A read refresh can only touch source identities already belonging to this centre.
  SELECT array_agg(DISTINCT stock) INTO stocks FROM(
    SELECT btrim(coalesce(normalized_data->>'batch',normalized_data->>'stock','')) stock
     FROM karratha135_pdc.navision_backend_records
    UNION SELECT btrim(v.stock_number) FROM karratha135_pdc.vehicles v
     WHERE v.deleted_at IS NULL AND EXISTS(
      SELECT 1 FROM karratha135_pdc.pdc_pilbara_service_operations o
       WHERE o.vehicle_id=v.id AND o.department='135')
   ) q WHERE karratha135_pdc.is_real_vehicle_stock_number(stock);
 END IF;
 IF coalesce(cardinality(stocks),0)=0 THEN
  RETURN jsonb_build_object('ok',true,'refreshed',0);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('k135:shared-navision-projection',0));
 FOR src IN
  SELECT s.* FROM public.navision_backend_records s
  WHERE s.source_system='microsoft_navision'
   AND (btrim(coalesce(s.normalized_data->>'batch',s.normalized_data->>'stock',''))=ANY(stocks)
     OR EXISTS(SELECT 1 FROM karratha135_pdc.shared_navision_projection_state_135 t
       WHERE t.shared_record_id=s.id))
  ORDER BY s.id
 LOOP
  SELECT * INTO state FROM karratha135_pdc.shared_navision_projection_state_135
   WHERE shared_record_id=src.id;
  IF FOUND AND state.shared_version=src.version
   AND state.shared_updated_at=src.updated_at THEN CONTINUE; END IF;

  -- Preserve exact import evidence in an own table; no shared triggers are installed here.
  INSERT INTO karratha135_pdc.navision_import_batches(
   id,idempotency_key,request_hash,source_name,source_timestamp,source_hash,preview_hash,
   base_revision,result_revision,status,total_rows,new_count,changed_count,unchanged_count,
   missing_count,invalid_count,conflict_count,receipt,actor_id,actor_email,applied_at,
   rolled_back_at,rolled_back_by,source_system,dealer_code)
  SELECT b.id,b.idempotency_key,b.request_hash,b.source_name,b.source_timestamp,b.source_hash,
   b.preview_hash,b.base_revision,b.result_revision,b.status,b.total_rows,b.new_count,b.changed_count,
   b.unchanged_count,b.missing_count,b.invalid_count,b.conflict_count,
   jsonb_build_object('contract','shared_navision_source_evidence_135','shared_batch_id',b.id,
     'source_hash',b.source_hash,'selected_record_projection',true),b.actor_id,
   b.actor_email,b.applied_at,b.rolled_back_at,b.rolled_back_by,b.source_system,b.dealer_code
  FROM public.navision_import_batches b
  WHERE b.id=ANY(ARRAY[src.first_seen_batch_id,src.last_seen_batch_id,src.missing_since_batch_id])
  ON CONFLICT(id) DO NOTHING;

  SELECT * INTO own FROM karratha135_pdc.navision_backend_records WHERE id=src.id FOR UPDATE;
  IF FOUND THEN own_link:=own.canonical_vehicle_id;
  ELSE
   SELECT count(*),min(v.id::text)::uuid INTO matches,own_link
    FROM karratha135_pdc.vehicles v
    WHERE btrim(v.stock_number)=btrim(coalesce(src.normalized_data->>'batch',src.normalized_data->>'stock',''))
     AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
     AND EXISTS(SELECT 1 FROM karratha135_pdc.pdc_pilbara_service_operations o
       WHERE o.vehicle_id=v.id AND o.department='135');
   IF matches<>1 THEN own_link:=NULL; END IF;
  END IF;
  -- The PMB canonical_vehicle_id is deliberately never read into the own link.
  INSERT INTO karratha135_pdc.navision_backend_records(
   id,source_record_id,row_hash,normalized_data,raw_evidence,canonical_vehicle_id,
   first_seen_batch_id,last_seen_batch_id,missing_since_batch_id,is_current,version,
   created_at,updated_at,source_system,dealer_code,record_status)
  VALUES(src.id,src.source_record_id,src.row_hash,src.normalized_data,src.raw_evidence,own_link,
   src.first_seen_batch_id,src.last_seen_batch_id,src.missing_since_batch_id,src.is_current,1,
   src.created_at,src.updated_at,src.source_system,src.dealer_code,src.record_status)
  ON CONFLICT(id) DO UPDATE SET
   source_record_id=excluded.source_record_id,row_hash=excluded.row_hash,
   normalized_data=excluded.normalized_data,raw_evidence=excluded.raw_evidence,
   first_seen_batch_id=excluded.first_seen_batch_id,last_seen_batch_id=excluded.last_seen_batch_id,
   missing_since_batch_id=excluded.missing_since_batch_id,is_current=excluded.is_current,
   version=karratha135_pdc.navision_backend_records.version+1,updated_at=excluded.updated_at,
   source_system=excluded.source_system,dealer_code=excluded.dealer_code,
   record_status=excluded.record_status;
  INSERT INTO karratha135_pdc.shared_navision_projection_state_135(
   shared_record_id,shared_version,shared_updated_at,refreshed_at)
  VALUES(src.id,src.version,src.updated_at,clock_timestamp())
  ON CONFLICT(shared_record_id) DO UPDATE SET
   shared_version=excluded.shared_version,shared_updated_at=excluded.shared_updated_at,
   refreshed_at=excluded.refreshed_at;
  copied:=copied+1;
 END LOOP;
 IF copied>0 THEN
  UPDATE karratha135_pdc.navision_backend_revision
   SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 END IF;
 RETURN jsonb_build_object('ok',true,'refreshed',copied);
END;
$function$
;
CREATE OR REPLACE FUNCTION karratha135_intake.import_owner_parts_core_20261007(p_envelope jsonb, p_rows jsonb)
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
 IF kind<>'user_attached_workbook' OR p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request'
 OR p_envelope->>'company' IS DISTINCT FROM '01' OR p_envelope->>'division' IS DISTINCT FROM '1'
 OR p_envelope->>'department' IS DISTINCT FROM '135'
 OR p_envelope ? 'gmail_message_id' OR p_envelope ? 'sender_verified' OR p_envelope ? 'mailbox'
 OR karratha135_intake.owner_attachment_actor_20261007() IS NULL
 OR NOT EXISTS(SELECT 1 FROM karratha135_intake.owner_attachment_manifests_20261007 m
  WHERE m.source_hash=current_setting('k135.owner_attachment_hash',true) AND m.source_kind='parts'
  AND m.server_request_sha256=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'envelope',p_envelope)::text,'UTF8'),'sha256'),'hex'))
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) z WHERE z->>'Dept' IS DISTINCT FROM '135')
 THEN RETURN jsonb_build_object('ok',false,'code','bound_department135_owner_attachment_required'); END IF;
 revolution:=true; -- Reuse the exact-one-department job guard for this scoped source.
 BEGIN snap:=(p_envelope->>'snapshot_at')::timestamptz;
  received:=CASE WHEN kind IN ('gmail_csv','authorised_gmail_workbook','revolution_automated_parts_workbook') THEN (p_envelope->>'received_at')::timestamptz ELSE NULL END;
 EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'code','invalid_snapshot_time'); END;
 IF snap IS NULL OR snap>clock_timestamp()+interval '5 minutes'
 OR (kind IN ('gmail_csv','authorised_gmail_workbook','revolution_automated_parts_workbook') AND (received IS NULL OR snap>received+interval '5 minutes' OR received>clock_timestamp()+interval '5 minutes'))
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

CREATE FUNCTION karratha135_intake.import_owner_attachment_20261007(
 p_kind text,p_rows jsonb,p_source_hash text,p_envelope jsonb,p_apply boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO pg_catalog SET lock_timeout TO '5s' SET statement_timeout TO '120s' AS $$
DECLARE actor uuid; req text; m karratha135_intake.owner_attachment_manifests_20261007;
 preview jsonb; applied jsonb; result jsonb; old_context text:=current_setting('k135.owner_attachment_hash',true);
BEGIN
 IF karratha135_intake.management_connection() IS NOT TRUE
  OR NOT EXISTS(SELECT 1 FROM karratha135_pdc.engine_release_135 WHERE singleton AND ready)
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_kind NOT IN('service','parts') OR coalesce(p_source_hash,'') !~ '^[a-f0-9]{64}$'
  OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 10000
  OR octet_length(p_rows::text)>8388608 OR p_envelope->>'source_kind' IS DISTINCT FROM 'user_attached_workbook'
  OR p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request'
  OR p_envelope->>'company' IS DISTINCT FROM '01' OR p_envelope->>'division' IS DISTINCT FROM '1'
  OR p_envelope->>'department' IS DISTINCT FROM '135'
  OR coalesce(p_envelope->>'attachment_sha256','') !~ '^[a-f0-9]{64}$'
  OR coalesce(p_envelope->>'source_file','') !~* '[.]xlsx$'
  OR nullif(p_envelope->>'attachment_id','') IS NULL OR length(coalesce(p_envelope->>'user_instruction',''))<20
  OR p_envelope ? 'gmail_message_id' OR p_envelope ? 'sender_verified' OR p_envelope ? 'mailbox'
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) r WHERE
   (p_kind='service' AND (r->>'department' IS DISTINCT FROM '135'
    OR r->'raw_row'->>'Dept' IS DISTINCT FROM '135' OR r->'raw_row'->>'Company' IS DISTINCT FROM '01'
    OR r->'raw_row'->>'Division' IS DISTINCT FROM '1' OR r->>'workbook_sha256' IS DISTINCT FROM p_envelope->>'attachment_sha256'
    OR r->'raw_row'->>'parent_attachment_sha256' IS DISTINCT FROM p_envelope->>'attachment_sha256'))
   OR (p_kind='parts' AND r->>'Dept' IS DISTINCT FROM '135'))
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_owner_attachment_contract'); END IF;
 SELECT u.id INTO actor FROM auth.users u WHERE lower(u.email)='codex.pmb.importer.staging@pmb.local'
  AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp());
 IF actor IS NULL THEN RETURN jsonb_build_object('ok',false,'code','import_actor_unavailable'); END IF;
 req:=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'envelope',p_envelope)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('k135:owner-attachment:'||p_source_hash,0));
 SELECT * INTO m FROM karratha135_intake.owner_attachment_manifests_20261007 WHERE source_hash=p_source_hash FOR UPDATE;
 IF FOUND AND (m.server_request_sha256<>req OR m.source_kind<>p_kind OR m.actor_id<>actor)
 THEN RETURN jsonb_build_object('ok',false,'code','source_hash_payload_conflict'); END IF;
 INSERT INTO karratha135_intake.owner_attachment_manifests_20261007(source_hash,workbook_sha256,server_request_sha256,source_kind,actor_id,source_rows,provenance)
 VALUES(p_source_hash,p_envelope->>'attachment_sha256',req,p_kind,actor,jsonb_array_length(p_rows),p_envelope) ON CONFLICT DO NOTHING;
 UPDATE karratha135_intake.owner_attachment_manifests_20261007 SET enabled=true,bound_txid=txid_current(),bound_until=clock_timestamp()+interval '5 minutes' WHERE source_hash=p_source_hash;
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
  result:=karratha135_intake.import_owner_parts_core_20261007(p_envelope,p_rows);
  IF coalesce(result->>'ok','false')<>'true' THEN RAISE EXCEPTION 'parts_import_failed: %',result; END IF;
 END IF;
 UPDATE karratha135_intake.owner_attachment_manifests_20261007 SET enabled=false,bound_txid=NULL,bound_until=NULL,receipt=result WHERE source_hash=p_source_hash;
 PERFORM set_config('k135.owner_attachment_hash',coalesce(old_context,''),true);
 RETURN result||jsonb_build_object('importer_disabled',true);
END $$;
REVOKE ALL ON FUNCTION karratha135_intake.owner_attachment_actor_20261007() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION karratha135_intake.owner_service_authorized_20261007(text,jsonb,text,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION karratha135_intake.import_owner_parts_core_20261007(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION karratha135_intake.import_owner_attachment_20261007(text,jsonb,text,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
