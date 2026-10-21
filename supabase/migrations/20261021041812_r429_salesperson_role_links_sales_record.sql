-- r429 (F41, 21 Oct, Craig: "why is andy.weir not getting salesperson access after i give it"). Staging cdsmnqxtyyoeoznmbidd only.
-- Fault: the Sales site needs two things for a salesperson: the role (pdc_user_roles.role='salesperson') AND a Sales record link
-- (pdc_sales_private.account_scopes -> salespeople), which picks whose vehicles they see. User Admin "Change role" only sets the role.
-- The link used to be made by the Sales site's salesperson access panel (assign_broome_sales_access), which was removed, so an account
-- switched to salesperson in User Admin signs in and gets "Ask an administrator to assign your salesperson access".
-- Fix: admin_change_role links the Sales record (the active salespeople row with the same email) in the same transaction, and refuses
-- the change with a clear message if there is no such row (no more half-done salesperson accounts). admin_approve_user links it too
-- when a match exists (not strict, so the existing assign_access approve-then-assign path keeps working). An existing link is never
-- re-pointed; can_view_all_salespeople is not touched. Every link writes an audit row (operation assign_broome_sales_access, via ...).
-- Same owner, grants, SECURITY DEFINER and search_path on the two RPCs (guarded). Pins and regression check salesperson_role_has_sales_link.
-- Repo copy: the link helper carries r429b's WHERE (migration 20261021042111) so the safeupdate lint passes.
-- Existing accounts are NOT changed here (the restore of the one account Craig switched is a separate audited data step).
-- Not touched: roles, account rows, audit history, the Sales context check, the clock tick, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r429: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r429: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r429: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r429: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='public.admin_change_role(text,pdc_role,text)'::regprocedure AND md5(p.prosrc)='eace79d601b07c3c9d001c35f03672c2' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|true|v|postgres|search_path=public')<>1 THEN RAISE EXCEPTION 'r429: admin_change_role is not the expected (r419) version'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='public.admin_approve_user(text,pdc_role,text)'::regprocedure AND md5(p.prosrc)='e09e4333b01a887ab5a475100dfda5e3' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|true|v|postgres|search_path=public')<>1 THEN RAISE EXCEPTION 'r429: admin_approve_user is not the expected version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.admin_change_role(text,public.pdc_role,text)' AND prosrc_md5='eace79d601b07c3c9d001c35f03672c2' AND release='r419')<>1 THEN RAISE EXCEPTION 'r429: r419 pin not as expected'; END IF;
 IF to_regprocedure('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r429')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='salesperson_role_has_sales_link' OR added_in='r429') THEN RAISE EXCEPTION 'r429: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=228) THEN RAISE EXCEPTION 'r429: sort_order 228 taken'; END IF;
END $g$;

CREATE FUNCTION pdc_sales_private.link_salesperson_scope_429(p_user_role_id uuid, p_operation text, p_strict boolean)
RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $fn$
DECLARE r public.pdc_user_roles; cur pdc_sales_private.account_scopes; sp_ids uuid[]; v_sp uuid; v_actor uuid;
BEGIN
 -- r429 (F41). Called only from admin_change_role (strict) and admin_approve_user (not strict); not granted to app roles.
 SELECT * INTO r FROM public.pdc_user_roles WHERE id=p_user_role_id;
 IF r.id IS NULL OR r.role::text<>'salesperson' THEN RETURN NULL; END IF;
 SELECT * INTO cur FROM pdc_sales_private.account_scopes WHERE user_role_id=r.id;
 IF cur.user_role_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.salespeople s WHERE s.id=cur.salesperson_id AND s.active) THEN
  RETURN cur.salesperson_id;  -- already linked: never re-point an existing link
 END IF;
 SELECT array_agg(s.id) INTO sp_ids FROM public.salespeople s
  WHERE s.active AND s.email IS NOT NULL AND lower(btrim(s.email))=lower(btrim(r.email));
 v_actor:=auth.uid();
 IF coalesce(cardinality(sp_ids),0)<>1 OR v_actor IS NULL THEN
  IF p_strict THEN
   IF v_actor IS NULL THEN RAISE EXCEPTION 'Sign in required to link Sales access' USING errcode='42501'; END IF;
   IF coalesce(cardinality(sp_ids),0)=0 THEN
    RAISE EXCEPTION 'No active salesperson record has the email %, so their Sales access cannot be linked. Add them to the salespeople list (or correct the email there) first, then change the role again.', r.email USING errcode='22023';
   END IF;
   RAISE EXCEPTION 'More than one active salesperson record has the email %. Fix the salespeople list first, then change the role again.', r.email USING errcode='22023';
  END IF;
  RETURN NULL;
 END IF;
 v_sp:=sp_ids[1];
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by)
 VALUES(r.id,v_sp,v_actor) ON CONFLICT(user_role_id) DO UPDATE
 SET salesperson_id=excluded.salesperson_id,assigned_by=excluded.assigned_by,updated_at=now()
 WHERE account_scopes.user_role_id=excluded.user_role_id;  -- r429b (20261021042111) adds this WHERE on staging
 PERFORM public.audit_pdc_event('role_change'::public.audit_action,'pdc_sales_private.account_scopes',r.id,NULL,
  CASE WHEN cur.user_role_id IS NULL THEN NULL ELSE to_jsonb(cur) END,
  jsonb_build_object('salesperson_id',v_sp,'dealer_code','37047'),
  jsonb_build_object('operation','assign_broome_sales_access','via',p_operation,'release','r429','matched_by','salespeople email'));
 RETURN v_sp;
END
$fn$;
REVOKE ALL ON FUNCTION pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean) FROM PUBLIC, anon, authenticated, service_role;

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

  -- r429 (F41): a salesperson role only works on the Sales site with its Sales record link
  -- (pdc_sales_private.account_scopes). Link it to the active salespeople row with the same email.
  if p_role = 'salesperson' then
    perform pdc_sales_private.link_salesperson_scope_429(v_target.id, 'admin_change_role', true);
  end if;

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

  -- r429 (F41): a salesperson role only works on the Sales site with its Sales record link
  -- (pdc_sales_private.account_scopes). Link it to the active salespeople row with the same email.
  if p_role = 'salesperson' then
    perform pdc_sales_private.link_salesperson_scope_429(v_target.id, 'admin_approve_user', false);
  end if;

  return v_target;
end;
$fn$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='a451a7b4f0071ea5270589ae13c57d93', release='r429', note='r429: links the Sales record when the role becomes salesperson (was r419 eace79d601b07c3c9d001c35f03672c2)', updated_at=now()
 WHERE signature='public.admin_change_role(text,public.pdc_role,text)' AND release='r419';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.admin_approve_user(text,public.pdc_role,text)','6e194aea5a34a344d548ec6ae2d85645','r429','r429: links the Sales record on salesperson approval when the email matches (was e09e4333b01a887ab5a475100dfda5e3, unpinned)'),
 ('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)','6f252dc514a40ff8d728073109de91bf','r429','r429: salesperson Sales record link by email');
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('salesperson_role_has_sales_link','F41','Every approved, active salesperson account has a Sales record link (account_scopes to an active salespeople row), so none gets "Ask an administrator to assign your salesperson access"; User Admin Change role and Approve link the record by email; the link helper is not callable by app roles',
  $chk$WITH a AS (
  SELECT count(*) total, count(*) FILTER (WHERE s.id IS NULL) unlinked,
   string_agg(CASE WHEN s.id IS NULL THEN coalesce(r.full_name,r.display_name,'(no name)') END,', ' ORDER BY r.full_name) names
  FROM public.pdc_user_roles r LEFT JOIN pdc_sales_private.account_scopes x ON x.user_role_id=r.id
  LEFT JOIN public.salespeople s ON s.id=x.salesperson_id AND s.active
  WHERE r.role::text='salesperson' AND r.account_status='approved' AND r.active AND r.auth_user_id IS NOT NULL
), f AS (
  SELECT (SELECT position('pdc_sales_private.link_salesperson_scope_429(v_target.id, ''admin_change_role'', true)' IN p.prosrc)>0
           FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.admin_change_role(text,public.pdc_role,text)')) acr,
   (SELECT position('pdc_sales_private.link_salesperson_scope_429(v_target.id, ''admin_approve_user'', false)' IN p.prosrc)>0
           FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.admin_approve_user(text,public.pdc_role,text)')) aau,
   (SELECT NOT has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
           FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)')) priv
)
SELECT (SELECT unlinked=0 FROM a) AND coalesce((SELECT acr AND aau AND priv FROM f),false) AS ok,
 'salesperson accounts: '||(SELECT total FROM a)||', without a Sales record link (see "Ask an administrator to assign your salesperson access"): '
 ||(SELECT unlinked FROM a)||coalesce(' ('||(SELECT names FROM a)||')','')
 ||'; Change role and Approve link the Sales record: '||CASE WHEN coalesce((SELECT acr AND aau FROM f),false) THEN 'yes' ELSE 'NO' END
 ||'; link helper closed to app roles: '||CASE WHEN coalesce((SELECT priv FROM f),false) THEN 'yes' ELSE 'NO' END AS detail$chk$,true,228,'r429');

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM (VALUES ('public.admin_change_role(text,public.pdc_role,text)','a451a7b4f0071ea5270589ae13c57d93','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|true|v|postgres|search_path=public'),
   ('public.admin_approve_user(text,public.pdc_role,text)','6e194aea5a34a344d548ec6ae2d85645','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|true|v|postgres|search_path=public'),
   ('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)','6f252dc514a40ff8d728073109de91bf','{postgres=X/postgres}|false|v|postgres|search_path=pg_catalog')) e(sig,m,a)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')=e.a)<>3 THEN RAISE EXCEPTION 'r429: a function did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r429')<>3 THEN RAISE EXCEPTION 'r429: pins not written'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r429: protected_function_md5s not ok: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='salesperson_role_has_sales_link') INTO x;
 IF position('Change role and Approve link the Sales record: yes' IN x.detail)=0 OR position('closed to app roles: yes' IN x.detail)=0 THEN RAISE EXCEPTION 'r429: new check wiring not ok: %', x.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
