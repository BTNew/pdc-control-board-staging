-- r817 (F456): Craig 2 Nov 2026 07:25 AWST: "look at the clock please and optimise".
-- Since 06:00 the workshop clock tick ran ~2.0 s every minute (0.07 s overnight). Cause: an unstarted planned job slides
-- with the clock every minute (r754b, Craig's choice), which makes every minute a full plan of the one connected
-- workshop graph (311 of 321 live bookings). That plan worked out each planned booking's hours twice from its operation
-- lines (capacity duration ~430 ms, then the effective-end cache ~550 ms), and the re-saves of ~52 bookings worked them out
-- again in their checks. Same answer each time: the tick does not change any operation line.
-- Fix: the tick works out each booking's base minutes once, into a temp table owned by the tick (the same guarded pattern
-- as pdc_clock_effective_ends), and workshop_booking_capacity_base_minutes reads it while the tick runs. A row is used only
-- when every booking field the answer depends on still matches; otherwise it is worked out as before. Outside the tick
-- nothing changes. The schedule the tick produces is identical (checked on a dry run: same plans, same moves).
-- Undo: re-create workshop_booking_capacity_base_minutes from the original SQL body and remove the two r817 lines from the tick.
DO $r817$
DECLARE
  sig regprocedure := 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;
  v_old text; v_new text; v_def text;
  a1 text := E' DROP TABLE IF EXISTS pg_temp.clock_linked_plan;\n CREATE TEMP TABLE clock_linked_plan ON COMMIT DROP AS';
  b1 text := E' DROP TABLE IF EXISTS pg_temp.clock_linked_plan;\n'
    || E' -- r817 (F456): each booking''s base minutes once per tick (read by workshop_booking_capacity_base_minutes).\n'
    || E' DROP TABLE IF EXISTS pg_temp.pdc_clock_base_minutes;\n'
    || E' CREATE TEMP TABLE pdc_clock_base_minutes ON COMMIT DROP AS\n'
    || E' SELECT b.id,b.vehicle_id,b.stage_id,b.status,b.work_category,b.work_category_scope,b.capacity_base_minutes,b.capacity_estimate_minutes,\n'
    || E'  b.default_duration_minutes,public.workshop_booking_capacity_base_minutes(b.id) base\n'
    || E' FROM public.workshop_bookings b WHERE b.deleted_at IS NULL AND b.status IN(''planned'',''queued'',''started'',''stoppage'')\n'
    || E'  AND NOT (b.status=''queued'' AND b.bay_id IS NULL);\n'
    || E' CREATE UNIQUE INDEX ON pdc_clock_base_minutes(id);\n'
    || E' CREATE TEMP TABLE clock_linked_plan ON COMMIT DROP AS';
  a2 text := E' DROP TABLE pg_temp.pdc_clock_effective_ends;\n';
  b2 text := E' DROP TABLE pg_temp.pdc_clock_effective_ends;\n DROP TABLE IF EXISTS pg_temp.pdc_clock_base_minutes; -- r817 (F456)\n';
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 606 OR fault_id = 'F456' OR added_in = 'r817') THEN RAISE EXCEPTION 'r817: sort 606 or F456 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r817: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF strpos(v_old, 'r817 (F456)') > 0 THEN RAISE EXCEPTION 'r817: already applied'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r817: tick anchor 1 not found once'; END IF;
  IF (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1 THEN RAISE EXCEPTION 'r817: tick anchor 2 not found once'; END IF;
  v_new := replace(replace(v_old, a1, b1), a2, b2);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r817: tick readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
END $r817$;

CREATE OR REPLACE FUNCTION public.workshop_booking_capacity_base_minutes(p_booking_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE result numeric;
BEGIN
 -- r817 (F456): inside the clock tick, use the tick's own once-per-tick answer when the booking still matches it.
 IF to_regclass('pg_temp.pdc_clock_base_minutes') IS NOT NULL AND EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=to_regclass('pg_temp.pdc_clock_base_minutes')
   AND c.relkind='r' AND c.relpersistence='t'
   AND c.relowner=(SELECT proowner FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)) THEN
  SELECT m.base INTO result FROM pg_temp.pdc_clock_base_minutes m
   JOIN public.workshop_bookings b ON b.id=m.id
    AND b.vehicle_id IS NOT DISTINCT FROM m.vehicle_id AND b.stage_id IS NOT DISTINCT FROM m.stage_id AND b.status IS NOT DISTINCT FROM m.status
    AND b.work_category IS NOT DISTINCT FROM m.work_category AND b.work_category_scope IS NOT DISTINCT FROM m.work_category_scope
    AND b.capacity_base_minutes IS NOT DISTINCT FROM m.capacity_base_minutes AND b.capacity_estimate_minutes IS NOT DISTINCT FROM m.capacity_estimate_minutes
    AND b.default_duration_minutes IS NOT DISTINCT FROM m.default_duration_minutes
   WHERE m.id=p_booking_id;
  IF FOUND THEN RETURN result; END IF;
 END IF;
 RETURN (
 SELECT CASE WHEN b.capacity_base_minutes IS NULL THEN greatest(q.minutes,b.default_duration_minutes)::numeric
 ELSE greatest(1,b.capacity_base_minutes+CASE WHEN q.minutes IS NOT NULL AND b.capacity_estimate_minutes IS NOT NULL
  THEN q.minutes-b.capacity_estimate_minutes ELSE 0 END) END
 FROM public.workshop_bookings b
 CROSS JOIN LATERAL(SELECT pdc_work_categories_private.minutes(b.id,b.vehicle_id,b.stage_id) minutes) q
 WHERE b.id=p_booking_id);
END
$function$;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('clock_tick_base_minutes_memo_817', 'F456',
  'Clock (r817): the tick works out base minutes once per tick; the memo is read only when the booking fields still match, and never outside the tick.',
  $chk$
SELECT strpos(t.src, 'CREATE TEMP TABLE pdc_clock_base_minutes ON COMMIT DROP AS') > 0
   AND strpos(t.src, 'DROP TABLE IF EXISTS pg_temp.pdc_clock_base_minutes; -- r817 (F456)') > 0
   AND strpos(f.src, 'b.default_duration_minutes IS NOT DISTINCT FROM m.default_duration_minutes') > 0
   AND strpos(f.src, 'relowner=(SELECT proowner FROM pg_proc WHERE oid=''public.workshop_clock_tick(boolean,timestamptz)''::regprocedure)') > 0
   AND to_regclass('pg_temp.pdc_clock_base_minutes') IS NULL
 AS ok, 'clock base-minutes memo guarded' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) t,
     (SELECT prosrc src FROM pg_proc WHERE oid = 'public.workshop_booking_capacity_base_minutes(uuid)'::regprocedure) f
$chk$, true, 606, 'r817');
