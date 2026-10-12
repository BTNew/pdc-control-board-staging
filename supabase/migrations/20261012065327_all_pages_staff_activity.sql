-- Extend usage reporting to all signed-in PDC and Broome Sales pages.
-- No historical activity is invented and no vehicle/customer records change.
do $guard$
begin
  if not exists (
    select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
  ) or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'Staging-only activity migration refused';
  end if;
  if md5(pg_get_functiondef('pdc_usage_private.record_usage(uuid,text,integer,boolean)'::regprocedure))
      is distinct from '16b57ecabe9577ea9bc5cd099ce79c60' then
    raise exception 'Usage recording function changed since review';
  end if;
end $guard$;

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
      and role in ('viewer','operator','importer','administrator','fitter','salesperson')
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
        'emailreview','ai-auditor','fitters','update-history','workshop',
        'visibility','tv','schedule','department','rft','zpl',
        'sales-myday','sales-dashboard','sales-pipeline','sales-customeremails',
        'sales-alerts','sales-finance','sales-finance-statistics',
        'sales-finance-applications','sales-labels','sales-history','other'
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
