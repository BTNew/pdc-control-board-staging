-- r442 (F54, change request; Craig 21 Oct 15:08 AWST via PMB Email): the Revolution report 'PMG PD Service Complete w/Sublet'
-- replaces 'PMG PD Service Complete' going forward (parts, CW and sales feeds unchanged). Staging cdsmnqxtyyoeoznmbidd only.
-- (1) Service manifest: a third branch accepts the w/Sublet workbook (exact subject and report title, filename
--     'PMG PD Service Complete w/Sublet[ - Job 1].xls(x)' with '/', '_', '-', ' ' or nothing between w and Sublet), header list = the
--     13 usual columns (NO Type) + the optional sublet columns with PO # required, plus the preparer's collapse and no-Type markers.
--     Same authenticated noreply@revolutionsoftware.com.au / SPF / DMARC / pmbcontroller and Company 01 / Division 1 checks. The old
--     'PMG PD Service Complete' and CW CSV branches are byte-for-byte unchanged (transition).
-- (2) Row validator: w/Sublet rows must carry no Type key, every distinct PO in raw_row.sublet_pos, the collapsed source row numbers
--     and collapse.hours_summed=false; a w/Sublet file is all w/Sublet rows with exactly one row per Dept + R/O + Line #.
-- (3) pdc_pilbara_service_apply_v1: after the service writes and job sync, feeds the file's POs through import_sublet_pos_439
--     (unchanged) and returns them as sublet_pos in the apply result and its receipt (the receipt is written once, after the feed).
--     The preview function, import_sublet_pos_439, the QC lines, the clock tick and Karratha 135 are not touched.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r442: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r442: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r442: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r442: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)<>'88c75359be6f3e4802c3c1a8f8fd3e10'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'56d5702b8946007875a85041e8260020'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'84e1ed9f1a722719c8c4b5b113e1884f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)<>'375bffc2dced95a7a5c74c3273dbccb3'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)<>'6cc118c512e103e33bfe94118b91d8a1' THEN RAISE EXCEPTION 'r442: service import functions are not the expected versions'; END IF;
 IF NOT ((SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)='{postgres=X/postgres,authenticated=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)='{postgres=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)='{postgres=X/postgres}') THEN RAISE EXCEPTION 'r442: unexpected function grants'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature IN ('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)','public.pdc_pilbara_service_apply_v1(uuid,text,text)','pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)'))<>0
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)') IS DISTINCT FROM '88c75359be6f3e4802c3c1a8f8fd3e10r439'
    OR to_regprocedure('pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r442')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_wsublet_contract_and_po_feed' OR added_in='r442') THEN RAISE EXCEPTION 'r442: already applied or pins unexpected'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=242) THEN RAISE EXCEPTION 'r442: sort_order 242 taken'; END IF;
END $g$;
CREATE FUNCTION pdc_codex_intake_private.service_sublet_po_feed_442(p_preview_batch_id uuid, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO 'pg_catalog', 'public'
AS $f$
DECLARE
 v_sha text; v_rows jsonb; v_res jsonb; v_coll jsonb; v_state text; v_msg text; v_exc jsonb;
BEGIN
 -- r442 (F54, Craig 21 Oct 15:08 AWST): the sublet POs of a service file go into the r439 PO tables as part of the same
 -- service apply, so PMB Email makes one call. Reads the preview batch's stored source rows: a w/Sublet row carries every
 -- distinct PO of its collapsed line in raw_row.sublet_pos (array); an r439 CSV / workbook row carries one in
 -- raw_row.sublet_columns."PO #". Each (stock, R/O, line, PO) goes through public.import_sublet_pos_439 unchanged (GP POs
 -- only, never clears a tick, never removes a PO, never creates or recategorises a line, never touches a bay or booking;
 -- owner-held, RFT, completed, inactive vehicles, closed jobs, completed / inactive / notes lines skipped), keyed by the
 -- source workbook hash. A file without POs is a no-op. A PO failure is reported (ok false, with the error) and rolled back
 -- on its own; it never undoes the service apply. p_dry_run true writes nothing (PMB Email may call it after a preview).
 SELECT b.source_link->>'workbook_sha256' INTO v_sha FROM public.pdc_pilbara_service_import_batches b
  WHERE b.batch_id=p_preview_batch_id AND b.batch_kind='preview' AND b.importer_version='pilbara_service_open_jobcards_v1';
 IF NOT FOUND THEN
  RETURN jsonb_build_object('contract','pdc-service-sublet-po-feed-442','ok',false,'code','preview_batch_not_found','dry_run',coalesce(p_dry_run,true));
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('stock',coalesce(r.stock_number,''),'ro',coalesce(r.repair_order_number,''),
   'line',coalesce(r.original_line_number::text,''),'po',p.po) ORDER BY r.source_order,p.o),'[]'::jsonb)
  INTO v_rows
  FROM public.pdc_pilbara_service_import_rows r
  CROSS JOIN LATERAL (
   SELECT q.e#>>'{}' AS po, q.o FROM jsonb_array_elements(CASE
     WHEN jsonb_typeof(r.raw_row->'sublet_pos')='array' THEN r.raw_row->'sublet_pos'
     WHEN jsonb_typeof(r.raw_row->'sublet_columns')='object' AND btrim(coalesce(r.raw_row->'sublet_columns'->>'PO #',''))<>''
      THEN jsonb_build_array(r.raw_row->'sublet_columns'->>'PO #')
     ELSE '[]'::jsonb END) WITH ORDINALITY q(e,o)
   WHERE jsonb_typeof(q.e)='string' AND btrim(q.e#>>'{}')<>'') p
  WHERE r.batch_id=p_preview_batch_id;
 SELECT jsonb_build_object('rule','r442_one_row_per_dept_ro_line','hours_summed',false,
   'lines',count(*) FILTER (WHERE r.raw_row ? 'collapse'),
   'lines_with_repeats',count(*) FILTER (WHERE r.raw_row->'collapse'->'source_rows' > '1'::jsonb),
   'source_rows',coalesce(sum(jsonb_array_length(r.raw_row->'source_row_numbers')) FILTER (WHERE jsonb_typeof(r.raw_row->'source_row_numbers')='array'),0),
   'conflicts',coalesce(jsonb_agg(jsonb_build_object('stock',r.stock_number,'ro',r.repair_order_number,'line',r.original_line_number,
      'fields',(SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb) FROM jsonb_object_keys(CASE WHEN jsonb_typeof(r.raw_row->'collapse'->'differing_values')='object' THEN r.raw_row->'collapse'->'differing_values' ELSE '{}'::jsonb END) k),
      'kept','first_row_in_source_order') ORDER BY r.source_order) FILTER (WHERE r.raw_row->'collapse'->>'conflict'='true'),'[]'::jsonb))
  INTO v_coll FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=p_preview_batch_id;
 IF jsonb_array_length(v_rows)=0 THEN
  v_res:=jsonb_build_object('ok',true,'contract','pdc-sublet-po-import-439','dry_run',coalesce(p_dry_run,true),'replay',false,'rows',0,'note','no_po_in_file',
   'totals','{}'::jsonb,'lines_with_po',0,'vehicles_with_po',0,'distinct_pos',0,'by_category','{}'::jsonb,
   'created_vehicles',0,'created_jobs',0,'created_lines',0,'category_changes',0,'booking_changes',0,'row_statuses','[]'::jsonb);
 ELSE
  BEGIN
   v_res:=public.import_sublet_pos_439(v_rows,v_sha,coalesce(p_dry_run,true));
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE, v_msg=MESSAGE_TEXT;
   v_res:=jsonb_build_object('ok',false,'code','sublet_po_feed_failed','sqlstate',v_state,'message',left(v_msg,300),
    'retry','public.import_sublet_pos_439(rows, source workbook sha256, false) with the same file');
  END;
 END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY (x->>'row')::integer),'[]'::jsonb) INTO v_exc FROM jsonb_array_elements(coalesce(v_res->'row_statuses','[]'::jsonb)) x
  WHERE x->>'status' NOT IN ('attached','already_attached','duplicate_in_file','ignored_blank_po');
 RETURN jsonb_build_object('contract','pdc-service-sublet-po-feed-442','ok',coalesce((v_res->>'ok')::boolean,false),
  'dry_run',coalesce(p_dry_run,true),'source_file_sha256',v_sha,'po_rows',jsonb_array_length(v_rows),
  'replay',coalesce((v_res->>'replay')::boolean,false),
  'totals',coalesce(v_res->'totals','{}'::jsonb),'lines_with_po',coalesce(v_res->'lines_with_po','0'::jsonb),
  'vehicles_with_po',coalesce(v_res->'vehicles_with_po','0'::jsonb),'distinct_pos',coalesce(v_res->'distinct_pos','0'::jsonb),
  'by_category',coalesce(v_res->'by_category','{}'::jsonb),
  'created_vehicles',0,'created_jobs',0,'created_lines',0,'category_changes',0,'booking_changes',0,'ticks_cleared',0,'pos_removed',0,
  'import',v_res-'row_statuses','exceptions',v_exc,'collapse',v_coll);
END
$f$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_manifest_20261006(p_provenance jsonb, p_message_id text, p_filename text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $f$
 SELECT coalesce(p_provenance->>'authority'='explicit_user_request'
 AND length(p_provenance->>'user_instruction')>20
 AND p_provenance->>'company'='01' AND p_provenance->>'division'='1'
 AND pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_provenance->'authentication',p_message_id)
 AND (
  (p_provenance->>'source_kind'='revolution_automated_service_workbook'
   AND p_provenance->>'subject'='PMG PD Service Complete'
   AND p_filename ~ '^PMG PD Service Complete( - Job 1)?[.]xlsx?$'
   AND p_provenance->>'source_format'='ooxml_workbook')
  OR
  (p_provenance->>'source_kind'='revolution_automated_service_csv'
   AND p_provenance->>'subject'='CW PMB Service Complete'
   AND p_filename='.csv' AND p_provenance->>'source_format'='csv'
   -- r439 (F50): the exact fifteen headers, optionally followed by the seven sublet columns (PO # etc.); nothing else.
   AND pdc_codex_intake_private.revolution_service_headers_439(p_provenance->'source_headers','["Type","Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Status","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb)
   AND p_provenance->>'snapshot_basis'='authenticated_revolution_email_date'
   AND p_provenance->>'source_scope_basis'='craig_20261019_fixed_company01_division1'
   AND p_provenance->>'source_snapshot_at'=p_provenance->>'producer_email_date_utc'
   AND p_provenance->>'producer_email_date_utc' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
   AND p_provenance->>'received_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
   AND abs(extract(epoch from ((p_provenance->>'received_at')::timestamptz-(p_provenance->>'producer_email_date_utc')::timestamptz)))<=300)
  OR
  -- r442 (F54, Craig 21 Oct 15:08 AWST): 'PMG PD Service Complete w/Sublet' replaces 'PMG PD Service Complete' going forward
  -- (the old branch above stays for the transition). No Type column: the 13 usual columns, then the sublet columns with PO #
  -- required. One service line per Dept + R/O + Line # (repeated per-PO rows collapsed by the preparer, hours never summed).
  (p_provenance->>'source_kind'='revolution_automated_service_workbook'
   AND p_provenance->>'subject'='PMG PD Service Complete w/Sublet'
   AND p_provenance->>'report_title'='PMG PD Service Complete w/Sublet'
   AND p_filename ~ '^PMG PD Service Complete w[/_ -]?Sublet( - Job 1)?[.]xlsx?$'
   AND p_provenance->>'source_format'='ooxml_workbook'
   AND pdc_codex_intake_private.revolution_service_headers_439(p_provenance->'source_headers','["Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb)
   AND p_provenance->'source_headers' ? 'PO #'
   AND p_provenance->>'type_column'='absent_r442'
   AND p_provenance->>'line_collapse'='r442_one_row_per_dept_ro_line')
 ),false);
$f$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_rows_20261006(p_rows jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $f$
 SELECT coalesce(jsonb_typeof(p_rows)='array' AND jsonb_array_length(p_rows)>0
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE
 coalesce(x->>'department','') NOT IN ('138','139')
 OR x->'raw_row'->>'Dept' IS DISTINCT FROM x->>'department'
 OR x->'raw_row'->>'Company' IS DISTINCT FROM '01'
 OR x->'raw_row'->>'Division' IS DISTINCT FROM '1'
 OR x->'raw_row'->>'from_address' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
 OR x->'raw_row'->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
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
   AND x->'raw_row'->'collapse'->'source_rows'=to_jsonb(jsonb_array_length(x->'raw_row'->'source_row_numbers'))),false)
 OR coalesce(x->>'repair_order_number','') !~ ('^J'||(x->>'department')||'[0-9]+$'))
 -- r442 (F54): a w/Sublet file is all w/Sublet rows, exactly one per Dept + R/O + Line # (never a repeated line, so never summed hours)
 AND (SELECT count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet') IN (0,count(*))
       AND count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet')
        =count(DISTINCT (x->>'department')||'|'||upper(x->>'repair_order_number')||'|'||coalesce(x->>'original_line_number',x->'raw_row'->>'Line #',''))
          FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet')
      FROM jsonb_array_elements(p_rows) x),false);
$f$;

DO $crlf$ BEGIN EXECUTE replace($ddl$CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1(p_preview_batch_id uuid, p_source_hash text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $f$~~CR~~
DECLARE~~CR~~
  v_codex_scoped boolean := public.pdc_email_ai_runtime_authorized_v1() IS NOT TRUE;~~CR~~
  v_candidate jsonb; v_stock text; v_tune boolean; v_code text; v_backend uuid;~~CR~~
  v_actor uuid:=pdc_codex_intake_private.import_actor();v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_actor_label text:=v_actor_email||':viewer:'||coalesce(v_actor::text,'missing');~~CR~~
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;~~CR~~
  v_preview public.pdc_pilbara_service_import_batches%rowtype;v_prior public.pdc_pilbara_service_import_batches%rowtype;v_apply_batch uuid:=gen_random_uuid();~~CR~~
  v_row public.pdc_pilbara_service_import_rows%rowtype;v_op public.pdc_pilbara_service_operations%rowtype;v_vehicle_id uuid;v_first_ro text;v_operation_id uuid;v_identity_hash text;v_response jsonb;~~CR~~
BEGIN~~CR~~
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL~~CR~~
  THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;~~CR~~
  IF v_codex_scoped AND pdc_codex_intake_private.authorized('apply',NULL,p_source_hash,p_idempotency_key,p_preview_batch_id) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;~~CR~~
  IF v_codex_scoped THEN v_actor_label:=v_actor_email||':codex_workbook_importer:'||v_actor::text; END IF;~~CR~~
  IF pdc_codex_intake_private.management_connection() IS TRUE THEN v_actor_label:='codex_supabase_management:postgres:'||v_actor::text; END IF;~~CR~~
  IF p_preview_batch_id IS NULL OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_apply_request');END IF;~~CR~~
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_import_batches b WHERE b.batch_id=p_preview_batch_id AND b.importer_version='pilbara_service_open_jobcards_v1' AND b.batch_kind='preview' FOR SHARE;~~CR~~
  IF NOT FOUND OR v_preview.source_hash<>v_source_hash OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'code','apply_not_eligible');END IF;~~CR~~
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
   PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));~~CR~~
  v_tune:=v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4','pmg_stock_v5');~~CR~~
  v_request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc_pilbara_service_apply_v1_dynamic_20260910','preview_batch_id',p_preview_batch_id,'source_hash',v_source_hash)::text,'UTF8'),'sha256'),'hex');~~CR~~
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:apply:'||v_source_hash,0));~~CR~~
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='apply' AND b.contract_revision=v_preview.contract_revision;~~CR~~
  IF FOUND THEN~~CR~~
    -- Final outcomes are append-only receipts; the batch header remains immutable.~~CR~~
    SELECT coalesce((SELECT r.outcome FROM public.pdc_pilbara_service_import_receipts r WHERE r.batch_id=v_prior.batch_id AND r.receipt_kind='apply' ORDER BY r.created_at DESC LIMIT 1),v_prior.response) INTO v_prior.response;~~CR~~
    IF v_codex_scoped AND pdc_codex_intake_private.authorized('readback',NULL,NULL,NULL,v_prior.batch_id) IS NOT TRUE~~CR~~
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;~~CR~~
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_apply_conflict');END IF;~~CR~~
    INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)~~CR~~
    VALUES(v_prior.batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,'replay',v_prior.response||jsonb_build_object('code','apply_replay','replay',true),v_actor,v_actor_label);~~CR~~
    RETURN v_prior.response||jsonb_build_object('code','apply_replay','replay',true,'tune_checkout_transfers',(SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts WHERE batch_id=v_prior.batch_id));END IF;~~CR~~
  IF v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4') AND v_preview.accepted_line_count>0 THEN~~CR~~
    RETURN jsonb_build_object('ok',false,'code','preview_refresh_required','contract_revision','pmg_stock_v5');~~CR~~
  END IF;~~CR~~
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
   PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));~~CR~~
  IF NOT v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 LEFT JOIN public.navision_backend_records b ON b.id=r0.backend_record_id LEFT JOIN public.vehicles v ON v.id=r0.vehicle_id~~CR~~
    WHERE r0.batch_id=v_preview.batch_id AND r0.decision IN('insert','unchanged') AND (b.id IS NULL OR NOT b.is_current OR b.record_status<>'current' OR b.source_system<>'microsoft_navision'~~CR~~
      OR b.dealer_code<>'37047' OR b.canonical_vehicle_id IS DISTINCT FROM r0.vehicle_id~~CR~~
      OR btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) IS DISTINCT FROM btrim(r0.stock_number)~~CR~~
      OR v.id IS NULL OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.stock_number_normalized IS DISTINCT FROM btrim(r0.stock_number)~~CR~~
      OR (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision' AND x.dealer_code='37047' AND x.is_current AND x.record_status='current'~~CR~~
        AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=btrim(r0.stock_number))<>1))~~CR~~
  THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed');END IF;~~CR~~
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='insert'~~CR~~
      AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'~~CR~~
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'))~~CR~~
     OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='unchanged'~~CR~~
      AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'~~CR~~
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'~~CR~~
        AND o.semantic_hash=r0.semantic_hash))~~CR~~
  THEN RETURN jsonb_build_object('ok',false,'code','operation_state_changed_after_preview');END IF;~~CR~~
  IF v_tune THEN~~CR~~
    -- Serialize Stock creation with all canonical writers and validate every candidate before any write.~~CR~~
    LOCK TABLE public.vehicles, public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;~~CR~~
    FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP~~CR~~
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_row.stock_number);~~CR~~
      IF (v_candidate->>'ok')::boolean IS NOT TRUE~~CR~~
        OR (v_row.vehicle_id IS NOT NULL AND v_row.vehicle_id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid)~~CR~~
        OR v_row.backend_record_id IS DISTINCT FROM (v_candidate->>'backend_record_id')::uuid~~CR~~
      THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed','stock_number',v_row.stock_number); END IF;~~CR~~
    END LOOP;~~CR~~
  END IF;~~CR~~
  IF v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r JOIN public.pdc_unidentified_tune_review u ON u.workbook_sha256=r.normalized_payload->>'workbook_sha256' AND u.operation_identity_hash=r.normalized_payload->>'operation_identity_hash'~~CR~~
    WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review' AND (u.source_estimated_hours IS DISTINCT FROM (r.normalized_payload->>'source_estimated_hours')::numeric OR u.raw_row IS DISTINCT FROM r.raw_row))~~CR~~
  THEN RETURN jsonb_build_object('ok',false,'code','unidentified_source_changed'); END IF;~~CR~~
  v_response:=jsonb_build_object('ok',true,'code','applied','replay',false,'apply_batch_id',v_apply_batch,'source_hash',v_source_hash,'source_link',v_preview.source_link,'unidentified_rows',(SELECT count(*) FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND reason='unidentified_tune_review'),'operation_updates_for_review',coalesce((v_preview.response->>'operation_updates_for_review')::integer,0),'approvals_created',0,'insert',v_preview.insert_count,'update',0,~~CR~~
    'unchanged',v_preview.unchanged_count,'duplicate_ignored',coalesce((v_preview.response->'operations'->>'duplicate_ignored')::integer,0),'bookings_created',0,'completions_created',0,'atomic',true);~~CR~~
  INSERT INTO public.pdc_pilbara_service_import_batches(contract_revision,source_link,batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,quarantined_line_count,~~CR~~
    matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)~~CR~~
  VALUES(v_preview.contract_revision,v_preview.source_link,v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'apply',v_preview.source_row_count,v_preview.accepted_line_count,v_preview.quarantined_line_count,~~CR~~
    v_preview.matched_stock_count,v_preview.unmatched_stock_count,v_preview.ambiguous_stock_count,v_preview.insert_count,0,v_preview.unchanged_count,v_preview.conflict_count,v_response,v_actor,v_actor_label);~~CR~~
  IF v_tune THEN~~CR~~
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP~~CR~~
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);~~CR~~
      IF (v_candidate->>'create_vehicle')::boolean THEN~~CR~~
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)~~CR~~
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));~~CR~~
      END IF;~~CR~~
      v_backend:=(v_candidate->>'backend_record_id')::uuid;~~CR~~
      IF v_backend IS NOT NULL THEN~~CR~~
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles~~CR~~
        WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_stock) AND deleted_at IS NULL;~~CR~~
        -- Link only the unique current exact-Stock record accepted by this revision.~~CR~~
        -- Keep the pending vehicle's lifecycle and location; do not activate the board.~~CR~~
        UPDATE public.navision_backend_records SET canonical_vehicle_id=v_vehicle_id~~CR~~
        WHERE id=v_backend AND canonical_vehicle_id IS NULL;~~CR~~
        UPDATE public.vehicles SET source_system='microsoft_navision',source_record_id=v_backend::text,~~CR~~
          source_payload=coalesce(source_payload,'{}')||v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg')~~CR~~
        WHERE id=v_vehicle_id;~~CR~~
        PERFORM public.navision_refresh_linked_vehicle_projection_770(v_backend);~~CR~~
      END IF;~~CR~~
    END LOOP;~~CR~~
    IF v_preview.contract_revision='pmg_stock_v5' THEN~~CR~~
      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP~~CR~~
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;~~CR~~
        PERFORM public.pdc_apply_tune_vehicle_fields_v5(v_vehicle_id,v_apply_batch,v_preview.batch_id);~~CR~~
      END LOOP;~~CR~~
    END IF;~~CR~~
    -- Key tags are vehicle metadata, including when operation edits await review.
    IF v_preview.contract_revision='pmg_stock_v5' THEN
      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;
        PERFORM public.pdc_apply_tune_key_number_v1(v_vehicle_id,v_apply_batch,v_preview.batch_id);
      END LOOP;
    END IF;
    INSERT INTO public.pdc_unidentified_tune_review(workbook_sha256,repair_order_number,department,original_line_number,operation_description,operation_identity_hash,source_estimated_hours,operation_code,proposed_station,raw_row,source_hash,source_batch_id)~~CR~~
    SELECT r.normalized_payload->>'workbook_sha256',r.repair_order_number,r.normalized_payload->>'department',r.original_line_number,r.normalized_payload->>'operation_description',r.normalized_payload->>'operation_identity_hash',~~CR~~
      (r.normalized_payload->>'source_estimated_hours')::numeric,r.normalized_payload->>'operation_code',r.normalized_payload->>'proposed_station',r.raw_row,v_source_hash,v_apply_batch~~CR~~
    FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review'~~CR~~
    ON CONFLICT(workbook_sha256,operation_identity_hash) DO NOTHING;~~CR~~
  END IF;~~CR~~
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged') ORDER BY r.source_order LOOP~~CR~~
    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;~~CR~~
    v_identity_hash:=v_row.normalized_payload->>'operation_identity_hash';~~CR~~
    SELECT * INTO v_op FROM public.pdc_pilbara_service_operations x WHERE x.importer_version='pilbara_service_open_jobcards_v1'~~CR~~
      AND public.pdc_pilbara_service_operation_identity_hash_v3(x.department,x.stock_number,x.repair_order_number,x.original_line_number,x.operation_description)=v_identity_hash FOR SHARE;~~CR~~
    IF v_row.decision='insert' THEN~~CR~~
      IF FOUND THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;~~CR~~
      INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,~~CR~~
        source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)~~CR~~
      VALUES(v_row.normalized_payload->>'department',v_row.normalized_payload->>'operation_code',v_row.normalized_payload->>'proposed_station','pilbara_service_open_jobcards_v1',v_row.stock_number,v_row.repair_order_number,v_row.original_line_number,v_row.source_order,v_row.vehicle_id,v_row.normalized_payload->>'operation_description',~~CR~~
        CASE WHEN v_row.normalized_payload->>'source_estimated_hours' IS NULL THEN NULL ELSE (v_row.normalized_payload->>'source_estimated_hours')::numeric END,~~CR~~
        (v_row.normalized_payload->>'effective_estimated_hours')::numeric,v_row.normalized_payload->>'hours_provenance',coalesce(v_row.normalized_payload->>'parts_on_backorder_raw',''),~~CR~~
        v_row.normalized_payload->>'parts_semantics','Review',v_row.semantic_hash,v_row.evidence_id) RETURNING operation_id INTO v_operation_id;~~CR~~
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)~~CR~~
      VALUES(v_operation_id,v_apply_batch,'insert',NULL,v_row.semantic_hash,v_row.normalized_payload);~~CR~~
    ELSE~~CR~~
      IF NOT FOUND OR v_op.semantic_hash<>v_row.semantic_hash THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;~~CR~~
      v_operation_id:=v_op.operation_id;~~CR~~
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)~~CR~~
      VALUES(v_operation_id,v_apply_batch,'unchanged',v_op.semantic_hash,v_op.semantic_hash,v_row.normalized_payload);~~CR~~
    END IF;~~CR~~
  END LOOP;~~CR~~
  FOR v_vehicle_id IN SELECT DISTINCT o.vehicle_id FROM public.pdc_pilbara_service_operation_history h JOIN public.pdc_pilbara_service_operations o USING(operation_id) WHERE h.batch_id=v_apply_batch LOOP~~CR~~
    -- Rolling imports retain operations absent from this file.~~CR~~
    SELECT CASE WHEN count(DISTINCT r0.repair_order_number)=1 THEN min(r0.repair_order_number) ELSE NULL END INTO v_first_ro FROM public.pdc_pilbara_service_import_rows r0~~CR~~
    WHERE r0.batch_id=v_preview.batch_id AND (r0.vehicle_id=v_vehicle_id OR (v_tune AND r0.stock_number=(SELECT stock_number FROM public.vehicles WHERE id=v_vehicle_id))) AND r0.decision IN('insert','unchanged');~~CR~~
    IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=v_vehicle_id AND NOT v.visible_on_board)~~CR~~
      AND NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v_vehicle_id AND r.status IN('closed','approved')) THEN~~CR~~
      INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,first_job_card,received_at,approved_at,approved_by,approval_key,approval_hash,approval_receipt)~~CR~~
      VALUES(v_vehicle_id,'pending',CASE WHEN v_tune THEN 'tune_pmg' ELSE 'revolution_report' END,v_first_ro,clock_timestamp(),NULL,NULL,NULL,NULL,NULL)~~CR~~
      ON CONFLICT(vehicle_id) DO UPDATE SET status='pending',source_kind=excluded.source_kind,first_job_card=excluded.first_job_card,received_at=clock_timestamp(),~~CR~~
        approved_at=NULL,approved_by=NULL,approval_key=NULL,approval_hash=NULL,approval_receipt=NULL WHERE true;~~CR~~
      UPDATE public.vehicles SET job_card_number=v_first_ro,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=v_vehicle_id AND visible_on_board=false;~~CR~~
    END IF;~~CR~~
  END LOOP;~~CR~~
  PERFORM public.pdc_capture_tune_operation_changes_20260912(v_preview.batch_id,v_apply_batch);
   v_response:=v_response||jsonb_build_object(
    'operation_updates_auto_approved',(SELECT count(*) FROM public.pdc_tune_operation_change_reviews q WHERE q.batch_id=v_apply_batch AND q.automation_result->>'ok'='true'),
    'operation_updates_for_review',(SELECT count(*) FROM public.pdc_tune_operation_change_reviews q WHERE q.status='pending' AND q.vehicle_id IN(SELECT vehicle_id FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id)));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;~~CR~~
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;~~CR~~
  PERFORM public.workshop_bump_revision();~~CR~~
  PERFORM pdc_parts_private.sync_service_jobs();~~CR~~
  PERFORM pdc_codex_intake_private.capture_service_locations(v_preview.batch_id,v_apply_batch);~~CR~~
  IF v_preview.contract_revision='pmg_stock_v5' THEN PERFORM pdc_codex_intake_private.capture_service_status(v_preview.batch_id,v_apply_batch); END IF;~~CR~~
  PERFORM pdc_codex_intake_private.apply_service_arrival(v_apply_batch);~~CR~~
  -- r442 (F54): the file's sublet POs go into the r439 PO tables in this same apply (GP only; never clears a tick, removes a PO,~~CR~~
  -- creates a line or changes a category, bay or booking). Runs after the job sync so new lines are matched; a PO failure is~~CR~~
  -- reported in sublet_pos and never undoes the service apply.~~CR~~
  v_response:=v_response||jsonb_build_object('sublet_pos',pdc_codex_intake_private.service_sublet_po_feed_442(v_preview.batch_id,false));~~CR~~
   -- Persist the final response in the append-only apply receipt below; do not mutate the batch header.~~CR~~
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)~~CR~~
  VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,'apply',v_response,v_actor,v_actor_label);~~CR~~
  RETURN v_response||jsonb_build_object('tune_checkout_transfers',(SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts WHERE batch_id=v_apply_batch));~~CR~~
END~~CR~~
$f$;
$ddl$,'~~CR~~',chr(13)); END $crlf$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='e4ba03437490bd155d4d8553285107f8',release='r442',note='r442 (F54): w/Sublet workbook branch added (was 88c75359be6f3e4802c3c1a8f8fd3e10 r439)',updated_at=now() WHERE signature='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)','fd1d9272719cba74fdca23f9015d6d08','r442','r442 (F54): w/Sublet rows: no Type, one row per Dept/R/O/Line, hours never summed (was 56d5702b8946007875a85041e8260020, unpinned)'),
 ('public.pdc_pilbara_service_apply_v1(uuid,text,text)','fc3717a5215de94c93ebb2c7facfe744','r442','r442 (F54): service apply feeds sublet POs (sublet_pos) before its receipt (was 84e1ed9f1a722719c8c4b5b113e1884f, unpinned)'),
 ('pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)','6119632a2c961505b8875d1f0dcbdbaa','r442','r442 (F54): service apply PO feed through import_sublet_pos_439');
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('service_wsublet_contract_and_po_feed','F54','Service w/Sublet (r442): the manifest accepts the authenticated PMG PD Service Complete w/Sublet workbook (no Type, PO # column, collapse marker) and still the old title; the row validator refuses a Type key, repeated Dept/R/O/Line rows and summed hours; the PO feed is private, wired into the service apply before its single receipt, and every apply receipt since r442 carries sublet_pos',
  $chk$WITH src AS (
 SELECT (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) app,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)')) feed
), e AS (
 SELECT jsonb_build_object('source_kind','revolution_automated_service_workbook','authority','explicit_user_request',
  'user_instruction','Owner standing authority for genuine Revolution 138/139 service import contracts (r442 check)','company','01','division','1',
  'subject','PMG PD Service Complete w/Sublet','report_title','PMG PD Service Complete w/Sublet','source_format','ooxml_workbook',
  'source_headers','["Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #","Description of sublet","PO #"]'::jsonb,
  'type_column','absent_r442','line_collapse','r442_one_row_per_dept_ro_line',
  'authentication',jsonb_build_object('gmail_message_id','abcdef1234567890','from_address','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com',
   'to_address','pmbcontroller@gmail.com','verified_by','gmail_receiving_provider','header_from','revolutionsoftware.com.au',
   'authentication_results','mx.google.com; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au; dmarc=pass header.from=revolutionsoftware.com.au')) p
), rw AS (
 SELECT jsonb_build_object('department','139','repair_order_number','J139000442','original_line_number',4,'raw_row',jsonb_build_object('Dept','139','Company','01','Division','1',
  'from_address','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com','email_subject','PMG PD Service Complete w/Sublet',
  'source_kind','revolution_automated_service_workbook','line_collapse','r442_one_row_per_dept_ro_line','sublet_pos','["GP13900442","GP13900443"]'::jsonb,
  'source_row_numbers','[5,6]'::jsonb,'collapse',jsonb_build_object('rule','r442_one_row_per_dept_ro_line','source_rows',2,'hours_summed',false,'conflict',false))) r
), w AS (
 SELECT
  pdc_codex_intake_private.revolution_service_manifest_20261006(e.p,'abcdef1234567890','PMG PD Service Complete w/Sublet.xlsx')
   AND pdc_codex_intake_private.revolution_service_manifest_20261006(e.p,'abcdef1234567890','PMG PD Service Complete w_Sublet - Job 1.xls')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e.p,'abcdef1234567890','PMG PD Service Complete w/Sublet - Job 2.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e.p,'abcdef1234567890','PMG PD Service Complete.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e.p,'{source_headers}',jsonb_build_array('Type')||(e.p->'source_headers')),'abcdef1234567890','PMG PD Service Complete w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e.p,'{source_headers}',(e.p->'source_headers')-14),'abcdef1234567890','PMG PD Service Complete w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e.p-'source_headers','abcdef1234567890','PMG PD Service Complete w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e.p-'line_collapse','abcdef1234567890','PMG PD Service Complete w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e.p-'type_column','abcdef1234567890','PMG PD Service Complete w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e.p,'{report_title}','"PMG PD Service Complete"'),'abcdef1234567890','PMG PD Service Complete w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e.p,'{company}','"02"'),'abcdef1234567890','PMG PD Service Complete w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e.p,'{authentication,from_address}','"fake@example.com"'),'abcdef1234567890','PMG PD Service Complete w/Sublet.xlsx')
   AND pdc_codex_intake_private.revolution_service_manifest_20261006(e.p||'{"subject":"PMG PD Service Complete"}'::jsonb-'source_headers','abcdef1234567890','PMG PD Service Complete - Job 1.xls')
   AS manifest,
  pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r))
   AND pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r,jsonb_set(rw.r,'{original_line_number}','5')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r,rw.r))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,Type}','"D"')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,collapse,hours_summed}','true')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,collapse,source_rows}','3')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r,jsonb_set(jsonb_set(rw.r,'{raw_row,email_subject}','"PMG PD Service Complete"'),'{original_line_number}','5')))
   AND pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,email_subject}','"PMG PD Service Complete"')))
   AS rows_contract,
  NOT has_function_privilege('anon','pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)','EXECUTE')
   AND NOT has_function_privilege('authenticated','pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)','EXECUTE')
   AND NOT has_function_privilege('service_role','pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)','EXECUTE')
   AND NOT has_function_privilege('anon','public.pdc_pilbara_service_apply_v1(uuid,text,text)','EXECUTE') AS grants,
  position('service_sublet_po_feed_442(v_preview.batch_id,false)' in src.app)>0
   AND position('service_sublet_po_feed_442(v_preview.batch_id,false)' in src.app)<position($q$VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,'apply',v_response$q$ in src.app)
   AND (length(src.app)-length(replace(src.app,$q$'apply',v_response$q$,'')))/length($q$'apply',v_response$q$)=1
   AND position('import_sublet_pos_439' in src.feed)>0
   AND src.feed !~* '(INSERT INTO|UPDATE|DELETE FROM)\s+public\.' AS feed_wired,
  pdc_codex_intake_private.service_sublet_po_feed_442('00000000-0000-4000-8000-000000000442'::uuid,true)->>'code'='preview_batch_not_found' AS feed_safe,
  NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_receipts rc
   WHERE rc.receipt_kind='apply' AND rc.created_at>=(SELECT min(updated_at) FROM pdc_ops.expected_function_md5 WHERE release='r442')
    AND NOT (rc.outcome ? 'sublet_pos')) AS receipts_carry_pos
 FROM src, e, rw
)
SELECT w.manifest AND w.rows_contract AND w.grants AND w.feed_wired AND w.feed_safe AND w.receipts_carry_pos AS ok,
 format('w/Sublet manifest %s, row contract (one row per line, no Type, hours never summed) %s, feed private %s, feed wired into apply before its receipt %s, feed safe %s, every apply receipt since r442 carries sublet_pos %s; %s w/Sublet service rows stored, %s apply receipts since r442',
  w.manifest,w.rows_contract,w.grants,w.feed_wired,w.feed_safe,w.receipts_carry_pos,
  (SELECT count(*) FROM public.pdc_pilbara_service_import_rows WHERE raw_row->>'email_subject'='PMG PD Service Complete w/Sublet'),
  (SELECT count(*) FROM public.pdc_pilbara_service_import_receipts rc WHERE rc.receipt_kind='apply' AND rc.created_at>=(SELECT min(updated_at) FROM pdc_ops.expected_function_md5 WHERE release='r442'))) AS detail
FROM w
$chk$,true,242,'r442');
DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)<>'e4ba03437490bd155d4d8553285107f8' OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'fd1d9272719cba74fdca23f9015d6d08'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'fc3717a5215de94c93ebb2c7facfe744' OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)'::regprocedure)<>'6119632a2c961505b8875d1f0dcbdbaa'
    OR (SELECT count(*) FROM pg_proc WHERE oid IN ('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure,'pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure,'public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure,'pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)'::regprocedure) AND proowner::regrole::text='postgres')<>4
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure) OR (SELECT prosecdef FROM pg_proc WHERE oid='pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)'::regprocedure)
 THEN RAISE EXCEPTION 'r442: functions did not land as expected'; END IF;
 IF NOT ((SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)='{postgres=X/postgres,authenticated=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)='{postgres=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)='{postgres=X/postgres}') OR has_function_privilege('authenticated','pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)','EXECUTE') OR has_function_privilege('service_role','pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)','EXECUTE') OR has_function_privilege('anon','pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)','EXECUTE') THEN RAISE EXCEPTION 'r442: grants changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r442')<>4 THEN RAISE EXCEPTION 'r442: pins not written'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='service_wsublet_contract_and_po_feed' AND added_in='r442')<>'ee2f688233572d57cda7fb5dd38f335f' THEN RAISE EXCEPTION 'r442: check did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)<>'375bffc2dced95a7a5c74c3273dbccb3' OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)<>'6cc118c512e103e33bfe94118b91d8a1' THEN RAISE EXCEPTION 'r442: preview or PO import changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r442: clock tick changed'; END IF;
END $g$;
