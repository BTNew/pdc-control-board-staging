-- r513 (F126): Website activity Period "Last 24 hours". SQL already applied on staging as r513_usage_last_24_hours version 20261023055941. Do not re-apply.
-- Website release on main is r525 (F139). The live check, pin release and function body stay as applied. Do not relabel them.
-- Staging cdsmnqxtyyoeoznmbidd only. Do not apply to production.
-- Replaces pdc_usage_private.report_usage(integer) so p_days may be 1, 7, 30 or 90.
-- p_days 1 is the rolling last 24 hours: cutoff stays now() - make_interval(days => p_days),
-- the same rolling window the 7, 30 and 90 day periods already use. It is not a Perth calendar day.
-- Active days stay distinct Australia/Perth dates inside that window. The public wrapper
-- public.get_pdc_usage_report_20260914(integer) is unchanged and still passes p_days through.
-- Karratha karratha135_usage.report_usage is a different function and is not replaced.
-- Old prosrc md5 1343d2c98a83cde1904a22eb5d2d3d85 (15 Sep 2026 presence report). New prosrc md5 258cb7610a194909c2bf814cfeb8126d. Body is LF only.
-- Undo: supabase/rollbacks/20261023140000_r513_usage_last_24_hours.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r513: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r513: staging only'; END IF;
 PERFORM set_config('pdc.r513_tick', (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure), true);
 PERFORM set_config('pdc.r513_frc', (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'pdc_ops.fault_regression_check()'::regprocedure), true);
 PERFORM set_config('pdc.r513_pins', (SELECT count(*) FROM pdc_ops.expected_function_md5)::text, true);
 PERFORM set_config('pdc.r513_wrap', (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.get_pdc_usage_report_20260914(integer)'::regprocedure), true);
 PERFORM set_config('pdc.r513_k135', coalesce((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_usage.report_usage(integer)')), ''), true);
 IF current_setting('pdc.r513_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r513: clock tick does not match its pin'; END IF;
 IF to_regprocedure('pdc_usage_private.report_usage(integer)') IS NULL THEN RAISE EXCEPTION 'r513: report_usage is missing'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'pdc_usage_private.report_usage(integer)'::regprocedure) IS DISTINCT FROM '1343d2c98a83cde1904a22eb5d2d3d85' THEN RAISE EXCEPTION 'r513: report_usage is not the 15 Sep 2026 presence report; inspect before replacing'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name = 'usage_period_24h_513' OR added_in = 'r513' OR sort_order = 300 OR fault_id = 'F126') THEN RAISE EXCEPTION 'r513: already applied or sort 300 / F126 taken'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature = 'pdc_usage_private.report_usage(integer)' OR release = 'r513') THEN RAISE EXCEPTION 'r513: report_usage is already pinned or an r513 pin exists'; END IF;
END $g$;

create or replace function pdc_usage_private.report_usage(p_days integer default 30)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog
as $ru513$
declare
  result jsonb;
  report_at timestamptz := now();
  cutoff timestamptz := now() - make_interval(days => p_days);
begin
  if auth.uid() is null or not exists (
    select 1 from public.pdc_user_roles
    where auth_user_id = auth.uid() and email = lower(auth.jwt()->>'email')
      and active and account_status = 'approved' and role = 'administrator'
  ) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  -- r510: 1 is the rolling last 24 hours. make_interval(days => 1) is 24 hours,
  -- the same rolling window as 7, 30 and 90, not a Perth calendar day.
  if p_days is null or p_days not in (1,7,30,90) then
    raise exception 'Invalid reporting period' using errcode = '22023';
  end if;

  -- Aggregate once per source instead of repeatedly scanning history per person.
  with event_totals as (
    select e.user_id, max(e.recorded_at) as last_active_at,
      count(distinct (e.recorded_at at time zone 'Australia/Perth')::date)
        filter (where e.recorded_at >= cutoff) as active_days,
      coalesce(sum(e.visits) filter (where e.recorded_at >= cutoff),0) as page_visits,
      coalesce(sum(e.clicks) filter (where e.recorded_at >= cutoff),0) as clicks
    from pdc_usage_private.events e group by e.user_id
  ), page_totals as (
    select e.user_id,e.page,sum(e.visits) as visits,sum(e.clicks) as clicks
    from pdc_usage_private.events e where e.recorded_at >= cutoff
    group by e.user_id,e.page
  ), pages as (
    select p.user_id,
      jsonb_agg(jsonb_build_object('page',p.page,'visits',p.visits,'clicks',p.clicks)
        order by p.visits desc,p.page) as pages
    from page_totals p group by p.user_id
  ), session_totals as (
    select s.user_id,
      count(*) filter (where s.first_seen_at >= cutoff) as sign_ins,
      max(s.last_active_at) filter (
        where a.id is not null and (a.not_after is null or a.not_after > report_at)
      ) as presence_last_active_at
    from pdc_usage_private.sessions s
    left join auth.sessions a on a.id = s.session_id and a.user_id = s.user_id
    group by s.user_id
  )
  select jsonb_agg(jsonb_build_object(
    'user_id',r.auth_user_id,
    'name',coalesce(r.full_name,r.display_name,r.email),
    'email',r.email,'role',r.role,
    'last_sign_in_at',u.last_sign_in_at,'last_active_at',e.last_active_at,
    'sign_ins',coalesce(s.sign_ins,0),'active_days',coalesce(e.active_days,0),
    'page_visits',coalesce(e.page_visits,0),'clicks',coalesce(e.clicks,0),
    'pages',coalesce(p.pages,'[]'::jsonb),
    'active_now',coalesce(s.presence_last_active_at >= report_at - interval '120 seconds',false),
    'presence_last_active_at',s.presence_last_active_at
  ) order by coalesce(r.full_name,r.display_name,r.email),r.email)
  into result
  from public.pdc_user_roles r
  join auth.users u on u.id = r.auth_user_id
  left join event_totals e on e.user_id = r.auth_user_id
  left join session_totals s on s.user_id = r.auth_user_id
  left join pages p on p.user_id = r.auth_user_id
  where r.active and r.account_status = 'approved';

  return jsonb_build_object(
    'days',p_days,'tracking_started_at',(select started_at from pdc_usage_private.settings),
    'generated_at',report_at,'active_window_seconds',120,
    'users',coalesce(result,'[]'::jsonb)
  );
end $ru513$;

REVOKE ALL ON FUNCTION pdc_usage_private.report_usage(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION pdc_usage_private.report_usage(integer) TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature, prosrc_md5, release, note, updated_at) VALUES
 ('pdc_usage_private.report_usage(integer)', '258cb7610a194909c2bf814cfeb8126d', 'r513', 'r513 (F126): Website activity Last 24 hours is p_days 1, the same rolling window as 7, 30 and 90 days', now());

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
 ('usage_period_24h_513', 'F126', 'Website activity report (r513): p_days 1, 7, 30 and 90; cutoff remains now() minus make_interval(days => p_days), so 1 is the rolling 24 hours; active days stay Australia/Perth dates; pinned; SECURITY DEFINER, STABLE, search_path pg_catalog; EXECUTE for authenticated only; the public wrapper still only forwards p_days',
  $chk510$WITH f AS (
  SELECT p.oid, md5(p.prosrc) AS m, p.prosecdef, p.provolatile, p.proconfig, p.prosrc
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('pdc_usage_private.report_usage(integer)')
), pin AS (
  SELECT count(*) AS n, count(*) FILTER (WHERE e.prosrc_md5 = (SELECT m FROM f)) AS ok
  FROM pdc_ops.expected_function_md5 e
  WHERE e.signature = 'pdc_usage_private.report_usage(integer)' AND e.release = 'r513'
), g AS (
  SELECT pg_catalog.has_function_privilege('anon', 'pdc_usage_private.report_usage(integer)', 'EXECUTE') AS anon_priv,
         pg_catalog.has_function_privilege('authenticated', 'pdc_usage_private.report_usage(integer)', 'EXECUTE') AS auth_priv,
         pg_catalog.has_function_privilege('anon', 'public.get_pdc_usage_report_20260914(integer)', 'EXECUTE') AS anon_wrap,
         pg_catalog.has_function_privilege('authenticated', 'public.get_pdc_usage_report_20260914(integer)', 'EXECUTE') AS auth_wrap
), w AS (
  SELECT p.prosrc
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.get_pdc_usage_report_20260914(integer)')
)
SELECT (SELECT count(*) = 1 FROM f)
   AND (SELECT prosecdef AND provolatile = 's' AND proconfig = '{search_path=pg_catalog}' FROM f)
   AND (SELECT m = '258cb7610a194909c2bf814cfeb8126d' FROM f)
   AND (SELECT position('not in (1,7,30,90)' in prosrc) > 0
            AND position('make_interval(days => p_days)' in prosrc) > 0
            AND position('Australia/Perth' in prosrc) > 0
            AND position(chr(13) in prosrc) = 0 FROM f)
   AND (SELECT n = 1 AND ok = 1 FROM pin)
   AND (SELECT NOT anon_priv AND auth_priv AND NOT anon_wrap AND auth_wrap FROM g)
   AND (SELECT count(*) = 1 AND position('pdc_usage_private.report_usage(p_days)' in prosrc) > 0
            AND position('1,7,30,90' in prosrc) = 0 FROM w) AS ok,
 'usage 24h pin '||coalesce((SELECT ok::text FROM pin), 'missing')||'/'||coalesce((SELECT n::text FROM pin), '0')
 ||'; md5 '||coalesce((SELECT m FROM f), 'missing')
 ||'; definer stable search_path '||coalesce((SELECT (prosecdef AND provolatile = 's' AND proconfig = '{search_path=pg_catalog}')::text FROM f), 'missing')
 ||'; anon private '||coalesce((SELECT anon_priv::text FROM g), 'null')
 ||', authenticated private '||coalesce((SELECT auth_priv::text FROM g), 'null')
 ||'; wrapper delegates '||coalesce((SELECT (position('pdc_usage_private.report_usage(p_days)' in prosrc) > 0)::text FROM w), 'missing') AS detail$chk510$, true, 300, 'r513');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'pdc_usage_private.report_usage(integer)'::regprocedure) IS DISTINCT FROM '258cb7610a194909c2bf814cfeb8126d'
    OR (SELECT position(chr(13) IN prosrc) FROM pg_proc WHERE oid = 'pdc_usage_private.report_usage(integer)'::regprocedure) <> 0 THEN RAISE EXCEPTION 'r513: function did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.get_pdc_usage_report_20260914(integer)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r513_wrap') THEN RAISE EXCEPTION 'r513: public usage wrapper changed'; END IF;
 IF coalesce((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_usage.report_usage(integer)')), '') IS DISTINCT FROM current_setting('pdc.r513_k135') THEN RAISE EXCEPTION 'r513: Karratha usage report changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r513_tick') THEN RAISE EXCEPTION 'r513: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r513_frc') THEN RAISE EXCEPTION 'r513: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release = 'r513') <> 1
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5) <> current_setting('pdc.r513_pins')::int + 1 THEN RAISE EXCEPTION 'r513: pins not as expected'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name = 'usage_period_24h_513' AND added_in = 'r513' AND sort_order = 300 AND fault_id = 'F126') THEN RAISE EXCEPTION 'r513: check missing'; END IF;
 PERFORM set_config('search_path', 'pg_catalog', true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'usage_period_24h_513') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r513: check not OK: %', y.detail; END IF;
 PERFORM set_config('search_path', 'public, extensions', true);
END $g$;
