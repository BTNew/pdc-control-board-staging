-- STAGING ONLY 747: recover the exact Stock 13000769 identity after the
-- incorrectly scoped 746 purge and open a receipt-backed QC retest cycle.
-- This is append-only: migration 746, its receipt and replay fence are never
-- updated or removed. The restore controller supplies the encrypted rows.
BEGIN;
SET LOCAL statement_timeout='15min';
SET LOCAL lock_timeout='30s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-747-recover-stock-13000769',0));

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260829130000' AND name='746_purge_stock_13000769')
     OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260829130000')
     OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260829140000')
  THEN RAISE EXCEPTION 'PDC_747_STAGING_OR_PREDECESSOR_GUARD_FAILED' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_stock_13000769_recovery_receipts_747(
  recovery_key text PRIMARY KEY CHECK(recovery_key='recover-stock-13000769-to-qc-20260828_161016_aa9508'),
  receipt_id uuid NOT NULL UNIQUE,
  dashboard_session text NOT NULL CHECK(dashboard_session='20260828_161016_aa9508'),
  stock_number text NOT NULL CHECK(stock_number='13000769'),
  vehicle_id uuid NOT NULL CHECK(vehicle_id='d777b071-a2b0-5367-893b-aa83a07fcfce'),
  backend_record_id uuid NOT NULL CHECK(backend_record_id='de800087-d086-4f7b-9569-bb8a88660475'),
  predecessor_migration text NOT NULL CHECK(predecessor_migration='20260829130000/746_purge_stock_13000769'),
  predecessor_purge_receipt text NOT NULL CHECK(predecessor_purge_receipt='complete-operational-purge-stock-13000769'),
  predecessor_replay_fence text NOT NULL CHECK(predecessor_replay_fence='pdc_email_replay_fences_746:uidvalidity-1-uid-639-stock-13000769'),
  backup_run_id uuid NOT NULL CHECK(backup_run_id='847b7b9a-7f25-4a13-868d-fb3a95b9e447'),
  backup_manifest_sha256 text NOT NULL CHECK(backup_manifest_sha256='7326179925f024eb3f295bdc504aa84b15f416c6e37cf71b777f7946958a817d'),
  encrypted_backup_sha256 text NOT NULL CHECK(encrypted_backup_sha256='949a8fa7274364b43ecd1fb5248af9f7628f6350cc8196b41733f6322fb8d0e7'),
  restored_table_count integer NOT NULL CHECK(restored_table_count=28),
  restored_row_count bigint NOT NULL CHECK(restored_row_count=206),
  excluded_pending_outbox_count integer NOT NULL CHECK(excluded_pending_outbox_count=1),
  original_vehicle_version integer NOT NULL CHECK(original_vehicle_version>0),
  recovered_vehicle_version integer NOT NULL CHECK(recovered_vehicle_version=original_vehicle_version+1),
  prior_qc_photo_receipt_id uuid NOT NULL,
  prior_qc_finalization_receipt_id uuid NOT NULL,
  recovery_action text NOT NULL CHECK(recovery_action='restore_exact_closure_then_move_rft_to_qc_retest'),
  actor_id uuid NOT NULL CHECK(actor_id='8a83b715-8d79-4b0e-95b2-02b55da6e8d7'),
  actor_email text NOT NULL CHECK(actor_email='craig.watson@broometoyota.com.au'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.pdc_qc_retest_events_747(
  event_id uuid PRIMARY KEY,
  cycle_id uuid NOT NULL,
  vehicle_id uuid NOT NULL CHECK(vehicle_id='d777b071-a2b0-5367-893b-aa83a07fcfce'),
  stock_number text NOT NULL CHECK(stock_number='13000769'),
  event_kind text NOT NULL CHECK(event_kind IN('recovered_to_qc','fresh_photo_accepted','qc_signed_off_to_rft','rollback')),
  idempotency_key uuid NOT NULL UNIQUE,
  request_sha256 text NOT NULL CHECK(request_sha256 ~ '^[a-f0-9]{64}$'),
  photo_receipt_id uuid,
  before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
  after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
  actor_id uuid NOT NULL,
  actor_email text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(cycle_id,event_kind)
);
CREATE INDEX pdc_qc_retest_events_747_vehicle_idx ON public.pdc_qc_retest_events_747(vehicle_id,created_at,event_id);

CREATE TABLE public.pdc_qc_retest_supersessions_747(
  supersession_id uuid PRIMARY KEY,
  cycle_id uuid NOT NULL,
  vehicle_id uuid NOT NULL CHECK(vehicle_id='d777b071-a2b0-5367-893b-aa83a07fcfce'),
  prior_photo_receipt_id uuid NOT NULL,
  prior_finalization_receipt_id uuid NOT NULL,
  supersession_reason text NOT NULL CHECK(supersession_reason='prior QC finalization/photo evidence superseded for fresh mobile QC retest'),
  actor_id uuid NOT NULL,
  actor_email text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(cycle_id), UNIQUE(prior_photo_receipt_id), UNIQUE(prior_finalization_receipt_id)
);

ALTER TABLE public.pdc_stock_13000769_recovery_receipts_747 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_stock_13000769_recovery_receipts_747 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_qc_retest_events_747 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_qc_retest_events_747 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_qc_retest_supersessions_747 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_qc_retest_supersessions_747 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_stock_13000769_recovery_receipts_747,public.pdc_qc_retest_events_747,public.pdc_qc_retest_supersessions_747 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_qc_retest_immutable_747()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_747_APPEND_ONLY_EVIDENCE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_qc_retest_immutable_747() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_747_recovery_receipt_immutable BEFORE UPDATE OR DELETE ON public.pdc_stock_13000769_recovery_receipts_747 FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_retest_immutable_747();
CREATE TRIGGER pdc_747_retest_event_immutable BEFORE UPDATE OR DELETE ON public.pdc_qc_retest_events_747 FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_retest_immutable_747();
CREATE TRIGGER pdc_747_retest_supersession_immutable BEFORE UPDATE OR DELETE ON public.pdc_qc_retest_supersessions_747 FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_retest_immutable_747();

-- No later broad worker or purge may remove the restored canonical identity.
-- The guard does not affect Stock 13017855 or any other vehicle.
CREATE OR REPLACE FUNCTION public.pdc_protect_recovered_stock_13000769_747()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.id='d777b071-a2b0-5367-893b-aa83a07fcfce'::uuid THEN
      RAISE EXCEPTION 'PDC_747_RECOVERED_STOCK_DELETE_BLOCKED' USING errcode='55000';
    END IF;
    RETURN OLD;
  END IF;
  IF OLD.id='d777b071-a2b0-5367-893b-aa83a07fcfce'::uuid
     AND (NEW.deleted_at IS NOT NULL OR NEW.lifecycle_state::text='deleted' OR NEW.stock_number IS NULL
          OR NEW.stock_number_normalized IS DISTINCT FROM '13000769') THEN
    RAISE EXCEPTION 'PDC_747_RECOVERED_STOCK_ARCHIVE_BLOCKED' USING errcode='55000';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.pdc_protect_recovered_stock_13000769_747() FROM public,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS pdc_747_recovered_vehicle_guard ON public.vehicles;
CREATE TRIGGER pdc_747_recovered_vehicle_guard BEFORE DELETE OR UPDATE OF stock_number,lifecycle_state,deleted_at,visible_on_board ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.pdc_protect_recovered_stock_13000769_747();

CREATE OR REPLACE FUNCTION public.pdc_protect_recovered_backend_13000769_747()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' AND OLD.id='de800087-d086-4f7b-9569-bb8a88660475'::uuid THEN
    RAISE EXCEPTION 'PDC_747_RECOVERED_BACKEND_DELETE_BLOCKED' USING errcode='55000';
  END IF;
  IF TG_OP='UPDATE' AND OLD.id='de800087-d086-4f7b-9569-bb8a88660475'::uuid
     AND NEW.canonical_vehicle_id IS DISTINCT FROM 'd777b071-a2b0-5367-893b-aa83a07fcfce'::uuid THEN
    RAISE EXCEPTION 'PDC_747_RECOVERED_BACKEND_UNLINK_BLOCKED' USING errcode='55000';
  END IF;
  RETURN COALESCE(NEW,OLD);
END $$;
REVOKE ALL ON FUNCTION public.pdc_protect_recovered_backend_13000769_747() FROM public,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS pdc_747_recovered_backend_guard ON public.navision_backend_records;
CREATE TRIGGER pdc_747_recovered_backend_guard BEFORE DELETE OR UPDATE OF canonical_vehicle_id ON public.navision_backend_records FOR EACH ROW EXECUTE FUNCTION public.pdc_protect_recovered_backend_13000769_747();

-- Any RFT transition for this recovered identity requires the new cycle's
-- fresh-photo/sign-off event; old QC evidence alone can never authorize RFT.
CREATE OR REPLACE FUNCTION public.pdc_require_retest_before_rft_747()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_cycle uuid;
BEGIN
  IF OLD.id='d777b071-a2b0-5367-893b-aa83a07fcfce'::uuid
     AND OLD.lifecycle_state::text='active' AND upper(coalesce(OLD.current_location,''))='QC'
     AND NEW.lifecycle_state::text='rft' AND upper(coalesce(NEW.current_location,''))='RFT' THEN
    v_cycle:=NULLIF(current_setting('pdc.747_retest_signoff',true),'')::uuid;
    IF v_cycle IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_qc_retest_events_747 e WHERE e.cycle_id=v_cycle AND e.event_kind='fresh_photo_accepted') THEN
      RAISE EXCEPTION 'PDC_747_FRESH_QC_PHOTO_REQUIRED_BEFORE_RFT' USING errcode='55000';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.pdc_require_retest_before_rft_747() FROM public,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS pdc_747_retest_rft_gate ON public.vehicles;
CREATE TRIGGER pdc_747_retest_rft_gate BEFORE UPDATE OF lifecycle_state,current_location ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.pdc_require_retest_before_rft_747();

CREATE OR REPLACE FUNCTION public.pdc_admin_recover_stock_13000769_to_qc_747(
  p_vehicle_id uuid,p_expected_version integer,p_confirmation_stock text,p_idempotency_key uuid,p_dashboard_session text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $$
DECLARE s jsonb; uid uuid; email text; v public.vehicles%rowtype; before_state jsonb; after_state jsonb;
  cycle uuid; receipt uuid; photo uuid; finalization uuid; req jsonb; req_sha text; response jsonb; existing public.pdc_stock_13000769_recovery_receipts_747%rowtype;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
  s:=public.pdc_admin_vehicle_actor();
  IF NOT coalesce((s->>'ok')::boolean,false) OR (s->'data'->>'actor_id')::uuid<>'8a83b715-8d79-4b0e-95b2-02b55da6e8d7'::uuid OR s->'data'->>'actor_email'<>'craig.watson@broometoyota.com.au' THEN RETURN jsonb_build_object('ok',false,'code','administrator_required'); END IF;
  uid:=(s->'data'->>'actor_id')::uuid; email:=s->'data'->>'actor_email';
  IF p_vehicle_id IS DISTINCT FROM 'd777b071-a2b0-5367-893b-aa83a07fcfce'::uuid OR p_confirmation_stock IS DISTINCT FROM '13000769' OR p_idempotency_key IS NULL OR p_dashboard_session IS DISTINCT FROM '20260828_161016_aa9508' THEN RETURN jsonb_build_object('ok',false,'code','recovery_identity_mismatch'); END IF;
  req:=jsonb_build_object('contract','pdc-stock-13000769-recovery-747','vehicle_id',p_vehicle_id,'expected_version',p_expected_version,'confirmation_stock',p_confirmation_stock,'idempotency_key',p_idempotency_key,'dashboard_session',p_dashboard_session,'backup_run_id','847b7b9a-7f25-4a13-868d-fb3a95b9e447');
  req_sha:=encode(extensions.digest(convert_to(req::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-747-recovery-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO existing FROM public.pdc_stock_13000769_recovery_receipts_747 WHERE recovery_key='recover-stock-13000769-to-qc-20260828_161016_aa9508' FOR SHARE;
  IF FOUND THEN
    IF existing.response->>'request_sha256'<>req_sha THEN RETURN jsonb_build_object('ok',false,'code','recovery_idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(existing.response,'{replay}','true'::jsonb,false)||jsonb_build_object('replay',true);
  END IF;
  IF p_expected_version IS NULL OR p_expected_version<1 THEN RETURN jsonb_build_object('ok',false,'code','missing_expected_version'); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.stock_number_normalized<>'13000769' OR v.job_card_number<>'J139125493' OR v.source_record_id_normalized<>'DE800087-D086-4F7B-9569-BB8A88660475' OR v.permanent_vehicle_id<>'PDC-AI-EA6245015374E22419FEF6A3' THEN RETURN jsonb_build_object('ok',false,'code','recovered_identity_mismatch'); END IF;
  IF v.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','current_version',v.version); END IF;
  IF v.lifecycle_state::text<>'rft' OR upper(v.current_location)<>'RFT' OR v.rft_collected_at IS NOT NULL OR v.rft_collected_by IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','recovery_requires_uncollected_rft'); END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND b.status::text NOT IN('completed','deleted','cancelled')) THEN RETURN jsonb_build_object('ok',false,'code','active_booking_present'); END IF;
  IF to_regclass('public.pdc_qc_salesperson_update_outbox_399') IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_qc_salesperson_update_outbox_399 o WHERE o.vehicle_id=v.id) THEN RETURN jsonb_build_object('ok',false,'code','outbox_present'); END IF;
  IF to_regclass('public.pdc_rft_transport_email_drafts_739') IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_drafts_739 d WHERE d.vehicle_id=v.id) THEN RETURN jsonb_build_object('ok',false,'code','draft_present'); END IF;
  SELECT photo_receipt_id INTO photo FROM public.pdc_qc_finalization_photo_evidence_399 WHERE vehicle_id=v.id ORDER BY created_at DESC LIMIT 1;
  SELECT receipt_id INTO finalization FROM public.pdc_qc_finalization_receipts_399 WHERE vehicle_id=v.id ORDER BY created_at DESC LIMIT 1;
  IF photo IS NULL OR finalization IS NULL THEN RETURN jsonb_build_object('ok',false,'code','prior_qc_evidence_missing'); END IF;
  before_state:=jsonb_build_object('vehicle',to_jsonb(v),'prior_qc_photo_receipt_id',photo,'prior_qc_finalization_receipt_id',finalization,'purge_receipt','complete-operational-purge-stock-13000769','replay_fence','pdc_email_replay_fences_746:uidvalidity-1-uid-639-stock-13000769');
  cycle:=extensions.uuid_generate_v5('74700000-0000-5000-8000-000000000747'::uuid,'cycle:'||p_idempotency_key::text);
  receipt:=extensions.uuid_generate_v5('74700000-0000-5000-8000-000000000747'::uuid,'recovery:'||p_idempotency_key::text);
  INSERT INTO public.pdc_qc_retest_supersessions_747(supersession_id,cycle_id,vehicle_id,prior_photo_receipt_id,prior_finalization_receipt_id,supersession_reason,actor_id,actor_email) VALUES(extensions.uuid_generate_v5('74700000-0000-5000-8000-000000000747'::uuid,'supersession:'||p_idempotency_key::text),cycle,v.id,photo,finalization,'prior QC finalization/photo evidence superseded for fresh mobile QC retest',uid,email);
  INSERT INTO public.pdc_qc_retest_events_747(event_id,cycle_id,vehicle_id,stock_number,event_kind,idempotency_key,request_sha256,before_state,after_state,actor_id,actor_email)
    VALUES(extensions.uuid_generate_v5('74700000-0000-5000-8000-000000000747'::uuid,'recovered_to_qc:'||p_idempotency_key::text),cycle,v.id,'13000769','recovered_to_qc',p_idempotency_key,req_sha,before_state,jsonb_build_object('cycle_id',cycle,'fresh_photo_required',true,'rft_permitted',false),uid,email);
  UPDATE public.vehicles SET lifecycle_state='active',current_location='QC',visible_on_board=true,pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,
    active_workshop_booking_id=NULL,qc_completed_at=NULL,qc_completed_by=NULL,rft_confirmed_at=NULL,rft_confirmed_by=NULL,rft_transferred_at=NULL,
    rft_transport_booked_at=NULL,rft_transport_booked_by=NULL,dealer_transit_started_at=NULL,dealer_transit_closed_at=NULL,dealer_transit_duration_seconds=NULL,
    version=version+1,updated_by=uid,updated_at=clock_timestamp() WHERE id=v.id RETURNING * INTO v;
  after_state:=jsonb_build_object('vehicle',to_jsonb(v),'cycle_id',cycle,'fresh_photo_required',true,'prior_qc_evidence_superseded',true,'rft_transport_booked',false,'dealer_transit_active',false,'collection_active',false);
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
    VALUES(v.id,'RFT','QC',NULL,NULL,NULL,NULL,NULL,NULL,'Staging recovery of incorrectly purged Stock 13000769; fresh QC mobile-photo retest required',uid);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state->'vehicle',after_state->'vehicle',jsonb_build_object('action','pdc_admin_recover_stock_13000769_to_qc_747','cycle_id',cycle,'dashboard_session',p_dashboard_session,'supersedes_purge_receipt','complete-operational-purge-stock-13000769'));
  response:=jsonb_build_object('ok',true,'code','stock_recovered_to_qc_retest','replay',false,'request_sha256',req_sha,'receipt_id',receipt,'cycle_id',cycle,'vehicle_id',v.id,'vehicle_version_before',p_expected_version,'vehicle_version_after',v.version,'stock_number','13000769','dashboard_session',p_dashboard_session,'fresh_photo_required',true,'rft_permitted',false,'prior_qc_photo_receipt_id',photo,'prior_qc_finalization_receipt_id',finalization,'outbox_restored',false,'dealer_transit_active',false,'collection_active',false);
  INSERT INTO public.pdc_stock_13000769_recovery_receipts_747 VALUES('recover-stock-13000769-to-qc-20260828_161016_aa9508',receipt,p_dashboard_session,'13000769',v.id,'de800087-d086-4f7b-9569-bb8a88660475','20260829130000/746_purge_stock_13000769','complete-operational-purge-stock-13000769','pdc_email_replay_fences_746:uidvalidity-1-uid-639-stock-13000769','847b7b9a-7f25-4a13-868d-fb3a95b9e447','7326179925f024eb3f295bdc504aa84b15f416c6e37cf71b777f7946958a817d','949a8fa7274364b43ecd1fb5248af9f7628f6350cc8196b41733f6322fb8d0e7',28,206,1,p_expected_version,v.version,photo,finalization,'restore_exact_closure_then_move_rft_to_qc_retest',uid,email,response);
  RETURN response;
END $$;
REVOKE ALL ON FUNCTION public.pdc_admin_recover_stock_13000769_to_qc_747(uuid,integer,text,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_admin_recover_stock_13000769_to_qc_747(uuid,integer,text,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_pdc_qc_retest_photo_747(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_cycle_id uuid,p_bucket_id text,p_storage_path text,p_content_type text,
  p_byte_length integer,p_original_byte_length integer,p_image_width integer,p_image_height integer,p_sha256 text,p_original_filename text,p_idempotency_key uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $$
DECLARE s jsonb; uid uuid; email text; v public.vehicles%rowtype; req jsonb; req_sha text; old public.pdc_qc_retest_events_747%rowtype; photo_id uuid; response jsonb; n integer;
BEGIN
  s:=public.pdc_admin_vehicle_actor(); IF NOT coalesce((s->>'ok')::boolean,false) THEN RETURN s; END IF; uid:=(s->'data'->>'actor_id')::uuid; email:=s->'data'->>'actor_email';
  IF p_vehicle_id IS DISTINCT FROM 'd777b071-a2b0-5367-893b-aa83a07fcfce'::uuid OR p_cycle_id IS NULL OR p_bucket_id<>'pdc-qc-evidence-staging' OR p_storage_path!~('^qc-finalization/'||uid::text||'/[0-9a-f-]{36}/[^/]{1,180}$') OR lower(btrim(coalesce(p_content_type,''))) NOT LIKE 'image/%' OR p_byte_length NOT BETWEEN 1 AND 1048576 OR p_original_byte_length NOT BETWEEN 1 AND 10485760 OR p_image_width NOT BETWEEN 1 AND 1600 OR p_image_height NOT BETWEEN 1 AND 1600 OR lower(btrim(coalesce(p_sha256,'')))!~'^[a-f0-9]{64}$' OR length(btrim(coalesce(p_original_filename,''))) NOT BETWEEN 1 AND 180 OR p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_photo_invalid_input'); END IF;
  req:=jsonb_build_object('contract','pdc-qc-retest-photo-747','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'cycle_id',p_cycle_id,'bucket_id',p_bucket_id,'storage_path',p_storage_path,'content_type',lower(btrim(p_content_type)),'byte_length',p_byte_length,'original_byte_length',p_original_byte_length,'image_width',p_image_width,'image_height',p_image_height,'sha256',lower(btrim(p_sha256)),'original_filename',btrim(p_original_filename),'idempotency_key',p_idempotency_key,'actor_id',uid); req_sha:=encode(extensions.digest(convert_to(req::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-747-photo:'||p_cycle_id::text,0));
  SELECT * INTO old FROM public.pdc_qc_retest_events_747 WHERE cycle_id=p_cycle_id AND event_kind='fresh_photo_accepted' FOR SHARE;
  IF FOUND THEN IF old.request_sha256<>req_sha THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_photo_replay_mismatch'); END IF; RETURN jsonb_build_object('ok',true,'code','qc_retest_photo_accepted','replay',true,'cycle_id',p_cycle_id,'photo_receipt_id',old.photo_receipt_id,'vehicle_id',p_vehicle_id); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR SHARE;
  IF NOT FOUND OR v.lifecycle_state::text<>'active' OR upper(v.current_location)<>'QC' OR v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_vehicle_version_or_location_conflict'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_qc_retest_events_747 WHERE cycle_id=p_cycle_id AND event_kind='recovered_to_qc') THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_cycle_not_found'); END IF;
  SELECT count(*) INTO n FROM storage.objects o WHERE o.bucket_id=p_bucket_id AND o.name=p_storage_path AND o.owner_id=uid::text;
  IF n<>1 THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_photo_storage_object_not_owned'); END IF;
  photo_id:=extensions.uuid_generate_v5('39900000-0000-5000-8000-000000000399'::uuid,'747-retest-photo:'||p_idempotency_key::text);
  INSERT INTO public.pdc_qc_finalization_photo_evidence_399(photo_receipt_id,vehicle_id,expected_vehicle_version,uploader_id,uploader_email,bucket_id,storage_path,content_type,byte_length,original_byte_length,image_width,image_height,sha256,original_filename,idempotency_key,request_sha256,response)
  VALUES(photo_id,p_vehicle_id,p_expected_vehicle_version,uid,email,p_bucket_id,p_storage_path,lower(btrim(p_content_type)),p_byte_length,p_original_byte_length,p_image_width,p_image_height,lower(btrim(p_sha256)),btrim(p_original_filename),p_idempotency_key,req_sha,jsonb_build_object('ok',true,'code','qc_retest_photo_accepted','cycle_id',p_cycle_id,'photo_receipt_id',photo_id,'fresh_cycle',true));
  response:=jsonb_build_object('ok',true,'code','qc_retest_photo_accepted','replay',false,'cycle_id',p_cycle_id,'photo_receipt_id',photo_id,'vehicle_id',p_vehicle_id,'vehicle_version',v.version,'fresh_cycle',true,'rft_permitted',false);
  INSERT INTO public.pdc_qc_retest_events_747(event_id,cycle_id,vehicle_id,stock_number,event_kind,idempotency_key,request_sha256,photo_receipt_id,before_state,after_state,actor_id,actor_email) VALUES(extensions.uuid_generate_v5('74700000-0000-5000-8000-000000000747'::uuid,'fresh_photo:'||p_idempotency_key::text),p_cycle_id,p_vehicle_id,'13000769','fresh_photo_accepted',p_idempotency_key,req_sha,photo_id,jsonb_build_object('vehicle_version',v.version,'current_location','QC'),response,uid,email);
  RETURN response;
END $$;
REVOKE ALL ON FUNCTION public.record_pdc_qc_retest_photo_747(uuid,integer,uuid,text,text,text,integer,integer,integer,integer,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_pdc_qc_retest_photo_747(uuid,integer,uuid,text,text,text,integer,integer,integer,integer,text,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.finalize_pdc_qc_retest_to_rft_747(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_cycle_id uuid,p_photo_receipt_id uuid,p_idempotency_key uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $$
DECLARE s jsonb; uid uuid; email text; v0 public.vehicles%rowtype; v1 public.vehicles%rowtype; old public.pdc_qc_retest_events_747%rowtype; req jsonb; req_sha text; lines jsonb; response jsonb;
BEGIN
  s:=public.pdc_admin_vehicle_actor(); IF NOT coalesce((s->>'ok')::boolean,false) THEN RETURN s; END IF; uid:=(s->'data'->>'actor_id')::uuid; email:=s->'data'->>'actor_email';
  IF p_vehicle_id IS DISTINCT FROM 'd777b071-a2b0-5367-893b-aa83a07fcfce'::uuid OR p_cycle_id IS NULL OR p_photo_receipt_id IS NULL OR p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_signoff_invalid_input'); END IF;
  req:=jsonb_build_object('contract','pdc-qc-retest-signoff-747','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'cycle_id',p_cycle_id,'photo_receipt_id',p_photo_receipt_id,'idempotency_key',p_idempotency_key,'actor_id',uid); req_sha:=encode(extensions.digest(convert_to(req::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-747-signoff:'||p_cycle_id::text,0));
  SELECT * INTO old FROM public.pdc_qc_retest_events_747 WHERE cycle_id=p_cycle_id AND event_kind='qc_signed_off_to_rft' FOR SHARE;
  IF FOUND THEN IF old.request_sha256<>req_sha THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_signoff_replay_mismatch'); END IF; RETURN jsonb_set(old.after_state,'{replay}','true'::jsonb,false)||jsonb_build_object('ok',true,'code','qc_retest_signed_off_to_rft','replay',true); END IF;
  SELECT * INTO v0 FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v0.lifecycle_state::text<>'active' OR upper(v0.current_location)<>'QC' OR v0.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','qc_retest_vehicle_version_or_location_conflict'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_qc_retest_events_747 WHERE cycle_id=p_cycle_id AND event_kind='fresh_photo_accepted' AND photo_receipt_id=p_photo_receipt_id) THEN RETURN jsonb_build_object('ok',false,'code','fresh_qc_photo_required'); END IF;
  lines:=public.pdc_qc_operation_lines_379(p_vehicle_id);
  IF jsonb_array_length(coalesce(lines,'[]'::jsonb))<>17 OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(lines,'[]'::jsonb)) x WHERE coalesce((x->>'active')::boolean,false) AND (NOT coalesce((x->>'completed')::boolean,false) OR nullif(btrim(coalesce(x->>'estimated_hours','')),'') IS NULL)) THEN RETURN jsonb_build_object('ok',false,'code','qc_operation_lines_incomplete'); END IF;
  PERFORM set_config('pdc.747_retest_signoff',p_cycle_id::text,true);
  UPDATE public.vehicles SET qc_completed_at=clock_timestamp(),qc_completed_by=uid,version=version+1,updated_by=uid,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v1;
  UPDATE public.vehicles SET lifecycle_state='rft',current_location='RFT',rft_transferred_at=clock_timestamp(),version=version+1,updated_by=uid,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v1;
  response:=jsonb_build_object('ok',true,'code','qc_retest_signed_off_to_rft','replay',false,'cycle_id',p_cycle_id,'vehicle_id',p_vehicle_id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v1.version,'fresh_photo_receipt_id',p_photo_receipt_id,'transport_booking_permitted',true,'fresh_photo_required_for_transport',true);
  INSERT INTO public.pdc_qc_retest_events_747(event_id,cycle_id,vehicle_id,stock_number,event_kind,idempotency_key,request_sha256,photo_receipt_id,before_state,after_state,actor_id,actor_email) VALUES(extensions.uuid_generate_v5('74700000-0000-5000-8000-000000000747'::uuid,'signoff:'||p_idempotency_key::text),p_cycle_id,p_vehicle_id,'13000769','qc_signed_off_to_rft',p_idempotency_key,req_sha,p_photo_receipt_id,jsonb_build_object('vehicle',to_jsonb(v0),'fresh_photo_receipt_id',p_photo_receipt_id),response,uid,email);
  RETURN response;
END $$;
REVOKE ALL ON FUNCTION public.finalize_pdc_qc_retest_to_rft_747(uuid,integer,uuid,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_pdc_qc_retest_to_rft_747(uuid,integer,uuid,uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.read_pdc_stock_13000769_qc_retest_snapshot_747()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v public.vehicles%rowtype; r public.pdc_stock_13000769_recovery_receipts_747%rowtype; cycle uuid; photo uuid; lines jsonb; active_booking bigint; outbox bigint; drafts bigint; collected boolean; superseded boolean;
BEGIN
  IF public.current_pdc_user_role()::text NOT IN('viewer','operator','administrator','importer') THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id='d777b071-a2b0-5367-893b-aa83a07fcfce' AND stock_number_normalized='13000769';
  SELECT * INTO r FROM public.pdc_stock_13000769_recovery_receipts_747 WHERE recovery_key='recover-stock-13000769-to-qc-20260828_161016_aa9508';
  SELECT cycle_id INTO cycle FROM public.pdc_qc_retest_events_747 WHERE vehicle_id=v.id AND event_kind='recovered_to_qc' ORDER BY created_at DESC LIMIT 1;
  SELECT photo_receipt_id INTO photo FROM public.pdc_qc_retest_events_747 WHERE cycle_id=cycle AND event_kind='fresh_photo_accepted';
  lines:=public.pdc_qc_operation_lines_379(v.id);
  SELECT count(*) INTO active_booking FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND b.status::text NOT IN('completed','deleted','cancelled');
  SELECT count(*) INTO outbox FROM public.pdc_qc_salesperson_update_outbox_399 o WHERE o.vehicle_id=v.id;
  SELECT count(*) INTO drafts FROM public.pdc_rft_transport_email_drafts_739 d WHERE d.vehicle_id=v.id;
  collected:=v.rft_collected_at IS NOT NULL OR v.rft_collected_by IS NOT NULL;
  superseded:=r IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_qc_retest_supersessions_747 s WHERE s.cycle_id=cycle AND s.prior_photo_receipt_id=r.prior_qc_photo_receipt_id AND s.prior_finalization_receipt_id=r.prior_qc_finalization_receipt_id);
  RETURN jsonb_build_object('ok',true,'code','stock_13000769_qc_retest_snapshot','data',jsonb_build_object('vehicle_count',case when v.id IS NULL then 0 else 1 end,'vehicle',case when v.id IS NULL then null else jsonb_build_object('id',v.id,'stock_number',v.stock_number,'job_card_number',v.job_card_number,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'visible_on_board',v.visible_on_board,'version',v.version,'qc_completed_at',v.qc_completed_at,'rft_confirmed_at',v.rft_confirmed_at,'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,'rft_transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at) end,'cycle_id',cycle,'fresh_cycle_open',cycle IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pdc_qc_retest_events_747 e WHERE e.cycle_id=cycle AND e.event_kind='qc_signed_off_to_rft'),'fresh_photo_receipt_id',photo,'fresh_photo_accepted',photo IS NOT NULL,'operation_line_count',jsonb_array_length(coalesce(lines,'[]'::jsonb)),'operation_lines_visible',jsonb_array_length(coalesce(lines,'[]'::jsonb))=17,'active_booking_count',active_booking,'outbox_count',outbox,'draft_count',drafts,'collection_active',collected,'prior_qc_evidence_superseded',superseded,'prior_qc_photo_receipt_id',r.prior_qc_photo_receipt_id,'prior_qc_finalization_receipt_id',r.prior_qc_finalization_receipt_id,'recovery_receipt_id',r.receipt_id,'dashboard_session',r.dashboard_session));
END $$;
REVOKE ALL ON FUNCTION public.read_pdc_stock_13000769_qc_retest_snapshot_747() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_stock_13000769_qc_retest_snapshot_747() TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260829140000','747_restore_stock_13000769_qc_retest',ARRAY['Staging-only exact encrypted 29-table closure restore bound to migration 746 purge receipt and UID 639 replay fence','Restore 28 exact identity, Navision, Job Card, 17 operation-line and immutable-history tables; exclude one pending QC salesperson outbox so no dispatch is recreated','Administrator-only exact UUID/Stock/current-version/idempotent recovery associated with existing dashboard session 20260828_161016_aa9508','Move restored RFT identity to active QC, clear only RFT/dealer-transit timer state, preserve completed operation-line truth and immutable history','Append-only QC retest event/supersession evidence; fresh mobile photo required before RFT; recovered identity/backend deletion and unlink blocked','Staging sentinel required and Production sentinel prohibited']);
NOTIFY pgrst,'reload schema';
COMMIT;
