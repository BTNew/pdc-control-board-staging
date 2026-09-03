-- STAGING-only exact alignment of the Python and installed v2 action allowlists.
-- Numeric operation provenance remains exactly ('job_card','ai_estimate','business_rule_default').
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903121000-v2-contract-alignment',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_sha text;
BEGIN
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_sha;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260903120000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903120000' AND name='pdc_email_ai_current_hours_fixture_generation_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903121000')
     OR v_sha<>'68c06ccced246a3eb63f3b460f372da3b7421dd728705863544c447dc129f8c0'
  THEN RAISE EXCEPTION 'PDC_20260903121000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_contract_alignments_20260903(
  alignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260903120000'),
  successor_head text NOT NULL CHECK(successor_head='20260903121000'),
  predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256~'^[a-f0-9]{64}$'),
  successor_function_sha256 text NOT NULL CHECK(successor_function_sha256~'^[a-f0-9]{64}$'),
  operation_update_first_apply_disabled boolean NOT NULL CHECK(operation_update_first_apply_disabled),
  operation_number_fully_anchored boolean NOT NULL CHECK(operation_number_fully_anchored),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_contract_alignments_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_contract_alignments_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_v2_contract_alignments_20260903 FROM public,anon,authenticated,service_role;

DO $repair$
DECLARE
  v_definition text;
  v_before text;
  v_after text;
  v_old_actions text:=$old$'activate_vehicle','operation_add','operation_update','parts_eta_set'$old$;
  v_new_actions text:=$new$'activate_vehicle','operation_add','parts_eta_set'$new$;
  v_old_branch text:=$old$p_item->>'action_type' IN('operation_add','operation_update')$old$;
  v_new_branch text:=$new$p_item->>'action_type'='operation_add'$new$;
  v_old_regex text:=$old$p->>'operation_no' !~ '^(OP[1-9][0-9]{0,2}|PD[0-9]{3}-[A-F0-9]{8})'$old$;
  v_new_regex text:=$new$p->>'operation_no' !~ '^(OP[1-9][0-9]{0,2}|PD[0-9]{3}-[A-F0-9]{8})$'$new$;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure) INTO v_definition;
  v_before:=encode(extensions.digest(convert_to(v_definition,'UTF8'),'sha256'),'hex');
  IF (length(v_definition)-length(replace(v_definition,v_old_actions,'')))/length(v_old_actions)<>1
     OR (length(v_definition)-length(replace(v_definition,v_old_branch,'')))/length(v_old_branch)<>1
     OR (length(v_definition)-length(replace(v_definition,v_old_regex,'')))/length(v_old_regex)<>1
  THEN RAISE EXCEPTION 'PDC_20260903121000_VALIDATOR_ANCHOR_FAILED' USING errcode='55000'; END IF;
  v_definition:=replace(v_definition,v_old_actions,v_new_actions);
  v_definition:=replace(v_definition,v_old_branch,v_new_branch);
  v_definition:=replace(v_definition,v_old_regex,v_new_regex);
  EXECUTE v_definition;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_after;
  INSERT INTO public.pdc_email_ai_v2_contract_alignments_20260903(
    event_key,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,
    operation_update_first_apply_disabled,operation_number_fully_anchored,production_writes,mailbox_contacted,outbound_email
  ) VALUES(
    encode(extensions.digest(convert_to('pdc-staging|20260903121000|v2-contract-alignment','UTF8'),'sha256'),'hex'),
    '20260903120000','20260903121000',v_before,v_after,true,true,false,false,false
  );
END $repair$;

DO $post$
DECLARE v_definition text:=pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure);
BEGIN
  IF position('''operation_update''' IN v_definition)>0
     OR position('^(OP[1-9][0-9]{0,2}|PD[0-9]{3}-[A-F0-9]{8})$' IN v_definition)=0
     OR position('(''job_card'',''ai_estimate'',''business_rule_default'')' IN v_definition)=0
     OR (SELECT count(*) FROM public.pdc_email_ai_v2_contract_alignments_20260903)<>1
     OR has_table_privilege('authenticated','public.pdc_email_ai_v2_contract_alignments_20260903','select')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260903121000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260903121000','pdc_email_ai_v2_contract_alignment_20260903',ARRAY[
    'Align the installed first-apply action allowlist with the Python v2 contract by fail-closing operation_update until provenance-preserving execution exists',
    'Fully anchor operation identifiers to OP1..OP999 or deterministic PD identifiers',
    'Retain exact job_card, ai_estimate and legacy business_rule_default numeric-hours provenance',
    'Production, mailbox and outbound paths remain untouched and disabled'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
