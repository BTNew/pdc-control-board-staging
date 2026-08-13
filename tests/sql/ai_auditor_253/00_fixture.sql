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
insert into supabase_migrations.schema_migrations values('250','baseline_head',array['local source fixture']);
create table public.pdc_staging_environment_sentinel(singleton boolean primary key,project_ref text not null);
insert into public.pdc_staging_environment_sentinel values(true,'cdsmnqxtyyoeoznmbidd');

create type public.pdc_role as enum('viewer','operator','importer','administrator');
create type public.pdc_account_status as enum('pending','approved','disabled','rejected');
create type public.vehicle_lifecycle_state as enum('active','rft','completed','deleted');
create type public.audit_action as enum('insert','update','move','import','delete','restore','rft','role_change','reference_change','rollback');
create table public.pdc_user_roles(id uuid primary key default gen_random_uuid(),email text unique not null,role public.pdc_role not null,active boolean not null,auth_user_id uuid references auth.users(id),account_status public.pdc_account_status not null);
create table public.vehicles(id uuid primary key,permanent_vehicle_id text unique not null,stock_number text,job_card_number text,lifecycle_state public.vehicle_lifecycle_state not null default 'active',current_location text,rft_collected_at timestamptz,deleted_at timestamptz);
create table public.vehicle_work_items(id uuid primary key default gen_random_uuid(),vehicle_id uuid not null references public.vehicles(id),work_key text not null,required boolean not null default false,completed boolean not null default false,completed_by uuid references auth.users(id),completed_at timestamptz,notes text,updated_at timestamptz not null default clock_timestamp(),unique(vehicle_id,work_key));
create table public.audit_events(id uuid primary key default gen_random_uuid(),action public.audit_action not null,table_name text,row_id uuid,vehicle_id uuid,actor_id uuid,actor_email text,before_data jsonb,after_data jsonb,metadata jsonb not null default '{}',created_at timestamptz default clock_timestamp());
create table public.pdc_authenticated_email_operation_lines(operation_line_id uuid primary key default gen_random_uuid(),import_receipt_id uuid not null default gen_random_uuid(),vehicle_id uuid not null references public.vehicles(id),source_hash text not null,source_uid text not null,operation_no text not null,work_key text not null,description text not null,operation_fingerprint text not null,estimated_hours numeric(6,2),estimated_hours_source text,job_card_number text,source_row_no integer,source_contract text,created_at timestamptz not null default clock_timestamp());
create table public.vehicle_workshop_line_adjustments(adjustment_id uuid primary key default gen_random_uuid(),vehicle_id uuid not null references public.vehicles(id),line_key text not null,source_kind text not null,stage_code text not null,description text not null,estimated_hours numeric(6,2),active boolean not null default true,version bigint not null default 1,created_by uuid not null,created_at timestamptz not null default clock_timestamp(),updated_by uuid not null,updated_at timestamptz not null default clock_timestamp(),operation_code text,display_order integer,manual_assignment_locked boolean not null default false,correction_origin text check(correction_origin is null or correction_origin in('ai_auditor','ai_auditor_rolled_back','manual_operator')),source_operation_line_id uuid references public.pdc_authenticated_email_operation_lines,job_card_number text,unique(vehicle_id,line_key));

create view public.pdc_effective_operation_lines with(security_invoker=false) as
with source_rows as(
 select ol.operation_line_id::text operation_line_identifier,ol.operation_line_id,ol.vehicle_id,coalesce(a.job_card_number,ol.job_card_number) job_card_number,coalesce(a.operation_code,ol.operation_no) operation_code,coalesce(case a.stage_code when 'FITTING' then 'fitting' when 'TINT' then 'tint' when 'HOIST' then 'hoist' when 'ELEC' then 'electrical' when 'FAB' then 'fabrication' when 'TYRE' then 'tyre' when 'PIT' then 'pitInspection' end,ol.work_key) work_key,coalesce(a.description,ol.description) description,coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,coalesce(a.display_order,ol.source_row_no) display_order,coalesce(a.active,true) active,coalesce(a.manual_assignment_locked,false) manual_assignment_locked,a.adjustment_id,a.correction_origin
 from public.pdc_authenticated_email_operation_lines ol left join public.vehicle_workshop_line_adjustments a on a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text and coalesce(a.correction_origin,'')<>'ai_auditor_rolled_back'
), added_rows as(
 select a.adjustment_id::text,null::uuid,a.vehicle_id,a.job_card_number,a.operation_code,case a.stage_code when 'FITTING' then 'fitting' when 'TINT' then 'tint' when 'HOIST' then 'hoist' when 'ELEC' then 'electrical' when 'FAB' then 'fabrication' when 'TYRE' then 'tyre' when 'PIT' then 'pitInspection' end,a.description,a.estimated_hours,a.display_order,a.active,a.manual_assignment_locked,a.adjustment_id,a.correction_origin from public.vehicle_workshop_line_adjustments a where a.correction_origin='ai_auditor' and a.source_operation_line_id is null and a.active
) select * from source_rows union all select * from added_rows;

create table public.pdc_auditor_workshop_revisions(revision_id bigint generated always as identity primary key,dealer_code text not null,environment text not null,event_type text not null,run_id uuid not null,rollback_receipt_id uuid,created_at timestamptz not null default clock_timestamp(),constraint revision_shape check((event_type='telegram_plan_applied_226' and rollback_receipt_id is null) or (event_type='telegram_run_rolled_back_226' and rollback_receipt_id is not null)),unique(run_id,event_type));
alter table public.pdc_auditor_workshop_revisions enable row level security;
create publication supabase_realtime;
alter publication supabase_realtime add table public.vehicle_workshop_line_adjustments,public.pdc_auditor_workshop_revisions;

create table public.fixture_vehicle_dealers(vehicle_id uuid primary key,dealer_code text not null);
create table public.pdc_auditor_user_dealer_scopes(auth_user_id uuid,email text,normalized_email text,dealer_code text,environment text,active boolean);
create function public.pdc_auditor_reject_history_mutation() returns trigger language plpgsql as $$begin raise exception 'immutable history' using errcode='55000';end$$;
create function public.pdc_auditor_normalize_identity_225(text) returns text language sql immutable as $$select lower(regexp_replace(btrim(coalesce($1,'')),'[^a-z0-9]+',' ','g'))$$;
create function public.workshop_stage_code_for_work_key(text) returns text language sql immutable as $$select case $1 when 'fitting' then 'FITTING' when 'tint' then 'TINT' when 'hoist' then 'HOIST' when 'electrical' then 'ELEC' when 'fabrication' then 'FAB' when 'tyre' then 'TYRE' when 'pitInspection' then 'PIT' end$$;
create function public.pdc_auditor_vehicle_dealer(uuid) returns text language sql stable as $$select dealer_code from public.fixture_vehicle_dealers where vehicle_id=$1$$;
create function public.pdc_auditor_operational_revision(text) returns text language sql stable set search_path=pg_catalog,public,extensions as $$select encode(extensions.digest(convert_to(coalesce((select string_agg(id::text||coalesce(stock_number,''),'|' order by id) from public.vehicles),'')||coalesce((select string_agg(adjustment_id::text||version::text||active::text,'|' order by adjustment_id) from public.vehicle_workshop_line_adjustments),''),'UTF8'),'sha256'),'hex')$$;
create function public.pdc_auditor_telegram_actor_scope_225(bigint) returns jsonb language sql stable as $$select jsonb_build_object('service_identity_id','10000000-0000-4000-8000-000000000001','service_user_id','10000000-0000-4000-8000-000000000002','service_email','auditor@example.test','admin_user_id','10000000-0000-4000-8000-000000000003','admin_email','craig@example.test','dealer_code','14450') where $1=7828138290$$;

insert into auth.users values('10000000-0000-4000-8000-000000000002','auditor@example.test','{}'),('10000000-0000-4000-8000-000000000003','craig@example.test','{}');
insert into public.pdc_user_roles(email,role,active,auth_user_id,account_status) values('craig@example.test','administrator',true,'10000000-0000-4000-8000-000000000003','approved');
insert into public.pdc_auditor_user_dealer_scopes values('10000000-0000-4000-8000-000000000003','craig@example.test','craig@example.test','14450','staging',true);
grant usage on schema auth to authenticated;
grant select on auth.users,public.pdc_user_roles,public.pdc_auditor_user_dealer_scopes to authenticated;
insert into public.vehicles values('20000000-0000-4000-8000-000000000001','perm-1','STK1','JC1','active','YH',null,null);
insert into public.fixture_vehicle_dealers values('20000000-0000-4000-8000-000000000001','14450');
insert into public.pdc_authenticated_email_operation_lines(operation_line_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,estimated_hours,job_card_number,source_row_no) values('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','hash-1','uid-1','OP1','fitting','Fit item','fingerprint-1',2.00,'JC1',1);
