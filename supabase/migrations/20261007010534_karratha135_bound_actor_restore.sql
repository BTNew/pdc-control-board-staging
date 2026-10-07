-- Same disabled-importer transaction discipline as the PMB API; rollback restores it on error.
CREATE OR REPLACE FUNCTION karratha135_intake.owner_service_authorized_20261007(
 p_action text,p_rows jsonb,p_source_hash text,p_idempotency_key text,p_batch_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path TO pg_catalog AS $$
DECLARE m karratha135_intake.owner_attachment_manifests_20261007; b karratha135_pdc.pdc_pilbara_service_import_batches;
BEGIN
 IF karratha135_intake.owner_attachment_actor_20261007() IS NULL THEN RETURN false; END IF;
 SELECT * INTO m FROM karratha135_intake.owner_attachment_manifests_20261007
 WHERE source_hash=current_setting('k135.owner_attachment_hash',true) AND source_kind='service';
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_action IN('readback','source_readback') THEN
  SELECT * INTO b FROM karratha135_pdc.pdc_pilbara_service_import_batches WHERE batch_id=p_batch_id;
  RETURN p_rows IS NULL AND p_source_hash IS NULL AND p_idempotency_key IS NULL
   AND b.source_hash=m.source_hash AND b.created_by=m.actor_id AND b.batch_kind='apply'
   AND b.source_link->>'workbook_sha256'=m.workbook_sha256
   AND b.idempotency_key='k135-owner-apply-'||m.source_hash;
 END IF;
 IF p_source_hash IS DISTINCT FROM m.source_hash THEN RETURN false; END IF;
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
CREATE OR REPLACE FUNCTION karratha135_intake.import_owner_attachment_20261007(
 p_kind text,p_rows jsonb,p_source_hash text,p_envelope jsonb,p_apply boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO pg_catalog SET lock_timeout TO '5s' SET statement_timeout TO '120s' AS $$
DECLARE actor uuid; prior_ban timestamptz; req text; m karratha135_intake.owner_attachment_manifests_20261007;
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
 SELECT u.id,u.banned_until INTO actor,prior_ban FROM auth.users u WHERE lower(u.email)='codex.pmb.importer.staging@pmb.local'
  AND u.deleted_at IS NULL FOR UPDATE;
 IF actor IS NULL THEN RETURN jsonb_build_object('ok',false,'code','import_actor_unavailable'); END IF;
 req:=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'envelope',p_envelope)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('k135:owner-attachment:'||p_source_hash,0));
 SELECT * INTO m FROM karratha135_intake.owner_attachment_manifests_20261007 WHERE source_hash=p_source_hash FOR UPDATE;
 IF FOUND AND (m.server_request_sha256<>req OR m.source_kind<>p_kind OR m.actor_id<>actor)
 THEN RETURN jsonb_build_object('ok',false,'code','source_hash_payload_conflict'); END IF;
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
  result:=karratha135_intake.import_owner_parts_core_20261007(p_envelope,p_rows);
  IF coalesce(result->>'ok','false')<>'true' THEN RAISE EXCEPTION 'parts_import_failed: %',result; END IF;
 END IF;
 UPDATE karratha135_intake.owner_attachment_manifests_20261007 SET enabled=false,bound_txid=NULL,bound_until=NULL,receipt=result WHERE source_hash=p_source_hash;
 UPDATE auth.users SET banned_until=prior_ban WHERE id=actor;
 IF (SELECT banned_until FROM auth.users WHERE id=actor) IS DISTINCT FROM prior_ban THEN RAISE EXCEPTION 'importer_state_restore_failed'; END IF;
 PERFORM set_config('k135.owner_attachment_hash',coalesce(old_context,''),true);
 RETURN result||jsonb_build_object('importer_disabled',true);
END $$;
