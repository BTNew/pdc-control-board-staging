-- r880 undo (F420). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Only needed if
-- 20261030130000_r880_fitting_stats_remove_times.sql was applied. Restores get_pdc_fitting_statistics_850 to its r850 body and pin,
-- drops the r880 functions, the check and the removed-times table (the list of removed times is lost; the jobs themselves were never
-- changed). Revert the PR as well.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r880 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r880 undo: staging only'; END IF;
 PERFORM set_config('pdc.r880_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r880_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r880_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r880_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r880 undo: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pdc_ops.expected_function_md5 e ON p.oid=to_regprocedure(e.signature) AND md5(p.prosrc)=e.prosrc_md5 WHERE e.release='r880')<>5 THEN RAISE EXCEPTION 'r880 undo: r880 is not applied as released; not undoing over unknown changes'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='fitting_stats_remove_times_880' AND added_in='r880';
CREATE OR REPLACE FUNCTION public.get_pdc_fitting_statistics_850(p_days integer, p_technician_id uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE result jsonb; v_since timestamptz; v_tech_name text;
BEGIN
 -- r850 (F400): Admin > Fitting statistics by model and fitter. Read only; administrators only (same test as r489).
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
 -- p_days 0 = all time.
 v_since := CASE WHEN p_days = 0 THEN NULL ELSE statement_timestamp() - make_interval(days => p_days) END;
 -- Same completed-line and timing rules as r489. Fitter = the technician the Done tick was made for (operation_progress.technician_id).
 -- Model = the vehicle's model family from vehicles.model, else vehicles.vehicle_description (e.g. ISUDMA, TOYHIA).
 WITH done_all AS MATERIALIZED (
   SELECT p.booking_id, p.line_identity, p.technician_id, b.vehicle_id, b.work_category AS booking_category, s.code AS stage_code,
          t.actual_seconds
   FROM pdc_fitter_private.operation_progress p
   JOIN public.workshop_bookings b ON b.id = p.booking_id AND b.deleted_at IS NULL
   JOIN public.workshop_stages s ON s.id = b.stage_id
   LEFT JOIN pdc_fitter_private.operation_timing t
     ON t.booking_id = p.booking_id AND t.line_identity = p.line_identity AND t.status = 'done'
    AND t.scope_hash IS NOT DISTINCT FROM p.scope_hash AND t.actual_seconds IS NOT NULL
   WHERE p.completed IS TRUE AND (v_since IS NULL OR p.updated_at >= v_since)
 ),
 fitters AS (
   SELECT d.technician_id, count(*) AS completed FROM done_all d WHERE d.technician_id IS NOT NULL GROUP BY d.technician_id
 ),
 done AS (
   SELECT d.* FROM done_all d WHERE p_technician_id IS NULL OR d.technician_id = p_technician_id
 ),
 vehicle_models AS (
   SELECT v.id AS vehicle_id,
     CASE
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
     END AS model_family
   FROM public.vehicles v
   CROSS JOIN LATERAL (SELECT lower(btrim(coalesce(nullif(btrim(v.model), ''), v.vehicle_description, ''))) AS m) mm
   WHERE v.id IN (SELECT vehicle_id FROM done UNION SELECT vehicle_id FROM public.workshop_bookings jb
                  WHERE jb.deleted_at IS NULL AND jb.status::text = 'completed' AND (v_since IS NULL OR jb.actual_end_at >= v_since))
 ),
 lines AS (
   SELECT d.*, coalesce(vm.model_family, 'UNKNOWN') AS model_family,
          l.line->>'description' AS description, l.line->>'work_category' AS line_category,
          CASE WHEN jsonb_typeof(l.line->'estimated_hours') = 'number' THEN (l.line->>'estimated_hours')::numeric END AS est_hours
   FROM done d
   LEFT JOIN vehicle_models vm ON vm.vehicle_id = d.vehicle_id
   LEFT JOIN pdc_work_categories_private.qc_operation_lines_cache c ON c.vehicle_id = d.vehicle_id
   LEFT JOIN LATERAL (SELECT x AS line FROM jsonb_array_elements(CASE WHEN jsonb_typeof(c.lines) = 'array' THEN c.lines ELSE '[]'::jsonb END) x
                      WHERE x->>'line_identity' = d.line_identity LIMIT 1) l ON true
 ),
 typed AS (
   SELECT model_family, coalesce(nullif(line_category, ''), nullif(booking_category, ''), stage_code) AS category,
          coalesce(nullif(lower(regexp_replace(btrim(description), '\s+', ' ', 'g')), ''), '~unknown') AS type_key,
          nullif(regexp_replace(btrim(description), '\s+', ' ', 'g'), '') AS description,
          actual_seconds / 60.0 AS actual_minutes, est_hours * 60 AS est_minutes
   FROM lines
 ),
 per_type AS (
   SELECT model_family, category, type_key, min(description) AS line_type,
          count(*) AS completed, count(actual_minutes) AS timed,
          round(avg(actual_minutes), 1) AS avg_minutes,
          round((percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_minutes))::numeric, 1) AS median_minutes,
          round(min(actual_minutes), 1) AS min_minutes, round(max(actual_minutes), 1) AS max_minutes,
          round(avg(est_minutes) FILTER (WHERE est_minutes > 0), 1) AS avg_allowance_minutes
   FROM typed GROUP BY model_family, category, type_key
 ),
 -- Whole station jobs finished in the period (Start work -> Complete). With a fitter chosen: jobs where that fitter ticked a line Done.
 jobs AS (
   SELECT coalesce(vm.model_family, 'UNKNOWN') AS model_family, coalesce(nullif(b.work_category, ''), s.code) AS category,
          count(*) AS jobs_completed,
          round(avg(extract(epoch FROM b.actual_end_at - b.actual_start_at) / 60.0), 1) AS job_avg_elapsed_minutes
   FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id = b.stage_id
   LEFT JOIN vehicle_models vm ON vm.vehicle_id = b.vehicle_id
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
               'line_type', CASE WHEN t.type_key = '~unknown' THEN NULL ELSE t.line_type END,
               'completed', t.completed, 'timed', t.timed, 'avg_minutes', t.avg_minutes, 'median_minutes', t.median_minutes,
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

REVOKE ALL ON FUNCTION public.get_pdc_fitting_statistics_850(integer,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_fitting_statistics_850(integer,uuid) TO authenticated;
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='170ecb5674f39d78f3fd9135cb75aae5', release='r850', note='r850 (F400): read-only Admin > Fitting statistics by model and fitter (administrators only)', updated_at=now()
 WHERE signature='public.get_pdc_fitting_statistics_850(integer,uuid)' AND release='r880';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r880' AND signature IN ('pdc_fitter_private.fitting_model_family_880(text,text)','pdc_fitter_private.fitting_lines_880(timestamp with time zone,uuid)','public.get_pdc_fitting_line_entries_880(integer,uuid,text,text,text)','public.set_pdc_fitting_time_excluded_880(uuid,text,boolean)');
DROP FUNCTION public.set_pdc_fitting_time_excluded_880(uuid,text,boolean);
DROP FUNCTION public.get_pdc_fitting_line_entries_880(integer,uuid,text,text,text);
DROP FUNCTION pdc_fitter_private.fitting_lines_880(timestamp with time zone,uuid);
DROP FUNCTION pdc_fitter_private.fitting_model_family_880(text,text);
DROP TABLE pdc_fitter_private.fitting_stats_excluded_880;
DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.get_pdc_fitting_statistics_850(integer,uuid)'::regprocedure) IS DISTINCT FROM '170ecb5674f39d78f3fd9135cb75aae5' THEN RAISE EXCEPTION 'r880 undo: stats body not restored'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_fitting_statistics_850(integer,uuid)') IS DISTINCT FROM '170ecb5674f39d78f3fd9135cb75aae5' THEN RAISE EXCEPTION 'r880 undo: stats pin not restored'; END IF;
 IF to_regclass('pdc_fitter_private.fitting_stats_excluded_880') IS NOT NULL OR to_regprocedure('public.get_pdc_fitting_line_entries_880(integer,uuid,text,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'r880 undo: objects still there'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r880_tick') THEN RAISE EXCEPTION 'r880 undo: clock tick changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r880') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r880')
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r880_pins')::int-4 THEN RAISE EXCEPTION 'r880 undo: did not fully undo'; END IF;
END $g$;
