-- STAGING ONLY 806: canonical frozen authentication tuple successor after 805.
-- The authoritative frozen export carries one derived authentication.aligned
-- marker. The canonical proposal/evidence contract stores only the five
-- verified authentication keys. This successor strips only that boolean
-- derived marker at the public and nested boundaries; every other malformed,
-- extra or missing key remains fail-closed. Existing proposal/source evidence
-- is never overwritten, deleted, equated or fabricated.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-806-canonical-authentication-tuple',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v_head text; v text; owner_name text; secdef boolean; acl text;
BEGIN
 SELECT (version,name)::text INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard()
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '(20260830222000,805_proposal_evidence_tuple_contained_successor)'
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260830222000')
    OR to_regprocedure('public.pdc_historical_authentication_canonical_806(jsonb)') IS NOT NULL
    OR to_regprocedure('public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)') IS NULL
    OR (SELECT count(*) FROM public.pdc_historical_reconciliation_writer_authorizations_773)<>15
    OR EXISTS(SELECT 1 FROM public.pdc_historical_reconciliation_writer_authorizations_773 WHERE provider_uid='1:197' OR stock_number='13056899')
    OR (SELECT count(*) FROM public.pdc_historical_reconciliation_778_receipts)<>0
    OR (SELECT count(*) FROM public.pdc_historical_provider_observations_778)<>0
    OR (SELECT count(*) FROM public.pdc_historical_complete_domain_readbacks_797)<>0
    OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
    OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
    OR (SELECT count(*) FROM public.pdc_email_source_claims)<>19
    OR NOT EXISTS(SELECT 1 FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)
 THEN RAISE EXCEPTION 'PDC_806_CURRENT_HEAD_OR_CONTAINMENT_GUARD_FAILED' USING errcode='55000'; END IF;
 FOREACH v IN ARRAY ARRAY['public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb)','public.submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb)','public.submit_pdc_historical_reconciliation_778_pre796(jsonb)','public.submit_pdc_historical_reconciliation_778_pre797(jsonb)','public.submit_pdc_historical_reconciliation_778(jsonb)'] LOOP
   SELECT p.proowner::regrole::text,p.prosecdef,p.proacl::text INTO owner_name,secdef,acl FROM pg_proc p WHERE p.oid=v::regprocedure;
   IF owner_name<>'postgres' OR NOT secdef OR (v='public.submit_pdc_historical_reconciliation_778(jsonb)' AND acl<>'{authenticated=X/postgres}') OR (v<>'public.submit_pdc_historical_reconciliation_778(jsonb)' AND acl<>'{postgres=X/postgres}') THEN RAISE EXCEPTION 'PDC_806_FUNCTION_SECURITY_PRESTATE_FAILED:%',v USING errcode='55000'; END IF;
 END LOOP;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'e395bf4b7c2ca358ecbc930034f69a57ee145709a9772b896c7bee0e5a476215' THEN RAISE EXCEPTION 'PDC_806_WRITER_SOURCE_PRESTATE_FAILED' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'5227b575c60a66987e59e2ef0d9e4ac8c1128dfb463d8974a083730d16ed74a7' THEN RAISE EXCEPTION 'PDC_806_793_SOURCE_PRESTATE_FAILED' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778_pre796(jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'04cdc16f0e770cca451afaa0a6ece2d74418a5ac059b2c6453f04c2f35b7ec99' THEN RAISE EXCEPTION 'PDC_806_PRE796_SOURCE_PRESTATE_FAILED' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778_pre797(jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'652632f569db58835650a5a1e6690016a5bec8c51952d1786ebcd4ca65732f1e' THEN RAISE EXCEPTION 'PDC_806_PRE797_SOURCE_PRESTATE_FAILED' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'b83ad98badc6e177e81f048f78b123d649c70905fbf3a3937fb13166c647787e' THEN RAISE EXCEPTION 'PDC_806_PUBLIC_SOURCE_PRESTATE_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.pdc_historical_authentication_canonical_806(p_authentication jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $auth$
DECLARE v jsonb:=coalesce(p_authentication,'null'::jsonb); v_keys text[];
BEGIN
 IF jsonb_typeof(v) IS DISTINCT FROM 'object' THEN RETURN v; END IF;
 SELECT array_agg(k ORDER BY k) INTO v_keys FROM jsonb_object_keys(v) k;
 IF v_keys IS DISTINCT FROM ARRAY['aligned','dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[] THEN RETURN v; END IF;
 IF jsonb_typeof(v->'aligned') IS DISTINCT FROM 'boolean' THEN RETURN v; END IF;
 RETURN v-'aligned';
END
$auth$;

REVOKE ALL ON FUNCTION public.pdc_historical_authentication_canonical_806(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_historical_authentication_canonical_806(jsonb) TO postgres;
CREATE OR REPLACE FUNCTION public.pdc_historical_writer_authorized_777(p_source_hash text, p_evidence_hash text, p_source_uid text, p_sender text, p_authentication jsonb, p_stock text, p_observations jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare
 v_source text:=lower(btrim(coalesce(p_source_hash,'')));
 v_evidence text:=lower(btrim(coalesce(p_evidence_hash,'')));
 v_uid text:=btrim(coalesce(p_source_uid,''));
 v_sender text:=lower(btrim(coalesce(p_sender,'')));
 v_stock text:=public.normalize_vehicle_stock_number(p_stock);
 v_attachment_id uuid;
 v_attachment_hash text:=lower(btrim(coalesce(p_observations->'attachment_manifest'->0->>'source_hash','')));
begin
 p_authentication:=public.pdc_historical_authentication_canonical_806(p_authentication);
 if not public.pdc_monitor_staging_guard()
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    or lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
    or coalesce(auth.jwt()->>'role','')<>'authenticated'
    or coalesce(auth.jwt()->>'app_role','importer') not in ('importer','')
    or (coalesce(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true')
    or v_uid='1:197' or v_stock='13056899'
    or v_source!~'^[a-f0-9]{64}$' or v_evidence!~'^[a-f0-9]{64}$'
    or jsonb_typeof(p_authentication) is distinct from 'object'
    or jsonb_typeof(p_observations) is distinct from 'object'
    or jsonb_typeof(p_observations->'attachment_manifest') is distinct from 'array' then
   return false;
 end if;
 if coalesce(p_observations->'attachment_manifest'->0->>'attachment_id','')
       ~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
   v_attachment_id:=(p_observations->'attachment_manifest'->0->>'attachment_id')::uuid;
 end if;
 return exists(
   select 1 from public.pdc_historical_reconciliation_writer_authorizations_773 e
   where e.active and e.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
     and e.provider_uid=v_uid and e.parent_source_hash=v_source and e.sender_email=v_sender
     and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')
     and e.provider_authentication is not distinct from p_authentication
     and public.normalize_vehicle_stock_number(e.stock_number)=v_stock
     and e.authorized_actor_id=auth.uid()
     and e.authorized_actor_email=lower(btrim(auth.jwt()->>'email'))
     and e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
 ) or exists(
   select 1
   from public.pdc_historical_reconciliation_writer_authorizations_773 e
   join public.ai_email_intake i on lower(i.source_hash)=e.parent_source_hash
   join public.ai_email_attachments a on a.intake_id=i.id
   where e.active and e.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
     and e.sender_email=v_sender and e.provider_authentication is not distinct from p_authentication
     and public.normalize_vehicle_stock_number(e.stock_number)=v_stock
     and e.authorized_actor_id=auth.uid()
     and e.authorized_actor_email=lower(btrim(auth.jwt()->>'email'))
     and e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
     and v_attachment_id is not null and a.id=v_attachment_id
     and lower(a.source_hash)=v_attachment_hash
     and v_source=public.pdc_233_length_prefixed_sha256(array[
       'pdc-attachment-canonical-source','233.1',i.id::text,a.id::text,
       e.parent_source_hash,v_attachment_hash])
     and v_uid='pdc-jc-159:'||encode(extensions.digest(convert_to(
       i.id::text||':'||a.id::text||':'||e.parent_source_hash||':'||v_attachment_hash,'UTF8'),'sha256'),'hex')
 );
end
$function$;
REVOKE ALL ON FUNCTION public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb) TO postgres;
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
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb) TO postgres;
CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778_pre796(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
 v_before jsonb; v_after jsonb; v_location_before text; v_location_after text; v_result jsonb; v_canonical_request text; v_booking_created boolean:=false; v_completion_created boolean:=false; v_location_scheduled boolean:=false; v_parts_changed boolean:=false;
 v_vehicle_id uuid; v_vehicle public.vehicles%rowtype; v_existing public.pdc_historical_reconciliation_778_receipts%rowtype; v_existing_proposal public.pdc_ai_intake_proposals%rowtype; v_child_receipt public.pdc_jobcard_attachment_import_receipts%rowtype; v_request_hash text; v_uid text; v_parent text; v_sender text; v_stock text; v_source jsonb; v_items jsonb; v_auth jsonb; v_runtime jsonb; v_authz public.pdc_historical_reconciliation_writer_authorizations_773%rowtype; v_authz_count integer; v_intake public.ai_email_intake%rowtype; v_intake_id uuid; v_attachment_id uuid; v_child jsonb; v_item jsonb; v_required jsonb; v_work_key text; v_booking_count integer:=0; v_completion_count integer:=0; v_parts_count integer:=0; v_receipt_count integer:=0;
BEGIN
 if jsonb_typeof(coalesce(p_request,'null'::jsonb))='object' then
   p_request:=jsonb_set(p_request,'{authentication}',public.pdc_historical_authentication_canonical_806(p_request->'authentication'),true);
 end if;
 IF auth.uid()='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid AND lower(btrim(coalesce(auth.jwt()->>'email','')))= 'sales@broometoyota.com.au' AND public.pdc_monitor_staging_guard() AND jsonb_typeof(p_request)='object' AND p_request->>'parent_source_hash' IS NOT NULL AND p_request->>'provider_uid' IS NOT NULL THEN
   SELECT * INTO v_existing_proposal FROM public.pdc_ai_intake_proposals WHERE source_hash=lower(p_request->>'parent_source_hash') AND source_uid=btrim(p_request->>'provider_uid') ORDER BY submitted_at DESC,proposal_id DESC LIMIT 1 FOR UPDATE;
   IF FOUND THEN
     IF v_existing_proposal.status::text<>'pending' THEN RETURN jsonb_build_object('ok',false,'code','historical_proposal_terminal_conflict','data',jsonb_build_object('proposal_id',v_existing_proposal.proposal_id,'status',v_existing_proposal.status,'review_required',true)); END IF;
     IF v_existing_proposal.evidence_hash IS DISTINCT FROM lower(p_request->>'evidence_hash') OR lower(v_existing_proposal.sender_address) IS DISTINCT FROM lower(p_request->>'sender_email') OR v_existing_proposal.authentication IS DISTINCT FROM coalesce(p_request->'authentication','null'::jsonb) OR public.normalize_vehicle_stock_number(v_existing_proposal.stock_number) IS DISTINCT FROM public.normalize_vehicle_stock_number(p_request->>'stock_number') THEN RETURN jsonb_build_object('ok',false,'code','historical_proposal_tuple_conflict','data',jsonb_build_object('proposal_id',v_existing_proposal.proposal_id,'review_required',true,'source_tuple_conflict',true)); END IF;
     IF v_existing_proposal.subject IS DISTINCT FROM p_request->>'subject' OR v_existing_proposal.action_type IS DISTINCT FROM p_request->>'action_type' OR v_existing_proposal.summary IS DISTINCT FROM p_request->>'summary' THEN RETURN jsonb_build_object('ok',false,'code','historical_proposal_payload_conflict','data',jsonb_build_object('proposal_id',v_existing_proposal.proposal_id,'review_required',true,'payload_conflict',true)); END IF;
   END IF;
 END IF;
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au' OR COALESCE(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true' OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_request) k) IS DISTINCT FROM ARRAY['action_type','attachment_manifest','authentication','canonical_request_utf8','evidence_hash','gateway_instance_id','job_card_children','manifest_high_water_uid','manifest_sha256','manifest_uid_count','manifest_uidvalidity','observations','parent_source_hash','provider_uid','release_manifest_sha256','release_name','release_source_sha','sender_email','source_metadata','stock_number','subject','summary']::text[] THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 v_uid:=btrim(coalesce(p_request->>'provider_uid','')); v_parent:=lower(btrim(coalesce(p_request->>'parent_source_hash',''))); v_sender:=lower(btrim(coalesce(p_request->>'sender_email',''))); v_stock:=public.normalize_vehicle_stock_number(p_request->>'stock_number'); v_source:=coalesce(p_request->'source_metadata','null'::jsonb); v_items:=coalesce(p_request->'attachment_manifest','null'::jsonb); v_auth:=coalesce(p_request->'authentication','null'::jsonb);
 IF p_request->>'gateway_instance_id' IS DISTINCT FROM 'pdc-monitor-staging-sales-uid509-v1' OR p_request->>'release_name' IS DISTINCT FROM 'pdc-monitor-staging-m502-2026.08.44' OR lower(p_request->>'release_source_sha') IS DISTINCT FROM 'e850c319989d98b45b95a28aa815d78e2c2e3a4b' OR lower(p_request->>'release_manifest_sha256') IS DISTINCT FROM 'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' OR p_request->>'manifest_sha256' IS DISTINCT FROM 'aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018' OR p_request->>'manifest_uidvalidity' IS DISTINCT FROM '1' OR p_request->>'manifest_high_water_uid' IS DISTINCT FROM '685' OR p_request->>'manifest_uid_count' IS DISTINCT FROM '669' OR v_request_hash!~'^[a-f0-9]{64}$' OR v_uid!~'^1:[1-9][0-9]{0,5}$' OR v_uid='1:197' OR v_parent!~'^[a-f0-9]{64}$' OR v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$' OR v_stock='13056899' OR NOT public.is_real_vehicle_stock_number(v_stock) OR p_request->>'evidence_hash'!~'^[a-f0-9]{64}$' OR p_request->>'action_type' NOT IN ('board_activate_only','review_only') OR jsonb_typeof(v_auth) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_auth) k) IS DISTINCT FROM ARRAY['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[] OR v_auth->>'sender_domain' IS DISTINCT FROM split_part(v_sender,'@',2) OR v_auth->'gmail_authentication_results' IS DISTINCT FROM 'true'::jsonb OR NOT(v_auth->'spf_aligned'='true'::jsonb OR v_auth->'dkim_aligned'='true'::jsonb OR v_auth->'dmarc_aligned'='true'::jsonb) OR jsonb_typeof(v_items) IS DISTINCT FROM 'array' OR jsonb_array_length(v_items) NOT BETWEEN 1 AND 25 OR jsonb_typeof(p_request->'job_card_children') IS DISTINCT FROM 'array' OR jsonb_array_length(p_request->'job_card_children')>25 OR jsonb_typeof(v_source) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_source) k) IS DISTINCT FROM ARRAY['attachment_names','graph_message_id','internet_message_id','parsed_text','provider_authserv_id','raw_body','received_at','recipient_mailbox','sender_name','uid','uidvalidity']::text[] OR v_source->>'uidvalidity' IS DISTINCT FROM '1' OR v_source->>'uid' IS DISTINCT FROM substring(v_uid FROM '^1:([0-9]+)$') OR v_source->>'provider_authserv_id' IS DISTINCT FROM 'mx.google.com' OR lower(v_source->>'recipient_mailbox') IS DISTINCT FROM 'pmbcontroller@gmail.com' OR v_source->>'received_at' IS NULL OR (v_source->>'received_at')::timestamptz > clock_timestamp()+interval '5 minutes' OR (v_source->>'received_at')::timestamptz < clock_timestamp()-interval '120 days' OR v_source->'attachment_names' IS DISTINCT FROM (SELECT jsonb_agg(m->>'filename' ORDER BY ordinality) FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality)) THEN RETURN jsonb_build_object('ok',false,'code','historical_wrapper_preflight_failed'); END IF;
 v_runtime:=public.verify_pdc_monitor_runtime_binding_authenticated_766('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227');
 IF v_runtime->>'ok' IS DISTINCT FROM 'true' OR v_runtime->>'actor_id' IS DISTINCT FROM auth.uid()::text OR v_runtime->>'actor_email' IS DISTINCT FROM lower(auth.jwt()->>'email') OR v_runtime->>'task_enabled' IS DISTINCT FROM 'false' OR v_runtime->>'mailbox_contacted' IS DISTINCT FROM 'false' OR v_runtime->>'production_writes' IS DISTINCT FROM 'false' THEN RETURN jsonb_build_object('ok',false,'code','historical_wrapper_preflight_failed'); END IF;
v_canonical_request:=public.pdc_historical_canonical_request_788(p_request,auth.uid(),lower(auth.jwt()->>'email'),v_runtime);
IF p_request->>'canonical_request_utf8' IS DISTINCT FROM v_canonical_request THEN RETURN jsonb_build_object('ok',false,'code','historical_canonical_request_mismatch'); END IF;
v_request_hash:=encode(extensions.digest(convert_to(v_canonical_request,'UTF8'),'sha256'),'hex');
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality) WHERE jsonb_typeof(x.m) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x.m) k) IS DISTINCT FROM ARRAY['attachment_kind','content_type','filename','ordinal','sha256','size']::text[] OR x.m->>'attachment_kind' NOT IN ('job_card','ambiguous_job_card','non_job_card_sibling') OR x.m->>'sha256'!~'^[a-f0-9]{64}$' OR x.m->>'ordinal'!~'^[1-9][0-9]{0,2}$' OR (x.m->>'ordinal')::integer<>x.ordinality OR x.m->>'size'!~'^[1-9][0-9]{0,7}$' OR x.m->>'content_type' IS NULL OR x.m->>'filename' IS NULL) THEN RETURN jsonb_build_object('ok',false,'code','historical_wrapper_preflight_failed'); END IF;
 SELECT count(*) INTO v_authz_count FROM public.pdc_historical_reconciliation_writer_authorizations_773 e WHERE e.active AND e.manifest_sha256=p_request->>'manifest_sha256' AND e.provider_uid=v_uid AND e.parent_source_hash=v_parent AND e.sender_email=v_sender AND e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex') AND e.provider_authentication IS NOT DISTINCT FROM v_auth AND public.normalize_vehicle_stock_number(e.stock_number)=v_stock AND e.authorized_actor_id=auth.uid() AND e.authorized_actor_email=lower(auth.jwt()->>'email') AND e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND public.pdc_historical_writer_authorized_773(v_parent,v_uid,v_sender,v_auth,v_stock);
 IF v_authz_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','pdc_778_exact_authorization_failed'); END IF;
 SELECT * INTO v_authz FROM public.pdc_historical_reconciliation_writer_authorizations_773 e WHERE e.active AND e.manifest_sha256=p_request->>'manifest_sha256' AND e.provider_uid=v_uid AND e.parent_source_hash=v_parent AND e.sender_email=v_sender AND e.authorized_actor_id=auth.uid() AND e.authorized_actor_email=lower(auth.jwt()->>'email') AND e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1';
 SELECT * INTO v_existing FROM public.pdc_historical_reconciliation_778_receipts WHERE actor_id=auth.uid() AND provider_uid=v_uid AND parent_source_hash=v_parent;
 IF FOUND THEN IF v_existing.request_sha256<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','historical_replay_conflict'); END IF; RETURN v_existing.canonical_response; END IF;
 SELECT * INTO v_intake FROM public.ai_email_intake WHERE source_hash=v_parent ORDER BY created_at DESC LIMIT 1;
 IF FOUND AND (v_intake.duplicate_of IS NOT NULL OR v_intake.status::text NOT IN ('received','processing') OR v_intake.received_at IS NULL OR v_intake.received_at>clock_timestamp()+interval '5 minutes' OR v_intake.received_at<clock_timestamp()-interval '120 days') THEN RETURN jsonb_build_object('ok',false,'code','pdc_782_old_mail_completed'); END IF;
 IF clock_timestamp()>v_authz.authorized_at+interval '24 hours' THEN RETURN jsonb_build_object('ok',false,'code','historical_authorization_expired'); END IF;
 v_before:=public.pdc_historical_782_boundary_snapshot();
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY to_jsonb(x)::text) FROM public.vehicle_movements x),'')||'|'||coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY to_jsonb(x)::text) FROM public.vehicle_aliases x),'')) INTO v_location_before;
 v_result:=public.submit_pdc_historical_reconciliation_793_proposal_review_succes(p_request);
 v_after:=public.pdc_historical_782_boundary_snapshot();
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY to_jsonb(x)::text) FROM public.vehicle_movements x),'')||'|'||coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY to_jsonb(x)::text) FROM public.vehicle_aliases x),'')) INTO v_location_after;
 v_booking_created:=v_after->>'workshop_bookings' IS DISTINCT FROM v_before->>'workshop_bookings' OR v_after->>'workshop_booking_assignments' IS DISTINCT FROM v_before->>'workshop_booking_assignments';
 v_completion_created:=v_after->>'pdc_qc_operation_completions_379' IS DISTINCT FROM v_before->>'pdc_qc_operation_completions_379';
 v_location_scheduled:=v_booking_created;
 v_parts_changed:=v_after->>'vehicle_parts_updates' IS DISTINCT FROM v_before->>'vehicle_parts_updates';
 v_location_scheduled:=v_location_scheduled OR v_location_after IS DISTINCT FROM v_location_before;
 IF v_booking_created OR v_completion_created OR v_location_scheduled OR v_parts_changed THEN RAISE EXCEPTION 'PDC_782_1740_PROTECTED_BOUNDARY_DRIFT' USING errcode='55000'; END IF;
IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'PDC_788_PROTECTED_BOUNDARY_DRIFT' USING errcode='55000'; END IF;
 IF v_result->>'ok'='true' THEN
   IF v_result->'data'->>'booking_created' IS DISTINCT FROM v_booking_created::text OR v_result->'data'->>'completion_created' IS DISTINCT FROM v_completion_created::text OR v_result->'data'->>'location_scheduled' IS DISTINCT FROM v_location_scheduled::text OR v_result->'data'->>'parts_changed' IS DISTINCT FROM v_parts_changed::text THEN RAISE EXCEPTION 'PDC_782_1740_FLAG_READBACK_FAILED' USING errcode='55000'; END IF;
   IF jsonb_typeof(v_result->'data'->'authoritative_state') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PDC_782_1740_AUTHORITATIVE_STATE_MISSING' USING errcode='55000'; END IF;
   IF v_result->'data'->'authoritative_state'->>'vehicle_id' IS NOT NULL THEN
     IF v_result->'data'->'authoritative_state'->>'vehicle_id' !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_782_1740_VEHICLE_ID_READBACK_FAILED' USING errcode='55000'; END IF;
     v_vehicle_id:=(v_result->'data'->'authoritative_state'->>'vehicle_id')::uuid;
     SELECT * INTO v_vehicle FROM public.vehicles WHERE id=v_vehicle_id;
     IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state::text<>'active' OR v_vehicle.board_purged_at IS NOT NULL OR NOT coalesce(v_vehicle.visible_on_board,false) THEN RAISE EXCEPTION 'PDC_782_1740_AUTHORITATIVE_VEHICLE_FAILED' USING errcode='55000'; END IF;
     select count(*) into v_booking_count from public.workshop_bookings where vehicle_id=v_vehicle_id;
     select count(*) into v_completion_count from public.pdc_qc_operation_completions_379 where vehicle_id=v_vehicle_id;
     select count(*) into v_parts_count from public.vehicle_parts_updates where vehicle_id=v_vehicle_id;
     IF v_booking_count<>0 OR v_completion_count<>0 OR v_parts_count<>0 THEN RAISE EXCEPTION 'PDC_782_1740_AUTHORITATIVE_PROTECTED_STATE_FAILED' USING errcode='55000'; END IF;
     FOR v_child IN SELECT value FROM jsonb_array_elements(p_request->'job_card_children') LOOP
       IF v_child->>'attachment_kind'='job_card' THEN
         v_intake_id:=NULLIF(v_result->'data'->>'intake_id','')::uuid;
         SELECT count(*) INTO v_receipt_count FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=p_request->>'provider_uid'||':historical-782-'||lpad((v_child->>'attachment_ordinal')::integer::text,3,'0')||'-'||lower(v_child->>'attachment_hash') AND lower(a.source_hash)=lower(v_child->>'attachment_hash');
         IF v_receipt_count<>1 THEN RAISE EXCEPTION 'PDC_782_1740_CHILD_ATTACHMENT_READBACK_FAILED' USING errcode='55000'; END IF;
         SELECT a.id INTO v_attachment_id FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=p_request->>'provider_uid'||':historical-782-'||lpad((v_child->>'attachment_ordinal')::integer::text,3,'0')||'-'||lower(v_child->>'attachment_hash');
         SELECT count(*) INTO v_receipt_count FROM public.pdc_jobcard_attachment_import_receipts r WHERE r.intake_id=v_intake_id AND r.attachment_id=v_attachment_id AND r.parent_source_hash=p_request->>'parent_source_hash' AND r.attachment_source_hash=lower(v_child->>'attachment_hash') AND r.attachment_content_type='application/pdf' AND r.job_card_number= v_child->'extraction'->'email_vehicle'->>'job_card_number' AND r.operation_count=jsonb_array_length(v_child->'extraction'->'operation_lines') AND r.canonical_import_receipt_id IS NOT NULL AND r.vehicle_id IS NOT NULL;
         IF v_receipt_count<>1 THEN RAISE EXCEPTION 'PDC_782_1740_CHILD_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
         v_vehicle_id:=NULLIF((SELECT r->>'authoritative_vehicle_id' FROM jsonb_array_elements(v_result->'data'->'attachment_receipts') r WHERE r->>'attachment_hash'=v_child->>'attachment_hash' LIMIT 1),'')::uuid;
         v_required:=coalesce(v_child->'extraction'->'required_work','[]'::jsonb);
         IF v_vehicle_id IS NULL OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_required) k WHERE NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v_vehicle_id AND wi.work_key=k AND wi.required)) THEN RAISE EXCEPTION 'PDC_782_1740_AUTHORITATIVE_WORK_FAILED' USING errcode='55000'; END IF;
       END IF;
     END LOOP;
   END IF;
 END IF;
 RETURN v_result;
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('ok',false,'code','historical_reconciliation_782_atomic_rollback');
END
$function$;
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre796(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre796(jsonb) TO postgres;
CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778_pre797(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
 v_before jsonb; v_after jsonb; v_result jsonb; v_readback jsonb; v_vehicle public.vehicles%rowtype; v_vehicle_id uuid; v_receipt_id uuid; v_request_hash text; v_existing_request_hash text;
 v_stock text; v_match_count integer:=0; v_had_vehicle boolean:=false; v_replay boolean:=false; v_replay_vehicle_id uuid; v_location text; v_lifecycle text;
BEGIN
 if jsonb_typeof(coalesce(p_request,'null'::jsonb))='object' then
   p_request:=jsonb_set(p_request,'{authentication}',public.pdc_historical_authentication_canonical_806(p_request->'authentication'),true);
 end if;
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
    OR COALESCE(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true'
 THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 v_stock:=public.normalize_vehicle_stock_number(p_request->>'stock_number');
 IF jsonb_typeof(p_request)='object' THEN
   SELECT r.request_sha256 INTO v_existing_request_hash FROM public.pdc_historical_reconciliation_778_receipts r WHERE r.actor_id=auth.uid() AND r.provider_uid=btrim(coalesce(p_request->>'provider_uid','')) AND r.parent_source_hash=lower(btrim(coalesce(p_request->>'parent_source_hash','')));
   IF v_existing_request_hash IS NOT NULL AND encode(extensions.digest(convert_to(coalesce(p_request->>'canonical_request_utf8',''),'UTF8'),'sha256'),'hex')=v_existing_request_hash THEN v_replay:=true; END IF;
 END IF;
 IF v_replay AND v_stock IS NOT NULL AND v_stock<>'' THEN
   SELECT count(*) INTO v_match_count FROM public.vehicles v WHERE v.stock_number_normalized=v_stock;
   IF v_match_count>1 THEN RETURN jsonb_build_object('ok',false,'code','PDC_796_REPLAY_IDENTITY_CONFLICT'); END IF;
   IF v_match_count=1 THEN SELECT v.id INTO v_replay_vehicle_id FROM public.vehicles v WHERE v.stock_number_normalized=v_stock ORDER BY v.id LIMIT 1; END IF;
 END IF;
 IF NOT v_replay AND jsonb_typeof(p_request)='object' AND v_stock IS NOT NULL AND v_stock<>'' THEN
   SELECT count(*) INTO v_match_count FROM public.vehicles v WHERE v.stock_number_normalized=v_stock;
   IF v_match_count>1 THEN RETURN jsonb_build_object('ok',false,'code','PDC_796_IDENTITY_CONFLICT'); END IF;
   SELECT * INTO v_vehicle FROM public.vehicles v WHERE v.stock_number_normalized=v_stock ORDER BY (v.deleted_at IS NULL) DESC,v.id LIMIT 1 FOR UPDATE;
   IF FOUND THEN
     v_had_vehicle:=true; v_vehicle_id:=v_vehicle.id; v_location:=lower(regexp_replace(btrim(coalesce(v_vehicle.current_location,'')),'\s+',' ','g')); v_lifecycle:=v_vehicle.lifecycle_state::text;
     IF v_lifecycle IN ('rft','completed','deleted','tombstoned') OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.board_purged_at IS NOT NULL
        OR v_vehicle.rft_transferred_at IS NOT NULL OR v_vehicle.rft_collected_at IS NOT NULL OR v_vehicle.rft_confirmed_at IS NOT NULL
        OR v_vehicle.rft_transport_booked_at IS NOT NULL OR v_vehicle.delivered_to_dealer_date IS NOT NULL OR v_vehicle.dealer_transit_closed_at IS NOT NULL
        OR v_location=ANY(ARRAY['yh','yard hold','vehicle yard hold','pmb','qc','pit','other','rft','collected','completed','delivered','delivered - at dealer','delivered - at body builder','planned for despatch - from twa','despatched - from body builder','vehicle out on consignment','vehicle delayed','vehicle waiting for wholesale','planned for production','waiting pd1','waiting pd2','vehicle at wharf','in transit to wa','ready for shipment']::text[])
     THEN RETURN jsonb_build_object('ok',false,'code','historical_terminal_or_protected_location','data',jsonb_build_object('vehicle_id',v_vehicle_id,'lifecycle_state',v_lifecycle,'current_location',v_vehicle.current_location,'review_required',true)); END IF;
     v_before:=public.pdc_historical_796_domain_snapshot(v_vehicle_id);
   END IF;
 END IF;
 v_result:=public.submit_pdc_historical_reconciliation_778_pre796(p_request);
 IF v_result->>'ok'='true' THEN
   IF (v_result->'data'->'authoritative_state'->>'vehicle_id') IS NOT NULL THEN v_vehicle_id:=(v_result->'data'->'authoritative_state'->>'vehicle_id')::uuid; END IF;
   IF v_vehicle_id IS NULL AND v_stock IS NOT NULL THEN SELECT v.id INTO v_vehicle_id FROM public.vehicles v WHERE v.stock_number_normalized=v_stock AND v.deleted_at IS NULL ORDER BY v.id LIMIT 1; END IF;
   v_after:=public.pdc_historical_796_domain_snapshot(v_vehicle_id);
   IF NOT v_replay THEN
     IF jsonb_typeof(v_after->'vehicle')='object' AND v_after->'vehicle'->>'lifecycle_state' IS DISTINCT FROM 'active' THEN RAISE EXCEPTION 'PDC_796_TERMINAL_READBACK_FAILED' USING errcode='55000'; END IF;
     IF v_had_vehicle AND (v_after->'vehicle'->>'lifecycle_state' IS DISTINCT FROM v_before->'vehicle'->>'lifecycle_state' OR v_after->'vehicle'->>'current_location' IS DISTINCT FROM v_before->'vehicle'->>'current_location' OR v_after->'protected_fingerprints' IS DISTINCT FROM v_before->'protected_fingerprints') THEN RAISE EXCEPTION 'PDC_796_PROTECTED_DOMAIN_DRIFT' USING errcode='55000'; END IF;
   END IF;
   IF (v_result->'data'->>'receipt_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_796_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
   v_receipt_id:=(v_result->'data'->>'receipt_id')::uuid;
   IF v_replay AND v_stock IS NOT NULL AND v_stock<>'' THEN
     IF v_replay_vehicle_id IS NOT NULL AND v_vehicle_id IS NOT NULL AND v_replay_vehicle_id IS DISTINCT FROM v_vehicle_id THEN RAISE EXCEPTION 'PDC_796_REPLAY_VEHICLE_ID_MISMATCH' USING errcode='55000'; END IF;
     IF v_vehicle_id IS NULL THEN v_vehicle_id:=v_replay_vehicle_id; v_after:=public.pdc_historical_796_domain_snapshot(v_vehicle_id); END IF;
     IF v_vehicle_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id=v_vehicle_id AND v.stock_number_normalized=v_stock) THEN RAISE EXCEPTION 'PDC_796_REPLAY_VEHICLE_READBACK_FAILED' USING errcode='55000'; END IF;
   END IF;
   IF v_replay AND v_vehicle_id IS NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_result->'data'->'attachment_receipts','[]'::jsonb)) r WHERE coalesce(r->'result'->>'code','')<>'historical_child_ambiguous') THEN RAISE EXCEPTION 'PDC_796_REPLAY_VEHICLE_READBACK_FAILED' USING errcode='55000'; END IF;
   SELECT r.request_sha256 INTO v_request_hash FROM public.pdc_historical_reconciliation_778_receipts r WHERE r.receipt_id=v_receipt_id;
   IF v_request_hash IS NULL THEN RAISE EXCEPTION 'PDC_796_AGGREGATE_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
   INSERT INTO public.pdc_historical_domain_readbacks_796(receipt_id,request_sha256,vehicle_id,authoritative_domain_state,before_protected_fingerprints,after_protected_fingerprints,protected_fingerprint)
   VALUES(v_receipt_id,v_request_hash,v_vehicle_id,v_after,coalesce(v_before->'protected_fingerprints','{}'::jsonb),v_after->'protected_fingerprints',v_after->'protected_fingerprints'->>'all') ON CONFLICT(receipt_id) DO NOTHING;
   SELECT jsonb_build_object('receipt_id',receipt_id,'request_sha256',request_sha256,'vehicle_id',vehicle_id,'authoritative_domain_state',authoritative_domain_state,'before_protected_fingerprints',before_protected_fingerprints,'after_protected_fingerprints',after_protected_fingerprints,'protected_fingerprint',protected_fingerprint) INTO v_readback FROM public.pdc_historical_domain_readbacks_796 WHERE receipt_id=v_receipt_id;
   IF v_readback IS NULL OR v_readback->>'request_sha256' IS NULL OR v_readback->>'protected_fingerprint' IS NULL THEN RAISE EXCEPTION 'PDC_796_DOMAIN_READBACK_FAILED' USING errcode='55000'; END IF;
   v_result:=jsonb_set(v_result,'{data,replay}',to_jsonb(v_replay),true);
   IF v_readback->'authoritative_domain_state' IS NOT NULL THEN v_result:=jsonb_set(v_result,'{data,authoritative_domain_state}',v_readback->'authoritative_domain_state',true); END IF;
 END IF;
 RETURN v_result;
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('ok',false,'code','historical_reconciliation_782_atomic_rollback');
END
$function$;
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre797(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre797(jsonb) TO postgres;
CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
 v_before jsonb; v_after jsonb; v_result jsonb; v_readback jsonb; v_vehicle_id uuid; v_stock text; v_request_hash text; v_receipt_id uuid;
 v_before_fp jsonb; v_after_fp jsonb; v_before_counts jsonb; v_after_counts jsonb;
BEGIN
 if jsonb_typeof(coalesce(p_request,'null'::jsonb))='object' then
   p_request:=jsonb_set(p_request,'{authentication}',public.pdc_historical_authentication_canonical_806(p_request->'authentication'),true);
 end if;
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
    OR COALESCE(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true'
 THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 v_stock:=public.normalize_vehicle_stock_number(p_request->>'stock_number');
 IF v_stock IS NOT NULL AND v_stock<>'' THEN
   SELECT v.id INTO v_vehicle_id FROM public.vehicles v WHERE v.stock_number_normalized=v_stock ORDER BY (v.deleted_at IS NULL) DESC,v.id LIMIT 1;
 END IF;
 v_before:=public.pdc_historical_797_complete_domain_snapshot(v_vehicle_id);
 v_result:=public.submit_pdc_historical_reconciliation_778_pre797(p_request);
 IF v_result->>'ok'='true' THEN
   IF (v_result->'data'->'authoritative_state'->>'vehicle_id') IS NOT NULL THEN v_vehicle_id:=(v_result->'data'->'authoritative_state'->>'vehicle_id')::uuid; END IF;
   v_after:=public.pdc_historical_797_complete_domain_snapshot(v_vehicle_id);
   v_before_fp:=coalesce(v_before->'complete_domain_fingerprints','{}'::jsonb); v_after_fp:=coalesce(v_after->'complete_domain_fingerprints','{}'::jsonb);
   v_before_counts:=coalesce(v_before->'complete_domain_counts','{}'::jsonb); v_after_counts:=coalesce(v_after->'complete_domain_counts','{}'::jsonb);
   IF v_before_fp IS DISTINCT FROM v_after_fp OR v_before_counts IS DISTINCT FROM v_after_counts THEN
     RAISE EXCEPTION 'PDC_797_COMPLETE_DOMAIN_DRIFT' USING errcode='55000';
   END IF;
   IF (v_result->'data'->>'receipt_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_797_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
   v_receipt_id:=(v_result->'data'->>'receipt_id')::uuid;
   SELECT r.request_sha256 INTO v_request_hash FROM public.pdc_historical_reconciliation_778_receipts r WHERE r.receipt_id=v_receipt_id;
   IF v_request_hash IS NULL THEN RAISE EXCEPTION 'PDC_797_AGGREGATE_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
   INSERT INTO public.pdc_historical_complete_domain_readbacks_797(receipt_id,request_sha256,vehicle_id,before_authoritative_domain_state,after_authoritative_domain_state,before_complete_domain_fingerprints,after_complete_domain_fingerprints,before_complete_domain_counts,after_complete_domain_counts,complete_domain_fingerprint)
   VALUES(v_receipt_id,v_request_hash,v_vehicle_id,v_before,v_after,v_before_fp,v_after_fp,v_before_counts,v_after_counts,v_after->>'complete_domain_fingerprint') ON CONFLICT(receipt_id) DO NOTHING;
   SELECT jsonb_build_object('receipt_id',receipt_id,'request_sha256',request_sha256,'vehicle_id',vehicle_id,'before_authoritative_domain_state',before_authoritative_domain_state,'after_authoritative_domain_state',after_authoritative_domain_state,'before_complete_domain_fingerprints',before_complete_domain_fingerprints,'after_complete_domain_fingerprints',after_complete_domain_fingerprints,'before_complete_domain_counts',before_complete_domain_counts,'after_complete_domain_counts',after_complete_domain_counts,'complete_domain_fingerprint',complete_domain_fingerprint) INTO v_readback FROM public.pdc_historical_complete_domain_readbacks_797 WHERE receipt_id=v_receipt_id;
   IF v_readback IS NULL OR v_readback->>'request_sha256' IS NULL OR v_readback->>'complete_domain_fingerprint' IS NULL THEN RAISE EXCEPTION 'PDC_797_COMPLETE_DOMAIN_READBACK_FAILED' USING errcode='55000'; END IF;
   v_result:=jsonb_set(v_result,'{data,authoritative_domain_before}',v_readback->'before_authoritative_domain_state',true);
   v_result:=jsonb_set(v_result,'{data,authoritative_domain_state}',v_readback->'after_authoritative_domain_state',true);
   v_result:=jsonb_set(v_result,'{data,no_unrelated_drift}','true'::jsonb,true);
   v_result:=jsonb_set(v_result,'{data,complete_domain_fingerprints}',v_readback->'after_complete_domain_fingerprints',true);
   v_result:=jsonb_set(v_result,'{data,complete_domain_counts}',v_readback->'after_complete_domain_counts',true);
 END IF;
 RETURN v_result;
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('ok',false,'code','historical_reconciliation_782_atomic_rollback');
END
$function$;
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) TO authenticated;
DO $post$
DECLARE v text; own text; acl text; sd boolean;
BEGIN
 FOREACH v IN ARRAY ARRAY['public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb)','public.submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb)','public.submit_pdc_historical_reconciliation_778_pre796(jsonb)','public.submit_pdc_historical_reconciliation_778_pre797(jsonb)','public.submit_pdc_historical_reconciliation_778(jsonb)'] LOOP
   SELECT p.proowner::regrole::text,p.prosecdef,p.proacl::text INTO own,sd,acl FROM pg_proc p WHERE p.oid=v::regprocedure;
   IF own<>'postgres' OR NOT sd OR (v='public.submit_pdc_historical_reconciliation_778(jsonb)' AND acl<>'{authenticated=X/postgres}') OR (v<>'public.submit_pdc_historical_reconciliation_778(jsonb)' AND acl<>'{postgres=X/postgres}') THEN RAISE EXCEPTION 'PDC_806_FUNCTION_SECURITY_POSTCONDITION_FAILED:%',v USING errcode='55000'; END IF;
 END LOOP;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.pdc_historical_authentication_canonical_806(jsonb)'::regprocedure;
 IF position('return v-' in lower(v))=0 OR position('aligned' in v)=0 THEN RAISE EXCEPTION 'PDC_806_CANONICALIZER_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'fb68cfea0065fccd4be555c1df1814f02007e912a30599e8adf8ec5ac8ca7e1d' OR position('pdc_historical_authentication_canonical_806' in v)=0 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v)=0 THEN RAISE EXCEPTION 'PDC_806_WRITER_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'c24bfdd7028cb0989760428dd2893bdef83fdd7dddfcc227263ccb26bab2d997' OR position('pdc_historical_authentication_canonical_806' in v)=0 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v)=0 THEN RAISE EXCEPTION 'PDC_806_793_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778_pre796(jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'a2c6a5bc7fcd11cd11b49548738a374cd2b029290d471889ab600369a73bc7f5' OR position('pdc_historical_authentication_canonical_806' in v)=0 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v)=0 THEN RAISE EXCEPTION 'PDC_806_PRE796_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778_pre797(jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'44a11f173bbb57e1aa6efb7aa74595bdc067db3b45bf5b12bcbd2153151d258c' OR position('pdc_historical_authentication_canonical_806' in v)=0 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v)=0 THEN RAISE EXCEPTION 'PDC_806_PRE797_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'f8b349be16131a94067d3a48118e92ddcf43a6f9a0af7c746a7a65116ca194d0' OR position('pdc_historical_authentication_canonical_806' in v)=0 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v)=0 THEN RAISE EXCEPTION 'PDC_806_PUBLIC_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830223000','806_canonical_frozen_authentication_tuple_successor',ARRAY[
 'canonicalize only the verified derived authentication.aligned export marker at public and nested boundaries',
 'preserve immutable proposal/source-claim conflicts, genuine unclaimed proposal creation, evidence, sibling isolation, replay/idempotency, RLS, grants, task, pilot, outbound and Production fail-closed controls',
 'preserve authenticated 802/672 zero-mailbox containment and unchanged normal 766 runtime behavior'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
