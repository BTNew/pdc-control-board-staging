-- Disposable PostgreSQL 17 fixture for source-only draft migration 253.
-- No staging/production connection or credential is used.
\set ON_ERROR_STOP on

do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;
create schema auth;
create schema extensions;
create schema supabase_migrations;
create extension pgcrypto with schema extensions;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)$$;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');
create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
create table public.pdc_staging_environment_sentinel(singleton boolean primary key,project_ref text not null);
insert into public.pdc_staging_environment_sentinel values(true,'cdsmnqxtyyoeoznmbidd');

create type public.pdc_role as enum('viewer','operator','importer','administrator');
create type public.pdc_account_status as enum('pending','approved','disabled','rejected');
create type public.vehicle_lifecycle_state as enum('active','rft','completed','deleted');
create type public.audit_action as enum('insert','update','move','import','delete','restore','rft','role_change','reference_change','rollback');
create table public.pdc_user_roles(id uuid primary key default gen_random_uuid(),email text unique not null,role public.pdc_role not null,active boolean not null,auth_user_id uuid references auth.users(id),account_status public.pdc_account_status not null,approved_at timestamptz,disabled_at timestamptz,revoked_at timestamptz);
create table public.vehicles(id uuid primary key,permanent_vehicle_id text unique not null,stock_number text,job_card_number text,lifecycle_state public.vehicle_lifecycle_state not null default 'active',current_location text,rft_collected_at timestamptz,deleted_at timestamptz,pmb_stage text,pmb_bay_stage text,pmb_bay_number text,active_workshop_booking_id uuid,workshop_status text,workshop_status_updated_at timestamptz,workshop_status_updated_by uuid,visible_on_board boolean not null default true,version integer not null default 1,updated_by uuid,updated_at timestamptz not null default clock_timestamp());
create table public.vehicle_work_items(id uuid primary key default gen_random_uuid(),vehicle_id uuid not null references public.vehicles(id),work_key text not null,required boolean not null default false,completed boolean not null default false,completed_by uuid references auth.users(id),completed_at timestamptz,notes text,updated_at timestamptz not null default clock_timestamp(),unique(vehicle_id,work_key));
create table public.audit_events(id uuid primary key default gen_random_uuid(),action public.audit_action not null,table_name text,row_id uuid,vehicle_id uuid,actor_id uuid,actor_email text,before_data jsonb,after_data jsonb,metadata jsonb not null default '{}',created_at timestamptz default clock_timestamp());

-- Empty Workshop compatibility schema used only so authentic self-ledgering
-- migrations 239-250 compile and establish migration 253's real predecessor.
create type public.workshop_booking_status as enum('queued','planned','started','stoppage','completed','cancelled');
create type public.workshop_assignment_type as enum('primary','support');
create table public.workshop_stages(id uuid primary key default gen_random_uuid(),code text unique not null,active boolean not null default true,planner_enabled boolean not null default true);
create table public.workshop_bays(id uuid primary key default gen_random_uuid(),stage_id uuid references public.workshop_stages(id),bay_number integer not null,is_active boolean not null default true);
create table public.workshop_bookings(id uuid primary key default gen_random_uuid(),vehicle_id uuid not null references public.vehicles(id),stage_id uuid not null references public.workshop_stages(id),bay_id uuid references public.workshop_bays(id),status public.workshop_booking_status not null default 'planned',scheduled_start_at timestamptz not null default clock_timestamp(),scheduled_end_at timestamptz not null default clock_timestamp(),default_duration_minutes integer not null default 60,actual_start_at timestamptz,actual_end_at timestamptz,actual_duration_minutes integer,stoppage_reason text,stoppage_started_at timestamptz,stoppage_accumulated_minutes integer not null default 0,returned_to_queue_at timestamptz,deleted_at timestamptz,deleted_reason text,source text,metadata_legacy_plan_id text,metadata jsonb not null default '{}',eta_at_booking date,eta_risk_status text,eta_risk_detected_at timestamptz,legacy_ambiguity_quarantined boolean not null default false,version integer not null default 1,updated_by uuid,updated_at timestamptz not null default clock_timestamp(),created_at timestamptz not null default clock_timestamp());
create table public.workshop_booking_assignments(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.workshop_bookings(id) on delete cascade,technician_id uuid,assignment_type public.workshop_assignment_type not null default 'primary',assigned_at timestamptz not null default clock_timestamp(),assigned_by uuid,scheduled_start_at timestamptz,scheduled_end_at timestamptz,released_at timestamptz,notes text,updated_at timestamptz not null default clock_timestamp());
create table public.workshop_booking_history(id uuid primary key default gen_random_uuid(),booking_id uuid references public.workshop_bookings(id),event_type text not null,before_data jsonb,after_data jsonb,metadata jsonb,actor_user_id uuid,actor_email text,created_at timestamptz not null default clock_timestamp());
create table public.workshop_booking_move_receipts(receipt_id uuid primary key default gen_random_uuid(),request_id uuid not null,actor_user_id uuid not null references auth.users(id),actor_email text not null,booking_id uuid not null references public.workshop_bookings(id),source text not null,reason text,cascade boolean not null,before_rows jsonb not null,after_rows jsonb not null,result jsonb not null,created_at timestamptz not null default clock_timestamp(),undone_at timestamptz,undone_by uuid references auth.users(id),undo_request_id uuid,undo_result jsonb,unique(actor_user_id,request_id));
create table public.pdc_auditor_executor_identities(auth_user_id uuid,normalized_email text,dealer_code text,environment text,active boolean,expires_at timestamptz,disabled_at timestamptz);
create table public.pdc_auditor_service_identities_225(service_identity_id uuid primary key default gen_random_uuid(),auth_user_id uuid,normalized_email text,dealer_code text,environment text,identity_purpose text,active boolean,approved_by_user_id uuid,approved_at timestamptz default clock_timestamp(),revoked_at timestamptz);
create table public.pdc_auditor_worker_identities(auth_user_id uuid,normalized_email text,dealer_code text,environment text,active boolean);
create table public.pdc_supervised_telegram_identities(identity_id uuid primary key default gen_random_uuid(),telegram_sender_id bigint not null unique,auth_user_id uuid not null references auth.users(id),actor_email text not null,authorized_by uuid not null references auth.users(id),active boolean not null default true,created_at timestamptz not null default clock_timestamp());
create table public.pdc_monitor_stage_activation_writers(user_id uuid,active boolean,revoked_at timestamptz);
create table public.pdc_monitor_vehicle_identity_readers(user_id uuid,active boolean,revoked_at timestamptz);
create function public.workshop_require_website_administrator_238() returns void language plpgsql security definer as $$begin null;end$$;
create function public.workshop_canonical_stage_code(text) returns text language sql immutable as $$select upper(btrim($1))$$;
create function public.workshop_booking_effective_end_at(uuid) returns timestamptz language sql stable as $$select scheduled_end_at from public.workshop_bookings where id=$1$$;
create function public.workshop_booking_move_row_238(public.workshop_bookings) returns jsonb language sql immutable as $$select to_jsonb($1)$$;
create function public.workshop_bump_revision() returns void language plpgsql as $$begin null;end$$;
create function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) returns jsonb language sql as $$select jsonb_build_object('ok',false)$$;
create function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb) returns jsonb language sql as $$select jsonb_build_object('ok',false)$$;
create function public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb) returns jsonb language sql as $$select jsonb_build_object('ok',false)$$;
create function public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb) returns jsonb language sql as $$select jsonb_build_object('ok',false)$$;
create function public.resize_workshop_booking(uuid,integer,integer,jsonb) returns jsonb language sql as $$select jsonb_build_object('ok',false)$$;
create function public.change_booking_bay(uuid,integer,integer,jsonb) returns jsonb language sql as $$select jsonb_build_object('ok',false)$$;
create function public.undo_administrator_workshop_booking_move(uuid,integer,uuid) returns jsonb language sql as $$select jsonb_build_object('ok',false)$$;

create table public.pdc_authenticated_email_operation_lines(operation_line_id uuid primary key default gen_random_uuid(),import_receipt_id uuid not null default gen_random_uuid(),vehicle_id uuid not null references public.vehicles(id),source_hash text not null,source_uid text not null,operation_no text not null,work_key text not null,description text not null,operation_fingerprint text not null,estimated_hours numeric(6,2),estimated_hours_source text,job_card_number text,source_row_no integer,source_contract text,created_at timestamptz not null default clock_timestamp());
create table public.vehicle_workshop_line_adjustments(adjustment_id uuid primary key default gen_random_uuid(),vehicle_id uuid not null references public.vehicles(id),line_key text not null,source_kind text not null,stage_code text not null,description text not null,estimated_hours numeric(6,2),active boolean not null default true,version bigint not null default 1,created_by uuid not null,created_at timestamptz not null default clock_timestamp(),updated_by uuid not null,updated_at timestamptz not null default clock_timestamp(),operation_code text,display_order integer,manual_assignment_locked boolean not null default false,correction_origin text check(correction_origin is null or correction_origin in('ai_auditor','ai_auditor_rolled_back','manual_operator')),source_operation_line_id uuid references public.pdc_authenticated_email_operation_lines,job_card_number text,unique(vehicle_id,line_key));

create view public.pdc_effective_operation_lines with(security_invoker=false) as
with source_rows as(
 select ol.operation_line_id::text operation_line_identifier,ol.operation_line_id,ol.vehicle_id,coalesce(a.job_card_number,ol.job_card_number) job_card_number,coalesce(a.operation_code,ol.operation_no) operation_code,coalesce(case a.stage_code when 'FITTING' then 'fitting' when 'TINT' then 'tint' when 'HOIST' then 'hoist' when 'ELEC' then 'electrical' when 'FAB' then 'fabrication' when 'TYRE' then 'tyre' when 'PIT' then 'pitInspection' end,ol.work_key) work_key,coalesce(a.description,ol.description) description,coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,coalesce(a.display_order,ol.source_row_no) display_order,coalesce(a.active,true) active,coalesce(a.manual_assignment_locked,false) manual_assignment_locked,a.adjustment_id,a.correction_origin
 from public.pdc_authenticated_email_operation_lines ol left join public.vehicle_workshop_line_adjustments a on a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text and coalesce(a.correction_origin,'')<>'ai_auditor_rolled_back'
), added_rows as(
 select a.adjustment_id::text,null::uuid,a.vehicle_id,a.job_card_number,a.operation_code,case a.stage_code when 'FITTING' then 'fitting' when 'TINT' then 'tint' when 'HOIST' then 'hoist' when 'ELEC' then 'electrical' when 'FAB' then 'fabrication' when 'TYRE' then 'tyre' when 'PIT' then 'pitInspection' end,a.description,a.estimated_hours,a.display_order,a.active,a.manual_assignment_locked,a.adjustment_id,a.correction_origin from public.vehicle_workshop_line_adjustments a where a.correction_origin='ai_auditor' and a.source_operation_line_id is null and a.active
) select * from source_rows union all select * from added_rows;

create table public.pdc_auditor_workshop_revisions(revision_id bigint generated always as identity primary key,dealer_code text not null check(dealer_code in('14450','37047')),environment text not null check(environment='staging'),event_type text not null,run_id uuid not null,rollback_receipt_id uuid,created_at timestamptz not null default clock_timestamp(),constraint revision_shape check((event_type='telegram_plan_applied_226' and rollback_receipt_id is null) or (event_type='telegram_run_rolled_back_226' and rollback_receipt_id is not null)),unique(run_id,event_type));
alter table public.pdc_auditor_workshop_revisions enable row level security;
create publication supabase_realtime;
alter publication supabase_realtime add table public.vehicle_workshop_line_adjustments,public.pdc_auditor_workshop_revisions;

create table public.fixture_vehicle_dealers(vehicle_id uuid primary key,dealer_code text not null);
create table public.pdc_auditor_user_dealer_scopes(auth_user_id uuid,email text,normalized_email text,dealer_code text,environment text,active boolean);
create function public.pdc_auditor_reject_history_mutation() returns trigger language plpgsql as $$begin raise exception 'immutable history' using errcode='55000';end$$;
create table public.pdc_auditor_telegram_deliveries_230(delivery_id uuid primary key default gen_random_uuid(),delivery_domain text not null check(delivery_domain in('operation','rule')),telegram_sender_id bigint not null,telegram_chat_id bigint not null,telegram_message_id bigint not null check(telegram_message_id>0),telegram_update_id bigint not null check(telegram_update_id>=0),bot_identity text not null,original_instruction text not null,instruction_sha256 text not null check(instruction_sha256~'^[a-f0-9]{64}$'),source_table text not null check(source_table in('pdc_auditor_telegram_instructions_225','pdc_auditor_rule_commands_227')),source_id uuid not null,reserved_at timestamptz not null default clock_timestamp(),unique(telegram_chat_id,telegram_message_id),unique(bot_identity,telegram_update_id),unique(source_table,source_id));
alter table public.pdc_auditor_telegram_deliveries_230 enable row level security;
revoke all on public.pdc_auditor_telegram_deliveries_230 from public,anon,authenticated,service_role;
create trigger pdc_auditor_telegram_deliveries_immutable_230 before update or delete on public.pdc_auditor_telegram_deliveries_230 for each row execute function public.pdc_auditor_reject_history_mutation();
create function public.pdc_auditor_normalize_identity_225(text) returns text language sql immutable as $$select lower(regexp_replace(btrim(coalesce($1,'')),'[^a-z0-9]+',' ','g'))$$;
create function public.workshop_stage_code_for_work_key(text) returns text language sql immutable as $$select case $1 when 'fitting' then 'FITTING' when 'tint' then 'TINT' when 'hoist' then 'HOIST' when 'electrical' then 'ELEC' when 'fabrication' then 'FAB' when 'tyre' then 'TYRE' when 'pitInspection' then 'PIT' end$$;
create function public.pdc_auditor_vehicle_dealer(uuid) returns text language sql stable as $$select dealer_code from public.fixture_vehicle_dealers where vehicle_id=$1$$;
create function public.pdc_auditor_operational_revision(text) returns text language sql stable set search_path=pg_catalog,public,extensions as $$select encode(extensions.digest(convert_to(coalesce((select string_agg(id::text||coalesce(stock_number,''),'|' order by id) from public.vehicles),'')||coalesce((select string_agg(adjustment_id::text||version::text||active::text,'|' order by adjustment_id) from public.vehicle_workshop_line_adjustments),''),'UTF8'),'sha256'),'hex')$$;
create function public.pdc_auditor_telegram_actor_scope_225(p_telegram_sender_id bigint)
returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,auth
as $scope$
declare
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_service public.pdc_auditor_service_identities_225%rowtype;
  v_admin uuid;
  v_admin_email text;
  v_count integer;
begin
  if v_uid is null or v_email='' or coalesce(auth.jwt()->>'role','')='service_role' then
    raise exception 'PDC_225_SERVICE_IDENTITY_REQUIRED' using errcode='42501';
  end if;
  select count(*) into v_count
  from public.pdc_auditor_service_identities_225 s
  join auth.users au on au.id=s.auth_user_id and lower(coalesce(au.email,''))=s.normalized_email
  join public.pdc_user_roles r on r.auth_user_id=s.auth_user_id
    and lower(r.email)=s.normalized_email and r.role::text='viewer'
    and r.active and r.account_status='approved'
  join public.pdc_user_roles approver on approver.auth_user_id=s.approved_by_user_id
    and approver.role::text='administrator' and approver.active and approver.account_status='approved'
  join auth.users approving_user on approving_user.id=s.approved_by_user_id
    and lower(coalesce(approving_user.email,''))=lower(approver.email)
  join public.pdc_auditor_worker_identities w on w.auth_user_id=s.auth_user_id
    and w.normalized_email=s.normalized_email and w.dealer_code=s.dealer_code
    and w.environment=s.environment and w.active
  join public.pdc_auditor_user_dealer_scopes d on d.auth_user_id=s.auth_user_id
    and d.normalized_email=s.normalized_email and d.dealer_code=s.dealer_code
    and d.environment=s.environment and d.active
  where s.auth_user_id=v_uid and s.normalized_email=v_email
    and s.environment='staging' and s.identity_purpose='ai_auditor_telegram_planner'
    and s.active and s.revoked_at is null;
  if v_count<>1 then
    raise exception 'PDC_225_SERVICE_IDENTITY_REQUIRED' using errcode='42501';
  end if;
  select * into strict v_service
  from public.pdc_auditor_service_identities_225 s
  where s.auth_user_id=v_uid and s.normalized_email=v_email
    and s.environment='staging' and s.identity_purpose='ai_auditor_telegram_planner'
    and s.active and s.revoked_at is null;

  select count(*),min(i.auth_user_id::text)::uuid,min(lower(i.actor_email))
    into v_count,v_admin,v_admin_email
  from public.pdc_supervised_telegram_identities i
  join auth.users au on au.id=i.auth_user_id and lower(coalesce(au.email,''))=lower(i.actor_email)
  join public.pdc_user_roles r on r.auth_user_id=i.auth_user_id
    and lower(r.email)=lower(i.actor_email) and r.role::text='administrator'
    and r.active and r.account_status='approved'
  where i.telegram_sender_id=p_telegram_sender_id and i.active
    and (p_telegram_sender_id=7828138290 or r.role::text='administrator');
  if v_count<>1 then
    raise exception 'PDC_225_TELEGRAM_ADMINISTRATOR_REQUIRED' using errcode='42501';
  end if;
  return jsonb_build_object(
    'service_identity_id',v_service.service_identity_id,
    'service_user_id',v_uid,'service_email',v_email,
    'admin_user_id',v_admin,'admin_email',v_admin_email,
    'dealer_code',v_service.dealer_code,'environment','staging'
  );
end
$scope$;
revoke all on function public.pdc_auditor_telegram_actor_scope_225(bigint) from public,anon,authenticated,service_role;

alter function public.pdc_auditor_telegram_actor_scope_225(bigint)
  rename to pdc_auditor_telegram_actor_scope_base_225;
revoke all on function public.pdc_auditor_telegram_actor_scope_base_225(bigint)
  from public,anon,authenticated,service_role;
create function public.pdc_auditor_telegram_actor_scope_225(p_telegram_sender_id bigint)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth
as $scope$
declare v_actor jsonb; v_count integer;
begin
  v_actor:=public.pdc_auditor_telegram_actor_scope_base_225(p_telegram_sender_id);
  select count(*) into v_count
  from public.pdc_supervised_telegram_identities i
  join auth.users au on au.id=i.auth_user_id and lower(coalesce(au.email,''))=lower(i.actor_email)
  join public.pdc_user_roles r on r.auth_user_id=i.auth_user_id
    and lower(r.email)=lower(i.actor_email) and r.role::text='administrator'
    and r.active and r.account_status='approved'
  where i.telegram_sender_id=p_telegram_sender_id and i.active
    and i.auth_user_id=(v_actor->>'admin_user_id')::uuid
    and lower(i.actor_email)=lower(v_actor->>'admin_email');
  if v_count<>1 then
    raise exception 'PDC_230_TELEGRAM_ADMINISTRATOR_REQUIRED' using errcode='42501';
  end if;
  return v_actor;
end
$scope$;
revoke all on function public.pdc_auditor_telegram_actor_scope_225(bigint)
  from public,anon,authenticated,service_role;

insert into auth.users values('10000000-0000-4000-8000-000000000002','auditor@example.test','{}'),('10000000-0000-4000-8000-000000000003','craig@example.test','{}');
insert into public.pdc_user_roles(email,role,active,auth_user_id,account_status,approved_at,disabled_at) values
('auditor@example.test','viewer',true,'10000000-0000-4000-8000-000000000002','approved',clock_timestamp(),null),
('craig@example.test','administrator',true,'10000000-0000-4000-8000-000000000003','approved',clock_timestamp(),null);
insert into public.pdc_auditor_user_dealer_scopes values
('10000000-0000-4000-8000-000000000002','auditor@example.test','auditor@example.test','14450','staging',true),
('10000000-0000-4000-8000-000000000003','craig@example.test','craig@example.test','14450','staging',true);
insert into public.pdc_auditor_worker_identities values('10000000-0000-4000-8000-000000000002','auditor@example.test','14450','staging',true);
insert into public.pdc_auditor_service_identities_225(service_identity_id,auth_user_id,normalized_email,dealer_code,environment,identity_purpose,active,approved_by_user_id,revoked_at) values('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','auditor@example.test','14450','staging','ai_auditor_telegram_planner',true,'10000000-0000-4000-8000-000000000003',null);
insert into public.pdc_supervised_telegram_identities(telegram_sender_id,auth_user_id,actor_email,authorized_by,active) values(7828138290,'10000000-0000-4000-8000-000000000003','craig@example.test','10000000-0000-4000-8000-000000000003',true);
grant usage on schema auth to authenticated;
grant select on auth.users,public.pdc_user_roles,public.pdc_auditor_user_dealer_scopes to authenticated;
insert into public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,current_location,rft_collected_at,deleted_at) values('20000000-0000-4000-8000-000000000001','perm-1','STK1','JC1','active','YH',null,null);
insert into public.fixture_vehicle_dealers values('20000000-0000-4000-8000-000000000001','14450');
insert into public.pdc_authenticated_email_operation_lines(operation_line_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,estimated_hours,job_card_number,source_row_no) values('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','hash-1','uid-1','OP1','fitting','Fit item','fingerprint-1',2.00,'JC1',1);
