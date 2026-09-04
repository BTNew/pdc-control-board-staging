-- PDC-14 bounded authenticated replay fixture cleanup. STAGING ONLY.
-- Approved STAGING project ref: cdsmnqxtyyoeoznmbidd.
BEGIN;
DO $guard$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-14-location-replay-fixture-cleanup-20260904011200',0));
  LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260904011100'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260904011100' AND name='pdc14_location_replay_runtime_schema_alignment')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904011200')
  THEN RAISE EXCEPTION 'PDC_14_EXACT_STAGING_011100_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc14_location_replay_fixture_cleanup_history_20260904(
  cleanup_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL CHECK(vehicle_id='67594974-0000-5000-8000-000000000014'::uuid),
  actor_id uuid,
  actor_email text NOT NULL CHECK(actor_email='functional.pdc.staging@example.com'),
  before_vehicle jsonb NOT NULL,
  lifecycle_history jsonb NOT NULL,
  movement_count integer NOT NULL CHECK(movement_count>=1),
  audit_count integer NOT NULL CHECK(audit_count>=1),
  retained_replay_receipt_count integer NOT NULL CHECK(retained_replay_receipt_count>=1),
  cleanup_reason text NOT NULL CHECK(cleanup_reason='bounded authenticated PDC-14 replay fixture; immutable replay receipts retained'),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc14_location_replay_fixture_cleanup_history_20260904 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc14_location_replay_fixture_cleanup_history_20260904 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc14_location_replay_fixture_cleanup_history_20260904 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc14_location_replay_fixture_cleanup_history_immutable_20260904()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $$ BEGIN RAISE EXCEPTION 'PDC14_LOCATION_REPLAY_FIXTURE_CLEANUP_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc14_location_replay_fixture_cleanup_history_immutable_20260904() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc14_location_replay_fixture_cleanup_history_immutable_20260904
BEFORE UPDATE OR DELETE ON public.pdc14_location_replay_fixture_cleanup_history_20260904
FOR EACH ROW EXECUTE FUNCTION public.pdc14_location_replay_fixture_cleanup_history_immutable_20260904();

CREATE FUNCTION public.cleanup_pdc14_location_replay_fixture_20260904()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth AS $cleanup$
DECLARE
  target constant uuid:='67594974-0000-5000-8000-000000000014'::uuid;
  v public.vehicles%rowtype;
  actor uuid;
  actor_email text;
  lifecycle jsonb;
  movement_total integer;
  audit_total integer;
  receipt_total integer;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC14_LOCATION_REPLAY_FIXTURE_CLEANUP_STAGING_POSTGRES_ONLY' USING errcode='42501'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc14-location-replay-fixture-67594974',0));
  SELECT * INTO v FROM public.vehicles WHERE id=target FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'code','already_clean','vehicle_id',target); END IF;
  IF v.permanent_vehicle_id<>'HERMES-PDC14-PERM-67594974'
     OR v.stock_number<>'HERMES-PDC14-67594974'
     OR v.job_card_number<>'HERMES-JC-PDC14'
     OR v.source_system<>'hermes_test'
     OR v.source_batch_id<>'t_67594974'
     OR v.source_record_id<>'location-replay'
     OR v.source_payload->>'bounded_fixture'<>'t_67594974'
     OR coalesce((v.source_payload->>'email_sent')::boolean,true)
  THEN RAISE EXCEPTION 'PDC14_LOCATION_REPLAY_FIXTURE_PROVENANCE_MISMATCH' USING errcode='55000'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.event_id),'[]'::jsonb),(array_agg(h.actor_id ORDER BY h.event_id))[1],(array_agg(lower(h.actor_email) ORDER BY h.event_id))[1]
    INTO lifecycle,actor,actor_email FROM public.pdc_vehicle_lifecycle_history_events_82000 h WHERE h.vehicle_id=target;
  SELECT count(*) INTO movement_total FROM public.vehicle_movements WHERE vehicle_id=target;
  SELECT count(*) INTO audit_total FROM public.audit_events WHERE vehicle_id=target AND action='move';
  SELECT count(*) INTO receipt_total FROM public.pdc_vehicle_location_receipts_20260904 WHERE vehicle_id=target;
  IF jsonb_array_length(lifecycle)<1 OR actor_email<>'functional.pdc.staging@example.com'
     OR movement_total<1 OR audit_total<1 OR receipt_total<1
  THEN RAISE EXCEPTION 'PDC14_LOCATION_REPLAY_FIXTURE_EVIDENCE_MISMATCH' USING errcode='55000'; END IF;

  INSERT INTO public.pdc14_location_replay_fixture_cleanup_history_20260904(
    vehicle_id,actor_id,actor_email,before_vehicle,lifecycle_history,movement_count,audit_count,
    retained_replay_receipt_count,cleanup_reason,production_writes)
  VALUES(target,actor,actor_email,to_jsonb(v),lifecycle,movement_total,audit_total,receipt_total,
    'bounded authenticated PDC-14 replay fixture; immutable replay receipts retained',false);

  LOCK TABLE public.pdc_vehicle_lifecycle_history_events_82000 IN ACCESS EXCLUSIVE MODE;
  ALTER TABLE public.pdc_vehicle_lifecycle_history_events_82000 DISABLE TRIGGER pdc_vehicle_lifecycle_history_events_82000_immutable;
  DELETE FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE vehicle_id=target;
  ALTER TABLE public.pdc_vehicle_lifecycle_history_events_82000 ENABLE TRIGGER pdc_vehicle_lifecycle_history_events_82000_immutable;
  DELETE FROM public.audit_events WHERE vehicle_id=target;
  DELETE FROM public.vehicle_movements WHERE vehicle_id=target;
  DELETE FROM public.vehicle_work_items WHERE vehicle_id=target;
  DELETE FROM public.vehicles WHERE id=target;
  IF EXISTS(SELECT 1 FROM public.vehicles WHERE id=target)
     OR EXISTS(SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE vehicle_id=target)
  THEN RAISE EXCEPTION 'PDC14_LOCATION_REPLAY_FIXTURE_CLEANUP_READBACK_FAILED' USING errcode='55000'; END IF;
  RETURN jsonb_build_object('ok',true,'code','bounded_fixture_cleaned','vehicle_id',target,'retained_replay_receipts',receipt_total,'production_writes',false);
END $cleanup$;
REVOKE ALL ON FUNCTION public.cleanup_pdc14_location_replay_fixture_20260904() FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904011200','pdc14_location_replay_fixture_cleanup',ARRAY[
  'Guard exact STAGING predecessor and Production absence',
  'Create forced-RLS immutable cleanup history for bounded authenticated replay evidence',
  'Create postgres-only exact-provenance fixture cleanup while retaining replay receipts',
  'Revoke all application-role execution'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
