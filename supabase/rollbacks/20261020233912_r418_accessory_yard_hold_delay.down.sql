-- r418 undo: restores get_accessories byte-exact (md5 49f6feab0ef97e1f515cf9d8c5de4fd9) and its r394 pin, drops the delay RPCs,
-- helpers and table (stored delays are copied into crm_audit as kind accessory_delay_undo first), removes the r418 pins and check.
-- Run between :02 and :45 with lock_timeout 2s. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r418 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r418 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r418 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r418 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('pdc_sales_private.sales_accessory_ticks(jsonb)','c831c3b42b906d982ff9e6344f23a61d'),
  ('pdc_sales_private.sales_accessory_tick(jsonb,text)','d428d8808dd3770ed3001ce2be6e9e4f'),
  ('pdc_sales_private.visibility_source_snapshot(boolean)','c51d473d947b4dea1ef457bb57f6d16d'),
  ('pdc_sales_private.board_visibility_source_snapshot(boolean)','2cdd2ec2581551363d39d055e2cf1397'),
  ('pdc_sales_private.crm_context()','ded7229678cd168498ae9193dd5e5b4c'),
  ('public.get_broome_sales_accessories()','41bc6acad0b8764f23204668dc7ace4a')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>6 THEN RAISE EXCEPTION 'r418 undo: a Sales function this release keeps unchanged is not the expected version'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.get_accessories()'::regprocedure AND p.prosecdef AND p.provolatile='s' AND p.proowner='postgres'::regrole
     AND p.proacl::text='{postgres=X/postgres,authenticated=X/postgres}' AND array_to_string(p.proconfig,'|')='search_path=pg_catalog, public, pdc_sales_private')<>1 THEN RAISE EXCEPTION 'r418 undo: get_accessories owner, grants, security or settings changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('pdc_sales_private.get_accessories()','ef91622d497528866f09537887c4a199'),
  ('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)','a18b25bc425141201a698ac17d9b982e'),
  ('pdc_sales_private.accessory_delay_lifted(text,text)','a2c556e53e8f6ab45743b4e52e18b2f8'),
  ('pdc_sales_private.sales_accessory_ticks_delayed(jsonb)','9ea1932228faffd692e04a533a09743d'),
  ('public.set_broome_sales_accessory_delay(uuid,text,boolean)','69fbaad0a913ffbee727817a1f53cc28')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>5 THEN RAISE EXCEPTION 'r418 undo: functions are not the r418 versions; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r418')<>5 THEN RAISE EXCEPTION 'r418 undo: r418 pins not as expected'; END IF;
END $g$;

-- Keep a record of any stored delays before the table goes.
INSERT INTO pdc_sales_private.crm_audit(record_id,kind,actor_id,before_data,after_data)
SELECT d.tracking_id,'accessory_delay_undo',d.created_by,jsonb_build_object('order_key',d.order_key,'line_key',d.line_key,'created_at',d.created_at,'delayed',true),jsonb_build_object('delayed',false)
FROM pdc_sales_private.sales_accessory_line_delays d;

CREATE OR REPLACE FUNCTION pdc_sales_private.get_accessories()
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
END $function$;

DROP FUNCTION public.set_broome_sales_accessory_delay(uuid,text,boolean);
DROP FUNCTION pdc_sales_private.set_accessory_line_delay(uuid,text,boolean);
DROP FUNCTION pdc_sales_private.sales_accessory_ticks_delayed(jsonb);
DROP FUNCTION pdc_sales_private.accessory_delay_lifted(text,text);
DROP TABLE pdc_sales_private.sales_accessory_line_delays;
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='49f6feab0ef97e1f515cf9d8c5de4fd9', release='r394', note=NULL, updated_at=now()
 WHERE signature='pdc_sales_private.get_accessories()' AND release='r418';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r418';
DELETE FROM pdc_ops.regression_checks WHERE check_name='accessory_delay_lifts_at_yard_hold' AND added_in='r418';
DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_sales_private.get_accessories()'::regprocedure)<>'49f6feab0ef97e1f515cf9d8c5de4fd9' THEN RAISE EXCEPTION 'r418 undo: get_accessories not restored'; END IF;
 IF (SELECT p.proacl::text||p.prosecdef::text||array_to_string(p.proconfig,'|') FROM pg_proc p WHERE p.oid='pdc_sales_private.get_accessories()'::regprocedure)<>'{postgres=X/postgres,authenticated=X/postgres}truesearch_path=pg_catalog, public, pdc_sales_private' THEN RAISE EXCEPTION 'r418 undo: get_accessories grants or settings not restored'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.get_accessories()' AND prosrc_md5='49f6feab0ef97e1f515cf9d8c5de4fd9' AND release='r394')<>1 THEN RAISE EXCEPTION 'r418 undo: pin not restored'; END IF;
 IF to_regclass('pdc_sales_private.sales_accessory_line_delays') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_proc WHERE proname IN ('set_accessory_line_delay','set_broome_sales_accessory_delay','accessory_delay_lifted','sales_accessory_ticks_delayed'))
  OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r418') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r418') THEN RAISE EXCEPTION 'r418 undo: r418 objects remain'; END IF;
END $p$;
