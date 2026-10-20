-- r394 undo (staging cdsmnqxtyyoeoznmbidd only). Restores the exact r392-era bodies of the four replaced functions
-- (captured with pg_get_functiondef before apply). Live bodies were LF-only; any body that had CR is re-expanded to CRLF.
-- CREATE OR REPLACE keeps the existing grants. No data is touched.
DO $undo$
DECLARE live jsonb;
BEGIN
  SELECT jsonb_object_agg(p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))) INTO live FROM pg_proc p
   WHERE p.oid IN ('pdc_sales_private.sales_accessory_tick(jsonb,text)'::regprocedure,'pdc_sales_private.get_accessories()'::regprocedure,
     'pdc_sales_private.set_ordering_status(uuid,text,text,integer)'::regprocedure,'pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)'::regprocedure);
  IF live IS DISTINCT FROM '{"pdc_sales_private.get_accessories()": "797dafc537b8849d59e84ea05ac1fe68", "pdc_sales_private.sales_accessory_tick(jsonb,text)": "c71bbc99943125e738092cbb2d3fe4bd", "pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)": "2b310c3ce34f59850be4d71ab25c503b", "pdc_sales_private.set_ordering_status(uuid,text,text,integer)": "30ad0d2fa6fbd8246e879c3526297452"}'::jsonb THEN RAISE EXCEPTION 'r394 undo: live bodies are not the r394 bodies: %', live; END IF;
  EXECUTE $def$CREATE OR REPLACE FUNCTION pdc_sales_private.get_accessories()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
 SELECT pdc_sales_private.board_visibility_source_snapshot(false)->'items',pdc_sales_private.build_stock_counts() INTO current_items,stock_counts;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'tracking_id',e->>'tracking_id','navision_record_id',e->>'navision_record_id','stock',e->>'stock','order',e->>'order','quote',st.quote,
   'source_file',r.file_name,'snapshot_at',st.snapshot_at,'derived',st.ticks,'status_version',st.version,
   'display',(SELECT jsonb_object_agg(k.key, CASE
       WHEN coalesce((to_jsonb(op)->>k.done)::boolean,false) THEN jsonb_build_object('state','completed','source','manual')
       WHEN coalesce((to_jsonb(op)->>k.nr)::boolean,false) THEN jsonb_build_object('state','not_needed','source','manual')
       WHEN k.key='tray_ordered' AND coalesce(op.tray_ordered,false) THEN jsonb_build_object('state','green','source','manual_ordered')
       ELSE jsonb_build_object('state',st.ticks->k.g->>'state','source','derived','reason',st.ticks->k.g->>'reason') END)
     FROM (VALUES ('tint','tint','tint_complete','tint_not_required'),('build_po','build','build_complete','build_not_required'),
       ('tray_ordered','tray','tray_complete','tray_not_required')) k(key,g,done,nr)),
   'lines',(SELECT coalesce(jsonb_agg(jsonb_build_object('group',l.line_class,'line',l.po_line,'item',l.description,'type',l.txn_type,
       'sublet',l.sub_type,'po',l.po_number,'po_state',l.po_state,'notes',l.notes,'in_house',l.in_house)
       ORDER BY array_position(ARRAY['build','tray','tint','admin'],l.line_class), l.source_row),'[]'::jsonb)
     FROM pdc_sales_private.sales_accessory_lines l WHERE l.dealer_code='37047' AND l.order_key=st.order_key AND l.superseded_receipt_id IS NULL)
  ) ORDER BY e->>'stock',e->>'order'),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(current_items) e
 JOIN pdc_sales_private.sales_accessory_vehicle_status st ON st.dealer_code='37047' AND st.order_key=upper(btrim(e->>'order'))
  AND e->>'navision_record_id'=st.navision_record_id::text
 JOIN pdc_sales_private.sales_accessory_receipts r ON r.id=st.receipt_id
 LEFT JOIN pdc_sales_private.ordering_progress op ON op.tracking_id=(e->>'tracking_id')::uuid
 WHERE e->>'salesperson_code' IN ('AW','BG','PM','CW') AND NOT coalesce((e->>'identity_conflict')::boolean,false)
 AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
 AND coalesce((stock_counts->>btrim(e->>'stock'))::integer,0)=1;
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales accessory display exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $function$
$def$;
  EXECUTE $def$CREATE OR REPLACE FUNCTION pdc_sales_private.sales_accessory_tick(p_lines jsonb, p_class text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  WITH l AS (SELECT e FROM jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) e WHERE e->>'line_class'=p_class),
  s AS (SELECT count(*) total,
    count(*) FILTER (WHERE e->>'po_state'='blank' AND NOT (p_class='build' AND (e->>'in_house')::boolean)) not_raised,
    count(*) FILTER (WHERE e->>'po_state'='blank' AND p_class='build' AND (e->>'in_house')::boolean) in_house_blank,
    count(*) FILTER (WHERE e->>'po_state'='other') other,
    count(*) FILTER (WHERE e->>'po_state'='po') po FROM l)
  SELECT jsonb_build_object('state',CASE WHEN total=0 THEN 'grey' WHEN not_raised>0 THEN 'red' WHEN other>0 THEN 'review' ELSE 'green' END,
    'reason',CASE WHEN total=0 THEN 'not_on_quote' WHEN not_raised>0 THEN 'po_not_raised' WHEN other>0 THEN 'unrecognised_po_text'
      WHEN po>0 THEN 'po_raised' ELSE 'no_po_needed' END,
    'lines',total,'not_raised',not_raised,'in_house_without_po',in_house_blank,'po_lines',po) FROM s
$function$
$def$;
  EXECUTE $def$CREATE OR REPLACE FUNCTION pdc_sales_private.set_ordering_flag(p_tracking_id uuid, p_flag text, p_checked boolean, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE base jsonb:=pdc_sales_private.snapshot(); target jsonb; result jsonb;
BEGIN
 -- The existing approved-account snapshot enforces dealer, current salesperson,
 -- manual assignments, disabled account/scope and deletion authority on every write.
 SELECT e INTO target FROM jsonb_array_elements(base->'items') e WHERE e->>'tracking_id'=p_tracking_id::text;
 IF target IS NULL OR coalesce((target->>'identity_conflict')::boolean,false) THEN RAISE EXCEPTION 'This order is not available for your ordering checklist' USING errcode='42501'; END IF;
 IF p_flag IS NULL OR p_flag NOT IN ('tint','build_po','build_complete','tray_ordered','tray_complete') OR p_checked IS NULL THEN RAISE EXCEPTION 'Choose one valid ordering checkbox'; END IF;
 IF p_expected_version IS NULL OR p_expected_version<0 OR coalesce((SELECT version FROM pdc_sales_private.ordering_progress WHERE tracking_id=p_tracking_id),0)<>p_expected_version THEN RAISE EXCEPTION 'Checklist changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 INSERT INTO pdc_sales_private.ordering_progress AS current(
  tracking_id,tint,build_po,build_complete,tray_ordered,tray_complete,updated_by)
 VALUES(p_tracking_id,
  CASE WHEN p_flag='tint' THEN p_checked ELSE false END,
  CASE WHEN p_flag='build_po' THEN p_checked ELSE false END,
  CASE WHEN p_flag='build_complete' THEN p_checked ELSE false END,
  CASE WHEN p_flag='tray_ordered' THEN p_checked ELSE false END,
  CASE WHEN p_flag='tray_complete' THEN p_checked ELSE false END,auth.uid())
 ON CONFLICT(tracking_id) DO UPDATE SET
  tint=CASE WHEN p_flag='tint' THEN p_checked ELSE current.tint END,
  tint_complete=CASE WHEN p_flag='tint' AND NOT p_checked THEN false ELSE current.tint_complete END,
  build_po=CASE WHEN p_flag='build_po' THEN p_checked ELSE current.build_po END,
  build_complete=CASE WHEN p_flag='build_complete' THEN p_checked ELSE current.build_complete END,
  tray_ordered=CASE WHEN p_flag='tray_ordered' THEN p_checked ELSE current.tray_ordered END,
  tray_complete=CASE WHEN p_flag='tray_complete' THEN p_checked ELSE current.tray_complete END,
  tint_not_required=CASE WHEN p_flag='tint' THEN false ELSE current.tint_not_required END,
  build_not_required=CASE WHEN p_flag IN ('build_po','build_complete') THEN false ELSE current.build_not_required END,
  tray_not_required=CASE WHEN p_flag IN ('tray_ordered','tray_complete') THEN false ELSE current.tray_not_required END,
  version=current.version+1,updated_at=now(),updated_by=auth.uid()
 WHERE current.version=p_expected_version
 RETURNING jsonb_build_object('tracking_id',tracking_id,'tint_complete',tint_complete,'tint',tint,'build_po',build_po,'build_complete',build_complete,
  'tray_ordered',tray_ordered,'tray_complete',tray_complete,'tint_not_required',tint_not_required,'build_not_required',build_not_required,'tray_not_required',tray_not_required,'ordering_version',version,'ordering_updated_at',updated_at) INTO result;
 IF result IS NULL THEN RAISE EXCEPTION 'Checklist changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 RETURN result;
END $function$
$def$;
  EXECUTE $def$CREATE OR REPLACE FUNCTION pdc_sales_private.set_ordering_status(p_tracking_id uuid, p_item text, p_status text, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE base jsonb:=pdc_sales_private.snapshot(); target jsonb; result jsonb; raised boolean; finished boolean; not_required boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 SELECT e INTO target FROM jsonb_array_elements(base->'items') e WHERE e->>'tracking_id'=p_tracking_id::text;
 IF target IS NULL OR coalesce((target->>'identity_conflict')::boolean,false) THEN RAISE EXCEPTION 'This order is not available for your ordering status' USING errcode='42501'; END IF;
 IF p_item IS NULL OR p_item NOT IN ('tint','build','tray') OR p_status IS NULL OR p_status NOT IN ('not_decided','not_needed','orders_raised','completed') THEN RAISE EXCEPTION 'Choose TINT, BUILD or TRAY and one valid ordering status'; END IF;
 IF p_expected_version IS NULL OR p_expected_version<0 OR coalesce((SELECT version FROM pdc_sales_private.ordering_progress WHERE tracking_id=p_tracking_id),0)<>p_expected_version THEN RAISE EXCEPTION 'Ordering status changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 raised:=p_status IN ('orders_raised','completed'); finished:=p_status='completed'; not_required:=p_status='not_needed';
 INSERT INTO pdc_sales_private.ordering_progress AS current(tracking_id,tint,tint_complete,build_po,build_complete,tray_ordered,tray_complete,tint_not_required,build_not_required,tray_not_required,updated_by)
 VALUES(p_tracking_id,p_item='tint' AND raised,p_item='tint' AND finished,p_item='build' AND raised,p_item='build' AND finished,p_item='tray' AND raised,p_item='tray' AND finished,p_item='tint' AND not_required,p_item='build' AND not_required,p_item='tray' AND not_required,auth.uid())
 ON CONFLICT(tracking_id) DO UPDATE SET
 tint=CASE WHEN p_item='tint' THEN raised ELSE current.tint END,
 tint_complete=CASE WHEN p_item='tint' THEN finished ELSE current.tint_complete END,
 build_po=CASE WHEN p_item='build' THEN raised ELSE current.build_po END,
 build_complete=CASE WHEN p_item='build' THEN finished ELSE current.build_complete END,
 tray_ordered=CASE WHEN p_item='tray' THEN raised ELSE current.tray_ordered END,
 tray_complete=CASE WHEN p_item='tray' THEN finished ELSE current.tray_complete END,
 tint_not_required=CASE WHEN p_item='tint' THEN not_required ELSE current.tint_not_required END,
 build_not_required=CASE WHEN p_item='build' THEN not_required ELSE current.build_not_required END,
 tray_not_required=CASE WHEN p_item='tray' THEN not_required ELSE current.tray_not_required END,
 version=current.version+1,updated_at=now(),updated_by=auth.uid()
 WHERE current.version=p_expected_version
 RETURNING jsonb_build_object('tracking_id',tracking_id,'tint',tint,'tint_complete',tint_complete,'build_po',build_po,'build_complete',build_complete,'tray_ordered',tray_ordered,'tray_complete',tray_complete,'tint_not_required',tint_not_required,'build_not_required',build_not_required,'tray_not_required',tray_not_required,'ordering_version',version,'ordering_updated_at',updated_at) INTO result;
 IF result IS NULL THEN RAISE EXCEPTION 'Ordering status changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 RETURN result;
END $function$
$def$;
  SELECT jsonb_object_agg(p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))) INTO live FROM pg_proc p
   WHERE p.oid IN ('pdc_sales_private.sales_accessory_tick(jsonb,text)'::regprocedure,'pdc_sales_private.get_accessories()'::regprocedure,
     'pdc_sales_private.set_ordering_status(uuid,text,text,integer)'::regprocedure,'pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)'::regprocedure);
  IF live IS DISTINCT FROM '{"pdc_sales_private.get_accessories()": "b2bd395ec0bd313fdeb5e7386316c842", "pdc_sales_private.sales_accessory_tick(jsonb,text)": "860014bf30819912b6143463e269d904", "pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)": "c210c07ae0fadb9c238efa83ed6ed4d5", "pdc_sales_private.set_ordering_status(uuid,text,text,integer)": "f18b10ba9b6634083edea276c394dca6"}'::jsonb THEN RAISE EXCEPTION 'r394 undo: restored md5s differ: %', live; END IF;
END $undo$;
