-- r407 (F21): snapshot function overhead. Staging cdsmnqxtyyoeoznmbidd only.
-- public.pdc_tune_approved_operation_source_20260912 ran 36,036 times per board snapshot. It was a
-- LANGUAGE sql function with SET search_path, so it is never inlined, and when called from inside
-- other functions (operation_station, the snapshot layers) its one-line query was planned again on
-- every call. pdc_bus_private.operation_station also looked it up twice per operation.
-- Fix: (1) the helper becomes PL/pgSQL with the same query, signature, volatility, owner, grants
-- and search_path, so its plan is kept for the session; (2) operation_station looks the approved
-- description up once (OFFSET 0 lateral) and reuses it. The joined keys are unique, so it still
-- returns at most one row. Board and location snapshot JSON were byte-identical (md5, per
-- department 138 and 139) in the rolled-back test; ~11% faster. The clock tick is not touched.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r407: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r407: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r407: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r407: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_tune_approved_operation_source_20260912(uuid)'::regprocedure)<>'157311e04f989c5c8a47c8894bd3a278' THEN RAISE EXCEPTION 'r407: approved-source helper is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'415c4a6993e8693f155c1c3fa4824d5e' THEN RAISE EXCEPTION 'r407: operation_station is not the expected version'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='approved_source_lookup_once') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r407') THEN RAISE EXCEPTION 'r407: already applied'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.pdc_tune_approved_operation_source_20260912(oid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  -- r407 (F21): PL/pgSQL keeps this lookup's plan for the session; the SQL form was
  -- re-planned on every call from inside other functions (36k calls per board snapshot).
  -- Same query, same result: the latest approved proposed_source, or NULL.
  RETURN (SELECT r.proposed_source FROM public.pdc_tune_operation_change_reviews r
          WHERE r.source_operation_id = $1 AND r.status = 'approved'
          ORDER BY r.approved_at DESC, r.change_id DESC LIMIT 1);
END
$function$;

CREATE OR REPLACE FUNCTION pdc_bus_private.operation_station(p_operation_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 -- r407 (F21): the approved description is looked up once per operation (OFFSET 0 keeps
 -- it a single evaluation) instead of once in the result and again in the routing join.
 -- The joined keys are unique (history pkey operation_id; ai_routing pkey
 -- (department, description_hash)), so at most one row, as before.
 SELECT coalesce(h.stage_code,pdc_work_categories_private.stage(r.category),
  public.pdc_department138_station_20260917(d.description))
 FROM public.pdc_pilbara_service_operations o
 CROSS JOIN LATERAL (
  SELECT coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description) AS description
  OFFSET 0) d
 LEFT JOIN pdc_bus_private.operation_routing_history_20261015 h ON h.operation_id=o.operation_id
 LEFT JOIN pdc_operation_updates_private.ai_routing_20261019 r ON r.department=btrim(o.department)
  AND r.description_hash=pdc_work_categories_private.import_description_hash_20261017(d.description)
 WHERE o.operation_id=p_operation_id;
$function$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
('public.pdc_tune_approved_operation_source_20260912(uuid)','867bb1b1c0afebfb62f45c08ad6b3154','r407','Latest approved source per operation; PL/pgSQL so the plan is kept (r407, F21)'),
('pdc_bus_private.operation_station(uuid)','a63c9309fd6ae046d37709cfb3666019','r407','Operation station; approved description looked up once (r407, F21)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
('approved_source_lookup_once','F21','The approved-source helper stays PL/pgSQL with a fixed search_path (plan kept, not re-planned per call), operation_station looks it up once per operation, and the helper returns exactly the latest approved proposed_source for every reviewed operation.','WITH f AS (
  SELECT l.lanname = ''plpgsql'' AS plpgsql,
         coalesce(p.proconfig, ''{}''::text[]) @> ARRAY[''search_path=pg_catalog, public''] AS search_path_fixed
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid = p.prolang
  WHERE p.oid = to_regprocedure(''public.pdc_tune_approved_operation_source_20260912(uuid)'')
), os AS (
  SELECT (length(p.prosrc) - length(replace(p.prosrc, ''pdc_tune_approved_operation_source_20260912'', '''')))
         / length(''pdc_tune_approved_operation_source_20260912'') AS refs
  FROM pg_catalog.pg_proc p WHERE p.oid = to_regprocedure(''pdc_bus_private.operation_station(uuid)'')
), eq AS (
  SELECT count(*) AS n,
         count(*) FILTER (WHERE public.pdc_tune_approved_operation_source_20260912(s.id) IS DISTINCT FROM (
           SELECT r.proposed_source FROM public.pdc_tune_operation_change_reviews r
           WHERE r.source_operation_id = s.id AND r.status = ''approved''
           ORDER BY r.approved_at DESC, r.change_id DESC LIMIT 1)) AS bad
  FROM (SELECT DISTINCT source_operation_id AS id FROM public.pdc_tune_operation_change_reviews
        WHERE source_operation_id IS NOT NULL) s
)
SELECT coalesce(f.plpgsql AND f.search_path_fixed, false) AND coalesce(os.refs, 0) = 1 AND eq.bad = 0 AS ok,
  ''approved-source helper '' || CASE WHEN coalesce(f.plpgsql, false) THEN ''plpgsql (plan kept)'' ELSE ''NOT plpgsql (re-planned per call)'' END
  || CASE WHEN coalesce(f.search_path_fixed, false) THEN '''' ELSE '', search_path not fixed'' END
  || ''; operation_station looks it up '' || coalesce(os.refs, 0) || ''x per operation (expected 1); ''
  || eq.bad || ''/'' || eq.n || '' reviewed operations differ from the direct latest-approved lookup'' AS detail
FROM eq LEFT JOIN f ON true LEFT JOIN os ON true',true,197,'r407');

DO $p$ DECLARE r record; BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r407: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r407: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r407: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_tune_approved_operation_source_20260912(uuid)'::regprocedure)<>'867bb1b1c0afebfb62f45c08ad6b3154' THEN RAISE EXCEPTION 'r407: approved-source helper is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'a63c9309fd6ae046d37709cfb3666019' THEN RAISE EXCEPTION 'r407: operation_station is not the expected version'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_tune_approved_operation_source_20260912(uuid)'::regprocedure)<>'{postgres=X/postgres,service_role=X/postgres}'
    OR (SELECT proacl::text||prosecdef::text||proowner::regrole::text FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'{postgres=X/postgres}truepostgres' THEN RAISE EXCEPTION 'r407: grants changed'; END IF;
IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='approved_source_lookup_once')<>'3065f403b5945c40cc864958ecc5dfe2' THEN RAISE EXCEPTION 'r407: check md5'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r407' AND md5(p.prosrc)=e.prosrc_md5)<>2 THEN RAISE EXCEPTION 'r407: pins'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='approved_source_lookup_once') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r407: check not ok: %', r.detail; END IF;
END $p$;
