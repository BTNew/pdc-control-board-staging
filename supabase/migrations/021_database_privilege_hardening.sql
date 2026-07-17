-- Migration 021: database privilege hardening (independent-review
-- remediation, high-priority findings #7 and #10).
--
-- The independent review found that most public-schema tables retained
-- Postgres's default broad grants to 'anon' and 'authenticated'
-- (INSERT/UPDATE/DELETE/TRUNCATE), with RLS as the only thing
-- preventing real mutation. Two specific problems:
--
--   1. TRUNCATE is not governed by row-level security at all -- a role
--      with TRUNCATE granted can always truncate the whole table
--      regardless of any RLS policy. Every table in this project
--      still had TRUNCATE granted to anon and authenticated.
--   2. Most tables have NO legitimate direct-write RLS policy at all
--      (every real mutation goes through a SECURITY DEFINER RPC that
--      runs as its definer, not as anon/authenticated) -- so their
--      INSERT/UPDATE/DELETE grants to anon/authenticated were pure
--      excess attack surface, not something any correct code path
--      actually uses.
--
-- This migration:
--   - Revokes TRUNCATE from anon and authenticated on every public
--     table, unconditionally.
--   - Revokes INSERT/UPDATE/DELETE from anon and authenticated on
--     every public table that has NO RLS policy naming
--     'authenticated'/'anon' for that command (i.e. every table whose
--     only real write path is a SECURITY DEFINER RPC).
--   - Leaves salespeople and sublet_providers exactly as they are:
--     both have RLS enabled AND a genuine
--     is_pdc_role('administrator') write policy scoped to
--     'authenticated', so an administrator's direct write to those two
--     tables is an intentional, RLS-governed pattern, not excess
--     privilege. (pdc_user_roles was already locked down the same way
--     in migration 020, for the same reason -- it does NOT get an
--     exception here because migration 020 intentionally removed its
--     direct-write policies.)
--
-- This is generated dynamically (a DO block over pg_tables /
-- pg_policies) rather than a long hand-written list, so it stays
-- correct as new tables are added by future migrations, and so it can
-- be safely re-run (idempotent -- REVOKE on a privilege that is not
-- currently granted is a no-op, not an error).

begin;

do $$
declare
  tbl record;
  has_write_policy_authenticated boolean;
  has_write_policy_anon boolean;
begin
  for tbl in
    select c.relname as table_name
    from pg_class c
    join pg_namespace n on c.relnamespace = n.oid
    where n.nspname = 'public' and c.relkind = 'r'
  loop
    -- TRUNCATE is never governed by RLS -- always revoke, no exceptions.
    execute format('revoke truncate on public.%I from anon', tbl.table_name);
    execute format('revoke truncate on public.%I from authenticated', tbl.table_name);

    -- Check each grantee independently: does this table have a real RLS
    -- policy that scopes INSERT/UPDATE/DELETE (or ALL) specifically to
    -- 'authenticated', and separately, specifically to 'anon'? A write
    -- policy scoped only to 'authenticated' (e.g. salespeople,
    -- sublet_providers) justifies keeping authenticated's write grant,
    -- but does NOT justify keeping anon's -- anon should never have a
    -- direct write grant on any table in this project.
    select exists (
      select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = tbl.table_name
        and p.cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
        and p.roles @> array['authenticated']::name[]
    ) into has_write_policy_authenticated;

    select exists (
      select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = tbl.table_name
        and p.cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
        and (p.roles @> array['anon']::name[] or p.roles @> array['public']::name[])
    ) into has_write_policy_anon;

    if not has_write_policy_authenticated then
      execute format('revoke insert, update, delete on public.%I from authenticated', tbl.table_name);
    end if;
    if not has_write_policy_anon then
      execute format('revoke insert, update, delete on public.%I from anon', tbl.table_name);
    end if;
  end loop;
end $$;

commit;
