-- STAGING ONLY 20260902264000: source-bound Job Card parity for exact
-- attachment evidence. No generic DML, role broadening or receipt rewriting.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260902264000-job-card-parity-correction',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260902263200
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260902264000')
     OR to_regclass('public.pdc_email_ai_successor_runtime_identities') IS NULL
     OR to_regclass('public.pdc_monitor_stage_activation_writers') IS NULL
     OR to_regclass('public.pdc_authenticated_email_import_receipts') IS NULL
     OR to_regclass('public.ai_email_intake') IS NULL
     OR to_regclass('public.ai_email_attachments') IS NULL
     OR to_regclass('public.pdc_provider_email_observations') IS NULL
     OR to_regclass('public.pdc_email_ai_successor_action_receipts') IS NULL
     OR to_regclass('public.pdc_email_ai_successor_transaction_receipts') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_action_readback_20260901(uuid,text,jsonb,jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_action_readback_parity_20260901(text,jsonb,jsonb,jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260902264000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_job_card_parity_corrections_20260902(
  correction_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_receipt_id uuid NOT NULL UNIQUE REFERENCES public.ai_email_intake(id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  source_hash text NOT NULL CHECK(source_hash~'^[a-f0-9]{64}$'),
  source_uid text NOT NULL,
  attachment_digest text NOT NULL CHECK(attachment_digest~'^[a-f0-9]{64}$'),
  stock_number text NOT NULL,
  vin text,
  job_card_number text NOT NULL CHECK(job_card_number~'^(J|JC)[0-9]{6,12}$'),
  request_hash text NOT NULL UNIQUE CHECK(request_hash~'^[a-f0-9]{64}$'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  corrected_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_job_card_parity_corrections_20260902 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_job_card_parity_corrections_20260902 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_job_card_parity_corrections_20260902 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_job_card_parity_corrections_immutable_20260902()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_20260902264000_CORRECTION_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_job_card_parity_corrections_immutable_20260902
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_job_card_parity_corrections_20260902
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_job_card_parity_corrections_immutable_20260902();

CREATE TABLE public.pdc_email_ai_v2_job_card_parity_correction_history_20260902(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260902263200'),
  successor_head text NOT NULL CHECK(successor_head='20260902264000'),
  predecessor_hashes jsonb NOT NULL CHECK(jsonb_typeof(predecessor_hashes)='object'),
  successor_hashes jsonb NOT NULL CHECK(jsonb_typeof(successor_hashes)='object'),
  contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_job_card_parity_correction_history_20260902 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_job_card_parity_correction_history_20260902 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_job_card_parity_correction_history_20260902 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_job_card_parity_correction_history_immutable_20260902()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_20260902264000_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_job_card_parity_correction_history_immutable_20260902
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_job_card_parity_correction_history_20260902
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_job_card_parity_correction_history_immutable_20260902();

ALTER TABLE public.pdc_email_ai_successor_action_receipts
  DROP CONSTRAINT IF EXISTS pdc_email_ai_successor_action_receipts_action_type_check;
ALTER TABLE public.pdc_email_ai_successor_action_receipts
  ADD CONSTRAINT pdc_email_ai_successor_action_receipts_action_type_check
  CHECK(action_type IN('activate_from_navision','activate_vehicle','location_set','workgroup_requirement_set','operation_upsert','operation_add','operation_update','parts_eta_set','parts_ordered','parts_complete','notes_append','note_append','job_card_upsert','job_card_set','sublet_booking_upsert','booking_set','booking_move','booking_cancel','required_work_set','work_complete','rft_transfer','rft_collect'));

CREATE FUNCTION public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(
  p_source_receipt_id uuid, p_vehicle_id uuid, p_source_hash text, p_source_uid text,
  p_attachment_digest text, p_stock_number text, p_vin text, p_job_card_number text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions AS $jobcard$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_identity public.pdc_email_ai_successor_runtime_identities%rowtype;
  v_intake public.ai_email_intake%rowtype;
  v_receipt public.pdc_authenticated_email_import_receipts%rowtype;
  v_attachment public.ai_email_attachments%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_existing public.pdc_email_ai_v2_job_card_parity_corrections_20260902%rowtype;
  v_before jsonb; v_after jsonb; v_response jsonb; v_request_hash text;
  v_operation_count integer; v_booking_count integer; v_correction_id uuid:=gen_random_uuid();
  v_evidence text;
BEGIN
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard()
     OR auth.role()<>'authenticated' OR v_actor IS NULL OR v_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','runtime_identity_required');
  END IF;
  SELECT * INTO v_identity FROM public.pdc_email_ai_successor_runtime_identities
   WHERE auth_user_id=v_actor AND normalized_email=v_email AND environment='staging'
     AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL FOR SHARE;
  IF NOT FOUND OR EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND r.active AND r.account_status='approved' AND r.role::text='administrator')
     OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL) THEN
    RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied');
  END IF;
  IF p_source_receipt_id IS NULL OR p_vehicle_id IS NULL OR lower(btrim(coalesce(p_source_hash,''))) !~ '^[a-f0-9]{64}$'
     OR btrim(coalesce(p_source_uid,''))='' OR lower(btrim(coalesce(p_attachment_digest,''))) !~ '^[a-f0-9]{64}$'
     OR public.normalize_vehicle_stock_number(p_stock_number) IS NULL
     OR (p_vin IS NOT NULL AND public.normalize_vehicle_vin(p_vin) IS NULL)
     OR btrim(coalesce(p_job_card_number,'')) !~ '^(J|JC)[0-9]{6,12}$' THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_job_card_request');
  END IF;
  v_request_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'source_receipt_id',p_source_receipt_id,'vehicle_id',p_vehicle_id,'source_hash',lower(btrim(p_source_hash)),
    'source_uid',btrim(p_source_uid),'attachment_digest',lower(btrim(p_attachment_digest)),
    'stock_number',public.normalize_vehicle_stock_number(p_stock_number),'vin',public.normalize_vehicle_vin(p_vin),
    'job_card_number',upper(btrim(p_job_card_number)))::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-email-ai-job-card:'||lower(btrim(p_source_hash)),0));
  SELECT * INTO v_existing FROM public.pdc_email_ai_v2_job_card_parity_corrections_20260902 WHERE source_receipt_id=p_source_receipt_id FOR SHARE;
  IF FOUND THEN
    IF v_existing.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict'); END IF;
    RETURN v_existing.response||jsonb_build_object('correction_replay',true);
  END IF;
  SELECT * INTO v_intake FROM public.ai_email_intake WHERE id=p_source_receipt_id AND lower(source_hash)=lower(btrim(p_source_hash)) AND duplicate_of IS NULL FOR SHARE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict'); END IF;
  SELECT * INTO v_receipt FROM public.pdc_authenticated_email_import_receipts
   WHERE source_hash=lower(btrim(p_source_hash)) AND vehicle_id=p_vehicle_id FOR SHARE;
  IF NOT FOUND OR v_receipt.source_uid<>btrim(p_source_uid) OR v_receipt.vehicle_id<>p_vehicle_id THEN
    RETURN jsonb_build_object('ok',false,'code','source_receipt_not_found');
  END IF;
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state::text<>'active' OR NOT v_vehicle.visible_on_board THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_lifecycle_protected');
  END IF;
  IF public.normalize_vehicle_stock_number(v_vehicle.stock_number)<>public.normalize_vehicle_stock_number(p_stock_number)
     OR (p_vin IS NOT NULL AND v_vehicle.vin IS NOT NULL AND public.normalize_vehicle_vin(v_vehicle.vin)<>public.normalize_vehicle_vin(p_vin)) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_identity_conflict');
  END IF;
  IF v_vehicle.job_card_number IS NOT NULL AND upper(btrim(v_vehicle.job_card_number))<>upper(btrim(p_job_card_number)) THEN
    RETURN jsonb_build_object('ok',false,'code','job_card_conflict_protected');
  END IF;
  SELECT * INTO v_attachment FROM public.ai_email_attachments
   WHERE intake_id=v_intake.id AND lower(source_hash)=lower(btrim(p_attachment_digest)) FOR SHARE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','attachment_source_mismatch'); END IF;
  v_evidence:=lower(coalesce(v_attachment.file_name,'')||' '||coalesce(v_attachment.extracted_text,''));
  IF position(lower(btrim(p_job_card_number)) IN v_evidence)=0
     OR position(lower(public.normalize_vehicle_stock_number(p_stock_number)) IN v_evidence)=0
     OR (p_vin IS NOT NULL AND position(lower(public.normalize_vehicle_vin(p_vin)) IN v_evidence)=0)
     OR v_evidence !~ '(^|[^a-z0-9])(j|jc)[0-9]{6,12}([^a-z0-9]|$)' THEN
    RETURN jsonb_build_object('ok',false,'code','attachment_source_mismatch');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_provider_email_observations o WHERE o.intake_id=v_intake.id AND o.attachment_id=v_attachment.id AND o.parent_source_hash=lower(btrim(p_source_hash)) AND o.attachment_source_hash=lower(btrim(p_attachment_digest)) AND o.attested_by=v_actor AND o.attested_authority='successor_runtime') THEN
    RETURN jsonb_build_object('ok',false,'code','provider_observation_not_attested');
  END IF;
  SELECT count(*) INTO v_operation_count FROM public.pdc_authenticated_email_operation_lines
   WHERE source_hash=lower(btrim(p_source_hash)) AND vehicle_id=p_vehicle_id;
  IF v_operation_count<1 OR NOT EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_action_receipts a WHERE a.source_receipt_id=p_source_receipt_id AND a.vehicle_id=p_vehicle_id AND a.action_type='operation_add') THEN
    RETURN jsonb_build_object('ok',false,'code','typed_operation_evidence_missing');
  END IF;
  SELECT count(*) INTO v_booking_count FROM public.workshop_bookings b WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL;
  IF v_booking_count<>0 THEN RETURN jsonb_build_object('ok',false,'code','active_booking_detected'); END IF;
  v_before:=to_jsonb(v_vehicle);
  IF v_vehicle.job_card_number IS NULL THEN
    UPDATE public.vehicles SET job_card_number=upper(btrim(p_job_card_number)),version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
     WHERE id=p_vehicle_id RETURNING * INTO v_vehicle;
  END IF;
  v_after:=to_jsonb(v_vehicle);
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
   VALUES('update'::public.audit_action,'vehicles',p_vehicle_id,p_vehicle_id,v_actor,v_email,v_before,v_after,jsonb_build_object(
     'source','pdc_email_ai_v2_job_card_parity_correction_20260902','source_receipt_id',p_source_receipt_id,
     'source_hash',lower(btrim(p_source_hash)),'source_uid',btrim(p_source_uid),'attachment_digest',lower(btrim(p_attachment_digest)),
     'job_card_number',upper(btrim(p_job_card_number)),'operation_count',v_operation_count,'booking_count',v_booking_count));
  v_response:=jsonb_build_object('ok',true,'code',case when v_before->>'job_card_number' IS NULL THEN 'job_card_parity_corrected' ELSE 'job_card_already_correct' END,
    'disposition',case when v_before->>'job_card_number' IS NULL THEN 'APPLIED_AND_VERIFIED' ELSE 'ALREADY_CORRECT' END,
    'correction_id',v_correction_id,'source_receipt_id',p_source_receipt_id,'vehicle_id',p_vehicle_id,
    'stock_number',v_vehicle.stock_number,'vin',v_vehicle.vin,'job_card_number',v_vehicle.job_card_number,
    'vehicle_version',v_vehicle.version,'operation_count',v_operation_count,'active_booking_count',v_booking_count,
    'booking_created',false,'completion_created',false,'location_scheduled',false,'production_writes',false,
    'mailbox_contacted',false,'outbound_email',false,'action_rpc_invoked',false);
  INSERT INTO public.pdc_email_ai_v2_job_card_parity_corrections_20260902(
    correction_id,source_receipt_id,vehicle_id,source_hash,source_uid,attachment_digest,stock_number,vin,job_card_number,request_hash,response,corrected_by)
   VALUES(v_correction_id,p_source_receipt_id,p_vehicle_id,lower(btrim(p_source_hash)),btrim(p_source_uid),lower(btrim(p_attachment_digest)),
     public.normalize_vehicle_stock_number(p_stock_number),public.normalize_vehicle_vin(p_vin),upper(btrim(p_job_card_number)),v_request_hash,v_response,v_actor);
  RETURN v_response;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO v_existing FROM public.pdc_email_ai_v2_job_card_parity_corrections_20260902 WHERE source_receipt_id=p_source_receipt_id;
  IF FOUND AND v_existing.request_hash=v_request_hash THEN RETURN v_existing.response||jsonb_build_object('correction_replay',true); END IF;
  RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict');
END $jobcard$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text) TO authenticated;

CREATE FUNCTION public.reconcile_pdc_email_ai_v2_job_card_parity_20260902(
  p_source_receipt_id uuid, p_vehicle_id uuid, p_source_hash text, p_source_uid text,
  p_attachment_digest text, p_stock_number text, p_vin text, p_job_card_number text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions AS $$
  SELECT public.apply_pdc_email_ai_v2_job_card_source_bound_20260902($1,$2,$3,$4,$5,$6,$7,$8)
$$;
REVOKE ALL ON FUNCTION public.reconcile_pdc_email_ai_v2_job_card_parity_20260902(uuid,uuid,text,text,text,text,text,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.reconcile_pdc_email_ai_v2_job_card_parity_20260902(uuid,uuid,text,text,text,text,text,text) TO authenticated;

DO $repair$
DECLARE d text; before_hash text; after_hash text; old text; new text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure), encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,before_hash;
  old:=$old$'note_append','location_set','rft_transfer','rft_collect')$old$;
  new:=$new$'note_append','location_set','job_card_set','rft_transfer','rft_collect')$new$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902264000_VALIDATOR_ACTION_ANCHOR_FAILED' USING errcode='55000'; END IF;
  d:=replace(d,old,new);
  old:=$old$  ELSIF p_item->>'action_type'='parts_eta_set' THEN$old$;
  new:=$new$  ELSIF p_item->>'action_type'='job_card_set' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['attachment_digest','job_card_number','source_uid','stock_number','vin']::text[]
       OR p->>'attachment_digest' !~ '^[a-f0-9]{64}$' OR p->>'job_card_number' !~ '^(J|JC)[0-9]{6,12}$'
       OR nullif(btrim(p->>'source_uid'),'') IS NULL OR p->>'stock_number' !~ '^[A-Z0-9][A-Z0-9-]{3,79}$'
       OR (p->>'vin' IS NOT NULL AND p->>'vin' !~ '^[A-HJ-NPR-Z0-9]{17}$') THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='parts_eta_set' THEN$new$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902264000_VALIDATOR_JOB_CARD_ANCHOR_FAILED' USING errcode='55000'; END IF;
  d:=replace(d,old,new); EXECUTE d;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;

  SELECT pg_get_functiondef('public.pdc_email_ai_successor_action_readback_parity_20260901(text,jsonb,jsonb,jsonb)'::regprocedure) INTO d;
  old:=$old$  WHEN 'operation_add' THEN$old$;
  new:=$jobparity$  WHEN 'job_card_set' THEN p_readback->'vehicle'->>'job_card_number'=upper(p_payload->>'job_card_number') AND p_readback->'vehicle'->>'stock_number'=p_payload->>'stock_number'
  WHEN 'operation_add' THEN$jobparity$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902264000_PARITY_JOB_CARD_ANCHOR_FAILED' USING errcode='55000'; END IF;
  EXECUTE replace(d,old,new);

  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure) INTO d;
  old:=$old$      ELSIF action_type='operation_add' THEN$old$;
  new:=$jobexecutor$      ELSIF action_type='job_card_set' THEN
        canonical_rpc:='public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)';
        result:=public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(source_id,vehicle.id,source_hash,item->'payload'->>'source_uid',item->'payload'->>'attachment_digest',item->'payload'->>'stock_number',item->'payload'->>'vin',item->'payload'->>'job_card_number');
      ELSIF action_type='operation_add' THEN$jobexecutor$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902264000_EXECUTOR_JOB_CARD_ANCHOR_FAILED' USING errcode='55000'; END IF;
  d:=replace(d,old,new); EXECUTE d;

  INSERT INTO public.pdc_email_ai_v2_job_card_parity_correction_history_20260902(
    event_key,predecessor_head,successor_head,predecessor_hashes,successor_hashes,contract,
    production_writes,mailbox_contacted,outbound_email,action_rpc_invoked)
  VALUES(encode(extensions.digest(convert_to('pdc-staging-20260902264000-job-card-parity-correction|forward','UTF8'),'sha256'),'hex'),
    '20260902263200','20260902264000',jsonb_build_object('v2_validator',before_hash),jsonb_build_object('v2_validator',after_hash),
    'An exact attachment-scoped Job Card is a typed source-bound action. The canonical writer locks the matched active vehicle, requires the exact intake/receipt/attachment/provider observation/Stock/VIN evidence, refuses protected or conflicting Job Cards, updates only the canonical vehicle atomically, records immutable correction/audit evidence, and replays idempotently. No operation duplication, booking, completion, location, mailbox, outbound or Production write is permitted.',false,false,false,false);
END $repair$;

DO $post$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure) INTO d;
  IF (SELECT count(*) FROM public.pdc_email_ai_v2_job_card_parity_correction_history_20260902)<>1
     OR position('job_card_set' IN d)=0
     OR position('apply_pdc_email_ai_v2_job_card_source_bound_20260902' IN (SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure)))=0
     OR position('job_card_set' IN (SELECT pg_get_functiondef('public.pdc_email_ai_successor_action_readback_parity_20260901(text,jsonb,jsonb,jsonb)'::regprocedure)))=0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_20260902264000_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260902264000','pdc_email_ai_v2_job_card_parity_correction_20260902',ARRAY[
  'Add source-bound typed job_card_set action with exact attachment digest, source UID, Stock and VIN identity; no-JC evidence remains non-dispatch review',
  'Persist an exact Job Card only when the matched active vehicle, intake, import receipt, attachment, provider observation and existing typed operation evidence all agree',
  'Fail closed for wrong Stock/VIN/source/attachment, conflicting or protected manual Job Cards, lifecycle-protected vehicles and active bookings',
  'Use one atomic canonical vehicle update with immutable correction/audit evidence and exact replay; preserve one operation, receipt and revision semantics',
  'Expose Job Card through canonical action readback and preserve no booking/completion/location, mailbox, outbound or Production effects'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
