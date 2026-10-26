-- r548 (F162). Craig approved go-live 26 Oct 2026 13:44 AWST.
-- Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Ledger r546_read_once_snapshots and r547_read_once_snapshots were undone.
-- Open preview #516 holds r547 / F161 / sort 325. This is the next free id.
-- Craig, 26 Oct 2026: dragging Key 516 (stock 12329493, JC J138000668) from Bus 4x4
-- Unallocated onto Mechanical Bay 01 or 02 was refused. The toast named its own
-- unallocated bookings faf85955 (BUS_ELECTRICAL, queued, bay_id null) and
-- 4d9dc515 (BUS_QA, queued, bay_id null) as Bay 00. e72552d3 is the 82.60 h
-- BUS_MECHANICAL stoppage, also bay_id null.
--
-- Rule: a vehicle's own bookings with bay_id null never block placing that
-- vehicle. The dragged booking is booked into the chosen bay at that slot.
-- Its remaining unallocated bookings (queued or stoppage, bay_id null) are
-- then placed after that booking, still with no bay, in workshop order
-- Mechanical, Accessories, Electrical, QA, Pit. Each starts 60 working minutes
-- after the previous one ends, on the plain workshop calendar. A booking that
-- already has a bay still overlaps and is still refused. Work in another
-- vehicle's bay is unchanged.
--
-- On 26 Oct 2026, besides Key 516, 7 vehicles had a null-bay queued or stoppage
-- booking whose stored window overlaps another active booking of the same
-- vehicle: keys 148, 235, 344, 360 and 504, and stocks 13000779 and 13018396.
--
-- The overlap exemption is one predicate inside workshop_validate_booking.
-- The pin row stays the same row (count 241): r417 body
-- 9efb08f2415c28ac57a14b401cf9f605 moves in place to r548. Sort 323 is live
-- r545. This check is r548 / F162 / sort 324. Filename 20261026230000 sorts
-- after r545 (20261026200000) and the undone r547 file (20261026220000).
-- Sorts 319, 321, 322 and 325 stay with the open previews.
-- Undo: supabase/rollbacks/20261026230000_r548_unallocated_bay_rechain.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r548: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r548: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r548: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='vehicle_board_snapshot_cache_545' AND fault_id='F159' AND sort_order=323 AND added_in='r545') THEN RAISE EXCEPTION 'r548: r545 / F159 sort 323 is not the live check'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=324 OR fault_id='F162' OR check_name='unallocated_bay_rechain_548' OR added_in='r548') THEN RAISE EXCEPTION 'r548: sort 324 or F162 is taken'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='workshop_validate_booking'
       AND pg_get_function_identity_arguments(p.oid)='p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_scheduled_start_at timestamp with time zone, p_scheduled_end_at timestamp with time zone, p_duration_minutes integer, p_status workshop_booking_status, p_technician_id uuid, p_allow_unchanged_past boolean')
    IS DISTINCT FROM '9efb08f2415c28ac57a14b401cf9f605' THEN RAISE EXCEPTION 'r548: workshop_validate_booking is not the r417 body'; END IF;
 IF pg_catalog.to_regclass('pg_temp.r548_absent') IS NOT NULL THEN RAISE EXCEPTION 'r548: unexpected'; END IF;
END $g$;

CREATE FUNCTION pdc_bay_seq_private.place_unallocated_after_548(p_vehicle_id uuid, p_anchor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $place548$
DECLARE
 v_cursor timestamptz;
 r record;
 v_minutes integer;
 v_start timestamptz;
 v_end timestamptz;
 v_n integer;
BEGIN
 SELECT public.workshop_booking_effective_end_at(p_anchor) INTO v_cursor;
 IF v_cursor IS NULL THEN
  RAISE EXCEPTION 'r548: the placed booking has no end' USING ERRCODE = '22023';
 END IF;
 -- Lock in id order, then walk workshop order, so two placements of one vehicle cannot deadlock.
 PERFORM 1 FROM public.workshop_bookings b
 WHERE b.vehicle_id = p_vehicle_id
   AND b.id IS DISTINCT FROM p_anchor
   AND b.deleted_at IS NULL
   AND b.bay_id IS NULL
   AND b.status IN ('queued', 'stoppage')
 ORDER BY b.id
 FOR UPDATE;
 FOR r IN
  SELECT b.id, b.default_duration_minutes, b.work_category
  FROM public.workshop_bookings b
  WHERE b.vehicle_id = p_vehicle_id
    AND b.id IS DISTINCT FROM p_anchor
    AND b.deleted_at IS NULL
    AND b.bay_id IS NULL
    AND b.status IN ('queued', 'stoppage')
  ORDER BY CASE b.work_category
    WHEN 'BUS_MECHANICAL' THEN 1
    WHEN 'BUS_ACCESSORIES' THEN 2
    WHEN 'BUS_ELECTRICAL' THEN 3
    WHEN 'BUS_QA' THEN 4
    WHEN 'BUS_PIT' THEN 5
    ELSE 9 END, b.scheduled_start_at, b.id
 LOOP
  v_minutes := r.default_duration_minutes;
  IF v_minutes IS NULL OR v_minutes < 1 THEN
   RAISE EXCEPTION 'r548: unallocated booking % has no duration', left(r.id::text, 8) USING ERRCODE = '22023';
  END IF;
  v_start := public.workshop_admin_next_operational_minute(public.workshop_add_operational_minutes(v_cursor, 60));
  v_end := public.workshop_add_operational_minutes(v_start, v_minutes);
  IF v_start IS NULL OR v_end IS NULL OR v_end <= v_start OR v_start < v_cursor THEN
   RAISE EXCEPTION 'r548: no working time after the placed booking' USING ERRCODE = '22023';
  END IF;
  UPDATE public.workshop_bookings
  SET scheduled_start_at = v_start, scheduled_end_at = v_end, version = version + 1,
      updated_by = coalesce(auth.uid(), updated_by), updated_at = clock_timestamp()
  WHERE id = r.id AND bay_id IS NULL AND deleted_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
   RAISE EXCEPTION 'r548: unallocated booking % was not moved', left(r.id::text, 8) USING ERRCODE = '22023';
  END IF;
  SELECT public.workshop_booking_effective_end_at(r.id) INTO v_cursor;
  IF v_cursor IS NULL OR v_cursor < v_end THEN v_cursor := v_end; END IF;
 END LOOP;
END $place548$;
REVOKE ALL ON FUNCTION pdc_bay_seq_private.place_unallocated_after_548(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION pdc_bay_seq_private.rechain_unallocated_548()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $rechain548$
BEGIN
 -- A drag of an existing unallocated booking is an UPDATE of bay_id from null.
 -- A new booking inserted straight into a bay is an INSERT. Either one places
 -- the dragged work; the vehicle's other unallocated rows then follow it.
 IF NEW.bay_id IS NULL OR NEW.deleted_at IS NOT NULL THEN
  RETURN NULL;
 END IF;
 IF TG_OP = 'UPDATE' THEN
  IF OLD.bay_id IS NOT NULL THEN
   RETURN NULL;
  END IF;
 ELSIF TG_OP <> 'INSERT' THEN
  RETURN NULL;
 END IF;
 PERFORM pdc_bay_seq_private.place_unallocated_after_548(NEW.vehicle_id, NEW.id);
 RETURN NULL;
END $rechain548$;
REVOKE ALL ON FUNCTION pdc_bay_seq_private.rechain_unallocated_548() FROM PUBLIC, anon, authenticated, service_role;

-- UPDATE OF bay_id does not run on a clock-tick time write. INSERT cannot share that column list.
CREATE TRIGGER zz_pdc_rechain_unallocated_548
 AFTER UPDATE OF bay_id ON public.workshop_bookings
 FOR EACH ROW
 WHEN (OLD.bay_id IS NULL AND NEW.bay_id IS NOT NULL AND NEW.deleted_at IS NULL)
 EXECUTE FUNCTION pdc_bay_seq_private.rechain_unallocated_548();

CREATE TRIGGER zz_pdc_rechain_unallocated_ins_548
 AFTER INSERT ON public.workshop_bookings
 FOR EACH ROW
 WHEN (NEW.bay_id IS NOT NULL AND NEW.deleted_at IS NULL)
 EXECUTE FUNCTION pdc_bay_seq_private.rechain_unallocated_548();

-- One predicate. A same-vehicle booking blocks only when it already has a bay.
DO $patch$
DECLARE
 v_src text;
 v_sql text;
 v_args text := 'p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_scheduled_start_at timestamp with time zone, p_scheduled_end_at timestamp with time zone, p_duration_minutes integer, p_status workshop_booking_status, p_technician_id uuid, p_allow_unchanged_past boolean';
BEGIN
 SELECT p.prosrc INTO v_src
 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'workshop_validate_booking'
   AND pg_get_function_identity_arguments(p.oid) = v_args
   AND md5(p.prosrc) = '9efb08f2415c28ac57a14b401cf9f605';
 IF v_src IS NULL THEN RAISE EXCEPTION 'r548: validate body changed before the patch'; END IF;
 IF position('NOT (b.status=''queued'' AND b.bay_id IS NULL)' IN v_src) = 0 THEN RAISE EXCEPTION 'r548: queued-only exemption missing'; END IF;
 IF position('b.bay_id IS NOT NULL' IN v_src) <> 0 THEN RAISE EXCEPTION 'r548: bay exemption already present'; END IF;
 IF position('$r548val$' IN v_src) <> 0 THEN RAISE EXCEPTION 'r548: validate body contains the patch quote'; END IF;
 v_src := replace(v_src, 'NOT (b.status=''queued'' AND b.bay_id IS NULL)', 'b.bay_id IS NOT NULL');
 v_sql := 'CREATE OR REPLACE FUNCTION public.workshop_validate_booking(' || v_args || ') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'', ''extensions'' AS $r548val$' || v_src || '$r548val$';
 EXECUTE v_sql;
END $patch$;

DO $pin$
DECLARE v_n integer;
BEGIN
 UPDATE pdc_ops.expected_function_md5 AS pin
 SET prosrc_md5 = md5(p.prosrc), release = 'r548', note = 'r548: own unallocated bookings do not block a bay (F162)', updated_at = clock_timestamp()
 FROM pg_proc p
 JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'workshop_validate_booking'
   AND pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_scheduled_start_at timestamp with time zone, p_scheduled_end_at timestamp with time zone, p_duration_minutes integer, p_status workshop_booking_status, p_technician_id uuid, p_allow_unchanged_past boolean'
   AND pin.signature = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'
   AND pin.prosrc_md5 = '9efb08f2415c28ac57a14b401cf9f605'
   AND pin.release = 'r417';
 GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n <> 1 THEN RAISE EXCEPTION 'r548: validate pin was not moved'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r548: pin count changed'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5
     WHERE signature = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)')
    IS DISTINCT FROM 'r548' THEN RAISE EXCEPTION 'r548: validate pin release is not r548'; END IF;
END $pin$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('unallocated_bay_rechain_548', 'F162',
 'Placing a vehicle ignores its own bay_id null bookings and rechains those queued and stoppage rows after the placed booking in Mechanical, Electrical, QA order. A booking that already has a bay still overlaps. A missing bay is not labelled Bay 00. Pin count stays 241.',
 $chk548$
SELECT
  pins.n = 241
  AND pin.release = 'r548'
  AND pin.prosrc_md5 = md5(body.prosrc)
  AND position('NOT (b.status=''queued'' AND b.bay_id IS NULL)' IN body.prosrc) = 0
  AND position('and b.bay_id IS NOT NULL' IN body.prosrc) > 0
  AND position('vehicle_overlap' IN body.prosrc) > 0
  AND position('bay_overlap' IN body.prosrc) > 0
  AND position('Bay 00' IN body.prosrc) = 0
  AND trg.present
  AND trg.insert_present
  AND position('BUS_MECHANICAL' IN chain.prosrc) > 0
  AND position('BUS_ELECTRICAL' IN chain.prosrc) > 0
  AND position('BUS_QA' IN chain.prosrc) > 0
  AND position('bay_id IS NULL' IN chain.prosrc) > 0
  AND position('Bay 00' IN chain.prosrc) = 0
  AND position('UPDATE public.workshop_bookings' IN chain.prosrc) > 0
 AS ok,
 format('pins %s release %s predicate %s triggers %s/%s',
   pins.n, pin.release,
   position('and b.bay_id IS NOT NULL' IN body.prosrc) > 0,
   trg.present, trg.insert_present) AS detail
FROM (SELECT count(*)::integer AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (
  SELECT prosrc_md5, release FROM pdc_ops.expected_function_md5
  WHERE signature = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'
) pin
CROSS JOIN (
  SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'workshop_validate_booking'
    AND pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_scheduled_start_at timestamp with time zone, p_scheduled_end_at timestamp with time zone, p_duration_minutes integer, p_status public.workshop_booking_status, p_technician_id uuid, p_allow_unchanged_past boolean'
) body
CROSS JOIN (
  SELECT
    EXISTS (
      SELECT 1 FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'workshop_bookings' AND t.tgname = 'zz_pdc_rechain_unallocated_548' AND NOT t.tgisinternal
    ) AS present,
    EXISTS (
      SELECT 1 FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'workshop_bookings' AND t.tgname = 'zz_pdc_rechain_unallocated_ins_548' AND NOT t.tgisinternal
    ) AS insert_present
) trg
CROSS JOIN (
  SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_bay_seq_private' AND p.proname = 'place_unallocated_after_548'
    AND pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid, p_anchor uuid'
) chain
$chk548$,
 true, 324, 'r548');

DO $chk$
DECLARE v_ok boolean; v_detail text;
BEGIN
 PERFORM set_config('search_path', 'pg_catalog', true);
 SELECT ok, detail INTO v_ok, v_detail FROM pdc_ops.fault_regression_check() WHERE check_name = 'unallocated_bay_rechain_548';
 IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'r548: unallocated_bay_rechain_548 failed: %', coalesce(v_detail, 'no row'); END IF;
END $chk$;
