-- Undo r597 (F211). Restores the stored full-station total on the snapshot,
-- the old vehicle exclusion, and the old move pin. Does not rewrite booking rows.

SET LOCAL lock_timeout = '2s';
DO $g$
DECLARE def text; n int;
BEGIN
  def := pg_get_functiondef('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure);
  def := replace(def, 'and b.bay_id is not null and b.id is distinct from p_booking_id and b.bay_id is distinct from v_target_bay', 'and b.bay_id is distinct from v_target_bay');
  def := replace(def,
    'if v_block is null then null; end if; -- r597 (F211): a snapped start with no other bay booked for this vehicle is not a conflict',
    'if v_block is null then v_result:=jsonb_build_object(''ok'',false,''error'',''vehicle_overlap''); raise exception ''r576: cross-station overlap not pushed'' using errcode=''P0415''; end if;');
  EXECUTE def;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure) IS DISTINCT FROM '6a02115d30578e8eb3807a283b1d60ea' THEN
    RAISE EXCEPTION 'r597 undo: move body did not return to the r571 text';
  END IF;
  UPDATE pdc_ops.expected_function_md5
     SET prosrc_md5 = '6a02115d30578e8eb3807a283b1d60ea',
         note = 'r571 pin restored by the r597 undo',
         updated_at = now()
   WHERE signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r597 undo: move pin'; END IF;

  def := pg_get_functiondef('public.workshop_exclusion_conflict_571(uuid,uuid,timestamp with time zone,integer,text,integer,jsonb,boolean)'::regprocedure);
  def := replace(def, 'and b.bay_id is not null -- r597 (F211): a row with no bay is not a conflict, and the booking being moved is already excluded', 'and not (b.status=''queued'' and b.bay_id is null)');
  EXECUTE def;

  UPDATE pdc_ops.regression_checks
     SET check_sql = replace(check_sql,
       'md5(mv) = (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = ''public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'')',
       'md5(mv) = ''6a02115d30578e8eb3807a283b1d60ea''')
   WHERE check_name = 'hoist_place_after_592';
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'key460_drag_597' AND added_in = 'r597';
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_overlay_canonical_booking_fields_397(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $function$
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
      'default_duration_minutes',b.default_duration_minutes,'bus_calendar_version',b.bus_calendar_version,
      'capacity_base_minutes',coalesce(b.capacity_base_minutes,b.default_duration_minutes::numeric),
      'capacity_efficiency_percent',coalesce(b.capacity_efficiency_percent,100),
      'capacity_estimate_minutes',b.capacity_estimate_minutes,
      'fitter_progress',pdc_fitter_private.progress(b.id),
      'status',b.status,
      'version',b.version,
      'actual_start_at',b.actual_start_at,
      'actual_end_at',b.actual_end_at,
      'stoppage_reason',b.stoppage_reason,
      'stoppage_started_at',b.stoppage_started_at,
      'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes
    )||pdc_bus_private.team_payload(b.id) END ORDER BY item.ordinality),'[]'::jsonb)
  INTO v_bookings
  FROM jsonb_array_elements(p_snapshot->'bookings') WITH ORDINALITY AS item(booking,ordinality)
  LEFT JOIN public.workshop_bookings b
    ON b.id=CASE
      WHEN coalesce(item.booking->>'booking_id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'booking_id')::uuid
      WHEN coalesce(item.booking->>'id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'id')::uuid
    END;
  RETURN jsonb_set(p_snapshot,'{bookings}',v_bookings,true)||jsonb_build_object('planning_calendar',pdc_bus_private.planning_calendar());
END $function$;

ALTER TABLE public.workshop_bookings DROP CONSTRAINT workshop_bookings_active_vehicle_no_overlap;
ALTER TABLE public.workshop_bookings ADD CONSTRAINT workshop_bookings_active_vehicle_no_overlap
  EXCLUDE USING gist (vehicle_id WITH =, tstzrange(scheduled_start_at, scheduled_end_at, '[)'::text) WITH &&)
  WHERE (deleted_at IS NULL AND NOT legacy_ambiguity_quarantined
    AND status = ANY (ARRAY['queued'::public.workshop_booking_status, 'planned'::public.workshop_booking_status, 'started'::public.workshop_booking_status, 'stoppage'::public.workshop_booking_status])
    AND NOT (status = 'queued'::public.workshop_booking_status AND bay_id IS NULL));
