-- r509 (F112): Sales PMB Status uses the Control Board station icons.
-- Staging cdsmnqxtyyoeoznmbidd only. PREVIEW / NOT applied. Never touch production.
-- r508 (F121) already widened the sales receipt message-id CHECK and owns sort 293
-- and added_in r508. This preview is r509 so the two releases do not collide.
-- r499 commit ac88ab7 is not in this repository. The station colours are the board
-- strip (styles.css "All ten work tracks"), copied into sales/pmb-stations.css.
-- Board projectWorkState glyphs, in board order: Parts / JITA, Tint, Bus 4x4, Hoist,
-- Fitting, Fab, Elec, Tyre, Sublet.
--   completed check wins, then stoppage !, then booked ! when required and (parts
--   ordered or an active workshop booking or an open/booked sublet), then required
--   dot, else an en dash.
-- started (JSON) is true only for an open booking on that stage with status started.
-- That is the planner workshop-plan-chip.is-started flash. It wins over booked orange.
-- Complete and stoppage stay started=false. An open sublet with no started SUBLET
-- booking stays booked and started=false. Queued and planned stay booked, not started.
-- A deleted booking is not open. A started booking on a station that is not required
-- stays none and does not flash.
-- When p_work is passed, vehicle_work_items is not read. When p_sublet is passed,
-- pdc_sublet_bookings is not read. Null vehicle id never reads either table.
-- Does not replace visibility_source_snapshot or board_visibility_source_snapshot (r420 pins stay).
-- Pins 212 to 216. Check sales_station_icons_509 sort 294 F112.
-- Undo: supabase/rollbacks/20261023140000_r509_sales_station_icons.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r509: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r509: staging only'; END IF;
 PERFORM set_config('pdc.r509_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r509_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r509_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r509: clock tick does not match its pin'; END IF;
 IF current_setting('pdc.r509_pins')::int IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r509: expected 212 pins at tip, got %', current_setting('pdc.r509_pins'); END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.visibility_source_snapshot(boolean)') IS DISTINCT FROM 'e57e0904890225fad39c5e41ee1b14ef' THEN RAISE EXCEPTION 'r509: r420 sales snapshot pin moved'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.visibility_source_snapshot(boolean)')) IS DISTINCT FROM 'e57e0904890225fad39c5e41ee1b14ef' THEN RAISE EXCEPTION 'r509: r420 sales snapshot body moved'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.board_visibility_source_snapshot(boolean)') IS DISTINCT FROM '37a9d2d92ce5c34e8617a0058cfd3e4f' THEN RAISE EXCEPTION 'r509: r420 board snapshot pin moved'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.board_visibility_source_snapshot(boolean)')) IS DISTINCT FROM '37a9d2d92ce5c34e8617a0058cfd3e4f' THEN RAISE EXCEPTION 'r509: r420 board snapshot body moved'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_mailbox_507' AND added_in='r507' AND sort_order=292 AND fault_id='F120') THEN RAISE EXCEPTION 'r509: r507 mailbox check is not applied'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_sales_receipt_message_id_508' AND added_in='r508' AND sort_order=293 AND fault_id='F121') THEN RAISE EXCEPTION 'r509: r508 sales receipt check is not applied'; END IF;
 IF to_regprocedure('pdc_sales_private.station_icons(uuid,jsonb,jsonb,jsonb,jsonb,text)') IS NOT NULL
    OR to_regprocedure('pdc_sales_private.attach_station_icons(jsonb)') IS NOT NULL
    OR to_regprocedure('pdc_sales_private.sales_snapshot_509()') IS NOT NULL
    OR to_regprocedure('pdc_sales_private.sales_board_snapshot_509()') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sales_station_icons_509' OR added_in='r509' OR fault_id='F112' OR sort_order=294)
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r509') THEN RAISE EXCEPTION 'r509: already applied'; END IF;
END $g$;

CREATE FUNCTION pdc_sales_private.station_icons(
  p_vehicle uuid,
  p_bookings jsonb,
  p_parts jsonb,
  p_work jsonb,
  p_jita jsonb,
  p_sublet text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  work jsonb;
  sublet text;
  result jsonb := '[]'::jsonb;
  rec record;
  required boolean;
  completed boolean;
  parts_ordered boolean;
  parts_stop boolean;
  jita_on boolean;
  stopped boolean;
  started boolean;
  active boolean;
  state text;
  marker text;
  working boolean;
  b jsonb;
  token text;
BEGIN
  IF p_work IS NOT NULL THEN
    work := p_work;
  ELSIF p_vehicle IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('work_key', wi.work_key, 'required', wi.required, 'completed', wi.completed)), '[]'::jsonb)
      INTO work
      FROM public.vehicle_work_items wi
     WHERE wi.vehicle_id = p_vehicle;
  ELSE
    work := '[]'::jsonb;
  END IF;

  IF p_sublet IS NOT NULL THEN
    sublet := p_sublet;
  ELSIF p_vehicle IS NOT NULL THEN
    SELECT CASE
      WHEN s.booking_date IS NOT NULL AND s.actual_return_date IS NULL
           AND s.booking_date <= (timezone('Australia/Perth', statement_timestamp()))::date THEN 'open'
      WHEN s.booking_date IS NOT NULL AND s.actual_return_date IS NULL THEN 'booked'
      ELSE 'none'
    END INTO sublet
    FROM public.pdc_sublet_bookings s
    WHERE s.vehicle_id = p_vehicle
    ORDER BY s.booking_date NULLS LAST
    LIMIT 1;
    sublet := coalesce(sublet, 'none');
  ELSE
    sublet := 'none';
  END IF;

  jita_on := CASE
    WHEN p_jita IS NULL OR p_jita = 'null'::jsonb THEN false
    WHEN jsonb_typeof(p_jita) = 'boolean' THEN p_jita = 'true'::jsonb
    WHEN jsonb_typeof(p_jita) = 'number' THEN (p_jita #>> '{}')::numeric <> 0
    WHEN jsonb_typeof(p_jita) = 'string' THEN btrim(p_jita #>> '{}') <> '' AND btrim(p_jita #>> '{}') !~ '^0+(\.0+)?$'
    WHEN jsonb_typeof(p_jita) = 'object' THEN p_jita <> '{}'::jsonb
    WHEN jsonb_typeof(p_jita) = 'array' THEN jsonb_array_length(p_jita) > 0
    ELSE false
  END;
  parts_ordered := coalesce((nullif(p_parts->>'ordered', ''))::boolean, false);
  parts_stop := coalesce((nullif(p_parts->>'stoppage', ''))::boolean, false);

  FOR rec IN
    SELECT * FROM (VALUES
      (1, 'parts', 'Parts / JITA', ARRAY[]::text[]),
      (2, 'tint', 'Tint', ARRAY['TINT']::text[]),
      (3, 'bus4x4', 'Bus 4x4', ARRAY['BUS4X4']::text[]),
      (4, 'hoist', 'Hoist', ARRAY['HOIST']::text[]),
      (5, 'fitting', 'Fitting', ARRAY['FITTING']::text[]),
      (6, 'fabrication', 'Fab', ARRAY['FABRICATION', 'FAB']::text[]),
      (7, 'electrical', 'Elec', ARRAY['ELECTRICAL', 'ELEC']::text[]),
      (8, 'tyre', 'Tyre', ARRAY['TYRE', 'TYRES']::text[]),
      (9, 'sublet', 'Sublet', ARRAY['SUBLET']::text[])
    ) AS t(ord, key, label, stages)
    ORDER BY 1
  LOOP
    SELECT coalesce(bool_or(wi.required), false), coalesce(bool_or(wi.completed), false)
      INTO required, completed
      FROM jsonb_to_recordset(coalesce(work, '[]'::jsonb)) AS wi(work_key text, required boolean, completed boolean)
     WHERE lower(coalesce(wi.work_key, '')) = rec.key;

    stopped := false;
    started := false;
    active := false;
    FOR b IN SELECT value FROM jsonb_array_elements(coalesce(p_bookings, '[]'::jsonb))
    LOOP
      IF coalesce(b->>'deleted_at', '') <> '' OR lower(coalesce(b->>'status', '')) = 'deleted' THEN
        CONTINUE;
      END IF;
      token := upper(regexp_replace(coalesce(b->>'stage_code', b->>'stage', ''), '[^A-Za-z0-9]+', '', 'g'));
      IF token = ANY (rec.stages) THEN
        IF lower(coalesce(b->>'status', '')) = 'stoppage' THEN stopped := true; END IF;
        IF lower(coalesce(b->>'status', '')) = 'started' THEN started := true; END IF;
        IF lower(coalesce(b->>'status', '')) IN ('queued', 'planned', 'started') THEN active := true; END IF;
      END IF;
    END LOOP;

    IF completed THEN
      state := 'completed'; marker := '✓'; working := false;
    ELSIF (rec.key = 'parts' AND parts_stop) OR stopped THEN
      state := 'stoppage'; marker := '!'; working := false;
    ELSIF required AND ((rec.key = 'parts' AND parts_ordered) OR active OR (rec.key = 'sublet' AND sublet IN ('open', 'booked'))) THEN
      state := 'booked'; marker := '!';
      working := started;
    ELSIF required THEN
      state := 'required'; marker := '•'; working := false;
    ELSE
      state := 'none'; marker := '–'; working := false;
    END IF;

    result := result || jsonb_build_array(jsonb_build_object(
      'key', rec.key,
      'label', rec.label,
      'state', state,
      'marker', marker,
      'started', working,
      'jita', CASE WHEN rec.key = 'parts' THEN jita_on ELSE NULL END
    ));
  END LOOP;
  RETURN result;
END
$fn$;

CREATE FUNCTION pdc_sales_private.attach_station_icons(p_snapshot jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pdc_sales_private
AS $fn$
DECLARE items jsonb;
BEGIN
  IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot->'items') IS DISTINCT FROM 'array' THEN
    RETURN p_snapshot;
  END IF;
  SELECT coalesce(jsonb_agg(
    CASE
      WHEN nullif(e.item->>'canonical_vehicle_id', '') IS NULL
        OR e.item->>'lifecycle_state' = 'completed'
        OR lower(btrim(coalesce(e.item->>'pmb_location', ''))) = 'completed'
      THEN e.item || jsonb_build_object('pmb_stations', '[]'::jsonb)
      ELSE e.item || jsonb_build_object('pmb_stations', pdc_sales_private.station_icons(
        (e.item->>'canonical_vehicle_id')::uuid,
        CASE
          WHEN coalesce(e.item->>'pmb_stoppage_started_at', '') <> '' AND coalesce(e.item->>'pmb_stoppage_cleared_at', '') = ''
          THEN coalesce(e.item->'bay_bookings', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
            'status', 'stoppage',
            'stage', coalesce(e.item->>'pmb_bay_stage', e.item->>'pmb_stage', ''),
            'stoppage_reason', e.item->>'pmb_stoppage_reason'))
          ELSE e.item->'bay_bookings'
        END,
        e.item->'parts',
        NULL,
        e.item->'jita',
        NULL))
    END
    ORDER BY e.ord), '[]'::jsonb) INTO items
  FROM jsonb_array_elements(p_snapshot->'items') WITH ORDINALITY e(item, ord);
  RETURN jsonb_set(p_snapshot, '{items}', items);
END
$fn$;

CREATE FUNCTION pdc_sales_private.sales_snapshot_509()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pdc_sales_private
AS $fn$
  SELECT pdc_sales_private.attach_station_icons(pdc_sales_private.snapshot_with_autocare());
$fn$;

CREATE FUNCTION pdc_sales_private.sales_board_snapshot_509()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pdc_sales_private
AS $fn$
  SELECT pdc_sales_private.attach_station_icons(pdc_sales_private.board_snapshot_with_autocare());
$fn$;

CREATE OR REPLACE FUNCTION public.get_broome_sales_snapshot()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path='pg_catalog','pdc_sales_private'
AS $fn$ SELECT pdc_sales_private.sales_snapshot_509(); $fn$;

CREATE OR REPLACE FUNCTION public.get_broome_sales_board_snapshot()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog
AS $fn$ SELECT pdc_sales_private.sales_board_snapshot_509(); $fn$;

REVOKE ALL ON FUNCTION pdc_sales_private.station_icons(uuid,jsonb,jsonb,jsonb,jsonb,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_sales_private.attach_station_icons(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_sales_private.sales_snapshot_509() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION pdc_sales_private.sales_board_snapshot_509() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.sales_snapshot_509() TO authenticated;
GRANT EXECUTE ON FUNCTION pdc_sales_private.sales_board_snapshot_509() TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature, prosrc_md5, release, note, updated_at)
SELECT v.signature, md5(p.prosrc), 'r509',
  'r509 (F112): Sales station icons match the PMB board; started=true flashes blue',
  now()
FROM (VALUES
  ('pdc_sales_private.station_icons(uuid,jsonb,jsonb,jsonb,jsonb,text)'),
  ('pdc_sales_private.attach_station_icons(jsonb)'),
  ('pdc_sales_private.sales_snapshot_509()'),
  ('pdc_sales_private.sales_board_snapshot_509()')
) AS v(signature)
JOIN pg_proc p ON p.oid = to_regprocedure(v.signature);

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('sales_station_icons_509', 'F112', 'Sales station icons (r509): board order and glyphs; completed and stoppage win over a started booking and do not flash; queued and planned do not flash; an open sublet without a started SUBLET booking does not flash; a started SUBLET booking does flash; parts ordered is booked and does not flash; JITA is separate from the parts glyph; required with no booking is the dot; a started booking that is not required stays none; a deleted started booking is not open; pins match the four new bodies; public wrappers call the r509 snapshots and stay invoker',
 $chk509$WITH cases(label, bookings, parts, work, jita, sublet, key, marker, state, working) AS (
  VALUES
   ('required', '[]'::jsonb, NULL::jsonb, '[{"work_key":"tint","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'tint', '•', 'required', 'false'),
   ('planned', '[{"status":"planned","stage":"Fitting"}]'::jsonb, NULL::jsonb, '[{"work_key":"fitting","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'fitting', '!', 'booked', 'false'),
   ('started', '[{"status":"started","stage_code":"FITTING"}]'::jsonb, NULL::jsonb, '[{"work_key":"fitting","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'fitting', '!', 'booked', 'true'),
   ('completed_wins', '[{"status":"started","stage":"Fitting"}]'::jsonb, NULL::jsonb, '[{"work_key":"fitting","required":true,"completed":true}]'::jsonb, 'null'::jsonb, 'none', 'fitting', '✓', 'completed', 'false'),
   ('stoppage', '[{"status":"stoppage","stage":"Fab"}]'::jsonb, NULL::jsonb, '[{"work_key":"fabrication","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'fabrication', '!', 'stoppage', 'false'),
   ('queued', '[{"status":"queued","stage":"Hoist"}]'::jsonb, NULL::jsonb, '[{"work_key":"hoist","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'hoist', '!', 'booked', 'false'),
   ('parts_ordered', '[]'::jsonb, '{"ordered":true}'::jsonb, '[{"work_key":"parts","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'parts', '!', 'booked', 'false'),
   ('jita', '[]'::jsonb, NULL::jsonb, '[]'::jsonb, '"J1"'::jsonb, 'none', 'parts', '–', 'none', 'false'),
   ('sublet_open', '[]'::jsonb, NULL::jsonb, '[{"work_key":"sublet","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'open', 'sublet', '!', 'booked', 'false'),
   ('sublet_future', '[]'::jsonb, NULL::jsonb, '[{"work_key":"sublet","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'booked', 'sublet', '!', 'booked', 'false'),
   ('sublet_started', '[{"status":"started","stage_code":"SUBLET"}]'::jsonb, NULL::jsonb, '[{"work_key":"sublet","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'sublet', '!', 'booked', 'true'),
   ('blocked_beats_started', '[{"status":"started","stage":"Fab"},{"status":"stoppage","stage":"Fab"}]'::jsonb, NULL::jsonb, '[{"work_key":"fabrication","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'fabrication', '!', 'stoppage', 'false'),
   ('deleted_started', '[{"status":"started","deleted_at":"2026-10-23T00:00:00Z","stage":"Fitting"}]'::jsonb, NULL::jsonb, '[{"work_key":"fitting","required":true,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'fitting', '•', 'required', 'false'),
   ('started_not_required', '[{"status":"started","stage":"Tyre"}]'::jsonb, NULL::jsonb, '[{"work_key":"tyre","required":false,"completed":false}]'::jsonb, 'null'::jsonb, 'none', 'tyre', '–', 'none', 'false')
), ev AS (
  SELECT c.label, c.marker AS want_marker, c.state AS want_state, c.working AS want_started,
    s.elem->>'marker' AS got_marker, s.elem->>'state' AS got_state, s.elem->>'started' AS got_started, s.elem->>'jita' AS got_jita
  FROM cases c
  CROSS JOIN LATERAL jsonb_array_elements(pdc_sales_private.station_icons(NULL::uuid, c.bookings, c.parts, c.work, c.jita, c.sublet)) AS s(elem)
  WHERE s.elem->>'key' = c.key
), keyed AS (
  SELECT pdc_sales_private.station_icons(NULL::uuid, '[]'::jsonb, NULL::jsonb, '[]'::jsonb, '"J1"'::jsonb, 'none') AS icons
), keys AS (
  SELECT string_agg(s.elem->>'key', ',' ORDER BY s.ordinality) AS k,
         string_agg(s.elem->>'label', ',' ORDER BY s.ordinality) AS labels
  FROM keyed
  CROSS JOIN LATERAL jsonb_array_elements(keyed.icons) WITH ORDINALITY AS s(elem, ordinality)
), jita AS (
  SELECT s.elem->>'jita' AS flag
  FROM keyed
  CROSS JOIN LATERAL jsonb_array_elements(keyed.icons) AS s(elem)
  WHERE s.elem->>'key' = 'parts'
), pins AS (
  SELECT e.signature, e.prosrc_md5, md5(p.prosrc) AS live, p.prosecdef
  FROM pdc_ops.expected_function_md5 e
  JOIN pg_proc p ON p.oid = to_regprocedure(e.signature)
  WHERE e.release = 'r509'
), wraps AS (
  SELECT p.prosrc, p.prosecdef
  FROM pg_proc p
  WHERE p.oid IN (
    to_regprocedure('public.get_broome_sales_snapshot()'),
    to_regprocedure('public.get_broome_sales_board_snapshot()')
  )
)
SELECT (SELECT count(*) = 14 FROM ev WHERE got_marker IS NOT DISTINCT FROM want_marker AND got_state IS NOT DISTINCT FROM want_state AND got_started IS NOT DISTINCT FROM want_started)
   AND (SELECT count(*) = 1 FROM keys WHERE k = 'parts,tint,bus4x4,hoist,fitting,fabrication,electrical,tyre,sublet'
        AND labels = 'Parts / JITA,Tint,Bus 4x4,Hoist,Fitting,Fab,Elec,Tyre,Sublet')
   AND (SELECT count(*) = 1 FROM jita WHERE flag = 'true')
   AND (SELECT count(*) = 4 FROM pins WHERE live IS NOT DISTINCT FROM prosrc_md5 AND prosecdef)
   AND (SELECT count(*) = 1 FROM wraps WHERE prosrc LIKE '%sales_snapshot_509%' AND prosrc NOT LIKE '%board_snapshot_509%' AND prosecdef IS FALSE)
   AND (SELECT count(*) = 1 FROM wraps WHERE prosrc LIKE '%sales_board_snapshot_509%' AND prosecdef IS FALSE)
   AND (SELECT count(*) = 1 FROM pdc_ops.expected_function_md5 WHERE signature = 'pdc_sales_private.visibility_source_snapshot(boolean)' AND prosrc_md5 = 'e57e0904890225fad39c5e41ee1b14ef')
   AND (SELECT count(*) = 1 FROM pdc_ops.expected_function_md5 WHERE signature = 'pdc_sales_private.board_visibility_source_snapshot(boolean)' AND prosrc_md5 = '37a9d2d92ce5c34e8617a0058cfd3e4f')
 AS ok,
 'cases '||(SELECT count(*) FILTER (WHERE got_marker IS NOT DISTINCT FROM want_marker AND got_state IS NOT DISTINCT FROM want_state AND got_started IS NOT DISTINCT FROM want_started) FROM ev)||'/14'
 ||coalesce(' WRONG '||(SELECT string_agg(label||' got '||coalesce(got_state,'null')||'/'||coalesce(got_marker,'null')||'/'||coalesce(got_started,'null'), '; ') FROM ev WHERE got_marker IS DISTINCT FROM want_marker OR got_state IS DISTINCT FROM want_state OR got_started IS DISTINCT FROM want_started), '')
 ||'; keys '||coalesce((SELECT k FROM keys), 'missing')
 ||'; jita '||coalesce((SELECT flag FROM jita), 'missing')
 ||'; pins '||(SELECT count(*) FROM pins WHERE live IS NOT DISTINCT FROM prosrc_md5)||'/4'
 AS detail$chk509$, true, 294, 'r509');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 216
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r509') IS DISTINCT FROM 4 THEN RAISE EXCEPTION 'r509: expected 216 pins (4 new)'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r509' AND md5(p.prosrc)=e.prosrc_md5 AND p.prosecdef) IS DISTINCT FROM 4 THEN RAISE EXCEPTION 'r509: a new pin does not match its body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r509_tick') THEN RAISE EXCEPTION 'r509: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.visibility_source_snapshot(boolean)')) IS DISTINCT FROM 'e57e0904890225fad39c5e41ee1b14ef' THEN RAISE EXCEPTION 'r509: r420 sales snapshot changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.board_visibility_source_snapshot(boolean)')) IS DISTINCT FROM '37a9d2d92ce5c34e8617a0058cfd3e4f' THEN RAISE EXCEPTION 'r509: r420 board snapshot changed'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_snapshot()')) IS NOT FALSE THEN RAISE EXCEPTION 'r509: sales snapshot wrapper must stay invoker'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_board_snapshot()')) IS NOT FALSE THEN RAISE EXCEPTION 'r509: board snapshot wrapper must stay invoker'; END IF;
 IF EXISTS (
   SELECT 1 FROM pg_proc p
   WHERE p.oid IN (
     to_regprocedure('pdc_sales_private.station_icons(uuid,jsonb,jsonb,jsonb,jsonb,text)'),
     to_regprocedure('pdc_sales_private.attach_station_icons(jsonb)')
   ) AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
 ) THEN RAISE EXCEPTION 'r509: station_icons and attach must stay owner-only'; END IF;
 IF NOT has_function_privilege('authenticated', to_regprocedure('pdc_sales_private.sales_snapshot_509()'), 'EXECUTE') THEN RAISE EXCEPTION 'r509: sales snapshot not granted'; END IF;
 IF NOT has_function_privilege('authenticated', to_regprocedure('pdc_sales_private.sales_board_snapshot_509()'), 'EXECUTE') THEN RAISE EXCEPTION 'r509: board snapshot not granted'; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='sales_station_icons_509';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r509: sales_station_icons_509 failed: %', y; END IF;
END $g$;
