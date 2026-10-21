-- r427 (F40, 21 Oct, Sales order dropdown report): Sales "Delay until yard hold" ignored the Navision/Toyota stage. Staging cdsmnqxtyyoeoznmbidd only.
-- Fault: r418 lifted delays (and refused new ones) only from the board's PMB location (YH or later) or a PMB arrival date. A Sales
-- vehicle the board has not linked or moved (no PMB location, or still IT) but that Toyota already shows past the yard, e.g. OD
-- "Delivered - At Body Builder", kept its delays amber "Delayed - yard hold" and still offered the tick.
-- Fix: new pdc_sales_private.yard_hold_stage_rank (the Navision stage order) and accessory_yard_hold_reached(item) (board location
-- OR PMB/QC/RFT/collected/dealer dates OR Navision stage at the yard or beyond). get_accessories and set_accessory_line_delay call it
-- instead of accessory_delay_lifted (kept, unchanged, still used inside). Same owner, grants, SECURITY DEFINER and settings (guarded).
-- Stored delays are NOT changed: they now read 'lifted' (red, "please raise the PO") wherever the vehicle is at or past yard hold.
-- Regression: new check accessory_delay_lifts_past_yard_hold_stages (F40, sort 227); r418's check reads the new call.
-- Not touched: the delay table and its rows, crm_audit, ticks, the import, the board, the clock tick, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r427: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r427: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r427: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r427: clock tick changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.get_accessories()'::regprocedure AND md5(p.prosrc)='ef91622d497528866f09537887c4a199' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private')<>1 THEN RAISE EXCEPTION 'r427: get_accessories is not the expected (r418) version'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)'::regprocedure AND md5(p.prosrc)='a18b25bc425141201a698ac17d9b982e' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public, pdc_sales_private')<>1 THEN RAISE EXCEPTION 'r427: set_accessory_line_delay is not the expected (r418) version'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.accessory_delay_lifted(text,text)'::regprocedure AND md5(p.prosrc)='a2c556e53e8f6ab45743b4e52e18b2f8' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog')<>1 THEN RAISE EXCEPTION 'r427: accessory_delay_lifted is not the expected (r418) version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r418' AND (signature,prosrc_md5) IN (('pdc_sales_private.get_accessories()','ef91622d497528866f09537887c4a199'),('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)','a18b25bc425141201a698ac17d9b982e')))<>2 THEN RAISE EXCEPTION 'r427: r418 pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='accessory_delay_lifts_at_yard_hold' AND added_in='r418')<>'ad890e048c9658cb0d1df4ec94addeaa' THEN RAISE EXCEPTION 'r427: r418 check is not the expected version'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE proname IN ('yard_hold_stage_rank','accessory_yard_hold_reached')) OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r427')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='accessory_delay_lifts_past_yard_hold_stages' OR added_in='r427') THEN RAISE EXCEPTION 'r427: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=227) THEN RAISE EXCEPTION 'r427: sort_order 227 taken'; END IF;
END $g$;

-- r427: the yard hold stage order, in one place. Toyota's Navision location status comes in families, in this order:
--   0 ''  production (planned, line off, final inspection, overseas wharf)
--   1 IT  in transit (shipment, WA / eastern states transit, vehicle at wharf)
--   2 Y?  at the Toyota WA yard: YH yard hold, YN waiting PD2 / vehicle delayed, YR waiting for wholesale, YW ready for transport from TWA
--   3 O?  out of the yard: OD despatched from TWA / delivered at body builder / ready for transport from body builder / at dealer, OC on consignment
-- Rank 2 or more is at or past yard hold. A blank or unrecognised code falls back to the Toyota status text (same words as the
-- Sales page categories, which run production, transit, yard hold, hold/waiting, released, dealer). The regression check
-- accessory_delay_lifts_past_yard_hold_stages goes red if the feed ever carries a location code outside these families.
CREATE FUNCTION pdc_sales_private.yard_hold_stage_rank(p_location_status text, p_toyota_status text)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  SELECT greatest(CASE WHEN x.code='' THEN 0 WHEN x.code='IT' THEN 1 WHEN x.code ~ '^Y[A-Z]$' THEN 2 WHEN x.code ~ '^O[A-Z]$' THEN 3 ELSE 0 END,
    CASE WHEN x.s ~ '(delivered|at dealer|body builder|consignment|ready for transport|ready for despatch|ready for dispatch|despatch|dispatch)' THEN 3
         WHEN x.s ~ '(yard hold|waiting pd|waiting for wholesale|\myh\M)' THEN 2
         WHEN x.s ~ '(in transit|wharf|shipment)' THEN 1 ELSE 0 END)
  FROM (SELECT upper(btrim(coalesce(p_location_status,''))) code, lower(coalesce(p_toyota_status,'')) s) x
$f$;

-- r427 (F40): a Sales vehicle has reached yard hold when ANY source says so: the board's PMB location is YH or later
-- (IT < YH < PMB < PIT < QC < RFT < Completed < Collected; r418 accessory_delay_lifted, unchanged), or it has a PMB arrival,
-- QC, RFT, collection or dealer-delivered date, or Navision/Toyota puts it at the yard or beyond (yard_hold_stage_rank >= 2).
-- r418 only read the board location, so a vehicle Toyota showed as OD (e.g. Delivered - At Body Builder) that the board had
-- not linked or moved kept its delay amber and still offered the tick.
CREATE FUNCTION pdc_sales_private.accessory_yard_hold_reached(p_item jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  SELECT pdc_sales_private.accessory_delay_lifted(p_item->>'pmb_location',p_item->>'pmb_arrival_date')
    OR upper(btrim(coalesce(p_item->>'pmb_location','')))='COLLECTED'
    OR coalesce(btrim(p_item->>'qc_completed_at'),'')<>'' OR coalesce(btrim(p_item->>'rft_transferred_at'),'')<>''
    OR coalesce(btrim(p_item->>'collected_at'),'')<>'' OR coalesce(btrim(p_item->>'dealer_delivered_date'),'')<>''
    OR pdc_sales_private.yard_hold_stage_rank(p_item->>'location_status',p_item->>'toyota_status')>=2
$f$;
REVOKE ALL ON FUNCTION pdc_sales_private.yard_hold_stage_rank(text,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_sales_private.accessory_yard_hold_reached(jsonb) FROM PUBLIC, anon, authenticated, service_role;

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
  IF pdc_sales_private.accessory_yard_hold_reached(item) THEN
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
  'delay',CASE WHEN NOT now_delayed THEN 'none' WHEN pdc_sales_private.accessory_yard_hold_reached(item) THEN 'lifted' ELSE 'delayed' END);
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='6249e21543ac7caf096e3175c81406c4', release='r427', note='r427: full yard hold stage order (was r418 ef91622d497528866f09537887c4a199)', updated_at=now()
 WHERE signature='pdc_sales_private.get_accessories()' AND release='r418' AND prosrc_md5='ef91622d497528866f09537887c4a199';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='f51eb800647a4c44353e74c1d70e343d', release='r427', note='r427: full yard hold stage order (was r418 a18b25bc425141201a698ac17d9b982e)', updated_at=now()
 WHERE signature='pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)' AND release='r418' AND prosrc_md5='a18b25bc425141201a698ac17d9b982e';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_sales_private.yard_hold_stage_rank(text,text)','a441a598a1a6477e36d0a73ad7c5d354','r427','Navision yard hold stage order'),
 ('pdc_sales_private.accessory_yard_hold_reached(jsonb)','84ac4e9482b8988eff9dcd662b5cc108','r427','yard hold trigger, every source');
UPDATE pdc_ops.regression_checks SET check_sql=$chk$WITH t AS (
  SELECT c.relrowsecurity rls,
   has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') auth_direct, has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') anon_direct
  FROM pg_catalog.pg_class c WHERE c.oid=to_regclass('pdc_sales_private.sales_accessory_line_delays')
), f AS (
  SELECT (SELECT NOT p.prosecdef AND has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
          FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.set_broome_sales_accessory_delay(uuid,text,boolean)')) rpc_ok,
   (SELECT p.prosecdef AND NOT has_function_privilege('anon',p.oid,'EXECUTE') FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)')) writer_ok,
   (SELECT position('accessory_yard_hold_reached(e)' IN p.prosrc)>0 AND position('''delay_active'',x.delay=''delayed''' IN p.prosrc)>0
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
   count(*) FILTER (WHERE pdc_sales_private.accessory_yard_hold_reached(jsonb_build_object('pmb_location',coalesce(nullif(v.location_override,''),v.current_location),
    'pmb_arrival_date',v.date_to_pmb,'location_status',coalesce(n.nd->>'navisionLocationStatus',''),'toyota_status',coalesce(n.nd->>'navisionSubLocationDescription',n.nd->>'toyotaStatus',''),
    'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,'collected_at',v.rft_collected_at,'dealer_delivered_date',v.delivered_to_dealer_date))) lifted
  FROM pdc_sales_private.sales_accessory_line_delays x
  LEFT JOIN LATERAL (SELECT n.canonical_vehicle_id, n.normalized_data nd FROM public.navision_backend_records n WHERE n.dealer_code=x.dealer_code AND n.is_current AND n.record_status='current'
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
 description='Sales "Delay until yard hold": the delay table is RLS/RPC-only, the read lifts every delay once the vehicle is at or past yard hold (r427: board location YH or later, PMB dates, or the Navision/Toyota stage at the yard or beyond) and a delayed line never turns a tick red while it is delayed; reports stored and lifted delays.'
 WHERE check_name='accessory_delay_lifts_at_yard_hold' AND added_in='r418';
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('accessory_delay_lifts_past_yard_hold_stages','F40','Sales yard hold delay follows the whole stage order: 40 fixed cases (every board location from YH on, PMB/QC/RFT/collected/dealer dates, Navision YH/YN/YR/YW/OD/OC and their Toyota statuses lift; production and transit do not); the read and the delay writer both use accessory_yard_hold_reached; red if the feed or the board carries a location code outside the known stage families.',
  $chk$WITH ls AS (
  SELECT b.id FROM public.navision_import_batches b WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047'
    AND b.status='applied' AND b.rolled_back_at IS NULL ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
), feed AS (
  SELECT n.normalized_data nd, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) order_key,
   upper(btrim(coalesce(n.normalized_data->>'navisionLocationStatus',''))) code, v.location_override, v.current_location, v.date_to_pmb,
   v.qc_completed_at, v.rft_transferred_at, v.rft_collected_at, v.delivered_to_dealer_date
  FROM public.navision_backend_records n JOIN ls ON ls.id=n.last_seen_batch_id
  LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
  WHERE n.dealer_code='37047' AND n.is_current AND n.record_status='current'
), item AS (
  SELECT f.order_key, f.code, jsonb_build_object('pmb_location',coalesce(nullif(f.location_override,''),f.current_location),'pmb_arrival_date',f.date_to_pmb,
   'location_status',coalesce(f.nd->>'navisionLocationStatus',''),'toyota_status',coalesce(f.nd->>'navisionSubLocationDescription',f.nd->>'toyotaStatus',''),
   'qc_completed_at',f.qc_completed_at,'rft_transferred_at',f.rft_transferred_at,'collected_at',f.rft_collected_at,'dealer_delivered_date',f.delivered_to_dealer_date) j
  FROM feed f
), cases AS (
  SELECT bool_and(pdc_sales_private.accessory_yard_hold_reached(c.j)=c.want) ok, count(*) n,
   string_agg(CASE WHEN pdc_sales_private.accessory_yard_hold_reached(c.j)<>c.want THEN c.j::text END,'; ') bad
  FROM (VALUES
   ('{"pmb_location":"YH"}'::jsonb,true),('{"pmb_location":" yh "}',true),('{"pmb_location":"PMB"}',true),('{"pmb_location":"PIT"}',true),
   ('{"pmb_location":"QC"}',true),('{"pmb_location":"RFT"}',true),('{"pmb_location":"Completed"}',true),('{"pmb_location":"Collected"}',true),
   ('{"pmb_location":"IT","pmb_arrival_date":"2026-10-01"}',true),('{"qc_completed_at":"2026-10-01T00:00:00Z"}',true),
   ('{"rft_transferred_at":"2026-10-01T00:00:00Z"}',true),('{"collected_at":"2026-10-01T00:00:00Z"}',true),('{"dealer_delivered_date":"2026-10-01"}',true),
   ('{"location_status":"YH","toyota_status":"Vehicle Yard Hold"}',true),('{"location_status":"YN","toyota_status":"Waiting PD2"}',true),
   ('{"location_status":"YN","toyota_status":"Vehicle Delayed"}',true),('{"location_status":"YR","toyota_status":"Vehicle Waiting For Wholesale"}',true),
   ('{"location_status":"YW","toyota_status":"Ready For Transport - From TWA"}',true),('{"location_status":"OD","toyota_status":"Despatched - From TWA"}',true),
   ('{"location_status":"OD","toyota_status":"Delivered - At Body Builder"}',true),('{"location_status":"od"}',true),
   ('{"location_status":"OD","toyota_status":"Ready For Transport - From Body Builder"}',true),('{"location_status":"OD","toyota_status":"Delivered - At Dealer"}',true),
   ('{"location_status":"OC","toyota_status":"Vehicle Out on Consignment"}',true),('{"pmb_location":"IT","location_status":"OD"}',true),
   ('{"location_status":"","toyota_status":"Delivered - At Body Builder"}',true),('{"toyota_status":"Vehicle In Yard Hold"}',true),
   ('{}',false),('{"pmb_location":"IT"}',false),('{"pmb_location":"Other","pmb_arrival_date":""}',false),
   ('{"location_status":"","toyota_status":"Planned for Production"}',false),('{"location_status":"","toyota_status":"Line Off Complete"}',false),
   ('{"location_status":"","toyota_status":"Final Inspection"}',false),('{"location_status":"","toyota_status":"In Transit To O/S Wharf"}',false),
   ('{"location_status":"","toyota_status":"At Overseas Wharf"}',false),('{"location_status":"","toyota_status":"Ready For Shipment"}',false),
   ('{"location_status":"IT","toyota_status":"In Transit To WA"}',false),('{"location_status":"IT","toyota_status":"In Transit To Eastern States"}',false),
   ('{"location_status":"IT","toyota_status":"Vehicle At Wharf"}',false),('{"pmb_location":"IT","location_status":"IT","toyota_status":"Line Off Complete"}',false)) c(j,want)
), reads AS (
  SELECT (SELECT (length(p.prosrc)-length(replace(p.prosrc,'accessory_yard_hold_reached(e)','')))/length('accessory_yard_hold_reached(e)')=2
           AND position('accessory_delay_lifted(' IN p.prosrc)=0 FROM pg_catalog.pg_proc p WHERE p.oid='pdc_sales_private.get_accessories()'::regprocedure) read_ok,
   (SELECT (length(p.prosrc)-length(replace(p.prosrc,'accessory_yard_hold_reached(item)','')))/length('accessory_yard_hold_reached(item)')=2
           AND position('accessory_delay_lifted(' IN p.prosrc)=0 FROM pg_catalog.pg_proc p WHERE p.oid='pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)'::regprocedure) write_ok
), codes AS (
  SELECT string_agg(DISTINCT CASE WHEN NOT (code IN ('','IT') OR code ~ '^[YO][A-Z]$') THEN code END,', ') unknown_navision,
   (SELECT string_agg(DISTINCT x,', ') FROM (SELECT v.current_location x FROM public.vehicles v WHERE v.deleted_at IS NULL UNION SELECT v.location_override FROM public.vehicles v WHERE v.deleted_at IS NULL) y
     WHERE x IS NOT NULL AND upper(btrim(x)) NOT IN ('IT','OTHER','YH','PMB','PIT','QC','RFT','COMPLETED','COLLECTED')) unknown_pmb,
   count(*) FILTER (WHERE pdc_sales_private.accessory_yard_hold_reached(j)) reached, count(*) total
  FROM item
), d AS (
  SELECT count(*) stored, count(*) FILTER (WHERE pdc_sales_private.accessory_yard_hold_reached(i.j)) lifted
  FROM pdc_sales_private.sales_accessory_line_delays x LEFT JOIN LATERAL (SELECT i.j FROM item i WHERE i.order_key=x.order_key LIMIT 1) i ON true
)
SELECT coalesce((SELECT ok FROM cases),false) AND coalesce((SELECT read_ok AND write_ok FROM reads),false)
   AND (SELECT unknown_navision IS NULL AND unknown_pmb IS NULL FROM codes) AS ok,
 'stage cases: '||CASE WHEN (SELECT ok FROM cases) THEN 'all '||(SELECT n FROM cases)||' right' ELSE 'WRONG for '||coalesce((SELECT bad FROM cases),'?') END
 ||'; read and delay writer use the full stage order: '||CASE WHEN coalesce((SELECT read_ok AND write_ok FROM reads),false) THEN 'yes' ELSE 'NO' END
 ||'; unclassified Navision location codes: '||coalesce((SELECT unknown_navision FROM codes),'none')
 ||'; unclassified PMB locations: '||coalesce((SELECT unknown_pmb FROM codes),'none')
 ||'; feed vehicles at or past yard hold: '||(SELECT reached FROM codes)||' of '||(SELECT total FROM codes)
 ||'; delays stored: '||(SELECT stored FROM d)||', lifted: '||(SELECT lifted FROM d) AS detail
$chk$,true,227,'r427');

DO $p$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM (VALUES ('pdc_sales_private.get_accessories()','6249e21543ac7caf096e3175c81406c4','{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public, pdc_sales_private'),
   ('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)','f51eb800647a4c44353e74c1d70e343d','{postgres=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public, pdc_sales_private'),
   ('pdc_sales_private.yard_hold_stage_rank(text,text)','a441a598a1a6477e36d0a73ad7c5d354','{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog'),
   ('pdc_sales_private.accessory_yard_hold_reached(jsonb)','84ac4e9482b8988eff9dcd662b5cc108','{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog')) e(sig,m,a)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')=e.a)<>4 THEN RAISE EXCEPTION 'r427: a function did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r427')<>4 THEN RAISE EXCEPTION 'r427: pins not written'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR r IN SELECT check_name FROM pdc_ops.regression_checks WHERE check_name IN ('accessory_delay_lifts_at_yard_hold','accessory_delay_lifts_past_yard_hold_stages','protected_function_md5s') LOOP
  DECLARE x record; BEGIN
   EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name=r.check_name) INTO x;
   IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r427: check % not ok: %', r.check_name, x.detail; END IF;
  END;
 END LOOP;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
