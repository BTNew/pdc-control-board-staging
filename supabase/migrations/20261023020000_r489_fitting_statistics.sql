-- r489 (F102): Admin > Fitting statistics. PREPARED ONLY - NOT APPLIED (overnight preview 22/23 Oct 2026; apply only after Craig approves).
-- Staging cdsmnqxtyyoeoznmbidd only. Adds ONE new read-only function and changes nothing else:
--   public.get_pdc_fitting_statistics_489(p_days integer) RETURNS jsonb, plpgsql STABLE SECURITY DEFINER, search_path pg_catalog,
--   EXECUTE authenticated only (not anon / PUBLIC); returns {ok:false, code:'permission_denied'} unless the caller is an approved,
--   active administrator (same test as get_pdc_update_history). p_days must be 7, 30, 90 or 365.
-- Why a new function: the per-item Start / Done times live in pdc_fitter_private.operation_timing and the Done ticks in
--   pdc_fitter_private.operation_progress (r440 / 20261020160000_bay_item_start_done); that schema is not exposed to the website,
--   and no existing RPC returns them across bookings (get_fitter_job is one booking for one technician).
-- What it returns per category (line work category, else booking category, else station): Done lines in the period, how many of them
--   were timed (Start then Done), whole station jobs completed with their average clock time Start work -> Complete, and per line type
--   (job card description, case/space-insensitive): completed, timed, average / median / fastest / slowest minutes on the job clock,
--   and the average allowance (estimated hours). No vehicle, stock number, customer or staff names are returned.
-- Reads only: operation_progress, operation_timing, workshop_bookings, workshop_stages, qc_operation_lines_cache, pdc_user_roles.
--   Writes nothing (no cache refill, no revision bump). New pin (pins +1 -> 208) and check fitting_statistics_489 (sort 289, F102).
-- prosrc md5 306a3d7a5ecd306492dcfafe00c70005; body is LF only.
-- Undo: supabase/rollbacks/20261023020000_r489_fitting_statistics.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r489: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r489: staging only'; END IF;
 PERFORM set_config('pdc.r489_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r489_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r489_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r489_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r489: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF to_regprocedure('public.get_pdc_fitting_statistics_489(integer)') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_fitting_statistics_489(integer)' OR release='r489')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='fitting_statistics_489' OR added_in='r489') THEN RAISE EXCEPTION 'r489: already applied (or pinned since prepared)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=289 OR fault_id='F102') THEN RAISE EXCEPTION 'r489: sort_order 289 / F102 taken'; END IF;
END $g$;

CREATE FUNCTION public.get_pdc_fitting_statistics_489(p_days integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE result jsonb; v_since timestamptz;
BEGIN
 -- r489 (F102): Admin > Fitting statistics. Read only; administrators only (same test as get_pdc_update_history).
 IF auth.uid() IS NULL OR NOT EXISTS (
   SELECT 1 FROM public.pdc_user_roles r
   WHERE r.auth_user_id = auth.uid() AND r.role::text = 'administrator'
     AND r.active IS TRUE AND r.account_status = 'approved') THEN
   RETURN jsonb_build_object('ok', false, 'code', 'permission_denied');
 END IF;
 IF p_days IS NULL OR p_days NOT IN (7, 30, 90, 365) THEN
   RETURN jsonb_build_object('ok', false, 'code', 'invalid_period');
 END IF;
 v_since := statement_timestamp() - make_interval(days => p_days);
 -- A completed line = a Done tick on a bay booking (pdc_fitter_private.operation_progress, the fitter / controller tick).
 -- Its time = Start -> Done on the job clock (operation_timing.actual_seconds, r440 item timing), only when the item was
 -- started first and is still 'done' for the same line scope. Line type = the job card line description (QC line cache),
 -- grouped case- and space-insensitively; category = the line's work category, else the booking's, else the station.
 WITH done AS MATERIALIZED (
   SELECT p.booking_id, p.line_identity, b.vehicle_id, b.work_category AS booking_category, s.code AS stage_code,
          t.actual_seconds
   FROM pdc_fitter_private.operation_progress p
   JOIN public.workshop_bookings b ON b.id = p.booking_id AND b.deleted_at IS NULL
   JOIN public.workshop_stages s ON s.id = b.stage_id
   LEFT JOIN pdc_fitter_private.operation_timing t
     ON t.booking_id = p.booking_id AND t.line_identity = p.line_identity AND t.status = 'done'
    AND t.scope_hash IS NOT DISTINCT FROM p.scope_hash AND t.actual_seconds IS NOT NULL
   WHERE p.completed IS TRUE AND p.updated_at >= v_since
 ),
 lines AS (
   SELECT d.*, l.line->>'description' AS description, l.line->>'work_category' AS line_category,
          CASE WHEN jsonb_typeof(l.line->'estimated_hours') = 'number' THEN (l.line->>'estimated_hours')::numeric END AS est_hours
   FROM done d
   LEFT JOIN pdc_work_categories_private.qc_operation_lines_cache c ON c.vehicle_id = d.vehicle_id
   LEFT JOIN LATERAL (SELECT x AS line FROM jsonb_array_elements(CASE WHEN jsonb_typeof(c.lines) = 'array' THEN c.lines ELSE '[]'::jsonb END) x
                      WHERE x->>'line_identity' = d.line_identity LIMIT 1) l ON true
 ),
 typed AS (
   SELECT coalesce(nullif(line_category, ''), nullif(booking_category, ''), stage_code) AS category,
          coalesce(nullif(lower(regexp_replace(btrim(description), '\s+', ' ', 'g')), ''), '~unknown') AS type_key,
          nullif(regexp_replace(btrim(description), '\s+', ' ', 'g'), '') AS description,
          actual_seconds / 60.0 AS actual_minutes, est_hours * 60 AS est_minutes
   FROM lines
 ),
 per_type AS (
   SELECT category, type_key, min(description) AS line_type,
          count(*) AS completed, count(actual_minutes) AS timed,
          round(avg(actual_minutes), 1) AS avg_minutes,
          round((percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_minutes))::numeric, 1) AS median_minutes,
          round(min(actual_minutes), 1) AS min_minutes, round(max(actual_minutes), 1) AS max_minutes,
          round(avg(est_minutes) FILTER (WHERE est_minutes > 0), 1) AS avg_allowance_minutes
   FROM typed GROUP BY category, type_key
 ),
 -- Whole station jobs finished in the period: clock time from Start work to Complete.
 jobs AS (
   SELECT coalesce(nullif(b.work_category, ''), s.code) AS category, count(*) AS jobs_completed,
          round(avg(extract(epoch FROM b.actual_end_at - b.actual_start_at) / 60.0), 1) AS job_avg_elapsed_minutes
   FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id = b.stage_id
   WHERE b.deleted_at IS NULL AND b.status::text = 'completed' AND b.actual_start_at IS NOT NULL
     AND b.actual_end_at >= b.actual_start_at AND b.actual_end_at >= v_since
   GROUP BY 1
 ),
 cats AS (SELECT category FROM per_type UNION SELECT category FROM jobs)
 SELECT jsonb_build_object(
   'ok', true, 'generated_at', statement_timestamp(), 'days', p_days, 'since', v_since,
   'timing_started_at', (SELECT min(started_at) FROM pdc_fitter_private.operation_timing),
   'categories', coalesce((SELECT jsonb_agg(jsonb_build_object(
       'category', c.category,
       'completed', coalesce((SELECT sum(t.completed) FROM per_type t WHERE t.category = c.category), 0),
       'timed', coalesce((SELECT sum(t.timed) FROM per_type t WHERE t.category = c.category), 0),
       'jobs_completed', coalesce(j.jobs_completed, 0), 'job_avg_elapsed_minutes', j.job_avg_elapsed_minutes,
       'lines', coalesce((SELECT jsonb_agg(jsonb_build_object(
           'line_type', CASE WHEN t.type_key = '~unknown' THEN NULL ELSE t.line_type END,
           'completed', t.completed, 'timed', t.timed, 'avg_minutes', t.avg_minutes, 'median_minutes', t.median_minutes,
           'min_minutes', t.min_minutes, 'max_minutes', t.max_minutes, 'avg_allowance_minutes', t.avg_allowance_minutes)
         ORDER BY t.completed DESC, t.type_key) FROM per_type t WHERE t.category = c.category), '[]'::jsonb)
     ) ORDER BY c.category) FROM cats c LEFT JOIN jobs j ON j.category = c.category), '[]'::jsonb))
 INTO result;
 RETURN result;
END
$function$;

REVOKE ALL ON FUNCTION public.get_pdc_fitting_statistics_489(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_fitting_statistics_489(integer) TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at) VALUES
 ('public.get_pdc_fitting_statistics_489(integer)','306a3d7a5ecd306492dcfafe00c70005','r489','r489 (F102): new read-only Admin > Fitting statistics report (administrators only)',now());

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('fitting_statistics_489','F102','Fitting statistics report (r489): pinned; SECURITY DEFINER, STABLE, search_path pg_catalog; EXECUTE for authenticated only (not anon); without a signed-in administrator it returns permission_denied and no data',
  $chk$WITH f AS (
  SELECT p.oid, md5(p.prosrc) m, p.prosecdef, p.provolatile, p.proconfig, p.proacl::text acl, pg_catalog.pg_get_userbyid(p.proowner) own
  FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_pdc_fitting_statistics_489(integer)')
), pin AS (
  SELECT count(*) n, count(*) FILTER (WHERE e.prosrc_md5=(SELECT m FROM f)) ok FROM pdc_ops.expected_function_md5 e WHERE e.signature='public.get_pdc_fitting_statistics_489(integer)'
), g AS (
  SELECT pg_catalog.has_function_privilege('anon','public.get_pdc_fitting_statistics_489(integer)','EXECUTE') anon_x, pg_catalog.has_function_privilege('authenticated','public.get_pdc_fitting_statistics_489(integer)','EXECUTE') auth_x
), r AS (
  SELECT public.get_pdc_fitting_statistics_489(30)->>'code' AS no_user
)
SELECT (SELECT count(*)=1 FROM f) AND (SELECT prosecdef AND provolatile='s' AND proconfig='{search_path=pg_catalog}' FROM f)
   AND (SELECT n=1 AND ok=1 FROM pin) AND (SELECT NOT anon_x AND auth_x FROM g)
   AND (SELECT no_user='permission_denied' FROM r) AS ok,
 'fitting statistics pin '||(SELECT ok FROM pin)||'/'||(SELECT n FROM pin)||'; definer stable search_path '||coalesce((SELECT (prosecdef AND provolatile='s' AND proconfig='{search_path=pg_catalog}')::text FROM f),'missing')
 ||'; anon execute '||(SELECT anon_x FROM g)||', authenticated execute '||(SELECT auth_x FROM g)||'; no signed-in user -> '||coalesce((SELECT no_user FROM r),'null') AS detail$chk$,true,289,'r489');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.get_pdc_fitting_statistics_489(integer)'::regprocedure) IS DISTINCT FROM '306a3d7a5ecd306492dcfafe00c70005'
    OR (SELECT position(chr(13) IN prosrc) FROM pg_proc WHERE oid='public.get_pdc_fitting_statistics_489(integer)'::regprocedure)<>0 THEN RAISE EXCEPTION 'r489: function did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r489_tick') THEN RAISE EXCEPTION 'r489: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r489_frc') THEN RAISE EXCEPTION 'r489: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r489')<>1 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r489_pins')::int+1 THEN RAISE EXCEPTION 'r489: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='fitting_statistics_489' AND added_in='r489' AND sort_order=289) IS DISTINCT FROM '1269198e5e0b7836cca85078d5dcecf6' THEN RAISE EXCEPTION 'r489: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='fitting_statistics_489') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r489: check not OK: %',y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
