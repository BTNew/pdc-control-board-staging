-- r394: Build / Tint / Tray ticks follow the sales export PO lines only (Craig, 20 Oct 16:31). Staging only.
-- * Grey: no line in that group. Green: every line has a real PO (^PO\d+$) or C&S ONLY / SELL ONLY / NO UPDATE.
--   Flashing red: any line has no PO raised (the r392 in-house exemption is removed). Amber review: unrecognised PO text.
-- * Manual Completed / Not required / Orders raised (incl. tray "ordered") no longer change what is shown.
-- * The two sales ordering RPCs (which only ever handled tint/build/tray) now refuse every write.
--   Stored ordering_progress values are not modified. No table, import, vehicle, PMB or email change.
DO $guard$
DECLARE live jsonb;
BEGIN
  SELECT jsonb_object_agg(p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))) INTO live FROM pg_proc p
   WHERE p.oid IN ('pdc_sales_private.sales_accessory_tick(jsonb,text)'::regprocedure,'pdc_sales_private.get_accessories()'::regprocedure,
     'pdc_sales_private.set_ordering_status(uuid,text,text,integer)'::regprocedure,'pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)'::regprocedure);
  IF live IS DISTINCT FROM '{"pdc_sales_private.get_accessories()": "b2bd395ec0bd313fdeb5e7386316c842", "pdc_sales_private.sales_accessory_tick(jsonb,text)": "860014bf30819912b6143463e269d904", "pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)": "c210c07ae0fadb9c238efa83ed6ed4d5", "pdc_sales_private.set_ordering_status(uuid,text,text,integer)": "f18b10ba9b6634083edea276c394dca6"}'::jsonb THEN
    RAISE EXCEPTION 'r394: live functions are not the expected r392-era bodies: %', live;
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION pdc_sales_private.sales_accessory_tick(p_lines jsonb, p_class text)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  WITH l AS (SELECT e FROM jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) e WHERE e->>'line_class'=p_class),
  s AS (SELECT count(*) total,
    count(*) FILTER (WHERE e->>'po_state'='blank') not_raised,
    count(*) FILTER (WHERE e->>'po_state'='other') other,
    count(*) FILTER (WHERE e->>'po_state'='po') po FROM l)
  SELECT jsonb_build_object('state',CASE WHEN total=0 THEN 'grey' WHEN not_raised>0 THEN 'red' WHEN other>0 THEN 'review' ELSE 'green' END,
    'reason',CASE WHEN total=0 THEN 'not_on_quote' WHEN not_raised>0 THEN 'po_not_raised' WHEN other>0 THEN 'unrecognised_po_text'
      WHEN po>0 THEN 'po_raised' ELSE 'no_po_needed' END,
    'lines',total,'not_raised',not_raised,'po_lines',po) FROM s
$f$;

-- Signed-in sales read (scoped exactly like get_builds). Ticks are derived live from the current lines; manual fields are ignored.
CREATE OR REPLACE FUNCTION pdc_sales_private.get_accessories()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog, public, pdc_sales_private AS $f$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
 SELECT pdc_sales_private.board_visibility_source_snapshot(false)->'items',pdc_sales_private.build_stock_counts() INTO current_items,stock_counts;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'tracking_id',e->>'tracking_id','navision_record_id',e->>'navision_record_id','stock',e->>'stock','order',e->>'order','quote',st.quote,
   'source_file',r.file_name,'snapshot_at',st.snapshot_at,'derived',d.ticks,'status_version',st.version,
   'display',jsonb_build_object(
     'tint',jsonb_build_object('state',d.ticks->'tint'->>'state','source','derived','reason',d.ticks->'tint'->>'reason'),
     'build_po',jsonb_build_object('state',d.ticks->'build'->>'state','source','derived','reason',d.ticks->'build'->>'reason'),
     'tray_ordered',jsonb_build_object('state',d.ticks->'tray'->>'state','source','derived','reason',d.ticks->'tray'->>'reason')),
   'lines',d.lines
  ) ORDER BY e->>'stock',e->>'order'),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(current_items) e
 JOIN pdc_sales_private.sales_accessory_vehicle_status st ON st.dealer_code='37047' AND st.order_key=upper(btrim(e->>'order'))
  AND e->>'navision_record_id'=st.navision_record_id::text
 JOIN pdc_sales_private.sales_accessory_receipts r ON r.id=st.receipt_id
 CROSS JOIN LATERAL (
   SELECT pdc_sales_private.sales_accessory_ticks(coalesce(jsonb_agg(jsonb_build_object('line_class',l.line_class,'po_state',l.po_state)),'[]'::jsonb)) ticks,
     coalesce(jsonb_agg(jsonb_build_object('group',l.line_class,'line',l.po_line,'item',l.description,'type',l.txn_type,
       'sublet',l.sub_type,'po',l.po_number,'po_state',l.po_state,'notes',l.notes,'in_house',l.in_house)
       ORDER BY array_position(ARRAY['build','tray','tint','admin'],l.line_class), l.source_row),'[]'::jsonb) lines
   FROM pdc_sales_private.sales_accessory_lines l WHERE l.dealer_code='37047' AND l.order_key=st.order_key AND l.superseded_receipt_id IS NULL) d
 WHERE e->>'salesperson_code' IN ('AW','BG','PM','CW') AND NOT coalesce((e->>'identity_conflict')::boolean,false)
 AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
 AND coalesce((stock_counts->>btrim(e->>'stock'))::integer,0)=1;
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales accessory display exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $f$;

-- Both ordering RPCs only ever accepted tint/build/tray, so both now refuse every caller (all roles).
CREATE OR REPLACE FUNCTION pdc_sales_private.set_ordering_status(p_tracking_id uuid, p_item text, p_status text, p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog, public, pdc_sales_private AS $f$
BEGIN
  RAISE EXCEPTION 'TINT, BUILD and TRAY now follow the sales export PO lines and cannot be changed here.' USING errcode='42501';
END $f$;
CREATE OR REPLACE FUNCTION pdc_sales_private.set_ordering_flag(p_tracking_id uuid, p_flag text, p_checked boolean, p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog, public, pdc_sales_private AS $f$
BEGIN
  RAISE EXCEPTION 'TINT, BUILD and TRAY now follow the sales export PO lines and cannot be changed here.' USING errcode='42501';
END $f$;
