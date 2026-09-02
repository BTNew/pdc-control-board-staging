-- STAGING ONLY 20260902263100: align the scoped activation source with the
-- existing canonical activation enum while retaining successor-only authority.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260902263100-scoped-navision-activation-source-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260902263000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260902263100')
     OR to_regprocedure('public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)') IS NULL
     OR to_regclass('public.pdc_email_ai_v2_scoped_navision_activation_history_20260902') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260902263100_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history_20260902(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260902263000'),
  successor_head text NOT NULL CHECK(successor_head='20260902263100'),
  predecessor_hash text NOT NULL,
  successor_hash text NOT NULL,
  repair_contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history_20260902 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history_20260902 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history_20260902 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history_immutable_20260902()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_20260902263100_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_scoped_navision_activation_source_repair_history_immutable_20260902
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history_20260902
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history_immutable_20260902();

DO $repair$
DECLARE d text; old text; new text; before_hash text; after_hash text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO d,before_hash;
  old:=$old$v_backend.id,'successor_scoped_navision',v_backend.normalized_data->>'batch'$old$;
  new:=$new$v_backend.id,'approved_email_build',v_backend.normalized_data->>'batch'$new$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902263100_SOURCE_ANCHOR_FAILED' USING errcode='55000'; END IF;
  EXECUTE replace(d,old,new);
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;
  INSERT INTO public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history(
    event_key,predecessor_head,successor_head,predecessor_hash,successor_hash,repair_contract,
    production_writes,mailbox_contacted,outbound_email,action_rpc_invoked)
  VALUES(
    encode(extensions.digest(convert_to('pdc-staging-20260902263100-scoped-navision-activation-source-repair|forward','UTF8'),'sha256'),'hex'),
    '20260902263000','20260902263100',before_hash,after_hash,
    'Use the existing approved_email_build activation-source value while retaining the exact authenticated successor identity, active stage-writer, source hash/UID/sender enrollment, canonical trigger, replay receipt, audit and zero operation/work/Parts/booking/completion/status mutation contract.',
    false,false,false,false);
END $repair$;

DO $post$
DECLARE d text; acl_public boolean; acl_anon boolean; acl_service boolean;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)'::regprocedure) INTO d;
  SELECT has_function_privilege('public','public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)','execute'),
         has_function_privilege('anon','public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)','execute'),
         has_function_privilege('service_role','public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)','execute')
    INTO acl_public,acl_anon,acl_service;
  IF position('approved_email_build' IN d)=0 OR position('successor_scoped_navision' IN d)>0
     OR position('pdc_monitor_exact_sender_enrollments' IN d)=0
     OR position('pdc_monitor_stage_activation_writers' IN d)=0
     OR acl_public OR acl_anon OR acl_service
     OR (SELECT count(*) FROM public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history_20260902)<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260902263100_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260902263100','pdc_email_ai_v2_scoped_navision_activation_source_repair_20260902',ARRAY[
  'Repair the activation source value to the existing approved_email_build enum without changing successor-only authorization',
  'Preserve exact source-bound identity, replay, canonical trigger, audit and no operational work/Parts/booking/completion/status mutation',
  'Record immutable predecessor/successor function hash and zero Production/mailbox/outbound/action-RPC proof'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
