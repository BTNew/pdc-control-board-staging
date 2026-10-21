-- r419 undo: restores admin_change_role (md5 a89ad7b9890309b63df2a3c57df3c33f) and admin_disable_user (md5 aff4a42d4a1915c781cfff830fb00b76)
-- byte-exact, drops pdc_effective_admin_count_419, the r419 pins and the admin_role_guard check. Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r419 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r419 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r419 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r419 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.admin_change_role(text,pdc_role,text)','eace79d601b07c3c9d001c35f03672c2'),
  ('public.admin_disable_user(text,text)','89ea2fd6d41f1df5fb2ada2cee68addd')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>2 THEN RAISE EXCEPTION 'r419 undo: admin functions are not the r419 versions; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid IN ('public.admin_change_role(text,pdc_role,text)'::regprocedure,'public.admin_disable_user(text,text)'::regprocedure)
     AND p.prosecdef AND p.provolatile='v' AND p.proowner='postgres'::regrole AND p.proacl::text='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' AND array_to_string(p.proconfig,'|')='search_path=public')<>2 THEN RAISE EXCEPTION 'r419 undo: owner, grants, security or settings of the admin functions are not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_effective_admin_count_419(uuid)'::regprocedure)<>'9001d3ca036515d57b99eb7d31be639e' THEN RAISE EXCEPTION 'r419 undo: helper is not the r419 version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r419')<>3 THEN RAISE EXCEPTION 'r419 undo: r419 pins not as expected'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.admin_change_role(p_target_email text, p_role pdc_role, p_reason text DEFAULT NULL::text)
 RETURNS pdc_user_roles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.admin_disable_user(p_target_email text, p_reason text DEFAULT NULL::text)
 RETURNS pdc_user_roles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

DROP FUNCTION public.pdc_effective_admin_count_419(uuid);
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r419';
DELETE FROM pdc_ops.regression_checks WHERE check_name='admin_role_guard' AND added_in='r419';
DO $p$ BEGIN
 IF (SELECT count(*) FROM (VALUES
  ('public.admin_change_role(text,pdc_role,text)','a89ad7b9890309b63df2a3c57df3c33f'),
  ('public.admin_disable_user(text,text)','aff4a42d4a1915c781cfff830fb00b76')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>2 THEN RAISE EXCEPTION 'r419 undo: admin functions not restored'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid IN ('public.admin_change_role(text,pdc_role,text)'::regprocedure,'public.admin_disable_user(text,text)'::regprocedure)
     AND p.prosecdef AND p.provolatile='v' AND p.proowner='postgres'::regrole AND p.proacl::text='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' AND array_to_string(p.proconfig,'|')='search_path=public')<>2 THEN RAISE EXCEPTION 'r419 undo: owner, grants, security or settings of the admin functions are not as expected'; END IF;
 IF to_regprocedure('public.pdc_effective_admin_count_419(uuid)') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r419')
  OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r419') THEN RAISE EXCEPTION 'r419 undo: r419 objects remain'; END IF;
END $p$;
