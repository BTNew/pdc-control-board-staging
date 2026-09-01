-- STAGING ONLY 20260901220000: reconcile the deployed strict v2 executor
-- with the reviewed 1200/1700 source and ledger. The executor remains a fixed
-- canonical-RPC dispatcher; this repair only resolves the canonical source UID
-- server-side and preserves canonical result/error evidence per action.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901220000-successor-executor-reconciliation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE executor_hash text; operation_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO executor_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO operation_hash;
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901210000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901220000')
     OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)') IS NULL
     OR to_regclass('public.pdc_authenticated_email_import_receipts') IS NULL
     OR executor_hash<>'9eb7692704510f822d806cdee077f7463f9709564c22390036a9347a2b701622'
     OR operation_hash<>'5408637ec6932e8fb4290d917d760949ab2a00c8e0e9f70f35f60775a50dbbfe'
  THEN RAISE EXCEPTION 'PDC_20260901220000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_successor_executor_reconciliation_history_20260901(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind='strict_executor_reconciliation'),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260901210000'),
  successor_head text NOT NULL CHECK(successor_head='20260901220000'),
  predecessor_executor_sha256 text NOT NULL,
  successor_executor_sha256 text NOT NULL,
  predecessor_operation_update_sha256 text NOT NULL,
  successor_operation_update_sha256 text NOT NULL,
  source_binding_contract text NOT NULL,
  result_error_contract text NOT NULL, -- canonical_rpc and canonical JSON remain explicit evidence
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_successor_executor_reconciliation_history_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_executor_reconciliation_history_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_successor_executor_reconciliation_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $reconcile$
DECLARE
  definition text;
  before_hash text;
  after_hash text;
  operation_definition text;
  operation_before_hash text;
  operation_after_hash text;
  old_declaration text;
  new_declaration text;
  old_loop text;
  new_loop text;
  old_add text;
  old_update text;
  old_parity text;
  new_parity text;
  old_rejected text;
  new_rejected text;
  old_exception text;
  new_exception text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;

  old_declaration := $old$ source_hash text:=lower(p_plan->>'source_digest'); v_source_hash_key text:=source_hash; evidence_hash text:=lower(p_plan->>'evidence_digest');$old$;
  new_declaration := $new$ source_hash text:=lower(p_plan->>'source_digest'); v_source_hash_key text:=source_hash; v_source_uid text; v_sqlstate text; v_message text; v_detail text; v_hint text; evidence_hash text:=lower(p_plan->>'evidence_digest');$new$;
  old_loop := $old$  FOR item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP$old$;
  new_loop := $new$  SELECT r.source_uid INTO v_source_uid
  FROM public.pdc_authenticated_email_import_receipts r
  WHERE r.source_hash=v_source_hash_key
  ORDER BY r.created_at,r.receipt_id
  LIMIT 1;
  FOR item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP$new$;
  old_add := $old$public.import_pdc_authenticated_email_operations_with_hours(source_hash,item->'payload'->>'source_uid',$old$;
  old_update := $old$public.pdc_email_ai_successor_operation_update_20260901(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,source_hash,item->'payload'->>'source_uid',$old$;
  old_parity := $old$readback:=public.pdc_email_ai_successor_action_readback_20260901(vehicle.id,action_type,item->'payload',result); verification:=jsonb_build_object('checked',true,'parity',public.pdc_email_ai_successor_action_readback_parity_20260901(action_type,item->'payload',result,readback),'field_scope',action_type); after_state:=readback; actual:=result;$old$;
  new_parity := $new$readback:=public.pdc_email_ai_successor_action_readback_20260901(vehicle.id,action_type,item->'payload',result); verification:=jsonb_build_object('checked',true,'parity',public.pdc_email_ai_successor_action_readback_parity_20260901(action_type,item->'payload',result,readback),'field_scope',action_type,'source_uid_binding',case when action_type in('operation_add','operation_update') then 'pdc_authenticated_email_import_receipts.source_uid' else 'not_applicable' end,'canonical_result',result); after_state:=readback; actual:=result;$new$;
  old_rejected := $old$      ELSE disposition:='FAILED_QUEUED_RETRY'; reason:=coalesce(result->>'error',result->>'code','canonical_action_rejected'); END IF;$old$;
  new_rejected := $new$      ELSE actual:=result; disposition:='FAILED_QUEUED_RETRY'; reason:=coalesce(result->>'error',result->>'code','canonical_action_rejected'); END IF;$new$;
  old_exception := $old$      EXCEPTION WHEN others THEN
        disposition:='FAILED_QUEUED_RETRY'; reason:='canonical_'||action_type||'_failed'; result:=jsonb_build_object('ok',false,'code',reason);
      END;$old$;
  new_exception := $new$      EXCEPTION WHEN others THEN
        GET STACKED DIAGNOSTICS v_sqlstate=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT,v_detail=PG_EXCEPTION_DETAIL,v_hint=PG_EXCEPTION_HINT;
        disposition:='FAILED_QUEUED_RETRY';
        reason:=coalesce(nullif(v_message,''),'canonical_'||action_type||'_failed');
        result:=jsonb_build_object('ok',false,'code','canonical_action_exception','sqlstate',v_sqlstate,'canonical_error',v_message,'detail',nullif(v_detail,''),'hint',nullif(v_hint,''));
        actual:=result;
      END;$new$;

  IF position(old_declaration IN definition)=0 OR position(old_loop IN definition)=0
     OR position(old_add IN definition)=0 OR position(old_update IN definition)=0
     OR position(old_parity IN definition)=0 OR position(old_rejected IN definition)=0
     OR position(old_exception IN definition)=0
  THEN RAISE EXCEPTION 'PDC_20260901220000_EXECUTOR_SOURCE_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old_declaration,new_declaration);
  definition:=replace(definition,old_loop,new_loop);
  definition:=replace(definition,old_add,'public.import_pdc_authenticated_email_operations_with_hours(source_hash,v_source_uid,');
  definition:=replace(definition,old_update,'public.pdc_email_ai_successor_operation_update_20260901(vehicle.id,(item->''expected_state''->>''vehicle_version'')::integer,source_hash,v_source_uid,');
  definition:=replace(definition,old_parity,new_parity);
  definition:=replace(definition,old_rejected,new_rejected);
  definition:=replace(definition,old_exception,new_exception);
  EXECUTE definition;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;

  SELECT pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO operation_definition,operation_before_hash;
  IF position('v_source_hash_key text:=source_hash;' IN operation_definition)=0
     OR position('SELECT to_jsonb(v) INTO before_state' IN operation_definition)=0
     OR position('pdc_email_ai_successor_operation_update_20260901(vehicle_id' IN operation_definition)=0
  THEN RAISE EXCEPTION 'PDC_20260901220000_OPERATION_SOURCE_ANCHOR_FAILED' USING errcode='55000'; END IF;
  operation_definition:=replace(operation_definition,
    'v_source_hash_key text:=source_hash;',
    'v_source_hash_key text:=source_hash; v_source_uid text;');
  operation_definition:=replace(operation_definition,
    '  SELECT to_jsonb(v) INTO before_state',
    '  SELECT r.source_uid INTO v_source_uid FROM public.pdc_authenticated_email_import_receipts r WHERE r.source_hash=v_source_hash_key ORDER BY r.created_at,r.receipt_id LIMIT 1;'||chr(10)||'  SELECT to_jsonb(v) INTO before_state');
  operation_definition:=replace(operation_definition,
    'source_hash,item->''payload''->>''source_uid'',item->''payload''->>''operation_no''',
    'source_hash,v_source_uid,item->''payload''->>''operation_no''');
  EXECUTE operation_definition;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO operation_after_hash;

  INSERT INTO public.pdc_email_ai_successor_executor_reconciliation_history_20260901(
    event_key,event_kind,predecessor_head,successor_head,predecessor_executor_sha256,
    successor_executor_sha256,predecessor_operation_update_sha256,successor_operation_update_sha256,
    source_binding_contract,result_error_contract,production_writes,mailbox_contacted,
    outbound_email,action_rpc_invoked)
  VALUES(
    encode(extensions.digest(convert_to('pdc-staging-20260901220000-executor-reconciliation|forward','UTF8'),'sha256'),'hex'),
    'strict_executor_reconciliation','20260901210000','20260901220000',before_hash,after_hash,
    operation_before_hash,operation_after_hash,
    'For operation_add and operation_update, resolve the exact pdc_authenticated_email_import_receipts.source_uid by validated source_hash; never derive message-id:attachment-digest and never trust the typed payload UID',
    'Retain the canonical RPC name, canonical returned JSON, SQLSTATE, message, detail and hint in per-action actual/verification evidence while preserving FAILED_QUEUED_RETRY isolation',
    false,false,false,false);
END $reconcile$;

DO $post$
DECLARE definition text; operation_definition text; executor_hash text; operation_hash text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,executor_hash;
  SELECT pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO operation_definition,operation_hash;
  IF (SELECT count(*) FROM public.pdc_email_ai_successor_executor_reconciliation_history_20260901)<>1
     OR position('SELECT r.source_uid INTO v_source_uid' IN definition)=0
     OR position('pdc_authenticated_email_import_receipts' IN definition)=0
     OR position('import_pdc_authenticated_email_operations_with_hours(source_hash,v_source_uid' IN definition)=0
     OR position('pdc_email_ai_successor_operation_update_20260901(vehicle.id,(item->''expected_state''->>''vehicle_version'')::integer,source_hash,v_source_uid' IN definition)=0
     OR position('GET STACKED DIAGNOSTICS' IN definition)=0
     OR position('RETURNED_SQLSTATE' IN definition)=0
     OR position('canonical_error' IN definition)=0
     OR position('SELECT r.source_uid INTO v_source_uid' IN operation_definition)=0
     OR position('source_hash,v_source_uid,item->''payload''->>''operation_no''' IN operation_definition)=0
     OR executor_hash='9eb7692704510f822d806cdee077f7463f9709564c22390036a9347a2b701622'
     OR operation_hash='5408637ec6932e8fb4290d917d760949ab2a00c8e0e9f70f35f60775a50dbbfe'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260901220000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260901220000','pdc_email_ai_successor_executor_reconciliation_20260901',ARRAY[
  'Reconcile the deployed strict executor with the reviewed 20260901120000 and deferred-FK 20260901170000 ledger head',
  'Resolve canonical operation add/update source_uid from the validated pdc_authenticated_email_import_receipts source_hash binding; no message-id:attachment derivation',
  'Preserve fixed canonical RPC dispatch, per-action isolation, OP/hour/zero-hour semantics, replay identity, field-level readback and no booking/completion',
  'Return canonical JSON and captured SQLSTATE/message/detail/hint evidence instead of legacy 0200-style empty actuals',
  'Record exact predecessor/successor function hashes and explicit zero Production/mailbox/outbound/action-RPC proof'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
