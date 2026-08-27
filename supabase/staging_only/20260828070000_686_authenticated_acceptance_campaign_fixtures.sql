-- STAGING ONLY 686: final authenticated Email AI natural-language acceptance.
-- Append-only successor after timestamp head 20260828060000 / 685.
-- It preserves the retained UID514 state, never invokes its intake, and keeps
-- the scheduled .44 task/outbound path disabled. Synthetic acceptance rows are
-- explicitly marked and use provider UIDs 515+ only.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-686-email-ai-final-functional-remediation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828060000'
     OR (SELECT count(*) FROM public.pdc_authenticated_provider_import_agentic_compatibility_controls_684 WHERE singleton AND enabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid AND provider_uid='imap_uid:514' AND source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' AND status='processing' AND locked_by='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid)<>1
     OR (SELECT count(*) FROM public.pdc_provider_email_observations WHERE intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid AND parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' AND attachment_source_hash='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4')<>1
     OR (SELECT count(*) FROM public.vehicles WHERE id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid AND public.normalize_vehicle_stock_number(stock_number)='13016925' AND lifecycle_state='active' AND deleted_at IS NULL)<>1
     OR to_regprocedure('public.pdc_monitor_authenticated_active_scope_674(text)') IS NULL
     OR to_regprocedure('public.update_pdc_parts_eta(uuid,integer,date)') IS NULL
     OR to_regprocedure('public.mark_pdc_parts_complete(uuid,integer)') IS NULL
     OR to_regprocedure('public.create_pdc_sublet_booking(uuid,bigint,uuid,date,date,text,text)') IS NULL
     OR to_regprocedure('public.update_pdc_sublet_booking(uuid,bigint,date,date,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_686_EXACT_685_HEAD_OR_UID514_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_authenticated_email_acceptance_campaign_runs_686(
  run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  namespace text NOT NULL UNIQUE CHECK(namespace ~ '^pdc-acceptance-686:[0-9a-f-]{36}$'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  jwt_role text NOT NULL CHECK(jwt_role='authenticated'),
  server_application_role text NOT NULL CHECK(server_application_role='importer'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'),
  planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'),
  trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'),
  target_vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  target_stock_number text NOT NULL CHECK(target_stock_number='13000765'),
  status text NOT NULL CHECK(status IN('active','cleaned')),
  acceptance_case_count integer NOT NULL CHECK(acceptance_case_count=6),
  result jsonb CHECK(result IS NULL OR jsonb_typeof(result)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  cleaned_at timestamptz
);

CREATE TABLE public.pdc_authenticated_email_acceptance_campaign_fixtures_686(
  fixture_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES public.pdc_authenticated_email_acceptance_campaign_runs_686(run_id) ON DELETE RESTRICT,
  case_key text NOT NULL CHECK(case_key IN('parts_eta','parts_complete','sublet_booking_date','multi_action','exact_replay','ambiguous_negative')),
  instruction_no integer NOT NULL CHECK(instruction_no BETWEEN 1 AND 20),
  intake_id uuid NOT NULL UNIQUE REFERENCES public.ai_email_intake(id) ON DELETE RESTRICT,
  attachment_id uuid NOT NULL UNIQUE REFERENCES public.ai_email_attachments(id) ON DELETE RESTRICT,
  observation_id uuid NOT NULL UNIQUE REFERENCES public.pdc_provider_email_observations(observation_id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  booking_id uuid REFERENCES public.pdc_sublet_booking_instances(booking_id) ON DELETE RESTRICT,
  provider_uid text NOT NULL UNIQUE CHECK(provider_uid ~ '^imap_uid:[0-9]+$' AND substring(provider_uid FROM 10)::bigint>=515),
  source_hash text NOT NULL UNIQUE CHECK(source_hash ~ '^[a-f0-9]{64}$'),
  attachment_hash text NOT NULL UNIQUE CHECK(attachment_hash ~ '^[a-f0-9]{64}$'),
  claim_token uuid NOT NULL UNIQUE,
  message_id text NOT NULL UNIQUE,
  sender text NOT NULL,
  natural_language text NOT NULL CHECK(length(btrim(natural_language)) BETWEEN 3 AND 2000),
  expected jsonb NOT NULL CHECK(jsonb_typeof(expected)='object'),
  active boolean NOT NULL DEFAULT true,
  cleaned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(run_id,case_key,instruction_no)
);

CREATE TABLE public.pdc_authenticated_email_acceptance_plans_686(
  plan_receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fixture_id uuid NOT NULL UNIQUE REFERENCES public.pdc_authenticated_email_acceptance_campaign_fixtures_686(fixture_id) ON DELETE RESTRICT,
  run_id uuid NOT NULL REFERENCES public.pdc_authenticated_email_acceptance_campaign_runs_686(run_id) ON DELETE RESTRICT,
  intake_id uuid NOT NULL REFERENCES public.ai_email_intake(id) ON DELETE RESTRICT,
  evidence_hash text NOT NULL CHECK(evidence_hash ~ '^[a-f0-9]{64}$'),
  plan_hash text NOT NULL UNIQUE CHECK(plan_hash ~ '^[a-f0-9]{64}$'),
  instruction text NOT NULL CHECK(length(btrim(instruction)) BETWEEN 3 AND 2000),
  actions jsonb NOT NULL CHECK(jsonb_typeof(actions)='array'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.pdc_authenticated_email_acceptance_action_receipts_686(
  action_receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_receipt_id uuid NOT NULL REFERENCES public.pdc_authenticated_email_acceptance_plans_686(plan_receipt_id) ON DELETE RESTRICT,
  fixture_id uuid NOT NULL REFERENCES public.pdc_authenticated_email_acceptance_campaign_fixtures_686(fixture_id) ON DELETE RESTRICT,
  action_no integer NOT NULL CHECK(action_no BETWEEN 1 AND 20),
  action_hash text NOT NULL UNIQUE CHECK(action_hash ~ '^[a-f0-9]{64}$'),
  action_type text NOT NULL CHECK(action_type IN('parts_eta','parts_complete','sublet_booking_date','unparsed')),
  requested jsonb NOT NULL CHECK(jsonb_typeof(requested)='object'),
  resolved_date date,
  disposition text NOT NULL CHECK(disposition IN('PENDING','APPLIED_AND_VERIFIED','ALREADY_CORRECT','SUPERSEDED','BLOCKED_WITH_EXACT_REASON','GENUINELY_AMBIGUOUS')),
  reason text NOT NULL,
  before_data jsonb,
  after_data jsonb,
  effect_count integer NOT NULL DEFAULT 0 CHECK(effect_count>=0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  executed_at timestamptz,
  UNIQUE(plan_receipt_id,action_no)
);

CREATE TABLE public.pdc_authenticated_email_acceptance_final_receipts_686(
  final_receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_authenticated_email_acceptance_plans_686(plan_receipt_id) ON DELETE RESTRICT,
  fixture_id uuid NOT NULL UNIQUE REFERENCES public.pdc_authenticated_email_acceptance_campaign_fixtures_686(fixture_id) ON DELETE RESTRICT,
  evidence_hash text NOT NULL CHECK(evidence_hash ~ '^[a-f0-9]{64}$'),
  plan_hash text NOT NULL CHECK(plan_hash ~ '^[a-f0-9]{64}$'),
  outcome text NOT NULL,
  result jsonb NOT NULL CHECK(jsonb_typeof(result)='object'),
  result_hash text NOT NULL CHECK(result_hash ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

DO $secure$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['pdc_authenticated_email_acceptance_campaign_runs_686','pdc_authenticated_email_acceptance_campaign_fixtures_686','pdc_authenticated_email_acceptance_plans_686','pdc_authenticated_email_acceptance_action_receipts_686','pdc_authenticated_email_acceptance_final_receipts_686'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM public,anon,authenticated,service_role,pdc_email_monitor',t);
  END LOOP;
END $secure$;

CREATE FUNCTION public.pdc_acceptance_history_immutable_686() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_686_ACCEPTANCE_RECEIPT_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_acceptance_history_immutable_686() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_acceptance_plans_immutable_686 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_acceptance_plans_686 FOR EACH ROW EXECUTE FUNCTION public.pdc_acceptance_history_immutable_686();
CREATE TRIGGER pdc_acceptance_actions_immutable_686 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_acceptance_action_receipts_686 FOR EACH ROW EXECUTE FUNCTION public.pdc_acceptance_history_immutable_686();
CREATE TRIGGER pdc_acceptance_finals_immutable_686 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_acceptance_final_receipts_686 FOR EACH ROW EXECUTE FUNCTION public.pdc_acceptance_history_immutable_686();

CREATE FUNCTION public.pdc_email_resolve_business_date_686(p_value text,p_existing_date date DEFAULT NULL) RETURNS date
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $date$
DECLARE v text:=lower(btrim(coalesce(p_value,''))); d integer; m integer; y integer; today date; candidate date;
BEGIN
  IF v~'^\d{4}-\d{2}-\d{2}$' THEN
    BEGIN candidate:=v::date; EXCEPTION WHEN others THEN RETURN NULL; END;
    IF to_char(candidate,'YYYY-MM-DD')<>v THEN RETURN NULL; END IF;
    RETURN candidate;
  END IF;
  IF v~'^(0?[1-9]|[12][0-9]|3[01])[[:space:]]+(january|february|march|april|may|june|july|august|september|october|november|december)$' THEN
    d:=(regexp_matches(v,'^(0?[1-9]|[12][0-9]|3[01])'))[1]::integer;
    m:=array_position(ARRAY['january','february','march','april','may','june','july','august','september','october','november','december'],(regexp_matches(v,'[[:space:]]+(january|february|march|april|may|june|july|august|september|october|november|december)$'))[1]);
  ELSIF v~'^(january|february|march|april|may|june|july|august|september|october|november|december)[[:space:]]+(0?[1-9]|[12][0-9]|3[01])$' THEN
    m:=array_position(ARRAY['january','february','march','april','may','june','july','august','september','october','november','december'],(regexp_matches(v,'^(january|february|march|april|may|june|july|august|september|october|november|december)'))[1]);
    d:=(regexp_matches(v,'[[:space:]]+(0?[1-9]|[12][0-9]|3[01])$'))[1]::integer;
  ELSE RETURN NULL;
  END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date;
  BEGIN
    IF p_existing_date IS NOT NULL THEN
      candidate:=make_date(extract(year FROM p_existing_date)::integer,m,d);
      IF candidate>=today THEN RETURN candidate; END IF;
    END IF;
    candidate:=make_date(extract(year FROM today)::integer,m,d);
    IF candidate<today THEN candidate:=make_date(extract(year FROM today)::integer+1,m,d); END IF;
    RETURN candidate;
  EXCEPTION WHEN others THEN RETURN NULL;
  END;
END $date$;
REVOKE ALL ON FUNCTION public.pdc_email_resolve_business_date_686(text,date) FROM public,anon,authenticated,service_role,pdc_email_monitor;

-- Exact live actor, .44 binding, synthetic fixture, claim, mailbox and hashes.
CREATE FUNCTION public.pdc_monitor_authenticated_acceptance_scope_686(p_intake_id uuid,p_evidence_hash text,p_claim_token uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $scope$
DECLARE f public.pdc_authenticated_email_acceptance_campaign_fixtures_686%rowtype; r public.pdc_authenticated_email_acceptance_campaign_runs_686%rowtype; i public.ai_email_intake%rowtype; a public.ai_email_attachments%rowtype; o public.pdc_provider_email_observations%rowtype; c public.pdc_authenticated_provider_import_agentic_compatibility_controls_684%rowtype;
BEGIN
 IF auth.role()<>'authenticated' OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au' OR p_evidence_hash!~'^[a-f0-9]{64}$' THEN RETURN jsonb_build_object('ok',false,'code','acceptance_scope_required'); END IF;
 SELECT * INTO f FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 WHERE active AND intake_id=p_intake_id AND source_hash=lower(p_evidence_hash) AND claim_token=p_claim_token;
 SELECT * INTO r FROM public.pdc_authenticated_email_acceptance_campaign_runs_686 WHERE run_id=f.run_id AND status='active';
 SELECT * INTO c FROM public.pdc_authenticated_provider_import_agentic_compatibility_controls_684 WHERE singleton AND enabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes;
 SELECT * INTO i FROM public.ai_email_intake WHERE id=f.intake_id AND status='processing' AND locked_by=auth.uid() AND claim_token=f.claim_token AND gateway_instance_id=c.gateway_instance_id AND provider_uid=f.provider_uid AND source_hash=f.source_hash AND coalesce(nullif(btrim(internet_message_id),''),graph_message_id)=f.message_id AND lower(btrim(sender_email))=lower(f.sender) AND recipient_mailbox='pmbcontroller@gmail.com' AND provider_authserv_id='mx.google.com' AND provider_authentication->'gmail_authentication_results'='true'::jsonb;
 SELECT * INTO a FROM public.ai_email_attachments WHERE id=f.attachment_id AND intake_id=f.intake_id AND source_hash=f.attachment_hash AND lower(content_type)='application/pdf' AND text_extraction_status='extracted';
 SELECT * INTO o FROM public.pdc_provider_email_observations WHERE observation_id=f.observation_id AND intake_id=f.intake_id AND attachment_id=f.attachment_id AND parent_source_hash=f.source_hash AND attachment_source_hash=f.attachment_hash AND provider_message_id=f.message_id AND provider_authserv_id='mx.google.com';
 IF f.fixture_id IS NULL OR r.run_id IS NULL OR c.actor_id IS NULL OR NOT public.pdc_monitor_authenticated_active_scope_674(c.gateway_instance_id) OR i.id IS NULL OR a.id IS NULL OR o.observation_id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','acceptance_scope_required'); END IF;
 RETURN jsonb_build_object('ok',true,'code','acceptance_scope_verified','fixture_id',f.fixture_id,'run_id',r.run_id,'intake_id',f.intake_id,'vehicle_id',f.vehicle_id,'booking_id',f.booking_id,'provider_uid',f.provider_uid,'source_hash',f.source_hash,'attachment_hash',f.attachment_hash,'claim_token',f.claim_token,'gateway_instance_id',c.gateway_instance_id,'release_name',c.release_name,'actor_id',c.actor_id,'actor_email',c.actor_email,'server_application_role',c.server_application_role,'planner_sha256',c.planner_sha256,'trust_receipt_sha256',c.trust_receipt_sha256,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'production_writes',false);
EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'code','acceptance_scope_required');
END $scope$;
REVOKE ALL ON FUNCTION public.pdc_monitor_authenticated_acceptance_scope_686(uuid,text,uuid) FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.create_pdc_authenticated_acceptance_campaign_686()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $create$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_run uuid:=gen_random_uuid(); v_namespace text:='pdc-acceptance-686:'||v_run::text; v_vehicle public.vehicles%rowtype; v_provider public.sublet_providers%rowtype; v_booking public.pdc_sublet_booking_instances%rowtype; v_result jsonb; v_case text; v_uid integer:=514; v_fixture uuid; v_intake uuid; v_attachment uuid; v_observation uuid; v_token uuid; v_source text; v_attachment_hash text; v_message text; v_sender text; v_text text; v_auth jsonb:=jsonb_build_object('dkim_aligned',true,'dmarc_aligned',true,'gmail_authentication_results',true,'sender_domain','staging.pdc-workshop.example.com','spf_aligned',true); v_expected jsonb; v_version bigint;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR auth.role()<>'authenticated' OR v_actor<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR v_email<>'sales@broometoyota.com.au' OR NOT public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1') THEN RETURN jsonb_build_object('ok',false,'code','acceptance_campaign_scope_required'); END IF;
 SELECT * INTO v_vehicle FROM public.vehicles WHERE id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid AND public.normalize_vehicle_stock_number(stock_number)='13000765' AND lifecycle_state='active' AND deleted_at IS NULL AND visible_on_board FOR UPDATE;
 IF NOT FOUND OR v_vehicle.source_system<>'microsoft_navision' OR v_vehicle.source_batch_id NOT IN('14450','37047') OR v_vehicle.source_record_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.id=v_vehicle.source_record_id::uuid AND n.is_current AND n.record_status='current' AND n.dealer_code=v_vehicle.source_batch_id AND public.normalize_vehicle_stock_number(n.normalized_data->>'batch')='13000765') OR NOT EXISTS(SELECT 1 FROM public.navision_board_activations b WHERE b.canonical_vehicle_id=v_vehicle.id AND b.active AND public.normalize_vehicle_stock_number(b.activated_stock_number)='13000765') THEN RETURN jsonb_build_object('ok',false,'code','acceptance_target_identity_or_visibility_required'); END IF;
 SELECT * INTO v_provider FROM public.sublet_providers WHERE active AND lower(name)='customer sublet';
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_provider_required'); END IF;
 SELECT * INTO v_booking FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v_vehicle.id AND status='active' FOR UPDATE;
 IF FOUND THEN
   IF (SELECT count(*) FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v_vehicle.id AND status='active')<>1 OR v_booking.provider_id<>v_provider.id OR v_booking.out_date<>'2026-09-10'::date THEN RETURN jsonb_build_object('ok',false,'code','acceptance_manual_sublet_prestate_mismatch'); END IF;
 ELSE
   v_result:=public.create_pdc_sublet_booking(v_vehicle.id,v_vehicle.version,v_provider.id,'2026-09-10','2026-09-11','', 'HERMES bounded staging acceptance fixture');
   IF coalesce((v_result->>'ok')::boolean,false) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','acceptance_manual_sublet_setup_failed','detail',v_result); END IF;
   SELECT * INTO v_booking FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v_vehicle.id AND status='active';
 END IF;
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes,updated_at)
 VALUES(v_vehicle.id,'sublet',true,false,'Required after manual canonical Sublet booking; HERMES acceptance fixture',clock_timestamp())
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true WHERE NOT public.vehicle_work_items.completed;
 INSERT INTO public.pdc_authenticated_email_acceptance_campaign_runs_686(namespace,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,target_vehicle_id,target_stock_number,status,acceptance_case_count)
 VALUES(v_namespace,v_actor,v_email,'authenticated','importer','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',v_vehicle.id,'13000765','active',6);
 FOREACH v_case IN ARRAY ARRAY['parts_eta','parts_complete','sublet_booking_date','multi_action','exact_replay','ambiguous_negative'] LOOP
   v_uid:=v_uid+1; v_fixture:=gen_random_uuid(); v_intake:=gen_random_uuid(); v_attachment:=gen_random_uuid(); v_observation:=gen_random_uuid(); v_token:=gen_random_uuid(); v_sender:='pdc-acceptance-'||replace(v_run::text,'-','')||'-'||v_case||'@staging.pdc-workshop.example.com'; v_message:='<pdc-acceptance-686-'||replace(v_run::text,'-','')||'-'||v_case||'@staging.invalid>'; v_source:=encode(extensions.digest(convert_to(v_namespace||'|'||v_case,'UTF8'),'sha256'),'hex'); v_attachment_hash:=encode(extensions.digest(convert_to(v_namespace||'|attachment|'||v_case,'UTF8'),'sha256'),'hex');
   v_text:=case v_case when 'parts_eta' then '13000765 parts ETA is 12 June.' when 'parts_complete' then '13000765 parts are complete.' when 'sublet_booking_date' then '13000765 sublet is booked for 15 September.' when 'multi_action' then '13000765 parts ETA is 15 September. 13000765 parts are complete. 13000765 sublet is booked for 15 September.' when 'exact_replay' then '13000765 parts ETA is 12 June.' else '13000765 parts may be complete or perhaps not.' end;
   v_expected:=case v_case when 'parts_eta' then '{"parts.eta":"2027-06-12"}'::jsonb when 'parts_complete' then '{"parts.complete":true}'::jsonb when 'sublet_booking_date' then '{"sublet.booking_date":"2026-09-15"}'::jsonb when 'multi_action' then '{"ordered":["parts_eta","parts_complete","sublet_booking_date"]}'::jsonb when 'exact_replay' then '{"parts.eta":"2027-06-12"}'::jsonb else '{"disposition":"GENUINELY_AMBIGUOUS"}'::jsonb end;
   INSERT INTO public.ai_email_intake(id,status,subject,sender_email,sender_name,received_at,graph_message_id,graph_thread_id,internet_message_id,attachment_names,raw_body,parsed_text,extracted_data,confidence,warnings,processing_result,monitored_mailbox_id,recipient_mailbox,queue_attempts,permanent_failure,provider_uid,source_hash,claim_token,gateway_instance_id,provider_authserv_id,provider_authentication,locked_at,locked_by)
   VALUES(v_intake,'processing','PDC Acceptance 686 '||v_case,v_sender,'PDC Acceptance Fixture',clock_timestamp(),v_message,v_namespace||'|'||v_case,v_message,ARRAY['acceptance-'||v_case||'.pdf'],v_text,v_text,'{}'::jsonb,1,'{}','{"test_fixture":true,"campaign":"686"}'::jsonb,'12fe383d-5c1e-5801-96e4-f67cf3e3bb57','pmbcontroller@gmail.com',0,false,'imap_uid:'||v_uid,v_source,v_token,'pdc-monitor-staging-sales-uid509-v1','mx.google.com',v_auth,clock_timestamp(),v_actor);
   INSERT INTO public.ai_email_attachments(id,intake_id,file_name,content_type,size_bytes,storage_path,text_extraction_status,extracted_text,source_hash) VALUES(v_attachment,v_intake,'acceptance-'||v_case||'.pdf','application/pdf',1024,'pdc-email-intake-private/acceptance-686/'||v_attachment_hash||'.pdf','extracted',v_text,v_attachment_hash);
   INSERT INTO public.pdc_provider_email_observations(observation_id,contract_version,intake_id,attachment_id,parent_source_hash,attachment_source_hash,provider_message_id,provider_authserv_id,authentication,request_sha256,attested_by,attested_authority) VALUES(v_observation,'159.2',v_intake,v_attachment,v_source,v_attachment_hash,v_message,'mx.google.com',v_auth,encode(extensions.digest(convert_to(v_namespace||'|observation|'||v_case,'UTF8'),'sha256'),'hex'),v_actor,'authenticated_acceptance_686');
   INSERT INTO public.pdc_authenticated_email_acceptance_campaign_fixtures_686(run_id,case_key,instruction_no,intake_id,attachment_id,observation_id,vehicle_id,booking_id,provider_uid,source_hash,attachment_hash,claim_token,message_id,sender,natural_language,expected)
   VALUES(v_run,v_case,1,v_intake,v_attachment,v_observation,v_vehicle.id,case when v_case in('sublet_booking_date','multi_action') then v_booking.booking_id else null end,'imap_uid:'||v_uid,v_source,v_attachment_hash,v_token,v_message,v_sender,v_text,v_expected);
 END LOOP;
 UPDATE public.pdc_authenticated_email_acceptance_campaign_runs_686 SET result=jsonb_build_object('fixture_count',6,'provider_uid_floor',515,'synthetic_fixture',true,'manual_booking_id',v_booking.booking_id,'manual_booking_date','2026-09-10','provider_id',v_provider.id,'target_vehicle_id',v_vehicle.id,'production_writes',false,'task_enabled',false,'mailbox_contacted',false) WHERE run_id=v_run;
 RETURN jsonb_build_object('ok',true,'code','acceptance_campaign_created','run_id',v_run,'namespace',v_namespace,'fixture_count',6,'acceptance_case_count',6,'provider_uid_floor',515,'target_vehicle_id',v_vehicle.id,'target_stock_number','13000765','manual_booking_id',v_booking.booking_id,'manual_booking_date','2026-09-10','provider_id',v_provider.id,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'fixtures',(SELECT coalesce(jsonb_agg(jsonb_build_object('fixture_id',fixture_id,'case_key',case_key,'intake_id',intake_id,'attachment_id',attachment_id,'observation_id',observation_id,'vehicle_id',vehicle_id,'booking_id',booking_id,'claim_token',claim_token,'provider_uid',provider_uid,'source_hash',source_hash,'attachment_hash',attachment_hash,'message_id',message_id,'sender',sender,'natural_language',natural_language,'expected',expected) ORDER BY provider_uid),'[]'::jsonb) FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 WHERE run_id=v_run));
EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'code','acceptance_campaign_create_failed');
END $create$;
REVOKE ALL ON FUNCTION public.create_pdc_authenticated_acceptance_campaign_686() FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.create_pdc_authenticated_acceptance_campaign_686() TO authenticated;

CREATE FUNCTION public.record_pdc_authenticated_email_acceptance_plan_686(p_intake_id uuid,p_evidence_hash text,p_claim_token uuid,p_instruction text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $plan$
DECLARE s jsonb; f public.pdc_authenticated_email_acceptance_campaign_fixtures_686%rowtype; existing public.pdc_authenticated_email_acceptance_plans_686%rowtype; v_instruction text:=btrim(coalesce(p_instruction,'')); v_lower text:=lower(v_instruction); v_actions jsonb:='[]'::jsonb; v_date_text text; v_date date; v_plan_hash text; v_action_hash text; v_no integer:=0; v_stock_count integer; v_other_stock_count integer;
BEGIN
 s:=public.pdc_monitor_authenticated_acceptance_scope_686(p_intake_id,lower(btrim(coalesce(p_evidence_hash,''))),p_claim_token); IF s->>'ok'<>'true' THEN RETURN s; END IF;
 SELECT * INTO f FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 WHERE fixture_id=(s->>'fixture_id')::uuid;
 SELECT * INTO existing FROM public.pdc_authenticated_email_acceptance_plans_686 WHERE fixture_id=f.fixture_id;
 IF FOUND THEN IF existing.instruction<>v_instruction THEN RETURN jsonb_build_object('ok',false,'code','acceptance_plan_replay_conflict'); END IF; RETURN jsonb_build_object('ok',true,'code','acceptance_plan_replayed','plan_receipt_id',existing.plan_receipt_id,'plan_hash',existing.plan_hash,'evidence_hash',existing.evidence_hash,'actions',existing.actions,'replay',true); END IF;
 IF length(v_instruction) NOT BETWEEN 3 AND 2000 OR v_instruction~'[[:cntrl:]]' OR v_lower~'\m(if|maybe|perhaps|possibly|not|pending|uncertain|could|would|should|might)\M' THEN v_actions:=jsonb_build_array(jsonb_build_object('action_no',1,'action_type','unparsed','evidence',v_instruction,'disposition','GENUINELY_AMBIGUOUS','reason','Genuinely unclear natural-language instruction; no canonical action inferred')); ELSE
   SELECT count(*) INTO v_stock_count FROM regexp_matches(v_instruction,'(?<![0-9])13000765(?![0-9])','g');
   SELECT count(*) INTO v_other_stock_count FROM regexp_matches(v_instruction,'(?<![0-9])[0-9]{8}(?![0-9])','g') m WHERE m[1]<>'13000765';
   IF v_stock_count<1 OR v_other_stock_count>0 THEN v_actions:=jsonb_build_array(jsonb_build_object('action_no',1,'action_type','unparsed','evidence',v_instruction,'disposition','GENUINELY_AMBIGUOUS','reason','Exact Stock 13000765 identity was not uniquely established')); ELSE
     IF v_lower~'parts?[[:space:]]+(?:eta|arrival|arrive)[[:space:]]+(?:is|on|arrives?)[[:space:]]+' THEN
       v_date_text:=((regexp_matches(v_lower,'parts?[[:space:]]+(?:eta|arrival|arrive)[[:space:]]+(?:is|on|arrives?)[[:space:]]+((?:[0-9]{4}-[0-9]{2}-[0-9]{2})|(?:0?[1-9]|[12][0-9]|3[01])[[:space:]]+(?:january|february|march|april|may|june|july|august|september|october|november|december)|(?:(?:january|february|march|april|may|june|july|august|september|october|november|december)[[:space:]]+(?:0?[1-9]|[12][0-9]|3[01])))'))[1];
       v_date:=public.pdc_email_resolve_business_date_686(v_date_text,NULL); v_no:=v_no+1; v_actions:=v_actions||jsonb_build_array(jsonb_build_object('action_no',v_no,'action_type',case when v_date is null then 'unparsed' else 'parts_eta' end,'evidence',v_instruction,'date_text',v_date_text,'resolved_date',v_date,'reason',case when v_date is null then 'Genuinely unclear or invalid business date' else 'Canonical next non-past business-date interpretation' end));
     END IF;
     IF v_lower~'parts?[^.?!]{0,80}(?:are|is)[[:space:]]+(?:now[[:space:]]+)?(?:complete|completed|received)' THEN v_no:=v_no+1; v_actions:=v_actions||jsonb_build_array(jsonb_build_object('action_no',v_no,'action_type','parts_complete','evidence',v_instruction,'reason','Exact Parts complete assertion')); END IF;
     IF v_lower~'sub[ -]?let[^.?!]{0,120}(?:is[[:space:]]+)?booked[[:space:]]+for' THEN
       v_date_text:=((regexp_matches(v_lower,'sub[ -]?let[^.?!]{0,120}(?:is[[:space:]]+)?booked[[:space:]]+for[[:space:]]+((?:[0-9]{4}-[0-9]{2}-[0-9]{2})|(?:0?[1-9]|[12][0-9]|3[01])[[:space:]]+(?:january|february|march|april|may|june|july|august|september|october|november|december)|(?:(?:january|february|march|april|may|june|july|august|september|october|november|december)[[:space:]]+(?:0?[1-9]|[12][0-9]|3[01])))'))[1];
       SELECT booking_date INTO v_date FROM public.pdc_sublet_bookings WHERE vehicle_id=f.vehicle_id; IF v_date IS NULL THEN SELECT out_date INTO v_date FROM public.pdc_sublet_booking_instances WHERE booking_id=f.booking_id AND status='active'; END IF; v_date:=public.pdc_email_resolve_business_date_686(v_date_text,v_date); v_no:=v_no+1; v_actions:=v_actions||jsonb_build_array(jsonb_build_object('action_no',v_no,'action_type',case when v_date is null then 'unparsed' else 'sublet_booking_date' end,'evidence',v_instruction,'date_text',v_date_text,'resolved_date',v_date,'reason',case when v_date is null then 'Genuinely unclear or invalid business date' else 'Manual booking year preserved when valid and non-past' end));
     END IF;
     IF v_no=0 THEN v_actions:=jsonb_build_array(jsonb_build_object('action_no',1,'action_type','unparsed','evidence',v_instruction,'disposition','GENUINELY_AMBIGUOUS','reason','No exact supported canonical action was recognized')); END IF;
   END IF;
 END IF;
 v_plan_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract_version','pdc-email-ai-natural-language-686.1','intake_id',f.intake_id,'evidence_hash',f.source_hash,'instruction',v_instruction,'actions',v_actions)::text,'UTF8'),'sha256'),'hex');
 FOR v_no IN 1..jsonb_array_length(v_actions) LOOP v_action_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract_version','pdc-email-ai-natural-language-686.1','source_hash',f.source_hash,'plan_hash',v_plan_hash,'action',v_actions->(v_no-1))::text,'UTF8'),'sha256'),'hex'); v_actions:=jsonb_set(v_actions,ARRAY[(v_no-1)::text],(v_actions->(v_no-1))||jsonb_build_object('action_hash',v_action_hash),true); END LOOP;
 INSERT INTO public.pdc_authenticated_email_acceptance_plans_686(fixture_id,run_id,intake_id,evidence_hash,plan_hash,instruction,actions) VALUES(f.fixture_id,f.run_id,f.intake_id,f.source_hash,v_plan_hash,v_instruction,v_actions) RETURNING * INTO existing;
 RETURN jsonb_build_object('ok',true,'code','acceptance_plan_recorded','plan_receipt_id',existing.plan_receipt_id,'plan_hash',existing.plan_hash,'evidence_hash',existing.evidence_hash,'actions',existing.actions,'replay',false);
EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'code','acceptance_plan_invalid');
END $plan$;
REVOKE ALL ON FUNCTION public.record_pdc_authenticated_email_acceptance_plan_686(uuid,text,uuid,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.record_pdc_authenticated_email_acceptance_plan_686(uuid,text,uuid,text) TO authenticated;

CREATE FUNCTION public.read_pdc_authenticated_email_acceptance_context_686(p_intake_id uuid,p_evidence_hash text,p_claim_token uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $read$
DECLARE s jsonb; v public.vehicles%rowtype; p public.vehicle_parts_updates%rowtype; w public.vehicle_work_items%rowtype; b public.pdc_sublet_booking_instances%rowtype;
BEGIN
 s:=public.pdc_monitor_authenticated_acceptance_scope_686(p_intake_id,p_evidence_hash,p_claim_token); IF s->>'ok'<>'true' THEN RETURN s; END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=(s->>'vehicle_id')::uuid; SELECT * INTO p FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1; SELECT * INTO w FROM public.vehicle_work_items WHERE vehicle_id=v.id AND upper(work_key)='PARTS'; SELECT * INTO b FROM public.pdc_sublet_booking_instances WHERE booking_id=(s->>'booking_id')::uuid;
 RETURN s||jsonb_build_object('code','acceptance_context','vehicle',jsonb_build_object('id',v.id,'stock_number',v.stock_number,'version',v.version,'location',v.current_location,'visible_on_board',v.visible_on_board),'parts',jsonb_build_object('required',coalesce(p.parts_required,false),'ordered',coalesce(p.parts_ordered,false),'received',coalesce(p.parts_received,false),'eta',p.worst_eta,'completed',coalesce(w.completed,false)),'sublet',case when b.booking_id IS NULL then '{}'::jsonb else jsonb_build_object('booking_id',b.booking_id,'provider_id',b.provider_id,'provider_name',b.provider_name,'out_date',b.out_date,'expected_return_date',b.expected_return_date,'version',b.version,'status',b.status) end);
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_authenticated_email_acceptance_context_686(uuid,text,uuid) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.read_pdc_authenticated_email_acceptance_context_686(uuid,text,uuid) TO authenticated;

CREATE FUNCTION public.execute_pdc_authenticated_email_acceptance_action_686(p_intake_id uuid,p_evidence_hash text,p_claim_token uuid,p_plan_hash text,p_action_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $execute$
DECLARE s jsonb; f public.pdc_authenticated_email_acceptance_campaign_fixtures_686%rowtype; p public.pdc_authenticated_email_acceptance_plans_686%rowtype; a public.pdc_authenticated_email_acceptance_action_receipts_686%rowtype; x jsonb; v public.vehicles%rowtype; parts public.vehicle_parts_updates%rowtype; work public.vehicle_work_items%rowtype; booking public.pdc_sublet_booking_instances%rowtype; result jsonb; before_data jsonb; after_data jsonb; resolved date; disposition text; reason text; effects integer:=0; action_no integer;
BEGIN
 s:=public.pdc_monitor_authenticated_acceptance_scope_686(p_intake_id,p_evidence_hash,p_claim_token); IF s->>'ok'<>'true' THEN RETURN s; END IF;
 SELECT * INTO f FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 WHERE fixture_id=(s->>'fixture_id')::uuid; SELECT * INTO p FROM public.pdc_authenticated_email_acceptance_plans_686 WHERE plan_hash=lower(btrim(p_plan_hash)) AND fixture_id=f.fixture_id; IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_plan_not_found'); END IF;
 SELECT * INTO a FROM public.pdc_authenticated_email_acceptance_action_receipts_686 WHERE action_hash=lower(btrim(p_action_hash)) AND plan_receipt_id=p.plan_receipt_id; IF FOUND THEN RETURN jsonb_build_object('ok',true,'code','acceptance_action_replayed','action_receipt_id',a.action_receipt_id,'action_hash',a.action_hash,'action_type',a.action_type,'disposition',a.disposition,'reason',a.reason,'before_data',a.before_data,'after_data',a.after_data,'effect_count',a.effect_count,'replay',true); END IF;
 SELECT action_no,value INTO action_no,x FROM jsonb_array_elements(p.actions) WITH ORDINALITY q(value,action_no) WHERE value->>'action_hash'=lower(btrim(p_action_hash)); IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_action_not_in_plan'); END IF;
 IF (SELECT count(*) FROM public.pdc_authenticated_email_acceptance_action_receipts_686 WHERE plan_receipt_id=p.plan_receipt_id AND disposition='PENDING')>0 THEN RETURN jsonb_build_object('ok',false,'code','acceptance_concurrent_action_in_progress'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=f.vehicle_id FOR UPDATE; before_data:=jsonb_build_object('vehicle',to_jsonb(v));
 IF x->>'action_type'='unparsed' OR x->>'resolved_date' IS NULL AND x->>'action_type' IN('parts_eta','sublet_booking_date') THEN disposition:='GENUINELY_AMBIGUOUS'; reason:=coalesce(x->>'reason','Genuinely unclear instruction');
 ELSIF x->>'action_type'='parts_eta' THEN
   resolved:=(x->>'resolved_date')::date; SELECT * INTO parts FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1;
   IF parts.worst_eta=resolved THEN disposition:='ALREADY_CORRECT'; reason:='Parts ETA already equals resolved ISO date'; ELSE result:=public.update_pdc_parts_eta(v.id,v.version,resolved); IF coalesce((result->>'ok')::boolean,false) THEN effects:=1; disposition:='APPLIED_AND_VERIFIED'; reason:='Canonical Parts ETA RPC applied and read back'; ELSE disposition:='BLOCKED_WITH_EXACT_REASON'; reason:=coalesce(result->>'error',result->>'code','Canonical Parts ETA RPC rejected'); END IF; END IF;
 ELSIF x->>'action_type'='parts_complete' THEN
   SELECT * INTO parts FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1; SELECT * INTO work FROM public.vehicle_work_items WHERE vehicle_id=v.id AND upper(work_key)='PARTS' FOR UPDATE;
   IF coalesce(work.completed,false) AND coalesce(parts.parts_received,false) THEN disposition:='ALREADY_CORRECT'; reason:='Canonical Parts state already complete';
   ELSIF parts.worst_eta IS NULL THEN disposition:='BLOCKED_WITH_EXACT_REASON'; reason:='parts_eta_required';
   ELSE BEGIN result:=public.mark_pdc_parts_complete(v.id,v.version); IF coalesce((result->>'ok')::boolean,false) AND coalesce((result->>'code'),'') IN('parts_completed','replayed') THEN effects:=case when coalesce((result#>>'{data,changed}')::boolean,false) then 1 else 0 end; disposition:=case when effects=1 then 'APPLIED_AND_VERIFIED' else 'ALREADY_CORRECT' end; reason:='Canonical Parts Complete RPC applied and read back'; ELSE disposition:='BLOCKED_WITH_EXACT_REASON'; reason:=coalesce(result->>'error',result->>'code','Canonical Parts Complete RPC rejected'); END IF; EXCEPTION WHEN others THEN disposition:='BLOCKED_WITH_EXACT_REASON'; reason:=sqlerrm; END; END IF;
 ELSIF x->>'action_type'='sublet_booking_date' THEN
   resolved:=(x->>'resolved_date')::date; SELECT * INTO booking FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v.id AND status='active' FOR UPDATE;
   IF NOT FOUND OR (SELECT count(*) FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v.id AND status='active')<>1 THEN disposition:='BLOCKED_WITH_EXACT_REASON'; reason:='sublet_existing_booking_required';
   ELSIF booking.out_date=resolved THEN disposition:='ALREADY_CORRECT'; reason:='Existing canonical Sublet booking already equals resolved ISO date';
   ELSE result:=public.update_pdc_sublet_booking(booking.booking_id,booking.version,resolved,booking.expected_return_date,booking.notes); IF coalesce((result->>'ok')::boolean,false) THEN effects:=1; disposition:='APPLIED_AND_VERIFIED'; reason:='Existing canonical Sublet booking updated; no provider or booking created'; ELSE disposition:='BLOCKED_WITH_EXACT_REASON'; reason:=coalesce(result->>'error',result->>'code','Canonical Sublet update rejected'); END IF; END IF;
 ELSE disposition:='GENUINELY_AMBIGUOUS'; reason:='Unsupported natural-language action';
 END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=f.vehicle_id; SELECT * INTO parts FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1; SELECT * INTO work FROM public.vehicle_work_items WHERE vehicle_id=v.id AND upper(work_key)='PARTS'; SELECT * INTO booking FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v.id AND status='active' ORDER BY out_date,booking_id LIMIT 1; after_data:=jsonb_build_object('vehicle',to_jsonb(v),'parts',jsonb_build_object('required',coalesce(parts.parts_required,false),'ordered',coalesce(parts.parts_ordered,false),'received',coalesce(parts.parts_received,false),'eta',parts.worst_eta,'completed',coalesce(work.completed,false)),'sublet',case when booking.booking_id IS NULL then '{}'::jsonb else jsonb_build_object('booking_id',booking.booking_id,'provider_id',booking.provider_id,'out_date',booking.out_date,'version',booking.version,'status',booking.status) end);
 INSERT INTO public.pdc_authenticated_email_acceptance_action_receipts_686(plan_receipt_id,fixture_id,action_no,action_hash,action_type,requested,resolved_date,disposition,reason,before_data,after_data,effect_count,executed_at) VALUES(p.plan_receipt_id,f.fixture_id,action_no,p_action_hash,x->>'action_type',x,resolved,disposition,reason,before_data,after_data,effects,clock_timestamp());
 SELECT * INTO a FROM public.pdc_authenticated_email_acceptance_action_receipts_686 WHERE action_hash=p_action_hash;
 RETURN jsonb_build_object('ok',true,'code','acceptance_action_executed','action_receipt_id',a.action_receipt_id,'action_hash',a.action_hash,'action_no',a.action_no,'action_type',a.action_type,'resolved_date',a.resolved_date,'disposition',a.disposition,'reason',a.reason,'before_data',a.before_data,'after_data',a.after_data,'effect_count',a.effect_count,'replay',false);
EXCEPTION WHEN unique_violation THEN SELECT * INTO a FROM public.pdc_authenticated_email_acceptance_action_receipts_686 WHERE action_hash=p_action_hash; IF FOUND THEN RETURN jsonb_build_object('ok',true,'code','acceptance_action_replayed','action_receipt_id',a.action_receipt_id,'action_hash',a.action_hash,'action_type',a.action_type,'disposition',a.disposition,'reason',a.reason,'before_data',a.before_data,'after_data',a.after_data,'effect_count',a.effect_count,'replay',true); END IF; RETURN jsonb_build_object('ok',false,'code','acceptance_action_replay_conflict');
END $execute$;
REVOKE ALL ON FUNCTION public.execute_pdc_authenticated_email_acceptance_action_686(uuid,text,uuid,text,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.execute_pdc_authenticated_email_acceptance_action_686(uuid,text,uuid,text,text) TO authenticated;

CREATE FUNCTION public.finalize_pdc_authenticated_email_acceptance_plan_686(p_intake_id uuid,p_evidence_hash text,p_claim_token uuid,p_plan_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $final$
DECLARE s jsonb; p public.pdc_authenticated_email_acceptance_plans_686%rowtype; f public.pdc_authenticated_email_acceptance_campaign_fixtures_686%rowtype; a jsonb; result jsonb:='[]'::jsonb; n integer; total integer; blocked integer; ambiguous integer; applied integer; overall text; final_hash text; existing public.pdc_authenticated_email_acceptance_final_receipts_686%rowtype;
BEGIN
 s:=public.pdc_monitor_authenticated_acceptance_scope_686(p_intake_id,p_evidence_hash,p_claim_token); IF s->>'ok'<>'true' THEN RETURN s; END IF; SELECT * INTO f FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 WHERE fixture_id=(s->>'fixture_id')::uuid; SELECT * INTO p FROM public.pdc_authenticated_email_acceptance_plans_686 WHERE fixture_id=f.fixture_id AND plan_hash=lower(btrim(p_plan_hash)); IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_plan_not_found'); END IF;
 SELECT count(*) INTO total FROM jsonb_array_elements(p.actions); SELECT count(*) INTO n FROM public.pdc_authenticated_email_acceptance_action_receipts WHERE plan_receipt_id=p.plan_receipt_id AND disposition<>'PENDING'; IF n<>total THEN RETURN jsonb_build_object('ok',false,'code','acceptance_actions_not_terminal','expected',total,'actual',n); END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('action_no',r.action_no,'action_hash',r.action_hash,'action_type',r.action_type,'resolved_date',r.resolved_date,'disposition',r.disposition,'reason',r.reason,'effect_count',r.effect_count) ORDER BY r.action_no),'[]'::jsonb) INTO result FROM public.pdc_authenticated_email_acceptance_action_receipts_686 r WHERE r.plan_receipt_id=p.plan_receipt_id;
 SELECT count(*) FILTER(WHERE disposition='BLOCKED_WITH_EXACT_REASON'),count(*) FILTER(WHERE disposition='GENUINELY_AMBIGUOUS'),count(*) FILTER(WHERE disposition='APPLIED_AND_VERIFIED'),count(*) INTO blocked,ambiguous,applied,n FROM public.pdc_authenticated_email_acceptance_action_receipts_686 WHERE plan_receipt_id=p.plan_receipt_id;
 overall:=case when ambiguous>0 then 'GENUINELY_AMBIGUOUS' when blocked>0 then 'BLOCKED_WITH_EXACT_REASON' when applied>0 then 'APPLIED_AND_VERIFIED' else 'ALREADY_CORRECT' end;
 result:=jsonb_build_object('ok',blocked=0 and ambiguous=0,'code','acceptance_plan_finalized','outcome',overall,'plan_hash',p.plan_hash,'evidence_hash',p.evidence_hash,'fixture_id',f.fixture_id,'vehicle_id',f.vehicle_id,'target_stock_number','13000765','actions',result,'dependency_order',case when total>1 then ARRAY['parts_eta','parts_complete','sublet_booking_date'] else ARRAY[]::text[] end,'resolved_dates_in_plan',p.actions,'booking_created',false,'provider_created',false,'location_changed',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'production_writes',false);
 final_hash:=encode(extensions.digest(convert_to(result::text,'UTF8'),'sha256'),'hex'); INSERT INTO public.pdc_authenticated_email_acceptance_final_receipts_686(plan_receipt_id,fixture_id,evidence_hash,plan_hash,outcome,result,result_hash) VALUES(p.plan_receipt_id,f.fixture_id,p.evidence_hash,p.plan_hash,overall,result,final_hash) ON CONFLICT(plan_receipt_id) DO NOTHING; SELECT * INTO existing FROM public.pdc_authenticated_email_acceptance_final_receipts_686 WHERE plan_receipt_id=p.plan_receipt_id; RETURN jsonb_build_object('ok',true,'code',case when existing.result_hash=final_hash then 'acceptance_finalized' else 'acceptance_final_replayed' end,'final_receipt_id',existing.final_receipt_id,'outcome',existing.outcome,'result',existing.result,'result_hash',existing.result_hash,'replay',existing.result_hash=final_hash);
END $final$;
REVOKE ALL ON FUNCTION public.finalize_pdc_authenticated_email_acceptance_plan_686(uuid,text,uuid,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.finalize_pdc_authenticated_email_acceptance_plan_686(uuid,text,uuid,text) TO authenticated;

CREATE FUNCTION public.cleanup_pdc_authenticated_acceptance_campaign_686(p_run_id uuid,p_result jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $cleanup$
DECLARE r public.pdc_authenticated_email_acceptance_campaign_runs_686%rowtype; v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); n integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR auth.role()<>'authenticated' OR v_actor<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR v_email<>'sales@broometoyota.com.au' OR jsonb_typeof(coalesce(p_result,'{}'::jsonb))<>'object' THEN RETURN jsonb_build_object('ok',false,'code','acceptance_cleanup_scope_required'); END IF;
 SELECT * INTO r FROM public.pdc_authenticated_email_acceptance_campaign_runs_686 WHERE run_id=p_run_id AND actor_id=v_actor AND status='active' FOR UPDATE; IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_campaign_not_found'); END IF;
 UPDATE public.ai_email_intake SET status='failed',permanent_failure=true,retry_class='review',last_error_code='pdc_acceptance_686_cleaned',locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null WHERE id IN(SELECT intake_id FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 WHERE run_id=p_run_id);
 UPDATE public.pdc_authenticated_email_acceptance_campaign_fixtures_686 SET active=false,cleaned_at=clock_timestamp() WHERE run_id=p_run_id AND active;
 UPDATE public.pdc_authenticated_email_acceptance_campaign_runs_686 SET status='cleaned',cleaned_at=clock_timestamp(),result=coalesce(r.result,'{}'::jsonb)||jsonb_build_object('cleanup',p_result,'immutable_receipts_preserved',true,'target_vehicle_preserved',true,'production_untouched',true) WHERE run_id=p_run_id;
 SELECT count(*) INTO n FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 WHERE run_id=p_run_id AND active;
 RETURN jsonb_build_object('ok',true,'code','acceptance_campaign_cleaned','run_id',p_run_id,'active_fixtures',n,'immutable_receipts_preserved',true,'target_vehicle_preserved',true,'production_writes',false);
END $cleanup$;
REVOKE ALL ON FUNCTION public.cleanup_pdc_authenticated_acceptance_campaign_686(uuid,jsonb) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.cleanup_pdc_authenticated_acceptance_campaign_686(uuid,jsonb) TO authenticated;

CREATE FUNCTION public.read_pdc_authenticated_acceptance_campaign_686(p_run_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $read$
DECLARE r public.pdc_authenticated_email_acceptance_campaign_runs_686%rowtype; f jsonb; p jsonb; a jsonb; fin jsonb; v jsonb; n integer;
BEGIN
 IF auth.role()<>'authenticated' OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid THEN RETURN jsonb_build_object('ok',false,'code','acceptance_campaign_read_scope_required'); END IF;
 SELECT * INTO r FROM public.pdc_authenticated_email_acceptance_campaign_runs_686 WHERE run_id=p_run_id AND actor_id=auth.uid(); IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','acceptance_campaign_not_found'); END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.provider_uid),'[]'::jsonb) INTO f FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 x WHERE x.run_id=p_run_id;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at),'[]'::jsonb) INTO p FROM public.pdc_authenticated_email_acceptance_plans_686 x WHERE x.run_id=p_run_id;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at),'[]'::jsonb) INTO a FROM public.pdc_authenticated_email_acceptance_action_receipts_686 x JOIN public.pdc_authenticated_email_acceptance_plans_686 q ON q.plan_receipt_id=x.plan_receipt_id WHERE q.run_id=p_run_id;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at),'[]'::jsonb) INTO fin FROM public.pdc_authenticated_email_acceptance_final_receipts_686 x JOIN public.pdc_authenticated_email_acceptance_plans_686 q ON q.plan_receipt_id=x.plan_receipt_id WHERE q.run_id=p_run_id;
 SELECT jsonb_build_object('id',v.id,'stock_number',v.stock_number,'version',v.version,'location',v.current_location,'visible_on_board',v.visible_on_board,'parts',jsonb_build_object('eta',(SELECT worst_eta FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1),'received',(SELECT parts_received FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1),'completed',(SELECT completed FROM public.vehicle_work_items WHERE vehicle_id=v.id AND upper(work_key)='PARTS')),'sublet',(SELECT jsonb_build_object('booking_id',booking_id,'provider_id',provider_id,'out_date',out_date,'version',version,'status',status) FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v.id AND status='active' ORDER BY out_date,booking_id LIMIT 1)) INTO v FROM public.vehicles v WHERE v.id=r.target_vehicle_id;
 RETURN jsonb_build_object('ok',true,'code','acceptance_campaign_readback','run_id',r.run_id,'namespace',r.namespace,'status',r.status,'fixture_count',jsonb_array_length(f),'acceptance_case_count',r.acceptance_case_count,'fixtures',f,'plans',p,'actions',a,'final_receipts',fin,'target',v,'result',r.result,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false);
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_authenticated_acceptance_campaign_686(uuid) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.read_pdc_authenticated_acceptance_campaign_686(uuid) TO authenticated;

-- Board projection repair: retain the existing snapshot and append only an exact
-- current Navision activation that satisfies dealer, source-row and visibility
-- rules. No receipt/table bypass is admitted for any other vehicle.
ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_686;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE r jsonb; rows jsonb; target jsonb;
BEGIN
 r:=public.get_pdc_email_vehicle_location_snapshot_pre_686(); IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
 SELECT jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,'registration',v.registration,'current_location',v.current_location,'visible_on_board',v.visible_on_board,'source_system',v.source_system,'source_record_id',v.source_record_id,'updated_at',v.updated_at,'operation_lines',coalesce((SELECT jsonb_agg(jsonb_build_object('operation_line_id',ol.operation_line_id,'operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source,'source_uid',ol.source_uid,'job_card_number',ol.job_card_number,'source_row_no',ol.source_row_no,'source_contract',ol.source_contract,'source_ref',ol.source_ref,'created_at',ol.created_at) ORDER BY ol.source_row_no,ol.operation_line_id) FROM public.pdc_authenticated_email_operation_lines ol WHERE ol.vehicle_id=v.id),'[]'::jsonb),'work_items',coalesce((SELECT jsonb_agg(jsonb_build_object('work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at,'completed_by',wi.completed_by) ORDER BY wi.work_key) FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id),'[]'::jsonb),'parts_required',coalesce((SELECT parts_required FROM public.vehicle_parts_updates pu WHERE pu.vehicle_id=v.id ORDER BY pu.updated_at DESC,pu.id DESC LIMIT 1),false),'parts_completed',coalesce((SELECT completed FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND upper(wi.work_key)='PARTS'),false),'parts_update',coalesce((SELECT jsonb_build_object('parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,'parts_received',pu.parts_received,'parts_stoppage',pu.parts_stoppage,'parts_stoppage_reason',pu.parts_stoppage_reason,'worst_eta',pu.worst_eta,'updated_at',pu.updated_at) FROM public.vehicle_parts_updates pu WHERE pu.vehicle_id=v.id ORDER BY pu.updated_at DESC,pu.id DESC LIMIT 1),'{}'::jsonb),'sublet_booking',coalesce((SELECT jsonb_build_object('provider',b.provider_name,'provider_email',b.provider_email,'booking_date',b.out_date,'expected_return_date',b.expected_return_date,'notes',b.notes,'version',b.version,'provider_id',b.provider_id,'booking_id',b.booking_id) FROM public.pdc_sublet_booking_instances b WHERE b.vehicle_id=v.id AND b.status='active' ORDER BY b.out_date,b.booking_id LIMIT 1),'{}'::jsonb),'sublet_bookings',coalesce((SELECT jsonb_agg(jsonb_build_object('booking_id',b.booking_id,'vehicle_id',b.vehicle_id,'vehicle_version',b.vehicle_version,'provider_id',b.provider_id,'provider_name',b.provider_name,'provider_email',b.provider_email,'out_date',b.out_date,'expected_return_date',b.expected_return_date,'status',b.status,'returned_at',b.returned_at,'returned_by',b.returned_by,'version',b.version,'notes',b.notes,'updated_at',b.updated_at) ORDER BY b.out_date,b.booking_id) FROM public.pdc_sublet_booking_instances b WHERE b.vehicle_id=v.id),'[]'::jsonb),'sublet_active_count',(SELECT count(*) FROM public.pdc_sublet_booking_instances b WHERE b.vehicle_id=v.id AND b.status='active')) INTO target FROM public.vehicles v WHERE v.id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid AND public.normalize_vehicle_stock_number(v.stock_number)='13000765' AND v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board AND v.source_system='microsoft_navision' AND v.source_batch_id IN('14450','37047') AND v.source_record_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.id=v.source_record_id::uuid AND n.is_current AND n.record_status='current' AND n.dealer_code=v.source_batch_id AND public.normalize_vehicle_stock_number(n.normalized_data->>'batch')='13000765') AND EXISTS(SELECT 1 FROM public.navision_board_activations b WHERE b.canonical_vehicle_id=v.id AND b.active AND public.normalize_vehicle_stock_number(b.activated_stock_number)='13000765');
 SELECT coalesce(jsonb_agg(x ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb) INTO rows FROM (SELECT value x FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) q UNION ALL SELECT target WHERE target IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) q WHERE q->>'id'=target->>'id')) z;
 RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;
DO $publication$ BEGIN IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') AND NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='pdc_email_vehicle_revision') THEN ALTER PUBLICATION supabase_realtime ADD TABLE public.pdc_email_vehicle_revision; END IF; END $publication$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828070000','686_authenticated_email_ai_final_functional_remediation',ARRAY['Exact 685 timestamp head and live claimed UID514 state guard; UID514 is never reprocessed','Narrow exact authenticated actor .44 binding validates actor/email/importer/writer/gateway/release/source/manifest/planner/trust/mailbox/claim/intake/evidence hashes','Manual canonical Sublet setup ensures one bounded Customer Sublet booking on Stock 13000765 at 2026-09-10 before AI tests; AI path only updates that booking','Deterministic yearless dates resolve to next non-past staging date; valid existing Sublet booking year is preserved; ISO date is retained in plan/evidence','Server natural-language plan splits multi-action instructions in ETA, Parts Complete, Sublet dependency order and records every action disposition','Canonical Parts ETA, Parts Complete and existing-booking Sublet update wrappers are idempotent and append-only; no provider/booking/location create by AI','Immutable instruction/action/final receipts; wrong actor/hash/plan/action/replay/concurrency fail closed; direct tables and operator RPC grants remain unchanged','Exact activated Navision Stock 13000765 projection is appended only when current source row, dealer/batch, activation and visibility predicates pass; Realtime revision publication preserved','Synthetic acceptance rows are provider UID 515+ and explicitly marked; cleanup archives only synthetic intakes and retains immutable receipts; task/mailbox/UID514/outbound/Production remain untouched']);
NOTIFY pgrst,'reload schema';
COMMIT;
