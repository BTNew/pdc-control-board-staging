-- r479 (F92) undo. Staging cdsmnqxtyyoeoznmbidd only; ONE transaction, between :02 and :45 (lock_timeout 2s).
-- Restores the manifest (e4ba0343, pin r442), the row validator (0534336e, pin r444) and pdc_apply_tune_key_number_v1
-- (4b25c880, unpinned) and capture_service_status (3cc871d8, unpinned; CRLF rebuilt with chr(13)) byte for byte, drops service_99_used_479, removes the
-- 7 other r479 pins and the check, and drops pdc_service_snapshot_private.
-- Refuses while any snapshot is recorded unless the session sets pdc.r479_undo = 'discard_snapshots' (snapshots are
-- re-creatable from the retained report files; export them first if wanted). Run BEFORE reverting the PR. Never touches a
-- vehicle, job, line, booking or hold; keys already filled from an as a Whole file stay (audited by r460).
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
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)<>'63ff5dabf94abcdf7c278fb3afa9bd96'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'b5e3ab4517bd59a1931509a2b9a1299f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)<>'7db7b5482de592222cfc5828ff9e6a45'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure)<>'7870d544117de6a5465b8212f0d228b7'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)'::regprocedure)<>'574255e4c99e77830069f74ad849d9b4'
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r479')<>9 THEN RAISE EXCEPTION 'r479 undo: r479 is not applied as shipped'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_service_snapshot_private.snapshots_479) AND coalesce(current_setting('pdc.r479_undo',true),'')<>'discard_snapshots' THEN
  RAISE EXCEPTION 'r479 undo: % snapshots recorded; export them, then SET LOCAL pdc.r479_undo = ''discard_snapshots'' and re-run', (SELECT count(*) FROM pdc_service_snapshot_private.snapshots_479); END IF;
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
      WHERE jsonb_typeof(d.value)<>'string' OR length(d.value#>>'{}')>4000 OR NOT (x->'raw_row'->'sublet_pos') ? d.key)))),false)
 OR coalesce(x->>'repair_order_number','') !~ ('^J'||(x->>'department')||'[0-9]+$'))
 -- r442 (F54): a w/Sublet file is all w/Sublet rows, exactly one per Dept + R/O + Line # (never a repeated line, so never summed hours)
 AND (SELECT count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet') IN (0,count(*))
       AND count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet')
        =count(DISTINCT (x->>'department')||'|'||upper(x->>'repair_order_number')||'|'||coalesce(x->>'original_line_number',x->'raw_row'->>'Line #',''))
          FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet')
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
 update public.vehicles set key_number=keys[1],
  source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_key_number',keys[1],'tune_key_batch_id',p_batch_id,'tune_key_source','Key Tag Number'),
  version=version+1,updated_by=b.created_by,updated_at=clock_timestamp() where id=v.id returning * into after_v;
 perform public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),to_jsonb(after_v),
  jsonb_build_object('contract','tune_key_tag_import_v1','source_batch_id',p_batch_id,'preview_batch_id',p_preview_batch_id));
 return jsonb_build_object('changed',true,'key_number',keys[1]);
end $f$;

-- capture_service_status: staging's body has CRLF line endings (md5 3cc871d8). Transports such as apply_migration turn CRLF
-- into LF, so the statement is kept LF here and its line endings are rebuilt explicitly (strip any CR, then every LF -> CR LF).
DO $r479cap$ BEGIN
 EXECUTE replace(replace($cap479$CREATE OR REPLACE FUNCTION pdc_codex_intake_private.capture_service_status(preview_id uuid, apply_id uuid)
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
   snapshot_at=excluded.snapshot_at,batch_id=excluded.batch_id,imported_at=clock_timestamp();

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
END $f$;$cap479$, chr(13), ''), chr(10), chr(13)||chr(10));
END $r479cap$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='service_whole_snapshot_479' AND added_in='r479';
DELETE FROM pdc_ops.expected_function_md5 WHERE signature IN ('public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)','pdc_service_snapshot_private.append_only_479()','pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)','pdc_service_snapshot_private.reconcile_479(text)','pdc_service_snapshot_private.review_list_479()','pdc_codex_intake_private.capture_service_status(uuid,uuid)','pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)') AND release='r479';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='e4ba03437490bd155d4d8553285107f8',release='r442',note='r442 (F54): w/Sublet workbook branch added (was 88c75359be6f3e4802c3c1a8f8fd3e10 r439)',updated_at=now() WHERE signature='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)' AND release='r479';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0534336e01558066cf7ec3dcb3995cd4',release='r444',note='r444 (F57): optional raw_row.sublet_po_descriptions (object keyed by the line POs, strings) (was fd1d9272719cba74fdca23f9015d6d08 r442)',updated_at=now() WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)' AND release='r479';
SELECT set_config('pdc.r479_undo','discard_snapshots',true);
DROP SCHEMA pdc_service_snapshot_private CASCADE;
DROP FUNCTION pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text);
DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)<>'e4ba03437490bd155d4d8553285107f8'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'0534336e01558066cf7ec3dcb3995cd4'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)<>'4b25c88071288d598d4ae29c50320d3b'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure)<>'3cc871d85d84195d9f8f65113a03e1ef'
    OR to_regprocedure('pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)') IS NOT NULL
    OR to_regnamespace('pdc_service_snapshot_private') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r479') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r479')
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)') IS DISTINCT FROM 'e4ba03437490bd155d4d8553285107f8r442'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)') IS DISTINCT FROM '0534336e01558066cf7ec3dcb3995cd4r444'
    OR NOT ((SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)='{postgres=X/postgres}'
     AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)='{postgres=X/postgres}'
     AND (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)='{postgres=X/postgres}'
     AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure)='{postgres=X/postgres}') THEN RAISE EXCEPTION 'r479 undo: not restored as expected'; END IF;
END $g$;
