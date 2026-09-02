-- STAGING ONLY 20260902263000: source-bound canonical activation for the
-- commissioned successor writer. This is the only branch allowed to create a
-- canonical vehicle/Board link from one authenticated current Navision Stock.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260902263000-scoped-navision-activation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]+$')<>20260902262000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260902263000')
     OR to_regprocedure('public.pdc_email_ai_v2_prepare_scoped_attachment_observation_20260902(jsonb)') IS NULL
     OR to_regprocedure('public.trigger_reconcile_navision_operational_record()') IS NULL
     OR to_regclass('public.navision_backend_audit') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260902263000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_hash text NOT NULL UNIQUE CHECK(source_hash~'^[a-f0-9]{64}$'),
  request_hash text NOT NULL CHECK(request_hash~'^[a-f0-9]{64}$'),
  source_uid text NOT NULL,
  sender_address text NOT NULL,
  backend_record_id uuid NOT NULL REFERENCES public.navision_backend_records(id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_scoped_navision_activation_receipts_immutable_20260902()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_20260902263000_ACTIVATION_RECEIPT_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_scoped_navision_activation_receipts_immutable_20260902
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_scoped_navision_activation_receipts_immutable_20260902();

CREATE TABLE public.pdc_email_ai_v2_scoped_navision_activation_history_20260902(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260902262000'),
  successor_head text NOT NULL CHECK(successor_head='20260902263000'),
  predecessor_hashes jsonb NOT NULL CHECK(jsonb_typeof(predecessor_hashes)='object'),
  successor_hashes jsonb NOT NULL CHECK(jsonb_typeof(successor_hashes)='object'),
  staging_sentinel text NOT NULL CHECK(staging_sentinel='cdsmnqxtyyoeoznmbidd'),
  activation_contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_scoped_navision_activation_history_20260902 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_scoped_navision_activation_history_20260902 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_scoped_navision_activation_history_20260902 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_scoped_navision_activation_history_immutable_20260902()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_20260902263000_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_scoped_navision_activation_history_immutable_20260902
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_scoped_navision_activation_history_20260902
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_scoped_navision_activation_history_immutable_20260902();

CREATE FUNCTION public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $activate$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_source text:=lower(btrim(coalesce(p_request->>'source_hash','')));
  v_evidence text:=lower(btrim(coalesce(p_request->>'evidence_hash','')));
  v_uid text:=btrim(coalesce(p_request->>'source_uid',''));
  v_sender text:=lower(btrim(coalesce(p_request->>'sender_address','')));
  v_stock text:=public.normalize_vehicle_stock_number(p_request->>'stock_number');
  v_auth jsonb:=coalesce(p_request->'authentication','null'::jsonb);
  v_source_received_at timestamptz;
  v_request_hash text;
  v_backend_ids uuid[]:='{}'::uuid[];
  v_backend public.navision_backend_records%rowtype;
  v_activation public.navision_board_activations%rowtype;
  v_receipt public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_vin text;
  v_location text;
  v_revision bigint;
  v_response jsonb;
BEGIN
  -- Authentication and exact successor identity are checked before any
  -- request-derived source or vehicle value is trusted.
  IF current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR auth.role()<>'authenticated' OR v_actor IS NULL OR v_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','runtime_identity_required');
  END IF;
  IF NOT EXISTS(
       SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i
       WHERE i.auth_user_id=v_actor AND i.normalized_email=v_email
         AND i.environment='staging'
         AND i.identity_purpose='pdc_email_ai_transaction_successor'
         AND i.active AND i.revoked_at IS NULL
     )
     OR EXISTS(
       SELECT 1 FROM public.pdc_user_roles r
       WHERE r.auth_user_id=v_actor AND r.active
         AND r.account_status='approved' AND r.role::text='administrator'
     )
     OR NOT EXISTS(
       SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
       WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL
     ) THEN
    RETURN jsonb_build_object('ok',false,'code','successor_stage_writer_denied');
  END IF;

  IF jsonb_typeof(p_request)<>'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_request) k) IS DISTINCT FROM
        ARRAY['attachments','authentication','evidence_hash','observations','provider_message_id','provider_thread_id','sender_address','source_hash','source_received_at','source_uid','stock_number','subject']::text[]
     OR v_source!~'^[a-f0-9]{64}$' OR v_evidence!~'^[a-f0-9]{64}$'
     OR v_uid!~'^[1-9][0-9]*:[1-9][0-9]*$'
     OR btrim(coalesce(p_request->>'provider_message_id',''))=''
     OR btrim(coalesce(p_request->>'provider_thread_id',''))=''
     OR v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
     OR jsonb_typeof(v_auth) IS DISTINCT FROM 'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_auth) k) IS DISTINCT FROM
        ARRAY['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     OR v_auth->>'sender_domain' IS DISTINCT FROM split_part(v_sender,'@',2)
     OR v_auth->'gmail_authentication_results' IS DISTINCT FROM 'true'::jsonb
     OR NOT(v_auth->'spf_aligned'='true'::jsonb OR v_auth->'dkim_aligned'='true'::jsonb OR v_auth->'dmarc_aligned'='true'::jsonb)
     OR length(btrim(coalesce(p_request->>'subject',''))) NOT BETWEEN 1 AND 300
     OR NOT public.is_real_vehicle_stock_number(v_stock)
     OR jsonb_typeof(p_request->'observations') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_request->'attachments') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_request->'attachments') NOT BETWEEN 1 AND 10 THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_activation_request');
  END IF;
  BEGIN
    v_source_received_at:=(p_request->>'source_received_at')::timestamptz;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_activation_request');
  END;
  IF v_source_received_at IS NULL
     OR v_source_received_at>clock_timestamp()+interval '5 minutes'
     OR v_source_received_at<clock_timestamp()-interval '120 days' THEN
    RETURN jsonb_build_object('ok',false,'code','evidence_expired');
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.pdc_monitor_exact_sender_enrollments e
    WHERE e.active AND e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','sender_not_enrolled');
  END IF;

  v_request_hash:=encode(extensions.digest(convert_to(p_request::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-email-ai-scoped-activation:'||v_source,0));
  PERFORM pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));

  SELECT coalesce(array_agg(r.id ORDER BY r.id),'{}'::uuid[]) INTO v_backend_ids
  FROM public.navision_backend_records r
  WHERE r.source_system='microsoft_navision' AND r.dealer_code IN('14450','37047')
    AND r.is_current AND r.record_status='current'
    AND public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
    AND public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
  IF cardinality(v_backend_ids)=0 THEN RETURN jsonb_build_object('ok',false,'code','backend_stock_not_found'); END IF;
  IF cardinality(v_backend_ids)<>1 THEN RETURN jsonb_build_object('ok',false,'code','backend_stock_ambiguous'); END IF;
  SELECT * INTO v_backend FROM public.navision_backend_records WHERE id=v_backend_ids[1] FOR UPDATE;
  SELECT * INTO v_receipt FROM public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902
  WHERE source_hash=v_source FOR UPDATE;
  IF FOUND THEN
    IF v_receipt.request_hash<>v_request_hash OR v_receipt.backend_record_id<>v_backend.id THEN
      RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict');
    END IF;
    RETURN v_receipt.response||jsonb_build_object('replay',true,'code','scoped_navision_activation_replayed');
  END IF;

  IF v_backend.canonical_vehicle_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','canonical_vehicle_identity_conflict');
  END IF;

  SELECT * INTO v_activation FROM public.navision_board_activations
  WHERE backend_record_id=v_backend.id FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','activation_identity_conflict');
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.navision_board_activations a
    WHERE a.backend_record_id<>v_backend.id
      AND public.normalize_vehicle_stock_number(a.activated_stock_number)=v_stock
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','activation_identity_conflict');
  END IF;

  -- Stock, VIN, source-record and active alias ownership must all be empty;
  -- trigger_reconcile_navision_operational_record is then the sole canonical
  -- vehicle construction path.
  v_vin:=CASE WHEN public.is_valid_vehicle_vin(v_backend.normalized_data->>'vin')
    THEN nullif(public.normalize_vehicle_vin(v_backend.normalized_data->>'vin'),'') ELSE NULL END;
  IF EXISTS(
       SELECT 1 FROM public.vehicles v
       WHERE v.stock_number_normalized=v_stock
          OR (v_vin IS NOT NULL AND v.vin_normalized=v_vin)
          OR v.source_record_id_normalized=public.normalize_vehicle_source_identifier(v_backend.id::text)
     )
     OR EXISTS(
       SELECT 1 FROM public.vehicle_aliases a
       WHERE a.active AND (
         (a.alias_type_normalized='stock_number' AND a.normalized_alias_value=v_stock)
         OR (v_vin IS NOT NULL AND a.alias_type_normalized='vin' AND a.normalized_alias_value=v_vin)
       )
     ) THEN
    RETURN jsonb_build_object('ok',false,'code','operational_identity_conflict');
  END IF;

  v_location:=public.navision_operational_location(v_backend.normalized_data);
  IF v_location='Completed' THEN
    RETURN jsonb_build_object('ok',false,'code','protected_backend_lifecycle');
  END IF;

  -- The existing canonical reconciliation trigger creates exactly one
  -- permanent vehicle and links this Board activation. No work, Parts,
  -- booking, completion or workflow-status DML is performed in this branch.
  INSERT INTO public.navision_board_activations(
    backend_record_id,activation_source,activated_stock_number,
    activated_by,activated_by_email,active
  ) VALUES(
    v_backend.id,'approved_email_build',v_backend.normalized_data->>'batch',
    v_actor,v_email,true
  ) RETURNING * INTO v_activation;

  SELECT * INTO v_backend FROM public.navision_backend_records WHERE id=v_backend.id FOR SHARE;
  SELECT * INTO v_activation FROM public.navision_board_activations
  WHERE backend_record_id=v_backend.id FOR SHARE;
  SELECT * INTO v_vehicle FROM public.vehicles
  WHERE id=v_activation.canonical_vehicle_id AND deleted_at IS NULL FOR SHARE;
  IF NOT FOUND OR v_activation.canonical_vehicle_id IS NULL
     OR NOT v_activation.active
     OR v_vehicle.lifecycle_state::text<>'active'
     OR NOT v_vehicle.visible_on_board
     OR public.normalize_vehicle_stock_number(v_vehicle.stock_number)<>v_stock
     OR v_backend.canonical_vehicle_id IS DISTINCT FROM v_vehicle.id THEN
    RAISE EXCEPTION 'PDC_20260902263000_ACTIVATION_READBACK_FAILED' USING errcode='55000';
  END IF;

  SELECT revision INTO v_revision FROM public.navision_backend_revision WHERE singleton;
  INSERT INTO public.navision_backend_audit(action,backend_record_id,revision,evidence,actor_id,actor_email)
  VALUES('board_activate',v_backend.id,v_revision,jsonb_build_object(
    'contract','pdc_email_ai_v2_scoped_navision_activation_20260902',
    'source_hash',v_source,'evidence_hash',v_evidence,'source_uid',v_uid,
    'sender_address',v_sender,'vehicle_id',v_vehicle.id,
    'activation_only',true,'work_mutated',false,'parts_mutated',false,
    'booking_created',false,'completion_created',false,'status_mutated',false,
    'predecessor_head','20260902262000','successor_head','20260902263000'
  ),v_actor,v_email);
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('insert','navision_board_activations',v_backend.id,v_vehicle.id,v_actor,v_email,NULL,to_jsonb(v_activation),jsonb_build_object(
    'source','pdc_email_ai_v2_scoped_navision_activation_20260902',
    'source_hash',v_source,'evidence_hash',v_evidence,'source_uid',v_uid,
    'activation_only',true,'work_mutated',false,'parts_mutated',false,
    'booking_created',false,'completion_created',false,'status_mutated',false
  ));

  v_response:=jsonb_build_object('ok',true,'code','scoped_navision_activation_prepared',
    'backend_record_id',v_backend.id,'vehicle_id',v_vehicle.id,
    'stock_number',v_stock,
    'current_location',v_vehicle.current_location,'visible_on_board',v_vehicle.visible_on_board,
    'activation_only',true,'canonical_vehicle_created',true,
    'work_mutated',false,'parts_mutated',false,'booking_created',false,
    'completion_created',false,'status_mutated',false,'production_writes',false,
    'mailbox_contacted',false,'outbound_email',false,'action_rpc_invoked',false);
  INSERT INTO public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902(
    source_hash,request_hash,source_uid,sender_address,backend_record_id,vehicle_id,actor_id,actor_email,response
  ) VALUES(v_source,v_request_hash,v_uid,v_sender,v_backend.id,v_vehicle.id,v_actor,v_email,v_response);
  RETURN v_response;
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict');
END $activate$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb) TO authenticated;

DO $prepare_repair$
DECLARE
  d text;
  before_hash text;
  after_hash text;
  old text;
  new text;
  hashes_before jsonb;
  hashes_after jsonb;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_v2_prepare_scoped_attachment_observation_20260902(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_v2_prepare_scoped_attachment_observation_20260902(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO d,before_hash;
  old:=$old$  SELECT * INTO v_activation FROM public.navision_board_activations a WHERE a.backend_record_id=v_backend.id AND a.active AND a.completed_at IS NULL FOR SHARE;
  IF NOT FOUND OR v_activation.canonical_vehicle_id IS NULL OR v_backend.canonical_vehicle_id IS DISTINCT FROM v_activation.canonical_vehicle_id THEN
    RETURN jsonb_build_object('ok',false,'code','active_canonical_link_required');
  END IF;$old$;
  new:=$new$  SELECT * INTO v_activation FROM public.navision_board_activations a WHERE a.backend_record_id=v_backend.id AND a.active AND a.completed_at IS NULL FOR SHARE;
  IF NOT FOUND OR v_activation.canonical_vehicle_id IS NULL OR v_backend.canonical_vehicle_id IS DISTINCT FROM v_activation.canonical_vehicle_id THEN
    v_response:=public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(p_request);
    IF NOT coalesce((v_response->>'ok')::boolean,false) THEN RETURN v_response; END IF;
    SELECT * INTO v_activation FROM public.navision_board_activations a WHERE a.backend_record_id=v_backend.id AND a.active AND a.completed_at IS NULL FOR SHARE;
  END IF;$new$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902263000_PREPARE_ACTIVATION_ANCHOR_FAILED' USING errcode='55000'; END IF;
  d:=replace(d,old,new);
  EXECUTE d;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_v2_prepare_scoped_attachment_observation_20260902(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;
  hashes_before:=jsonb_build_object('prepare_rpc',before_hash,'activation_helper',encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex'));
  hashes_after:=jsonb_build_object('prepare_rpc',after_hash,'activation_helper',encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex'));
  INSERT INTO public.pdc_email_ai_v2_scoped_navision_activation_history_20260902(
    event_key,predecessor_head,successor_head,predecessor_hashes,successor_hashes,staging_sentinel,activation_contract,
    production_writes,mailbox_contacted,outbound_email,action_rpc_invoked)
  VALUES(
    encode(extensions.digest(convert_to('pdc-staging-20260902263000-scoped-navision-activation|forward','UTF8'),'sha256'),'hex'),
    '20260902262000','20260902263000',hashes_before,hashes_after,'cdsmnqxtyyoeoznmbidd',
    'The exact authenticated active successor identity and active stage-writer may create one canonical vehicle and Navision Board activation only when one current Navision Stock row exists, the exact enrolled sender/source UID/hash is authenticated, and no stock/VIN/source/alias operational identity conflicts. Existing reconciliation remains the sole canonical construction path; no operation, work, Parts, booking, completion or workflow-status mutation is performed. Replay is source-hash/request-hash bound and all direct table access remains denied.',
    false,false,false,false);
END $prepare_repair$;

DO $post$
DECLARE d text; h text; acl_public boolean; acl_anon boolean; acl_service boolean;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_v2_prepare_scoped_attachment_observation_20260902(jsonb)'::regprocedure) INTO d;
  SELECT has_function_privilege('public','public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)','execute'),
         has_function_privilege('anon','public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)','execute'),
         has_function_privilege('service_role','public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)','execute')
    INTO acl_public,acl_anon,acl_service;
  IF (SELECT count(*) FROM public.pdc_email_ai_v2_scoped_navision_activation_history_20260902)<>1
     OR position('pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(p_request)' IN d)=0
     OR acl_public OR acl_anon OR acl_service
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260902263000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260902263000','pdc_email_ai_v2_scoped_navision_activation_20260902',ARRAY[
  'Add authenticated successor-writer-only source-bound canonical Navision activation for exactly one current Stock row with no operational identity conflict',
  'Use the existing canonical reconciliation trigger as the only vehicle/Board construction path and preserve canonical identity, Navision revision and audit',
  'Bind replay to exact source hash/request hash and preserve predecessor/successor function hashes in immutable forced-RLS history',
  'Perform no operation, work, Parts, booking, completion or workflow-status mutation and deny direct table/service-role access',
  'Keep the pdc_email_ai_v2_prepare_scoped_attachment_observation_20260902 source receipt path fail-closed until activation is read back'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
