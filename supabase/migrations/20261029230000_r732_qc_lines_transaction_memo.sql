-- r732 (F342): a cross-bay cascade onto a packed bay took 84 s to apply and the API allows 30 s, so it failed.
-- Craig Watson, 29 Oct 2026 20:14 AWST: "cascading jobs ... no problems ... very, very quick tomorrow."
--
-- Fault. Every booking the planner cascade moves (pdc_bay_seq_private.place) fires the QC lines cache invalidation
-- for that vehicle (by design: the cache row is deleted, the cron refill rebuilds it within 5 s). Inside the same
-- transaction nothing refills it, and the cascade then scans the whole bay many times (effective end, estimates,
-- the overlap safety net), so every scan recomputed those vehicles' lines uncached: 2278 uncached computes
-- (pdc_qc_operation_lines_379_uncached, 30 to 100 ms each) for 24 pushes, 84 s in p_apply, measured 21:55 AWST in a
-- rolled-back trial. The authenticated role has statement_timeout 30 s, so the move failed on the board.
--
-- Fix. A transaction-scoped memo (temp table pdc_qc_lines_memo_732, ON COMMIT DROP) holds the lines of a vehicle
-- together with the cache epoch generations it was computed under. pdc_qc_operation_lines_379 reads the memo first,
-- only when the generations still match (so any invalidation in this transaction or committed by another session
-- makes it miss), then the persistent cache, then computes. p_apply fills the memo for every vehicle it will touch
-- and again after each placement (one compute per placement instead of one per scan). Nothing else changes: the
-- persistent cache, its refill and its invalidation are untouched; outside a cascade transaction the memo table does
-- not exist and the reader behaves exactly as before. Rolled-back trial with this change: p_apply 7 s, plan 7 s.
--
-- Pins: pdc_qc_operation_lines_379 (baseline) and p_apply (r424) move to the new bodies; the new fill function is
-- pinned (242 pins). The three checks that froze the reader's md5 (578, 587, 590) follow it (F339 lesson).
-- Staging cdsmnqxtyyoeoznmbidd only. Production never touched. No vehicle, booking, line or tick changes.
-- Rollback: supabase/rollbacks/20261029230000_r732_qc_lines_transaction_memo.down.sql

DO $r732$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  v_oid oid; v_src text; v_new text; v_def text; v_n integer; v_reader_md5 text;
  c_place1 text := $a$   PERFORM pdc_bay_seq_private.place(r.id,r.bay_id,r.new_start,r.dur,p_metadata);$a$;
  c_place2 text := $a$   PERFORM pdc_bay_seq_private.place(r.id,r.cur_bay,v_s,r.dur,p_metadata);$a$;
  c_park text := $a$ SELECT max(greatest(new_end,coalesce(cur_end,new_end)))+interval '120 days' INTO v_park FROM pg_temp.r424_p;$a$;
  c_fill text := $a$ PERFORM pdc_work_categories_private.qc_lines_memo_fill_732(r.vehicle_id);$a$;
BEGIN
  IF awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r732: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r732: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r732: an import job is running'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r732: pin count is not 241'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r732: reader body is not the baseline body'; END IF;
  IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'public.pdc_qc_operation_lines_379(uuid)' AND release = 'baseline') IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r732: reader pin is not baseline'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('pdc_bay_seq_private.p_apply(jsonb,text)')) IS DISTINCT FROM 'd6eb557f2d80ed074658a9b525b8578a' THEN RAISE EXCEPTION 'r732: p_apply body is not the r424 body'; END IF;
  IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'pdc_bay_seq_private.p_apply(jsonb,text)' AND release = 'r424') IS DISTINCT FROM 'd6eb557f2d80ed074658a9b525b8578a' THEN RAISE EXCEPTION 'r732: p_apply pin is not r424'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('station_icon_completion_578','board_qc_nesting_587','qc_signoff_override_590') AND strpos(check_sql, 'b7f90bff12643229ff80f8ca552663a2') > 0) <> 3 THEN RAISE EXCEPTION 'r732: the three reader md5 literals are not where expected'; END IF;
  IF to_regprocedure('pdc_work_categories_private.qc_lines_memo_fill_732(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r732: fill function already exists'; END IF;
  IF (SELECT data_type FROM information_schema.columns WHERE table_schema = 'pdc_work_categories_private' AND table_name = 'qc_operation_lines_cache_epoch' AND column_name = 'gen') IS DISTINCT FROM 'bigint' THEN RAISE EXCEPTION 'r732: epoch gen is not bigint'; END IF;

  -- 1. the memo writer (only the cascade calls it)
  CREATE FUNCTION pdc_work_categories_private.qc_lines_memo_fill_732(p_vehicle_id uuid) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog' AS $b$
 BEGIN
  -- r732 (F342): transaction-scoped memo of a vehicle's QC lines, stamped with the cache epoch generations.
  IF p_vehicle_id IS NULL THEN RETURN; END IF;
  CREATE TEMP TABLE IF NOT EXISTS pdc_qc_lines_memo_732(vehicle_id uuid PRIMARY KEY, vgen bigint NOT NULL, ggen bigint NOT NULL, lines jsonb NOT NULL) ON COMMIT DROP;
  INSERT INTO pg_temp.pdc_qc_lines_memo_732(vehicle_id, vgen, ggen, lines)
  SELECT p_vehicle_id,
    coalesce((SELECT gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch WHERE vehicle_id = p_vehicle_id), 0),
    coalesce((SELECT gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch WHERE vehicle_id = '00000000-0000-0000-0000-000000000000'::uuid), 0),
    public.pdc_qc_operation_lines_379_uncached(p_vehicle_id)
  ON CONFLICT (vehicle_id) DO UPDATE SET vgen = excluded.vgen, ggen = excluded.ggen, lines = excluded.lines;
 END $b$;
  REVOKE ALL ON FUNCTION pdc_work_categories_private.qc_lines_memo_fill_732(uuid) FROM PUBLIC, anon, authenticated;

  -- 2. the reader: memo (when its generations still match), then the persistent cache, then compute
  CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid) RETURNS jsonb
  LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog' AS $b$
DECLARE v jsonb;
BEGIN
 -- r732 (F342): a cascade transaction keeps a memo of the lines it recomputed; it is valid only while the cache
 -- epoch generations it was stamped with are unchanged.
 IF EXISTS (SELECT 1 FROM pg_class c WHERE c.oid = to_regclass('pg_temp.pdc_qc_lines_memo_732') AND c.relpersistence = 't'
            AND c.relowner = (SELECT proowner FROM pg_proc WHERE oid = 'pdc_work_categories_private.qc_lines_memo_fill_732(uuid)'::regprocedure)) THEN
  SELECT m.lines INTO v FROM pg_temp.pdc_qc_lines_memo_732 m
   WHERE m.vehicle_id = p_vehicle_id
     AND m.vgen = coalesce((SELECT e.gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e WHERE e.vehicle_id = p_vehicle_id), 0)
     AND m.ggen = coalesce((SELECT e.gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e WHERE e.vehicle_id = '00000000-0000-0000-0000-000000000000'::uuid), 0);
  IF v IS NOT NULL THEN RETURN v; END IF;
 END IF;
 SELECT c.lines INTO v FROM pdc_work_categories_private.qc_operation_lines_cache c WHERE c.vehicle_id = p_vehicle_id;
 IF v IS NOT NULL THEN RETURN v; END IF;
 RETURN public.pdc_qc_operation_lines_379_uncached(p_vehicle_id);
END $b$;
  SELECT md5(prosrc) INTO v_reader_md5 FROM pg_proc WHERE oid = to_regprocedure('public.pdc_qc_operation_lines_379(uuid)');

  -- 3. p_apply fills the memo for every vehicle it touches, and again after each placement
  v_oid := to_regprocedure('pdc_bay_seq_private.p_apply(jsonb,text)');
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF (length(v_src) - length(replace(v_src, c_place1, ''))) / length(c_place1) <> 1 THEN RAISE EXCEPTION 'r732: anchor place 1'; END IF;
  IF (length(v_src) - length(replace(v_src, c_place2, ''))) / length(c_place2) <> 1 THEN RAISE EXCEPTION 'r732: anchor place 2'; END IF;
  IF (length(v_src) - length(replace(v_src, c_park, ''))) / length(c_park) <> 1 THEN RAISE EXCEPTION 'r732: anchor park'; END IF;
  v_new := replace(v_src, c_place1, c_place1 || c_fill);
  v_new := replace(v_new, c_place2, c_place2 || c_fill);
  v_new := replace(v_new, c_park, c_park || E'\n -- r732 (F342): memo the lines of every vehicle this plan touches before the bay scans begin.\n PERFORM pdc_work_categories_private.qc_lines_memo_fill_732(z.vehicle_id) FROM (SELECT DISTINCT vehicle_id FROM pg_temp.r424_p WHERE changed) z;');
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_def := replace(v_def, v_src, v_new);
  IF v_def = pg_get_functiondef(v_oid) THEN RAISE EXCEPTION 'r732: p_apply definition unchanged'; END IF;
  EXECUTE v_def;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF v_src <> v_new THEN RAISE EXCEPTION 'r732: p_apply readback differs'; END IF;

  -- 4. pins and check literals follow
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_reader_md5, note = coalesce(note,'') || '; r732 (F342): memo-first reader; was b7f90bff12643229ff80f8ca552663a2', updated_at = clock_timestamp()
  WHERE signature = 'public.pdc_qc_operation_lines_379(uuid)' AND release = 'baseline';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r732: reader pin not moved'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new), note = coalesce(note,'') || '; r732 (F342): fills the QC lines memo; was d6eb557f2d80ed074658a9b525b8578a', updated_at = clock_timestamp()
  WHERE signature = 'pdc_bay_seq_private.p_apply(jsonb,text)' AND release = 'r424';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r732: p_apply pin not moved'; END IF;
  INSERT INTO pdc_ops.expected_function_md5(signature, prosrc_md5, release, note)
  SELECT 'pdc_work_categories_private.qc_lines_memo_fill_732(uuid)', md5(prosrc), 'r732', 'F342: transaction-scoped QC lines memo writer, cascade only'
  FROM pg_proc WHERE oid = to_regprocedure('pdc_work_categories_private.qc_lines_memo_fill_732(uuid)');
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'b7f90bff12643229ff80f8ca552663a2', v_reader_md5)
  WHERE check_name IN ('station_icon_completion_578','board_qc_nesting_587','qc_signoff_override_590');
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 3 THEN RAISE EXCEPTION 'r732: check literals not moved'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 242 THEN RAISE EXCEPTION 'r732: pin count is not 242'; END IF;
  RAISE NOTICE 'r732: reader % p_apply %', v_reader_md5, md5(v_new);
END $r732$;

INSERT INTO pdc_ops.regression_checks(check_name, sort_order, fault_id, added_in, enabled, description, check_sql)
VALUES ('qc_lines_memo_732', 454, 'F342', 'r732', true,
  'A planner cascade keeps a transaction memo of the QC lines it recomputes (stamped with the cache epoch generations) so a packed-bay push applies in seconds, not minutes: the reader checks the memo before the cache, p_apply fills it before the scans and after each placement, the fill function is private, and the bodies match their pins.',
  $chk$
WITH rd AS (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')),
ap AS (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_bay_seq_private.p_apply(jsonb,text)')),
fl AS (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_work_categories_private.qc_lines_memo_fill_732(uuid)'))
SELECT (SELECT pg_catalog.strpos(prosrc, 'pg_temp.pdc_qc_lines_memo_732') FROM rd) > 0
   AND (SELECT pg_catalog.strpos(prosrc, 'm.vgen = coalesce(') FROM rd) > 0
   AND (SELECT pg_catalog.strpos(prosrc, 'm.ggen = coalesce(') FROM rd) > 0
   AND (SELECT count(*) FROM pg_catalog.regexp_matches((SELECT prosrc FROM ap), 'qc_lines_memo_fill_732\(r\.vehicle_id\)', 'g')) = 2
   AND (SELECT pg_catalog.strpos(prosrc, 'qc_lines_memo_fill_732(z.vehicle_id) FROM (SELECT DISTINCT vehicle_id FROM pg_temp.r424_p WHERE changed)') FROM ap) > 0
   AND (SELECT pg_catalog.strpos(prosrc, 'ON COMMIT DROP') FROM fl) > 0
   AND NOT pg_catalog.has_function_privilege('authenticated', 'pdc_work_categories_private.qc_lines_memo_fill_732(uuid)', 'execute')
   AND NOT pg_catalog.has_function_privilege('anon', 'pdc_work_categories_private.qc_lines_memo_fill_732(uuid)', 'execute')
   AND (SELECT pg_catalog.md5(prosrc) FROM rd) = (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature = 'public.pdc_qc_operation_lines_379(uuid)' AND e.release = 'baseline')
   AND (SELECT pg_catalog.md5(prosrc) FROM ap) = (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature = 'pdc_bay_seq_private.p_apply(jsonb,text)' AND e.release = 'r424')
   AND (SELECT pg_catalog.md5(prosrc) FROM fl) = (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature = 'pdc_work_categories_private.qc_lines_memo_fill_732(uuid)' AND e.release = 'r732')
 AS ok,
 'QC lines memo in the cascade (r732)' AS detail
$chk$);

DO $post732$
DECLARE r record; v_red text := ''; v_n integer := 0;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x
   WHERE x.check_name IN ('qc_lines_memo_732','station_icon_completion_578','board_qc_nesting_587','qc_signoff_override_590','protected_function_md5s',
     'regression_checks_self_test','category_move_full_bay_730','bay_resequence_and_stopped_replan','key460_drag_597','outstanding_station_hours_594','qc_cache_zero_mismatches')
  LOOP
    v_n := v_n + 1;
    IF NOT r.ok THEN v_red := v_red || r.check_name || ' (' || left(r.detail, 160) || '); '; END IF;
  END LOOP;
  IF v_n <> 11 THEN RAISE EXCEPTION 'r732: expected 11 checks, saw %', v_n; END IF;
  IF v_red <> '' THEN RAISE EXCEPTION 'r732: red after apply, rolled back: %', v_red; END IF;
  RAISE NOTICE 'r732: 11 checks green';
END $post732$;
