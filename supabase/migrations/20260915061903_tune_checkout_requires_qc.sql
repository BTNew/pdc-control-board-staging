-- STAGING ONLY. Tune Sub Status 99 completes workshop work and queues QC.
-- It does not sign off QC, transfer to RFT, or check individual QC operations.
DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: staging only';
 END IF;
 IF md5(pg_get_functiondef('pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure))<>'07637113083a3564d51110c9ec368e97'
 OR md5(pg_get_functiondef('pdc_codex_intake_private.finish_tune_checkout(uuid)'::regprocedure))<>'db5ea82aab70196a91693be0c7c1aa32'
 OR md5(pg_get_functiondef('pdc_codex_intake_private.vehicle_tune_checkout(uuid)'::regprocedure))<>'1e2b5ae6f9d3e944c1327e7b9913617c'
 OR md5(pg_get_functiondef('public.pdc_enforce_qc_then_rft()'::regprocedure))<>'64a528b4f3fb31932e4353ee82ab5d9d'
 OR md5(pg_get_functiondef('public.pdc_vehicle_first_milestones()'::regprocedure))<>'c89b36bd439118c11975cc59320673a8' THEN
  RAISE EXCEPTION 'Checkout definitions changed since review';
 END IF;
END $guard$;

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
END $function$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.finish_tune_checkout(vid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r pdc_codex_intake_private.tune_checkout_receipts%rowtype;
BEGIN
 SELECT * INTO STRICT r FROM pdc_codex_intake_private.tune_checkout_receipts
 WHERE vehicle_id=vid AND transaction_id=txid_current() ORDER BY recorded_at DESC LIMIT 1;
 -- The receipt binds the exact vehicle to a successful, authenticated service apply.
 -- Completion is recorded from Tune, never attributed to a technician or QC inspector.
 -- QC checklist completion is an inspector action, not imported workshop completion.
 UPDATE public.vehicle_work_items SET completed=true,completed_at=r.recorded_at,completed_by=r.actor_id,
  notes=concat_ws(E'\n',nullif(notes,''),'Completed by Tune Sub Status 99; receipt '||r.receipt_id),updated_at=clock_timestamp()
 WHERE vehicle_id=vid AND required AND NOT completed AND lower(work_key) NOT IN('qc','qc_signoff');
 -- Preserve planned and actual dates: the export states completion, not actual labour time.
 UPDATE public.workshop_bookings SET status='completed',version=version+1,updated_by=r.actor_id,updated_at=clock_timestamp()
 WHERE vehicle_id=vid AND deleted_at IS NULL AND status IN('queued','planned','started','stoppage');
 UPDATE public.pdc_sublet_booking_instances SET status='returned',returned_at=r.recorded_at,returned_by=r.actor_id,
  source_evidence=coalesce(source_evidence,'{}')||jsonb_build_object('completion_source','Tune Sub Status 99','checkout_receipt',r.receipt_id,'return_time_is_import_recording',true),
  version=version+1,updated_by=r.actor_id,updated_at=clock_timestamp()
 WHERE vehicle_id=vid AND status='active';
 UPDATE pdc_parts_private.jobs SET closed_at=r.recorded_at WHERE vehicle_id=vid AND closed_at IS NULL;
 UPDATE public.vehicles SET workshop_status='completed',active_workshop_booking_id=NULL,workshop_status_updated_at=r.recorded_at,
  workshop_status_updated_by=r.actor_id,version=version+1,
  source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_work_completed_receipt_id',r.receipt_id)
 WHERE id=vid;
 PERFORM public.audit_pdc_event('update','vehicles',vid,vid,NULL,jsonb_build_object('workshop_status','completed'),
  jsonb_build_object('authority','Owner approved any R/O Sub Status 99 completes vehicle','checkout_receipt',r.receipt_id,'qc_signoff_created',false,'actual_labour_times_changed',false));
END $function$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.vehicle_tune_checkout(vid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 SELECT jsonb_build_object('confirmed',true,'source','Tune Sub Status 99','snapshot_at',r.snapshot_at,
 'recorded_at',r.recorded_at,'job_cards',r.job_cards,'receipt_id',r.receipt_id)
 FROM pdc_codex_intake_private.tune_checkout_receipts r JOIN public.vehicles v ON v.id=r.vehicle_id
 WHERE r.vehicle_id=vid AND v.source_payload->>'tune_checkout_receipt_id'=r.receipt_id::text
 AND upper(v.current_location) IN ('QC','RFT') AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
$function$;

CREATE OR REPLACE FUNCTION public.pdc_enforce_qc_then_rft()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_issues text[];
  v_authoritative_delivered_rft boolean:=public.pdc_vehicle_has_current_navision_dealer_delivery(new.id);
begin
  if (upper(btrim(coalesce(new.current_location,'')))='RFT'
      or lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft')
     and new.qc_completed_at is null and not v_authoritative_delivered_rft then
    raise exception 'RFT requires prior QC or current Navision dealer delivery' using errcode='22023';
  end if;
  if old.qc_completed_at is null and new.qc_completed_at is not null then
    if upper(btrim(coalesce(new.current_location,'')))='RFT'
       or lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft' then
      raise exception 'QC sign-off and RFT transfer must be separate audited transitions' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'QC gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;
  if ((upper(btrim(coalesce(old.current_location,''))) is distinct from 'RFT'
       and upper(btrim(coalesce(new.current_location,'')))='RFT')
      or (lower(btrim(coalesce(old.lifecycle_state::text,''))) is distinct from 'rft'
       and lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft'))
     and not v_authoritative_delivered_rft then
    if old.qc_completed_at is null then
      raise exception 'QC sign-off must be completed before RFT transfer' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'RFT gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.pdc_vehicle_first_milestones()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_business_date date:=(clock_timestamp() at time zone 'Australia/Perth')::date;
  v_receipt_backed_external_completion boolean:=false;
BEGIN
  IF tg_op='INSERT' THEN
    IF upper(btrim(coalesce(new.current_location,''))) IN ('PMB','PIT','QC','RFT','COMPLETED') THEN new.date_to_pmb:=coalesce(new.date_to_pmb,v_business_date); END IF;
    IF upper(btrim(coalesce(new.current_location,''))) IN ('RFT','COMPLETED') THEN new.date_to_rft:=coalesce(new.date_to_rft,v_business_date); END IF;
    IF lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed' THEN new.delivered_to_dealer_date:=coalesce(new.delivered_to_dealer_date,v_business_date); END IF;
    RETURN new;
  END IF;

  v_receipt_backed_external_completion:=
    old.delivered_to_dealer_date IS NULL
    AND new.delivered_to_dealer_date IS NULL
    AND new.rft_collected_at IS NOT NULL
    AND lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed'
    AND EXISTS(
      SELECT 1 FROM public.pdc_external_completion_authorizations_20260903 a
      WHERE a.vehicle_id=new.id
        AND a.receipt_id::text=coalesce(new.source_payload->>'external_completion_receipt_id','')
        AND a.actor_id=new.updated_by
    );

  new.date_to_pmb:=CASE WHEN upper(coalesce(new.current_location,'')) IN ('QC','RFT') AND old.date_to_pmb IS NULL AND new.date_to_pmb IS NULL AND EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts receipt WHERE receipt.vehicle_id=new.id AND receipt.receipt_id::text=new.source_payload->>'tune_checkout_receipt_id') THEN old.date_to_pmb ELSE coalesce(old.date_to_pmb,new.date_to_pmb,
    CASE WHEN upper(btrim(coalesce(new.current_location,''))) IN ('PMB','PIT','QC','RFT','COMPLETED') THEN v_business_date END) END;
  new.date_to_rft:=coalesce(old.date_to_rft,new.date_to_rft,
    CASE WHEN upper(btrim(coalesce(new.current_location,''))) IN ('RFT','COMPLETED') THEN v_business_date END);
  new.delivered_to_dealer_date:=CASE
    WHEN v_receipt_backed_external_completion THEN NULL
    ELSE coalesce(old.delivered_to_dealer_date,new.delivered_to_dealer_date,
      CASE WHEN lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed' THEN v_business_date END)
  END;
  RETURN new;
END;
$function$;

-- Existing grants are preserved; no new callable RPCs or table permissions.


-- One-time, receipt-bound correction of the four affected staging vehicles.
-- STAGING ONLY. Run in the SAME transaction as the reviewed function migration.
-- These four exact checkout receipts caused an unsigned RFT transfer on 15 September.
-- Original imports, source operations, work completion and all audit history are retained.
SET LOCAL lock_timeout='5s';
DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Wrong environment'; END IF;
END $guard$;
-- The lock serializes operator changes with this correction. The milestone trigger
-- is disabled only inside this atomic transaction to remove its falsely latched date.
LOCK TABLE public.vehicles IN ACCESS EXCLUSIVE MODE;
-- Flush deferred constraint triggers before altering the single milestone trigger.
-- Keep constraints immediate for the rest of this short migration transaction so
-- the canonical vehicle updates cannot leave pending events before re-enabling it.
SET CONSTRAINTS ALL IMMEDIATE;
CREATE TEMP TABLE qc99_repair_expected(stock text PRIMARY KEY,expected_lines integer) ON COMMIT DROP;
INSERT INTO qc99_repair_expected VALUES ('13047384',22),('13070060',23),('IS50969833',29),('IS60271021',13);
CREATE TEMP TABLE qc99_repair_targets ON COMMIT DROP AS
 SELECT v.id,v.stock_number,r.receipt_id,r.recorded_at,r.actor_id,e.expected_lines,to_jsonb(v) vehicle_before,
  original.before_data import_before
 FROM qc99_repair_expected e
 JOIN public.vehicles v ON v.stock_number=e.stock
 JOIN pdc_codex_intake_private.tune_checkout_receipts r ON r.vehicle_id=v.id
  AND r.receipt_id::text=v.source_payload->>'tune_checkout_receipt_id'
  AND r.snapshot_at='2026-09-15T01:02:00Z'::timestamptz
  AND r.source_hash='1d24b1cb9f08010044dcf8c0d9fa8758520277db029baf7ec913a747e70d23dc'
  AND r.recorded_at>='2026-09-15T06:07:16Z'::timestamptz AND r.recorded_at<'2026-09-15T06:07:17Z'::timestamptz
 JOIN public.pdc_pilbara_service_import_batches batch ON batch.batch_id=r.batch_id
  AND batch.batch_kind='apply' AND batch.contract_revision='pmg_stock_v5' AND batch.source_hash=r.source_hash
 JOIN LATERAL (
  SELECT a.before_data FROM public.audit_events a
  WHERE a.vehicle_id=v.id AND a.metadata->>'authority'='Tune Sub Status 99'
    AND a.after_data->>'tune_checkout_receipt_id'=r.receipt_id::text
  ORDER BY a.created_at LIMIT 1
 ) original ON true
 WHERE v.current_location='RFT' AND v.lifecycle_state='rft' AND v.visible_on_board
  AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
  AND v.qc_completed_at IS NULL AND v.rft_confirmed_at IS NULL
  AND v.rft_transport_booked_at IS NULL AND v.rft_collected_at IS NULL
  AND v.dealer_transit_started_at IS NULL AND v.delivered_to_dealer_date IS NULL
  AND v.source_payload->>'tune_checkout_receipt_id'=r.receipt_id::text
  AND v.source_payload->>'tune_work_completed_receipt_id'=r.receipt_id::text
  AND v.rft_transferred_at BETWEEN r.recorded_at AND r.recorded_at+interval '1 second'
  AND v.date_to_rft=(r.recorded_at AT TIME ZONE 'Australia/Perth')::date
  AND original.before_data->>'rft_transferred_at' IS NULL
  AND original.before_data->>'date_to_rft' IS NULL;
DO $preflight$
BEGIN
 IF (SELECT count(*) FROM qc99_repair_targets)<>4 THEN
  RAISE EXCEPTION 'Repair preflight changed: re-review affected vehicles before applying';
 END IF;
 IF EXISTS(SELECT 1 FROM qc99_repair_targets t
   WHERE (SELECT count(*) FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=t.id)<>t.expected_lines
    OR jsonb_array_length(public.pdc_qc_operation_lines_379(t.id))<>t.expected_lines) THEN
  RAISE EXCEPTION 'Source operation counts changed: nothing repaired';
 END IF;
 IF EXISTS(SELECT 1 FROM qc99_repair_targets t JOIN public.pdc_vehicle_lifecycle_history_events_82000 h ON h.vehicle_id=t.id
   WHERE h.transition_kind='RFT') THEN
  RAISE EXCEPTION 'Recorded RFT lifecycle evidence needs separate review';
 END IF;
END $preflight$;

-- Preserve later inspector edits. A completion is reverted only if its entire
-- current state exactly matches the checkout history row that created it.
CREATE TEMP TABLE qc99_repair_lines ON COMMIT DROP AS
 SELECT c.vehicle_id,c.line_identity,to_jsonb(c) current_state,h.before_state restore_state,t.actor_id,t.receipt_id
 FROM qc99_repair_targets t
 JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=t.id
 JOIN LATERAL (
  SELECT hist.* FROM public.pdc_qc_operation_completion_history_379 hist
  WHERE hist.vehicle_id=c.vehicle_id AND hist.line_identity=c.line_identity
   AND hist.reason='Completed by Tune Sub Status 99; receipt '||t.receipt_id
  ORDER BY hist.created_at DESC,hist.history_id DESC LIMIT 1
 ) h ON to_jsonb(c)=h.after_state
 WHERE c.completed;
DO $checks$
DECLARE row record; restored public.pdc_qc_operation_completions_379%rowtype;
BEGIN
 FOR row IN SELECT * FROM qc99_repair_lines LOOP
  UPDATE public.pdc_qc_operation_completions_379 c SET
   completed=coalesce((row.restore_state->>'completed')::boolean,false),
   completed_by=(row.restore_state->>'completed_by')::uuid,
   completed_at=(row.restore_state->>'completed_at')::timestamptz,
   version=c.version+1,updated_at=clock_timestamp()
  WHERE c.vehicle_id=row.vehicle_id AND c.line_identity=row.line_identity AND to_jsonb(c)=row.current_state
  RETURNING c.* INTO restored;
  IF NOT FOUND THEN RAISE EXCEPTION 'QC line changed during repair'; END IF;
  INSERT INTO public.pdc_qc_operation_completion_history_379(history_id,vehicle_id,line_identity,actor_id,before_state,after_state,reason)
  VALUES(gen_random_uuid(),row.vehicle_id,row.line_identity,row.actor_id,row.current_state,to_jsonb(restored),
   'System correction: Tune import completed workshop work, not QC inspection; receipt '||row.receipt_id);
 END LOOP;
END $checks$;

ALTER TABLE public.vehicles DISABLE TRIGGER vehicles_first_milestones;
DO $repair$
DECLARE row record; after_row jsonb;
BEGIN
 FOR row IN SELECT * FROM qc99_repair_targets LOOP
  UPDATE public.vehicles SET current_location='QC',lifecycle_state='active',
   pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,
   rft_transferred_at=NULL,date_to_rft=NULL,
   version=version+1,
   source_payload=coalesce(source_payload,'{}')||jsonb_build_object(
    'tune_qc_routing_correction',jsonb_build_object('checkout_receipt',row.receipt_id,'corrected_at',clock_timestamp(),
     'reason','Tune Sub Status 99 completes work and requires separate QC inspection'))
  WHERE id=row.id;
  SELECT to_jsonb(v) INTO after_row FROM public.vehicles v WHERE id=row.id;
  PERFORM public.audit_pdc_event('update','vehicles',row.id,row.id,row.vehicle_before,after_row,
   jsonb_build_object('authority','System correction requested by owner','migration','tune_checkout_requires_qc',
    'checkout_receipt',row.receipt_id,'operation_lines_preserved',row.expected_lines,
    'qc_checks_reset',(SELECT count(*) FROM qc99_repair_lines l WHERE l.vehicle_id=row.id),
    'qc_signoff_created',false,'prior_audit_evidence_retained',true));
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,reason,moved_by,moved_at)
  VALUES(row.id,'RFT','QC','System correction: Tune Sub Status 99 work complete, awaiting QC inspection; receipt '||row.receipt_id,row.actor_id,clock_timestamp());
 END LOOP;
END $repair$;
ALTER TABLE public.vehicles ENABLE TRIGGER vehicles_first_milestones;

DO $post$
BEGIN
 IF EXISTS(SELECT 1 FROM qc99_repair_targets t JOIN public.vehicles v ON v.id=t.id
  WHERE v.current_location<>'QC' OR v.lifecycle_state<>'active' OR v.qc_completed_at IS NOT NULL
   OR v.rft_transferred_at IS NOT NULL OR v.date_to_rft IS NOT NULL
   OR v.date_to_pmb::text IS DISTINCT FROM t.vehicle_before->>'date_to_pmb'
   OR public.pdc_lifecycle_history_payload_82000(v.id)->>'first_became_rft_at' IS NOT NULL
   OR cardinality(public.pdc_qc_gate_issues(v.id))<>0
   OR jsonb_array_length(public.pdc_qc_operation_lines_379(v.id))<>t.expected_lines) THEN
  RAISE EXCEPTION 'QC repair postcondition failed; transaction must roll back';
 END IF;
 IF EXISTS(SELECT 1 FROM qc99_repair_targets t JOIN public.pdc_vehicle_lifecycle_history_events_82000 h ON h.vehicle_id=t.id
  WHERE h.transition_kind='RFT') THEN RAISE EXCEPTION 'False RFT lifecycle evidence remains'; END IF;
END $post$;



