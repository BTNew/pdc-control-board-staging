-- r427 undo (F40). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Restores get_accessories and set_accessory_line_delay
-- byte for byte (r418), the r418 pins and check, and drops the r427 functions, pins and check. Stored delays and their history are
-- not touched (r427 never changed them); after the undo they read as r418 did.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r427 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r427 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r427 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES ('pdc_sales_private.get_accessories()','6249e21543ac7caf096e3175c81406c4'),('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)','f51eb800647a4c44353e74c1d70e343d'),
   ('pdc_sales_private.yard_hold_stage_rank(text,text)','a441a598a1a6477e36d0a73ad7c5d354'),('pdc_sales_private.accessory_yard_hold_reached(jsonb)','84ac4e9482b8988eff9dcd662b5cc108')) e(sig,m)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>4 THEN RAISE EXCEPTION 'r427 undo: r427 functions are not the expected version'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='accessory_delay_lifts_at_yard_hold')<>'863b05e18bbf6d6210fc290a27de519d'
    OR (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='accessory_delay_lifts_past_yard_hold_stages' AND added_in='r427')<>'0589980ea62cead45b11d196c5ae1a3d' THEN RAISE EXCEPTION 'r427 undo: checks are not the r427 version'; END IF;
END $g$;

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
   'lines',d.lines,
   -- r418: yard hold delay. at_or_past_yard_hold lifts every delay; delay_lifted_lines flags the order row.
   'at_or_past_yard_hold',pdc_sales_private.accessory_delay_lifted(e->>'pmb_location',e->>'pmb_arrival_date'),'delay_lifted_lines',d.lifted
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
     WHEN pdc_sales_private.accessory_delay_lifted(e->>'pmb_location',e->>'pmb_arrival_date') THEN 'lifted' ELSE 'delayed' END delay) x
   WHERE l.dealer_code='37047' AND l.order_key=st.order_key AND l.superseded_receipt_id IS NULL) d
 WHERE e->>'salesperson_code' IN ('AW','BG','PM','CW') AND NOT coalesce((e->>'identity_conflict')::boolean,false)
 AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
 AND coalesce((stock_counts->>btrim(e->>'stock'))::integer,0)=1;
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales accessory display exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.set_accessory_line_delay(p_tracking_id uuid, p_line_key text, p_delayed boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); item jsonb; okey text; v_line pdc_sales_private.sales_accessory_lines; changed integer:=0; now_delayed boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in to change accessory lines' USING errcode='42501'; END IF;
 IF p_tracking_id IS NULL OR p_line_key IS NULL OR p_delayed IS NULL OR p_line_key !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'Choose an accessory line to delay';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-accessory-delay:'||p_tracking_id::text,0));
 SELECT e INTO item FROM jsonb_array_elements(pdc_sales_private.visibility_source_snapshot(false)->'items') e
  WHERE e->>'tracking_id'=p_tracking_id::text AND NOT coalesce((e->>'identity_conflict')::boolean,false) LIMIT 1;
 IF item IS NULL THEN RAISE EXCEPTION 'Vehicle is outside your current sales access' USING errcode='42501'; END IF;
 okey:=upper(btrim(coalesce(item->>'order','')));
 IF NOT EXISTS(SELECT 1 FROM pdc_sales_private.sales_accessory_vehicle_status st WHERE st.dealer_code='37047' AND st.order_key=okey
   AND st.navision_record_id::text=item->>'navision_record_id') THEN
  RAISE EXCEPTION 'This vehicle has no current sales export lines. Reload the page';
 END IF;
 SELECT * INTO v_line FROM pdc_sales_private.sales_accessory_lines l
  WHERE l.dealer_code='37047' AND l.order_key=okey AND l.line_key=p_line_key AND l.superseded_receipt_id IS NULL;
 IF v_line.id IS NULL THEN RAISE EXCEPTION 'This line is no longer in the latest sales export. Reload the page'; END IF;
 IF p_delayed THEN
  IF v_line.po_state<>'blank' THEN RAISE EXCEPTION 'A PO is already recorded for this line; it does not need a delay'; END IF;
  IF pdc_sales_private.accessory_delay_lifted(item->>'pmb_location',item->>'pmb_arrival_date') THEN
   RAISE EXCEPTION 'Vehicle is at yard hold, delay removed, please raise the PO';
  END IF;
  INSERT INTO pdc_sales_private.sales_accessory_line_delays(dealer_code,order_key,line_key,tracking_id,created_by)
  VALUES('37047',okey,p_line_key,p_tracking_id,auth.uid()) ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS changed = ROW_COUNT;
 ELSE
  DELETE FROM pdc_sales_private.sales_accessory_line_delays d WHERE d.dealer_code='37047' AND d.order_key=okey AND d.line_key=p_line_key;
  GET DIAGNOSTICS changed = ROW_COUNT;
 END IF;
 IF changed>0 THEN
  INSERT INTO pdc_sales_private.crm_audit(record_id,kind,actor_id,before_data,after_data)
  VALUES(p_tracking_id,'accessory_delay',auth.uid(),jsonb_build_object('line_key',p_line_key,'item',v_line.description,'delayed',NOT p_delayed),
   jsonb_build_object('line_key',p_line_key,'item',v_line.description,'delayed',p_delayed));
 END IF;
 now_delayed:=EXISTS(SELECT 1 FROM pdc_sales_private.sales_accessory_line_delays d WHERE d.dealer_code='37047' AND d.order_key=okey AND d.line_key=p_line_key);
 RETURN jsonb_build_object('tracking_id',p_tracking_id,'line_key',p_line_key,'delayed',now_delayed,
  'delay',CASE WHEN NOT now_delayed THEN 'none' WHEN pdc_sales_private.accessory_delay_lifted(item->>'pmb_location',item->>'pmb_arrival_date') THEN 'lifted' ELSE 'delayed' END);
END $function$;

DROP FUNCTION pdc_sales_private.accessory_yard_hold_reached(jsonb);
DROP FUNCTION pdc_sales_private.yard_hold_stage_rank(text,text);
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='ef91622d497528866f09537887c4a199', release='r418', note='r418: yard hold delay (was r394 49f6feab0ef97e1f515cf9d8c5de4fd9)', updated_at=now()
 WHERE signature='pdc_sales_private.get_accessories()' AND release='r427';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='a18b25bc425141201a698ac17d9b982e', release='r418', note='yard hold delay writer', updated_at=now()
 WHERE signature='pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)' AND release='r427';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r427';
DELETE FROM pdc_ops.regression_checks WHERE check_name='accessory_delay_lifts_past_yard_hold_stages' AND added_in='r427';
UPDATE pdc_ops.regression_checks SET check_sql=$chk$WITH t AS (
  SELECT c.relrowsecurity rls,
   has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') auth_direct, has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') anon_direct
  FROM pg_catalog.pg_class c WHERE c.oid=to_regclass('pdc_sales_private.sales_accessory_line_delays')
), f AS (
  SELECT (SELECT NOT p.prosecdef AND has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
          FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.set_broome_sales_accessory_delay(uuid,text,boolean)')) rpc_ok,
   (SELECT p.prosecdef AND NOT has_function_privilege('anon',p.oid,'EXECUTE') FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)')) writer_ok,
   (SELECT position('accessory_delay_lifted(e->>''pmb_location'',e->>''pmb_arrival_date'')' IN p.prosrc)>0 AND position('''delay_active'',x.delay=''delayed''' IN p.prosrc)>0
      AND position('sales_accessory_ticks_delayed(' IN p.prosrc)>0 FROM pg_catalog.pg_proc p WHERE p.oid='pdc_sales_private.get_accessories()'::regprocedure) read_ok
), l AS (
  SELECT pdc_sales_private.accessory_delay_lifted('YH') AND pdc_sales_private.accessory_delay_lifted(' yh ') AND pdc_sales_private.accessory_delay_lifted('PMB')
   AND pdc_sales_private.accessory_delay_lifted('PIT') AND pdc_sales_private.accessory_delay_lifted('QC') AND pdc_sales_private.accessory_delay_lifted('RFT')
   AND pdc_sales_private.accessory_delay_lifted('Completed') AND pdc_sales_private.accessory_delay_lifted('IT','2026-10-01')
   AND NOT pdc_sales_private.accessory_delay_lifted('IT') AND NOT coalesce(pdc_sales_private.accessory_delay_lifted(NULL),true) AND NOT pdc_sales_private.accessory_delay_lifted('Other','') AS lift_ok,
   pdc_sales_private.sales_accessory_ticks_delayed('[{"line_class":"tint","po_state":"blank","delay_active":true}]')->'tint'->>'state'='review'
   AND pdc_sales_private.sales_accessory_ticks_delayed('[{"line_class":"tint","po_state":"blank","delay_active":true},{"line_class":"tint","po_state":"blank"}]')->'tint'->>'state'='red'
   AND pdc_sales_private.sales_accessory_ticks_delayed('[{"line_class":"tint","po_state":"blank"},{"line_class":"build","po_state":"po"},{"line_class":"tray","po_state":"other"}]')
     =pdc_sales_private.sales_accessory_ticks('[{"line_class":"tint","po_state":"blank"},{"line_class":"build","po_state":"po"},{"line_class":"tray","po_state":"other"}]') AS tick_ok
), d AS (
  SELECT count(*) total,
   count(*) FILTER (WHERE pdc_sales_private.accessory_delay_lifted(coalesce(nullif(v.location_override,''),v.current_location),v.date_to_pmb::text)) lifted
  FROM pdc_sales_private.sales_accessory_line_delays x
  LEFT JOIN LATERAL (SELECT n.canonical_vehicle_id FROM public.navision_backend_records n WHERE n.dealer_code=x.dealer_code AND n.is_current AND n.record_status='current'
    AND upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order'))))=x.order_key LIMIT 1) n ON true
  LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
)
SELECT coalesce((SELECT rls AND NOT auth_direct AND NOT anon_direct FROM t),false) AND coalesce((SELECT rpc_ok AND writer_ok AND read_ok FROM f),false)
   AND (SELECT lift_ok AND tick_ok FROM l) AS ok,
 'table '||coalesce((SELECT CASE WHEN rls AND NOT auth_direct AND NOT anon_direct THEN 'RLS, RPC only' ELSE 'OPEN or no RLS' END FROM t),'MISSING')
 ||'; RPC '||CASE WHEN coalesce((SELECT rpc_ok AND writer_ok FROM f),false) THEN 'ok' ELSE 'WRONG grants or security' END
 ||'; read lifts delays at yard hold: '||CASE WHEN coalesce((SELECT read_ok FROM f),false) AND (SELECT lift_ok FROM l) THEN 'yes' ELSE 'NO' END
 ||'; delayed tick never red: '||CASE WHEN (SELECT tick_ok FROM l) THEN 'yes' ELSE 'NO' END
 ||'; delays stored: '||(SELECT total FROM d)||', lifted (vehicle at or past yard hold, PO to raise): '||(SELECT lifted FROM d) AS detail$chk$,
 description='Sales "Delay until yard hold": the delay table is RLS/RPC-only, the read lifts every delay once the vehicle is at yard hold (PMB location YH or later, or a PMB arrival date) and a delayed line never turns a tick red while it is delayed; reports stored and lifted delays.'
 WHERE check_name='accessory_delay_lifts_at_yard_hold' AND added_in='r418';

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM (VALUES ('pdc_sales_private.get_accessories()','ef91622d497528866f09537887c4a199','{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private'),
   ('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)','a18b25bc425141201a698ac17d9b982e','{postgres=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public, pdc_sales_private')) e(sig,m,a)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')=e.a)<>2 THEN RAISE EXCEPTION 'r427 undo: functions not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE proname IN ('yard_hold_stage_rank','accessory_yard_hold_reached')) OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r427')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r427') THEN RAISE EXCEPTION 'r427 undo: r427 objects remain'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r418' AND (signature,prosrc_md5) IN (('pdc_sales_private.get_accessories()','ef91622d497528866f09537887c4a199'),('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)','a18b25bc425141201a698ac17d9b982e')))<>2 THEN RAISE EXCEPTION 'r427 undo: pins not restored'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='accessory_delay_lifts_at_yard_hold')<>'ad890e048c9658cb0d1df4ec94addeaa' THEN RAISE EXCEPTION 'r427 undo: r418 check not restored'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r427 undo: protected_function_md5s not ok: %', x.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
