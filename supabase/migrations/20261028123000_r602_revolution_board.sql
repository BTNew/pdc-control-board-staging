-- r602 (F216) / sort 373. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Read-only board snapshot for the Revolution upload dry run. It does not import and it does not write.
-- Kajel's rows function 9be0883b1a555f48f3c1ba9fa111c891 and apply function b62fb7c29ffd2a1629f214f696e5cb14 stay byte-identical.
-- r601 / F215 / sort 372 (validate_cross_bay_off_601) is the cascade check. This is the next free triple.
-- Pin count stays 241. No new pin. Department 135 stays fd05b9eef69498002ac06dd68e01cdff.
-- Undo: supabase/rollbacks/20261028123000_r602_revolution_board.down.sql
SET LOCAL lock_timeout = '8s';
DO $g$
DECLARE
  awst time;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r602: quiet window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r602: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r602: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r602: pin count is not 241'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=372 AND fault_id='F215' AND check_name='validate_cross_bay_off_601' AND added_in='r601') THEN RAISE EXCEPTION 'r602: r601 is not in the ledger'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=373 OR fault_id='F216' OR check_name='revolution_board_602' OR added_in='r602') THEN RAISE EXCEPTION 'r602: sort 373 / F216 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r602: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r602: Kajel apply changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r602: department 135 changed'; END IF;
  IF to_regprocedure('public.pdc_revolution_board_602(text)') IS NOT NULL THEN RAISE EXCEPTION 'r602: board snapshot already exists'; END IF;
END $g$;

CREATE FUNCTION public.pdc_revolution_board_602(p_kind text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pdc_sales_private, pdc_parts_private
SET statement_timeout = '8s'
SET lock_timeout = '2s'
AS $board$
DECLARE
  kind text := lower(btrim(coalesce(p_kind, '')));
  vehicles jsonb;
  jobs jsonb;
BEGIN
  -- r602 board snapshot. Read only. Granted to service_role.
  IF NOT public.pdc_monitor_staging_guard() THEN
    RAISE EXCEPTION 'r602: staging only';
  END IF;
  IF kind = 'bt_deal_items' OR kind = 'kta_deal_items' THEN
    IF kind = 'bt_deal_items' THEN
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'stock', s.stock, 'quote', s.quote, 'dealer_code', '37047', 'line_keys', s.line_keys
      ) ORDER BY s.stock), '[]'::jsonb) INTO vehicles
      FROM (
        SELECT upper(btrim(l.stock)) AS stock, min(l.quote) AS quote,
               coalesce(jsonb_agg(l.line_key ORDER BY l.line_key), '[]'::jsonb) AS line_keys
        FROM pdc_sales_private.sales_accessory_lines l
        WHERE l.dealer_code = '37047' AND l.superseded_receipt_id IS NULL
        GROUP BY upper(btrim(l.stock))
      ) s;
    ELSE
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'stock', s.stock, 'quote', s.quote, 'dealer_code', '14450', 'line_keys', s.line_keys
      ) ORDER BY s.stock), '[]'::jsonb) INTO vehicles
      FROM (
        SELECT upper(btrim(l.stock)) AS stock, min(l.quote) AS quote,
               coalesce(jsonb_agg(l.line_key ORDER BY l.line_key), '[]'::jsonb) AS line_keys
        FROM pdc_sales_private.karratha_sales_accessory_lines l
        WHERE l.dealer_code = '14450' AND l.superseded_receipt_id IS NULL
        GROUP BY upper(btrim(l.stock))
      ) s;
    END IF;
    RETURN jsonb_build_object('ok', true, 'kind', kind, 'vehicles', vehicles, 'jobs', '[]'::jsonb);
  END IF;
  IF kind = 'service_whole' OR kind = 'service_complete' THEN
    WITH sales_stock AS (
      SELECT public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock')) AS stock,
             min(n.dealer_code) AS dealer_code
      FROM public.navision_backend_records n
      WHERE n.source_system = 'microsoft_navision' AND n.is_current AND n.record_status::text = 'current'
        AND n.dealer_code IN ('37047', '037047', '14450', '014450')
      GROUP BY 1
    ), picked AS (
      SELECT v.id, v.stock_number, v.job_card_number, v.lifecycle_state::text AS ls,
             v.visible_on_board, v.key_number::text AS key_number, sales.dealer_code
      FROM public.vehicles v
      LEFT JOIN sales_stock sales ON sales.stock = public.normalize_vehicle_stock_number(v.stock_number)
      WHERE v.deleted_at IS NULL AND v.board_purged_at IS NULL
        AND v.lifecycle_state::text IN ('active', 'rft')
        AND EXISTS (
          SELECT 1 FROM public.pdc_pilbara_service_operations o
          WHERE o.vehicle_id = v.id AND o.department IN ('138', '139')
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.pdc_pilbara_service_operations o
          WHERE o.vehicle_id = v.id AND o.department = '135'
        )
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'stock', p.stock_number, 'jc', p.job_card_number, 'ls', p.ls,
      'deleted', false, 'visible', p.visible_on_board, 'key', p.key_number, 'dealer_code', p.dealer_code
    )), '[]'::jsonb) INTO vehicles
    FROM picked p;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'vehicle_id', j.vehicle_id, 'ro', j.ro_number, 'closed', j.closed_at IS NOT NULL
    )), '[]'::jsonb) INTO jobs
    FROM pdc_parts_private.jobs j
    WHERE j.company = '01' AND j.division = '1' AND j.source_system = 'tune_pmg'
      AND j.departments && ARRAY['138', '139']::text[]
      AND j.vehicle_id IN (
        SELECT v.id FROM public.vehicles v
        WHERE v.deleted_at IS NULL AND v.board_purged_at IS NULL
          AND v.lifecycle_state::text IN ('active', 'rft')
          AND EXISTS (
            SELECT 1 FROM public.pdc_pilbara_service_operations o
            WHERE o.vehicle_id = v.id AND o.department IN ('138', '139')
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.pdc_pilbara_service_operations o
            WHERE o.vehicle_id = v.id AND o.department = '135'
          )
      );
    RETURN jsonb_build_object('ok', true, 'kind', kind, 'vehicles', vehicles, 'jobs', jobs);
  END IF;
  IF kind = 'cw_parts' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'vehicle_id', j.vehicle_id, 'ro', j.ro_number, 'closed', false
    )), '[]'::jsonb) INTO jobs
    FROM pdc_parts_private.jobs j
    JOIN public.vehicles v ON v.id = j.vehicle_id
    WHERE j.company = '01' AND j.division = '1' AND j.source_system = 'tune_pmg'
      AND j.closed_at IS NULL
      AND j.departments && ARRAY['138', '139']::text[]
      AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
      AND v.lifecycle_state::text = 'active' AND v.visible_on_board
      AND nullif(btrim(v.stock_number), '') IS NOT NULL
      AND j.stock_number = btrim(v.stock_number);
    RETURN jsonb_build_object('ok', true, 'kind', kind, 'vehicles', '[]'::jsonb, 'jobs', jobs);
  END IF;
  RETURN jsonb_build_object('ok', false, 'kind', kind, 'vehicles', '[]'::jsonb, 'jobs', '[]'::jsonb);
END;
$board$;

REVOKE ALL ON FUNCTION public.pdc_revolution_board_602(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_revolution_board_602(text) TO service_role;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('revolution_board_602', 'F216', 'Revolution dry run reads the current board. Deal lines come from current accessory rows. Service is departments 138 and 139. Parts jobs are the open 138 and 139 cards. Kajel and department 135 stay pinned.',
$chk601$SELECT
  fn.prosecdef
  AND fn.provolatile = 's'
  AND has_function_privilege('service_role', fn.oid, 'EXECUTE')
  AND NOT has_function_privilege('anon', fn.oid, 'EXECUTE')
  AND NOT has_function_privilege('authenticated', fn.oid, 'EXECUTE')
  AND fn.prosrc !~ '\m(insert|update|delete)\M'
  AND pg_catalog.strpos(fn.prosrc, 'superseded_receipt_id IS NULL') > 0
  AND pg_catalog.strpos(fn.prosrc, '37047') > 0
  AND pg_catalog.strpos(fn.prosrc, '14450') > 0
  AND pg_catalog.strpos(fn.prosrc, '138') > 0
  AND rows_fn.md5 = '9be0883b1a555f48f3c1ba9fa111c891'
  AND apply_fn.md5 = 'b62fb7c29ffd2a1629f214f696e5cb14'
  AND dept.md5 = 'fd05b9eef69498002ac06dd68e01cdff'
  AND (bt.payload->>'ok') = 'true'
  AND (bt.payload->>'kind') = 'bt_deal_items'
  AND jsonb_typeof(bt.payload->'vehicles') = 'array'
  AND jsonb_typeof(kta.payload->'vehicles') = 'array'
  AND (kta.payload->>'kind') = 'kta_deal_items'
  AND jsonb_typeof(svc.payload->'vehicles') = 'array'
  AND jsonb_typeof(svc.payload->'jobs') = 'array'
  AND (parts.payload->>'kind') = 'cw_parts'
  AND jsonb_typeof(parts.payload->'jobs') = 'array'
  AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(bt.payload->'vehicles') v
    WHERE jsonb_typeof(v->'line_keys') IS DISTINCT FROM 'array' OR coalesce(v->>'stock', '') = '' OR v->>'dealer_code' IS DISTINCT FROM '37047'
  )
  AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(parts.payload->'jobs') j
    WHERE coalesce(j->>'ro', '') = '' OR (j->>'closed') IS DISTINCT FROM 'false'
  )
 AS ok,
 'Revolution dry run reads the current board' AS detail
 FROM (
  SELECT p.oid, p.prosecdef, p.provolatile, p.prosrc
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_revolution_board_602(text)')
 ) fn
 CROSS JOIN (SELECT public.pdc_revolution_board_602('bt_deal_items') AS payload) bt
 CROSS JOIN (SELECT public.pdc_revolution_board_602('kta_deal_items') AS payload) kta
 CROSS JOIN (SELECT public.pdc_revolution_board_602('service_whole') AS payload) svc
 CROSS JOIN (SELECT public.pdc_revolution_board_602('cw_parts') AS payload) parts
 CROSS JOIN (SELECT md5(p.prosrc) AS md5 FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) rows_fn
 CROSS JOIN (SELECT md5(p.prosrc) AS md5 FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) apply_fn
 CROSS JOIN (SELECT md5(p.prosrc) AS md5 FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) dept
$chk601$,
true, 373, 'r602');

DO $p$
DECLARE
  ok boolean;
  detail text;
BEGIN
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='revolution_board_602' AND fault_id='F216' AND sort_order=373 AND added_in='r602' AND enabled)<>1 THEN RAISE EXCEPTION 'r602: check missing'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r602: pin count changed'; END IF;
  IF (SELECT provolatile FROM pg_proc WHERE oid=to_regprocedure('public.pdc_revolution_board_602(text)')) IS DISTINCT FROM 's' THEN RAISE EXCEPTION 'r602: board snapshot is not stable'; END IF;
  IF NOT has_function_privilege('service_role', 'public.pdc_revolution_board_602(text)', 'EXECUTE') THEN RAISE EXCEPTION 'r602: service role cannot read the board'; END IF;
  IF has_function_privilege('anon', 'public.pdc_revolution_board_602(text)', 'EXECUTE') OR has_function_privilege('authenticated', 'public.pdc_revolution_board_602(text)', 'EXECUTE') THEN RAISE EXCEPTION 'r602: board snapshot is granted too widely'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r602: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r602: Kajel apply changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r602: department 135 changed'; END IF;
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='revolution_board_602') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r602: board check red: %', left(coalesce(detail, ''), 200); END IF;
END $p$;
