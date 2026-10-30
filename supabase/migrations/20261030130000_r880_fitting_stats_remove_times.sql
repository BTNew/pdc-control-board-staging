-- r880 (F420) / sort 540. Staging cdsmnqxtyyoeoznmbidd only. PREPARED - apply only after Craig's go-live.
-- Craig 30 Oct 2026 12:28: "give me the option to delete lines from the fitting statistics, example a bullbar is in there for 1min and
--   stuffing up the averages because someone forgot to click it."
-- Adds a Times list per job card line on Admin > Fitting statistics, with Remove / Restore per job. Removing only takes that job's time
--   out of the averages (fastest / slowest / median too); the line still counts as done. Nothing on the job itself changes: the tick, its
--   Start / Done times (operation_progress / operation_timing) and every other screen are untouched.
--   1. Table pdc_fitter_private.fitting_stats_excluded_880 (booking_id, line_identity, excluded_by, excluded_at), RLS on, no site access.
--   2. pdc_fitter_private.fitting_model_family_880(text,text) (the r850 model mapping) and fitting_lines_880(since, fitter) (the r850 row
--      rules, plus removed flag), both private, no EXECUTE for site roles.
--   3. get_pdc_fitting_statistics_850 rebuilt on fitting_lines_880 (same output; lines gain type_key and excluded). Re-pinned.
--   4. New get_pdc_fitting_line_entries_880 (timed jobs behind one line type: date, fitter, stock, key, minutes, allowance, removed) and
--      set_pdc_fitting_time_excluded_880 (remove / restore one time). Administrators only, EXECUTE authenticated only.
-- md5s: model 418d557b40b2f1901767f43c8a65f8da, lines f6f5a9314ff349aa015ccba4cf98fdc7, stats 87f526294d771c7bc5c0ff4e1c3bf11f (was 170ecb5674f39d78f3fd9135cb75aae5), entries b1d7fd424fdbd6b907614c8bc4d66dda, set 5aa6a09a23317105645a5e98ae79cae5. LF only.
-- Undo: supabase/rollbacks/20261030130000_r880_fitting_stats_remove_times.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r880: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r880: staging only'; END IF;
 PERFORM set_config('pdc.r880_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r880_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r880_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r880_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r880: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_fitting_statistics_850(integer,uuid)')) IS DISTINCT FROM '170ecb5674f39d78f3fd9135cb75aae5' THEN RAISE EXCEPTION 'r880: get_pdc_fitting_statistics_850 is not the r850 body'; END IF;
 IF to_regclass('pdc_fitter_private.fitting_stats_excluded_880') IS NOT NULL OR to_regprocedure('public.get_pdc_fitting_line_entries_880(integer,uuid,text,text,text)') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r880')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='fitting_stats_remove_times_880' OR added_in='r880') THEN RAISE EXCEPTION 'r880: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=540 OR fault_id='F420') THEN RAISE EXCEPTION 'r880: sort_order 540 / F420 taken'; END IF;
END $g$;

CREATE TABLE pdc_fitter_private.fitting_stats_excluded_880 (
 booking_id uuid NOT NULL REFERENCES public.workshop_bookings(id) ON DELETE CASCADE,
 line_identity text NOT NULL,
 excluded_by uuid REFERENCES auth.users(id),
 excluded_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (booking_id, line_identity)
);
ALTER TABLE pdc_fitter_private.fitting_stats_excluded_880 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_fitter_private.fitting_stats_excluded_880 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE pdc_fitter_private.fitting_stats_excluded_880 IS 'r880 (F420): job times Craig removed from Admin > Fitting statistics. Statistics only; the job itself is unchanged.';

CREATE FUNCTION pdc_fitter_private.fitting_model_family_880(p_model text, p_description text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 -- r880 (F420): vehicle model family, same mapping as r850 (vehicles.model, else vehicle_description such as ISUDMA / TOYHIA).
 SELECT CASE
   WHEN m ~ '(hilux|toyhil)' THEN 'HILUX'
   WHEN m ~ '(prado|toypra)' THEN 'PRADO'
   WHEN m ~ '(lc ?7[0-9]|70 series|land ?cruiser 7[0-9]|toylc7)' THEN 'LC70'
   WHEN m ~ '(lc ?300|land ?cruiser 300|toylc3)' THEN 'LC300'
   WHEN m ~ '(land ?cruiser|toylcr)' THEN 'LANDCRUISER'
   WHEN m ~ '(coaster|toycoa)' THEN 'COASTER'
   WHEN m ~ '(hiace|toyhia)' THEN 'HIACE'
   WHEN m ~ '(isuzu|d-?max|isudma)' THEN 'DMAX'
   WHEN m ~ 'fortuner' THEN 'FORTUNER'
   WHEN m ~ 'tundra' THEN 'TUNDRA'
   WHEN m ~ 'bz4x' THEN 'BZ4X'
   WHEN m ~ 'rav ?4' THEN 'RAV4'
   WHEN m ~ 'kluger' THEN 'KLUGER'
   WHEN m ~ 'camry' THEN 'CAMRY'
   WHEN m ~ 'corolla' THEN 'COROLLA'
   WHEN m ~ 'yaris' THEN 'YARIS'
   WHEN m ~ 'granvia' THEN 'GRANVIA'
   WHEN m = '' THEN 'UNKNOWN'
   ELSE 'OTHER'
 END
 FROM (SELECT lower(btrim(coalesce(nullif(btrim(p_model), ''), p_description, ''))) AS m) mm
$function$;

CREATE FUNCTION pdc_fitter_private.fitting_lines_880(p_since timestamp with time zone, p_technician_id uuid)
 RETURNS TABLE(booking_id uuid, line_identity text, technician_id uuid, vehicle_id uuid, done_at timestamp with time zone, model_family text, category text, type_key text, description text, actual_minutes numeric, recorded_minutes numeric, excluded boolean, est_minutes numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
 -- r880 (F420): one row per bay line ticked Done (same rules as r489 / r850), with its model, category, line type, fitter and time.
 -- A time Craig removed (fitting_stats_excluded_880) has minutes NULL so it never counts in an average; the line still counts as done.
 WITH done AS MATERIALIZED (
   SELECT p.booking_id, p.line_identity, p.technician_id, p.updated_at AS done_at, b.vehicle_id,
          b.work_category AS booking_category, s.code AS stage_code, t.actual_seconds,
          (x.booking_id IS NOT NULL) AS excluded
   FROM pdc_fitter_private.operation_progress p
   JOIN public.workshop_bookings b ON b.id = p.booking_id AND b.deleted_at IS NULL
   JOIN public.workshop_stages s ON s.id = b.stage_id
   LEFT JOIN pdc_fitter_private.operation_timing t
     ON t.booking_id = p.booking_id AND t.line_identity = p.line_identity AND t.status = 'done'
    AND t.scope_hash IS NOT DISTINCT FROM p.scope_hash AND t.actual_seconds IS NOT NULL
   LEFT JOIN pdc_fitter_private.fitting_stats_excluded_880 x ON x.booking_id = p.booking_id AND x.line_identity = p.line_identity
   WHERE p.completed IS TRUE AND (p_since IS NULL OR p.updated_at >= p_since)
     AND (p_technician_id IS NULL OR p.technician_id = p_technician_id)
 )
 SELECT d.booking_id, d.line_identity, d.technician_id, d.vehicle_id, d.done_at,
        pdc_fitter_private.fitting_model_family_880(v.model, v.vehicle_description) AS model_family,
        coalesce(nullif(l.line->>'work_category', ''), nullif(d.booking_category, ''), d.stage_code) AS category,
        coalesce(nullif(lower(regexp_replace(btrim(l.line->>'description'), '\s+', ' ', 'g')), ''), '~unknown') AS type_key,
        nullif(regexp_replace(btrim(l.line->>'description'), '\s+', ' ', 'g'), '') AS description,
        CASE WHEN d.excluded THEN NULL ELSE d.actual_seconds / 60.0 END AS actual_minutes,
        d.actual_seconds / 60.0 AS recorded_minutes,
        d.excluded AND d.actual_seconds IS NOT NULL AS excluded,
        CASE WHEN jsonb_typeof(l.line->'estimated_hours') = 'number' THEN (l.line->>'estimated_hours')::numeric * 60 END AS est_minutes
 FROM done d
 LEFT JOIN public.vehicles v ON v.id = d.vehicle_id
 LEFT JOIN pdc_work_categories_private.qc_operation_lines_cache c ON c.vehicle_id = d.vehicle_id
 LEFT JOIN LATERAL (SELECT x AS line FROM jsonb_array_elements(CASE WHEN jsonb_typeof(c.lines) = 'array' THEN c.lines ELSE '[]'::jsonb END) x
                    WHERE x->>'line_identity' = d.line_identity LIMIT 1) l ON true
$function$;

REVOKE ALL ON FUNCTION pdc_fitter_private.fitting_model_family_880(text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_fitter_private.fitting_lines_880(timestamp with time zone,uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_pdc_fitting_statistics_850(p_days integer, p_technician_id uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE result jsonb; v_since timestamptz; v_tech_name text;
BEGIN
 -- r850 (F400) / r880 (F420): Admin > Fitting statistics by model and fitter. Read only; administrators only.
 -- r880: rows come from pdc_fitter_private.fitting_lines_880 (same rules as before); a time Craig removed is not in any average
 -- and each line type reports how many times were removed. Line types also return their type_key for the Times list.
 IF auth.uid() IS NULL OR NOT EXISTS (
   SELECT 1 FROM public.pdc_user_roles r
   WHERE r.auth_user_id = auth.uid() AND r.role::text = 'administrator'
     AND r.active IS TRUE AND r.account_status = 'approved') THEN
   RETURN jsonb_build_object('ok', false, 'code', 'permission_denied');
 END IF;
 IF p_days IS NULL OR p_days NOT IN (0, 7, 30, 90, 365) THEN
   RETURN jsonb_build_object('ok', false, 'code', 'invalid_period');
 END IF;
 IF p_technician_id IS NOT NULL THEN
   SELECT t.name INTO v_tech_name FROM public.workshop_technicians t WHERE t.id = p_technician_id;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'unknown_fitter'); END IF;
 END IF;
 v_since := CASE WHEN p_days = 0 THEN NULL ELSE statement_timestamp() - make_interval(days => p_days) END;
 WITH all_lines AS MATERIALIZED (
   SELECT * FROM pdc_fitter_private.fitting_lines_880(v_since, NULL)
 ),
 fitters AS (
   SELECT a.technician_id, count(*) AS completed FROM all_lines a WHERE a.technician_id IS NOT NULL GROUP BY a.technician_id
 ),
 typed AS (
   SELECT a.* FROM all_lines a WHERE p_technician_id IS NULL OR a.technician_id = p_technician_id
 ),
 per_type AS (
   SELECT model_family, category, type_key, min(description) AS line_type,
          count(*) AS completed, count(actual_minutes) AS timed, count(*) FILTER (WHERE excluded) AS excluded,
          round(avg(actual_minutes), 1) AS avg_minutes,
          round((percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_minutes))::numeric, 1) AS median_minutes,
          round(min(actual_minutes), 1) AS min_minutes, round(max(actual_minutes), 1) AS max_minutes,
          round(avg(est_minutes) FILTER (WHERE est_minutes > 0), 1) AS avg_allowance_minutes
   FROM typed GROUP BY model_family, category, type_key
 ),
 -- Whole station jobs finished in the period (Start work -> Complete). With a fitter chosen: jobs where that fitter ticked a line Done.
 jobs AS (
   SELECT pdc_fitter_private.fitting_model_family_880(v.model, v.vehicle_description) AS model_family,
          coalesce(nullif(b.work_category, ''), s.code) AS category,
          count(*) AS jobs_completed,
          round(avg(extract(epoch FROM b.actual_end_at - b.actual_start_at) / 60.0), 1) AS job_avg_elapsed_minutes
   FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id = b.stage_id
   LEFT JOIN public.vehicles v ON v.id = b.vehicle_id
   WHERE b.deleted_at IS NULL AND b.status::text = 'completed' AND b.actual_start_at IS NOT NULL
     AND b.actual_end_at >= b.actual_start_at AND (v_since IS NULL OR b.actual_end_at >= v_since)
     AND (p_technician_id IS NULL OR EXISTS (SELECT 1 FROM pdc_fitter_private.operation_progress op
          WHERE op.booking_id = b.id AND op.completed IS TRUE AND op.technician_id = p_technician_id))
   GROUP BY 1, 2
 ),
 cats AS (SELECT model_family, category FROM per_type UNION SELECT model_family, category FROM jobs),
 models AS (SELECT DISTINCT model_family FROM cats)
 SELECT jsonb_build_object(
   'ok', true, 'generated_at', statement_timestamp(), 'days', p_days, 'since', v_since,
   'timing_started_at', (SELECT min(started_at) FROM pdc_fitter_private.operation_timing),
   'technician', CASE WHEN p_technician_id IS NULL THEN NULL ELSE jsonb_build_object('id', p_technician_id, 'name', v_tech_name) END,
   'technicians', coalesce((SELECT jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'completed', coalesce(f.completed, 0))
       ORDER BY t.name)
     FROM public.workshop_technicians t LEFT JOIN fitters f ON f.technician_id = t.id
     WHERE f.technician_id IS NOT NULL OR t.id = p_technician_id), '[]'::jsonb),
   'models', coalesce((SELECT jsonb_agg(jsonb_build_object(
       'model', m.model_family,
       'categories', (SELECT jsonb_agg(jsonb_build_object(
           'category', c.category,
           'jobs_completed', coalesce(j.jobs_completed, 0), 'job_avg_elapsed_minutes', j.job_avg_elapsed_minutes,
           'lines', coalesce((SELECT jsonb_agg(jsonb_build_object(
               'line_type', CASE WHEN t.type_key = '~unknown' THEN NULL ELSE t.line_type END, 'type_key', t.type_key,
               'completed', t.completed, 'timed', t.timed, 'excluded', t.excluded,
               'avg_minutes', t.avg_minutes, 'median_minutes', t.median_minutes,
               'min_minutes', t.min_minutes, 'max_minutes', t.max_minutes, 'avg_allowance_minutes', t.avg_allowance_minutes)
             ORDER BY t.completed DESC, t.type_key)
             FROM per_type t WHERE t.model_family = c.model_family AND t.category = c.category), '[]'::jsonb))
         ORDER BY c.category)
         FROM cats c LEFT JOIN jobs j ON j.model_family = c.model_family AND j.category = c.category
         WHERE c.model_family = m.model_family))
     ORDER BY m.model_family) FROM models m), '[]'::jsonb))
 INTO result;
 RETURN result;
END
$function$;

CREATE FUNCTION public.get_pdc_fitting_line_entries_880(p_days integer, p_technician_id uuid, p_model text, p_category text, p_type_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v_since timestamptz;
BEGIN
 -- r880 (F420): every timed job behind one line type (model + category + line type), newest first, so Craig can remove a bad time
 -- (e.g. a bull bar Started and Done a minute apart). Administrators only. Read only.
 IF auth.uid() IS NULL OR NOT EXISTS (
   SELECT 1 FROM public.pdc_user_roles r
   WHERE r.auth_user_id = auth.uid() AND r.role::text = 'administrator'
     AND r.active IS TRUE AND r.account_status = 'approved') THEN
   RETURN jsonb_build_object('ok', false, 'code', 'permission_denied');
 END IF;
 IF p_days IS NULL OR p_days NOT IN (0, 7, 30, 90, 365) OR p_model IS NULL OR p_category IS NULL OR p_type_key IS NULL THEN
   RETURN jsonb_build_object('ok', false, 'code', 'invalid_request');
 END IF;
 v_since := CASE WHEN p_days = 0 THEN NULL ELSE statement_timestamp() - make_interval(days => p_days) END;
 RETURN jsonb_build_object('ok', true, 'entries', coalesce((
   SELECT jsonb_agg(jsonb_build_object(
       'booking_id', f.booking_id, 'line_identity', f.line_identity, 'done_at', f.done_at,
       'fitter', t.name, 'stock_number', v.stock_number, 'key_number', v.key_number,
       'description', f.description, 'minutes', round(f.recorded_minutes, 1),
       'allowance_minutes', round(f.est_minutes, 1), 'excluded', f.excluded)
     ORDER BY f.done_at DESC)
   FROM pdc_fitter_private.fitting_lines_880(v_since, p_technician_id) f
   LEFT JOIN public.workshop_technicians t ON t.id = f.technician_id
   LEFT JOIN public.vehicles v ON v.id = f.vehicle_id
   WHERE f.model_family = p_model AND f.category = p_category AND f.type_key = p_type_key AND f.recorded_minutes IS NOT NULL), '[]'::jsonb));
END
$function$;

CREATE FUNCTION public.set_pdc_fitting_time_excluded_880(p_booking_id uuid, p_line_identity text, p_excluded boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_found boolean;
BEGIN
 -- r880 (F420): remove (or restore) one job's time from Fitting statistics. Only the statistics change: the tick, its Start / Done
 -- times on the job and every other screen stay exactly as they were. Administrators only.
 IF v_uid IS NULL OR NOT EXISTS (
   SELECT 1 FROM public.pdc_user_roles r
   WHERE r.auth_user_id = v_uid AND r.role::text = 'administrator'
     AND r.active IS TRUE AND r.account_status = 'approved') THEN
   RETURN jsonb_build_object('ok', false, 'code', 'permission_denied');
 END IF;
 IF p_booking_id IS NULL OR p_line_identity IS NULL OR p_excluded IS NULL THEN
   RETURN jsonb_build_object('ok', false, 'code', 'invalid_request');
 END IF;
 SELECT EXISTS (SELECT 1 FROM pdc_fitter_private.operation_progress p
   WHERE p.booking_id = p_booking_id AND p.line_identity = p_line_identity AND p.completed IS TRUE) INTO v_found;
 IF NOT v_found AND p_excluded THEN RETURN jsonb_build_object('ok', false, 'code', 'not_found'); END IF;
 IF p_excluded THEN
   INSERT INTO pdc_fitter_private.fitting_stats_excluded_880(booking_id, line_identity, excluded_by, excluded_at)
   VALUES (p_booking_id, p_line_identity, v_uid, statement_timestamp())
   ON CONFLICT (booking_id, line_identity) DO NOTHING;
 ELSE
   DELETE FROM pdc_fitter_private.fitting_stats_excluded_880 x WHERE x.booking_id = p_booking_id AND x.line_identity = p_line_identity;
 END IF;
 RETURN jsonb_build_object('ok', true, 'excluded', p_excluded);
END
$function$;

REVOKE ALL ON FUNCTION public.get_pdc_fitting_line_entries_880(integer,uuid,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_fitting_line_entries_880(integer,uuid,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.set_pdc_fitting_time_excluded_880(uuid,text,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_pdc_fitting_time_excluded_880(uuid,text,boolean) TO authenticated;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='87f526294d771c7bc5c0ff4e1c3bf11f', release='r880', note='r880 (F420): Fitting statistics by model and fitter, built on fitting_lines_880; removed times left out', updated_at=now()
 WHERE signature='public.get_pdc_fitting_statistics_850(integer,uuid)' AND prosrc_md5='170ecb5674f39d78f3fd9135cb75aae5';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at) VALUES
 ('pdc_fitter_private.fitting_model_family_880(text,text)','418d557b40b2f1901767f43c8a65f8da','r880','r880 (F420): vehicle model family for Fitting statistics',now()),
 ('pdc_fitter_private.fitting_lines_880(timestamp with time zone,uuid)','f6f5a9314ff349aa015ccba4cf98fdc7','r880','r880 (F420): Fitting statistics rows (private)',now()),
 ('public.get_pdc_fitting_line_entries_880(integer,uuid,text,text,text)','b1d7fd424fdbd6b907614c8bc4d66dda','r880','r880 (F420): timed jobs behind a Fitting statistics line type (administrators only)',now()),
 ('public.set_pdc_fitting_time_excluded_880(uuid,text,boolean)','5aa6a09a23317105645a5e98ae79cae5','r880','r880 (F420): remove / restore a time in Fitting statistics (administrators only)',now());

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('fitting_stats_remove_times_880','F420','Fitting statistics remove times (r880): 5 functions pinned (stats re-pinned); no anon EXECUTE, private helper not callable by the site; exclusions table RLS on and not readable by site roles; without a signed-in administrator every RPC returns permission_denied',
  $chk$WITH f AS (
  SELECT e.signature, e.prosrc_md5, (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure(e.signature)) live
  FROM pdc_ops.expected_function_md5 e WHERE e.release='r880'
), g AS (
  SELECT pg_catalog.has_function_privilege('anon','public.get_pdc_fitting_line_entries_880(integer,uuid,text,text,text)','EXECUTE') OR pg_catalog.has_function_privilege('anon','public.set_pdc_fitting_time_excluded_880(uuid,text,boolean)','EXECUTE')
      OR pg_catalog.has_function_privilege('anon','public.get_pdc_fitting_statistics_850(integer,uuid)','EXECUTE') OR pg_catalog.has_function_privilege('authenticated','pdc_fitter_private.fitting_lines_880(timestamp with time zone,uuid)','EXECUTE') AS leaked
), t AS (
  SELECT c.relrowsecurity rls, pg_catalog.has_table_privilege('authenticated','pdc_fitter_private.fitting_stats_excluded_880','SELECT') OR pg_catalog.has_table_privilege('anon','pdc_fitter_private.fitting_stats_excluded_880','SELECT') AS readable
  FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('pdc_fitter_private.fitting_stats_excluded_880')
), r AS (
  SELECT public.get_pdc_fitting_line_entries_880(0,NULL,'HILUX','FITTING','x')->>'code' a, public.set_pdc_fitting_time_excluded_880(NULL,NULL,true)->>'code' b, public.get_pdc_fitting_statistics_850(0,NULL)->>'code' c
)
SELECT (SELECT count(*)=5 AND bool_and(prosrc_md5=live) FROM f) AND NOT (SELECT leaked FROM g) AND (SELECT rls AND NOT readable FROM t)
   AND (SELECT a='permission_denied' AND b='permission_denied' AND c='permission_denied' FROM r) AS ok,
 'r880 pins '||(SELECT count(*) FILTER (WHERE prosrc_md5=live)||'/'||count(*) FROM f)||'; leaked execute '||(SELECT leaked FROM g)
 ||'; exclusions table rls '||coalesce((SELECT rls::text FROM t),'missing')||', readable by site roles '||coalesce((SELECT readable::text FROM t),'missing')
 ||'; no-user calls -> '||(SELECT concat_ws('/',a,b,c) FROM r) AS detail$chk$,true,540,'r880');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pdc_ops.expected_function_md5 e ON p.oid=to_regprocedure(e.signature) AND md5(p.prosrc)=e.prosrc_md5 WHERE e.release='r880')<>5
    OR EXISTS(SELECT 1 FROM pg_proc p JOIN pdc_ops.expected_function_md5 e ON p.oid=to_regprocedure(e.signature) WHERE e.release='r880' AND position(chr(13) IN p.prosrc)<>0) THEN RAISE EXCEPTION 'r880: functions did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.get_pdc_fitting_statistics_489(integer)'::regprocedure) IS DISTINCT FROM '306a3d7a5ecd306492dcfafe00c70005' THEN RAISE EXCEPTION 'r880: r489 report changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r880_tick') THEN RAISE EXCEPTION 'r880: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r880_frc') THEN RAISE EXCEPTION 'r880: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r880_pins')::int+4 THEN RAISE EXCEPTION 'r880: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='fitting_stats_remove_times_880' AND added_in='r880' AND sort_order=540) IS DISTINCT FROM '58b3f58c842a75ac7d0266faad8235f3' THEN RAISE EXCEPTION 'r880: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='fitting_stats_remove_times_880') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r880: check not OK: %',y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
