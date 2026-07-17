begin;

-- ============================================================================
-- Migration 018: Individual account registration + administrator approval
-- workflow (staging-first; safe to apply to production later once
-- staging-tested per the standing "staging first" convention).
--
-- Model decision: approval/account lifecycle is kept SEPARATE from the
-- existing operational role (pdc_role: viewer/operator/importer/
-- administrator). A user's account can be pending/approved/disabled/
-- rejected regardless of what operational role they will eventually hold,
-- and a rejected/disabled/pending account has NO operational role at all
-- (role is nullable and NULL for anyone not yet approved). This keeps
-- "can this person use the app at all" cleanly separate from "what can
-- an approved person do", per the task's explicit instruction not to
-- represent pending/disabled as operational roles.
-- ============================================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'pdc_account_status') then
    create type public.pdc_account_status as enum ('pending', 'approved', 'disabled', 'rejected');
  end if;
end $$;

-- pdc_user_roles already exists (migration 001) with columns:
--   id, email, display_name, role (pdc_role, not null, default 'viewer'),
--   active (boolean), approved_by, approved_at, notes, created_at, updated_at
--
-- Extend it rather than create a parallel table, since it is already the
-- single source of truth the rest of the schema's RLS policies key off
-- (current_pdc_user_role() / is_pdc_role()). New self-registered accounts
-- land here with status='pending', role=NULL, active=false.
alter table public.pdc_user_roles
  add column if not exists auth_user_id uuid references auth.users(id) on delete set null,
  add column if not exists account_status public.pdc_account_status not null default 'approved',
  add column if not exists full_name text,
  add column if not exists registered_at timestamptz,
  add column if not exists rejected_by uuid,
  add column if not exists rejected_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists disabled_by uuid,
  add column if not exists disabled_at timestamptz,
  add column if not exists disabled_reason text,
  add column if not exists restored_by uuid,
  add column if not exists restored_at timestamptz,
  add column if not exists last_sign_in_at timestamptz;

-- Ensure these FKs point at pdc_user_roles(id) (the acting administrator's
-- own row), not auth.users(id) -- idempotent: drop-then-add so a
-- previously-applied (and since corrected) version of this migration
-- cannot leave a stale FK target behind.
alter table public.pdc_user_roles drop constraint if exists pdc_user_roles_rejected_by_fkey;
alter table public.pdc_user_roles add constraint pdc_user_roles_rejected_by_fkey
  foreign key (rejected_by) references public.pdc_user_roles(id) on delete set null;
alter table public.pdc_user_roles drop constraint if exists pdc_user_roles_disabled_by_fkey;
alter table public.pdc_user_roles add constraint pdc_user_roles_disabled_by_fkey
  foreign key (disabled_by) references public.pdc_user_roles(id) on delete set null;
alter table public.pdc_user_roles drop constraint if exists pdc_user_roles_restored_by_fkey;
alter table public.pdc_user_roles add constraint pdc_user_roles_restored_by_fkey
  foreign key (restored_by) references public.pdc_user_roles(id) on delete set null;

-- role must be nullable now: a pending/rejected/disabled-before-ever-
-- approved account has no operational role at all.
alter table public.pdc_user_roles alter column role drop not null;
alter table public.pdc_user_roles alter column role drop default;

-- Backfill: every pre-existing row (all rows created before this
-- migration, i.e. the existing staging test accounts) is already an
-- approved, active staff account -- preserve that exactly.
update public.pdc_user_roles
   set account_status = 'approved'
 where account_status is distinct from 'approved'
   and active = true;

comment on column public.pdc_user_roles.account_status is
  'Account lifecycle, independent of operational role. pending: just self-registered, awaiting admin decision, role is NULL. approved: role is set, active=true. disabled: previously approved, access revoked, role preserved for restore. rejected: registration declined, role stays NULL.';
comment on column public.pdc_user_roles.role is
  'Operational role (viewer/operator/importer/administrator). NULL until an administrator approves the account and assigns a role. A user can never set this themselves.';

-- ----------------------------------------------------------------------
-- Self-registration trigger: fires when a new auth.users row is created
-- via Supabase Auth signup. Creates the matching pdc_user_roles row as
-- pending/no-role/inactive. This is the ONLY path that creates a pending
-- account row -- nothing in the browser can insert into pdc_user_roles
-- directly (RLS below still only allows administrator insert/update, but
-- this SECURITY DEFINER trigger runs as the table owner regardless of
-- RLS, which is the standard, safe Postgres/Supabase pattern for this).
-- ----------------------------------------------------------------------
create or replace function public.handle_new_pdc_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.pdc_user_roles (
    email, display_name, full_name, role, active, account_status,
    auth_user_id, registered_at
  ) values (
    lower(new.email),
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email),
    new.raw_user_meta_data ->> 'full_name',
    null,
    false,
    'pending',
    new.id,
    now()
  )
  on conflict (email) do update set
    auth_user_id = excluded.auth_user_id,
    registered_at = coalesce(public.pdc_user_roles.registered_at, excluded.registered_at);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_pdc on auth.users;
create trigger on_auth_user_created_pdc
  after insert on auth.users
  for each row execute function public.handle_new_pdc_auth_user();

-- pdc_user_roles.email must be unique for the ON CONFLICT above and to
-- guarantee current_pdc_user_role()/is_pdc_role() always resolve a
-- single row per signed-in email.
create unique index if not exists pdc_user_roles_email_key on public.pdc_user_roles (email);

-- ----------------------------------------------------------------------
-- current_pdc_account_status(): the single source of truth the frontend
-- and RLS both use to decide "can this signed-in user see operational
-- data at all". Deliberately separate from current_pdc_user_role() so a
-- pending/disabled/rejected account with role=NULL still resolves to a
-- concrete, checkable status.
-- ----------------------------------------------------------------------
create or replace function public.current_pdc_account_status()
returns public.pdc_account_status
language sql
stable
security definer
set search_path = public
as $$
  select account_status
  from public.pdc_user_roles
  where email = public.current_actor_email()
  limit 1;
$$;

-- is_pdc_role()/current_pdc_user_role() already filter on active=true,
-- so a pending/disabled/rejected account (active=false) already
-- correctly resolves to no role and therefore no operational access
-- everywhere those functions are used in existing RLS policies -- this
-- migration does not need to touch those functions or any existing
-- operational RLS policy for that guarantee to hold. Verified by direct
-- API test in _staging_test_tools/test_account_approval_staging.py.

-- ----------------------------------------------------------------------
-- RLS on pdc_user_roles: a signed-in user must be able to read their OWN
-- row (to render "awaiting approval" / "disabled" / "rejected" screens)
-- but nothing about any other user; administrators can read/manage all
-- rows. The pre-existing policies already do exactly this
-- (pdc_user_roles_select_self_or_admin / _admin_insert / _admin_update),
-- so no policy change is required here -- re-asserted for clarity and to
-- guard against a future migration accidentally loosening it.
-- ----------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_policy where polname = 'pdc_user_roles_select_self_or_admin'
      and polrelid = 'public.pdc_user_roles'::regclass
  ) then
    raise exception 'Expected pre-existing RLS policy pdc_user_roles_select_self_or_admin is missing';
  end if;
end $$;

-- ----------------------------------------------------------------------
-- Protected administrator-only RPCs for the approval workflow. Every one
-- re-verifies the caller is an active administrator via require_pdc_role
-- (database-enforced, not just a frontend check), and every state change
-- is written to audit_events via the existing audit_pdc_event() helper.
-- ----------------------------------------------------------------------

create or replace function public.current_pdc_actor_role_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.pdc_user_roles where email = public.current_actor_email() limit 1;
$$;

create or replace function public.admin_approve_user(
  p_target_email text,
  p_role public.pdc_role,
  p_notes text default null
) returns public.pdc_user_roles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.pdc_user_roles;
  v_before jsonb;
begin
  perform public.require_pdc_role('administrator');

  select * into v_target from public.pdc_user_roles where email = lower(p_target_email);
  if v_target.id is null then
    raise exception 'No registration found for %', p_target_email using errcode = 'P0002';
  end if;
  if v_target.account_status = 'approved' and v_target.active then
    raise exception 'Account is already approved' using errcode = '22023';
  end if;

  v_before := to_jsonb(v_target);

  update public.pdc_user_roles set
    role = p_role,
    active = true,
    account_status = 'approved',
    approved_by = public.current_pdc_actor_role_id(),
    approved_at = now(),
    rejected_by = null,
    rejected_at = null,
    rejection_reason = null,
    disabled_by = null,
    disabled_at = null,
    disabled_reason = null,
    restored_by = case when v_target.account_status = 'disabled' then public.current_pdc_actor_role_id() else restored_by end,
    restored_at = case when v_target.account_status = 'disabled' then now() else restored_at end,
    notes = coalesce(p_notes, notes),
    updated_at = now()
  where email = lower(p_target_email)
  returning * into v_target;

  perform public.audit_pdc_event(
    'role_change'::audit_action, 'pdc_user_roles', v_target.id, null,
    v_before, to_jsonb(v_target),
    jsonb_build_object('operation', 'admin_approve_user', 'target_email', v_target.email, 'assigned_role', p_role, 'reason', p_notes)
  );

  return v_target;
end;
$$;

create or replace function public.admin_reject_registration(
  p_target_email text,
  p_reason text default null
) returns public.pdc_user_roles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.pdc_user_roles;
  v_before jsonb;
begin
  perform public.require_pdc_role('administrator');

  select * into v_target from public.pdc_user_roles where email = lower(p_target_email);
  if v_target.id is null then
    raise exception 'No registration found for %', p_target_email using errcode = 'P0002';
  end if;
  if v_target.account_status = 'approved' and v_target.active and v_target.role = 'administrator' then
    -- Rejecting only makes sense for a pending registration; an already-
    -- approved administrator must go through admin_disable_user (with
    -- its last-administrator protection) instead.
    raise exception 'Use admin_disable_user for an already-approved account' using errcode = '22023';
  end if;

  v_before := to_jsonb(v_target);

  update public.pdc_user_roles set
    role = null,
    active = false,
    account_status = 'rejected',
    rejected_by = public.current_pdc_actor_role_id(),
    rejected_at = now(),
    rejection_reason = p_reason,
    updated_at = now()
  where email = lower(p_target_email)
  returning * into v_target;

  perform public.audit_pdc_event(
    'role_change'::audit_action, 'pdc_user_roles', v_target.id, null,
    v_before, to_jsonb(v_target),
    jsonb_build_object('operation', 'admin_reject_registration', 'target_email', v_target.email, 'reason', p_reason)
  );

  return v_target;
end;
$$;

create or replace function public.admin_change_role(
  p_target_email text,
  p_role public.pdc_role,
  p_reason text default null
) returns public.pdc_user_roles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.pdc_user_roles;
  v_before jsonb;
  v_active_admin_count int;
begin
  perform public.require_pdc_role('administrator');

  select * into v_target from public.pdc_user_roles where email = lower(p_target_email);
  if v_target.id is null then
    raise exception 'No account found for %', p_target_email using errcode = 'P0002';
  end if;
  if v_target.account_status != 'approved' or not v_target.active then
    raise exception 'Account must be approved and active to change its role' using errcode = '22023';
  end if;

  if v_target.role = 'administrator' and p_role != 'administrator' then
    select count(*) into v_active_admin_count
    from public.pdc_user_roles
    where role = 'administrator' and active = true and account_status = 'approved';
    if v_active_admin_count <= 1 then
      raise exception 'Cannot remove the last active administrator role. Approve or restore a second administrator first.' using errcode = '42501';
    end if;
  end if;

  v_before := to_jsonb(v_target);

  update public.pdc_user_roles set
    role = p_role,
    notes = coalesce(p_reason, notes),
    updated_at = now()
  where email = lower(p_target_email)
  returning * into v_target;

  perform public.audit_pdc_event(
    'role_change'::audit_action, 'pdc_user_roles', v_target.id, null,
    v_before, to_jsonb(v_target),
    jsonb_build_object('operation', 'admin_change_role', 'target_email', v_target.email, 'new_role', p_role, 'reason', p_reason)
  );

  return v_target;
end;
$$;

create or replace function public.admin_disable_user(
  p_target_email text,
  p_reason text default null
) returns public.pdc_user_roles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.pdc_user_roles;
  v_before jsonb;
  v_active_admin_count int;
  v_self_email text;
begin
  perform public.require_pdc_role('administrator');

  v_self_email := public.current_actor_email();

  select * into v_target from public.pdc_user_roles where email = lower(p_target_email);
  if v_target.id is null then
    raise exception 'No account found for %', p_target_email using errcode = 'P0002';
  end if;

  if v_target.role = 'administrator' and v_target.active then
    select count(*) into v_active_admin_count
    from public.pdc_user_roles
    where role = 'administrator' and active = true and account_status = 'approved';
    if v_active_admin_count <= 1 then
      raise exception 'Cannot disable the last active administrator. Approve or restore a second administrator first.' using errcode = '42501';
    end if;
    if lower(v_target.email) = v_self_email then
      raise exception 'You cannot disable your own administrator account while it is the acting session. Ask a second administrator to disable it.' using errcode = '42501';
    end if;
  end if;

  v_before := to_jsonb(v_target);

  update public.pdc_user_roles set
    active = false,
    account_status = 'disabled',
    disabled_by = public.current_pdc_actor_role_id(),
    disabled_at = now(),
    disabled_reason = p_reason,
    updated_at = now()
  where email = lower(p_target_email)
  returning * into v_target;

  perform public.audit_pdc_event(
    'role_change'::audit_action, 'pdc_user_roles', v_target.id, null,
    v_before, to_jsonb(v_target),
    jsonb_build_object('operation', 'admin_disable_user', 'target_email', v_target.email, 'reason', p_reason)
  );

  return v_target;
end;
$$;

create or replace function public.admin_restore_user(
  p_target_email text,
  p_reason text default null
) returns public.pdc_user_roles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.pdc_user_roles;
  v_before jsonb;
begin
  perform public.require_pdc_role('administrator');

  select * into v_target from public.pdc_user_roles where email = lower(p_target_email);
  if v_target.id is null then
    raise exception 'No account found for %', p_target_email using errcode = 'P0002';
  end if;
  if v_target.account_status != 'disabled' then
    raise exception 'Only a disabled account can be restored' using errcode = '22023';
  end if;

  v_before := to_jsonb(v_target);

  update public.pdc_user_roles set
    active = true,
    account_status = 'approved',
    restored_by = public.current_pdc_actor_role_id(),
    restored_at = now(),
    disabled_by = null,
    disabled_at = null,
    disabled_reason = null,
    notes = coalesce(p_reason, notes),
    updated_at = now()
  where email = lower(p_target_email)
  returning * into v_target;

  perform public.audit_pdc_event(
    'role_change'::audit_action, 'pdc_user_roles', v_target.id, null,
    v_before, to_jsonb(v_target),
    jsonb_build_object('operation', 'admin_restore_user', 'target_email', v_target.email, 'reason', p_reason)
  );

  return v_target;
end;
$$;

-- record_pdc_login(): called once per successful sign-in from the
-- frontend (any authenticated caller may update only their OWN last
-- sign-in timestamp; enforced by the where clause matching the caller's
-- own email, not by trusting a parameter).
create or replace function public.record_pdc_login()
returns void
language sql
security definer
set search_path = public
as $$
  update public.pdc_user_roles
  set last_sign_in_at = now()
  where email = public.current_actor_email();
$$;

revoke all on function public.handle_new_pdc_auth_user() from public, anon, authenticated;
grant execute on function public.current_pdc_account_status() to authenticated;
grant execute on function public.current_pdc_actor_role_id() to authenticated;
grant execute on function public.admin_approve_user(text, public.pdc_role, text) to authenticated;
grant execute on function public.admin_reject_registration(text, text) to authenticated;
grant execute on function public.admin_change_role(text, public.pdc_role, text) to authenticated;
grant execute on function public.admin_disable_user(text, text) to authenticated;
grant execute on function public.admin_restore_user(text, text) to authenticated;
grant execute on function public.record_pdc_login() to authenticated;
-- Not granted to anon: an unauthenticated caller has no session to act
-- as, and require_pdc_role() would reject them anyway, but not granting
-- execute at all is a stronger, defence-in-depth boundary.
revoke all on function public.admin_approve_user(text, public.pdc_role, text) from anon;
revoke all on function public.admin_reject_registration(text, text) from anon;
revoke all on function public.admin_change_role(text, public.pdc_role, text) from anon;
revoke all on function public.admin_disable_user(text, text) from anon;
revoke all on function public.admin_restore_user(text, text) from anon;
revoke all on function public.record_pdc_login() from anon;

commit;
