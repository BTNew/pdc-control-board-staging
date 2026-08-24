-- STAGING ONLY 366: name every synthetic wrapper argument for PostgREST RPC invocation.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-366-overnight-wrapper-argument-names',0));
LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;
DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825020000' AND name='365_overnight_synthetic_mutation_wrappers')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260825020000' AND version~'^[0-9]{14}$')
   OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_366_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_hermes_test_vehicle_edit_365(
 p_run_id text,p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid,p_pmb_key_tag text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365(p_run_id,p_vehicle_id,p_expected_version,NULL,NULL,p_idempotency_key,'vehicle_edit',jsonb_build_object('pmb_key_tag',p_pmb_key_tag)) $$;
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_set_work_states_365(
 p_run_id text,p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid,p_work_states jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365(p_run_id,p_vehicle_id,p_expected_version,NULL,NULL,p_idempotency_key,'work_states',jsonb_build_object('work_states',p_work_states)) $$;
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_lifecycle_365(
 p_run_id text,p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid,p_action text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim(p_action)) NOT IN('to_pmb','ready_qc','qc_to_rft','collect') THEN RAISE EXCEPTION 'PDC_365_LIFECYCLE_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365(p_run_id,p_vehicle_id,p_expected_version,NULL,NULL,p_idempotency_key,'lifecycle_'||lower(btrim(p_action)),'{}'::jsonb);
END $$;
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_parts_365(
 p_run_id text,p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid,p_action text,p_worst_eta date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim(p_action)) NOT IN('eta','ordered','complete') OR (lower(btrim(p_action))<>'eta' AND p_worst_eta IS NOT NULL) THEN RAISE EXCEPTION 'PDC_365_PARTS_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365(p_run_id,p_vehicle_id,p_expected_version,NULL,NULL,p_idempotency_key,'parts_'||lower(btrim(p_action)),
  CASE WHEN lower(btrim(p_action))='eta' THEN jsonb_build_object('worst_eta',p_worst_eta) ELSE '{}'::jsonb END);
END $$;
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_parts_stoppage_365(
 p_run_id text,p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid,p_action text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim(p_action)) NOT IN('stoppage','recover') OR (lower(btrim(p_action))='recover' AND p_reason IS NOT NULL) THEN RAISE EXCEPTION 'PDC_365_PARTS_STOPPAGE_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365(p_run_id,p_vehicle_id,p_expected_version,NULL,NULL,p_idempotency_key,'parts_'||lower(btrim(p_action)),
  CASE WHEN lower(btrim(p_action))='stoppage' THEN jsonb_build_object('reason',p_reason) ELSE '{}'::jsonb END);
END $$;
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_schedule_365(
 p_run_id text,p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid,p_stage_code text,p_bay_number integer,
 p_scheduled_start_at timestamptz,p_duration_minutes integer,p_technician_id uuid,p_override_reason text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365(p_run_id,p_vehicle_id,p_expected_version,NULL,NULL,p_idempotency_key,'workshop_schedule',jsonb_strip_nulls(jsonb_build_object(
  'stage_code',p_stage_code,'bay_number',p_bay_number,'scheduled_start_at',p_scheduled_start_at,'duration_minutes',p_duration_minutes,'technician_id',p_technician_id,'override_reason',p_override_reason))) $$;
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_booking_365(
 p_run_id text,p_vehicle_id uuid,p_expected_vehicle_version integer,p_booking_id uuid,p_expected_booking_version integer,
 p_idempotency_key uuid,p_action text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim(p_action)) NOT IN('move','start','stop','resume','complete') THEN RAISE EXCEPTION 'PDC_365_BOOKING_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365(p_run_id,p_vehicle_id,p_expected_vehicle_version,p_booking_id,p_expected_booking_version,
  p_idempotency_key,'workshop_'||lower(btrim(p_action)),coalesce(p_payload,'{}'::jsonb));
END $$;
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_sublet_365(
 p_run_id text,p_vehicle_id uuid,p_expected_vehicle_version integer,p_booking_id uuid,p_expected_booking_version integer,
 p_idempotency_key uuid,p_action text,p_provider_id uuid,p_out_date date,p_expected_return_date date,p_returned_at timestamptz,p_notes text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim(p_action)) NOT IN('create','update','return') THEN RAISE EXCEPTION 'PDC_365_SUBLET_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365(p_run_id,p_vehicle_id,p_expected_vehicle_version,p_booking_id,p_expected_booking_version,
  p_idempotency_key,'sublet_'||lower(btrim(p_action)),jsonb_strip_nulls(jsonb_build_object('provider_id',p_provider_id,'out_date',p_out_date,
   'expected_return_date',p_expected_return_date,'returned_at',p_returned_at,'notes',p_notes)));
END $$;

DO $post$
DECLARE v_missing integer;
BEGIN
 SELECT count(*) INTO v_missing FROM (VALUES
  ('pdc_hermes_test_vehicle_edit_365','p_run_id,p_vehicle_id,p_expected_version,p_idempotency_key,p_pmb_key_tag'),
  ('pdc_hermes_test_set_work_states_365','p_run_id,p_vehicle_id,p_expected_version,p_idempotency_key,p_work_states'),
  ('pdc_hermes_test_lifecycle_365','p_run_id,p_vehicle_id,p_expected_version,p_idempotency_key,p_action'),
  ('pdc_hermes_test_parts_365','p_run_id,p_vehicle_id,p_expected_version,p_idempotency_key,p_action,p_worst_eta'),
  ('pdc_hermes_test_parts_stoppage_365','p_run_id,p_vehicle_id,p_expected_version,p_idempotency_key,p_action,p_reason'),
  ('pdc_hermes_test_schedule_365','p_run_id,p_vehicle_id,p_expected_version,p_idempotency_key,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_technician_id,p_override_reason'),
  ('pdc_hermes_test_booking_365','p_run_id,p_vehicle_id,p_expected_vehicle_version,p_booking_id,p_expected_booking_version,p_idempotency_key,p_action,p_payload'),
  ('pdc_hermes_test_sublet_365','p_run_id,p_vehicle_id,p_expected_vehicle_version,p_booking_id,p_expected_booking_version,p_idempotency_key,p_action,p_provider_id,p_out_date,p_expected_return_date,p_returned_at,p_notes')
 ) expected(proname,argnames)
 WHERE NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname=expected.proname
   AND array_to_string(p.proargnames,',')=expected.argnames AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
   AND has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('public',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE'));
 IF v_missing<>0 THEN RAISE EXCEPTION 'PDC_366_ARGUMENT_OR_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825030000','366_overnight_wrapper_postgrest_argument_names',array[
 'Exact migration 365 head and staging containment',
 'Name all eight public synthetic façade arguments for PostgREST RPC invocation',
 'Preserve exact façade signatures, security-definer ownership, ACLs and action validation'
]);
NOTIFY pgrst,'reload schema';
DO $final$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_366_FINAL_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $final$;
COMMIT;
