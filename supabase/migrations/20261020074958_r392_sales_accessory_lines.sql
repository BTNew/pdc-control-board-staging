-- r392: Broome sales accessory and PO lines with derived Build / Tint / Tray ticks (staging only).
-- Source: Broome Sales "Results" workbook (BT Allocation - Deal Items, Dept 110/112), headers on row 4.
-- PMB Email owns the feed; it calls pdc_sales_private.import_sales_accessories_20261020 over the
-- management connection. This migration never writes public.vehicles, Navision, jobs, bookings, the
-- 3 Oct sales_build_* data or the manual ordering ticks; matched lines attach to existing sales vehicles only.
DO $guard$
BEGIN
  IF current_database() <> 'postgres' OR NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='pdc_sales_private')
     OR to_regprocedure('pdc_codex_intake_private.management_connection()') IS NULL
     OR to_regprocedure('pdc_codex_intake_private.import_actor()') IS NULL THEN
    RAISE EXCEPTION 'r392 prerequisites missing';
  END IF;
  IF to_regclass('pdc_sales_private.sales_accessory_receipts') IS NOT NULL THEN
    RAISE EXCEPTION 'r392 already applied';
  END IF;
END $guard$;

CREATE TABLE pdc_sales_private.sales_accessory_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dealer_code text NOT NULL DEFAULT '37047' CHECK (dealer_code='37047'),
  file_sha256 text NOT NULL UNIQUE CHECK (file_sha256 ~ '^[0-9a-f]{64}$'),
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  file_name text NOT NULL CHECK (file_name ~* '\.xlsx$' AND length(file_name) <= 255),
  mailbox text NOT NULL CHECK (length(mailbox) BETWEEN 3 AND 320),
  sender text NOT NULL CHECK (length(sender) BETWEEN 1 AND 320),
  gmail_message_id text NOT NULL CHECK (gmail_message_id ~ '^[A-Za-z0-9_-]{6,128}$'),
  received_at timestamptz NOT NULL,
  snapshot_at timestamptz NOT NULL,
  extract_text text NOT NULL CHECK (length(extract_text) <= 2000),
  source_rows integer NOT NULL CHECK (source_rows BETWEEN 0 AND 10000),
  stock_count integer NOT NULL CHECK (stock_count BETWEEN 0 AND 2000),
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
CREATE TABLE pdc_sales_private.sales_accessory_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dealer_code text NOT NULL DEFAULT '37047' CHECK (dealer_code='37047'),
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
  first_seen_receipt_id uuid NOT NULL REFERENCES pdc_sales_private.sales_accessory_receipts(id),
  first_seen_at timestamptz NOT NULL,
  last_seen_receipt_id uuid NOT NULL REFERENCES pdc_sales_private.sales_accessory_receipts(id),
  last_seen_at timestamptz NOT NULL,
  superseded_receipt_id uuid REFERENCES pdc_sales_private.sales_accessory_receipts(id),
  superseded_at timestamptz,
  CHECK ((superseded_receipt_id IS NULL) = (superseded_at IS NULL))
);
CREATE UNIQUE INDEX sales_accessory_lines_current_key ON pdc_sales_private.sales_accessory_lines (dealer_code, order_key, line_key) WHERE superseded_receipt_id IS NULL;
CREATE INDEX sales_accessory_lines_order ON pdc_sales_private.sales_accessory_lines (dealer_code, order_key);
CREATE TABLE pdc_sales_private.sales_accessory_vehicle_status (
  dealer_code text NOT NULL DEFAULT '37047' CHECK (dealer_code='37047'),
  order_key text NOT NULL CHECK (order_key <> ''),
  tracking_id uuid NOT NULL,
  navision_record_id uuid NOT NULL,
  stock text NOT NULL,
  quote text NOT NULL,
  receipt_id uuid NOT NULL REFERENCES pdc_sales_private.sales_accessory_receipts(id),
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
ALTER TABLE pdc_sales_private.sales_accessory_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.sales_accessory_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.sales_accessory_vehicle_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.sales_accessory_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.sales_accessory_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.sales_accessory_vehicle_status FORCE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_sales_private.sales_accessory_receipts, pdc_sales_private.sales_accessory_lines,
  pdc_sales_private.sales_accessory_vehicle_status FROM PUBLIC, anon, authenticated, service_role;

-- Classification mirrors classify.py (20 Oct findings); Python \b is \y here.
CREATE FUNCTION pdc_sales_private.sales_accessory_class(p_description text, p_sub_type text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  SELECT CASE
    WHEN coalesce(p_description,'')='' THEN 'empty'
    WHEN p_description ~* 'freight|transport|fleet return|delivery to|deliver to|pit and weigh|pre delivery|tsa|capped price|service free|\yrego|3rd party.*(fee|tba)|sublet fee' THEN 'admin'
    WHEN p_description ~* '\ytint' AND p_description !~* 'bonnet protector' THEN 'tint'
    WHEN (coalesce(p_sub_type,'') LIKE 'TR8%' OR p_description ~* 'tray body|steel tray|alloy tray|\yHD[AS]?\y.*tray|tray.*\yROPS\y|custom .*body build|body build')
      AND p_description !~* 'tow ?bar|towing|camera|under ?tray|headboard|rear of tray|to tray|tool ?box|water tank|tyre hanger|canopy to tray' THEN 'tray'
    ELSE 'build' END
$f$;
CREATE FUNCTION pdc_sales_private.sales_accessory_po_state(p_po text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  SELECT CASE
    WHEN upper(btrim(coalesce(p_po,''))) IN ('','NONE') THEN 'blank'
    WHEN upper(btrim(p_po)) ~ '^PO\d+$' THEN 'po'
    WHEN upper(btrim(p_po))='C&S ONLY' THEN 'cs_only'
    WHEN upper(btrim(p_po))='SELL ONLY' THEN 'sell_only'
    WHEN upper(btrim(p_po))='NO UPDATE' THEN 'no_update'
    ELSE 'other' END
$f$;
-- Craig 20 Oct: in-house no-PO lines (Install Supplied..., Transfer..., Dash Mat) never trigger the flash.
CREATE FUNCTION pdc_sales_private.sales_accessory_in_house(p_description text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  SELECT coalesce(p_description,'') ~* '^\s*install\s+supplied\y|^\s*transfer\y|\ydash\s*mat\y'
$f$;
-- Derived tick for one group from line objects {line_class, po_state, in_house}.
CREATE FUNCTION pdc_sales_private.sales_accessory_tick(p_lines jsonb, p_class text)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
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
$f$;
CREATE FUNCTION pdc_sales_private.sales_accessory_ticks(p_lines jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  SELECT jsonb_build_object('build',pdc_sales_private.sales_accessory_tick(p_lines,'build'),
    'tint',pdc_sales_private.sales_accessory_tick(p_lines,'tint'),'tray',pdc_sales_private.sales_accessory_tick(p_lines,'tray'))
$f$;

-- Workbook cell to text: integral numbers lose any ".0"; strings are trimmed; null is ''.
CREATE FUNCTION pdc_sales_private.sales_accessory_cell(p jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  SELECT CASE jsonb_typeof(p)
    WHEN 'number' THEN CASE WHEN (p#>>'{}')::numeric = trunc((p#>>'{}')::numeric) THEN trunc((p#>>'{}')::numeric)::text ELSE (p#>>'{}') END
    WHEN 'string' THEN btrim(p#>>'{}', E' \t\r\n')
    WHEN 'null' THEN '' WHEN NULL THEN ''
    ELSE NULL END
$f$;

-- Validates the PMB Email envelope + rows and returns normalized lines. Raises on any contract breach.
CREATE FUNCTION pdc_sales_private.sales_accessory_normalize(p_envelope jsonb, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $f$
DECLARE headers constant jsonb := '["Quote #","Stock #","PO Line","Price Level Desc","Notes","PO #","Transaction Sub-Type","Transaction Type"]';
  allowed constant text[] := ARRAY['row','Quote #','Stock #','PO Line','Price Level Desc','Notes','PO #','Transaction Sub-Type','Transaction Type'];
  r jsonb; k text; result jsonb;
BEGIN
  IF jsonb_typeof(p_envelope)<>'object' OR p_envelope->>'source_kind' IS DISTINCT FROM 'broome_sales_deal_items_workbook'
     OR p_envelope->>'sheet' IS DISTINCT FROM 'Results' OR p_envelope->'header_row' IS DISTINCT FROM '4'::jsonb
     OR p_envelope->'headers' IS DISTINCT FROM headers THEN
    RAISE EXCEPTION 'sales_accessory_contract: envelope source_kind/sheet/header_row/headers' USING errcode='22023';
  END IF;
  IF coalesce(p_envelope->>'extract_text','') !~ '^Extracted on [A-Za-z]+, [A-Za-z]+ \d{1,2}, \d{4} @ \d{1,2}:\d{2} [AP]M'
     OR p_envelope->>'extract_text' !~ 'Dept = "110"' OR p_envelope->>'extract_text' !~ 'Dept = "112"' THEN
    RAISE EXCEPTION 'sales_accessory_contract: extract_text must be the row 2 stamp with Dept 110 and 112' USING errcode='22023';
  END IF;
  IF jsonb_typeof(p_rows)<>'array' OR jsonb_array_length(p_rows)>10000
     OR (p_envelope->'source_rows') IS DISTINCT FROM to_jsonb(jsonb_array_length(p_rows)) THEN
    RAISE EXCEPTION 'sales_accessory_contract: rows must be an array matching envelope.source_rows' USING errcode='22023';
  END IF;
  FOR r IN SELECT e FROM jsonb_array_elements(p_rows) e LOOP
    IF jsonb_typeof(r)<>'object' OR jsonb_typeof(r->'row')<>'number' THEN
      RAISE EXCEPTION 'sales_accessory_contract: each row needs an object with a numeric row' USING errcode='22023';
    END IF;
    FOR k IN SELECT jsonb_object_keys(r) LOOP
      IF NOT k = ANY(allowed) THEN RAISE EXCEPTION 'sales_accessory_contract: unexpected column %', k USING errcode='22023'; END IF;
      IF jsonb_typeof(r->k) NOT IN ('number','string','null') THEN RAISE EXCEPTION 'sales_accessory_contract: column % must be a scalar', k USING errcode='22023'; END IF;
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
    RAISE EXCEPTION 'sales_accessory_contract: unreadable cell' USING errcode='22023';
  END IF;
  IF (SELECT count(DISTINCT e->>'source_row') FROM jsonb_array_elements(result) e) <> jsonb_array_length(result)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(result) e WHERE (e->>'source_row')::integer < 5) THEN
    RAISE EXCEPTION 'sales_accessory_contract: source rows must be unique and start after header row 4' USING errcode='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(result) e WHERE e->>'stock' !~ '^[A-Z0-9]{1,20}$') THEN
    RAISE EXCEPTION 'sales_accessory_contract: stock numbers must be 1-20 letters or digits' USING errcode='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(result) e GROUP BY e->>'stock' HAVING count(DISTINCT e->>'quote')>1) THEN
    RAISE EXCEPTION 'sales_accessory_contract: a stock appears on more than one quote' USING errcode='22023';
  END IF;
  RETURN result;
END $f$;

-- Context-free copy of the Broome sales visibility rules (as build_stock_counts/get_builds):
-- latest applied Navision batch for 37047, current rows, COSI yes, not hidden, linked vehicle not deleted.
CREATE FUNCTION pdc_sales_private.sales_accessory_candidates()
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog, public, pdc_sales_private AS $f$
DECLARE result jsonb;
BEGIN
  WITH latest AS MATERIALIZED (
    SELECT b.id FROM public.navision_import_batches b WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047'
      AND b.status='applied' AND b.rolled_back_at IS NULL ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
  ), source_rows AS (
    SELECT n.*, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) order_key
    FROM public.navision_backend_records n JOIN latest b ON b.id=n.last_seen_batch_id
    WHERE n.source_system='microsoft_navision' AND n.dealer_code='37047' AND n.is_current AND n.record_status='current'
  ), counted AS (
    SELECT n.*, count(*) OVER (PARTITION BY dealer_code, order_key) order_matches FROM source_rows n
  ), feed AS (
    SELECT coalesce(o.id,n.id) tracking_id, n.id navision_record_id, n.order_key, n.order_matches>1 identity_conflict,
      n.is_current, n.canonical_vehicle_id, v.id vehicle_id,
      upper(btrim(coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',v.stock_number,''))) stock,
      CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END salesperson_code,
      coalesce(h.hidden,false) hidden,
      lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi'
        ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) IN ('yes','true','1') cosi
    FROM counted n
    LEFT JOIN pdc_sales_private.tracked_orders o ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
    LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
    LEFT JOIN LATERAL (SELECT x.hidden FROM pdc_sales_private.vehicle_visibility x
      WHERE x.tracking_id=coalesce(o.id,n.id) OR (n.order_matches=1 AND x.dealer_code=n.dealer_code AND x.order_key=n.order_key)
      ORDER BY (x.tracking_id=coalesce(o.id,n.id)) DESC LIMIT 1) h ON true
    LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
    LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
      nullif(btrim(public.navision_original_column_value(n.normalized_data,'Salesperson')),''),
      nullif(n.normalized_data->>'salesperson',''),nullif(n.normalized_data->>'consultant',''),n.normalized_data->>'owner','')),' ',1))
  )
  SELECT coalesce(jsonb_object_agg(f.stock, f.items),'{}'::jsonb) INTO result FROM (
    SELECT stock, jsonb_agg(jsonb_build_object('tracking_id',tracking_id,'navision_record_id',navision_record_id,'order_key',order_key,
      'identity_conflict',identity_conflict,'source_current',is_current,'salesperson_code',salesperson_code,
      'visible',(cosi AND NOT hidden AND (canonical_vehicle_id IS NULL OR vehicle_id IS NOT NULL)),
      'cosi',cosi,'hidden',hidden,'linked_vehicle_deleted',(canonical_vehicle_id IS NOT NULL AND vehicle_id IS NULL))
      ORDER BY order_key, tracking_id) items
    FROM feed WHERE stock<>'' GROUP BY stock) f;
  RETURN result;
END $f$;

-- Read-only plan for a manifested receipt. Hash binds every decision and the current line state.
CREATE FUNCTION pdc_sales_private.sales_accessory_plan(p_receipt_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog, pdc_sales_private AS $f$
DECLARE rec pdc_sales_private.sales_accessory_receipts; cand jsonb := pdc_sales_private.sales_accessory_candidates(); stocks jsonb; plan jsonb;
BEGIN
  SELECT * INTO rec FROM pdc_sales_private.sales_accessory_receipts WHERE id=p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'sales_accessory_receipt_missing'; END IF;
  WITH file_stocks AS (
    SELECT e->>'stock' stock, min(e->>'quote') quote,
      coalesce(jsonb_agg(e ORDER BY (e->>'source_row')::integer) FILTER (WHERE e->>'line_class'<>'empty'),'[]'::jsonb) lines,
      count(*) FILTER (WHERE e->>'line_class'='empty') empty_rows
    FROM jsonb_array_elements(rec.lines) e GROUP BY e->>'stock'
  ), matched AS (
    SELECT s.*,
      coalesce(cand->s.stock, CASE WHEN s.stock ~ '^\d{1,7}$' THEN cand->lpad(s.stock,8,'0') END, '[]'::jsonb) all_c
    FROM file_stocks s
  ), judged AS (
    SELECT m.*, v.visible_c,
      CASE
        WHEN jsonb_array_length(v.visible_c)=0 AND EXISTS (SELECT 1 FROM jsonb_array_elements(m.all_c) c WHERE (c->>'linked_vehicle_deleted')::boolean) THEN 'linked_pdc_vehicle_deleted'
        WHEN jsonb_array_length(v.visible_c)=0 AND jsonb_array_length(m.all_c)>0 THEN 'not_visible_sales_vehicle'
        WHEN jsonb_array_length(v.visible_c)=0 THEN 'not_on_current_broome_navision'
        WHEN jsonb_array_length(v.visible_c)>1 THEN 'duplicate_current_stock'
        WHEN (v.visible_c->0->>'identity_conflict')::boolean THEN 'identity_conflict'
        WHEN coalesce(v.visible_c->0->>'order_key','')='' THEN 'missing_current_order'
        WHEN v.visible_c->0->>'source_current' IS DISTINCT FROM 'true' THEN 'source_not_current'
        WHEN coalesce(v.visible_c->0->>'salesperson_code','') NOT IN ('AW','BG','PM','CW') THEN 'outside_sales_roster'
        ELSE NULL END unmatched_reason
    FROM matched m
    CROSS JOIN LATERAL (SELECT coalesce(jsonb_agg(c),'[]'::jsonb) visible_c FROM jsonb_array_elements(m.all_c) c WHERE (c->>'visible')::boolean) v
  ), decided AS (
    SELECT j.*, st.snapshot_at status_snapshot, st.version status_version,
      CASE WHEN j.unmatched_reason IS NULL AND st.snapshot_at > rec.snapshot_at THEN 'older_than_current_snapshot' ELSE j.unmatched_reason END reason,
      (SELECT coalesce(jsonb_agg(l.line_key ORDER BY l.line_key),'[]'::jsonb) FROM pdc_sales_private.sales_accessory_lines l
        WHERE l.dealer_code='37047' AND l.order_key=j.visible_c->0->>'order_key' AND l.superseded_receipt_id IS NULL) current_keys
    FROM judged j
    LEFT JOIN pdc_sales_private.sales_accessory_vehicle_status st ON st.dealer_code='37047' AND st.order_key=j.visible_c->0->>'order_key'
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
  plan := jsonb_build_object('receipt_id',rec.id,'file_sha256',rec.file_sha256,'payload_sha256',rec.payload_sha256,
    'snapshot_at',rec.snapshot_at,'stocks',stocks);
  RETURN plan || jsonb_build_object('preview_hash',encode(sha256(convert_to(plan::text,'UTF8')),'hex'));
END $f$;

-- Summary of a plan for PMB Email (counts per state and per action).
CREATE FUNCTION pdc_sales_private.sales_accessory_plan_summary(p_plan jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
  WITH s AS (SELECT e FROM jsonb_array_elements(p_plan->'stocks') e),
  m AS (SELECT e FROM s WHERE e->>'match'='matched'),
  k AS (SELECT e, (SELECT count(*) FROM jsonb_array_elements_text(e->'new_keys') n WHERE NOT (e->'current_keys') ? n) ins,
      (SELECT count(*) FROM jsonb_array_elements_text(e->'current_keys') c WHERE NOT (e->'new_keys') ? c) sup,
      (SELECT count(*) FROM jsonb_array_elements_text(e->'new_keys') n WHERE (e->'current_keys') ? n) kept FROM m)
  SELECT jsonb_build_object('stocks',(SELECT count(*) FROM s),'matched',(SELECT count(*) FROM m),
    'unmatched',(SELECT count(*) FROM s WHERE e->>'match'<>'matched'),
    'unmatched_by_reason',(SELECT coalesce(jsonb_object_agg(r,c),'{}'::jsonb) FROM (SELECT e->>'reason' r,count(*) c FROM s WHERE e->>'match'<>'matched' GROUP BY 1) x),
    'unmatched_stocks',(SELECT coalesce(jsonb_agg(jsonb_build_object('stock',e->>'stock','reason',e->>'reason') ORDER BY e->>'stock'),'[]'::jsonb) FROM s WHERE e->>'match'<>'matched'),
    'lines_insert',(SELECT coalesce(sum(ins),0) FROM k),'lines_supersede',(SELECT coalesce(sum(sup),0) FROM k),'lines_kept',(SELECT coalesce(sum(kept),0) FROM k),
    'ticks',(SELECT jsonb_object_agg(g,cnt) FROM (SELECT g, jsonb_object_agg(st,c) cnt FROM (SELECT g, m.e->'ticks'->g->>'state' st, count(*) c
       FROM m, unnest(ARRAY['build','tint','tray']) g GROUP BY 1,2) y GROUP BY g) z))
$f$;

-- PMB Email import entry point (management connection only; postgres-owned; no role grants).
-- p_action: manifest (store rows, idempotent on file sha) | preview (read-only plan + hash)
--           | apply (needs preview hash; bound importer enable/re-ban) | readback (stored receipt + live recount).
CREATE FUNCTION pdc_sales_private.import_sales_accessories_20261020(p_action text, p_envelope jsonb, p_rows jsonb DEFAULT NULL, p_expected_preview_hash text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql
SET search_path=pg_catalog SET lock_timeout='5s' SET statement_timeout='120s' AS $f$
DECLARE
  sha text := lower(coalesce(p_envelope->>'file_sha256',''));
  rec pdc_sales_private.sales_accessory_receipts; v_lines jsonb; payload text; plan jsonb; summary jsonb;
  importer_id uuid; prior_ban timestamptz; restored_ban timestamptz; actor uuid; s jsonb; inserted int:=0; superseded int:=0; kept int:=0; v_result jsonb;
  snap timestamptz; m text[];
BEGIN
  IF NOT coalesce(pdc_codex_intake_private.management_connection(),false) THEN
    RAISE EXCEPTION 'sales_accessory_import: management connection required' USING errcode='42501';
  END IF;
  IF p_action NOT IN ('manifest','preview','apply','readback') THEN RAISE EXCEPTION 'sales_accessory_import: unknown action' USING errcode='22023'; END IF;
  IF sha !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'sales_accessory_import: file_sha256 required' USING errcode='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc_sales_private.sales_accessories',0));

  SELECT * INTO rec FROM pdc_sales_private.sales_accessory_receipts WHERE file_sha256=sha FOR UPDATE;

  IF p_action='manifest' THEN
    v_lines := pdc_sales_private.sales_accessory_normalize(p_envelope, p_rows);
    -- Payload = the workbook content (extract stamp + normalized rows); mail metadata may differ on a re-send of the same file.
    payload := encode(sha256(convert_to(jsonb_build_object('extract_text',p_envelope->>'extract_text','lines',v_lines)::text,'UTF8')),'hex');
    IF FOUND THEN
      IF rec.payload_sha256<>payload THEN
        RETURN jsonb_build_object('ok',false,'code','file_sha_payload_conflict','receipt_id',rec.id,'status',rec.status);
      END IF;
      RETURN jsonb_build_object('ok',true,'replay',true,'receipt_id',rec.id,'status',rec.status,'payload_sha256',rec.payload_sha256,
        'source_rows',rec.source_rows,'stock_count',rec.stock_count,'result',rec.result);
    END IF;
    m := regexp_match(p_envelope->>'extract_text','^Extracted on [A-Za-z]+, ([A-Za-z]+ \d{1,2}, \d{4}) @ (\d{1,2}:\d{2} [AP]M)');
    snap := (to_timestamp(m[1]||' '||m[2],'FMMonth FMDD, YYYY FMHH12:MI AM')::timestamp) AT TIME ZONE 'Australia/Perth';
    INSERT INTO pdc_sales_private.sales_accessory_receipts (file_sha256,payload_sha256,file_name,mailbox,sender,gmail_message_id,received_at,snapshot_at,
      extract_text,source_rows,stock_count,lines)
    VALUES (sha,payload,p_envelope->>'file_name',p_envelope->>'mailbox',p_envelope->>'sender',p_envelope->>'gmail_message_id',
      (p_envelope->>'received_at')::timestamptz,snap,p_envelope->>'extract_text',jsonb_array_length(p_rows),
      (SELECT count(DISTINCT e->>'stock') FROM jsonb_array_elements(v_lines) e),v_lines)
    RETURNING * INTO rec;
    RETURN jsonb_build_object('ok',true,'replay',false,'receipt_id',rec.id,'status',rec.status,'payload_sha256',rec.payload_sha256,
      'snapshot_at',rec.snapshot_at,'source_rows',rec.source_rows,'stock_count',rec.stock_count);
  END IF;

  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','manifest_missing'); END IF;
  IF rec.status='revoked' THEN RETURN jsonb_build_object('ok',false,'code','receipt_revoked','receipt_id',rec.id); END IF;

  IF p_action='readback' THEN
    RETURN jsonb_build_object('ok',true,'receipt_id',rec.id,'status',rec.status,'file_sha256',rec.file_sha256,'snapshot_at',rec.snapshot_at,
      'applied_at',rec.applied_at,'result',rec.result,
      'live',jsonb_build_object(
        'status_rows',(SELECT count(*) FROM pdc_sales_private.sales_accessory_vehicle_status WHERE receipt_id=rec.id),
        'current_lines_last_seen',(SELECT count(*) FROM pdc_sales_private.sales_accessory_lines WHERE last_seen_receipt_id=rec.id AND superseded_receipt_id IS NULL),
        'lines_first_seen',(SELECT count(*) FROM pdc_sales_private.sales_accessory_lines WHERE first_seen_receipt_id=rec.id),
        'lines_superseded',(SELECT count(*) FROM pdc_sales_private.sales_accessory_lines WHERE superseded_receipt_id=rec.id),
        'tick_states',(SELECT jsonb_build_object(
          'build',(SELECT jsonb_object_agg(build_state,c) FROM (SELECT build_state,count(*) c FROM pdc_sales_private.sales_accessory_vehicle_status WHERE receipt_id=rec.id GROUP BY 1) x),
          'tint',(SELECT jsonb_object_agg(tint_state,c) FROM (SELECT tint_state,count(*) c FROM pdc_sales_private.sales_accessory_vehicle_status WHERE receipt_id=rec.id GROUP BY 1) x),
          'tray',(SELECT jsonb_object_agg(tray_state,c) FROM (SELECT tray_state,count(*) c FROM pdc_sales_private.sales_accessory_vehicle_status WHERE receipt_id=rec.id GROUP BY 1) x)))),
      'consistent',CASE WHEN rec.status<>'applied' THEN NULL ELSE
        (SELECT count(*) FROM pdc_sales_private.sales_accessory_lines WHERE first_seen_receipt_id=rec.id)=(rec.result->>'lines_inserted')::int
        AND (SELECT count(*) FROM pdc_sales_private.sales_accessory_lines WHERE superseded_receipt_id=rec.id)=(rec.result->>'lines_superseded')::int END);
  END IF;

  IF p_action='preview' THEN
    IF rec.status='applied' THEN RETURN jsonb_build_object('ok',true,'replay',true,'receipt_id',rec.id,'status',rec.status,'result',rec.result); END IF;
    plan := pdc_sales_private.sales_accessory_plan(rec.id);
    summary := pdc_sales_private.sales_accessory_plan_summary(plan);
    UPDATE pdc_sales_private.sales_accessory_receipts SET preview_hash=plan->>'preview_hash' WHERE id=rec.id;
    RETURN jsonb_build_object('ok',true,'receipt_id',rec.id,'status',rec.status,'preview_hash',plan->>'preview_hash','summary',summary,
      'stocks',(SELECT jsonb_agg(e - 'new_keys' - 'current_keys') FROM jsonb_array_elements(plan->'stocks') e));
  END IF;

  -- apply
  IF rec.status='applied' THEN RETURN jsonb_build_object('ok',true,'replay',true,'receipt_id',rec.id,'status',rec.status,'result',rec.result); END IF;
  plan := pdc_sales_private.sales_accessory_plan(rec.id);
  IF p_expected_preview_hash IS NULL OR plan->>'preview_hash' <> lower(p_expected_preview_hash) THEN
    RETURN jsonb_build_object('ok',false,'code','stale_preview','receipt_id',rec.id,'preview_hash',plan->>'preview_hash');
  END IF;
  summary := pdc_sales_private.sales_accessory_plan_summary(plan);

  SELECT u.id, u.banned_until INTO importer_id, prior_ban FROM auth.users u
   WHERE lower(u.email)='codex.pmb.importer.staging@pmb.local' FOR UPDATE;
  IF importer_id IS NULL OR prior_ban IS NULL OR prior_ban <= now() THEN RAISE EXCEPTION 'importer_not_parked'; END IF;
  UPDATE auth.users SET banned_until=NULL WHERE id=importer_id;
  actor := pdc_codex_intake_private.import_actor();
  IF actor IS DISTINCT FROM importer_id THEN RAISE EXCEPTION 'importer_actor_unavailable'; END IF;

  FOR s IN SELECT e FROM jsonb_array_elements(plan->'stocks') e WHERE e->>'match'='matched' LOOP
    UPDATE pdc_sales_private.sales_accessory_lines l SET superseded_receipt_id=rec.id, superseded_at=rec.snapshot_at
     WHERE l.dealer_code='37047' AND l.order_key=s->>'order_key' AND l.superseded_receipt_id IS NULL AND NOT (s->'new_keys') ? l.line_key;
    GET DIAGNOSTICS kept=ROW_COUNT; superseded := superseded+kept;
    UPDATE pdc_sales_private.sales_accessory_lines l SET last_seen_receipt_id=rec.id, last_seen_at=rec.snapshot_at
     WHERE l.dealer_code='37047' AND l.order_key=s->>'order_key' AND l.superseded_receipt_id IS NULL AND (s->'new_keys') ? l.line_key;
    INSERT INTO pdc_sales_private.sales_accessory_lines (order_key,stock,quote,line_key,occurrence,source_row,po_line,description,notes,po_number,
      po_state,sub_type,txn_type,line_class,in_house,first_seen_receipt_id,first_seen_at,last_seen_receipt_id,last_seen_at)
    SELECT s->>'order_key', e->>'stock', e->>'quote', e->>'line_key', (e->>'occurrence')::int, (e->>'source_row')::int, e->>'po_line', e->>'description',
      e->>'notes', e->>'po_number', e->>'po_state', e->>'sub_type', e->>'txn_type', e->>'line_class', (e->>'in_house')::boolean,
      rec.id, rec.snapshot_at, rec.id, rec.snapshot_at
    FROM jsonb_array_elements(rec.lines) e
    WHERE e->>'stock'=s->>'stock' AND e->>'line_class'<>'empty'
      AND NOT EXISTS (SELECT 1 FROM pdc_sales_private.sales_accessory_lines l WHERE l.dealer_code='37047' AND l.order_key=s->>'order_key'
        AND l.superseded_receipt_id IS NULL AND l.line_key=e->>'line_key');
    GET DIAGNOSTICS kept=ROW_COUNT; inserted := inserted+kept;
    INSERT INTO pdc_sales_private.sales_accessory_vehicle_status AS t (order_key,tracking_id,navision_record_id,stock,quote,receipt_id,snapshot_at,
      build_state,tint_state,tray_state,ticks,line_count)
    VALUES (s->>'order_key',(s->>'tracking_id')::uuid,(s->>'navision_record_id')::uuid,s->>'stock',s->>'quote',rec.id,rec.snapshot_at,
      s->'ticks'->'build'->>'state',s->'ticks'->'tint'->>'state',s->'ticks'->'tray'->>'state',s->'ticks',(s->>'lines')::int)
    ON CONFLICT (dealer_code,order_key) DO UPDATE SET tracking_id=EXCLUDED.tracking_id,navision_record_id=EXCLUDED.navision_record_id,
      stock=EXCLUDED.stock,quote=EXCLUDED.quote,receipt_id=EXCLUDED.receipt_id,snapshot_at=EXCLUDED.snapshot_at,build_state=EXCLUDED.build_state,
      tint_state=EXCLUDED.tint_state,tray_state=EXCLUDED.tray_state,ticks=EXCLUDED.ticks,line_count=EXCLUDED.line_count,
      version=t.version+1,updated_at=now()
    WHERE t.dealer_code='37047' AND t.order_key=EXCLUDED.order_key;
  END LOOP;

  v_result := summary || jsonb_build_object('lines_inserted',inserted,'lines_superseded',superseded,'preview_hash',plan->>'preview_hash','actor_id',actor);
  UPDATE pdc_sales_private.sales_accessory_receipts SET status='applied',applied_at=now(),applied_by=actor,result=v_result,preview_hash=plan->>'preview_hash'
   WHERE id=rec.id;

  UPDATE auth.users SET banned_until=prior_ban WHERE id=importer_id;
  SELECT banned_until INTO restored_ban FROM auth.users WHERE id=importer_id;
  IF restored_ban IS DISTINCT FROM prior_ban OR pdc_codex_intake_private.import_actor() IS NOT NULL THEN
    RAISE EXCEPTION 'importer_state_restore_failed';
  END IF;
  RETURN jsonb_build_object('ok',true,'replay',false,'receipt_id',rec.id,'status','applied','result',v_result);
END $f$;

-- Signed-in sales read (scoped exactly like get_builds): current lines and display ticks per visible vehicle.
CREATE FUNCTION pdc_sales_private.get_accessories()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog, public, pdc_sales_private AS $f$
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
END $f$;

CREATE FUNCTION public.get_broome_sales_accessories()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $f$ SELECT pdc_sales_private.get_accessories() $f$;

REVOKE ALL ON FUNCTION pdc_sales_private.sales_accessory_class(text,text), pdc_sales_private.sales_accessory_po_state(text),
  pdc_sales_private.sales_accessory_in_house(text), pdc_sales_private.sales_accessory_tick(jsonb,text), pdc_sales_private.sales_accessory_ticks(jsonb),
  pdc_sales_private.sales_accessory_cell(jsonb), pdc_sales_private.sales_accessory_normalize(jsonb,jsonb), pdc_sales_private.sales_accessory_candidates(),
  pdc_sales_private.sales_accessory_plan(uuid), pdc_sales_private.sales_accessory_plan_summary(jsonb),
  pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text), pdc_sales_private.get_accessories(), public.get_broome_sales_accessories()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.get_accessories() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_broome_sales_accessories() TO authenticated;
