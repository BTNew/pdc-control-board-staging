-- Staging-only verification using the actual browser database roles.
-- Generated sessions and activity are rolled back; no user history is backfilled.
begin;
set local statement_timeout='15s';
do $test$
declare uid uuid; mail text; admin_id uuid; admin_mail text; sid uuid:=gen_random_uuid(); expired_sid uuid:=gen_random_uuid(); foreign_sid uuid:=gen_random_uuid();
page_name text; batch uuid; r jsonb; before_usage jsonb; after_usage jsonb; blocked boolean:=false;
begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then raise exception 'Staging mismatch'; end if;
 select auth_user_id,email into strict uid,mail from public.pdc_user_roles r where active and account_status='approved' and role='salesperson' and auth_user_id is not null order by (select count(*) from pdc_usage_private.events e where e.user_id=r.auth_user_id and recorded_at>now()-interval '1 hour'),id limit 1;
 select auth_user_id,email into strict admin_id,admin_mail from public.pdc_user_roles where active and account_status='approved' and role='administrator' and auth_user_id is not null order by id limit 1;
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values(sid,uid,now(),now(),now()+interval '1 minute'),(expired_sid,uid,now(),now(),now()-interval '1 second'),(foreign_sid,admin_id,now(),now(),now()+interval '1 minute');
 execute 'set local role authenticated';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email',admin_mail,'role','authenticated')::text,true);
 select x into strict before_usage from jsonb_array_elements(public.get_pdc_usage_report_20260914(30)->'users') x where x->>'user_id'=uid::text;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'email',mail,'session_id',sid,'role','authenticated')::text,true);
 foreach page_name in array array['dashboard','qc','workflow','planner-bus-4x4','planner-tint','planner-hoist','planner-fitting','planner-fab','planner-elec','planner-tyre','parts','sublet','user-management','lists','import','backup','deleted','collected','completed','backend','newvehicles','emailreview','ai-auditor','fitters','update-history','workshop','visibility','tv','schedule','department','rft','zpl','sales-myday','sales-dashboard','sales-pipeline','sales-customeremails','sales-alerts','sales-finance','sales-finance-statistics','sales-finance-applications','sales-labels','sales-history','other'] loop
 batch:=gen_random_uuid();
 r:=public.record_pdc_usage_20260914(batch,page_name,2,true);
 if r->>'ok' is distinct from 'true' then raise exception 'Page % rejected',page_name;end if;
 r:=public.record_pdc_usage_20260914(batch,page_name,2,true);
 if r->>'replay' is distinct from 'true' then raise exception 'Duplicate counted';end if;
 end loop;
 blocked:=false;
 begin perform count(*) from pdc_usage_private.events;exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Direct usage table access allowed';end if;
 blocked:=false;
 begin perform public.record_pdc_usage_20260914(gen_random_uuid(),'Customer private text',2,true);exception when invalid_parameter_value then blocked:=true;end;
 if not blocked then raise exception 'Sensitive page text accepted';end if;
 blocked:=false;
 begin perform public.record_pdc_usage_20260914(gen_random_uuid(),'sales-finance',201,true);exception when invalid_parameter_value then blocked:=true;end;
 if not blocked then raise exception 'Unbounded clicks accepted';end if;
 blocked:=false;

 begin perform public.get_pdc_usage_report_20260914(30);exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Sales staff can read report';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email',admin_mail,'role','authenticated')::text,true);
 select x into strict after_usage from jsonb_array_elements(public.get_pdc_usage_report_20260914(30)->'users') x where x->>'user_id'=uid::text;
 if (after_usage->>'page_visits')::int<>(before_usage->>'page_visits')::int+43 or (after_usage->>'clicks')::int<>(before_usage->>'clicks')::int+86 or (after_usage->>'sign_ins')::int<>(before_usage->>'sign_ins')::int+1 or after_usage->>'active_now' is distinct from 'true' or after_usage->>'last_sign_in_at' is distinct from before_usage->>'last_sign_in_at' or (after_usage->>'last_active_at')::timestamptz is distinct from now() then raise exception 'Report mismatch';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'email','wrong@example.invalid','session_id',sid,'role','authenticated')::text,true);
 blocked:=false;
 begin perform public.record_pdc_usage_20260914(gen_random_uuid(),'sales-dashboard',1,true);exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Mismatched email accepted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'email',mail,'session_id',expired_sid,'role','authenticated')::text,true);
 blocked:=false;
 begin perform public.record_pdc_usage_20260914(gen_random_uuid(),'sales-dashboard',1,true);exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Expired session accepted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'email',mail,'session_id',foreign_sid,'role','authenticated')::text,true);
 blocked:=false;
 begin perform public.record_pdc_usage_20260914(gen_random_uuid(),'sales-dashboard',1,true);exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Foreign session accepted';end if;
 perform set_config('request.jwt.claims','{}',true);
 blocked:=false;
 begin perform public.record_pdc_usage_20260914(gen_random_uuid(),'sales-dashboard',1,true);exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Signed-out usage accepted';end if;
 execute 'set local role anon';
 blocked:=false;
 begin perform public.record_pdc_usage_20260914(gen_random_uuid(),'sales-dashboard',1,true);exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Anonymous RPC allowed';end if;
end $test$;
reset role;
select 'PASS all 43 pages, authenticated Sales role, Admin-only report, privacy, deduplication and presence; test records roll back' as result;
rollback;
