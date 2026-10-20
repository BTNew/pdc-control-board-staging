-- r396 undo (staging cdsmnqxtyyoeoznmbidd only): restores the r392 import function, validator and .xlsx-only file_name check, then asserts the md5s.
DO $u$
BEGIN
  IF md5(pg_get_functiondef('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)'::regprocedure))<>'e95ac8fea1ef9f9dbdd25eabce6e7f12'
     OR md5(pg_get_functiondef('pdc_sales_private.sales_accessory_normalize(jsonb,jsonb)'::regprocedure))<>'17be4dad310b7d1ec65c0f76bb7a4180' THEN
    RAISE EXCEPTION 'r396 undo: live definitions are not the r396 ones';
  END IF;
  IF EXISTS (SELECT 1 FROM pdc_sales_private.sales_accessory_receipts WHERE file_name !~* '\.xlsx$') THEN
    RAISE EXCEPTION 'r396 undo: receipts named .xls exist; the .xlsx-only check cannot be restored without changing stored data (decide first)';
  END IF;
  ALTER TABLE pdc_sales_private.sales_accessory_receipts DROP CONSTRAINT sales_accessory_receipts_file_name_check,
    ADD CONSTRAINT sales_accessory_receipts_file_name_check CHECK (file_name ~* '\.xlsx$' AND length(file_name) <= 255);
  EXECUTE $def$CREATE OR REPLACE FUNCTION pdc_sales_private.sales_accessory_normalize(p_envelope jsonb, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
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
END $function$
$def$;
  EXECUTE $def$CREATE OR REPLACE FUNCTION pdc_sales_private.import_sales_accessories_20261020(p_action text, p_envelope jsonb, p_rows jsonb DEFAULT NULL::jsonb, p_expected_preview_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '120s'
AS $function$
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
END $function$
$def$;
  IF md5(pg_get_functiondef('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)'::regprocedure))<>'418b21e32ad877a6e18ec96b836b5e76'
     OR md5(pg_get_functiondef('pdc_sales_private.sales_accessory_normalize(jsonb,jsonb)'::regprocedure))<>'9801ff7658e60fee649387f0a45f69b2'
     OR (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='sales_accessory_receipts_file_name_check')
        IS DISTINCT FROM $c$CHECK (((file_name ~* '\.xlsx$'::text) AND (length(file_name) <= 255)))$c$ THEN
    RAISE EXCEPTION 'r396 undo: restored definitions do not match the originals';
  END IF;
END $u$;
