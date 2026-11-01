-- r799 (F409) / sort 579. Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 08:16 AWST: "Yes, build it to test, make sure NOTHING
-- BREAKS ... keep todays columns for all departments". Vehicle Locations with Department 138 picked shows a column per Bus 4x4
-- category (Mechanical, Accessories, Electrical, QA, Pit) instead of one Bus 4x4 column; Department 139 drops Bus 4x4.
-- This migration adds the per-category read the board needs. Nothing existing changes:
--   * pdc_work_categories_private.bus_category_completion_799(ids): one row per vehicle and Bus 4x4 category with total, done,
--     complete (every line ticked, or the Bus 4x4 override with no line part-way: the r578 rule), booked (an open Bus 4x4 booking
--     for that category) and stoppage. Pit lines are counted here (the board column is for them), unlike the single icon (r810).
--   * public.list_station_icon_completion_578 returns the r578 rows followed by these rows (work_key 'bus4x4:BUS_MECHANICAL' ...).
--     The r578 private function, its check and every other reader are untouched; the client keeps category rows apart.
-- Rollback: supabase/rollbacks/20261101084500_r799_bus_category_columns.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'public.list_station_icon_completion_578(uuid[])@r799pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'public.list_station_icon_completion_578(uuid[])'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $g$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r799: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 579 OR fault_id = 'F409' OR added_in = 'r799') THEN RAISE EXCEPTION 'r799: sort 579 or F409 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.list_station_icon_completion_578(uuid[])'::regprocedure) <> 'df6ea3b81690d85efd750e32a6f7098d' THEN RAISE EXCEPTION 'r799: list_station_icon_completion_578 is not the expected body'; END IF;
  IF to_regprocedure('pdc_work_categories_private.bus_category_completion_799(uuid[])') IS NOT NULL THEN RAISE EXCEPTION 'r799: already applied'; END IF;
END $g$;

CREATE FUNCTION pdc_work_categories_private.bus_category_completion_799(p_vehicle_ids uuid[])
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
WITH ids AS (
 SELECT DISTINCT id FROM pg_catalog.unnest(coalesce(p_vehicle_ids, '{}'::uuid[])) AS id WHERE id IS NOT NULL LIMIT 1000
), raw AS (
 SELECT ids.id AS vehicle_id, l
 FROM ids CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(coalesce(public.pdc_qc_operation_lines_379(ids.id), '[]'::jsonb)) l
), known AS (
 SELECT vehicle_id, l->>'line_identity' AS line_identity,
  pg_catalog.upper(pg_catalog.btrim(coalesce(l->>'work_category', ''))) AS cat,
  coalesce((l->>'completed')::boolean, false) AS qc_done
 FROM raw
 WHERE coalesce((l->>'active')::boolean, true) AND coalesce((l->>'rejected')::boolean, false) = false AND l->>'line_identity' IS NOT NULL
), mapped AS (
 -- a line handed to another station (r583) leaves its category; a hand-off into a Bus category joins that category
 SELECT k.vehicle_id, k.line_identity, k.qc_done,
  CASE WHEN h.to_stage_code IS NULL THEN k.cat
       WHEN pg_catalog.upper(pg_catalog.btrim(h.to_stage_code)) IN ('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN pg_catalog.upper(pg_catalog.btrim(h.to_stage_code))
       ELSE NULL END AS cat
 FROM known k
 LEFT JOIN public.pdc_line_handoff_583 h ON h.vehicle_id = k.vehicle_id AND h.line_identity = k.line_identity
), uniq AS (
 SELECT vehicle_id, cat, line_identity, bool_or(qc_done) AS qc_done
 FROM mapped WHERE cat IN ('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT')
 GROUP BY vehicle_id, cat, line_identity
), panel AS (
 SELECT c.vehicle_id, c.line_identity, c.completed FROM public.pdc_panel_line_completion_565 c JOIN ids ON ids.id = c.vehicle_id
), fitter AS (
 SELECT DISTINCT ON (wb.vehicle_id, p.line_identity) wb.vehicle_id, p.line_identity, p.completed
 FROM pdc_fitter_private.operation_progress p
 JOIN public.workshop_bookings wb ON wb.id = p.booking_id
 JOIN ids ON ids.id = wb.vehicle_id
 WHERE wb.deleted_at IS NULL
 ORDER BY wb.vehicle_id, p.line_identity, p.updated_at DESC, p.booking_id
), tallied AS (
 SELECT u.vehicle_id, u.cat, count(*) AS total,
  count(*) FILTER (WHERE u.qc_done OR coalesce(panel.completed, false) OR coalesce(fitter.completed, false)) AS done
 FROM uniq u
 LEFT JOIN panel ON panel.vehicle_id = u.vehicle_id AND panel.line_identity = u.line_identity
 LEFT JOIN fitter ON fitter.vehicle_id = u.vehicle_id AND fitter.line_identity = u.line_identity
 GROUP BY u.vehicle_id, u.cat
), ovr AS (
 SELECT o.vehicle_id, o.completed, o.actor_email, o.acted_at
 FROM public.pdc_station_completion_override_578 o JOIN ids ON ids.id = o.vehicle_id WHERE o.work_key = 'bus4x4'
), booked AS (
 SELECT b.vehicle_id, pg_catalog.upper(pg_catalog.btrim(b.work_category)) AS cat,
  bool_or(b.status::text IN ('queued','planned','started')) AS booked,
  bool_or(b.status::text = 'stoppage') AS stoppage,
  pg_catalog.max(b.stoppage_reason) FILTER (WHERE b.status::text = 'stoppage') AS stoppage_reason
 FROM public.workshop_bookings b
 JOIN public.workshop_stages s ON s.id = b.stage_id
 JOIN ids ON ids.id = b.vehicle_id
 WHERE b.deleted_at IS NULL AND s.code = 'BUS_4X4' AND b.work_category IS NOT NULL
 GROUP BY b.vehicle_id, pg_catalog.upper(pg_catalog.btrim(b.work_category))
)
SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 'vehicle_id', t.vehicle_id,
 'work_key', 'bus4x4:' || t.cat,
 'category', t.cat,
 'complete', (t.total > 0 AND t.done = t.total) OR (coalesce(o.completed, false) AND t.done = 0),
 'total', t.total,
 'done', t.done,
 'override', coalesce(o.completed, false) AND t.done < t.total,
 'override_email', CASE WHEN coalesce(o.completed, false) THEN o.actor_email END,
 'acted_at', CASE WHEN coalesce(o.completed, false) THEN o.acted_at END,
 'booked', coalesce(bk.booked, false),
 'stoppage', coalesce(bk.stoppage, false),
 'stoppage_reason', bk.stoppage_reason
) ORDER BY t.vehicle_id, t.cat), '[]'::jsonb)
FROM tallied t
LEFT JOIN ovr o ON o.vehicle_id = t.vehicle_id
LEFT JOIN booked bk ON bk.vehicle_id = t.vehicle_id AND bk.cat = t.cat
$function$;

REVOKE ALL ON FUNCTION pdc_work_categories_private.bus_category_completion_799(uuid[]) FROM PUBLIC, anon, authenticated;

DO $r799$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'public.list_station_icon_completion_578(uuid[])'::regprocedure;
  a1 text := $a$ RETURN pg_catalog.jsonb_build_object('ok', true, 'stations', pdc_work_categories_private.station_icon_completion_578(v_ids));$a$;
  b1 text := $a$ -- r799 (F409): the r578 rows, then one row per Bus 4x4 category (work_key 'bus4x4:<category>') for the Department 138 columns.
 RETURN pg_catalog.jsonb_build_object('ok', true, 'stations',
  pdc_work_categories_private.station_icon_completion_578(v_ids) || pdc_work_categories_private.bus_category_completion_799(v_ids));$a$;
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r799: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r799: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE position(md5(v_old) IN check_sql) > 0;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('bus_category_columns_799', 'F409',
    'Board (r799): list_station_icon_completion_578 appends one row per Bus 4x4 category; the category function is private (no anon/authenticated execute) and every category row has a matching r578 bus4x4 total.',
    $chk$
WITH ids AS (SELECT array_agg(v.id) a FROM (SELECT v.id FROM public.vehicles v JOIN public.workshop_bookings b ON b.vehicle_id = v.id JOIN public.workshop_stages s ON s.id = b.stage_id
             WHERE v.deleted_at IS NULL AND s.code = 'BUS_4X4' AND b.deleted_at IS NULL ORDER BY v.updated_at DESC LIMIT 60) v),
 cat AS (SELECT r.* FROM ids, pg_catalog.jsonb_to_recordset(pdc_work_categories_private.bus_category_completion_799(ids.a)) AS r(vehicle_id uuid, category text, total int, done int, complete boolean)),
 sta AS (SELECT r.* FROM ids, pg_catalog.jsonb_to_recordset(pdc_work_categories_private.station_icon_completion_578(ids.a)) AS r(vehicle_id uuid, work_key text, total int, done int))
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.list_station_icon_completion_578(uuid[])')), 'bus_category_completion_799(v_ids)') > 0
   AND NOT has_function_privilege('anon', to_regprocedure('pdc_work_categories_private.bus_category_completion_799(uuid[])'), 'EXECUTE')
   AND NOT has_function_privilege('authenticated', to_regprocedure('pdc_work_categories_private.bus_category_completion_799(uuid[])'), 'EXECUTE')
   AND NOT EXISTS (SELECT 1 FROM cat WHERE cat.done > cat.total OR cat.total <= 0 OR (cat.complete AND cat.done <> cat.total AND cat.done <> 0))
   AND NOT EXISTS (SELECT 1 FROM cat WHERE cat.category <> 'BUS_PIT' AND NOT EXISTS (SELECT 1 FROM sta WHERE sta.vehicle_id = cat.vehicle_id AND sta.work_key = 'bus4x4' AND sta.total >= cat.total))
 AS ok, 'category rows ' || (SELECT count(*) FROM cat)::text || ' on ' || (SELECT count(DISTINCT vehicle_id) FROM cat)::text || ' bus vehicles' AS detail
$chk$, true, 579, 'r799');
END $r799$;
