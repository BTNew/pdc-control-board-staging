-- Undo r528 (F142). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Drops the Karratha accessory tables and restores get_accessories to the r495 body.
-- Pin count 241 back to 236. Leaves the r527 / F141 check (sort 308) in place.
-- Broome import_sales_accessories_20261020 is not changed.
-- Removes any Karratha accessory receipts, lines and status written by this release.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r528 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r528 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM '46d4b464c5c1800c8ada245fb2d33bd3' THEN RAISE EXCEPTION 'r528 undo: Broome import changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)')) IS DISTINCT FROM 'c70dc4234952dfb58cbc022c98bcecdb' THEN RAISE EXCEPTION 'r528 undo: Karratha import is not the r528 body'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r528 undo: pin count is not 241'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_sales_private.get_accessories()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
 -- r495 (F108): the build sheet and Sales Results accessory feeds exist for Broome Toyota (37047) only.
 IF ctx->>'dealer_code' IS DISTINCT FROM '37047' THEN RETURN jsonb_build_object('context',ctx,'items','[]'::jsonb,'checked_at',now()); END IF;
 SELECT pdc_sales_private.board_visibility_source_snapshot(false)->'items',pdc_sales_private.build_stock_counts() INTO current_items,stock_counts;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'tracking_id',e->>'tracking_id','navision_record_id',e->>'navision_record_id','stock',e->>'stock','order',e->>'order','quote',st.quote,
   'source_file',r.file_name,'snapshot_at',st.snapshot_at,'derived',d.ticks,'status_version',st.version,
   'display',jsonb_build_object(
     'tint',jsonb_build_object('state',d.ticks->'tint'->>'state','source','derived','reason',d.ticks->'tint'->>'reason'),
     'build_po',jsonb_build_object('state',d.ticks->'build'->>'state','source','derived','reason',d.ticks->'build'->>'reason'),
     'tray_ordered',jsonb_build_object('state',d.ticks->'tray'->>'state','source','derived','reason',d.ticks->'tray'->>'reason')),
   'lines',d.lines,
   -- r418: yard hold delay. at_or_past_yard_hold lifts every delay; delay_lifted_lines flags the order row.
   -- r427: yard hold is read from the whole stage order (board location, PMB dates and the Navision/Toyota stage).
   'at_or_past_yard_hold',pdc_sales_private.accessory_yard_hold_reached(e),'delay_lifted_lines',d.lifted
  ) ORDER BY e->>'stock',e->>'order'),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(current_items) e
 JOIN pdc_sales_private.sales_accessory_vehicle_status st ON st.dealer_code='37047' AND st.order_key=upper(btrim(e->>'order'))
  AND e->>'navision_record_id'=st.navision_record_id::text
 JOIN pdc_sales_private.sales_accessory_receipts r ON r.id=st.receipt_id
 CROSS JOIN LATERAL (
   SELECT pdc_sales_private.sales_accessory_ticks_delayed(coalesce(jsonb_agg(jsonb_build_object('line_class',l.line_class,'po_state',l.po_state,'delay_active',x.delay='delayed')),'[]'::jsonb)) ticks,
     coalesce(jsonb_agg(jsonb_build_object('group',l.line_class,'line',l.po_line,'item',l.description,'type',l.txn_type,
       'sublet',l.sub_type,'po',l.po_number,'po_state',l.po_state,'notes',l.notes,'in_house',l.in_house,'line_key',l.line_key,'delay',x.delay)
       ORDER BY array_position(ARRAY['build','tray','tint','admin'],l.line_class), l.source_row),'[]'::jsonb) lines,
     count(*) FILTER (WHERE x.delay='lifted') lifted
   FROM pdc_sales_private.sales_accessory_lines l
   LEFT JOIN pdc_sales_private.sales_accessory_line_delays dl ON dl.dealer_code=l.dealer_code AND dl.order_key=l.order_key AND dl.line_key=l.line_key
   CROSS JOIN LATERAL (SELECT CASE WHEN dl.line_key IS NULL OR l.po_state<>'blank' THEN 'none'
     WHEN pdc_sales_private.accessory_yard_hold_reached(e) THEN 'lifted' ELSE 'delayed' END delay) x
   WHERE l.dealer_code='37047' AND l.order_key=st.order_key AND l.superseded_receipt_id IS NULL) d
 WHERE e->>'salesperson_code' IN ('AW','BG','PM','CW') AND NOT coalesce((e->>'identity_conflict')::boolean,false)
 AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
 AND coalesce((stock_counts->>btrim(e->>'stock'))::integer,0)=1;
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales accessory display exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $function$;


DROP FUNCTION pdc_sales_private.get_karratha_sales_accessories_528();
DROP FUNCTION pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text);
DROP FUNCTION pdc_sales_private.karratha_sales_accessory_plan_528(jsonb,timestamptz);
DROP FUNCTION pdc_sales_private.karratha_sales_accessory_candidates_528();
DROP FUNCTION pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb);
DROP TABLE pdc_sales_private.karratha_sales_accessory_lines;
DROP TABLE pdc_sales_private.karratha_sales_accessory_vehicle_status;
DROP TABLE pdc_sales_private.karratha_sales_accessory_receipts;

DELETE FROM pdc_ops.expected_function_md5 WHERE signature IN (
 'pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)',
 'pdc_sales_private.karratha_sales_accessory_candidates_528()',
 'pdc_sales_private.karratha_sales_accessory_plan_528(jsonb,timestamp with time zone)',
 'pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)',
 'pdc_sales_private.get_karratha_sales_accessories_528()');
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='2f7f060cdaca01cc2763a15b921debf8', release='r495',
 note='r495 (F108): Sales branch (Broome / Karratha) aware (was 6249e21543ac7caf096e3175c81406c4 r427)', updated_at=now()
 WHERE signature='pdc_sales_private.get_accessories()';
DELETE FROM pdc_ops.regression_checks WHERE check_name='karratha_sales_accessories_528' AND added_in='r528' AND fault_id='F142' AND sort_order=309;

DO $v$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>236 THEN RAISE EXCEPTION 'r528 undo: pin count is not 236'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_accessories()')) IS DISTINCT FROM '2f7f060cdaca01cc2763a15b921debf8' THEN RAISE EXCEPTION 'r528 undo: get_accessories was not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM '46d4b464c5c1800c8ada245fb2d33bd3' THEN RAISE EXCEPTION 'r528 undo: Broome import changed'; END IF;
 IF to_regclass('pdc_sales_private.karratha_sales_accessory_receipts') IS NOT NULL THEN RAISE EXCEPTION 'r528 undo: Karratha receipt table remains'; END IF;
 IF to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)') IS NOT NULL THEN RAISE EXCEPTION 'r528 undo: Karratha import remains'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='qa_bay_technician_527' AND fault_id='F141' AND sort_order=308 AND added_in='r527') THEN RAISE EXCEPTION 'r528 undo: r527 check missing'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='karratha_sales_accessories_528' OR fault_id='F142' OR added_in='r528') THEN RAISE EXCEPTION 'r528 undo: F142 check remains'; END IF;
END $v$;
