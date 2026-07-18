-- Migration 024: Stage 2A -- Realtime delivery fixes for shared
-- workshop lookup/configuration data.
--
-- Independent-review remediation. During Stage 2A two-browser Realtime
-- verification, an independent Node-based diagnostic client
-- (scripts/stage2a_realtime_diagnostic.js) that authenticates as a real
-- staging user and subscribes directly to postgres_changes -- completely
-- outside the application code -- proved conclusively that:
--
--   1. workshop_technicians, workshop_bays and workshop_settings were
--      already in the supabase_realtime publication and correctly
--      delivered INSERT/UPDATE events (confirmed via a live diagnostic
--      run: INSERT, UPDATE, and an active=false deactivate UPDATE were
--      all received cleanly).
--   2. salespeople and sublet_providers were NOT in the
--      supabase_realtime publication at all, so realtime UPDATE events
--      for those two tables were never delivered to any subscriber,
--      independent of any frontend code. This was the root cause of
--      "salesperson/sublet-provider changes never appear live" during
--      Stage 2A acceptance testing.
--
-- This migration codifies the direct staging fixes already applied and
-- verified during that investigation, so staging schema state matches
-- Git migration history exactly (no schema drift left uncommitted):
--
--   - REPLICA IDENTITY FULL on all five Stage 2A reference tables (was
--     already applied directly to staging and re-verified as NOT the
--     root cause of the "stuck one edit behind" symptom -- that was
--     actually workshop-reference-data-service.js's own request-race
--     bug, fixed separately in application code -- but REPLICA IDENTITY
--     FULL is still worth keeping: it guarantees `old` record data is
--     present on UPDATE/DELETE payloads, which the frontend's realtime
--     onChange handler does not currently rely on, but is good practice
--     for any future consumer that inspects payload.old).
--   - Publication membership for salespeople and sublet_providers.
--
-- Idempotent: ALTER TABLE ... REPLICA IDENTITY FULL and
-- ALTER PUBLICATION ... ADD TABLE are both safe to re-run (the latter
-- via a guarded DO block, since Postgres raises a duplicate-object error
-- rather than silently no-op'ing on ADD TABLE for an already-member
-- table).

alter table public.workshop_technicians replica identity full;
alter table public.sublet_providers replica identity full;
alter table public.salespeople replica identity full;
alter table public.workshop_bays replica identity full;
alter table public.workshop_settings replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'salespeople'
  ) then
    alter publication supabase_realtime add table public.salespeople;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'sublet_providers'
  ) then
    alter publication supabase_realtime add table public.sublet_providers;
  end if;
end;
$$;
