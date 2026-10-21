-- r432 undo (F43): puts the Sales context check back to the pre-r432 version (b0238d177dcdd68ec945a1964f4efac6), drops
-- admin_link_controller_salesperson_432 and pdc_my_sales_link_432, removes the r432 pins and the controller_sales_link check.
-- Sales record links already made for controllers are NOT deleted (they stay as history and are ignored by the restored check;
-- undo a data-step link with its own data undo first if it should go). Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r432 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r432 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r432 undo: clock tick changed (r431 is the clock fix; this release must not run on top of an unknown tick)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r432 undo: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.context()'::regprocedure AND md5(p.prosrc)='f46074748e6fcb748b97b072d1160b4e' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private')<>1
    OR (SELECT count(*) FROM pg_proc p WHERE p.oid='public.admin_link_controller_salesperson_432(text)'::regprocedure AND md5(p.prosrc)='88157e1ba08f5fb16d1b1c522b698b15')<>1
    OR (SELECT count(*) FROM pg_proc p WHERE p.oid='public.pdc_my_sales_link_432()'::regprocedure AND md5(p.prosrc)='a431f0cdf91c7537832ba9969994074f')<>1
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r432')<>3
 THEN RAISE EXCEPTION 'r432 undo: r432 is not applied as released (changed since?); nothing undone'; END IF;
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
 IF r.role::text IS DISTINCT FROM 'salesperson' OR r.auth_user_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Salesperson access required' USING errcode='42501';
 END IF;
 SELECT * INTO scope FROM pdc_sales_private.account_scopes WHERE user_role_id=r.id;
 SELECT * INTO sp FROM public.salespeople WHERE id=scope.salesperson_id AND active;
 IF sp.id IS NULL THEN RAISE EXCEPTION 'Ask an administrator to assign your salesperson access' USING errcode='42501'; END IF;
 RETURN jsonb_build_object('role','salesperson','display_name',sp.name,'salesperson_code',sp.code,
  'salesperson_id',sp.id,'dealer_code',scope.dealer_code,'division','Broome Toyota',
  'can_view_all_salespeople',scope.can_view_all_salespeople);
END $fn$;
DROP FUNCTION public.admin_link_controller_salesperson_432(text);
DROP FUNCTION public.pdc_my_sales_link_432();
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r432' AND signature IN ('pdc_sales_private.context()','public.admin_link_controller_salesperson_432(text)','public.pdc_my_sales_link_432()');
DELETE FROM pdc_ops.regression_checks WHERE check_name='controller_sales_link' AND added_in='r432';

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.context()'::regprocedure AND md5(p.prosrc)='b0238d177dcdd68ec945a1964f4efac6' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private')<>1 THEN RAISE EXCEPTION 'r432 undo: context not restored'; END IF;
 IF to_regprocedure('public.admin_link_controller_salesperson_432(text)') IS NOT NULL OR to_regprocedure('public.pdc_my_sales_link_432()') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r432') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r432') THEN RAISE EXCEPTION 'r432 undo: leftovers'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r432 undo: protected_function_md5s not ok: %', x.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
