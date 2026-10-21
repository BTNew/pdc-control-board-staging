-- r419 (F34, Craig 21 Oct, permissions review): admin role guard. Staging cdsmnqxtyyoeoznmbidd only.
-- admin_change_role: an administrator can no longer remove their own administrator role, and the last-administrator check
-- counts only administrators who can actually sign in (login exists and matches, not banned, signed in at least once).
-- admin_disable_user: same last-administrator count (the self-disable refusal was already there).
-- New private helper pdc_effective_admin_count_419 (SECURITY DEFINER, no grant to anon/authenticated).
-- Same owner, grants, SECURITY DEFINER and settings (guarded). Not touched: approve/reject/restore, is_pdc_role, the clock tick,
-- the board, Karratha 135. Frontend (same PR): the role lists include fitter and salesperson, preselect the real role and confirm
-- every role change.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r419: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r419: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r419: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r419: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.admin_change_role(text,pdc_role,text)','a89ad7b9890309b63df2a3c57df3c33f'),
  ('public.admin_disable_user(text,text)','aff4a42d4a1915c781cfff830fb00b76')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>2 THEN RAISE EXCEPTION 'r419: admin functions are not the expected versions'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid IN ('public.admin_change_role(text,pdc_role,text)'::regprocedure,'public.admin_disable_user(text,text)'::regprocedure)
     AND p.prosecdef AND p.provolatile='v' AND p.proowner='postgres'::regrole AND p.proacl::text='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' AND array_to_string(p.proconfig,'|')='search_path=public')<>2 THEN RAISE EXCEPTION 'r419: owner, grants, security or settings of the admin functions are not as expected'; END IF;
 IF to_regprocedure('public.pdc_effective_admin_count_419(uuid)') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r419')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='admin_role_guard' OR added_in='r419') THEN RAISE EXCEPTION 'r419: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=221) THEN RAISE EXCEPTION 'r419: sort_order 221 taken'; END IF;
END $g$;

CREATE FUNCTION public.pdc_effective_admin_count_419(p_exclude_role_id uuid DEFAULT NULL)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
 -- r419 (F34): approved, active administrators whose login exists, matches, is not banned and has signed in at least once.
 SELECT count(*)::integer
 FROM public.pdc_user_roles r
 JOIN auth.users u ON u.id = r.auth_user_id
 WHERE r.role = 'administrator' AND r.active AND r.account_status = 'approved'
   AND (p_exclude_role_id IS NULL OR r.id <> p_exclude_role_id)
   AND lower(coalesce(u.email, '')) = r.email
   AND u.deleted_at IS NULL
   AND (u.banned_until IS NULL OR u.banned_until <= now())
   AND coalesce(u.last_sign_in_at, r.last_sign_in_at) IS NOT NULL;
$function$;

REVOKE ALL ON FUNCTION public.pdc_effective_admin_count_419(uuid) FROM PUBLIC, anon, authenticated;

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
    -- r419 (F34): only administrators who can actually sign in count towards the last-administrator check.
    v_active_admin_count := public.pdc_effective_admin_count_419(v_target.id);
    if v_active_admin_count < 1 then
      raise exception 'Cannot disable the last administrator who can sign in. Approve or restore a second administrator first.' using errcode = '42501';
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

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.admin_change_role(text,public.pdc_role,text)','eace79d601b07c3c9d001c35f03672c2','r419','no self-demotion; last-admin count = admins who can sign in (was a89ad7b9890309b63df2a3c57df3c33f)'),
 ('public.admin_disable_user(text,text)','89ea2fd6d41f1df5fb2ada2cee68addd','r419','last-admin count = admins who can sign in (was aff4a42d4a1915c781cfff830fb00b76)'),
 ('public.pdc_effective_admin_count_419(uuid)','9001d3ca036515d57b99eb7d31be639e','r419','administrators who can sign in');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('admin_role_guard','F34','User Admin: an administrator cannot remove their own admin role or disable themselves, the last-administrator check only counts administrators who can sign in (not banned, signed in at least once), the helper is private, and at least one such administrator exists.',
 $chk$WITH f AS (
 SELECT
  (SELECT position('pdc_effective_admin_count_419(v_target.id)' IN p.prosrc)>0 AND position('cannot remove your own administrator role' IN lower(p.prosrc))>0
     FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.admin_change_role(text,public.pdc_role,text)')) change_ok,
  (SELECT position('pdc_effective_admin_count_419(v_target.id)' IN p.prosrc)>0 AND position('cannot disable your own administrator account' IN lower(p.prosrc))>0
     FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.admin_disable_user(text,text)')) disable_ok,
  (SELECT p.prosecdef AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
     FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.pdc_effective_admin_count_419(uuid)')) helper_ok
), c AS (
 SELECT public.pdc_effective_admin_count_419(NULL) eff,
  (SELECT count(*) FROM public.pdc_user_roles WHERE role='administrator' AND active AND account_status='approved') nominal
)
SELECT coalesce(f.change_ok AND f.disable_ok AND f.helper_ok,false) AND c.eff>=1 AS ok,
 'self-demotion refused: '||CASE WHEN coalesce(f.change_ok,false) THEN 'yes' ELSE 'NO' END
 ||'; self-disable refused and last-admin count uses sign-in-able admins: '||CASE WHEN coalesce(f.disable_ok,false) THEN 'yes' ELSE 'NO' END
 ||'; helper private: '||CASE WHEN coalesce(f.helper_ok,false) THEN 'yes' ELSE 'NO' END
 ||'; administrators who can sign in: '||c.eff||' of '||c.nominal||' approved' AS detail
FROM f, c$chk$,true,221,'r419');

DO $p$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM (VALUES
  ('public.admin_change_role(text,pdc_role,text)','eace79d601b07c3c9d001c35f03672c2'),
  ('public.admin_disable_user(text,text)','89ea2fd6d41f1df5fb2ada2cee68addd')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>2 THEN RAISE EXCEPTION 'r419: new admin function bodies are not the expected md5s'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid IN ('public.admin_change_role(text,pdc_role,text)'::regprocedure,'public.admin_disable_user(text,text)'::regprocedure)
     AND p.prosecdef AND p.provolatile='v' AND p.proowner='postgres'::regrole AND p.proacl::text='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' AND array_to_string(p.proconfig,'|')='search_path=public')<>2 THEN RAISE EXCEPTION 'r419: owner, grants, security or settings of the admin functions are not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_effective_admin_count_419(uuid)'::regprocedure)<>'9001d3ca036515d57b99eb7d31be639e'
  OR (SELECT coalesce(proacl::text,'') FROM pg_proc WHERE oid='public.pdc_effective_admin_count_419(uuid)'::regprocedure)<>'{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r419: helper md5 or grants not as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r419')<>3 THEN RAISE EXCEPTION 'r419: pins not written'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='admin_role_guard') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r419: new regression check is not ok: %', r.detail; END IF;
 -- Same checks again under the runner's search_path (pg_catalog only), as pdc_ops.fault_regression_check() runs them.
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='admin_role_guard') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r419: admin_role_guard not ok under the runner search_path: %', r.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r419: protected_function_md5s not ok: %', r.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
