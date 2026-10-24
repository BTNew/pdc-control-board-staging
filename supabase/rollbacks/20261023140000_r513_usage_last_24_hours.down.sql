-- r513 undo (F126). Staging cdsmnqxtyyoeoznmbidd only. Run between :02 and :45. Do not run on production.
-- Restores pdc_usage_private.report_usage(integer) to the 15 Sep 2026 presence report
-- (prosrc md5 1343d2c98a83cde1904a22eb5d2d3d85) and removes the r513 pin and usage_period_24h_513 check.
-- Refuses unless the live body is the r513 body (prosrc md5 258cb7610a194909c2bf814cfeb8126d).
-- Does not change public.get_pdc_usage_report_20260914 or karratha135_usage.report_usage.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r513 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r513 undo: staging only'; END IF;
 PERFORM set_config('pdc.r513_tick', (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure), true);
 PERFORM set_config('pdc.r513_wrap', (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.get_pdc_usage_report_20260914(integer)'::regprocedure), true);
 PERFORM set_config('pdc.r513_k135', coalesce((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_usage.report_usage(integer)')), ''), true);
 IF current_setting('pdc.r513_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r513 undo: clock tick pin mismatch'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'pdc_usage_private.report_usage(integer)'::regprocedure) IS DISTINCT FROM '258cb7610a194909c2bf814cfeb8126d' THEN RAISE EXCEPTION 'r513 undo: report_usage is not the r513 body'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature = 'pdc_usage_private.report_usage(integer)' AND release = 'r513' AND prosrc_md5 = '258cb7610a194909c2bf814cfeb8126d') THEN RAISE EXCEPTION 'r513 undo: r513 pin missing'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name = 'usage_period_24h_513' AND added_in = 'r513' AND sort_order = 300 AND fault_id = 'F126') THEN RAISE EXCEPTION 'r513 undo: r513 check is not applied'; END IF;
END $g$;

create or replace function pdc_usage_private.report_usage(p_days integer default 30)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog
as $function$
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
  if p_days is null or p_days not in (7,30,90) then
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
end $function$;

REVOKE ALL ON FUNCTION pdc_usage_private.report_usage(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION pdc_usage_private.report_usage(integer) TO authenticated;

DELETE FROM pdc_ops.expected_function_md5
 WHERE signature = 'pdc_usage_private.report_usage(integer)' AND release = 'r513' AND prosrc_md5 = '258cb7610a194909c2bf814cfeb8126d';

DELETE FROM pdc_ops.regression_checks
 WHERE check_name = 'usage_period_24h_513' AND added_in = 'r513' AND fault_id = 'F126' AND sort_order = 300;

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'pdc_usage_private.report_usage(integer)'::regprocedure) IS DISTINCT FROM '1343d2c98a83cde1904a22eb5d2d3d85' THEN RAISE EXCEPTION 'r513 undo: old report_usage body did not land'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature = 'pdc_usage_private.report_usage(integer)' OR release = 'r513') THEN RAISE EXCEPTION 'r513 undo: pin remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name = 'usage_period_24h_513' OR added_in = 'r513' OR fault_id = 'F126') THEN RAISE EXCEPTION 'r513 undo: check remains'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.get_pdc_usage_report_20260914(integer)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r513_wrap') THEN RAISE EXCEPTION 'r513 undo: public wrapper changed'; END IF;
 IF coalesce((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_usage.report_usage(integer)')), '') IS DISTINCT FROM current_setting('pdc.r513_k135') THEN RAISE EXCEPTION 'r513 undo: Karratha usage report changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r513_tick') THEN RAISE EXCEPTION 'r513 undo: clock tick changed'; END IF;
END $g$;
