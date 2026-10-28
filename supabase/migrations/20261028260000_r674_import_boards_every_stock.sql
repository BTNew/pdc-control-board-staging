-- r674 (F283) / sort 422. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 28 Oct 2026 21:03: every job on the Service as a Whole import must be on the board. A vehicle in the
-- New Vehicles section counts as on the board (waiting on approval).
-- At submit_finish of an apply job, for each stock sent (not held):
--   * the 19 Oct owner board hold for that stock is released (so the importer can create a missing vehicle,
--     which it then queues in New Vehicles itself);
--   * an existing hidden vehicle that is not already waiting in New Vehicles is put back there:
--     lifecycle active, review pending.
-- A preview job only counts them (to_new_vehicles). BUSPARTS gets a standing not-a-vehicle hold.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard674$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r674: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r674: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r674: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 422 OR fault_id = 'F283' OR added_in = 'r674' OR check_name = 'import_boards_every_stock_674') THEN RAISE EXCEPTION 'r674: sort 422 or F283 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r674: an import job is running'; END IF;
  IF to_regprocedure('pdc_import_620.board_every_stock_674(uuid,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'r674: already applied'; END IF;
END $guard674$;

CREATE FUNCTION pdc_import_620.board_every_stock_674(p_job uuid, p_write boolean)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_s text; v_vid uuid; v_released integer := 0; v_n integer; v_queued text[] := '{}'; v_unheld text[] := '{}';
BEGIN
  FOR v_s IN SELECT DISTINCT stock_number FROM pdc_import_620.job_rows WHERE job_id = p_job AND held_reason IS NULL ORDER BY 1 LOOP
    IF EXISTS (SELECT 1 FROM pdc_codex_intake_private.owner_board_visibility_holds_20261019 h WHERE h.released_at IS NULL AND h.stock_number = v_s) THEN
      v_unheld := v_unheld || v_s;
      IF p_write THEN
        UPDATE pdc_codex_intake_private.owner_board_visibility_holds_20261019
        SET released_at = clock_timestamp(), release_reason = 'r674: on the Service as a Whole import (Craig 28 Oct 2026: every job on the import is on the board)'
        WHERE released_at IS NULL AND stock_number = v_s;
        GET DIAGNOSTICS v_n = ROW_COUNT; v_released := v_released + v_n;
      END IF;
    END IF;
    SELECT v.id INTO v_vid FROM public.vehicles v
    WHERE v.stock_number_normalized = public.normalize_vehicle_stock_number(v_s) AND v.deleted_at IS NULL
      AND v.visible_on_board IS NOT TRUE
      AND NOT (v.lifecycle_state::text = 'active' AND EXISTS (SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id = v.id AND r.status = 'pending'))
    ORDER BY v.created_at DESC LIMIT 1;
    IF v_vid IS NOT NULL THEN
      v_queued := v_queued || v_s;
      IF p_write THEN
        UPDATE public.vehicles SET lifecycle_state = 'active', version = version + 1, updated_at = clock_timestamp()
        WHERE id = v_vid AND lifecycle_state::text <> 'active';
        INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id, status, source_kind, first_job_card, received_at)
        VALUES (v_vid, 'pending', 'revolution_report',
          (SELECT min(r.row->>'repair_order_number') FROM pdc_import_620.job_rows r WHERE r.job_id = p_job AND r.stock_number = v_s), clock_timestamp())
        ON CONFLICT (vehicle_id) DO UPDATE SET status = 'pending', source_kind = excluded.source_kind, first_job_card = excluded.first_job_card,
          received_at = clock_timestamp(), approved_at = NULL, approved_by = NULL, approval_key = NULL, approval_hash = NULL, approval_receipt = NULL,
          closed_at = NULL, closure_reason = NULL
        WHERE pdc_new_vehicle_reviews.vehicle_id = excluded.vehicle_id;
      END IF;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('owner_holds_released', CASE WHEN p_write THEN v_released ELSE cardinality(v_unheld) END,
    'owner_hold_stocks', to_jsonb(v_unheld), 'to_new_vehicles', to_jsonb(v_queued), 'written', p_write);
END $fn$;

DO $edit674$
DECLARE v_old text; v_new text; v_def text;
  c_at text := E'  CREATE TEMP TABLE IF NOT EXISTS pdc620_stock_part (stock text PRIMARY KEY, part integer) ON COMMIT DROP;';
  c_ret text := E'    ''new_board_vehicles'', v_new, ''partitions'', v_parts);';
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'pdc_import_620.submit_finish(uuid)'::regprocedure;
  v_old := replace(v_old, E'\r\n', E'\n');
  IF (length(v_old) - length(replace(v_old, c_at, ''))) / length(c_at) <> 1 THEN RAISE EXCEPTION 'r674: partition anchor not found once'; END IF;
  IF (length(v_old) - length(replace(v_old, c_ret, ''))) / length(c_ret) <> 1 THEN RAISE EXCEPTION 'r674: return anchor not found once'; END IF;
  v_new := replace(v_old, c_at,
    E'  -- r674 (F283): every stock sent is on the board (active, or waiting in New Vehicles). Apply writes; preview counts.\n'
    || E'  v_board := pdc_import_620.board_every_stock_674(p_job, v_job.mode = ''apply'' AND v_status = ''queued'');\n' || c_at);
  v_new := replace(v_new, c_ret, E'    ''new_board_vehicles'', v_new, ''partitions'', v_parts, ''board_every_stock'', v_board);');
  v_new := replace(v_new, E'DECLARE v_job pdc_import_620.jobs;', E'DECLARE v_board jsonb; v_job pdc_import_620.jobs;');
  IF strpos(v_new, 'DECLARE v_board jsonb;') = 0 THEN RAISE EXCEPTION 'r674: declare anchor'; END IF;
  v_def := pg_get_functiondef('pdc_import_620.submit_finish(uuid)'::regprocedure);
  v_def := regexp_replace(v_def, '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
END $edit674$;

SELECT pdc_import_620.add_hold('BUSPARTS', 'standing_hold:not_a_vehicle');

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_import_620 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON PROCEDURE pdc_import_620.run_jobs() FROM PUBLIC, anon, authenticated, service_role;

DO $check674$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('import_boards_every_stock_674', 'F283',
    'An apply import puts every stock it sends on the board: owner holds released, hidden vehicles back in New Vehicles (pending).',
    $chk674$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.submit_finish(uuid)')), 'board_every_stock_674(p_job, v_job.mode = ''apply''') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.board_every_stock_674(uuid,boolean)')), 'owner_board_visibility_holds_20261019') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.board_every_stock_674(uuid,boolean)')), 'status = ''pending''') > 0
  AND EXISTS (SELECT 1 FROM pdc_import_620.holds WHERE active AND stock_number = 'BUSPARTS')
 AS ok, 'import boards every stock' AS detail
$chk674$, true, 422, 'r674');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'import_boards_every_stock_674') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r674: check red: %', detail; END IF;
END $check674$;
