-- Owner-edited PMB Board Workflow (2).drawio + explicit any-job-99 confirmation, 15 September 2026.
DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
IF md5(replace(pg_get_functiondef('public.workshop_enforce_booking_lifecycle()'::regprocedure),E'\r\n',E'\n'))<>'85ed6e1824379e1ac5499ebf818dbb5f' THEN RAISE EXCEPTION 'Concurrent change: public.workshop_enforce_booking_lifecycle()'; END IF;
IF md5(replace(pg_get_functiondef('public.workshop_require_planner_booking_mutation()'::regprocedure),E'\r\n',E'\n'))<>'8be445d1c6ab934cb7b5f38ec360d560' THEN RAISE EXCEPTION 'Concurrent change: public.workshop_require_planner_booking_mutation()'; END IF;
IF md5(replace(pg_get_functiondef('pdc_codex_intake_private.capture_service_status(uuid,uuid)'::regprocedure),E'\r\n',E'\n'))<>'4429e471cfcc355d7f0d1589cc14ca07' THEN RAISE EXCEPTION 'Concurrent change: pdc_codex_intake_private.capture_service_status(uuid,uuid)'; END IF;
IF md5(replace(pg_get_functiondef('pdc_codex_intake_private.capture_service_locations(uuid,uuid)'::regprocedure),E'\r\n',E'\n'))<>'d00fc9f41dcf48892dff5629498cc2a9' THEN RAISE EXCEPTION 'Concurrent change: pdc_codex_intake_private.capture_service_locations(uuid,uuid)'; END IF;
IF md5(replace(pg_get_functiondef('public.pdc_apply_tune_vehicle_fields_v5(uuid,uuid,uuid)'::regprocedure),E'\r\n',E'\n'))<>'63e4243b470b6db9ecfe483642466246' THEN RAISE EXCEPTION 'Concurrent change: public.pdc_apply_tune_vehicle_fields_v5(uuid,uuid,uuid)'; END IF;
IF md5(replace(pg_get_functiondef((SELECT oid FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='pdc_pilbara_service_apply_v1')),E'\r\n',E'\n'))<>'bad3fac79bcf49dbf0adfb67863c74a8' THEN RAISE EXCEPTION 'Concurrent change: public.pdc_pilbara_service_apply_v1(jsonb)'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.finish_tune_checkout(vid uuid)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE r pdc_codex_intake_private.tune_checkout_receipts%rowtype; l jsonb; before_row jsonb; after_row jsonb;
BEGIN
 SELECT * INTO STRICT r FROM pdc_codex_intake_private.tune_checkout_receipts
 WHERE vehicle_id=vid AND transaction_id=txid_current() ORDER BY recorded_at DESC LIMIT 1;
 -- The receipt binds the exact vehicle to a successful, authenticated service apply.
 -- Completion is recorded from Tune, never attributed to a technician or QC inspector.
 FOR l IN SELECT value FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vid)) WHERE (value->>'active')::boolean LOOP
  SELECT to_jsonb(c) INTO before_row FROM public.pdc_qc_operation_completions_379 c WHERE vehicle_id=vid AND line_identity=l->>'line_identity';
  IF coalesce((before_row->>'completed')::boolean,false) THEN CONTINUE; END IF;
  INSERT INTO public.pdc_qc_operation_completions_379(vehicle_id,line_identity,source_kind,source_line_id,stage_code,completed,completed_by,completed_at,version)
  VALUES(vid,l->>'line_identity',l->>'source_kind',(l->>'source_line_id')::uuid,l->>'stage_code',true,r.actor_id,r.recorded_at,1)
  ON CONFLICT(vehicle_id,line_identity) DO UPDATE SET completed=true,completed_by=excluded.completed_by,completed_at=excluded.completed_at,version=pdc_qc_operation_completions_379.version+1,updated_at=clock_timestamp();
  SELECT to_jsonb(c) INTO after_row FROM public.pdc_qc_operation_completions_379 c WHERE vehicle_id=vid AND line_identity=l->>'line_identity';
  INSERT INTO public.pdc_qc_operation_completion_history_379(history_id,vehicle_id,line_identity,actor_id,before_state,after_state,reason)
  VALUES(gen_random_uuid(),vid,l->>'line_identity',r.actor_id,before_row,after_row,'Completed by Tune Sub Status 99; receipt '||r.receipt_id);
 END LOOP;
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
END $$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.finish_tune_checkout(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.apply_service_arrival(apply_id uuid)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE v public.vehicles%rowtype; k record; b public.pdc_pilbara_service_import_batches%rowtype;
BEGIN
 SELECT * INTO STRICT b FROM public.pdc_pilbara_service_import_batches WHERE batch_id=apply_id AND batch_kind='apply';
 FOR v IN SELECT x.* FROM public.vehicles x WHERE x.id IN(SELECT vehicle_id FROM pdc_codex_intake_private.service_location_fields WHERE batch_id=apply_id AND vehicle_key_number ~ '^[0-9]+$' AND CASE WHEN vehicle_key_number ~ '^[0-9]+$' THEN vehicle_key_number::numeric>0 ELSE false END) FOR UPDATE LOOP
  IF v.deleted_at IS NOT NULL OR v.board_purged_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.qc_completed_at IS NOT NULL OR v.rft_transferred_at IS NOT NULL THEN CONTINUE; END IF;
  SELECT count(DISTINCT vehicle_key_number) n,min(vehicle_key_number) key INTO k
   FROM pdc_codex_intake_private.service_location_fields WHERE vehicle_id=v.id AND vehicle_key_number ~ '^[0-9]+$' AND CASE WHEN vehicle_key_number ~ '^[0-9]+$' THEN vehicle_key_number::numeric>0 ELSE false END;
  IF k.n<>1 THEN CONTINUE; END IF;
  -- Repeated snapshots must not drag a vehicle out of a bay, QC, PIT or Sublet.
  IF upper(btrim(coalesce(v.current_location,''))) NOT IN('','YH','YARD HOLD','IT','IN TRANSIT','OTHER','NON NAVISION VEHICLES') THEN CONTINUE; END IF;
  UPDATE public.vehicles SET current_location='PMB',location_override='PMB',location_override_reason='Tune service key confirms PMB arrival',
   location_override_at=b.created_at,location_override_by=b.created_by,key_number=k.key,
   date_to_pmb=coalesce(date_to_pmb,(b.created_at AT TIME ZONE 'Australia/Perth')::date),
   source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_key_arrival_batch_id',apply_id,'tune_key_arrival_number',k.key),
   version=version+1,updated_by=b.created_by WHERE id=v.id;
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),jsonb_build_object('current_location','PMB','key_number',k.key),jsonb_build_object('authority','Owner service key arrival rule','apply_batch_id',apply_id));
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.apply_service_arrival(uuid) FROM PUBLIC,anon,authenticated,service_role;


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
  and exists(select 1 from pdc_codex_intake_private.tune_checkout_receipts r where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by)
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
end $function$
;

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
  and exists(select 1 from pdc_codex_intake_private.tune_checkout_receipts r where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by)
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
end $function$
;

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
 FROM public.pdc_pilbara_service_import_rows WHERE batch_id=preview_id AND raw_row ? 'Sub Status' AND raw_row ? 'Status'
 GROUP BY raw_row->>'Company',raw_row->>'Division',repair_order_number
 LOOP
  problem:=NULL;target:=NULL;
  IF r.company='' OR r.division='' OR nullif(r.ro,'') IS NULL OR nullif(r.stock,'') IS NULL OR r.stocks<>1
   OR r.statuses<>1 OR r.substatuses<>1 OR r.snapshots<>1 OR r.snapshot_text IS NULL OR NOT r.valid_rows
   OR coalesce(r.status,'') !~ '^[0-9]{1,2}$' OR (r.sub_status IS NOT NULL AND r.sub_status !~ '^[0-9]{1,2}$')
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
    ELSIF FOUND AND old.snapshot_at=r.snapshot_text::timestamptz AND (old.status IS DISTINCT FROM r.status OR old.sub_status IS DISTINCT FROM r.sub_status)
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
  ON CONFLICT(company,division,ro_number) DO UPDATE SET status=excluded.status,sub_status=excluded.sub_status,
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

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.capture_service_locations(preview_id uuid, apply_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r record; target uuid; matches integer; old pdc_codex_intake_private.service_location_fields%rowtype;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_batches WHERE batch_id=apply_id AND batch_kind='apply' AND source_hash=(SELECT source_hash FROM public.pdc_pilbara_service_import_batches WHERE batch_id=preview_id AND batch_kind='preview')) THEN RAISE EXCEPTION 'applied_batch_required'; END IF;
 FOR r IN
  SELECT raw_row->>'Company' company,raw_row->>'Division' division,repair_order_number ro,
   min(stock_number) stock,count(DISTINCT stock_number) stock_count,
   bool_or((raw_row ? 'Key Number' AND raw_row ? 'Key Tag Number' AND raw_row->>'Key Number' IS DISTINCT FROM raw_row->>'Key Tag Number') OR (raw_row ? 'Key Number' AND raw_row ? 'Block Number' AND raw_row->>'Key Number' IS DISTINCT FROM raw_row->>'Block Number') OR (raw_row ? 'Tag #' AND raw_row ? 'Parts Location' AND raw_row->>'Tag #' IS DISTINCT FROM raw_row->>'Parts Location') OR (raw_row ? 'Block Number' AND raw_row ? 'Key Tag Number' AND raw_row->>'Block Number' IS DISTINCT FROM raw_row->>'Key Tag Number')) alias_conflict,
   count(DISTINCT coalesce(coalesce(raw_row->>'Parts Location',raw_row->>'Tag #'),'')) tags,count(DISTINCT coalesce(coalesce(raw_row->>'Key Number',raw_row->>'Key Tag Number',raw_row->>'Block Number'),'')) blocks,
   min(nullif(btrim(coalesce(raw_row->>'Parts Location',raw_row->>'Tag #')),'')) tag,min(nullif(btrim(coalesce(raw_row->>'Key Number',raw_row->>'Key Tag Number',raw_row->>'Block Number')),'')) block,
   min((raw_row->>'source_snapshot_at')::timestamptz) snapshot,
   jsonb_agg(jsonb_build_object('stock',stock_number,'tag',coalesce(raw_row->'Parts Location',raw_row->'Tag #'),'block',coalesce(raw_row->'Key Number',raw_row->'Key Tag Number',raw_row->'Block Number'))) evidence
  FROM public.pdc_pilbara_service_import_rows
  WHERE batch_id=preview_id AND (raw_row ? 'Tag #' OR raw_row ? 'Parts Location') AND (raw_row ? 'Key Number' OR raw_row ? 'Block Number' OR raw_row ? 'Key Tag Number')
  GROUP BY raw_row->>'Company',raw_row->>'Division',repair_order_number
 LOOP
  SELECT count(DISTINCT o.vehicle_id),min(o.vehicle_id::text)::uuid INTO matches,target
  FROM public.pdc_pilbara_service_operations o JOIN public.vehicles v ON v.id=o.vehicle_id
  JOIN public.pdc_pilbara_service_import_rows evidence ON evidence.evidence_id=o.raw_evidence_id
  WHERE o.repair_order_number=r.ro AND o.stock_number=r.stock
   AND (pdc_parts_private.service_scope(evidence.raw_row,o.stock_number,o.repair_order_number)->>'company')=r.company
   AND (pdc_parts_private.service_scope(evidence.raw_row,o.stock_number,o.repair_order_number)->>'division')=r.division
   AND v.stock_number_normalized=public.normalize_vehicle_stock_number(r.stock)
   AND v.deleted_at IS NULL AND v.lifecycle_state::text='active';
  IF r.alias_conflict OR matches<>1 OR r.stock_count<>1 OR r.tags>1 OR r.blocks>1 OR r.snapshot IS NULL
   OR length(coalesce(r.tag,''))>80 OR length(coalesce(r.block,''))>40
   OR lower(coalesce(r.tag,''))='all' OR lower(coalesce(r.block,''))='all' THEN
   INSERT INTO pdc_codex_intake_private.service_location_reviews VALUES(apply_id,coalesce(r.company,''),coalesce(r.division,''),r.ro,'unmatched_or_conflicting_location_fields',r.evidence,clock_timestamp()) ON CONFLICT DO NOTHING;
   CONTINUE;
  END IF;
  SELECT * INTO old FROM pdc_codex_intake_private.service_location_fields WHERE company=r.company AND division=r.division AND ro_number=r.ro FOR UPDATE;
  IF FOUND AND (old.vehicle_id<>target OR old.snapshot_at>r.snapshot OR (old.snapshot_at=r.snapshot AND (old.parts_location IS DISTINCT FROM r.tag OR old.vehicle_key_number IS DISTINCT FROM r.block))) THEN
   INSERT INTO pdc_codex_intake_private.service_location_reviews VALUES(apply_id,r.company,r.division,r.ro,'older_snapshot_or_conflicting_identity',r.evidence,clock_timestamp()) ON CONFLICT DO NOTHING; CONTINUE;
  END IF;
  INSERT INTO pdc_codex_intake_private.service_location_fields(company,division,ro_number,vehicle_id,stock_number,parts_location,vehicle_key_number,snapshot_at,batch_id)
  VALUES(r.company,r.division,r.ro,target,r.stock,r.tag,r.block,r.snapshot,apply_id)
  ON CONFLICT(company,division,ro_number) DO UPDATE SET parts_location=excluded.parts_location,vehicle_key_number=excluded.vehicle_key_number,snapshot_at=excluded.snapshot_at,imported_at=clock_timestamp(),batch_id=excluded.batch_id;
 END LOOP;
END $function$
;

CREATE OR REPLACE FUNCTION public.pdc_apply_tune_vehicle_fields_v5(p_vehicle_id uuid, p_batch_id uuid, p_preview_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.pdc_pilbara_service_import_batches%rowtype; v public.vehicles%rowtype; fields jsonb; e public.pdc_tune_intake_evidence_v5%rowtype;
 details jsonb; p public.vehicle_parts_updates%rowtype; desired text; n public.navision_backend_records%rowtype; target_location text;
BEGIN
 SELECT * INTO STRICT b FROM public.pdc_pilbara_service_import_batches WHERE batch_id=p_batch_id AND batch_kind='apply' AND contract_revision='pmg_stock_v5';
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 SELECT jsonb_agg(r.normalized_payload->'tune_source_fields' ORDER BY r.source_order) INTO fields FROM public.pdc_pilbara_service_import_rows r
 WHERE r.batch_id=p_preview_batch_id
 AND r.stock_number=v.stock_number AND r.decision IN('insert','unchanged');
 -- Apply batches on this route bind their preview in request data, not a separate FK.
 IF fields IS NULL THEN RAISE EXCEPTION 'missing_tune_source_fields'; END IF;
 desired:=public.pdc_tune_parts_status_v5(fields);
 INSERT INTO public.pdc_tune_intake_evidence_v5(vehicle_id,batch_id,source_hash,workbook_sha256,customer_name,vehicle_description,tune_vin,parts_status,purchase_order_numbers,source_fields,created_by)
 SELECT v.id,b.batch_id,b.source_hash,b.source_link->>'workbook_sha256',min(nullif(f->>'customer_name','')),min(nullif(f->>'vehicle_description','')),min(nullif(f->>'vin','')),desired,
 coalesce(jsonb_agg(DISTINCT f->>'purchase_order_number') FILTER(WHERE nullif(f->>'purchase_order_number','') IS NOT NULL),'[]'),fields,b.created_by
 FROM jsonb_array_elements(fields) f RETURNING * INTO e;
 INSERT INTO public.pdc_tune_intake_current_v5(vehicle_id,evidence_id) VALUES(v.id,e.evidence_id) ON CONFLICT(vehicle_id) DO UPDATE SET evidence_id=excluded.evidence_id;
 details:=public.pdc_tune_vehicle_details_v5(v.id);
 UPDATE public.vehicles SET customer_name=details->>'customer_name',vehicle_description=details->>'vehicle_description',
 source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_details_evidence_id',e.evidence_id,'details_source',details->>'details_source'),
 version=version+1,updated_by=b.created_by,updated_at=clock_timestamp() WHERE id=v.id;

 -- Pending Tune intake follows its unique current Navision location.
 -- Owner rule: Delivered at Body Builder enters PMB; At Dealer uses delivery closure, never PMB.
 IF NOT v.visible_on_board AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
  AND v.qc_completed_at IS NULL AND v.rft_transferred_at IS NULL AND v.date_to_pmb IS NULL
  AND upper(btrim(coalesce(v.current_location,''))) IN('YARD HOLD','YH','IT','OTHER')
  AND NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status<>'pending')
  AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings w WHERE w.vehicle_id=v.id AND w.deleted_at IS NULL)
  AND NOT EXISTS(SELECT 1 FROM public.vehicle_movements m WHERE m.vehicle_id=v.id)
  AND details->>'details_source'='microsoft_navision' THEN
  SELECT * INTO n FROM public.navision_backend_records
   WHERE id=(details->>'details_backend_record_id')::uuid AND canonical_vehicle_id=v.id
    AND is_current AND record_status='current';
  IF FOUND THEN
   target_location:=CASE WHEN public.navision_exact_lifecycle_status(n.normalized_data)='deliveredatdealer'
    THEN 'At Dealer' ELSE public.navision_operational_location(n.normalized_data) END;
   IF target_location IN('PMB','YH','IT','Other','At Dealer') THEN
    UPDATE public.vehicles SET current_location=target_location,
     eta_to_kewdale=coalesce(public.navision_kewdale_eta(n.normalized_data),eta_to_kewdale),
     source_payload=coalesce(source_payload,'{}')||jsonb_build_object(
      'tune_location_authority','navision_pending_intake_exact_sublocation',
      'tune_location_backend_record_id',n.id,'tune_location_backend_version',n.version,
      'tune_location_navision_code',n.normalized_data->>'navisionLocationStatus',
      'tune_location_navision_description',n.normalized_data->>'navisionSubLocationDescription'),
     version=version+1,updated_by=b.created_by,updated_at=clock_timestamp()
    WHERE id=v.id;
    IF target_location='At Dealer' THEN
     INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,closed_at,closure_reason)
     VALUES(v.id,'closed','tune_pmg',clock_timestamp(),'Navision: Delivered - At Dealer')
     ON CONFLICT(vehicle_id) DO UPDATE SET status='closed',closed_at=clock_timestamp(),closure_reason=excluded.closure_reason
      WHERE public.pdc_new_vehicle_reviews.status='pending';
    END IF;
   END IF;
  END IF;
 END IF;
 IF details->>'details_source'<>'microsoft_navision' AND NOT v.visible_on_board
  AND v.lifecycle_state::text='active' AND v.deleted_at IS NULL AND v.date_to_pmb IS NULL
  AND upper(btrim(v.current_location)) IN('YARD HOLD','YH')
  AND NOT EXISTS(SELECT 1 FROM public.vehicle_movements WHERE vehicle_id=v.id)
  AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v.id AND deleted_at IS NULL)
 THEN
  UPDATE public.vehicles SET current_location='Other',eta_to_kewdale=NULL,
   source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_incoming_group','nonnavision'),
   version=version+1,updated_by=b.created_by WHERE id=v.id;
 END IF;
 -- Numeric parts evidence never signs off receipt or overwrites staff Parts state.
 PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),jsonb_build_object('details',details,'parts_status',desired),jsonb_build_object('contract','tune_daily_fields_v5','evidence_id',e.evidence_id,'source_batch_id',p_batch_id));
 RETURN jsonb_build_object('vehicle_id',v.id,'evidence_id',e.evidence_id,'details_source',details->>'details_source','parts_status',desired);
END $function$
;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1(p_preview_batch_id uuid, p_source_hash text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  v_codex_scoped boolean := public.pdc_email_ai_runtime_authorized_v1() IS NOT TRUE;
  v_candidate jsonb; v_stock text; v_tune boolean; v_code text; v_backend uuid;
  v_actor uuid:=pdc_codex_intake_private.import_actor();v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_actor_label text:=v_actor_email||':viewer:'||coalesce(v_actor::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;
  v_preview public.pdc_pilbara_service_import_batches%rowtype;v_prior public.pdc_pilbara_service_import_batches%rowtype;v_apply_batch uuid:=gen_random_uuid();
  v_row public.pdc_pilbara_service_import_rows%rowtype;v_op public.pdc_pilbara_service_operations%rowtype;v_vehicle_id uuid;v_first_ro text;v_operation_id uuid;v_identity_hash text;v_response jsonb;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;
  IF v_codex_scoped AND pdc_codex_intake_private.authorized('apply',NULL,p_source_hash,p_idempotency_key,p_preview_batch_id) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
  IF v_codex_scoped THEN v_actor_label:=v_actor_email||':codex_workbook_importer:'||v_actor::text; END IF;
  IF pdc_codex_intake_private.management_connection() IS TRUE THEN v_actor_label:='codex_supabase_management:postgres:'||v_actor::text; END IF;
  IF p_preview_batch_id IS NULL OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_apply_request');END IF;
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_import_batches b WHERE b.batch_id=p_preview_batch_id AND b.importer_version='pilbara_service_open_jobcards_v1' AND b.batch_kind='preview' FOR SHARE;
  IF NOT FOUND OR v_preview.source_hash<>v_source_hash OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'code','apply_not_eligible');END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  v_tune:=v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4','pmg_stock_v5');
  v_request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc_pilbara_service_apply_v1_dynamic_20260910','preview_batch_id',p_preview_batch_id,'source_hash',v_source_hash)::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:apply:'||v_source_hash,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='apply' AND b.contract_revision=v_preview.contract_revision;
  IF FOUND THEN
    IF v_codex_scoped AND pdc_codex_intake_private.authorized('readback',NULL,NULL,NULL,v_prior.batch_id) IS NOT TRUE
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_apply_conflict');END IF;
    INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
    VALUES(v_prior.batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,'replay',v_prior.response||jsonb_build_object('code','apply_replay','replay',true),v_actor,v_actor_label);
    RETURN v_prior.response||jsonb_build_object('code','apply_replay','replay',true,'tune_checkout_transfers',(SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts WHERE batch_id=v_prior.batch_id));END IF;
  IF v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4') AND v_preview.accepted_line_count>0 THEN
    RETURN jsonb_build_object('ok',false,'code','preview_refresh_required','contract_revision','pmg_stock_v5');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  IF NOT v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 LEFT JOIN public.navision_backend_records b ON b.id=r0.backend_record_id LEFT JOIN public.vehicles v ON v.id=r0.vehicle_id
    WHERE r0.batch_id=v_preview.batch_id AND r0.decision IN('insert','unchanged') AND (b.id IS NULL OR NOT b.is_current OR b.record_status<>'current' OR b.source_system<>'microsoft_navision'
      OR b.dealer_code<>'37047' OR b.canonical_vehicle_id IS DISTINCT FROM r0.vehicle_id
      OR btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) IS DISTINCT FROM btrim(r0.stock_number)
      OR v.id IS NULL OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.stock_number_normalized IS DISTINCT FROM btrim(r0.stock_number)
      OR (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision' AND x.dealer_code='37047' AND x.is_current AND x.record_status='current'
        AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=btrim(r0.stock_number))<>1))
  THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed');END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='insert'
      AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'))
     OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='unchanged'
      AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'
        AND o.semantic_hash=r0.semantic_hash))
  THEN RETURN jsonb_build_object('ok',false,'code','operation_state_changed_after_preview');END IF;
  IF v_tune THEN
    -- Serialize Stock creation with all canonical writers and validate every candidate before any write.
    LOCK TABLE public.vehicles, public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
    FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_row.stock_number);
      IF (v_candidate->>'ok')::boolean IS NOT TRUE
        OR (v_row.vehicle_id IS NOT NULL AND v_row.vehicle_id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid)
        OR v_row.backend_record_id IS DISTINCT FROM (v_candidate->>'backend_record_id')::uuid
      THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed','stock_number',v_row.stock_number); END IF;
    END LOOP;
  END IF;
  IF v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r JOIN public.pdc_unidentified_tune_review u ON u.workbook_sha256=r.normalized_payload->>'workbook_sha256' AND u.operation_identity_hash=r.normalized_payload->>'operation_identity_hash'
    WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review' AND (u.source_estimated_hours IS DISTINCT FROM (r.normalized_payload->>'source_estimated_hours')::numeric OR u.raw_row IS DISTINCT FROM r.raw_row))
  THEN RETURN jsonb_build_object('ok',false,'code','unidentified_source_changed'); END IF;
  v_response:=jsonb_build_object('ok',true,'code','applied','replay',false,'apply_batch_id',v_apply_batch,'source_hash',v_source_hash,'source_link',v_preview.source_link,'unidentified_rows',(SELECT count(*) FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND reason='unidentified_tune_review'),'operation_updates_for_review',coalesce((v_preview.response->>'operation_updates_for_review')::integer,0),'approvals_created',0,'insert',v_preview.insert_count,'update',0,
    'unchanged',v_preview.unchanged_count,'duplicate_ignored',coalesce((v_preview.response->'operations'->>'duplicate_ignored')::integer,0),'bookings_created',0,'completions_created',0,'atomic',true);
  INSERT INTO public.pdc_pilbara_service_import_batches(contract_revision,source_link,batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,quarantined_line_count,
    matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_preview.contract_revision,v_preview.source_link,v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'apply',v_preview.source_row_count,v_preview.accepted_line_count,v_preview.quarantined_line_count,
    v_preview.matched_stock_count,v_preview.unmatched_stock_count,v_preview.ambiguous_stock_count,v_preview.insert_count,0,v_preview.unchanged_count,v_preview.conflict_count,v_response,v_actor,v_actor_label);
  IF v_tune THEN
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL THEN
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles
        WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_stock) AND deleted_at IS NULL;
        -- Link only the unique current exact-Stock record accepted by this revision.
        -- Keep the pending vehicle's lifecycle and location; do not activate the board.
        UPDATE public.navision_backend_records SET canonical_vehicle_id=v_vehicle_id
        WHERE id=v_backend AND canonical_vehicle_id IS NULL;
        UPDATE public.vehicles SET source_system='microsoft_navision',source_record_id=v_backend::text,
          source_payload=coalesce(source_payload,'{}')||v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg')
        WHERE id=v_vehicle_id;
        PERFORM public.navision_refresh_linked_vehicle_projection_770(v_backend);
      END IF;
    END LOOP;
    IF v_preview.contract_revision='pmg_stock_v5' THEN
      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;
        PERFORM public.pdc_apply_tune_vehicle_fields_v5(v_vehicle_id,v_apply_batch,v_preview.batch_id);
      END LOOP;
    END IF;
    INSERT INTO public.pdc_unidentified_tune_review(workbook_sha256,repair_order_number,department,original_line_number,operation_description,operation_identity_hash,source_estimated_hours,operation_code,proposed_station,raw_row,source_hash,source_batch_id)
    SELECT r.normalized_payload->>'workbook_sha256',r.repair_order_number,r.normalized_payload->>'department',r.original_line_number,r.normalized_payload->>'operation_description',r.normalized_payload->>'operation_identity_hash',
      (r.normalized_payload->>'source_estimated_hours')::numeric,r.normalized_payload->>'operation_code',r.normalized_payload->>'proposed_station',r.raw_row,v_source_hash,v_apply_batch
    FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review'
    ON CONFLICT(workbook_sha256,operation_identity_hash) DO NOTHING;
  END IF;
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged') ORDER BY r.source_order LOOP
    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;
    v_identity_hash:=v_row.normalized_payload->>'operation_identity_hash';
    SELECT * INTO v_op FROM public.pdc_pilbara_service_operations x WHERE x.importer_version='pilbara_service_open_jobcards_v1'
      AND public.pdc_pilbara_service_operation_identity_hash_v3(x.department,x.stock_number,x.repair_order_number,x.original_line_number,x.operation_description)=v_identity_hash FOR SHARE;
    IF v_row.decision='insert' THEN
      IF FOUND THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
        source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
      VALUES(v_row.normalized_payload->>'department',v_row.normalized_payload->>'operation_code',v_row.normalized_payload->>'proposed_station','pilbara_service_open_jobcards_v1',v_row.stock_number,v_row.repair_order_number,v_row.original_line_number,v_row.source_order,v_row.vehicle_id,v_row.normalized_payload->>'operation_description',
        CASE WHEN v_row.normalized_payload->>'source_estimated_hours' IS NULL THEN NULL ELSE (v_row.normalized_payload->>'source_estimated_hours')::numeric END,
        (v_row.normalized_payload->>'effective_estimated_hours')::numeric,v_row.normalized_payload->>'hours_provenance',coalesce(v_row.normalized_payload->>'parts_on_backorder_raw',''),
        v_row.normalized_payload->>'parts_semantics','Review',v_row.semantic_hash,v_row.evidence_id) RETURNING operation_id INTO v_operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'insert',NULL,v_row.semantic_hash,v_row.normalized_payload);
    ELSE
      IF NOT FOUND OR v_op.semantic_hash<>v_row.semantic_hash THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      v_operation_id:=v_op.operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'unchanged',v_op.semantic_hash,v_op.semantic_hash,v_row.normalized_payload);
    END IF;
  END LOOP;
  FOR v_vehicle_id IN SELECT DISTINCT o.vehicle_id FROM public.pdc_pilbara_service_operation_history h JOIN public.pdc_pilbara_service_operations o USING(operation_id) WHERE h.batch_id=v_apply_batch LOOP
    -- Rolling imports retain operations absent from this file.
    SELECT CASE WHEN count(DISTINCT r0.repair_order_number)=1 THEN min(r0.repair_order_number) ELSE NULL END INTO v_first_ro FROM public.pdc_pilbara_service_import_rows r0
    WHERE r0.batch_id=v_preview.batch_id AND (r0.vehicle_id=v_vehicle_id OR (v_tune AND r0.stock_number=(SELECT stock_number FROM public.vehicles WHERE id=v_vehicle_id))) AND r0.decision IN('insert','unchanged');
    IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=v_vehicle_id AND NOT v.visible_on_board)
      AND NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v_vehicle_id AND r.status='closed') THEN
      INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,first_job_card,received_at,approved_at,approved_by,approval_key,approval_hash,approval_receipt)
      VALUES(v_vehicle_id,'pending',CASE WHEN v_tune THEN 'tune_pmg' ELSE 'revolution_report' END,v_first_ro,clock_timestamp(),NULL,NULL,NULL,NULL,NULL)
      ON CONFLICT(vehicle_id) DO UPDATE SET status='pending',source_kind=excluded.source_kind,first_job_card=excluded.first_job_card,received_at=clock_timestamp(),
        approved_at=NULL,approved_by=NULL,approval_key=NULL,approval_hash=NULL,approval_receipt=NULL;
      UPDATE public.vehicles SET job_card_number=v_first_ro,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=v_vehicle_id AND visible_on_board=false;
    END IF;
  END LOOP;
  PERFORM public.pdc_capture_tune_operation_changes_20260912(v_preview.batch_id,v_apply_batch);
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,'apply',v_response,v_actor,v_actor_label);
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  PERFORM public.workshop_bump_revision();
  PERFORM pdc_parts_private.sync_service_jobs();
  PERFORM pdc_codex_intake_private.capture_service_locations(v_preview.batch_id,v_apply_batch);
  IF v_preview.contract_revision='pmg_stock_v5' THEN PERFORM pdc_codex_intake_private.capture_service_status(v_preview.batch_id,v_apply_batch); END IF;
  PERFORM pdc_codex_intake_private.apply_service_arrival(v_apply_batch);
  RETURN v_response||jsonb_build_object('tune_checkout_transfers',(SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts WHERE batch_id=v_apply_batch));
END
$function$
;