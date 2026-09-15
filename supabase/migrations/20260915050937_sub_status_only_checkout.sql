-- Owner: Sub Status99 alone triggers checkout; Status is no longer required or used for eligibility.
DO $guard$ BEGIN IF md5(replace(pg_get_functiondef('pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure),E'\r\n',E'\n')) <> 'a2e4663f72513f7156659396d918eb8b' THEN RAISE EXCEPTION 'Concurrent checkout function change'; END IF; END $guard$;
ALTER TABLE pdc_codex_intake_private.service_job_status ALTER COLUMN status DROP NOT NULL;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.capture_service_status(preview_id uuid, apply_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  IF v.current_location='RFT' THEN CONTINUE; END IF;
  problem:=NULL;
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
  UPDATE public.vehicles SET current_location='RFT',lifecycle_state='rft',visible_on_board=true,location_override=NULL,location_override_reason=NULL,location_override_at=NULL,location_override_by=NULL,
   rft_transferred_at=coalesce(rft_transferred_at,clock_timestamp()),version=version+1,updated_by=b.created_by,
   source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_checkout_receipt_id',receipt,'tune_checkout_source_snapshot',latest)
   WHERE id=v.id;
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),jsonb_build_object('current_location','RFT','tune_checkout_receipt_id',receipt),jsonb_build_object('authority','Tune Sub Status 99','apply_batch_id',apply_id,'qc_signoff_created',false));
  PERFORM pdc_codex_intake_private.finish_tune_checkout(v.id);
 END LOOP;
END $function$
;

