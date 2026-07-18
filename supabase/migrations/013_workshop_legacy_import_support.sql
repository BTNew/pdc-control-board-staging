-- 013_workshop_legacy_import_support.sql
--
-- Adds the minimum schema support required for a safe, repeatable legacy
-- browser-local workshop data import (see scripts/workshop_legacy_import.py
-- and scripts/workshop_planner_legacy_validate.js):
--
--   - a nullable, indexed, unique-when-present legacy plan-id pointer on
--     workshop_bookings so re-running the same extract updates existing
--     imported rows instead of creating duplicates
--   - a metadata jsonb column to carry the original raw legacy record
--     (audit/rollback requirement) without inventing new tables for it
--   - 'legacy_migration' is already a valid workshop_bookings.source value
--     (workshop_bookings.source is free-text in migration 006, not an
--     enum), so no type change is required there
--
-- This migration does not touch RLS or grants beyond what 008/011 already
-- enforce: the browser publishable key still has no direct write access to
-- workshop_bookings. The import script itself connects with the staging
-- database's superuser/service credentials over a direct Postgres
-- connection (not through the browser client), exactly like the earlier
-- staging fixture-seeding scripts in this project.

begin;

alter table public.workshop_bookings
  add column if not exists metadata_legacy_plan_id text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create unique index if not exists workshop_bookings_legacy_plan_id_key
  on public.workshop_bookings (metadata_legacy_plan_id)
  where metadata_legacy_plan_id is not null;

comment on column public.workshop_bookings.metadata_legacy_plan_id is
  'Legacy browser-local workshop plan id this booking was imported from, if any. Used to make re-running the same legacy import idempotent (update instead of duplicate insert). Null for bookings created normally through the app.';

comment on column public.workshop_bookings.metadata is
  'Free-form structured metadata, primarily used by the legacy import process to retain the original raw legacy record for audit and rollback. Never used for authoritative business state -- that always lives in dedicated typed columns.';

commit;
