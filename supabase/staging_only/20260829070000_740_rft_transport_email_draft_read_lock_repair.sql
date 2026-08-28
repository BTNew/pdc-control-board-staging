-- STAGING ONLY 740: repair stable draft-read locks after 739.
-- Stable authenticated read functions cannot use SELECT FOR SHARE in PostgreSQL;
-- the row remains protected by the SECURITY DEFINER boundary and forced RLS.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-740-rft-transport-email-draft-read-lock-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260829060000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260829060000' AND name='739_rft_transport_email_draft_successor')<>1
     OR to_regprocedure('public.read_rft_transport_booking_context_739(uuid)') IS NULL
     OR to_regprocedure('public.read_rft_transport_draft_739(uuid)') IS NULL
  THEN RAISE EXCEPTION 'PDC_740_STAGING_ONLY' USING errcode='55000'; END IF;
END $guard$;

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
      AND r.account_status='approved' AND r.role IN('operator','administrator','viewer','importer'))
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

CREATE OR REPLACE FUNCTION public.read_rft_transport_draft_739(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public AS $read$
DECLARE uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); d public.pdc_rft_transport_email_drafts_739%rowtype;
BEGIN
  IF uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator','viewer','importer'))
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

DO $post$
BEGIN
  IF position('FOR SHARE' in pg_get_functiondef('public.read_rft_transport_booking_context_739(uuid)'::regprocedure))>0
     OR position('FOR SHARE' in pg_get_functiondef('public.read_rft_transport_draft_739(uuid)'::regprocedure))>0
     OR has_function_privilege('anon','public.read_rft_transport_booking_context_739(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.read_rft_transport_booking_context_739(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.read_rft_transport_draft_739(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.read_rft_transport_draft_739(uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'PDC_740_SECURITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260829070000','740_rft_transport_email_draft_read_lock_repair',ARRAY[
  'Append-only correction over 739; stable authenticated draft context/read RPCs no longer use PostgreSQL FOR SHARE',
  'Forced-RLS and SECURITY DEFINER role checks remain unchanged; no booking or vehicle data is rewritten',
  'Production sentinel and outbound delivery containment remain required'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
