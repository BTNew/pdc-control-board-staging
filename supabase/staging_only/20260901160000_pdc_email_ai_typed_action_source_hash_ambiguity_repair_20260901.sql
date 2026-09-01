-- STAGING ONLY 20260901160000: repair the deployed v2 source-binding
-- variable ambiguity without changing action semantics or safety boundaries.
-- The source_hash column is explicitly qualified; the PL/pgSQL key is given a
-- distinct name in each affected wrapper so PostgreSQL cannot resolve it as a
-- column reference.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901160000-source-hash-ambiguity-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE h_execute text; h_non_dispatch text; h_operation text;
BEGIN
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO h_execute;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO h_non_dispatch;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO h_operation;
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901140000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901160000')
     OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)') IS NULL
     OR to_regclass('public.pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901') IS NOT NULL
     OR h_execute<>'14fa8e912732e8d21f3bf56d00b953a9a3f9f60753d3348a6bebf86449ac465c'
     OR h_non_dispatch<>'3df2bff20c151221f782e969a88604e833fd182dff228b536ff600ed55f2daf6'
     OR h_operation<>'d84cca9a4e0fb7868aadc4657eedc6e870e52e8cb4b13740ccd7bf1a428b3ba6'
  THEN RAISE EXCEPTION 'PDC_20260901160000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;

  IF position('source_hash text:=lower(p_plan->>''source_digest'');' IN pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure))=0
     OR position('lower(coalesce(i.source_hash,''''))=source_hash' IN pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure))=0
     OR position('source_hash text:=lower(p_plan->>''source_digest'');' IN pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure))=0
     OR position('lower(coalesce(i.source_hash,''''))=source_hash' IN pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure))=0
     OR position('source_hash text:=lower(p_plan->>''source_digest'');' IN pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure))=0
     OR position('lower(coalesce(i.source_hash,''''))=source_hash' IN pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure))=0
  THEN RAISE EXCEPTION 'PDC_20260901160000_SOURCE_BINDING_ANCHOR_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind='source_hash_ambiguity_repair'),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260901140000'),
  successor_head text NOT NULL CHECK(successor_head='20260901160000'),
  predecessor_function_sha256 jsonb NOT NULL,
  successor_function_sha256 jsonb NOT NULL,
  repair_contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_typed_action_source_hash_ambiguity_history_immutable_20260901()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_20260901160000_HISTORY_IMMUTABLE' USING errcode='55000'; END
$$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_typed_action_source_hash_ambiguity_history_immutable_20260901() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_email_ai_typed_action_source_hash_ambiguity_history_immutable_20260901
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_typed_action_source_hash_ambiguity_history_immutable_20260901();

DO $repair$
DECLARE d text; before_sha text; after_sha text; old_decl text; new_decl text; old_pred text; new_pred text;
BEGIN
  old_decl:=$old$source_hash text:=lower(p_plan->>'source_digest');$old$;
  new_decl:=$new$source_hash text:=lower(p_plan->>'source_digest'); v_source_hash_key text:=source_hash;$new$;
  old_pred:=$old$lower(coalesce(i.source_hash,''))=source_hash$old$;
  new_pred:=$new$lower(coalesce(i.source_hash,''))=v_source_hash_key$new$;

  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure), encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,before_sha;
  IF position(old_decl IN d)=0 OR position(old_pred IN d)=0 THEN RAISE EXCEPTION 'PDC_20260901160000_EXECUTOR_SOURCE_DRIFT' USING errcode='55000'; END IF;
  d:=replace(replace(d,old_decl,new_decl),old_pred,new_pred); EXECUTE d;

  SELECT pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure), encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,before_sha;
  IF position(old_decl IN d)=0 OR position(old_pred IN d)=0 THEN RAISE EXCEPTION 'PDC_20260901160000_NON_DISPATCH_SOURCE_DRIFT' USING errcode='55000'; END IF;
  d:=replace(replace(d,old_decl,new_decl),old_pred,new_pred); EXECUTE d;

  SELECT pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure), encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,before_sha;
  IF position(old_decl IN d)=0 OR position(old_pred IN d)=0 THEN RAISE EXCEPTION 'PDC_20260901160000_OPERATION_SOURCE_DRIFT' USING errcode='55000'; END IF;
  d:=replace(replace(d,old_decl,new_decl),old_pred,new_pred); EXECUTE d;

  INSERT INTO public.pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901(
    event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,
    successor_function_sha256,repair_contract,production_writes,mailbox_contacted,
    outbound_email,action_rpc_invoked)
  VALUES(
    encode(extensions.digest(convert_to('pdc-staging-20260901160000-source-hash-ambiguity-repair|forward','UTF8'),'sha256'),'hex'),
    'source_hash_ambiguity_repair','20260901140000','20260901160000',
    jsonb_build_object(
      'execute','14fa8e912732e8d21f3bf56d00b953a9a3f9f60753d3348a6bebf86449ac465c',
      'non_dispatch','3df2bff20c151221f782e969a88604e833fd182dff228b536ff600ed55f2daf6',
      'operation_update','d84cca9a4e0fb7868aadc4657eedc6e870e52e8cb4b13740ccd7bf1a428b3ba6'),
    jsonb_build_object(
      'execute',encode(extensions.digest(convert_to((SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure)),'UTF8'),'sha256'),'hex'),
      'non_dispatch',encode(extensions.digest(convert_to((SELECT pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure)),'UTF8'),'sha256'),'hex'),
      'operation_update',encode(extensions.digest(convert_to((SELECT pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure)),'UTF8'),'sha256'),'hex')),
    'Rename only the PL/pgSQL source digest key used in the three deployed v2 source-binding predicates; preserve exact source/evidence binding, action semantics, receipts, RLS, ACL and all staging-only boundaries',
    false,false,false,false);
END $repair$;

DO $post$
DECLARE d text;
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901)<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901140000
  THEN RAISE EXCEPTION 'PDC_20260901160000_HISTORY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure) INTO d;
  IF position('lower(coalesce(i.source_hash,''''))=source_hash' IN d)>0 OR position('lower(coalesce(i.source_hash,''''))=v_source_hash_key' IN d)=0 THEN RAISE EXCEPTION 'PDC_20260901160000_EXECUTOR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure) INTO d;
  IF position('lower(coalesce(i.source_hash,''''))=source_hash' IN d)>0 OR position('lower(coalesce(i.source_hash,''''))=v_source_hash_key' IN d)=0 THEN RAISE EXCEPTION 'PDC_20260901160000_NON_DISPATCH_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)'::regprocedure) INTO d;
  IF position('lower(coalesce(i.source_hash,''''))=source_hash' IN d)>0 OR position('lower(coalesce(i.source_hash,''''))=v_source_hash_key' IN d)=0 THEN RAISE EXCEPTION 'PDC_20260901160000_OPERATION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  IF to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_20260901160000_PRODUCTION_SENTINEL_PRESENT' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260901160000','pdc_email_ai_typed_action_source_hash_ambiguity_repair_20260901',ARRAY[
  'Repair the deployed strict v2 executor source-binding ambiguity by using a distinct PL/pgSQL variable name beside the qualified source_hash column',
  'Apply the same narrow repair to non-dispatch and operation-update source-bound wrappers because all three share the predicate shape',
  'Record immutable predecessor/successor hashes and explicit zero action-RPC proof in a forced-RLS history table',
  'Preserve strict authenticated-only ACL, append-only receipts, evidence binding, per-action isolation, mailbox/outbound and Production boundaries'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
