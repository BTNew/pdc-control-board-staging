begin;

-- Backup system metadata (staging-only for now; migration is written so it
-- can be applied to production later once the staging backup/restore cycle
-- has been proven, per the standing "staging first" rule).
--
-- This table is intentionally NOT included in its own backup payload (see
-- scripts/pdc_backup.py TABLES list) -- it is operational metadata about
-- the backup system itself, not vehicle/workshop data, and restoring it
-- would create a confusing merge of two backup histories. It is however
-- covered by the same RLS/audit conventions as the rest of the schema.

create type public.backup_run_status as enum ('running', 'success', 'failed');
create type public.backup_run_kind as enum ('scheduled', 'manual');

create table public.backup_runs (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('staging', 'production')),
  kind public.backup_run_kind not null default 'scheduled',
  status public.backup_run_status not null default 'running',
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  backup_version text not null default '1',
  migration_version text,
  table_row_counts jsonb not null default '{}'::jsonb,
  file_path text,
  file_size_bytes bigint,
  file_sha256 text,
  encrypted boolean not null default true,
  error_message text,
  triggered_by text not null default 'cron',
  created_at timestamptz not null default now()
);

create index backup_runs_environment_started_idx on public.backup_runs (environment, started_at desc);

alter table public.backup_runs enable row level security;

-- Administrators can view backup history (status widget). No one can
-- write to this table through PostgREST -- only the backup script writes
-- to it, and it authenticates with the service_role key (server-side
-- only, never shipped to the browser), which bypasses RLS entirely.
create policy backup_runs_select_admin on public.backup_runs
  for select
  using (is_pdc_role('administrator'::pdc_role));

-- Restore test tracking, separate from backup_runs because a single
-- backup can be restore-tested multiple times (e.g. re-verified after a
-- restore script change) and a restore test always targets an isolated
-- schema, never the live database.
create table public.restore_test_runs (
  id uuid primary key default gen_random_uuid(),
  backup_run_id uuid references public.backup_runs(id) on delete set null,
  environment text not null check (environment in ('staging', 'production')),
  target_schema text not null,
  status public.backup_run_status not null default 'running',
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  verification_report jsonb,
  row_count_matches boolean,
  error_message text,
  created_at timestamptz not null default now()
);

alter table public.restore_test_runs enable row level security;

create policy restore_test_runs_select_admin on public.restore_test_runs
  for select
  using (is_pdc_role('administrator'::pdc_role));

commit;
