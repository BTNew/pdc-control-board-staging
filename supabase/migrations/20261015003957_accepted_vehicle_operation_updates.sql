-- Craig, 15 October: accepted vehicles receive uploaded work automatically.
-- New Vehicles is only initial intake. Never reopen completed work or guess hours.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'staging_only'; END IF;
END $guard$;
CREATE SCHEMA pdc_operation_updates_private;
REVOKE ALL ON SCHEMA pdc_operation_updates_private FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.pdc_tune_operation_change_reviews ADD COLUMN automation_result jsonb,
 ADD COLUMN automation_checked_at timestamptz;
CREATE TABLE pdc_operation_updates_private.schedule_writes(
 transaction_id bigint NOT NULL,booking_id uuid NOT NULL,change_id uuid NOT NULL,actor_id uuid NOT NULL,
 before_row jsonb NOT NULL,start_at timestamptz NOT NULL,end_at timestamptz NOT NULL,minutes integer NOT NULL,
 PRIMARY KEY(transaction_id,booking_id));
ALTER TABLE pdc_operation_updates_private.schedule_writes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_operation_updates_private.schedule_writes FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_operation_updates_private.allowed_schedule(old_row jsonb,new_row jsonb)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT EXISTS(SELECT 1 FROM pdc_operation_updates_private.schedule_writes w
  JOIN public.pdc_tune_operation_change_reviews q ON q.change_id=w.change_id AND q.status='approved'
  WHERE w.transaction_id=txid_current() AND w.booking_id=(old_row->>'id')::uuid
   AND w.before_row=old_row AND (new_row->>'updated_by')::uuid=w.actor_id
   AND (new_row->>'scheduled_start_at')::timestamptz=w.start_at
   AND (new_row->>'scheduled_end_at')::timestamptz=w.end_at
   AND (new_row->>'default_duration_minutes')::integer=w.minutes
   AND (new_row->>'version')::integer=(old_row->>'version')::integer+1
   AND (new_row-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes'])
     =(old_row-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes']));
$fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.allowed_schedule(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Extend only the booking trigger's role check for exact internally recorded writes.
-- All lifecycle, overlap, parts, calendar, location and planner guards still execute.
DO $patch$ DECLARE d text; BEGIN
 d:=pg_get_functiondef('public.workshop_require_planner_booking_mutation()'::regprocedure);
 IF position('if auth.uid() is not null then' in d)=0 THEN RAISE EXCEPTION 'booking_guard_changed'; END IF;
 d:=replace(d,'if auth.uid() is not null then',
  'if auth.uid() is not null and NOT (TG_OP=''UPDATE'' AND pdc_operation_updates_private.allowed_schedule(to_jsonb(OLD),to_jsonb(NEW))) then');
 EXECUTE d;
END $patch$;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.reconcile_bookings(p_vehicle_id uuid, p_stage_codes text[], p_change_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
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
 -- A station booking is the whole station estimate, not just the changed line.
 -- Never manufacture a booking for a newly required, unbooked station.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan
  WHERE vehicle_id=p_vehicle_id AND stage_code=ANY(p_stage_codes) AND bay_id IS NOT NULL ORDER BY ordinal
 LOOP
  IF (SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan x
    WHERE x.vehicle_id=p_vehicle_id AND x.stage_id=item.stage_id AND x.bay_id IS NOT NULL)>1 THEN
   RAISE EXCEPTION 'This station has more than one active booking. Review those bookings before approving the operation.'
    USING DETAIL='operation_schedule_multiple_station_bookings';
  END IF;
  minutes:=CASE WHEN item.status IN('queued','planned') THEN public.workshop_booking_capacity_duration_minutes(item.booking_id,p_vehicle_id,item.stage_id,item.bay_id) ELSE public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,item.stage_id) END;
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
  PERFORM public.workshop_write_history(item.booking_id,'operation_change_schedule_updated',old_snapshot,new_snapshot,
   jsonb_build_object('source','approved_tune_operation_change','change_id',p_change_id,
    'approved_vehicle_id',p_vehicle_id,'buffer_minutes',60,'previous_duration_minutes',item.original_minutes,
    'duration_minutes',item.minutes,'moved',item.final_start IS DISTINCT FROM item.original_start));
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
REVOKE ALL ON FUNCTION pdc_operation_updates_private.reconcile_bookings(uuid,text[],uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION pdc_operation_updates_private.proposal(p_change_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,public AS $fn$
DECLARE q public.pdc_tune_operation_change_reviews%rowtype; p jsonb; choice jsonb; actual jsonb; h numeric; stage text;
BEGIN
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','operation_review_not_found'); END IF;
 p:=q.proposed_source;
 choice:=public.pdc_pending_work_category_20260912(jsonb_build_object(
  'description',p->>'operation_description','department',p->>'department',
  'stage_code',p->>'proposed_station','estimated_hours',p->'effective_estimated_hours',
  'source_estimated_hours',p->'source_estimated_hours','hours_provenance',p->>'hours_provenance'));
 SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(q.vehicle_id)) l
 WHERE l->>'line_identity'='source:'||q.source_operation_id;
 stage:=choice->>'stage_code';
 -- Preserve the previously accepted station on existing work. Dept138's shared
 -- Tint exception remains authoritative, including after a description change.
 IF p->>'department'='138' THEN stage:=public.pdc_department138_station_20260917(p->>'operation_description');
 ELSIF actual->>'stage_code' IN('FITTING','ELECTRICAL','FABRICATION','HOIST','TINT','TYRE','BUS_4X4','SUBLET')
 THEN stage:=actual->>'stage_code'; END IF;
 h:=public.pdc_standard_operation_hours_20260910(p->>'operation_description',(choice->>'estimated_hours')::numeric);
 -- A metadata-only update must not replace a saved estimate with source zero.
 IF actual IS NOT NULL AND q.before_source->'source_estimated_hours' IS NOT DISTINCT FROM p->'source_estimated_hours'
  AND q.before_source->>'operation_description' IS NOT DISTINCT FROM p->>'operation_description'
 THEN h:=(actual->>'estimated_hours')::numeric; choice:=choice||jsonb_build_object('hours_provenance','retained_accepted_estimate'); END IF;
 IF stage IS NULL OR stage NOT IN('FITTING','ELECTRICAL','FABRICATION','HOIST','TINT','TYRE','BUS_4X4','SUBLET')
 THEN RETURN jsonb_build_object('ok',false,'code','station_needs_review','proposal',choice); END IF;
 IF choice->>'hours_provenance'='conflicting_description_times'
 THEN RETURN jsonb_build_object('ok',false,'code','conflicting_description_times','proposal',choice); END IF;
 IF stage<>'SUBLET' AND (h IS NULL OR h<=0 OR h>999.99 OR mod(h,0.01)<>0)
 THEN RETURN jsonb_build_object('ok',false,'code','estimated_hours_required','proposal',choice); END IF;
 RETURN choice||jsonb_build_object('ok',true,'stage_code',stage,'estimated_hours',coalesce(h,0));
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.proposal(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_operation_updates_private.accept_change(p_change_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,public,extensions AS $fn$
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
 IF work IS NULL THEN RETURN jsonb_build_object('ok',false,'code','station_needs_review'); END IF;
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
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 VALUES(v.id,work,true,false,'Automatically accepted uploaded operation')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp();
 SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=key FOR UPDATE;
 IF FOUND THEN
  UPDATE public.vehicle_workshop_line_adjustments SET stage_code=stage,estimated_hours=h,
   version=version+1,updated_by=actor,updated_at=clock_timestamp() WHERE adjustment_id=a.adjustment_id;
 ELSE
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,manual_assignment_locked,created_by,updated_by)
  VALUES(v.id,key,'source',stage,btrim(left(btrim(regexp_replace(p->>'operation_description','[[:cntrl:]]',' ','g')),180)),h,true,1,true,actor,actor);
 END IF;
 SELECT l INTO new_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF new_line->>'stage_code' IS DISTINCT FROM stage OR (new_line->>'estimated_hours')::numeric IS DISTINCT FROM h
  OR new_line->>'description' IS DISTINCT FROM p->>'operation_description' OR new_line->>'completed' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'operation_readback_mismatch'; END IF;
 schedule:=pdc_operation_updates_private.reconcile_bookings(v.id,ARRAY[stage,actual->>'stage_code'],q.change_id,actor);
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
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.accept_change(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_operation_updates_private.process_pending(p_vehicle_ids uuid[],p_limit integer DEFAULT 100,p_department text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,public AS $fn$
DECLARE q record; result jsonb; accepted integer:=0; held integer:=0;
BEGIN
 FOR q IN SELECT change_id FROM public.pdc_tune_operation_change_reviews
  WHERE status='pending' AND vehicle_id=ANY(p_vehicle_ids) AND proposed_source->>'department' IN('138','139')
   AND (nullif(btrim(p_department),'') IS NULL OR proposed_source->>'department'=p_department)
  ORDER BY created_at,change_id LIMIT greatest(0,least(p_limit,500)) LOOP
  result:=pdc_operation_updates_private.accept_change(q.change_id);
  UPDATE public.pdc_tune_operation_change_reviews SET automation_result=result,automation_checked_at=clock_timestamp() WHERE change_id=q.change_id;
  IF result->>'ok'='true' THEN accepted:=accepted+1; ELSE held:=held+1; END IF;
 END LOOP;
 RETURN jsonb_build_object('approved',accepted,'needs_attention',held);
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.process_pending(uuid[],integer,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_capture_tune_operation_changes_20260912(preview_id uuid, applied_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r public.pdc_pilbara_service_import_rows%rowtype; q public.pdc_tune_operation_change_reviews%rowtype; c jsonb; n integer:=0;
BEGIN
 FOR r IN SELECT * FROM public.pdc_pilbara_service_import_rows WHERE batch_id=preview_id AND (reason='operation_update_review' OR decision='unchanged') AND EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=pdc_pilbara_service_import_rows.vehicle_id AND v.visible_on_board) LOOP
  PERFORM 1 FROM public.vehicles WHERE id=r.vehicle_id AND visible_on_board AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'operation_review_vehicle_changed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(r.vehicle_id,r.normalized_payload||jsonb_build_object('raw_row',r.raw_row));
  IF c ? 'conflict' THEN RAISE EXCEPTION 'operation_review_identity_changed'; END IF;
  IF (c->>'needs_review')::boolean IS NOT TRUE THEN
    UPDATE public.pdc_tune_operation_change_reviews SET status='superseded',version=version+1 WHERE vehicle_id=r.vehicle_id AND company=c->>'company' AND division=c->>'division' AND repair_order_number=r.repair_order_number AND original_line_number=r.original_line_number AND status='pending';
    CONTINUE;
  END IF;
  SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id=r.vehicle_id AND company=c->>'company' AND division=c->>'division'
  AND repair_order_number=r.repair_order_number AND original_line_number=r.original_line_number AND status='pending' FOR UPDATE;
  IF FOUND AND q.proposed_hash=c->>'proposed_hash' THEN
    UPDATE public.pdc_tune_operation_change_reviews SET last_seen_at=clock_timestamp() WHERE change_id=q.change_id;
  ELSE
    UPDATE public.pdc_tune_operation_change_reviews SET status='superseded',version=version+1 WHERE change_id=q.change_id AND status='pending';
    INSERT INTO public.pdc_tune_operation_change_reviews(vehicle_id,company,division,repair_order_number,original_line_number,source_operation_id,change_kind,before_source,proposed_source,proposed_hash,evidence_id,batch_id)
    VALUES(r.vehicle_id,c->>'company',c->>'division',r.repair_order_number,r.original_line_number,(c->>'source_operation_id')::uuid,c->>'change_kind',c->'before_source',r.normalized_payload,c->>'proposed_hash',r.evidence_id,applied_id);
    n:=n+1;
  END IF;
 END LOOP;
 PERFORM pdc_operation_updates_private.process_pending(
  ARRAY(SELECT DISTINCT vehicle_id FROM public.pdc_pilbara_service_import_rows WHERE batch_id=preview_id AND vehicle_id IS NOT NULL),500);
 RETURN n;
END $function$
;
CREATE OR REPLACE FUNCTION public.pdc_tune_operation_change_row_20260912(cid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE q public.pdc_tune_operation_change_reviews%rowtype; v public.vehicles%rowtype; actual jsonb; result jsonb;
BEGIN
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 SELECT * INTO v FROM public.vehicles WHERE id=q.vehicle_id;
 IF q.change_id IS NULL OR v.id IS NULL THEN RETURN NULL; END IF;
 SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'='source:'||q.source_operation_id;
 result:=jsonb_build_object('change_id',q.change_id,'vehicle_id',v.id,'vehicle_version',v.version,'stock_number',v.stock_number,'customer_name',v.customer_name,
 'vehicle_description',v.vehicle_description,'current_location',v.current_location,'already_on_board',v.visible_on_board,'status',q.status,'version',q.version,
 'job_number',q.repair_order_number,'line_number',q.original_line_number,'company',q.company,'division',q.division,'change_kind',q.change_kind,
 'before',q.before_source,'current_work',actual,'proposed',q.proposed_source,'received_at',q.created_at,'automation_result',q.automation_result,
 'effective_hours',public.pdc_standard_operation_hours_20260910(q.proposed_source->>'operation_description',(q.proposed_source->>'source_estimated_hours')::numeric),
 'source_operation_id',q.source_operation_id);
 RETURN result||jsonb_build_object('snapshot_hash',encode(extensions.digest(convert_to(result::text,'UTF8'),'sha256'),'hex'));
END $function$
;
CREATE OR REPLACE FUNCTION public.get_pdc_review_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE vehicles_count bigint; changes_count bigint;
BEGIN
 -- These queues are intentionally unavailable to fitter-only accounts.
 IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid()
   AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email','')))
   AND r.active AND r.account_status='approved' AND r.role IN('viewer','operator','importer','administrator'))
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 SELECT count(*) INTO vehicles_count
 FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
 WHERE r.status='pending' AND v.visible_on_board IS NOT TRUE AND r.approved_at IS NULL AND v.deleted_at IS NULL AND v.lifecycle_state::text='active';
 SELECT count(*) INTO changes_count FROM public.pdc_tune_operation_change_reviews WHERE status='pending';
 RETURN jsonb_build_object('ok',true,'data',jsonb_build_object(
  'new_vehicles',vehicles_count,'operation_changes',changes_count));
END $function$
;
CREATE OR REPLACE FUNCTION public.get_pdc_review_counts_by_department(p_department text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE vehicles_count bigint; changes_count bigint; unidentified_count bigint; scope_department text:=nullif(btrim(p_department),'');
BEGIN
 IF public.pdc_department_review_reader_20260919() IS NOT TRUE
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF scope_department IS NOT NULL AND scope_department NOT IN('138','139')
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_department'); END IF;
 SELECT count(*) INTO vehicles_count
 FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
 WHERE r.status='pending' AND v.visible_on_board IS NOT TRUE AND r.approved_at IS NULL AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
  AND (scope_department IS NULL OR public.pdc_vehicle_department_membership_20260919(r.vehicle_id)->'department_codes' ? scope_department);
 SELECT count(*) INTO changes_count FROM public.pdc_tune_operation_change_reviews r
 WHERE r.status='pending' AND (scope_department IS NULL OR public.pdc_change_department_membership_20260919(r)->'department_codes' ? scope_department);
 SELECT count(*) INTO unidentified_count FROM (
  SELECT r.workbook_sha256,r.repair_order_number,r.department FROM public.pdc_unidentified_tune_review r
  WHERE scope_department IS NULL OR btrim(r.department)=scope_department
  GROUP BY r.workbook_sha256,r.repair_order_number,r.department) x;
 RETURN jsonb_build_object('ok',true,'data',jsonb_build_object(
  'new_vehicles',vehicles_count,'operation_changes',changes_count,'unidentified',unidentified_count,'department',scope_department));
END $function$
;
CREATE OR REPLACE FUNCTION public.list_pdc_new_vehicle_reviews(p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE rows jsonb; total integer;
BEGIN
 IF auth.role() IS DISTINCT FROM 'authenticated' OR auth.uid() IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid()
  AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email','')))
  AND r.active AND r.account_status='approved' AND r.role IN('viewer','operator','importer','administrator'))
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_page'); END IF;
 SELECT count(*) INTO total FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
 WHERE r.status='pending' AND v.visible_on_board IS NOT TRUE AND r.approved_at IS NULL AND v.deleted_at IS NULL AND v.lifecycle_state::text='active';
 SELECT coalesce(jsonb_agg(public.pdc_new_vehicle_review_row(x.vehicle_id) ORDER BY x.received_at DESC,x.vehicle_id),'[]') INTO rows
 FROM (SELECT r.vehicle_id,r.received_at FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
  WHERE r.status='pending' AND v.visible_on_board IS NOT TRUE AND r.approved_at IS NULL AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
  ORDER BY r.received_at DESC,r.vehicle_id LIMIT p_limit OFFSET p_offset) x;
 RETURN jsonb_build_object('ok',true,'code','new_vehicle_reviews','data',jsonb_build_object(
  'items',rows,'total',total,'offset',p_offset,'has_more',p_offset+jsonb_array_length(rows)<total));
END $function$
;
CREATE OR REPLACE FUNCTION public.list_pdc_new_vehicle_reviews_by_department(p_offset integer DEFAULT 0, p_limit integer DEFAULT 50, p_department text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE rows jsonb; total bigint; scope_department text:=nullif(btrim(p_department),'');
BEGIN
 IF public.pdc_department_review_reader_20260919() IS NOT TRUE
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF scope_department IS NOT NULL AND scope_department NOT IN('138','139')
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_department'); END IF;
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_page'); END IF;
 WITH candidates AS MATERIALIZED (
  SELECT r.vehicle_id,r.received_at,public.pdc_vehicle_department_membership_20260919(r.vehicle_id) membership
  FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
  WHERE r.status='pending' AND v.visible_on_board IS NOT TRUE AND r.approved_at IS NULL AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
 ), matching AS MATERIALIZED (
  SELECT * FROM candidates c WHERE scope_department IS NULL OR c.membership->'department_codes' ? scope_department
 ), page AS (
  SELECT * FROM matching ORDER BY received_at DESC,vehicle_id LIMIT p_limit OFFSET p_offset
 )
 SELECT (SELECT count(*) FROM matching),
  coalesce(jsonb_agg(public.pdc_new_vehicle_review_row(x.vehicle_id)||x.membership
   ORDER BY x.received_at DESC,x.vehicle_id),'[]'::jsonb) INTO total,rows FROM page x;
 RETURN jsonb_build_object('ok',true,'code','new_vehicle_reviews','data',jsonb_build_object(
  'items',rows,'total',total,'offset',p_offset,'has_more',p_offset+jsonb_array_length(rows)<total,'department',scope_department));
END $function$
;

CREATE FUNCTION public.retry_pdc_accepted_operation_updates(p_department text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
 SET lock_timeout='5s' SET statement_timeout='120s' AS $fn$
DECLARE ids uuid[];
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
 IF auth.role() IS DISTINCT FROM 'authenticated' OR auth.uid() IS NULL OR NOT public.workshop_is_planner_operator()
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF nullif(btrim(p_department),'') IS NOT NULL AND p_department NOT IN('138','139')
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_department'); END IF;
 SELECT array_agg(DISTINCT q.vehicle_id) INTO ids FROM public.pdc_tune_operation_change_reviews q
 WHERE q.status='pending' AND q.proposed_source->>'department' IN('138','139')
  AND (nullif(btrim(p_department),'') IS NULL OR q.proposed_source->>'department'=p_department);
 RETURN jsonb_build_object('ok',true,'data',pdc_operation_updates_private.process_pending(ids,100,p_department));
END $fn$;
REVOKE ALL ON FUNCTION public.retry_pdc_accepted_operation_updates(text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.retry_pdc_accepted_operation_updates(text) TO authenticated;

-- The private capture hook executes inside the existing authorized import.
-- Take the clock gate before the import's top-level lock; do not reopen an
-- already approved hidden vehicle as a new intake.
DO $patch$ DECLARE d text; BEGIN
 d:=pg_get_functiondef('public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure);
 IF position('PERFORM public.pdc_capture_tune_operation_changes_20260912(v_preview.batch_id,v_apply_batch);' in d)=0
 THEN RAISE EXCEPTION 'import_hook_changed'; END IF;
 d:=replace(d,
  'PERFORM pg_advisory_xact_lock(hashtextextended(''pdc:workshop:top-level-mutation'',0));',
  'PERFORM pg_advisory_xact_lock(hashtextextended(''workshop-clock-cascade-20260911'',0));
   PERFORM pg_advisory_xact_lock(hashtextextended(''pdc:workshop:top-level-mutation'',0));');
 d:=replace(d,'r.status=''closed'') THEN','r.status IN(''closed'',''approved'')) THEN');
 d:=replace(d,'PERFORM public.pdc_capture_tune_operation_changes_20260912(v_preview.batch_id,v_apply_batch);',
  'PERFORM public.pdc_capture_tune_operation_changes_20260912(v_preview.batch_id,v_apply_batch);
   v_response:=v_response||jsonb_build_object(
    ''operation_updates_auto_approved'',(SELECT count(*) FROM public.pdc_tune_operation_change_reviews q WHERE q.batch_id=v_apply_batch AND q.automation_result->>''ok''=''true''),
    ''operation_updates_for_review'',(SELECT count(*) FROM public.pdc_tune_operation_change_reviews q WHERE q.status=''pending'' AND q.vehicle_id IN(SELECT vehicle_id FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id)));
   UPDATE public.pdc_pilbara_service_import_batches SET response=v_response WHERE batch_id=v_apply_batch;');
 EXECUTE d;
END $patch$;
NOTIFY pgrst,'reload schema';

-- Track the separate accepted-operation exception page through the same staff policy.
CREATE OR REPLACE FUNCTION pdc_usage_private.record_usage(p_batch_id uuid, p_page text, p_clicks integer, p_visit boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  u uuid := auth.uid();
  s uuid;
  n integer;
  activity_at timestamptz := now();
begin
  if u is null or not exists (
    select 1 from public.pdc_user_roles
    where auth_user_id = u and email = lower(auth.jwt()->>'email')
      and active and account_status = 'approved'
      and role in ('viewer','operator','importer','administrator','fitter','salesperson')
  ) then
    raise exception 'Approved staff access required' using errcode = '42501';
  end if;
  s := (auth.jwt()->>'session_id')::uuid;
  if s is null or not exists (
    select 1 from auth.sessions
    where id = s and user_id = u and (not_after is null or not_after > activity_at)
  ) then
    raise exception 'Valid sign-in session required' using errcode = '42501';
  end if;
  if p_batch_id is null or p_clicks is null or p_clicks not between 0 and 200
      or p_visit is null or p_page is null or p_page not in (
        'dashboard','qc','workflow','planner-bus-4x4','planner-tint',
        'planner-hoist','planner-fitting','planner-fab','planner-elec',
        'planner-tyre','parts','sublet','user-management','lists','import',
        'backup','deleted','collected','completed','backend','newvehicles','operationupdates',
        'emailreview','ai-auditor','fitters','update-history','workshop',
        'visibility','tv','schedule','department','rft','zpl',
        'sales-myday','sales-dashboard','sales-pipeline','sales-customeremails',
        'sales-alerts','sales-finance','sales-finance-statistics',
        'sales-finance-applications','sales-labels','sales-history','other'
      ) then
    raise exception 'Invalid usage batch' using errcode = '22023';
  end if;
  if exists (
    select 1 from pdc_usage_private.events where user_id = u and batch_id = p_batch_id
  ) then
    return jsonb_build_object('ok',true,'replay',true);
  end if;
  select count(*) into n from pdc_usage_private.events
  where user_id = u and recorded_at > activity_at - interval '1 hour';
  if n >= 300 then
    return jsonb_build_object('ok',false,'code','usage_rate_limit');
  end if;

  -- Only the transaction that inserts the batch may update session activity.
  -- The earlier replay lookup alone would not cover concurrent duplicate calls.
  insert into pdc_usage_private.events(user_id,batch_id,page,visits,clicks)
  values (u,p_batch_id,p_page,p_visit::integer,p_clicks)
  on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then
    return jsonb_build_object('ok',true,'replay',true);
  end if;

  insert into pdc_usage_private.sessions as existing(user_id,session_id,last_active_at)
  values (u,s,case when p_visit or p_clicks > 0 then activity_at end)
  on conflict (user_id,session_id) do update
    set last_active_at = greatest(existing.last_active_at,excluded.last_active_at)
    where excluded.last_active_at is not null;

  delete from pdc_usage_private.events
  where recorded_at < activity_at - interval '180 days';
  -- An old sign-in can still be in use; retain its presence until activity ages out.
  delete from pdc_usage_private.sessions
  where first_seen_at < activity_at - interval '180 days'
    and coalesce(last_active_at,first_seen_at) < activity_at - interval '180 days';
  return jsonb_build_object('ok',true);
end $function$
;
