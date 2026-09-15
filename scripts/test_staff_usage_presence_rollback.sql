-- Run against staging after the candidate migration, or append both inside a
-- single BEGIN/ROLLBACK candidate check. All auth/session fixtures roll back.
begin;
set local statement_timeout = '30s';

create function pg_temp.assert_usage_count_parity(p_days integer)
returns void language plpgsql as $test$
declare
  actual jsonb := public.get_pdc_usage_report_20260914(p_days);
  expected jsonb;
  cutoff timestamptz := now() - make_interval(days => p_days);
  stripped jsonb;
begin
  -- The original report's queries are intentionally retained as an independent
  -- oracle for every old field, including zero-use staff and page breakdowns.
  select jsonb_agg(jsonb_build_object(
    'name',coalesce(r.full_name,r.display_name,r.email),'email',r.email,'role',r.role,
    'last_sign_in_at',u.last_sign_in_at,
    'last_active_at',(select max(recorded_at) from pdc_usage_private.events where user_id=r.auth_user_id),
    'sign_ins',(select count(*) from pdc_usage_private.sessions where user_id=r.auth_user_id and first_seen_at>=cutoff),
    'active_days',(select count(distinct(recorded_at at time zone 'Australia/Perth')::date) from pdc_usage_private.events where user_id=r.auth_user_id and recorded_at>=cutoff),
    'page_visits',(select coalesce(sum(visits),0) from pdc_usage_private.events where user_id=r.auth_user_id and recorded_at>=cutoff),
    'clicks',(select coalesce(sum(clicks),0) from pdc_usage_private.events where user_id=r.auth_user_id and recorded_at>=cutoff),
    'pages',coalesce((select jsonb_agg(to_jsonb(p) order by p.visits desc,p.page)
      from (select page,sum(visits) visits,sum(clicks) clicks from pdc_usage_private.events
        where user_id=r.auth_user_id and recorded_at>=cutoff group by page) p),'[]'::jsonb)
  ) order by coalesce(r.full_name,r.display_name,r.email),r.email)
  into expected from public.pdc_user_roles r join auth.users u on u.id=r.auth_user_id
  where r.active and r.account_status='approved';
  select jsonb_agg(x - 'user_id' - 'active_now' - 'presence_last_active_at' order by ord)
  into stripped from jsonb_array_elements(actual->'users') with ordinality as t(x,ord);
  if coalesce(stripped,'[]'::jsonb) is distinct from coalesce(expected,'[]'::jsonb) then
    raise exception 'Usage count parity failed for % days',p_days;
  end if;
end $test$;

do $test$
declare
  uid uuid; admin_id uuid; staff_email text; admin_email text;
  sid uuid := gen_random_uuid(); sid2 uuid := gen_random_uuid();
  idle_sid uuid := gen_random_uuid(); old_sid uuid := gen_random_uuid();
  b1 uuid := gen_random_uuid(); b2 uuid := gen_random_uuid();
  claims_staff text; claims_admin text;
  r jsonb; person jsonb; baseline jsonb;
  blocked boolean; old_activity timestamptz := now() - interval '3 minutes';
begin
  if not exists(select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'Staging environment sentinel mismatch';
  end if;
  select auth_user_id,email into strict uid,staff_email
  from public.pdc_user_roles r
  where role='operator' and active and account_status='approved' and auth_user_id is not null
  order by (select count(*) from pdc_usage_private.events e
    where e.user_id=r.auth_user_id and recorded_at>now()-interval '1 hour'),r.id limit 1;
  select auth_user_id,email into strict admin_id,admin_email
  from public.pdc_user_roles where role='administrator' and active
    and account_status='approved' and auth_user_id is not null order by id limit 1;
  claims_staff := jsonb_build_object('sub',uid,'email',staff_email,'session_id',sid,'role','authenticated')::text;
  claims_admin := jsonb_build_object('sub',admin_id,'email',admin_email,'role','authenticated')::text;

  perform set_config('request.jwt.claims',claims_admin,true);
  perform pg_temp.assert_usage_count_parity(7);
  perform pg_temp.assert_usage_count_parity(30);
  perform pg_temp.assert_usage_count_parity(90);
  r := public.get_pdc_usage_report_20260914(30);
  if (r->>'active_window_seconds')::integer is distinct from 120
      or (r->>'generated_at')::timestamptz is distinct from now() then
    raise exception 'Presence report timing contract incorrect';
  end if;
  select x into strict baseline from jsonb_array_elements(r->'users') x where x->>'user_id'=uid::text;

  -- Isolate this user's existing presence inside the rollback transaction only.
  update pdc_usage_private.sessions set last_active_at=null where user_id=uid;
  insert into auth.sessions(id,user_id,created_at,updated_at)
  values(sid,uid,now(),now()),(sid2,uid,now(),now()),
    (idle_sid,uid,now(),now()),(old_sid,uid,now()-interval '181 days',now());
  perform set_config('request.jwt.claims',claims_staff,true);
  r := public.record_pdc_usage_20260914(b1,'dashboard',3,true);
  if r->>'ok' is distinct from 'true' then raise exception 'Real activity rejected'; end if;
  if (select last_active_at from pdc_usage_private.sessions where user_id=uid and session_id=sid)
      is distinct from now() then raise exception 'Exact session activity missing'; end if;
  perform set_config('request.jwt.claims',claims_admin,true);
  r := public.get_pdc_usage_report_20260914(30);
  select x into strict person from jsonb_array_elements(r->'users') x where x->>'user_id'=uid::text;
  if person->>'active_now' is distinct from 'true'
      or (person->>'presence_last_active_at')::timestamptz is distinct from now() then
    raise exception 'Recent authenticated activity must show active';
  end if;

  update pdc_usage_private.sessions set last_active_at=old_activity where user_id=uid and session_id=sid;
  perform set_config('request.jwt.claims',claims_staff,true);
  r := public.record_pdc_usage_20260914(b1,'dashboard',3,true);
  if r->>'replay' is distinct from 'true' then raise exception 'Retry not deduplicated'; end if;
  perform public.record_pdc_usage_20260914(b2,'dashboard',0,false);
  update auth.sessions set updated_at=now(),refreshed_at=now() at time zone 'UTC' where id=sid;
  if (select last_active_at from pdc_usage_private.sessions where user_id=uid and session_id=sid)
      is distinct from old_activity then raise exception 'Replay/empty batch revived presence'; end if;
  perform set_config('request.jwt.claims',claims_admin,true);
  r := public.get_pdc_usage_report_20260914(30);
  select x into strict person from jsonb_array_elements(r->'users') x where x->>'user_id'=uid::text;
  if person->>'active_now' is distinct from 'false' then raise exception 'Idle refreshed session showed active'; end if;

  perform set_config('request.jwt.claims',claims_staff,true);
  perform public.record_pdc_usage_20260914(gen_random_uuid(),'parts',4,false);
  if (select last_active_at from pdc_usage_private.sessions where user_id=uid and session_id=sid)
      is distinct from now() then raise exception 'Click-only batch did not revive presence'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'email',staff_email,'session_id',sid2,'role','authenticated')::text,true);
  r := public.record_pdc_usage_20260914(b1,'dashboard',3,true);
  if r->>'replay' is distinct from 'true'
      or exists(select 1 from pdc_usage_private.sessions where user_id=uid and session_id=sid2) then
    raise exception 'Cross-session replay created false presence/sign-in';
  end if;
  perform public.record_pdc_usage_20260914(gen_random_uuid(),'qc',0,true);
  perform set_config('request.jwt.claims',claims_admin,true);
  r := public.get_pdc_usage_report_20260914(30);
  select x into strict person from jsonb_array_elements(r->'users') x where x->>'user_id'=uid::text;
  if (person->>'sign_ins')::bigint is distinct from (baseline->>'sign_ins')::bigint+2 then
    raise exception 'Distinct sign-in session counts changed';
  end if;

  -- One revoked browser must not hide activity in another still-valid browser.
  delete from auth.sessions where id=sid2;
  r := public.get_pdc_usage_report_20260914(30);
  select x into strict person from jsonb_array_elements(r->'users') x where x->>'user_id'=uid::text;
  if person->>'active_now' is distinct from 'true' then raise exception 'Valid second session lost presence'; end if;
  update pdc_usage_private.sessions set last_active_at=old_activity where user_id=uid and session_id=sid;
  r := public.get_pdc_usage_report_20260914(30);
  select x into strict person from jsonb_array_elements(r->'users') x where x->>'user_id'=uid::text;
  if person->>'active_now' is distinct from 'false'
      or (person->>'presence_last_active_at')::timestamptz is distinct from old_activity then
    raise exception 'Revoked recent session made idle session active';
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'email',staff_email,'session_id',sid2,'role','authenticated')::text,true);
  blocked := false;
  begin perform public.record_pdc_usage_20260914(gen_random_uuid(),'dashboard',1,false);
  exception when insufficient_privilege then blocked := true; end;
  if not blocked then raise exception 'Revoked session recorded activity'; end if;

  -- Explicitly expired sessions can remain in auth.sessions until Auth cleans up.
  update auth.sessions set not_after=now()-interval '1 second' where id=sid;
  update pdc_usage_private.sessions set last_active_at=now() where user_id=uid and session_id=sid;
  perform set_config('request.jwt.claims',claims_admin,true);
  r := public.get_pdc_usage_report_20260914(30);
  select x into strict person from jsonb_array_elements(r->'users') x where x->>'user_id'=uid::text;
  if person->>'active_now' is distinct from 'false' then raise exception 'Expired session showed active'; end if;
  perform set_config('request.jwt.claims',claims_staff,true);
  blocked := false;
  begin perform public.record_pdc_usage_20260914(gen_random_uuid(),'dashboard',1,false);
  exception when insufficient_privilege then blocked := true; end;
  if not blocked then raise exception 'Expired session recorded activity'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'email',staff_email,'session_id',idle_sid,'role','authenticated')::text,true);
  perform public.record_pdc_usage_20260914(gen_random_uuid(),'dashboard',0,false);
  if (select last_active_at from pdc_usage_private.sessions where user_id=uid and session_id=idle_sid)
      is not null then raise exception 'Empty first batch manufactured presence'; end if;
  perform set_config('request.jwt.claims',claims_admin,true);
  r := public.get_pdc_usage_report_20260914(30);
  select x into strict person from jsonb_array_elements(r->'users') x where x->>'user_id'=uid::text;
  if person->>'active_now' is distinct from 'false' then raise exception 'Idle new session inherited other session activity'; end if;

  -- Sign-ins older than retention must still show genuine current activity.
  insert into pdc_usage_private.sessions(user_id,session_id,first_seen_at)
  values(uid,old_sid,now()-interval '181 days');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'email',staff_email,'session_id',old_sid,'role','authenticated')::text,true);
  perform public.record_pdc_usage_20260914(gen_random_uuid(),'parts',2,false);
  if (select last_active_at from pdc_usage_private.sessions where user_id=uid and session_id=old_sid)
      is distinct from now() then raise exception 'Retention deleted current old-session presence'; end if;
  blocked := false;
  begin perform public.get_pdc_usage_report_20260914(30);
  exception when insufficient_privilege then blocked := true; end;
  if not blocked then raise exception 'Non-administrator read the report'; end if;

  perform set_config('request.jwt.claims',claims_admin,true);
  r := public.get_pdc_usage_report_20260914(30);
  select x into strict person from jsonb_array_elements(r->'users') x where x->>'user_id'=uid::text;
  if (person->>'clicks')::bigint is distinct from (baseline->>'clicks')::bigint+9
      or (person->>'page_visits')::bigint is distinct from (baseline->>'page_visits')::bigint+2
      or (person->>'sign_ins')::bigint is distinct from (baseline->>'sign_ins')::bigint+3 then
    raise exception 'Usage totals changed or duplicate/revoked batches were counted';
  end if;
  perform pg_temp.assert_usage_count_parity(7);
  perform pg_temp.assert_usage_count_parity(30);
  perform pg_temp.assert_usage_count_parity(90);
  blocked := false;
  begin perform public.get_pdc_usage_report_20260914(null);
  exception when invalid_parameter_value then blocked := true; end;
  if not blocked then raise exception 'Null reporting window accepted'; end if;
  perform set_config('request.jwt.claims','{}',true);
  blocked := false;
  begin perform public.get_pdc_usage_report_20260914(30);
  exception when insufficient_privilege then blocked := true; end;
  if not blocked then raise exception 'Signed-out report access accepted'; end if;
  if has_table_privilege('authenticated','pdc_usage_private.sessions','SELECT')
      or has_table_privilege('authenticated','pdc_usage_private.sessions','INSERT')
      or has_function_privilege('anon','public.get_pdc_usage_report_20260914(integer)','EXECUTE')
      or has_function_privilege('anon','pdc_usage_private.report_usage(integer)','EXECUTE') then
    raise exception 'Private usage access was exposed';
  end if;
end $test$;

select 'PASS: recent/idle/replay/empty/refreshed/revoked/expired/multiple-session presence, distinct sign-ins, retention, 7/30/90-day count parity, non-admin and signed-out denial; fixtures rolled back' as result;
rollback;

