-- PDC-14 partial replay-fixture cleanup identifier repair. STAGING ONLY.
-- Approved STAGING project ref: cdsmnqxtyyoeoznmbidd.
BEGIN;
DO $guard$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-14-location-replay-fixture-cleanup-20260904011400',0));
  LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260904011300'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260904011300' AND name='pdc14_location_replay_partial_fixture_cleanup')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904011400')
  THEN RAISE EXCEPTION 'PDC_14_EXACT_STAGING_011300_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.cleanup_pdc14_location_replay_fixture_20260904()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth AS $cleanup$
DECLARE
  target constant uuid:='67594974-0000-5000-8000-000000000014'::uuid;
  v public.vehicles%rowtype;
  actor uuid;
  expected_actor_email constant text:='functional.pdc.staging@example.com';
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
  actor:=v.created_by;
  IF v.permanent_vehicle_id<>'HERMES-PDC14-PERM-67594974'
     OR v.stock_number<>'HERMES-PDC14-67594974'
     OR v.job_card_number<>'HERMES-JC-PDC14'
     OR v.source_system<>'hermes_test'
     OR v.source_batch_id<>'t_67594974'
     OR v.source_record_id<>'location-replay'
     OR v.source_payload->>'bounded_fixture'<>'t_67594974'
     OR coalesce((v.source_payload->>'email_sent')::boolean,true)
     OR actor IS NULL
     OR (SELECT count(*) FROM auth.users u WHERE u.id=actor AND lower(u.email)=expected_actor_email)<>1
     OR EXISTS(
       SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 h
       WHERE h.vehicle_id=target AND (h.actor_id IS DISTINCT FROM actor OR lower(coalesce(h.actor_email,''))<>expected_actor_email)
     )
  THEN RAISE EXCEPTION 'PDC14_LOCATION_REPLAY_FIXTURE_PROVENANCE_MISMATCH' USING errcode='55000'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.event_id),'[]'::jsonb)
    INTO lifecycle FROM public.pdc_vehicle_lifecycle_history_events_82000 h WHERE h.vehicle_id=target;
  SELECT count(*) INTO movement_total FROM public.vehicle_movements WHERE vehicle_id=target;
  SELECT count(*) INTO audit_total FROM public.audit_events WHERE vehicle_id=target AND action='move';
  SELECT count(*) INTO receipt_total FROM public.pdc_vehicle_location_receipts_20260904 WHERE vehicle_id=target;
  INSERT INTO public.pdc14_location_replay_fixture_cleanup_history_20260904(
    vehicle_id,actor_id,actor_email,before_vehicle,lifecycle_history,movement_count,audit_count,
    retained_replay_receipt_count,cleanup_reason,production_writes)
  VALUES(target,actor,expected_actor_email,to_jsonb(v),lifecycle,movement_total,audit_total,receipt_total,
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
  RETURN jsonb_build_object('ok',true,'code','bounded_fixture_cleaned','vehicle_id',target,
    'lifecycle_events_archived',jsonb_array_length(lifecycle),'movements_removed',movement_total,
    'audits_removed',audit_total,'retained_replay_receipts',receipt_total,'production_writes',false);
END $cleanup$;
REVOKE ALL ON FUNCTION public.cleanup_pdc14_location_replay_fixture_20260904() FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904011400','pdc14_location_replay_partial_cleanup_identifier_repair',ARRAY[
  'Guard exact STAGING predecessor and Production absence',
  'Disambiguate the expected temporary actor email from cleanup-history columns',
  'Preserve exact-provenance partial fixture cleanup and retained replay receipts'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
