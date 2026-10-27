-- r577 (F191) / sort 349. Go-live. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Renumbered at apply: r570 / F184 / sort 341 is the service archive. r572 / F186 / sort 342 is the card stack.
-- Table and function names stay _570. The new check is r577 / F191 / sort 349.
-- book_all_vehicle_stations keeps its r450 pin marker. target_end_469 and
-- overlap_chain_469 keep their r469 markers. Their prosrc md5s still move.
-- bus_whole_job_450 counts 15 r450 pins. cascade_insert_overlap_chain_469
-- counts 4 r469 pins. workshop_validate_booking stays release r548 so
-- unallocated_bay_rechain_548 still sees that marker. The capacity plan keeps
-- the bus text needle pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id.
-- Five other pins take release r577. The pin count stays 241.
--
-- Craig, 27 Oct 2026 11:00 AWST: a Bay Manager under Admin so a workshop
-- controller can set the work hours of each bay.
--
-- Release ledger when this file was written:
--   origin/main r569 (F183) / sort 340 is the live bay-job pause (#554).
--   r568 (F182) / sort 339 is the live Bus component split (#553).
--   r567 (F181) / sort 338 is the live parts stoppage note.
--   Open preview #557 still claims r567 / F181 / sort 341 (stale release, live sort).
--   Open previews #556 and #555 still say r566 / F180. #556 also says sort 340,
--   which r569 already took. #551 is the rolled-back Electrical hide.
--   This apply uses the free triple r577 / F191 / sort 349. Object names stay _570.
--
-- Today's hours, with no row in workshop_bay_work_hours_570:
--   Hoist, Fab, Fitting, Electrical, Tint, Tyres and Pit use the workshop
--   calendar (workshop_settings: 06:00–16:30, Monday–Friday, no breaks,
--   no closures, no overtime). Perth is UTC+8 and has no daylight saving.
--   Bus 4x4 uses pdc_bus_private.minute_available: Monday–Friday 06:00–15:00,
--   bays 8 and 9 finish at 14:00, minus the same break and closure lists and
--   pdc_bus_private.public_holiday_dates(). The clock passes a Bus bay id only
--   when the stage is BUS_4X4 and the vehicle is an active department 138 bus.
-- A bay with no override keeps that path. The patched functions return before
-- the old body only when workshop_bay_has_hours_570 is true.
--
-- Saving hours does not update workshop_bookings. The save returns bookings
-- on that bay whose start is closed or whose open minutes are shorter than
-- the booked duration. A later clock tick uses the new hours for that bay.
-- An unchanged stored window still passes workshop_validate_booking so the
-- tick does not fail on a booking that was already saved.
--
-- The clock reads the hours once per transaction into the local GUC
-- pdc.bay_hours_570 (one aggregate of a small table, then memory). The tick
-- body calls workshop_bay_has_hours_570 only. It does not name the hours table.
-- Pin count stays 241. Five pins take release r577. book_all stays r450,
-- the two cascade helpers stay r469, and workshop_validate_booking stays r548.
-- Their md5s move with the body. Department 135 is not edited.
-- Undo: supabase/rollbacks/20261027233000_r570_bay_manager_hours.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r577: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r577: staging only'; END IF;
 IF EXISTS (SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE project_ref='vjdtsswhroyguxyfjdkt') THEN RAISE EXCEPTION 'r577: production ref'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r577: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_job_pause_569' AND fault_id='F183' AND sort_order=340 AND added_in='r569') THEN RAISE EXCEPTION 'r577: r569 / F183 sort 340 is not the live check'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bus_component_split_568' AND fault_id='F182' AND sort_order=339 AND added_in='r568') THEN RAISE EXCEPTION 'r577: r568 / F182 sort 339 is not the live check'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_stoppage_manual_567' AND fault_id='F181' AND sort_order=338 AND added_in='r567') THEN RAISE EXCEPTION 'r577: r567 / F181 sort 338 is not the live check'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_whole_archive_570' AND fault_id='F184' AND sort_order=341 AND added_in='r570') THEN RAISE EXCEPTION 'r577: archive check is not live'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_card_stack_572' AND fault_id='F186' AND sort_order=342 AND added_in='r572') THEN RAISE EXCEPTION 'r577: card stack check is not live'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='slot_between_571' AND fault_id='F185' AND sort_order=343 AND added_in='r571') THEN RAISE EXCEPTION 'r577: slot between check is not live'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='hours_description_fits_573' AND fault_id='F187' AND sort_order=344 AND added_in='r573') THEN RAISE EXCEPTION 'r577: hours wording check is not live'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_dept_ack_book_574' AND fault_id='F188' AND sort_order=345 AND added_in='r574') THEN RAISE EXCEPTION 'r577: department book check is not live'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='active_key_unique_575' AND fault_id='F189' AND sort_order=346 AND added_in='r575') THEN RAISE EXCEPTION 'r577: active key check is not live'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='cross_station_drop_576' AND fault_id='F190' AND sort_order=347 AND added_in='r576') THEN RAISE EXCEPTION 'r577: cross station check is not live'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='electrical_bays_7_566' AND fault_id='F180' AND sort_order=348 AND added_in='r566') THEN RAISE EXCEPTION 'r577: electrical hide check is not live'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=349 OR fault_id='F191' OR check_name='bay_manager_hours_570' OR added_in='r577') THEN RAISE EXCEPTION 'r577: sort 349 or F191 is taken'; END IF;
 IF to_regclass('public.workshop_bay_work_hours_570') IS NOT NULL OR to_regprocedure('public.set_workshop_bay_hours_570(uuid,integer,jsonb,text)') IS NOT NULL THEN RAISE EXCEPTION 'r577: already applied'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '83a2c8d5ff85b5a295343e5f3ef66ded' THEN RAISE EXCEPTION 'r577: clock tick is not the r559 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.add_minutes(timestamptz,integer,uuid)')) IS DISTINCT FROM 'c43afa5c1312392aa5d3666a8aa7cf65' THEN RAISE EXCEPTION 'r577: bus add_minutes changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.minute_available(timestamptz,uuid)')) IS DISTINCT FROM 'ca85b70cf2728a523a6e8d4231a19b08' THEN RAISE EXCEPTION 'r577: bus minute_available changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.clock_next_minute(timestamptz,uuid)')) IS DISTINCT FROM '734b6fc0d468b8a8a9cee2b955f9b21b' THEN RAISE EXCEPTION 'r577: bus clock_next_minute changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.clock_minutes_between(timestamptz,timestamptz,uuid)')) IS DISTINCT FROM 'c1e4e6b69cd67aebcbce738fd1a68dc2' THEN RAISE EXCEPTION 'r577: bus clock_minutes_between changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bay_seq_private.end_at(timestamptz,integer,uuid)')) IS DISTINCT FROM '8067dd22688d7b93d90c9c03eabfbe7d' THEN RAISE EXCEPTION 'r577: end_at changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bay_seq_private.next_start(timestamptz,uuid)')) IS DISTINCT FROM '6d2cdc4cb26bb37794c6998b206f6e0c' THEN RAISE EXCEPTION 'r577: next_start changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.target_end_469(uuid,uuid,timestamptz,integer)')) IS DISTINCT FROM 'b7b98893bfc7a04b39330ca689f8f1b1' THEN RAISE EXCEPTION 'r577: target_end changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.overlap_chain_469(uuid[],timestamptz)')) IS DISTINCT FROM 'e3602ba6f9d5973deea4eef09f5077c0' THEN RAISE EXCEPTION 'r577: overlap_chain changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_capacity_plan(text,uuid,integer,timestamptz)')) IS DISTINCT FROM 'bc237d9f466c45a086c251ec8c3071a7' THEN RAISE EXCEPTION 'r577: capacity plan changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.book_all_vehicle_stations(uuid,integer)')) IS DISTINCT FROM '90fc0d4727d827db53c308ff9dfa8bcd' THEN RAISE EXCEPTION 'r577: book_all changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')) IS DISTINCT FROM 'ae08aa9b0dc99e7c93b1710efdcb5070' THEN RAISE EXCEPTION 'r577: validate changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_booking_effective_end_at(uuid)')) IS DISTINCT FROM '3cd30a49767b2b79fadc325d56cbca42' THEN RAISE EXCEPTION 'r577: effective end changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)')) IS DISTINCT FROM 'd5e0543537cafb026383c7338c8e2b82' THEN RAISE EXCEPTION 'r577: cascade move changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'eb25ab44d4d007d3b749bd7bc5e56abc' THEN RAISE EXCEPTION 'r577: department 135 clock changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_bus.add_minutes(timestamptz,integer,uuid)')) IS DISTINCT FROM '832bf8be742c16b86f937fa9579ee056' THEN RAISE EXCEPTION 'r577: department 135 bus add_minutes changed'; END IF;
END $g$;

CREATE TABLE public.workshop_bay_work_hours_570 (
  bay_id uuid PRIMARY KEY REFERENCES public.workshop_bays(id) ON DELETE CASCADE,
  hours jsonb NOT NULL,
  version integer NOT NULL DEFAULT 1 CHECK (version >= 1),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_by uuid,
  CHECK (jsonb_typeof(hours) = 'object')
);

ALTER TABLE public.workshop_bay_work_hours_570 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.workshop_bay_work_hours_570 FROM PUBLIC, anon, authenticated;

-- One aggregate per transaction. An empty string means the next read reloads.
CREATE FUNCTION public.workshop_bay_hours_blob_570()
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $blob570$
DECLARE raw text; bag jsonb;
BEGIN
  raw := current_setting('pdc.bay_hours_570', true);
  IF raw IS NOT NULL AND raw <> '' THEN
    RETURN raw::jsonb;
  END IF;
  SELECT coalesce(jsonb_object_agg(h.bay_id::text, h.hours), '{}'::jsonb) INTO bag
    FROM public.workshop_bay_work_hours_570 h;
  PERFORM set_config('pdc.bay_hours_570', bag::text, true);
  RETURN bag;
END
$blob570$;

CREATE FUNCTION public.workshop_bay_has_hours_570(p_bay_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $has570$
BEGIN
  IF p_bay_id IS NULL THEN RETURN false; END IF;
  RETURN public.workshop_bay_hours_blob_570() ? p_bay_id::text;
END
$has570$;

CREATE FUNCTION public.workshop_bay_dow_key_570(p_at timestamptz)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO pg_catalog
AS $dow570$
 SELECT (ARRAY['monday','tuesday','wednesday','thursday','friday','saturday','sunday'])[extract(isodow FROM (p_at AT TIME ZONE 'Australia/Perth'))::int];
$dow570$;

CREATE FUNCTION public.workshop_bay_date_closed_570(p_day date, p_bus boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $closed570$
DECLARE bag jsonb;
BEGIN
  IF p_day IS NULL THEN RETURN true; END IF;
  bag := coalesce(public.workshop_settings_bag_554()->'closures', '[]'::jsonb);
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(bag) c
    WHERE coalesce(c->>'date', c #>> '{}') = p_day::text
  ) THEN RETURN true; END IF;
  IF coalesce(p_bus, false) AND p_day = ANY(pdc_bus_private.public_holiday_dates()) THEN
    RETURN true;
  END IF;
  RETURN false;
END
$closed570$;

-- Open segments for one Perth date, in minutes from midnight. NULL when this bay has no override.
CREATE FUNCTION public.workshop_bay_segments_570(p_bay_id uuid, p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $seg570$
DECLARE
  spec jsonb;
  day_key text;
  day_spec jsonb;
  start_min int;
  finish_min int;
  windows jsonb := '[]'::jsonb;
  br jsonb;
  bstart int;
  bfinish int;
  next_windows jsonb;
  w jsonb;
  ws int;
  we int;
  stage text;
BEGIN
  IF p_bay_id IS NULL OR p_day IS NULL OR NOT public.workshop_bay_has_hours_570(p_bay_id) THEN
    RETURN NULL;
  END IF;
  spec := public.workshop_bay_hours_blob_570() -> p_bay_id::text;
  day_key := (ARRAY['monday','tuesday','wednesday','thursday','friday','saturday','sunday'])[extract(isodow FROM p_day)::int];
  day_spec := spec -> day_key;
  SELECT f.code INTO stage FROM public.workshop_bay_stage_554(p_bay_id) f;
  IF public.workshop_bay_date_closed_570(p_day, stage = 'BUS_4X4') THEN
    RETURN '[]'::jsonb;
  END IF;
  IF day_spec IS NULL OR coalesce((day_spec->>'off')::boolean, false) THEN
    RETURN '[]'::jsonb;
  END IF;
  start_min := split_part(day_spec->>'start', ':', 1)::int * 60 + split_part(day_spec->>'start', ':', 2)::int;
  finish_min := split_part(day_spec->>'finish', ':', 1)::int * 60 + split_part(day_spec->>'finish', ':', 2)::int;
  IF finish_min <= start_min THEN RETURN '[]'::jsonb; END IF;
  windows := jsonb_build_array(jsonb_build_object('s', start_min, 'e', finish_min));
  FOR br IN SELECT value FROM jsonb_array_elements(coalesce(day_spec->'breaks', '[]'::jsonb)) LOOP
    bstart := split_part(br->>'start', ':', 1)::int * 60 + split_part(br->>'start', ':', 2)::int;
    bfinish := split_part(coalesce(br->>'finish', br->>'end'), ':', 1)::int * 60 + split_part(coalesce(br->>'finish', br->>'end'), ':', 2)::int;
    next_windows := '[]'::jsonb;
    FOR w IN SELECT value FROM jsonb_array_elements(windows) LOOP
      ws := (w->>'s')::int; we := (w->>'e')::int;
      IF bfinish <= ws OR bstart >= we THEN
        next_windows := next_windows || jsonb_build_array(w);
      ELSE
        IF bstart > ws THEN next_windows := next_windows || jsonb_build_array(jsonb_build_object('s', ws, 'e', bstart)); END IF;
        IF bfinish < we THEN next_windows := next_windows || jsonb_build_array(jsonb_build_object('s', bfinish, 'e', we)); END IF;
      END IF;
    END LOOP;
    windows := next_windows;
  END LOOP;
  RETURN windows;
END
$seg570$;

CREATE FUNCTION public.workshop_bay_minute_open_570(p_at timestamptz, p_bay_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $open570$
DECLARE
  local_ts timestamp;
  segs jsonb;
  w jsonb;
  minute_num numeric;
BEGIN
  IF p_at IS NULL OR p_bay_id IS NULL OR NOT public.workshop_bay_has_hours_570(p_bay_id) THEN
    RETURN false;
  END IF;
  local_ts := p_at AT TIME ZONE 'Australia/Perth';
  segs := public.workshop_bay_segments_570(p_bay_id, local_ts::date);
  IF segs IS NULL OR jsonb_array_length(segs) = 0 THEN RETURN false; END IF;
  minute_num := extract(epoch FROM (local_ts - date_trunc('day', local_ts))) / 60.0;
  FOR w IN SELECT value FROM jsonb_array_elements(segs) LOOP
    IF minute_num >= (w->>'s')::numeric AND minute_num < (w->>'e')::numeric THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END
$open570$;

CREATE FUNCTION public.workshop_bay_next_minute_570(p_at timestamptz, p_bay_id uuid)
 RETURNS timestamptz
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $next570$
DECLARE
  t timestamptz;
  limit_at timestamptz;
  local_ts timestamp;
  day date;
  segs jsonb;
  w jsonb;
  m int;
  jump timestamptz;
  guard int := 0;
BEGIN
  IF p_at IS NULL OR p_bay_id IS NULL THEN RETURN NULL; END IF;
  t := date_trunc('minute', p_at);
  IF t < p_at THEN t := t + interval '1 minute'; END IF;
  limit_at := p_at + interval '90 days';
  WHILE t < limit_at AND guard < 4000 LOOP
    guard := guard + 1;
    IF public.workshop_bay_minute_open_570(t, p_bay_id) THEN RETURN t; END IF;
    local_ts := t AT TIME ZONE 'Australia/Perth';
    day := local_ts::date;
    segs := public.workshop_bay_segments_570(p_bay_id, day);
    m := extract(hour FROM local_ts)::int * 60 + extract(minute FROM local_ts)::int;
    jump := NULL;
    IF segs IS NOT NULL THEN
      FOR w IN SELECT value FROM jsonb_array_elements(segs) LOOP
        IF (w->>'e')::int > m THEN
          IF (w->>'s')::int > m THEN
            jump := (day::timestamp + make_interval(mins => (w->>'s')::int)) AT TIME ZONE 'Australia/Perth';
          ELSE
            jump := t + interval '1 minute';
          END IF;
          EXIT;
        END IF;
      END LOOP;
    END IF;
    IF jump IS NULL THEN
      jump := ((day + 1)::timestamp) AT TIME ZONE 'Australia/Perth';
    END IF;
    IF jump <= t THEN jump := t + interval '1 minute'; END IF;
    t := jump;
  END LOOP;
  RETURN NULL;
END
$next570$;

CREATE FUNCTION public.workshop_bay_add_minutes_570(p_start timestamptz, p_minutes integer, p_bay_id uuid)
 RETURNS timestamptz
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $add570$
DECLARE
  cursor_at timestamptz;
  remaining numeric;
  local_ts timestamp;
  day date;
  segs jsonb;
  w jsonb;
  minute_num numeric;
  seg_s numeric;
  seg_e numeric;
  available numeric;
  guard int := 0;
  seg_end timestamptz;
BEGIN
  IF p_start IS NULL OR p_minutes IS NULL OR p_minutes < 0 OR p_bay_id IS NULL THEN RETURN NULL; END IF;
  IF p_minutes > 59999 THEN RETURN NULL; END IF;
  IF NOT public.workshop_bay_has_hours_570(p_bay_id) THEN RETURN NULL; END IF;
  IF p_minutes = 0 THEN
    IF public.workshop_bay_minute_open_570(p_start, p_bay_id) THEN RETURN p_start; END IF;
    RETURN public.workshop_bay_next_minute_570(p_start, p_bay_id);
  END IF;
  cursor_at := p_start;
  IF NOT public.workshop_bay_minute_open_570(cursor_at, p_bay_id) THEN
    cursor_at := public.workshop_bay_next_minute_570(cursor_at, p_bay_id);
    IF cursor_at IS NULL THEN RETURN NULL; END IF;
  END IF;
  remaining := p_minutes;
  WHILE remaining > 0 AND guard < 800 LOOP
    guard := guard + 1;
    IF cursor_at > p_start + interval '366 days' THEN RETURN NULL; END IF;
    local_ts := cursor_at AT TIME ZONE 'Australia/Perth';
    day := local_ts::date;
    segs := public.workshop_bay_segments_570(p_bay_id, day);
    minute_num := extract(epoch FROM (local_ts - date_trunc('day', local_ts))) / 60.0;
    seg_s := NULL; seg_e := NULL;
    IF segs IS NOT NULL THEN
      FOR w IN SELECT value FROM jsonb_array_elements(segs) LOOP
        IF (w->>'e')::numeric > minute_num THEN
          seg_s := (w->>'s')::numeric;
          seg_e := (w->>'e')::numeric;
          EXIT;
        END IF;
      END LOOP;
    END IF;
    IF seg_e IS NULL THEN
      cursor_at := public.workshop_bay_next_minute_570(((day + 1)::timestamp) AT TIME ZONE 'Australia/Perth', p_bay_id);
      IF cursor_at IS NULL THEN RETURN NULL; END IF;
      CONTINUE;
    END IF;
    IF minute_num < seg_s THEN
      cursor_at := (day::timestamp + make_interval(mins => seg_s::int)) AT TIME ZONE 'Australia/Perth';
      minute_num := seg_s;
    END IF;
    available := seg_e - minute_num;
    IF remaining <= available THEN
      RETURN cursor_at + (remaining * interval '1 minute');
    END IF;
    remaining := remaining - available;
    seg_end := (day::timestamp + make_interval(mins => ceil(seg_e)::int)) AT TIME ZONE 'Australia/Perth';
    cursor_at := public.workshop_bay_next_minute_570(seg_end, p_bay_id);
    IF cursor_at IS NULL THEN RETURN NULL; END IF;
  END LOOP;
  RETURN NULL;
END
$add570$;

CREATE FUNCTION public.workshop_bay_minutes_between_570(p_start timestamptz, p_end timestamptz, p_bay_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $between570$
DECLARE
  day date;
  last_day date;
  segs jsonb;
  w jsonb;
  window_start timestamptz;
  window_end timestamptz;
  overlap_start timestamptz;
  overlap_end timestamptz;
  total numeric := 0;
  guard int := 0;
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_end <= p_start OR p_bay_id IS NULL THEN RETURN 0; END IF;
  IF NOT public.workshop_bay_has_hours_570(p_bay_id) THEN RETURN NULL; END IF;
  day := (p_start AT TIME ZONE 'Australia/Perth')::date;
  last_day := (p_end AT TIME ZONE 'Australia/Perth')::date;
  WHILE day <= last_day AND guard < 400 LOOP
    guard := guard + 1;
    segs := public.workshop_bay_segments_570(p_bay_id, day);
    IF segs IS NOT NULL THEN
      FOR w IN SELECT value FROM jsonb_array_elements(segs) LOOP
        window_start := (day::timestamp + make_interval(mins => (w->>'s')::int)) AT TIME ZONE 'Australia/Perth';
        window_end := (day::timestamp + make_interval(mins => (w->>'e')::int)) AT TIME ZONE 'Australia/Perth';
        overlap_start := greatest(p_start, window_start);
        overlap_end := least(p_end, window_end);
        IF overlap_end > overlap_start THEN
          total := total + extract(epoch FROM (overlap_end - overlap_start)) / 60.0;
        END IF;
      END LOOP;
    END IF;
    day := day + 1;
  END LOOP;
  RETURN round(total)::int;
END
$between570$;

CREATE FUNCTION public.workshop_bay_station_key_570(p_bay_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $st570$
 SELECT CASE
   WHEN b.is_sublet_row THEN NULL
   WHEN s.code = 'BUS_4X4' AND b.bay_number BETWEEN 1 AND 4 THEN 'bus-mechanical'
   WHEN s.code = 'BUS_4X4' AND b.bay_number BETWEEN 5 AND 6 THEN 'bus-progression'
   WHEN s.code = 'BUS_4X4' AND b.bay_number = 7 THEN 'bus-qa'
   WHEN s.code = 'BUS_4X4' AND b.bay_number IN (8, 9) THEN 'bus-electrical'
   WHEN s.code = 'BUS_4X4' AND b.bay_number = 10 THEN 'bus-accessory'
   WHEN s.code = 'HOIST' THEN 'hoist'
   WHEN s.code = 'FABRICATION' THEN 'fab'
   WHEN s.code = 'FITTING' THEN 'fitting'
   WHEN s.code = 'ELECTRICAL' THEN 'electrical'
   WHEN s.code = 'TINT' THEN 'tint'
   WHEN s.code = 'TYRE' THEN 'tyre'
   WHEN s.code = 'PIT_INSPECTION' THEN 'pit'
   ELSE 'other-' || s.code
 END
 FROM public.workshop_bays b
 JOIN public.workshop_stages s ON s.id = b.stage_id
 WHERE b.id = p_bay_id;
$st570$;

-- The week the bay uses today when it has no saved override. Closures and
-- public holidays stay date rules in the engine; they are not weekly fields.
CREATE FUNCTION public.workshop_bay_station_default_570(p_bay_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $def570$
DECLARE
  bag jsonb;
  stage text;
  bay_no int;
  start_t text;
  finish_t text;
  week jsonb;
  breaks jsonb;
  names text[] := ARRAY['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
  i int;
  day_name text;
  working boolean;
  day_breaks jsonb;
  result jsonb := '{}'::jsonb;
BEGIN
  IF p_bay_id IS NULL THEN RETURN NULL; END IF;
  bag := public.workshop_settings_bag_554();
  SELECT f.code, f.bay_number INTO stage, bay_no FROM public.workshop_bay_stage_554(p_bay_id) f;
  week := coalesce(bag->'working_week', '["monday","tuesday","wednesday","thursday","friday"]'::jsonb);
  breaks := coalesce(bag->'break_windows', '[]'::jsonb);
  IF stage = 'BUS_4X4' THEN
    start_t := '06:00';
    finish_t := CASE WHEN bay_no IN (8, 9) THEN '14:00' ELSE '15:00' END;
  ELSE
    start_t := coalesce(bag->'day_start_time' #>> '{}', '06:00');
    finish_t := coalesce(bag->'day_end_time' #>> '{}', '16:30');
  END IF;
  FOR i IN 1..7 LOOP
    day_name := names[i];
    IF stage = 'BUS_4X4' THEN
      working := i <= 5;
    ELSE
      working := week ? day_name;
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('start', x.start_at, 'finish', x.finish_at) ORDER BY x.start_at), '[]'::jsonb)
      INTO day_breaks
    FROM (
      SELECT coalesce(w->>'start', w->>'from') AS start_at,
             coalesce(w->>'end', w->>'finish', w->>'to') AS finish_at,
             coalesce(w->>'scope', 'global') AS scope,
             nullif(w->>'date', '') AS on_date
      FROM jsonb_array_elements(breaks) w
    ) x
    WHERE x.on_date IS NULL
      AND x.start_at IS NOT NULL AND x.finish_at IS NOT NULL
      AND (x.scope = 'global' OR (working AND x.scope = 'working_day') OR x.scope = day_name);
    result := result || jsonb_build_object(day_name, jsonb_build_object(
      'off', NOT working,
      'start', start_t,
      'finish', finish_t,
      'breaks', coalesce(day_breaks, '[]'::jsonb)
    ));
  END LOOP;
  RETURN result;
END
$def570$;

CREATE FUNCTION public.workshop_bay_hours_normalize_570(p_hours jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO pg_catalog
AS $norm570$
DECLARE
  names text[] := ARRAY['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
  day_name text;
  spec jsonb;
  result jsonb := '{}'::jsonb;
  br jsonb;
  breaks jsonb;
  seen int[] := ARRAY[]::int[];
  bstart int;
  bfinish int;
  dstart int;
  dfinish int;
  n int;
  v_start text;
  v_finish text;
BEGIN
  IF jsonb_typeof(p_hours) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'hours_shape' USING ERRCODE = '22023';
  END IF;
  IF octet_length(p_hours::text) > 4000 THEN
    RAISE EXCEPTION 'hours_size' USING ERRCODE = '22023';
  END IF;
  FOREACH day_name IN ARRAY names LOOP
    spec := p_hours -> day_name;
    IF spec IS NULL OR jsonb_typeof(spec) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'hours_day' USING ERRCODE = '22023';
    END IF;
    v_start := coalesce(spec->>'start', '06:00');
    IF v_start !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'hours_time' USING ERRCODE = '22023'; END IF;
    dstart := split_part(v_start, ':', 1)::int * 60 + split_part(v_start, ':', 2)::int;
    v_finish := coalesce(spec->>'finish', '16:30');
    IF v_finish !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'hours_time' USING ERRCODE = '22023'; END IF;
    dfinish := split_part(v_finish, ':', 1)::int * 60 + split_part(v_finish, ':', 2)::int;
    IF coalesce((spec->>'off')::boolean, false) THEN
      result := result || jsonb_build_object(day_name, jsonb_build_object('off', true, 'start', v_start, 'finish', v_finish, 'breaks', '[]'::jsonb));
      CONTINUE;
    END IF;
    IF dfinish <= dstart THEN RAISE EXCEPTION 'hours_order' USING ERRCODE = '22023'; END IF;
    breaks := '[]'::jsonb;
    seen := ARRAY[]::int[];
    n := 0;
    FOR br IN SELECT value FROM jsonb_array_elements(coalesce(spec->'breaks', '[]'::jsonb)) LOOP
      n := n + 1;
      IF n > 4 THEN RAISE EXCEPTION 'hours_breaks' USING ERRCODE = '22023'; END IF;
      IF coalesce(br->>'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'hours_time' USING ERRCODE = '22023'; END IF;
      IF coalesce(br->>'finish', br->>'end', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'hours_time' USING ERRCODE = '22023'; END IF;
      bstart := split_part(br->>'start', ':', 1)::int * 60 + split_part(br->>'start', ':', 2)::int;
      bfinish := split_part(coalesce(br->>'finish', br->>'end'), ':', 1)::int * 60 + split_part(coalesce(br->>'finish', br->>'end'), ':', 2)::int;
      IF bfinish <= bstart OR bstart < dstart OR bfinish > dfinish THEN RAISE EXCEPTION 'hours_break_outside' USING ERRCODE = '22023'; END IF;
      IF array_length(seen, 1) IS NOT NULL THEN
        -- overlap against previously accepted [start, finish) packed as start*10000+finish
        IF EXISTS (
          SELECT 1 FROM unnest(seen) packed
          WHERE (packed / 10000) < bfinish AND bstart < (packed % 10000)
        ) THEN RAISE EXCEPTION 'hours_break_overlap' USING ERRCODE = '22023'; END IF;
      END IF;
      seen := seen || (bstart * 10000 + bfinish);
      breaks := breaks || jsonb_build_array(jsonb_build_object('start', br->>'start', 'finish', coalesce(br->>'finish', br->>'end')));
    END LOOP;
    result := result || jsonb_build_object(day_name, jsonb_build_object(
      'off', false,
      'start', v_start,
      'finish', v_finish,
      'breaks', breaks
    ));
  END LOOP;
  RETURN result;
END
$norm570$;

CREATE FUNCTION public.workshop_bay_hours_outside_570(p_bay_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $out570$
DECLARE
  rows jsonb := '[]'::jsonb;
  n int := 0;
BEGIN
  PERFORM set_config('pdc.bay_hours_570', '', true);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'stock_number', stock_number,
      'key_number', key_number,
      'bay', bay_name,
      'status', status,
      'start', scheduled_start_at,
      'finish', scheduled_end_at
    ) ORDER BY scheduled_start_at), '[]'::jsonb)
  INTO rows
  FROM (
    SELECT v.stock_number,
           v.key_number::text AS key_number,
           coalesce(nullif(btrim(b.display_name), ''), b.code) AS bay_name,
           bk.status::text AS status,
           bk.scheduled_start_at,
           bk.scheduled_end_at
    FROM public.workshop_bookings bk
    JOIN public.workshop_bays b ON b.id = bk.bay_id
    JOIN public.workshop_stages s ON s.id = b.stage_id
    LEFT JOIN public.vehicles v ON v.id = bk.vehicle_id
    WHERE bk.bay_id = ANY(coalesce(p_bay_ids, '{}'::uuid[]))
      AND bk.deleted_at IS NULL
      AND bk.status IN ('queued', 'planned', 'started', 'stoppage')
      AND bk.scheduled_end_at > clock_timestamp() - interval '1 day'
      AND (
        CASE
          WHEN public.workshop_bay_has_hours_570(bk.bay_id) THEN NOT public.workshop_bay_minute_open_570(bk.scheduled_start_at, bk.bay_id)
          ELSE NOT pdc_bus_private.minute_available(bk.scheduled_start_at, bk.bay_id)
        END
        OR coalesce(
          CASE
            WHEN public.workshop_bay_has_hours_570(bk.bay_id) THEN public.workshop_bay_minutes_between_570(bk.scheduled_start_at, bk.scheduled_end_at, bk.bay_id)
            WHEN s.code = 'BUS_4X4' THEN pdc_bus_private.clock_minutes_between(bk.scheduled_start_at, bk.scheduled_end_at, bk.bay_id)
            ELSE public.workshop_operational_minutes_between(bk.scheduled_start_at, bk.scheduled_end_at)
          END, 0
        ) < bk.default_duration_minutes
      )
    ORDER BY bk.scheduled_start_at, bk.id
    LIMIT 41
  ) hit;
  n := coalesce(jsonb_array_length(rows), 0);
  IF n > 40 THEN rows := rows - 40; END IF;
  RETURN jsonb_build_object('outside', rows, 'outside_count', n, 'outside_truncated', n > 40);
END
$out570$;
CREATE FUNCTION public.list_workshop_bay_hours_570()
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $list570$
DECLARE
  stations jsonb;
BEGIN
  IF to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'staging_only');
  END IF;
  IF NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authorized');
  END IF;
  SELECT coalesce(jsonb_agg(station ORDER BY sort_no, station_key), '[]'::jsonb) INTO stations
  FROM (
    SELECT station_key,
           min(sort_no) AS sort_no,
           jsonb_build_object(
             'key', station_key,
             'label', min(station_label),
             'bays', jsonb_agg(jsonb_build_object(
               'id', id,
               'code', code,
               'bay_number', bay_number,
               'stage', stage,
               'display_name', display_name,
               'is_active', is_active,
               'bay_version', bay_version,
               'hours_version', hours_version,
               'override', override_hours,
               'station_default', station_default,
               'source', CASE WHEN override_hours IS NULL THEN CASE WHEN stage = 'BUS_4X4' THEN 'bus_shift' ELSE 'workshop_calendar' END ELSE 'override' END
             ) ORDER BY bay_number)
           ) AS station
    FROM (
      SELECT b.id,
             b.code,
             b.bay_number,
             s.code AS stage,
             coalesce(nullif(btrim(b.display_name), ''), b.code) AS display_name,
             b.is_active,
             b.version AS bay_version,
             coalesce(h.version, 0) AS hours_version,
             h.hours AS override_hours,
             public.workshop_bay_station_default_570(b.id) AS station_default,
             public.workshop_bay_station_key_570(b.id) AS station_key,
             CASE public.workshop_bay_station_key_570(b.id)
               WHEN 'hoist' THEN 10 WHEN 'fab' THEN 20 WHEN 'fitting' THEN 30 WHEN 'electrical' THEN 40
               WHEN 'bus-mechanical' THEN 50 WHEN 'bus-progression' THEN 60 WHEN 'bus-qa' THEN 70
               WHEN 'bus-electrical' THEN 80 WHEN 'bus-accessory' THEN 90
               WHEN 'tint' THEN 100 WHEN 'tyre' THEN 110 WHEN 'pit' THEN 120 ELSE 200 END AS sort_no,
             CASE public.workshop_bay_station_key_570(b.id)
               WHEN 'hoist' THEN 'Hoist · PMB (139)'
               WHEN 'fab' THEN 'Fab · PMB (139)'
               WHEN 'fitting' THEN 'Fitting · PMB (139)'
               WHEN 'electrical' THEN 'Electrical · PMB (139)'
               WHEN 'bus-mechanical' THEN 'Mechanical · Bus 4×4 (138)'
               WHEN 'bus-progression' THEN 'Progression · Bus 4×4 (138)'
               WHEN 'bus-qa' THEN 'QA · Bus 4×4 (138)'
               WHEN 'bus-electrical' THEN 'Electrical · Bus 4×4 (138)'
               WHEN 'bus-accessory' THEN 'Accessory Fitting · Bus 4×4 (138)'
               WHEN 'tint' THEN 'Tint · shared'
               WHEN 'tyre' THEN 'Tyres · shared'
               WHEN 'pit' THEN 'Pit'
               ELSE s.display_name END AS station_label
      FROM public.workshop_bays b
      JOIN public.workshop_stages s ON s.id = b.stage_id
      LEFT JOIN public.workshop_bay_work_hours_570 h ON h.bay_id = b.id
      WHERE NOT b.is_sublet_row
        AND s.code IN ('HOIST','FABRICATION','FITTING','ELECTRICAL','BUS_4X4','TINT','TYRE','PIT_INSPECTION')
    ) bay
    GROUP BY station_key
  ) grouped;
  RETURN jsonb_build_object(
    'ok', true,
    'can_write', coalesce(public.is_pdc_role('operator'::public.pdc_role), false),
    'role', public.current_pdc_user_role()::text,
    'stations', stations
  );
END
$list570$;

CREATE FUNCTION public.set_workshop_bay_hours_570(p_bay_id uuid, p_expected_version integer, p_hours jsonb, p_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $set570$
DECLARE
  v_mode text := lower(coalesce(p_mode, ''));
  v_key text;
  v_row public.workshop_bay_work_hours_570%ROWTYPE;
  v_hours jsonb;
  v_before jsonb;
  v_ids uuid[] := '{}'::uuid[];
  v_sib uuid;
  v_sib_row public.workshop_bay_work_hours_570%ROWTYPE;
  v_warn jsonb;
BEGIN
  IF to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'staging_only');
  END IF;
  PERFORM public.require_pdc_role('operator'::public.pdc_role);
  IF v_mode NOT IN ('save', 'reset', 'copy') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mode');
  END IF;
  v_key := public.workshop_bay_station_key_570(p_bay_id);
  IF v_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF v_mode IN ('save', 'copy') THEN
    BEGIN
      v_hours := public.workshop_bay_hours_normalize_570(p_hours);
    EXCEPTION WHEN SQLSTATE '22023' THEN
      RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
    END;
  END IF;
  SELECT * INTO v_row FROM public.workshop_bay_work_hours_570 WHERE bay_id = p_bay_id FOR UPDATE;
  IF FOUND THEN
    IF v_row.version IS DISTINCT FROM p_expected_version THEN
      IF v_mode = 'reset' OR v_row.hours IS DISTINCT FROM v_hours THEN
        RETURN jsonb_build_object('ok', false, 'error', 'version_conflict', 'hours_version', v_row.version);
      END IF;
    END IF;
    v_before := v_row.hours;
  ELSE
    IF coalesce(p_expected_version, 0) <> 0 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'version_conflict', 'hours_version', 0);
    END IF;
    v_before := NULL;
  END IF;

  IF v_mode = 'reset' THEN
    IF FOUND THEN
      DELETE FROM public.workshop_bay_work_hours_570 WHERE bay_id = p_bay_id;
      PERFORM public.audit_pdc_event(
        'reference_change'::public.audit_action,
        'workshop_bay_work_hours_570',
        p_bay_id,
        NULL::uuid,
        v_before,
        NULL::jsonb,
        jsonb_build_object('action', 'reset', 'release', 'r577'));
    END IF;
    v_ids := ARRAY[p_bay_id];
  ELSE
    IF FOUND AND v_row.hours IS NOT DISTINCT FROM v_hours THEN
      NULL;
    ELSIF FOUND THEN
      UPDATE public.workshop_bay_work_hours_570
         SET hours = v_hours, version = version + 1, updated_at = clock_timestamp(), updated_by = auth.uid()
       WHERE bay_id = p_bay_id
       RETURNING hours INTO v_hours;
      PERFORM public.audit_pdc_event(
        'reference_change'::public.audit_action, 'workshop_bay_work_hours_570', p_bay_id, NULL::uuid,
        v_before, v_hours, jsonb_build_object('action', v_mode, 'release', 'r577'));
    ELSE
      INSERT INTO public.workshop_bay_work_hours_570 (bay_id, hours, version, updated_by)
      VALUES (p_bay_id, v_hours, 1, auth.uid());
      PERFORM public.audit_pdc_event(
        'reference_change'::public.audit_action, 'workshop_bay_work_hours_570', p_bay_id, NULL::uuid,
        NULL::jsonb, v_hours, jsonb_build_object('action', v_mode, 'release', 'r577'));
    END IF;
    v_ids := ARRAY[p_bay_id];
    IF v_mode = 'copy' THEN
      FOR v_sib IN
        SELECT b.id
        FROM public.workshop_bays b
        WHERE public.workshop_bay_station_key_570(b.id) = v_key
          AND b.id <> p_bay_id
          AND NOT b.is_sublet_row
        FOR UPDATE
      LOOP
        SELECT * INTO v_sib_row FROM public.workshop_bay_work_hours_570 WHERE bay_id = v_sib FOR UPDATE;
        IF FOUND AND v_sib_row.hours IS NOT DISTINCT FROM v_hours THEN
          CONTINUE;
        ELSIF FOUND THEN
          UPDATE public.workshop_bay_work_hours_570
             SET hours = v_hours, version = version + 1, updated_at = clock_timestamp(), updated_by = auth.uid()
           WHERE bay_id = v_sib;
          PERFORM public.audit_pdc_event(
            'reference_change'::public.audit_action, 'workshop_bay_work_hours_570', v_sib, NULL::uuid,
            v_sib_row.hours, v_hours, jsonb_build_object('action', 'copy', 'release', 'r577', 'from_bay', p_bay_id));
        ELSE
          INSERT INTO public.workshop_bay_work_hours_570 (bay_id, hours, version, updated_by)
          VALUES (v_sib, v_hours, 1, auth.uid());
          PERFORM public.audit_pdc_event(
            'reference_change'::public.audit_action, 'workshop_bay_work_hours_570', v_sib, NULL::uuid,
            NULL::jsonb, v_hours, jsonb_build_object('action', 'copy', 'release', 'r577', 'from_bay', p_bay_id));
        END IF;
        v_ids := v_ids || v_sib;
      END LOOP;
    END IF;
  END IF;

  PERFORM set_config('pdc.bay_hours_570', '', true);
  v_warn := public.workshop_bay_hours_outside_570(v_ids);
  RETURN jsonb_build_object('ok', true, 'mode', v_mode, 'bay_id', p_bay_id, 'hours', CASE WHEN v_mode = 'reset' THEN NULL ELSE v_hours END)
    || v_warn;
END
$set570$;

REVOKE ALL ON FUNCTION public.workshop_bay_hours_blob_570() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_has_hours_570(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_dow_key_570(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_date_closed_570(date, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_segments_570(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_minute_open_570(timestamptz, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_next_minute_570(timestamptz, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_add_minutes_570(timestamptz, integer, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_minutes_between_570(timestamptz, timestamptz, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_station_key_570(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_station_default_570(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_hours_normalize_570(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_bay_hours_outside_570(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_workshop_bay_hours_570() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_workshop_bay_hours_570(uuid, integer, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_workshop_bay_hours_570() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_workshop_bay_hours_570(uuid, integer, jsonb, text) TO authenticated;

-- The clock and the planners call the helpers. Owners keep execute; anon and authenticated do not.
GRANT EXECUTE ON FUNCTION public.workshop_bay_has_hours_570(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.workshop_bay_minute_open_570(timestamptz, uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.workshop_bay_next_minute_570(timestamptz, uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.workshop_bay_add_minutes_570(timestamptz, integer, uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.workshop_bay_minutes_between_570(timestamptz, timestamptz, uuid) TO postgres;

CREATE FUNCTION pg_temp.r570_patch(p_sig text, p_md5 text, p_from text, p_to text, p_count int)
 RETURNS void
 LANGUAGE plpgsql
AS $patch570$
DECLARE def text; got int;
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(p_sig)) IS DISTINCT FROM p_md5 THEN
    RAISE EXCEPTION 'r577: % is not %', p_sig, p_md5;
  END IF;
  def := pg_get_functiondef(to_regprocedure(p_sig));
  got := (length(def) - length(replace(def, p_from, ''))) / length(p_from);
  IF got <> p_count THEN
    RAISE EXCEPTION 'r577: % pattern count % wanted %', p_sig, got, p_count;
  END IF;
  EXECUTE replace(def, p_from, p_to);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(p_sig)) = p_md5 THEN
    RAISE EXCEPTION 'r577: % did not change', p_sig;
  END IF;
END
$patch570$;

SELECT pg_temp.r570_patch(
  'pdc_bus_private.minute_available(timestamptz,uuid)',
  'ca85b70cf2728a523a6e8d4231a19b08',
  $old$BEGIN
 SELECT f.bay_number, f.code INTO bay, code FROM public.workshop_bay_stage_554(p_bay_id) f;$old$,
  $new$BEGIN
 IF public.workshop_bay_has_hours_570(p_bay_id) THEN RETURN public.workshop_bay_minute_open_570(p_at, p_bay_id); END IF;
 SELECT f.bay_number, f.code INTO bay, code FROM public.workshop_bay_stage_554(p_bay_id) f;$new$,
  1);

SELECT pg_temp.r570_patch(
  'pdc_bus_private.add_minutes(timestamptz,integer,uuid)',
  'c43afa5c1312392aa5d3666a8aa7cf65',
  $old$IF p_start IS NULL OR p_minutes IS NULL OR p_minutes<0 OR p_minutes>59999 THEN RAISE EXCEPTION 'Invalid duration' USING errcode='22023'; END IF;$old$,
  $new$IF p_start IS NULL OR p_minutes IS NULL OR p_minutes<0 OR p_minutes>59999 THEN RAISE EXCEPTION 'Invalid duration' USING errcode='22023'; END IF;
 IF public.workshop_bay_has_hours_570(p_bay_id) THEN RETURN public.workshop_bay_add_minutes_570(p_start, p_minutes, p_bay_id); END IF;$new$,
  1);

SELECT pg_temp.r570_patch(
  'pdc_bus_private.clock_next_minute(timestamptz,uuid)',
  '734b6fc0d468b8a8a9cee2b955f9b21b',
  $old$IF p_at IS NULL THEN RAISE EXCEPTION 'Clock time required' USING errcode='22023'; END IF;$old$,
  $new$IF p_at IS NULL THEN RAISE EXCEPTION 'Clock time required' USING errcode='22023'; END IF;
 IF public.workshop_bay_has_hours_570(p_calendar_bay_id) THEN RETURN public.workshop_bay_next_minute_570(p_at, p_calendar_bay_id); END IF;$new$,
  1);

SELECT pg_temp.r570_patch(
  'pdc_bus_private.clock_minutes_between(timestamptz,timestamptz,uuid)',
  'c1e4e6b69cd67aebcbce738fd1a68dc2',
  $old$IF p_calendar_bay_id IS NULL THEN RETURN public.workshop_operational_minutes_between(p_start,p_end); END IF;$old$,
  $new$IF p_calendar_bay_id IS NULL THEN RETURN public.workshop_operational_minutes_between(p_start,p_end); END IF;
 IF public.workshop_bay_has_hours_570(p_calendar_bay_id) THEN RETURN public.workshop_bay_minutes_between_570(p_start, p_end, p_calendar_bay_id); END IF;$new$,
  1);

SELECT pg_temp.r570_patch(
  'pdc_bay_seq_private.end_at(timestamptz,integer,uuid)',
  '8067dd22688d7b93d90c9c03eabfbe7d',
  $old$BEGIN
 IF EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay AND s.code='BUS_4X4') THEN$old$,
  $new$BEGIN
 IF public.workshop_bay_has_hours_570(p_bay) THEN RETURN public.workshop_bay_add_minutes_570(p_start, greatest(p_minutes,0), p_bay); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay AND s.code='BUS_4X4') THEN$new$,
  1);

SELECT pg_temp.r570_patch(
  'pdc_bay_seq_private.next_start(timestamptz,uuid)',
  '6d2cdc4cb26bb37794c6998b206f6e0c',
  $old$IF p_at IS NULL THEN RETURN NULL; END IF;$old$,
  $new$IF p_at IS NULL THEN RETURN NULL; END IF;
 IF public.workshop_bay_has_hours_570(p_bay) THEN RETURN public.workshop_bay_next_minute_570(p_at, p_bay); END IF;$new$,
  1);

SELECT pg_temp.r570_patch(
  'pdc_cascade_private.target_end_469(uuid,uuid,timestamptz,integer)',
  'b7b98893bfc7a04b39330ca689f8f1b1',
  $old$if p_start is null or p_minutes is null or p_minutes < 1 then return null; end if;$old$,
  $new$if p_start is null or p_minutes is null or p_minutes < 1 then return null; end if;
  if public.workshop_bay_has_hours_570(p_bay_id) then return public.workshop_bay_add_minutes_570(p_start, p_minutes, p_bay_id); end if;$new$,
  1);

SELECT pg_temp.r570_patch(
  'pdc_cascade_private.overlap_chain_469(uuid[],timestamptz)',
  'e3602ba6f9d5973deea4eef09f5077c0',
  $old$select b.id, b.version, b.scheduled_start_at, b.scheduled_end_at, b.default_duration_minutes$old$,
  $new$select b.id, b.version, b.scheduled_start_at, b.scheduled_end_at, b.default_duration_minutes, b.bay_id$new$,
  1);

-- Second overlap replace. The md5 has already moved, so patch against the live body.
DO $ov$
DECLARE def text; cur text; src text := $old$    v_new_start := public.workshop_next_calendar_window(v_cursor, v_row.default_duration_minutes);
    v_new_end := public.workshop_add_operational_minutes(v_new_start, v_row.default_duration_minutes);$old$;
BEGIN
  cur := (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.overlap_chain_469(uuid[],timestamptz)'));
  def := pg_get_functiondef(to_regprocedure('pdc_cascade_private.overlap_chain_469(uuid[],timestamptz)'));
  IF (length(def)-length(replace(def, src, ''))) / length(src) <> 1 THEN
    RAISE EXCEPTION 'r577: overlap window pattern missing';
  END IF;
  EXECUTE replace(def, src, $new$    v_new_start := CASE WHEN public.workshop_bay_has_hours_570(v_row.bay_id) THEN public.workshop_bay_next_minute_570(v_cursor, v_row.bay_id) ELSE public.workshop_next_calendar_window(v_cursor, v_row.default_duration_minutes) END;
    v_new_end := CASE WHEN public.workshop_bay_has_hours_570(v_row.bay_id) THEN public.workshop_bay_add_minutes_570(v_new_start, v_row.default_duration_minutes, v_row.bay_id) ELSE public.workshop_add_operational_minutes(v_new_start, v_row.default_duration_minutes) END;$new$);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.overlap_chain_469(uuid[],timestamptz)')) = cur THEN
    RAISE EXCEPTION 'r577: overlap chain did not change';
  END IF;
END $ov$;

SELECT pg_temp.r570_patch(
  'public.workshop_clock_tick(boolean,timestamptz)',
  '83a2c8d5ff85b5a295343e5f3ef66ded',
  $old$CASE WHEN s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END$old$,
  $new$CASE WHEN (s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id)) OR public.workshop_bay_has_hours_570(b.bay_id) THEN b.bay_id END$new$,
  2);

SELECT pg_temp.r570_patch(
  'public.workshop_capacity_plan(text,uuid,integer,timestamptz)',
  'bc237d9f466c45a086c251ec8c3071a7',
  $old$CASE WHEN s.code='BUS_4X4' AND b.bay_id IS NOT NULL AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END$old$,
  $new$CASE WHEN public.workshop_bay_has_hours_570(b.bay_id) OR s.code='BUS_4X4' AND b.bay_id IS NOT NULL AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END$new$,
  1);

SELECT pg_temp.r570_patch(
  'public.book_all_vehicle_stations(uuid,integer)',
  '90fc0d4727d827db53c308ff9dfa8bcd',
  $old$calendar_bay:=CASE WHEN item->>'code'='BUS_4X4' AND pdc_bus_private.active_vehicle(v.id) THEN bay.id END;$old$,
  $new$calendar_bay:=CASE WHEN (item->>'code'='BUS_4X4' AND pdc_bus_private.active_vehicle(v.id)) OR public.workshop_bay_has_hours_570(bay.id) THEN bay.id END;$new$,
  1);

SELECT pg_temp.r570_patch(
  'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)',
  'ae08aa9b0dc99e7c93b1710efdcb5070',
  $old$if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND public.workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at)<>p_duration_minutes then$old$,
  $new$if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND NOT (public.workshop_bay_has_hours_570(p_bay_id) AND EXISTS (SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.bay_id=p_bay_id AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at AND b.default_duration_minutes=p_duration_minutes AND b.deleted_at IS NULL)) AND (CASE WHEN public.workshop_bay_has_hours_570(p_bay_id) THEN public.workshop_bay_minutes_between_570(p_scheduled_start_at,p_scheduled_end_at,p_bay_id) ELSE public.workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at) END) <>p_duration_minutes then$new$,
  1);

DO $val$
DECLARE def text; cur text; src text := $old$END ELSE public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) END else p_scheduled_end_at end$old$;
BEGIN
  cur := (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'));
  def := pg_get_functiondef(to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'));
  IF (length(def)-length(replace(def, src, ''))) / length(src) <> 1 THEN
    RAISE EXCEPTION 'r577: validate end pattern missing';
  END IF;
  EXECUTE replace(def, src, $new$END ELSE CASE WHEN public.workshop_bay_has_hours_570(p_bay_id) THEN public.workshop_bay_add_minutes_570(p_scheduled_start_at,v_estimated_duration,p_bay_id) ELSE public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) END END else p_scheduled_end_at end$new$);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')) = cur THEN
    RAISE EXCEPTION 'r577: validate end did not change';
  END IF;
END $val$;

SELECT pg_temp.r570_patch(
  'public.workshop_booking_effective_end_at(uuid)',
  '3cd30a49767b2b79fadc325d56cbca42',
  $old$RETURN (SELECT CASE WHEN b.bus_calendar_version=1 AND b.status IN('queued','planned','started','stoppage')
 THEN pdc_bus_private.add_minutes(b.scheduled_start_at,public.workshop_booking_effective_duration_minutes(b.id),b.bay_id)$old$,
  $new$RETURN (SELECT CASE WHEN public.workshop_bay_has_hours_570(b.bay_id) AND b.status IN('queued','planned','started','stoppage')
 THEN public.workshop_bay_add_minutes_570(b.scheduled_start_at,public.workshop_booking_effective_duration_minutes(b.id),b.bay_id)
 WHEN b.bus_calendar_version=1 AND b.status IN('queued','planned','started','stoppage')
 THEN pdc_bus_private.add_minutes(b.scheduled_start_at,public.workshop_booking_effective_duration_minutes(b.id),b.bay_id)$new$,
  1);

SELECT pg_temp.r570_patch(
  'public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
  'd5e0543537cafb026383c7338c8e2b82',
  $old$v_target_end:=public.workshop_add_operational_minutes(p_scheduled_start_at,v_target_duration);$old$,
  $new$v_target_end:=COALESCE((SELECT public.workshop_bay_add_minutes_570(p_scheduled_start_at,v_target_duration,b.id) FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE public.workshop_canonical_stage_code(s.code)=public.workshop_canonical_stage_code(p_stage_code) AND b.bay_number=p_bay_number AND NOT b.is_sublet_row AND public.workshop_bay_has_hours_570(b.id) LIMIT 1), public.workshop_add_operational_minutes(p_scheduled_start_at,v_target_duration));$new$,
  1);

DO $pins$
DECLARE n int;
BEGIN
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.add_minutes(timestamptz,integer,uuid)')), release='r577', note='r577: per-bay hours when an override exists (was c43afa5c1312392aa5d3666a8aa7cf65)', updated_at=now()
   WHERE signature='pdc_bus_private.add_minutes(timestamp with time zone,integer,uuid)' AND prosrc_md5='c43afa5c1312392aa5d3666a8aa7cf65' AND release='20261020015824';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r577: add_minutes pin'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bay_seq_private.end_at(timestamptz,integer,uuid)')), release='r577', note='r577: per-bay hours when an override exists (was 8067dd22688d7b93d90c9c03eabfbe7d, r424)', updated_at=now()
   WHERE signature='pdc_bay_seq_private.end_at(timestamp with time zone,integer,uuid)' AND prosrc_md5='8067dd22688d7b93d90c9c03eabfbe7d' AND release='r424';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r577: end_at pin'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bay_seq_private.next_start(timestamptz,uuid)')), release='r577', note='r577: per-bay hours when an override exists (was 6d2cdc4cb26bb37794c6998b206f6e0c, r424)', updated_at=now()
   WHERE signature='pdc_bay_seq_private.next_start(timestamp with time zone,uuid)' AND prosrc_md5='6d2cdc4cb26bb37794c6998b206f6e0c' AND release='r424';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r577: next_start pin'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.target_end_469(uuid,uuid,timestamptz,integer)')), note='r577: per-bay hours when an override exists. Release stays r469 so cascade_insert_overlap_chain_469 still counts 4 pins (was b7b98893bfc7a04b39330ca689f8f1b1).', updated_at=now()
   WHERE signature='pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer)' AND prosrc_md5='b7b98893bfc7a04b39330ca689f8f1b1' AND release='r469';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r577: target_end pin'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.overlap_chain_469(uuid[],timestamptz)')), note='r577: per-bay hours when an override exists. Release stays r469 so cascade_insert_overlap_chain_469 still counts 4 pins (was e3602ba6f9d5973deea4eef09f5077c0).', updated_at=now()
   WHERE signature='pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone)' AND prosrc_md5='e3602ba6f9d5973deea4eef09f5077c0' AND release='r469';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r577: overlap pin'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')), release='r577', note='r577: per-bay hours when an override exists (was 83a2c8d5ff85b5a295343e5f3ef66ded, r559)', updated_at=now()
   WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)' AND prosrc_md5='83a2c8d5ff85b5a295343e5f3ef66ded' AND release='r559';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r577: clock tick pin'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_capacity_plan(text,uuid,integer,timestamptz)')), release='r577', note='r577: per-bay hours when an override exists. The bus calendar needle stays intact (was bc237d9f466c45a086c251ec8c3071a7, r542).', updated_at=now()
   WHERE signature='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)' AND prosrc_md5='bc237d9f466c45a086c251ec8c3071a7' AND release='r542';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r577: capacity pin'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.book_all_vehicle_stations(uuid,integer)')), note='r577: per-bay hours when an override exists. Release stays r450 so bus_whole_job_450 still counts 15 pins (was 90fc0d4727d827db53c308ff9dfa8bcd).', updated_at=now()
   WHERE signature='public.book_all_vehicle_stations(uuid,integer)' AND prosrc_md5='90fc0d4727d827db53c308ff9dfa8bcd' AND release='r450';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r577: book_all pin'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')), note='r577: per-bay hours when an override exists. Release stays r548 so unallocated_bay_rechain_548 still sees r548 (was ae08aa9b0dc99e7c93b1710efdcb5070).', updated_at=now()
   WHERE signature='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)' AND prosrc_md5='ae08aa9b0dc99e7c93b1710efdcb5070' AND release='r548';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r577: validate pin'; END IF;
END $pins$;

UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, '83a2c8d5ff85b5a295343e5f3ef66ded', (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')))
 WHERE check_sql LIKE '%83a2c8d5ff85b5a295343e5f3ef66ded%';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'ae08aa9b0dc99e7c93b1710efdcb5070', (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')))
 WHERE check_sql LIKE '%ae08aa9b0dc99e7c93b1710efdcb5070%';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'bc237d9f466c45a086c251ec8c3071a7', (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_capacity_plan(text,uuid,integer,timestamptz)')))
 WHERE check_sql LIKE '%bc237d9f466c45a086c251ec8c3071a7%';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'release=''r559''', 'release=''r577''')
 WHERE check_name IN ('clock_ticks_recent', 'clock_tick_resaves_per_tick') AND check_sql LIKE '%release=''r559''%';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'tick_pin.release=''r559''', 'tick_pin.release=''r577''')
 WHERE check_name = 'bay_default_clock_gap_559' AND check_sql LIKE '%tick_pin.release=''r559''%';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, $from$release=''r559''$from$, $to$release=''r577''$to$)
 WHERE check_name = 'bay_default_clock_gap_559' AND check_sql LIKE $like$%release=''r559''%$like$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('bay_manager_hours_570', 'F191',
 'Bay Manager hours (r577): pin count stays 241, a bay with no override matches today, the clock tick reads the cached hours flag and does not scan the hours table, and saving hours does not rewrite a booking. Department 135 stays frozen.',
$chk570$
SELECT
  pins.n = 241
  AND pins.moved = 5
  AND val_pin.release = 'r548'
  AND val_pin.prosrc_md5 = pg_catalog.md5(val_fn.prosrc)
  AND pins.r450 = 15
  AND pins.r469 = 4
  AND book_pin.release = 'r450'
  AND book_pin.prosrc_md5 = pg_catalog.md5(book_fn.prosrc)
  AND tend_pin.release = 'r469'
  AND tend_pin.prosrc_md5 = pg_catalog.md5(tend_fn.prosrc)
  AND chain_pin.release = 'r469'
  AND chain_pin.prosrc_md5 = pg_catalog.md5(chain_fn.prosrc)
  AND tick_pin.release = 'r577'
  AND tick_pin.prosrc_md5 = pg_catalog.md5(tick.prosrc)
  AND pg_catalog.strpos(tick.prosrc, 'workshop_bay_has_hours_570') > 0
  AND pg_catalog.strpos(tick.prosrc, 'workshop_bay_work_hours_570') = 0
  AND k135.md5 = 'eb25ab44d4d007d3b749bd7bc5e56abc'
  AND kbus.md5 = '832bf8be742c16b86f937fa9579ee056'
  AND public.workshop_bay_has_hours_570('00000000-0000-0000-0000-000000000000'::uuid) IS FALSE
  AND pdc_bus_private.add_minutes(pg_catalog.timestamptz '2026-10-26 00:00:00+00', 60, '00000000-0000-0000-0000-000000000000'::uuid)
      IS NOT DISTINCT FROM public.workshop_add_operational_minutes(pg_catalog.timestamptz '2026-10-26 00:00:00+00', 60)
  AND pg_catalog.strpos(setter.prosrc, 'UPDATE public.workshop_bookings') = 0
  AND setter.prosecdef
  AND pg_catalog.strpos(coalesce(pg_catalog.array_to_string(setter.proconfig, ','), ''), 'pg_catalog') > 0
  AND pg_catalog.has_function_privilege('authenticated'::name, setter.oid, 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon'::name, setter.oid, 'EXECUTE')
  AND reader.prosecdef
  AND pg_catalog.has_function_privilege('authenticated'::name, reader.oid, 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon'::name, reader.oid, 'EXECUTE')
  AND tbl.relrowsecurity
  AND NOT pg_catalog.has_table_privilege('authenticated'::name, tbl.oid, 'SELECT')
  AND NOT pg_catalog.has_table_privilege('anon'::name, tbl.oid, 'SELECT')
  AND pg_catalog.strpos(recent.check_sql, 'release=''r577''') > 0
 AS ok,
 'tick '||pg_catalog.md5(tick.prosrc)||' pins '||pins.n::text||' moved '||pins.moved::text AS detail
FROM (SELECT count(*) AS n, count(*) FILTER (WHERE release = 'r577') AS moved, count(*) FILTER (WHERE release = 'r450') AS r450, count(*) FILTER (WHERE release = 'r469') AS r469 FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT prosrc_md5, release FROM pdc_ops.expected_function_md5 WHERE signature = 'public.book_all_vehicle_stations(uuid,integer)') book_pin
CROSS JOIN (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.book_all_vehicle_stations(uuid,integer)')) book_fn
CROSS JOIN (SELECT prosrc_md5, release FROM pdc_ops.expected_function_md5 WHERE signature = 'pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer)') tend_pin
CROSS JOIN (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('pdc_cascade_private.target_end_469(uuid,uuid,timestamptz,integer)')) tend_fn
CROSS JOIN (SELECT prosrc_md5, release FROM pdc_ops.expected_function_md5 WHERE signature = 'pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone)') chain_pin
CROSS JOIN (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('pdc_cascade_private.overlap_chain_469(uuid[],timestamptz)')) chain_fn
CROSS JOIN (SELECT prosrc_md5, release FROM pdc_ops.expected_function_md5 WHERE signature = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)') val_pin
CROSS JOIN (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')) val_fn
CROSS JOIN (SELECT prosrc_md5, release FROM pdc_ops.expected_function_md5 WHERE signature = 'public.workshop_clock_tick(boolean,timestamp with time zone)') tick_pin
CROSS JOIN (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) tick
CROSS JOIN (SELECT md5(prosrc) AS md5 FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.workshop_clock_tick(boolean,timestamptz)')) k135
CROSS JOIN (SELECT md5(prosrc) AS md5 FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_bus.add_minutes(timestamptz,integer,uuid)')) kbus
CROSS JOIN (SELECT prosrc, prosecdef, proconfig, oid FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.set_workshop_bay_hours_570(uuid,integer,jsonb,text)')) setter
CROSS JOIN (SELECT prosecdef, oid FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.list_workshop_bay_hours_570()')) reader
CROSS JOIN (SELECT c.oid, c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid = pg_catalog.to_regclass('public.workshop_bay_work_hours_570')) tbl
CROSS JOIN (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'clock_ticks_recent') recent
$chk570$, true, 349, 'r577');

DO $z$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r577: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release = 'r577') <> 5 THEN RAISE EXCEPTION 'r577: expected five pins to take release r577'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release = 'r450') <> 15 THEN RAISE EXCEPTION 'r577: r450 pin count left 15'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release = 'r469') <> 4 THEN RAISE EXCEPTION 'r577: r469 pin count left 4'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)') IS DISTINCT FROM 'r548' THEN RAISE EXCEPTION 'r577: validate left r548'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.book_all_vehicle_stations(uuid,integer)') IS DISTINCT FROM 'r450' THEN RAISE EXCEPTION 'r577: book_all left r450'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer)') IS DISTINCT FROM 'r469' THEN RAISE EXCEPTION 'r577: target_end left r469'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone)') IS DISTINCT FROM 'r469' THEN RAISE EXCEPTION 'r577: overlap chain left r469'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'eb25ab44d4d007d3b749bd7bc5e56abc' THEN RAISE EXCEPTION 'r577: department 135 clock moved'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_bus.add_minutes(timestamptz,integer,uuid)')) IS DISTINCT FROM '832bf8be742c16b86f937fa9579ee056' THEN RAISE EXCEPTION 'r577: department 135 bus add moved'; END IF;
 IF pg_catalog.strpos((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.set_workshop_bay_hours_570(uuid,integer,jsonb,text)')), 'UPDATE public.workshop_bookings') <> 0 THEN RAISE EXCEPTION 'r577: save rewrites bookings'; END IF;
 IF pg_catalog.strpos((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')), 'workshop_bay_work_hours_570') <> 0 THEN RAISE EXCEPTION 'r577: tick names the hours table'; END IF;
END $z$;
