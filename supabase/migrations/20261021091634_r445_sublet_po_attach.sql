-- r445 (F58, change request; Craig 21 Oct 17:05 AWST): attach the sublet purchase order PDF to a GP PO on the PDC staging
-- board. Staging cdsmnqxtyyoeoznmbidd only. ATTACH ONLY: no supplier email, no outbox, nothing is ever sent.
-- Craig's workflow: whoever raises the job card attaches the sublet PO straight away, before the w/Sublet upload brings the PO
-- onto the board. So a document is stored against the VEHICLE and the GP PO NUMBER (GP + 8 digits), optionally with the
-- operation lines it covers; when the w/Sublet import later attaches that PO to lines, the read joins on vehicle + PO number
-- and shows it on those sublet rows (no importer change).
-- (1) public.pdc_sublet_po_attach_pilot_445: the pilot gate (vehicle ids). Empty here; the pilot vehicle is added at apply
--     time outside Git. Every r445 RPC and the storage upload policy refuse vehicles that are not in it.
-- (2) public.pdc_sublet_po_documents_445: one row per uploaded PDF; one current document per vehicle + PO; Replace supersedes
--     (superseded_at / superseded_by_doc_id set once) and keeps history. Append-only (no delete, no other update). RLS, no
--     app-role table access (SECURITY DEFINER RPCs only).
-- (3) Private bucket pdc-sublet-po-staging: PDF only, 10 MB. Storage policies: INSERT (controllers / administrators, own
--     sublet-po/<uid>/<pilot vehicle>/<uuid>.pdf path) and SELECT (controllers / administrators, recorded documents only; used
--     for signed URLs). No UPDATE or DELETE policy.
-- (4) RPCs: get_pdc_sublet_po_attach_pilot_445(), get_pdc_sublet_po_documents_445(uuid), record_pdc_sublet_po_document_445(...).
-- Not touched: vehicles, lines, ticks, PO refs, categories, bays, bookings, imports, the clock tick, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r445: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r445: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r445: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r445: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)<>'6083fb5bcf03d341d9101831c2217cb8'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.sublet_po_vehicle_439(uuid)'::regprocedure)<>'756b7a4164a6e9ce37bb33c7c861b346'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)'::regprocedure)<>'709b0156a11db82721e6acb40c2c947b'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.get_pdc_sublet_lines_439(uuid)'::regprocedure)<>'b211d82171b565ee841c08ae9023c297'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.sublet_line_key_439(jsonb)'::regprocedure) IS NULL
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'fc3717a5215de94c93ebb2c7facfe744' THEN RAISE EXCEPTION 'r445: sublet / import functions are not the r444 versions (this release must not touch them)'; END IF;
 IF to_regclass('public.pdc_sublet_po_documents_445') IS NOT NULL OR to_regclass('public.pdc_sublet_po_attach_pilot_445') IS NOT NULL
    OR EXISTS(SELECT 1 FROM storage.buckets WHERE id='pdc-sublet-po-staging')
    OR EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND policyname LIKE 'pdc_sublet_po_%_445')
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r445')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sublet_po_attach_445' OR added_in='r445') THEN RAISE EXCEPTION 'r445: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=244) THEN RAISE EXCEPTION 'r445: sort_order 244 taken'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>157 THEN RAISE EXCEPTION 'r445: expected 157 pins before'; END IF;
END $g$;

CREATE TABLE public.pdc_sublet_po_attach_pilot_445 (
 vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id),
 added_by text NOT NULL CHECK (length(btrim(added_by)) BETWEEN 1 AND 200),
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 300),
 added_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.pdc_sublet_po_attach_pilot_445 IS 'r445 (F58): vehicles in the sublet PO attach pilot (filled at apply time, outside Git). RPCs and the storage upload policy refuse other vehicles.';
ALTER TABLE public.pdc_sublet_po_attach_pilot_445 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_sublet_po_attach_pilot_445 FROM PUBLIC, anon, authenticated;

CREATE TABLE public.pdc_sublet_po_documents_445 (
 doc_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 po_number text NOT NULL CHECK (po_number ~ '^GP[0-9]{8}$'),
 covered_line_keys text[] NOT NULL DEFAULT '{}'::text[] CHECK (cardinality(covered_line_keys)<=200),
 bucket_id text NOT NULL CHECK (bucket_id='pdc-sublet-po-staging'),
 storage_path text NOT NULL UNIQUE CHECK (storage_path ~ '^sublet-po/[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.pdf$'),
 content_type text NOT NULL CHECK (content_type='application/pdf'),
 byte_length integer NOT NULL CHECK (byte_length BETWEEN 1 AND 10485760),
 sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
 original_filename text NOT NULL CHECK (length(original_filename) BETWEEN 5 AND 180 AND original_filename ~* '\.pdf$'),
 uploaded_by uuid NOT NULL,
 uploaded_by_email text NOT NULL,
 uploaded_role text NOT NULL CHECK (uploaded_role IN ('operator','administrator')),
 uploaded_at timestamptz NOT NULL DEFAULT now(),
 replaces_doc_id uuid REFERENCES public.pdc_sublet_po_documents_445(doc_id),
 superseded_at timestamptz,
 superseded_by_doc_id uuid REFERENCES public.pdc_sublet_po_documents_445(doc_id) DEFERRABLE INITIALLY DEFERRED,
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
 response jsonb,
 CHECK ((superseded_at IS NULL) = (superseded_by_doc_id IS NULL)),
 CHECK (storage_path LIKE 'sublet-po/'||uploaded_by::text||'/'||vehicle_id::text||'/%'),
 UNIQUE (uploaded_by, idempotency_key)
);
CREATE UNIQUE INDEX pdc_sublet_po_documents_445_current ON public.pdc_sublet_po_documents_445(vehicle_id, po_number) WHERE superseded_at IS NULL;
CREATE INDEX pdc_sublet_po_documents_445_vehicle ON public.pdc_sublet_po_documents_445(vehicle_id, uploaded_at);
COMMENT ON TABLE public.pdc_sublet_po_documents_445 IS 'r445 (F58): sublet purchase order PDFs per vehicle + GP PO (one current, superseded ones kept as history). Append-only.';
ALTER TABLE public.pdc_sublet_po_documents_445 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_sublet_po_documents_445 FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.pdc_sublet_po_documents_append_only_445()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $f$
BEGIN
 -- r445 (F58): documents are history. No delete; the only update is marking a current document superseded, once.
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'PDC_445_DOCUMENTS_APPEND_ONLY' USING errcode='42501'; END IF;
 IF OLD.superseded_at IS NOT NULL OR NEW.superseded_at IS NULL OR NEW.superseded_by_doc_id IS NULL
    OR (to_jsonb(NEW)-'superseded_at'-'superseded_by_doc_id') IS DISTINCT FROM (to_jsonb(OLD)-'superseded_at'-'superseded_by_doc_id') THEN
  RAISE EXCEPTION 'PDC_445_DOCUMENTS_APPEND_ONLY' USING errcode='42501'; END IF;
 RETURN NEW;
END
$f$;
REVOKE ALL ON FUNCTION public.pdc_sublet_po_documents_append_only_445() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER pdc_sublet_po_documents_append_only_445 BEFORE UPDATE OR DELETE ON public.pdc_sublet_po_documents_445
 FOR EACH ROW EXECUTE FUNCTION public.pdc_sublet_po_documents_append_only_445();

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 VALUES ('pdc-sublet-po-staging','pdc-sublet-po-staging',false,10485760,ARRAY['application/pdf']);

-- The caller's role when they are an approved, active controller (operator) or administrator; NULL otherwise.
CREATE OR REPLACE FUNCTION public.pdc_sublet_po_attach_role_445()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $f$
 -- r445 (F58): controllers (operator) and administrators only; human sessions with a matching email (no service paths).
 SELECT r.role::text FROM public.pdc_user_roles r
 WHERE auth.uid() IS NOT NULL AND coalesce(auth.jwt()->>'role','')='authenticated' AND public.pdc_monitor_staging_guard()
   AND r.auth_user_id=auth.uid() AND lower(r.email)=lower(btrim(coalesce(auth.jwt()->>'email','')))
   AND r.active AND r.account_status='approved' AND r.role::text IN ('operator','administrator')
 LIMIT 1;
$f$;
REVOKE ALL ON FUNCTION public.pdc_sublet_po_attach_role_445() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pdc_sublet_po_attach_role_445() TO authenticated;

CREATE OR REPLACE FUNCTION public.pdc_sublet_po_upload_allowed_445(p_bucket text, p_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $f$
DECLARE v_parts text[];
BEGIN
 -- r445 (F58): storage INSERT policy. Controllers / administrators upload only to sublet-po/<own uid>/<pilot vehicle>/<uuid>.pdf
 -- (the bucket itself limits type to application/pdf and size to 10 MB). Never an overwrite (no UPDATE policy).
 IF p_bucket IS DISTINCT FROM 'pdc-sublet-po-staging' OR public.pdc_sublet_po_attach_role_445() IS NULL THEN RETURN false; END IF;
 IF coalesce(p_name,'') !~ '^sublet-po/[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$' THEN RETURN false; END IF;
 v_parts:=string_to_array(p_name,'/');
 IF v_parts[2] IS DISTINCT FROM auth.uid()::text THEN RETURN false; END IF;
 RETURN EXISTS(SELECT 1 FROM public.pdc_sublet_po_attach_pilot_445 p JOIN public.vehicles v ON v.id=p.vehicle_id
  WHERE p.vehicle_id::text=v_parts[3] AND v.deleted_at IS NULL AND v.lifecycle_state='active');
EXCEPTION WHEN others THEN RETURN false;
END
$f$;
REVOKE ALL ON FUNCTION public.pdc_sublet_po_upload_allowed_445(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pdc_sublet_po_upload_allowed_445(text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.pdc_sublet_po_read_allowed_445(p_bucket text, p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $f$
 -- r445 (F58): storage SELECT policy (signed URLs): controllers / administrators, recorded documents only (current or history).
 SELECT p_bucket='pdc-sublet-po-staging' AND public.pdc_sublet_po_attach_role_445() IS NOT NULL
  AND EXISTS(SELECT 1 FROM public.pdc_sublet_po_documents_445 d WHERE d.bucket_id=p_bucket AND d.storage_path=p_name);
$f$;
REVOKE ALL ON FUNCTION public.pdc_sublet_po_read_allowed_445(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pdc_sublet_po_read_allowed_445(text,text) TO authenticated;

CREATE POLICY pdc_sublet_po_upload_445 ON storage.objects FOR INSERT TO authenticated
 WITH CHECK (bucket_id='pdc-sublet-po-staging' AND public.pdc_sublet_po_upload_allowed_445(bucket_id,name));
CREATE POLICY pdc_sublet_po_read_445 ON storage.objects FOR SELECT TO authenticated
 USING (bucket_id='pdc-sublet-po-staging' AND public.pdc_sublet_po_read_allowed_445(bucket_id,name));

-- The vehicle's operation lines (key + label) for the "covers lines" picker; same line set and keys as the r439 Sublet read.
CREATE OR REPLACE FUNCTION public.pdc_sublet_po_vehicle_lines_445(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $f$
 SELECT coalesce(jsonb_agg(jsonb_build_object('line_key',k,'label',CASE WHEN op ~ '^PD[0-9]{3}-' THEN 'PD line '||(substring(op from 3 for 3))::integer::text ELSE coalesce(nullif(op,''),k) END,
   'description',left(coalesce(l->>'description',''),180)) ORDER BY ord),'[]'::jsonb)
 FROM (SELECT x.l, x.ord, pdc_work_categories_private.sublet_line_key_439(x.l) k, upper(btrim(coalesce(x.l->>'operation_no',''))) op
       FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY x(l,ord)
       WHERE coalesce((x.l->>'active')::boolean,true) AND NOT coalesce((x.l->>'rejected')::boolean,false)) s
 WHERE k IS NOT NULL;
$f$;
REVOKE ALL ON FUNCTION public.pdc_sublet_po_vehicle_lines_445(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_pdc_sublet_po_attach_pilot_445()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $f$
DECLARE v_role text:=public.pdc_sublet_po_attach_role_445();
BEGIN
 -- r445 (F58): which vehicles show the Attach PO controls. Controllers / administrators get the pilot vehicle ids; anyone
 -- else gets none (the documents are for controllers and administrators only).
 IF v_role IS NULL THEN RETURN jsonb_build_object('ok',true,'version','r445','can_attach',false,'vehicle_ids','[]'::jsonb); END IF;
 RETURN jsonb_build_object('ok',true,'version','r445','can_attach',true,'actor_role',v_role,'bucket_id','pdc-sublet-po-staging','max_bytes',10485760,
  'vehicle_ids',coalesce((SELECT jsonb_agg(p.vehicle_id ORDER BY p.vehicle_id) FROM public.pdc_sublet_po_attach_pilot_445 p
   JOIN public.vehicles v ON v.id=p.vehicle_id WHERE v.deleted_at IS NULL),'[]'::jsonb));
END
$f$;
REVOKE ALL ON FUNCTION public.get_pdc_sublet_po_attach_pilot_445() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_sublet_po_attach_pilot_445() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pdc_sublet_po_documents_445(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $f$
DECLARE v_role text:=public.pdc_sublet_po_attach_role_445(); v_lines jsonb; v_pilot boolean; v_active boolean;
BEGIN
 -- r445 (F58): one vehicle's sublet PO documents. Each current document (vehicle + GP PO) with its file details, who / when,
 -- the lines it was said to cover, its history (superseded uploads) and the board lines that now carry that PO from the
 -- w/Sublet import (joined on vehicle + PO number at read time): state 'pending' until the upload brings the PO, then 'linked'.
 IF v_role IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 SELECT v.deleted_at IS NULL AND v.lifecycle_state='active' INTO v_active FROM public.vehicles v WHERE v.id=p_vehicle_id;
 IF p_vehicle_id IS NULL OR v_active IS NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 v_pilot:=EXISTS(SELECT 1 FROM public.pdc_sublet_po_attach_pilot_445 WHERE vehicle_id=p_vehicle_id);
 IF NOT v_pilot AND NOT EXISTS(SELECT 1 FROM public.pdc_sublet_po_documents_445 WHERE vehicle_id=p_vehicle_id) THEN
  RETURN jsonb_build_object('ok',false,'code','sublet_po_attach_not_in_pilot'); END IF;
 v_lines:=public.pdc_sublet_po_vehicle_lines_445(p_vehicle_id);
 RETURN jsonb_build_object('ok',true,'code','sublet_po_documents','version','r445','vehicle_id',p_vehicle_id,'pilot',v_pilot,
  'can_attach',v_pilot AND v_active,'actor_role',v_role,'bucket_id','pdc-sublet-po-staging','max_bytes',10485760,'lines',v_lines,
  'documents',coalesce((SELECT jsonb_agg(jsonb_build_object('doc_id',d.doc_id,'po_number',d.po_number,'original_filename',d.original_filename,
     'byte_length',d.byte_length,'sha256',d.sha256,'storage_path',d.storage_path,'uploaded_by_email',d.uploaded_by_email,'uploaded_role',d.uploaded_role,
     'uploaded_at',d.uploaded_at,'replaces_doc_id',d.replaces_doc_id,'covered_line_keys',to_jsonb(d.covered_line_keys),
     'covered_labels',(SELECT coalesce(jsonb_agg(e->>'label' ORDER BY o),'[]'::jsonb) FROM jsonb_array_elements(v_lines) WITH ORDINALITY y(e,o) WHERE (e->>'line_key')=ANY(d.covered_line_keys)),
     'board_lines',b.lines,'state',CASE WHEN jsonb_array_length(b.lines)>0 THEN 'linked' ELSE 'pending' END,
     'history',(SELECT coalesce(jsonb_agg(jsonb_build_object('doc_id',h.doc_id,'original_filename',h.original_filename,'byte_length',h.byte_length,'sha256',h.sha256,
        'storage_path',h.storage_path,'uploaded_by_email',h.uploaded_by_email,'uploaded_at',h.uploaded_at,'superseded_at',h.superseded_at) ORDER BY h.uploaded_at DESC),'[]'::jsonb)
       FROM public.pdc_sublet_po_documents_445 h WHERE h.vehicle_id=d.vehicle_id AND h.po_number=d.po_number AND h.superseded_at IS NOT NULL))
    ORDER BY d.po_number)
   FROM public.pdc_sublet_po_documents_445 d
   CROSS JOIN LATERAL (SELECT coalesce(jsonb_agg(jsonb_build_object('line_key',r.line_key,'label',coalesce((SELECT e->>'label' FROM jsonb_array_elements(v_lines) e WHERE e->>'line_key'=r.line_key LIMIT 1),r.line_key))
      ORDER BY r.line_no NULLS LAST, r.line_key),'[]'::jsonb) lines
     FROM public.pdc_service_line_po_refs_439 r WHERE r.vehicle_id=d.vehicle_id AND r.active AND r.po_number=d.po_number) b
   WHERE d.vehicle_id=p_vehicle_id AND d.superseded_at IS NULL),'[]'::jsonb));
END
$f$;
REVOKE ALL ON FUNCTION public.get_pdc_sublet_po_documents_445(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_sublet_po_documents_445(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_pdc_sublet_po_document_445(p_vehicle_id uuid, p_po_number text, p_storage_path text, p_byte_length integer,
 p_sha256 text, p_original_filename text, p_covered_line_keys text[], p_replaces_doc_id uuid, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $f$
DECLARE
 v_uid uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_role text:=public.pdc_sublet_po_attach_role_445();
 v_po text:=upper(btrim(coalesce(p_po_number,''))); v_sha text:=lower(btrim(coalesce(p_sha256,''))); v_name text;
 v_keys text[]; v_valid text[]; v_req text; v_prior public.pdc_sublet_po_documents_445%rowtype; v_cur public.pdc_sublet_po_documents_445%rowtype;
 v_obj record; v_doc uuid:=gen_random_uuid(); v_res jsonb;
BEGIN
 -- r445 (F58): record a sublet purchase order PDF the screen has just uploaded to pdc-sublet-po-staging (own
 -- sublet-po/<uid>/<vehicle>/<uuid>.pdf path) against the vehicle and GP PO number. Works before the w/Sublet upload brings
 -- the PO (the read joins later). Controllers / administrators on pilot vehicles only. A second document for the same
 -- vehicle + PO must be a Replace of the current one (p_replaces_doc_id); the old one is kept as history. Idempotent per
 -- (user, p_idempotency_key). Writes only pdc_sublet_po_documents_445: never a vehicle, line, tick, PO ref, category, bay or booking.
 IF v_role IS NULL OR v_uid IS NULL OR v_email='' THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_vehicle_id IS NULL OR p_idempotency_key IS NULL OR p_storage_path IS NULL OR p_byte_length IS NULL THEN RETURN jsonb_build_object('ok',false,'code','invalid_input'); END IF;
 IF v_po !~ '^GP[0-9]{8}$' THEN RETURN jsonb_build_object('ok',false,'code','po_number_invalid'); END IF;
 IF v_sha !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('ok',false,'code','sha256_invalid'); END IF;
 IF p_byte_length<1 OR p_byte_length>10485760 THEN RETURN jsonb_build_object('ok',false,'code','file_too_large_or_empty'); END IF;
 v_name:=btrim(regexp_replace(regexp_replace(coalesce(p_original_filename,''),'^.*[\\/]',''),'[[:cntrl:]]','','g'));
 IF v_name='' THEN v_name:=v_po||'.pdf'; END IF;
 IF v_name !~* '\.pdf$' THEN RETURN jsonb_build_object('ok',false,'code','not_a_pdf'); END IF;
 IF length(v_name)>180 THEN v_name:=left(v_name,176)||'.pdf'; END IF;
 IF length(v_name)<5 THEN v_name:=v_po||'.pdf'; END IF;
 v_keys:=ARRAY(SELECT DISTINCT btrim(k) FROM unnest(coalesce(p_covered_line_keys,'{}'::text[])) k WHERE btrim(coalesce(k,''))<>'' ORDER BY 1);
 v_req:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc-sublet-po-document-445','vehicle_id',p_vehicle_id,'po',v_po,'path',p_storage_path,
  'bytes',p_byte_length,'sha256',v_sha,'name',v_name,'lines',to_jsonb(v_keys),'replaces',p_replaces_doc_id)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-445-doc-actor:'||v_uid::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_prior FROM public.pdc_sublet_po_documents_445 WHERE uploaded_by=v_uid AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_prior.request_sha256<>v_req THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
  RETURN v_prior.response||jsonb_build_object('replay',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.pdc_sublet_po_attach_pilot_445 WHERE vehicle_id=p_vehicle_id) THEN RETURN jsonb_build_object('ok',false,'code','sublet_po_attach_not_in_pilot'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active') THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_active'); END IF;
 IF p_storage_path !~ ('^sublet-po/'||v_uid::text||'/'||p_vehicle_id::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$') THEN
  RETURN jsonb_build_object('ok',false,'code','storage_path_invalid'); END IF;
 SELECT o.owner_id, o.metadata INTO v_obj FROM storage.objects o WHERE o.bucket_id='pdc-sublet-po-staging' AND o.name=p_storage_path;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','upload_not_found'); END IF;
 IF v_obj.owner_id IS DISTINCT FROM v_uid::text THEN RETURN jsonb_build_object('ok',false,'code','upload_not_yours'); END IF;
 IF lower(coalesce(v_obj.metadata->>'mimetype','')) <> 'application/pdf' THEN RETURN jsonb_build_object('ok',false,'code','not_a_pdf'); END IF;
 IF (v_obj.metadata->>'size') IS NULL OR (v_obj.metadata->>'size')::bigint<>p_byte_length THEN RETURN jsonb_build_object('ok',false,'code','upload_size_mismatch'); END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_sublet_po_documents_445 WHERE storage_path=p_storage_path) THEN RETURN jsonb_build_object('ok',false,'code','upload_already_recorded'); END IF;
 v_valid:=ARRAY(SELECT e->>'line_key' FROM jsonb_array_elements(public.pdc_sublet_po_vehicle_lines_445(p_vehicle_id)) e);
 IF EXISTS(SELECT 1 FROM unnest(v_keys) k WHERE k<>ALL(v_valid)) THEN RETURN jsonb_build_object('ok',false,'code','covered_line_not_on_vehicle'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-445-doc:'||p_vehicle_id::text||':'||v_po,0));
 SELECT * INTO v_cur FROM public.pdc_sublet_po_documents_445 WHERE vehicle_id=p_vehicle_id AND po_number=v_po AND superseded_at IS NULL FOR UPDATE;
 IF FOUND AND p_replaces_doc_id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','po_already_attached','data',jsonb_build_object('doc_id',v_cur.doc_id)); END IF;
 IF (FOUND AND p_replaces_doc_id<>v_cur.doc_id) OR (NOT FOUND AND p_replaces_doc_id IS NOT NULL) THEN
  RETURN jsonb_build_object('ok',false,'code','replace_conflict','data',jsonb_build_object('current_doc_id',v_cur.doc_id)); END IF;
 v_res:=jsonb_build_object('ok',true,'code',CASE WHEN p_replaces_doc_id IS NULL THEN 'sublet_po_attached' ELSE 'sublet_po_replaced' END,'version','r445',
  'data',jsonb_build_object('doc_id',v_doc,'vehicle_id',p_vehicle_id,'po_number',v_po,'storage_path',p_storage_path,'byte_length',p_byte_length,'sha256',v_sha,
   'original_filename',v_name,'covered_line_keys',to_jsonb(v_keys),'replaces_doc_id',p_replaces_doc_id,'uploaded_by_email',v_email,'uploaded_role',v_role,
   'pending',NOT EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 r WHERE r.vehicle_id=p_vehicle_id AND r.active AND r.po_number=v_po)));
 -- Supersede first (one current document per vehicle + PO); the link to the new row is checked at commit.
 IF p_replaces_doc_id IS NOT NULL THEN
  UPDATE public.pdc_sublet_po_documents_445 SET superseded_at=clock_timestamp(), superseded_by_doc_id=v_doc WHERE doc_id=p_replaces_doc_id AND superseded_at IS NULL;
 END IF;
 INSERT INTO public.pdc_sublet_po_documents_445(doc_id,vehicle_id,po_number,covered_line_keys,bucket_id,storage_path,content_type,byte_length,sha256,
  original_filename,uploaded_by,uploaded_by_email,uploaded_role,replaces_doc_id,idempotency_key,request_sha256,response)
 VALUES (v_doc,p_vehicle_id,v_po,v_keys,'pdc-sublet-po-staging',p_storage_path,'application/pdf',p_byte_length,v_sha,
  v_name,v_uid,v_email,v_role,p_replaces_doc_id,p_idempotency_key,v_req,v_res);
 RETURN v_res;
END
$f$;
REVOKE ALL ON FUNCTION public.record_pdc_sublet_po_document_445(uuid,text,text,integer,text,text,text[],uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_pdc_sublet_po_document_445(uuid,text,text,integer,text,text,text[],uuid,uuid) TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at)
SELECT s.sig, md5(p.prosrc), 'r445', s.note, now()
FROM (VALUES
 ('public.pdc_sublet_po_documents_append_only_445()','r445 (F58): sublet PO documents append-only (no delete; supersede once)'),
 ('public.pdc_sublet_po_attach_role_445()','r445 (F58): approved active controller / administrator (human session) or NULL'),
 ('public.pdc_sublet_po_upload_allowed_445(text,text)','r445 (F58): storage INSERT policy: own sublet-po/<uid>/<pilot vehicle>/<uuid>.pdf'),
 ('public.pdc_sublet_po_read_allowed_445(text,text)','r445 (F58): storage SELECT policy: recorded documents, controllers / administrators'),
 ('public.pdc_sublet_po_vehicle_lines_445(uuid)','r445 (F58): vehicle operation lines (r439 line keys) for the covers-lines picker'),
 ('public.get_pdc_sublet_po_attach_pilot_445()','r445 (F58): pilot vehicle ids for controllers / administrators'),
 ('public.get_pdc_sublet_po_documents_445(uuid)','r445 (F58): vehicle sublet PO documents, history, pending / linked (join on vehicle + PO)'),
 ('public.record_pdc_sublet_po_document_445(uuid,text,text,integer,text,text,text[],uuid,uuid)','r445 (F58): record an uploaded sublet PO PDF (attach / replace; pilot only)')
) s(sig,note) JOIN pg_catalog.pg_proc p ON p.oid=s.sig::regprocedure;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('sublet_po_attach_445','F58','Sublet PO attach (r445): private PDF-only 10 MB bucket with exactly one INSERT and one SELECT storage policy (no UPDATE / DELETE, no anon); document and pilot tables RLS with no app-role access; documents append-only (trigger), GP######## POs, one current per vehicle + PO, superseded rows linked to their replacement, every document on a pilot vehicle with its storage object (same size, PDF) under the uploader''s own path; pilot holds at most one vehicle; the r445 functions write only the documents table (never vehicles, lines, ticks, PO refs, bays or bookings); no email or outbox',
  $chk$WITH b AS (
 SELECT (SELECT count(*) FROM storage.buckets WHERE id='pdc-sublet-po-staging' AND NOT public AND file_size_limit=10485760 AND allowed_mime_types=ARRAY['application/pdf'])=1 AS bucket,
  (SELECT array_agg(cmd::text||':'||policyname ORDER BY policyname) FROM pg_catalog.pg_policies WHERE schemaname='storage' AND tablename='objects'
    AND (policyname LIKE '%445%' OR coalesce(qual,'') LIKE '%pdc-sublet-po-staging%' OR coalesce(with_check,'') LIKE '%pdc-sublet-po-staging%'))
   =ARRAY['SELECT:pdc_sublet_po_read_445','INSERT:pdc_sublet_po_upload_445']
   AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'pdc_sublet_po_%_445' AND roles<>'{authenticated}'::name[]) AS policies,
  (SELECT bool_and(c.relrowsecurity AND NOT has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE'))
    FROM pg_catalog.pg_class c WHERE c.oid IN (to_regclass('public.pdc_sublet_po_documents_445'),to_regclass('public.pdc_sublet_po_attach_pilot_445')))
   AND (SELECT count(*) FROM pg_catalog.pg_class WHERE oid IN (to_regclass('public.pdc_sublet_po_documents_445'),to_regclass('public.pdc_sublet_po_attach_pilot_445')))=2 AS tables,
  EXISTS(SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid=to_regclass('public.pdc_sublet_po_documents_445') AND tgname='pdc_sublet_po_documents_append_only_445' AND tgenabled='O') AS append_only,
  (SELECT count(*) FROM public.pdc_sublet_po_attach_pilot_445)<=1 AS pilot_one,
  NOT EXISTS(SELECT 1 FROM public.pdc_sublet_po_documents_445 d WHERE d.po_number !~ '^GP[0-9]{8}$'
    OR NOT EXISTS(SELECT 1 FROM public.pdc_sublet_po_attach_pilot_445 p WHERE p.vehicle_id=d.vehicle_id)
    OR d.storage_path NOT LIKE 'sublet-po/'||d.uploaded_by::text||'/'||d.vehicle_id::text||'/%'
    OR NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id=d.bucket_id AND o.name=d.storage_path AND o.owner_id=d.uploaded_by::text
      AND (o.metadata->>'size')::bigint=d.byte_length AND lower(o.metadata->>'mimetype')='application/pdf')
    OR (d.superseded_at IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pdc_sublet_po_documents_445 n WHERE n.doc_id=d.superseded_by_doc_id AND n.replaces_doc_id=d.doc_id AND n.po_number=d.po_number AND n.vehicle_id=d.vehicle_id))) AS documents,
  NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.proname LIKE '%sublet_po%445' AND p.prosrc ~* '(INSERT INTO|UPDATE|DELETE FROM)\s+public\.(vehicles|vehicle_work_items|workshop_bookings|pdc_pilbara_service_operations|pdc_sublet_line_ticks_439|pdc_service_line_po_refs_439)\b')
   AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.proname LIKE '%sublet_po%445' AND p.prosrc ~* '(outbox|net\.http|smtp|send_email)') AS writes_only_docs,
  auth.uid() IS NOT NULL OR (SELECT public.get_pdc_sublet_po_documents_445(NULL)->>'code')='not_authorized' AND (SELECT public.get_pdc_sublet_po_attach_pilot_445()->'vehicle_ids')='[]'::jsonb
   AND (SELECT public.record_pdc_sublet_po_document_445(NULL,'GP00000000','x',1,repeat('0',64),'x.pdf',NULL,NULL,NULL)->>'code')='not_authorized'
   AND NOT public.pdc_sublet_po_upload_allowed_445('pdc-sublet-po-staging','sublet-po/x') AND NOT public.pdc_sublet_po_read_allowed_445('pdc-sublet-po-staging','x') AS no_session_refused
)
SELECT b.bucket AND b.policies AND b.tables AND b.append_only AND b.pilot_one AND b.documents AND b.writes_only_docs AND b.no_session_refused AS ok,
 format('%s current / %s superseded sublet PO documents on %s pilot vehicle(s) (%s pending a board PO); bucket %s, policies %s, tables %s, append-only %s, pilot<=1 %s, documents %s, writes only documents %s, no-session refused %s',
  (SELECT count(*) FROM public.pdc_sublet_po_documents_445 WHERE superseded_at IS NULL),(SELECT count(*) FROM public.pdc_sublet_po_documents_445 WHERE superseded_at IS NOT NULL),
  (SELECT count(*) FROM public.pdc_sublet_po_attach_pilot_445),
  (SELECT count(*) FROM public.pdc_sublet_po_documents_445 d WHERE d.superseded_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 r WHERE r.vehicle_id=d.vehicle_id AND r.active AND r.po_number=d.po_number)),
  b.bucket,b.policies,b.tables,b.append_only,b.pilot_one,b.documents,b.writes_only_docs,b.no_session_refused) AS detail
FROM b
$chk$,true,244,'r445');
DO $g$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r445')<>8 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>165 THEN RAISE EXCEPTION 'r445: pins not written'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)<>'6083fb5bcf03d341d9101831c2217cb8'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.sublet_po_vehicle_439(uuid)'::regprocedure)<>'756b7a4164a6e9ce37bb33c7c861b346' THEN RAISE EXCEPTION 'r445: sublet functions changed'; END IF;
 IF has_function_privilege('anon','public.record_pdc_sublet_po_document_445(uuid,text,text,integer,text,text,text[],uuid,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.get_pdc_sublet_po_documents_445(uuid)','EXECUTE')
    OR has_function_privilege('authenticated','public.pdc_sublet_po_vehicle_lines_445(uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.record_pdc_sublet_po_document_445(uuid,text,text,integer,text,text,text[],uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'r445: unexpected function grants'; END IF;
END $g$;
