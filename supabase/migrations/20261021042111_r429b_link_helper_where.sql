-- r429b (F41): the r429 link helper (migration 20261021041812) wrote the Sales record link with INSERT ... ON CONFLICT DO UPDATE
-- without a WHERE clause, which the release rules (pg-safeupdate lint, RELEASE_FLOW step 4) do not allow. Same function with an
-- explicit WHERE on the conflicting row; nothing else changes. Undo: supabase/rollbacks/20261021042111_r429b_link_helper_where.down.sql.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r429b: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r429b: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r429b: clock tick changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)'::regprocedure AND md5(p.prosrc)='6f252dc514a40ff8d728073109de91bf' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|v|postgres|search_path=pg_catalog')<>1
    OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)' AND release='r429')<>'6f252dc514a40ff8d728073109de91bf'
 THEN RAISE EXCEPTION 'r429b: link helper is not the r429 version'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_sales_private.link_salesperson_scope_429(p_user_role_id uuid, p_operation text, p_strict boolean)
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
 WHERE account_scopes.user_role_id=excluded.user_role_id;
 PERFORM public.audit_pdc_event('role_change'::public.audit_action,'pdc_sales_private.account_scopes',r.id,NULL,
  CASE WHEN cur.user_role_id IS NULL THEN NULL ELSE to_jsonb(cur) END,
  jsonb_build_object('salesperson_id',v_sp,'dealer_code','37047'),
  jsonb_build_object('operation','assign_broome_sales_access','via',p_operation,'release','r429','matched_by','salespeople email'));
 RETURN v_sp;
END
$fn$;
REVOKE ALL ON FUNCTION pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean) FROM PUBLIC, anon, authenticated, service_role;
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='280d0afd36816510053cd6ea8fe154b1', release='r429b', note='r429b: explicit WHERE on the ON CONFLICT update (was r429 6f252dc514a40ff8d728073109de91bf)', updated_at=now()
 WHERE signature='pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)' AND release='r429';

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)'::regprocedure AND md5(p.prosrc)='280d0afd36816510053cd6ea8fe154b1' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|v|postgres|search_path=pg_catalog')<>1
    OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)' AND release='r429b')<>'280d0afd36816510053cd6ea8fe154b1' THEN RAISE EXCEPTION 'r429b: helper or pin not as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r429b: protected_function_md5s not ok: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='salesperson_role_has_sales_link') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r429b: salesperson_role_has_sales_link not ok: %', x.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
