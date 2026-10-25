-- r528 (F142). Staging cdsmnqxtyyoeoznmbidd only. Preview for Craig; he will go-live.
-- KTA Allocation - Deal Items (noreply@revolutionsoftware.com.au to pdc@pmgwa.com.au) into Karratha
-- Sales accessories, dealer 14450. Dept 105/107. Same columns as BT Allocation. No dealer column.
-- Dedicated importer. import_sales_accessories_20261020 stays the Broome 37047 function (r505 body).
-- Karratha rows live in karratha_sales_accessory_* tables, so the Broome function cannot see them or
-- write them. Broome CHECK (dealer_code = '37047') is not widened.
-- Match is current Karratha Navision stock only. No insert into vehicles, jobs, bookings or Navision.
-- Unmatched stocks are reported and not inserted. Same file sha or same Outlook message id is a no-op.
-- A newer snapshot replaces lines for that stock. An older snapshot does not.
-- Department 135 is not changed. import_karratha_sales_orders is a different feed and is not created.
-- Pins 236 to 241. r527 / F141 is already on main (sort 308, pin count 236). Check karratha_sales_accessories_528 sort 309 F142.
-- Undo: supabase/rollbacks/20261025120000_r528_karratha_sales_accessories.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r528: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r528: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM '46d4b464c5c1800c8ada245fb2d33bd3' THEN RAISE EXCEPTION 'r528: Broome accessory import is not the r505 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_accessories()')) IS DISTINCT FROM '2f7f060cdaca01cc2763a15b921debf8' THEN RAISE EXCEPTION 'r528: get_accessories is not the r495 body'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>236 THEN RAISE EXCEPTION 'r528: pin count is not 236'; END IF;
 IF to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)') IS NOT NULL
    OR to_regprocedure('pdc_sales_private.import_karratha_sales_orders(jsonb,boolean)') IS NOT NULL
    OR to_regclass('pdc_sales_private.karratha_sales_accessory_receipts') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=309 OR fault_id='F142' OR check_name='karratha_sales_accessories_528' OR added_in='r528')
 THEN RAISE EXCEPTION 'r528: already applied, or sort 309 / F142 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='qa_bay_technician_527' AND fault_id='F141' AND sort_order=308 AND added_in='r527')
 THEN RAISE EXCEPTION 'r528: r527 / F141 sort 308 is not the live QA Bay 07 check'; END IF;
 IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='pdc_sales_private.sales_accessory_receipts'::regclass AND conname='sales_accessory_receipts_dealer_code_check') IS DISTINCT FROM 'CHECK ((dealer_code = ''37047''::text))' THEN RAISE EXCEPTION 'r528: Broome receipt dealer check changed'; END IF;
END $g$;

CREATE TABLE pdc_sales_private.karratha_sales_accessory_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dealer_code text NOT NULL CHECK (dealer_code='14450'),
  file_sha256 text NOT NULL UNIQUE CHECK (file_sha256 ~ '^[0-9a-f]{64}$'),
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  file_name text NOT NULL CHECK (file_name ~* '\.xlsx?$' AND length(file_name) <= 255),
  mailbox text NOT NULL CHECK (mailbox='pdc@pmgwa.com.au'),
  sender text NOT NULL CHECK (sender='noreply@revolutionsoftware.com.au'),
  gmail_message_id text NOT NULL UNIQUE CHECK (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]')),
  received_at timestamptz NOT NULL,
  snapshot_at timestamptz NOT NULL,
  extract_text text NOT NULL CHECK (length(extract_text) <= 2000),
  source_rows integer NOT NULL CHECK (source_rows BETWEEN 0 AND 10000),
  stock_count integer NOT NULL CHECK (stock_count BETWEEN 0 AND 5000),
  lines jsonb NOT NULL CHECK (jsonb_typeof(lines)='array'),
  status text NOT NULL DEFAULT 'manifested' CHECK (status IN ('manifested','applied','revoked')),
  manifested_at timestamptz NOT NULL DEFAULT now(),
  preview_hash text CHECK (preview_hash IS NULL OR preview_hash ~ '^[0-9a-f]{64}$'),
  applied_at timestamptz,
  applied_by uuid,
  result jsonb,
  revoked_at timestamptz,
  CHECK ((status='applied') = (applied_at IS NOT NULL AND applied_by IS NOT NULL AND result IS NOT NULL))
);
CREATE TABLE pdc_sales_private.karratha_sales_accessory_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dealer_code text NOT NULL CHECK (dealer_code='14450'),
  order_key text NOT NULL CHECK (order_key <> ''),
  stock text NOT NULL CHECK (stock <> ''),
  quote text NOT NULL,
  line_key text NOT NULL CHECK (line_key ~ '^[0-9a-f]{64}$'),
  occurrence integer NOT NULL CHECK (occurrence >= 1),
  source_row integer,
  po_line text NOT NULL DEFAULT '',
  description text NOT NULL,
  notes text NOT NULL DEFAULT '',
  po_number text NOT NULL DEFAULT '',
  po_state text NOT NULL CHECK (po_state IN ('po','blank','cs_only','sell_only','no_update','other')),
  sub_type text NOT NULL DEFAULT '',
  txn_type text NOT NULL DEFAULT '',
  line_class text NOT NULL CHECK (line_class IN ('build','tint','tray','admin')),
  in_house boolean NOT NULL DEFAULT false,
  first_seen_receipt_id uuid NOT NULL REFERENCES pdc_sales_private.karratha_sales_accessory_receipts(id),
  first_seen_at timestamptz NOT NULL,
  last_seen_receipt_id uuid NOT NULL REFERENCES pdc_sales_private.karratha_sales_accessory_receipts(id),
  last_seen_at timestamptz NOT NULL,
  superseded_receipt_id uuid REFERENCES pdc_sales_private.karratha_sales_accessory_receipts(id),
  superseded_at timestamptz,
  CHECK ((superseded_receipt_id IS NULL) = (superseded_at IS NULL))
);
CREATE UNIQUE INDEX karratha_sales_accessory_lines_current_key ON pdc_sales_private.karratha_sales_accessory_lines (dealer_code, order_key, line_key) WHERE superseded_receipt_id IS NULL;
CREATE INDEX karratha_sales_accessory_lines_order ON pdc_sales_private.karratha_sales_accessory_lines (dealer_code, order_key);
CREATE TABLE pdc_sales_private.karratha_sales_accessory_vehicle_status (
  dealer_code text NOT NULL CHECK (dealer_code='14450'),
  order_key text NOT NULL CHECK (order_key <> ''),
  tracking_id uuid NOT NULL,
  navision_record_id uuid NOT NULL,
  stock text NOT NULL,
  quote text NOT NULL,
  receipt_id uuid NOT NULL REFERENCES pdc_sales_private.karratha_sales_accessory_receipts(id),
  snapshot_at timestamptz NOT NULL,
  build_state text NOT NULL CHECK (build_state IN ('green','grey','red','review')),
  tint_state text NOT NULL CHECK (tint_state IN ('green','grey','red','review')),
  tray_state text NOT NULL CHECK (tray_state IN ('green','grey','red','review')),
  ticks jsonb NOT NULL,
  line_count integer NOT NULL,
  version integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (dealer_code, order_key)
);
ALTER TABLE pdc_sales_private.karratha_sales_accessory_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.karratha_sales_accessory_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.karratha_sales_accessory_vehicle_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.karratha_sales_accessory_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.karratha_sales_accessory_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.karratha_sales_accessory_vehicle_status FORCE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_sales_private.karratha_sales_accessory_receipts, pdc_sales_private.karratha_sales_accessory_lines,
  pdc_sales_private.karratha_sales_accessory_vehicle_status FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION pdc_sales_private.karratha_sales_accessory_normalize_528(p_envelope jsonb, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $k528n$
DECLARE headers constant jsonb := '["Quote #","Stock #","PO Line","Price Level Desc","Notes","PO #","Transaction Sub-Type","Transaction Type"]';
  allowed constant text[] := ARRAY['row','Quote #','Stock #','PO Line','Price Level Desc','Notes','PO #','Transaction Sub-Type','Transaction Type'];
  r jsonb; k text; result jsonb; dealer text;
BEGIN
  -- r528 (F142): KTA Allocation Deal Items. Dept 105 and 107. No dealer column. Dealer is 14450.
  IF jsonb_typeof(p_envelope)<>'object' OR p_envelope->>'source_kind' IS DISTINCT FROM 'karratha_sales_deal_items_workbook'
     OR p_envelope->>'sheet' IS DISTINCT FROM 'Results' OR p_envelope->'header_row' IS DISTINCT FROM '4'::jsonb
     OR p_envelope->'headers' IS DISTINCT FROM headers THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: envelope source_kind/sheet/header_row/headers' USING errcode='22023';
  END IF;
  dealer := ltrim(coalesce(nullif(btrim(p_envelope->>'dealer_code'),''),'14450'),'0');
  IF dealer IS DISTINCT FROM '14450' THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: dealer must be Karratha 14450' USING errcode='22023';
  END IF;
  IF coalesce(p_envelope->>'file_name','') !~* '\.xlsx?$' THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: file_name must end .xls or .xlsx' USING errcode='22023';
  END IF;
  IF lower(btrim(coalesce(p_envelope->>'mailbox',''))) IS DISTINCT FROM 'pdc@pmgwa.com.au' THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: mailbox must be pdc@pmgwa.com.au' USING errcode='22023';
  END IF;
  IF lower(btrim(coalesce(p_envelope->>'sender',''))) IS DISTINCT FROM 'noreply@revolutionsoftware.com.au' THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: sender must be noreply@revolutionsoftware.com.au' USING errcode='22023';
  END IF;
  IF coalesce(p_envelope->>'extract_text','') !~ '^Extracted on [A-Za-z]+, [A-Za-z]+ \d{1,2}, \d{4} @ \d{1,2}:\d{2} [AP]M'
     OR p_envelope->>'extract_text' !~ 'Dept = "105"' OR p_envelope->>'extract_text' !~ 'Dept = "107"'
     OR p_envelope->>'extract_text' ~ 'Dept = "110"' OR p_envelope->>'extract_text' ~ 'Dept = "112"'
     OR p_envelope->>'extract_text' ~ 'Dept = "135"' THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: extract_text must be the row 2 stamp with Dept 105 and 107 only' USING errcode='22023';
  END IF;
  IF p_envelope ? 'extract_tz' AND coalesce(p_envelope->>'extract_tz','') NOT IN ('Australia/Perth','Australia/Brisbane','Australia/Sydney','Australia/Melbourne') THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: extract_tz must be Australia/Perth, Australia/Brisbane, Australia/Sydney or Australia/Melbourne' USING errcode='22023';
  END IF;
  IF jsonb_typeof(p_rows)<>'array' OR jsonb_array_length(p_rows)>10000
     OR (p_envelope->'source_rows') IS DISTINCT FROM to_jsonb(jsonb_array_length(p_rows)) THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: rows must be an array matching envelope.source_rows' USING errcode='22023';
  END IF;
  FOR r IN SELECT e FROM jsonb_array_elements(p_rows) e LOOP
    IF jsonb_typeof(r)<>'object' OR jsonb_typeof(r->'row')<>'number' THEN
      RAISE EXCEPTION 'karratha_sales_accessory_contract: each row needs an object with a numeric row' USING errcode='22023';
    END IF;
    FOR k IN SELECT jsonb_object_keys(r) LOOP
      IF NOT k = ANY(allowed) THEN RAISE EXCEPTION 'karratha_sales_accessory_contract: unexpected column %', k USING errcode='22023'; END IF;
      IF jsonb_typeof(r->k) NOT IN ('number','string','null') THEN RAISE EXCEPTION 'karratha_sales_accessory_contract: column % must be a scalar', k USING errcode='22023'; END IF;
    END LOOP;
  END LOOP;
  WITH raw AS (
    SELECT (e->>'row')::numeric::integer source_row,
      pdc_sales_private.sales_accessory_cell(e->'Quote #') quote,
      pdc_sales_private.sales_accessory_cell(e->'Stock #') stock_raw,
      pdc_sales_private.sales_accessory_cell(e->'PO Line') po_line,
      pdc_sales_private.sales_accessory_cell(e->'Price Level Desc') description,
      pdc_sales_private.sales_accessory_cell(e->'Notes') notes,
      pdc_sales_private.sales_accessory_cell(e->'PO #') po_number,
      pdc_sales_private.sales_accessory_cell(e->'Transaction Sub-Type') sub_type,
      pdc_sales_private.sales_accessory_cell(e->'Transaction Type') txn_type
    FROM jsonb_array_elements(p_rows) e
  ), typed AS (
    SELECT r.*, upper(r.stock_raw) stock,
      pdc_sales_private.sales_accessory_class(r.description, r.sub_type) line_class,
      pdc_sales_private.sales_accessory_po_state(r.po_number) po_state,
      pdc_sales_private.sales_accessory_in_house(r.description) in_house
    FROM raw r
  ), keyed AS (
    SELECT t.*, row_number() OVER (PARTITION BY t.stock, t.quote, t.po_line, t.sub_type, t.description, t.txn_type, t.notes, t.po_number ORDER BY t.source_row) occurrence
    FROM typed t
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('source_row',source_row,'quote',quote,'stock',stock,'po_line',po_line,
      'description',description,'notes',notes,'po_number',po_number,'sub_type',sub_type,'txn_type',txn_type,
      'line_class',line_class,'po_state',po_state,'in_house',in_house,'occurrence',occurrence,
      'line_key',encode(sha256(convert_to(jsonb_build_array(quote,po_line,sub_type,description,txn_type,notes,po_number,occurrence)::text,'UTF8')),'hex'))
    ORDER BY source_row),'[]'::jsonb) INTO result
  FROM keyed;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(result) e WHERE e->>'stock' IS NULL OR e->>'quote' IS NULL OR e->>'description' IS NULL
       OR e->>'notes' IS NULL OR e->>'po_number' IS NULL OR e->>'sub_type' IS NULL OR e->>'txn_type' IS NULL OR e->>'po_line' IS NULL) THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: unreadable cell' USING errcode='22023';
  END IF;
  IF (SELECT count(DISTINCT e->>'source_row') FROM jsonb_array_elements(result) e) <> jsonb_array_length(result)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(result) e WHERE (e->>'source_row')::integer < 5) THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: source rows must be unique and start after header row 4' USING errcode='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(result) e WHERE e->>'stock' !~ '^[A-Z0-9]{1,20}$') THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: stock numbers must be 1-20 letters or digits' USING errcode='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(result) e GROUP BY e->>'stock' HAVING count(DISTINCT e->>'quote')>1) THEN
    RAISE EXCEPTION 'karratha_sales_accessory_contract: a stock appears on more than one quote' USING errcode='22023';
  END IF;
  RETURN result;
END $k528n$;

CREATE FUNCTION pdc_sales_private.karratha_sales_accessory_candidates_528()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $k528c$
DECLARE result jsonb;
BEGIN
  -- r528 (F142): latest applied Navision batch for dealer 14450 only. Read. No tracked-order insert.
  WITH latest AS MATERIALIZED (
    SELECT b.id FROM public.navision_import_batches b WHERE b.source_system='microsoft_navision' AND b.dealer_code='14450'
      AND b.status='applied' AND b.rolled_back_at IS NULL ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
  ), source_rows AS (
    SELECT n.*, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) order_key
    FROM public.navision_backend_records n JOIN latest b ON b.id=n.last_seen_batch_id
    WHERE n.source_system='microsoft_navision' AND n.dealer_code='14450' AND n.is_current AND n.record_status='current'
  ), counted AS (
    SELECT n.*, count(*) OVER (PARTITION BY dealer_code, order_key) order_matches FROM source_rows n
  ), feed AS (
    SELECT n.id tracking_id, n.id navision_record_id, n.order_key, n.order_matches>1 identity_conflict,
      n.is_current, n.canonical_vehicle_id, v.id vehicle_id,
      upper(btrim(coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',''))) stock,
      coalesce(h.hidden,false) hidden,
      lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi'
        ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) IN ('yes','true','1') cosi
    FROM counted n
    LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
    LEFT JOIN LATERAL (SELECT x.hidden FROM pdc_sales_private.vehicle_visibility x
      WHERE x.tracking_id=n.id OR (x.dealer_code='14450' AND x.order_key=n.order_key)
      ORDER BY (x.tracking_id=n.id) DESC, x.changed_at DESC NULLS LAST LIMIT 1) h ON true
  )
  SELECT coalesce(jsonb_object_agg(f.stock, f.items),'{}'::jsonb) INTO result FROM (
    SELECT stock, jsonb_agg(jsonb_build_object('tracking_id',tracking_id,'navision_record_id',navision_record_id,'order_key',order_key,
      'identity_conflict',identity_conflict,'source_current',is_current,
      'visible',(cosi AND NOT hidden AND (canonical_vehicle_id IS NULL OR vehicle_id IS NOT NULL)),
      'cosi',cosi,'hidden',hidden,'linked_vehicle_deleted',(canonical_vehicle_id IS NOT NULL AND vehicle_id IS NULL))
      ORDER BY order_key, tracking_id) items
    FROM feed WHERE stock<>'' GROUP BY stock) f;
  RETURN result;
END $k528c$;

CREATE FUNCTION pdc_sales_private.karratha_sales_accessory_plan_528(p_lines jsonb, p_snapshot timestamptz)
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

CREATE FUNCTION pdc_sales_private.import_karratha_sales_accessories_20261025(p_action text, p_envelope jsonb, p_rows jsonb DEFAULT NULL::jsonb, p_expected_preview_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '120s'
AS $k528i$
DECLARE
  sha text := lower(coalesce(p_envelope->>'file_sha256',''));
  msg text := coalesce(nullif(p_envelope->>'gmail_message_id',''),nullif(p_envelope->>'internet_message_id',''),nullif(p_envelope->>'outlook_message_id',''),nullif(p_envelope->>'microsoft_message_id',''));
  rec pdc_sales_private.karratha_sales_accessory_receipts;
  by_msg pdc_sales_private.karratha_sales_accessory_receipts;
  v_lines jsonb; payload text; plan jsonb; summary jsonb;
  importer_id uuid; prior_ban timestamptz; restored_ban timestamptz; actor uuid; s jsonb; inserted int:=0; superseded int:=0; kept int:=0; v_result jsonb;
  snap timestamptz; m text[]; local_ts timestamp; tzs text[];
BEGIN
  IF NOT coalesce(pdc_codex_intake_private.management_connection(),false) THEN
    RAISE EXCEPTION 'karratha_sales_accessory_import: management connection required' USING errcode='42501';
  END IF;
  IF p_action NOT IN ('match','manifest','preview','apply','readback') THEN RAISE EXCEPTION 'karratha_sales_accessory_import: unknown action' USING errcode='22023'; END IF;
  IF sha !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'karratha_sales_accessory_import: file_sha256 required' USING errcode='22023'; END IF;
  IF p_action IN ('match','manifest') THEN
    IF msg IS NULL OR NOT (msg ~ '^[a-f0-9]+$' OR (length(msg) BETWEEN 8 AND 512 AND msg !~ '[[:space:]]')) THEN
      RAISE EXCEPTION 'karratha_sales_accessory_import: internet_message_id required' USING errcode='22023';
    END IF;
    v_lines := pdc_sales_private.karratha_sales_accessory_normalize_528(p_envelope, p_rows);
    payload := encode(sha256(convert_to(jsonb_build_object('extract_text',p_envelope->>'extract_text','lines',v_lines)::text,'UTF8')),'hex');
    m := regexp_match(p_envelope->>'extract_text','^Extracted on [A-Za-z]+, ([A-Za-z]+ \d{1,2}, \d{4}) @ (\d{1,2}:\d{2} [AP]M)');
    local_ts := to_timestamp(m[1]||' '||m[2],'FMMonth FMDD, YYYY FMHH12:MI AM')::timestamp;
    tzs := CASE WHEN p_envelope ? 'extract_tz' THEN ARRAY[p_envelope->>'extract_tz'] ELSE ARRAY['Australia/Perth'] END;
    snap := local_ts AT TIME ZONE tzs[1];
    IF snap > (p_envelope->>'received_at')::timestamptz + interval '10 minutes' THEN
      RAISE EXCEPTION 'karratha_sales_accessory_contract: extract stamp % is later than received_at; check extract_tz', snap USING errcode='22023';
    END IF;
  END IF;

  IF p_action='match' THEN
    plan := pdc_sales_private.karratha_sales_accessory_plan_528(v_lines, snap);
    summary := pdc_sales_private.sales_accessory_plan_summary(plan);
    RETURN jsonb_build_object('ok',true,'action','match','wrote',false,'replay',false,'dealer_code','14450',
      'file_sha256',sha,'gmail_message_id',msg,'snapshot_at',snap,'payload_sha256',payload,
      'source_rows',jsonb_array_length(p_rows),
      'stock_count',(SELECT count(DISTINCT e->>'stock') FROM jsonb_array_elements(v_lines) e),
      'preview_hash',plan->>'preview_hash','summary',summary,
      'vehicles_created',0,'jobs_created',0,'bookings_created',0);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc_sales_private.karratha_sales_accessories',0));
  SELECT * INTO rec FROM pdc_sales_private.karratha_sales_accessory_receipts WHERE file_sha256=sha FOR UPDATE;
  SELECT * INTO by_msg FROM pdc_sales_private.karratha_sales_accessory_receipts WHERE gmail_message_id=msg FOR UPDATE;

  IF p_action='manifest' THEN
    IF by_msg.id IS NOT NULL AND (rec.id IS NULL OR by_msg.id<>rec.id) THEN
      RETURN jsonb_build_object('ok',false,'code','message_id_sha_conflict','receipt_id',by_msg.id,'status',by_msg.status,'wrote',false);
    END IF;
    IF rec.id IS NOT NULL THEN
      IF rec.payload_sha256<>payload THEN
        RETURN jsonb_build_object('ok',false,'code','file_sha_payload_conflict','receipt_id',rec.id,'status',rec.status,'wrote',false);
      END IF;
      IF rec.snapshot_at IS DISTINCT FROM snap THEN
        RETURN jsonb_build_object('ok',false,'code','file_sha_snapshot_conflict','receipt_id',rec.id,'status',rec.status,'snapshot_at',rec.snapshot_at,'wrote',false);
      END IF;
      RETURN jsonb_build_object('ok',true,'replay',true,'wrote',false,'receipt_id',rec.id,'status',rec.status,'payload_sha256',rec.payload_sha256,
        'source_rows',rec.source_rows,'stock_count',rec.stock_count,'result',rec.result,'dealer_code','14450');
    END IF;
    INSERT INTO pdc_sales_private.karratha_sales_accessory_receipts (dealer_code,file_sha256,payload_sha256,file_name,mailbox,sender,gmail_message_id,received_at,snapshot_at,
      extract_text,source_rows,stock_count,lines)
    VALUES ('14450',sha,payload,p_envelope->>'file_name','pdc@pmgwa.com.au','noreply@revolutionsoftware.com.au',msg,
      (p_envelope->>'received_at')::timestamptz,snap,p_envelope->>'extract_text',jsonb_array_length(p_rows),
      (SELECT count(DISTINCT e->>'stock') FROM jsonb_array_elements(v_lines) e),v_lines)
    RETURNING * INTO rec;
    RETURN jsonb_build_object('ok',true,'replay',false,'wrote',true,'receipt_id',rec.id,'status',rec.status,'payload_sha256',rec.payload_sha256,
      'snapshot_at',rec.snapshot_at,'source_rows',rec.source_rows,'stock_count',rec.stock_count,'dealer_code','14450',
      'vehicles_created',0,'jobs_created',0,'bookings_created',0);
  END IF;

  IF rec.id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','manifest_missing','wrote',false); END IF;
  IF rec.dealer_code IS DISTINCT FROM '14450' THEN RAISE EXCEPTION 'karratha_sales_accessory_import: receipt dealer is not 14450' USING errcode='42501'; END IF;
  IF msg IS NOT NULL AND rec.gmail_message_id IS DISTINCT FROM msg THEN
    RETURN jsonb_build_object('ok',false,'code','message_id_sha_conflict','receipt_id',rec.id,'status',rec.status,'wrote',false);
  END IF;
  IF rec.status='revoked' THEN RETURN jsonb_build_object('ok',false,'code','receipt_revoked','receipt_id',rec.id,'wrote',false); END IF;

  IF p_action='readback' THEN
    RETURN jsonb_build_object('ok',true,'wrote',false,'receipt_id',rec.id,'status',rec.status,'file_sha256',rec.file_sha256,'snapshot_at',rec.snapshot_at,
      'applied_at',rec.applied_at,'result',rec.result,'dealer_code','14450',
      'live',jsonb_build_object(
        'status_rows',(SELECT count(*) FROM pdc_sales_private.karratha_sales_accessory_vehicle_status WHERE receipt_id=rec.id AND dealer_code='14450'),
        'current_lines_last_seen',(SELECT count(*) FROM pdc_sales_private.karratha_sales_accessory_lines WHERE last_seen_receipt_id=rec.id AND superseded_receipt_id IS NULL AND dealer_code='14450'),
        'lines_first_seen',(SELECT count(*) FROM pdc_sales_private.karratha_sales_accessory_lines WHERE first_seen_receipt_id=rec.id AND dealer_code='14450'),
        'lines_superseded',(SELECT count(*) FROM pdc_sales_private.karratha_sales_accessory_lines WHERE superseded_receipt_id=rec.id AND dealer_code='14450')));
  END IF;

  plan := pdc_sales_private.karratha_sales_accessory_plan_528(rec.lines, rec.snapshot_at);
  summary := pdc_sales_private.sales_accessory_plan_summary(plan);

  IF p_action='preview' THEN
    IF rec.status='applied' THEN RETURN jsonb_build_object('ok',true,'replay',true,'wrote',false,'receipt_id',rec.id,'status',rec.status,'result',rec.result,'dealer_code','14450'); END IF;
    UPDATE pdc_sales_private.karratha_sales_accessory_receipts SET preview_hash=plan->>'preview_hash' WHERE id=rec.id AND dealer_code='14450';
    RETURN jsonb_build_object('ok',true,'wrote',false,'receipt_id',rec.id,'status',rec.status,'preview_hash',plan->>'preview_hash','summary',summary,'dealer_code','14450',
      'vehicles_created',0,'jobs_created',0,'bookings_created',0,
      'stocks',(SELECT jsonb_agg(e - 'new_keys' - 'current_keys') FROM jsonb_array_elements(plan->'stocks') e));
  END IF;

  IF rec.status='applied' THEN RETURN jsonb_build_object('ok',true,'replay',true,'wrote',false,'receipt_id',rec.id,'status',rec.status,'result',rec.result,'dealer_code','14450'); END IF;
  IF p_expected_preview_hash IS NULL OR plan->>'preview_hash' <> lower(p_expected_preview_hash) THEN
    RETURN jsonb_build_object('ok',false,'code','stale_preview','receipt_id',rec.id,'preview_hash',plan->>'preview_hash','wrote',false);
  END IF;

  SELECT u.id, u.banned_until INTO importer_id, prior_ban FROM auth.users u
   WHERE lower(u.email)='codex.pmb.importer.staging@pmb.local' FOR UPDATE;
  IF importer_id IS NULL OR prior_ban IS NULL OR prior_ban <= now() THEN RAISE EXCEPTION 'importer_not_parked'; END IF;
  UPDATE auth.users SET banned_until=NULL WHERE id=importer_id;
  actor := pdc_codex_intake_private.import_actor();
  IF actor IS DISTINCT FROM importer_id THEN RAISE EXCEPTION 'importer_actor_unavailable'; END IF;

  FOR s IN SELECT e FROM jsonb_array_elements(plan->'stocks') e WHERE e->>'match'='matched' LOOP
    UPDATE pdc_sales_private.karratha_sales_accessory_lines l SET superseded_receipt_id=rec.id, superseded_at=rec.snapshot_at
     WHERE l.dealer_code='14450' AND l.order_key=s->>'order_key' AND l.superseded_receipt_id IS NULL AND NOT (s->'new_keys') ? l.line_key;
    GET DIAGNOSTICS kept=ROW_COUNT; superseded := superseded+kept;
    UPDATE pdc_sales_private.karratha_sales_accessory_lines l SET last_seen_receipt_id=rec.id, last_seen_at=rec.snapshot_at
     WHERE l.dealer_code='14450' AND l.order_key=s->>'order_key' AND l.superseded_receipt_id IS NULL AND (s->'new_keys') ? l.line_key;
    INSERT INTO pdc_sales_private.karratha_sales_accessory_lines (dealer_code,order_key,stock,quote,line_key,occurrence,source_row,po_line,description,notes,po_number,
      po_state,sub_type,txn_type,line_class,in_house,first_seen_receipt_id,first_seen_at,last_seen_receipt_id,last_seen_at)
    SELECT '14450', s->>'order_key', e->>'stock', e->>'quote', e->>'line_key', (e->>'occurrence')::int, (e->>'source_row')::int, e->>'po_line', e->>'description',
      e->>'notes', e->>'po_number', e->>'po_state', e->>'sub_type', e->>'txn_type', e->>'line_class', (e->>'in_house')::boolean,
      rec.id, rec.snapshot_at, rec.id, rec.snapshot_at
    FROM jsonb_array_elements(rec.lines) e
    WHERE e->>'stock'=s->>'stock' AND e->>'line_class'<>'empty'
      AND NOT EXISTS (SELECT 1 FROM pdc_sales_private.karratha_sales_accessory_lines l WHERE l.dealer_code='14450' AND l.order_key=s->>'order_key'
        AND l.superseded_receipt_id IS NULL AND l.line_key=e->>'line_key');
    GET DIAGNOSTICS kept=ROW_COUNT; inserted := inserted+kept;
    INSERT INTO pdc_sales_private.karratha_sales_accessory_vehicle_status AS t (dealer_code,order_key,tracking_id,navision_record_id,stock,quote,receipt_id,snapshot_at,
      build_state,tint_state,tray_state,ticks,line_count)
    VALUES ('14450',s->>'order_key',(s->>'tracking_id')::uuid,(s->>'navision_record_id')::uuid,s->>'stock',s->>'quote',rec.id,rec.snapshot_at,
      s->'ticks'->'build'->>'state',s->'ticks'->'tint'->>'state',s->'ticks'->'tray'->>'state',s->'ticks',(s->>'lines')::int)
    ON CONFLICT (dealer_code,order_key) DO UPDATE SET tracking_id=EXCLUDED.tracking_id,navision_record_id=EXCLUDED.navision_record_id,
      stock=EXCLUDED.stock,quote=EXCLUDED.quote,receipt_id=EXCLUDED.receipt_id,snapshot_at=EXCLUDED.snapshot_at,build_state=EXCLUDED.build_state,
      tint_state=EXCLUDED.tint_state,tray_state=EXCLUDED.tray_state,ticks=EXCLUDED.ticks,line_count=EXCLUDED.line_count,
      version=t.version+1,updated_at=now()
    WHERE t.dealer_code='14450' AND t.order_key=EXCLUDED.order_key;
  END LOOP;

  v_result := summary || jsonb_build_object('lines_inserted',inserted,'lines_superseded',superseded,'preview_hash',plan->>'preview_hash','actor_id',actor,
    'dealer_code','14450','vehicles_created',0,'jobs_created',0,'bookings_created',0);
  UPDATE pdc_sales_private.karratha_sales_accessory_receipts SET status='applied',applied_at=now(),applied_by=actor,result=v_result,preview_hash=plan->>'preview_hash'
   WHERE id=rec.id AND dealer_code='14450';

  UPDATE auth.users SET banned_until=prior_ban WHERE id=importer_id;
  SELECT banned_until INTO restored_ban FROM auth.users WHERE id=importer_id;
  IF restored_ban IS DISTINCT FROM prior_ban OR pdc_codex_intake_private.import_actor() IS NOT NULL THEN
    RAISE EXCEPTION 'importer_state_restore_failed';
  END IF;
  RETURN jsonb_build_object('ok',true,'replay',false,'wrote',true,'receipt_id',rec.id,'status','applied','result',v_result,'dealer_code','14450');
END $k528i$;

CREATE FUNCTION pdc_sales_private.get_karratha_sales_accessories_528()
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

CREATE OR REPLACE FUNCTION pdc_sales_private.get_accessories()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
 -- r495 (F108): Broome Toyota (37047) keeps the Sales Results accessory feed below.
 -- r528 (F142): Karratha Toyota (14450) reads its own accessory tables. Any other dealer stays empty.
 IF ctx->>'dealer_code'='14450' THEN RETURN pdc_sales_private.get_karratha_sales_accessories_528(); END IF;
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

REVOKE ALL ON FUNCTION pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb),
  pdc_sales_private.karratha_sales_accessory_candidates_528(),
  pdc_sales_private.karratha_sales_accessory_plan_528(jsonb,timestamptz),
  pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text),
  pdc_sales_private.get_karratha_sales_accessories_528()
  FROM PUBLIC, anon, authenticated, service_role;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='ff5de642f867c80b62d6c3fef987f131', release='r528',
 note='r528 (F142): Karratha 14450 reads its own accessory tables; Broome 37047 path unchanged (was 2f7f060cdaca01cc2763a15b921debf8 r495)', updated_at=now()
 WHERE signature='pdc_sales_private.get_accessories()';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at) VALUES
 ('pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)','ef85e5393c5039ac4e8421f6b058c405','r528','r528 (F142): KTA Allocation Deal Items contract, Dept 105/107, dealer 14450',now()),
 ('pdc_sales_private.karratha_sales_accessory_candidates_528()','b3fb58ca909d0f706426a4996dd9d489','r528','r528 (F142): current Karratha Navision stock, read only',now()),
 ('pdc_sales_private.karratha_sales_accessory_plan_528(jsonb,timestamp with time zone)','fd4caaffec31dcb70f47756676d40d37','r528','r528 (F142): match report, no vehicle insert',now()),
 ('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)','c70dc4234952dfb58cbc022c98bcecdb','r528','r528 (F142): Karratha Sales accessories import, Outlook pdc@ message id',now()),
 ('pdc_sales_private.get_karratha_sales_accessories_528()','faab38bf242ef572522dc4c3bf32285f','r528','r528 (F142): Karratha Sales accessory read',now());

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('karratha_sales_accessories_528','F142','Karratha Sales accessories (r528): import writes dealer 14450 only; Broome import body unchanged; no vehicle, job or booking insert; Outlook message id accepted; Dept 135 untouched',
 $chk528$SELECT
  (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)'))='46d4b464c5c1800c8ada245fb2d33bd3'
  AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)'))=(SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)')
  AND (SELECT position('37047' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)'))=0
  AND (SELECT position('public.vehicles' IN prosrc)+position('workshop_bookings' IN prosrc)+position('INSERT INTO public.' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)'))=0
  AND (SELECT position('internet_message_id' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)'))>0
  AND (SELECT position('pdc@pmgwa.com.au' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)'))>0
  AND NOT pg_catalog.has_function_privilege('anon','pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)','EXECUTE')
  AND NOT pg_catalog.has_function_privilege('authenticated','pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)','EXECUTE')
  AND NOT pg_catalog.has_function_privilege('service_role','pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)','EXECUTE')
  AND (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='pdc_sales_private.sales_accessory_receipts'::regclass AND conname='sales_accessory_receipts_dealer_code_check')='CHECK ((dealer_code = ''37047''::text))'
  AND (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='pdc_sales_private.karratha_sales_accessory_receipts'::regclass AND conname='karratha_sales_accessory_receipts_dealer_code_check') LIKE '%14450%'
  AND (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='pdc_sales_private.karratha_sales_accessory_receipts'::regclass AND conname='karratha_sales_accessory_receipts_dealer_code_check') NOT LIKE '%37047%'
  AND to_regprocedure('pdc_sales_private.import_karratha_sales_orders(jsonb,boolean)') IS NULL
  AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='karratha135_pdc' AND p.proname ILIKE '%accessor%')=0
$chk528$,true,309,'r528');

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r528: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM '46d4b464c5c1800c8ada245fb2d33bd3' THEN RAISE EXCEPTION 'r528: Broome import changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)')) IS DISTINCT FROM 'ef85e5393c5039ac4e8421f6b058c405' THEN RAISE EXCEPTION 'r528: normalize pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.karratha_sales_accessory_candidates_528()')) IS DISTINCT FROM 'b3fb58ca909d0f706426a4996dd9d489' THEN RAISE EXCEPTION 'r528: candidates pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.karratha_sales_accessory_plan_528(jsonb,timestamptz)')) IS DISTINCT FROM 'fd4caaffec31dcb70f47756676d40d37' THEN RAISE EXCEPTION 'r528: plan pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)')) IS DISTINCT FROM 'c70dc4234952dfb58cbc022c98bcecdb' THEN RAISE EXCEPTION 'r528: import pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_karratha_sales_accessories_528()')) IS DISTINCT FROM 'faab38bf242ef572522dc4c3bf32285f' THEN RAISE EXCEPTION 'r528: read pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_accessories()')) IS DISTINCT FROM 'ff5de642f867c80b62d6c3fef987f131' THEN RAISE EXCEPTION 'r528: get_accessories pin'; END IF;
 IF (SELECT position('37047' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_karratha_sales_accessories_20261025(text,jsonb,jsonb,text)'))<>0 THEN RAISE EXCEPTION 'r528: import mentions Broome dealer'; END IF;
END $p$;
