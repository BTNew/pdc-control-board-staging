-- STAGING ONLY 20260901231000: repair the v2 transaction-local GUC name.
-- PostgreSQL custom settings require a dotted namespace; this append-only
-- correction preserves the exact capability contract and all prior receipts.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901231000-v2-canonical-action-guc-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901230000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901231000')
     OR to_regprocedure('public.pdc_email_ai_v2_canonical_action_capability_20260902()') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL
     OR to_regclass('public.pdc_email_ai_v2_canonical_action_capability_history_20260901') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901231000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_canonical_action_guc_repair_history_20260901(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260901230000'),
  successor_head text NOT NULL CHECK(successor_head='20260901231000'),
  predecessor_hashes jsonb NOT NULL,
  successor_hashes jsonb NOT NULL,
  repair_contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_canonical_action_guc_repair_history_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_canonical_action_guc_repair_history_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_canonical_action_guc_repair_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_canonical_action_guc_repair_history_immutable_20260901()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_20260901231000_GUC_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_canonical_action_guc_repair_history_immutable_20260901
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_canonical_action_guc_repair_history_20260901
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_canonical_action_guc_repair_history_immutable_20260901();

DO $repair$
DECLARE
  capability text;
  executor text;
  before_hashes jsonb;
  after_hashes jsonb;
  old_helper_name text:='pdc_email_ai_v2_canonical_capability_20260902';
  old_executor_name text:='pdc_email_ai_v2_canonical_action_capability_20260902';
  new_name text:='pdc.monitor.v2_canonical_action_capability_20260902';
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_v2_canonical_action_capability_20260902()'::regprocedure) INTO capability;
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure) INTO executor;
  before_hashes:=jsonb_build_object(
    'capability',encode(extensions.digest(convert_to(capability,'UTF8'),'sha256'),'hex'),
    'executor',encode(extensions.digest(convert_to(executor,'UTF8'),'sha256'),'hex'));
  IF position('current_setting('''||old_helper_name IN capability)=0 OR position('set_config('''||old_executor_name IN executor)=0
  THEN RAISE EXCEPTION 'PDC_20260901231000_GUC_NAME_ANCHOR_FAILED' USING errcode='55000'; END IF;
  capability:=replace(capability,'current_setting('''||old_helper_name||''',true)','current_setting('''||new_name||''',true)');
  executor:=replace(executor,'set_config('''||old_executor_name||''',','set_config('''||new_name||''',');
  EXECUTE capability;
  EXECUTE executor;
  SELECT jsonb_build_object(
    'capability',encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_v2_canonical_action_capability_20260902()'::regprocedure),'UTF8'),'sha256'),'hex'),
    'executor',encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')) INTO after_hashes;
  INSERT INTO public.pdc_email_ai_v2_canonical_action_guc_repair_history_20260901(
    event_key,predecessor_head,successor_head,predecessor_hashes,successor_hashes,
    repair_contract,production_writes,mailbox_contacted,outbound_email,action_rpc_invoked)
  VALUES(
    encode(extensions.digest(convert_to('pdc-staging-20260901231000-v2-canonical-action-guc-repair|forward','UTF8'),'sha256'),'hex'),
    '20260901230000','20260901231000',before_hashes,after_hashes,
    'Use dotted PostgreSQL custom-GUC namespace pdc.monitor.v2_canonical_action_capability_20260902; preserve transaction-local scope, exact source/action binding and actor-bound helper checks.',
    false,false,false,false);
END $repair$;

DO $post$
DECLARE capability text; executor text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_v2_canonical_action_capability_20260902()'::regprocedure) INTO capability;
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure) INTO executor;
  IF (SELECT count(*) FROM public.pdc_email_ai_v2_canonical_action_guc_repair_history_20260901)<>1
     OR position('pdc.monitor.v2_canonical_action_capability_20260902' IN capability)=0
     OR position('pdc.monitor.v2_canonical_action_capability_20260902' IN executor)=0
     OR position('current_setting(''pdc_email_ai_v2_canonical_capability_20260902' IN capability)>0
     OR position('set_config(''pdc_email_ai_v2_canonical_action_capability_20260902' IN executor)>0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260901231000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260901231000','pdc_email_ai_v2_canonical_action_guc_repair_20260901',ARRAY[
  'Repair the custom GUC name to the required dotted PostgreSQL namespace without changing the v2 capability contract',
  'Preserve the actor-bound active stage-writer/non-admin/authenticated checks and transaction-local action binding',
  'Preserve all prior receipts, source/action idempotency, per-action isolation, canonical result/error evidence and field-level readback',
  'Record immutable forced-RLS repair history and explicit zero Production/mailbox/outbound/action-RPC proof'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
