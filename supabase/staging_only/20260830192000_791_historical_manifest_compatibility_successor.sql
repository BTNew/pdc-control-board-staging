-- STAGING ONLY 791: exact authorized attachment-manifest byte successor after 790.
-- Preserve JSONB tuple equality while hashing the original compact field order
-- used by the immutable 773 authorization evidence.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-791-historical-manifest-compatibility',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830191000,790_historical_proposal_conflict_wrapper)' OR to_regprocedure('public.submit_pdc_historical_reconciliation_789_proposal_binding_base(jsonb)') IS NULL OR to_regprocedure('public.submit_pdc_historical_reconciliation_791_manifest_compatibility_base(jsonb)') IS NOT NULL OR to_regclass('public.pdc_historical_proposal_bindings_789') IS NULL THEN RAISE EXCEPTION 'PDC_791_CURRENT_HEAD_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_791_manifest_compatibility_base(p_request jsonb)
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
 v_job_card_count integer:=0; v_sibling_count integer:=0; v_operation_count integer; v_actual_operation_count integer; v_canonical_request text; v_canonical_observation text; v_booking_created boolean:=false; v_completion_created boolean:=false; v_location_scheduled boolean:=false; v_parts_changed boolean:=false; v_status_changed boolean:=false;
 v_proposal public.pdc_ai_intake_proposals%rowtype; v_proposal_id uuid; v_proposal_binding_id uuid:=gen_random_uuid(); v_proposal_observation_match boolean; v_proposal_binding_kind text; v_manifest_text text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_actor<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR v_actor_email<>'sales@broometoyota.com.au'
    OR NOT public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1')
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
 SELECT count(*),max(v.id),max(v.current_location) INTO v_attachment_count,v_known_vehicle_id,v_known_location FROM public.vehicles v WHERE v.stock_number_normalized=v_stock AND v.deleted_at IS NULL;
 IF v_attachment_count>1 THEN RAISE EXCEPTION 'PDC_782_IDENTITY_CONFLICT' USING errcode='P0001'; END IF;
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
$body$;


REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_791_manifest_compatibility_base(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_791_manifest_compatibility_base(jsonb) TO postgres;
CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778(p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
SET statement_timeout='300s'
AS $wrapper$
DECLARE
 v_before jsonb; v_after jsonb; v_location_before text; v_location_after text; v_result jsonb; v_canonical_request text; v_booking_created boolean:=false; v_completion_created boolean:=false; v_location_scheduled boolean:=false; v_parts_changed boolean:=false;
 v_vehicle_id uuid; v_vehicle public.vehicles%rowtype; v_existing public.pdc_historical_reconciliation_778_receipts%rowtype; v_existing_proposal public.pdc_ai_intake_proposals%rowtype; v_child_receipt public.pdc_jobcard_attachment_import_receipts%rowtype; v_request_hash text; v_uid text; v_parent text; v_sender text; v_stock text; v_source jsonb; v_items jsonb; v_auth jsonb; v_runtime jsonb; v_authz public.pdc_historical_reconciliation_writer_authorizations_773%rowtype; v_authz_count integer; v_intake public.ai_email_intake%rowtype; v_intake_id uuid; v_attachment_id uuid; v_child jsonb; v_item jsonb; v_required jsonb; v_work_key text; v_booking_count integer:=0; v_completion_count integer:=0; v_parts_count integer:=0; v_receipt_count integer:=0;
BEGIN
 IF auth.uid()='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid AND lower(btrim(coalesce(auth.jwt()->>'email','')))= 'sales@broometoyota.com.au' AND public.pdc_monitor_staging_guard() AND jsonb_typeof(p_request)='object' AND p_request->>'parent_source_hash' IS NOT NULL AND p_request->>'provider_uid' IS NOT NULL THEN
   SELECT * INTO v_existing_proposal FROM public.pdc_ai_intake_proposals WHERE source_hash=lower(p_request->>'parent_source_hash') AND source_uid=btrim(p_request->>'provider_uid') ORDER BY submitted_at DESC,proposal_id DESC LIMIT 1 FOR UPDATE;
   IF FOUND THEN
     IF v_existing_proposal.status::text<>'pending' THEN RETURN jsonb_build_object('ok',false,'code','historical_proposal_terminal_conflict','data',jsonb_build_object('proposal_id',v_existing_proposal.proposal_id,'status',v_existing_proposal.status,'review_required',true)); END IF;
     IF v_existing_proposal.evidence_hash IS DISTINCT FROM lower(p_request->>'evidence_hash') OR lower(v_existing_proposal.sender_address) IS DISTINCT FROM lower(p_request->>'sender_email') OR v_existing_proposal.authentication IS DISTINCT FROM coalesce(p_request->'authentication','null'::jsonb) OR public.normalize_vehicle_stock_number(v_existing_proposal.stock_number) IS DISTINCT FROM public.normalize_vehicle_stock_number(p_request->>'stock_number') THEN RETURN jsonb_build_object('ok',false,'code','historical_proposal_tuple_conflict','data',jsonb_build_object('proposal_id',v_existing_proposal.proposal_id,'review_required',true,'source_tuple_conflict',true)); END IF;
     IF v_existing_proposal.subject IS DISTINCT FROM p_request->>'subject' OR v_existing_proposal.action_type IS DISTINCT FROM p_request->>'action_type' OR v_existing_proposal.summary IS DISTINCT FROM p_request->>'summary' THEN RETURN jsonb_build_object('ok',false,'code','historical_proposal_payload_conflict','data',jsonb_build_object('proposal_id',v_existing_proposal.proposal_id,'review_required',true,'payload_conflict',true)); END IF;
   END IF;
 END IF;
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au' OR NOT public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1') OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_request) k) IS DISTINCT FROM ARRAY['action_type','attachment_manifest','authentication','canonical_request_utf8','evidence_hash','gateway_instance_id','job_card_children','manifest_high_water_uid','manifest_sha256','manifest_uid_count','manifest_uidvalidity','observations','parent_source_hash','provider_uid','release_manifest_sha256','release_name','release_source_sha','sender_email','source_metadata','stock_number','subject','summary']::text[] THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 v_uid:=btrim(coalesce(p_request->>'provider_uid','')); v_parent:=lower(btrim(coalesce(p_request->>'parent_source_hash',''))); v_sender:=lower(btrim(coalesce(p_request->>'sender_email',''))); v_stock:=public.normalize_vehicle_stock_number(p_request->>'stock_number'); v_source:=coalesce(p_request->'source_metadata','null'::jsonb); v_items:=coalesce(p_request->'attachment_manifest','null'::jsonb); v_auth:=coalesce(p_request->'authentication','null'::jsonb);
 IF p_request->>'gateway_instance_id' IS DISTINCT FROM 'pdc-monitor-staging-sales-uid509-v1' OR p_request->>'release_name' IS DISTINCT FROM 'pdc-monitor-staging-m502-2026.08.44' OR lower(p_request->>'release_source_sha') IS DISTINCT FROM 'e850c319989d98b45b95a28aa815d78e2c2e3a4b' OR lower(p_request->>'release_manifest_sha256') IS DISTINCT FROM 'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' OR p_request->>'manifest_sha256' IS DISTINCT FROM 'aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018' OR p_request->>'manifest_uidvalidity' IS DISTINCT FROM '1' OR p_request->>'manifest_high_water_uid' IS DISTINCT FROM '685' OR p_request->>'manifest_uid_count' IS DISTINCT FROM '669' OR v_request_hash!~'^[a-f0-9]{64}$' OR v_uid!~'^1:[1-9][0-9]{0,5}$' OR v_uid='1:197' OR v_parent!~'^[a-f0-9]{64}$' OR v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$' OR v_stock='13056899' OR NOT public.is_real_vehicle_stock_number(v_stock) OR v_request->>'evidence_hash'!~'^[a-f0-9]{64}$' OR p_request->>'action_type' NOT IN ('board_activate_only','review_only') OR jsonb_typeof(v_auth) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_auth) k) IS DISTINCT FROM ARRAY['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[] OR v_auth->>'sender_domain' IS DISTINCT FROM split_part(v_sender,'@',2) OR v_auth->'gmail_authentication_results' IS DISTINCT FROM 'true'::jsonb OR NOT(v_auth->'spf_aligned'='true'::jsonb OR v_auth->'dkim_aligned'='true'::jsonb OR v_auth->'dmarc_aligned'='true'::jsonb) OR jsonb_typeof(v_items) IS DISTINCT FROM 'array' OR jsonb_array_length(v_items) NOT BETWEEN 1 AND 25 OR jsonb_typeof(p_request->'job_card_children') IS DISTINCT FROM 'array' OR jsonb_array_length(p_request->'job_card_children')>25 OR jsonb_typeof(v_source) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_source) k) IS DISTINCT FROM ARRAY['attachment_names','graph_message_id','internet_message_id','parsed_text','provider_authserv_id','raw_body','received_at','recipient_mailbox','sender_name','uid','uidvalidity']::text[] OR v_source->>'uidvalidity' IS DISTINCT FROM '1' OR v_source->>'uid' IS DISTINCT FROM substring(v_uid FROM '^1:([0-9]+)$') OR v_source->>'provider_authserv_id' IS DISTINCT FROM 'mx.google.com' OR lower(v_source->>'recipient_mailbox') IS DISTINCT FROM 'pmbcontroller@gmail.com' OR v_source->>'received_at' IS NULL OR (v_source->>'received_at')::timestamptz > clock_timestamp()+interval '5 minutes' OR (v_source->>'received_at')::timestamptz < clock_timestamp()-interval '120 days' OR v_source->'attachment_names' IS DISTINCT FROM (SELECT jsonb_agg(m->>'filename' ORDER BY ordinality) FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality)) THEN RETURN jsonb_build_object('ok',false,'code','historical_wrapper_preflight_failed'); END IF;
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
 v_result:=public.submit_pdc_historical_reconciliation_791_manifest_compatibility_base(p_request);
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
$wrapper$;



REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) TO authenticated;
DO $verify$
DECLARE d text; w text; b boolean;
BEGIN
 SELECT pg_get_functiondef('public.submit_pdc_historical_reconciliation_791_manifest_compatibility_base(jsonb)'::regprocedure) INTO d;
 SELECT pg_get_functiondef('public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure) INTO w;
 SELECT relrowsecurity AND relforcerowsecurity INTO b FROM pg_class WHERE oid='public.pdc_historical_proposal_bindings_789'::regclass;
 IF position('v_manifest_text' in lower(d))=0 OR position('to_jsonb(m->>''content_type'')' in lower(d))=0 OR position('submit_pdc_historical_reconciliation_791_manifest_compatibility_base' in lower(w))=0 OR position('historical_proposal_tuple_conflict' in lower(w))=0 OR position('limit 1 for update' in lower(w))=0 OR NOT coalesce(b,false) OR has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_791_manifest_compatibility_base(jsonb)','execute') OR has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute') OR has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute') OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_791_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $verify$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830192000','791_historical_manifest_compatibility_successor',ARRAY['Preserve immutable 773 JSONB attachment tuple equality while hashing the original compact authorized UTF-8 field order','Forward the typed 790 proposal conflict wrapper to the 791 private base without changing proposal rows','Retain binding-table forced RLS, private-base protection, authenticated-only wrapper, atomicity, replay and sibling isolation']);
NOTIFY pgrst,'reload schema';
COMMIT;
