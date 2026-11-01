-- r813 (F451): night review 1 Nov 2026. Craig works evenings and Sundays (1 Nov 17:00-20:40, a Sunday). The board prewarm only ran
-- Mon-Sat 05:30-18:30, so outside those hours every board refresh after 15 s rebuilt the 18 MB snapshot inside the request (5.8 s).
-- Now the prewarm also runs 05:00-22:30 any day while a controller / administrator / importer has read the board in the last
-- 5 minutes (one small row, written at most every 30 s). Daytime behaviour is unchanged; idle nights stay idle.
CREATE TABLE IF NOT EXISTS pdc_ops.board_demand_813 (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  last_read_at timestamptz NOT NULL DEFAULT '-infinity'
);
INSERT INTO pdc_ops.board_demand_813 (singleton) VALUES (true) ON CONFLICT DO NOTHING;
REVOKE ALL ON pdc_ops.board_demand_813 FROM PUBLIC, anon, authenticated;

DO $r813$
DECLARE
  sig regprocedure := 'public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)'::regprocedure;
  v_old text; v_new text; v_def text; v_job bigint;
  a1 text := E'  -- The original reader owns caching, rebuild locking and freshness.\n';
  b1 text := E'  -- r813 (F451): a person reading the board keeps the prewarm running outside working hours (at most one write per 30 s).\n'
          || E'  IF public.current_pdc_user_role()::text IN (''operator'',''administrator'',''importer'') THEN\n'
          || E'    UPDATE pdc_ops.board_demand_813 SET last_read_at = clock_timestamp() WHERE singleton AND last_read_at < clock_timestamp() - interval ''30 seconds'';\n'
          || E'  END IF;\n' || a1;
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 OR strpos(v_old, 'r813 (F451)') > 0 THEN RAISE EXCEPTION 'r813: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r813: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);

  SELECT jobid INTO v_job FROM cron.job WHERE jobname = 'staging-vehicle-board-prewarm-729';
  IF v_job IS NULL THEN RAISE EXCEPTION 'r813: prewarm job not found'; END IF;
  PERFORM cron.alter_job(job_id := v_job, command := $cmd$SELECT CASE WHEN (((clock_timestamp() AT TIME ZONE 'Australia/Perth')::time BETWEEN time '05:30' AND time '18:30' AND extract(isodow FROM clock_timestamp() AT TIME ZONE 'Australia/Perth') < 7) OR ((clock_timestamp() AT TIME ZONE 'Australia/Perth')::time BETWEEN time '05:00' AND time '22:30' AND coalesce((SELECT d.last_read_at FROM pdc_ops.board_demand_813 d WHERE d.singleton), '-infinity') > clock_timestamp() - interval '5 minutes')) AND coalesce((SELECT c.computed_at FROM pdc_ops.vehicle_board_snapshot_cache_545 c WHERE c.singleton), '-infinity') < clock_timestamp() - interval '15 seconds' THEN (SELECT (public.get_pdc_email_vehicle_board_snapshot()->>'code') FROM set_config('request.jwt.claims','{"email":"workshopdisplay@pmgwa.com.au","role":"authenticated"}',true) s) ELSE 'fresh_or_idle' END$cmd$);

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('board_prewarm_on_demand_813', 'F451',
    'Board speed (r813): the prewarm also runs 05:00-22:30 any day while someone used the board in the last 5 minutes.',
    $chk$
SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'staging-vehicle-board-prewarm-729' AND active
                 AND strpos(command, 'board_demand_813') > 0 AND strpos(command, $$AT TIME ZONE 'Australia/Perth') < 7$$) > 0)
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)')), 'board_demand_813') > 0
   AND (SELECT count(*) FROM pdc_ops.board_demand_813) = 1
 AS ok, 'prewarm on demand' AS detail
$chk$, true, 600, 'r813');
END $r813$;
