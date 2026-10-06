-- Craig authorised automated service feeds for Departments 138 and 139 on 6 October.
-- The genuine automated source remains recorded; no Craig impersonation or auth grants.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR pdc_codex_intake_private.management_connection() IS NOT TRUE THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF md5(pg_get_functiondef('pdc_codex_intake_private.management_authorized(text,jsonb,text,text,uuid)'::regprocedure))<>'5412c7e7f74f3808d79f13e72f3ab9e4' THEN RAISE EXCEPTION 'management_authorizer_changed'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_manifest_20261006(p_provenance jsonb,p_message_id text,p_filename text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog
AS $fn$
 SELECT coalesce(p_provenance->>'source_kind'='revolution_automated_service_workbook'
 AND p_provenance->>'authority'='explicit_user_request'
 AND length(p_provenance->>'user_instruction')>20
 AND p_provenance->>'subject'='PMG PD Service Complete'
 AND p_filename ~ '^PMG PD Service Complete[.]xlsx?$'
 AND p_provenance->>'source_format'='ooxml_workbook'
 AND p_provenance->>'company'='01' AND p_provenance->>'division'='1'
 AND pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_provenance->'authentication',p_message_id),false);
$fn$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_rows_20261006(p_rows jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog
AS $fn$
 SELECT coalesce(jsonb_typeof(p_rows)='array' AND jsonb_array_length(p_rows)>0
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE
 coalesce(x->>'department','') NOT IN ('138','139')
 OR x->'raw_row'->>'Dept' IS DISTINCT FROM x->>'department'
 OR x->'raw_row'->>'Company' IS DISTINCT FROM '01'
 OR x->'raw_row'->>'Division' IS DISTINCT FROM '1'
 OR x->'raw_row'->>'from_address' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
 OR x->'raw_row'->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
 OR x->'raw_row'->>'email_subject' IS DISTINCT FROM 'PMG PD Service Complete'
 OR coalesce(x->>'repair_order_number','') !~ ('^J'||(x->>'department')||'[0-9]+$')),false);
$fn$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.revolution_service_rows_20261006(jsonb) FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 DROP CONSTRAINT management_email_manifests_sender_check,
 ADD CONSTRAINT management_email_manifests_sender_check CHECK(sender IN ('craig.watson@broometoyota.com.au','bhavesh.patel@pmgwa.com.au','noreply@revolutionsoftware.com.au')),
 ADD CONSTRAINT management_manifest_revolution_authentication CHECK(sender IS DISTINCT FROM 'noreply@revolutionsoftware.com.au' OR pdc_codex_intake_private.revolution_service_manifest_20261006(provenance,gmail_message_id,filename));
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
   IF m.sender='noreply@revolutionsoftware.com.au' AND (NOT revolution_service_manifest_20261006(m.provenance,m.gmail_message_id,m.filename) OR NOT revolution_service_rows_20261006(p_rows)) THEN RETURN false; END IF;
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
 IF m.sender='noreply@revolutionsoftware.com.au' AND NOT revolution_service_manifest_20261006(m.provenance,m.gmail_message_id,m.filename) THEN RETURN false; END IF;
 IF p_action='apply' THEN
   IF m.sender='noreply@revolutionsoftware.com.au' THEN
    SELECT jsonb_agg(r.normalized_payload||jsonb_build_object('raw_row',r.raw_row) ORDER BY r.source_order) INTO scope_rows FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=b.batch_id;
    IF jsonb_array_length(coalesce(scope_rows,'[]'))<>m.source_rows OR NOT revolution_service_rows_20261006(scope_rows) THEN RETURN false; END IF;
   END IF;
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
END $function$
;
