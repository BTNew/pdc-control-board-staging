-- STAGING-only append-only evidence-bound fixture refresh after generation 4 acceptance exposed controller-side identity rewriting.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903124000-mixed-apply-fixture-refresh',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_strict_sha text; v_executor_sha text;
BEGIN
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_strict_sha;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_executor_sha;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260903123000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903123000' AND name='pdc_email_ai_mixed_apply_fixture_refresh_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903124000')
     OR v_strict_sha<>'28237657d6b16b783ae984ed79832bb2476a2595811769c9d28186f33ca04859'
     OR v_executor_sha<>'e9f61731254263a893352ecb0311798c032c4384e17df1a72369990a6e7b8b1a'
     OR (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v4)<>14
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_transaction_receipts t
         JOIN public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v4 f ON f.source_receipt_id=t.source_receipt_id
         WHERE f.scenario_no=1 AND t.aggregate_disposition='PARTIAL_FAILURE')<>1
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_action_receipts a
         JOIN public.pdc_email_ai_successor_transaction_receipts t USING(transaction_id)
         JOIN public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v4 f ON f.source_receipt_id=t.source_receipt_id
         WHERE f.scenario_no=1 AND a.disposition='APPLIED_AND_VERIFIED')<>2
  THEN RAISE EXCEPTION 'PDC_20260903124000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5(
  generation_id uuid PRIMARY KEY,
  generation_no integer NOT NULL UNIQUE CHECK(generation_no=5),
  fixture_contract text NOT NULL UNIQUE CHECK(fixture_contract='pdc-email-ai-v2-acceptance-fixture/20260903/generation-5'),
  fixture_count integer NOT NULL CHECK(fixture_count=14),
  reason text NOT NULL,
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5(
  fixture_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  generation_id uuid NOT NULL REFERENCES public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5(generation_id),
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
  fixture_contract text NOT NULL CHECK(fixture_contract='pdc-email-ai-v2-acceptance-fixture/20260903/generation-5'),
  operation_number_offset integer NOT NULL CHECK(operation_number_offset=90),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(generation_id,scenario_no), UNIQUE(generation_id,scenario_key)
);
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5,public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_g5_generations_immutable_20260903 BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_acceptance_generation_immutable_20260903();
CREATE TRIGGER pdc_email_ai_g5_fixtures_immutable_20260903 BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_acceptance_generation_immutable_20260903();

INSERT INTO public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5(generation_id,generation_no,fixture_contract,fixture_count,reason)
VALUES('5bf31237-0005-4000-8000-000000000014',5,'pdc-email-ai-v2-acceptance-fixture/20260903/generation-5',14,
  'Fresh immutable successor that binds reserved OP91/OP92/OP93 identities into attachment text and extracted source evidence before digest calculation.');

DO $fixtures$
DECLARE
  v_generation uuid:='5bf31237-0005-4000-8000-000000000014'::uuid;
  old_fixture public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v4%rowtype;
  old_intake public.ai_email_intake%rowtype; old_attachment public.ai_email_attachments%rowtype;
  v_source_receipt_id uuid; v_attachment_id uuid; v_message_id text; v_thread_id text; v_provider_uid text;
  v_source_digest text; v_attachment_digest text; v_evidence_digest text; v_body text; v_attachment_text text; v_extracted jsonb;
BEGIN
  FOR old_fixture IN SELECT * FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v4 ORDER BY scenario_no LOOP
    SELECT * INTO STRICT old_intake FROM public.ai_email_intake WHERE id=old_fixture.source_receipt_id;
    SELECT * INTO STRICT old_attachment FROM public.ai_email_attachments WHERE intake_id=old_fixture.source_receipt_id ORDER BY created_at,id LIMIT 1;
    v_source_receipt_id:=gen_random_uuid(); v_attachment_id:=gen_random_uuid();
    v_message_id:=format('<pdc-v2-acceptance-g5-20260903-%s@staging.invalid>',lpad(old_fixture.scenario_no::text,2,'0'));
    v_thread_id:=format('pdc-v2-acceptance-g5-20260903-thread-%s',lpad(old_fixture.scenario_no::text,2,'0'));
    v_provider_uid:=format('fixture:pdc-v2-acceptance-g5-20260903:%s',lpad(old_fixture.scenario_no::text,2,'0'));
    v_body:=replace(replace(old_intake.raw_body,'GENERATION 4','GENERATION 5'),'generation 4','generation 5');
    v_body:=v_body||CASE old_fixture.scenario_no
      WHEN 2 THEN format(' Activate Stock %s from the authoritative backend record.',old_intake.extracted_data->>'stock_number')
      WHEN 3 THEN format(' Parts ETA for Stock %s is 2099-01-01.',old_intake.extracted_data->>'stock_number')
      WHEN 4 THEN format(' Parts are complete for Stock %s.',old_intake.extracted_data->>'stock_number')
      WHEN 5 THEN format(' Parts ETA for Stock %s is 2099-01-02. Add note: multi-action fixture verified for Stock %s.',old_intake.extracted_data->>'stock_number',old_intake.extracted_data->>'stock_number')
      WHEN 10 THEN format(' Add note: revised evidence supersedes scenario 6 for Stock %s.',old_intake.extracted_data->>'stock_number')
      ELSE '' END;
    v_attachment_text:=replace(replace(replace(replace(replace(old_attachment.extracted_text,'generation 4','generation 5'),'g4','g5'),'OP 010','OP 091'),'OP 020','OP 092'),'OP 030','OP 093');
    v_extracted:=(old_intake.extracted_data-'pdc_email_ai_evidence_digest')||jsonb_build_object('generation_id',v_generation,'fixture_contract','pdc-email-ai-v2-acceptance-fixture/20260903/generation-5','operation_number_offset',90);
    v_extracted:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      v_extracted,
      '{operation_lines,0,operation_no}',to_jsonb('OP91'::text),false),
      '{operation_lines,0,source_row_no}',to_jsonb(1),false),
      '{operation_lines,1,operation_no}',to_jsonb('OP92'::text),false),
      '{operation_lines,1,source_row_no}',to_jsonb(2),false),
      '{operation_lines,2,operation_no}',to_jsonb('OP93'::text),false),
      '{operation_lines,2,source_row_no}',to_jsonb(3),false);
    IF old_fixture.scenario_no=12 THEN
      v_extracted:=jsonb_set(v_extracted,'{operation_lines}',(v_extracted->'operation_lines')||jsonb_build_object('operation_no','OP94','source_row_no',4,'description','mixed FMG signage / GVM / GCM / Tare decals','estimated_hours',NULL),false);
      v_attachment_text:=v_attachment_text||E'\nOP 094 | mixed FMG signage / GVM / GCM / Tare decals';
    END IF;
    v_source_digest:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc-email-ai-v2-acceptance-fixture/20260903/generation-5','generation_id',v_generation,'scenario_no',old_fixture.scenario_no,'scenario_key',old_fixture.scenario_key,'body',v_body)::text,'UTF8'),'sha256'),'hex');
    v_attachment_digest:=encode(extensions.digest(convert_to(v_attachment_text,'UTF8'),'sha256'),'hex');
    INSERT INTO public.ai_email_intake(id,status,subject,sender_email,sender_name,received_at,graph_message_id,graph_thread_id,internet_message_id,attachment_names,raw_body,parsed_text,extracted_data,confidence,warnings,processing_result,linked_vehicle_id,source_hash,recipient_mailbox,provider_uid,revision_summary,gateway_instance_id,provider_authserv_id,provider_authentication)
    VALUES(v_source_receipt_id,'received',replace(old_intake.subject,'G4','G5'),old_intake.sender_email,old_intake.sender_name,old_intake.received_at+interval '1 hour',v_message_id,v_thread_id,v_message_id,ARRAY[replace(old_attachment.file_name,'g4','g5')],v_body,v_body,v_extracted,old_intake.confidence,old_intake.warnings,jsonb_build_object('fixture_only',true,'mailbox_contacted',false,'outbound_email',false),old_intake.linked_vehicle_id,v_source_digest,NULL,v_provider_uid,jsonb_build_object('fixture_only',true,'generation',5,'supersedes_generation',4),'pdc-email-ai-v2-acceptance-fixtures-g5-20260903','staging-fixture.local',jsonb_build_object('synthetic',true,'authenticated_source',true));
    INSERT INTO public.ai_email_attachments(id,intake_id,graph_attachment_id,file_name,content_type,size_bytes,text_extraction_status,extracted_text,source_hash)
    VALUES(v_attachment_id,v_source_receipt_id,format('fixture-g5-attachment-%s',old_fixture.scenario_no),replace(old_attachment.file_name,'g4','g5'),old_attachment.content_type,octet_length(convert_to(v_attachment_text,'UTF8')),'completed',v_attachment_text,v_attachment_digest);
    v_evidence_digest:=public.pdc_email_ai_successor_source_evidence_digest_20260901(v_source_digest,NULL,v_message_id,v_thread_id,old_intake.received_at+interval '1 hour',old_intake.sender_email,replace(old_intake.subject,'G4','G5'),v_provider_uid,v_body,jsonb_build_array(v_attachment_digest));
    UPDATE public.ai_email_intake SET extracted_data=extracted_data||jsonb_build_object('pdc_email_ai_evidence_digest',v_evidence_digest),updated_at=created_at WHERE id=v_source_receipt_id;
    INSERT INTO public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5(generation_id,scenario_no,scenario_key,source_receipt_id,source_digest,evidence_digest,attachment_digests,source_message_id,source_thread_id,target_vehicle_id,authoritative_snapshot,operation_source,fixture_contract,operation_number_offset)
    VALUES(v_generation,old_fixture.scenario_no,old_fixture.scenario_key,v_source_receipt_id,v_source_digest,v_evidence_digest,jsonb_build_array(v_attachment_digest),v_message_id,v_thread_id,old_fixture.target_vehicle_id,old_fixture.authoritative_snapshot,old_fixture.operation_source,'pdc-email-ai-v2-acceptance-fixture/20260903/generation-5',90);
  END LOOP;
END $fixtures$;

CREATE FUNCTION public.pdc_email_ai_g5_source_immutable_20260903() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$
BEGIN IF EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 f WHERE f.source_receipt_id=OLD.id) THEN RAISE EXCEPTION 'PDC_EMAIL_AI_ACCEPTANCE_GENERATION_5_SOURCE_IMMUTABLE' USING errcode='55000'; END IF; RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END; END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_g5_source_immutable_20260903() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_g5_source_immutable_20260903 BEFORE UPDATE OR DELETE ON public.ai_email_intake FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_g5_source_immutable_20260903();
CREATE FUNCTION public.pdc_email_ai_g5_attachment_immutable_20260903() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$
BEGIN IF TG_OP<>'INSERT' AND EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 f WHERE f.source_receipt_id=OLD.intake_id) THEN RAISE EXCEPTION 'PDC_EMAIL_AI_ACCEPTANCE_GENERATION_5_ATTACHMENT_IMMUTABLE' USING errcode='55000'; END IF; IF TG_OP<>'DELETE' AND EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 f WHERE f.source_receipt_id=NEW.intake_id) THEN RAISE EXCEPTION 'PDC_EMAIL_AI_ACCEPTANCE_GENERATION_5_ATTACHMENT_IMMUTABLE' USING errcode='55000'; END IF; RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END; END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_g5_attachment_immutable_20260903() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_g5_attachment_immutable_20260903 BEFORE INSERT OR UPDATE OR DELETE ON public.ai_email_attachments FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_g5_attachment_immutable_20260903();

CREATE FUNCTION public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v5(p_generation_id uuid DEFAULT '5bf31237-0005-4000-8000-000000000014'::uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $fixtures$
DECLARE v_rows jsonb; v_generation public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5%rowtype;
BEGIN
  IF NOT public.pdc_email_ai_acceptance_runtime_scope_20260903() THEN RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_scope_denied','fixtures','[]'::jsonb); END IF;
  SELECT * INTO v_generation FROM public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5 WHERE generation_id=p_generation_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_generation_not_found','fixtures','[]'::jsonb); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('generation_id',f.generation_id,'generation_no',v_generation.generation_no,'fixture_contract',f.fixture_contract,'operation_number_offset',f.operation_number_offset,'scenario_no',f.scenario_no,'scenario_key',f.scenario_key,'source_receipt_id',f.source_receipt_id,'source_digest',f.source_digest,'evidence_digest',f.evidence_digest,'attachment_digests',f.attachment_digests,'source_message_id',f.source_message_id,'source_thread_id',f.source_thread_id,'target_vehicle_id',f.target_vehicle_id,'authoritative_snapshot',f.authoritative_snapshot,'operation_source',f.operation_source,'source',jsonb_build_object('sender',i.sender_email,'subject',i.subject,'received_at',i.received_at,'provider_uid',i.provider_uid,'correspondence',i.raw_body,'extracted_data',i.extracted_data,'attachments',(SELECT coalesce(jsonb_agg(jsonb_build_object('file_name',a.file_name,'content_type',a.content_type,'source_hash',a.source_hash,'extracted_text',a.extracted_text) ORDER BY a.created_at,a.id),'[]'::jsonb) FROM public.ai_email_attachments a WHERE a.intake_id=i.id)),'consumed',EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_transaction_receipts t WHERE t.source_receipt_id=f.source_receipt_id),'production_writes',false,'mailbox_contacted',false,'outbound_email',false) ORDER BY f.scenario_no),'[]'::jsonb) INTO v_rows
  FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 f JOIN public.ai_email_intake i ON i.id=f.source_receipt_id WHERE f.generation_id=p_generation_id;
  RETURN jsonb_build_object('ok',jsonb_array_length(v_rows)=14,'code',case when jsonb_array_length(v_rows)=14 then 'pdc_email_ai_v2_acceptance_fixture_generation_ready' else 'acceptance_fixture_count_invalid' end,'generation_id',v_generation.generation_id,'generation_no',v_generation.generation_no,'fixture_contract',v_generation.fixture_contract,'fixture_count',jsonb_array_length(v_rows),'fixtures',v_rows,'production_writes',false,'mailbox_contacted',false,'outbound_email',false);
END $fixtures$;
REVOKE ALL ON FUNCTION public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v5(uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v5(uuid) TO authenticated;

CREATE FUNCTION public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v5(p_generation_id uuid,p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $validate$
DECLARE v_fixture public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5%rowtype; v_valid boolean;
BEGIN
  IF NOT public.pdc_email_ai_acceptance_runtime_scope_20260903() THEN RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_scope_denied'); END IF;
  IF jsonb_typeof(p_plan)<>'object' THEN RETURN jsonb_build_object('ok',false,'code','typed_v2_plan_invalid'); END IF;
  SELECT * INTO v_fixture FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 f WHERE f.generation_id=p_generation_id AND f.source_receipt_id::text=p_plan->>'source_receipt_id' AND f.source_digest=p_plan->>'source_digest' AND f.evidence_digest=p_plan->>'evidence_digest' AND f.source_message_id=p_plan->>'source_message_id' AND f.source_thread_id=p_plan->>'source_thread_id' AND f.attachment_digests=coalesce(p_plan->'attachment_digests','[]'::jsonb);
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_fixture_plan_binding_invalid'); END IF;
  v_valid:=public.pdc_email_ai_successor_validate_v2_plan_20260901(p_plan);
  RETURN jsonb_build_object('ok',v_valid,'code',case when v_valid then 'typed_v2_plan_valid' else 'typed_v2_plan_invalid' end,'generation_id',p_generation_id,'scenario_no',v_fixture.scenario_no,'scenario_key',v_fixture.scenario_key,'instruction_count',jsonb_array_length(coalesce(p_plan->'instructions','[]'::jsonb)),'production_writes',false,'mailbox_contacted',false,'outbound_email',false);
END $validate$;
REVOKE ALL ON FUNCTION public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v5(uuid,jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v5(uuid,jsonb) TO authenticated;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 WHERE generation_id='5bf31237-0005-4000-8000-000000000014' AND operation_number_offset=90
       AND source_receipt_id IN (SELECT id FROM public.ai_email_intake WHERE extracted_data#>>'{operation_lines,0,operation_no}'='OP91'))<>14
     OR EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 f JOIN public.pdc_email_ai_successor_transaction_receipts t ON t.source_receipt_id=f.source_receipt_id)
     OR has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5','select,insert,update,delete')
     OR NOT has_function_privilege('authenticated','public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v5(uuid)','execute')
     OR NOT has_function_privilege('authenticated','public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v5(uuid,jsonb)','execute')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260903124000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260903124000','pdc_email_ai_evidence_bound_fixture_refresh_20260903',ARRAY[
  'Preserve generation 4 and expose fresh immutable generation 5 after review found controller-side operation identity rewriting',
  'Bind OP91, OP92 and OP93 into extracted source rows and attachment text before attachment and evidence digest calculation',
  'Keep fixture tables private and expose read/validation only to the existing scoped non-admin runtime identity',
  'Production, mailbox and outbound paths remain untouched and disabled'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
