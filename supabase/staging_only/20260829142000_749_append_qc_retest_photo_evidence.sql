-- STAGING ONLY 749: permit one append-only fresh photo for the new QC
-- retest cycle without altering the immutable prior 399 photo row.
BEGIN;
SET LOCAL lock_timeout='30s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-747-recover-stock-13000769',0));
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260829141000' AND name='748_repair_recovery_identity_guard')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260829141000')
  THEN RAISE EXCEPTION 'PDC_749_STAGING_OR_PREDECESSOR_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_qc_retest_photo_evidence_747(
  photo_receipt_id uuid PRIMARY KEY,
  cycle_id uuid NOT NULL,
  vehicle_id uuid NOT NULL CHECK(vehicle_id='d777b071-a2b0-5367-893b-aa83a07fcfce'),
  expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
  uploader_id uuid NOT NULL,
  uploader_email text NOT NULL,
  bucket_id text NOT NULL CHECK(bucket_id='pdc-qc-evidence-staging'),
  storage_path text NOT NULL,
  content_type text NOT NULL CHECK(content_type LIKE 'image/%'),
  byte_length integer NOT NULL CHECK(byte_length BETWEEN 1 AND 1048576),
  original_byte_length integer NOT NULL CHECK(original_byte_length BETWEEN 1 AND 10485760),
  image_width integer NOT NULL CHECK(image_width BETWEEN 1 AND 1600),
  image_height integer NOT NULL CHECK(image_height BETWEEN 1 AND 1600),
  sha256 text NOT NULL CHECK(sha256~'^[a-f0-9]{64}$'),
  original_filename text NOT NULL,
  idempotency_key uuid NOT NULL UNIQUE,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(cycle_id)
);
ALTER TABLE public.pdc_qc_retest_photo_evidence_747 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_qc_retest_photo_evidence_747 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_qc_retest_photo_evidence_747 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_749_retest_photo_immutable BEFORE UPDATE OR DELETE ON public.pdc_qc_retest_photo_evidence_747 FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_retest_immutable_747();

CREATE OR REPLACE FUNCTION public.record_pdc_qc_retest_photo_747(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_cycle_id uuid,p_bucket_id text,p_storage_path text,p_content_type text,
  p_byte_length integer,p_original_byte_length integer,p_image_width integer,p_image_height integer,p_sha256 text,p_original_filename text,p_idempotency_key uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $$
DECLARE s jsonb; uid uuid; email text; v public.vehicles%rowtype; req jsonb; req_sha text; old public.pdc_qc_retest_events_747%rowtype; prior public.pdc_qc_retest_photo_evidence_747%rowtype; photo_id uuid; response jsonb; n integer;
BEGIN
  s:=public.pdc_admin_vehicle_actor(); IF NOT coalesce((s->>'ok')::boolean,false) THEN RETURN s; END IF; uid:=(s->'data'->>'actor_id')::uuid; email:=s->'data'->>'actor_email';
  IF p_vehicle_id IS DISTINCT FROM 'd777b071-a2b0-5367-893b-aa83a07fcfce'::uuid OR p_cycle_id IS NULL OR p_bucket_id<>'pdc-qc-evidence-staging' OR p_storage_path!~('^qc-finalization/'||uid::text||'/[0-9a-f-]{36}/[^/]{1,180}$') OR lower(btrim(coalesce(p_content_type,''))) NOT LIKE 'image/%' OR p_byte_length NOT BETWEEN 1 AND 1048576 OR p_original_byte_length NOT BETWEEN 1 AND 10485760 OR p_image_width NOT BETWEEN 1 AND 1600 OR p_image_height NOT BETWEEN 1 AND 1600 OR lower(btrim(coalesce(p_sha256,'')))!~'^[a-f0-9]{64}$' OR length(btrim(coalesce(p_original_filename,''))) NOT BETWEEN 1 AND 180 OR p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_photo_invalid_input'); END IF;
  req:=jsonb_build_object('contract','pdc-qc-retest-photo-747','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'cycle_id',p_cycle_id,'bucket_id',p_bucket_id,'storage_path',p_storage_path,'content_type',lower(btrim(p_content_type)),'byte_length',p_byte_length,'original_byte_length',p_original_byte_length,'image_width',p_image_width,'image_height',p_image_height,'sha256',lower(btrim(p_sha256)),'original_filename',btrim(p_original_filename),'idempotency_key',p_idempotency_key,'actor_id',uid); req_sha:=encode(extensions.digest(convert_to(req::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-747-photo:'||p_cycle_id::text,0));
  SELECT * INTO old FROM public.pdc_qc_retest_events_747 WHERE cycle_id=p_cycle_id AND event_kind='fresh_photo_accepted' FOR SHARE;
  IF FOUND THEN IF old.request_sha256<>req_sha THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_photo_replay_mismatch'); END IF; RETURN jsonb_build_object('ok',true,'code','qc_retest_photo_accepted','replay',true,'cycle_id',p_cycle_id,'photo_receipt_id',old.photo_receipt_id,'vehicle_id',p_vehicle_id); END IF;
  SELECT * INTO prior FROM public.pdc_qc_retest_photo_evidence_747 WHERE idempotency_key=p_idempotency_key OR cycle_id=p_cycle_id FOR SHARE;
  IF FOUND THEN IF prior.request_sha256<>req_sha THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_photo_replay_mismatch'); END IF; RETURN jsonb_build_object('ok',true,'code','qc_retest_photo_accepted','replay',true,'cycle_id',p_cycle_id,'photo_receipt_id',prior.photo_receipt_id,'vehicle_id',p_vehicle_id); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR SHARE;
  IF NOT FOUND OR v.lifecycle_state::text<>'active' OR upper(v.current_location)<>'QC' OR v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_vehicle_version_or_location_conflict'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_qc_retest_events_747 WHERE cycle_id=p_cycle_id AND event_kind='recovered_to_qc') THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_cycle_not_found'); END IF;
  SELECT count(*) INTO n FROM storage.objects o WHERE o.bucket_id=p_bucket_id AND o.name=p_storage_path AND o.owner_id=uid::text;
  IF n<>1 THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_photo_storage_object_not_owned'); END IF;
  photo_id:=extensions.uuid_generate_v5('39900000-0000-5000-8000-000000000399'::uuid,'747-retest-photo:'||p_idempotency_key::text);
  response:=jsonb_build_object('ok',true,'code','qc_retest_photo_accepted','cycle_id',p_cycle_id,'photo_receipt_id',photo_id,'vehicle_id',p_vehicle_id,'vehicle_version',v.version,'fresh_cycle',true);
  INSERT INTO public.pdc_qc_retest_photo_evidence_747(photo_receipt_id,cycle_id,vehicle_id,expected_vehicle_version,uploader_id,uploader_email,bucket_id,storage_path,content_type,byte_length,original_byte_length,image_width,image_height,sha256,original_filename,idempotency_key,request_sha256,response)
  VALUES(photo_id,p_cycle_id,p_vehicle_id,p_expected_vehicle_version,uid,email,p_bucket_id,p_storage_path,lower(btrim(p_content_type)),p_byte_length,p_original_byte_length,p_image_width,p_image_height,lower(btrim(p_sha256)),btrim(p_original_filename),p_idempotency_key,req_sha,response);
  INSERT INTO public.pdc_qc_retest_events_747(event_id,cycle_id,vehicle_id,stock_number,event_kind,idempotency_key,request_sha256,photo_receipt_id,before_state,after_state,actor_id,actor_email) VALUES(extensions.uuid_generate_v5('74700000-0000-5000-8000-000000000747'::uuid,'fresh_photo:'||p_idempotency_key::text),p_cycle_id,p_vehicle_id,'13000769','fresh_photo_accepted',p_idempotency_key,req_sha,photo_id,jsonb_build_object('vehicle_version',v.version,'current_location','QC'),response,uid,email);
  RETURN response;
END $$;
REVOKE ALL ON FUNCTION public.record_pdc_qc_retest_photo_747(uuid,integer,uuid,text,text,text,integer,integer,integer,integer,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_pdc_qc_retest_photo_747(uuid,integer,uuid,text,text,text,integer,integer,integer,integer,text,text,uuid) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260829142000','749_append_qc_retest_photo_evidence',ARRAY['Legacy 399 QC photo uniqueness is preserved; fresh retest photo is stored in a separate immutable per-cycle evidence table','Exact staging storage owner, image metadata, SHA-256, UUID, cycle and idempotency guards retained']);
NOTIFY pgrst,'reload schema';
COMMIT;
