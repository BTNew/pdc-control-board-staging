-- STAGING ONLY 20260901230000: give the exact authenticated v2 stage-writer
-- a transaction-local canonical capability. Canonical operator/admin paths remain
-- unchanged; direct callers still fail closed and no role is promoted.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901230000-v2-canonical-action-capability',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901220000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901230000')
     OR to_regclass('public.pdc_email_ai_v2_canonical_action_capability_history_20260901') IS NOT NULL
     OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.update_pdc_parts_eta(uuid,integer,date)') IS NULL
     OR to_regprocedure('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)') IS NULL
     OR to_regprocedure('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('public.move_vehicle(uuid,integer,text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_operation_update_20260901(uuid,integer,text,text,text,text,text,numeric)') IS NULL
     OR to_regclass('public.pdc_email_ai_successor_runtime_identities') IS NULL
     OR to_regclass('public.pdc_monitor_stage_activation_writers') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901230000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- This helper is internal-only. The capability is valid only inside an
-- authenticated request for the exact active staging identity and writer row;
-- administrators are deliberately excluded from this least-authority branch.
CREATE FUNCTION public.pdc_email_ai_v2_canonical_action_capability_20260902()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public,auth
AS $capability$
SELECT current_setting('pdc_email_ai_v2_canonical_capability_20260902',true) LIKE 'pdc-email-ai-v2|%'
   AND length(current_setting('pdc_email_ai_v2_canonical_capability_20260902',true)) > length('pdc-email-ai-v2|')+10
   AND auth.role()='authenticated'
   AND auth.uid() IS NOT NULL
   AND EXISTS(
     SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i
     WHERE i.auth_user_id=auth.uid()
       AND i.environment='staging'
       AND i.identity_purpose='pdc_email_ai_transaction_successor'
       AND i.active AND i.revoked_at IS NULL
   )
   AND EXISTS(
     SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
     WHERE w.user_id=auth.uid() AND w.active AND w.revoked_at IS NULL
   )
   AND NOT EXISTS(
     SELECT 1 FROM public.pdc_user_roles r
     WHERE r.auth_user_id=auth.uid() AND r.active
       AND r.account_status='approved' AND r.role::text='administrator'
   )
$capability$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_canonical_action_capability_20260902() FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_email_ai_v2_canonical_action_capability_history_20260901(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260901220000'),
  successor_head text NOT NULL CHECK(successor_head='20260901230000'),
  predecessor_hashes jsonb NOT NULL,
  successor_hashes jsonb NOT NULL,
  capability_contract text NOT NULL,
  allowed_actions text[] NOT NULL CHECK(allowed_actions=ARRAY['parts_eta_set','parts_complete','required_work_set','note_append','location_set','operation_add','operation_update']::text[]),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_canonical_action_capability_history_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_canonical_action_capability_history_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_canonical_action_capability_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_canonical_action_capability_history_immutable_20260901()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RAISE EXCEPTION 'PDC_20260901230000_CAPABILITY_HISTORY_IMMUTABLE' USING errcode='55000';
END $$;
CREATE TRIGGER pdc_email_ai_v2_canonical_action_capability_history_immutable_20260901
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_canonical_action_capability_history_20260901
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_canonical_action_capability_history_immutable_20260901();

DO $reconcile$
DECLARE
  definition text;
  before_hash text;
  after_hash text;
  hashes_before jsonb;
  hashes_after jsonb;
  old text;
BEGIN
  -- Preserve the historical 693 capability while adding the v2 capability;
  -- ordinary operator/admin execution still reaches require_pdc_role.
  SELECT pg_get_functiondef('public.update_pdc_parts_eta(uuid,integer,date)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.update_pdc_parts_eta(uuid,integer,date)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;
  hashes_before:=jsonb_build_object('parts_eta',before_hash);
  old:=$old$IF public.current_pdc_user_role()::text='importer' AND current_setting('pdc_monitor_canonical_action',true)<>'pdc-email-ai-693' THEN RAISE EXCEPTION 'PDC_MONITOR_DIRECT_OPERATOR_RPC_DENIED' USING errcode='42501'; END IF; perform public.require_pdc_role('operator');$old$;
  IF position(old IN definition)=0 THEN RAISE EXCEPTION 'PDC_20260901230000_PARTS_ETA_GUARD_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old,$new$IF public.current_pdc_user_role()::text='importer' AND current_setting('pdc_monitor_canonical_action',true)<>'pdc-email-ai-693' AND NOT public.pdc_email_ai_v2_canonical_action_capability_20260902() THEN RAISE EXCEPTION 'PDC_MONITOR_DIRECT_OPERATOR_RPC_DENIED' USING errcode='42501'; END IF; IF current_setting('pdc_monitor_canonical_action',true)='pdc-email-ai-693' OR public.pdc_email_ai_v2_canonical_action_capability_20260902() THEN NULL; ELSE perform public.require_pdc_role('operator'); END IF;$new$);
  EXECUTE definition;

  SELECT pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;
  hashes_before:=hashes_before||jsonb_build_object('work_states',before_hash);
  old:=$old$PERFORM public.require_pdc_role('operator');$old$;
  IF position(old IN definition)=0 THEN RAISE EXCEPTION 'PDC_20260901230000_WORK_STATES_GUARD_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old,$new$IF NOT public.pdc_email_ai_v2_canonical_action_capability_20260902() THEN PERFORM public.require_pdc_role('operator'); END IF;$new$);
  EXECUTE definition;

  SELECT pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;
  hashes_before:=hashes_before||jsonb_build_object('timeline',before_hash);
  old:=$old$if not public.workshop_is_planner_operator() then$old$;
  IF position(old IN definition)=0 THEN RAISE EXCEPTION 'PDC_20260901230000_TIMELINE_GUARD_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old,$new$if not public.workshop_is_planner_operator() and not public.pdc_email_ai_v2_canonical_action_capability_20260902() then$new$);
  EXECUTE definition;

  SELECT pg_get_functiondef('public.move_vehicle(uuid,integer,text,text,text,text,text)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.move_vehicle(uuid,integer,text,text,text,text,text)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;
  hashes_before:=hashes_before||jsonb_build_object('location',before_hash);
  old:=$old$perform public.workshop_require_planner_operator();$old$;
  IF position(old IN definition)=0 THEN RAISE EXCEPTION 'PDC_20260901230000_LOCATION_GUARD_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old,$new$IF NOT public.pdc_email_ai_v2_canonical_action_capability_20260902() THEN perform public.workshop_require_planner_operator(); END IF;$new$);
  EXECUTE definition;

  SELECT jsonb_build_object(
    'parts_eta',encode(extensions.digest(convert_to(pg_get_functiondef('public.update_pdc_parts_eta(uuid,integer,date)'::regprocedure),'UTF8'),'sha256'),'hex'),
    'work_states',encode(extensions.digest(convert_to(pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex'),
    'timeline',encode(extensions.digest(convert_to(pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex'),
    'location',encode(extensions.digest(convert_to(pg_get_functiondef('public.move_vehicle(uuid,integer,text,text,text,text,text)'::regprocedure),'UTF8'),'sha256'),'hex')
  ) INTO hashes_after;

  INSERT INTO public.pdc_email_ai_v2_canonical_action_capability_history_20260901(
    event_key,predecessor_head,successor_head,predecessor_hashes,successor_hashes,
    capability_contract,allowed_actions,production_writes,mailbox_contacted,outbound_email,action_rpc_invoked)
  VALUES(
    encode(extensions.digest(convert_to('pdc-staging-20260901230000-v2-canonical-action-capability|forward','UTF8'),'sha256'),'hex'),
    '20260901220000','20260901230000',hashes_before,hashes_after,
    'Only the strict authenticated v2 executor may set the transaction-local action-bound capability; actor must be the active non-admin staging runtime identity and active stage-writer. Direct calls remain operator/admin-gated.',
    ARRAY['parts_eta_set','parts_complete','required_work_set','note_append','location_set','operation_add','operation_update']::text[],
    false,false,false,false);
END $reconcile$;

-- Operation add/update continue through the existing canonical
-- pdc_authenticated_email_import_operations_with_hours(source_hash,v_source_uid,...)
-- and pdc_email_ai_successor_operation_update_20260901(source_hash,v_source_uid,...)
-- source-receipt bindings; this migration changes only authority consumption.

-- Bind the capability to the exact v2 dispatch transaction. This is set only
-- after strict validation/source binding (source_hash/source_uid) and is reset before canonical result/error evidence and readback.
DO $executor$
DECLARE definition text; old_start text; new_start text; old_end text; new_end text; old_exception text; new_exception text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure) INTO definition;
  old_start:='    ELSE'||chr(10)||'      BEGIN'||chr(10)||'      IF action_type=''activate_vehicle'' THEN';
  new_start:='    ELSE'||chr(10)||'      PERFORM set_config(''pdc_email_ai_v2_canonical_action_capability_20260902'',''pdc-email-ai-v2|''||source_id::text||''|''||action_key,true);'||chr(10)||'      BEGIN'||chr(10)||'      IF action_type=''activate_vehicle'' THEN';
  old_end:='      END IF;'||chr(10)||'      IF coalesce((result->>''ok'')::boolean,action_type=''note_append'' OR action_type=''location_set'') THEN';
  new_end:='      END IF;'||chr(10)||'      PERFORM set_config(''pdc_email_ai_v2_canonical_action_capability_20260902'','''',true);'||chr(10)||'      IF coalesce((result->>''ok'')::boolean,action_type=''note_append'' OR action_type=''location_set'') THEN';
  old_exception:='      EXCEPTION WHEN others THEN'||chr(10)||'        GET STACKED DIAGNOSTICS';
  new_exception:='      EXCEPTION WHEN others THEN'||chr(10)||'        PERFORM set_config(''pdc_email_ai_v2_canonical_action_capability_20260902'','''',true);'||chr(10)||'        GET STACKED DIAGNOSTICS';
  IF position(old_start IN definition)=0 OR position(old_end IN definition)=0 OR position(old_exception IN definition)=0
  THEN RAISE EXCEPTION 'PDC_20260901230000_EXECUTOR_CAPABILITY_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old_start,new_start);
  definition:=replace(definition,old_end,new_end);
  definition:=replace(definition,old_exception,new_exception);
  EXECUTE definition;
END $executor$;

DO $post$
DECLARE d text; h text; capability text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure) INTO d;
  SELECT pg_get_functiondef('public.update_pdc_parts_eta(uuid,integer,date)'::regprocedure) INTO capability;
  IF (SELECT count(*) FROM public.pdc_email_ai_v2_canonical_action_capability_history_20260901)<>1
     OR position('pdc_email_ai_v2_canonical_action_capability_20260902' IN d)=0
     OR position('set_config(''pdc_email_ai_v2_canonical_action_capability_20260902'',''pdc-email-ai-v2|''||source_id::text||''|''||action_key,true)' IN d)=0
     OR position('set_config(''pdc_email_ai_v2_canonical_action_capability_20260902'','''',true)' IN d)=0
     OR position('pdc_email_ai_v2_canonical_action_capability_20260902()' IN capability)=0
     OR position('pdc_email_ai_v2_canonical_action_capability_20260902()' IN (SELECT pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure)))=0
     OR position('pdc_email_ai_v2_canonical_action_capability_20260902()' IN (SELECT pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure)))=0
     OR position('pdc_email_ai_v2_canonical_action_capability_20260902()' IN (SELECT pg_get_functiondef('public.move_vehicle(uuid,integer,text,text,text,text,text)'::regprocedure)))=0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260901230000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260901230000','pdc_email_ai_v2_canonical_action_capability_20260901',ARRAY[
  'Add one internal transaction-local capability for the exact authenticated v2 stage-writer; no operator/admin/service role promotion',
  'Allow only the approved Parts ETA, Parts Complete, required-work, note, location and operation action path to consume the capability',
  'Preserve ordinary operator/admin checks and direct caller denial; actor identity, active stage-writer, authenticated role and non-admin state are rechecked',
  'Preserve receipt-bound source UID, canonical result/error evidence, per-action isolation, idempotency and field-level readback',
  'Record immutable forced-RLS history with explicit zero production/mailbox/outbound/action-RPC proof'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
