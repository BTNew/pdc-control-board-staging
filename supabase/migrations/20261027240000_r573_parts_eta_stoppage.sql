-- r581 (F194) / sort 352. Go-live. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
--
-- The preview claimed r573 / F187 / sort 344. That triple is
-- hours_description_fits_573. r577 is on the ledger from the rolled-back
-- bay-manager hours release. r578 stays free for a later queue. r579 / F192 /
-- sort 350 is bay_code_identity_579. r580 (F193) / sort 351 was applied and
-- rolled back: the stored check compared the pin total to 241, and
-- regression_checks_self_test went red. r580 stays on the ledger. F193 and
-- sort 351 stay unused. F191 and sort 349 stay free for the bay-manager
-- rework. Object names and the check name stay _573.
-- The stored check reports the pin count. It does not compare that count to a
-- number. The opening guard and the proof block still require 241.
--
-- r567 (F181, sort 338) already stores one manual parts ETA and note per vehicle
-- in pdc_parts_stoppage_564. This release does not replace that. It adds the
-- choice to place that ETA as a vehicle STOPPAGE until 06:00 Perth on the ETA
-- date. Clearing the ETA, or receiving the parts, ends it. Later jobs of this
-- vehicle are pushed back. A raw exclusion error is not returned.
-- A stoppage occupies the vehicle through workshop_bookings_active_vehicle_no_overlap
-- even with no bay. The row uses the PARTS stage and a null bay, so it is not a
-- fitting-bay chip. The planner lists it in the Stoppage section.
-- Pin count stays 241. No pin row is inserted. set_pdc_parts_stoppage_564 is not
-- edited. Department 135 functions are not edited.
-- Undo: supabase/rollbacks/20261027240000_r573_parts_eta_stoppage.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r573: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r573: staging only'; END IF;
 IF EXISTS (SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE project_ref='vjdtsswhroyguxyfjdkt') THEN RAISE EXCEPTION 'r573: production ref'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r573: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_stoppage_manual_567' AND fault_id='F181' AND sort_order=338 AND added_in='r567') THEN RAISE EXCEPTION 'r573: r567 / F181 sort 338 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_card_stack_572' AND fault_id='F186' AND sort_order=342 AND added_in='r572') THEN RAISE EXCEPTION 'r573: r572 / F186 sort 342 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=352 OR fault_id='F194' OR check_name='parts_eta_stoppage_573' OR added_in='r581') THEN RAISE EXCEPTION 'r573: sort 352 or F194 is taken'; END IF;
 IF pg_catalog.to_regprocedure('public.place_parts_eta_stoppage_573(uuid,date,text,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'r573: already applied'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')) IS DISTINCT FROM 'fa275b45be296e9021f9f4dc570f5751' THEN RAISE EXCEPTION 'r573: set_pdc_parts_stoppage_564 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r573: set_parts_eta changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '83a2c8d5ff85b5a295343e5f3ef66ded' THEN RAISE EXCEPTION 'r573: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r573: department 135 move changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='karratha135_pdc' AND p.proname='workshop_create_booking' AND pg_get_function_identity_arguments(p.oid)='p_vehicle_id uuid, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_metadata jsonb') IS DISTINCT FROM '8976b0adba341dc35723bab724ff0f1e' THEN RAISE EXCEPTION 'r573: department 135 create changed'; END IF;
END $g$;

ALTER TABLE public.pdc_parts_stoppage_564
  ADD COLUMN placed_stoppage boolean NOT NULL DEFAULT false,
  ADD COLUMN stoppage_booking_id uuid;

ALTER TABLE public.pdc_parts_stoppage_audit_564 DROP CONSTRAINT pdc_parts_stoppage_audit_564_action_check;
ALTER TABLE public.pdc_parts_stoppage_audit_564
  ADD CONSTRAINT pdc_parts_stoppage_audit_564_action_check
  CHECK (action IN ('set', 'clear', 'check', 'place', 'lift'));

CREATE FUNCTION public.end_parts_eta_stoppage_573(p_vehicle_id uuid, p_reason text, p_actor text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $end573$
DECLARE
  v_role text := public.current_pdc_user_role()::text;
  v_uid uuid := auth.uid();
  v_actor text := left(coalesce(nullif(btrim(coalesce(p_actor, '')), ''), nullif(btrim(coalesce(auth.jwt()->>'email', '')), ''), v_uid::text, 'parts received'), 200);
  v_why text := left(coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Parts ETA stoppage lifted'), 180);
  v_row public.pdc_parts_stoppage_564%ROWTYPE;
  v_book uuid;
  v_stock text;
BEGIN
  -- r573 (F187): end the parts-ETA stoppage. Called on lift, on a cleared manual ETA, and when parts_received becomes true.
  IF p_vehicle_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vehicle_not_found', 'code', 'vehicle_not_found');
  END IF;
  IF v_role IS DISTINCT FROM 'importer' AND v_role IS DISTINCT FROM 'operator' AND v_role IS DISTINCT FROM 'administrator' THEN
    v_role := 'operator';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc:workshop:top-level-mutation', 0));
  SELECT * INTO v_row FROM public.pdc_parts_stoppage_564 WHERE vehicle_id = p_vehicle_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'changed', false, 'action', 'lift');
  END IF;
  v_stock := v_row.stock_number;
  v_book := v_row.stoppage_booking_id;
  IF v_book IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.workshop_bookings b
     WHERE b.id = v_book AND b.deleted_at IS NULL AND b.status = 'stoppage'
  ) THEN
    SELECT b.id INTO v_book
      FROM public.workshop_bookings b
     WHERE b.vehicle_id = p_vehicle_id
       AND b.deleted_at IS NULL
       AND b.status = 'stoppage'
       AND b.metadata->>'source' = 'parts_eta_stoppage_573'
     ORDER BY b.created_at DESC
     LIMIT 1;
  END IF;
  IF v_book IS NULL AND v_row.placed_stoppage IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', true, 'changed', false, 'action', 'lift');
  END IF;
  IF v_book IS NOT NULL THEN
    UPDATE public.workshop_bookings
       SET status = 'deleted',
           deleted_at = clock_timestamp(),
           deleted_reason = v_why,
           updated_by = coalesce(v_uid, updated_by),
           updated_at = clock_timestamp(),
           version = version + 1
     WHERE id = v_book
       AND deleted_at IS NULL
       AND status = 'stoppage';
  END IF;
  UPDATE public.pdc_parts_stoppage_564
     SET placed_stoppage = false,
         stoppage_booking_id = NULL
   WHERE vehicle_id = p_vehicle_id
     AND (placed_stoppage OR stoppage_booking_id IS NOT NULL);
  INSERT INTO public.pdc_parts_stoppage_audit_564
    (vehicle_id, stock_number, action, old_eta, new_eta, old_note, new_note, last_checked_on, actor_id, actor, actor_role)
  VALUES
    (p_vehicle_id, v_stock, 'lift', v_row.eta_date, v_row.eta_date, v_row.note, v_row.note, v_row.last_checked_on, v_uid, v_actor, v_role);
  RETURN jsonb_build_object('ok', true, 'changed', true, 'action', 'lift', 'booking_id', v_book);
END
$end573$;

REVOKE ALL ON FUNCTION public.end_parts_eta_stoppage_573(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_parts_eta_stoppage_573(uuid, text, text) TO authenticated;

CREATE FUNCTION public.parts_eta_stoppage_573_on_manual()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $manual573$
DECLARE
  v_actor text;
BEGIN
  IF pg_catalog.pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;
  IF NEW.placed_stoppage IS NOT TRUE THEN
    RETURN NEW;
  END IF;
  IF NEW.active IS TRUE AND NEW.eta_date IS NOT NULL THEN
    RETURN NEW;
  END IF;
  v_actor := coalesce(nullif(btrim(coalesce(auth.jwt()->>'email', '')), ''), 'parts cleared');
  PERFORM public.end_parts_eta_stoppage_573(NEW.vehicle_id, 'Parts ETA cleared', v_actor);
  RETURN NEW;
END
$manual573$;

CREATE TRIGGER trg_parts_eta_stoppage_573_manual
AFTER UPDATE ON public.pdc_parts_stoppage_564
FOR EACH ROW
EXECUTE FUNCTION public.parts_eta_stoppage_573_on_manual();

CREATE FUNCTION public.parts_eta_stoppage_573_on_received()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $recv573$
BEGIN
  IF pg_catalog.pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;
  IF NEW.parts_received IS TRUE AND OLD.parts_received IS DISTINCT FROM TRUE THEN
    PERFORM public.end_parts_eta_stoppage_573(NEW.vehicle_id, 'Parts received', 'parts received');
  END IF;
  RETURN NEW;
END
$recv573$;

CREATE TRIGGER trg_parts_eta_stoppage_573_received
AFTER UPDATE OF parts_received ON public.vehicle_parts_updates
FOR EACH ROW
WHEN (NEW.parts_received IS TRUE AND OLD.parts_received IS DISTINCT FROM TRUE)
EXECUTE FUNCTION public.parts_eta_stoppage_573_on_received();

CREATE FUNCTION public.place_parts_eta_stoppage_573(p_vehicle_id uuid, p_eta date, p_note text, p_place boolean)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $place573$
DECLARE
  v_role text := public.current_pdc_user_role()::text;
  v_uid uuid := auth.uid();
  v_actor text := left(coalesce(nullif(btrim(coalesce(auth.jwt()->>'email', '')), ''), v_uid::text, 'unknown'), 200);
  v_today date := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date;
  v_note text;
  v_eta date;
  v_stock text;
  v_key text;
  v_start timestamptz;
  v_end timestamptz;
  v_floor timestamptz;
  v_blocker uuid;
  v_stage uuid;
  v_mins integer;
  v_reason text;
  v_meta jsonb;
  v_existing uuid;
  v_linked uuid;
  v_has_row boolean := false;
  v_old_eta date;
  v_old_note text;
  v_row public.pdc_parts_stoppage_564%ROWTYPE;
  v_cursor timestamptz;
  v_new_end timestamptz;
  v_chain timestamptz;
  v_count integer := 0;
  v_pass integer := 0;
  v_hit record;
  rec record;
BEGIN
  -- r573 (F187): place or lift a parts ETA as a vehicle STOPPAGE. Later jobs move back. exclusion_violation becomes push_failed.
  IF pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'staging_only', 'code', 'staging_only');
  END IF;
  IF v_uid IS NULL OR (v_role IS DISTINCT FROM 'importer' AND v_role IS DISTINCT FROM 'operator' AND v_role IS DISTINCT FROM 'administrator') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authorized', 'code', 'not_authorized');
  END IF;
  IF p_vehicle_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vehicle_not_found', 'code', 'vehicle_not_found');
  END IF;
  IF coalesce(p_place, false) IS NOT TRUE THEN
    RETURN public.end_parts_eta_stoppage_573(p_vehicle_id, 'Place as STOPPAGE lifted', v_actor);
  END IF;
  SELECT upper(btrim(coalesce(v.stock_number, ''))), nullif(btrim(coalesce(v.key_number, '')), '')
    INTO v_stock, v_key
    FROM public.vehicles v
   WHERE v.id = p_vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vehicle_not_found', 'code', 'vehicle_not_found');
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc:workshop:top-level-mutation', 0));
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc_parts_stoppage_564:' || p_vehicle_id::text, 0));
  SELECT * INTO v_row FROM public.pdc_parts_stoppage_564 WHERE vehicle_id = p_vehicle_id FOR UPDATE;
  v_has_row := FOUND;
  IF v_has_row THEN
    v_linked := v_row.stoppage_booking_id;
    v_old_eta := v_row.eta_date;
    v_old_note := v_row.note;
  END IF;
  v_note := nullif(regexp_replace(btrim(coalesce(p_note, CASE WHEN v_has_row THEN v_row.note ELSE '' END, '')), '\s+', ' ', 'g'), '');
  IF v_note IS NOT NULL AND (length(v_note) > 180 OR v_note ~ '[[:cntrl:]]') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'note_too_long', 'code', 'note_too_long');
  END IF;
  v_eta := coalesce(p_eta, CASE WHEN v_has_row AND v_row.active THEN v_row.eta_date ELSE NULL END);
  IF v_eta IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'eta_required', 'code', 'eta_required');
  END IF;
  IF v_eta < v_today - 366 OR v_eta > v_today + 366 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'eta_date_out_of_range', 'code', 'eta_date_out_of_range');
  END IF;
  v_start := date_trunc('minute', clock_timestamp());
  v_end := (v_eta + time '06:00') AT TIME ZONE 'Australia/Perth';
  IF v_end <= v_start THEN
    RETURN jsonb_build_object('ok', false, 'error', 'eta_reached', 'code', 'eta_reached');
  END IF;
  SELECT b.id,
         CASE
           WHEN public.workshop_booking_effective_end_at(b.id) IS NULL THEN b.scheduled_end_at
           WHEN public.workshop_booking_effective_end_at(b.id) > b.scheduled_end_at THEN public.workshop_booking_effective_end_at(b.id)
           ELSE b.scheduled_end_at
         END
    INTO v_blocker, v_floor
    FROM public.workshop_bookings b
   WHERE b.vehicle_id = p_vehicle_id
     AND b.deleted_at IS NULL
     AND NOT b.legacy_ambiguity_quarantined
     AND b.status = 'started'
     AND b.scheduled_start_at < v_end
     AND b.scheduled_end_at > v_start
   ORDER BY 2 DESC
   LIMIT 1;
  IF v_floor IS NOT NULL AND v_floor >= v_end THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vehicle_running', 'code', 'vehicle_running', 'booking_id', v_blocker);
  END IF;
  IF v_floor IS NOT NULL AND v_floor > v_start THEN
    v_start := v_floor;
  END IF;
  IF v_end <= v_start THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vehicle_running', 'code', 'vehicle_running', 'booking_id', v_blocker);
  END IF;
  SELECT s.id INTO v_stage FROM public.workshop_stages s WHERE s.code = 'PARTS' LIMIT 1;
  IF v_stage IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'stage_missing', 'code', 'stage_missing');
  END IF;
  v_mins := public.workshop_operational_minutes_between(v_start, v_end);
  IF v_mins IS NULL OR v_mins < 1 THEN
    v_mins := 1;
  END IF;
  v_reason := left('STOPPAGE · Parts ETA ' || to_char(v_eta, 'DD/MM/YY') || CASE WHEN v_note IS NULL THEN '' ELSE ' · ' || v_note END, 180);
  v_meta := jsonb_build_object('source', 'parts_eta_stoppage_573', 'eta', v_eta, 'note', v_note, 'actor', v_actor);
  SELECT b.id INTO v_existing
    FROM public.workshop_bookings b
   WHERE b.vehicle_id = p_vehicle_id
     AND b.deleted_at IS NULL
     AND b.status = 'stoppage'
     AND (
       b.id = v_linked
       OR b.metadata->>'source' = 'parts_eta_stoppage_573'
     )
   ORDER BY CASE WHEN b.id = v_linked THEN 0 ELSE 1 END, b.created_at DESC
   LIMIT 1;

  BEGIN
    CREATE TEMP TABLE IF NOT EXISTS parts_eta_stoppage_573_move (
      id uuid PRIMARY KEY,
      old_start timestamptz NOT NULL,
      new_start timestamptz NOT NULL,
      new_end timestamptz NOT NULL,
      bay_id uuid,
      vehicle_id uuid NOT NULL,
      minutes integer NOT NULL
    ) ON COMMIT DROP;
    DELETE FROM parts_eta_stoppage_573_move WHERE id IS NOT NULL OR id IS NULL;
    v_cursor := v_end;
    FOR rec IN
      SELECT b.id, b.scheduled_start_at, b.bay_id, b.vehicle_id,
             greatest(coalesce(b.default_duration_minutes, 1), 1) AS minutes
        FROM public.workshop_bookings b
       WHERE b.vehicle_id = p_vehicle_id
         AND b.deleted_at IS NULL
         AND NOT b.legacy_ambiguity_quarantined
         AND b.id IS DISTINCT FROM v_existing
         AND (b.status IN ('planned', 'stoppage') OR (b.status = 'queued' AND b.bay_id IS NOT NULL))
         AND b.scheduled_start_at < v_end
         AND b.scheduled_end_at > v_start
       ORDER BY b.scheduled_start_at, b.id
    LOOP
      v_new_end := public.workshop_add_operational_minutes(v_cursor, rec.minutes);
      IF v_new_end IS NULL OR v_new_end <= v_cursor THEN
        v_new_end := v_cursor + interval '1 minute';
      END IF;
      INSERT INTO parts_eta_stoppage_573_move (id, old_start, new_start, new_end, bay_id, vehicle_id, minutes)
      VALUES (rec.id, rec.scheduled_start_at, v_cursor, v_new_end, rec.bay_id, rec.vehicle_id, rec.minutes);
      v_cursor := v_new_end;
      v_count := v_count + 1;
      IF v_count > 40 THEN
        RAISE EXCEPTION 'parts_eta_stoppage_573:push_cap';
      END IF;
    END LOOP;

    WHILE v_pass < 12 LOOP
      v_pass := v_pass + 1;
      SELECT o.id, o.scheduled_start_at, o.scheduled_end_at, o.bay_id, o.vehicle_id, o.status,
             greatest(coalesce(o.default_duration_minutes, 1), 1) AS minutes
        INTO v_hit
        FROM public.workshop_bookings o
        JOIN parts_eta_stoppage_573_move m
          ON o.id <> m.id
         AND o.deleted_at IS NULL
         AND NOT o.legacy_ambiguity_quarantined
         AND o.id IS DISTINCT FROM v_existing
         AND o.scheduled_start_at < m.new_end
         AND o.scheduled_end_at > m.new_start
         AND (
           (o.bay_id IS NOT NULL AND o.bay_id = m.bay_id AND o.status IN ('planned', 'started', 'stoppage'))
           OR (o.vehicle_id = m.vehicle_id AND (o.status IN ('planned', 'stoppage', 'started') OR (o.status = 'queued' AND o.bay_id IS NOT NULL)))
         )
        LEFT JOIN parts_eta_stoppage_573_move already ON already.id = o.id
       WHERE already.id IS NULL
       ORDER BY o.scheduled_start_at, o.id
       LIMIT 1;
      EXIT WHEN NOT FOUND;
      IF v_hit.status = 'started' AND v_hit.vehicle_id = p_vehicle_id THEN
        RAISE EXCEPTION 'parts_eta_stoppage_573:vehicle_running:%', v_hit.id;
      END IF;
      IF v_hit.status = 'started' THEN
        RAISE EXCEPTION 'parts_eta_stoppage_573:bay_running:%', v_hit.id;
      END IF;
      IF v_count >= 40 THEN
        RAISE EXCEPTION 'parts_eta_stoppage_573:push_cap';
      END IF;
      SELECT max(m.new_end) INTO v_chain
        FROM parts_eta_stoppage_573_move m
       WHERE (m.vehicle_id = v_hit.vehicle_id OR (m.bay_id IS NOT NULL AND m.bay_id = v_hit.bay_id))
         AND m.new_end > v_hit.scheduled_start_at;
      IF v_chain IS NULL THEN
        v_chain := v_end;
      END IF;
      v_new_end := public.workshop_add_operational_minutes(v_chain, v_hit.minutes);
      IF v_new_end IS NULL OR v_new_end <= v_chain THEN
        v_new_end := v_chain + interval '1 minute';
      END IF;
      INSERT INTO parts_eta_stoppage_573_move (id, old_start, new_start, new_end, bay_id, vehicle_id, minutes)
      VALUES (v_hit.id, v_hit.scheduled_start_at, v_chain, v_new_end, v_hit.bay_id, v_hit.vehicle_id, v_hit.minutes);
      v_count := v_count + 1;
    END LOOP;

    FOR rec IN
      SELECT id, old_start, new_start, new_end, minutes
        FROM parts_eta_stoppage_573_move
       ORDER BY old_start DESC, id DESC
    LOOP
      UPDATE public.workshop_bookings
         SET scheduled_start_at = rec.new_start,
             scheduled_end_at = rec.new_end,
             default_duration_minutes = rec.minutes,
             updated_by = v_uid,
             updated_at = clock_timestamp(),
             version = version + 1
       WHERE id = rec.id
         AND deleted_at IS NULL
         AND status <> 'started'
         AND status IN ('planned', 'stoppage', 'queued');
      IF NOT FOUND THEN
        RAISE EXCEPTION 'parts_eta_stoppage_573:push_cap';
      END IF;
    END LOOP;

    IF v_existing IS NOT NULL THEN
      UPDATE public.workshop_bookings
         SET stage_id = v_stage,
             bay_id = NULL,
             status = 'stoppage',
             scheduled_start_at = v_start,
             scheduled_end_at = v_end,
             default_duration_minutes = v_mins,
             actual_start_at = v_start,
             stoppage_started_at = v_start,
             stoppage_reason = v_reason,
             eta_at_booking = v_eta,
             source = 'parts_eta_stoppage_573',
             metadata = v_meta,
             updated_by = v_uid,
             updated_at = clock_timestamp(),
             version = version + 1
       WHERE id = v_existing
         AND vehicle_id = p_vehicle_id
         AND deleted_at IS NULL;
      IF NOT FOUND THEN
        v_existing := NULL;
      END IF;
    END IF;
    IF v_existing IS NULL THEN
      INSERT INTO public.workshop_bookings (
        vehicle_id, stage_id, bay_id, status, scheduled_start_at, scheduled_end_at,
        default_duration_minutes, actual_start_at, stoppage_started_at, stoppage_reason,
        eta_at_booking, source, metadata, created_by, updated_by, eta_risk_status,
        legacy_ambiguity_quarantined, stoppage_accumulated_minutes
      ) VALUES (
        p_vehicle_id, v_stage, NULL, 'stoppage', v_start, v_end,
        v_mins, v_start, v_start, v_reason,
        v_eta, 'parts_eta_stoppage_573', v_meta, v_uid, v_uid, 'none',
        false, 0
      )
      RETURNING id INTO v_existing;
    END IF;

    IF v_has_row THEN
      UPDATE public.pdc_parts_stoppage_564
         SET stock_number = v_stock,
             eta_date = v_eta,
             note = v_note,
             last_checked_on = v_today,
             active = true,
             placed_stoppage = true,
             stoppage_booking_id = v_existing,
             set_at = clock_timestamp(),
             set_by = v_uid,
             set_by_actor = v_actor,
             set_by_role = v_role
       WHERE vehicle_id = p_vehicle_id;
    ELSE
      INSERT INTO public.pdc_parts_stoppage_564 (
        vehicle_id, stock_number, eta_date, note, last_checked_on, active,
        set_by, set_by_actor, set_by_role, placed_stoppage, stoppage_booking_id
      ) VALUES (
        p_vehicle_id, v_stock, v_eta, v_note, v_today, true,
        v_uid, v_actor, v_role, true, v_existing
      );
    END IF;
    INSERT INTO public.pdc_parts_stoppage_audit_564
      (vehicle_id, stock_number, action, old_eta, new_eta, old_note, new_note, last_checked_on, actor_id, actor, actor_role)
    VALUES
      (p_vehicle_id, v_stock, 'place', v_old_eta, v_eta, v_old_note, v_note, v_today, v_uid, v_actor, v_role);
  EXCEPTION
    WHEN exclusion_violation THEN
      RETURN jsonb_build_object('ok', false, 'error', 'push_failed', 'code', 'push_failed');
    WHEN raise_exception THEN
      IF pg_catalog.strpos(SQLERRM, 'parts_eta_stoppage_573:bay_running:') = 1 THEN
        RETURN jsonb_build_object('ok', false, 'error', 'bay_running', 'code', 'bay_running', 'booking_id', pg_catalog.split_part(SQLERRM, ':', 3));
      ELSIF pg_catalog.strpos(SQLERRM, 'parts_eta_stoppage_573:vehicle_running:') = 1 THEN
        RETURN jsonb_build_object('ok', false, 'error', 'vehicle_running', 'code', 'vehicle_running', 'booking_id', pg_catalog.split_part(SQLERRM, ':', 3));
      ELSIF pg_catalog.strpos(SQLERRM, 'parts_eta_stoppage_573:push_cap') = 1 THEN
        RETURN jsonb_build_object('ok', false, 'error', 'push_failed', 'code', 'push_failed');
      ELSE
        RAISE;
      END IF;
  END;

  RETURN jsonb_build_object(
    'ok', true, 'changed', true, 'action', 'place', 'booking_id', v_existing,
    'eta_date', v_eta, 'note', v_note, 'reason', v_reason, 'until', v_end,
    'pushed', v_count, 'stock_number', v_stock, 'key_number', v_key, 'set_by_actor', v_actor
  );
END
$place573$;

REVOKE ALL ON FUNCTION public.place_parts_eta_stoppage_573(uuid, date, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_parts_eta_stoppage_573(uuid, date, text, boolean) TO authenticated;

CREATE FUNCTION public.get_pdc_parts_eta_stoppage_board_573()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $board573$
  -- r573 (F187): planner Stoppage section. One row per placed parts ETA. Board readers only.
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false) THEN
    jsonb_build_object('ok', false, 'code', 'not_authorized', 'vehicles', '[]'::jsonb)
  ELSE
    jsonb_build_object('ok', true, 'vehicles', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'vehicle_id', s.vehicle_id,
        'stock_number', s.stock_number,
        'key_number', v.key_number,
        'eta_date', s.eta_date,
        'note', s.note,
        'reason', b.stoppage_reason,
        'booking_id', b.id,
        'until', b.scheduled_end_at,
        'set_by_actor', s.set_by_actor
      ) ORDER BY s.stock_number)
      FROM public.pdc_parts_stoppage_564 s
      JOIN public.vehicles v ON v.id = s.vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
      JOIN public.workshop_bookings b ON b.id = s.stoppage_booking_id
        AND b.deleted_at IS NULL
        AND b.status = 'stoppage'
        AND b.metadata->>'source' = 'parts_eta_stoppage_573'
      WHERE s.active AND s.placed_stoppage
    ), '[]'::jsonb))
  END
$board573$;

REVOKE ALL ON FUNCTION public.get_pdc_parts_eta_stoppage_board_573() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_parts_eta_stoppage_board_573() TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('parts_eta_stoppage_573', 'F194',
 'Parts ETA placed as STOPPAGE (r581): runs until 06:00 Perth on the ETA, a clear or parts received lifts it, later jobs are pushed, a vehicle stoppage still occupies the vehicle, pins stay 241, and department 135 is unchanged',
 $chk573$
WITH reported_faults AS (
  SELECT
    (SELECT count(*) FROM pg_catalog.pg_proc p
      WHERE p.oid = pg_catalog.to_regprocedure('public.place_parts_eta_stoppage_573(uuid,date,text,boolean)')
        AND p.prosecdef
        AND pg_catalog.strpos(coalesce(pg_catalog.array_to_string(p.proconfig, ','), ''), 'pg_catalog') > 0) = 1 AS place_fn,
    (SELECT count(*) FROM pg_catalog.pg_proc p
      WHERE p.oid IN (
        pg_catalog.to_regprocedure('public.end_parts_eta_stoppage_573(uuid,text,text)'),
        pg_catalog.to_regprocedure('public.get_pdc_parts_eta_stoppage_board_573()'),
        pg_catalog.to_regprocedure('public.parts_eta_stoppage_573_on_manual()'),
        pg_catalog.to_regprocedure('public.parts_eta_stoppage_573_on_received()'))
        AND p.prosecdef) = 4 AS helpers,
    NOT EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release = 'r581') AS no_new_pin,
    (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')) = 'fa275b45be296e9021f9f4dc570f5751' AS manual_unchanged,
    (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) = '88d31cbd6ca5ddd372e3143d5f8c013f' AS email_unchanged,
    (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) = '83a2c8d5ff85b5a295343e5f3ef66ded' AS clock_unchanged,
    (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) = '4eb5baf999b849d174880a1e261fcbf2' AS dept135_move,
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'karratha135_pdc' AND p.proname = 'workshop_create_booking') = '8976b0adba341dc35723bab724ff0f1e' AS dept135_create
), body AS (
  SELECT pg_catalog.string_agg(p.prosrc, E'\n') AS prosrc
  FROM pg_catalog.pg_proc p
  WHERE p.oid IN (
    pg_catalog.to_regprocedure('public.place_parts_eta_stoppage_573(uuid,date,text,boolean)'),
    pg_catalog.to_regprocedure('public.end_parts_eta_stoppage_573(uuid,text,text)'),
    pg_catalog.to_regprocedure('public.parts_eta_stoppage_573_on_manual()'),
    pg_catalog.to_regprocedure('public.parts_eta_stoppage_573_on_received()'))
), rule AS (
  SELECT pg_catalog.pg_get_constraintdef(c.oid) AS def
  FROM pg_catalog.pg_constraint c
  WHERE c.conname = 'workshop_bookings_active_vehicle_no_overlap'
    AND c.conrelid = 'public.workshop_bookings'::regclass
)
SELECT (SELECT place_fn AND helpers AND no_new_pin AND manual_unchanged AND email_unchanged AND clock_unchanged AND dept135_move AND dept135_create FROM reported_faults)
  AND (SELECT pg_catalog.strpos(prosrc, 'stoppage') > 0
    AND pg_catalog.strpos(prosrc, 'Australia/Perth') > 0
    AND pg_catalog.strpos(prosrc, 'workshop_add_operational_minutes') > 0
    AND pg_catalog.strpos(prosrc, 'exclusion_violation') > 0
    AND pg_catalog.strpos(prosrc, 'pdc_parts_stoppage_audit_564') > 0
    AND pg_catalog.strpos(prosrc, 'parts_received') > 0
    AND pg_catalog.strpos(prosrc, 'lift') > 0
    AND pg_catalog.strpos(prosrc, 'UPDATE public.vehicles') = 0
    AND pg_catalog.strpos(prosrc, 'karratha135') = 0 FROM body)
  AND (SELECT pg_catalog.strpos(def, 'stoppage') > 0
    AND pg_catalog.strpos(def, 'queued') > 0
    AND pg_catalog.strpos(def, 'bay_id IS NULL') > 0 FROM rule) AS ok,
  'pins '||(SELECT count(*) FROM pdc_ops.expected_function_md5)||' place '||coalesce((SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.place_parts_eta_stoppage_573(uuid,date,text,boolean)')), 'missing') AS detail
$chk573$,
true, 352, 'r581');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r573: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r581') THEN RAISE EXCEPTION 'r573: a pin was inserted'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')) IS DISTINCT FROM 'fa275b45be296e9021f9f4dc570f5751' THEN RAISE EXCEPTION 'r573: manual set changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '83a2c8d5ff85b5a295343e5f3ef66ded' THEN RAISE EXCEPTION 'r573: clock tick changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='parts_eta_stoppage_573' AND fault_id='F194' AND sort_order=352 AND added_in='r581' AND enabled)<>1 THEN RAISE EXCEPTION 'r573: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog, public',true);
 PERFORM set_config('request.jwt.claims','',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_eta_stoppage_573' AND fault_id='F194' AND sort_order=352 AND added_in='r581') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r573: check parts_eta_stoppage_573 not OK: %', y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
