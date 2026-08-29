-- STAGING ONLY 782: collision-safe current-head security successor.
-- Applies only after the live 778 receipt/occurrence contract at 20260830172000.
-- No historical Apply, mailbox polling, outbound email, Production access, task
-- enablement, or broad privilege is performed by this migration.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-782-historical-reconciliation-security-successor',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_head text;
  v_body text;
  v_owner text;
  v_config text;
  v_acl text;
  v_secdef boolean;
  v_trigger_text text;
  v_trigger_hash text;
  r record;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830172000,778_historical_reconciliation_receipt_and_occurrence_repair)'
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830172000' AND name='778_historical_reconciliation_receipt_and_occurrence_repair' AND statements=ARRAY[
       'Bind the UUID-free caller to frozen UIDVALIDITY 1/high-water 685/669-message manifest and current authenticated Monitor release/gateway/runtime',
       'Enforce exact immutable 773 authorization, sender/source/authentication/Stock binding, 24-hour expiry and receipt-backed one-time replay protection',
       'Use provider-bound enqueue and immutable per-sibling observations, continue valid Job Card siblings while ambiguous siblings fail closed, and require exact child Stock scope',
       'Preserve Navision not_found/identity failures, old-mail completion protection, Stock 13056899 / UID 1:197 exclusion, audit, no booking/completion/location, outbound email, task and Production boundaries'
     ])
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830173000')
  THEN RAISE EXCEPTION 'PDC_782_CURRENT_HEAD_GUARD_FAILED' USING errcode='55000'; END IF;

  FOR r IN SELECT * FROM (VALUES
    ('public.pdc_monitor_staging_guard()','596f9c1c46c405b245b7aca9e21e33a1232a0cae01a596a61d3f11168328edba','search_path=pg_catalog, public','postgres:EXECUTE:false|service_role:EXECUTE:false','pdc_monitor_staging_guard'),
    ('public.pdc_monitor_authenticated_active_scope_674(text)','cdf74a6b90abd0839a7226c881830844e5d0dcc20f8652141395662e9853f5ba','search_path=pg_catalog, public, auth','postgres:EXECUTE:false','pdc_monitor_authenticated_active_scope_674'),
    ('public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)','ac5d8baa2adbda0c078b3da5fa721ff262301ab6402954a92603ccc57d1c6086','search_path=pg_catalog, public, auth, extensions','authenticated:EXECUTE:false|postgres:EXECUTE:false','verify_pdc_monitor_runtime_binding_authenticated_766'),
    ('public.pdc_historical_writer_authorized_773(text,text,text,jsonb,text)','9bd5a567213e77dd4fb3ff45fa7031443444707505e576a3c17ace1c7c6699dd','search_path=pg_catalog, public, auth, extensions','postgres:EXECUTE:false','pdc_historical_reconciliation_writer_authorizations_773'),
    ('public.enqueue_pdc_email_intake(jsonb,jsonb)','f4f6f14d094afc04c110c72ca6d6d2c642bf6bf2fa8a96f59d3115793a6accd8','search_path=pg_catalog, public, extensions','authenticated:EXECUTE:false|postgres:EXECUTE:false','pdc_historical_writer_authorized_773'),
    ('public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)','f73dd525e5dc6caccde4d5658bea8a2cabd95ec7f55898b792e5984568de5950','search_path=pg_catalog, public, extensions','postgres:EXECUTE:false','pdc_monitor_staging_guard'),
    ('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','6497f2ba7ad244ea414f26d80400a3fa4bff2bf090746fdaa4cad800cbe53cfb','search_path=pg_catalog, public, extensions,statement_timeout=180s','postgres:EXECUTE:false','pdc_historical_provider_observations_778'),
    ('public.read_pdc_historical_reconciliation_778_receipt(uuid)','f6a954d162f3b9d7ae53a6fa073f4195b6a1067f51fc8ba7346217a95f518bb8','search_path=pg_catalog, public, auth, extensions','authenticated:EXECUTE:false|postgres:EXECUTE:false','pdc_historical_reconciliation_778_receipts'),
    ('public.submit_pdc_historical_reconciliation_778(jsonb)','2c679c4a0f245c646e5afbc746f48463a76cc04d06954566bff35567863a5512','search_path=pg_catalog, public, auth, extensions,statement_timeout=300s','authenticated:EXECUTE:false|postgres:EXECUTE:false','enqueue_pdc_email_intake')
  ) AS x(sig,body_hash,config,acl,callee) LOOP
    SELECT pg_get_userbyid(p.proowner),p.prosecdef,coalesce(array_to_string(p.proconfig,','),''),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex'),
      coalesce((SELECT string_agg(coalesce(pg_get_userbyid(a.grantee),'PUBLIC')||':'||a.privilege_type||':'||a.is_grantable,'|' ORDER BY coalesce(pg_get_userbyid(a.grantee),'PUBLIC'),a.privilege_type,a.is_grantable) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),'')
    INTO v_owner,v_secdef,v_config,v_body,v_acl FROM pg_proc p WHERE p.oid=r.sig::regprocedure;
    IF v_owner IS DISTINCT FROM 'postgres' OR v_secdef IS DISTINCT FROM true OR v_config IS DISTINCT FROM r.config OR v_body IS DISTINCT FROM r.body_hash OR v_acl IS DISTINCT FROM r.acl OR to_regprocedure(r.sig) IS NULL THEN
      RAISE EXCEPTION 'PDC_782_DEPENDENCY_CONTRACT_DRIFT:%',r.sig USING errcode='55000';
    END IF;
    SELECT pg_get_functiondef(r.sig::regprocedure) INTO v_body;
    IF position(r.callee in v_body)=0 THEN RAISE EXCEPTION 'PDC_782_CALLEE_CONTRACT_DRIFT:%',r.sig USING errcode='55000'; END IF;
  END LOOP;

  SELECT coalesce(string_agg(event_object_table||'|'||trigger_name||'|'||event_manipulation||'|'||action_timing||'|'||action_statement,'|' ORDER BY event_object_table,trigger_name,event_manipulation),'') INTO v_trigger_text
  FROM information_schema.triggers
  WHERE event_object_schema='public' AND event_object_table IN (
    'ai_email_intake','ai_email_attachments','vehicles','vehicle_work_items','pdc_authenticated_email_operation_lines',
    'vehicle_workshop_line_adjustments','vehicle_parts_updates','workshop_bookings','workshop_booking_assignments',
    'pdc_sublet_bookings','pdc_sublet_booking_instances','pdc_qc_operation_completions_379','pdc_pmb_stoppage_receipts_422',
    'pdc_email_monitor_current_head_compatibility_controls_766','pdc_email_monitor_pilot','pdc_email_monitor_status',
    'pdc_qc_salesperson_update_outbox_399','pdc_rft_transport_email_outbox_734','pdc_sublet_email_update_receipts',
    'pdc_historical_provider_observations_778','pdc_historical_reconciliation_778_receipts');
  v_trigger_hash:=encode(extensions.digest(convert_to(v_trigger_text,'UTF8'),'sha256'),'hex');
  IF v_trigger_hash<>'ff68e5580c8a77701eb5f92ef6a0b6ad99a44f0036185e60900a4292775870f1' THEN RAISE EXCEPTION 'PDC_782_TRIGGER_CONTRACT_DRIFT' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_historical_job_card_attachments_782(
  manifest_sha256 text NOT NULL CHECK(manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'),
  provider_uid text NOT NULL CHECK(provider_uid~'^1:[1-9][0-9]{0,5}$' AND provider_uid<>'1:197'),
  parent_source_hash text NOT NULL CHECK(parent_source_hash~'^[a-f0-9]{64}$'),
  attachment_ordinal integer NOT NULL CHECK(attachment_ordinal BETWEEN 1 AND 25),
  attachment_kind text NOT NULL CHECK(attachment_kind='job_card'),
  attachment_hash text NOT NULL CHECK(attachment_hash~'^[a-f0-9]{64}$'),
  content_type text NOT NULL CHECK(content_type='application/pdf'),
  filename text NOT NULL CHECK(length(filename) BETWEEN 1 AND 180),
  size_bytes bigint NOT NULL CHECK(size_bytes BETWEEN 1 AND 10485760),
  extraction_hash text NOT NULL CHECK(extraction_hash~'^[a-f0-9]{64}$'),
  stock_number text NOT NULL CHECK(stock_number<>'13056899' AND public.is_real_vehicle_stock_number(stock_number)),
  job_card_number text NOT NULL CHECK(length(job_card_number) BETWEEN 1 AND 80),
  PRIMARY KEY(provider_uid,parent_source_hash,attachment_ordinal),
  UNIQUE(provider_uid,parent_source_hash,attachment_hash)
);
ALTER TABLE public.pdc_historical_job_card_attachments_782 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_historical_job_card_attachments_782 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_historical_job_card_attachments_782 FROM public,anon,authenticated,service_role,pdc_email_monitor;
INSERT INTO public.pdc_historical_job_card_attachments_782(manifest_sha256,provider_uid,parent_source_hash,attachment_ordinal,attachment_kind,attachment_hash,content_type,filename,size_bytes,extraction_hash,stock_number,job_card_number) VALUES
('aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018','1:22','3294df7294ab0682cd13f32526c075a31aeb81034c976a6588b99b8d09cb3506',4,'job_card','ae17dd135b7ff8426f796e9ffef60993434264961c0a84661c7dcd99d9483275','application/pdf','J139125200_RepairOrder.pdf',107401,'e6c23878f9ada7b5a44226076c11c4c6ff93cbfbed170039b1fab5e006907e2a','13047257','J139125200'),
('aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018','1:23','392c1c25de67254b809c9aed6a40b74c60f7917912d4f722df57c253876dedec','3','job_card','c728d22403f21a9f40e079ec75e935efd2f73fc7fecf6f5ecee9b70255e594e3','application/pdf','J139125202_RepairOrder.pdf',114170,'20fee4e65a32d4ffb1c02f724ef0c2c0fa224c2356f59e440400d1968f48c205','13047384','J139125202'),
('aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018','1:134','7b5efbc4b51369208b986cfa29f541c6191e18a7749d810b9e61756487faf6d8','2','job_card','135af46d804838f37371c8d261b39f9e1f58f8f9c4bfbdc97d8e106d46872c87','application/pdf','J139125240_RepairOrder.pdf',106406,'1ae8b1b1b4337b34f1057c390f763e7a5ed6a6b44390db57a736f554a1b4dd71','13047383','J139125240');
CREATE FUNCTION public.pdc_historical_job_card_attachments_immutable_782() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_782_JOBCARD_EVIDENCE_IMMUTABLE' USING errcode='55000'; END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_historical_job_card_attachments_immutable_782() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_historical_job_card_attachments_immutable_782 BEFORE UPDATE OR DELETE ON public.pdc_historical_job_card_attachments_782 FOR EACH ROW EXECUTE FUNCTION public.pdc_historical_job_card_attachments_immutable_782();

CREATE FUNCTION public.pdc_historical_782_boundary_snapshot() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
BEGIN
 RETURN jsonb_build_object(
  'vehicle_parts_updates',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.vehicle_parts_updates x),'')),
  'workshop_bookings',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.workshop_bookings x),'')),
  'workshop_booking_assignments',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.workshop_booking_assignments x),'')),
  'pdc_sublet_bookings',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_sublet_bookings x),'')),
  'pdc_sublet_booking_instances',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_sublet_booking_instances x),'')),
  'pdc_qc_operation_completions_379',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_qc_operation_completions_379 x),'')),
  'pdc_pmb_stoppage_receipts_422',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_pmb_stoppage_receipts_422 x),'')),
  'monitored_mailboxes',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.monitored_mailboxes x),'')),
  'monitor_controls',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_email_monitor_current_head_compatibility_controls_766 x),'')),
  'monitor_pilot',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_email_monitor_pilot x),'')),
  'monitor_status',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_email_monitor_status x),'')),
  'qc_salesperson_outbox',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_qc_salesperson_update_outbox_399 x),'')),
  'rft_transport_outbox',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_rft_transport_email_outbox_734 x),'')),
  'sublet_email_receipts',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_sublet_email_update_receipts x),''))
 );
END $snapshot$;
REVOKE ALL ON FUNCTION public.pdc_historical_782_boundary_snapshot() FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.pdc_historical_782_unrelated_snapshot(p_exclude_vehicle uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
BEGIN
 RETURN jsonb_build_object(
  'vehicles',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.vehicles x where p_exclude_vehicle is null or x.id<>p_exclude_vehicle),'')),
  'vehicle_work_items',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.vehicle_work_items x where p_exclude_vehicle is null or x.vehicle_id<>p_exclude_vehicle),'')),
  'operation_lines',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.pdc_authenticated_email_operation_lines x where p_exclude_vehicle is null or x.vehicle_id<>p_exclude_vehicle),'')),
  'workshop_adjustments',md5(coalesce((select string_agg(to_jsonb(x)::text,'|' order by to_jsonb(x)::text) from public.vehicle_workshop_line_adjustments x where p_exclude_vehicle is null or x.vehicle_id<>p_exclude_vehicle),''))
 );
END $snapshot$;
REVOKE ALL ON FUNCTION public.pdc_historical_782_unrelated_snapshot(uuid) FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778(p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
SET statement_timeout='300s'
AS $body$
DECLARE
 v_actor uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_request jsonb:=coalesce(p_request,'null'::jsonb); v_authentication jsonb:=coalesce(v_request->'authentication','null'::jsonb);
 v_manifest text:=lower(btrim(coalesce(v_request->>'manifest_sha256',''))); v_uid text:=btrim(coalesce(v_request->>'provider_uid',''));
 v_parent text:=lower(btrim(coalesce(v_request->>'parent_source_hash',''))); v_sender text:=lower(btrim(coalesce(v_request->>'sender_email','')));
 v_stock text:=public.normalize_vehicle_stock_number(v_request->>'stock_number'); v_items jsonb:=coalesce(v_request->'attachment_manifest','null'::jsonb);
 v_children jsonb:=coalesce(v_request->'job_card_children','null'::jsonb); v_source jsonb:=coalesce(v_request->'source_metadata','null'::jsonb);
 v_authz public.pdc_historical_reconciliation_writer_authorizations_773%rowtype; v_existing public.pdc_historical_reconciliation_778_receipts%rowtype;
 v_intake public.ai_email_intake%rowtype; v_attachment public.ai_email_attachments%rowtype; v_child_receipt public.pdc_jobcard_attachment_import_receipts%rowtype; v_vehicle public.vehicles%rowtype;
 v_enqueue jsonb; v_parent_result jsonb; v_child_result jsonb; v_child_results jsonb:='[]'::jsonb; v_response jsonb;
 v_runtime jsonb; v_manifest_canonical jsonb; v_manifest_hash text; v_request_hash text; v_observation_sha text; v_extraction_hash text;
 v_child jsonb; v_item jsonb; v_intake_id uuid; v_attachment_id uuid; v_receipt_id uuid:=gen_random_uuid(); v_known_vehicle_id uuid; v_known_location text;
 v_boundary_before jsonb; v_boundary_after jsonb; v_related_before jsonb; v_related_after jsonb; v_authz_count integer; v_child_expected integer; v_child_seen integer:=0; v_attachment_count integer;
 v_job_card_count integer:=0; v_sibling_count integer:=0; v_operation_count integer; v_actual_operation_count integer; v_booking_created boolean:=false; v_completion_created boolean:=false; v_location_scheduled boolean:=false; v_parts_changed boolean:=false; v_status_changed boolean:=false;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_actor<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR v_actor_email<>'sales@broometoyota.com.au'
    OR NOT public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1')
    OR jsonb_typeof(v_request) IS DISTINCT FROM 'object'
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_request) k) IS DISTINCT FROM ARRAY[
      'action_type','attachment_manifest','authentication','evidence_hash','gateway_instance_id','job_card_children',
      'manifest_high_water_uid','manifest_sha256','manifest_uid_count','manifest_uidvalidity','observations','parent_source_hash',
      'provider_uid','release_manifest_sha256','release_name','release_source_sha','sender_email','source_metadata','stock_number','subject','summary']::text[] THEN
   RETURN jsonb_build_object('ok',false,'code','unauthorized');
 END IF;
 IF v_request->>'gateway_instance_id' IS DISTINCT FROM 'pdc-monitor-staging-sales-uid509-v1'
    OR v_request->>'release_name' IS DISTINCT FROM 'pdc-monitor-staging-m502-2026.08.44'
    OR lower(v_request->>'release_source_sha') IS DISTINCT FROM 'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
    OR lower(v_request->>'release_manifest_sha256') IS DISTINCT FROM 'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
    OR v_request->>'manifest_uidvalidity' IS DISTINCT FROM '1' OR v_request->>'manifest_high_water_uid' IS DISTINCT FROM '685' OR v_request->>'manifest_uid_count' IS DISTINCT FROM '669' THEN
   RETURN jsonb_build_object('ok',false,'code','historical_manifest_or_runtime_binding_mismatch');
 END IF;
 v_runtime:=public.verify_pdc_monitor_runtime_binding_authenticated_766('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227');
 IF v_runtime->>'ok' IS DISTINCT FROM 'true' OR v_runtime->>'actor_id' IS DISTINCT FROM v_actor::text OR v_runtime->>'actor_email' IS DISTINCT FROM v_actor_email OR v_runtime->>'task_enabled' IS DISTINCT FROM 'false' OR v_runtime->>'mailbox_contacted' IS DISTINCT FROM 'false' OR v_runtime->>'production_writes' IS DISTINCT FROM 'false' THEN
   RETURN jsonb_build_object('ok',false,'code','historical_runtime_binding_unavailable');
 END IF;
 IF v_manifest IS DISTINCT FROM 'aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
    OR v_uid!~'^1:[1-9][0-9]{0,5}$' OR v_uid='1:197' OR v_parent!~'^[a-f0-9]{64}$'
    OR v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
    OR jsonb_typeof(v_authentication) IS DISTINCT FROM 'object' OR jsonb_typeof(v_items) IS DISTINCT FROM 'array' OR jsonb_array_length(v_items) NOT BETWEEN 1 AND 25
    OR jsonb_typeof(v_children) IS DISTINCT FROM 'array' OR jsonb_array_length(v_children)>25 OR jsonb_typeof(v_source) IS DISTINCT FROM 'object'
    OR v_request->>'evidence_hash'!~'^[a-f0-9]{64}$' OR length(coalesce(v_request->>'subject','')) NOT BETWEEN 1 AND 300
    OR length(coalesce(v_request->>'summary','')) NOT BETWEEN 5 AND 2000 OR v_request->>'action_type' NOT IN ('board_activate_only','review_only') THEN
   RETURN jsonb_build_object('ok',false,'code','invalid_input');
 END IF;
 IF v_stock='13056899' OR NOT public.is_real_vehicle_stock_number(v_stock) THEN RETURN jsonb_build_object('ok',false,'code','historical_reference_stock_excluded'); END IF;
 IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_source) k) IS DISTINCT FROM ARRAY['attachment_names','graph_message_id','internet_message_id','parsed_text','provider_authserv_id','raw_body','received_at','recipient_mailbox','sender_name','uid','uidvalidity']::text[]
    OR v_source->>'uidvalidity' IS DISTINCT FROM '1' OR v_source->>'uid' IS DISTINCT FROM substring(v_uid FROM '^1:([0-9]+)$')
    OR v_source->>'provider_authserv_id' IS DISTINCT FROM 'mx.google.com' OR v_source->>'received_at' IS NULL OR lower(v_source->>'recipient_mailbox') IS DISTINCT FROM 'pmbcontroller@gmail.com'
    OR v_source->'attachment_names' IS DISTINCT FROM (SELECT jsonb_agg(m->>'filename' ORDER BY ordinality) FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality)) THEN
   RETURN jsonb_build_object('ok',false,'code','invalid_source_metadata');
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality) WHERE jsonb_typeof(x.m) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x.m) k) IS DISTINCT FROM ARRAY['attachment_kind','content_type','filename','ordinal','sha256','size']::text[] OR x.m->>'attachment_kind' NOT IN ('job_card','ambiguous_job_card','non_job_card_sibling') OR x.m->>'content_type' IS NULL OR x.m->>'filename' IS NULL OR x.m->>'sha256'!~'^[a-f0-9]{64}$' OR x.m->>'ordinal'!~'^[1-9][0-9]{0,2}$' OR (x.m->>'ordinal')::integer<>x.ordinality OR x.m->>'size'!~'^[1-9][0-9]{0,7}$') THEN
   RETURN jsonb_build_object('ok',false,'code','invalid_attachment_metadata');
 END IF;
 SELECT count(*) INTO v_authz_count FROM public.pdc_historical_reconciliation_writer_authorizations_773 e
  WHERE e.active AND e.manifest_sha256=v_manifest AND e.provider_uid=v_uid AND e.parent_source_hash=v_parent AND e.sender_email=v_sender
    AND e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex') AND e.provider_authentication IS NOT DISTINCT FROM v_authentication
    AND public.normalize_vehicle_stock_number(e.stock_number)=v_stock AND e.authorized_actor_id=v_actor AND e.authorized_actor_email=v_actor_email AND e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
    AND public.pdc_historical_writer_authorized_773(v_parent,v_uid,v_sender,v_authentication,v_stock);
 IF v_authz_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','pdc_778_exact_authorization_failed'); END IF;
 SELECT * INTO v_authz FROM public.pdc_historical_reconciliation_writer_authorizations_773 e
  WHERE e.active AND e.manifest_sha256=v_manifest AND e.provider_uid=v_uid AND e.parent_source_hash=v_parent AND e.sender_email=v_sender AND e.authorized_actor_id=v_actor AND e.authorized_actor_email=v_actor_email AND e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1';
 IF clock_timestamp()>v_authz.authorized_at+interval '24 hours' THEN RETURN jsonb_build_object('ok',false,'code','historical_authorization_expired'); END IF;
 SELECT jsonb_agg(jsonb_build_object('content_type',m->>'content_type','filename',m->>'filename','sha256',lower(m->>'sha256'),'size',(m->>'size')::bigint) ORDER BY ordinality) INTO v_manifest_canonical FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality);
 v_manifest_hash:=encode(extensions.digest(convert_to(v_manifest_canonical::text,'UTF8'),'sha256'),'hex');
 IF v_manifest_hash<>v_authz.attachment_manifest_sha256 OR v_manifest_canonical IS DISTINCT FROM v_authz.attachment_manifest OR jsonb_array_length(v_items)<>v_authz.attachment_count THEN RETURN jsonb_build_object('ok',false,'code','historical_attachment_manifest_mismatch'); END IF;
 v_request_hash:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-778:'||v_uid||':'||v_parent,0));
 SELECT * INTO v_existing FROM public.pdc_historical_reconciliation_778_receipts WHERE actor_id=v_actor AND provider_uid=v_uid AND parent_source_hash=v_parent;
 IF FOUND THEN IF v_existing.request_sha256<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','historical_replay_conflict'); END IF; RETURN v_existing.canonical_response; END IF;
 SELECT count(*),max(v.id),max(v.current_location) INTO v_attachment_count,v_known_vehicle_id,v_known_location FROM public.vehicles v WHERE v.stock_number_normalized=v_stock AND v.deleted_at IS NULL;
 IF v_attachment_count>1 THEN RAISE EXCEPTION 'PDC_782_IDENTITY_CONFLICT' USING errcode='P0001'; END IF;
 v_boundary_before:=public.pdc_historical_782_boundary_snapshot(); v_related_before:=public.pdc_historical_782_unrelated_snapshot(v_known_vehicle_id);
 v_enqueue:=public.enqueue_pdc_email_intake(jsonb_build_object('graph_message_id',v_source->>'graph_message_id','internet_message_id',v_source->>'internet_message_id','provider_uid',v_uid,'source_hash',v_parent,'subject',v_request->>'subject','sender_email',v_sender,'sender_name',v_source->>'sender_name','received_at',v_source->>'received_at','raw_body',v_source->>'raw_body','parsed_text',v_source->>'parsed_text','attachment_names',v_source->'attachment_names','recipient_mailbox',lower(v_source->>'recipient_mailbox'),'provider_authserv_id',v_source->>'provider_authserv_id','provider_authentication',v_authentication,'stock_number',v_stock),(SELECT jsonb_agg(jsonb_build_object('graph_attachment_id',v_uid||':historical-782-'||lpad(x.ordinality::text,3,'0')||'-'||lower(x.m->>'sha256'),'file_name',x.m->>'filename','content_type',x.m->>'content_type','size_bytes',(x.m->>'size')::bigint,'source_hash',lower(x.m->>'sha256'),'storage_path','pdc-email-intake-private/historical-782/'||lpad(x.ordinality::text,3,'0')||'-'||lower(x.m->>'sha256'),'validation_status','verified') ORDER BY x.ordinality) FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality)));
 IF NOT coalesce((v_enqueue->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_782_ENQUEUE_FAILED' USING errcode='P0001'; END IF;
 IF v_enqueue->>'intake_id' !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_782_ENQUEUE_ID_FAILED' USING errcode='55000'; END IF;
 v_intake_id:=(v_enqueue->>'intake_id')::uuid;
 SELECT * INTO v_intake FROM public.ai_email_intake WHERE id=v_intake_id FOR UPDATE;
 IF NOT FOUND OR lower(coalesce(v_intake.source_hash,''))<>v_parent OR v_intake.provider_uid<>v_uid OR lower(coalesce(v_intake.sender_email,''))<>v_sender OR v_intake.received_at IS DISTINCT FROM (v_source->>'received_at')::timestamptz OR v_intake.internet_message_id IS DISTINCT FROM v_source->>'internet_message_id' OR v_intake.graph_message_id IS DISTINCT FROM v_source->>'graph_message_id' OR lower(coalesce(v_intake.recipient_mailbox,''))<>lower(v_source->>'recipient_mailbox') OR v_intake.provider_authserv_id IS DISTINCT FROM v_source->>'provider_authserv_id' OR v_intake.provider_authentication IS DISTINCT FROM v_authentication THEN RAISE EXCEPTION 'PDC_782_INTAKE_BINDING_FAILED' USING errcode='P0001'; END IF;
 IF v_intake.duplicate_of IS NOT NULL OR v_intake.status::text IN ('duplicate_detected','failed','ignored','vehicle_created','vehicle_updated') THEN RAISE EXCEPTION 'PDC_782_OLD_MAIL_COMPLETED' USING errcode='P0001'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
   SELECT count(*) INTO v_attachment_count FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND lower(a.source_hash)=lower(v_item->>'sha256') AND lower(a.file_name)=lower(v_item->>'filename') AND lower(coalesce(a.content_type,''))=lower(v_item->>'content_type') AND a.size_bytes=(v_item->>'size')::bigint AND a.graph_attachment_id=v_uid||':historical-782-'||lpad((v_item->>'ordinal')::integer::text,3,'0')||'-'||lower(v_item->>'sha256');
   IF v_attachment_count<>1 THEN RAISE EXCEPTION 'PDC_782_ATTACHMENT_BINDING_FAILED' USING errcode='P0001'; END IF;
   SELECT * INTO v_attachment FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=v_uid||':historical-782-'||lpad((v_item->>'ordinal')::integer::text,3,'0')||'-'||lower(v_item->>'sha256');
   v_observation_sha:=encode(extensions.digest(convert_to(jsonb_build_object('contract_version','782.1','authorization_id',v_authz.authorization_id,'intake_id',v_intake_id,'attachment_id',v_attachment.id,'provider_uid',v_uid,'parent_source_hash',v_parent,'attachment_source_hash',lower(v_item->>'sha256'),'attachment_ordinal',(v_item->>'ordinal')::integer,'attachment_kind',v_item->>'attachment_kind','provider_message_id',v_source->>'internet_message_id','provider_authserv_id',v_source->>'provider_authserv_id','authentication',v_authentication)::text,'UTF8'),'sha256'),'hex');
   INSERT INTO public.pdc_historical_provider_observations_778(contract_version,authorization_id,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,intake_id,attachment_id,attachment_source_hash,provider_message_id,provider_authserv_id,authentication,request_sha256) VALUES('782.1',v_authz.authorization_id,v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_sender,v_stock,v_intake_id,v_attachment.id,lower(v_item->>'sha256'),v_source->>'internet_message_id',v_source->>'provider_authserv_id',v_authentication,v_observation_sha) ON CONFLICT(intake_id,attachment_id) DO NOTHING;
   IF NOT EXISTS(SELECT 1 FROM public.pdc_historical_provider_observations_778 h WHERE h.intake_id=v_intake_id AND h.attachment_id=v_attachment.id AND h.contract_version='782.1' AND h.authorization_id=v_authz.authorization_id AND h.actor_id=v_actor AND h.actor_email=v_actor_email AND h.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND h.manifest_sha256=v_manifest AND h.provider_uid=v_uid AND h.parent_source_hash=v_parent AND h.sender_email=v_sender AND h.stock_number=v_stock AND h.attachment_source_hash=lower(v_item->>'sha256') AND h.provider_message_id=v_source->>'internet_message_id' AND h.provider_authserv_id=v_source->>'provider_authserv_id' AND h.authentication IS NOT DISTINCT FROM v_authentication AND h.request_sha256=v_request_hash) THEN RAISE EXCEPTION 'PDC_782_OBSERVATION_REPLAY_CONFLICT' USING errcode='55000'; END IF;
   IF v_item->>'attachment_kind'='job_card' THEN v_job_card_count:=v_job_card_count+1; ELSE v_sibling_count:=v_sibling_count+1; END IF;
 END LOOP;
 v_parent_result:=public.submit_pdc_ai_intake_observation_pre135(v_parent, v_request->>'evidence_hash',v_uid,v_sender,v_authentication,(v_source->>'received_at')::timestamptz,v_request->>'subject',v_request->>'action_type',v_stock,v_request->>'summary',v_request->'observations');
 IF NOT coalesce((v_parent_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_782_PARENT_OBSERVATION_FAILED' USING errcode='P0001'; END IF;
 SELECT count(*) INTO v_child_expected FROM jsonb_array_elements(v_items) m WHERE m->>'attachment_kind' IN ('job_card','ambiguous_job_card');
 IF jsonb_array_length(v_children)<>v_child_expected THEN RAISE EXCEPTION 'PDC_782_CHILD_CARDINALITY_FAILED' USING errcode='P0001'; END IF;
 FOR v_child IN SELECT value FROM jsonb_array_elements(v_children) LOOP
   v_child_seen:=v_child_seen+1;
   IF jsonb_typeof(v_child) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_child) k) IS DISTINCT FROM ARRAY['attachment_hash','attachment_kind','attachment_ordinal','extraction','extraction_hash']::text[] OR v_child->>'attachment_hash'!~'^[a-f0-9]{64}$' OR v_child->>'attachment_ordinal'!~'^[1-9][0-9]{0,2}$' OR v_child->>'extraction_hash'!~'^[a-f0-9]{64}$' OR jsonb_typeof(v_child->'extraction') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PDC_782_CHILD_INVALID' USING errcode='P0001'; END IF;
   SELECT m INTO v_item FROM jsonb_array_elements(v_items) m WHERE (m->>'ordinal')::integer=(v_child->>'attachment_ordinal')::integer;
   IF NOT FOUND OR lower(v_item->>'sha256') IS DISTINCT FROM lower(v_child->>'attachment_hash') OR v_child->>'attachment_kind' IS DISTINCT FROM v_item->>'attachment_kind' THEN RAISE EXCEPTION 'PDC_782_CHILD_OCCURRENCE_MISMATCH' USING errcode='P0001'; END IF;
   IF v_child->>'attachment_kind'='ambiguous_job_card' THEN
     IF NOT(coalesce(jsonb_array_length(v_child->'extraction'->'email_vehicle'->'stock_numbers'),0)>1 OR coalesce(jsonb_array_length(v_child->'extraction'->'email_vehicle'->'vins'),0)>1 OR coalesce(jsonb_array_length(v_child->'extraction'->'email_vehicle'->'conflicts'),0)>0 OR coalesce(jsonb_array_length(v_child->'extraction'->'job_cards'),0)<>1) THEN RAISE EXCEPTION 'PDC_782_AMBIGUITY_NOT_PROVEN' USING errcode='P0001'; END IF;
     v_child_results:=v_child_results||jsonb_build_array(jsonb_build_object('attachment_ordinal',(v_child->>'attachment_ordinal')::integer,'attachment_hash',v_child->>'attachment_hash','result',jsonb_build_object('ok',false,'code','historical_child_ambiguous')));
     CONTINUE;
   END IF;
   SELECT * INTO v_authz FROM public.pdc_historical_reconciliation_writer_authorizations_773 e WHERE e.authorization_id=v_authz.authorization_id;
   IF NOT EXISTS(SELECT 1 FROM public.pdc_historical_job_card_attachments_782 j WHERE j.manifest_sha256=v_manifest AND j.provider_uid=v_uid AND j.parent_source_hash=v_parent AND j.attachment_ordinal=(v_child->>'attachment_ordinal')::integer AND j.attachment_kind='job_card' AND j.attachment_hash=lower(v_child->>'attachment_hash') AND lower(j.content_type)=lower(v_item->>'content_type') AND lower(j.filename)=lower(v_item->>'filename') AND j.size_bytes=(v_item->>'size')::bigint AND j.stock_number=v_stock AND lower(j.job_card_number)=lower(v_child->'extraction'->'email_vehicle'->>'job_card_number') AND j.extraction_hash=lower(v_child->>'extraction_hash')) THEN RAISE EXCEPTION 'PDC_782_JOB_CARD_KIND_MISMATCH' USING errcode='55000'; END IF;
   v_extraction_hash:=encode(extensions.digest(convert_to((v_child->'extraction')::text,'UTF8'),'sha256'),'hex');
   IF lower(v_child->>'extraction_hash') IS DISTINCT FROM v_extraction_hash THEN RAISE EXCEPTION 'PDC_782_EXTRACTION_HASH_FAILED' USING errcode='P0001'; END IF;
   SELECT count(*) INTO v_attachment_count FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=v_uid||':historical-782-'||lpad((v_child->>'attachment_ordinal')::integer::text,3,'0')||'-'||lower(v_child->>'attachment_hash') AND lower(a.source_hash)=lower(v_child->>'attachment_hash') AND lower(a.file_name)=lower(v_item->>'filename') AND lower(coalesce(a.content_type,''))=lower(v_item->>'content_type') AND a.size_bytes=(v_item->>'size')::bigint;
   IF v_attachment_count<>1 THEN RAISE EXCEPTION 'PDC_782_CHILD_ATTACHMENT_NONUNIQUE' USING errcode='P0001'; END IF;
   SELECT * INTO v_attachment FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=v_uid||':historical-782-'||lpad((v_child->>'attachment_ordinal')::integer::text,3,'0')||'-'||lower(v_child->>'attachment_hash');
   v_child_result:=public.import_pdc_jobcard_attachment_canonical(v_intake_id,v_attachment.id,v_parent,lower(v_child->>'attachment_hash'),v_authentication,v_child->'extraction'->'email_vehicle',v_child->'extraction'->'required_work',v_child->'extraction'->'operation_lines');
   IF NOT coalesce((v_child_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_782_CHILD_IMPORT_FAILED' USING errcode='P0001'; END IF;
   SELECT count(*) INTO v_attachment_count FROM public.pdc_jobcard_attachment_import_receipts r WHERE r.intake_id=v_intake_id AND r.attachment_id=v_attachment.id;
   IF v_attachment_count<>1 THEN RAISE EXCEPTION 'PDC_782_CHILD_RECEIPT_FAILED' USING errcode='P0001'; END IF;
   SELECT * INTO v_child_receipt FROM public.pdc_jobcard_attachment_import_receipts r WHERE r.intake_id=v_intake_id AND r.attachment_id=v_attachment.id;
   SELECT * INTO v_vehicle FROM public.vehicles v WHERE v.id=v_child_receipt.vehicle_id;
   IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state::text<>'active' OR v_vehicle.board_purged_at IS NOT NULL OR NOT coalesce(v_vehicle.visible_on_board,false) OR v_vehicle.stock_number_normalized<>v_stock OR upper(btrim(coalesce(v_vehicle.job_card_number,'')))<>upper(v_child->'extraction'->'email_vehicle'->>'job_card_number') THEN RAISE EXCEPTION 'PDC_782_AUTHORITATIVE_STATE_FAILED' USING errcode='P0001'; END IF;
   v_operation_count:=jsonb_array_length(v_child->'extraction'->'operation_lines');
   SELECT count(*) INTO v_actual_operation_count FROM public.pdc_authenticated_email_operation_lines ol WHERE ol.vehicle_id=v_vehicle.id AND ol.source_hash=v_child_receipt.canonical_source_hash AND ol.source_uid=v_child_receipt.source_uid;
   IF v_actual_operation_count<>v_operation_count OR v_child_receipt.operation_count<>v_operation_count OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_child->'extraction'->'operation_lines') x WHERE NOT EXISTS(SELECT 1 FROM public.pdc_authenticated_email_operation_lines ol WHERE ol.vehicle_id=v_vehicle.id AND ol.source_hash=v_child_receipt.canonical_source_hash AND ol.source_uid=v_child_receipt.source_uid AND ol.operation_no=x->>'operation_no' AND ol.work_key=x->>'work_key' AND ol.description=x->>'description' AND ol.estimated_hours IS NOT DISTINCT FROM CASE WHEN jsonb_typeof(x->'estimated_hours')='number' THEN (x->>'estimated_hours')::numeric ELSE NULL END)) THEN RAISE EXCEPTION 'PDC_782_AUTHORITATIVE_STATE_FAILED' USING errcode='55000'; END IF;
   IF v_known_vehicle_id IS NOT NULL AND v_vehicle.current_location IS DISTINCT FROM v_known_location THEN RAISE EXCEPTION 'PDC_782_LOCATION_SIDE_EFFECT' USING errcode='55000'; END IF;
   v_child_results:=v_child_results||jsonb_build_array(jsonb_build_object('attachment_ordinal',(v_child->>'attachment_ordinal')::integer,'attachment_hash',v_child->>'attachment_hash','result',v_child_result,'authoritative_vehicle_id',v_vehicle.id,'authoritative_operation_count',v_actual_operation_count));
 END LOOP;
 v_boundary_after:=public.pdc_historical_782_boundary_snapshot(); v_related_after:=public.pdc_historical_782_unrelated_snapshot(v_vehicle.id);
 v_booking_created:=v_boundary_after->>'workshop_bookings' IS DISTINCT FROM v_boundary_before->>'workshop_bookings' OR v_boundary_after->>'workshop_booking_assignments' IS DISTINCT FROM v_boundary_before->>'workshop_booking_assignments';
 v_completion_created:=v_boundary_after->>'pdc_qc_operation_completions_379' IS DISTINCT FROM v_boundary_before->>'pdc_qc_operation_completions_379';
 v_location_scheduled:=v_booking_created;
 v_parts_changed:=v_boundary_after->>'vehicle_parts_updates' IS DISTINCT FROM v_boundary_before->>'vehicle_parts_updates';
 v_status_changed:=v_related_after->>'vehicles' IS DISTINCT FROM v_related_before->>'vehicles';
 IF v_parts_changed OR v_booking_created OR v_completion_created OR v_location_scheduled THEN RAISE EXCEPTION 'PDC_782_PROTECTED_BOUNDARY_DRIFT' USING errcode='55000'; END IF;
 IF v_status_changed OR v_related_after IS DISTINCT FROM v_related_before THEN RAISE EXCEPTION 'PDC_782_UNRELATED_STATE_DRIFT' USING errcode='55000'; END IF;
 v_response:=jsonb_build_object('ok',true,'code','historical_reconciliation_782_receipt','data',jsonb_build_object('receipt_id',v_receipt_id,'contract_version','782.1','manifest_sha256',v_manifest,'provider_uid',v_uid,'parent_source_hash',v_parent,'sender_email',v_sender,'stock_number',v_stock,'intake_id',v_intake_id,'attachment_count',jsonb_array_length(v_items),'job_card_count',v_job_card_count,'sibling_count',v_sibling_count,'attachment_receipts',v_child_results,'parent_observation',v_parent_result,'authoritative_state',jsonb_build_object('vehicle_id',v_vehicle.id,'lifecycle_state',v_vehicle.lifecycle_state,'current_location',v_vehicle.current_location,'operation_count',coalesce(v_actual_operation_count,0),'booking_count',0,'completion_count',0,'parts_changed',v_parts_changed),'booking_created',v_booking_created,'completion_created',v_completion_created,'location_scheduled',v_location_scheduled,'parts_changed',v_parts_changed,'status_changed',v_status_changed,'no_booking',NOT v_booking_created,'no_completion',NOT v_completion_created,'no_location_mutation',NOT v_location_scheduled));
 INSERT INTO public.pdc_historical_reconciliation_778_receipts(receipt_id,contract_version,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,request_sha256,intake_id,attachment_count,job_card_count,sibling_count,request_evidence,canonical_response) VALUES(v_receipt_id,'782.1',v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_sender,v_stock,v_request_hash,v_intake_id,jsonb_array_length(v_items),v_job_card_count,v_sibling_count,v_request,v_response);
 INSERT INTO public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata) VALUES('insert','pdc_historical_reconciliation_778_receipts',v_actor,v_actor_email,NULL,v_response->'data',jsonb_build_object('contract','782.1','manifest_sha256',v_manifest,'protected_boundary_before',v_boundary_before,'protected_boundary_after',v_boundary_after,'unrelated_before',v_related_before,'unrelated_after',v_related_after));
 RETURN v_response;
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('ok',false,'code','historical_reconciliation_782_atomic_rollback');
END
$body$;
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) TO authenticated;

DO $verify$
DECLARE d text; o text; c text; a text; s boolean;
BEGIN
 SELECT pg_get_functiondef('public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure),pg_get_userbyid(p.proowner),coalesce(array_to_string(p.proconfig,','),''),p.prosecdef INTO d,o,c,s FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure;
 IF o IS DISTINCT FROM 'postgres' OR s IS DISTINCT FROM true OR c IS DISTINCT FROM 'search_path=pg_catalog, public, auth, extensions,statement_timeout=300s'
    OR position('PDC_782_PROTECTED_BOUNDARY_DRIFT' in d)=0 OR position('PDC_782_AUTHORITATIVE_STATE_FAILED' in d)=0 OR position('PDC_782_JOB_CARD_KIND_MISMATCH' in d)=0
    OR position('PDC_782_CHILD_OCCURRENCE_MISMATCH' in d)=0 OR position('pdc_historical_782_boundary_snapshot' in d)=0
    OR position('booking_created' in d)=0 OR position('completion_created' in d)=0 OR position('location_scheduled' in d)=0 OR position('parts_changed' in d)=0
    OR NOT has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
    OR has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
    OR has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_782_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.pdc_historical_job_card_attachments_782'::regclass AND relrowsecurity AND relforcerowsecurity)
    OR has_table_privilege('anon','public.pdc_historical_job_card_attachments_782','select') THEN RAISE EXCEPTION 'PDC_782_BINDING_TABLE_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$verify$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830173000','782_historical_reconciliation_current_head_security_successor',ARRAY[
 'Lock and equality-bind the exact live 20260830172000/778 predecessor serialization before replacement',
 'Pin delegated child, parent, enqueue and authorization bodies by owner, SECURITY DEFINER, config, ACL, body hash, callee marker and protected trigger fingerprint',
 'Bind every frozen Job Card by immutable parent/provider/ordinal/kind/hash/MIME/filename/size/extraction/job-card/Stock evidence and reject sibling substitution',
 'Atomically enqueue, observe, parent-process and canonical-child-process; reread authoritative vehicle/operations and protected boundaries before deriving flags or writing the immutable receipt',
 'Preserve frozen manifest/runtime/sender/Stock/UID/24-hour/replay/old-mail/RLS/authenticated-only/Production/outbound/task boundaries'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
