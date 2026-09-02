-- STAGING ONLY: enforce the current ETA + 7 day booking rule for IT vehicles.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903010000-workshop-eta-plus-seven',0));

DO $pre$
BEGIN
  IF current_user<>'postgres' OR session_user NOT IN('postgres','cli_login_postgres')
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR to_regprocedure('public.workshop_candidate_schedule_gate(uuid,text,timestamp with time zone)') IS NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260902274000' AND name='pdc_email_ai_v2_exact_success_replay_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903010000')
  THEN
    RAISE EXCEPTION 'PDC_20260903010000_EXACT_STAGING_PRESTATE_REQUIRED current=% session=% staging=% production=% gate=% head=% self=%',
      current_user,
      session_user,
      (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd'),
      to_regclass('public.pdc_production_environment_sentinel'),
      to_regprocedure('public.workshop_candidate_schedule_gate(uuid,text,timestamp with time zone)'),
      (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260902274000' AND name='pdc_email_ai_v2_exact_success_replay_20260903'),
      (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903010000')
      USING errcode='55000';
  END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.workshop_candidate_schedule_gate(
  p_vehicle_id uuid,
  p_stage_code text,
  p_scheduled_start_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $gate$
DECLARE
  v_stage_code text;
  v_candidate record;
  v_schedule_date date;
BEGIN
  v_stage_code:=public.workshop_canonical_stage_code(p_stage_code);
  SELECT e.* INTO v_candidate
  FROM public.workshop_station_eligibility(v_stage_code)e
  WHERE e.vehicle_id=p_vehicle_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'error','vehicle_not_eligible_for_station');
  END IF;
  IF coalesce(v_candidate.existing_booking,false) THEN
    RETURN jsonb_build_object('ok',false,'error','active_booking_exists');
  END IF;
  v_schedule_date:=(p_scheduled_start_at AT TIME ZONE 'Australia/Perth')::date;
  IF public.pdc_sublet_away_on_date(p_vehicle_id,v_schedule_date) THEN
    RETURN jsonb_build_object('ok',false,'error','sublet_away','sublet_date',v_schedule_date);
  END IF;
  IF v_candidate.current_location='IT' AND v_candidate.eta_to_kewdale IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','it_eta_missing');
  END IF;
  IF v_candidate.current_location='IT'
     AND v_schedule_date<v_candidate.eta_to_kewdale+7 THEN
    RETURN jsonb_build_object(
      'ok',false,
      'error','it_before_eta_plus_seven',
      'earliest_permitted_date',v_candidate.eta_to_kewdale+7
    );
  END IF;
  RETURN jsonb_build_object(
    'ok',true,
    'earliest_permitted_date',CASE WHEN v_candidate.current_location='IT' THEN v_candidate.eta_to_kewdale+7 ELSE NULL END
  );
END;
$gate$;
REVOKE ALL ON FUNCTION public.workshop_candidate_schedule_gate(uuid,text,timestamptz) FROM public,anon,authenticated,service_role;

DO $post$
BEGIN
  IF has_function_privilege('anon','public.workshop_candidate_schedule_gate(uuid,text,timestamp with time zone)','EXECUTE')
     OR has_function_privilege('authenticated','public.workshop_candidate_schedule_gate(uuid,text,timestamp with time zone)','EXECUTE')
     OR has_function_privilege('service_role','public.workshop_candidate_schedule_gate(uuid,text,timestamp with time zone)','EXECUTE')
     OR position('v_schedule_date<v_candidate.eta_to_kewdale+7' IN pg_get_functiondef('public.workshop_candidate_schedule_gate(uuid,text,timestamp with time zone)'::regprocedure))=0
  THEN
    RAISE EXCEPTION 'PDC_20260903010000_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260903010000','workshop_eta_plus_seven_authority_20260903',ARRAY[
  'Require exact STAGING sentinel, absent Production sentinel and current Email AI v2 applied head',
  'Reject IT workshop schedules before ETA plus seven calendar days and return the exact earliest permitted date',
  'Keep PMB/YH resource scheduling behavior unchanged and keep the internal scheduling gate non-callable by browser roles'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
