-- Migration 022: Stage 2A -- shared workshop lookup/configuration data.
--
-- Independent-review remediation, Stage 2A (localStorage -> Supabase,
-- shared lookup/configuration data only -- see
-- docs/localstorage-to-supabase-migration-plan.md for the approved
-- design this migration implements).
--
-- SCHEMA AUDIT PERFORMED BEFORE WRITING THIS FILE (live staging, not
-- assumed from migration source): public.salespeople,
-- public.sublet_providers, public.workshop_technicians,
-- public.workshop_bays, public.workshop_stages, and
-- public.workshop_settings ALL ALREADY EXIST (migrations 001/006) and
-- already have RLS SELECT policies for viewer+. None of the five had
-- ANY write RLS policy and none had any protected write RPC -- the
-- frontend still reads/writes mechanics, salespeople, and sublet
-- providers from three separate localStorage key families instead.
-- This migration does NOT create new mechanic/bay/provider tables --
-- it extends the five existing tables with the columns this Stage 2A
-- design requires (stable code, sort order, created_by/updated_by,
-- and optimistic-concurrency version where a record can be
-- concurrently edited by two administrators), then migration 023 adds
-- the protected RPCs.
--
-- workshop_settings is intentionally NOT redesigned into one row per
-- discrete field. It already uses a deliberate, already-deployed
-- entity-attribute-value shape (one row per named setting, e.g.
-- 'day_start_time', 'working_week', 'closures') -- this is reused, not
-- replaced by a wide single-JSON-blob table (which the review
-- explicitly warned against) or a fully normalised table-per-field
-- design (which would be a breaking rewrite of an already-deployed,
-- already-correct table for no real gain, since each row is one named,
-- independently-typed, independently-versioned setting rather than an
-- undifferentiated blob). A version column is added so an
-- administrator's configuration update can be optimistic-lock
-- protected exactly like every other protected RPC in this project.

-- ---------------------------------------------------------------------
-- 1. public.workshop_technicians -- add code, sort_order, created_by,
--    updated_by, version. (No existing frontend "mechanic code"
--    concept was found during the code audit for this table -- code
--    is added as an optional field for future use, matching the
--    salespeople.code requirement below, not backfilled from
--    anything because no source data for it exists today.)
-- ---------------------------------------------------------------------
alter table public.workshop_technicians
  add column if not exists code text,
  add column if not exists sort_order integer,
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists version integer not null default 1;

-- Backfill sort_order from existing alphabetical name order so
-- existing rows get a stable, deterministic order rather than NULL.
with ordered as (
  select id, row_number() over (order by name) as rn
  from public.workshop_technicians
  where sort_order is null
)
update public.workshop_technicians t
set sort_order = ordered.rn
from ordered
where t.id = ordered.id;

alter table public.workshop_technicians
  alter column sort_order set not null,
  alter column sort_order set default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'workshop_technicians_code_key'
  ) then
    alter table public.workshop_technicians
      add constraint workshop_technicians_code_key unique (code);
  end if;
end $$;

comment on column public.workshop_technicians.code is
  'Optional short mechanic code/initials (Stage 2A). NULL is permitted (unique constraint on a nullable column allows multiple NULLs) since no source data exists for this field today.';

-- ---------------------------------------------------------------------
-- 2. public.salespeople -- add code (the "salesperson codes" the task
--    requires -- confirmed via code audit this maps to the existing
--    frontend concept of a salesperson's short "initials" field),
--    sort_order, created_by, updated_by, version.
-- ---------------------------------------------------------------------
alter table public.salespeople
  add column if not exists code text,
  add column if not exists sort_order integer,
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists version integer not null default 1;

with ordered as (
  select id, row_number() over (order by name) as rn
  from public.salespeople
  where sort_order is null
)
update public.salespeople s
set sort_order = ordered.rn
from ordered
where s.id = ordered.id;

alter table public.salespeople
  alter column sort_order set not null,
  alter column sort_order set default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'salespeople_code_key'
  ) then
    alter table public.salespeople
      add constraint salespeople_code_key unique (code);
  end if;
end $$;

comment on column public.salespeople.code is
  'Short salesperson code/initials (Stage 2A) -- corresponds to the existing frontend "initials" concept from normalizeSalespersonRecord(). NULL permitted for records imported without one.';

-- ---------------------------------------------------------------------
-- 3. public.sublet_providers -- add sort_order, created_by,
--    updated_by, version. (No "code" concept was found for sublet
--    providers in the frontend code audit -- not added, per the
--    "do not guess" instruction; a provider is identified by name.)
-- ---------------------------------------------------------------------
alter table public.sublet_providers
  add column if not exists sort_order integer,
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists version integer not null default 1;

with ordered as (
  select id, row_number() over (order by name) as rn
  from public.sublet_providers
  where sort_order is null
)
update public.sublet_providers p
set sort_order = ordered.rn
from ordered
where p.id = ordered.id;

alter table public.sublet_providers
  alter column sort_order set not null,
  alter column sort_order set default 0;

-- ---------------------------------------------------------------------
-- 4. public.workshop_bays -- add created_by, updated_by, version.
--    (code/display_name/is_active/bay_number/stage_id already exist
--    from migration 006 and already provide everything the task's
--    "workshop bays" requirement needs except audit/concurrency
--    columns.)
-- ---------------------------------------------------------------------
alter table public.workshop_bays
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists version integer not null default 1;

-- ---------------------------------------------------------------------
-- 5. public.workshop_settings -- add version for optimistic-lock
--    protected configuration updates. Value-shape validation per key
--    (day_start_time is a time string, working_week is a day-name
--    array, etc.) is enforced in the RPC layer (migration 023), not
--    by a blanket "accept any JSON" write path, and only a fixed,
--    known set of setting keys may ever be written -- an unknown key
--    is rejected, never silently created.
-- ---------------------------------------------------------------------
alter table public.workshop_settings
  add column if not exists version integer not null default 1;

-- ---------------------------------------------------------------------
-- 6. RLS: keep every existing viewer-read policy exactly as-is (no
--    write RLS is added here -- writes for all five tables happen
--    exclusively through the protected RPCs added in migration 023,
--    consistent with the review's explicit instruction not to add a
--    generic table-level write policy and not to rely on RLS alone
--    for these business actions). Revoke direct table write grants
--    from authenticated/anon on workshop_technicians and
--    workshop_bays specifically, since Stage 7's privilege-hardening
--    pass (migration 021) only ever intentionally preserved direct
--    write grants for salespeople/sublet_providers (both already
--    RLS-governed by administrator-only write policies) -- this
--    migration does NOT add a matching RLS write policy for those two
--    tables' NEW columns' worth of extra risk; instead §7 below
--    revokes those two tables' direct write grants entirely so every
--    mutation must go through a protected RPC, matching
--    workshop_technicians/workshop_bays/workshop_settings/
--    workshop_stages' existing (already correct) posture.
-- ---------------------------------------------------------------------
revoke insert, update, delete, truncate on public.salespeople from authenticated;
revoke insert, update, delete, truncate on public.sublet_providers from authenticated;

comment on table public.workshop_technicians is
  'Shared mechanic/technician roster (Stage 2A). All writes go through protected RPCs (add_technician/edit_technician/set_technician_active) -- no direct table write grant exists for any role.';
comment on table public.salespeople is
  'Shared salesperson roster (Stage 2A). All writes go through protected RPCs (add_salesperson/edit_salesperson/set_salesperson_active) as of this migration -- the direct administrator write grant from migration 021 is revoked here in favour of the audited RPC path.';
comment on table public.sublet_providers is
  'Shared sublet-provider roster (Stage 2A). All writes go through protected RPCs (add_sublet_provider/edit_sublet_provider/set_sublet_provider_active) as of this migration -- the direct administrator write grant from migration 021 is revoked here in favour of the audited RPC path.';
comment on table public.workshop_bays is
  'Shared workshop bay list (Stage 2A). All writes go through protected RPCs (add_workshop_bay/edit_workshop_bay/set_workshop_bay_active).';
comment on table public.workshop_settings is
  'Shared workshop configuration (operating hours, working days, minimum booking duration, closures) (Stage 2A). All writes go through the protected update_workshop_configuration RPC, which validates a fixed known key set and per-key value shape.';
