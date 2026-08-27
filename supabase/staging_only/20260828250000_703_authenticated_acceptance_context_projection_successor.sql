-- STAGING ONLY 703: exact-actor synthetic 686 context projection successor.
-- Append-only after live validator head 20260828240000 / 701.
-- Normal Board snapshots and normal 502 vehicle reads are unchanged. This
-- successor admits only a live, uniquely bound, test-marked 686 fixture.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-703-acceptance-context-projection',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h
 FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR lower(coalesce(current_setting('app.environment',true),''))='production'
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828240000'
    OR (SELECT count(*) FROM public.pdc_authenticated_email_plan_validator_evidence_ref_history_701 WHERE event_kind='plan_validator_evidence_ref_precedence_repair')<>1
    OR h<>'227dd190b639c6f21cea1a668c85994c437b950adb155622c6819d2f1eb07e1a'
    OR to_regclass('public.pdc_authenticated_acceptance_context_projection_history_703') IS NOT NULL
    OR to_regprocedure('public.pdc_monitor_authenticated_acceptance_context_projection_703(jsonb)') IS NOT NULL
    OR to_regprocedure('public.read_pdc_agentic_email_vehicle_502_pre_703(uuid)') IS NOT NULL
    OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.read_pdc_agentic_email_vehicle_502(uuid)'::regprocedure)<>'068f0e7be6fe85b6d8a0d9aeed480271fa8a21c5928cdcb1c5e0918668b198aa'
    OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.read_pdc_agentic_email_context_authenticated_684(jsonb)'::regprocedure)<>'412fb6835a401ccb0f32aa864aa7a1a67726b22b373d61cfb23434544cf06834'
    OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_authenticated_684(jsonb)'::regprocedure)<>'86132013a747b69d65682522171da94e886ba6b5005a247eedb64f9cc9fbf100'
 THEN RAISE EXCEPTION 'PDC_703_EXACT_701_CONTEXT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_authenticated_acceptance_context_projection_history_703(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='acceptance_context_projection_successor'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260828240000'),
 successor_head text NOT NULL CHECK(successor_head='20260828250000'),
 validator_sha256 text NOT NULL CHECK(validator_sha256='227dd190b639c6f21cea1a668c85994c437b950adb155622c6819d2f1eb07e1a'),
 predecessor_function_hashes jsonb NOT NULL,
 successor_function_hashes jsonb NOT NULL,
 repair_contract text NOT NULL,
 production_writes boolean NOT NULL CHECK(NOT production_writes),
 task_enabled boolean NOT NULL CHECK(NOT task_enabled),
 mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
 uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_authenticated_acceptance_context_projection_history_703 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_authenticated_acceptance_context_projection_history_703 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_authenticated_acceptance_context_projection_history_703 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_acceptance_context_projection_history_immutable_703() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_703_CONTEXT_PROJECTION_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_acceptance_context_projection_history_immutable_703() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_acceptance_context_projection_history_immutable_703 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_acceptance_context_projection_history_703 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_acceptance_context_projection_history_immutable_703();

CREATE FUNCTION public.pdc_monitor_authenticated_acceptance_context_projection_703(p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $projection$
DECLARE s jsonb; base jsonb; canon jsonb; rows jsonb; state jsonb;
        f public.pdc_authenticated_email_acceptance_campaign_fixtures_686%rowtype;
        r public.pdc_authenticated_email_acceptance_campaign_runs_686%rowtype;
        i public.ai_email_intake%rowtype; a public.ai_email_attachments%rowtype;
        o public.pdc_provider_email_observations%rowtype;
        c public.pdc_authenticated_provider_import_agentic_compatibility_controls_684%rowtype;
        v public.vehicles%rowtype; pu public.vehicle_parts_updates%rowtype;
        wi public.vehicle_work_items%rowtype; b public.pdc_sublet_booking_instances%rowtype;
BEGIN
 IF jsonb_typeof(p_evidence)<>'object' OR auth.role()<>'authenticated'
    OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
    OR p_evidence->>'gateway_instance_id'<>'pdc-monitor-staging-sales-uid509-v1'
    OR p_evidence->>'provider_uid' IS NULL
    OR p_evidence->>'provider_uid' !~ '^imap_uid:[0-9]+$'
    OR substring(p_evidence->>'provider_uid' FROM 10)::bigint<515
 THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required','ambiguous',true,'vehicles','[]'::jsonb); END IF;
 s:=public.pdc_monitor_authenticated_acceptance_scope_686(
   nullif(p_evidence->>'intake_id','')::uuid,
   lower(btrim(coalesce(p_evidence->>'source_hash',''))),
   nullif(p_evidence->>'claim_token','')::uuid);
 IF s->>'ok'<>'true' THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required','ambiguous',true,'vehicles','[]'::jsonb); END IF;
 SELECT * INTO f FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686
   WHERE fixture_id=(s->>'fixture_id')::uuid AND active AND run_id=(s->>'run_id')::uuid
     AND intake_id=nullif(p_evidence->>'intake_id','')::uuid
     AND provider_uid=p_evidence->>'provider_uid'
     AND source_hash=lower(p_evidence->>'source_hash')
     AND claim_token=nullif(p_evidence->>'claim_token','')::uuid;
 SELECT * INTO r FROM public.pdc_authenticated_email_acceptance_campaign_runs_686 WHERE run_id=f.run_id AND status='active';
 SELECT * INTO c FROM public.pdc_authenticated_provider_import_agentic_compatibility_controls_684
   WHERE singleton AND enabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes;
 SELECT * INTO i FROM public.ai_email_intake WHERE id=f.intake_id AND status='processing' AND locked_by=auth.uid()
   AND claim_token=f.claim_token AND gateway_instance_id=c.gateway_instance_id AND provider_uid=f.provider_uid
   AND source_hash=f.source_hash AND coalesce(nullif(btrim(internet_message_id),''),graph_message_id)=f.message_id
   AND lower(btrim(sender_email))=lower(f.sender) AND recipient_mailbox='pmbcontroller@gmail.com'
   AND provider_authserv_id='mx.google.com' AND provider_authentication->'gmail_authentication_results'='true'::jsonb;
 SELECT * INTO a FROM public.ai_email_attachments WHERE id=f.attachment_id AND intake_id=f.intake_id
   AND source_hash=f.attachment_hash AND lower(content_type)='application/pdf' AND text_extraction_status='extracted';
 SELECT * INTO o FROM public.pdc_provider_email_observations WHERE observation_id=f.observation_id AND intake_id=f.intake_id
   AND attachment_id=f.attachment_id AND parent_source_hash=f.source_hash AND attachment_source_hash=f.attachment_hash
   AND provider_message_id=f.message_id AND provider_authserv_id='mx.google.com';
 SELECT * INTO v FROM public.vehicles WHERE id=f.vehicle_id;
 IF f.fixture_id IS NULL OR r.run_id IS NULL OR c.actor_id IS NULL OR i.id IS NULL OR a.id IS NULL OR o.observation_id IS NULL
    OR r.actor_id<>auth.uid() OR r.actor_email<>'sales@broometoyota.com.au' OR r.jwt_role<>'authenticated'
    OR r.server_application_role<>'importer' OR r.gateway_instance_id<>c.gateway_instance_id
    OR r.release_name<>'pdc-monitor-staging-m502-2026.08.44'
    OR r.planner_sha256<>'7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'
    OR r.trust_receipt_sha256<>'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'
    OR c.actor_id<>auth.uid() OR c.actor_email<>'sales@broometoyota.com.au'
    OR c.server_application_role<>'importer' OR c.gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
    OR c.release_name<>'pdc-monitor-staging-m502-2026.08.44'
    OR c.planner_sha256<>r.planner_sha256 OR c.trust_receipt_sha256<>r.trust_receipt_sha256
    OR v.id IS NULL OR v.lifecycle_state<>'active' OR v.deleted_at IS NOT NULL
    OR v.source_payload->>'test_fixture' IS DISTINCT FROM 'true'
    OR v.source_payload->>'campaign' IS DISTINCT FROM '686'
    OR v.source_payload->>'namespace' IS DISTINCT FROM r.namespace
    OR v.permanent_vehicle_id NOT LIKE 'PDC-ACCEPT-686-%'
    OR i.subject NOT LIKE 'PDC Acceptance 686 %'
    OR lower(btrim(i.sender_email)) NOT LIKE 'pdc-acceptance-%@staging.pdc-workshop.example.com'
 THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required','ambiguous',true,'vehicles','[]'::jsonb); END IF;
 SELECT * INTO pu FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1;
 SELECT * INTO wi FROM public.vehicle_work_items WHERE vehicle_id=v.id AND upper(work_key)='PARTS' ORDER BY updated_at DESC LIMIT 1;
 SELECT * INTO b FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v.id AND status='active' ORDER BY out_date,booking_id LIMIT 1;
 state:=jsonb_build_object('vehicle',to_jsonb(v),'parts',jsonb_build_object('required',coalesce(pu.parts_required,false),'ordered',coalesce(pu.parts_ordered,false),'received',coalesce(pu.parts_received,false),'eta',pu.worst_eta,'completed',coalesce(wi.completed,false)),'sublet',case when b.booking_id IS NULL then '{}'::jsonb else jsonb_build_object('booking_id',b.booking_id,'provider_id',b.provider_id,'provider_name',b.provider_name,'out_date',b.out_date,'expected_return_date',b.expected_return_date,'version',b.version,'status',b.status) end);
 base:=public.read_pdc_agentic_email_context_502(p_evidence);
 IF base->>'ok' IS DISTINCT FROM 'true' THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required','ambiguous',true,'vehicles','[]'::jsonb); END IF;
 canon:=base->'canonical_evidence'||jsonb_build_object('acceptance_context_projection',jsonb_build_object('contract_version','pdc-acceptance-context-projection-703.1','run_id',r.run_id,'namespace',r.namespace,'fixture_id',f.fixture_id,'intake_id',f.intake_id,'claim_token',f.claim_token,'vehicle_id',v.id,'provider_uid',f.provider_uid,'source_hash',f.source_hash,'gateway_instance_id',c.gateway_instance_id,'release_name',r.release_name,'planner_sha256',r.planner_sha256,'trust_receipt_sha256',r.trust_receipt_sha256,'synthetic_fixture',true,'board_snapshot_bypass',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'production_writes',false,'canonical_state',state));
 rows:=jsonb_build_array(jsonb_build_object('vehicle_id',v.id,'context_kind','acceptance_synthetic_fixture','identity',jsonb_build_object('stock_number',coalesce(v.stock_number_normalized,''),'vin',coalesce(v.vin_normalized,''),'job_card_number',coalesce(v.job_card_number,''),'customer',coalesce(v.customer_name,'')),'navision','{}'::jsonb,'state',state,'board',jsonb_build_object('id',v.id,'stock_number',v.stock_number,'version',v.version,'current_location',v.current_location,'visible_on_board',v.visible_on_board,'acceptance_only',true)));
 RETURN public.pdc_agentic_email_issue_context_502(canon,rows,'agentic_context',false);
EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required','ambiguous',true,'vehicles','[]'::jsonb);
END $projection$;
REVOKE ALL ON FUNCTION public.pdc_monitor_authenticated_acceptance_context_projection_703(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.pdc_monitor_authenticated_acceptance_vehicle_projection_703(p_vehicle_id uuid,p_context_receipt_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $vehicle$
DECLARE q public.pdc_agentic_email_context_receipts_502%rowtype; f public.pdc_authenticated_email_acceptance_campaign_fixtures_686%rowtype; r public.pdc_authenticated_email_acceptance_campaign_runs_686%rowtype; c public.pdc_authenticated_provider_import_agentic_compatibility_controls_684%rowtype; v public.vehicles%rowtype; pu public.vehicle_parts_updates%rowtype; wi public.vehicle_work_items%rowtype; b public.pdc_sublet_booking_instances%rowtype; parity jsonb; all_bookings jsonb;
BEGIN
 IF auth.role()<>'authenticated' OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au' THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required'); END IF;
 SELECT * INTO q FROM public.pdc_agentic_email_context_receipts_502 WHERE context_receipt_id=p_context_receipt_id AND actor_id=auth.uid();
 SELECT * INTO f FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 WHERE fixture_id=nullif(q.canonical_evidence#>>'{acceptance_context_projection,fixture_id}','')::uuid AND active AND vehicle_id=p_vehicle_id;
 SELECT * INTO r FROM public.pdc_authenticated_email_acceptance_campaign_runs_686 WHERE run_id=f.run_id AND status='active';
 SELECT * INTO c FROM public.pdc_authenticated_provider_import_agentic_compatibility_controls_684 WHERE singleton AND enabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id;
 IF q.context_receipt_id IS NULL OR q.canonical_evidence#>>'{acceptance_context_projection,contract_version}'<>'pdc-acceptance-context-projection-703.1'
    OR q.canonical_evidence#>>'{acceptance_context_projection,run_id}'<>r.run_id::text
    OR q.canonical_evidence#>>'{acceptance_context_projection,namespace}'<>r.namespace
    OR q.canonical_evidence#>>'{acceptance_context_projection,vehicle_id}'<>p_vehicle_id::text
    OR q.canonical_evidence#>>'{acceptance_context_projection,gateway_instance_id}'<>c.gateway_instance_id
    OR q.canonical_evidence#>>'{acceptance_context_projection,release_name}'<>c.release_name
    OR q.canonical_evidence#>>'{acceptance_context_projection,planner_sha256}'<>c.planner_sha256
    OR q.canonical_evidence#>>'{acceptance_context_projection,trust_receipt_sha256}'<>c.trust_receipt_sha256
    OR q.canonical_evidence#>>'{acceptance_context_projection,provider_uid}'<>f.provider_uid
    OR q.canonical_evidence#>>'{acceptance_context_projection,source_hash}'<>f.source_hash
    OR v.id IS NULL OR v.lifecycle_state<>'active' OR v.deleted_at IS NOT NULL
    OR v.source_payload->>'test_fixture' IS DISTINCT FROM 'true' OR v.source_payload->>'campaign' IS DISTINCT FROM '686'
    OR v.source_payload->>'namespace' IS DISTINCT FROM r.namespace
 THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required'); END IF;
 SELECT * INTO pu FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1;
 SELECT * INTO wi FROM public.vehicle_work_items WHERE vehicle_id=v.id AND upper(work_key)='PARTS' ORDER BY updated_at DESC LIMIT 1;
 SELECT * INTO b FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v.id AND status='active' ORDER BY out_date,booking_id LIMIT 1;
 SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',x.booking_id,'vehicle_id',x.vehicle_id,'vehicle_version',x.vehicle_version,'provider_id',x.provider_id,'provider_name',x.provider_name,'provider_email',x.provider_email,'out_date',x.out_date,'expected_return_date',x.expected_return_date,'status',x.status,'version',x.version,'notes',x.notes,'updated_at',x.updated_at) ORDER BY x.out_date,x.booking_id),'[]'::jsonb) INTO all_bookings FROM public.pdc_sublet_booking_instances x WHERE x.vehicle_id=v.id;
 parity:=public.pdc_operation_projection_parity_493(p_vehicle_id);
 RETURN jsonb_build_object('ok',true,'vehicle_id',p_vehicle_id,'vehicle',jsonb_build_object('id',v.id,'stock_number',v.stock_number,'version',v.version,'job_card_number',v.job_card_number,'current_location',v.current_location,'eta',v.eta_to_kewdale,'notes',v.notes,'lifecycle_state',v.lifecycle_state,'visible_on_board',v.visible_on_board,'deleted_at',v.deleted_at),'parts',jsonb_build_object('complete',coalesce(wi.completed,false),'eta',pu.worst_eta,'required',coalesce(pu.parts_required,false),'update',coalesce(jsonb_build_object('parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,'parts_received',pu.parts_received,'parts_stoppage',pu.parts_stoppage,'parts_stoppage_reason',pu.parts_stoppage_reason,'worst_eta',pu.worst_eta,'updated_at',pu.updated_at),'{}'::jsonb)),'sublet',jsonb_build_object('booking_date',b.out_date,'booking',case when b.booking_id IS NULL then '{}'::jsonb else to_jsonb(b) end),'sublet_bookings',all_bookings,'booking','{}'::jsonb,'bookings','[]'::jsonb,'workgroups',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.work_key) FROM public.vehicle_work_items x WHERE x.vehicle_id=v.id),'[]'::jsonb),'operations',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.source_row_no,x.operation_line_id) FROM public.pdc_authenticated_email_operation_lines x WHERE x.vehicle_id=v.id),'[]'::jsonb),'qc_operations','[]'::jsonb,'operation_parity',parity,'context_projection','acceptance_synthetic_703');
EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required');
END $vehicle$;
REVOKE ALL ON FUNCTION public.pdc_monitor_authenticated_acceptance_vehicle_projection_703(uuid,uuid) FROM public,anon,authenticated,service_role,pdc_email_monitor;

ALTER FUNCTION public.read_pdc_agentic_email_vehicle_502(uuid) RENAME TO read_pdc_agentic_email_vehicle_502_pre_703;
CREATE FUNCTION public.read_pdc_agentic_email_vehicle_502(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $read$
DECLARE q text; projected jsonb;
BEGIN
 q:=nullif(current_setting('pdc_acceptance_context_receipt_703',true),'');
 IF q IS NOT NULL AND q~'^[0-9a-f-]{36}$' THEN
   projected:=public.pdc_monitor_authenticated_acceptance_vehicle_projection_703(p_vehicle_id,q::uuid);
   IF projected->>'ok'='true' THEN RETURN projected; END IF;
   RETURN jsonb_build_object('ok',false,'code','vehicle_not_found');
 END IF;
 RETURN public.read_pdc_agentic_email_vehicle_502_pre_703(p_vehicle_id);
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_agentic_email_vehicle_502(uuid) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.read_pdc_agentic_email_vehicle_502(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.read_pdc_agentic_email_context_authenticated_684(p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $context$
BEGIN
 IF coalesce(p_evidence->>'provider_uid','')~'^imap_uid:[0-9]+$' AND substring(p_evidence->>'provider_uid' FROM 10)::bigint>=515 THEN
   RETURN public.pdc_monitor_authenticated_acceptance_context_projection_703(p_evidence);
 END IF;
 IF NOT public.pdc_monitor_authenticated_uid514_source_scope_684(p_evidence) THEN RETURN jsonb_build_object('ok',false,'code','authenticated_uid514_source_required','ambiguous',true,'vehicles','[]'::jsonb); END IF;
 RETURN public.read_pdc_agentic_email_context_502(p_evidence);
END $context$;

CREATE OR REPLACE FUNCTION public.execute_pdc_agentic_email_action_authenticated_684(p_action jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $execute$
DECLARE p public.pdc_agentic_email_plans_502%rowtype; marker jsonb; probe jsonb; result jsonb;
BEGIN
 IF NOT public.pdc_monitor_authenticated_uid514_source_scope_684(p_action->'source_binding') THEN
   IF coalesce(p_action->'source_binding'->>'provider_uid','')~'^imap_uid:[0-9]+$' AND substring(p_action->'source_binding'->>'provider_uid' FROM 10)::bigint>=515 THEN
     SELECT * INTO p FROM public.pdc_agentic_email_plans_502 WHERE actor_id=auth.uid() AND plan_hash=p_action->>'plan_hash';
     SELECT canonical_evidence->'acceptance_context_projection' INTO marker FROM public.pdc_agentic_email_context_receipts_502 WHERE context_receipt_id=p.context_receipt_id AND actor_id=auth.uid();
     IF marker IS NULL OR marker->>'vehicle_id' IS DISTINCT FROM coalesce(p_action->>'planned_vehicle_id',p_action->>'vehicle_id') OR marker->>'gateway_instance_id' IS DISTINCT FROM p_action#>>'{source_binding,gateway_instance_id}' OR marker->>'release_name' IS DISTINCT FROM 'pdc-monitor-staging-m502-2026.08.44' OR marker->>'planner_sha256' IS DISTINCT FROM '7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' OR marker->>'trust_receipt_sha256' IS DISTINCT FROM 'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required'); END IF;
     probe:=public.pdc_monitor_authenticated_acceptance_vehicle_projection_703((coalesce(p_action->>'planned_vehicle_id',p_action->>'vehicle_id'))::uuid,p.context_receipt_id);
     IF probe->>'ok' IS DISTINCT FROM 'true' THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required'); END IF;
     PERFORM set_config('pdc_acceptance_context_receipt_703',p.context_receipt_id::text,true);
     result:=public.execute_pdc_agentic_email_action_502(p_action);
     RETURN result;
   END IF;
   RETURN jsonb_build_object('ok',false,'code','authenticated_uid514_source_required');
 END IF;
 RETURN public.execute_pdc_agentic_email_action_502(p_action);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('ok',false,'code','acceptance_context_projection_required');
END $execute$;

INSERT INTO public.pdc_authenticated_acceptance_context_projection_history_703(event_key,event_kind,predecessor_head,successor_head,validator_sha256,predecessor_function_hashes,successor_function_hashes,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed)
VALUES(encode(extensions.digest(convert_to('pdc-staging-703-acceptance-context-projection|forward','UTF8'),'sha256'),'hex'),'acceptance_context_projection_successor','20260828240000','20260828250000','227dd190b639c6f21cea1a668c85994c437b950adb155622c6819d2f1eb07e1a',jsonb_build_object('read_vehicle','068f0e7be6fe85b6d8a0d9aeed480271fa8a21c5928cdcb1c5e0918668b198aa','read_context_684','412fb6835a401ccb0f32aa864aa7a1a67726b22b373d61cfb23434544cf06834','execute_684','86132013a747b69d65682522171da94e886ba6b5005a247eedb64f9cc9fbf100'),jsonb_build_object('successor','computed_after_install'),'Only an active uniquely namespaced test-marked 686 fixture for the exact authenticated actor, gateway, .44 release, planner and trust may receive a direct server-side vehicle/Parts/ETA/Sublet context projection; normal Board snapshots and normal vehicle reads remain unchanged; strict 502 receipts, hashes, replay, RLS, UID514 and production controls remain intact',false,false,false,false);

DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_authenticated_acceptance_context_projection_history_703 WHERE event_kind='acceptance_context_projection_successor')<>1
    OR to_regprocedure('public.read_pdc_agentic_email_vehicle_502_pre_703(uuid)') IS NULL
    OR to_regprocedure('public.pdc_monitor_authenticated_acceptance_context_projection_703(jsonb)') IS NULL
    OR to_regprocedure('public.pdc_monitor_authenticated_acceptance_vehicle_projection_703(uuid,uuid)') IS NULL
    OR to_regprocedure('public.read_pdc_agentic_email_vehicle_502(uuid)') IS NULL
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_703_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828250000','703_authenticated_acceptance_context_projection_successor',ARRAY['Exact live 701 validator hash and predecessor function guards','Exact actor/gateway/release/planner/trust, active namespaced fixture, UID>=515 and synthetic source markers','Server-side synthetic vehicle and canonical Parts/ETA/Sublet projection is persisted as a strict 502 context receipt/evidence hash','Only transaction-local execute pre-read uses the projection; normal Board snapshot and normal vehicle reads fall through unchanged','Immutable forced-RLS history; wrong actor/gateway/source/noncampaign/cleaned fixture fail closed; UID514/task/mailbox/outbound/Production unchanged']);
NOTIFY pgrST,'reload schema';
COMMIT;
