-- r758 (F364) / sort 475. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 13:01: "if it's at WPC, then work is complete. The time has started from PMB to complete. And then if it
-- gets to delivered at dealer on Navision or comes off Navision before it can get to there, we calculate that time so
-- we know exactly how long it takes ... from PMG to delivery". Two rules:
--  1. Delivered - At Dealer already completes the car wherever it sits (r734). It only recorded the dealer-transit time
--     when the car had been RFT booked and collected. Now, with no RFT booking, the time runs from work complete
--     (the WPC moment, else the final-check pass) to the Navision delivered status, and is stored the same way.
--  2. A linked car whose Navision record leaves the latest upload (record_status no longer current) while its work is
--     complete (final check passed, at WPC or RFT) is completed the same way, reason "Left Navision", with the same
--     time recorded. Cars still in work are not touched by this rule.
-- Rollback: supabase/rollbacks/20261030131500_r758_wpc_completes_on_navision.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

CREATE OR REPLACE FUNCTION pdc_navision_delivery_private.work_complete_at_758(p_vehicle public.vehicles)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
  SELECT coalesce(
    (SELECT w.wpc_at FROM pdc_key_number_private.vehicle_wpc_830 w WHERE w.vehicle_id = p_vehicle.id AND w.reverted_at IS NULL ORDER BY w.wpc_at DESC LIMIT 1),
    p_vehicle.qc_completed_at);
$fn$;
REVOKE ALL ON FUNCTION pdc_navision_delivery_private.work_complete_at_758(public.vehicles) FROM PUBLIC, anon, authenticated;

-- The statistics row names its basis; the check only knew the exact Navision literal.
ALTER TABLE public.pdc_rft_dealer_transit_statistics_734 DROP CONSTRAINT pdc_rft_dealer_transit_statistics_734_status_literal_check;
ALTER TABLE public.pdc_rft_dealer_transit_statistics_734 ADD CONSTRAINT pdc_rft_dealer_transit_statistics_734_status_literal_check
  CHECK (status_literal IN ('Delivered - At Dealer', 'Delivered - At Dealer (from work complete, no RFT booking)', 'Left Navision (from work complete)'));

DO $r758$
DECLARE v_old text; v_new text; v_def text; v_n integer;
  sig regprocedure := 'public.reconcile_navision_delivery_734(uuid,uuid,text)'::regprocedure;
  a1 text := E' receipt uuid; duration bigint; has_interval boolean:=false; cancelled integer:=0; assignments jsonb;\n';
  b1 text := E' receipt uuid; duration bigint; has_interval boolean:=false; cancelled integer:=0; assignments jsonb;\n fallback_start timestamptz; has_fallback boolean:=false;\n';
  a2 text := E' IF has_interval THEN duration:=greatest(0,floor(extract(epoch FROM(closed_at-v.dealer_transit_started_at)))::bigint); END IF;\n';
  b2 text := E' IF has_interval THEN duration:=greatest(0,floor(extract(epoch FROM(closed_at-v.dealer_transit_started_at)))::bigint); END IF;\n'
          || E' -- r758: no RFT booking; the dealer-transit time runs from work complete (WPC, else final check) to the Navision status.\n'
          || E' IF NOT has_interval AND v.dealer_transit_closed_at IS NULL AND v.dealer_transit_duration_seconds IS NULL THEN\n'
          || E'  fallback_start:=pdc_navision_delivery_private.work_complete_at_758(v);\n'
          || E'  IF fallback_start IS NOT NULL AND fallback_start<=closed_at THEN has_fallback:=true; duration:=greatest(0,floor(extract(epoch FROM(closed_at-fallback_start)))::bigint); END IF;\n'
          || E' END IF;\n';
  a3 text := E'   dealer_transit_closed_at=CASE WHEN has_interval THEN closed_at ELSE dealer_transit_closed_at END,\n   dealer_transit_duration_seconds=CASE WHEN has_interval THEN duration ELSE dealer_transit_duration_seconds END,\n';
  b3 text := E'   dealer_transit_started_at=CASE WHEN has_fallback THEN fallback_start ELSE dealer_transit_started_at END,\n   dealer_transit_closed_at=CASE WHEN has_interval OR has_fallback THEN closed_at ELSE dealer_transit_closed_at END,\n   dealer_transit_duration_seconds=CASE WHEN has_interval OR has_fallback THEN duration ELSE dealer_transit_duration_seconds END,\n';
  a4 text := E'    ''collection_recorded'',has_interval,''work_completion_inferred'',false,''cancelled_bookings'',cancelled),result);\n  IF has_interval THEN\n';
  b4 text := E'    ''collection_recorded'',has_interval,''work_complete_fallback'',has_fallback,''work_completion_inferred'',false,''cancelled_bookings'',cancelled),result);\n  IF has_interval OR has_fallback THEN\n';
  a5 text := E'    v.dealer_transit_started_at,closed_at,duration,''Delivered - At Dealer'');\n';
  b5 text := E'    coalesce(v.dealer_transit_started_at,fallback_start),closed_at,duration,CASE WHEN has_fallback THEN ''Delivered - At Dealer (from work complete, no RFT booking)'' ELSE ''Delivered - At Dealer'' END);\n';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r758: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 475 OR fault_id = 'F364' OR added_in = 'r758') THEN RAISE EXCEPTION 'r758: sort 475 or F364 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r758: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> 'b7f8a5e503f820fa85d21ccac579e582' THEN RAISE EXCEPTION 'r758: reconcile_navision_delivery_734 is not the expected body'; END IF;
  FOREACH v_def IN ARRAY ARRAY[a1, a2, a3, a4, a5] LOOP
    IF (length(v_old) - length(replace(v_old, v_def, ''))) / length(v_def) <> 1 THEN RAISE EXCEPTION 'r758: anchor not found once: %', left(v_def, 60); END IF;
  END LOOP;
  v_new := replace(replace(replace(replace(replace(v_old, a1, b1), a2, b2), a3, b3), a4, b4), a5, b5);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r758: readback differs'; END IF;
END $r758$;

-- Rule 2: the record leaves Navision while the work is complete.
CREATE OR REPLACE FUNCTION pdc_navision_delivery_private.complete_left_navision_758(p_backend_record_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE b public.navision_backend_records%rowtype; v public.vehicles%rowtype; closed_at timestamptz := clock_timestamp();
  started_at timestamptz; duration bigint; receipt uuid; before_state jsonb; after_state jsonb; request_payload jsonb; result jsonb;
  actor_id uuid := auth.uid(); actor_email text := coalesce(nullif(public.current_actor_email(), ''), 'system@staging.invalid');
BEGIN
  SELECT * INTO b FROM public.navision_backend_records WHERE id = p_backend_record_id;
  IF NOT FOUND OR b.canonical_vehicle_id IS NULL OR (b.is_current AND b.record_status = 'current') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'left_navision_not_applicable');
  END IF;
  -- Another current record for the same car means the car is still on Navision (re-keyed record); leave it.
  IF EXISTS (SELECT 1 FROM public.navision_backend_records o WHERE o.canonical_vehicle_id = b.canonical_vehicle_id AND o.id <> b.id AND o.is_current AND o.record_status = 'current') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'left_navision_still_current_elsewhere');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop:vehicle:' || b.canonical_vehicle_id::text, 0));
  SELECT * INTO v FROM public.vehicles WHERE id = b.canonical_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state <> 'active' OR v.qc_completed_at IS NULL
     OR upper(btrim(coalesce(v.current_location, ''))) <> 'RFT' OR v.rft_collected_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'left_navision_vehicle_not_work_complete');
  END IF;
  IF EXISTS (SELECT 1 FROM public.workshop_bookings WHERE vehicle_id = v.id AND deleted_at IS NULL AND status IN ('queued', 'planned', 'started', 'stoppage')) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'left_navision_open_booking');
  END IF;
  started_at := coalesce(v.dealer_transit_started_at, pdc_navision_delivery_private.work_complete_at_758(v));
  IF started_at IS NOT NULL AND started_at <= closed_at THEN duration := greatest(0, floor(extract(epoch FROM (closed_at - started_at)))::bigint); END IF;
  before_state := public.pdc_rft_transport_snapshot_734(v.id) || jsonb_build_object('vehicle', to_jsonb(v));
  UPDATE public.vehicles SET lifecycle_state = 'completed', current_location = 'Completed', visible_on_board = false,
    active_workshop_booking_id = NULL, pmb_stage = NULL, pmb_bay_stage = NULL, pmb_bay_number = NULL, workshop_status = 'completed',
    workshop_status_updated_at = closed_at, workshop_status_updated_by = actor_id,
    location_override = NULL, location_override_reason = NULL, location_override_at = NULL, location_override_by = NULL,
    dealer_transit_started_at = coalesce(dealer_transit_started_at, started_at),
    dealer_transit_closed_at = CASE WHEN duration IS NOT NULL THEN closed_at ELSE dealer_transit_closed_at END,
    dealer_transit_duration_seconds = CASE WHEN duration IS NOT NULL THEN duration ELSE dealer_transit_duration_seconds END,
    delivered_to_dealer_date = coalesce(delivered_to_dealer_date, (closed_at AT TIME ZONE 'Australia/Perth')::date),
    source_payload = coalesce(source_payload, '{}'::jsonb) || jsonb_build_object('navision_left_rule', 'r758', 'navision_record_id', b.id,
      'navision_status_literal', coalesce(b.normalized_data->>'toyotaStatus', ''), 'navision_record_status', b.record_status, 'left_navision_at', closed_at),
    version = version + 1, updated_at = closed_at, updated_by = actor_id
  WHERE id = v.id RETURNING * INTO v;
  UPDATE public.navision_board_activations SET active = false, completed_at = coalesce(completed_at, closed_at),
    completion_reason = 'Left Navision', completed_by = actor_id, completed_by_email = actor_email, updated_at = closed_at
  WHERE backend_record_id = b.id AND (active OR completed_at IS NULL);
  receipt := extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000758', 'left-navision:' || b.id::text || ':' || v.id::text);
  result := jsonb_build_object('ok', true, 'code', 'left_navision_completed', 'data', jsonb_build_object('receipt_id', receipt, 'vehicle_id', v.id,
    'backend_record_id', b.id, 'dealer_transit_started_at', v.dealer_transit_started_at, 'dealer_transit_closed_at', v.dealer_transit_closed_at,
    'dealer_transit_duration_seconds', v.dealer_transit_duration_seconds));
  after_state := public.pdc_rft_transport_snapshot_734(v.id) || jsonb_build_object('vehicle', to_jsonb(v));
  request_payload := jsonb_build_object('contract', 'pdc-navision-left-758', 'backend_record_id', b.id, 'vehicle_id', v.id, 'record_status', b.record_status);
  INSERT INTO public.pdc_rft_transport_lifecycle_receipts_734
    (receipt_id, vehicle_id, action, actor_id, actor_email, idempotency_key, request_sha256, request_payload, before_state, after_state, evidence, response)
  VALUES (receipt, v.id, 'delivered', actor_id, actor_email,
    extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000758', 'left-navision-idempotency:' || b.id::text || ':' || v.id::text),
    encode(extensions.digest(convert_to(request_payload::text, 'UTF8'), 'sha256'), 'hex'), request_payload, before_state, after_state,
    jsonb_build_object('left_navision', true, 'exact_status_literal', false, 'work_complete_fallback', duration IS NOT NULL, 'work_completion_inferred', false), result)
  ON CONFLICT DO NOTHING;
  IF duration IS NOT NULL THEN
    INSERT INTO public.pdc_rft_dealer_transit_statistics_734 (statistic_id, vehicle_id, delivered_receipt_id, started_at, closed_at, duration_seconds, status_literal)
    VALUES (extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000758', 'statistic:' || v.id::text), v.id, receipt, started_at, closed_at, duration, 'Left Navision (from work complete)')
    ON CONFLICT DO NOTHING;
  END IF;
  PERFORM public.audit_pdc_event('update', 'vehicles', v.id, v.id, before_state, after_state,
    jsonb_build_object('action', 'navision_left_completed', 'receipt_id', receipt, 'backend_record_id', b.id, 'record_status', b.record_status));
  UPDATE public.navision_backend_revision SET revision = revision + 1, updated_at = closed_at WHERE singleton;
  UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = closed_at WHERE singleton;
  RETURN result;
END
$fn$;
REVOKE ALL ON FUNCTION pdc_navision_delivery_private.complete_left_navision_758(uuid) FROM PUBLIC, anon, authenticated;

DO $r758t$
DECLARE v_old text; v_new text; v_def text;
  sig regprocedure := 'public.trigger_reconcile_navision_operational_record()'::regprocedure;
  a1 text := E' result:=public.reconcile_navision_operational_record(v_backend_record_id,auth.uid(),public.current_actor_email());\n';
  b1 text := E' -- r758: the record left the latest Navision upload while the car''s work was complete (WPC or RFT): complete it.\n'
          || E' IF TG_TABLE_NAME=''navision_backend_records'' AND TG_OP=''UPDATE'' AND OLD.is_current AND OLD.record_status=''current''\n'
          || E'    AND NOT (NEW.is_current AND NEW.record_status=''current'') AND NEW.canonical_vehicle_id IS NOT NULL THEN\n'
          || E'  PERFORM pdc_navision_delivery_private.complete_left_navision_758(NEW.id);\n'
          || E' END IF;\n'
          || E' result:=public.reconcile_navision_operational_record(v_backend_record_id,auth.uid(),public.current_actor_email());\n';
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '54fbd5264b1a3dca04840ca635b5a55f' THEN RAISE EXCEPTION 'r758: trigger body is not the expected one'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r758: trigger anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r758: trigger readback differs'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('wpc_completes_on_navision_758', 'F364',
    'Navision (r758): Delivered - At Dealer records the dealer-transit time from work complete when there was no RFT booking, and a record leaving Navision completes a work-complete car. Both code paths present; no active work-complete car is linked only to a non-current Navision record.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.reconcile_navision_delivery_734(uuid,uuid,text)')), 'work_complete_at_758') > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.trigger_reconcile_navision_operational_record()')), 'complete_left_navision_758') > 0
   AND NOT EXISTS (
     SELECT 1 FROM public.vehicles v
     WHERE v.deleted_at IS NULL AND v.lifecycle_state = 'active' AND v.qc_completed_at IS NOT NULL AND upper(btrim(coalesce(v.current_location,''))) = 'RFT'
       AND v.rft_collected_at IS NULL AND v.updated_at < now() - interval '30 minutes'
       AND EXISTS (SELECT 1 FROM public.navision_backend_records b WHERE b.canonical_vehicle_id = v.id)
       AND NOT EXISTS (SELECT 1 FROM public.navision_backend_records b WHERE b.canonical_vehicle_id = v.id AND b.is_current AND b.record_status = 'current')
       AND NOT EXISTS (SELECT 1 FROM public.workshop_bookings w WHERE w.vehicle_id = v.id AND w.deleted_at IS NULL AND w.status IN ('queued','planned','started','stoppage')))
 AS ok, 'work-complete cars complete when Navision says delivered or drops them' AS detail
$chk$, true, 475, 'r758');
END $r758t$;
