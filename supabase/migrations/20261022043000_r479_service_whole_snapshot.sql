-- r479 (F92, change request; Craig approved the build in chat 22 Oct 2026, "build the as a Whole import, preview first"):
-- the Revolution report 'PMG PD Service as a Whole w/Sublet' (the full snapshot of every open R/O for Depts 138 and 139,
-- status 20 to <90, same 15 columns as w/Sublet) as a service import, previewed before any apply.
-- Staging cdsmnqxtyyoeoznmbidd only. Apply as ONE transaction (apply_migration / psql -1), between :02 and :45.
-- (1) Service manifest: a fourth branch accepts the authenticated 'as a Whole' workbook (exact subject and report title,
--     filename 'PMG PD Service as a Whole w/Sublet[ - Job 1].xls(x)' with '/', '_', '-', ' ' or nothing between w and Sublet,
--     the w/Sublet headers and collapse markers, plus snapshot_scope and identity_rule). Other branches byte for byte unchanged.
-- (2) Row validator: an 'as a Whole' line follows every w/Sublet rule, carries the snapshot marker and the board identity it
--     was linked by (raw_row.identity_r479) and a non-blank stock; an 'as a Whole' file is all such rows, one per line.
-- (3) pdc_apply_tune_key_number_v1: from an 'as a Whole' preview a Key Tag only fills a BLANK board key (an existing key,
--     e.g. a controller's r460 edit, is kept, reported as kept). w/Sublet and older reports unchanged.
-- (4) pdc_service_snapshot_private (no app-role access): snapshots_479 + snapshot_lines_479 (sha, R/O, line, seen_at),
--     record_snapshot_479(header, lines) (idempotent, parts allowed, keeps the newest 48), reconcile_479(sha) and
--     review_list_479() (READ-ONLY review list: open R/O with no board vehicle, R/O with every line at Sub Status 80/99 but
--     still open, board vehicle / R/O missing from the last TWO consecutive snapshots; never closes, hides or deletes).
-- (5) capture_service_status (called by the pinned apply): a Sub Status 99 checks a vehicle out ONCE. The existing rules stay
--     (any prior checkout receipt, QC / RFT, inspected or transferred: skipped); in addition a 99 R/O already on a checkout
--     receipt, or already at 99 in an import before an owner reopen (audit action owner_reopen_workshop_status), never
--     completes the vehicle again (service_99_used_479, read-only). The as a Whole report re-sends every 99 every hour.
--     The reconcile's 80/99 items say which 99s are already used (checkout_99_used).
-- Rebased onto main 2b1c3202: the one ON CONFLICT ... DO UPDATE in capture_service_status now ends 'WHERE true' (the r424b /
--   r429b safeupdate convention for migrations newer than 20261020082000); same behaviour, new prosrc md5.
-- v2 (22 Oct 13:35 AWST): this file is LF only. apply_migration (MCP / HTTP) turns CRLF into LF, so v1's CRLF capture body
--   landed as 7870d544 instead of c306c07f and the final check refused. The capture body is now LF, md5 7870d544 on any transport.
-- Not touched: the service preview / apply (pinned), import_sublet_pos_439, capture_service_locations, the clock tick,
-- any vehicle, job, line, booking or hold, Karratha 135. New vehicles and jobs are never created by this path: the preparer
-- sends only R/Os linked to a live board vehicle.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r479: run between :02 and :45 (the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r479: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'0aaaa15690ca286ed0db87fc72271d5a' THEN RAISE EXCEPTION 'r479: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r479: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)<>'375bffc2dced95a7a5c74c3273dbccb3'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'fc3717a5215de94c93ebb2c7facfe744'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_headers_439(jsonb,jsonb)'::regprocedure)<>'bfda8a3acd8a08bb36f5851ead2cd5e4' THEN RAISE EXCEPTION 'r479: service preview / apply / header check are not the expected versions'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)<>'e4ba03437490bd155d4d8553285107f8'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'0534336e01558066cf7ec3dcb3995cd4'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)<>'4b25c88071288d598d4ae29c50320d3b'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure)<>'3cc871d85d84195d9f8f65113a03e1ef'
    OR to_regprocedure('pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'r479: manifest / row validator / key import / status capture are not the expected versions'; END IF;
 IF (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)') IS DISTINCT FROM 'e4ba03437490bd155d4d8553285107f8r442'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)') IS DISTINCT FROM '0534336e01558066cf7ec3dcb3995cd4r444'
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature IN ('public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)','pdc_service_snapshot_private.append_only_479()','pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)','pdc_service_snapshot_private.reconcile_479(text)','pdc_service_snapshot_private.review_list_479()','pdc_codex_intake_private.capture_service_status(uuid,uuid)','pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)') OR release='r479') THEN RAISE EXCEPTION 'r479: pins unexpected or already applied'; END IF;
 IF NOT ((SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)='{postgres=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)='{postgres=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)='{postgres=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure)='{postgres=X/postgres}') THEN RAISE EXCEPTION 'r479: unexpected function grants'; END IF;
 IF to_regnamespace('pdc_service_snapshot_private') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_whole_snapshot_479' OR added_in='r479')
 THEN RAISE EXCEPTION 'r479: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=279 OR fault_id='F92') THEN RAISE EXCEPTION 'r479: sort_order 279 / F92 taken'; END IF;
END $g$;

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
  OR
  -- r479 (F92, Craig 22 Oct 2026 12:09 AWST): 'PMG PD Service as a Whole w/Sublet', the full snapshot of every open R/O for
  -- Depts 138 and 139 (status 20 to <90), replaces the hourly w/Sublet feed as the primary service import. Same 15 columns as
  -- w/Sublet (headers unwrapped from ="..." by the preparer), same collapse; the preparer marks it as a full snapshot.
  (p_provenance->>'source_kind'='revolution_automated_service_workbook'
   AND p_provenance->>'subject'='PMG PD Service as a Whole w/Sublet'
   AND p_provenance->>'report_title'='PMG PD Service as a Whole w/Sublet'
   AND p_filename ~ '^PMG PD Service as a Whole w[/_ -]?Sublet( - Job 1)?[.]xlsx?$'
   AND p_provenance->>'source_format'='ooxml_workbook'
   AND pdc_codex_intake_private.revolution_service_headers_439(p_provenance->'source_headers','["Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb)
   AND p_provenance->'source_headers' ? 'PO #'
   AND p_provenance->>'type_column'='absent_r442'
   AND p_provenance->>'line_collapse'='r442_one_row_per_dept_ro_line'
   AND p_provenance->>'snapshot_scope'='full_open_ro_snapshot_r479'
   AND p_provenance->>'identity_rule'='r479_exact_board_stock_or_job_card')
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
$f$;

CREATE OR REPLACE FUNCTION public.pdc_apply_tune_key_number_v1(p_vehicle_id uuid, p_batch_id uuid, p_preview_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $f$
declare b public.pdc_pilbara_service_import_batches%rowtype; v public.vehicles%rowtype; after_v public.vehicles%rowtype; keys text[];
begin
 select * into strict b from public.pdc_pilbara_service_import_batches where batch_id=p_batch_id and batch_kind='apply' and contract_revision='pmg_stock_v5';
 if not exists(select 1 from public.pdc_pilbara_service_import_batches where batch_id=p_preview_batch_id and batch_kind='preview' and source_hash=b.source_hash and contract_revision=b.contract_revision) then
  raise exception 'tune_key_preview_apply_mismatch' using errcode='22023';
 end if;
 select * into strict v from public.vehicles where id=p_vehicle_id and deleted_at is null for update;
 select array_agg(distinct k.key_number) filter(where k.key_number is not null) into keys
 from public.pdc_pilbara_service_import_rows r
 cross join lateral(select public.pdc_tune_key_number_v1(r.raw_row||r.normalized_payload) key_number) k
 where r.batch_id=p_preview_batch_id and r.stock_number=v.stock_number and (r.decision in('insert','unchanged') or (r.decision='quarantine' and r.reason='operation_update_review' and r.vehicle_id=v.id));
 if cardinality(keys)>1 then raise exception 'conflicting_tune_key_numbers' using errcode='22023'; end if;
 if keys[1] is null or keys[1] is not distinct from v.key_number then
  return jsonb_build_object('changed',false,'key_number',v.key_number);
 end if;
 -- r479 (F92): the 'as a Whole' report re-sends every open R/O every hour, so from it a Key Tag only fills a BLANK board key;
 -- a key already on the board (for example a controller's r460 edit) is kept. The w/Sublet and older reports are unchanged.
 if nullif(btrim(coalesce(v.key_number,'')),'') is not null and exists(select 1 from public.pdc_pilbara_service_import_rows r
   where r.batch_id=p_preview_batch_id and r.stock_number=v.stock_number and r.raw_row->>'email_subject'='PMG PD Service as a Whole w/Sublet') then
  return jsonb_build_object('changed',false,'key_number',v.key_number,'kept','board_key_not_blank_r479','file_key_number',keys[1]);
 end if;
 update public.vehicles set key_number=keys[1],
  source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_key_number',keys[1],'tune_key_batch_id',p_batch_id,'tune_key_source','Key Tag Number'),
  version=version+1,updated_by=b.created_by,updated_at=clock_timestamp() where id=v.id returning * into after_v;
 perform public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),to_jsonb(after_v),
  jsonb_build_object('contract','tune_key_tag_import_v1','source_batch_id',p_batch_id,'preview_batch_id',p_preview_batch_id));
 return jsonb_build_object('changed',true,'key_number',keys[1]);
end $f$;

CREATE FUNCTION pdc_codex_intake_private.service_99_used_479(p_vehicle_id uuid, p_stock text, p_company text, p_division text, p_ro text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $f$
 -- r479 (F92): why a Sub Status 99 on this R/O may no longer check this vehicle out (NULL = not used yet).
 --   checkout_receipt          the R/O is on one of the vehicle's Tune checkout receipts (it already checked it out)
 --   used_before_owner_reopen  the R/O was already at 99 in a service import before an owner reopen of the vehicle
 -- Read-only.
 SELECT CASE
  WHEN EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts r CROSS JOIN LATERAL jsonb_array_elements(coalesce(r.job_cards,'[]'::jsonb)) c
    WHERE r.vehicle_id=p_vehicle_id AND upper(btrim(c->>'ro'))=upper(btrim(p_ro))
     AND coalesce(c->>'company',p_company) IS NOT DISTINCT FROM p_company AND coalesce(c->>'division',p_division) IS NOT DISTINCT FROM p_division)
   THEN 'checkout_receipt'
  WHEN EXISTS(SELECT 1 FROM public.audit_events a WHERE a.vehicle_id=p_vehicle_id AND a.metadata->>'action'='owner_reopen_workshop_status'
    AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows ir
     WHERE upper(btrim(ir.repair_order_number))=upper(btrim(p_ro)) AND (ir.vehicle_id=p_vehicle_id OR ir.stock_number=p_stock)
      AND btrim(ir.raw_row->>'Sub Status')='99' AND coalesce(ir.raw_row->>'Company',p_company) IS NOT DISTINCT FROM p_company
      AND ir.created_at<a.created_at))
   THEN 'used_before_owner_reopen'
 END
$f$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text) FROM PUBLIC, anon, authenticated, service_role;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.capture_service_status(preview_id uuid, apply_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $f$
DECLARE r record; v public.vehicles%rowtype; old pdc_codex_intake_private.service_job_status%rowtype;
 b public.pdc_pilbara_service_import_batches%rowtype; matches integer; target uuid; problem text;
 receipt uuid; cards jsonb; latest timestamptz;
BEGIN
 SELECT * INTO STRICT b FROM public.pdc_pilbara_service_import_batches WHERE batch_id=apply_id AND batch_kind='apply'
 AND contract_revision='pmg_stock_v5' AND source_hash=(SELECT source_hash FROM public.pdc_pilbara_service_import_batches WHERE batch_id=preview_id AND batch_kind='preview');
 FOR r IN
 SELECT coalesce(raw_row->>'Company','') company,coalesce(raw_row->>'Division','') division,repair_order_number ro,
 min(stock_number) stock,count(DISTINCT coalesce(stock_number,'')) stocks,
 min(btrim(raw_row->>'Status')) status,min(nullif(btrim(raw_row->>'Sub Status'),'')) sub_status,
 count(DISTINCT coalesce(btrim(raw_row->>'Status'),'')) statuses,
 count(DISTINCT coalesce(btrim(raw_row->>'Sub Status'),'')) substatuses,
 min(raw_row->>'source_snapshot_at') snapshot_text,count(DISTINCT raw_row->>'source_snapshot_at') snapshots,
 bool_and(decision IN('insert','unchanged','duplicate') OR reason IN('operation_update_review','tune_checkout_status_only')) valid_rows,
 jsonb_agg(jsonb_build_object('row',raw_row->'source_row_number','stock',stock_number,'status',raw_row->'Status','sub_status',raw_row->'Sub Status','decision',decision,'reason',reason)) evidence
 FROM public.pdc_pilbara_service_import_rows WHERE batch_id=preview_id AND raw_row ? 'Sub Status'
 GROUP BY raw_row->>'Company',raw_row->>'Division',repair_order_number
 LOOP
  problem:=NULL;target:=NULL;
  IF r.company='' OR r.division='' OR nullif(r.ro,'') IS NULL OR nullif(r.stock,'') IS NULL OR r.stocks<>1
   OR r.substatuses<>1 OR r.snapshots<>1 OR r.snapshot_text IS NULL OR NOT r.valid_rows
   OR (r.sub_status IS NOT NULL AND r.sub_status !~ '^[0-9]{1,2}$')
  THEN problem:='invalid_or_unidentified_job_status';
  ELSE
   SELECT count(*),min(id::text)::uuid INTO matches,target FROM public.vehicles
   WHERE stock_number=r.stock AND deleted_at IS NULL AND board_purged_at IS NULL AND lifecycle_state::text IN('active','rft');
   IF matches<>1 THEN problem:='unmatched_or_historical_vehicle';
   ELSIF EXISTS(SELECT 1 FROM pdc_parts_private.jobs WHERE source_system='tune_pmg' AND company=r.company AND division=r.division AND ro_number=r.ro AND (vehicle_id<>target OR stock_number<>r.stock))
    THEN problem:='conflicting_stock_ro_mapping';
   ELSE
    SELECT * INTO old FROM pdc_codex_intake_private.service_job_status WHERE company=r.company AND division=r.division AND ro_number=r.ro FOR UPDATE;
    IF FOUND AND (old.vehicle_id<>target OR old.stock_number<>r.stock) THEN problem:='conflicting_stock_ro_mapping';
    ELSIF FOUND AND old.snapshot_at>r.snapshot_text::timestamptz THEN problem:='older_status_snapshot';
    ELSIF FOUND AND old.snapshot_at=r.snapshot_text::timestamptz AND (old.sub_status IS DISTINCT FROM r.sub_status)
     THEN problem:='conflicting_same_time_status';
    END IF;
   END IF;
  END IF;
  IF problem IS NOT NULL THEN
   INSERT INTO pdc_codex_intake_private.service_status_reviews(batch_id,company,division,ro_number,stock_number,reason,evidence)
   VALUES(apply_id,r.company,r.division,coalesce(r.ro,''),r.stock,problem,r.evidence) ON CONFLICT DO NOTHING; CONTINUE;
  END IF;
  INSERT INTO pdc_codex_intake_private.service_job_status(company,division,ro_number,vehicle_id,stock_number,status,sub_status,snapshot_at,batch_id)
  VALUES(r.company,r.division,r.ro,target,r.stock,r.status,r.sub_status,r.snapshot_text::timestamptz,apply_id)
  ON CONFLICT(company,division,ro_number) DO UPDATE SET status=coalesce(excluded.status,service_job_status.status),sub_status=excluded.sub_status,
   snapshot_at=excluded.snapshot_at,batch_id=excluded.batch_id,imported_at=clock_timestamp() WHERE true;

  IF EXISTS(SELECT 1 FROM public.vehicles WHERE id=target AND current_location='RFT') AND (
    r.sub_status IS DISTINCT FROM '99' OR EXISTS(
      SELECT 1 FROM public.pdc_pilbara_service_import_rows ir WHERE ir.batch_id=preview_id AND ir.repair_order_number=r.ro AND ir.stock_number=r.stock
       AND ir.reason='tune_checkout_status_only' AND NOT EXISTS(
        SELECT 1 FROM public.pdc_pilbara_service_operations op WHERE op.vehicle_id=target AND op.repair_order_number=r.ro
         AND op.original_line_number=ir.original_line_number AND op.department=ir.normalized_payload->>'department'
         AND op.operation_description=ir.normalized_payload->>'operation_description'
         AND op.source_estimated_hours IS NOT DISTINCT FROM (ir.normalized_payload->>'source_estimated_hours')::numeric))) THEN
   INSERT INTO pdc_codex_intake_private.service_status_reviews(batch_id,company,division,ro_number,stock_number,reason,evidence)
   VALUES(apply_id,r.company,r.division,r.ro,r.stock,'checked_out_job_change_requires_review',r.evidence) ON CONFLICT DO NOTHING;
  END IF;
 END LOOP;
 FOR v IN SELECT x.* FROM public.vehicles x WHERE x.id IN(SELECT vehicle_id FROM pdc_codex_intake_private.service_job_status WHERE batch_id=apply_id AND sub_status='99') FOR UPDATE LOOP
  IF v.deleted_at IS NOT NULL OR v.board_purged_at IS NOT NULL OR v.lifecycle_state::text NOT IN('active','rft') THEN CONTINUE; END IF;
  -- A checkout is consumed once. Replays must not erase inspections or QC rework.
  IF v.lifecycle_state::text='rft' OR upper(btrim(v.current_location)) IN ('QC','RFT')
   OR v.qc_completed_at IS NOT NULL OR v.rft_transferred_at IS NOT NULL
   OR EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts prior WHERE prior.vehicle_id=v.id)
   THEN CONTINUE; END IF;
  -- r479 (F92): a Sub Status 99 is used once. A 99 R/O already on one of the vehicle's checkout receipts, or already at 99
  -- in an import before an owner reopen (audit action owner_reopen_workshop_status), never checks the vehicle out again;
  -- only a 99 R/O not used that way can. The 'as a Whole' report re-sends every open R/O, 99s included, every hour.
  IF NOT EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_job_status u WHERE u.vehicle_id=v.id AND u.batch_id=apply_id AND u.sub_status='99'
     AND pdc_codex_intake_private.service_99_used_479(v.id,v.stock_number,u.company,u.division,u.ro_number) IS NULL)
   THEN CONTINUE; END IF;
  problem:=NULL;
  IF EXISTS(SELECT 1 FROM public.pdc_qc_vehicle_rejection_receipts_767 q WHERE q.vehicle_id=v.id)
   OR EXISTS(SELECT 1 FROM public.pdc_qc_operation_rejections_381 q WHERE q.vehicle_id=v.id AND q.active)
   THEN problem:='qc_rework_requires_review';
  END IF;
  -- Owner: any successfully matched R/O at 99 completes the whole vehicle.
  IF EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_status_reviews z WHERE z.batch_id=apply_id AND z.stock_number=v.stock_number)
   THEN problem:='job_status_validation_requires_review';
  END IF;
  IF problem IS NOT NULL THEN
   INSERT INTO pdc_codex_intake_private.service_status_reviews(batch_id,company,division,ro_number,stock_number,reason,evidence)
   SELECT apply_id,company,division,ro_number,stock_number,problem,jsonb_build_object('vehicle_id',v.id,'sub_status',sub_status)
   FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND batch_id=apply_id AND sub_status='99' ON CONFLICT DO NOTHING; CONTINUE;
  END IF;
  SELECT jsonb_agg(jsonb_build_object('company',company,'division',division,'ro',ro_number,'sub_status',sub_status,'snapshot_at',snapshot_at) ORDER BY company,division,ro_number),max(snapshot_at)
   INTO cards,latest FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND sub_status='99';
  INSERT INTO pdc_codex_intake_private.tune_checkout_receipts(vehicle_id,batch_id,snapshot_at,source_hash,job_cards,prior_location,actor_id)
  VALUES(v.id,apply_id,latest,b.source_hash,cards,v.current_location,b.created_by) RETURNING receipt_id INTO receipt;
  UPDATE public.pdc_new_vehicle_reviews SET status='closed',closed_at=clock_timestamp(),closure_reason='Tune checked out: Sub Status 99'
   WHERE vehicle_id=v.id AND status='pending';
  UPDATE public.vehicles SET current_location='QC',lifecycle_state='active',pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,visible_on_board=true,location_override=NULL,location_override_reason=NULL,location_override_at=NULL,location_override_by=NULL,
   version=version+1,updated_by=b.created_by,
   source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_checkout_receipt_id',receipt,'tune_checkout_source_snapshot',latest)
   WHERE id=v.id;
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),jsonb_build_object('current_location','QC','tune_checkout_receipt_id',receipt),jsonb_build_object('authority','Tune Sub Status 99','apply_batch_id',apply_id,'qc_signoff_created',false));
  PERFORM pdc_codex_intake_private.finish_tune_checkout(v.id);
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
   from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by,moved_at)
  VALUES(v.id,v.current_location,'QC',v.pmb_stage,NULL,v.pmb_bay_stage,NULL,v.pmb_bay_number,NULL,
   'Tune Sub Status 99: work completed; awaiting QC inspection. Receipt '||receipt,b.created_by,clock_timestamp());
 END LOOP;
 PERFORM pdc_codex_intake_private.apply_service_pmb_complete(apply_id);
END $f$;

CREATE SCHEMA pdc_service_snapshot_private;
REVOKE ALL ON SCHEMA pdc_service_snapshot_private FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON SCHEMA pdc_service_snapshot_private IS 'r479 (F92): full open-R/O service snapshots (as a Whole w/Sublet) and the read-only reconcile. No app-role access.';
CREATE TABLE pdc_service_snapshot_private.snapshots_479(
 snapshot_sha256 text PRIMARY KEY CHECK (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 report_title text NOT NULL CHECK (report_title='PMG PD Service as a Whole w/Sublet'),
 snapshot_scope text NOT NULL CHECK (snapshot_scope='full_open_ro_snapshot_r479'),
 source_snapshot_at timestamptz NOT NULL,
 gmail_message_id text,
 expected_line_count integer NOT NULL CHECK (expected_line_count BETWEEN 1 AND 100000),
 expected_ro_count integer NOT NULL CHECK (expected_ro_count BETWEEN 1 AND 100000),
 lib_md5 text,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by text NOT NULL DEFAULT current_user);
CREATE TABLE pdc_service_snapshot_private.snapshot_lines_479(
 snapshot_sha256 text NOT NULL REFERENCES pdc_service_snapshot_private.snapshots_479(snapshot_sha256) ON DELETE CASCADE,
 department text NOT NULL CHECK (department IN ('138','139')),
 repair_order_number text NOT NULL CHECK (repair_order_number ~ ('^J'||department||'[0-9]+$')),
 original_line_number integer NOT NULL CHECK (original_line_number>0),
 stock_number text,
 file_stock text,
 file_rego text,
 sub_status text,
 identity_status text NOT NULL CHECK (identity_status IN ('linked','no_board_vehicle','vehicle_not_live','ambiguous')),
 seen_at timestamptz NOT NULL,
 CHECK ((identity_status='linked')=(coalesce(btrim(stock_number),'')<>'')),
 PRIMARY KEY (snapshot_sha256,department,repair_order_number,original_line_number));
CREATE INDEX snapshot_lines_479_ro ON pdc_service_snapshot_private.snapshot_lines_479(repair_order_number);
CREATE INDEX snapshots_479_at ON pdc_service_snapshot_private.snapshots_479(source_snapshot_at DESC);
ALTER TABLE pdc_service_snapshot_private.snapshots_479 ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_service_snapshot_private.snapshot_lines_479 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_service_snapshot_private.snapshots_479, pdc_service_snapshot_private.snapshot_lines_479 FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION pdc_service_snapshot_private.append_only_479()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $f$
BEGIN
 -- r479 (F92): snapshot rows are evidence. No UPDATE ever; DELETE only through the retention step of record_snapshot_479
 -- (pdc.r479_prune) or the r479 undo (pdc.r479_undo).
 IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'r479: snapshot rows are append-only' USING ERRCODE='55000'; END IF;
 IF coalesce(current_setting('pdc.r479_prune',true),'')<>'on' AND coalesce(current_setting('pdc.r479_undo',true),'')<>'discard_snapshots' THEN
  RAISE EXCEPTION 'r479: snapshot rows are deleted only by retention or the r479 undo' USING ERRCODE='55000';
 END IF;
 RETURN OLD;
END
$f$;
CREATE TRIGGER snapshots_479_append_only BEFORE UPDATE OR DELETE ON pdc_service_snapshot_private.snapshots_479 FOR EACH ROW EXECUTE FUNCTION pdc_service_snapshot_private.append_only_479();
CREATE TRIGGER snapshot_lines_479_append_only BEFORE UPDATE OR DELETE ON pdc_service_snapshot_private.snapshot_lines_479 FOR EACH ROW EXECUTE FUNCTION pdc_service_snapshot_private.append_only_479();

CREATE FUNCTION pdc_service_snapshot_private.record_snapshot_479(p_header jsonb, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO 'pg_catalog', 'public'
AS $f$
DECLARE
 h jsonb:=p_header; v_sha text; v_at timestamptz; v_exp integer; v_ros integer; v_old pdc_service_snapshot_private.snapshots_479%rowtype;
 v_in integer:=0; v_total integer; v_bad jsonb; v_pruned integer:=0;
BEGIN
 -- r479 (F92): records one full 'as a Whole' snapshot (sha, R/O, line, seen_at) sent by the PMB Email preparer, in one or more
 -- calls (same header each time; lines may come in parts). Idempotent: a line already recorded with the same values is
 -- skipped; a different value for the same sha / line is refused. Writes ONLY this schema: never a vehicle, job, line,
 -- booking or hold. Keeps the newest 48 snapshots.
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'r479: staging only'; END IF;
 IF jsonb_typeof(h)<>'object' OR jsonb_typeof(p_lines)<>'array' OR jsonb_array_length(p_lines) NOT BETWEEN 1 AND 30000 THEN
  RAISE EXCEPTION 'r479: header object and 1 to 30000 lines required' USING ERRCODE='22023'; END IF;
 v_sha:=h->>'snapshot_sha256';
 IF coalesce(v_sha,'') !~ '^[0-9a-f]{64}$' OR h->>'report_title' IS DISTINCT FROM 'PMG PD Service as a Whole w/Sublet'
    OR h->>'snapshot_scope' IS DISTINCT FROM 'full_open_ro_snapshot_r479' OR coalesce(h->>'source_snapshot_at','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
    OR coalesce(h->>'line_count','') !~ '^[0-9]{1,5}$' OR coalesce(h->>'ro_count','') !~ '^[0-9]{1,5}$' THEN
  RAISE EXCEPTION 'r479: invalid snapshot header' USING ERRCODE='22023'; END IF;
 v_at:=(h->>'source_snapshot_at')::timestamptz; v_exp:=(h->>'line_count')::integer; v_ros:=(h->>'ro_count')::integer;
 IF v_exp<1 OR v_ros<1 OR v_at>clock_timestamp()+interval '10 minutes' THEN RAISE EXCEPTION 'r479: invalid snapshot header values' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(e.o ORDER BY e.o),'[]'::jsonb) INTO v_bad FROM jsonb_array_elements(p_lines) WITH ORDINALITY e(x,o)
  WHERE jsonb_typeof(e.x)<>'array' OR jsonb_array_length(e.x)<>8
   OR e.x->>0 NOT IN ('138','139') OR coalesce(e.x->>1,'') !~ ('^J'||(e.x->>0)||'[0-9]+$')
   OR jsonb_typeof(e.x->2)<>'number' OR coalesce(e.x->>2,'') !~ '^[1-9][0-9]{0,4}$'
   OR jsonb_typeof(e.x->3) NOT IN ('string','null') OR jsonb_typeof(e.x->4) NOT IN ('string','null')
   OR jsonb_typeof(e.x->5) NOT IN ('string','null') OR jsonb_typeof(e.x->6) NOT IN ('string','null')
   OR e.x->>7 NOT IN ('linked','no_board_vehicle','vehicle_not_live','ambiguous')
   OR ((e.x->>7='linked') <> (btrim(coalesce(e.x->>3,''))<>''));
 IF jsonb_array_length(v_bad)>0 THEN RAISE EXCEPTION 'r479: invalid snapshot lines at %',left(v_bad::text,200) USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('r479:snapshot:'||v_sha,0));
 SELECT * INTO v_old FROM pdc_service_snapshot_private.snapshots_479 WHERE snapshot_sha256=v_sha;
 IF FOUND THEN
  IF v_old.source_snapshot_at<>v_at OR v_old.expected_line_count<>v_exp OR v_old.expected_ro_count<>v_ros THEN
   RAISE EXCEPTION 'r479: snapshot % already recorded with a different header',v_sha USING ERRCODE='23505'; END IF;
 ELSE
  INSERT INTO pdc_service_snapshot_private.snapshots_479(snapshot_sha256,report_title,snapshot_scope,source_snapshot_at,gmail_message_id,expected_line_count,expected_ro_count,lib_md5)
  VALUES(v_sha,h->>'report_title',h->>'snapshot_scope',v_at,left(h->>'gmail_message_id',120),v_exp,v_ros,left(h->>'lib_md5',32));
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_lines) e(x) JOIN pdc_service_snapshot_private.snapshot_lines_479 l
   ON l.snapshot_sha256=v_sha AND l.department=e.x->>0 AND l.repair_order_number=e.x->>1 AND l.original_line_number=(e.x->>2)::integer
   WHERE (l.stock_number,l.file_stock,l.file_rego,l.sub_status,l.identity_status) IS DISTINCT FROM (e.x->>3,e.x->>4,e.x->>5,e.x->>6,e.x->>7)) THEN
  RAISE EXCEPTION 'r479: a line of snapshot % was already recorded with different values',v_sha USING ERRCODE='23505'; END IF;
 INSERT INTO pdc_service_snapshot_private.snapshot_lines_479(snapshot_sha256,department,repair_order_number,original_line_number,stock_number,file_stock,file_rego,sub_status,identity_status,seen_at)
 SELECT v_sha,e.x->>0,e.x->>1,(e.x->>2)::integer,e.x->>3,e.x->>4,e.x->>5,e.x->>6,e.x->>7,v_at FROM jsonb_array_elements(p_lines) e(x)
 ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS v_in=ROW_COUNT;
 SELECT count(*) INTO v_total FROM pdc_service_snapshot_private.snapshot_lines_479 WHERE snapshot_sha256=v_sha;
 IF v_total>v_exp THEN RAISE EXCEPTION 'r479: snapshot % has more lines (%) than its header (%)',v_sha,v_total,v_exp USING ERRCODE='22023'; END IF;
 IF v_total=v_exp THEN
  IF (SELECT count(DISTINCT (department,repair_order_number)) FROM pdc_service_snapshot_private.snapshot_lines_479 WHERE snapshot_sha256=v_sha)<>v_ros THEN
   RAISE EXCEPTION 'r479: snapshot % R/O count differs from its header',v_sha USING ERRCODE='22023'; END IF;
  PERFORM set_config('pdc.r479_prune','on',true);
  DELETE FROM pdc_service_snapshot_private.snapshots_479 s WHERE s.snapshot_sha256 IN (
   SELECT x.snapshot_sha256 FROM pdc_service_snapshot_private.snapshots_479 x ORDER BY x.source_snapshot_at DESC, x.recorded_at DESC OFFSET 48);
  GET DIAGNOSTICS v_pruned=ROW_COUNT;
  PERFORM set_config('pdc.r479_prune','off',true);
 END IF;
 RETURN jsonb_build_object('contract','pdc-service-whole-snapshot-479','ok',true,'snapshot_sha256',v_sha,'source_snapshot_at',v_at,
  'lines_recorded_now',v_in,'lines_total',v_total,'line_count',v_exp,'complete',v_total=v_exp,'snapshots_pruned',v_pruned,
  'writes','pdc_service_snapshot_private only (no vehicle, job, line, booking or hold)');
END
$f$;

CREATE FUNCTION pdc_service_snapshot_private.reconcile_479(p_sha text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $f$
DECLARE v_win text[]; v_res jsonb; v_items jsonb; v_flag boolean;
BEGIN
 -- r479 (F92): READ-ONLY review list from the newest complete 'as a Whole' snapshot(s) against the board. Never closes,
 -- hides, deletes or changes anything. A board vehicle / R/O is flagged as missing only when absent from the last TWO
 -- consecutive complete snapshots (before that it is reported as *_pending). p_sha picks the newest snapshot to use.
 SELECT array_agg(s.snapshot_sha256 ORDER BY s.source_snapshot_at DESC, s.recorded_at DESC) INTO v_win FROM (
  SELECT x.* FROM pdc_service_snapshot_private.snapshots_479 x
  WHERE (SELECT count(*) FROM pdc_service_snapshot_private.snapshot_lines_479 l WHERE l.snapshot_sha256=x.snapshot_sha256)=x.expected_line_count
   AND (p_sha IS NULL OR x.source_snapshot_at<=(SELECT y.source_snapshot_at FROM pdc_service_snapshot_private.snapshots_479 y WHERE y.snapshot_sha256=p_sha))
  ORDER BY x.source_snapshot_at DESC, x.recorded_at DESC LIMIT 2) s;
 IF p_sha IS NOT NULL AND (v_win IS NULL OR v_win[1]<>p_sha) THEN
  RETURN jsonb_build_object('contract','pdc-service-whole-reconcile-479','ok',false,'code','snapshot_not_complete_or_unknown','snapshot_sha256',p_sha);
 END IF;
 IF v_win IS NULL THEN
  RETURN jsonb_build_object('contract','pdc-service-whole-reconcile-479','ok',true,'note','no_complete_snapshot','snapshots',jsonb_build_array(),
   'counts',jsonb_build_object(),'items',jsonb_build_array(),'missing_after_consecutive_snapshots',2,'read_only',true);
 END IF;
 v_flag:=cardinality(v_win)>=2;
 WITH latest AS (SELECT * FROM pdc_service_snapshot_private.snapshot_lines_479 WHERE snapshot_sha256=v_win[1]),
 ro AS (SELECT department,repair_order_number,min(identity_status) ident,min(stock_number) stock,min(file_stock) file_stock,min(file_rego) file_rego,
   count(*) lines,bool_and(coalesce(sub_status,'') IN ('80','99')) all_closing,array_agg(DISTINCT sub_status ORDER BY sub_status) subs
  FROM latest GROUP BY department,repair_order_number),
 win AS (SELECT * FROM pdc_service_snapshot_private.snapshot_lines_479 WHERE snapshot_sha256=ANY(v_win)),
 seen_ro AS (SELECT upper(btrim(repair_order_number)) ro,count(DISTINCT snapshot_sha256) n FROM win GROUP BY 1),
 seen_stock AS (SELECT k,count(DISTINCT snapshot_sha256) n FROM win CROSS JOIN LATERAL (VALUES (upper(btrim(stock_number))),(upper(btrim(file_stock))),(upper(btrim(file_rego)))) t(k)
  WHERE coalesce(k,'')<>'' GROUP BY 1),
 live AS (SELECT v.id,v.stock_number FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state::text IN ('active','rft')),
 openjob AS (SELECT DISTINCT l.id vehicle_id,l.stock_number,upper(btrim(j.ro_number)) ro FROM pdc_parts_private.jobs j JOIN live l ON l.id=j.vehicle_id
  WHERE j.closed_at IS NULL AND j.company='01' AND j.division='1' AND coalesce(btrim(j.ro_number),'')<>''),
 veh AS (SELECT o.vehicle_id,min(o.stock_number) stock,array_agg(DISTINCT o.ro ORDER BY o.ro) ros,
   NOT EXISTS(SELECT 1 FROM seen_stock s WHERE s.k=upper(btrim(min(o.stock_number))))
   AND NOT EXISTS(SELECT 1 FROM seen_ro s WHERE s.ro=ANY(array_agg(o.ro))) absent
  FROM openjob o GROUP BY o.vehicle_id),
 items AS (
  SELECT 1 g,department||repair_order_number s,jsonb_build_object('category','open_ro_no_board_vehicle','reason',ident,'department',department,'ro',repair_order_number,
    'file_stock',file_stock,'file_rego',file_rego,'lines',lines) i FROM ro WHERE ident<>'linked'
  UNION ALL
  SELECT 2,department||repair_order_number,jsonb_build_object('category','ro_all_lines_80_99_still_open','department',department,'ro',repair_order_number,'stock',stock,
    'lines',lines,'sub_status',to_jsonb(subs),
    -- r479: a 99 already used (receipt / before an owner reopen) will not check the vehicle out again
    'checkout_99_used',CASE WHEN '99'=ANY(subs) THEN (SELECT pdc_codex_intake_private.service_99_used_479(l.id,l.stock_number,'01','1',ro.repair_order_number)
      FROM live l WHERE l.stock_number=ro.stock ORDER BY l.id LIMIT 1) END) FROM ro WHERE all_closing
  UNION ALL
  SELECT 3,upper(btrim(stock)),jsonb_build_object('category',CASE WHEN v_flag THEN 'board_vehicle_missing' ELSE 'board_vehicle_missing_pending' END,'stock',stock,'open_ros',to_jsonb(ros))
   FROM veh WHERE absent
  UNION ALL
  SELECT 4,upper(btrim(o.stock_number))||o.ro,jsonb_build_object('category',CASE WHEN v_flag THEN 'board_ro_missing' ELSE 'board_ro_missing_pending' END,'stock',o.stock_number,'ro',o.ro)
   FROM openjob o JOIN veh ON veh.vehicle_id=o.vehicle_id AND NOT veh.absent WHERE NOT EXISTS(SELECT 1 FROM seen_ro s WHERE s.ro=o.ro))
 SELECT coalesce(jsonb_agg(i ORDER BY g,s),'[]'::jsonb) INTO v_items FROM items;
 SELECT coalesce(jsonb_object_agg(c,n),'{}'::jsonb) INTO v_res FROM (SELECT x->>'category' c,count(*) n FROM jsonb_array_elements(v_items) x GROUP BY 1) q;
 RETURN jsonb_build_object('contract','pdc-service-whole-reconcile-479','ok',true,'read_only',true,'missing_after_consecutive_snapshots',2,
  'snapshots',(SELECT jsonb_agg(jsonb_build_object('snapshot_sha256',s.snapshot_sha256,'source_snapshot_at',s.source_snapshot_at,'lines',s.expected_line_count,'ros',s.expected_ro_count)
    ORDER BY s.source_snapshot_at DESC) FROM pdc_service_snapshot_private.snapshots_479 s WHERE s.snapshot_sha256=ANY(v_win)),
  'counts',v_res,'items',v_items);
END
$f$;

CREATE FUNCTION pdc_service_snapshot_private.review_list_479()
 RETURNS TABLE(category text, reason text, department text, ro text, stock text, item jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $f$
 -- r479 (F92): the reconcile review list as rows (read-only).
 SELECT x->>'category', x->>'reason', x->>'department', x->>'ro', coalesce(x->>'stock',x->>'file_stock',x->>'file_rego'), x
 FROM jsonb_array_elements(coalesce(pdc_service_snapshot_private.reconcile_479(NULL)->'items','[]'::jsonb)) x
$f$;
REVOKE ALL ON FUNCTION pdc_service_snapshot_private.append_only_479(), pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb),
 pdc_service_snapshot_private.reconcile_479(text), pdc_service_snapshot_private.review_list_479() FROM PUBLIC, anon, authenticated, service_role;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='63ff5dabf94abcdf7c278fb3afa9bd96',release='r479',note='r479 (F92): as a Whole w/Sublet branch added (was e4ba03437490bd155d4d8553285107f8 r442)',updated_at=now() WHERE signature='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='b5e3ab4517bd59a1931509a2b9a1299f',release='r479',note='r479 (F92): as a Whole rows: w/Sublet rules + snapshot marker + board identity, one row per line, never mixed (was 0534336e01558066cf7ec3dcb3995cd4 r444)',updated_at=now() WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)','7db7b5482de592222cfc5828ff9e6a45','r479','r479 (F92): from an as a Whole preview a Key Tag only fills a blank board key (was 4b25c88071288d598d4ae29c50320d3b, unpinned)'),
 ('pdc_service_snapshot_private.append_only_479()','1ab209a3fff8dbc2efe3051f17c42703','r479','r479 (F92): snapshot rows append-only (retention / undo only)'),
 ('pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)','fe1aa81a9ff00b6071eb4c0b7ea1a4ab','r479','r479 (F92): record one as a Whole snapshot (sha, R/O, line, seen_at); writes only its schema'),
 ('pdc_service_snapshot_private.reconcile_479(text)','f4470aaa28afeb5a89fa206edb8a6076','r479','r479 (F92): read-only reconcile / review list (missing only after 2 consecutive snapshots)'),
 ('pdc_service_snapshot_private.review_list_479()','a84de72c728027dcea5a2d9adb4c04ad','r479','r479 (F92): review list rows (read-only)'),
 ('pdc_codex_intake_private.capture_service_status(uuid,uuid)','7870d544117de6a5465b8212f0d228b7','r479','r479 (F92): a Sub Status 99 checks a vehicle out once (used on a receipt / before an owner reopen: never again) (was 3cc871d85d84195d9f8f65113a03e1ef, unpinned)'),
 ('pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)','574255e4c99e77830069f74ad849d9b4','r479','r479 (F92): which 99 R/Os are already used (read-only)');
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('service_whole_snapshot_479','F92','Service as a Whole w/Sublet (r479): the manifest accepts the authenticated full open-R/O snapshot (and still w/Sublet, never crossed); the row validator needs the snapshot marker, the board identity and a stock, one row per line, never mixed; a Key Tag from it only fills a blank key; the snapshot schema is private and its reconcile is read-only and runs; no partial snapshot older than 2 h',
  $chk$WITH e AS (
 SELECT jsonb_build_object('source_kind','revolution_automated_service_workbook','authority','explicit_user_request',
  'user_instruction','Owner standing authority for genuine Revolution 138/139 service import contracts (r479 check)','company','01','division','1',
  'subject','PMG PD Service as a Whole w/Sublet','report_title','PMG PD Service as a Whole w/Sublet','source_format','ooxml_workbook',
  'source_headers','["Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #","Description of sublet","PO #"]'::jsonb,
  'type_column','absent_r442','line_collapse','r442_one_row_per_dept_ro_line','snapshot_scope','full_open_ro_snapshot_r479','identity_rule','r479_exact_board_stock_or_job_card',
  'authentication',jsonb_build_object('gmail_message_id','abcdef1234567479','from_address','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com',
   'to_address','pmbcontroller@gmail.com','verified_by','gmail_receiving_provider','header_from','revolutionsoftware.com.au',
   'authentication_results','mx.google.com; spf=pass smtp.mailfrom=noreply@revolutionsoftware.com.au; dmarc=pass header.from=revolutionsoftware.com.au')) p
), rw AS (
 SELECT jsonb_build_object('department','139','repair_order_number','J139999479','original_line_number',4,'stock_number','SYN479','raw_row',jsonb_build_object('Dept','139','Company','01','Division','1',
  'from_address','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com','email_subject','PMG PD Service as a Whole w/Sublet',
  'source_kind','revolution_automated_service_workbook','line_collapse','r442_one_row_per_dept_ro_line','snapshot_scope','full_open_ro_snapshot_r479',
  'identity_r479',jsonb_build_object('rule','r479_exact_board_stock_or_job_card','basis','stock_column'),
  'sublet_pos','["GP13900479"]'::jsonb,'sublet_po_descriptions','{"GP13900479":"SYNTHETIC"}'::jsonb,
  'source_row_numbers','[5,6]'::jsonb,'collapse',jsonb_build_object('rule','r442_one_row_per_dept_ro_line','source_rows',2,'hours_summed',false,'conflict',false))) r
), ws AS (
 SELECT jsonb_set(jsonb_set(e.p,'{subject}','"PMG PD Service Complete w/Sublet"'),'{report_title}','"PMG PD Service Complete w/Sublet"')-'snapshot_scope'-'identity_rule' p FROM e
), src AS (
 SELECT (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)')) k,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)')) rec,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('pdc_service_snapshot_private.reconcile_479(text)')) rcn,
  (SELECT provolatile FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('pdc_service_snapshot_private.reconcile_479(text)')) rcn_vol,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.capture_service_status(uuid,uuid)')) cap
), rc AS (SELECT pdc_service_snapshot_private.reconcile_479(NULL) j
), w AS (
 SELECT
  pdc_codex_intake_private.revolution_service_manifest_20261006(e.p,'abcdef1234567479','PMG PD Service as a Whole w/Sublet.xlsx')
   AND pdc_codex_intake_private.revolution_service_manifest_20261006(e.p,'abcdef1234567479','PMG PD Service as a Whole w_Sublet - Job 1.xls')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e.p,'abcdef1234567479','PMG PD Service Complete w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e.p,'abcdef1234567479','PMG PD Service as a Whole w/Sublet - Job 2.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e.p-'snapshot_scope','abcdef1234567479','PMG PD Service as a Whole w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(e.p-'identity_rule','abcdef1234567479','PMG PD Service as a Whole w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e.p,'{source_headers}',jsonb_build_array('Type')||(e.p->'source_headers')),'abcdef1234567479','PMG PD Service as a Whole w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e.p,'{report_title}','"PMG PD Service Complete w/Sublet"'),'abcdef1234567479','PMG PD Service as a Whole w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb_set(e.p,'{authentication,from_address}','"fake@example.com"'),'abcdef1234567479','PMG PD Service as a Whole w/Sublet.xlsx')
   AND pdc_codex_intake_private.revolution_service_manifest_20261006(ws.p,'abcdef1234567479','PMG PD Service Complete w/Sublet.xlsx')
   AND NOT pdc_codex_intake_private.revolution_service_manifest_20261006(ws.p,'abcdef1234567479','PMG PD Service as a Whole w/Sublet.xlsx') AS manifest,
  pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r))
   AND pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r,jsonb_set(rw.r,'{original_line_number}','5')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r,rw.r))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,Type}','"D"')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r #- '{raw_row,snapshot_scope}'))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r #- '{raw_row,identity_r479}'))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{stock_number}','""')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,collapse,hours_summed}','true')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r,jsonb_set(jsonb_set(rw.r,'{raw_row,email_subject}','"PMG PD Service Complete w/Sublet"'),'{original_line_number}','5')))
   AND pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,email_subject}','"PMG PD Service Complete w/Sublet"') #- '{raw_row,snapshot_scope}' #- '{raw_row,identity_r479}')) AS rows_contract,
  position($q$'board_key_not_blank_r479'$q$ in src.k)>0 AND position($q$r.raw_row->>'email_subject'='PMG PD Service as a Whole w/Sublet'$q$ in src.k)>0 AS key_fill_blank_only,
  NOT has_function_privilege('anon','pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)','EXECUTE')
   AND NOT has_function_privilege('authenticated','pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)','EXECUTE')
   AND NOT has_function_privilege('service_role','pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)','EXECUTE')
   AND NOT has_function_privilege('anon','pdc_service_snapshot_private.reconcile_479(text)','EXECUTE')
   AND NOT has_function_privilege('authenticated','pdc_service_snapshot_private.reconcile_479(text)','EXECUTE')
   AND NOT has_function_privilege('authenticated','pdc_service_snapshot_private.review_list_479()','EXECUTE')
   AND NOT has_table_privilege('authenticated','pdc_service_snapshot_private.snapshot_lines_479','SELECT')
   AND NOT has_table_privilege('anon','pdc_service_snapshot_private.snapshots_479','SELECT')
   AND (SELECT bool_and(relrowsecurity) FROM pg_catalog.pg_class WHERE oid IN (to_regclass('pdc_service_snapshot_private.snapshots_479'),to_regclass('pdc_service_snapshot_private.snapshot_lines_479'))) AS private,
  src.rec !~* '(INSERT INTO|UPDATE|DELETE FROM)\s+public\.' AND src.rcn !~* '(INSERT|UPDATE|DELETE)\s' AND src.rcn_vol='s' AS writes_nothing_outside,
  rc.j->>'contract'='pdc-service-whole-reconcile-479' AND (rc.j->>'ok')::boolean AS reconcile_runs,
  position('pdc_codex_intake_private.service_99_used_479(v.id,v.stock_number,u.company,u.division,u.ro_number) IS NULL' in src.cap)>0
   AND position('tune_checkout_receipts prior WHERE prior.vehicle_id=v.id' in src.cap)>0
   AND to_regprocedure('pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)') IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts GROUP BY vehicle_id HAVING count(*)>1) AS checkout_99_once,
  NOT EXISTS(SELECT 1 FROM pdc_service_snapshot_private.snapshots_479 s WHERE s.recorded_at<clock_timestamp()-interval '2 hours'
   AND (SELECT count(*) FROM pdc_service_snapshot_private.snapshot_lines_479 l WHERE l.snapshot_sha256=s.snapshot_sha256)<>s.expected_line_count) AS no_stale_partial
 FROM e, rw, ws, src, rc
)
SELECT w.manifest AND w.rows_contract AND w.key_fill_blank_only AND w.private AND w.writes_nothing_outside AND w.reconcile_runs AND w.checkout_99_once AND w.no_stale_partial AS ok,
 format('as a Whole manifest %s, row contract %s, key fills blank only %s, private %s, writes nothing outside %s, reconcile runs %s, a 99 checks a vehicle out once %s, no partial snapshot older than 2 h %s; %s snapshots kept, newest %s; review list %s',
  w.manifest,w.rows_contract,w.key_fill_blank_only,w.private,w.writes_nothing_outside,w.reconcile_runs,w.checkout_99_once,w.no_stale_partial,
  (SELECT count(*) FROM pdc_service_snapshot_private.snapshots_479),
  coalesce((SELECT to_char(max(source_snapshot_at) AT TIME ZONE 'Australia/Perth','DD Mon HH24:MI "AWST"') FROM pdc_service_snapshot_private.snapshots_479),'none yet'),
  coalesce((SELECT rc.j->>'counts' FROM rc),'{}')) AS detail
FROM w$chk$,true,279,'r479');

DO $g$ DECLARE r record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)<>'63ff5dabf94abcdf7c278fb3afa9bd96'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'b5e3ab4517bd59a1931509a2b9a1299f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)<>'7db7b5482de592222cfc5828ff9e6a45'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_service_snapshot_private.append_only_479()'::regprocedure)<>'1ab209a3fff8dbc2efe3051f17c42703'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)'::regprocedure)<>'fe1aa81a9ff00b6071eb4c0b7ea1a4ab'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_service_snapshot_private.reconcile_479(text)'::regprocedure)<>'f4470aaa28afeb5a89fa206edb8a6076'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_service_snapshot_private.review_list_479()'::regprocedure)<>'a84de72c728027dcea5a2d9adb4c04ad'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure)<>'7870d544117de6a5465b8212f0d228b7'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)'::regprocedure)<>'574255e4c99e77830069f74ad849d9b4' THEN RAISE EXCEPTION 'r479: functions did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r479')<>9 THEN RAISE EXCEPTION 'r479: pins not written'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='service_whole_snapshot_479' AND added_in='r479' AND sort_order=279)<>'856d54308605e8995c85265a198c64fd' THEN RAISE EXCEPTION 'r479: check did not land as expected'; END IF;
 IF NOT ((SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)='{postgres=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)='{postgres=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)='{postgres=X/postgres}')
    OR has_function_privilege('authenticated','pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)','EXECUTE') OR has_function_privilege('service_role','pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)','EXECUTE')
    OR has_function_privilege('anon','pdc_service_snapshot_private.reconcile_479(text)','EXECUTE') OR has_function_privilege('authenticated','pdc_service_snapshot_private.reconcile_479(text)','EXECUTE') OR has_function_privilege('service_role','pdc_service_snapshot_private.reconcile_479(text)','EXECUTE')
    OR has_function_privilege('authenticated','pdc_service_snapshot_private.review_list_479()','EXECUTE')
    OR (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}'
    OR has_function_privilege('authenticated','pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)','EXECUTE') OR has_function_privilege('service_role','pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)','EXECUTE') OR has_function_privilege('anon','pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)','EXECUTE') THEN RAISE EXCEPTION 'r479: grants changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'0aaaa15690ca286ed0db87fc72271d5a'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)<>'375bffc2dced95a7a5c74c3273dbccb3'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'fc3717a5215de94c93ebb2c7facfe744' THEN RAISE EXCEPTION 'r479: tick / preview / apply changed'; END IF;
 -- run protected_function_md5s and the new check exactly as the daily suite does (search_path pg_catalog); refuse if either fails
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name IN ('protected_function_md5s','service_whole_snapshot_479','service_wsublet_contract_and_po_feed') AND enabled ORDER BY sort_order LOOP
  DECLARE x record; BEGIN
   PERFORM set_config('search_path','pg_catalog',true);
   EXECUTE r.check_sql INTO x;
   PERFORM set_config('search_path','"$user", public, extensions',true);
   IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r479: daily check % fails after the migration: %', r.check_name, left(x.detail,300); END IF;
  END;
 END LOOP;
END $g$;
