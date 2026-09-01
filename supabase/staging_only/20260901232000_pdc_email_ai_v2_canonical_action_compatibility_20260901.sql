-- STAGING ONLY 20260901232000: repair canonical action compatibility defects
-- exposed by the first capability proof. Preserve strict source fail-closed
-- behavior; do not manufacture an operation receipt or change the S04 fixture.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901232000-v2-canonical-action-compatibility',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901231000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901232000')
     OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)') IS NULL
     OR to_regprocedure('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901232000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_canonical_action_compatibility_history_20260901(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260901231000'),
  successor_head text NOT NULL CHECK(successor_head='20260901232000'),
  predecessor_hashes jsonb NOT NULL,
  successor_hashes jsonb NOT NULL,
  repair_contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_canonical_action_compatibility_history_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_canonical_action_compatibility_history_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_canonical_action_compatibility_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_canonical_action_compatibility_history_immutable_20260901()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_20260901232000_COMPATIBILITY_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_canonical_action_compatibility_history_immutable_20260901
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_canonical_action_compatibility_history_20260901
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_canonical_action_compatibility_history_immutable_20260901();

DO $repair$
DECLARE
  definition text;
  before_hash text;
  after_hash text;
  before_hashes jsonb:='{}'::jsonb;
  after_hashes jsonb:='{}'::jsonb;
  old text;
  new text;
BEGIN
  SELECT pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;
  before_hashes:=before_hashes||jsonb_build_object('work_states',before_hash);
  old:=$old$jsonb_object_length(p_work_states)$old$;
  IF position(old IN definition)=0 THEN RAISE EXCEPTION 'PDC_20260901232000_WORK_STATES_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old,$new$(SELECT count(*) FROM jsonb_object_keys(p_work_states))$new$);
  EXECUTE definition;

  SELECT pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;
  before_hashes:=before_hashes||jsonb_build_object('timeline',before_hash);
  old:=$old$if not public.workshop_is_planner_operator() and not public.pdc_email_ai_v2_canonical_action_capability_20260902() then$old$;
  new:=$new$if not public.workshop_is_planner_operator() and not (
    current_setting('pdc.monitor.v2_canonical_action_capability_20260902',true) LIKE 'pdc-email-ai-v2|%'
    AND length(current_setting('pdc.monitor.v2_canonical_action_capability_20260902',true)) > length('pdc-email-ai-v2|')+10
    AND auth.uid() IS NOT NULL
    AND EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i WHERE i.auth_user_id=auth.uid() AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor' AND i.active AND i.revoked_at IS NULL)
    AND EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=auth.uid() AND w.active AND w.revoked_at IS NULL)
    AND NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid() AND r.active AND r.account_status='approved' AND r.role::text='administrator')
  ) then$new$;
  IF position(old IN definition)=0 THEN RAISE EXCEPTION 'PDC_20260901232000_TIMELINE_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old,new);
  EXECUTE definition;

  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;
  before_hashes:=before_hashes||jsonb_build_object('executor',before_hash);
  old:=$old$ELSIF action_type='operation_add' THEN canonical_rpc:='public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'; result:=public.import_pdc_authenticated_email_operations_with_hours(source_hash,v_source_uid,jsonb_build_array($old$;
  new:=$new$ELSIF action_type='operation_add' THEN canonical_rpc:='public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'; IF v_source_uid IS NULL THEN result:=jsonb_build_object('ok',false,'code','canonical_operation_source_receipt_not_found'); ELSE result:=public.import_pdc_authenticated_email_operations_with_hours(source_hash,v_source_uid,jsonb_build_array($new$;
  IF position(old IN definition)=0 THEN RAISE EXCEPTION 'PDC_20260901232000_OPERATION_ADD_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old,new);
  old:=$old$'estimated_hours_source','job_card')));$old$;
  new:=$new$'estimated_hours_source','job_card'))); END IF;$new$;
  IF position(old IN definition)=0 THEN RAISE EXCEPTION 'PDC_20260901232000_OPERATION_ADD_END_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old,new);
  after_hashes:=jsonb_build_object('work_states',encode(extensions.digest(convert_to(pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex'),'timeline',encode(extensions.digest(convert_to(pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex'),'executor',encode(extensions.digest(convert_to(definition,'UTF8'),'sha256'),'hex'));
  EXECUTE definition;
  INSERT INTO public.pdc_email_ai_v2_canonical_action_compatibility_history_20260901(event_key,predecessor_head,successor_head,predecessor_hashes,successor_hashes,repair_contract,production_writes,mailbox_contacted,outbound_email,action_rpc_invoked)
  VALUES(encode(extensions.digest(convert_to('pdc-staging-20260901232000-v2-canonical-action-compatibility|forward','UTF8'),'sha256'),'hex'),'20260901231000','20260901232000',before_hashes,after_hashes,'Replace unavailable jsonb_object_length with jsonb_object_keys count; let the v2 capability reach the timeline path with duplicated actor-bound checks; operation add returns an explicit source-receipt failure before canonical importer validation when no validated source_uid exists.',false,false,false,false);
END $repair$;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_ai_v2_canonical_action_compatibility_history_20260901)<>1
     OR position('jsonb_object_length' IN (SELECT pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure)))>0
     OR position('pdc.monitor.v2_canonical_action_capability_20260902' IN (SELECT pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure)))=0
     OR position('canonical_operation_source_receipt_not_found' IN (SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure)))=0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260901232000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901232000','pdc_email_ai_v2_canonical_action_compatibility_20260901',ARRAY[
 'Repair PostgreSQL jsonb_object_length incompatibility in the canonical work-state RPC without changing its state map or operator check',
 'Permit the exact actor-bound transaction-local capability through the canonical timeline path while retaining planner-operator authority for all other callers',
 'Fail closed with canonical_operation_source_receipt_not_found when operation add lacks a validated receipt-bound source UID instead of sending null into canonical importer validation',
 'Preserve immutable receipt/source binding, action isolation, idempotency, field-level readback and explicit zero Production/mailbox/outbound/action-RPC proof'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
