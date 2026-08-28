-- STAGING ONLY 739: atomic intercepted salesperson .eml draft successor.
--
-- 734 remains the durable booking primitive. 739 adds the missing artifact
-- contract: the authenticated client binds the exact immutable QC photo bytes
-- to a deterministic MIME draft in the same transaction as the booking.
-- Delivery remains permanently intercepted; no mailbox or SMTP path exists.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-739-rft-transport-email-draft-successor',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260829050000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260829050000' AND name='738_authenticated_parts_received_auditor_wrapper')<>1
     OR to_regprocedure('public.book_rft_transport_734(uuid,integer,uuid)') IS NULL
     OR to_regprocedure('public.pdc_rft_transport_snapshot_734(uuid)') IS NULL
     OR to_regprocedure('public.pdc_qc_operation_lines_379(uuid)') IS NULL
     OR to_regprocedure('public.pdc_vehicle_effective_salesperson_json_386(uuid)') IS NULL
     OR to_regclass('public.pdc_qc_finalization_photo_evidence_399') IS NULL
     OR to_regclass('public.pdc_rft_transport_email_evidence_734') IS NULL
     OR to_regclass('public.pdc_rft_transport_email_drafts_739') IS NOT NULL
     OR to_regprocedure('public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_739_STAGING_ONLY' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_rft_transport_email_drafts_739(
  draft_id uuid PRIMARY KEY,
  transport_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_rft_transport_lifecycle_receipts_734(receipt_id) ON DELETE RESTRICT,
  notification_id uuid NOT NULL UNIQUE REFERENCES public.pdc_rft_transport_email_outbox_734(notification_id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL UNIQUE REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL CHECK(length(btrim(actor_email))>3),
  recipient_email text NOT NULL CHECK(recipient_email=lower(recipient_email) AND recipient_email~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  status text NOT NULL DEFAULT 'intercepted' CHECK(status='intercepted'),
  draft_filename text NOT NULL CHECK(draft_filename~'^[A-Za-z0-9._-]{1,180}\.eml$'),
  mime_content_type text NOT NULL CHECK(mime_content_type='message/rfc822'),
  mime_bytes bytea NOT NULL CHECK(octet_length(mime_bytes)>0),
  mime_byte_length integer NOT NULL CHECK(mime_byte_length>0),
  mime_sha256 text NOT NULL CHECK(mime_sha256~'^[a-f0-9]{64}$'),
  photo_receipt_id uuid NOT NULL REFERENCES public.pdc_qc_finalization_photo_evidence_399(photo_receipt_id) ON DELETE RESTRICT,
  photo_bucket_id text NOT NULL CHECK(photo_bucket_id='pdc-qc-evidence-staging'),
  photo_storage_path text NOT NULL,
  photo_content_type text NOT NULL CHECK(photo_content_type LIKE 'image/%'),
  photo_byte_length integer NOT NULL CHECK(photo_byte_length>0),
  photo_sha256 text NOT NULL CHECK(photo_sha256~'^[a-f0-9]{64}$'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(status='intercepted'),
  CHECK(mime_byte_length=octet_length(mime_bytes))
);
CREATE INDEX pdc_rft_transport_email_drafts_739_vehicle_idx
  ON public.pdc_rft_transport_email_drafts_739(vehicle_id,created_at DESC);

CREATE OR REPLACE FUNCTION public.pdc_739_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_739_APPEND_ONLY' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_739_append_only() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_rft_transport_email_drafts_739_append_only
  BEFORE UPDATE OR DELETE ON public.pdc_rft_transport_email_drafts_739
  FOR EACH ROW EXECUTE FUNCTION public.pdc_739_append_only();

ALTER TABLE public.pdc_rft_transport_email_drafts_739 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_email_drafts_739 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_rft_transport_email_drafts_739 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.read_rft_transport_booking_context_739(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public AS $context$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v public.vehicles%rowtype; photo public.pdc_qc_finalization_photo_evidence_399%rowtype;
  salesperson jsonb; lines jsonb; snap jsonb; storage_count integer;
BEGIN
  IF uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r
    WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active
      AND r.account_status='approved' AND r.role IN('operator','administrator','viewer','importer') FOR SHARE)
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  salesperson:=public.pdc_vehicle_effective_salesperson_json_386(v.id);
  IF lower(btrim(coalesce(salesperson->>'salesperson_email','')))='' OR lower(btrim(salesperson->>'salesperson_email'))!~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    THEN RETURN jsonb_build_object('ok',false,'code','salesperson_email_required','data',jsonb_build_object('vehicle_id',v.id)); END IF;
  SELECT * INTO photo FROM public.pdc_qc_finalization_photo_evidence_399
    WHERE vehicle_id=v.id ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND OR photo.bucket_id<>'pdc-qc-evidence-staging' OR photo.content_type NOT LIKE 'image/%' OR photo.byte_length<1
    THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_receipt_required','data',jsonb_build_object('vehicle_id',v.id)); END IF;
  SELECT count(*) INTO storage_count FROM storage.objects o
    WHERE o.bucket_id=photo.bucket_id AND o.name=photo.storage_path;
  IF storage_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_storage_missing','data',jsonb_build_object('vehicle_id',v.id,'photo_receipt_id',photo.photo_receipt_id)); END IF;
  lines:=coalesce(public.pdc_qc_operation_lines_379(v.id),'[]'::jsonb);
  IF jsonb_array_length(lines)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(lines) line
    WHERE coalesce((line->>'active')::boolean,false)
      AND (NOT coalesce((line->>'completed')::boolean,false)
        OR nullif(btrim(coalesce(line->>'estimated_hours','')),'') IS NULL))
    THEN RETURN jsonb_build_object('ok',false,'code','qc_items_required','data',jsonb_build_object('vehicle_id',v.id,'active_item_count',jsonb_array_length(lines))); END IF;
  snap:=public.pdc_rft_transport_snapshot_734(v.id);
  RETURN jsonb_build_object('ok',true,'code','rft_transport_booking_context','data',jsonb_build_object(
    'vehicle_id',v.id,'vehicle_version',v.version,'rft_confirmed',v.rft_confirmed_at IS NOT NULL,
    'salesperson',salesperson,'completed_items',lines,
    'photo',jsonb_build_object('photo_receipt_id',photo.photo_receipt_id,'bucket_id',photo.bucket_id,
      'storage_path',photo.storage_path,'content_type',photo.content_type,'byte_length',photo.byte_length,
      'sha256',photo.sha256,'original_filename',photo.original_filename),
    'snapshot',snap));
END $context$;
REVOKE ALL ON FUNCTION public.read_rft_transport_booking_context_739(uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_rft_transport_booking_context_739(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.book_rft_transport_email_draft_739(
  p_vehicle_id uuid,
  p_expected_vehicle_version integer,
  p_idempotency_key uuid,
  p_photo_receipt_id uuid,
  p_photo_bucket_id text,
  p_photo_storage_path text,
  p_photo_content_type text,
  p_photo_byte_length integer,
  p_photo_sha256 text,
  p_photo_bytes_base64 text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='150s' AS $book$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v public.vehicles%rowtype; photo public.pdc_qc_finalization_photo_evidence_399%rowtype;
  salesperson jsonb; lines jsonb; snap jsonb; booking_result jsonb; existing public.pdc_rft_transport_email_drafts_739%rowtype;
  request_payload jsonb; request_sha text; receipt uuid; notification uuid; draft uuid;
  photo_bytes bytea; encoded_photo text; wrapped_photo text:=''; mime_text text; mime_bytes_out bytea;
  mime_sha text; body text; crlf text:=chr(13)||chr(10); filename text; booked_at text;
  i integer; storage_count integer; result jsonb; outbox_status text;
BEGIN
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
     OR p_idempotency_key IS NULL OR p_photo_receipt_id IS NULL
     OR p_photo_bucket_id IS NULL OR p_photo_storage_path IS NULL
     OR p_photo_content_type IS NULL OR p_photo_byte_length IS NULL OR p_photo_sha256 IS NULL
     OR p_photo_bytes_base64 IS NULL OR length(p_photo_bytes_base64)>1600000
    THEN RETURN jsonb_build_object('ok',false,'code','rft_transport_draft_invalid_input'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r
    WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active
      AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE)
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  request_payload:=jsonb_build_object('contract','pdc-rft-transport-email-draft-739','vehicle_id',p_vehicle_id,
    'expected_vehicle_version',p_expected_vehicle_version,'idempotency_key',p_idempotency_key,
    'photo_receipt_id',p_photo_receipt_id,'photo_bucket_id',p_photo_bucket_id,'photo_storage_path',p_photo_storage_path,
    'photo_content_type',lower(btrim(p_photo_content_type)),'photo_byte_length',p_photo_byte_length,
    'photo_sha256',lower(btrim(p_photo_sha256)));
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-739-draft-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO existing FROM public.pdc_rft_transport_email_drafts_739 WHERE actor_id=uid AND transport_receipt_id IN
    (SELECT receipt_id FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE actor_id=uid AND idempotency_key=p_idempotency_key);
  IF FOUND THEN
    IF existing.response->>'request_sha256' IS DISTINCT FROM request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(existing.response,'{replay}','true'::jsonb,false);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-739-draft-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO existing FROM public.pdc_rft_transport_email_drafts_739 WHERE vehicle_id=p_vehicle_id;
  IF FOUND THEN RETURN jsonb_build_object('ok',false,'code','transport_draft_already_exists','data',jsonb_build_object('vehicle_id',p_vehicle_id,'draft_id',existing.draft_id,'mime_sha256',existing.mime_sha256)); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version)); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' OR v.rft_collected_at IS NOT NULL
    THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_rft'); END IF;
  IF v.rft_confirmed_at IS NULL THEN RETURN jsonb_build_object('ok',false,'code','rft_confirmation_required'); END IF;
  salesperson:=public.pdc_vehicle_effective_salesperson_json_386(v.id);
  IF lower(btrim(coalesce(salesperson->>'salesperson_email','')))='' OR lower(btrim(salesperson->>'salesperson_email'))!~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    THEN RETURN jsonb_build_object('ok',false,'code','salesperson_email_required'); END IF;
  SELECT * INTO photo FROM public.pdc_qc_finalization_photo_evidence_399
    WHERE vehicle_id=v.id ORDER BY created_at DESC LIMIT 1 FOR SHARE;
  IF NOT FOUND OR photo.photo_receipt_id<>p_photo_receipt_id OR photo.bucket_id<>p_photo_bucket_id
     OR photo.storage_path<>p_photo_storage_path OR photo.content_type<>lower(btrim(p_photo_content_type))
     OR photo.byte_length<>p_photo_byte_length OR photo.sha256<>lower(btrim(p_photo_sha256))
    THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_evidence_changed'); END IF;
  SELECT count(*) INTO storage_count FROM storage.objects o WHERE o.bucket_id=photo.bucket_id AND o.name=photo.storage_path;
  IF storage_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_storage_missing'); END IF;
  BEGIN photo_bytes:=decode(p_photo_bytes_base64,'base64'); EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_bytes_invalid'); END;
  IF octet_length(photo_bytes)<>photo.byte_length OR encode(extensions.digest(photo_bytes,'sha256'),'hex')<>photo.sha256
    THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_bytes_mismatch'); END IF;
  lines:=coalesce(public.pdc_qc_operation_lines_379(v.id),'[]'::jsonb);
  IF jsonb_array_length(lines)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(lines) line
    WHERE coalesce((line->>'active')::boolean,false)
      AND (NOT coalesce((line->>'completed')::boolean,false)
        OR nullif(btrim(coalesce(line->>'estimated_hours','')),'') IS NULL))
    THEN RETURN jsonb_build_object('ok',false,'code','qc_items_required'); END IF;

  booking_result:=public.book_rft_transport_734(v.id,p_expected_vehicle_version,p_idempotency_key);
  IF NOT coalesce((booking_result->>'ok')::boolean,false) THEN RETURN booking_result; END IF;
  receipt:=(booking_result#>>'{data,receipt_id}')::uuid;
  notification:=(booking_result#>>'{data,notification_id}')::uuid;
  IF receipt IS NULL OR notification IS NULL THEN RETURN jsonb_build_object('ok',false,'code','transport_booking_receipt_invalid'); END IF;
  SELECT coalesce(payload->>'delivery_status','intercepted') INTO outbox_status FROM public.pdc_rft_transport_email_outbox_734 WHERE notification_id=notification;
  IF outbox_status IS DISTINCT FROM 'intercepted' THEN RETURN jsonb_build_object('ok',false,'code','staging_delivery_not_intercepted'); END IF;

  snap:=public.pdc_rft_transport_snapshot_734(v.id);
  booked_at:=coalesce(v.rft_transport_booked_at::text,'');
  filename:=coalesce(nullif(regexp_replace(btrim(photo.original_filename),'[^A-Za-z0-9._-]','-','g'),'') ,'completion-photo.jpg');
  IF right(lower(filename),4)<>'.jpg' AND right(lower(filename),5)<>'.jpeg' THEN filename:=filename||'.jpg'; END IF;
  body:='RFT transport status: BOOKED'||crlf||crlf
    ||'Stock: '||coalesce(v.stock_number,'(none)')||crlf
    ||'Job Card: '||coalesce(v.job_card_number,'(none)')||crlf
    ||'Customer: '||coalesce(v.customer_name,'(none)')||crlf
    ||'Vehicle: '||coalesce(v.vehicle_description,concat_ws(' ',v.make,v.model))||crlf
    ||'Completed work: '||lines::text||crlf
    ||'Dates: '||jsonb_build_object('date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,'transport_booked_at',v.rft_transport_booked_at)::text||crlf
    ||'Build times: '||coalesce(snap->'build_times','[]'::jsonb)::text||crlf
    ||'Stoppages: '||coalesce(snap->'stoppages','[]'::jsonb)::text;
  encoded_photo:=encode(photo_bytes,'base64');
  IF length(encoded_photo)>0 THEN
    FOR i IN 1..length(encoded_photo) BY 76 LOOP wrapped_photo:=wrapped_photo||substr(encoded_photo,i,76)||crlf; END LOOP;
  END IF;
  mime_text:='MIME-Version: 1.0'||crlf
    ||'Content-Type: multipart/mixed; boundary="pdc-rft-739-'||replace(notification::text,'-','')||'"'||crlf
    ||'To: '||lower(btrim(salesperson->>'salesperson_email'))||crlf
    ||'Subject: RFT transport booked - Stock '||coalesce(v.stock_number,'No stock')||crlf
    ||'X-PDC-Delivery: INTERCEPTED-STAGING'||crlf
    ||'X-PDC-Draft-Only: true'||crlf||crlf
    ||'--pdc-rft-739-'||replace(notification::text,'-','')||crlf
    ||'Content-Type: text/plain; charset=UTF-8'||crlf
    ||'Content-Transfer-Encoding: 8bit'||crlf||crlf||body||crlf
    ||'--pdc-rft-739-'||replace(notification::text,'-','')||crlf
    ||'Content-Type: '||photo.content_type||crlf
    ||'Content-Transfer-Encoding: base64'||crlf
    ||'Content-Disposition: attachment; filename="'||filename||'"'||crlf
    ||'X-PDC-Photo-Receipt-ID: '||photo.photo_receipt_id::text||crlf
    ||'X-PDC-Photo-SHA256: '||photo.sha256||crlf
    ||'X-PDC-Photo-Byte-Length: '||photo.byte_length::text||crlf||crlf
    ||wrapped_photo
    ||'--pdc-rft-739-'||replace(notification::text,'-','')||'--'||crlf;
  mime_bytes_out:=convert_to(mime_text,'UTF8');
  mime_sha:=encode(extensions.digest(mime_bytes_out,'sha256'),'hex');
  draft:=extensions.uuid_generate_v5('73900000-0000-5000-8000-000000000739'::uuid,receipt::text||':eml');
  result:=jsonb_build_object('ok',true,'code','rft_transport_booked','replay',false,'data',coalesce(booking_result->'data','{}'::jsonb)||jsonb_build_object(
    'draft_id',draft,'draft_filename',filename,'draft_content_type','message/rfc822','draft_mime_sha256',mime_sha,
    'draft_mime_byte_length',octet_length(mime_bytes_out),'draft_photo_receipt_id',photo.photo_receipt_id,
    'draft_photo_content_type',photo.content_type,'draft_photo_byte_length',photo.byte_length,'draft_photo_sha256',photo.sha256,
    'draft_status','intercepted','delivery_enabled',false,'sent_at',null,'delivered_at',null));
  INSERT INTO public.pdc_rft_transport_email_drafts_739(
    draft_id,transport_receipt_id,notification_id,vehicle_id,actor_id,actor_email,recipient_email,status,
    draft_filename,mime_content_type,mime_bytes,mime_byte_length,mime_sha256,photo_receipt_id,photo_bucket_id,
    photo_storage_path,photo_content_type,photo_byte_length,photo_sha256,response)
  VALUES(draft,receipt,notification,v.id,uid,actor_email,lower(btrim(salesperson->>'salesperson_email')),'intercepted',
    filename,'message/rfc822',mime_bytes_out,octet_length(mime_bytes_out),mime_sha,photo.photo_receipt_id,photo.bucket_id,
    photo.storage_path,photo.content_type,photo.byte_length,photo.sha256,result||jsonb_build_object('request_sha256',request_sha));
  IF NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_drafts_739 d WHERE d.draft_id=draft AND d.status='intercepted'
      AND d.mime_byte_length=octet_length(d.mime_bytes) AND d.mime_sha256=encode(extensions.digest(d.mime_bytes,'sha256'),'hex')
      AND d.photo_receipt_id=photo.photo_receipt_id AND d.photo_byte_length=photo.byte_length AND d.photo_sha256=photo.sha256
      AND d.mime_content_type='message/rfc822') THEN
    RAISE EXCEPTION 'PDC_739_DRAFT_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO existing FROM public.pdc_rft_transport_email_drafts_739 WHERE vehicle_id=p_vehicle_id;
  IF FOUND THEN RETURN jsonb_set(existing.response,'{replay}','true'::jsonb,false); END IF;
  RETURN jsonb_build_object('ok',false,'code','rft_transport_draft_conflict');
END $book$;
REVOKE ALL ON FUNCTION public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.read_rft_transport_draft_739(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public AS $read$
DECLARE uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); d public.pdc_rft_transport_email_drafts_739%rowtype;
BEGIN
  IF uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator','viewer','importer') FOR SHARE)
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  SELECT * INTO d FROM public.pdc_rft_transport_email_drafts_739 WHERE vehicle_id=p_vehicle_id ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','transport_draft_not_found'); END IF;
  RETURN jsonb_build_object('ok',true,'code','rft_transport_draft','data',jsonb_build_object(
    'draft_id',d.draft_id,'vehicle_id',d.vehicle_id,'notification_id',d.notification_id,'transport_receipt_id',d.transport_receipt_id,
    'recipient_email',d.recipient_email,'status',d.status,'draft_filename',d.draft_filename,'mime_content_type',d.mime_content_type,
    'mime_byte_length',d.mime_byte_length,'mime_sha256',d.mime_sha256,'mime_base64',encode(d.mime_bytes,'base64'),
    'photo_receipt_id',d.photo_receipt_id,'photo_bucket_id',d.photo_bucket_id,'photo_storage_path',d.photo_storage_path,
    'photo_content_type',d.photo_content_type,'photo_byte_length',d.photo_byte_length,'photo_sha256',d.photo_sha256,
    'sent_at',null,'delivered_at',null,'delivery_enabled',false,'intercepted',true));
END $read$;
REVOKE ALL ON FUNCTION public.read_rft_transport_draft_739(uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_rft_transport_draft_739(uuid) TO authenticated;

-- Add the artifact metadata to the existing authoritative snapshot without
-- changing the row identity/version contract or the three direct controls.
ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_739;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE r jsonb; rows jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_739();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('rft_transport_draft',coalesce((SELECT jsonb_build_object(
    'draft_id',d.draft_id,'draft_filename',d.draft_filename,'mime_content_type',d.mime_content_type,
    'mime_byte_length',d.mime_byte_length,'mime_sha256',d.mime_sha256,'photo_receipt_id',d.photo_receipt_id,
    'photo_content_type',d.photo_content_type,'photo_byte_length',d.photo_byte_length,'photo_sha256',d.photo_sha256,
    'status',d.status,'delivery_enabled',false,'intercepted',true,'sent_at',null,'delivered_at',null)
    FROM public.pdc_rft_transport_email_drafts_739 d WHERE d.vehicle_id=(x->>'id')::uuid ORDER BY d.created_at DESC LIMIT 1),'{}'::jsonb)) ORDER BY x->>'stock_number'),'[]'::jsonb)
    INTO rows FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_739() FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

DO $post$
BEGIN
  IF has_function_privilege('anon','public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)','EXECUTE')
     OR has_function_privilege('service_role','public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.read_rft_transport_draft_739(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.read_rft_transport_draft_739(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.read_rft_transport_draft_739(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.read_rft_transport_booking_context_739(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.read_rft_transport_booking_context_739(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.read_rft_transport_booking_context_739(uuid)','EXECUTE')
     OR has_table_privilege('authenticated','public.pdc_rft_transport_email_drafts_739','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon','public.pdc_rft_transport_email_drafts_739','SELECT,INSERT,UPDATE,DELETE')
     OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_drafts_739 WHERE status<>'intercepted' OR mime_content_type<>'message/rfc822' OR mime_byte_length<>octet_length(mime_bytes) OR mime_sha256<>encode(extensions.digest(mime_bytes,'sha256'),'hex') OR photo_content_type NOT LIKE 'image/%' OR photo_byte_length<1 OR photo_sha256!~'^[a-f0-9]{64}$')
     OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_outbox_734 WHERE delivery_enabled OR sent_at IS NOT NULL OR delivered_at IS NOT NULL)
  THEN RAISE EXCEPTION 'PDC_739_SECURITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260829060000','739_rft_transport_email_draft_successor',ARRAY[
  'Staging-only append-only intercepted message/rfc822 .eml draft with deterministic MIME bytes and staff read/download RPC',
  'Authenticated booking successor binds the exact immutable QC photo reference, content type, byte length, SHA-256 and bytes before invoking durable 734 booking in the same transaction',
  'MIME contains explicit BOOKED status, completed work, dates, build times, stoppages and the exact QC image attachment',
  'One draft per canonical vehicle/transport receipt with actor/idempotency/stale-version/duplicate-click guards and authoritative snapshot metadata',
  'Missing salesperson, QC items, QC receipt, photo reference, storage object or exact bytes return precise fail-closed codes',
  'Forced-RLS append-only draft table, delivery_enabled false, intercepted status, sent/delivered null, Production sentinel forbidden'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
