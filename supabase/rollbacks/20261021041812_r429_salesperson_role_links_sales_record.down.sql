-- r429 undo (F41): restores admin_change_role (r419) and admin_approve_user byte for byte, the r419 pin, drops the r429 pins, check and
-- link helper. Sales record links already made stay (they are ordinary account_scopes rows with audit history; remove one with the
-- r429 data-step undo if needed). Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r429 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r429 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r429 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES ('public.admin_change_role(text,public.pdc_role,text)','a451a7b4f0071ea5270589ae13c57d93','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|true|v|postgres|search_path=public'),
   ('public.admin_approve_user(text,public.pdc_role,text)','6e194aea5a34a344d548ec6ae2d85645','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|true|v|postgres|search_path=public'),
   ('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)','6f252dc514a40ff8d728073109de91bf','{postgres=X/postgres}|false|v|postgres|search_path=pg_catalog')) e(sig,m,a)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')=e.a)<>3 THEN RAISE EXCEPTION 'r429 undo: functions are not the r429 versions; nothing restored'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.admin_change_role(p_target_email text, p_role public.pdc_role, p_reason text DEFAULT NULL::text)
 RETURNS public.pdc_user_roles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
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
    -- r419 (F34): an administrator cannot remove their own administrator role, and the last-administrator
    -- count only includes administrators who can actually sign in (login not banned, signed in at least once).
    if lower(v_target.email) = public.current_actor_email() then
      raise exception 'You cannot remove your own administrator role. Ask another administrator to change it.' using errcode = '42501';
    end if;
    v_active_admin_count := public.pdc_effective_admin_count_419(v_target.id);
    if v_active_admin_count < 1 then
      raise exception 'Cannot remove the last administrator who can sign in. Approve or restore a second administrator first.' using errcode = '42501';
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
$fn$;

CREATE OR REPLACE FUNCTION public.admin_approve_user(p_target_email text, p_role public.pdc_role, p_notes text DEFAULT NULL::text)
 RETURNS public.pdc_user_roles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
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
$fn$;

DROP FUNCTION pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean);
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='eace79d601b07c3c9d001c35f03672c2', release='r419', note='no self-demotion; last-admin count = admins who can sign in (was a89ad7b9890309b63df2a3c57df3c33f)', updated_at=now()
 WHERE signature='public.admin_change_role(text,public.pdc_role,text)' AND release='r429';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r429';
DELETE FROM pdc_ops.regression_checks WHERE check_name='salesperson_role_has_sales_link' AND added_in='r429';

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM (VALUES ('public.admin_change_role(text,pdc_role,text)','eace79d601b07c3c9d001c35f03672c2'),('public.admin_approve_user(text,pdc_role,text)','e09e4333b01a887ab5a475100dfda5e3')) e(sig,m)
   JOIN pg_proc p ON p.oid=e.sig::regprocedure WHERE md5(p.prosrc)=e.m AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|true|v|postgres|search_path=public')<>2 THEN RAISE EXCEPTION 'r429 undo: functions not restored'; END IF;
 IF to_regprocedure('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r429')
   OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.admin_change_role(text,public.pdc_role,text)' AND release='r419' AND prosrc_md5='eace79d601b07c3c9d001c35f03672c2')<>1 THEN RAISE EXCEPTION 'r429 undo: pins not restored'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r429 undo: protected_function_md5s not ok: %', x.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
