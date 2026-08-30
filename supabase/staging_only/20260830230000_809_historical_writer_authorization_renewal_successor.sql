-- STAGING ONLY 809: append-only renewal history for five exact frozen proposal notices.
BEGIN;
SET LOCAL lock_timeout='15s'; SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-809-historical-authorization-renewal',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v_head text; v text; owner_name text; secdef boolean; acl text;
BEGIN
 SELECT (version,name)::text INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 SELECT p.proowner::regrole::text,p.prosecdef,p.proacl::text,p.prosrc INTO owner_name,secdef,acl,v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_793_proposal_review_successor(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_head IS DISTINCT FROM '(20260830225000,808_historical_writer_auth_contained_successor)' OR owner_name IS DISTINCT FROM 'postgres' OR NOT secdef OR acl IS DISTINCT FROM '{postgres=X/postgres}' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'c24bfdd7028cb0989760428dd2893bdef83fdd7dddfcc227263ccb26bab2d997' OR (SELECT count(*) FROM public.pdc_historical_reconciliation_writer_authorizations_773 WHERE active) IS DISTINCT FROM 15 OR (SELECT count(*) FROM public.pdc_ai_intake_proposals WHERE status::text='pending') IS DISTINCT FROM 15 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active) IS DISTINCT FROM 0 OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) IS DISTINCT FROM 1 OR EXISTS(SELECT 1 FROM public.pdc_historical_reconciliation_writer_authorizations_773 WHERE provider_uid IN ('1:21','1:22','1:23','1:26','1:40','1:57','1:85','1:93','1:95','1:96')) IS NOT TRUE THEN RAISE EXCEPTION 'PDC_809_CURRENT_HEAD_OR_PROPOSAL_PRESTATE_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_historical_reconciliation_writer_authorizations_809(
 renewal_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), supersedes_authorization_id uuid NOT NULL REFERENCES public.pdc_historical_reconciliation_writer_authorizations_773(authorization_id) ON DELETE RESTRICT,
 manifest_sha256 text NOT NULL CHECK(manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'), provider_uid text NOT NULL CHECK(provider_uid~'^1:[1-9][0-9]{0,5}$' AND provider_uid NOT IN ('1:21','1:22','1:23','1:26','1:40','1:57','1:85','1:93','1:95','1:96')), parent_source_hash text NOT NULL CHECK(parent_source_hash~'^[a-f0-9]{64}$'), evidence_hash text NOT NULL CHECK(evidence_hash~'^[a-f0-9]{64}$'), sender_email text NOT NULL CHECK(sender_email=lower(btrim(sender_email))), sender_sha256 text NOT NULL CHECK(sender_sha256=encode(extensions.digest(convert_to(sender_email,'UTF8'),'sha256'),'hex')), provider_authentication jsonb NOT NULL CHECK(jsonb_typeof(provider_authentication)='object'), stock_number text NOT NULL CHECK(stock_number<>'13056899' AND public.is_real_vehicle_stock_number(stock_number)), attachment_manifest jsonb NOT NULL CHECK(jsonb_typeof(attachment_manifest)='array' AND jsonb_array_length(attachment_manifest) BETWEEN 1 AND 25), attachment_manifest_sha256 text NOT NULL CHECK(attachment_manifest_sha256~'^[a-f0-9]{64}$'), attachment_count integer NOT NULL CHECK(attachment_count=jsonb_array_length(attachment_manifest) AND attachment_count BETWEEN 1 AND 25), authorized_actor_id uuid NOT NULL CHECK(authorized_actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'), authorized_actor_email text NOT NULL CHECK(authorized_actor_email='sales@broometoyota.com.au'), authorized_gateway_instance_id text NOT NULL CHECK(authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'), authorization_reason text NOT NULL CHECK(authorization_reason='frozen manifest direct/approved sender evidence'), renewal_reason text NOT NULL CHECK(renewal_reason='Craig-authorized STAGING renewal of expired exact frozen proposal-notice authorization'), active boolean NOT NULL DEFAULT true CHECK(active), authorized_at timestamptz NOT NULL DEFAULT clock_timestamp(), expires_at timestamptz NOT NULL CHECK(expires_at>authorized_at AND expires_at<=authorized_at+interval '24 hours')
);
ALTER TABLE public.pdc_historical_reconciliation_writer_authorizations_809 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_historical_reconciliation_writer_authorizations_809 FORCE ROW LEVEL SECURITY; REVOKE ALL ON TABLE public.pdc_historical_reconciliation_writer_authorizations_809 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE OR REPLACE FUNCTION public.pdc_historical_writer_authorizations_809_immutable() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $immutable$
BEGIN RAISE EXCEPTION 'PDC_809_WRITER_AUTHORIZATION_IMMUTABLE' USING errcode='55000'; END
$immutable$;
REVOKE ALL ON FUNCTION public.pdc_historical_writer_authorizations_809_immutable() FROM public,anon,authenticated,service_role,pdc_email_monitor; GRANT EXECUTE ON FUNCTION public.pdc_historical_writer_authorizations_809_immutable() TO postgres;
CREATE TRIGGER pdc_historical_writer_authorizations_809_immutable BEFORE UPDATE OR DELETE ON public.pdc_historical_reconciliation_writer_authorizations_809 FOR EACH ROW EXECUTE FUNCTION public.pdc_historical_writer_authorizations_809_immutable();
WITH renew(provider_uid,stock_number,evidence_hash,parent_source_hash) AS (VALUES
      ('1:133','13047164','868866bfebe0d8a924bd15ce151d472a8966a739ab8d733ff6d6a4f907a69f69','5bac1b23095f1d011d40f0b558793f4919c63e989b5f2f0040c2b312bf9ba0c8'),
      ('1:134','13047383','038180cf1bb30136dbd2d176f45dbb9c4c6cf730cff7a7ed6e59a32dd5f1ec7c','7b5efbc4b51369208b986cfa29f541c6191e18a7749d810b9e61756487faf6d8'),
      ('1:137','13047272','b0dfa4aaaefed0d71f878e8b69adf7459251f79795cff9809009b8418159abff','60fad201d61ec5f3618022fbe56e5ffad3f6f60e9f5cd2de14f552244360964b'),
      ('1:168','13049488','5df8e4c6ccf29f88eeaca96c8856b2653eff27390e9ca08c872343480358fa09','0778b8d186142868fedbdbe39c8e7c8584e133f0d52b4ad8a46a673fb311ecb1'),
      ('1:172','13044227','345ee4f9d9d2a7fa47376d8615e9f05086a5f9f65ce9fa6322df9f726e0dd56e','63049973879eed3c4529a7f51952f513b5f026f30693fa4fdc8c4e228e0ffc9a')
), inserted AS (INSERT INTO public.pdc_historical_reconciliation_writer_authorizations_809(supersedes_authorization_id,manifest_sha256,provider_uid,parent_source_hash,evidence_hash,sender_email,sender_sha256,provider_authentication,stock_number,attachment_manifest,attachment_manifest_sha256,attachment_count,authorized_actor_id,authorized_actor_email,authorized_gateway_instance_id,authorization_reason,renewal_reason,authorized_at,expires_at)
 SELECT e.authorization_id,e.manifest_sha256,e.provider_uid,e.parent_source_hash,r.evidence_hash,e.sender_email,e.sender_sha256,e.provider_authentication,e.stock_number,e.attachment_manifest,e.attachment_manifest_sha256,e.attachment_count,e.authorized_actor_id,e.authorized_actor_email,e.authorized_gateway_instance_id,e.authorization_reason,'Craig-authorized STAGING renewal of expired exact frozen proposal-notice authorization',clock_timestamp(),clock_timestamp()+interval '24 hours' FROM renew r JOIN public.pdc_historical_reconciliation_writer_authorizations_773 e ON e.provider_uid=r.provider_uid AND e.stock_number=r.stock_number AND e.parent_source_hash=r.parent_source_hash AND e.active WHERE NOT EXISTS(SELECT 1 FROM public.pdc_historical_reconciliation_writer_authorizations_809 s WHERE s.provider_uid=r.provider_uid AND s.evidence_hash=r.evidence_hash AND s.active AND s.expires_at>clock_timestamp()) RETURNING renewal_id) SELECT count(*) FROM inserted;
CREATE OR REPLACE FUNCTION public.pdc_historical_writer_authorization_809_resolve(p_manifest text,p_uid text,p_parent text,p_sender text,p_auth jsonb,p_stock text,p_evidence text)
RETURNS public.pdc_historical_reconciliation_writer_authorizations_773 LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','auth','extensions'
AS $resolve$
 SELECT e.authorization_id,e.manifest_sha256,e.provider_uid,e.parent_source_hash,e.sender_email,e.sender_sha256,e.provider_authentication,e.stock_number,e.attachment_manifest,e.attachment_manifest_sha256,e.attachment_count,e.authorized_actor_id,e.authorized_actor_email,e.authorized_gateway_instance_id,e.authorization_reason,e.active,s.authorized_at
 FROM public.pdc_historical_reconciliation_writer_authorizations_773 e JOIN public.pdc_historical_reconciliation_writer_authorizations_809 s ON s.supersedes_authorization_id=e.authorization_id
 WHERE s.active AND s.expires_at>clock_timestamp() AND s.manifest_sha256=p_manifest AND s.provider_uid=p_uid AND s.parent_source_hash=p_parent AND s.sender_email=p_sender AND s.evidence_hash=lower(btrim(coalesce(p_evidence,''))) AND s.sender_sha256=encode(extensions.digest(convert_to(p_sender,'UTF8'),'sha256'),'hex') AND s.provider_authentication IS NOT DISTINCT FROM p_auth AND public.normalize_vehicle_stock_number(s.stock_number)=public.normalize_vehicle_stock_number(p_stock) AND s.authorized_actor_id=auth.uid() AND s.authorized_actor_email=lower(btrim(auth.jwt()->>'email')) AND s.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND e.active AND e.manifest_sha256=p_manifest AND e.provider_uid=p_uid AND e.parent_source_hash=p_parent AND e.sender_email=p_sender AND e.provider_authentication IS NOT DISTINCT FROM p_auth AND public.normalize_vehicle_stock_number(e.stock_number)=public.normalize_vehicle_stock_number(p_stock) AND e.authorized_actor_id=auth.uid() AND e.authorized_actor_email=lower(btrim(auth.jwt()->>'email')) AND e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
 ORDER BY s.authorized_at DESC,s.renewal_id DESC LIMIT 1
$resolve$;
REVOKE ALL ON FUNCTION public.pdc_historical_writer_authorization_809_resolve(text,text,text,text,jsonb,text,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_historical_writer_authorization_809_resolve(text,text,text,text,jsonb,text,text) TO postgres;

CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_succes(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
 SET statement_timeout TO '300s'
AS $function$
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
 v_job_card_count integer:=0; v_sibling_count integer:=0; v_operation_count integer; v_actual_operation_count integer; v_canonical_request text; v_canonical_observation text; v_booking_created boolean:=false; v_completion_created boolean:=false; v_location_scheduled boolean:=false; v_parts_changed boolean:=false; v_status_changed boolean:=false;
 v_proposal public.pdc_ai_intake_proposals%rowtype; v_proposal_id uuid; v_proposal_binding_id uuid:=gen_random_uuid(); v_proposal_observation_match boolean; v_proposal_binding_kind text; v_manifest_text text;
BEGIN
 if jsonb_typeof(v_request)='object' then
   v_request:=jsonb_set(v_request,'{authentication}',public.pdc_historical_authentication_canonical_806(v_request->'authentication'),true);
   v_authentication:=coalesce(v_request->'authentication','null'::jsonb);
 end if;
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_actor<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR v_actor_email<>'sales@broometoyota.com.au'
    OR (coalesce(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true')
    OR jsonb_typeof(v_request) IS DISTINCT FROM 'object'
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_request) k) IS DISTINCT FROM ARRAY[
      'action_type','attachment_manifest','authentication','canonical_request_utf8','evidence_hash','gateway_instance_id','job_card_children',
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
 IF v_request->>'manifest_sha256' IS DISTINCT FROM lower(v_request->>'manifest_sha256') OR v_request->>'parent_source_hash' IS DISTINCT FROM lower(v_request->>'parent_source_hash') OR v_request->>'sender_email' IS DISTINCT FROM lower(v_request->>'sender_email') OR v_request->>'evidence_hash' IS DISTINCT FROM lower(v_request->>'evidence_hash') OR v_request->>'stock_number' IS DISTINCT FROM public.normalize_vehicle_stock_number(v_request->>'stock_number') OR v_source->>'recipient_mailbox' IS DISTINCT FROM lower(v_source->>'recipient_mailbox') OR v_request->'canonical_request_utf8' IS NULL THEN RETURN jsonb_build_object('ok',false,'code','historical_canonical_normalization_mismatch'); END IF;
v_canonical_request:=public.pdc_historical_canonical_request_788(v_request,v_actor,v_actor_email,v_runtime);
IF v_request->>'canonical_request_utf8' IS DISTINCT FROM v_canonical_request THEN RETURN jsonb_build_object('ok',false,'code','historical_canonical_request_mismatch'); END IF;
SELECT count(*) INTO v_authz_count
  FROM public.pdc_historical_writer_authorization_809_resolve(v_manifest,v_uid,v_parent,v_sender,v_authentication,v_stock,v_request->>'evidence_hash') r;
 IF v_authz_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','pdc_778_exact_authorization_failed'); END IF;
 SELECT * INTO v_authz
  FROM public.pdc_historical_writer_authorization_809_resolve(v_manifest,v_uid,v_parent,v_sender,v_authentication,v_stock,v_request->>'evidence_hash');
 IF clock_timestamp()>v_authz.authorized_at+interval '24 hours' THEN RETURN jsonb_build_object('ok',false,'code','historical_authorization_expired'); END IF;
 SELECT jsonb_agg(jsonb_build_object('content_type',m->>'content_type','filename',m->>'filename','sha256',lower(m->>'sha256'),'size',(m->>'size')::bigint) ORDER BY ordinality) INTO v_manifest_canonical FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality);
 SELECT '['||coalesce(string_agg('{"content_type":'||to_jsonb(m->>'content_type')::text||',"filename":'||to_jsonb(m->>'filename')::text||',"sha256":'||to_jsonb(lower(m->>'sha256'))::text||',"size":'||((m->>'size')::bigint)::text||'}',',' ORDER BY ordinality),'')||']' INTO v_manifest_text FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality);
 v_manifest_hash:=encode(extensions.digest(convert_to(v_manifest_text,'UTF8'),'sha256'),'hex');
 IF v_manifest_hash<>v_authz.attachment_manifest_sha256 OR v_manifest_canonical IS DISTINCT FROM v_authz.attachment_manifest OR jsonb_array_length(v_items)<>v_authz.attachment_count THEN RETURN jsonb_build_object('ok',false,'code','historical_attachment_manifest_mismatch'); END IF;
 v_request_hash:=encode(extensions.digest(convert_to(v_canonical_request,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-778:'||v_uid||':'||v_parent,0));
 SELECT * INTO v_existing FROM public.pdc_historical_reconciliation_778_receipts WHERE actor_id=v_actor AND provider_uid=v_uid AND parent_source_hash=v_parent;
 IF FOUND THEN IF v_existing.request_sha256<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','historical_replay_conflict'); END IF; RETURN v_existing.canonical_response; END IF;
 SELECT count(*) INTO v_attachment_count FROM public.vehicles v WHERE v.stock_number_normalized=v_stock AND v.deleted_at IS NULL;
 IF v_attachment_count>1 THEN RAISE EXCEPTION 'PDC_782_IDENTITY_CONFLICT' USING errcode='P0001'; END IF;
 SELECT v.id,v.current_location INTO v_known_vehicle_id,v_known_location FROM public.vehicles v WHERE v.stock_number_normalized=v_stock AND v.deleted_at IS NULL ORDER BY v.id LIMIT 1;
 v_parent_result:=public.submit_pdc_ai_intake_observation_pre135(v_parent, v_request->>'evidence_hash',v_uid,v_sender,v_authentication,(v_source->>'received_at')::timestamptz,v_request->>'subject',v_request->>'action_type',v_stock,v_request->>'summary',v_request->'observations');
 IF NOT coalesce((v_parent_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_789_PARENT_PROPOSAL_FAILED' USING errcode='P0001'; END IF;
 IF (v_parent_result->'data'->>'proposal_id') IS NULL OR (v_parent_result->'data'->>'proposal_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_789_PROPOSAL_ID_READBACK_FAILED' USING errcode='55000'; END IF;
 v_proposal_id:=(v_parent_result->'data'->>'proposal_id')::uuid;
 SELECT * INTO v_proposal FROM public.pdc_ai_intake_proposals WHERE proposal_id=v_proposal_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_789_PROPOSAL_READBACK_FAILED' USING errcode='55000'; END IF;
 IF v_proposal.status::text<>'pending' THEN
   RETURN jsonb_build_object('ok',false,'code','historical_proposal_terminal_conflict','data',jsonb_build_object('proposal_id',v_proposal.proposal_id,'status',v_proposal.status,'review_required',true));
 END IF;
 IF v_proposal.source_hash IS DISTINCT FROM v_parent
    OR v_proposal.evidence_hash IS DISTINCT FROM lower(v_request->>'evidence_hash')
    OR v_proposal.source_uid IS DISTINCT FROM v_uid
    OR lower(v_proposal.sender_address) IS DISTINCT FROM v_sender
    OR v_proposal.authentication IS DISTINCT FROM v_authentication
    OR public.normalize_vehicle_stock_number(v_proposal.stock_number) IS DISTINCT FROM v_stock
    OR v_proposal.source_received_at IS DISTINCT FROM (v_source->>'received_at')::timestamptz
    OR v_proposal.subject IS DISTINCT FROM v_request->>'subject'
    OR v_proposal.action_type IS DISTINCT FROM v_request->>'action_type'
    OR v_proposal.summary IS DISTINCT FROM v_request->>'summary' THEN
   RETURN jsonb_build_object('ok',false,'code','historical_proposal_tuple_conflict','data',jsonb_build_object('proposal_id',v_proposal.proposal_id,'review_required',true,'source_tuple_conflict',true));
 END IF;
 v_proposal_observation_match:=v_proposal.observations IS NOT DISTINCT FROM v_request->'observations';
 v_proposal_binding_kind:=CASE WHEN v_proposal_observation_match THEN 'pending_proposal_observation_match' ELSE 'pending_proposal_observation_mismatch' END;

 IF v_parent_result->>'code'='already_noticed' AND NOT EXISTS(SELECT 1 FROM public.ai_email_intake WHERE source_hash=v_parent ORDER BY created_at DESC LIMIT 1) THEN
   INSERT INTO public.pdc_historical_proposal_compatibility_reviews_793(
     review_id,proposal_id,contract_version,historical_contract_version,authorization_id,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,evidence_hash,sender_email,authentication,stock_number,source_received_at,subject,action_type,summary,request_sha256,proposal_observations,requested_observations,observation_match,review_code
   ) VALUES(
     gen_random_uuid(),v_proposal.proposal_id,'793.1','788.1',v_authz.authorization_id,v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_request->>'evidence_hash',v_sender,v_authentication,v_stock,(v_source->>'received_at')::timestamptz,v_request->>'subject',v_request->>'action_type',v_request->>'summary',v_request_hash,v_proposal.observations,v_request->'observations',v_proposal_observation_match,'historical_proposal_observation_review_required'
   ) ON CONFLICT(proposal_id,request_sha256) DO NOTHING;
   RETURN jsonb_build_object('ok',false,'code','historical_proposal_observation_review_required','data',jsonb_build_object('proposal_id',v_proposal.proposal_id,'review_required',true,'observation_match',v_proposal_observation_match,'intake_present',false));
 END IF;

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
   v_canonical_observation:=public.pdc_historical_canonical_observation_788(v_request,v_runtime,v_authz.authorization_id,v_intake_id,v_attachment.id,(v_item->>'ordinal')::integer,v_item->>'attachment_kind',lower(v_item->>'sha256'),v_request_hash);
   v_observation_sha:=encode(extensions.digest(convert_to(v_canonical_observation,'UTF8'),'sha256'),'hex');
   INSERT INTO public.pdc_historical_provider_observations_778(contract_version,authorization_id,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,intake_id,attachment_id,attachment_source_hash,provider_message_id,provider_authserv_id,authentication,request_sha256,observation_sha256) VALUES('778.1',v_authz.authorization_id,v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_sender,v_stock,v_intake_id,v_attachment.id,lower(v_item->>'sha256'),v_source->>'internet_message_id',v_source->>'provider_authserv_id',v_authentication,v_request_hash,v_observation_sha) ON CONFLICT(intake_id,attachment_id) DO NOTHING;
   IF NOT EXISTS(SELECT 1 FROM public.pdc_historical_provider_observations_778 h WHERE h.intake_id=v_intake_id AND h.attachment_id=v_attachment.id AND h.contract_version='778.1' AND h.authorization_id=v_authz.authorization_id AND h.actor_id=v_actor AND h.actor_email=v_actor_email AND h.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND h.manifest_sha256=v_manifest AND h.provider_uid=v_uid AND h.parent_source_hash=v_parent AND h.sender_email=v_sender AND h.stock_number=v_stock AND h.attachment_source_hash=lower(v_item->>'sha256') AND h.provider_message_id=v_source->>'internet_message_id' AND h.provider_authserv_id=v_source->>'provider_authserv_id' AND h.authentication IS NOT DISTINCT FROM v_authentication AND h.request_sha256=v_request_hash AND h.observation_sha256=v_observation_sha) THEN RAISE EXCEPTION 'PDC_788_OBSERVATION_REPLAY_CONFLICT' USING errcode='55000'; END IF;
   IF v_item->>'attachment_kind'='job_card' THEN v_job_card_count:=v_job_card_count+1; ELSE v_sibling_count:=v_sibling_count+1; END IF;
 END LOOP;
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
IF v_boundary_after IS DISTINCT FROM v_boundary_before THEN RAISE EXCEPTION 'PDC_788_PROTECTED_BOUNDARY_DRIFT' USING errcode='55000'; END IF;
 v_response:=jsonb_build_object('ok',true,'code','historical_reconciliation_782_receipt','data',jsonb_build_object('receipt_id',v_receipt_id,'contract_version','778.1','manifest_sha256',v_manifest,'provider_uid',v_uid,'parent_source_hash',v_parent,'sender_email',v_sender,'stock_number',v_stock,'intake_id',v_intake_id,'attachment_count',jsonb_array_length(v_items),'proposal_id',v_proposal.proposal_id,'proposal_binding_kind',v_proposal_binding_kind,'proposal_observation_match',v_proposal_observation_match,'job_card_count',v_job_card_count,'sibling_count',v_sibling_count,'attachment_receipts',v_child_results,'parent_observation',v_parent_result,'authoritative_state',jsonb_build_object('vehicle_id',v_vehicle.id,'lifecycle_state',v_vehicle.lifecycle_state,'current_location',v_vehicle.current_location,'operation_count',coalesce(v_actual_operation_count,0),'booking_count',0,'completion_count',0,'parts_changed',v_parts_changed),'booking_created',v_booking_created,'completion_created',v_completion_created,'location_scheduled',v_location_scheduled,'parts_changed',v_parts_changed,'status_changed',v_status_changed,'no_booking',NOT v_booking_created,'no_completion',NOT v_completion_created,'no_location_mutation',NOT v_location_scheduled));
 INSERT INTO public.pdc_historical_reconciliation_778_receipts(receipt_id,contract_version,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,request_sha256,intake_id,attachment_count,job_card_count,sibling_count,request_evidence,canonical_response) VALUES(v_receipt_id,'778.1',v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_sender,v_stock,v_request_hash,v_intake_id,jsonb_array_length(v_items),v_job_card_count,v_sibling_count,v_request,v_response);
 INSERT INTO public.pdc_historical_proposal_bindings_789(
   binding_id,receipt_id,proposal_id,contract_version,historical_contract_version,authorization_id,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,evidence_hash,sender_email,authentication,stock_number,source_received_at,subject,action_type,summary,request_sha256,proposal_observations,requested_observations,observation_match,binding_kind
 ) VALUES(
   v_proposal_binding_id,v_receipt_id,v_proposal.proposal_id,'789.1','788.1',v_authz.authorization_id,v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_request->>'evidence_hash',v_sender,v_authentication,v_stock,(v_source->>'received_at')::timestamptz,v_request->>'subject',v_request->>'action_type',v_request->>'summary',v_request_hash,v_proposal.observations,v_request->'observations',v_proposal_observation_match,v_proposal_binding_kind
 );
 INSERT INTO public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata) VALUES('insert','pdc_historical_reconciliation_778_receipts',v_actor,v_actor_email,NULL,v_response->'data',jsonb_build_object('contract','778.1','manifest_sha256',v_manifest,'protected_boundary_before',v_boundary_before,'protected_boundary_after',v_boundary_after,'unrelated_before',v_related_before,'unrelated_after',v_related_after));
 RETURN v_response;
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('ok',false,'code','historical_reconciliation_782_atomic_rollback');
END
$function$;

REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_successor(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor; GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_successor(jsonb) TO postgres;
DO $post$
DECLARE v text; owner_name text; secdef boolean; acl text; n integer;
BEGIN
 SELECT count(*) INTO n FROM public.pdc_historical_reconciliation_writer_authorizations_809 WHERE active AND expires_at>clock_timestamp() AND provider_uid IN ('1:133','1:134','1:137','1:168','1:172');
 SELECT p.proowner::regrole::text,p.prosecdef,p.proacl::text,p.prosrc INTO owner_name,secdef,acl,v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_793_proposal_review_successor(jsonb)'::regprocedure;
 IF n<>5 OR owner_name IS DISTINCT FROM 'postgres' OR NOT secdef OR acl IS DISTINCT FROM '{postgres=X/postgres}' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '666a8d0dc172e0ca5de52c25867dbcc7121dba1b668063a2b6de95291301fd0e' OR position('pdc_historical_writer_authorization_809_resolve' in v)=0 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_writer_authorizations_809 WHERE provider_uid IN ('1:21','1:22','1:23','1:26','1:40','1:57','1:85','1:93','1:95','1:96'))<>0 THEN RAISE EXCEPTION 'PDC_809_RENEWAL_OR_PROPOSAL_RESOLVER_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830230000','809_historical_writer_authorization_renewal_successor',ARRAY['append five exact evidence-backed 24-hour renewal rows linked to immutable 773 authorizations','resolve only renewed five rows through 793 while preserving original authorization IDs and history','exclude ten material tuple conflicts and preserve fail-closed review outcomes','no historical Apply outbox mailbox task outbound or Production operation']); COMMIT;
