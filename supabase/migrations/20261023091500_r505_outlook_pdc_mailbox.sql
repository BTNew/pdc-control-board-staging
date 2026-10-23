-- r505 (F118): accept Revolution PMB reports delivered via Outlook to pdc@pmgwa.com.au.
-- Staging cdsmnqxtyyoeoznmbidd only. PREVIEW / NOT applied. Never touch production.
-- Craig moved monitoring off pmbcontroller@gmail.com at 08:03 AWST 23 Oct 2026.
-- Shared auth helper gains an Outlook / Microsoft path (mailbox pdc@, verified_by microsoft_receiving_provider,
--   mx.microsoft.com, internet_message_id|outlook_message_id|microsoft_message_id). Gmail path unchanged.
-- Callers that hard-code mailbox or gmail_message_id are widened: parts import, Karratha 135 contract,
--   service rows validator, sales accessories receipt id coalesce. Service manifest inherits via p_message_id.
-- PARTS ETA (set_parts_eta_from_email) has no mailbox gate; HANDOFF only.
-- Pins: UPDATE auth/rows/sales; INSERT parts import + k135 (+2, 210 -> 212). Check outlook_pdc_auth_505 sort 290.
-- Auth / rows / sales bodies LF. Parts import + k135 tip are CRLF; new bodies installed via chr(13) rebuild so CRLF survives apply_migration.
-- Undo: supabase/rollbacks/20261023091500_r505_outlook_pdc_mailbox.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r505: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r505: staging only'; END IF;
 PERFORM set_config('pdc.r505_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r505_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r505_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 PERFORM set_config('pdc.r505_manifest',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')),true);
 IF current_setting('pdc.r505_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r505: clock tick does not match its pin'; END IF;
 IF current_setting('pdc.r505_pins')::int IS DISTINCT FROM 210 THEN RAISE EXCEPTION 'r505: expected 210 pins at tip, got %', current_setting('pdc.r505_pins'); END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '6c1a612f6ed82dfcbf5788c17d2e5d87'
    OR (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM 'abbb00e85839a85c47df7de16c9895bd' THEN RAISE EXCEPTION 'r505: auth tip mismatch'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)')) IS DISTINCT FROM '986b89b3ca9180765fdc3f70bb7b49d5' THEN RAISE EXCEPTION 'r505: parts import tip mismatch'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_intake.revolution_csv_contract_20261007(text,jsonb)')) IS DISTINCT FROM '2f478c0f84a18f250805a3b9b1a40955' THEN RAISE EXCEPTION 'r505: k135 tip mismatch'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM 'b5e3ab4517bd59a1931509a2b9a1299f' THEN RAISE EXCEPTION 'r505: rows tip mismatch'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM 'ee577536b060c7447e1a4ff352250b79' THEN RAISE EXCEPTION 'r505: sales tip mismatch'; END IF;
 IF current_setting('pdc.r505_manifest') IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r505: service manifest tip mismatch (must stay unchanged)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r505')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_pdc_auth_505' OR added_in='r505') THEN RAISE EXCEPTION 'r505: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=290 OR fault_id='F118') THEN RAISE EXCEPTION 'r505: sort_order 290 / F118 taken'; END IF;
END $g$;

-- 1. Shared auth helper (LF)
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_auth jsonb, p_message_id text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT coalesce(jsonb_typeof(p_auth)='object'
  AND p_auth->>'from_address'='noreply@revolutionsoftware.com.au'
  AND p_auth->>'header_from'='revolutionsoftware.com.au'
  AND coalesce(nullif(p_auth->>'reply_to',''),'noreply@revolutionsoftware.com.au')='noreply@revolutionsoftware.com.au'
  AND (p_auth->>'to_address'='pmbcontroller@gmail.com' OR (p_auth->>'to_address'='craig.watson@broometoyota.com.au' AND p_auth->'cc_addresses' @> '["pmbcontroller@gmail.com"]'::jsonb)
   OR (p_auth->>'to_address'='pdc@pmgwa.com.au' AND p_auth->'cc_addresses' @> '["craig.watson@broometoyota.com.au"]'::jsonb))
  AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from=revolutionsoftware[.]com[.]au([;[:space:]]|$)'
  AND (
   -- Gmail path (unchanged from r484)
   (p_message_id ~ '^[a-f0-9]{10,40}$' AND p_auth->>'gmail_message_id'=p_message_id
    AND p_auth->>'mailbox'='pmbcontroller@gmail.com' AND p_auth->>'verified_by'='gmail_receiving_provider'
    AND p_auth->>'authentication_results' ~* '^mx[.]google[.]com;'
    AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*spf=pass[^;]*smtp[.]mailfrom=noreply@revolutionsoftware[.]com[.]au([;[:space:]]|$)')
   OR
   -- r505 (F118): Outlook / Microsoft path — mailbox pdc@pmgwa.com.au, Microsoft verifier, mx.microsoft.com; message id is internet_message_id or outlook_message_id or microsoft_message_id (not hex-only)
   (length(p_message_id) BETWEEN 8 AND 512 AND p_message_id !~ '[[:space:]]'
    AND (p_auth->>'internet_message_id'=p_message_id OR p_auth->>'outlook_message_id'=p_message_id OR p_auth->>'microsoft_message_id'=p_message_id)
    AND p_auth->>'mailbox'='pdc@pmgwa.com.au' AND p_auth->>'verified_by'='microsoft_receiving_provider'
    AND p_auth->>'authentication_results' ~* '^mx[.]microsoft[.]com([[:space:]]+[0-9]+)?[[:space:]]*;'
    AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*spf=pass[^;]*smtp[.]mailfrom=(noreply@)?revolutionsoftware[.]com[.]au([;[:space:]]|$)')
  ),false);
$function$;

-- 2. Service rows: mailbox pdc@ allowed (LF)
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_rows_20261006(p_rows jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT coalesce(jsonb_typeof(p_rows)='array' AND jsonb_array_length(p_rows)>0
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE
 coalesce(x->>'department','') NOT IN ('138','139')
 OR x->'raw_row'->>'Dept' IS DISTINCT FROM x->>'department'
 OR x->'raw_row'->>'Company' IS DISTINCT FROM '01'
 OR x->'raw_row'->>'Division' IS DISTINCT FROM '1'
 OR x->'raw_row'->>'from_address' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
 OR x->'raw_row'->>'mailbox' NOT IN ('pmbcontroller@gmail.com','pdc@pmgwa.com.au')
 OR NOT coalesce(
  x->'raw_row'->>'email_subject'='PMG PD Service Complete'
  OR (x->'raw_row'->>'email_subject'='CW PMB Service Complete'
   AND x->'raw_row'->>'source_kind'='revolution_automated_service_csv'
   AND x->'raw_row'->>'source_filename'='.csv'
   AND x->'raw_row'->>'scope_provenance'='craig_20261019_fixed_company01_division1')
  -- r442 (F54): a w/Sublet line: no Type key, every distinct PO in sublet_pos, the source rows it came from, hours not summed
  OR (x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet'
   AND x->'raw_row'->>'source_kind'='revolution_automated_service_workbook'
   AND NOT (x->'raw_row' ? 'Type')
   AND x->'raw_row'->>'line_collapse'='r442_one_row_per_dept_ro_line'
   AND jsonb_typeof(x->'raw_row'->'sublet_pos')='array'
   AND jsonb_typeof(x->'raw_row'->'source_row_numbers')='array'
   AND jsonb_array_length(x->'raw_row'->'source_row_numbers')>0
   AND jsonb_typeof(x->'raw_row'->'collapse')='object'
   AND x->'raw_row'->'collapse'->'hours_summed'='false'::jsonb
   AND x->'raw_row'->'collapse'->'source_rows'=to_jsonb(jsonb_array_length(x->'raw_row'->'source_row_numbers'))
   -- r444 (F57): optional sublet_po_descriptions: an object keyed by POs of this line (sublet_pos), string values up to 4000 characters
   AND (NOT (x->'raw_row' ? 'sublet_po_descriptions')
    OR (jsonb_typeof(x->'raw_row'->'sublet_po_descriptions')='object'
     AND NOT EXISTS(SELECT 1 FROM jsonb_each(x->'raw_row'->'sublet_po_descriptions') d
      WHERE jsonb_typeof(d.value)<>'string' OR length(d.value#>>'{}')>4000 OR NOT (x->'raw_row'->'sublet_pos') ? d.key))))
  -- r479 (F92): an 'as a Whole' line: every w/Sublet rule above, plus the full-snapshot marker and the board identity it was
  -- linked by (exact board stock, or a blank Stock # matched only by an exact board stock in Rego # or an exact job card)
  OR (x->'raw_row'->>'email_subject'='PMG PD Service as a Whole w/Sublet'
   AND x->'raw_row'->>'source_kind'='revolution_automated_service_workbook'
   AND NOT (x->'raw_row' ? 'Type')
   AND x->'raw_row'->>'line_collapse'='r442_one_row_per_dept_ro_line'
   AND x->'raw_row'->>'snapshot_scope'='full_open_ro_snapshot_r479'
   AND jsonb_typeof(x->'raw_row'->'identity_r479')='object'
   AND x->'raw_row'->'identity_r479'->>'rule'='r479_exact_board_stock_or_job_card'
   AND x->'raw_row'->'identity_r479'->>'basis' IN ('stock_column','rego_column_exact_board_stock','job_card_exact','job_card_service_job')
   AND btrim(coalesce(x->>'stock_number',''))<>''
   AND jsonb_typeof(x->'raw_row'->'sublet_pos')='array'
   AND jsonb_typeof(x->'raw_row'->'source_row_numbers')='array'
   AND jsonb_array_length(x->'raw_row'->'source_row_numbers')>0
   AND jsonb_typeof(x->'raw_row'->'collapse')='object'
   AND x->'raw_row'->'collapse'->'hours_summed'='false'::jsonb
   AND x->'raw_row'->'collapse'->'source_rows'=to_jsonb(jsonb_array_length(x->'raw_row'->'source_row_numbers'))
   AND (NOT (x->'raw_row' ? 'sublet_po_descriptions')
    OR (jsonb_typeof(x->'raw_row'->'sublet_po_descriptions')='object'
     AND NOT EXISTS(SELECT 1 FROM jsonb_each(x->'raw_row'->'sublet_po_descriptions') d
      WHERE jsonb_typeof(d.value)<>'string' OR length(d.value#>>'{}')>4000 OR NOT (x->'raw_row'->'sublet_pos') ? d.key)))),false)
 OR coalesce(x->>'repair_order_number','') !~ ('^J'||(x->>'department')||'[0-9]+$'))
 -- r442 (F54): a w/Sublet file is all w/Sublet rows, exactly one per Dept + R/O + Line # (never a repeated line, so never summed hours)
 AND (SELECT count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet') IN (0,count(*))
       AND count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet')
        =count(DISTINCT (x->>'department')||'|'||upper(x->>'repair_order_number')||'|'||coalesce(x->>'original_line_number',x->'raw_row'->>'Line #',''))
          FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet')
      FROM jsonb_array_elements(p_rows) x)
 -- r479 (F92): an 'as a Whole' file is all 'as a Whole' rows, exactly one per Dept + R/O + Line # (so never mixed with w/Sublet)
 AND (SELECT count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service as a Whole w/Sublet') IN (0,count(*))
       AND count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service as a Whole w/Sublet')
        =count(DISTINCT (x->>'department')||'|'||upper(x->>'repair_order_number')||'|'||coalesce(x->>'original_line_number',x->'raw_row'->>'Line #',''))
          FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service as a Whole w/Sublet')
      FROM jsonb_array_elements(p_rows) x),false);
$function$;

-- 3. Sales accessories: coalesce Outlook message ids into gmail_message_id column (LF)
CREATE OR REPLACE FUNCTION pdc_sales_private.import_sales_accessories_20261020(p_action text, p_envelope jsonb, p_rows jsonb DEFAULT NULL::jsonb, p_expected_preview_hash text DEFAULT NULL::text)
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
  snap timestamptz; m text[]; local_ts timestamp; tzs text[];
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
    -- r396: the row 2 stamp has no zone. Read it in envelope.extract_tz (default Australia/Perth); snapshot_at_utc, when sent, must be that
    -- stamp in UTC (in extract_tz, or in one of the four allowed zones when extract_tz is absent). Ordering then compares true instants.
    m := regexp_match(p_envelope->>'extract_text','^Extracted on [A-Za-z]+, ([A-Za-z]+ \d{1,2}, \d{4}) @ (\d{1,2}:\d{2} [AP]M)');
    local_ts := to_timestamp(m[1]||' '||m[2],'FMMonth FMDD, YYYY FMHH12:MI AM')::timestamp;
    tzs := CASE WHEN p_envelope ? 'extract_tz' THEN ARRAY[p_envelope->>'extract_tz']
                WHEN p_envelope ? 'snapshot_at_utc' THEN ARRAY['Australia/Perth','Australia/Brisbane','Australia/Sydney','Australia/Melbourne']
                ELSE ARRAY['Australia/Perth'] END;
    IF p_envelope ? 'snapshot_at_utc' THEN
      snap := (p_envelope->>'snapshot_at_utc')::timestamptz;
      IF NOT EXISTS (SELECT 1 FROM unnest(tzs) z WHERE (local_ts AT TIME ZONE z) = snap) THEN
        RAISE EXCEPTION 'sales_accessory_contract: snapshot_at_utc does not match the extract stamp in extract_tz' USING errcode='22023';
      END IF;
    ELSE
      snap := local_ts AT TIME ZONE tzs[1];
    END IF;
    IF FOUND THEN
      IF rec.payload_sha256<>payload THEN
        RETURN jsonb_build_object('ok',false,'code','file_sha_payload_conflict','receipt_id',rec.id,'status',rec.status);
      END IF;
      IF rec.snapshot_at IS DISTINCT FROM snap THEN
        RETURN jsonb_build_object('ok',false,'code','file_sha_snapshot_conflict','receipt_id',rec.id,'status',rec.status,'snapshot_at',rec.snapshot_at);
      END IF;
      RETURN jsonb_build_object('ok',true,'replay',true,'receipt_id',rec.id,'status',rec.status,'payload_sha256',rec.payload_sha256,
        'source_rows',rec.source_rows,'stock_count',rec.stock_count,'result',rec.result);
    END IF;
    IF snap > (p_envelope->>'received_at')::timestamptz + interval '10 minutes' THEN
      RAISE EXCEPTION 'sales_accessory_contract: extract stamp % is later than received_at; check extract_tz', snap USING errcode='22023';
    END IF;
    INSERT INTO pdc_sales_private.sales_accessory_receipts (file_sha256,payload_sha256,file_name,mailbox,sender,gmail_message_id,received_at,snapshot_at,
      extract_text,source_rows,stock_count,lines)
    VALUES (sha,payload,p_envelope->>'file_name',p_envelope->>'mailbox',p_envelope->>'sender',coalesce(nullif(p_envelope->>'gmail_message_id',''),nullif(p_envelope->>'internet_message_id',''),nullif(p_envelope->>'outlook_message_id',''),p_envelope->>'microsoft_message_id'),
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
END $function$;

-- 4. Parts import: mailbox pdc@ + Outlook message id coalesce (CRLF via chr(13))
DO $u$ DECLARE src text; BEGIN
 src := $p505$
DECLARE rec pdc_parts_private.receipts%rowtype; j pdc_parts_private.jobs%rowtype; x record; n integer;
 a integer;b integer;p integer; outcome text;reason text; target uuid; candidates uuid[];
 snap timestamptz; received timestamptz; reqhash text; resp jsonb; kind text; bhavesh boolean:=false; revolution boolean:=false;
BEGIN
 IF pdc_codex_intake_private.management_connection() IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
 kind:=coalesce(p_envelope->>'source_kind','gmail_csv');
 IF p_envelope->>'source_system' IS DISTINCT FROM 'tune_pmg' OR nullif(p_envelope->>'company','') IS NULL OR nullif(p_envelope->>'division','') IS NULL
 OR coalesce(p_envelope->>'attachment_sha256','') !~ '^[a-f0-9]{64}$'
 OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 10000
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_report_envelope'); END IF;
 IF kind IN ('gmail_csv','authorised_gmail_workbook') THEN
  IF (kind='gmail_csv' AND p_envelope->>'subject' IS DISTINCT FROM 'PMG PD Parts Status')
  OR (kind='authorised_gmail_workbook' AND (p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request' OR length(coalesce(p_envelope->>'user_instruction',''))<20 OR nullif(p_envelope->>'subject','') IS NULL OR coalesce(p_envelope->>'source_file','') !~* '[.]xlsx$')) OR p_envelope->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
  OR coalesce(p_envelope->>'sender','') NOT IN ('craig.watson@broometoyota.com.au','bhavesh.patel@pmgwa.com.au')
  OR p_envelope->>'sender_verified' IS DISTINCT FROM 'true' OR nullif(p_envelope->>'authentication_results','') IS NULL
  OR coalesce(p_envelope->>'gmail_message_id','') !~ '^[a-f0-9]{10,40}$'
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_or_unverified_envelope'); END IF;
  bhavesh:=p_envelope->>'sender'='bhavesh.patel@pmgwa.com.au';
  IF bhavesh AND (NOT pdc_codex_intake_private.bhavesh_email_authenticated_20260923(p_envelope->'authentication',p_envelope->>'gmail_message_id')
   OR p_envelope->>'authentication_results' IS DISTINCT FROM p_envelope->'authentication'->>'authentication_results')
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_or_unverified_envelope'); END IF;
  IF bhavesh AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) z WHERE z->>'Dept' IS DISTINCT FROM '138')
  THEN RETURN jsonb_build_object('ok',false,'code','department_138_scope_required'); END IF;
 ELSIF kind='revolution_automated_parts_workbook' THEN
  revolution:=true;
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
   OR p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request'
   OR length(coalesce(p_envelope->>'user_instruction',''))<20
   OR NOT coalesce((p_envelope->>'subject'='PMG PD Parts Status Complete - Pilbara'
      AND p_envelope->>'source_file' ~ '^PMG PD Parts Status Complete[.]xlsx?$')
    OR (p_envelope->>'subject'='PMG PD Parts Status'
      AND p_envelope->>'source_file' ~ '^PMG PD Parts Status V1 - Job 1[.]xlsx?$'),false)
   OR p_envelope->>'source_format' IS DISTINCT FROM 'ooxml_workbook'
   OR p_envelope->>'company' IS DISTINCT FROM '01' OR p_envelope->>'division' IS DISTINCT FROM '1'
   OR p_envelope->>'mailbox' NOT IN ('pmbcontroller@gmail.com','pdc@pmgwa.com.au')
   OR p_envelope->>'sender' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
   OR p_envelope->>'sender_verified' IS DISTINCT FROM 'true'
   OR NOT pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_envelope->'authentication',
     CASE WHEN p_envelope->>'mailbox'='pdc@pmgwa.com.au'
      THEN coalesce(nullif(p_envelope->>'internet_message_id',''),nullif(p_envelope->>'outlook_message_id',''),nullif(p_envelope->>'microsoft_message_id',''),p_envelope->>'gmail_message_id')
      ELSE p_envelope->>'gmail_message_id' END)
   OR p_envelope->>'authentication_results' IS DISTINCT FROM p_envelope->'authentication'->>'authentication_results'
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_or_unverified_envelope'); END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) z WHERE coalesce(z->>'Dept','') NOT IN ('138','139'))
  THEN RETURN jsonb_build_object('ok',false,'code','department_138_139_scope_required'); END IF;
 ELSIF kind='user_attached_workbook' THEN
  IF p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request'
  OR nullif(p_envelope->>'attachment_id','') IS NULL OR nullif(p_envelope->>'source_file','') IS NULL
  OR length(coalesce(p_envelope->>'user_instruction',''))<20
  OR p_envelope ? 'gmail_message_id' OR p_envelope ? 'sender_verified' OR p_envelope ? 'mailbox'
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_direct_attachment_evidence'); END IF;
 ELSE RETURN jsonb_build_object('ok',false,'code','unsupported_report_origin'); END IF;
 BEGIN snap:=(p_envelope->>'snapshot_at')::timestamptz;
  received:=CASE WHEN kind IN ('gmail_csv','authorised_gmail_workbook','revolution_automated_parts_workbook') THEN (p_envelope->>'received_at')::timestamptz ELSE NULL END;
 EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'code','invalid_snapshot_time'); END;
 IF snap IS NULL OR snap>clock_timestamp()+interval '5 minutes'
 OR (kind IN ('gmail_csv','authorised_gmail_workbook','revolution_automated_parts_workbook') AND (received IS NULL OR snap>received+interval '5 minutes' OR received>clock_timestamp()+interval '5 minutes'))
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_snapshot_time'); END IF;
 reqhash:=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'source',p_envelope->>'source_system','company',p_envelope->>'company','division',p_envelope->>'division','snapshot',snap)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO rec FROM pdc_parts_private.receipts WHERE source_system=p_envelope->>'source_system'
 AND company=p_envelope->>'company' AND division=p_envelope->>'division' AND attachment_sha256=p_envelope->>'attachment_sha256';
 IF FOUND THEN
 IF rec.request_hash<>reqhash THEN RETURN jsonb_build_object('ok',false,'code','attachment_replay_conflict');END IF;
 RETURN rec.response||jsonb_build_object('replay',true);END IF;
 INSERT INTO pdc_parts_private.receipts(source_kind,mailbox,message_id,attachment_sha256,source_system,company,division,snapshot_at,received_at,request_hash,evidence)
 VALUES(kind,p_envelope->>'mailbox',p_envelope->>'gmail_message_id',p_envelope->>'attachment_sha256',p_envelope->>'source_system',p_envelope->>'company',p_envelope->>'division',snap,received,reqhash,p_envelope) RETURNING * INTO rec;
 FOR x IN SELECT value raw,ordinality::integer rowno FROM jsonb_array_elements(p_rows) WITH ORDINALITY LOOP
 target:=NULL;outcome:='invalid';reason:='invalid_flags_or_identity';
 a:=public.pdc_numeric_parts_flag_20260911(x.raw->'Parts Attached');b:=public.pdc_numeric_parts_flag_20260911(x.raw->'Parts on Backorder');p:=public.pdc_numeric_parts_flag_20260911(x.raw->'Backorder with PO (1=Yes, 0=No)');
 IF jsonb_typeof(x.raw)='object' AND nullif(btrim(x.raw->>'R/O #'),'') IS NOT NULL AND x.raw->>'Dept' IN('138','139') AND a IS NOT NULL AND b IS NOT NULL AND p IS NOT NULL AND NOT(p=1 AND b=0) THEN
 IF (SELECT count(*) FROM jsonb_array_elements(p_rows) z WHERE upper(btrim(z->>'R/O #'))=upper(btrim(x.raw->>'R/O #')))>1 THEN
 outcome:='ambiguous';reason:='duplicate_ro_rows';
 ELSE
 SELECT array_agg(j0.id) INTO candidates FROM pdc_parts_private.jobs j0 JOIN public.vehicles v ON v.id=j0.vehicle_id
 WHERE j0.source_system=rec.source_system AND j0.company=rec.company AND j0.division=rec.division
 AND j0.ro_number=upper(btrim(x.raw->>'R/O #')) AND x.raw->>'Dept'=ANY(j0.departments)
 AND j0.closed_at IS NULL AND v.deleted_at IS NULL AND v.lifecycle_state='active' AND v.visible_on_board AND v.board_purged_at IS NULL
 AND nullif(btrim(v.stock_number),'') IS NOT NULL AND j0.stock_number=btrim(v.stock_number);
 n:=coalesce(cardinality(candidates),0);
 IF n=0 THEN outcome:='unmatched';reason:='no_exact_active_board_job';
 ELSIF n>1 THEN outcome:='ambiguous';reason:='multiple_board_jobs';
 ELSE
 target:=candidates[1]; SELECT * INTO j FROM pdc_parts_private.jobs WHERE id=target FOR UPDATE;
 IF bhavesh AND (coalesce(cardinality(j.departments),0)=0
  OR EXISTS(SELECT 1 FROM unnest(j.departments) d WHERE d IS DISTINCT FROM '138'))
 THEN outcome:='ambiguous';reason:='department_138_job_scope_required';
 ELSIF revolution AND (coalesce(cardinality(j.departments),0)<>1 OR j.departments[1] IS DISTINCT FROM x.raw->>'Dept')
 THEN outcome:='ambiguous';reason:='exact_department_job_scope_required';
 ELSIF nullif(btrim(x.raw->>'Stock #'),'') IS NOT NULL AND btrim(x.raw->>'Stock #')<>j.stock_number THEN outcome:='ambiguous';reason:='stock_ro_conflict';
 ELSIF j.parts_snapshot_at IS NOT NULL AND snap<j.parts_snapshot_at THEN outcome:='stale';reason:='older_snapshot';
 ELSIF snap=j.parts_snapshot_at AND (j.parts_attached IS DISTINCT FROM a OR j.backorder IS DISTINCT FROM b OR j.po_flag IS DISTINCT FROM p) THEN outcome:='ambiguous';reason:='equal_snapshot_conflict';
 ELSE
 outcome:=CASE WHEN j.parts_attached=a AND j.backorder=b AND j.po_flag=p THEN 'unchanged' ELSE 'updated' END;reason:='exact_ro_match';
 UPDATE pdc_parts_private.jobs SET parts_attached=a,backorder=b,po_flag=p,parts_snapshot_at=snap,parts_imported_at=rec.imported_at,
 parts_receipt_id=rec.id,parts_origin=kind,version=version+1 WHERE id=target;
 END IF;
 END IF;
 END IF;
 ELSIF p=1 AND b=0 THEN reason:='po_without_backorder'; END IF;
 INSERT INTO pdc_parts_private.row_results(receipt_id,row_number,raw_row,job_id,outcome,reason) VALUES(rec.id,x.rowno,x.raw,target,outcome,reason);
 END LOOP;
 SELECT jsonb_build_object('ok',true,'replay',false,'receipt_id',rec.id,'source_rows',count(*),
 'matched',count(*) FILTER(WHERE rr.job_id IS NOT NULL),'updated',count(*) FILTER(WHERE rr.outcome='updated'),
 'unchanged',count(*) FILTER(WHERE rr.outcome='unchanged'),'unmatched',count(*) FILTER(WHERE rr.outcome='unmatched'),
 'ambiguous',count(*) FILTER(WHERE rr.outcome='ambiguous'),'invalid',count(*) FILTER(WHERE rr.outcome='invalid'),
 'stale',count(*) FILTER(WHERE rr.outcome='stale'),'last_successful_import_at',rec.imported_at,'snapshot_at',snap,
 'vehicles_created',0,'jobs_created',0,'operations_changed',0,'bookings_created',0) INTO resp FROM pdc_parts_private.row_results rr WHERE rr.receipt_id=rec.id;
 UPDATE pdc_parts_private.receipts SET response=resp WHERE id=rec.id;
 UPDATE pdc_parts_private.settings SET last_successful_import_at=rec.imported_at WHERE singleton;
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 PERFORM public.workshop_bump_revision();
 RETURN resp;
END $p505$;
 src := replace(src, chr(10), chr(13)||chr(10));
 IF md5(src) IS DISTINCT FROM 'ccf492618ca11625470b691fbe029ac7' THEN RAISE EXCEPTION 'r505: parts new body md5 % not ccf492618ca11625470b691fbe029ac7', md5(src); END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.pdc_import_job_parts_csv_20260912(p_envelope jsonb, p_rows jsonb)'||chr(10)
  ||' RETURNS jsonb'||chr(10)
  ||' LANGUAGE plpgsql'||chr(10)
  ||' SET search_path TO ''pg_catalog'', ''public'', ''pdc_parts_private'''||chr(10)
  ||'AS '||quote_literal(src);
END $u$;

-- 5. Karratha 135 contract: mailbox pdc@ + Outlook message id coalesce (CRLF via chr(13))
DO $u$ DECLARE src text; BEGIN
 src := $k505$
DECLARE snap timestamptz;received timestamptz;
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN('service','parts')
 OR p_envelope->>'source_kind' IS DISTINCT FROM 'revolution_automated_'||p_kind||'_csv'
 OR p_envelope->>'authority' IS DISTINCT FROM 'explicit_user_request'
 OR length(coalesce(p_envelope->>'user_instruction',''))<20
 OR p_envelope->>'source_system' IS DISTINCT FROM 'tune_pmg'
 OR p_envelope->>'source_format' IS DISTINCT FROM 'csv'
 OR p_envelope->>'company' IS DISTINCT FROM '01' OR p_envelope->>'division' IS DISTINCT FROM '1'
 OR p_envelope->>'department' IS DISTINCT FROM '135'
 OR p_envelope->>'mailbox' NOT IN ('pmbcontroller@gmail.com','pdc@pmgwa.com.au')
 OR p_envelope->>'sender' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
 OR nullif(p_envelope->>'attachment_id','') IS NULL
 OR coalesce(p_envelope->>'attachment_sha256','') !~ '^[a-f0-9]{64}$'
 OR p_envelope->>'snapshot_basis' IS DISTINCT FROM 'authenticated_revolution_email_date'
 OR p_envelope->>'snapshot_at' IS DISTINCT FROM p_envelope->>'producer_email_date_utc'
 OR NOT pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_envelope->'authentication',
  CASE WHEN p_envelope->>'mailbox'='pdc@pmgwa.com.au'
   THEN coalesce(nullif(p_envelope->>'internet_message_id',''),nullif(p_envelope->>'outlook_message_id',''),nullif(p_envelope->>'microsoft_message_id',''),p_envelope->>'gmail_message_id')
   ELSE p_envelope->>'gmail_message_id' END)
 THEN RETURN false; END IF;
 IF p_kind='service' THEN
  IF p_envelope->>'subject' IS DISTINCT FROM 'PMG KTA Service Complete'
  OR p_envelope->>'source_file' IS DISTINCT FROM 'PMG KTA Service Complete - Job 1.csv'
  OR p_envelope->'source_headers' IS DISTINCT FROM '["Type","Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb
  THEN RETURN false; END IF;
 ELSE
  IF p_envelope->>'subject' IS DISTINCT FROM 'PMG KTA Parts Complete'
  OR p_envelope->>'source_file' IS DISTINCT FROM 'PMG KTA Parts Complete  - Job 1.csv'
  OR p_envelope->'source_headers' IS DISTINCT FROM '["Type","Dept","R/O #","Line #","Parts Attached","Parts on Backorder","Backorder with PO (1=Yes, 0=No)","Modified Date","Modified Date"]'::jsonb
  THEN RETURN false; END IF;
 END IF;
 BEGIN snap:=(p_envelope->>'snapshot_at')::timestamptz;received:=(p_envelope->>'received_at')::timestamptz;
 EXCEPTION WHEN OTHERS THEN RETURN false; END;
 RETURN coalesce(snap IS NOT NULL AND received IS NOT NULL
 AND snap<=received+interval '5 minutes' AND snap>=received-interval '5 minutes'
 AND received<=clock_timestamp()+interval '5 minutes',false);
END $k505$;
 src := replace(src, chr(10), chr(13)||chr(10));
 IF md5(src) IS DISTINCT FROM 'b8b37ceab1d1297a6e13709cd68bc243' THEN RAISE EXCEPTION 'r505: k135 new body md5 % not b8b37ceab1d1297a6e13709cd68bc243', md5(src); END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION karratha135_intake.revolution_csv_contract_20261007(p_kind text, p_envelope jsonb)'||chr(10)
  ||' RETURNS boolean'||chr(10)
  ||' LANGUAGE plpgsql'||chr(10)
  ||' SET search_path TO ''pg_catalog'''||chr(10)
  ||'AS '||quote_literal(src);
END $u$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='4df79e85792a93bbac4e484d7a2b82f3', release='r505',
 note='r505 (F118): Outlook/pdc@ path + Gmail path (was 6c1a612f6ed82dfcbf5788c17d2e5d87 r484)', updated_at=now()
 WHERE signature='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)';

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='5807a896cef15f81030f84a1b68a597b', release='r505',
 note='r505 (F118): mailbox pdc@pmgwa.com.au allowed (was b5e3ab4517bd59a1931509a2b9a1299f r479)', updated_at=now()
 WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)';

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='46d4b464c5c1800c8ada245fb2d33bd3', release='r505',
 note='r505 (F118): coalesce Outlook message ids into gmail_message_id (was ee577536b060c7447e1a4ff352250b79)', updated_at=now()
 WHERE signature='pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)';

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at) VALUES
 ('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)','ccf492618ca11625470b691fbe029ac7','r505','r505 (F118): mailbox pdc@ + Outlook message id coalesce (was 986b89b3ca9180765fdc3f70bb7b49d5, unpinned)',now()),
 ('karratha135_intake.revolution_csv_contract_20261007(text,jsonb)','b8b37ceab1d1297a6e13709cd68bc243','r505','r505 (F118): mailbox pdc@ + Outlook message id coalesce (was 2f478c0f84a18f250805a3b9b1a40955, unpinned)',now());

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('outlook_pdc_auth_505','F118','Revolution report sign-in (r505): auth pin LF; Gmail path still passes; Outlook/pdc@ with microsoft_receiving_provider + mx.microsoft.com + internet/outlook/microsoft message id passes; bad SPF/DMARC/To without Craig CC/wrong mailbox/verifier fail; parts/k135/rows/sales pins match; service manifest unchanged',
  $chk$WITH f AS (
  SELECT p.oid, md5(p.prosrc) m, p.prosecdef, p.provolatile, p.proconfig, p.proacl::text acl,
         pg_catalog.pg_get_userbyid(p.proowner) own, position(chr(13) in p.prosrc) AS cr
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')
), pin AS (
  SELECT count(*) n, count(*) FILTER (WHERE e.prosrc_md5=(SELECT m FROM f)) ok
  FROM pdc_ops.expected_function_md5 e
  WHERE e.signature='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'
), gmail AS (
  SELECT jsonb_build_object(
    'gmail_message_id','a505a505a505a505',
    'from_address','noreply@revolutionsoftware.com.au',
    'mailbox','pmbcontroller@gmail.com',
    'to_address','pmbcontroller@gmail.com',
    'cc_addresses','[]'::jsonb,
    'verified_by','gmail_receiving_provider',
    'header_from','revolutionsoftware.com.au',
    'reply_to','noreply@revolutionsoftware.com.au',
    'authentication_results','mx.google.com;       spf=pass (google.com: domain of noreply@revolutionsoftware.com.au designates 192.0.2.10 as permitted sender) smtp.mailfrom=noreply@revolutionsoftware.com.au;       dmarc=pass (p=QUARANTINE sp=QUARANTINE dis=NONE) header.from=revolutionsoftware.com.au'
  ) a
), outlook AS (
  SELECT jsonb_build_object(
    'internet_message_id','<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>',
    'outlook_message_id','AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE7dQAA',
    'from_address','noreply@revolutionsoftware.com.au',
    'mailbox','pdc@pmgwa.com.au',
    'to_address','pdc@pmgwa.com.au',
    'cc_addresses',jsonb_build_array('craig.watson@broometoyota.com.au'),
    'verified_by','microsoft_receiving_provider',
    'header_from','revolutionsoftware.com.au',
    'reply_to','noreply@revolutionsoftware.com.au',
    'authentication_results','mx.microsoft.com 1; spf=pass (sender IP is 13.238.252.82) smtp.mailfrom=revolutionsoftware.com.au; dkim=none (message not signed) header.d=none;dmarc=pass action=none header.from=revolutionsoftware.com.au;compauth=pass reason=100'
  ) a
), cases(name, want, a, mid) AS (
  SELECT 'gmail: To pmbcontroller', true, (SELECT a FROM gmail), 'a505a505a505a505' UNION ALL
  SELECT 'gmail: To Craig CC pmb', true, (SELECT a FROM gmail)||'{"to_address":"craig.watson@broometoyota.com.au","cc_addresses":["pmbcontroller@gmail.com"]}', 'a505a505a505a505' UNION ALL
  SELECT 'gmail: To pdc CC Craig (mailbox still pmb)', true, (SELECT a FROM gmail)||'{"to_address":"pdc@pmgwa.com.au","cc_addresses":["craig.watson@broometoyota.com.au"]}', 'a505a505a505a505' UNION ALL
  SELECT 'outlook: internet_message_id', true, (SELECT a FROM outlook), '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: outlook_message_id (Graph)', true, (SELECT a FROM outlook), 'AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE7dQAA' UNION ALL
  SELECT 'outlook: microsoft_message_id field', true,
    ((SELECT a FROM outlook)-'internet_message_id'-'outlook_message_id')||jsonb_build_object('microsoft_message_id','AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE7dQAA'),
    'AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE7dQAA' UNION ALL
  SELECT 'outlook: To pdc no Craig CC', false, (SELECT a FROM outlook)||'{"cc_addresses":[]}', '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: wrong mailbox (still gmail)', false, (SELECT a FROM outlook)||'{"mailbox":"pmbcontroller@gmail.com"}', '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: gmail verifier', false, (SELECT a FROM outlook)||'{"verified_by":"gmail_receiving_provider"}', '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: mx.google.com', false,
    (SELECT a FROM outlook)||jsonb_build_object('authentication_results', replace((SELECT a->>'authentication_results' FROM outlook),'mx.microsoft.com 1;','mx.google.com;')),
    '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: SPF fail', false,
    (SELECT a FROM outlook)||jsonb_build_object('authentication_results', replace((SELECT a->>'authentication_results' FROM outlook),'spf=pass','spf=fail')),
    '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: DMARC fail', false,
    (SELECT a FROM outlook)||jsonb_build_object('authentication_results', replace((SELECT a->>'authentication_results' FROM outlook),'dmarc=pass','dmarc=fail')),
    '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: id mismatch', false, (SELECT a FROM outlook), '<other$id@host>' UNION ALL
  SELECT 'outlook: spaces in id', false, (SELECT a FROM outlook)||jsonb_build_object('internet_message_id','<a b@c>'), '<a b@c>' UNION ALL
  SELECT 'gmail: wrong mailbox=pdc', false, (SELECT a FROM gmail)||'{"mailbox":"pdc@pmgwa.com.au"}', 'a505a505a505a505' UNION ALL
  SELECT 'gmail: microsoft verifier', false, (SELECT a FROM gmail)||'{"verified_by":"microsoft_receiving_provider"}', 'a505a505a505a505' UNION ALL
  SELECT 'not an object', false, '["x"]'::jsonb, 'a505a505a505a505'
), r AS (
  SELECT name, want, pdc_codex_intake_private.revolution_parts_authenticated_20261006(a, mid) got FROM cases
), callers AS (
  SELECT
    (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)')) = 'ccf492618ca11625470b691fbe029ac7' AS parts_ok,
    (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_intake.revolution_csv_contract_20261007(text,jsonb)')) = 'b8b37ceab1d1297a6e13709cd68bc243' AS k135_ok,
    (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) = '5807a896cef15f81030f84a1b68a597b' AS rows_ok,
    (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) = '46d4b464c5c1800c8ada245fb2d33bd3' AS sales_ok,
    (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) = '63ff5dabf94abcdf7c278fb3afa9bd96' AS manifest_ok
)
SELECT (SELECT count(*)=1 FROM f)
   AND (SELECT NOT prosecdef AND provolatile='i' AND proconfig='{search_path=pg_catalog}'
            AND acl='{postgres=X/postgres}' AND own='postgres' AND cr=0 FROM f)
   AND (SELECT n=1 AND ok=1 FROM pin)
   AND (SELECT count(*)=17 AND bool_and(got IS NOT DISTINCT FROM want) FROM r)
   AND (SELECT parts_ok AND k135_ok AND rows_ok AND sales_ok AND manifest_ok FROM callers) AS ok,
 'auth pin '||(SELECT ok FROM pin)||'/'||(SELECT n FROM pin)
 ||'; settings '||coalesce((SELECT (NOT prosecdef AND provolatile='i' AND proconfig='{search_path=pg_catalog}'
        AND acl='{postgres=X/postgres}' AND own='postgres' AND cr=0)::text FROM f),'missing')
 ||'; cases '||(SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) FROM r)||'/'||(SELECT count(*) FROM r)
 ||coalesce(' (WRONG: '||(SELECT string_agg(name||' -> '||coalesce(got::text,'null'),'; ')
              FROM r WHERE got IS DISTINCT FROM want)||')','')
 ||'; callers parts/k135/rows/sales/manifest '||(SELECT parts_ok||'/'||k135_ok||'/'||rows_ok||'/'||sales_ok||'/'||manifest_ok FROM callers)
 AS detail$chk$,true,290,'r505');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3'
    OR (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '726bf5dfc8dffaa4add2e087185e9ac1'
    OR (SELECT position(chr(13) IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'))<>0 THEN RAISE EXCEPTION 'r505: auth did not land as expected (LF)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)')) IS DISTINCT FROM 'ccf492618ca11625470b691fbe029ac7'
    OR (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)')) IS DISTINCT FROM '2868827fe333373debf7b40194f5d46c'
    OR (SELECT position(chr(13) IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)'))=0 THEN RAISE EXCEPTION 'r505: parts import did not land as CRLF expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_intake.revolution_csv_contract_20261007(text,jsonb)')) IS DISTINCT FROM 'b8b37ceab1d1297a6e13709cd68bc243'
    OR (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=to_regprocedure('karratha135_intake.revolution_csv_contract_20261007(text,jsonb)')) IS DISTINCT FROM '93281316c340c4183c6c1c9385581ea2'
    OR (SELECT position(chr(13) IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_intake.revolution_csv_contract_20261007(text,jsonb)'))=0 THEN RAISE EXCEPTION 'r505: k135 did not land as CRLF expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '5807a896cef15f81030f84a1b68a597b'
    OR (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9e3c016f33d61e5545839106f23b3bf8' THEN RAISE EXCEPTION 'r505: rows did not land'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM '46d4b464c5c1800c8ada245fb2d33bd3'
    OR (SELECT md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM '0225509ce53754461cce5115c351abe6' THEN RAISE EXCEPTION 'r505: sales did not land'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) IS DISTINCT FROM current_setting('pdc.r505_manifest') THEN RAISE EXCEPTION 'r505: service manifest changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r505_tick') THEN RAISE EXCEPTION 'r505: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r505_frc') THEN RAISE EXCEPTION 'r505: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r505')<>5 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r505_pins')::int+2 THEN RAISE EXCEPTION 'r505: pins not as expected (want tip+2 with 5 at r505)'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_pdc_auth_505' AND added_in='r505' AND sort_order=290 AND fault_id='F118') THEN RAISE EXCEPTION 'r505: check missing'; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_pdc_auth_505';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r505: outlook_pdc_auth_505 failed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='parts_auth_pdc_mailbox_484';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r505: r484 check regressed: %', y; END IF;
END $g$;
