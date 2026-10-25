-- Undo r530 (F144). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Restores the r528 plan and Karratha read. GP######## goes back to unrecognised PO text.
-- Pin count stays 241. Leaves the r528 / F142 check (sort 309) in place.
-- Broome import_sales_accessories_20261020 and the Karratha importer body are not changed.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r530 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r530 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r530 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM '46d4b464c5c1800c8ada245fb2d33bd3' THEN RAISE EXCEPTION 'r530 undo: Broome import changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)')) IS DISTINCT FROM 'c70dc4234952dfb58cbc022c98bcecdb' THEN RAISE EXCEPTION 'r530 undo: Karratha import changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.karratha_sales_accessory_plan_528(jsonb,timestamptz)')) IS DISTINCT FROM '694b7a7c95b7af1a46040b500dcbf40f' THEN RAISE EXCEPTION 'r530 undo: plan is not the r530 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_karratha_sales_accessories_528()')) IS DISTINCT FROM '0e5f6c5e90b6cd91f631671c065fb9c7' THEN RAISE EXCEPTION 'r530 undo: read is not the r530 body'; END IF;
END $g$;

DROP TRIGGER IF EXISTS karratha_sales_accessory_po_touch_530 ON pdc_sales_private.karratha_sales_accessory_lines;

UPDATE pdc_sales_private.karratha_sales_accessory_lines
SET po_state = pdc_sales_private.sales_accessory_po_state(po_number)
WHERE dealer_code = '14450';

UPDATE pdc_sales_private.karratha_sales_accessory_vehicle_status st
SET build_state = x.ticks->'build'->>'state',
    tint_state = x.ticks->'tint'->>'state',
    tray_state = x.ticks->'tray'->>'state',
    ticks = x.ticks,
    updated_at = now()
FROM (
  SELECT st2.dealer_code, st2.order_key,
    pdc_sales_private.sales_accessory_ticks(coalesce(jsonb_agg(jsonb_build_object(
      'line_class', l.line_class, 'po_state', l.po_state, 'in_house', l.in_house)) FILTER (WHERE l.line_key IS NOT NULL), '[]'::jsonb)) ticks
  FROM pdc_sales_private.karratha_sales_accessory_vehicle_status st2
  LEFT JOIN pdc_sales_private.karratha_sales_accessory_lines l
    ON l.dealer_code = st2.dealer_code AND l.order_key = st2.order_key AND l.superseded_receipt_id IS NULL
  WHERE st2.dealer_code = '14450'
  GROUP BY st2.dealer_code, st2.order_key
) x
WHERE st.dealer_code = x.dealer_code AND st.order_key = x.order_key AND st.dealer_code = '14450';

CREATE OR REPLACE FUNCTION pdc_sales_private.karratha_sales_accessory_plan_528(p_lines jsonb, p_snapshot timestamptz)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'pdc_sales_private'
AS $k528p$
DECLARE cand jsonb := pdc_sales_private.karratha_sales_accessory_candidates_528(); stocks jsonb; plan jsonb;
BEGIN
  WITH file_stocks AS (
    SELECT e->>'stock' stock, min(e->>'quote') quote,
      coalesce(jsonb_agg(e ORDER BY (e->>'source_row')::integer) FILTER (WHERE e->>'line_class'<>'empty'),'[]'::jsonb) lines,
      count(*) FILTER (WHERE e->>'line_class'='empty') empty_rows
    FROM jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) e GROUP BY e->>'stock'
  ), matched AS (
    SELECT s.*,
      coalesce(cand->s.stock, CASE WHEN s.stock ~ '^\d{1,7}$' THEN cand->lpad(s.stock,8,'0') END, '[]'::jsonb) all_c
    FROM file_stocks s
  ), judged AS (
    SELECT m.*, v.visible_c,
      CASE
        WHEN jsonb_array_length(v.visible_c)=0 AND EXISTS (SELECT 1 FROM jsonb_array_elements(m.all_c) c WHERE (c->>'linked_vehicle_deleted')::boolean) THEN 'linked_pdc_vehicle_deleted'
        WHEN jsonb_array_length(v.visible_c)=0 AND jsonb_array_length(m.all_c)>0 THEN 'not_visible_sales_vehicle'
        WHEN jsonb_array_length(v.visible_c)=0 THEN 'not_on_current_karratha_navision'
        WHEN jsonb_array_length(v.visible_c)>1 THEN 'duplicate_current_stock'
        WHEN (v.visible_c->0->>'identity_conflict')::boolean THEN 'identity_conflict'
        WHEN coalesce(v.visible_c->0->>'order_key','')='' THEN 'missing_current_order'
        WHEN v.visible_c->0->>'source_current' IS DISTINCT FROM 'true' THEN 'source_not_current'
        ELSE NULL END unmatched_reason
    FROM matched m
    CROSS JOIN LATERAL (SELECT coalesce(jsonb_agg(c),'[]'::jsonb) visible_c FROM jsonb_array_elements(m.all_c) c WHERE (c->>'visible')::boolean) v
  ), decided AS (
    SELECT j.*, st.snapshot_at status_snapshot, st.version status_version,
      CASE WHEN j.unmatched_reason IS NULL AND st.snapshot_at > p_snapshot THEN 'older_than_current_snapshot' ELSE j.unmatched_reason END reason,
      (SELECT coalesce(jsonb_agg(l.line_key ORDER BY l.line_key),'[]'::jsonb) FROM pdc_sales_private.karratha_sales_accessory_lines l
        WHERE l.dealer_code='14450' AND l.order_key=j.visible_c->0->>'order_key' AND l.superseded_receipt_id IS NULL) current_keys
    FROM judged j
    LEFT JOIN pdc_sales_private.karratha_sales_accessory_vehicle_status st ON st.dealer_code='14450' AND st.order_key=j.visible_c->0->>'order_key'
  )
  SELECT jsonb_agg(jsonb_build_object('stock',d.stock,'quote',d.quote,'lines',jsonb_array_length(d.lines),'empty_rows',d.empty_rows,
      'match',CASE WHEN d.reason IS NULL THEN 'matched' ELSE 'unmatched' END,'reason',d.reason,
      'tracking_id',CASE WHEN d.reason IS NULL THEN d.visible_c->0->>'tracking_id' END,
      'navision_record_id',CASE WHEN d.reason IS NULL THEN d.visible_c->0->>'navision_record_id' END,
      'order_key',CASE WHEN d.reason IS NULL THEN d.visible_c->0->>'order_key' END,
      'new_keys',(SELECT coalesce(jsonb_agg(e->>'line_key' ORDER BY e->>'line_key'),'[]'::jsonb) FROM jsonb_array_elements(d.lines) e),
      'current_keys',CASE WHEN d.reason IS NULL THEN d.current_keys ELSE '[]'::jsonb END,
      'status_version',CASE WHEN d.reason IS NULL THEN d.status_version END,
      'ticks',pdc_sales_private.sales_accessory_ticks(d.lines)) ORDER BY d.stock) INTO stocks
  FROM decided d;
  stocks := coalesce(stocks,'[]'::jsonb);
  plan := jsonb_build_object('dealer_code','14450','snapshot_at',p_snapshot,'stocks',stocks,
    'vehicles_created',0,'jobs_created',0,'bookings_created',0);
  RETURN plan || jsonb_build_object('preview_hash',encode(sha256(convert_to(plan::text,'UTF8')),'hex'));
END $k528p$;

CREATE OR REPLACE FUNCTION pdc_sales_private.get_karratha_sales_accessories_528()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $k528r$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
  IF ctx->>'dealer_code' IS DISTINCT FROM '14450' THEN
    RETURN jsonb_build_object('context',ctx,'items','[]'::jsonb,'checked_at',now());
  END IF;
  SELECT pdc_sales_private.board_visibility_source_snapshot(false)->'items' INTO current_items;
  WITH latest AS MATERIALIZED (
    SELECT b.id FROM public.navision_import_batches b WHERE b.source_system='microsoft_navision' AND b.dealer_code='14450'
      AND b.status='applied' AND b.rolled_back_at IS NULL ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
  ), stocks AS (
    SELECT upper(btrim(coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',''))) stock
    FROM public.navision_backend_records n JOIN latest b ON b.id=n.last_seen_batch_id
    WHERE n.source_system='microsoft_navision' AND n.dealer_code='14450' AND n.is_current AND n.record_status='current'
      AND lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi' ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) IN ('yes','true','1')
      AND NOT EXISTS (SELECT 1 FROM pdc_sales_private.vehicle_visibility h WHERE h.hidden AND (h.tracking_id=n.id OR (h.dealer_code='14450'
        AND h.order_key=upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))))))
  )
  SELECT coalesce(jsonb_object_agg(s.stock,s.matches),'{}'::jsonb) INTO stock_counts FROM (SELECT stock,count(*) matches FROM stocks WHERE stock<>'' GROUP BY stock) s;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'tracking_id',e->>'tracking_id','navision_record_id',e->>'navision_record_id','stock',e->>'stock','order',e->>'order','quote',st.quote,
    'source_file',r.file_name,'snapshot_at',st.snapshot_at,'derived',d.ticks,'status_version',st.version,
    'display',jsonb_build_object(
      'tint',jsonb_build_object('state',d.ticks->'tint'->>'state','source','derived','reason',d.ticks->'tint'->>'reason'),
      'build_po',jsonb_build_object('state',d.ticks->'build'->>'state','source','derived','reason',d.ticks->'build'->>'reason'),
      'tray_ordered',jsonb_build_object('state',d.ticks->'tray'->>'state','source','derived','reason',d.ticks->'tray'->>'reason')),
    'lines',d.lines,
    'at_or_past_yard_hold',pdc_sales_private.accessory_yard_hold_reached(e),'delay_lifted_lines',0
  ) ORDER BY e->>'stock',e->>'order'),'[]'::jsonb) INTO result
  FROM jsonb_array_elements(current_items) e
  JOIN pdc_sales_private.karratha_sales_accessory_vehicle_status st ON st.dealer_code='14450' AND st.order_key=upper(btrim(e->>'order'))
   AND e->>'navision_record_id'=st.navision_record_id::text
  JOIN pdc_sales_private.karratha_sales_accessory_receipts r ON r.id=st.receipt_id AND r.dealer_code='14450'
  CROSS JOIN LATERAL (
    SELECT pdc_sales_private.sales_accessory_ticks(coalesce(jsonb_agg(jsonb_build_object('line_class',l.line_class,'po_state',l.po_state,'in_house',l.in_house)),'[]'::jsonb)) ticks,
      coalesce(jsonb_agg(jsonb_build_object('group',l.line_class,'line',l.po_line,'item',l.description,'type',l.txn_type,
        'sublet',l.sub_type,'po',l.po_number,'po_state',l.po_state,'notes',l.notes,'in_house',l.in_house,'line_key',l.line_key,'delay','none')
        ORDER BY array_position(ARRAY['build','tray','tint','admin'],l.line_class), l.source_row),'[]'::jsonb) lines
    FROM pdc_sales_private.karratha_sales_accessory_lines l
    WHERE l.dealer_code='14450' AND l.order_key=st.order_key AND l.superseded_receipt_id IS NULL) d
  WHERE e->>'salesperson_code' IN (SELECT upper(sp.code) FROM pdc_sales_private.salesperson_branches mb JOIN public.salespeople sp ON sp.id=mb.salesperson_id WHERE mb.dealer_code='14450' AND mb.enabled AND sp.active)
   AND NOT coalesce((e->>'identity_conflict')::boolean,false)
   AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
   AND coalesce((stock_counts->>upper(btrim(e->>'stock')))::integer,0)=1;
  IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales accessory display exceeds supported size'; END IF;
  RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $k528r$;

DROP FUNCTION pdc_sales_private.karratha_sales_accessory_po_touch_530();
DROP FUNCTION pdc_sales_private.karratha_sales_accessory_po_state_530(text);

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='fd4caaffec31dcb70f47756676d40d37', release='r528',
 note='r528 (F142): match report, no vehicle insert', updated_at=now()
 WHERE signature='pdc_sales_private.karratha_sales_accessory_plan_528(jsonb,timestamp with time zone)'
   AND prosrc_md5='694b7a7c95b7af1a46040b500dcbf40f';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='faab38bf242ef572522dc4c3bf32285f', release='r528',
 note='r528 (F142): Karratha Sales accessory read', updated_at=now()
 WHERE signature='pdc_sales_private.get_karratha_sales_accessories_528()'
   AND prosrc_md5='0e5f6c5e90b6cd91f631671c065fb9c7';

DELETE FROM pdc_ops.regression_checks WHERE check_name='karratha_gp_po_530' AND added_in='r530' AND fault_id='F144' AND sort_order=311;

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r530 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.karratha_sales_accessory_plan_528(jsonb,timestamptz)')) IS DISTINCT FROM 'fd4caaffec31dcb70f47756676d40d37' THEN RAISE EXCEPTION 'r530 undo: plan not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_karratha_sales_accessories_528()')) IS DISTINCT FROM 'faab38bf242ef572522dc4c3bf32285f' THEN RAISE EXCEPTION 'r530 undo: read not restored'; END IF;
 IF to_regprocedure('pdc_sales_private.karratha_sales_accessory_po_state_530(text)') IS NOT NULL THEN RAISE EXCEPTION 'r530 undo: po state function remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='karratha_gp_po_530' OR fault_id='F144' OR sort_order=311) THEN RAISE EXCEPTION 'r530 undo: check remains'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='karratha_sales_accessories_528' AND fault_id='F142' AND sort_order=309) THEN RAISE EXCEPTION 'r530 undo: r528 check missing'; END IF;
END $p$;
