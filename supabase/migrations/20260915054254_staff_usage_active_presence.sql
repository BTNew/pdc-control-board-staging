-- Activity is evidence from a newly accepted page visit or click batch, attached
-- to the exact authenticated session. Existing history cannot identify its
-- originating session, so deliberately leave existing last_active_at values null.
do $guard$
begin
  if not exists (
    select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
  ) then
    raise exception 'Staging environment sentinel mismatch';
  end if;
  if to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'Production sentinel present; staging-only migration refused';
  end if;
  if md5(pg_get_functiondef('pdc_usage_private.record_usage(uuid,text,integer,boolean)'::regprocedure))
      is distinct from '9022cbe841636e703bbab28e6ba65cbe'
    or md5(pg_get_functiondef('pdc_usage_private.report_usage(integer)'::regprocedure))
      is distinct from 'c6455fa837d4fce34aa1cb16ebe0aa3c' then
    raise exception 'Usage functions changed since review; inspect before replacing';
  end if;
end $guard$;

alter table pdc_usage_private.sessions add column last_active_at timestamptz;
comment on column pdc_usage_private.sessions.last_active_at is
  'Server receipt time of the last new visit/click batch for this exact session; no heartbeat, refresh, empty batch, replay, or historical backfill.';

create or replace function pdc_usage_private.record_usage(
  p_batch_id uuid, p_page text, p_clicks integer, p_visit boolean
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog
as $function$
declare
  u uuid := auth.uid();
  s uuid;
  n integer;
  activity_at timestamptz := now();
begin
  if u is null or not exists (
    select 1 from public.pdc_user_roles
    where auth_user_id = u and email = lower(auth.jwt()->>'email')
      and active and account_status = 'approved'
      and role in ('viewer','operator','importer','administrator')
  ) then
    raise exception 'Approved staff access required' using errcode = '42501';
  end if;
  s := (auth.jwt()->>'session_id')::uuid;
  if s is null or not exists (
    select 1 from auth.sessions
    where id = s and user_id = u and (not_after is null or not_after > activity_at)
  ) then
    raise exception 'Valid sign-in session required' using errcode = '42501';
  end if;
  if p_batch_id is null or p_clicks is null or p_clicks not between 0 and 200
      or p_visit is null or p_page is null or p_page not in (
        'dashboard','qc','workflow','planner-bus-4x4','planner-tint',
        'planner-hoist','planner-fitting','planner-fab','planner-elec',
        'planner-tyre','parts','sublet','user-management','lists','import',
        'backup','deleted','collected','completed','backend','newvehicles',
        'emailreview','ai-auditor','other'
      ) then
    raise exception 'Invalid usage batch' using errcode = '22023';
  end if;
  if exists (
    select 1 from pdc_usage_private.events where user_id = u and batch_id = p_batch_id
  ) then
    return jsonb_build_object('ok',true,'replay',true);
  end if;
  select count(*) into n from pdc_usage_private.events
  where user_id = u and recorded_at > activity_at - interval '1 hour';
  if n >= 300 then
    return jsonb_build_object('ok',false,'code','usage_rate_limit');
  end if;

  -- Only the transaction that inserts the batch may update session activity.
  -- The earlier replay lookup alone would not cover concurrent duplicate calls.
  insert into pdc_usage_private.events(user_id,batch_id,page,visits,clicks)
  values (u,p_batch_id,p_page,p_visit::integer,p_clicks)
  on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then
    return jsonb_build_object('ok',true,'replay',true);
  end if;

  insert into pdc_usage_private.sessions as existing(user_id,session_id,last_active_at)
  values (u,s,case when p_visit or p_clicks > 0 then activity_at end)
  on conflict (user_id,session_id) do update
    set last_active_at = greatest(existing.last_active_at,excluded.last_active_at)
    where excluded.last_active_at is not null;

  delete from pdc_usage_private.events
  where recorded_at < activity_at - interval '180 days';
  -- An old sign-in can still be in use; retain its presence until activity ages out.
  delete from pdc_usage_private.sessions
  where first_seen_at < activity_at - interval '180 days'
    and coalesce(last_active_at,first_seen_at) < activity_at - interval '180 days';
  return jsonb_build_object('ok',true);
end $function$;

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

-- Keep the existing invoker RPC wrappers and the private-schema security model.
revoke all on function pdc_usage_private.record_usage(uuid,text,integer,boolean),
  pdc_usage_private.report_usage(integer) from public,anon;
grant execute on function pdc_usage_private.record_usage(uuid,text,integer,boolean),
  pdc_usage_private.report_usage(integer) to authenticated;
revoke all on pdc_usage_private.sessions from public,anon,authenticated;
alter table pdc_usage_private.sessions enable row level security;

