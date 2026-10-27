-- r585 (F199) / sort 357. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig approved go-live 28 Oct 2026 05:18 AWST for this speed work.
-- PR #498 holds r584 / F198 / sort 356 and is not used. Live tip is r583 / F197 / sort 355.
-- This is the next free triple after that preview: r585 / F199 / sort 357.
--
-- Since 27 Oct 12:33 AWST the station snapshot and the sublet board have been rebuilt
-- by every open planner at once. One uncontended Fitting call is under a second. The
-- pile-up is what passes the 8s client timeout. r545 caches the vehicle board and r554
-- caches location and eligibility. Neither covers these two reads.
--
-- The calculation bodies are copied, not rewritten:
--   station 98cc6aafa9cc7627c77eda8b46b389fa
--   sublet  7dde7e19d31b269136a93ebecd12217a
-- The public functions authorise first, then reuse that exact JSON for 15 seconds.
-- A station revision, an email revision, or a QC-line generation drops the station copy.
-- An email revision, a QC-line generation, a PO sighting, or a sublet tick drops the board copy.
-- Pin count stays 241. The sublet pin stays release r439 and takes the new wrapper md5 in place.
-- Department 135 fitter_job_command stays fd05b9eef69498002ac06dd68e01cdff.
-- Kajel rows stay 9be0883b1a555f48f3c1ba9fa111c891 and apply stays b62fb7c29ffd2a1629f214f696e5cb14.
-- Undo: supabase/rollbacks/20261028054500_r585_station_sublet_cache.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r585: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r585: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r585: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_station_workshop_snapshot(text,date,date)')) IS DISTINCT FROM '98cc6aafa9cc7627c77eda8b46b389fa' THEN RAISE EXCEPTION 'r585: station snapshot is not the live body'; END IF;
 IF (SELECT provolatile<>'s' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_station_workshop_snapshot(text,date,date)')) THEN RAISE EXCEPTION 'r585: station snapshot is not a stable definer'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_sublet_po_board_439()')) IS DISTINCT FROM '7dde7e19d31b269136a93ebecd12217a' THEN RAISE EXCEPTION 'r585: sublet board is not the r439 body'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_sublet_po_board_439()' AND release='r439') IS DISTINCT FROM '7dde7e19d31b269136a93ebecd12217a' THEN RAISE EXCEPTION 'r585: sublet pin is not r439'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r585: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r585: fitter command changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r585: Kajel rows changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r585: Kajel apply changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r585: clock tick changed'; END IF;
 IF to_regprocedure('pdc_ops.station_workshop_snapshot_compute_585(text,date,date)') IS NOT NULL
    OR to_regprocedure('pdc_ops.sublet_po_board_compute_585()') IS NOT NULL
    OR to_regprocedure('pdc_ops.cache_holds_snapshot_585(text,text,date,date,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r585: compute function already exists'; END IF;
 IF to_regclass('pdc_ops.station_workshop_snapshot_cache_585') IS NOT NULL
    OR to_regclass('pdc_ops.sublet_po_board_cache_585') IS NOT NULL THEN RAISE EXCEPTION 'r585: cache table already exists'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='line_handoff_583' AND fault_id='F197' AND sort_order=355 AND added_in='r583') THEN RAISE EXCEPTION 'r585: r583 / F197 sort 355 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=356 OR fault_id='F198' OR added_in='r584') THEN RAISE EXCEPTION 'r585: sort 356 / F198 is taken; leave that preview its number'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=357 OR fault_id='F199' OR check_name='station_sublet_cache_585' OR added_in='r585') THEN RAISE EXCEPTION 'r585: sort 357 / F199 is taken'; END IF;
END $g$;

DO $copy$
DECLARE def text; n int; v_owner name;
BEGIN
  SELECT pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure) INTO def;
  n := (length(def)-length(replace(def,'public.get_station_workshop_snapshot(','')))/length('public.get_station_workshop_snapshot(');
  IF n<>1 THEN RAISE EXCEPTION 'r585: station functiondef shape %', n; END IF;
  def := regexp_replace(def, 'public\.get_station_workshop_snapshot\(', 'pdc_ops.station_workshop_snapshot_compute_585(');
  EXECUTE def;
  SELECT pg_get_functiondef('public.get_pdc_sublet_po_board_439()'::regprocedure) INTO def;
  n := (length(def)-length(replace(def,'public.get_pdc_sublet_po_board_439(','')))/length('public.get_pdc_sublet_po_board_439(');
  IF n<>1 THEN RAISE EXCEPTION 'r585: sublet functiondef shape %', n; END IF;
  def := regexp_replace(def, 'public\.get_pdc_sublet_po_board_439\(', 'pdc_ops.sublet_po_board_compute_585(');
  EXECUTE def;
  SELECT pg_catalog.pg_get_userbyid(p.proowner) INTO v_owner FROM pg_proc p WHERE p.oid=to_regprocedure('public.get_station_workshop_snapshot(text,date,date)');
  EXECUTE format('ALTER FUNCTION pdc_ops.station_workshop_snapshot_compute_585(text,date,date) OWNER TO %I', v_owner);
  EXECUTE format('ALTER FUNCTION pdc_ops.sublet_po_board_compute_585() OWNER TO %I', v_owner);
  REVOKE ALL ON FUNCTION pdc_ops.station_workshop_snapshot_compute_585(text,date,date), pdc_ops.sublet_po_board_compute_585() FROM PUBLIC, anon, authenticated, service_role;
  EXECUTE format('GRANT EXECUTE ON FUNCTION pdc_ops.station_workshop_snapshot_compute_585(text,date,date), pdc_ops.sublet_po_board_compute_585() TO %I', v_owner);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.station_workshop_snapshot_compute_585(text,date,date)')) IS DISTINCT FROM '98cc6aafa9cc7627c77eda8b46b389fa' THEN RAISE EXCEPTION 'r585: station calculation changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.sublet_po_board_compute_585()')) IS DISTINCT FROM '7dde7e19d31b269136a93ebecd12217a' THEN RAISE EXCEPTION 'r585: sublet calculation changed'; END IF;
  IF (SELECT provolatile<>'s' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.station_workshop_snapshot_compute_585(text,date,date)')) THEN RAISE EXCEPTION 'r585: station calculation is not a stable definer'; END IF;
  IF (SELECT provolatile<>'s' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.sublet_po_board_compute_585()')) THEN RAISE EXCEPTION 'r585: sublet calculation is not a stable definer'; END IF;
END
$copy$;

CREATE TABLE pdc_ops.station_workshop_snapshot_cache_585 (
  stage_code text NOT NULL,
  date_from date NOT NULL,
  date_to date NOT NULL,
  station_revision bigint NOT NULL,
  email_revision bigint NOT NULL,
  qc_epoch bigint NOT NULL,
  snapshot jsonb NOT NULL,
  computed_at timestamptz NOT NULL,
  PRIMARY KEY (stage_code, date_from, date_to)
);
CREATE TABLE pdc_ops.sublet_po_board_cache_585 (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  email_revision bigint NOT NULL,
  qc_epoch bigint NOT NULL,
  po_seen timestamptz NOT NULL,
  po_active bigint NOT NULL,
  tick_updated timestamptz NOT NULL,
  tick_count bigint NOT NULL,
  snapshot jsonb NOT NULL,
  computed_at timestamptz NOT NULL
);
ALTER TABLE pdc_ops.station_workshop_snapshot_cache_585 ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_ops.sublet_po_board_cache_585 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_ops.station_workshop_snapshot_cache_585, pdc_ops.sublet_po_board_cache_585 FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON TABLE pdc_ops.station_workshop_snapshot_cache_585 IS
  'r585 (F199): one station snapshot per stage and date range. No API access. The station function is the only reader and writer.';
COMMENT ON TABLE pdc_ops.sublet_po_board_cache_585 IS
  'r585 (F199): one sublet PO board payload. No API access. The sublet function is the only reader and writer.';

DO $own$
DECLARE v_owner name;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(p.proowner) INTO v_owner FROM pg_proc p WHERE p.oid=to_regprocedure('pdc_ops.station_workshop_snapshot_compute_585(text,date,date)');
  EXECUTE format('ALTER TABLE pdc_ops.station_workshop_snapshot_cache_585 OWNER TO %I', v_owner);
  EXECUTE format('ALTER TABLE pdc_ops.sublet_po_board_cache_585 OWNER TO %I', v_owner);
END
$own$;

CREATE OR REPLACE FUNCTION public.get_station_workshop_snapshot(p_stage_code text, p_date_from date, p_date_to date)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_stage text;
  v_srev bigint;
  v_erev bigint;
  v_epoch bigint;
  v_cached jsonb;
  v_lock boolean;
  v_snapshot jsonb;
BEGIN
  -- r585 (F199): authorise first, then one shared copy for 15 seconds.
  -- The JSON is the unchanged calculation. Parallel refreshes were each rebuilding it.
  PERFORM public.workshop_require_planner_operator();
  v_stage := public.workshop_canonical_stage_code(p_stage_code);
  IF v_stage IS NULL OR p_date_from IS NULL OR p_date_to IS NULL
     OR p_date_to < p_date_from OR p_date_to > p_date_from + 31 THEN
    RETURN pdc_ops.station_workshop_snapshot_compute_585(p_stage_code, p_date_from, p_date_to);
  END IF;

  v_srev := public.workshop_current_station_revision(v_stage);
  SELECT coalesce(r.revision, 0) INTO v_erev
  FROM public.pdc_email_vehicle_revision r
  WHERE r.singleton;
  v_erev := coalesce(v_erev, 0);
  SELECT coalesce(max(e.gen), 0) INTO v_epoch
  FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e;

  SELECT c.snapshot INTO v_cached
  FROM pdc_ops.station_workshop_snapshot_cache_585 c
  WHERE c.stage_code = v_stage
    AND c.date_from = p_date_from
    AND c.date_to = p_date_to
    AND c.station_revision = v_srev
    AND c.email_revision = v_erev
    AND c.qc_epoch = v_epoch
    AND c.computed_at > clock_timestamp() - interval '15 seconds';
  IF v_cached IS NOT NULL THEN
    RETURN v_cached;
  END IF;

  v_lock := pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r585-station:' || v_stage || ':' || p_date_from::text || ':' || p_date_to::text, 0));
  IF NOT v_lock THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r585-station:' || v_stage || ':' || p_date_from::text || ':' || p_date_to::text, 0));
    v_srev := public.workshop_current_station_revision(v_stage);
    SELECT coalesce(r.revision, 0) INTO v_erev
    FROM public.pdc_email_vehicle_revision r
    WHERE r.singleton;
    v_erev := coalesce(v_erev, 0);
    SELECT coalesce(max(e.gen), 0) INTO v_epoch
    FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e;
    SELECT c.snapshot INTO v_cached
    FROM pdc_ops.station_workshop_snapshot_cache_585 c
    WHERE c.stage_code = v_stage
      AND c.date_from = p_date_from
      AND c.date_to = p_date_to
      AND c.station_revision = v_srev
      AND c.email_revision = v_erev
      AND c.qc_epoch = v_epoch
      AND c.computed_at > clock_timestamp() - interval '15 seconds';
    IF v_cached IS NOT NULL THEN
      RETURN v_cached;
    END IF;
  END IF;

  v_snapshot := pdc_ops.station_workshop_snapshot_compute_585(p_stage_code, p_date_from, p_date_to);
  INSERT INTO pdc_ops.station_workshop_snapshot_cache_585
    (stage_code, date_from, date_to, station_revision, email_revision, qc_epoch, snapshot, computed_at)
  VALUES (v_stage, p_date_from, p_date_to, v_srev, v_erev, v_epoch, v_snapshot, clock_timestamp())
  ON CONFLICT (stage_code, date_from, date_to) DO UPDATE
    SET station_revision = EXCLUDED.station_revision,
        email_revision = EXCLUDED.email_revision,
        qc_epoch = EXCLUDED.qc_epoch,
        snapshot = EXCLUDED.snapshot,
        computed_at = EXCLUDED.computed_at
    WHERE station_workshop_snapshot_cache_585.stage_code = EXCLUDED.stage_code
      AND station_workshop_snapshot_cache_585.date_from = EXCLUDED.date_from
      AND station_workshop_snapshot_cache_585.date_to = EXCLUDED.date_to;
  RETURN v_snapshot;
END
$function$;

CREATE OR REPLACE FUNCTION public.get_pdc_sublet_po_board_439()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_erev bigint;
  v_epoch bigint;
  v_po_seen timestamptz;
  v_po_active bigint;
  v_tick_at timestamptz;
  v_tick_n bigint;
  v_cached jsonb;
  v_lock boolean;
  v_snapshot jsonb;
BEGIN
  -- r585 (F199): same r439 authorisation, then one shared board for 15 seconds.
  IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor
     AND lower(r.email)=v_email AND r.active AND r.account_status='approved')
   THEN RAISE EXCEPTION 'PDC_439_UNAUTHORIZED' USING errcode='42501'; END IF;

  SELECT coalesce(r.revision, 0) INTO v_erev
  FROM public.pdc_email_vehicle_revision r
  WHERE r.singleton;
  v_erev := coalesce(v_erev, 0);
  SELECT coalesce(max(e.gen), 0) INTO v_epoch
  FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e;
  SELECT coalesce(max(p.last_seen_at), '-infinity'::timestamptz), count(*) FILTER (WHERE p.active)
    INTO v_po_seen, v_po_active
  FROM public.pdc_service_line_po_refs_439 p;
  SELECT coalesce(max(t.updated_at), '-infinity'::timestamptz), count(*)
    INTO v_tick_at, v_tick_n
  FROM public.pdc_sublet_line_ticks_439 t;

  SELECT c.snapshot INTO v_cached
  FROM pdc_ops.sublet_po_board_cache_585 c
  WHERE c.singleton
    AND c.email_revision = v_erev
    AND c.qc_epoch = v_epoch
    AND c.po_seen = v_po_seen
    AND c.po_active = v_po_active
    AND c.tick_updated = v_tick_at
    AND c.tick_count = v_tick_n
    AND c.computed_at > clock_timestamp() - interval '15 seconds';
  IF v_cached IS NOT NULL THEN
    RETURN v_cached;
  END IF;

  v_lock := pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r585-sublet-board', 0));
  IF NOT v_lock THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r585-sublet-board', 0));
    SELECT coalesce(r.revision, 0) INTO v_erev
    FROM public.pdc_email_vehicle_revision r
    WHERE r.singleton;
    v_erev := coalesce(v_erev, 0);
    SELECT coalesce(max(e.gen), 0) INTO v_epoch
    FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e;
    SELECT coalesce(max(p.last_seen_at), '-infinity'::timestamptz), count(*) FILTER (WHERE p.active)
      INTO v_po_seen, v_po_active
    FROM public.pdc_service_line_po_refs_439 p;
    SELECT coalesce(max(t.updated_at), '-infinity'::timestamptz), count(*)
      INTO v_tick_at, v_tick_n
    FROM public.pdc_sublet_line_ticks_439 t;
    SELECT c.snapshot INTO v_cached
    FROM pdc_ops.sublet_po_board_cache_585 c
    WHERE c.singleton
      AND c.email_revision = v_erev
      AND c.qc_epoch = v_epoch
      AND c.po_seen = v_po_seen
      AND c.po_active = v_po_active
      AND c.tick_updated = v_tick_at
      AND c.tick_count = v_tick_n
      AND c.computed_at > clock_timestamp() - interval '15 seconds';
    IF v_cached IS NOT NULL THEN
      RETURN v_cached;
    END IF;
  END IF;

  v_snapshot := pdc_ops.sublet_po_board_compute_585();
  INSERT INTO pdc_ops.sublet_po_board_cache_585
    (singleton, email_revision, qc_epoch, po_seen, po_active, tick_updated, tick_count, snapshot, computed_at)
  VALUES (true, v_erev, v_epoch, v_po_seen, v_po_active, v_tick_at, v_tick_n, v_snapshot, clock_timestamp())
  ON CONFLICT (singleton) DO UPDATE
    SET email_revision = EXCLUDED.email_revision,
        qc_epoch = EXCLUDED.qc_epoch,
        po_seen = EXCLUDED.po_seen,
        po_active = EXCLUDED.po_active,
        tick_updated = EXCLUDED.tick_updated,
        tick_count = EXCLUDED.tick_count,
        snapshot = EXCLUDED.snapshot,
        computed_at = EXCLUDED.computed_at
    WHERE sublet_po_board_cache_585.singleton;
  RETURN v_snapshot;
END
$function$;

REVOKE ALL ON FUNCTION public.get_station_workshop_snapshot(text,date,date), public.get_pdc_sublet_po_board_439() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_station_workshop_snapshot(text,date,date), public.get_pdc_sublet_po_board_439() TO authenticated, service_role;
COMMENT ON FUNCTION public.get_station_workshop_snapshot(text,date,date) IS
  'r585 (F199): station snapshot. One shared copy for 15 seconds. Calculation md5 98cc6aafa9cc7627c77eda8b46b389fa.';
COMMENT ON FUNCTION public.get_pdc_sublet_po_board_439() IS
  'r585 (F199): sublet PO board. One shared copy for 15 seconds. Calculation md5 7dde7e19d31b269136a93ebecd12217a.';

CREATE FUNCTION pdc_ops.cache_holds_snapshot_585(p_kind text, p_stage text, p_from date, p_to date, p_snap jsonb)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog
AS $hold$
BEGIN
  -- A fresh command sees a cache row committed while the regression statement was already running.
  -- The wrapper is volatile and can see that row. The statement around it cannot.
  IF p_kind = 'station' THEN
    RETURN EXISTS (
      SELECT 1 FROM pdc_ops.station_workshop_snapshot_cache_585 c
      WHERE c.stage_code = p_stage AND c.date_from = p_from AND c.date_to = p_to
        AND c.snapshot IS NOT DISTINCT FROM p_snap
        AND c.computed_at > clock_timestamp() - interval '15 seconds'
    );
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM pdc_ops.sublet_po_board_cache_585 c
    WHERE c.singleton AND c.snapshot IS NOT DISTINCT FROM p_snap
      AND c.computed_at > clock_timestamp() - interval '15 seconds'
  );
END
$hold$;
REVOKE ALL ON FUNCTION pdc_ops.cache_holds_snapshot_585(text,text,date,date,jsonb) FROM PUBLIC, anon, authenticated, service_role;

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_sublet_po_board_439()')),
    updated_at = now()
WHERE signature='public.get_pdc_sublet_po_board_439()'
  AND release='r439'
  AND prosrc_md5='7dde7e19d31b269136a93ebecd12217a';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('station_sublet_cache_585','F199','Station snapshot and sublet PO board (r585): one shared copy stays under 8s and matches the previous calculation',
 $chk585$SELECT
  shape.ok
  AND st1.snap = st2.snap
  AND octet_length(st1.snap::text) > 100000
  AND su1.snap = su2.snap
  AND su1.snap->>'code' = 'sublet_po_board'
  AND octet_length(su1.snap::text) > 5000
  AND timed.station_ms < 8000
  AND timed.station_hit_ms < 8000
  AND timed.sublet_ms < 8000
  AND timed.sublet_hit_ms < 8000
  AND cached.station_same
  AND cached.sublet_same
 AS ok,
 format('fitting %s ms then %s ms / %s bytes; sublet %s ms then %s ms / %s bytes; stored %s/%s',
   timed.station_ms, timed.station_hit_ms, octet_length(st1.snap::text),
   timed.sublet_ms, timed.sublet_hit_ms, octet_length(su1.snap::text),
   cached.station_same, cached.sublet_same) AS detail
 FROM (
  SELECT
   to_regclass('pdc_ops.station_workshop_snapshot_cache_585') IS NOT NULL
   AND to_regclass('pdc_ops.sublet_po_board_cache_585') IS NOT NULL
   AND (SELECT c.relrowsecurity AND NOT c.relforcerowsecurity FROM pg_class c WHERE c.oid='pdc_ops.station_workshop_snapshot_cache_585'::regclass)
   AND (SELECT c.relrowsecurity AND NOT c.relforcerowsecurity FROM pg_class c WHERE c.oid='pdc_ops.sublet_po_board_cache_585'::regclass)
   AND NOT has_table_privilege('anon','pdc_ops.station_workshop_snapshot_cache_585','SELECT')
   AND NOT has_table_privilege('authenticated','pdc_ops.station_workshop_snapshot_cache_585','SELECT')
   AND NOT has_table_privilege('anon','pdc_ops.sublet_po_board_cache_585','SELECT')
   AND NOT has_table_privilege('authenticated','pdc_ops.sublet_po_board_cache_585','SELECT')
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.station_workshop_snapshot_compute_585(text,date,date)'))='98cc6aafa9cc7627c77eda8b46b389fa'
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.sublet_po_board_compute_585()'))='7dde7e19d31b269136a93ebecd12217a'
   AND (SELECT p.provolatile='v' AND p.prosecdef
         AND position('workshop_require_planner_operator' IN p.prosrc) < position('station_workshop_snapshot_cache_585' IN p.prosrc)
         AND position('pdc-r585-station:' IN p.prosrc)>0
         AND position('interval ''15 seconds''' IN p.prosrc)>0
         AND (length(p.prosrc)-length(replace(p.prosrc,'FROM public.pdc_email_vehicle_revision','')))/length('FROM public.pdc_email_vehicle_revision')=2
         AND (length(p.prosrc)-length(replace(p.prosrc,'workshop_current_station_revision','')))/length('workshop_current_station_revision')=2
        FROM pg_proc p WHERE p.oid=to_regprocedure('public.get_station_workshop_snapshot(text,date,date)'))
   AND (SELECT p.provolatile='v' AND p.prosecdef
         AND position('PDC_439_UNAUTHORIZED' IN p.prosrc) < position('sublet_po_board_cache_585' IN p.prosrc)
         AND position('pdc-r585-sublet-board' IN p.prosrc)>0
         AND (length(p.prosrc)-length(replace(p.prosrc,'FROM public.pdc_email_vehicle_revision','')))/length('FROM public.pdc_email_vehicle_revision')=2
        FROM pg_proc p WHERE p.oid=to_regprocedure('public.get_pdc_sublet_po_board_439()'))
   AND has_function_privilege('authenticated','public.get_station_workshop_snapshot(text,date,date)','EXECUTE')
   AND has_function_privilege('authenticated','public.get_pdc_sublet_po_board_439()','EXECUTE')
   AND NOT has_function_privilege('anon','public.get_station_workshop_snapshot(text,date,date)','EXECUTE')
   AND NOT has_function_privilege('anon','public.get_pdc_sublet_po_board_439()','EXECUTE')
   AND NOT has_function_privilege('authenticated','pdc_ops.station_workshop_snapshot_compute_585(text,date,date)','EXECUTE')
   AND NOT has_function_privilege('authenticated','pdc_ops.sublet_po_board_compute_585()','EXECUTE')
   AND (SELECT e.prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_sublet_po_board_439()'))
         AND e.release='r439'
        FROM pdc_ops.expected_function_md5 e WHERE e.signature='public.get_pdc_sublet_po_board_439()')
   AND (SELECT p.provolatile='v' AND p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure('pdc_ops.cache_holds_snapshot_585(text,text,date,date,jsonb)'))
   AND NOT has_function_privilege('authenticated','pdc_ops.cache_holds_snapshot_585(text,text,date,date,jsonb)','EXECUTE')
   AND NOT has_function_privilege('anon','pdc_ops.cache_holds_snapshot_585(text,text,date,date,jsonb)','EXECUTE')
  AS ok
 ) shape
 CROSS JOIN LATERAL (
  SELECT r.email, r.auth_user_id
  FROM public.pdc_user_roles r
  WHERE r.role::text='administrator' AND r.active AND r.account_status='approved' AND r.auth_user_id IS NOT NULL
  ORDER BY r.auth_user_id
  LIMIT 1
 ) actor
 CROSS JOIN LATERAL (
  SELECT set_config('request.jwt.claims', json_build_object('sub', actor.auth_user_id, 'email', actor.email)::text, true) AS claims,
         set_config('request.jwt.claim.sub', actor.auth_user_id::text, true) AS sub,
         set_config('request.jwt.claim.email', actor.email, true) AS email,
         (timezone('Australia/Perth', clock_timestamp()))::date AS d
 ) primed
 CROSS JOIN LATERAL (SELECT clock_timestamp() AS t0, primed.d AS d) s0
 CROSS JOIN LATERAL (
  SELECT public.get_station_workshop_snapshot('FITTING', s0.d, s0.d) AS snap
 ) st1
 CROSS JOIN LATERAL (SELECT clock_timestamp() AS t1, st1.snap AS gate) s1
 CROSS JOIN LATERAL (
  SELECT public.get_station_workshop_snapshot('FITTING', s0.d, s0.d) AS snap
  WHERE s1.gate IS NOT NULL
 ) st2
 CROSS JOIN LATERAL (SELECT clock_timestamp() AS t2) s2
 CROSS JOIN LATERAL (
  SELECT public.get_pdc_sublet_po_board_439() AS snap
  WHERE s2.t2 IS NOT NULL
 ) su1
 CROSS JOIN LATERAL (SELECT clock_timestamp() AS t3, su1.snap AS gate) s3
 CROSS JOIN LATERAL (
  SELECT public.get_pdc_sublet_po_board_439() AS snap
  WHERE s3.gate IS NOT NULL
 ) su2
 CROSS JOIN LATERAL (
  SELECT round((extract(epoch FROM s1.t1 - s0.t0)*1000)::numeric, 1) AS station_ms,
         round((extract(epoch FROM s2.t2 - s1.t1)*1000)::numeric, 1) AS station_hit_ms,
         round((extract(epoch FROM s3.t3 - s2.t2)*1000)::numeric, 1) AS sublet_ms,
         round((extract(epoch FROM clock_timestamp() - s3.t3)*1000)::numeric, 1) AS sublet_hit_ms,
         set_config('request.jwt.claims', '', true) AS clear_claims,
         set_config('request.jwt.claim.sub', '', true) AS clear_sub,
         set_config('request.jwt.claim.email', '', true) AS clear_email
 ) timed
 CROSS JOIN LATERAL (
  SELECT pdc_ops.cache_holds_snapshot_585('station', 'FITTING', s0.d, s0.d, st1.snap) AS station_same,
         pdc_ops.cache_holds_snapshot_585('sublet', NULL, NULL, NULL, su1.snap) AS sublet_same
 ) cached$chk585$,
 true, 357, 'r585');

DO $proof$
DECLARE
  actor record;
  d date;
  stage text;
  fresh jsonb;
  once jsonb;
  twice jsonb;
BEGIN
  SELECT r.email, r.auth_user_id INTO actor
  FROM public.pdc_user_roles r
  WHERE r.role::text='administrator' AND r.active AND r.account_status='approved' AND r.auth_user_id IS NOT NULL
  ORDER BY r.auth_user_id
  LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', actor.auth_user_id, 'email', actor.email)::text, true);
  PERFORM set_config('request.jwt.claim.sub', actor.auth_user_id::text, true);
  PERFORM set_config('request.jwt.claim.email', actor.email, true);
  d := (timezone('Australia/Perth', clock_timestamp()))::date;
  FOREACH stage IN ARRAY ARRAY['FITTING','HOIST','TINT'] LOOP
    fresh := pdc_ops.station_workshop_snapshot_compute_585(stage, d, d);
    once := public.get_station_workshop_snapshot(stage, d, d);
    twice := public.get_station_workshop_snapshot(stage, d, d);
    IF fresh IS DISTINCT FROM once OR once IS DISTINCT FROM twice THEN
      RAISE EXCEPTION 'r585: % payload changed', stage;
    END IF;
  END LOOP;
  fresh := pdc_ops.sublet_po_board_compute_585();
  once := public.get_pdc_sublet_po_board_439();
  twice := public.get_pdc_sublet_po_board_439();
  IF fresh IS DISTINCT FROM once OR once IS DISTINCT FROM twice THEN
    RAISE EXCEPTION 'r585: sublet payload changed';
  END IF;
  IF once->>'code' IS DISTINCT FROM 'sublet_po_board' THEN RAISE EXCEPTION 'r585: sublet code changed'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.email', '', true);
END
$proof$;

DO $p$
DECLARE chk record;
BEGIN
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='station_sublet_cache_585') INTO chk;
 IF chk.ok IS NOT TRUE THEN RAISE EXCEPTION 'r585: check not ok: %', chk.detail; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r585: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_sublet_po_board_439()' AND release='r439'
      AND prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_sublet_po_board_439()')))<>1 THEN RAISE EXCEPTION 'r585: sublet pin did not move in place'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_sublet_po_board_439()') = '7dde7e19d31b269136a93ebecd12217a' THEN RAISE EXCEPTION 'r585: sublet pin still names the old body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r585: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r585: Kajel rows changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r585: Kajel apply changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r585: clock tick changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='station_sublet_cache_585' AND fault_id='F199' AND sort_order=357 AND added_in='r585' AND enabled)<>1 THEN RAISE EXCEPTION 'r585: check missing'; END IF;
 IF (SELECT pg_catalog.pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid=to_regprocedure('public.get_station_workshop_snapshot(text,date,date)'))
    IS DISTINCT FROM (SELECT pg_catalog.pg_get_userbyid(c.relowner) FROM pg_class c WHERE c.oid='pdc_ops.station_workshop_snapshot_cache_585'::regclass)
 THEN RAISE EXCEPTION 'r585: station cache owner'; END IF;
END $p$;
