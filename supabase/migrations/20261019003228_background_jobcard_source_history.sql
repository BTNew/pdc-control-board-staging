DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL OR NOT pdc_codex_intake_private.management_connection()
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF md5(regexp_replace(pg_get_functiondef('pdc_operation_updates_private.accept_change(uuid)'::regprocedure),'[[:space:]]+',' ','g'))<>'7b9b7b95e37f501902967b4e5c34fca0'
 OR md5(pg_get_functiondef('pdc_operation_updates_private.reconcile_bookings(uuid,text[],uuid,uuid)'::regprocedure))<>'5cb064fddd6ce6381cc56a0732ac1338'
 THEN RAISE EXCEPTION 'source_history_version_changed'; END IF;
END $guard$;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION pdc_operation_updates_private.accept_change(p_change_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE q public.pdc_tune_operation_change_reviews%rowtype; v public.vehicles%rowtype;
 a public.vehicle_workshop_line_adjustments%rowtype; evidence public.pdc_pilbara_service_import_rows%rowtype;
 actor uuid; choice jsonb; candidate jsonb; p jsonb; actual jsonb; new_line jsonb; schedule jsonb; reply jsonb;
 source_id uuid; key text; stage text; work text; h numeric; before_vehicle jsonb;
 original_defer text:=current_setting('pdc.defer_workshop_adjustment_reconcile',true);
 original_required_defer text:=current_setting('pdc.defer_workshop_required_work_reconcile',true);
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
 -- Same lock order as the workshop clock. Do not hold up an upload behind it.
 IF NOT pg_try_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0))
 THEN RETURN jsonb_build_object('ok',false,'code','operation_schedule_busy'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL
  AND status IN('queued','planned','started','stoppage') ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE NOWAIT;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE NOWAIT;
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id FOR UPDATE NOWAIT;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','operation_review_not_found'); END IF;
 IF q.status='approved' THEN RETURN q.approval_receipt||jsonb_build_object('replay',true); END IF;
 IF q.status<>'pending' THEN RETURN jsonb_build_object('ok',false,'code','review_not_pending'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=q.vehicle_id FOR UPDATE NOWAIT;
 IF v.deleted_at IS NOT NULL OR v.visible_on_board IS NOT TRUE OR v.lifecycle_state::text<>'active'
  OR v.qc_completed_at IS NOT NULL OR upper(btrim(coalesce(v.current_location,''))) IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
  OR NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='approved' AND r.approved_at IS NOT NULL)
 THEN RETURN jsonb_build_object('ok',false,'code','vehicle_or_review_state_protected'); END IF;
 p:=q.proposed_source;
 IF p->>'department' NOT IN('138','139') OR q.company<>'01' OR q.division<>'1'
  OR v.stock_number IS DISTINCT FROM p->>'stock_number'
  OR q.repair_order_number IS DISTINCT FROM p->>'repair_order_number'
  OR q.original_line_number IS DISTINCT FROM (p->>'original_line_number')::integer
  OR (q.before_source->>'department' IS NOT NULL AND q.before_source->>'department' IS DISTINCT FROM p->>'department')
 THEN RETURN jsonb_build_object('ok',false,'code','operation_identity_needs_review'); END IF;
 SELECT * INTO evidence FROM public.pdc_pilbara_service_import_rows WHERE evidence_id=q.evidence_id;
 SELECT created_by INTO actor FROM public.pdc_pilbara_service_import_batches WHERE batch_id=q.batch_id AND batch_kind='apply';
 IF actor IS NULL OR evidence.normalized_payload IS DISTINCT FROM p
 THEN RETURN jsonb_build_object('ok',false,'code','source_evidence_mismatch'); END IF;
 candidate:=public.pdc_tune_operation_change_candidate_20260912(v.id,p||jsonb_build_object('raw_row',evidence.raw_row));
 IF candidate ? 'conflict' OR candidate->>'proposed_hash' IS DISTINCT FROM q.proposed_hash
  OR (candidate->>'source_operation_id')::uuid IS DISTINCT FROM q.source_operation_id
 THEN RETURN jsonb_build_object('ok',false,'code','operation_identity_changed'); END IF;
 choice:=pdc_operation_updates_private.proposal(q.change_id);
 IF choice->>'ok' IS DISTINCT FROM 'true' THEN RETURN choice; END IF;
 stage:=choice->>'stage_code';h:=(choice->>'estimated_hours')::numeric;
 SELECT work_key INTO work FROM public.workshop_stages WHERE code=stage AND active;
 IF work IS NULL AND stage<>'JOB_CARD_NOTES' THEN RETURN jsonb_build_object('ok',false,'code','station_needs_review'); END IF;
 IF EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v.id AND work_key=work AND completed)
 THEN RETURN jsonb_build_object('ok',false,'code','completed_station_requires_rework_review'); END IF;
 source_id:=q.source_operation_id;key:='source:'||source_id;
 SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF source_id IS NOT NULL AND (actual IS NULL OR actual->>'completed'='true' OR actual->>'rejected'='true' OR actual->>'active' IS DISTINCT FROM 'true')
 THEN RETURN jsonb_build_object('ok',false,'code','completed_or_removed_line_protected'); END IF;
 before_vehicle:=to_jsonb(v)-ARRAY['version','updated_at','updated_by'];
 PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','407',true);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile','407',true);
 IF source_id IS NULL THEN
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v.id AND repair_order_number=q.repair_order_number AND original_line_number=q.original_line_number)
  THEN RAISE EXCEPTION 'operation_identity_changed'; END IF;
  INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
   source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
  VALUES(p->>'department',p->>'operation_code','REVIEW','pilbara_service_open_jobcards_v1',v.stock_number,q.repair_order_number,q.original_line_number,(p->>'source_order')::integer,v.id,p->>'operation_description',
   (p->>'source_estimated_hours')::numeric,(p->>'effective_estimated_hours')::numeric,p->>'hours_provenance',coalesce(p->>'parts_on_backorder_raw',''),'review','Review',p->>'semantic_hash',q.evidence_id)
  RETURNING operation_id INTO source_id;
  key:='source:'||source_id;
  INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
  VALUES(source_id,q.batch_id,'insert',NULL,p->>'semantic_hash',p);
 END IF;
 UPDATE public.pdc_tune_operation_change_reviews SET status='approved',source_operation_id=source_id,
  approved_at=clock_timestamp(),approved_by=actor WHERE change_id=q.change_id;
 IF stage<>'JOB_CARD_NOTES' THEN
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 VALUES(v.id,work,true,false,'Automatically accepted uploaded operation')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp();
 END IF;
 SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=key FOR UPDATE;
 IF FOUND THEN
  UPDATE public.vehicle_workshop_line_adjustments SET stage_code=coalesce(choice->>'adjustment_stage_code',stage),estimated_hours=h,
   version=version+1,updated_by=actor,updated_at=clock_timestamp() WHERE adjustment_id=a.adjustment_id;
 ELSE
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,manual_assignment_locked,created_by,updated_by,correction_origin)
  VALUES(v.id,key,'source',coalesce(choice->>'adjustment_stage_code',stage),btrim(left(btrim(regexp_replace(p->>'operation_description','[[:cntrl:]]',' ','g')),180)),h,true,1,(stage<>'JOB_CARD_NOTES' AND (q.source_operation_id IS NOT NULL OR p->>'department'<>'138')),actor,actor,CASE WHEN q.source_operation_id IS NULL AND p->>'department'='138' THEN 'job_card_source_correction' END);
 END IF;
 SELECT l INTO new_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF new_line->>'stage_code' IS DISTINCT FROM stage OR (new_line->>'estimated_hours')::numeric IS DISTINCT FROM h
  OR new_line->>'description' IS DISTINCT FROM p->>'operation_description' OR new_line->>'completed' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'operation_readback_mismatch'; END IF;
 IF stage='JOB_CARD_NOTES' THEN schedule:=jsonb_build_object('changed_count',0);
 ELSE schedule:=pdc_operation_updates_private.reconcile_bookings(v.id,ARRAY[stage,actual->>'stage_code'],q.change_id,actor); END IF;
 IF before_vehicle IS DISTINCT FROM (SELECT to_jsonb(x)-ARRAY['version','updated_at','updated_by'] FROM public.vehicles x WHERE id=v.id)
 THEN RAISE EXCEPTION 'protected_vehicle_state_changed'; END IF;
 reply:=jsonb_build_object('ok',true,'code','operation_change_auto_approved','data',jsonb_build_object(
  'change_id',q.change_id,'vehicle_id',v.id,'operation',new_line,'estimate',choice,'location_changed',false,
  'bookings_changed',(schedule->>'changed_count')::integer>0,'schedule',schedule));
 UPDATE public.pdc_tune_operation_change_reviews SET approval_key=q.change_id,
  approval_hash=q.proposed_hash,approval_receipt=reply,version=version+1 WHERE change_id=q.change_id;
 PERFORM public.audit_pdc_event('update','pdc_tune_operation_change_reviews',q.change_id,v.id,q.before_source,p,
  jsonb_build_object('action','auto_accept_uploaded_operation','source_evidence_id',q.evidence_id,'estimate',choice));
 DELETE FROM pdc_operation_updates_private.schedule_writes WHERE transaction_id=txid_current() AND change_id=q.change_id;
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 PERFORM public.workshop_bump_revision();
 PERFORM set_config('pdc.defer_workshop_adjustment_reconcile',coalesce(original_defer,''),true);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile',coalesce(original_required_defer,''),true);
 RETURN reply;
EXCEPTION WHEN OTHERS THEN
 -- Each failed change rolls back independently; immutable uploaded evidence stays.
 PERFORM set_config('pdc.defer_workshop_adjustment_reconcile',coalesce(original_defer,''),true);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile',coalesce(original_required_defer,''),true);
 RETURN jsonb_build_object('ok',false,'code',CASE WHEN SQLSTATE IN('40001','40P01','55P03') THEN 'operation_schedule_busy' ELSE 'operation_schedule_conflict' END,
  'detail',SQLERRM);
END $function$
;
CREATE OR REPLACE FUNCTION pdc_operation_updates_private.reconcile_bookings(p_vehicle_id uuid, p_stage_codes text[], p_change_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '120s'
AS $function$
#variable_conflict use_column
<<plan>>
DECLARE
 item record; prior record; n integer; minutes integer; proposed_start timestamptz;
 proposed_end timestamptz; blocked_until timestamptz; unavailable_date date;
 old_snapshot jsonb; new_snapshot jsonb; receipt jsonb:='[]'; changed boolean;
 root_change boolean; technician uuid; validation jsonb; graph_count integer;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Operation approval is available on staging only.';
 END IF;

 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.bay_id IS NOT NULL
    AND b.status IN('queued','planned','started','stoppage') AND s.code=ANY(p_stage_codes)
    AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET') THEN
  RETURN jsonb_build_object('bookings',receipt,'changed_count',0,'extended_count',0,'moved_count',0,'buffer_minutes',60);
 END IF;
 -- These are the same rows written by the existing planner. Preserve its guards
 -- and immediate overlap constraints; never hide or temporarily delete a job.
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL
  AND status IN('queued','planned','started','stoppage') ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE NOWAIT;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE NOWAIT;
 DROP TABLE IF EXISTS pg_temp.pdc_tune_cascade_plan;
 CREATE TEMP TABLE pdc_tune_cascade_plan(
  ordinal bigint PRIMARY KEY,booking_id uuid UNIQUE NOT NULL,vehicle_id uuid NOT NULL,
  stage_id uuid NOT NULL,stage_code text NOT NULL,bay_id uuid,status text NOT NULL,
  original_start timestamptz NOT NULL,original_end timestamptz NOT NULL,
  original_minutes integer NOT NULL,minutes integer NOT NULL,version integer NOT NULL,
  final_start timestamptz NOT NULL,final_end timestamptz NOT NULL,
  technicians uuid[] NOT NULL,root_change boolean NOT NULL DEFAULT false,
  changed boolean NOT NULL DEFAULT false,before_row jsonb NOT NULL
 ) ON COMMIT DROP;
 INSERT INTO pg_temp.pdc_tune_cascade_plan
  (ordinal,booking_id,vehicle_id,stage_id,stage_code,bay_id,status,original_start,original_end,
   original_minutes,minutes,version,final_start,final_end,technicians,before_row)
 SELECT row_number() OVER(ORDER BY b.scheduled_start_at,b.id),b.id,b.vehicle_id,b.stage_id,s.code,b.bay_id,b.status::text,
  b.scheduled_start_at,b.scheduled_end_at,b.default_duration_minutes,b.default_duration_minutes,b.version,
  b.scheduled_start_at,b.scheduled_end_at,
  coalesce((SELECT array_agg(DISTINCT a.technician_id) FROM public.workshop_booking_assignments a
    WHERE a.booking_id=b.id AND a.released_at IS NULL),'{}'::uuid[]),to_jsonb(b)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
  AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET';
 SELECT count(*) INTO graph_count FROM pg_temp.pdc_tune_cascade_plan;
 IF graph_count>10000 THEN RAISE EXCEPTION 'The workshop queue needs a smaller scheduling review.'
  USING DETAIL='operation_schedule_limit'; END IF;
 -- Category bookings use their own current work estimate; legacy bookings retain whole-station scope.
 -- Never manufacture a booking for a newly required, unbooked station.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan
  WHERE vehicle_id=p_vehicle_id AND stage_code=ANY(p_stage_codes) AND bay_id IS NOT NULL ORDER BY ordinal
 LOOP
  IF EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan x
    JOIN public.workshop_bookings other_booking ON other_booking.id=x.booking_id
    JOIN public.workshop_bookings current_booking ON current_booking.id=item.booking_id
    WHERE x.vehicle_id=p_vehicle_id AND x.stage_id=item.stage_id AND x.bay_id IS NOT NULL
     AND x.booking_id<>item.booking_id
     AND (other_booking.work_category IS NULL OR current_booking.work_category IS NULL
      OR other_booking.work_category=current_booking.work_category)) THEN
   RAISE EXCEPTION 'This work scope has more than one active booking. Review those bookings before approving the operation.'
    USING DETAIL='operation_schedule_multiple_station_bookings';
  END IF;
  minutes:=CASE WHEN item.status IN('queued','planned') THEN public.workshop_booking_capacity_duration_minutes(item.booking_id,p_vehicle_id,item.stage_id,item.bay_id) ELSE pdc_work_categories_private.minutes(item.booking_id,p_vehicle_id,item.stage_id) END;
  IF minutes IS NULL OR minutes<1 THEN
   RAISE EXCEPTION 'This change would leave a booked station without work. Move or remove its booking before approving.'
    USING DETAIL='operation_schedule_empty_station';
  END IF;
  -- Reducing an estimate must not shorten a job that is already in progress.
  IF item.status IN('started','stoppage') THEN minutes:=greatest(minutes,item.original_minutes); END IF;
  proposed_end:=public.workshop_add_operational_minutes(item.original_start,minutes);
  UPDATE pg_temp.pdc_tune_cascade_plan SET minutes=plan.minutes,
   root_change=(plan.minutes IS DISTINCT FROM item.original_minutes OR proposed_end IS DISTINCT FROM item.original_end)
   WHERE booking_id=item.booking_id;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan WHERE root_change) THEN
  RETURN jsonb_build_object('bookings',receipt,'changed_count',0,'extended_count',0,'moved_count',0,'buffer_minutes',60);
 END IF;
 -- Dependency order is the original queue order. Every move is to the right,
 -- so a later bay or vehicle job can never jump ahead of its predecessor.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan ORDER BY ordinal LOOP
  root_change:=item.root_change;
  SELECT max(greatest(x.final_end,CASE WHEN x.status IN('started','stoppage') THEN date_trunc('minute',clock_timestamp()) ELSE x.final_end END)
      +CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END) INTO blocked_until
   FROM pg_temp.pdc_tune_cascade_plan x WHERE x.ordinal<item.ordinal AND x.changed
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  IF NOT root_change AND coalesce(blocked_until,item.original_start)<=item.original_start THEN CONTINUE; END IF;
  IF item.bay_id IS NULL THEN
   RAISE EXCEPTION 'A later job is queued without a bay. Review that booking before approving this change.'
    USING DETAIL='operation_schedule_queued_without_bay';
  END IF;
  proposed_start:=greatest(item.original_start,coalesce(blocked_until,item.original_start));
  IF item.status IN('started','stoppage') AND proposed_start>item.original_start THEN
   RAISE EXCEPTION 'A later job is already in progress or stopped. Resolve that booking before approving this change.'
    USING DETAIL='operation_schedule_protected_active_booking';
  END IF;
  minutes:=item.minutes;
  IF item.status IN('queued','planned') THEN
   minutes:=coalesce(public.workshop_booking_capacity_duration_minutes(item.booking_id,item.vehicle_id,item.stage_id,item.bay_id),minutes);
   proposed_start:=greatest(proposed_start,date_trunc('minute',clock_timestamp())+interval '1 minute');
  END IF;
  -- Once a booking moves, also respect unchanged predecessors and technician
  -- reservations. Unrelated jobs with no incoming change are left untouched.
  SELECT max(greatest(x.final_end,CASE WHEN x.status IN('started','stoppage') THEN date_trunc('minute',clock_timestamp()) ELSE x.final_end END)
     +CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END) INTO blocked_until
   FROM pg_temp.pdc_tune_cascade_plan x WHERE x.ordinal<item.ordinal
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  proposed_start:=greatest(proposed_start,coalesce(blocked_until,proposed_start));
  IF item.status IN('started','stoppage') AND proposed_start>item.original_start THEN
   RAISE EXCEPTION 'The current job cannot be moved automatically. Resolve its earlier booking conflict first.'
    USING DETAIL='operation_schedule_protected_active_booking';
  END IF;
  n:=0;
  LOOP
   n:=n+1;
   IF n>1000 THEN RAISE EXCEPTION 'No safe workshop slot was found for this change.'
    USING DETAIL='operation_schedule_no_slot'; END IF;
   IF item.status IN('queued','planned') THEN
    proposed_start:=public.workshop_admin_next_operational_minute(proposed_start);
    IF proposed_start IS NULL THEN RAISE EXCEPTION 'No open workshop time was found for this change.'
     USING DETAIL='operation_schedule_calendar_unavailable'; END IF;
   END IF;
   proposed_end:=public.workshop_add_operational_minutes(proposed_start,minutes);
   SELECT max(a.scheduled_end_at) INTO blocked_until FROM public.workshop_admin_blocks a
    WHERE a.deleted_at IS NULL AND a.bay_id=item.bay_id
     AND a.scheduled_start_at<proposed_end AND a.scheduled_end_at>proposed_start;
   SELECT max(d::date) INTO unavailable_date FROM generate_series(
    (proposed_start AT TIME ZONE 'Australia/Perth')::date::timestamp,
    ((proposed_end-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
    WHERE public.pdc_sublet_away_on_date(item.vehicle_id,d::date);
   IF unavailable_date IS NOT NULL THEN
    blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
   END IF;
   FOREACH technician IN ARRAY item.technicians LOOP
    unavailable_date:=public.workshop_technician_leave_date(technician,proposed_start,proposed_end);
    IF unavailable_date IS NOT NULL THEN
     blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
    END IF;
   END LOOP;
   EXIT WHEN blocked_until IS NULL;
   IF item.status IN('started','stoppage') THEN
    RAISE EXCEPTION 'The longer current job conflicts with an Admin block, Sublet visit or technician leave. Resolve that conflict before approving.'
     USING DETAIL='operation_schedule_protected_reservation';
   END IF;
   proposed_start:=greatest(proposed_start+interval '1 minute',blocked_until);
  END LOOP;
  changed:=proposed_start IS DISTINCT FROM item.original_start OR proposed_end IS DISTINCT FROM item.original_end OR minutes IS DISTINCT FROM item.original_minutes;
  UPDATE pg_temp.pdc_tune_cascade_plan SET final_start=proposed_start,final_end=proposed_end,
   minutes=plan.minutes,changed=plan.changed
   WHERE booking_id=item.booking_id;
 END LOOP;
 -- Move downstream jobs first, vacating intervals before earlier extensions.
 -- Immediate bay, vehicle and technician exclusion constraints remain enabled.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan WHERE changed ORDER BY ordinal DESC LOOP
  old_snapshot:=public.workshop_booking_snapshot(item.booking_id);
  INSERT INTO pdc_operation_updates_private.schedule_writes(transaction_id,booking_id,change_id,actor_id,before_row,start_at,end_at,minutes)
  VALUES(txid_current(),item.booking_id,p_change_id,p_actor,(SELECT to_jsonb(b) FROM public.workshop_bookings b WHERE id=item.booking_id),item.final_start,item.final_end,item.minutes)
  ON CONFLICT(transaction_id,booking_id) DO UPDATE SET change_id=excluded.change_id,actor_id=excluded.actor_id,before_row=excluded.before_row,start_at=excluded.start_at,end_at=excluded.end_at,minutes=excluded.minutes;
  UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
   default_duration_minutes=item.minutes,version=version+1,updated_by=p_actor,updated_at=clock_timestamp()
   WHERE id=item.booking_id AND version=item.version AND status::text=item.status AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'A booking changed while this operation was being approved. Refresh and try again.'
   USING ERRCODE='40001',DETAIL='operation_schedule_changed'; END IF;
  -- Retain every assignment and its identity, including secondary technicians.
  UPDATE public.workshop_booking_assignments SET scheduled_start_at=item.final_start,
   scheduled_end_at=item.final_end,updated_at=clock_timestamp()
   WHERE booking_id=item.booking_id AND released_at IS NULL;
  new_snapshot:=public.workshop_booking_snapshot(item.booking_id);
  IF (SELECT to_jsonb(b)-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes']
      FROM public.workshop_bookings b WHERE id=item.booking_id)
    IS DISTINCT FROM item.before_row-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes'] THEN
   RAISE EXCEPTION 'Operation approval changed protected booking details.' USING DETAIL='operation_schedule_readback_mismatch';
  END IF;
  -- The immutable import batch actor is audit attribution, not an interactive login.
  -- A deliberately disabled importer must stay disabled; do not borrow a staff session.
  IF NOT EXISTS(SELECT 1 FROM pdc_operation_updates_private.schedule_writes w
   JOIN public.pdc_tune_operation_change_reviews q ON q.change_id=w.change_id AND q.status='approved'
   JOIN public.pdc_pilbara_service_import_batches b ON b.batch_id=q.batch_id AND b.created_by=w.actor_id
   WHERE w.transaction_id=txid_current() AND w.booking_id=item.booking_id
    AND w.change_id=p_change_id AND w.actor_id=p_actor AND q.approved_by=p_actor)
  THEN RAISE EXCEPTION 'import_schedule_actor_unbound'; END IF;
  INSERT INTO public.workshop_booking_history(booking_id,vehicle_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
  VALUES(item.booking_id,item.vehicle_id,'operation_change_schedule_updated',old_snapshot,new_snapshot,
   jsonb_build_object('source','approved_tune_operation_change','change_id',p_change_id,'approved_vehicle_id',p_vehicle_id,
    'buffer_minutes',60,'previous_duration_minutes',item.original_minutes,'duration_minutes',item.minutes,
    'moved',item.final_start IS DISTINCT FROM item.original_start,'actor_basis','authenticated_source_batch'),
   p_actor,(SELECT email FROM auth.users WHERE id=p_actor));
  PERFORM public.audit_pdc_event('update','workshop_bookings',item.booking_id,item.vehicle_id,old_snapshot,new_snapshot,
   jsonb_build_object('event_type','operation_change_schedule_updated','source','approved_tune_operation_change',
    'change_id',p_change_id,'import_actor_user_id',p_actor,'actor_basis','authenticated_source_batch'));

 END LOOP;
 -- Check the final vehicle handovers against the calculated plan. General
 -- planner validation separately verifies bay, technician, ETA and calendar.
 IF EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan a JOIN pg_temp.pdc_tune_cascade_plan b
   ON a.vehicle_id=b.vehicle_id AND a.ordinal<b.ordinal
   WHERE (a.changed OR b.changed) AND a.final_end+interval '1 hour'>b.final_start) THEN
  RAISE EXCEPTION 'The vehicle needs one hour between workshop jobs.' USING DETAIL='operation_schedule_handover_conflict';
 END IF;
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan WHERE changed LOOP
  FOREACH technician IN ARRAY item.technicians LOOP
   IF public.workshop_find_technician_conflict(item.booking_id,technician,item.final_start,item.final_end) IS NOT NULL THEN
    RAISE EXCEPTION 'The revised job conflicts with another technician booking.' USING DETAIL='operation_schedule_technician_conflict';
   END IF;
  END LOOP;
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',x.booking_id,'vehicle_id',x.vehicle_id,
  'stock_number',coalesce(nullif(btrim(v.stock_number),''),'—'),'stage_code',x.stage_code,'bay_id',x.bay_id,'bay_name',coalesce(nullif(btrim(b.display_name),''),'Bay '||b.bay_number),
  'previous_start_at',x.original_start,'previous_end_at',x.original_end,'start_at',x.final_start,'end_at',x.final_end,
  'previous_estimated_hours',x.original_minutes::numeric/60,'estimated_hours',x.minutes::numeric/60,
  'status',x.status) ORDER BY x.ordinal),'[]') INTO receipt
 FROM pg_temp.pdc_tune_cascade_plan x JOIN public.vehicles v ON v.id=x.vehicle_id
 LEFT JOIN public.workshop_bays b ON b.id=x.bay_id WHERE x.changed;
 RETURN jsonb_build_object('bookings',receipt,'changed_count',jsonb_array_length(receipt),
  'extended_count',(SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan WHERE changed AND minutes>original_minutes),
  'moved_count',(SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan WHERE changed AND final_start IS DISTINCT FROM original_start),
  'buffer_minutes',60);
END $function$
;
