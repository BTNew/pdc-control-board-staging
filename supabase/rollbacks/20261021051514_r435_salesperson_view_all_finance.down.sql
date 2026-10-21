-- r435 undo (F46). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Run r435_data.down.sql FIRST if the data step is
-- being undone too. Restores pdc_sales_private.finance_pipeline() byte-for-byte (md5 6f9bf4771df31527d847f81b186c5cdf, unpinned as before r435), drops the
-- r435 check, both r435 pins and the check helper. r435 changed no table or row.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r435 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r435 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r435 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_sales_private.finance_pipeline()'::regprocedure)<>'372dcae199c750594923e2269f661e43' THEN RAISE EXCEPTION 'r435 undo: finance_pipeline is not the r435 version (changed since?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_visibility_check_435()'))<>'b618db56602ab648872951306a5ad273' THEN RAISE EXCEPTION 'r435 undo: check helper is not the r435 version'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='salesperson_view_all_sees_all_finance' AND added_in='r435';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r435' AND signature IN ('pdc_sales_private.finance_pipeline()','pdc_sales_private.finance_visibility_check_435()');
DROP FUNCTION pdc_sales_private.finance_visibility_check_435();
CREATE OR REPLACE FUNCTION pdc_sales_private.finance_pipeline()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $f$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); editor boolean:=(ctx->>'can_edit_finance')::boolean; entries jsonb; refs jsonb:='[]'; people jsonb:='[]';
BEGIN
 SELECT coalesce(jsonb_agg(pdc_sales_private.finance_application_json(r,editor) ORDER BY r.created_at,r.id),'[]') INTO entries
 FROM pdc_sales_private.finance_applications r WHERE editor OR r.salesperson_id=(ctx->>'salesperson_id')::uuid;
 IF editor THEN
  refs:=pdc_sales_private.crm_finance_refs();
  SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.code,'name',s.name) ORDER BY s.name),'[]') INTO people FROM public.salespeople s WHERE s.active;
 END IF;
 RETURN jsonb_build_object('context',ctx,'entries',entries,'vehicle_options',refs,'salespeople',people,'checked_at',clock_timestamp());
END $f$;

DO $g$ BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.finance_pipeline()'::regprocedure AND md5(p.prosrc)='6f9bf4771df31527d847f81b186c5cdf' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private')<>1 THEN RAISE EXCEPTION 'r435 undo: finance_pipeline not restored'; END IF;
 IF to_regprocedure('pdc_sales_private.finance_visibility_check_435()') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r435')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r435') THEN RAISE EXCEPTION 'r435 undo: leftovers'; END IF;
END $g$;
