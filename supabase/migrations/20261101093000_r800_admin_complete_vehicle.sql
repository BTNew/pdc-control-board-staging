-- r800 (F415) / sort 580. Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 08:37 AWST: "give me the option, for admins to override
-- and complete vehicles to remove them to completed vehicles."
--   * public.admin_complete_vehicle_800(vehicle, expected version, stock typed to confirm, reason, idempotency key):
--     administrators only. Marks an active or RFT car completed exactly as the Navision delivery rule does (reconcile_navision_delivery_734):
--     lifecycle completed, location Completed, off the board, PMB fields cleared, location override cleared, queued/planned/stoppage
--     bookings cancelled (a started booking must be finished first), pending New Vehicles review closed, Navision activation closed,
--     a vehicle_movements row and an audit event. The override is recorded in source_payload.admin_completed_800.
--   * board_every_stock_674 leaves an admin-completed car alone (same place as the r791/r796 Navision rule), so the next service
--     upload does not put it back into New Vehicles while its Revolution job card is still open.
-- Rollback: supabase/rollbacks/20261101093000_r800_admin_complete_vehicle.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.board_every_stock_674(uuid,boolean)@r800pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $g$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r800: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 580 OR fault_id = 'F415' OR added_in = 'r800') THEN RAISE EXCEPTION 'r800: sort 580 or F415 is taken'; END IF;
  IF to_regprocedure('public.admin_complete_vehicle_800(uuid,integer,text,text,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r800: already applied'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r800: an import job is running'; END IF;
END $g$;

CREATE FUNCTION public.admin_complete_vehicle_800(p_vehicle_id uuid, p_expected_version integer, p_confirmation_stock text, p_reason text, p_idempotency_key uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'extensions'
SET statement_timeout TO '60s'
AS $function$
DECLARE
  uid uuid := auth.uid(); actor_email text := lower(btrim(coalesce(auth.jwt()->>'email', '')));
  v public.vehicles%rowtype; b public.workshop_bookings%rowtype; booking_result jsonb; cancelled integer := 0;
  reason text := btrim(coalesce(p_reason, '')); done_at timestamptz := clock_timestamp();
  prior jsonb; before_state jsonb; after_state jsonb; movement uuid; reviews integer := 0; from_location text;
BEGIN
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_version IS NULL OR p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'code', 'invalid_input'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id = uid AND lower(r.email) = actor_email AND r.active AND r.account_status = 'approved' AND r.role = 'administrator') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'administrator_required');
  END IF;
  IF length(reason) < 3 THEN RETURN jsonb_build_object('ok', false, 'code', 'reason_required'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop:vehicle:' || p_vehicle_id::text, 0));
  SELECT * INTO v FROM public.vehicles WHERE id = p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found'); END IF;
  prior := v.source_payload->'admin_completed_800';
  IF prior IS NOT NULL AND prior->>'idempotency_key' = p_idempotency_key::text THEN
    RETURN jsonb_build_object('ok', true, 'code', 'vehicle_completed', 'replay', true, 'data', jsonb_build_object('vehicle_id', v.id, 'vehicle_version', v.version));
  END IF;
  IF v.version <> p_expected_version THEN RETURN jsonb_build_object('ok', false, 'code', 'vehicle_version_conflict', 'data', jsonb_build_object('vehicle_version', v.version)); END IF;
  IF public.normalize_vehicle_stock_number(coalesce(p_confirmation_stock, '')) IS DISTINCT FROM v.stock_number_normalized THEN RETURN jsonb_build_object('ok', false, 'code', 'stock_confirmation_mismatch'); END IF;
  IF v.lifecycle_state::text NOT IN ('active', 'rft') THEN RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_active', 'data', jsonb_build_object('lifecycle_state', v.lifecycle_state)); END IF;
  IF EXISTS (SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id = v.id AND x.deleted_at IS NULL AND x.status::text = 'started') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'started_booking_must_be_completed_first');
  END IF;
  before_state := to_jsonb(v);
  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id = v.id AND deleted_at IS NULL AND status::text IN ('queued', 'planned', 'stoppage') ORDER BY id FOR UPDATE LOOP
    booking_result := public.cancel_workshop_booking(b.id, b.version, 'Administrator completed the vehicle: ' || reason, jsonb_build_object('source', 'admin_complete_vehicle_800'));
    IF NOT coalesce((booking_result->>'ok')::boolean, false) THEN
      RAISE EXCEPTION 'PDC_800_BOOKING_CANCEL_FAILED:%', coalesce(booking_result->>'error', booking_result->>'code', 'unknown') USING errcode = 'PT409';
    END IF;
    cancelled := cancelled + 1;
  END LOOP;
  UPDATE public.pdc_new_vehicle_reviews SET status = 'closed', closed_at = done_at,
    closure_reason = 'Administrator ' || actor_email || ' completed the vehicle (r800): ' || reason
  WHERE vehicle_id = v.id AND status = 'pending';
  GET DIAGNOSTICS reviews = ROW_COUNT;
  from_location := coalesce(v.current_location, '');
  UPDATE public.vehicles SET lifecycle_state = 'completed', current_location = 'Completed', visible_on_board = false,
    active_workshop_booking_id = NULL, pmb_stage = NULL, pmb_bay_stage = NULL, pmb_bay_number = NULL, workshop_status = 'completed',
    workshop_status_updated_at = done_at, workshop_status_updated_by = uid,
    location_override = NULL, location_override_reason = NULL, location_override_at = NULL, location_override_by = NULL,
    source_payload = coalesce(source_payload, '{}'::jsonb) || jsonb_build_object('admin_completed_800', jsonb_build_object(
      'at', done_at, 'by', actor_email, 'reason', reason, 'from_location', from_location, 'from_lifecycle', v.lifecycle_state::text, 'idempotency_key', p_idempotency_key)),
    version = version + 1, updated_at = done_at, updated_by = uid
  WHERE id = v.id RETURNING * INTO v;
  IF from_location IS DISTINCT FROM 'Completed' THEN
    INSERT INTO public.vehicle_movements(vehicle_id, from_location, to_location, reason, moved_by, moved_at)
    VALUES (v.id, from_location, 'Completed', 'Administrator completed the vehicle: ' || reason, uid, done_at) RETURNING id INTO movement;
  END IF;
  UPDATE public.navision_board_activations a SET active = false, completed_at = coalesce(a.completed_at, done_at),
    completion_reason = 'Administrator completed the vehicle', completed_by = uid, completed_by_email = actor_email, updated_at = done_at
  FROM public.navision_backend_records n WHERE a.backend_record_id = n.id AND n.canonical_vehicle_id = v.id AND (a.active OR a.completed_at IS NULL);
  after_state := to_jsonb(v);
  PERFORM public.audit_pdc_event('update', 'vehicles', v.id, v.id, before_state, after_state,
    jsonb_build_object('action', 'admin_complete_vehicle_800', 'reason', reason, 'cancelled_bookings', cancelled, 'closed_reviews', reviews, 'movement_id', movement));
  RETURN jsonb_build_object('ok', true, 'code', 'vehicle_completed', 'replay', false,
    'data', jsonb_build_object('vehicle_id', v.id, 'vehicle_version', v.version, 'from_location', from_location, 'cancelled_bookings', cancelled, 'closed_reviews', reviews));
END
$function$;

REVOKE ALL ON FUNCTION public.admin_complete_vehicle_800(uuid, integer, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_complete_vehicle_800(uuid, integer, text, text, uuid) TO authenticated;

DO $r800$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure;
  a1 text := $a$      -- r796 (F406): the current Navision record if any, else the most recent one (car delivered, then dropped off Navision).$a$;
  b1 text := $a$      -- r800 (F415): an administrator completed the car on purpose; the import leaves it completed.
      AND (v.source_payload IS NULL OR NOT (v.source_payload ? 'admin_completed_800'))
      -- r796 (F406): the current Navision record if any, else the most recent one (car delivered, then dropped off Navision).$a$;
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '4b8ead90d34c6818f077f8e729b04d9d' THEN RAISE EXCEPTION 'r800: board_every_stock_674 is not the r796 body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r800: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r800: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE position(md5(v_old) IN check_sql) > 0;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('admin_complete_vehicle_800', 'F415',
    'Board (r800): admin_complete_vehicle_800 exists for authenticated only, needs the administrator role, never deletes, and the import leaves admin-completed cars completed.',
    $chk$
SELECT (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.admin_complete_vehicle_800(uuid,integer,text,text,uuid)')) IS NOT NULL
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.admin_complete_vehicle_800(uuid,integer,text,text,uuid)')), $q$r.role = 'administrator'$q$) > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.admin_complete_vehicle_800(uuid,integer,text,text,uuid)')), 'DELETE FROM') = 0
   AND has_function_privilege('authenticated', to_regprocedure('public.admin_complete_vehicle_800(uuid,integer,text,text,uuid)'), 'EXECUTE')
   AND NOT has_function_privilege('anon', to_regprocedure('public.admin_complete_vehicle_800(uuid,integer,text,text,uuid)'), 'EXECUTE')
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.board_every_stock_674(uuid,boolean)')), 'admin_completed_800') > 0
   AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.source_payload ? 'admin_completed_800' AND v.lifecycle_state::text <> 'completed')
 AS ok, 'admin complete: ' || (SELECT count(*) FROM public.vehicles v WHERE v.source_payload ? 'admin_completed_800')::text || ' cars' AS detail
$chk$, true, 580, 'r800');
END $r800$;
