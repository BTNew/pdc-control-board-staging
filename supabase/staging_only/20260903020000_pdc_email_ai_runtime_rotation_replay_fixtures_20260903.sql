-- STAGING-only runtime-rotation replay and immutable v2 acceptance fixtures.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903020000-email-ai-runtime-rotation-fixtures',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR v_head<>'20260903010000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903010000' AND name='workshop_eta_plus_seven_authority_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903020000')
     OR to_regprocedure('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)') IS NULL
     OR to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_source_evidence_digest_20260901(text,text,text,text,timestamptz,text,text,text,text,jsonb)') IS NULL
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_runtime_identities WHERE auth_user_id='e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8'::uuid AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.vehicles WHERE id='2cc5e9b8-7114-5d77-ada5-b296c9d10a9f'::uuid AND deleted_at IS NULL AND lifecycle_state::text='active' AND visible_on_board)<>1
     OR public.pdc_email_ai_v2_validated_operation_source_20260902('2cc5e9b8-7114-5d77-ada5-b296c9d10a9f'::uuid)='{}'::jsonb
  THEN RAISE EXCEPTION 'PDC_20260903020000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_acceptance_fixtures_20260903(
  fixture_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_no integer NOT NULL UNIQUE CHECK(scenario_no BETWEEN 1 AND 14),
  scenario_key text NOT NULL UNIQUE,
  source_receipt_id uuid NOT NULL UNIQUE REFERENCES public.ai_email_intake(id),
  source_digest text NOT NULL UNIQUE CHECK(source_digest~'^[a-f0-9]{64}$'),
  evidence_digest text NOT NULL UNIQUE CHECK(evidence_digest~'^[a-f0-9]{64}$'),
  attachment_digests jsonb NOT NULL CHECK(jsonb_typeof(attachment_digests)='array' AND jsonb_array_length(attachment_digests)=1),
  source_message_id text NOT NULL UNIQUE,
  source_thread_id text NOT NULL UNIQUE,
  target_vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
  authoritative_snapshot jsonb NOT NULL CHECK(jsonb_typeof(authoritative_snapshot)='object'),
  operation_source jsonb NOT NULL CHECK(jsonb_typeof(operation_source)='object'),
  fixture_contract text NOT NULL CHECK(fixture_contract='pdc-email-ai-v2-acceptance-fixture/20260903'),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixtures_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixtures_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_v2_acceptance_fixtures_20260903 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_email_ai_v2_acceptance_fixture_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $immutable$
BEGIN
  RAISE EXCEPTION 'PDC_EMAIL_AI_V2_ACCEPTANCE_FIXTURE_IMMUTABLE' USING errcode='55000';
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_acceptance_fixture_immutable_20260903() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_v2_acceptance_fixture_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_acceptance_fixtures_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_acceptance_fixture_immutable_20260903();

DO $fixtures$
DECLARE
  v_scenarios text[]:=ARRAY[
    'exact_vehicle_identity','job_card_activation','parts_eta_state_update','parts_complete_update',
    'multi_action_email','all_operation_lines_accounted','explicit_hours_preserved',
    'missing_hours_estimated_with_provenance','ambiguous_identity_review','revised_superseding_evidence',
    'replay_idempotency','taxonomy_review','typed_write_readback_board_intake_parity',
    'restart_recovery_no_duplicate_effect'
  ];
  v_descriptions text[]:=ARRAY[
    'Resolve exact Stock 13059806 and backend record dd31d0a4-3e2f-4163-befd-93d59d7d6019 without creating a duplicate vehicle.',
    'Confirm Job Card J139125567 for Stock 13059806 using the attached complete source.',
    'Set a future Parts ETA for Stock 13059806 from explicit correspondence evidence.',
    'Mark Parts complete for Stock 13059806 from explicit correspondence evidence.',
    'Apply two independent clear instructions for Stock 13059806 and account for each separately.',
    'Account for every attached Job Card operation line, including lines that require REVIEW.',
    'Preserve explicit 0.00 and 2.50 hour values exactly for attached operation lines.',
    'Estimate missing Pre-Delivery at 1.0 hour with AI ESTIMATE provenance and leave it editable.',
    'Vehicle identity is ambiguous; create a REVIEW receipt and dispatch no action RPC.',
    'Treat the attached revision as superseding prior evidence while retaining immutable provenance.',
    'Replay this byte-identical successful source-bound plan and return the original receipts.',
    'Mixed FMG signage / GVM / GCM / Tare decals require taxonomy REVIEW; do not infer Hoist or Sublet.',
    'Apply typed writes, perform authoritative read-back, and prove Board/AI Intake parity.',
    'Restart after receipt persistence and recover without a duplicate effect.'
  ];
  v_no integer;
  v_key text;
  v_body text;
  v_attachment_text text;
  v_source_receipt_id uuid;
  v_attachment_id uuid;
  v_message_id text;
  v_thread_id text;
  v_provider_uid text;
  v_source_digest text;
  v_attachment_digest text;
  v_evidence_digest text;
  v_received_at timestamptz;
  v_snapshot jsonb;
  v_operation_source jsonb;
BEGIN
  SELECT jsonb_build_object(
    'captured_at','2026-09-03T00:30:00+00:00',
    'vehicle',to_jsonb(v),
    'work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key,w.id) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),
    'parts_update',coalesce((SELECT to_jsonb(p) FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id ORDER BY p.updated_at DESC,p.id DESC LIMIT 1),'{}'::jsonb),
    'board_revision',(SELECT revision FROM public.pdc_email_vehicle_revision WHERE singleton),
    'source','authoritative_staging_snapshot'
  ), public.pdc_email_ai_v2_validated_operation_source_20260902(v.id)
  INTO v_snapshot,v_operation_source
  FROM public.vehicles v WHERE v.id='2cc5e9b8-7114-5d77-ada5-b296c9d10a9f'::uuid;

  FOR v_no IN SELECT generate_series(1,14) LOOP
    v_key:=v_scenarios[v_no];
    v_message_id:=format('<pdc-v2-acceptance-20260903-%s@staging.invalid>',lpad(v_no::text,2,'0'));
    v_thread_id:=format('pdc-v2-acceptance-20260903-thread-%s',lpad(v_no::text,2,'0'));
    v_provider_uid:=format('fixture:pdc-v2-acceptance-20260903:%s',lpad(v_no::text,2,'0'));
    v_received_at:='2026-09-03T00:30:00+00:00'::timestamptz+make_interval(secs=>v_no);
    v_body:=format('STAGING IMMUTABLE ACCEPTANCE FIXTURE %s/14 [%s]. %s No outbound response is authorised.',v_no,v_key,v_descriptions[v_no]);
    v_attachment_text:=format('Fixture %s [%s]\nStock: 13059806\nJob Card: J139125567\nOP 010 Pre-Delivery explicit hours: missing\nOP 020 Wheel Nut Indicator Set explicit hours: 2.50\nOP 030 Inspection explicit hours: 0.00\nEvidence instruction: %s',v_no,v_key,v_descriptions[v_no]);
    v_source_digest:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc-email-ai-v2-acceptance-fixture/20260903','scenario_no',v_no,'scenario_key',v_key,'body',v_body)::text,'UTF8'),'sha256'),'hex');
    v_attachment_digest:=encode(extensions.digest(convert_to(v_attachment_text,'UTF8'),'sha256'),'hex');
    v_source_receipt_id:=gen_random_uuid();
    v_attachment_id:=gen_random_uuid();

    INSERT INTO public.ai_email_intake(
      id,status,subject,sender_email,sender_name,received_at,graph_message_id,graph_thread_id,internet_message_id,
      attachment_names,raw_body,parsed_text,extracted_data,confidence,warnings,processing_result,linked_vehicle_id,
      source_hash,recipient_mailbox,provider_uid,revision_summary,gateway_instance_id,provider_authserv_id,provider_authentication
    ) VALUES(
      v_source_receipt_id,'received',format('[STAGING FIXTURE %s/14] %s',v_no,v_key),'acceptance-fixture@staging.invalid','PDC v2 Acceptance Fixture',v_received_at,
      v_message_id,v_thread_id,v_message_id,ARRAY[format('pdc-v2-acceptance-%s.txt',lpad(v_no::text,2,'0'))],v_body,v_body,
      jsonb_build_object('test_fixture',true,'immutable',true,'fixture_contract','pdc-email-ai-v2-acceptance-fixture/20260903','scenario_no',v_no,'scenario_key',v_key,
        'job_card_number','J139125567','stock_number','13059806','backend_record_id','dd31d0a4-3e2f-4163-befd-93d59d7d6019',
        'operation_lines',jsonb_build_array(
          jsonb_build_object('operation_no','010','description','Pre-Delivery','estimated_hours',null,'required_provenance','AI ESTIMATE','default_hours',1.0),
          jsonb_build_object('operation_no','020','description','Wheel Nut Indicator Set','estimated_hours',2.50,'required_provenance','EXPLICIT SOURCE'),
          jsonb_build_object('operation_no','030','description','Inspection','estimated_hours',0.00,'required_provenance','EXPLICIT SOURCE')),
        'authoritative_snapshot',v_snapshot,'operation_source',v_operation_source),
      1.0,ARRAY[]::text[],jsonb_build_object('fixture_only',true,'mailbox_contacted',false,'outbound_email',false),
      '2cc5e9b8-7114-5d77-ada5-b296c9d10a9f',v_source_digest,NULL,v_provider_uid,
      jsonb_build_object('fixture_only',true,'supersedes_scenario',case when v_no=10 then 6 else null end),
      'pdc-email-ai-v2-acceptance-fixtures-20260903','staging-fixture.local',jsonb_build_object('synthetic',true,'authenticated_source',true)
    );

    INSERT INTO public.ai_email_attachments(
      id,intake_id,graph_attachment_id,file_name,content_type,size_bytes,text_extraction_status,extracted_text,source_hash
    ) VALUES(
      v_attachment_id,v_source_receipt_id,format('fixture-attachment-%s',v_no),format('pdc-v2-acceptance-%s.txt',lpad(v_no::text,2,'0')),
      'text/plain',octet_length(convert_to(v_attachment_text,'UTF8')),'completed',v_attachment_text,v_attachment_digest
    );

    v_evidence_digest:=public.pdc_email_ai_successor_source_evidence_digest_20260901(
      v_source_digest,NULL,v_message_id,v_thread_id,v_received_at,'acceptance-fixture@staging.invalid',
      format('[STAGING FIXTURE %s/14] %s',v_no,v_key),v_provider_uid,v_body,jsonb_build_array(v_attachment_digest));
    UPDATE public.ai_email_intake
      SET extracted_data=extracted_data||jsonb_build_object('pdc_email_ai_evidence_digest',v_evidence_digest),updated_at=created_at
      WHERE id=v_source_receipt_id;

    INSERT INTO public.pdc_email_ai_v2_acceptance_fixtures_20260903(
      scenario_no,scenario_key,source_receipt_id,source_digest,evidence_digest,attachment_digests,
      source_message_id,source_thread_id,target_vehicle_id,authoritative_snapshot,operation_source,
      fixture_contract,production_writes,mailbox_contacted,outbound_email
    ) VALUES(
      v_no,v_key,v_source_receipt_id,v_source_digest,v_evidence_digest,jsonb_build_array(v_attachment_digest),
      v_message_id,v_thread_id,'2cc5e9b8-7114-5d77-ada5-b296c9d10a9f',v_snapshot,v_operation_source,
      'pdc-email-ai-v2-acceptance-fixture/20260903',false,false,false
    );
  END LOOP;
END $fixtures$;

CREATE FUNCTION public.pdc_email_ai_v2_acceptance_source_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $immutable$
BEGIN
  IF EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_20260903 f WHERE f.source_receipt_id=OLD.id) THEN
    RAISE EXCEPTION 'PDC_EMAIL_AI_V2_ACCEPTANCE_SOURCE_IMMUTABLE' USING errcode='55000';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_acceptance_source_immutable_20260903() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_v2_acceptance_source_immutable_20260903
BEFORE UPDATE OR DELETE ON public.ai_email_intake
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_acceptance_source_immutable_20260903();

CREATE FUNCTION public.pdc_email_ai_v2_acceptance_attachment_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $immutable$
BEGIN
  IF EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_20260903 f WHERE f.source_receipt_id=OLD.intake_id) THEN
    RAISE EXCEPTION 'PDC_EMAIL_AI_V2_ACCEPTANCE_ATTACHMENT_IMMUTABLE' USING errcode='55000';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_acceptance_attachment_immutable_20260903() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_v2_acceptance_attachment_immutable_20260903
BEFORE UPDATE OR DELETE ON public.ai_email_attachments
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_acceptance_attachment_immutable_20260903();

CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_exact_success_replay_20260903(
  p_plan jsonb,
  p_actor uuid,
  p_email text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path=pg_catalog,public,auth,extensions AS $replay$
DECLARE
  v_successor public.pdc_email_ai_successor_runtime_identities%rowtype;
  v_existing public.pdc_email_ai_successor_transaction_receipts%rowtype;
  v_matches integer:=0;
  v_action_receipt_ids jsonb:='[]'::jsonb;
BEGIN
  IF jsonb_typeof(p_plan)<>'object'
     OR p_actor IS NULL OR nullif(lower(btrim(p_email)),'') IS NULL
     OR coalesce(p_plan->>'source_receipt_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR coalesce(p_plan->>'source_digest','') !~ '^[a-f0-9]{64}$'
     OR coalesce(p_plan->>'evidence_digest','') !~ '^[a-f0-9]{64}$'
  THEN RETURN NULL; END IF;

  SELECT * INTO v_successor
  FROM public.pdc_email_ai_successor_runtime_identities
  WHERE auth_user_id=p_actor AND normalized_email=lower(btrim(p_email))
    AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor'
    AND active AND revoked_at IS NULL;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT count(*) INTO v_matches
  FROM public.pdc_email_ai_successor_transaction_receipts t
  JOIN public.pdc_email_ai_successor_runtime_identities predecessor ON t.identity_id=predecessor.identity_id
  WHERE predecessor.environment=v_successor.environment
    AND predecessor.identity_purpose=v_successor.identity_purpose
    AND (predecessor.identity_id=v_successor.identity_id OR (
      predecessor.created_at<v_successor.created_at AND predecessor.revoked_at IS NOT NULL AND NOT predecessor.active
    ))
    AND t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid
    AND t.source_digest=lower(p_plan->>'source_digest')
    AND t.evidence_digest=lower(p_plan->>'evidence_digest')
    AND t.aggregate_disposition::text='SUCCESS'
    AND t.readback_parity
    AND t.plan_hash=public.pdc_email_ai_successor_hash(p_plan)
    AND t.typed_plan=p_plan
    AND EXISTS(
      SELECT 1 FROM public.ai_email_intake i
      WHERE i.id=t.source_receipt_id AND i.duplicate_of IS NULL
        AND lower(coalesce(i.source_hash,''))=t.source_digest
        AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=t.evidence_digest
        AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->>'source_message_id')
        AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->>'source_thread_id')
    );
  IF v_matches=0 THEN RETURN NULL; END IF;
  IF v_matches<>1 THEN
    RETURN jsonb_build_object('ok',false,'code','exact_successful_replay_ambiguous','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb,'production_writes',false,'mailbox_contacted',false,'outbound_email',false);
  END IF;

  SELECT t.* INTO v_existing
  FROM public.pdc_email_ai_successor_transaction_receipts t
  JOIN public.pdc_email_ai_successor_runtime_identities predecessor ON t.identity_id=predecessor.identity_id
  WHERE predecessor.environment=v_successor.environment
    AND predecessor.identity_purpose=v_successor.identity_purpose
    AND (predecessor.identity_id=v_successor.identity_id OR (
      predecessor.created_at<v_successor.created_at AND predecessor.revoked_at IS NOT NULL AND NOT predecessor.active
    ))
    AND t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid
    AND t.source_digest=lower(p_plan->>'source_digest')
    AND t.evidence_digest=lower(p_plan->>'evidence_digest')
    AND t.aggregate_disposition::text='SUCCESS' AND t.readback_parity
    AND t.plan_hash=public.pdc_email_ai_successor_hash(p_plan)
    AND t.typed_plan=p_plan;

  SELECT coalesce(jsonb_agg(a.action_receipt_id ORDER BY a.created_at,a.action_receipt_id),'[]'::jsonb)
  INTO v_action_receipt_ids
  FROM public.pdc_email_ai_successor_action_receipts a
  WHERE a.transaction_id=v_existing.transaction_id;

  RETURN coalesce(v_existing.response,'{}'::jsonb) || jsonb_build_object(
    'ok',true,'code','pdc_email_ai_typed_action_surface_verified','disposition','SUCCESS',
    'transaction_id',v_existing.transaction_id,'source_receipt_id',v_existing.source_receipt_id,
    'plan_hash',v_existing.plan_hash,'readback_parity',true,'action_receipt_ids',v_action_receipt_ids,
    'exact_successful_replay',true,'runtime_rotation_replay',v_existing.identity_id<>v_successor.identity_id,
    'original_identity_id',v_existing.identity_id,'current_identity_id',v_successor.identity_id,
    'production_writes',false,'mailbox_contacted',false,'outbound_email',false
  );
END $replay$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text) FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.get_pdc_email_ai_v2_acceptance_fixtures_20260903()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth AS $fixtures$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_fixtures jsonb;
BEGIN
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard()
     OR auth.role()<>'authenticated' OR v_actor IS NULL OR v_email=''
     OR NOT EXISTS(
       SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i
       WHERE i.auth_user_id=v_actor AND i.normalized_email=v_email AND i.environment='staging'
         AND i.identity_purpose='pdc_email_ai_transaction_successor' AND i.active AND i.revoked_at IS NULL
     )
     OR EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND r.active AND r.account_status='approved' AND r.role::text='administrator')
     OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL)
  THEN RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_scope_denied','fixtures','[]'::jsonb); END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'scenario_no',f.scenario_no,'scenario_key',f.scenario_key,
    'source_receipt_id',f.source_receipt_id,'source_digest',f.source_digest,'evidence_digest',f.evidence_digest,
    'attachment_digests',f.attachment_digests,'source_message_id',f.source_message_id,'source_thread_id',f.source_thread_id,
    'target_vehicle_id',f.target_vehicle_id,'authoritative_snapshot',f.authoritative_snapshot,'operation_source',f.operation_source,
    'source',jsonb_build_object('sender',i.sender_email,'subject',i.subject,'received_at',i.received_at,'provider_uid',i.provider_uid,
      'correspondence',i.raw_body,'extracted_data',i.extracted_data,
      'attachments',(SELECT coalesce(jsonb_agg(jsonb_build_object('file_name',a.file_name,'content_type',a.content_type,'source_hash',a.source_hash,'extracted_text',a.extracted_text) ORDER BY a.created_at,a.id),'[]'::jsonb) FROM public.ai_email_attachments a WHERE a.intake_id=i.id)),
    'consumed',EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_transaction_receipts t WHERE t.source_receipt_id=f.source_receipt_id),
    'production_writes',false,'mailbox_contacted',false,'outbound_email',false
  ) ORDER BY f.scenario_no),'[]'::jsonb)
  INTO v_fixtures
  FROM public.pdc_email_ai_v2_acceptance_fixtures_20260903 f
  JOIN public.ai_email_intake i ON i.id=f.source_receipt_id;
  IF jsonb_array_length(v_fixtures)=14 THEN
    RETURN jsonb_build_object('ok',true,'code','pdc_email_ai_v2_acceptance_fixtures_ready','fixture_count',14,'fixtures',v_fixtures,
      'production_writes',false,'mailbox_contacted',false,'outbound_email',false);
  END IF;
  RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_count_invalid','fixtures',v_fixtures);
END $fixtures$;
REVOKE ALL ON FUNCTION public.get_pdc_email_ai_v2_acceptance_fixtures_20260903() FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_ai_v2_acceptance_fixtures_20260903() TO authenticated;

CREATE TABLE public.pdc_email_ai_runtime_rotation_history_20260903(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260903010000'),
  successor_head text NOT NULL CHECK(successor_head='20260903020000'),
  replay_function_sha256 text NOT NULL CHECK(replay_function_sha256~'^[a-f0-9]{64}$'),
  fixture_count integer NOT NULL CHECK(fixture_count=14),
  contract text NOT NULL,
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_runtime_rotation_history_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_runtime_rotation_history_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_runtime_rotation_history_20260903 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_runtime_rotation_history_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_runtime_rotation_history_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_acceptance_fixture_immutable_20260903();
INSERT INTO public.pdc_email_ai_runtime_rotation_history_20260903(
  event_key,predecessor_head,successor_head,replay_function_sha256,fixture_count,contract
)
SELECT encode(extensions.digest(convert_to('pdc-staging|20260903020000|runtime-rotation-replay-fixtures','UTF8'),'sha256'),'hex'),
  '20260903010000','20260903020000',
  encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex'),14,
  'An active registered successor may retrieve only an exact immutable successful receipt from itself or a duly registered earlier revoked predecessor of the same staging purpose. Fourteen fresh immutable complete-evidence sources are readable only through the scoped runtime RPC.'
FROM pg_proc p WHERE p.oid='public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure;

DO $post$
DECLARE
  v_fixtures jsonb;
  v_replay text:=pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure);
  v_strict text:=pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure);
BEGIN
  SELECT jsonb_agg(to_jsonb(f) ORDER BY f.scenario_no) INTO v_fixtures FROM public.pdc_email_ai_v2_acceptance_fixtures_20260903 f;
  IF jsonb_array_length(v_fixtures)<>14
     OR (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_20260903 f JOIN public.ai_email_intake i ON i.id=f.source_receipt_id WHERE i.duplicate_of IS NULL AND i.source_hash=f.source_digest AND i.extracted_data->>'pdc_email_ai_evidence_digest'=f.evidence_digest)<>14
     OR (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_20260903 f JOIN public.ai_email_attachments a ON a.intake_id=f.source_receipt_id WHERE f.attachment_digests @> jsonb_build_array(a.source_hash))<>14
     OR position('predecessor.created_at<v_successor.created_at' IN v_replay)=0
     OR position('t.typed_plan=p_plan' IN v_replay)=0
     OR position('pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)' IN v_strict)=0
     OR has_function_privilege('authenticated','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR NOT has_function_privilege('authenticated','public.get_pdc_email_ai_v2_acceptance_fixtures_20260903()','execute')
     OR has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixtures_20260903','select')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260903020000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260903020000','pdc_email_ai_runtime_rotation_replay_fixtures_20260903',ARRAY[
    'Exact successful immutable receipt replay accepts the active identity itself or a duly registered earlier revoked predecessor with identical staging purpose; source, evidence, plan hash and typed JSON remain exact',
    'Changed plans, cross-source reuse, hostile plans and fresh invalid plans remain on the strict validator/conflict path; no receipt mutation or generic table grant was added',
    'Fourteen fresh synthetic STAGING source/evidence fixtures include correspondence, extracted attachment text, operation lines, authoritative snapshot and operation-source readback',
    'Fixture source, attachment, registry and history rows are immutable; runtime receives them only through an active non-admin scoped-writer RPC',
    'Production, mailbox and outbound paths remain untouched and disabled'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
