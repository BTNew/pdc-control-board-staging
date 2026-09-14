create schema if not exists pdc_usage_private;
revoke all on schema pdc_usage_private from public,anon;
grant usage on schema pdc_usage_private to authenticated;
create table pdc_usage_private.settings(singleton boolean primary key default true check(singleton),started_at timestamptz not null default now());
insert into pdc_usage_private.settings default values;
create table pdc_usage_private.sessions(user_id uuid not null references auth.users(id) on delete cascade,session_id uuid not null,first_seen_at timestamptz not null default now(),primary key(user_id,session_id));
create table pdc_usage_private.events(user_id uuid not null references auth.users(id) on delete cascade,batch_id uuid not null,recorded_at timestamptz not null default now(),page text not null,visits integer not null check(visits between 0 and 1),clicks integer not null check(clicks between 0 and 200),primary key(user_id,batch_id));
create index pdc_usage_events_time on pdc_usage_private.events(recorded_at);
create index pdc_usage_sessions_time on pdc_usage_private.sessions(first_seen_at);
alter table pdc_usage_private.settings enable row level security;
alter table pdc_usage_private.sessions enable row level security;
alter table pdc_usage_private.events enable row level security;
revoke all on all tables in schema pdc_usage_private from public,anon,authenticated;
create function pdc_usage_private.record_usage(p_batch_id uuid,p_page text,p_clicks integer,p_visit boolean)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pdc_usage_private as $$
declare u uuid:=auth.uid(); s uuid; n integer;
begin
 if u is null or not exists(select 1 from public.pdc_user_roles where auth_user_id=u and email=lower(auth.jwt()->>'email') and active and account_status='approved' and role in('viewer','operator','importer','administrator')) then raise exception 'Approved staff access required' using errcode='42501';end if;
 s:=(auth.jwt()->>'session_id')::uuid;
 if s is null or not exists(select 1 from auth.sessions where id=s and user_id=u) then raise exception 'Valid sign-in session required' using errcode='42501';end if;
 if p_batch_id is null or p_clicks is null or p_clicks not between 0 and 200 or p_visit is null or p_page is null or p_page not in('dashboard','qc','workflow','planner-bus-4x4','planner-tint','planner-hoist','planner-fitting','planner-fab','planner-elec','planner-tyre','parts','sublet','user-management','lists','import','backup','deleted','collected','completed','backend','newvehicles','emailreview','ai-auditor','other') then raise exception 'Invalid usage batch' using errcode='22023';end if;
 if exists(select 1 from pdc_usage_private.events where user_id=u and batch_id=p_batch_id) then return jsonb_build_object('ok',true,'replay',true);end if;
 select count(*) into n from pdc_usage_private.events where user_id=u and recorded_at>now()-interval '1 hour';
 if n>=300 then return jsonb_build_object('ok',false,'code','usage_rate_limit');end if;
 insert into pdc_usage_private.sessions(user_id,session_id) values(u,s) on conflict do nothing;
 insert into pdc_usage_private.events(user_id,batch_id,page,visits,clicks) values(u,p_batch_id,p_page,p_visit::integer,p_clicks) on conflict do nothing;
 delete from pdc_usage_private.events where recorded_at<now()-interval '180 days';
 delete from pdc_usage_private.sessions where first_seen_at<now()-interval '180 days';
 return jsonb_build_object('ok',true);
end $$;
create function public.record_pdc_usage_20260914(p_batch_id uuid,p_page text,p_clicks integer,p_visit boolean)
returns jsonb language sql security invoker set search_path=pg_catalog as $$ select pdc_usage_private.record_usage(p_batch_id,p_page,p_clicks,p_visit) $$;
create function pdc_usage_private.report_usage(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pdc_usage_private as $$
declare result jsonb; cutoff timestamptz:=now()-make_interval(days=>p_days);
begin
 if auth.uid() is null or not exists(select 1 from public.pdc_user_roles where auth_user_id=auth.uid() and email=lower(auth.jwt()->>'email') and active and account_status='approved' and role='administrator') then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_days not in(7,30,90) then raise exception 'Invalid reporting period';end if;
 select jsonb_agg(jsonb_build_object('name',coalesce(r.full_name,r.display_name,r.email),'email',r.email,'role',r.role,'last_sign_in_at',u.last_sign_in_at,'last_active_at',(select max(recorded_at) from pdc_usage_private.events where user_id=r.auth_user_id),'sign_ins',(select count(*) from pdc_usage_private.sessions where user_id=r.auth_user_id and first_seen_at>=cutoff),'active_days',(select count(distinct(recorded_at at time zone 'Australia/Perth')::date) from pdc_usage_private.events where user_id=r.auth_user_id and recorded_at>=cutoff),'page_visits',(select coalesce(sum(visits),0) from pdc_usage_private.events where user_id=r.auth_user_id and recorded_at>=cutoff),'clicks',(select coalesce(sum(clicks),0) from pdc_usage_private.events where user_id=r.auth_user_id and recorded_at>=cutoff),'pages',coalesce((select jsonb_agg(to_jsonb(p) order by p.visits desc,p.page) from(select page,sum(visits) visits,sum(clicks) clicks from pdc_usage_private.events where user_id=r.auth_user_id and recorded_at>=cutoff group by page)p),'[]'::jsonb)) order by coalesce(r.full_name,r.display_name,r.email))
 into result from public.pdc_user_roles r join auth.users u on u.id=r.auth_user_id where r.active and r.account_status='approved';
 return jsonb_build_object('days',p_days,'tracking_started_at',(select started_at from pdc_usage_private.settings),'generated_at',now(),'users',coalesce(result,'[]'::jsonb));
end $$;
create function public.get_pdc_usage_report_20260914(p_days integer default 30)
returns jsonb language sql stable security invoker set search_path=pg_catalog as $$ select pdc_usage_private.report_usage(p_days) $$;
revoke all on function pdc_usage_private.record_usage(uuid,text,integer,boolean),pdc_usage_private.report_usage(integer),public.record_pdc_usage_20260914(uuid,text,integer,boolean),public.get_pdc_usage_report_20260914(integer) from public,anon;
grant execute on function pdc_usage_private.record_usage(uuid,text,integer,boolean),pdc_usage_private.report_usage(integer),public.record_pdc_usage_20260914(uuid,text,integer,boolean),public.get_pdc_usage_report_20260914(integer) to authenticated;
comment on schema pdc_usage_private is 'Admin-only board usage reporting. No typed text, passwords, form values, stock identifiers or click target content collected; records retained for 180 days.';

