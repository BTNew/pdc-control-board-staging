-- r433 (F44, 21 Oct, Craig via PMB Email 12:45 AWST): every Navision vehicle whose location status starts with Y goes in the Sales
-- "YH / Yard Hold" tile. Staging cdsmnqxtyyoeoznmbidd only.
-- Fault: the Sales tracker tile (sales/sales.js category()) only put a vehicle in Yard Hold when its Navision location code was exactly
-- 'YH' or the Toyota text said "yard hold"; every other Y code fell through to the Toyota status text: YN Waiting PD2 / Vehicle Delayed
-- and YR Waiting For Wholesale went to Hold/Waiting, YW Ready For Transport - From TWA went to Released. Today's feed has no YH at all,
-- so the tile read 0 while 18 yard vehicles sat in other tiles.
-- Fix is on the screen (sales.js: location code starting with Y -> yardhold). This migration adds only the server mirror of the tile rule,
-- pdc_sales_private.sales_tracker_tile(item) (IMMUTABLE, private, not callable by app roles), so the regression check
-- navision_y_status_maps_to_yard_hold (F44, sort 231) can test today's feed. No existing function, table, row, import or email path is changed.
-- Consistent with r427 (F40): Y? is rank 2 (at the yard) in yard_hold_stage_rank; the check goes red on any Y code outside that family.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r433: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r433: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r433: clock tick changed (this release must not touch it; r431 is the clock release)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r433: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_sales_private.yard_hold_stage_rank(text,text)'::regprocedure)<>'a441a598a1a6477e36d0a73ad7c5d354' THEN RAISE EXCEPTION 'r433: r427 yard_hold_stage_rank changed'; END IF;
 IF to_regprocedure('pdc_sales_private.sales_tracker_tile(jsonb)') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r433')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='navision_y_status_maps_to_yard_hold' OR added_in='r433') THEN RAISE EXCEPTION 'r433: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=231) THEN RAISE EXCEPTION 'r433: sort_order 231 taken'; END IF;
END $g$;

-- r433 (F44): the Sales "Navision vehicle tracker" tile for one row, byte-for-byte the same rule as sales/sales.js category():
-- dealer > Autocare dispatched > awaiting stock > YH / Yard Hold (location code starting with Y, or Toyota text "yard hold") >
-- production > released > hold/waiting > transit > unknown. Used by the regression check only.
CREATE FUNCTION pdc_sales_private.sales_tracker_tile(p_item jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  SELECT CASE
    WHEN x.s ~ '(delivered.*dealer|at dealer)' THEN 'dealer'
    WHEN p_item->'autocare_dispatched'='true'::jsonb THEN 'autocare'
    WHEN x.stock IS NULL OR x.stock IN ('','false') OR x.stock ~* '^(0|TBA)$' THEN 'unconfirmed'
    WHEN x.code LIKE 'Y%' OR position('yard hold' IN x.s)>0 THEN 'yardhold'
    WHEN x.s ~ '(planned for production|line off|final inspection|o/s wharf|eastern states)' THEN 'production'
    WHEN x.s ~ '(consignment|body builder|ready for transport|ready for despatch|ready for dispatch|despatched|dispatched|despatch to|dispatch to)' THEN 'released'
    WHEN x.s ~ '(waiting pd|waiting for wholesale|delayed|hold|waiting)' THEN 'hold'
    WHEN x.s ~ '(ready for shipment|in transit|wharf|shipment)' THEN 'transit'
    ELSE 'unknown' END
  FROM (SELECT lower(coalesce(p_item->>'toyota_status','')) s,
    upper(btrim(coalesce(p_item->>'location_status',''),E' \t\r\n')) code,
    CASE WHEN jsonb_typeof(p_item->'stock') IN ('string','number','boolean') THEN p_item->>'stock'
      WHEN jsonb_typeof(p_item->'stock') IN ('object','array') THEN '[object]' END stock) x
$f$;
REVOKE ALL ON FUNCTION pdc_sales_private.sales_tracker_tile(jsonb) FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_sales_private.sales_tracker_tile(jsonb)','dea0658ecc8ec486568cc6d354a5bce2','r433','r433 (F44): server mirror of the Sales tracker tile rule; Y location codes are Yard Hold');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('navision_y_status_maps_to_yard_hold','F44','Every Navision feed vehicle whose location status starts with Y (YH, YN, YR, YW, any Y code) is in the Sales YH / Yard Hold tile (unless it is at the dealer, Autocare dispatched or has no stock number); 34 tile cases; red on a Y code outside the r427 yard family',
  $chk$WITH ls AS (
  SELECT b.id FROM public.navision_import_batches b WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047'
    AND b.status='applied' AND b.rolled_back_at IS NULL ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
), feed AS (
  SELECT n.normalized_data nd, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) order_key,
   v.stock_number
  FROM public.navision_backend_records n JOIN ls ON ls.id=n.last_seen_batch_id
  LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
  WHERE n.dealer_code='37047' AND n.is_current AND n.record_status='current'
   AND lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi' ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) IN ('yes','true','1')
), item AS (
  SELECT j, upper(btrim(j->>'location_status')) code, pdc_sales_private.sales_tracker_tile(j) tile,
   pdc_sales_private.yard_hold_stage_rank(j->>'location_status',j->>'toyota_status') rank
  FROM (SELECT jsonb_build_object('location_status',coalesce(f.nd->>'navisionLocationStatus',''),
    'toyota_status',coalesce(f.nd->>'navisionSubLocationDescription',f.nd->>'toyotaStatus',''),
    'stock',coalesce(nullif(f.nd->>'batch',''),f.nd->>'stock',f.stock_number,''),
    'autocare_dispatched',coalesce(d.dispatched,false) AND NOT (lower(coalesce(f.nd->>'navisionSubLocationDescription',f.nd->>'toyotaStatus','')) ~ 'delivered.*dealer|at dealer')) j
   FROM feed f LEFT JOIN pdc_sales_private.autocare_dispatches d ON d.dealer_code='37047' AND d.order_key=f.order_key) z
), cases AS (
  SELECT bool_and(pdc_sales_private.sales_tracker_tile(c.j)=c.want) ok, count(*) n,
   string_agg(CASE WHEN pdc_sales_private.sales_tracker_tile(c.j)<>c.want THEN c.j::text||' gave '||pdc_sales_private.sales_tracker_tile(c.j) END,'; ') bad
  FROM (VALUES
   ('{"stock":"S","location_status":"YH","toyota_status":"Vehicle Yard Hold"}'::jsonb,'yardhold'),
   ('{"stock":"S","location_status":"YN","toyota_status":"Waiting PD2"}','yardhold'),
   ('{"stock":"S","location_status":"YN","toyota_status":"Vehicle Delayed"}','yardhold'),
   ('{"stock":"S","location_status":"YR","toyota_status":"Vehicle Waiting For Wholesale"}','yardhold'),
   ('{"stock":"S","location_status":"YW","toyota_status":"Ready For Transport - From TWA"}','yardhold'),
   ('{"stock":"S","location_status":" yw ","toyota_status":"Ready For Transport - From TWA"}','yardhold'),
   ('{"stock":"S","location_status":"YX","toyota_status":"In Transit To WA"}','yardhold'),
   ('{"stock":"S","location_status":"Y","toyota_status":""}','yardhold'),
   ('{"stock":"S","location_status":"YH","toyota_status":"In Transit"}','yardhold'),
   ('{"stock":"S","location_status":"","toyota_status":"Vehicle In Yard Hold"}','yardhold'),
   ('{"stock":"","location_status":"YN","toyota_status":"Waiting PD2"}','unconfirmed'),
   ('{"stock":"TBA","location_status":"YW"}','unconfirmed'),
   ('{"stock":"S","location_status":"YW","autocare_dispatched":true}','autocare'),
   ('{"stock":"S","location_status":"YW","autocare_dispatched":"true"}','yardhold'),
   ('{"stock":"S","location_status":"YH","toyota_status":"Delivered - At Dealer"}','dealer'),
   ('{"stock":"S","location_status":"","toyota_status":"Planned for Production"}','production'),
   ('{"stock":"S","location_status":"","toyota_status":"Line Off Complete"}','production'),
   ('{"stock":"S","location_status":"","toyota_status":"Final Inspection"}','production'),
   ('{"stock":"S","location_status":"","toyota_status":"In Transit To O/S Wharf"}','production'),
   ('{"stock":"S","location_status":"IT","toyota_status":"In Transit To Eastern States"}','production'),
   ('{"stock":"S","location_status":"","toyota_status":"At Overseas Wharf"}','transit'),
   ('{"stock":"S","location_status":"","toyota_status":"Ready For Shipment"}','transit'),
   ('{"stock":"S","location_status":"IT","toyota_status":"In Transit To WA"}','transit'),
   ('{"stock":"S","location_status":"IT","toyota_status":"Vehicle At Wharf"}','transit'),
   ('{"stock":"S","location_status":"OD","toyota_status":"Despatched - From TWA"}','released'),
   ('{"stock":"S","location_status":"OD","toyota_status":"Delivered - At Body Builder"}','released'),
   ('{"stock":"S","location_status":"OD","toyota_status":"Ready For Transport - From Body Builder"}','released'),
   ('{"stock":"S","location_status":"OC","toyota_status":"Vehicle Out on Consignment"}','released'),
   ('{"stock":"S","location_status":"OD","toyota_status":"Delivered - At Dealer"}','dealer'),
   ('{"stock":"S","location_status":"","toyota_status":"Waiting PD2"}','hold'),
   ('{"stock":"S","location_status":"","toyota_status":"Vehicle Waiting For Wholesale"}','hold'),
   ('{"stock":"S","location_status":"","toyota_status":""}','unknown'),
   ('{"stock":0,"location_status":"YH"}','unconfirmed'),
   ('{"stock":13,"location_status":"YH"}','yardhold')) c(j,want)
), y AS (
  SELECT count(*) total, count(*) FILTER (WHERE tile='yardhold') in_tile,
   string_agg(DISTINCT CASE WHEN tile NOT IN ('yardhold','dealer','autocare','unconfirmed') THEN code||' -> '||tile END,', ') wrong,
   string_agg(DISTINCT CASE WHEN tile IN ('dealer','autocare','unconfirmed') THEN code||' -> '||tile END,', ') exempt,
   string_agg(DISTINCT CASE WHEN rank<2 OR code !~ '^Y[A-Z]$' THEN code END,', ') outside_r427,
   (SELECT string_agg(code||' '||n,', ' ORDER BY code) FROM (SELECT code,count(*) n FROM item WHERE code LIKE 'Y%' GROUP BY code) q) by_code
  FROM item WHERE code LIKE 'Y%'
), tiles AS (
  SELECT string_agg(tile||' '||n,', ' ORDER BY tile) t FROM (SELECT tile,count(*) n FROM item GROUP BY tile) q
)
SELECT coalesce((SELECT ok FROM cases),false) AND (SELECT wrong IS NULL AND outside_r427 IS NULL FROM y) AS ok,
 'tile cases: '||CASE WHEN (SELECT ok FROM cases) THEN 'all '||(SELECT n FROM cases)||' right' ELSE 'WRONG for '||coalesce((SELECT bad FROM cases),'?') END
 ||'; Navision Y-status feed vehicles: '||(SELECT total FROM y)||' ('||coalesce((SELECT by_code FROM y),'none')||'), in YH / Yard Hold: '||(SELECT in_tile FROM y)
 ||'; Y vehicles in another tile: '||coalesce((SELECT wrong FROM y),'none')
 ||'; Y vehicles shown as dealer, Autocare or awaiting stock instead: '||coalesce((SELECT exempt FROM y),'none')
 ||'; Y codes outside the r427 yard family: '||coalesce((SELECT outside_r427 FROM y),'none')
 ||'; feed tiles: '||coalesce((SELECT t FROM tiles),'none') AS detail
$chk$,true,231,'r433');

DO $g$ BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('pdc_sales_private.sales_tracker_tile(jsonb)') AND md5(p.prosrc)='dea0658ecc8ec486568cc6d354a5bce2' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog')<>1 THEN RAISE EXCEPTION 'r433: sales_tracker_tile did not land as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='navision_y_status_maps_to_yard_hold' AND added_in='r433')<>'13a9f786621910cc3ea3f64a9ce3f5bc' THEN RAISE EXCEPTION 'r433: check did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r433: clock tick changed'; END IF;
END $g$;
