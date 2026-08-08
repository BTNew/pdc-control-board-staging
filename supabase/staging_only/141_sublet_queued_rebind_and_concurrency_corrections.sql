-- Staging-only correction for delayed Sublet release review findings.
-- Adds queued Workshop authority and vehicle-rebind protection over migration 140.
begin;

DO $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pdc_staging_environment_sentinel
    WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd'
  ) OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'Migration 141 is staging-only';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version='140' and name='sublet_return_calendar_and_workshop_availability'
  ) OR EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='141'
  ) THEN
    RAISE EXCEPTION 'Migration 141 predecessor/target guard failed';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.pdc_sublet_bookings s
    JOIN public.workshop_bookings b ON b.vehicle_id=s.vehicle_id
    WHERE s.booking_date IS NOT NULL
      AND b.deleted_at IS NULL
      AND b.status::text IN ('queued','planned','started','stoppage')
      AND daterange(s.booking_date,s.actual_return_date,'[)') && daterange(
        (b.scheduled_start_at AT TIME ZONE 'Australia/Perth')::date,
        ((b.scheduled_end_at-interval '1 microsecond') AT TIME ZONE 'Australia/Perth')::date+1,
        '[)'
      )
  ) THEN
    RAISE EXCEPTION 'Migration 141 found an existing active Workshop/Sublet overlap';
  END IF;
END;
$guard$;

CREATE OR REPLACE FUNCTION public.pdc_workshop_booking_sublet_away_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $guard$
DECLARE
  v_start_date date;
  v_end_date date;
BEGIN
  IF new.deleted_at IS NOT NULL OR new.status::text NOT IN ('queued','planned','started','stoppage') THEN
    RETURN new;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||new.vehicle_id::text,0));
  v_start_date:=(new.scheduled_start_at AT TIME ZONE 'Australia/Perth')::date;
  v_end_date:=((new.scheduled_end_at-interval '1 microsecond') AT TIME ZONE 'Australia/Perth')::date;
  IF EXISTS(
    SELECT 1 FROM generate_series(v_start_date,v_end_date,interval '1 day') d
    WHERE public.pdc_sublet_away_on_date(new.vehicle_id,d::date)
  ) THEN
    RAISE EXCEPTION '%',jsonb_build_object(
      'error','sublet_away','vehicle_id',new.vehicle_id,
      'scheduled_start_date',v_start_date,'scheduled_end_date',v_end_date
    )::text USING errcode='23514';
  END IF;
  RETURN new;
END;
$guard$;
REVOKE ALL ON FUNCTION public.pdc_workshop_booking_sublet_away_guard() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_sublet_booking_workshop_overlap_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $guard$
DECLARE
  v_first_vehicle text;
  v_second_vehicle text;
BEGIN
  IF new.booking_date IS NULL AND (new.expected_return_date IS NOT NULL OR new.actual_return_date IS NOT NULL) THEN
    RAISE EXCEPTION '%',jsonb_build_object('error','invalid_date_order','reason','booking_date_required','vehicle_id',new.vehicle_id)::text USING errcode='23514';
  END IF;
  IF new.expected_return_date IS NOT NULL AND new.expected_return_date<new.booking_date THEN
    RAISE EXCEPTION '%',jsonb_build_object('error','invalid_date_order','reason','expected_before_booking','vehicle_id',new.vehicle_id)::text USING errcode='23514';
  END IF;
  IF new.actual_return_date IS NOT NULL AND new.actual_return_date<new.booking_date THEN
    RAISE EXCEPTION '%',jsonb_build_object('error','invalid_date_order','reason','actual_before_booking','vehicle_id',new.vehicle_id)::text USING errcode='23514';
  END IF;

  IF TG_OP='UPDATE' AND old.vehicle_id IS DISTINCT FROM new.vehicle_id THEN
    v_first_vehicle:=least(old.vehicle_id::text,new.vehicle_id::text);
    v_second_vehicle:=greatest(old.vehicle_id::text,new.vehicle_id::text);
    PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||v_first_vehicle,0));
    PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||v_second_vehicle,0));
  ELSE
    PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||new.vehicle_id::text,0));
  END IF;

  IF new.booking_date IS NOT NULL AND EXISTS(
    SELECT 1
    FROM public.workshop_bookings b
    WHERE b.vehicle_id=new.vehicle_id
      AND b.deleted_at IS NULL
      AND b.status::text IN ('queued','planned','started','stoppage')
      AND daterange(new.booking_date,new.actual_return_date,'[)') && daterange(
        (b.scheduled_start_at AT TIME ZONE 'Australia/Perth')::date,
        ((b.scheduled_end_at-interval '1 microsecond') AT TIME ZONE 'Australia/Perth')::date+1,
        '[)'
      )
  ) THEN
    RAISE EXCEPTION '%',jsonb_build_object('error','workshop_booking_conflict','vehicle_id',new.vehicle_id)::text USING errcode='23514';
  END IF;
  RETURN new;
END;
$guard$;
REVOKE ALL ON FUNCTION public.pdc_sublet_booking_workshop_overlap_guard() FROM public,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS pdc_sublet_booking_workshop_overlap_guard ON public.pdc_sublet_bookings;
CREATE TRIGGER pdc_sublet_booking_workshop_overlap_guard
BEFORE INSERT OR UPDATE OF vehicle_id,booking_date,expected_return_date,actual_return_date
ON public.pdc_sublet_bookings FOR EACH ROW EXECUTE FUNCTION public.pdc_sublet_booking_workshop_overlap_guard();

-- The trigger is final authority. Keep the shared RPC's readable preflight aligned
-- by replacing its one historical active-status predicate from migration 140.
DO $rpc$
DECLARE
  v_definition text;
  v_corrected text;
BEGIN
  SELECT pg_get_functiondef('public.update_pdc_sublet_booking_field(uuid,bigint,text,text)'::regprocedure)
  INTO v_definition;
  v_corrected:=replace(
    v_definition,
    'b.status::text in (''planned'',''started'',''stoppage'')',
    'b.status::text in (''queued'',''planned'',''started'',''stoppage'')'
  );
  IF v_corrected=v_definition THEN
    RAISE EXCEPTION 'Migration 141 could not find the exact migration-140 RPC status predicate';
  END IF;
  EXECUTE v_corrected;
END;
$rpc$;

DO $postcondition$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.pdc_sublet_bookings s
    JOIN public.workshop_bookings b ON b.vehicle_id=s.vehicle_id
    WHERE s.booking_date IS NOT NULL
      AND b.deleted_at IS NULL
      AND b.status::text IN ('queued','planned','started','stoppage')
      AND daterange(s.booking_date,s.actual_return_date,'[)') && daterange(
        (b.scheduled_start_at AT TIME ZONE 'Australia/Perth')::date,
        ((b.scheduled_end_at-interval '1 microsecond') AT TIME ZONE 'Australia/Perth')::date+1,
        '[)'
      )
  ) THEN
    RAISE EXCEPTION 'Migration 141 overlap postcondition failed';
  END IF;
  IF pg_get_triggerdef((
    SELECT oid FROM pg_trigger
    WHERE tgrelid='public.pdc_sublet_bookings'::regclass
      AND tgname='pdc_sublet_booking_workshop_overlap_guard'
      AND NOT tgisinternal
  )) NOT ILIKE '%UPDATE OF vehicle_id, booking_date, expected_return_date, actual_return_date%' THEN
    RAISE EXCEPTION 'Migration 141 reverse trigger postcondition failed';
  END IF;
END;
$postcondition$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('141','sublet_queued_rebind_and_concurrency_corrections',ARRAY['review blockers corrected'])
ON CONFLICT(version) DO NOTHING;

COMMIT;
