-- STAGING ONLY 397: canonical workshop booking fields must win snapshot projection.
--
-- The existing station/full snapshot contracts can carry stale allocation or
-- estimate fields after a later booking resize/cascade. This additive wrapper
-- keeps the snapshot shape and every non-booking field unchanged, but overlays
-- scheduling/live fields from workshop_bookings by immutable booking UUID.
-- It never writes booking, vehicle, audit, receipt or notification rows.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-397-canonical-workshop-booking-snapshot-authority',0));

DO $pre$
DECLARE
  v_head text;
BEGIN
  SELECT max(version) INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version ~ '^[0-9]{14}$';
  IF current_user <> 'postgres'
     OR session_user <> 'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR v_head IS DISTINCT FROM '20260826123000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260826123000') <> 1
     OR to_regclass('public.workshop_bookings') IS NULL
     OR to_regprocedure('public.get_workshop_snapshot(date,date)') IS NULL
     OR to_regprocedure('public.get_station_workshop_snapshot(text,date,date)') IS NULL
     OR to_regprocedure('public.workshop_planner_booking_dto(uuid)') IS NULL THEN
    RAISE EXCEPTION 'PDC_397_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
  END IF;
END $pre$;

CREATE FUNCTION public.workshop_overlay_canonical_booking_fields_397(p_snapshot jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $overlay$
DECLARE
  v_bookings jsonb;
BEGIN
  IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot->'bookings') IS DISTINCT FROM 'array' THEN
    RETURN p_snapshot;
  END IF;

  SELECT coalesce(jsonb_agg(
    CASE WHEN b.id IS NULL THEN item.booking ELSE item.booking||jsonb_build_object(
      'scheduled_start_at',b.scheduled_start_at,
      'scheduled_end_at',b.scheduled_end_at,
      'default_duration_minutes',b.default_duration_minutes,
      'status',b.status,
      'version',b.version,
      'actual_start_at',b.actual_start_at,
      'actual_end_at',b.actual_end_at,
      'stoppage_reason',b.stoppage_reason,
      'stoppage_started_at',b.stoppage_started_at,
      'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes
    ) END ORDER BY item.ordinality),'[]'::jsonb)
  INTO v_bookings
  FROM jsonb_array_elements(p_snapshot->'bookings') WITH ORDINALITY AS item(booking,ordinality)
  LEFT JOIN public.workshop_bookings b
    ON b.id=CASE
      WHEN coalesce(item.booking->>'booking_id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'booking_id')::uuid
      WHEN coalesce(item.booking->>'id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'id')::uuid
    END;

  RETURN jsonb_set(p_snapshot,'{bookings}',v_bookings,true);
END $overlay$;
REVOKE ALL ON FUNCTION public.workshop_overlay_canonical_booking_fields_397(jsonb)
  FROM public,anon,authenticated,service_role;

ALTER FUNCTION public.get_workshop_snapshot(date,date)
  RENAME TO get_workshop_snapshot_pre_397;
CREATE FUNCTION public.get_workshop_snapshot(
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $full_snapshot$
DECLARE
  v_snapshot jsonb;
BEGIN
  v_snapshot:=public.get_workshop_snapshot_pre_397(p_date_from,p_date_to);
  RETURN public.workshop_overlay_canonical_booking_fields_397(v_snapshot);
END $full_snapshot$;

ALTER FUNCTION public.get_station_workshop_snapshot(text,date,date)
  RENAME TO get_station_workshop_snapshot_pre_397;
CREATE FUNCTION public.get_station_workshop_snapshot(
  p_stage_code text,
  p_date_from date,
  p_date_to date
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $station_snapshot$
DECLARE
  v_snapshot jsonb;
BEGIN
  v_snapshot:=public.get_station_workshop_snapshot_pre_397(p_stage_code,p_date_from,p_date_to);
  RETURN public.workshop_overlay_canonical_booking_fields_397(v_snapshot);
END $station_snapshot$;

REVOKE ALL ON FUNCTION public.get_workshop_snapshot_pre_397(date,date)
  FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_station_workshop_snapshot_pre_397(text,date,date)
  FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_workshop_snapshot(date,date)
  FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_station_workshop_snapshot(text,date,date)
  FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_workshop_snapshot(date,date) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_station_workshop_snapshot(text,date,date)
  TO authenticated,service_role;

DO $post$
DECLARE
  v_full_definition text;
  v_station_definition text;
BEGIN
  SELECT pg_get_functiondef('public.get_workshop_snapshot(date,date)'::regprocedure)
    INTO v_full_definition;
  SELECT pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure)
    INTO v_station_definition;
  IF position('workshop_overlay_canonical_booking_fields_397' IN v_full_definition)=0
     OR position('workshop_overlay_canonical_booking_fields_397' IN v_station_definition)=0
     OR has_function_privilege('public','public.get_workshop_snapshot(date,date)','EXECUTE')
     OR has_function_privilege('anon','public.get_workshop_snapshot(date,date)','EXECUTE')
     OR has_function_privilege('authenticated','public.get_workshop_snapshot(date,date)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.get_workshop_snapshot(date,date)','EXECUTE')
     OR has_function_privilege('public','public.get_station_workshop_snapshot(text,date,date)','EXECUTE')
     OR has_function_privilege('anon','public.get_station_workshop_snapshot(text,date,date)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.get_station_workshop_snapshot(text,date,date)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.get_station_workshop_snapshot(text,date,date)','EXECUTE') THEN
    RAISE EXCEPTION 'PDC_397_SNAPSHOT_AUTHORITY_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826130000','397_canonical_workshop_booking_snapshot_authority',ARRAY[
  'station and full Workshop snapshots overlay canonical workshop_bookings fields by stable booking UUID',
  'scheduled allocation wins over stale operation estimates for chip geometry',
  'started, stoppage, actual and version truth remains canonical and active bookings are never moved',
  'existing snapshot shape, RLS/grants, audit, receipts, revisions and zero-notification mutation boundaries are preserved'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
