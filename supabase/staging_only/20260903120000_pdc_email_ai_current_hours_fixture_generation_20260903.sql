-- STAGING-only current-hours validator repair and immutable acceptance generation 2.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903120000-current-hours-fixture-generation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_validator_sha text;
  v_executor_sha text;
BEGIN
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_validator_sha;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_executor_sha;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260903110000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903110000' AND name='pdc_email_ai_safe_projection_freeze_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903120000')
     OR v_validator_sha<>'4337b4dcdf490847f7bae226e1de6698fcaa5986cd1cdb9573dbba9fd76e7326'
     OR v_executor_sha<>'e9f61731254263a893352ecb0311798c032c4384e17df1a72369990a6e7b8b1a'
     OR position('import_pdc_authenticated_email_operations_with_hours' IN pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure))=0
     OR position('estimated_hours_source'',item->''payload''->>''estimated_hours_source''' IN pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure))=0
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_runtime_identities WHERE auth_user_id='e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8'::uuid AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.vehicles WHERE id='2cc5e9b8-7114-5d77-ada5-b296c9d10a9f'::uuid AND deleted_at IS NULL AND lifecycle_state::text='active' AND visible_on_board)<>1
     OR public.pdc_email_ai_v2_validated_operation_source_20260902('2cc5e9b8-7114-5d77-ada5-b296c9d10a9f'::uuid)='{}'::jsonb
  THEN RAISE EXCEPTION 'PDC_20260903120000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_current_hours_repairs_20260903(
  repair_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260903110000'),
  successor_head text NOT NULL CHECK(successor_head='20260903120000'),
  predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256~'^[a-f0-9]{64}$'),
  successor_function_sha256 text NOT NULL CHECK(successor_function_sha256~'^[a-f0-9]{64}$'),
  executor_function_sha256 text NOT NULL CHECK(executor_function_sha256~'^[a-f0-9]{64}$'),
  contract text NOT NULL,
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_current_hours_repairs_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_current_hours_repairs_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_current_hours_repairs_20260903 FROM public,anon,authenticated,service_role;

DO $repair$
DECLARE
  v_definition text;
  v_before text;
  v_after text;
  v_executor text;
  v_old text:=$old$('job_card','business_rule_default')$old$;
  v_new text:=$new$('job_card','ai_estimate','business_rule_default')$new$;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure) INTO v_definition;
  v_before:=encode(extensions.digest(convert_to(v_definition,'UTF8'),'sha256'),'hex');
  IF (length(v_definition)-length(replace(v_definition,v_old,'')))/length(v_old)<>1 THEN
    RAISE EXCEPTION 'PDC_20260903120000_VALIDATOR_ANCHOR_FAILED' USING errcode='55000';
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_after;
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure) INTO v_executor;
  INSERT INTO public.pdc_email_ai_current_hours_repairs_20260903(
    event_key,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,
    executor_function_sha256,contract,production_writes,mailbox_contacted,outbound_email
  ) VALUES(
    encode(extensions.digest(convert_to('pdc-staging|20260903120000|current-hours-validator','UTF8'),'sha256'),'hex'),
    '20260903110000','20260903120000',v_before,v_after,
    encode(extensions.digest(convert_to(v_executor,'UTF8'),'sha256'),'hex'),
    'Permit the current typed planner ai_estimate provenance only for bounded numeric operation hours. Existing job_card and legacy business_rule_default provenance remain unchanged. The hash-pinned executor forwards both hours and provenance to the canonical importer and verifies field-level readback.',
    false,false,false
  );
END $repair$;

CREATE FUNCTION public.pdc_email_ai_acceptance_generation_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $immutable$
BEGIN
  RAISE EXCEPTION 'PDC_EMAIL_AI_ACCEPTANCE_GENERATION_IMMUTABLE' USING errcode='55000';
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_acceptance_generation_immutable_20260903() FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_email_ai_v2_acceptance_fixture_generations_20260903(
  generation_id uuid PRIMARY KEY,
  generation_no integer NOT NULL UNIQUE CHECK(generation_no=2),
  fixture_contract text NOT NULL UNIQUE CHECK(fixture_contract='pdc-email-ai-v2-acceptance-fixture/20260903/generation-2'),
  fixture_count integer NOT NULL CHECK(fixture_count=14),
  reason text NOT NULL,
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixture_generations_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixture_generations_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_v2_acceptance_fixture_generations_20260903 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_acceptance_generations_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_acceptance_fixture_generations_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_acceptance_generation_immutable_20260903();

CREATE TABLE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903(
  fixture_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  generation_id uuid NOT NULL REFERENCES public.pdc_email_ai_v2_acceptance_fixture_generations_20260903(generation_id),
  scenario_no integer NOT NULL CHECK(scenario_no BETWEEN 1 AND 14),
  scenario_key text NOT NULL,
  source_receipt_id uuid NOT NULL UNIQUE REFERENCES public.ai_email_intake(id),
  source_digest text NOT NULL UNIQUE CHECK(source_digest~'^[a-f0-9]{64}$'),
  evidence_digest text NOT NULL UNIQUE CHECK(evidence_digest~'^[a-f0-9]{64}$'),
  attachment_digests jsonb NOT NULL CHECK(jsonb_typeof(attachment_digests)='array' AND jsonb_array_length(attachment_digests)=1),
  source_message_id text NOT NULL UNIQUE,
  source_thread_id text NOT NULL UNIQUE,
  target_vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
  authoritative_snapshot jsonb NOT NULL CHECK(jsonb_typeof(authoritative_snapshot)='object'),
  operation_source jsonb NOT NULL CHECK(jsonb_typeof(operation_source)='object'),
  fixture_contract text NOT NULL CHECK(fixture_contract='pdc-email-ai-v2-acceptance-fixture/20260903/generation-2'),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(generation_id,scenario_no), UNIQUE(generation_id,scenario_key)
);
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_acceptance_generation_fixtures_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_acceptance_generation_immutable_20260903();

INSERT INTO public.pdc_email_ai_v2_acceptance_fixture_generations_20260903(
  generation_id,generation_no,fixture_contract,fixture_count,reason,production_writes,mailbox_contacted,outbound_email
) VALUES(
  '9cea2926-0002-4000-8000-000000000014',2,'pdc-email-ai-v2-acceptance-fixture/20260903/generation-2',14,
  'Fresh immutable successor after generation 1 scenario 1 reached the executor during validator isolation.',false,false,false
);

DO $fixtures$
DECLARE
  v_generation uuid:='9cea2926-0002-4000-8000-000000000014'::uuid;
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
  v_no integer; v_key text; v_body text; v_attachment_text text;
  v_source_receipt_id uuid; v_attachment_id uuid; v_message_id text; v_thread_id text; v_provider_uid text;
  v_source_digest text; v_attachment_digest text; v_evidence_digest text; v_received_at timestamptz;
  v_snapshot jsonb; v_operation_source jsonb;
BEGIN
  SELECT jsonb_build_object(
    'captured_at','2026-09-03T03:12:00+00:00','vehicle',to_jsonb(v),
    'work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key,w.id) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),
    'parts_update',coalesce((SELECT to_jsonb(p) FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id ORDER BY p.updated_at DESC,p.id DESC LIMIT 1),'{}'::jsonb),
    'board_revision',(SELECT revision FROM public.pdc_email_vehicle_revision WHERE singleton),'source','authoritative_staging_snapshot'
  ), public.pdc_email_ai_v2_validated_operation_source_20260902(v.id)
  INTO v_snapshot,v_operation_source
  FROM public.vehicles v WHERE v.id='2cc5e9b8-7114-5d77-ada5-b296c9d10a9f'::uuid;

  FOR v_no IN SELECT generate_series(1,14) LOOP
    v_key:=v_scenarios[v_no];
    v_message_id:=format('<pdc-v2-acceptance-g2-20260903-%s@staging.invalid>',lpad(v_no::text,2,'0'));
    v_thread_id:=format('pdc-v2-acceptance-g2-20260903-thread-%s',lpad(v_no::text,2,'0'));
    v_provider_uid:=format('fixture:pdc-v2-acceptance-g2-20260903:%s',lpad(v_no::text,2,'0'));
    v_received_at:='2026-09-03T03:12:00+00:00'::timestamptz+make_interval(secs=>v_no);
    v_body:=format('STAGING IMMUTABLE ACCEPTANCE FIXTURE GENERATION 2 %s/14 [%s]. %s No outbound response is authorised.',v_no,v_key,v_descriptions[v_no]);
    v_attachment_text:=format('Fixture generation 2 %s [%s]\nStock: 13059806\nJob Card: J139125567\nOP 010 Pre-Delivery explicit hours: missing\nOP 020 Wheel Nut Indicator Set explicit hours: 2.50\nOP 030 Inspection explicit hours: 0.00\nEvidence instruction: %s',v_no,v_key,v_descriptions[v_no]);
    v_source_digest:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc-email-ai-v2-acceptance-fixture/20260903/generation-2','generation_id',v_generation,'scenario_no',v_no,'scenario_key',v_key,'body',v_body)::text,'UTF8'),'sha256'),'hex');
    v_attachment_digest:=encode(extensions.digest(convert_to(v_attachment_text,'UTF8'),'sha256'),'hex');
    v_source_receipt_id:=gen_random_uuid(); v_attachment_id:=gen_random_uuid();

    INSERT INTO public.ai_email_intake(
      id,status,subject,sender_email,sender_name,received_at,graph_message_id,graph_thread_id,internet_message_id,
      attachment_names,raw_body,parsed_text,extracted_data,confidence,warnings,processing_result,linked_vehicle_id,
      source_hash,recipient_mailbox,provider_uid,revision_summary,gateway_instance_id,provider_authserv_id,provider_authentication
    ) VALUES(
      v_source_receipt_id,'received',format('[STAGING FIXTURE G2 %s/14] %s',v_no,v_key),'acceptance-fixture@staging.invalid','PDC v2 Acceptance Fixture',v_received_at,
      v_message_id,v_thread_id,v_message_id,ARRAY[format('pdc-v2-acceptance-g2-%s.txt',lpad(v_no::text,2,'0'))],v_body,v_body,
      jsonb_build_object('test_fixture',true,'immutable',true,'generation_id',v_generation,'fixture_contract','pdc-email-ai-v2-acceptance-fixture/20260903/generation-2','scenario_no',v_no,'scenario_key',v_key,
        'job_card_number','J139125567','stock_number','13059806','backend_record_id','dd31d0a4-3e2f-4163-befd-93d59d7d6019',
        'operation_lines',jsonb_build_array(
          jsonb_build_object('operation_no','OP1','source_row_no',10,'description','Pre-Delivery','estimated_hours',null,'required_provenance','AI ESTIMATE','default_hours',1.0),
          jsonb_build_object('operation_no','OP2','source_row_no',20,'description','Wheel Nut Indicator Set','estimated_hours',2.50,'required_provenance','EXPLICIT SOURCE'),
          jsonb_build_object('operation_no','OP3','source_row_no',30,'description','Inspection','estimated_hours',0.00,'required_provenance','EXPLICIT SOURCE')),
        'authoritative_snapshot',v_snapshot,'operation_source',v_operation_source),
      1.0,ARRAY[]::text[],jsonb_build_object('fixture_only',true,'mailbox_contacted',false,'outbound_email',false),
      '2cc5e9b8-7114-5d77-ada5-b296c9d10a9f',v_source_digest,NULL,v_provider_uid,
      jsonb_build_object('fixture_only',true,'generation',2,'supersedes_generation',1),
      'pdc-email-ai-v2-acceptance-fixtures-g2-20260903','staging-fixture.local',jsonb_build_object('synthetic',true,'authenticated_source',true)
    );
    INSERT INTO public.ai_email_attachments(id,intake_id,graph_attachment_id,file_name,content_type,size_bytes,text_extraction_status,extracted_text,source_hash)
    VALUES(v_attachment_id,v_source_receipt_id,format('fixture-g2-attachment-%s',v_no),format('pdc-v2-acceptance-g2-%s.txt',lpad(v_no::text,2,'0')),
      'text/plain',octet_length(convert_to(v_attachment_text,'UTF8')),'completed',v_attachment_text,v_attachment_digest);
    v_evidence_digest:=public.pdc_email_ai_successor_source_evidence_digest_20260901(
      v_source_digest,NULL,v_message_id,v_thread_id,v_received_at,'acceptance-fixture@staging.invalid',
      format('[STAGING FIXTURE G2 %s/14] %s',v_no,v_key),v_provider_uid,v_body,jsonb_build_array(v_attachment_digest));
    UPDATE public.ai_email_intake SET extracted_data=extracted_data||jsonb_build_object('pdc_email_ai_evidence_digest',v_evidence_digest),updated_at=created_at WHERE id=v_source_receipt_id;
    INSERT INTO public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903(
      generation_id,scenario_no,scenario_key,source_receipt_id,source_digest,evidence_digest,attachment_digests,
      source_message_id,source_thread_id,target_vehicle_id,authoritative_snapshot,operation_source,fixture_contract,
      production_writes,mailbox_contacted,outbound_email
    ) VALUES(v_generation,v_no,v_key,v_source_receipt_id,v_source_digest,v_evidence_digest,jsonb_build_array(v_attachment_digest),
      v_message_id,v_thread_id,'2cc5e9b8-7114-5d77-ada5-b296c9d10a9f',v_snapshot,v_operation_source,
      'pdc-email-ai-v2-acceptance-fixture/20260903/generation-2',false,false,false);
  END LOOP;
END $fixtures$;

CREATE FUNCTION public.pdc_email_ai_v2_acceptance_generation_source_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$
BEGIN
  IF EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 f WHERE f.source_receipt_id=OLD.id) THEN
    RAISE EXCEPTION 'PDC_EMAIL_AI_ACCEPTANCE_GENERATION_SOURCE_IMMUTABLE' USING errcode='55000';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_acceptance_generation_source_immutable_20260903() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_v2_acceptance_generation_source_immutable_20260903
BEFORE UPDATE OR DELETE ON public.ai_email_intake
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_acceptance_generation_source_immutable_20260903();

CREATE FUNCTION public.pdc_email_ai_v2_acceptance_generation_attachment_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$
BEGIN
  IF TG_OP<>'INSERT' AND EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 f WHERE f.source_receipt_id=OLD.intake_id) THEN
    RAISE EXCEPTION 'PDC_EMAIL_AI_ACCEPTANCE_GENERATION_ATTACHMENT_IMMUTABLE' USING errcode='55000';
  END IF;
  IF TG_OP<>'DELETE' AND EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 f WHERE f.source_receipt_id=NEW.intake_id) THEN
    RAISE EXCEPTION 'PDC_EMAIL_AI_ACCEPTANCE_GENERATION_ATTACHMENT_IMMUTABLE' USING errcode='55000';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_acceptance_generation_attachment_immutable_20260903() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_v2_acceptance_generation_attachment_immutable_20260903
BEFORE INSERT OR UPDATE OR DELETE ON public.ai_email_attachments
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_acceptance_generation_attachment_immutable_20260903();

CREATE FUNCTION public.pdc_email_ai_acceptance_runtime_scope_20260903()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $scope$
  SELECT current_setting('app.environment',true)<>'production' AND public.pdc_monitor_staging_guard()
    AND auth.role()='authenticated' AND auth.uid() IS NOT NULL
    AND EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i
      WHERE i.auth_user_id=auth.uid() AND i.normalized_email=lower(btrim(coalesce(auth.jwt()->>'email','')))
        AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor' AND i.active AND i.revoked_at IS NULL)
    AND NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid() AND r.active AND r.account_status='approved' AND r.role::text='administrator')
    AND EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=auth.uid() AND w.active AND w.revoked_at IS NULL)
$scope$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_acceptance_runtime_scope_20260903() FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903(
  p_generation_id uuid DEFAULT '9cea2926-0002-4000-8000-000000000014'::uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $fixtures$
DECLARE v_rows jsonb; v_generation public.pdc_email_ai_v2_acceptance_fixture_generations_20260903%rowtype;
BEGIN
  IF NOT public.pdc_email_ai_acceptance_runtime_scope_20260903() THEN
    RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_scope_denied','fixtures','[]'::jsonb);
  END IF;
  SELECT * INTO v_generation FROM public.pdc_email_ai_v2_acceptance_fixture_generations_20260903 WHERE generation_id=p_generation_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_generation_not_found','fixtures','[]'::jsonb); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'generation_id',f.generation_id,'generation_no',v_generation.generation_no,'fixture_contract',f.fixture_contract,
    'scenario_no',f.scenario_no,'scenario_key',f.scenario_key,'source_receipt_id',f.source_receipt_id,
    'source_digest',f.source_digest,'evidence_digest',f.evidence_digest,'attachment_digests',f.attachment_digests,
    'source_message_id',f.source_message_id,'source_thread_id',f.source_thread_id,'target_vehicle_id',f.target_vehicle_id,
    'authoritative_snapshot',f.authoritative_snapshot,'operation_source',f.operation_source,
    'source',jsonb_build_object('sender',i.sender_email,'subject',i.subject,'received_at',i.received_at,'provider_uid',i.provider_uid,
      'correspondence',i.raw_body,'extracted_data',i.extracted_data,
      'attachments',(SELECT coalesce(jsonb_agg(jsonb_build_object('file_name',a.file_name,'content_type',a.content_type,'source_hash',a.source_hash,'extracted_text',a.extracted_text) ORDER BY a.created_at,a.id),'[]'::jsonb) FROM public.ai_email_attachments a WHERE a.intake_id=i.id)),
    'consumed',EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_transaction_receipts t WHERE t.source_receipt_id=f.source_receipt_id),
    'production_writes',false,'mailbox_contacted',false,'outbound_email',false
  ) ORDER BY f.scenario_no),'[]'::jsonb) INTO v_rows
  FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 f JOIN public.ai_email_intake i ON i.id=f.source_receipt_id
  WHERE f.generation_id=p_generation_id;
  RETURN jsonb_build_object('ok',jsonb_array_length(v_rows)=14,'code',case when jsonb_array_length(v_rows)=14 then 'pdc_email_ai_v2_acceptance_fixture_generation_ready' else 'acceptance_fixture_count_invalid' end,
    'generation_id',v_generation.generation_id,'generation_no',v_generation.generation_no,'fixture_contract',v_generation.fixture_contract,
    'fixture_count',jsonb_array_length(v_rows),'fixtures',v_rows,'production_writes',false,'mailbox_contacted',false,'outbound_email',false);
END $fixtures$;
REVOKE ALL ON FUNCTION public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903(uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903(uuid) TO authenticated;

CREATE FUNCTION public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903(
  p_generation_id uuid,p_plan jsonb
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $validate$
DECLARE v_fixture public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903%rowtype; v_valid boolean;
BEGIN
  IF NOT public.pdc_email_ai_acceptance_runtime_scope_20260903() THEN
    RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_scope_denied');
  END IF;
  IF jsonb_typeof(p_plan)<>'object' THEN RETURN jsonb_build_object('ok',false,'code','typed_v2_plan_invalid'); END IF;
  SELECT * INTO v_fixture FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 f
  WHERE f.generation_id=p_generation_id
    AND f.source_receipt_id::text=p_plan->>'source_receipt_id' AND f.source_digest=p_plan->>'source_digest'
    AND f.evidence_digest=p_plan->>'evidence_digest' AND f.source_message_id=p_plan->>'source_message_id'
    AND f.source_thread_id=p_plan->>'source_thread_id' AND f.attachment_digests=coalesce(p_plan->'attachment_digests','[]'::jsonb);
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_plan_binding_invalid'); END IF;
  v_valid:=public.pdc_email_ai_successor_validate_v2_plan_20260901(p_plan);
  RETURN jsonb_build_object('ok',v_valid,'code',case when v_valid then 'typed_v2_plan_valid' else 'typed_v2_plan_invalid' end,
    'generation_id',p_generation_id,'scenario_no',v_fixture.scenario_no,'scenario_key',v_fixture.scenario_key,
    'instruction_count',jsonb_array_length(coalesce(p_plan->'instructions','[]'::jsonb)),
    'production_writes',false,'mailbox_contacted',false,'outbound_email',false);
END $validate$;
REVOKE ALL ON FUNCTION public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903(uuid,jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903(uuid,jsonb) TO authenticated;

DO $post$
DECLARE v_validator text:=pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure);
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_ai_current_hours_repairs_20260903)<>1
     OR position('(''job_card'',''ai_estimate'',''business_rule_default'')' IN v_validator)=0
     OR (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixture_generations_20260903 WHERE generation_id='9cea2926-0002-4000-8000-000000000014'::uuid AND fixture_count=14)<>1
     OR (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 WHERE generation_id='9cea2926-0002-4000-8000-000000000014'::uuid)<>14
     OR EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 f JOIN public.pdc_email_ai_successor_transaction_receipts t ON t.source_receipt_id=f.source_receipt_id)
     OR has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903','select')
     OR has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903','insert,update,delete')
     OR NOT has_function_privilege('authenticated','public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903(uuid)','execute')
     OR NOT has_function_privilege('authenticated','public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903(uuid,jsonb)','execute')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260903120000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260903120000','pdc_email_ai_current_hours_fixture_generation_20260903',ARRAY[
    'Hash-guard the installed typed instruction validator and admit ai_estimate only as bounded numeric operation-hours provenance alongside existing accepted provenance',
    'Retain the hash-pinned executor path that forwards estimated_hours and estimated_hours_source to the canonical operation importer and verifies both in field-level readback',
    'Create immutable acceptance fixture generation 2 with 14 fresh complete-evidence sources preserving explicit 0.00, explicit 2.50 and missing Pre-Delivery 1.0 AI ESTIMATE cases',
    'Expose generation 2 and read-only plan validation only to the active non-admin scoped runtime identity; keep all generation/source/attachment tables private and immutable',
    'Production, mailbox and outbound paths remain untouched and disabled'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
