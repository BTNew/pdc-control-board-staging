-- r432 (F43, 21 Oct 2026, Craig: "Let controllers with a salesperson record also use Sales"). Staging cdsmnqxtyyoeoznmbidd only.
-- Fault: the Sales site check (pdc_sales_private.context) accepted only administrators and salespeople, and an account has one role.
-- A controller who is also a salesperson (lost Sales when trimmed from administrator) could not use Sales without losing the
-- controller role. Change: the Sales check also accepts an approved, active controller (operator) whose account has a Sales record
-- link (pdc_sales_private.account_scopes to an active salespeople row). They get exactly a salesperson's Sales context (role
-- 'salesperson', own vehicles unless can_view_all_salespeople), plus account_role 'operator'; their pdc_user_roles row, controller
-- rights and dealer scope (r423) are untouched and nothing here grants administrator. An unlinked controller still gets
-- "Salesperson access required". New admin RPC admin_link_controller_salesperson_432 (User Admin "Link salesperson record"):
-- administrators only, approved active controllers only, matches the one active salespeople row with the same email (refuses
-- none or more than one), never re-points a working link, never changes can_view_all_salespeople, writes an audit row.
-- New pdc_my_sales_link_432() (own account only) lets the sign-in page keep a linked controller on the Sales site.
-- Pins (context, link RPC, status) and regression check controller_sales_link. Existing accounts are NOT linked here.
-- Not touched: roles, account rows, the r429 helper, admin_change_role/approve, the clock tick and its cron, Karratha 135.
-- Undo: supabase/rollbacks/20261021044811_r432_controller_sales_link.down.sql.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r432: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r432: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r432: clock tick changed (r431 is the clock fix; this release must not run on top of an unknown tick)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r432: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.context()'::regprocedure AND md5(p.prosrc)='b0238d177dcdd68ec945a1964f4efac6' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private')<>1 THEN RAISE EXCEPTION 'r432: Sales context check is not the expected version'; END IF;
 IF to_regprocedure('public.admin_link_controller_salesperson_432(text)') IS NOT NULL OR to_regprocedure('public.pdc_my_sales_link_432()') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r432' OR signature='pdc_sales_private.context()')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='controller_sales_link' OR added_in='r432') THEN RAISE EXCEPTION 'r432: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=229) THEN RAISE EXCEPTION 'r432: sort_order 229 taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_sales_private.context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO pg_catalog, public, pdc_sales_private
AS $fn$
DECLARE r public.pdc_user_roles; sp public.salespeople; scope pdc_sales_private.account_scopes;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 SELECT * INTO r FROM public.pdc_user_roles
 WHERE email=lower(coalesce(auth.jwt()->>'email','')) AND active AND account_status='approved'
 AND (auth_user_id=auth.uid() OR auth_user_id IS NULL);
 IF r.role::text='administrator' THEN
  RETURN jsonb_build_object('role','administrator','display_name',coalesce(r.full_name,r.display_name,r.email),
   'dealer_code','37047','division','Broome Toyota','can_view_all_salespeople',true);
 END IF;
 -- r432 (F43): a controller (operator) whose account has a Sales record link uses Sales as that salesperson, with the
 -- same scope as a salesperson (own vehicles unless can_view_all_salespeople). It is never treated as administrator here.
 IF coalesce(r.role::text,'') NOT IN ('salesperson','operator') OR r.auth_user_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Salesperson access required' USING errcode='42501';
 END IF;
 SELECT * INTO scope FROM pdc_sales_private.account_scopes WHERE user_role_id=r.id;
 SELECT * INTO sp FROM public.salespeople WHERE id=scope.salesperson_id AND active;
 IF sp.id IS NULL AND r.role::text='operator' THEN RAISE EXCEPTION 'Salesperson access required' USING errcode='42501'; END IF;
 IF sp.id IS NULL THEN RAISE EXCEPTION 'Ask an administrator to assign your salesperson access' USING errcode='42501'; END IF;
 RETURN jsonb_build_object('role','salesperson','display_name',sp.name,'salesperson_code',sp.code,
  'salesperson_id',sp.id,'dealer_code',scope.dealer_code,'division','Broome Toyota',
  'can_view_all_salespeople',scope.can_view_all_salespeople,'account_role',r.role::text);
END $fn$;

CREATE FUNCTION public.admin_link_controller_salesperson_432(p_target_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO public
AS $fn$
DECLARE v_target public.pdc_user_roles; cur pdc_sales_private.account_scopes; sp_ids uuid[]; v_sp public.salespeople;
BEGIN
 -- r432 (F43): User Admin "Link salesperson record" for a controller. Administrators only; matches the one active
 -- salespeople row with the same email; never changes the role, never re-points a working link; audited.
 PERFORM public.require_pdc_role('administrator');
 SELECT * INTO v_target FROM public.pdc_user_roles WHERE email=lower(btrim(coalesce(p_target_email,''))) FOR UPDATE;
 IF v_target.id IS NULL THEN RAISE EXCEPTION 'No account found for %', p_target_email USING errcode='P0002'; END IF;
 IF v_target.account_status<>'approved' OR NOT v_target.active THEN
  RAISE EXCEPTION 'Account must be approved and active to link a salesperson record' USING errcode='22023';
 END IF;
 IF v_target.role::text<>'operator' THEN
  RAISE EXCEPTION 'Only a controller can be linked here. A salesperson is linked when their role is changed to salesperson, and an administrator already sees all of Sales.' USING errcode='22023';
 END IF;
 SELECT * INTO cur FROM pdc_sales_private.account_scopes WHERE user_role_id=v_target.id FOR UPDATE;
 IF cur.user_role_id IS NOT NULL THEN
  SELECT * INTO v_sp FROM public.salespeople WHERE id=cur.salesperson_id AND active;
  IF v_sp.id IS NOT NULL THEN
   RETURN jsonb_build_object('ok',true,'already_linked',true,'salesperson_code',v_sp.code,'salesperson_name',v_sp.name);
  END IF;
 END IF;
 SELECT array_agg(s.id) INTO sp_ids FROM public.salespeople s
  WHERE s.active AND s.email IS NOT NULL AND lower(btrim(s.email))=lower(btrim(v_target.email));
 IF coalesce(cardinality(sp_ids),0)=0 THEN
  RAISE EXCEPTION 'No active salesperson record has the email %. Add them to the salespeople list (or correct the email there) first, then link again.', v_target.email USING errcode='22023';
 END IF;
 IF cardinality(sp_ids)>1 THEN
  RAISE EXCEPTION 'More than one active salesperson record has the email %. Fix the salespeople list first, then link again.', v_target.email USING errcode='22023';
 END IF;
 SELECT * INTO v_sp FROM public.salespeople WHERE id=sp_ids[1];
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by)
 VALUES(v_target.id,v_sp.id,auth.uid()) ON CONFLICT(user_role_id) DO UPDATE
 SET salesperson_id=excluded.salesperson_id,assigned_by=excluded.assigned_by,updated_at=now()
 WHERE account_scopes.user_role_id=excluded.user_role_id;
 PERFORM public.audit_pdc_event('role_change'::public.audit_action,'pdc_sales_private.account_scopes',v_target.id,NULL,
  CASE WHEN cur.user_role_id IS NULL THEN NULL ELSE to_jsonb(cur) END,
  jsonb_build_object('salesperson_id',v_sp.id,'dealer_code','37047'),
  jsonb_build_object('operation','assign_broome_sales_access','via','admin_link_controller_salesperson','release','r432',
   'matched_by','salespeople email','target_email',v_target.email,'role_kept',v_target.role::text));
 RETURN jsonb_build_object('ok',true,'already_linked',false,'salesperson_code',v_sp.code,'salesperson_name',v_sp.name);
END
$fn$;
REVOKE ALL ON FUNCTION public.admin_link_controller_salesperson_432(text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_link_controller_salesperson_432(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_link_controller_salesperson_432(text) TO service_role;

CREATE FUNCTION public.pdc_my_sales_link_432()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO pg_catalog
AS $fn$
 -- r432 (F43): true when the signed-in account is an approved, active salesperson or controller with a Sales record link
 -- (used by the sign-in page to let a linked controller stay on the Sales site and show the site switcher).
 SELECT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r
  JOIN pdc_sales_private.account_scopes x ON x.user_role_id=r.id
  JOIN public.salespeople s ON s.id=x.salesperson_id AND s.active
  WHERE auth.uid() IS NOT NULL AND r.auth_user_id=auth.uid()
    AND r.email=lower(coalesce(auth.jwt()->>'email',''))
    AND r.active AND r.account_status='approved' AND r.role::text IN ('salesperson','operator'))
$fn$;
REVOKE ALL ON FUNCTION public.pdc_my_sales_link_432() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.pdc_my_sales_link_432() TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_sales_private.context()','f46074748e6fcb748b97b072d1160b4e','r432','r432: also accepts a controller with a Sales record link, as a salesperson (was b0238d177dcdd68ec945a1964f4efac6, unpinned)'),
 ('public.admin_link_controller_salesperson_432(text)','88157e1ba08f5fb16d1b1c522b698b15','r432','r432: User Admin Link salesperson record for a controller (admin only, by email, audited)'),
 ('public.pdc_my_sales_link_432()','a431f0cdf91c7537832ba9969994074f','r432','r432: own Sales record link status for the sign-in page');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('controller_sales_link','F43',
  'r432: a controller linked to a salesperson record can use the Sales site as that salesperson (never as administrator); every controller link points at an active salespeople row with the same email; the User Admin link is admin-only',
  $chk$WITH l AS (
  SELECT count(*) total,
   count(*) FILTER (WHERE s.id IS NULL OR lower(btrim(coalesce(s.email,'')))<>lower(btrim(r.email))) bad
  FROM pdc_sales_private.account_scopes x JOIN public.pdc_user_roles r ON r.id=x.user_role_id
  LEFT JOIN public.salespeople s ON s.id=x.salesperson_id AND s.active
  WHERE r.role::text='operator' AND r.active AND r.account_status='approved'
), f AS (
  SELECT
   (SELECT position('NOT IN (''salesperson'',''operator'')' IN p.prosrc)>0
       AND position('IF r.role::text=''administrator'' THEN' IN p.prosrc)>0
       AND position('''account_role'',r.role::text' IN p.prosrc)>0
     FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('pdc_sales_private.context()')) ctx,
   (SELECT position('PERFORM public.require_pdc_role(''administrator'');' IN p.prosrc)>0
       AND position('v_target.role::text<>''operator''' IN p.prosrc)>0
       AND has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
     FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.admin_link_controller_salesperson_432(text)')) link,
   (SELECT has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
     FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.pdc_my_sales_link_432()')) st
)
SELECT (SELECT bad=0 FROM l) AND coalesce((SELECT ctx AND link AND st FROM f),false) AS ok,
 'controllers linked to a salesperson record: '||(SELECT total FROM l)||', link not to an active same-email salesperson: '||(SELECT bad FROM l)
 ||'; Sales check accepts linked controllers (never as administrator): '||CASE WHEN coalesce((SELECT ctx FROM f),false) THEN 'yes' ELSE 'NO' END
 ||'; User Admin link is admin-only and closed to anon: '||CASE WHEN coalesce((SELECT link FROM f),false) THEN 'yes' ELSE 'NO' END
 ||'; link status closed to anon: '||CASE WHEN coalesce((SELECT st FROM f),false) THEN 'yes' ELSE 'NO' END AS detail$chk$,true,229,'r432');

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM (VALUES ('pdc_sales_private.context()','f46074748e6fcb748b97b072d1160b4e','{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private'),
   ('public.admin_link_controller_salesperson_432(text)','88157e1ba08f5fb16d1b1c522b698b15','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|true|v|postgres|search_path=public'),
   ('public.pdc_my_sales_link_432()','a431f0cdf91c7537832ba9969994074f','{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog')) e(sig,m,a)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')=e.a)<>3 THEN RAISE EXCEPTION 'r432: a function did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r432')<>3 THEN RAISE EXCEPTION 'r432: pins not written'; END IF;
 IF has_function_privilege('anon','public.admin_link_controller_salesperson_432(text)','EXECUTE') OR has_function_privilege('anon','public.pdc_my_sales_link_432()','EXECUTE') THEN RAISE EXCEPTION 'r432: anon can execute a new function'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r432: protected_function_md5s not ok: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='controller_sales_link') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r432: controller_sales_link not ok: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='salesperson_role_has_sales_link') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r432: salesperson_role_has_sales_link not ok: %', x.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
