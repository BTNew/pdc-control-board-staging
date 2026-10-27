-- r567 (F181) / sort 338. Go-live. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
--
-- The preview claimed r564 / F178 / sort 338. r564 / F178 is the live Fitters key badge
-- and inserted no check. sort 338 is free (r565 / F179 / sort 337 is the panel tick).
-- r566 / F180 was applied for the Electrical bay hide and rolled back, so this release
-- is r567 / F181 / sort 338. Object names stay _564 so the preview prosrc md5s still match.
--
-- Parts staff track stoppage dates in the Job Stoppage sheet. The board already reads a
-- parts-staff email into public.pdc_parts_eta and a JITA paste into public.pdc_jita_eta.
-- This release adds a vehicle-level date and a short note that parts and workshop
-- controllers type on the board. A typed date wins over the email date. The email row and
-- the JITA row are not rewritten, and both stay readable.
--
-- Per purchase-order line is not stored here. The GP chip on a PD line is a sublet PO
-- (public.pdc_service_line_po_refs_439: vehicle, line, GP number). It is not the DMS
-- purchase-order part line whose In To Store date the sheet is copied from, and a vehicle
-- can be waiting on a part that has no GP chip. One date per vehicle is the choice.
--
-- Writers: importer (parts), operator (workshop controller), administrator.
-- Readers: the same board readers as the email parts ETA (is_pdc_role viewer).
-- Every change writes public.pdc_parts_stoppage_audit_564 (who, when, old, new).
-- Last checked is the Perth date of that change.
-- No vehicle, job, booking or email ETA row is created, hidden, closed or removed.
-- Pin count stays 241. No pinned function is edited.
-- Source up md5 0cfa2b48d798149f9397230d8d67f564. Source down md5 c84bc247c3e3362fc9861d4094f9e0f2.
-- The preview check called pg_catalog.position(x IN y). That form does not parse, so the
-- check uses pg_catalog.strpos. Function bodies are unchanged.
-- Undo: supabase/rollbacks/20261027170000_r567_parts_stoppage_eta.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r567: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r567: staging only'; END IF;
 IF EXISTS (SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE project_ref='vjdtsswhroyguxyfjdkt') THEN RAISE EXCEPTION 'r567: production ref'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r567: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r567: set_parts_eta is not the r436 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')) IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec' THEN RAISE EXCEPTION 'r567: parts ETA board read is not the r436 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board_v2()')) IS DISTINCT FROM '6a0046123aeb862667dce68884318850' THEN RAISE EXCEPTION 'r567: parts ETA board v2 is not the r475 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)')) IS DISTINCT FROM 'a81b786bfc7868c3217d827933299678' THEN RAISE EXCEPTION 'r567: set_parts_eta_from_email is not the r475 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_jita_eta_board()')) IS DISTINCT FROM '29dcb35956acd61b6a8aa2ca07a80182' THEN RAISE EXCEPTION 'r567: JITA board read is not the r516 body'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=338 OR fault_id='F181' OR check_name='parts_stoppage_manual_567' OR added_in='r567') THEN RAISE EXCEPTION 'r567: sort 338 or F181 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='newvehiclebuild_pdc_route_558' AND fault_id='F172' AND sort_order=333 AND added_in='r558') THEN RAISE EXCEPTION 'r567: r558 / F172 sort 333 is not the live check'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='panel_line_completion_565' AND fault_id='F179' AND sort_order=337 AND added_in='r565') THEN RAISE EXCEPTION 'r567: r565 / F179 sort 337 is not present'; END IF;
 IF to_regclass('public.pdc_parts_stoppage_564') IS NOT NULL OR to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'r567: already applied'; END IF;
END $g$;

CREATE TABLE public.pdc_parts_stoppage_564 (
  vehicle_id uuid PRIMARY KEY,
  stock_number text NOT NULL,
  eta_date date,
  note text,
  last_checked_on date NOT NULL,
  active boolean NOT NULL DEFAULT true,
  set_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  set_by uuid,
  set_by_actor text NOT NULL,
  set_by_role text NOT NULL,
  CHECK (note IS NULL OR (length(note) BETWEEN 1 AND 180 AND note !~ '[[:cntrl:]]')),
  CHECK (set_by_role IN ('importer', 'operator', 'administrator')),
  CHECK (length(set_by_actor) BETWEEN 1 AND 200)
);

CREATE TABLE public.pdc_parts_stoppage_audit_564 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT clock_timestamp(),
  vehicle_id uuid NOT NULL,
  stock_number text NOT NULL,
  action text NOT NULL CHECK (action IN ('set', 'clear', 'check')),
  old_eta date,
  new_eta date,
  old_note text,
  new_note text,
  last_checked_on date,
  actor_id uuid,
  actor text NOT NULL,
  actor_role text NOT NULL
);
CREATE INDEX pdc_parts_stoppage_audit_564_vehicle ON public.pdc_parts_stoppage_audit_564 (vehicle_id, id DESC);

ALTER TABLE public.pdc_parts_stoppage_564 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_parts_stoppage_audit_564 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_parts_stoppage_564, public.pdc_parts_stoppage_audit_564 FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.pdc_parts_stoppage_564, public.pdc_parts_stoppage_audit_564 TO authenticated;
CREATE POLICY pdc_parts_stoppage_564_read ON public.pdc_parts_stoppage_564
  FOR SELECT TO authenticated USING (public.is_pdc_role('viewer'::public.pdc_role));
CREATE POLICY pdc_parts_stoppage_audit_564_read ON public.pdc_parts_stoppage_audit_564
  FOR SELECT TO authenticated USING (public.is_pdc_role('viewer'::public.pdc_role));

CREATE FUNCTION public.set_pdc_parts_stoppage_564(
  p_vehicle_id uuid,
  p_eta_date date DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_clear boolean DEFAULT false,
  p_mark_checked boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $set564$
DECLARE
  v_role text := public.current_pdc_user_role()::text;
  v_uid uuid := auth.uid();
  v_actor text := coalesce(nullif(btrim(coalesce(auth.jwt()->>'email', '')), ''), v_uid::text, 'unknown');
  v_today date := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date;
  v_note text;
  v_eta date;
  v_clear boolean := coalesce(p_clear, false);
  v_check boolean := coalesce(p_mark_checked, false);
  v_row public.pdc_parts_stoppage_564%ROWTYPE;
  v_stock text;
  v_action text;
BEGIN
  -- r564 (F178): one manual parts ETA and stoppage note per vehicle. Does not write the email ETA, the JITA ETA, or any vehicle row.
  IF to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'staging_only');
  END IF;
  IF v_role IS DISTINCT FROM 'importer' AND v_role IS DISTINCT FROM 'operator' AND v_role IS DISTINCT FROM 'administrator' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
  END IF;
  IF p_vehicle_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found');
  END IF;
  SELECT upper(btrim(coalesce(v.stock_number, ''))) INTO v_stock
  FROM public.vehicles v
  WHERE v.id = p_vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found');
  END IF;
  v_note := nullif(regexp_replace(btrim(coalesce(p_note, '')), '\s+', ' ', 'g'), '');
  IF v_note IS NOT NULL AND (length(v_note) > 180 OR v_note ~ '[[:cntrl:]]') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'note_too_long');
  END IF;
  v_eta := CASE WHEN v_clear THEN NULL ELSE p_eta_date END;
  IF v_eta IS NOT NULL AND (v_eta < v_today - 366 OR v_eta > v_today + 366) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'eta_date_out_of_range');
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc_parts_stoppage_564:' || p_vehicle_id::text, 0));
  SELECT * INTO v_row FROM public.pdc_parts_stoppage_564 WHERE vehicle_id = p_vehicle_id FOR UPDATE;

  IF v_eta IS NULL AND v_note IS NULL AND NOT v_check THEN
    IF NOT FOUND OR v_row.active IS NOT TRUE THEN
      RETURN jsonb_build_object('ok', true, 'changed', false, 'action', 'none', 'eta_date', NULL, 'note', NULL,
        'last_checked_on', CASE WHEN FOUND THEN v_row.last_checked_on ELSE NULL END, 'set_by_actor', CASE WHEN FOUND THEN v_row.set_by_actor ELSE NULL END);
    END IF;
    UPDATE public.pdc_parts_stoppage_564
       SET active = false, eta_date = NULL, note = NULL, last_checked_on = v_today,
           set_at = clock_timestamp(), set_by = v_uid, set_by_actor = v_actor, set_by_role = v_role, stock_number = v_stock
     WHERE vehicle_id = p_vehicle_id AND active;
    INSERT INTO public.pdc_parts_stoppage_audit_564
      (vehicle_id, stock_number, action, old_eta, new_eta, old_note, new_note, last_checked_on, actor_id, actor, actor_role)
    VALUES
      (p_vehicle_id, v_stock, 'clear', v_row.eta_date, NULL, v_row.note, NULL, v_today, v_uid, v_actor, v_role);
    RETURN jsonb_build_object('ok', true, 'changed', true, 'action', 'clear', 'eta_date', NULL, 'note', NULL,
      'last_checked_on', v_today, 'set_by_actor', v_actor);
  END IF;

  IF FOUND AND v_row.active IS TRUE
     AND v_row.eta_date IS NOT DISTINCT FROM v_eta
     AND v_row.note IS NOT DISTINCT FROM v_note
     AND (NOT v_check OR v_row.last_checked_on = v_today) THEN
    RETURN jsonb_build_object('ok', true, 'changed', false, 'action', 'none', 'eta_date', v_row.eta_date, 'note', v_row.note,
      'last_checked_on', v_row.last_checked_on, 'set_by_actor', v_row.set_by_actor, 'set_at', v_row.set_at);
  END IF;

  v_action := CASE
    WHEN FOUND AND v_row.active IS TRUE AND v_row.eta_date IS NOT DISTINCT FROM v_eta AND v_row.note IS NOT DISTINCT FROM v_note THEN 'check'
    ELSE 'set' END;

  IF FOUND THEN
    UPDATE public.pdc_parts_stoppage_564
       SET eta_date = v_eta, note = v_note, last_checked_on = v_today, active = true,
           set_at = clock_timestamp(), set_by = v_uid, set_by_actor = v_actor, set_by_role = v_role, stock_number = v_stock
     WHERE vehicle_id = p_vehicle_id;
  ELSE
    INSERT INTO public.pdc_parts_stoppage_564
      (vehicle_id, stock_number, eta_date, note, last_checked_on, active, set_by, set_by_actor, set_by_role)
    VALUES
      (p_vehicle_id, v_stock, v_eta, v_note, v_today, true, v_uid, v_actor, v_role);
  END IF;
  INSERT INTO public.pdc_parts_stoppage_audit_564
    (vehicle_id, stock_number, action, old_eta, new_eta, old_note, new_note, last_checked_on, actor_id, actor, actor_role)
  VALUES
    (p_vehicle_id, v_stock, v_action, CASE WHEN FOUND THEN v_row.eta_date ELSE NULL END, v_eta,
     CASE WHEN FOUND THEN v_row.note ELSE NULL END, v_note, v_today, v_uid, v_actor, v_role);
  RETURN jsonb_build_object('ok', true, 'changed', true, 'action', v_action, 'eta_date', v_eta, 'note', v_note,
    'last_checked_on', v_today, 'set_by_actor', v_actor, 'set_at', clock_timestamp());
END
$set564$;

REVOKE ALL ON FUNCTION public.set_pdc_parts_stoppage_564(uuid, date, text, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_parts_stoppage_564(uuid, date, text, boolean, boolean) TO authenticated;

CREATE FUNCTION public.get_pdc_parts_stoppage_board_564()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $board564$
  -- r564 (F178): current manual parts ETA per live vehicle. A null date does not hide an email ETA. Board readers only.
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false) THEN NULL::jsonb ELSE
    jsonb_build_object(
      'today', (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date,
      'can_edit', public.current_pdc_user_role()::text IN ('importer', 'operator', 'administrator'),
      'vehicles', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'vehicle_id', s.vehicle_id,
          'stock_number', s.stock_number,
          'eta_date', s.eta_date,
          'note', s.note,
          'last_checked_on', s.last_checked_on,
          'set_at', s.set_at,
          'set_by_actor', s.set_by_actor,
          'set_by_role', s.set_by_role
        ) ORDER BY s.stock_number)
        FROM public.pdc_parts_stoppage_564 s
        JOIN public.vehicles v ON v.id = s.vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
        WHERE s.active
      ), '[]'::jsonb))
  END
$board564$;

REVOKE ALL ON FUNCTION public.get_pdc_parts_stoppage_board_564() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_parts_stoppage_board_564() TO authenticated;

CREATE FUNCTION public.get_pdc_parts_stoppage_history_564(p_vehicle_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $hist564$
  -- r564 (F178): who changed the manual parts ETA, and when. Last 20. Board readers only.
  SELECT CASE
    WHEN p_vehicle_id IS NULL OR NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false)
      THEN jsonb_build_object('ok', false, 'code', 'not_authorized')
    ELSE jsonb_build_object('ok', true, 'history', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'at', a.at, 'action', a.action, 'old_eta', a.old_eta, 'new_eta', a.new_eta,
        'old_note', a.old_note, 'new_note', a.new_note, 'last_checked_on', a.last_checked_on,
        'by', a.actor, 'role', a.actor_role
      ) ORDER BY a.id DESC)
      FROM (
        SELECT id, at, action, old_eta, new_eta, old_note, new_note, last_checked_on, actor, actor_role
        FROM public.pdc_parts_stoppage_audit_564
        WHERE vehicle_id = p_vehicle_id
        ORDER BY id DESC
        LIMIT 20
      ) a
    ), '[]'::jsonb))
  END
$hist564$;

REVOKE ALL ON FUNCTION public.get_pdc_parts_stoppage_history_564(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_parts_stoppage_history_564(uuid) TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('parts_stoppage_manual_567', 'F181',
 'Manual parts ETA (r567): one row per vehicle, parts and workshop controllers write, everyone else reads, the email parts ETA and the JITA ETA stay the pinned bodies, and no vehicle row is written',
 $chk$
WITH fn AS (
  SELECT count(*) n,
    count(*) FILTER (WHERE p.prosecdef) sd,
    bool_and(NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')) no_anon,
    bool_and(pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')) auth_exec,
    bool_and(pg_catalog.strpos(coalesce(pg_catalog.array_to_string(p.proconfig, ','), ''), 'pg_catalog') > 0) path_ok
  FROM pg_catalog.pg_proc p
  WHERE p.oid IN (
    pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)'),
    pg_catalog.to_regprocedure('public.get_pdc_parts_stoppage_board_564()'),
    pg_catalog.to_regprocedure('public.get_pdc_parts_stoppage_history_564(uuid)'))
), pins AS (
  SELECT (SELECT count(*) FROM pdc_ops.expected_function_md5) pin_count,
    (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) parts_set,
    (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.get_pdc_parts_eta_board()')) parts_board,
    (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.get_pdc_parts_eta_board_v2()')) parts_v2,
    (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)')) parts_email,
    (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.get_pdc_jita_eta_board()')) jita_board
), body AS (
  SELECT prosrc
  FROM pg_catalog.pg_proc
  WHERE oid = pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')
), tb AS (
  SELECT count(*) n,
    count(*) FILTER (WHERE c.relrowsecurity) rls,
    count(*) FILTER (WHERE pg_catalog.has_table_privilege('authenticated', c.oid, 'INSERT')
      OR pg_catalog.has_table_privilege('authenticated', c.oid, 'UPDATE')
      OR pg_catalog.has_table_privilege('authenticated', c.oid, 'DELETE')
      OR pg_catalog.has_table_privilege('anon', c.oid, 'SELECT')) writable
  FROM pg_catalog.pg_class c
  WHERE c.oid IN (pg_catalog.to_regclass('public.pdc_parts_stoppage_564'), pg_catalog.to_regclass('public.pdc_parts_stoppage_audit_564'))
)
SELECT (SELECT n = 3 AND sd = 3 AND no_anon AND auth_exec AND path_ok FROM fn)
  AND (SELECT pin_count = 241
    AND parts_set = '88d31cbd6ca5ddd372e3143d5f8c013f'
    AND parts_board = 'decd9053241b3fe8ede99bd231ad98ec'
    AND parts_v2 = '6a0046123aeb862667dce68884318850'
    AND parts_email = 'a81b786bfc7868c3217d827933299678'
    AND jita_board = '29dcb35956acd61b6a8aa2ca07a80182' FROM pins)
  AND (SELECT pg_catalog.strpos(prosrc, 'importer') > 0
    AND pg_catalog.strpos(prosrc, 'operator') > 0
    AND pg_catalog.strpos(prosrc, 'administrator') > 0
    AND pg_catalog.strpos(prosrc, 'deleted_at IS NULL') > 0
    AND pg_catalog.strpos(prosrc, 'UPDATE public.vehicles') = 0
    AND pg_catalog.strpos(prosrc, 'DELETE FROM') = 0
    AND pg_catalog.strpos(prosrc, 'pdc_parts_eta') = 0
    AND pg_catalog.strpos(prosrc, 'pdc_jita_eta') = 0 FROM body)
  AND (SELECT n = 2 AND rls = 2 AND writable = 0 FROM tb)
  AND (SELECT count(*) FROM (
      SELECT 1 FROM public.pdc_parts_stoppage_564 GROUP BY vehicle_id HAVING count(*) > 1
    ) z) = 0
  AND NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy po
    WHERE po.polrelid IN (pg_catalog.to_regclass('public.pdc_parts_stoppage_564'), pg_catalog.to_regclass('public.pdc_parts_stoppage_audit_564'))
      AND po.polcmd <> 'r') AS ok,
  'pins '||(SELECT pin_count FROM pins)||' parts '||coalesce((SELECT parts_set FROM pins), 'missing') AS detail
$chk$,
true, 338, 'r567');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')) IS DISTINCT FROM 'fa275b45be296e9021f9f4dc570f5751' THEN RAISE EXCEPTION 'r567: set did not land'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_stoppage_board_564()')) IS DISTINCT FROM '89a8b409650f95c59f459c8b2ff31e60' THEN RAISE EXCEPTION 'r567: board read did not land'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_stoppage_history_564(uuid)')) IS DISTINCT FROM 'db31f96870cb5478e5f25426249a7e3e' THEN RAISE EXCEPTION 'r567: history did not land'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r567: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r567: set_parts_eta changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_jita_eta_board()')) IS DISTINCT FROM '29dcb35956acd61b6a8aa2ca07a80182' THEN RAISE EXCEPTION 'r567: JITA board read changed'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 PERFORM set_config('request.jwt.claims','',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_stoppage_manual_567' AND fault_id='F181' AND sort_order=338 AND added_in='r567') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r567: check parts_stoppage_manual_567 not OK: %', y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
