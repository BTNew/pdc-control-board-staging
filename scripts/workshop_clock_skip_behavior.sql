-- Synthetic clock fixtures. No customer jobs. Compares one tick's JSON and rows.
CREATE OR REPLACE FUNCTION probe_fail(p_label text, p_detail text) RETURNS void
LANGUAGE plpgsql AS $fn$
BEGIN
 RAISE EXCEPTION 'clock probe failed: % (%)', p_label, p_detail;
END $fn$;

CREATE OR REPLACE FUNCTION probe_clear() RETURNS void
LANGUAGE plpgsql AS $fn$
BEGIN
 DELETE FROM public.workshop_clock_history;
 DELETE FROM public.workshop_clock_status;
 DELETE FROM public.workshop_clock_watermarks;
 DELETE FROM public.workshop_booking_assignments;
 DELETE FROM public.workshop_admin_blocks;
 DELETE FROM public.workshop_bookings;
END $fn$;

CREATE OR REPLACE FUNCTION probe_booking(
 p_id uuid, p_vehicle uuid, p_bay uuid, p_stage uuid, p_status text,
 p_start timestamptz, p_end timestamptz, p_minutes integer,
 p_actual timestamptz DEFAULT NULL, p_bus integer DEFAULT NULL
) RETURNS void LANGUAGE sql AS $fn$
 INSERT INTO public.workshop_bookings(
  id, vehicle_id, bay_id, stage_id, status, actual_start_at, scheduled_start_at, scheduled_end_at,
  default_duration_minutes, version, bus_calendar_version, updated_at)
 VALUES (
  p_id, p_vehicle, p_bay, p_stage, p_status, p_actual, p_start, p_end,
  p_minutes, 1, p_bus, timestamptz '2026-10-01 00:00:00+08');
$fn$;

CREATE OR REPLACE FUNCTION probe_state() RETURNS jsonb
LANGUAGE sql STABLE AS $fn$
 SELECT jsonb_build_object(
  'bookings', coalesce((SELECT jsonb_agg(jsonb_build_object(
    'id', id, 'status', status, 'bay_id', bay_id, 'vehicle_id', vehicle_id,
    'start', scheduled_start_at, 'end', scheduled_end_at, 'minutes', default_duration_minutes,
    'version', version, 'actual', actual_start_at, 'updated_by', updated_by, 'bus', bus_calendar_version
   ) ORDER BY id) FROM public.workshop_bookings), '[]'::jsonb),
  'assignments', coalesce((SELECT jsonb_agg(jsonb_build_object(
    'booking_id', booking_id, 'start', scheduled_start_at, 'end', scheduled_end_at, 'technician_id', technician_id
   ) ORDER BY booking_id) FROM public.workshop_booking_assignments WHERE released_at IS NULL), '[]'::jsonb),
  'status', coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.bay_id) FROM public.workshop_clock_status s), '[]'::jsonb),
  'history', coalesce((SELECT jsonb_agg(jsonb_build_object(
    'booking_id', booking_id, 'bay_id', bay_id, 'clock_at', clock_at,
    'before_start', before_data->>'scheduled_start_at', 'before_end', before_data->>'scheduled_end_at',
    'after_start', after_data->>'scheduled_start_at', 'after_end', after_data->>'scheduled_end_at',
    'after_version', after_data->>'version', 'after_minutes', after_data->>'default_duration_minutes'
   ) ORDER BY booking_id, id) FROM public.workshop_clock_history), '[]'::jsonb),
  'watermarks', coalesce((SELECT jsonb_agg(jsonb_build_object('booking_id', booking_id, 'through', accounted_through)
   ORDER BY booking_id) FROM public.workshop_clock_watermarks), '[]'::jsonb));
$fn$;

CREATE OR REPLACE FUNCTION probe_at(p_id uuid, p_column text) RETURNS timestamptz
LANGUAGE sql STABLE AS $fn$
 SELECT CASE p_column WHEN 'start' THEN scheduled_start_at ELSE scheduled_end_at END
 FROM public.workshop_bookings WHERE id = p_id $fn$;

CREATE OR REPLACE FUNCTION probe_scenario(p_phase text, p_name text) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE payload jsonb; fit uuid := '10000000-0000-4000-8000-000000000001';
 bus uuid := '10000000-0000-4000-8000-000000000002';
 bay1 uuid := '20000000-0000-4000-8000-000000000001';
 bay2 uuid := '20000000-0000-4000-8000-000000000002';
 bay3 uuid := '20000000-0000-4000-8000-000000000003';
 bay4 uuid := '20000000-0000-4000-8000-000000000004';
 bay5 uuid := '20000000-0000-4000-8000-000000000005';
 bay6 uuid := '20000000-0000-4000-8000-000000000006';
 bay7 uuid := '20000000-0000-4000-8000-000000000007';
 bus1 uuid := '20000000-0000-4000-8000-000000000008';
 bus2 uuid := '20000000-0000-4000-8000-000000000009';
 inactive uuid := '20000000-0000-4000-8000-00000000000a';
 veh_c uuid := '30000000-0000-4000-8000-000000000001';
 veh_q uuid := '30000000-0000-4000-8000-000000000002';
 veh_f uuid := '30000000-0000-4000-8000-000000000003';
 veh_r uuid := '30000000-0000-4000-8000-000000000004';
 veh_s uuid := '30000000-0000-4000-8000-000000000005';
 veh_b uuid := '30000000-0000-4000-8000-000000000006';
 veh_i uuid := '30000000-0000-4000-8000-000000000007';
 job_a uuid := '40000000-0000-4000-8000-000000000001';
 job_b uuid := '40000000-0000-4000-8000-000000000002';
 job_run uuid := '40000000-0000-4000-8000-000000000003';
 job_future uuid := '40000000-0000-4000-8000-000000000004';
 job_bayless uuid := '40000000-0000-4000-8000-000000000005';
 job_rp uuid := '40000000-0000-4000-8000-000000000006';
 job_rr uuid := '40000000-0000-4000-8000-000000000007';
 job_stop uuid := '40000000-0000-4000-8000-000000000008';
 job_queued uuid := '40000000-0000-4000-8000-000000000009';
 job_ba uuid := '40000000-0000-4000-8000-00000000000a';
 job_bb uuid := '40000000-0000-4000-8000-00000000000b';
 job_close uuid := '40000000-0000-4000-8000-00000000000c';
 job_quiet_run uuid := '40000000-0000-4000-8000-00000000000d';
 job_quiet_plan uuid := '40000000-0000-4000-8000-00000000000e';
 job_off uuid := '40000000-0000-4000-8000-00000000000f';
BEGIN
 PERFORM probe_clear();
 IF p_name = 'cascade' THEN
  PERFORM probe_booking(job_a, veh_c, bay1, fit, 'planned', '2026-10-16 14:00:00+08', '2026-10-16 15:00:00+08', 60);
  PERFORM probe_booking(job_b, veh_c, bay2, fit, 'planned', '2026-10-16 15:00:00+08', '2026-10-16 16:00:00+08', 60);
  PERFORM probe_booking(job_bayless, veh_c, NULL, fit, 'queued', '2026-10-16 09:00:00+08', '2026-10-16 10:00:00+08', 60);
  PERFORM probe_booking(job_run, veh_q, bay3, fit, 'started', '2026-10-19 08:00:00+08', '2026-10-19 15:00:00+08', 420, '2026-10-19 08:00:00+08');
  PERFORM probe_booking(job_future, veh_f, bay4, fit, 'planned', '2026-10-19 13:00:00+08', '2026-10-19 14:00:00+08', 60);
  INSERT INTO public.workshop_booking_assignments(id, booking_id, technician_id, scheduled_start_at, scheduled_end_at)
  VALUES ('41000000-0000-4000-8000-000000000001', job_a, '50000000-0000-4000-8000-000000000001',
   '2026-10-16 14:00:00+08', '2026-10-16 15:00:00+08');
  payload := public.workshop_clock_tick(true, '2026-10-17 12:00:00+08');
  IF probe_at(job_a, 'start') IS DISTINCT FROM '2026-10-19 06:00:00+08'::timestamptz
   OR probe_at(job_a, 'end') IS DISTINCT FROM '2026-10-19 07:00:00+08'::timestamptz THEN
   PERFORM probe_fail('cascade arrival', probe_at(job_a, 'start')::text || ' -> ' || probe_at(job_a, 'end')::text);
  END IF;
  IF probe_at(job_b, 'start') IS DISTINCT FROM '2026-10-19 08:00:00+08'::timestamptz
   OR probe_at(job_b, 'end') IS DISTINCT FROM '2026-10-19 09:00:00+08'::timestamptz
   OR probe_at(job_b, 'start') IS DISTINCT FROM probe_at(job_a, 'end') + interval '1 hour' THEN
   PERFORM probe_fail('cascade handover', probe_at(job_b, 'start')::text || ' -> ' || probe_at(job_b, 'end')::text);
  END IF;
  IF extract(isodow FROM probe_at(job_a, 'start') AT TIME ZONE 'Australia/Perth') <> 1
   OR extract(isodow FROM probe_at(job_b, 'start') AT TIME ZONE 'Australia/Perth') <> 1 THEN
   PERFORM probe_fail('cascade landed off Monday', probe_at(job_a, 'start')::text);
  END IF;
  IF probe_at(job_run, 'start') IS DISTINCT FROM '2026-10-19 08:00:00+08'::timestamptz
   OR probe_at(job_future, 'start') IS DISTINCT FROM '2026-10-19 13:00:00+08'::timestamptz
   OR probe_at(job_bayless, 'start') IS DISTINCT FROM '2026-10-16 09:00:00+08'::timestamptz THEN
   PERFORM probe_fail('cascade moved a non-seed', probe_state()::text);
  END IF;
  IF (payload->>'ok')::boolean IS NOT TRUE OR (payload->>'moved_count')::integer <> 2
   OR jsonb_array_length(payload->'issues') <> 0 OR jsonb_array_length(payload->'plans') <> 1
   OR jsonb_array_length(payload->'plans'->0->'moves') <> 2 THEN
   PERFORM probe_fail('cascade payload', payload::text);
  END IF;
  IF (SELECT version FROM public.workshop_bookings WHERE id = job_a) <> 2
   OR (SELECT scheduled_start_at FROM public.workshop_booking_assignments WHERE booking_id = job_a)
    IS DISTINCT FROM probe_at(job_a, 'start') THEN
   PERFORM probe_fail('cascade persisted assignment', probe_state()::text);
  END IF;
 ELSIF p_name = 'closure' THEN
  UPDATE public.workshop_settings SET value = '[{"date":"2026-10-19"}]'::jsonb WHERE key = 'closures';
  BEGIN
   PERFORM probe_booking(job_close, veh_f, bay4, fit, 'planned', '2026-10-16 14:00:00+08', '2026-10-16 15:00:00+08', 60);
   IF public.workshop_calendar_minute_available('2026-10-19 06:00:00+08') THEN
    PERFORM probe_fail('Monday closure was open', 'calendar');
   END IF;
   payload := public.workshop_clock_tick(true, '2026-10-17 12:00:00+08');
   IF probe_at(job_close, 'start') IS DISTINCT FROM '2026-10-20 06:00:00+08'::timestamptz
    OR probe_at(job_close, 'end') IS DISTINCT FROM '2026-10-20 07:00:00+08'::timestamptz THEN
    PERFORM probe_fail('closure landing', probe_at(job_close, 'start')::text || ' -> ' || probe_at(job_close, 'end')::text);
   END IF;
   UPDATE public.workshop_settings SET value = '[]'::jsonb WHERE key = 'closures';
  EXCEPTION WHEN OTHERS THEN
   UPDATE public.workshop_settings SET value = '[]'::jsonb WHERE key = 'closures';
   RAISE;
  END;
 ELSIF p_name = 'bus' THEN
  PERFORM probe_booking(job_ba, veh_b, bus1, bus, 'planned', '2026-10-16 14:00:00+08', '2026-10-16 15:00:00+08', 60, NULL, 1);
  PERFORM probe_booking(job_bb, veh_b, bus2, bus, 'planned', '2026-10-16 14:30:00+08', '2026-10-16 15:30:00+08', 60, NULL, 1);
  payload := public.workshop_clock_tick(true, '2026-10-17 12:00:00+08');
  IF probe_at(job_ba, 'start') IS DISTINCT FROM '2026-10-19 06:00:00+08'::timestamptz
   OR probe_at(job_ba, 'end') IS DISTINCT FROM '2026-10-19 07:00:00+08'::timestamptz THEN
   PERFORM probe_fail('bus arrival', probe_at(job_ba, 'start')::text || ' -> ' || probe_at(job_ba, 'end')::text);
  END IF;
  IF probe_at(job_bb, 'start') IS DISTINCT FROM '2026-10-19 08:00:00+08'::timestamptz
   OR probe_at(job_bb, 'start') IS DISTINCT FROM probe_at(job_ba, 'end') + interval '1 hour' THEN
   PERFORM probe_fail('bus handover', probe_at(job_bb, 'start')::text || ' -> ' || probe_at(job_bb, 'end')::text);
  END IF;
  IF (payload->>'moved_count')::integer <> 2 OR jsonb_array_length(payload->'issues') <> 0 THEN
   PERFORM probe_fail('bus payload', payload::text);
  END IF;
 ELSIF p_name = 'running_conflict' THEN
  PERFORM probe_booking(job_rp, veh_r, bay1, fit, 'planned', '2026-10-19 06:30:00+08', '2026-10-19 09:30:00+08', 180);
  PERFORM probe_booking(job_rr, veh_r, bay2, fit, 'started', '2026-10-19 08:00:00+08', '2026-10-19 10:00:00+08', 120, '2026-10-19 08:00:00+08');
  payload := public.workshop_clock_tick(true, '2026-10-19 09:00:00+08');
  IF (payload->>'ok')::boolean IS NOT FALSE OR (payload->>'moved_count')::integer <> 0
   OR payload->'issues'->0->>'code' IS DISTINCT FROM '22023'
   OR position('preserving workshop order' IN payload->'issues'->0->>'detail') = 0 THEN
   PERFORM probe_fail('running conflict payload', payload::text);
  END IF;
  IF (SELECT version FROM public.workshop_bookings WHERE id = job_rp) <> 1
   OR probe_at(job_rp, 'start') IS DISTINCT FROM '2026-10-19 06:30:00+08'::timestamptz
   OR probe_at(job_rr, 'start') IS DISTINCT FROM '2026-10-19 08:00:00+08'::timestamptz
   OR (SELECT count(*) FROM public.workshop_clock_status WHERE error_code = '22023') <> 2 THEN
   PERFORM probe_fail('running conflict persisted', probe_state()::text);
  END IF;
 ELSIF p_name = 'stoppage_conflict' THEN
  PERFORM probe_booking(job_stop, veh_s, bay6, fit, 'stoppage', '2026-10-16 14:00:00+08', '2026-10-16 15:00:00+08', 60, '2026-10-16 14:00:00+08');
  PERFORM probe_booking(job_queued, veh_s, bay7, fit, 'queued', '2026-10-19 06:00:00+08', '2026-10-19 07:00:00+08', 60);
  payload := public.workshop_clock_tick(true, '2026-10-17 12:00:00+08');
  IF (payload->>'ok')::boolean IS NOT FALSE OR (payload->>'moved_count')::integer <> 0
   OR payload->'issues'->0->>'code' IS DISTINCT FROM '22023'
   OR position('cannot move automatically' IN payload->'issues'->0->>'detail') = 0 THEN
   PERFORM probe_fail('stoppage conflict payload', payload::text);
  END IF;
  IF probe_at(job_stop, 'end') IS DISTINCT FROM '2026-10-16 15:00:00+08'::timestamptz
   OR probe_at(job_queued, 'start') IS DISTINCT FROM '2026-10-19 06:00:00+08'::timestamptz
   OR (SELECT count(*) FROM public.workshop_clock_status WHERE error_code = '22023') <> 2 THEN
   PERFORM probe_fail('stoppage conflict persisted', probe_state()::text);
  END IF;
 ELSIF p_name = 'quiet' THEN
  PERFORM probe_booking(job_quiet_run, veh_q, bay3, fit, 'started', '2026-10-19 08:00:00+08', '2026-10-19 16:00:00+08', 480, '2026-10-19 08:00:00+08');
  PERFORM probe_booking(job_quiet_plan, veh_f, bay4, fit, 'planned', '2026-10-19 13:00:00+08', '2026-10-19 14:00:00+08', 60);
  PERFORM probe_booking(job_off, veh_i, inactive, fit, 'planned', '2026-10-19 07:00:00+08', '2026-10-19 08:00:00+08', 60);
  INSERT INTO public.workshop_clock_status(bay_id, last_checked_at, last_success_at, moved_count)
  VALUES (bay3, '2026-10-01 00:00:00+08', '2026-10-01 00:00:00+08', 4);
  payload := public.workshop_clock_tick(true, '2026-10-19 10:00:00+08');
  IF (payload->>'ok')::boolean IS NOT TRUE OR (payload->>'moved_count')::integer <> 0
   OR payload->'plans' <> '[]'::jsonb OR payload->'issues' <> '[]'::jsonb THEN
   PERFORM probe_fail('quiet payload', payload::text);
  END IF;
  IF (SELECT version FROM public.workshop_bookings WHERE id = job_off) <> 1
   OR (SELECT moved_count FROM public.workshop_clock_status WHERE bay_id = bay3) <> 4
   OR EXISTS (SELECT 1 FROM public.workshop_clock_history)
   OR EXISTS (SELECT 1 FROM public.workshop_clock_watermarks) THEN
   PERFORM probe_fail('quiet wrote state', probe_state()::text);
  END IF;
 ELSE
  PERFORM probe_fail('unknown scenario', p_name);
 END IF;
 INSERT INTO public.probe_result(phase, scenario, payload, state)
 VALUES (p_phase, p_name, payload, probe_state());
END $fn$;

CREATE OR REPLACE FUNCTION probe_store_calls(p_phase text, p_name text) RETURNS void
LANGUAGE plpgsql AS $fn$
BEGIN
 -- The preceding statement requested the flush. Drop the cached stats snapshot first.
 PERFORM pg_stat_clear_snapshot();
 UPDATE public.probe_result r SET
  plan_calls = coalesce((SELECT sum(calls) FROM pg_stat_user_functions WHERE schemaname = 'public' AND funcname = 'workshop_clock_plan'), 0),
  effective_calls = coalesce((SELECT sum(calls) FROM pg_stat_user_functions WHERE schemaname = 'public' AND funcname = 'workshop_booking_effective_end_at'), 0),
  capacity_calls = coalesce((SELECT sum(calls) FROM pg_stat_user_functions WHERE schemaname = 'public' AND funcname = 'workshop_booking_capacity_duration_minutes'), 0)
 WHERE r.phase = p_phase AND r.scenario = p_name;
END $fn$;

CREATE OR REPLACE FUNCTION probe_load_board(p_kind text) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE bays integer := 40; started_n integer := 800; planned_n integer := 400;
BEGIN
 INSERT INTO public.workshop_bays(id, stage_id, is_active, bay_number)
 SELECT ('63000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '10000000-0000-4000-8000-000000000001', true, 20 + n
 FROM generate_series(1, bays) n
 ON CONFLICT (id) DO NOTHING;
 INSERT INTO public.vehicles(id, current_location)
 SELECT ('62000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'PMB'
 FROM generate_series(1, started_n + planned_n + 1) n
 ON CONFLICT (id) DO NOTHING;
 INSERT INTO public.workshop_bookings(
  id, vehicle_id, bay_id, stage_id, status, actual_start_at, scheduled_start_at, scheduled_end_at,
  default_duration_minutes, version, updated_at)
 SELECT ('61000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  ('62000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  ('63000000-0000-4000-8000-' || lpad(((n % bays) + 1)::text, 12, '0'))::uuid,
  '10000000-0000-4000-8000-000000000001', 'started',
  '2026-10-19 08:00:00+08', '2026-10-19 08:00:00+08', '2026-10-19 16:00:00+08', 480, 1,
  '2026-10-01 00:00:00+08'
 FROM generate_series(1, started_n) n;
 INSERT INTO public.workshop_bookings(
  id, vehicle_id, bay_id, stage_id, status, scheduled_start_at, scheduled_end_at,
  default_duration_minutes, version, updated_at)
 SELECT ('61100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  ('62000000-0000-4000-8000-' || lpad((started_n + n)::text, 12, '0'))::uuid,
  ('63000000-0000-4000-8000-' || lpad(((n % bays) + 1)::text, 12, '0'))::uuid,
  '10000000-0000-4000-8000-000000000001', 'planned',
  '2026-10-19 13:00:00+08', '2026-10-19 14:00:00+08', 60, 1, '2026-10-01 00:00:00+08'
 FROM generate_series(1, planned_n) n;
 IF p_kind = 'busy' THEN
  PERFORM probe_booking('64000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000003',
   '20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', 'planned',
   '2026-10-19 07:00:00+08', '2026-10-19 08:00:00+08', 60);
 END IF;
END $fn$;

CREATE OR REPLACE FUNCTION probe_time(p_phase text, p_kind text) RETURNS integer
LANGUAGE plpgsql AS $fn$
DECLARE started timestamptz; sample integer; total numeric := 0; samples integer := 5;
BEGIN
 PERFORM probe_clear();
 PERFORM probe_load_board(p_kind);
 PERFORM public.workshop_clock_tick(false, '2026-10-19 10:00:00+08');
 FOR sample IN 1..samples LOOP
  started := clock_timestamp();
  PERFORM public.workshop_clock_tick(false, '2026-10-19 10:00:00+08');
  total := total + extract(epoch FROM clock_timestamp() - started) * 1000;
 END LOOP;
 IF EXISTS (SELECT 1 FROM public.workshop_clock_history) THEN
  PERFORM probe_fail('timing wrote history', p_kind);
 END IF;
 INSERT INTO public.probe_timing(phase, kind, avg_ms, samples)
 VALUES (p_phase, p_kind, round(total / samples, 3), samples);
 PERFORM probe_clear();
 RETURN 1;
END $fn$;

CREATE OR REPLACE FUNCTION probe_compare() RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE row record; before_ms numeric; after_ms numeric; busy_before numeric; busy_after numeric;
BEGIN
 FOR row IN SELECT b.scenario, b.payload before_payload, a.payload after_payload, b.state before_state, a.state after_state,
  b.plan_calls before_plan, a.plan_calls after_plan, b.capacity_calls before_capacity, a.capacity_calls after_capacity,
  b.effective_calls before_effective, a.effective_calls after_effective
  FROM public.probe_result b JOIN public.probe_result a ON a.scenario = b.scenario
  WHERE b.phase = 'before' AND a.phase = 'after'
 LOOP
  IF row.before_payload IS DISTINCT FROM row.after_payload THEN
   PERFORM probe_fail(row.scenario || ' payload', row.before_payload::text || ' || ' || row.after_payload::text);
  END IF;
  IF row.before_state IS DISTINCT FROM row.after_state THEN
   PERFORM probe_fail(row.scenario || ' state', row.before_state::text || ' || ' || row.after_state::text);
  END IF;
  IF row.scenario IN ('cascade', 'bus', 'running_conflict', 'stoppage_conflict')
   AND (row.before_plan IS NULL OR row.before_plan < 1 OR row.after_plan IS NULL OR row.after_plan < 1) THEN
   PERFORM probe_fail(row.scenario || ' did not enter the planner', row.before_plan::text || '/' || row.after_plan::text);
  END IF;
  IF row.scenario = 'quiet' AND (row.before_capacity IS NULL OR row.before_capacity < 1 OR row.after_capacity IS DISTINCT FROM 0) THEN
   PERFORM probe_fail('quiet capacity calls', row.before_capacity::text || ' -> ' || row.after_capacity::text);
  END IF;
  IF row.scenario = 'quiet' AND (row.after_effective IS NULL OR row.before_effective IS NULL OR row.after_effective >= row.before_effective) THEN
   PERFORM probe_fail('quiet effective-end calls', row.before_effective::text || ' -> ' || row.after_effective::text);
  END IF;
 END LOOP;
 SELECT avg_ms INTO before_ms FROM public.probe_timing WHERE phase = 'before' AND kind = 'idle';
 SELECT avg_ms INTO after_ms FROM public.probe_timing WHERE phase = 'after' AND kind = 'idle';
 SELECT avg_ms INTO busy_before FROM public.probe_timing WHERE phase = 'before' AND kind = 'busy';
 SELECT avg_ms INTO busy_after FROM public.probe_timing WHERE phase = 'after' AND kind = 'busy';
 IF before_ms IS NULL OR after_ms IS NULL OR NOT (after_ms < before_ms) THEN
  PERFORM probe_fail('idle timing', before_ms::text || ' -> ' || after_ms::text);
 END IF;
 IF busy_before IS NULL OR busy_after IS NULL OR busy_after > busy_before * 2 THEN
  PERFORM probe_fail('busy timing grew', busy_before::text || ' -> ' || busy_after::text);
 END IF;
 RAISE NOTICE 'clock timings idle before % ms after % ms; busy before % ms after % ms', before_ms, after_ms, busy_before, busy_after;
 FOR row IN SELECT phase, scenario, plan_calls, effective_calls, capacity_calls
  FROM public.probe_result WHERE phase IN ('before', 'after') ORDER BY scenario, phase
 LOOP
  RAISE NOTICE 'clock calls % % plan % effective % capacity %', row.phase, row.scenario, row.plan_calls, row.effective_calls, row.capacity_calls;
 END LOOP;
END $fn$;

CREATE OR REPLACE FUNCTION probe_compare_rollback() RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE row record;
BEGIN
 FOR row IN SELECT b.scenario FROM public.probe_result b WHERE b.phase = 'before'
 LOOP
  IF (SELECT payload FROM public.probe_result WHERE phase = 'rollback' AND scenario = row.scenario)
    IS DISTINCT FROM (SELECT payload FROM public.probe_result WHERE phase = 'before' AND scenario = row.scenario)
   OR (SELECT state FROM public.probe_result WHERE phase = 'rollback' AND scenario = row.scenario)
    IS DISTINCT FROM (SELECT state FROM public.probe_result WHERE phase = 'before' AND scenario = row.scenario) THEN
   PERFORM probe_fail('rollback ' || row.scenario, 'differs from the reviewed clock');
  END IF;
 END LOOP;
END $fn$;
