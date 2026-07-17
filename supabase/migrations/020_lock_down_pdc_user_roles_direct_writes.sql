-- Migration 020: lock down pdc_user_roles direct writes (independent-review
-- remediation, finding #4 / critical blocker #4).
--
-- The independent review of the 2026-07-17 production-readiness package
-- found that an authenticated administrator session could bypass every
-- protected approval/disable/role-change RPC by writing directly to
-- public.pdc_user_roles via the REST API, because:
--
--   1. pdc_user_roles_admin_insert / pdc_user_roles_admin_update (added
--      in migration 002, before the account-approval RPCs existed) let
--      any row with is_pdc_role('administrator') true insert or update
--      ANY row in the table directly, with no audit trail, no
--      last-active-administrator protection, and no transition
--      validation.
--   2. The table also still carried the default broad grants for
--      'anon' and 'authenticated' (INSERT/UPDATE/DELETE/TRUNCATE),
--      which RLS was the *only* thing standing between those roles and
--      real mutation.
--
-- This migration removes both problems: it drops the two admin direct
-- write policies, revokes every write-capable privilege from anon and
-- authenticated on this table, and leaves SELECT as the only
-- permitted direct operation (already correctly scoped to "your own
-- row, or every row if you are an administrator" by the pre-existing
-- pdc_user_roles_select_self_or_admin policy). Every mutation must now
-- go through the protected SECURITY DEFINER RPCs added in migration
-- 018 (admin_approve_user, admin_reject_registration,
-- admin_change_role, admin_disable_user, admin_restore_user), which
-- remain callable by 'authenticated' and internally re-verify the
-- caller is an active administrator before doing anything.
--
-- This migration also adds two safety nets the review specifically
-- asked for:
--   - a CHECK constraint enforcing that only a small number of valid
--     (account_status, role, active) combinations can ever exist, so a
--     future bug cannot silently produce an approved-but-inactive or
--     pending-but-active row even via a SECURITY DEFINER function;
--   - explicit REVOKE of the default PUBLIC EXECUTE grant from the
--     administrator-only RPCs, so only 'authenticated' can even
--     attempt to call them (the functions still self-check the role
--     internally either way -- this is defense in depth, not the only
--     line of defense).
--
-- Idempotent: safe to re-run.

begin;

-- ---------------------------------------------------------------------
-- 1. Drop the direct administrator write policies.
-- ---------------------------------------------------------------------
drop policy if exists pdc_user_roles_admin_insert on public.pdc_user_roles;
drop policy if exists pdc_user_roles_admin_update on public.pdc_user_roles;

-- ---------------------------------------------------------------------
-- 2. Revoke every write-capable table privilege from anon/authenticated.
--    SELECT is retained (governed entirely by the pre-existing
--    pdc_user_roles_select_self_or_admin RLS policy, unchanged here).
-- ---------------------------------------------------------------------
revoke insert, update, delete, truncate on public.pdc_user_roles from anon;
revoke insert, update, delete, truncate on public.pdc_user_roles from authenticated;

-- The table's own row-level trigger functions and the SECURITY DEFINER
-- RPCs run as their definer (the migration-applying role / postgres),
-- not as anon/authenticated, so this revoke does not affect them.

-- ---------------------------------------------------------------------
-- 3. Explicit REVOKE of default PUBLIC EXECUTE on the administrator
--    RPCs, then re-grant only to authenticated (defense in depth --
--    each function already calls require_pdc_role('administrator')
--    internally as its first statement).
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_proc where proname = 'admin_approve_user') then
    revoke all on function public.admin_approve_user(text, pdc_role, text) from public;
    grant execute on function public.admin_approve_user(text, pdc_role, text) to authenticated;
  end if;
  if exists (select 1 from pg_proc where proname = 'admin_reject_registration') then
    revoke all on function public.admin_reject_registration(text, text) from public;
    grant execute on function public.admin_reject_registration(text, text) to authenticated;
  end if;
  if exists (select 1 from pg_proc where proname = 'admin_change_role') then
    revoke all on function public.admin_change_role(text, pdc_role, text) from public;
    grant execute on function public.admin_change_role(text, pdc_role, text) to authenticated;
  end if;
  if exists (select 1 from pg_proc where proname = 'admin_disable_user') then
    revoke all on function public.admin_disable_user(text, text) from public;
    grant execute on function public.admin_disable_user(text, text) to authenticated;
  end if;
  if exists (select 1 from pg_proc where proname = 'admin_restore_user') then
    revoke all on function public.admin_restore_user(text, text) from public;
    grant execute on function public.admin_restore_user(text, text) to authenticated;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. CHECK constraint enforcing valid (account_status, role, active)
--    combinations. Matches the rules the RPCs already enforce in code;
--    this is a second, database-level guarantee that cannot be bypassed
--    by any future direct write path or RPC bug.
--
--    pending  : role is null,      active = false
--    rejected : role is null,      active = false
--    approved : role is not null,  active = true
--    disabled : role is not null (preserved for restore), active = false
-- ---------------------------------------------------------------------
alter table public.pdc_user_roles drop constraint if exists pdc_user_roles_status_role_active_consistency;
alter table public.pdc_user_roles add constraint pdc_user_roles_status_role_active_consistency
  check (
    (account_status = 'pending'  and role is null     and active = false) or
    (account_status = 'rejected' and role is null      and active = false) or
    (account_status = 'approved' and role is not null and active = true) or
    (account_status = 'disabled' and role is not null and active = false)
  );

commit;
