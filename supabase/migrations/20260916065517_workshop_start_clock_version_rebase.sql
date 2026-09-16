-- Only an automatic workshop clock movement may rebase a Start request.
-- Other actions and unproven stale versions retain optimistic concurrency checks.
-- The caller holds the workshop mutation lock and the selected booking row lock.
CREATE OR REPLACE FUNCTION pdc_fitter_private.clock_start_version(p_booking_id uuid,p_expected_version integer)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE b public.workshop_bookings; h record; prior jsonb; first_before jsonb;
 n integer:=0; expected integer:=p_expected_version; cutoff timestamptz;
 allowed text[]:=ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at'];
BEGIN
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 IF NOT FOUND OR b.deleted_at IS NOT NULL OR b.status<>'planned' OR b.actual_start_at IS NOT NULL
 OR p_expected_version IS NULL OR p_expected_version>=b.version OR b.version-p_expected_version>10 THEN RETURN NULL; END IF;
 FOR h IN SELECT before_data,after_data,created_at FROM public.workshop_clock_history
  WHERE booking_id=b.id AND actor_kind='automatic_workshop_clock'
   AND (before_data->>'version')::integer>=p_expected_version
   AND (after_data->>'version')::integer<=b.version
  ORDER BY (before_data->>'version')::integer,id LOOP
  -- Clock workers and browsers can serialize the same timestamp in UTC or Perth.
  -- Compare typed booking rows, preserving every field while normalizing zones.
  h.before_data:=to_jsonb(jsonb_populate_record(NULL::public.workshop_bookings,h.before_data));
  h.after_data:=to_jsonb(jsonb_populate_record(NULL::public.workshop_bookings,h.after_data));
  IF h.created_at<clock_timestamp()-interval '10 minutes'
    OR (h.before_data->>'version')::integer<>expected
    OR (h.after_data->>'version')::integer<>expected+1
    OR h.before_data-allowed IS DISTINCT FROM h.after_data-allowed
    OR (prior IS NOT NULL AND prior IS DISTINCT FROM h.before_data)
    OR h.before_data->>'id' IS DISTINCT FROM b.id::text THEN RETURN NULL; END IF;
  IF first_before IS NULL THEN first_before:=h.before_data; END IF;
  prior:=h.after_data; expected:=expected+1; n:=n+1;
 END LOOP;
 IF n<>b.version-p_expected_version OR expected<>b.version OR prior IS DISTINCT FROM to_jsonb(b) THEN RETURN NULL; END IF;
 -- Keep default technician/capacity fixed while this proof and Start run.
 PERFORM 1 FROM public.vehicles WHERE id=b.vehicle_id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_bays WHERE id=b.bay_id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE booking_id=b.id ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=b.vehicle_id ORDER BY adjustment_id FOR UPDATE NOWAIT;
 cutoff:=(first_before->>'updated_at')::timestamptz;
 IF cutoff IS NULL THEN RETURN NULL; END IF;
 -- Assignment APIs increment the booking version and therefore break the chain.
 -- Also reject newly assigned/released technicians and changed bay defaults,
 -- which are related resources outside the booking's own version counter.
 IF EXISTS(SELECT 1 FROM public.workshop_bays bay WHERE bay.id=b.bay_id AND bay.updated_at>cutoff)
 OR EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id
   AND (a.assigned_at>cutoff OR a.released_at>cutoff))
 OR EXISTS(SELECT 1 FROM public.workshop_booking_history bh WHERE bh.booking_id=b.id AND bh.created_at>cutoff)
 THEN RETURN NULL; END IF;
 -- Reconcile with authoritative operation hours. Any work-scope update since
 -- that version is conservative: require the caller to refresh, even if its
 -- total hours happen to be unchanged.
 IF public.workshop_vehicle_stage_estimated_duration_minutes(b.vehicle_id,b.stage_id)
    IS DISTINCT FROM b.capacity_estimate_minutes
 OR EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=b.vehicle_id AND v.updated_at>cutoff)
 OR EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments a WHERE a.vehicle_id=b.vehicle_id AND a.updated_at>cutoff)
 OR EXISTS(SELECT 1 FROM public.pdc_authenticated_email_operation_lines o WHERE o.vehicle_id=b.vehicle_id AND o.created_at>cutoff)
 OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=b.vehicle_id AND (
   o.created_at>cutoff
   OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operation_history oh WHERE oh.operation_id=o.operation_id AND oh.created_at>cutoff)
   OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_classification_current c WHERE c.operation_id=o.operation_id AND c.updated_at>cutoff)
   OR EXISTS(SELECT 1 FROM public.pdc_tune_operation_change_reviews cr WHERE cr.source_operation_id=o.operation_id AND cr.approved_at>cutoff)))
 THEN RETURN NULL; END IF;
 RETURN b.version;
EXCEPTION WHEN lock_not_available THEN
 -- Scope writers can lock vehicle before booking. Never wait in the reverse
 -- order: preserve the version conflict and require a fresh request instead.
 RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION pdc_fitter_private.clock_start_version(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.start_workshop_work(p_booking_id uuid,p_expected_version integer,
 p_actual_start_at timestamptz DEFAULT now(),p_metadata jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE v integer:=p_expected_version; current_version integer; r jsonb; metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
BEGIN
 PERFORM public.workshop_require_planner_operator();
 PERFORM public.workshop_require_version(p_expected_version);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT version INTO current_version FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF current_version<>p_expected_version THEN
  v:=coalesce(pdc_fitter_private.clock_start_version(p_booking_id,p_expected_version),p_expected_version);
  IF v<>p_expected_version THEN metadata:=metadata||jsonb_build_object('clock_rebased_from_version',p_expected_version); END IF;
 END IF;
 r:=public.start_workshop_work_pre345(p_booking_id,v,p_actual_start_at,metadata);
 IF coalesce((r->>'ok')::boolean,false) AND v<>p_expected_version THEN
  r:=r||jsonb_build_object('clock_rebased',true,'clock_rebased_from_version',p_expected_version);
 END IF;
 RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN
   IF p_action='start' THEN
     clock_version:=pdc_fitter_private.clock_start_version(b.id,p_expected_version);
     IF clock_version IS NOT NULL THEN
       d:=public.get_fitter_job(p_technician_id,b.id);
       IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN
         RETURN jsonb_build_object('ok',false,'error','scope_changed');
       END IF;
     END IF;
   END IF;
   IF clock_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id,'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp();
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'clock_rebased',clock_version IS NOT NULL,
    'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END,
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$
;
