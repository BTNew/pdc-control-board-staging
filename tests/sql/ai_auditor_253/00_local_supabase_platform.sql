-- Disposable local PostgreSQL substitutes only for Supabase platform-owned primitives.
-- Application schema, functions, triggers, RLS and grants come from real migrations.
\set ON_ERROR_STOP on

do $$begin
 if current_database() !~ '^pdc_auditor_253_' then raise exception 'refusing non-test database'; end if;
 if not exists(select 1 from pg_roles where rolname='postgres') then create role postgres nologin superuser; end if;
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end$$;
create schema if not exists auth;
create schema if not exists extensions;
create schema if not exists supabase_migrations;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;
set search_path = public, extensions;
alter role postgres set search_path = public, extensions;
alter role anon set search_path = public, extensions;
alter role authenticated set search_path = public, extensions;
alter role service_role set search_path = public, extensions;
do $$begin
 execute format('alter role %I set search_path = public, extensions', current_user);
end$$;
create table if not exists auth.users(
 id uuid primary key,
 instance_id uuid,
 aud varchar(255), role varchar(255), email varchar(255), encrypted_password varchar(255),
 email_confirmed_at timestamptz, invited_at timestamptz, confirmation_token varchar(255),
 confirmation_sent_at timestamptz, recovery_token varchar(255), recovery_sent_at timestamptz,
 email_change_token_new varchar(255), email_change varchar(255), email_change_sent_at timestamptz,
 last_sign_in_at timestamptz, raw_app_meta_data jsonb default '{}', raw_user_meta_data jsonb default '{}',
 is_super_admin boolean, created_at timestamptz default now(), updated_at timestamptz default now(),
 phone text, phone_confirmed_at timestamptz, phone_change text, phone_change_token varchar(255),
 phone_change_sent_at timestamptz, confirmed_at timestamptz, email_change_token_current varchar(255),
 email_change_confirm_status smallint default 0, banned_until timestamptz, reauthentication_token varchar(255),
 reauthentication_sent_at timestamptz, is_sso_user boolean default false, deleted_at timestamptz,
 is_anonymous boolean default false
);
create or replace function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create or replace function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)$$;
create table if not exists supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
create schema if not exists storage;
create table if not exists storage.buckets(id text primary key,name text not null,public boolean not null default false,file_size_limit bigint,allowed_mime_types text[]);
create table if not exists storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,owner uuid,metadata jsonb,created_at timestamptz default now(),updated_at timestamptz default now());
alter table storage.objects enable row level security;
do $$begin if not exists(select 1 from pg_publication where pubname='supabase_realtime') then create publication supabase_realtime; end if;end$$;
create table if not exists public.pdc_staging_environment_sentinel(singleton boolean primary key,project_ref text not null);
insert into public.pdc_staging_environment_sentinel values(true,'cdsmnqxtyyoeoznmbidd') on conflict(singleton) do update set project_ref=excluded.project_ref;
