DO $guard$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
IF md5(pg_get_functiondef('pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure))<>'0de85ac396771abefff4f746c05e4488' THEN RAISE EXCEPTION 'Definition changed: pdc_codex_intake_private.capture_service_status'; END IF;
IF md5(pg_get_functiondef('public.workshop_enforce_booking_lifecycle()'::regprocedure))<>'6f926369fea53137a352804749b7986a' THEN RAISE EXCEPTION 'Definition changed: public.workshop_enforce_booking_lifecycle'; END IF;
IF md5(pg_get_functiondef('public.workshop_require_planner_booking_mutation()'::regprocedure))<>'8a56a9fc9223b5c548c8884f1b8c99d1' THEN RAISE EXCEPTION 'Definition changed: public.workshop_require_planner_booking_mutation'; END IF;
IF md5(pg_get_functiondef('public.pdc_vehicle_first_milestones()'::regprocedure))<>'ddf2ea4a043f9871ec49265bf63adf19' THEN RAISE EXCEPTION 'Definition changed: public.pdc_vehicle_first_milestones'; END IF;
END $guard$;

CREATE TABLE pdc_codex_intake_private.tune_pmb_complete_receipts (
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 batch_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_import_batches(batch_id),
 snapshot_at timestamptz NOT NULL, source_hash text NOT NULL, job_cards jsonb NOT NULL,
 prior_location text, actor_id uuid NOT NULL REFERENCES auth.users(id),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 transaction_id bigint NOT NULL DEFAULT txid_current(),
 UNIQUE(vehicle_id)
);
ALTER TABLE pdc_codex_intake_private.tune_pmb_complete_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_codex_intake_private.tune_pmb_complete_receipts FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_codex_intake_private.apply_service_pmb_complete(apply_id uuid)
RETURNS void LANGUAGE plpgsql SET search_path TO pg_catalog,public AS $fn$
DECLARE b public.pdc_pilbara_service_import_batches%rowtype; v public.vehicles%rowtype;
 receipt uuid; cards jsonb; latest timestamptz; problem text; recorded timestamptz;
BEGIN
 SELECT * INTO STRICT b FROM public.pdc_pilbara_service_import_batches
 WHERE batch_id=apply_id AND batch_kind='apply' AND contract_revision='pmg_stock_v5';
 FOR v IN SELECT x.* FROM public.vehicles x WHERE x.id IN (
  SELECT vehicle_id FROM pdc_codex_intake_private.service_job_status WHERE batch_id=apply_id AND sub_status='80'
 ) ORDER BY x.id FOR UPDATE LOOP
  -- Never replay completion over inspection, rework, deleted or terminal history.
  IF v.deleted_at IS NOT NULL OR v.board_purged_at IS NOT NULL OR v.lifecycle_state::text<>'active'
   OR upper(btrim(coalesce(v.current_location,''))) IN('QC','RFT','COMPLETED')
   OR v.qc_completed_at IS NOT NULL OR v.rft_transferred_at IS NOT NULL
   OR EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id=v.id)
   OR EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND sub_status='99')
   OR EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_pmb_complete_receipts WHERE vehicle_id=v.id)
  THEN CONTINUE; END IF;
  SELECT jsonb_agg(jsonb_build_object('company',company,'division',division,'ro',ro_number,'sub_status',sub_status,'snapshot_at',snapshot_at)
    ORDER BY company,division,ro_number),max(snapshot_at) INTO cards,latest
  FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND batch_id=apply_id AND sub_status='80';
  problem:=NULL;
  IF EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_status_reviews WHERE batch_id=apply_id AND stock_number=v.stock_number)
   THEN problem:='job_status_validation_requires_review';
  ELSIF EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND snapshot_at>latest AND sub_status IS DISTINCT FROM '80')
   THEN problem:='newer_linked_job_requires_review';
  ELSIF EXISTS(SELECT 1 FROM public.pdc_qc_vehicle_rejection_receipts_767 WHERE vehicle_id=v.id)
    OR EXISTS(SELECT 1 FROM public.pdc_qc_operation_rejections_381 WHERE vehicle_id=v.id AND active)
   THEN problem:='qc_rework_requires_review';
  ELSIF v.pmb_stoppage_started_at IS NOT NULL
   THEN problem:='active_stoppage_requires_review';
  ELSIF upper(btrim(coalesce(v.current_location,'')))='SUBLET'
   THEN problem:='sublet_return_requires_review';
  ELSIF EXISTS(SELECT 1 FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id=v.id AND status='pending')
   THEN problem:='pending_operation_changes_require_review';
  END IF;
  IF problem IS NOT NULL THEN
   INSERT INTO pdc_codex_intake_private.service_status_reviews(batch_id,company,division,ro_number,stock_number,reason,evidence)
   SELECT apply_id,company,division,ro_number,stock_number,problem,
    jsonb_build_object('vehicle_id',v.id,'sub_status','80','action','PMB work complete; QC transfer held')
   FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id=v.id AND batch_id=apply_id AND sub_status='80'
   ON CONFLICT DO NOTHING;
   CONTINUE;
  END IF;
  INSERT INTO pdc_codex_intake_private.tune_pmb_complete_receipts(vehicle_id,batch_id,snapshot_at,source_hash,job_cards,prior_location,actor_id)
  VALUES(v.id,apply_id,latest,b.source_hash,cards,v.current_location,b.created_by)
  RETURNING receipt_id,recorded_at INTO receipt,recorded;
  -- This is PMB workshop completion, not parts readiness, Sublet return or QC inspection.
  UPDATE public.vehicle_work_items SET completed=true,completed_at=recorded,completed_by=b.created_by,
   notes=concat_ws(E'\n',nullif(notes,''),'PMB work complete from Tune Sub Status 80; receipt '||receipt),updated_at=clock_timestamp()
  WHERE vehicle_id=v.id AND required AND NOT completed
   AND lower(work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre');
  UPDATE public.workshop_bookings wb SET status='completed',version=wb.version+1,updated_by=b.created_by,updated_at=clock_timestamp()
  FROM public.workshop_stages s WHERE wb.stage_id=s.id AND wb.vehicle_id=v.id AND wb.deleted_at IS NULL
   AND wb.status IN('queued','planned','started','stoppage')
   AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE');
  UPDATE public.pdc_new_vehicle_reviews SET status='closed',closed_at=recorded,closure_reason='PMB work complete: Tune Sub Status 80; awaiting QC'
  WHERE vehicle_id=v.id AND status='pending';
  UPDATE public.vehicles SET current_location='QC',pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,
   visible_on_board=true,workshop_status='completed',active_workshop_booking_id=NULL,
   workshop_status_updated_at=recorded,workshop_status_updated_by=b.created_by,
   location_override=NULL,location_override_reason=NULL,location_override_at=NULL,location_override_by=NULL,
   version=version+1,updated_by=b.created_by,
   source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_pmb_complete_receipt_id',receipt,
    'tune_pmb_complete_source_snapshot',latest,'tune_pmb_work_status','PMB work complete - awaiting QC')
  WHERE id=v.id;
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
   from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by,moved_at)
  VALUES(v.id,v.current_location,'QC',v.pmb_stage,NULL,v.pmb_bay_stage,NULL,v.pmb_bay_number,NULL,
   'Tune Sub Status 80: PMB work complete; awaiting QC inspection. Receipt '||receipt,b.created_by,recorded);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),
   jsonb_build_object('current_location','QC','workshop_status','completed','tune_pmb_complete_receipt_id',receipt),
   jsonb_build_object('authority','Owner: Tune Sub Status 80 means PMB work complete','apply_batch_id',apply_id,
    'qc_signoff_created',false,'parts_changed',false,'sublet_return_created',false,'actual_labour_times_changed',false));
 END LOOP;
END $fn$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.apply_service_pmb_complete(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.workshop_enforce_booking_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_allowed boolean:=false;
begin

 if tg_op='UPDATE' and new.status='completed' and old.status in ('queued','planned','started','stoppage')
  and (to_jsonb(new)-array['status','version','updated_by','updated_at']) is not distinct from (to_jsonb(old)-array['status','version','updated_by','updated_at'])
  and (exists(select 1 from pdc_codex_intake_private.tune_pmb_complete_receipts r
      join public.workshop_stages s on s.id=new.stage_id
      where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by
      and s.code in('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE')) or exists(select 1 from pdc_codex_intake_private.tune_checkout_receipts r where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by))
 then return new; end if;
  if tg_op='INSERT' or new.status=old.status then return new; end if;
  v_allowed :=
    (old.status in ('queued','planned') and new.status='started') or
    (old.status='started' and new.status='stoppage') or
    (old.status='stoppage' and new.status='started') or
    (old.status in ('started','stoppage') and new.status='completed') or
    (old.status in ('queued','planned','stoppage') and new.status='deleted') or
    (old.status='queued' and new.status='stoppage'
      and old.actual_start_at is not null
      and old.returned_to_queue_at is not null
      and nullif(trim(coalesce(old.stoppage_reason,'')),'') is not null
      and new.bay_id is null);
  if old.status='completed' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'reopen_completed');
  elsif old.status='deleted' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'restore');
  elsif old.status in ('started','stoppage') and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'return_to_queue');
  end if;
  if not v_allowed then
    raise exception 'Invalid Workshop Planner lifecycle transition: % -> %',old.status,new.status using errcode='22023';
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.workshop_require_planner_booking_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_stage_id uuid; v_stage_code text; v_planner_enabled boolean;
begin

 if tg_op='UPDATE' and new.status='completed' and old.status in ('queued','planned','started','stoppage')
  and (to_jsonb(new)-array['status','version','updated_by','updated_at']) is not distinct from (to_jsonb(old)-array['status','version','updated_by','updated_at'])
  and (exists(select 1 from pdc_codex_intake_private.tune_pmb_complete_receipts r
      join public.workshop_stages s on s.id=new.stage_id
      where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by
      and s.code in('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE')) or exists(select 1 from pdc_codex_intake_private.tune_checkout_receipts r where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by))
 then return new; end if;
 if auth.uid() is not null then
  if tg_op='UPDATE' and pg_trigger_depth()>1
     and (to_jsonb(new)-array['eta_at_booking','eta_risk_status','eta_risk_detected_at','version','updated_by'])
         is not distinct from
         (to_jsonb(old)-array['eta_at_booking','eta_risk_status','eta_risk_detected_at','version','updated_by']) then
   return new;
  end if;
  perform public.workshop_require_planner_operator();
 end if;
 v_stage_id:=case when tg_op='DELETE' then old.stage_id else new.stage_id end;
 select s.code,coalesce(s.planner_enabled,false) into v_stage_code,v_planner_enabled
 from public.workshop_stages s where s.id=v_stage_id;
 if coalesce(v_planner_enabled,false)=false then
  if tg_op='UPDATE' and new.status='completed' and old.status is distinct from 'completed'
     and (to_jsonb(new)-array['status','actual_start_at','actual_end_at','actual_duration_minutes','stoppage_started_at','stoppage_accumulated_minutes','updated_by','updated_at','version'])
         is not distinct from
         (to_jsonb(old)-array['status','actual_start_at','actual_end_at','actual_duration_minutes','stoppage_started_at','stoppage_accumulated_minutes','updated_by','updated_at','version']) then
   return new;
  end if;
  raise exception 'planner_disabled stage=%',coalesce(v_stage_code,'unknown') using errcode='22023';
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $function$;

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

  new.date_to_pmb:=CASE WHEN upper(coalesce(new.current_location,'')) IN ('QC','RFT') AND old.date_to_pmb IS NULL AND new.date_to_pmb IS NULL AND (EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts receipt WHERE receipt.vehicle_id=new.id AND receipt.receipt_id::text=new.source_payload->>'tune_checkout_receipt_id') OR EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_pmb_complete_receipts receipt WHERE receipt.vehicle_id=new.id AND receipt.receipt_id::text=new.source_payload->>'tune_pmb_complete_receipt_id')) THEN old.date_to_pmb ELSE coalesce(old.date_to_pmb,new.date_to_pmb,
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
 PERFORM pdc_codex_intake_private.apply_service_pmb_complete(apply_id);
END $function$;

