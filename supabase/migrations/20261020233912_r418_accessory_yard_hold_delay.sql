-- r418 (F32, Craig 21 Oct): Sales "Delay until yard hold" on Not raised accessory lines. Staging cdsmnqxtyyoeoznmbidd only.
-- A Not raised line can be delayed until the vehicle reaches yard hold (e.g. tint, whose PO is raised at yard hold). While
-- delayed and before yard hold, the line shows "Delayed - yard hold" and its Build/Tint/Tray tick is amber review, never red.
-- Yard hold trigger (the board's own value): PMB location YH (vehicles.current_location or location_override), or any later
-- board stage (PMB, PIT, QC, RFT, Completed), or a PMB arrival date. Then every delay on that vehicle lifts automatically:
-- the line and tick go red again and the order row is flagged. Raising a PO makes it a new export line: green as normal.
-- This is the only exception to "ticks are automatic from PO data"; it only ever defers the red flag.
-- New: table sales_accessory_line_delays (RLS, no direct grants, like vehicle_notes), helpers accessory_delay_lifted and
-- sales_accessory_ticks_delayed, writer set_accessory_line_delay (SECURITY DEFINER, same access check as save_vehicle_notes,
-- audited in crm_audit) behind public.set_broome_sales_accessory_delay (SECURITY INVOKER). Changed: get_accessories (adds
-- line_key, delay per line, at_or_past_yard_hold and delay_lifted_lines per vehicle; ticks via sales_accessory_ticks_delayed,
-- identical to before when no delay is stored). Same owner, grants, SECURITY DEFINER and settings (guarded).
-- Not touched: sales_accessory_tick(s), the import, ordering RPCs, the clock tick, the board, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r418: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r418: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r418: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r418: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('pdc_sales_private.sales_accessory_ticks(jsonb)','c831c3b42b906d982ff9e6344f23a61d'),
  ('pdc_sales_private.sales_accessory_tick(jsonb,text)','d428d8808dd3770ed3001ce2be6e9e4f'),
  ('pdc_sales_private.visibility_source_snapshot(boolean)','c51d473d947b4dea1ef457bb57f6d16d'),
  ('pdc_sales_private.board_visibility_source_snapshot(boolean)','2cdd2ec2581551363d39d055e2cf1397'),
  ('pdc_sales_private.crm_context()','ded7229678cd168498ae9193dd5e5b4c'),
  ('public.get_broome_sales_accessories()','41bc6acad0b8764f23204668dc7ace4a')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>6 THEN RAISE EXCEPTION 'r418: a Sales function this release keeps unchanged is not the expected version'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_sales_private.get_accessories()'::regprocedure AND p.prosecdef AND p.provolatile='s' AND p.proowner='postgres'::regrole
     AND p.proacl::text='{postgres=X/postgres,authenticated=X/postgres}' AND array_to_string(p.proconfig,'|')='search_path=pg_catalog, public, pdc_sales_private')<>1 THEN RAISE EXCEPTION 'r418: get_accessories owner, grants, security or settings changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_sales_private.get_accessories()'::regprocedure)<>'49f6feab0ef97e1f515cf9d8c5de4fd9' THEN RAISE EXCEPTION 'r418: get_accessories is not the expected (r394) version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.get_accessories()' AND prosrc_md5='49f6feab0ef97e1f515cf9d8c5de4fd9' AND release='r394')<>1 THEN RAISE EXCEPTION 'r418: get_accessories pin is not the r394 pin'; END IF;
 IF to_regclass('pdc_sales_private.sales_accessory_line_delays') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_proc WHERE proname IN ('set_accessory_line_delay','set_broome_sales_accessory_delay','accessory_delay_lifted','sales_accessory_ticks_delayed'))
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='accessory_delay_lifts_at_yard_hold' OR added_in='r418') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r418') THEN RAISE EXCEPTION 'r418: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=220) THEN RAISE EXCEPTION 'r418: sort_order 220 taken'; END IF;
END $g$;

-- One row per Not raised sales-export line that sales chose to delay until the vehicle reaches yard hold.
-- Keyed on the export line identity (dealer, order, line_key). line_key includes the PO number, so a line whose PO is raised
-- is a new line and the delay no longer applies (it goes green as normal). Same access model as vehicle_notes: RLS on, no
-- direct grants, every read and write through the Sales RPCs.
CREATE TABLE pdc_sales_private.sales_accessory_line_delays (
  dealer_code text NOT NULL DEFAULT '37047' CHECK (dealer_code='37047'),
  order_key text NOT NULL CHECK (order_key<>'' AND order_key=upper(btrim(order_key))),
  line_key text NOT NULL CHECK (line_key ~ '^[0-9a-f]{64}$'),
  tracking_id uuid NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (dealer_code, order_key, line_key)
);
ALTER TABLE pdc_sales_private.sales_accessory_line_delays ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_accessory_line_delays_rpc_only ON pdc_sales_private.sales_accessory_line_delays FOR ALL USING (false) WITH CHECK (false);
REVOKE ALL ON pdc_sales_private.sales_accessory_line_delays FROM PUBLIC, anon, authenticated, service_role;

-- The board's yard hold is the PMB location YH (vehicles.current_location or its override). A vehicle at YH or any later
-- board stage, or one that has a PMB arrival date (it has been past yard hold), has reached yard hold: every delay on it lifts.
CREATE FUNCTION pdc_sales_private.accessory_delay_lifted(p_location text, p_pmb_arrival text DEFAULT NULL)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  SELECT upper(btrim(coalesce(p_location,''))) IN ('YH','PMB','PIT','QC','RFT','COMPLETED') OR coalesce(btrim(p_pmb_arrival),'')<>''
$f$;

-- Build/Tint/Tray ticks with active delays. Delayed lines are left out of the normal tick; a class that would then be green
-- or grey shows review (amber, never red) with reason delayed_until_yard_hold. Any other Not raised line keeps it red.
-- With no active delay the result is exactly sales_accessory_ticks() of the same lines.
CREATE FUNCTION pdc_sales_private.sales_accessory_ticks_delayed(p_lines jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  WITH l AS (SELECT e, coalesce((e->>'delay_active')::boolean,false) AND e->>'po_state'='blank' AS delayed
             FROM jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) e),
  base AS (SELECT pdc_sales_private.sales_accessory_ticks(coalesce((SELECT jsonb_agg(e - 'delay_active') FROM l WHERE NOT delayed),'[]'::jsonb)) t),
  d AS (SELECT c, (SELECT count(*) FROM l WHERE delayed AND e->>'line_class'=c) n FROM unnest(ARRAY['build','tint','tray']) c)
  SELECT jsonb_object_agg(d.c, CASE WHEN d.n=0 THEN base.t->d.c
    WHEN base.t->d.c->>'state' IN ('green','grey') THEN (base.t->d.c)||jsonb_build_object('state','review','reason','delayed_until_yard_hold','delayed',d.n)
    ELSE (base.t->d.c)||jsonb_build_object('delayed',d.n) END) FROM base, d
$f$;

-- Tick or untick "Delay until yard hold" on one Not raised line. Same access as saving Sales notes (save_vehicle_notes).
CREATE FUNCTION pdc_sales_private.set_accessory_line_delay(p_tracking_id uuid, p_line_key text, p_delayed boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog, public, pdc_sales_private AS $f$
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
END $f$;

CREATE FUNCTION public.set_broome_sales_accessory_delay(p_tracking_id uuid, p_line_key text, p_delayed boolean)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO 'pg_catalog', 'pdc_sales_private'
AS $function$ SELECT pdc_sales_private.set_accessory_line_delay(p_tracking_id,p_line_key,p_delayed); $function$;

REVOKE ALL ON FUNCTION pdc_sales_private.accessory_delay_lifted(text,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_sales_private.sales_accessory_ticks_delayed(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_sales_private.set_accessory_line_delay(uuid,text,boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.set_broome_sales_accessory_delay(uuid,text,boolean) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.set_accessory_line_delay(uuid,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_broome_sales_accessory_delay(uuid,text,boolean) TO authenticated;

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

-- Pins: get_accessories re-pinned; the new functions pinned.
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='ef91622d497528866f09537887c4a199', release='r418', note='r418: yard hold delay (was r394 49f6feab0ef97e1f515cf9d8c5de4fd9)', updated_at=now()
 WHERE signature='pdc_sales_private.get_accessories()' AND prosrc_md5='49f6feab0ef97e1f515cf9d8c5de4fd9';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)','a18b25bc425141201a698ac17d9b982e','r418','yard hold delay writer'),
 ('pdc_sales_private.accessory_delay_lifted(text,text)','a2c556e53e8f6ab45743b4e52e18b2f8','r418','yard hold trigger'),
 ('pdc_sales_private.sales_accessory_ticks_delayed(jsonb)','9ea1932228faffd692e04a533a09743d','r418','ticks with delays'),
 ('public.set_broome_sales_accessory_delay(uuid,text,boolean)','69fbaad0a913ffbee727817a1f53cc28','r418','yard hold delay RPC (invoker)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('accessory_delay_lifts_at_yard_hold','F32','Sales "Delay until yard hold": the delay table is RLS/RPC-only, the read lifts every delay once the vehicle is at yard hold (PMB location YH or later, or a PMB arrival date) and a delayed line never turns a tick red while it is delayed; reports stored and lifted delays.',
 $chk$WITH t AS (
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
 ||'; delays stored: '||(SELECT total FROM d)||', lifted (vehicle at or past yard hold, PO to raise): '||(SELECT lifted FROM d) AS detail$chk$,true,220,'r418');

-- Post-check inside the migration.
DO $p$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM (VALUES
  ('pdc_sales_private.get_accessories()','ef91622d497528866f09537887c4a199'),
  ('pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)','a18b25bc425141201a698ac17d9b982e'),
  ('pdc_sales_private.accessory_delay_lifted(text,text)','a2c556e53e8f6ab45743b4e52e18b2f8'),
  ('pdc_sales_private.sales_accessory_ticks_delayed(jsonb)','9ea1932228faffd692e04a533a09743d'),
  ('public.set_broome_sales_accessory_delay(uuid,text,boolean)','69fbaad0a913ffbee727817a1f53cc28')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>5 THEN RAISE EXCEPTION 'r418: new function bodies are not the expected md5s'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r418')<>5 THEN RAISE EXCEPTION 'r418: pins not written'; END IF;
 IF (SELECT p.proacl::text FROM pg_proc p WHERE p.oid='public.set_broome_sales_accessory_delay(uuid,text,boolean)'::regprocedure)<>'{postgres=X/postgres,authenticated=X/postgres}'
  OR (SELECT p.proacl::text FROM pg_proc p WHERE p.oid='pdc_sales_private.set_accessory_line_delay(uuid,text,boolean)'::regprocedure)<>'{postgres=X/postgres,authenticated=X/postgres}'
  OR (SELECT p.proacl::text FROM pg_proc p WHERE p.oid='pdc_sales_private.accessory_delay_lifted(text,text)'::regprocedure)<>'{postgres=X/postgres}'
  OR (SELECT p.proacl::text FROM pg_proc p WHERE p.oid='pdc_sales_private.sales_accessory_ticks_delayed(jsonb)'::regprocedure)<>'{postgres=X/postgres}'
  OR (SELECT p.proacl::text FROM pg_proc p WHERE p.oid='pdc_sales_private.get_accessories()'::regprocedure)<>'{postgres=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r418: function grants are not as expected'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='accessory_delay_lifts_at_yard_hold') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r418: new regression check is not ok: %', r.detail; END IF;
END $p$;
