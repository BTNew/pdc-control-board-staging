-- r435 (F46, 21 Oct 2026, Craig: "make sure Andy can see all finance deals", then: Andy, Bryce and Peter should each see ALL finance
-- deals and all other salespeople's vehicles). Staging cdsmnqxtyyoeoznmbidd only.
-- Fault: the Sales Finance page (Finance, Pipeline and All applications) comes from pdc_sales_private.finance_pipeline(), which returned
-- every entry only to finance editors (crm_finance_editors) and administrators, and otherwise only entries whose salesperson is the
-- caller. The "view all salespeople" setting (account_scopes.can_view_all_salespeople, set by set_broome_sales_board_view_access) widened
-- vehicles but never Finance, so even Bryce (view-all on) saw 5 of 58 entries, and 50 entries have no salesperson at all.
-- Change: finance_pipeline() also returns every entry when the caller has view-all. Read-only and masked exactly as before for
-- non-editors (no financier or commission figures; no Add/edit, no vehicle picker). Editors, administrators and own-only salespeople
-- are unchanged. Adds the private check helper pdc_sales_private.finance_visibility_check_435() and the regression check
-- salesperson_view_all_sees_all_finance (F46, sort 235). Pins both functions. No table or row changes here (the view-all switch for
-- Andy and Peter is the separate audited data step r435_data.sql).
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r435: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r435: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r435: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r435: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_sales_private.context()'::regprocedure)<>'f46074748e6fcb748b97b072d1160b4e' THEN RAISE EXCEPTION 'r435: Sales context changed since r432'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.finance_pipeline()'::regprocedure AND md5(p.prosrc)='6f9bf4771df31527d847f81b186c5cdf' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private')<>1 THEN RAISE EXCEPTION 'r435: finance_pipeline is not the expected original'; END IF;
 IF to_regprocedure('pdc_sales_private.finance_visibility_check_435()') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r435' OR signature='pdc_sales_private.finance_pipeline()')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='salesperson_view_all_sees_all_finance' OR added_in='r435') THEN RAISE EXCEPTION 'r435: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=235) THEN RAISE EXCEPTION 'r435: sort_order 235 taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_sales_private.finance_pipeline()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $f$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); editor boolean:=(ctx->>'can_edit_finance')::boolean; entries jsonb; refs jsonb:='[]'; people jsonb:='[]';
BEGIN
 SELECT coalesce(jsonb_agg(pdc_sales_private.finance_application_json(r,editor) ORDER BY r.created_at,r.id),'[]') INTO entries
 -- r435 (F46): a salesperson with "view all salespeople" (can_view_all_salespeople) sees every finance entry, read-only, with the
 -- same non-editor field masking (no financier or commission figures); finance editors and administrators are unchanged.
 FROM pdc_sales_private.finance_applications r WHERE editor OR coalesce((ctx->>'can_view_all_salespeople')::boolean,false)
  OR r.salesperson_id=(ctx->>'salesperson_id')::uuid;
 IF editor THEN
  refs:=pdc_sales_private.crm_finance_refs();
  SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.code,'name',s.name) ORDER BY s.name),'[]') INTO people FROM public.salespeople s WHERE s.active;
 END IF;
 RETURN jsonb_build_object('context',ctx,'entries',entries,'vehicle_options',refs,'salespeople',people,'checked_at',clock_timestamp());
END $f$;

CREATE FUNCTION pdc_sales_private.finance_visibility_check_435(OUT ok boolean, OUT detail text)
 LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE prev text:=current_setting('request.jwt.claims',true); a record; f jsonb; total int; want int; got int; n int:=0; nva int:=0; bad text:='';
BEGIN
 -- r435 (F46): runs pdc_sales_private.finance_pipeline() as each approved Sales account (salesperson, or controller with a Sales
 -- record link) and compares what it returns with what it should: everything for view-all or finance editors, otherwise only that
 -- salesperson's own entries; non-editors never get financier or commission fields. Read-only; restores the caller's claims.
 SELECT count(*) INTO total FROM pdc_sales_private.finance_applications;
 FOR a IN SELECT r.id, r.email, r.auth_user_id, x.salesperson_id, x.can_view_all_salespeople va,
   EXISTS(SELECT 1 FROM pdc_sales_private.crm_finance_editors e WHERE e.user_role_id=r.id AND e.enabled) ed
  FROM public.pdc_user_roles r JOIN pdc_sales_private.account_scopes x ON x.user_role_id=r.id
  JOIN public.salespeople s ON s.id=x.salesperson_id AND s.active
  WHERE r.active AND r.account_status='approved' AND r.auth_user_id IS NOT NULL AND r.role::text IN ('salesperson','operator') AND x.dealer_code='37047'
  ORDER BY r.id
 LOOP
  n:=n+1; IF a.va THEN nva:=nva+1; END IF;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',a.auth_user_id,'email',a.email,'role','authenticated')::text,true);
  BEGIN
   f:=pdc_sales_private.finance_pipeline();
  EXCEPTION WHEN OTHERS THEN
   bad:=bad||' account '||left(a.id::text,8)||' error: '||SQLERRM||';'; f:=NULL;
  END;
  IF f IS NOT NULL THEN
   got:=jsonb_array_length(f->'entries');
   IF a.va OR a.ed THEN want:=total;
   ELSE SELECT count(*) INTO want FROM pdc_sales_private.finance_applications WHERE salesperson_id=a.salesperson_id; END IF;
   IF got<>want THEN bad:=bad||' account '||left(a.id::text,8)||' sees '||got||' of '||want||';'; END IF;
   IF NOT a.ed AND EXISTS(SELECT 1 FROM jsonb_array_elements(f->'entries') e WHERE e ?| ARRAY['financier','finance_comm','dof_daf','mvi','rsa','total_comm','naf']) THEN
    bad:=bad||' account '||left(a.id::text,8)||' (not a finance editor) gets financier/commission fields;';
   END IF;
  END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(prev,''),true);
 ok:=(bad='' AND n>0);
 detail:=format('%s Sales accounts; %s with view-all see all %s finance entries; the rest see only their own; non-editors get no commission fields%s',
  n,nva,total,CASE WHEN bad<>'' THEN ' | BAD:'||bad WHEN n=0 THEN ' | BAD: no Sales accounts found' ELSE '' END);
END $f$;
REVOKE ALL ON FUNCTION pdc_sales_private.finance_visibility_check_435() FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_sales_private.finance_pipeline()','372dcae199c750594923e2269f661e43','r435','r435 (F46): view-all salespeople see every finance entry, read-only and masked (was 6f9bf4771df31527d847f81b186c5cdf, unpinned)'),
 ('pdc_sales_private.finance_visibility_check_435()','b618db56602ab648872951306a5ad273','r435','r435 (F46): regression check helper, runs finance_pipeline as each Sales account');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('salesperson_view_all_sees_all_finance','F46','Every approved Sales account sees the right Finance entries: all of them with "view all salespeople" or as a finance editor, otherwise only its own; non-editors never get financier or commission fields',
  $chk$SELECT c.ok, c.detail FROM pdc_sales_private.finance_visibility_check_435() c$chk$,true,235,'r435');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.finance_pipeline()'::regprocedure AND md5(p.prosrc)='372dcae199c750594923e2269f661e43' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private')<>1 THEN RAISE EXCEPTION 'r435: finance_pipeline did not land as expected'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('pdc_sales_private.finance_visibility_check_435()') AND md5(p.prosrc)='b618db56602ab648872951306a5ad273' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|v|postgres|search_path=pg_catalog')<>1 THEN RAISE EXCEPTION 'r435: check helper did not land as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='salesperson_view_all_sees_all_finance' AND added_in='r435')<>'86d98eaa9064027a5f43cdd3bedd39f9' THEN RAISE EXCEPTION 'r435: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='salesperson_view_all_sees_all_finance') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r435: check not green: %', x.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r435: clock tick changed'; END IF;
END $g$;
