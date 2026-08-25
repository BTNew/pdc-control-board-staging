-- STAGING ONLY 429: sealed interception proof for mandatory RFT salesperson email.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-429-rft-email-intercept',0));
DO $pre$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826203000' AND name='428_collected_vehicle_authoritative_snapshot')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826203000')
  OR to_regclass('storage.objects') IS NULL THEN RAISE EXCEPTION 'PDC_429_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000'; END IF;
END $pre$;
CREATE TABLE public.pdc_rft_transport_email_intercept_claims_429(
 notification_id uuid PRIMARY KEY REFERENCES public.pdc_rft_transport_salesperson_outbox_412(notification_id),
 claim_token uuid NOT NULL UNIQUE,claimed_by uuid NOT NULL,claimed_at timestamptz NOT NULL,expires_at timestamptz NOT NULL,payload_sha256 text NOT NULL CHECK(payload_sha256~'^[a-f0-9]{64}$')
);
CREATE TABLE public.pdc_rft_transport_email_intercept_receipts_429(
 receipt_id uuid PRIMARY KEY,notification_id uuid NOT NULL UNIQUE REFERENCES public.pdc_rft_transport_salesperson_outbox_412(notification_id),transport_receipt_id uuid NOT NULL REFERENCES public.pdc_rft_transport_action_receipts_412(receipt_id),vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 actor_id uuid NOT NULL,actor_email text NOT NULL,claim_token uuid NOT NULL,payload_sha256 text NOT NULL CHECK(payload_sha256~'^[a-f0-9]{64}$'),mime_sha256 text NOT NULL CHECK(mime_sha256~'^[a-f0-9]{64}$'),attachment_sha256 text NOT NULL CHECK(attachment_sha256~'^[a-f0-9]{64}$'),artifact_sha256 text NOT NULL CHECK(artifact_sha256~'^[a-f0-9]{64}$'),artifact_bytes bigint NOT NULL CHECK(artifact_bytes>0),outcome text NOT NULL CHECK(outcome='intercepted'),created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_rft_transport_email_intercept_claims_429 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_rft_transport_email_intercept_claims_429 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_email_intercept_receipts_429 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_rft_transport_email_intercept_receipts_429 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_rft_transport_email_intercept_claims_429,public.pdc_rft_transport_email_intercept_receipts_429 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_rft_transport_email_intercept_receipts_429_append_only BEFORE UPDATE OR DELETE ON public.pdc_rft_transport_email_intercept_receipts_429 FOR EACH ROW EXECUTE FUNCTION public.pdc_412_append_only();

CREATE OR REPLACE FUNCTION public.claim_pdc_rft_transport_email_intercept_429()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $claim$
DECLARE uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); o public.pdc_rft_transport_salesperson_outbox_412%rowtype; v public.vehicles%rowtype; token uuid; payload_sha text; now_at timestamptz:=clock_timestamp();
BEGIN
 IF uid<>'69846ef4-a74c-4569-9e35-376cf0837888'::uuid OR actor_email<>'pmbcontroller@gmail.com'
  OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.role='importer' AND r.active AND r.account_status='approved')
  OR EXISTS(SELECT 1 FROM public.monitored_mailboxes m WHERE lower(m.mailbox_address)=actor_email AND (m.active OR coalesce((m.config->>'outbound_email_enabled')::boolean,false)))
  OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=uid AND w.active AND w.revoked_at IS NULL)
  OR NOT public.pdc_monitor_staging_guard() THEN RETURN jsonb_build_object('ok',false,'code','intercept_runtime_not_contained'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-429-email-intercept-claim',0));
 SELECT x.* INTO o FROM public.pdc_rft_transport_salesperson_outbox_412 x JOIN public.vehicles vehicle ON vehicle.id=x.vehicle_id
 WHERE x.delivery_status='pending' AND x.sent_at IS NULL AND x.delivered_at IS NULL AND NOT coalesce((x.payload->>'delivery_enabled')::boolean,false)
  AND vehicle.stock_number LIKE 'HERMES-TEST-%' AND NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_intercept_receipts_429 r WHERE r.notification_id=x.notification_id)
 ORDER BY x.created_at,x.notification_id LIMIT 1 FOR UPDATE OF x SKIP LOCKED;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'code','no_pending_synthetic_intercept'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=o.vehicle_id;
 payload_sha:=encode(extensions.digest(convert_to(o.payload::text,'UTF8'),'sha256'),'hex'); token:=extensions.uuid_generate_v5('42900000-0000-5000-8000-000000000429'::uuid,o.notification_id::text||':'||payload_sha);
 INSERT INTO public.pdc_rft_transport_email_intercept_claims_429(notification_id,claim_token,claimed_by,claimed_at,expires_at,payload_sha256)
 VALUES(o.notification_id,token,uid,now_at,now_at+interval '10 minutes',payload_sha)
 ON CONFLICT(notification_id) DO UPDATE SET claim_token=excluded.claim_token,claimed_by=excluded.claimed_by,claimed_at=excluded.claimed_at,expires_at=excluded.expires_at,payload_sha256=excluded.payload_sha256
 WHERE public.pdc_rft_transport_email_intercept_claims_429.expires_at<now_at OR public.pdc_rft_transport_email_intercept_claims_429.claimed_by=uid;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','intercept_already_claimed'); END IF;
 RETURN jsonb_build_object('ok',true,'code','synthetic_email_intercept_claimed','notification_id',o.notification_id,'transport_receipt_id',o.transport_receipt_id,'vehicle_id',o.vehicle_id,'stock_number',v.stock_number,'claim_token',token,'expires_at',now_at+interval '10 minutes','payload_sha256',payload_sha,'recipient_email',o.recipient_email,'payload',o.payload);
END $claim$;

CREATE OR REPLACE FUNCTION public.ack_pdc_rft_transport_email_intercept_429(p_notification_id uuid,p_claim_token uuid,p_payload_sha256 text,p_mime_sha256 text,p_attachment_sha256 text,p_artifact_sha256 text,p_artifact_bytes bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $ack$
DECLARE uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); c public.pdc_rft_transport_email_intercept_claims_429%rowtype; o public.pdc_rft_transport_salesperson_outbox_412%rowtype; old public.pdc_rft_transport_email_intercept_receipts_429%rowtype; payload_sha text; receipt uuid; result jsonb;
BEGIN
 IF uid<>'69846ef4-a74c-4569-9e35-376cf0837888'::uuid OR actor_email<>'pmbcontroller@gmail.com' OR p_notification_id IS NULL OR p_claim_token IS NULL OR p_payload_sha256!~'^[a-f0-9]{64}$' OR p_mime_sha256!~'^[a-f0-9]{64}$' OR p_attachment_sha256!~'^[a-f0-9]{64}$' OR p_artifact_sha256!~'^[a-f0-9]{64}$' OR p_artifact_bytes<1 OR NOT public.pdc_monitor_staging_guard() THEN RETURN jsonb_build_object('ok',false,'code','intercept_ack_invalid_or_uncontained'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-429-email-intercept-ack:'||p_notification_id::text,0));
 SELECT * INTO old FROM public.pdc_rft_transport_email_intercept_receipts_429 WHERE notification_id=p_notification_id;
 IF FOUND THEN
  IF old.claim_token<>p_claim_token OR old.payload_sha256<>p_payload_sha256 OR old.mime_sha256<>p_mime_sha256 OR old.attachment_sha256<>p_attachment_sha256 OR old.artifact_sha256<>p_artifact_sha256 OR old.artifact_bytes<>p_artifact_bytes THEN RAISE EXCEPTION 'PDC_429_INTERCEPT_REPLAY_MISMATCH' USING errcode='22023'; END IF;
  RETURN jsonb_build_object('ok',true,'code','synthetic_email_intercepted','replay',true,'receipt_id',old.receipt_id,'notification_id',old.notification_id,'outcome',old.outcome);
 END IF;
 SELECT * INTO c FROM public.pdc_rft_transport_email_intercept_claims_429 WHERE notification_id=p_notification_id AND claim_token=p_claim_token AND claimed_by=uid AND expires_at>=clock_timestamp() FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','intercept_claim_missing_or_expired'); END IF;
 SELECT * INTO o FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE notification_id=p_notification_id FOR SHARE;
 payload_sha:=encode(extensions.digest(convert_to(o.payload::text,'UTF8'),'sha256'),'hex');
 IF payload_sha<>c.payload_sha256 OR payload_sha<>p_payload_sha256 OR lower(o.payload#>>'{photo_attachment,sha256}')<>p_attachment_sha256 OR o.delivery_status<>'pending' OR o.sent_at IS NOT NULL OR o.delivered_at IS NOT NULL OR coalesce((o.payload->>'delivery_enabled')::boolean,false) THEN RAISE EXCEPTION 'PDC_429_INTERCEPT_EVIDENCE_MISMATCH' USING errcode='55000'; END IF;
 receipt:=extensions.uuid_generate_v5('42900000-0000-5000-8000-000000000429'::uuid,o.notification_id::text||':'||payload_sha||':'||p_mime_sha256);
 INSERT INTO public.pdc_rft_transport_email_intercept_receipts_429 VALUES(receipt,o.notification_id,o.transport_receipt_id,o.vehicle_id,uid,actor_email,p_claim_token,p_payload_sha256,p_mime_sha256,p_attachment_sha256,p_artifact_sha256,p_artifact_bytes,'intercepted',clock_timestamp());
 result:=jsonb_build_object('ok',true,'code','synthetic_email_intercepted','replay',false,'receipt_id',receipt,'notification_id',o.notification_id,'outcome','intercepted','outbox_status',o.delivery_status,'sent_at',o.sent_at,'delivered_at',o.delivered_at);
 RETURN result;
END $ack$;
REVOKE ALL ON FUNCTION public.claim_pdc_rft_transport_email_intercept_429() FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.ack_pdc_rft_transport_email_intercept_429(uuid,uuid,text,text,text,text,bigint) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_pdc_rft_transport_email_intercept_429() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ack_pdc_rft_transport_email_intercept_429(uuid,uuid,text,text,text,text,bigint) TO authenticated;

CREATE POLICY pdc_rft_transport_interceptor_read_429 ON storage.objects FOR SELECT TO authenticated USING(
 bucket_id='pdc-qc-evidence-staging' AND auth.uid()='69846ef4-a74c-4569-9e35-376cf0837888'::uuid AND EXISTS(
  SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 o JOIN public.vehicles v ON v.id=o.vehicle_id
  WHERE o.delivery_status='pending' AND o.sent_at IS NULL AND o.delivered_at IS NULL AND v.stock_number LIKE 'HERMES-TEST-%'
   AND o.payload#>>'{photo_attachment,bucket_id}'=storage.objects.bucket_id AND o.payload#>>'{photo_attachment,storage_path}'=storage.objects.name));

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_429;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE r jsonb; rows jsonb; BEGIN r:=public.get_pdc_email_vehicle_location_snapshot_pre_429(); IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
 SELECT coalesce(jsonb_agg(x||jsonb_build_object('rft_transport_outbox',coalesce(x->'rft_transport_outbox','{}'::jsonb)||coalesce((SELECT jsonb_build_object('intercept_receipt_id',i.receipt_id,'intercepted_at',i.created_at,'intercept_outcome',i.outcome) FROM public.pdc_rft_transport_email_intercept_receipts_429 i WHERE i.vehicle_id=(x->>'id')::uuid ORDER BY i.created_at DESC LIMIT 1),'{}'::jsonb)) ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb) INTO rows FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
 RETURN jsonb_set(r,'{data,vehicles}',rows,true); END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_429() FROM public,anon,authenticated,service_role; REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon; GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260826204000','429_rft_email_intercept_receipts',ARRAY[
 'Private claims plus append-only interception receipts prove deterministic mandatory RFT salesperson MIME and exact QC attachment without SMTP/provider delivery',
 'Exact pmbcontroller importer identity, inactive mailbox/writer, delivery_enabled=false, synthetic Stock and staging guard are mandatory',
 'Original 412 outbox remains immutable pending with null sent/delivered timestamps; narrow Storage read policy covers only its referenced synthetic QC object'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
