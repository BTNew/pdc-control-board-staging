-- r424 (F38): stopped jobs can be re-planned, a job that runs into its own next stage offers to push that stage back,
-- and planners can re-order or swap upcoming jobs within any bay (preview, apply in one transaction, undo).
-- Bhavesh, 21 Oct 2026 (Key 516 on stoppage for super single rims and tyres; Key 799 to go ahead in Bus 4x4 Bay 1).
-- Causes: (1) "Return to Unallocated" with STOPPAGE keeps the booking in status stoppage with no bay; r415 only
-- resumed status queued, so the drag back into Bay 1 was refused (protected_booking) and Schedule refused
-- (active_booking_exists). (2) Booked after 799, 516's remaining Mechanical hours run past its Electrical booking in
-- Bay 8 (2 Nov), which the board refused as vehicle_overlap. (3) Moves inside one bay need an empty slot
-- ("bay already occupied"); there was no way to re-order. Staging only. Undo: supabase/rollbacks/<this name>.down.sql
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r424: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r424: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r424: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure)<>'0f5bff8fba5c0a3385609c893a5edc44'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_resume_returned_booking_415(uuid,integer,text)'::regprocedure)<>'870cd66b8511239f449defc8615686ee'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_return_booking_to_queue(uuid,integer,text,jsonb)'::regprocedure)<>'1362a701f22974e774e489ca97b9857e'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_enforce_booking_lifecycle()'::regprocedure)<>'94230674500701543bcaf93e58158a54'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_enforce_booking_validation()'::regprocedure)<>'78d71792f08c56acfe9f6fcfcc27838c'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.add_minutes(timestamp with time zone,integer,uuid)'::regprocedure)<>'c43afa5c1312392aa5d3666a8aa7cf65'
 THEN RAISE EXCEPTION 'r424: a function changed since the release was prepared'; END IF;
 IF to_regnamespace('pdc_bay_seq_private') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_resequence_and_stopped_replan' OR added_in='r424')
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r424') THEN RAISE EXCEPTION 'r424: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=225) THEN RAISE EXCEPTION 'r424: sort_order 225 taken'; END IF;
END $g$;

CREATE SCHEMA pdc_bay_seq_private;
REVOKE ALL ON SCHEMA pdc_bay_seq_private FROM PUBLIC, anon, authenticated;

-- One row per applied re-order, push-back or undo: who, when, what changed (before and after), for the undo.
CREATE TABLE pdc_bay_seq_private.receipts(
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 request_id uuid NOT NULL,
 actor_id uuid NOT NULL,
 actor_email text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 operation text NOT NULL CHECK (operation IN ('resequence','push_later','undo')),
 bay_id uuid,
 booking_id uuid,
 target_booking_id uuid,
 mode text,
 plan_hash text,
 changes jsonb NOT NULL,
 before_rows jsonb NOT NULL,
 after_rows jsonb NOT NULL,
 result jsonb,
 undone_at timestamptz,
 undone_by uuid,
 undo_receipt_id uuid,
 UNIQUE (actor_id, request_id)
);
ALTER TABLE pdc_bay_seq_private.receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_bay_seq_private.receipts FROM PUBLIC, anon, authenticated;

-- A stopped job taken off stoppage so it can be re-planned: the stoppage it had is kept here (and in its history).
CREATE TABLE pdc_bay_seq_private.stopped_requeue(
 id bigserial PRIMARY KEY,
 booking_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 bay_id_before uuid,
 stoppage_reason text,
 stoppage_started_at timestamptz,
 stoppage_accumulated_before integer,
 stoppage_minutes_added integer,
 returned_to_queue_at_before timestamptz,
 booking_version_before integer,
 actor_id uuid,
 actor_email text,
 source text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_bay_seq_private.stopped_requeue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_bay_seq_private.stopped_requeue FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE pdc_bay_seq_private.stopped_requeue_id_seq FROM PUBLIC, anon, authenticated;

-- First working minute at or after p_at in this bay (Bus 4x4 shift hours, otherwise the workshop calendar).
CREATE FUNCTION pdc_bay_seq_private.next_start(p_at timestamptz, p_bay uuid) RETURNS timestamptz
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE t timestamptz:=date_trunc('minute',p_at);
BEGIN
 IF p_at IS NULL THEN RETURN NULL; END IF;
 IF t<p_at THEN t:=t+interval '1 minute'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay AND s.code='BUS_4X4') THEN
  IF pdc_bus_private.minute_available(t,p_bay) THEN RETURN t; END IF;
  RETURN pdc_bus_private.add_minutes(t,1,p_bay)-interval '1 minute';
 END IF;
 RETURN public.workshop_admin_next_operational_minute(t);
END $f$;

-- End of p_minutes working minutes from p_start in this bay.
CREATE FUNCTION pdc_bay_seq_private.end_at(p_start timestamptz, p_minutes integer, p_bay uuid) RETURNS timestamptz
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
BEGIN
 IF EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay AND s.code='BUS_4X4') THEN
  RETURN pdc_bus_private.add_minutes(p_start,greatest(p_minutes,0),p_bay);
 END IF;
 RETURN public.workshop_add_operational_minutes(p_start,greatest(p_minutes,0));
END $f$;

-- The booking's own planned minutes in a bay: what the board books (capacity basis) and what it shows (effective).
CREATE FUNCTION pdc_bay_seq_private.minutes(p_booking_id uuid, p_bay uuid) RETURNS integer
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
 SELECT coalesce(public.workshop_booking_capacity_duration_minutes(b.id,b.vehicle_id,b.stage_id,p_bay),public.workshop_booking_effective_duration_minutes(b.id),b.default_duration_minutes)
 FROM public.workshop_bookings b WHERE b.id=p_booking_id
$f$;

-- The working plan for one call (transaction-local).
CREATE FUNCTION pdc_bay_seq_private.p_init() RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
BEGIN
 CREATE TEMP TABLE IF NOT EXISTS r424_p(
  id uuid PRIMARY KEY, vehicle_id uuid NOT NULL, stage_id uuid, bay_id uuid, cur_bay uuid, status text,
  kind text NOT NULL, prio integer NOT NULL, ord integer,
  cur_start timestamptz, cur_end timestamptz, new_start timestamptz, new_end timestamptz, want_start timestamptz,
  dur integer, version integer, changed boolean NOT NULL DEFAULT false, resumed boolean NOT NULL DEFAULT false,
  loaded boolean NOT NULL DEFAULT false, pending boolean NOT NULL DEFAULT false) ON COMMIT DROP;
 TRUNCATE r424_p;
END $f$;

-- Pull in every live booking that shares a bay or a vehicle with a booking the plan moves or pins.
-- planned and not started = can be pushed back; started / on stoppage = fixed (keeps its actual times).
CREATE FUNCTION pdc_bay_seq_private.p_load() RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE n integer;
BEGIN
 INSERT INTO pg_temp.r424_p(id,vehicle_id,stage_id,bay_id,cur_bay,status,kind,prio,cur_start,cur_end,new_start,new_end,dur,version)
 SELECT b.id,b.vehicle_id,b.stage_id,b.bay_id,b.bay_id,b.status::text,
  CASE WHEN b.status='planned' AND b.actual_start_at IS NULL THEN 'move' ELSE 'fixed' END,
  CASE WHEN b.status='planned' AND b.actual_start_at IS NULL THEN 2 ELSE 0 END,
  b.scheduled_start_at,e.e,b.scheduled_start_at,e.e,
  CASE WHEN b.status='planned' AND b.actual_start_at IS NULL THEN pdc_bay_seq_private.minutes(b.id,b.bay_id) END,b.version
 FROM public.workshop_bookings b CROSS JOIN LATERAL (SELECT public.workshop_booking_effective_end_at(b.id) e) e
 WHERE b.deleted_at IS NULL AND b.status IN ('planned','started','stoppage') AND b.bay_id IS NOT NULL AND e.e>clock_timestamp()
  AND (b.bay_id IN (SELECT p.bay_id FROM pg_temp.r424_p p WHERE (p.changed OR p.kind IN ('seed','pin')) AND NOT p.loaded)
    OR b.vehicle_id IN (SELECT p.vehicle_id FROM pg_temp.r424_p p WHERE (p.changed OR p.kind IN ('seed','pin')) AND NOT p.loaded))
 ON CONFLICT (id) DO NOTHING;
 GET DIAGNOSTICS n=ROW_COUNT;
 UPDATE pg_temp.r424_p SET loaded=true WHERE (changed OR kind IN ('seed','pin')) AND NOT loaded;
 RETURN n;
END $f$;

-- Push bookings back until nothing overlaps: one job at a time per bay, and a vehicle's later stage starts at least
-- 60 working minutes after its earlier stage ends (the board's hand-over gap). Only bookings that are planned and not
-- started move, and only later. Started, stopped and pinned bookings never move.
CREATE FUNCTION pdc_bay_seq_private.p_close() RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE i integer:=0; r record; v_s timestamptz;
BEGIN
 LOOP
  i:=i+1;
  IF i>800 THEN RETURN jsonb_build_object('ok',false,'error','resequence_too_large'); END IF;
  PERFORM pdc_bay_seq_private.p_load();
  SELECT * INTO r FROM (
   SELECT 'bay' t,p1.id a,p2.id b,p1.kind ak,p2.kind bk,p1.new_end a_end,p2.new_end b_end,p1.bay_id a_bay,p2.bay_id b_bay,greatest(p1.new_start,p2.new_start) at_
   FROM pg_temp.r424_p p1 JOIN pg_temp.r424_p p2 ON p1.bay_id=p2.bay_id AND p1.id<>p2.id
   WHERE p1.new_start<p2.new_end AND p2.new_start<p1.new_end
    AND (p1.new_start,p1.prio,p1.id::text)<(p2.new_start,p2.prio,p2.id::text)
    AND NOT (p1.kind IN ('fixed','pin') AND p2.kind IN ('fixed','pin'))
   UNION ALL
   SELECT 'vehicle',p1.id,p2.id,p1.kind,p2.kind,p1.new_end,p2.new_end,p1.bay_id,p2.bay_id,greatest(p1.new_start,p2.new_start)
   FROM pg_temp.r424_p p1 JOIN pg_temp.r424_p p2 ON p1.vehicle_id=p2.vehicle_id AND p1.id<>p2.id
   WHERE (coalesce(p1.cur_start,p1.new_start),p1.id::text)<(coalesce(p2.cur_start,p2.new_start),p2.id::text)
    AND NOT (p1.kind IN ('fixed','pin') AND p2.kind IN ('fixed','pin'))
    AND (p1.changed OR p2.changed OR p1.kind IN ('pin','seed') OR p2.kind IN ('pin','seed'))
    AND p2.new_start<pdc_bay_seq_private.end_at(p1.new_end,60,p2.bay_id)
  ) c ORDER BY at_,t LIMIT 1;
  EXIT WHEN NOT FOUND;
  IF r.bk NOT IN ('fixed','pin') THEN
   v_s:=pdc_bay_seq_private.next_start(CASE WHEN r.t='bay' THEN r.a_end ELSE pdc_bay_seq_private.end_at(r.a_end,60,r.b_bay) END,r.b_bay);
   UPDATE pg_temp.r424_p SET new_start=v_s,new_end=pdc_bay_seq_private.end_at(v_s,dur,bay_id),changed=true WHERE id=r.b;
  ELSIF r.ak NOT IN ('fixed','pin') THEN
   v_s:=pdc_bay_seq_private.next_start(CASE WHEN r.t='bay' THEN r.b_end ELSE pdc_bay_seq_private.end_at(r.b_end,60,r.a_bay) END,r.a_bay);
   UPDATE pg_temp.r424_p SET new_start=v_s,new_end=pdc_bay_seq_private.end_at(v_s,dur,bay_id),changed=true WHERE id=r.a;
  END IF;
 END LOOP;
 UPDATE pg_temp.r424_p SET changed=true WHERE kind='seed' AND (cur_start IS NULL OR new_start<>cur_start OR bay_id IS DISTINCT FROM cur_bay);
 UPDATE pg_temp.r424_p SET changed=false WHERE kind='move' AND changed AND new_start=cur_start AND bay_id IS NOT DISTINCT FROM cur_bay;
 RETURN jsonb_build_object('ok',true,'steps',i);
END $f$;

-- Place a list of bookings one after another in a bay, from p_anchor (or each one's wanted start, if later),
-- stepping over started and stopped jobs, which keep their times.
CREATE FUNCTION pdc_bay_seq_private.p_place_sequence(p_bay uuid, p_anchor timestamptz) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE r record; v_cursor timestamptz:=p_anchor; v_s timestamptz; v_e timestamptz; f record; n integer;
BEGIN
 FOR r IN SELECT * FROM pg_temp.r424_p WHERE kind='seed' AND bay_id=p_bay ORDER BY ord LOOP
  v_s:=pdc_bay_seq_private.next_start(greatest(v_cursor,coalesce(r.want_start,v_cursor)),p_bay);
  n:=0;
  LOOP
   n:=n+1; IF n>200 THEN RAISE EXCEPTION 'r424: no room found in the bay' USING errcode='22023'; END IF;
   v_e:=pdc_bay_seq_private.end_at(v_s,r.dur,p_bay);
   SELECT * INTO f FROM pg_temp.r424_p x WHERE x.bay_id=p_bay AND x.kind='fixed' AND x.new_start<v_e AND v_s<x.new_end ORDER BY x.new_end DESC LIMIT 1;
   EXIT WHEN NOT FOUND;
   v_s:=pdc_bay_seq_private.next_start(f.new_end,p_bay);
  END LOOP;
  UPDATE pg_temp.r424_p SET new_start=v_s,new_end=v_e WHERE id=r.id;
  v_cursor:=v_e;
 END LOOP;
END $f$;

-- What the plan changes, in plain terms (no customer details).
CREATE FUNCTION pdc_bay_seq_private.p_changes(p_exclude uuid DEFAULT NULL) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
BEGIN
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',p.id,'vehicle_id',p.vehicle_id,'key_number',v.key_number,
   'work_category',b.work_category,'bay_number',bay.bay_number,'stage_code',s.code,'kind',p.kind,'resumed',p.resumed,
   'from_start',p.cur_start,'from_end',p.cur_end,'to_start',p.new_start,'to_end',p.new_end,'minutes',p.dur,
   'shift_minutes',CASE WHEN p.cur_start IS NOT NULL THEN round(extract(epoch FROM p.new_start-p.cur_start)/60)::integer END)
   ORDER BY bay.bay_number,p.new_start,p.id),'[]'::jsonb)
 FROM pg_temp.r424_p p JOIN public.workshop_bookings b ON b.id=p.id JOIN public.vehicles v ON v.id=p.vehicle_id
 LEFT JOIN public.workshop_bays bay ON bay.id=p.bay_id LEFT JOIN public.workshop_stages s ON s.id=bay.stage_id
 WHERE p.changed AND p.id IS DISTINCT FROM p_exclude);
END $f$;

CREATE FUNCTION pdc_bay_seq_private.p_hash(p_exclude uuid DEFAULT NULL) RETURNS text
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
BEGIN
 RETURN (SELECT md5(coalesce(string_agg(p.id::text||':'||coalesce(p.bay_id::text,'-'),',' ORDER BY p.bay_id,p.new_start,p.id),''))
 FROM pg_temp.r424_p p WHERE p.changed AND p.id IS DISTINCT FROM p_exclude);
END $f$;

-- r424 (F38): a job that was started and then put on STOPPAGE (in its bay or returned to Unallocated) can be re-planned.
-- The stoppage is ended the same way the board returns a job to the queue (single-use return_to_queue authorisation),
-- the stopped time is added to the job's stoppage minutes (it is not worked time), the reason is kept here, in the
-- booking metadata (pdc_requeue_424) and in history, and then r415 resumes it: time worked is kept, only the
-- remaining hours are booked. The job is not placed here; the caller places it.
CREATE FUNCTION pdc_bay_seq_private.requeue_stopped(p_booking_id uuid, p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE b public.workshop_bookings%rowtype; v_ret jsonb; v_res jsonb; v_added integer; v_before jsonb; v_after jsonb; v_entry jsonb; v_now timestamptz;
 v_park timestamptz; v_park_end timestamptz;
BEGIN
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND OR NOT (b.deleted_at IS NULL AND b.status='stoppage' AND b.actual_start_at IS NOT NULL AND b.actual_end_at IS NULL) THEN
  RETURN jsonb_build_object('ok',false,'error','protected_booking');
 END IF;
 v_before:=public.workshop_booking_snapshot(b.id);
 -- While it waits in Unallocated the job reserves nothing. Its old booked window (bus shift hours) is parked after
 -- the vehicle's other bookings on the plain workshop calendar, so the queue checks see no overlap; the caller then
 -- books the remaining hours at the chosen place. The old window is kept in history and pdc_requeue_424.
 SELECT public.workshop_admin_next_operational_minute(greatest(clock_timestamp(),coalesce(max(public.workshop_booking_effective_end_at(o.id)),clock_timestamp()))+interval '1 day')
 INTO v_park FROM public.workshop_bookings o
 WHERE o.vehicle_id=b.vehicle_id AND o.id<>b.id AND o.deleted_at IS NULL AND o.status IN ('queued','planned','started','stoppage');
 v_park_end:=public.workshop_add_operational_minutes(v_park,b.default_duration_minutes);
 IF b.bay_id IS NULL THEN
  UPDATE public.workshop_bookings SET scheduled_start_at=v_park,scheduled_end_at=v_park_end,version=version+1,
    updated_by=coalesce(auth.uid(),updated_by),updated_at=clock_timestamp() WHERE id=b.id;
  b.version:=b.version+1;
 END IF;
 INSERT INTO public.workshop_transition_authorizations(txid,booking_id,transition,authorized_by)
 VALUES(txid_current(),b.id,'return_to_queue',auth.uid());
 v_ret:=public.workshop_return_booking_to_queue(b.id,b.version,NULL,jsonb_build_object('source',p_source,'release','r424','reason','re-planned after a stoppage'));
 IF coalesce((v_ret->>'ok')::boolean,false) IS NOT TRUE THEN RETURN v_ret; END IF;
 SELECT returned_to_queue_at INTO v_now FROM public.workshop_bookings WHERE id=b.id;
 v_added:=greatest(0,coalesce(public.workshop_operational_minutes_between(coalesce(b.stoppage_started_at,v_now),v_now),0));
 v_entry:=jsonb_build_object('stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
   'stoppage_minutes_added',v_added,'bay_id_before',b.bay_id,'returned_to_queue_at_before',b.returned_to_queue_at,
   'requeued_at',v_now,'requeued_by',auth.uid(),'source',p_source);
 v_entry:=v_entry||jsonb_build_object('scheduled_start_before',b.scheduled_start_at,'scheduled_end_before',b.scheduled_end_at);
 UPDATE public.workshop_bookings w SET stoppage_accumulated_minutes=coalesce(w.stoppage_accumulated_minutes,0)+v_added,
   scheduled_start_at=v_park,scheduled_end_at=v_park_end,
   metadata=coalesce(w.metadata,'{}'::jsonb)||jsonb_build_object('pdc_requeue_424',
     CASE WHEN jsonb_typeof(w.metadata->'pdc_requeue_424')='array' THEN w.metadata->'pdc_requeue_424' ELSE '[]'::jsonb END||jsonb_build_array(v_entry)),
   version=w.version+1,updated_by=coalesce(auth.uid(),w.updated_by),updated_at=clock_timestamp()
 WHERE w.id=b.id;
 INSERT INTO pdc_bay_seq_private.stopped_requeue(booking_id,vehicle_id,bay_id_before,stoppage_reason,stoppage_started_at,stoppage_accumulated_before,
   stoppage_minutes_added,returned_to_queue_at_before,booking_version_before,actor_id,actor_email,source)
 VALUES(b.id,b.vehicle_id,b.bay_id,b.stoppage_reason,b.stoppage_started_at,b.stoppage_accumulated_minutes,v_added,b.returned_to_queue_at,b.version,
   auth.uid(),public.current_actor_email(),p_source);
 v_after:=public.workshop_booking_snapshot(b.id);
 PERFORM public.workshop_write_history(b.id,'stoppage_ended_for_replan',v_before,v_after,v_entry||jsonb_build_object('release','r424'));
 v_res:=public.workshop_resume_returned_booking_415(b.id,(SELECT version FROM public.workshop_bookings WHERE id=b.id),p_source);
 IF coalesce((v_res->>'ok')::boolean,false) IS NOT TRUE THEN RETURN v_res; END IF;
 RETURN v_res||jsonb_build_object('stoppage_minutes_added',v_added,'stoppage_reason',b.stoppage_reason);
END $f$;

-- Put one booking at its planned place. A planned job is shifted like the existing bay cascade does (same checks,
-- same assignment update); a resumed job is booked through move_workshop_booking (the normal re-plan path).
CREATE FUNCTION pdc_bay_seq_private.place(p_booking_id uuid, p_bay uuid, p_start timestamptz, p_minutes integer, p_metadata jsonb) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE b public.workshop_bookings%rowtype; v_tech uuid; v_res jsonb; v_code text; v_bay_number integer; v_end timestamptz;
BEGIN
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF b.status='queued' AND b.bay_id IS NULL THEN
  SELECT s.code,bay.bay_number INTO v_code,v_bay_number FROM public.workshop_bays bay JOIN public.workshop_stages s ON s.id=bay.stage_id WHERE bay.id=p_bay;
  v_res:=public.move_workshop_booking(b.id,b.version,v_code,v_bay_number,p_start,p_minutes,
    CASE WHEN public.workshop_parts_ready(b.vehicle_id) THEN NULL ELSE 'Re-planned after a stoppage (r424); parts unchanged' END,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('resequence_424',true));
  IF coalesce((v_res->>'ok')::boolean,false) IS NOT TRUE THEN
   RAISE EXCEPTION 'r424: booking % could not be placed: %',left(b.id::text,8),v_res::text USING errcode='22023';
  END IF;
  RETURN;
 END IF;
 IF NOT (b.status='planned' AND b.actual_start_at IS NULL AND b.deleted_at IS NULL AND b.bay_id=p_bay) THEN
  RAISE EXCEPTION 'r424: booking % is no longer a planned job in this bay',left(b.id::text,8) USING errcode='22023';
 END IF;
 UPDATE public.workshop_bookings SET scheduled_start_at=p_start,
   scheduled_end_at=pdc_bay_seq_private.end_at(p_start,p_minutes,p_bay),
   default_duration_minutes=p_minutes,updated_by=auth.uid(),version=version+1
 WHERE id=b.id;
 SELECT scheduled_end_at INTO v_end FROM public.workshop_bookings WHERE id=b.id;
 SELECT a.technician_id INTO v_tech FROM public.workshop_booking_assignments a
 WHERE a.booking_id=b.id AND a.released_at IS NULL ORDER BY CASE WHEN a.assignment_type='primary' THEN 0 ELSE 1 END,a.assigned_at DESC LIMIT 1;
 PERFORM public.workshop_upsert_primary_assignment(b.id,v_tech,p_start,v_end,'bay_resequenced_424');
END $f$;

-- Apply the plan in one go. Every ordinary booking check stays on, so the order of writes matters: a booking is
-- moved only when its new time is free; if two bookings need each other's place (a swap), one is first parked well
-- after everything else in its own bay, then put in its final place. Returns before/after rows for the receipt.
CREATE FUNCTION pdc_bay_seq_private.p_apply(p_metadata jsonb, p_event text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE r record; v_park timestamptz; v_n integer:=0; v_before jsonb; v_after jsonb; v_snap jsonb; v_s timestamptz; v_e timestamptz; v_bad integer;
BEGIN
 PERFORM 1 FROM public.workshop_bookings b WHERE b.id IN (SELECT id FROM pg_temp.r424_p WHERE changed) ORDER BY b.id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM pg_temp.r424_p p JOIN public.workshop_bookings b ON b.id=p.id WHERE p.changed AND b.version<>p.version) THEN
  RETURN jsonb_build_object('ok',false,'error','concurrent_queue_change','retry',true);
 END IF;
 IF EXISTS(SELECT 1 FROM pg_temp.r424_p WHERE changed AND kind NOT IN ('move','seed')) THEN
  RETURN jsonb_build_object('ok',false,'error','started_job_fixed');
 END IF;
 CREATE TEMP TABLE IF NOT EXISTS r424_snap(id uuid PRIMARY KEY, before jsonb) ON COMMIT DROP;
 TRUNCATE r424_snap;
 INSERT INTO r424_snap SELECT id,public.workshop_booking_snapshot(id) FROM pg_temp.r424_p WHERE changed;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'vehicle_id',b.vehicle_id,'bay_id',b.bay_id,'status',b.status,'start',b.scheduled_start_at,
   'end',b.scheduled_end_at,'version',b.version,'actual_start_at',b.actual_start_at,'stoppage_reason',b.stoppage_reason) ORDER BY b.id),'[]'::jsonb)
 INTO v_before FROM public.workshop_bookings b WHERE b.id IN (SELECT id FROM pg_temp.r424_p WHERE changed);
 UPDATE pg_temp.r424_p SET pending=changed WHERE true; -- r424b (20261021013136) applied this WHERE on staging; the text applied here ended before it
 SELECT max(greatest(new_end,coalesce(cur_end,new_end)))+interval '120 days' INTO v_park FROM pg_temp.r424_p;
 LOOP
  EXIT WHEN NOT EXISTS(SELECT 1 FROM pg_temp.r424_p WHERE pending);
  v_n:=v_n+1;
  IF v_n>2000 THEN RAISE EXCEPTION 'r424: plan could not be applied' USING errcode='22023'; END IF;
  SELECT p.* INTO r FROM pg_temp.r424_p p WHERE p.pending AND NOT EXISTS(
    SELECT 1 FROM pg_temp.r424_p q WHERE q.pending AND q.id<>p.id AND q.cur_start IS NOT NULL AND q.cur_bay IS NOT NULL
     AND (q.cur_bay=p.bay_id OR q.vehicle_id=p.vehicle_id) AND q.cur_start<p.new_end AND p.new_start<q.cur_end)
  ORDER BY p.new_start DESC,p.id LIMIT 1;
  IF FOUND THEN
   PERFORM pdc_bay_seq_private.place(r.id,r.bay_id,r.new_start,r.dur,p_metadata);
   UPDATE pg_temp.r424_p SET pending=false,cur_start=new_start,cur_end=new_end,cur_bay=bay_id WHERE id=r.id;
  ELSE
   SELECT p.* INTO r FROM pg_temp.r424_p p WHERE p.pending AND p.cur_start IS NOT NULL AND p.cur_bay IS NOT NULL ORDER BY p.cur_start DESC,p.id LIMIT 1;
   IF NOT FOUND THEN RAISE EXCEPTION 'r424: plan could not be ordered' USING errcode='22023'; END IF;
   v_s:=pdc_bay_seq_private.next_start(v_park,r.cur_bay);
   PERFORM pdc_bay_seq_private.place(r.id,r.cur_bay,v_s,r.dur,p_metadata);
   v_e:=public.workshop_booking_effective_end_at(r.id);
   UPDATE pg_temp.r424_p SET cur_start=v_s,cur_end=v_e WHERE id=r.id;
   v_park:=v_e+interval '1 day';
  END IF;
 END LOOP;
 -- Final safety net: nothing the plan touched may overlap in its bay.
 SELECT count(*) INTO v_bad FROM public.workshop_bookings a JOIN public.workshop_bookings b2 ON a.bay_id=b2.bay_id AND a.id<>b2.id
 WHERE a.id IN (SELECT id FROM pg_temp.r424_p WHERE changed) AND b2.deleted_at IS NULL AND b2.status IN ('planned','started','stoppage')
  AND tstzrange(a.scheduled_start_at,public.workshop_booking_effective_end_at(a.id),'[)') && tstzrange(b2.scheduled_start_at,public.workshop_booking_effective_end_at(b2.id),'[)');
 IF v_bad>0 THEN RAISE EXCEPTION 'r424: the new order would overlap in a bay' USING errcode='22023'; END IF;
 FOR r IN SELECT p.id,s.before FROM pg_temp.r424_p p JOIN r424_snap s ON s.id=p.id WHERE p.changed LOOP
  v_snap:=public.workshop_booking_snapshot(r.id);
  PERFORM public.workshop_write_history(r.id,p_event,r.before,v_snap,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('release','r424'));
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'vehicle_id',b.vehicle_id,'bay_id',b.bay_id,'status',b.status,'start',b.scheduled_start_at,
   'end',b.scheduled_end_at,'version',b.version,'actual_start_at',b.actual_start_at,'stoppage_reason',b.stoppage_reason) ORDER BY b.id),'[]'::jsonb)
 INTO v_after FROM public.workshop_bookings b WHERE b.id IN (SELECT id FROM pg_temp.r424_p WHERE changed);
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true,'before_rows',v_before,'after_rows',v_after);
END $f$;

-- r424 (F38): re-order or swap the upcoming jobs in one bay. Drag a booking onto (or before) another booking in the
-- same bay and choose "Move ahead of" or "Swap with". The bay's upcoming jobs are then laid out again one after
-- another from the first upcoming start (never before now), each with its own hours and the bay's shift hours.
-- Started jobs keep their actual times and are stepped over. A stopped job that is moved (or that another job is
-- moved ahead of) is taken off stoppage and resumed (time worked kept). If a job then runs into the same vehicle's
-- next stage in another bay, that stage (and whatever follows it) is pushed back too; the preview lists every change.
-- p_apply=false only previews (nothing is saved). p_apply=true needs the plan_hash of the preview just shown and
-- applies everything in one transaction, with a receipt for workshop_undo_bay_resequence_424.
CREATE FUNCTION public.workshop_resequence_bay_424(p_booking_id uuid, p_expected_version integer, p_target_booking_id uuid,
 p_mode text, p_apply boolean, p_plan_hash text, p_metadata jsonb, p_request_id uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE x public.workshop_bookings%rowtype; y public.workshop_bookings%rowtype; v_bay uuid; v_ids uuid[]; v_order uuid[]; v_old uuid[];
 v_i integer; v_ix integer; v_iy integer; v_anchor timestamptz; v_out jsonb; v_hash text; v_apply jsonb; v_receipt uuid; v_conv uuid[]:='{}';
 v_existing pdc_bay_seq_private.receipts%rowtype; v_res jsonb; v_meta jsonb:=coalesce(p_metadata,'{}'::jsonb); c uuid;
BEGIN
 PERFORM pdc_planner_access_private.require_vehicle_planner();
 IF p_booking_id IS NULL OR p_target_booking_id IS NULL OR p_expected_version IS NULL OR p_request_id IS NULL
    OR p_mode IS NULL OR p_mode NOT IN ('ahead','swap','after') OR p_booking_id=p_target_booking_id THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_input');
 END IF;
 IF p_apply THEN
  SELECT * INTO v_existing FROM pdc_bay_seq_private.receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
  IF FOUND THEN RETURN v_existing.result||jsonb_build_object('idempotent_replay',true); END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:cascade-move',0));
 SELECT * INTO x FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','booking_not_found'); END IF;
 IF x.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 SELECT * INTO y FROM public.workshop_bookings WHERE id=p_target_booking_id FOR UPDATE;
 IF NOT FOUND OR x.bay_id IS NULL OR y.bay_id IS DISTINCT FROM x.bay_id OR x.deleted_at IS NOT NULL OR y.deleted_at IS NOT NULL THEN
  RETURN jsonb_build_object('ok',false,'error','not_same_bay');
 END IF;
 v_bay:=x.bay_id;
 IF x.status='started' OR (x.status='planned' AND x.actual_start_at IS NOT NULL) OR x.status NOT IN ('planned','stoppage') THEN
  RETURN jsonb_build_object('ok',false,'error','started_job_fixed');
 END IF;
 IF y.status NOT IN ('planned','stoppage') OR (y.status='planned' AND y.actual_start_at IS NOT NULL) THEN
  RETURN jsonb_build_object('ok',false,'error','started_job_fixed');
 END IF;
 PERFORM 1 FROM public.workshop_bookings b WHERE b.bay_id=v_bay AND b.deleted_at IS NULL AND b.status IN ('planned','started','stoppage') ORDER BY b.id FOR UPDATE;
 -- The bay's upcoming jobs in their current order (plus x or y if it is a stopped job being re-planned).
 SELECT array_agg(b.id ORDER BY b.scheduled_start_at,b.id) INTO v_old FROM public.workshop_bookings b
 WHERE b.bay_id=v_bay AND b.deleted_at IS NULL
  AND ((b.status='planned' AND b.actual_start_at IS NULL AND public.workshop_booking_effective_end_at(b.id)>clock_timestamp())
    OR b.id IN (x.id,y.id));
 v_ix:=array_position(v_old,x.id); v_iy:=array_position(v_old,y.id);
 v_order:=v_old;
 IF p_mode='swap' THEN
  v_order[v_ix]:=y.id; v_order[v_iy]:=x.id;
 ELSE
  v_order:=array_remove(v_old,x.id);
  v_i:=array_position(v_order,y.id);
  v_order:=CASE WHEN p_mode='ahead' THEN v_order[1:v_i-1]||x.id||v_order[v_i:] ELSE v_order[1:v_i]||x.id||v_order[v_i+1:] END;
 END IF;
 IF v_order=v_old THEN RETURN jsonb_build_object('ok',false,'error','order_unchanged'); END IF;
 BEGIN
  -- A stopped job only moves if it changes place in the order.
  FOREACH c IN ARRAY ARRAY[x.id,y.id] LOOP
   IF (SELECT status FROM public.workshop_bookings WHERE id=c)='stoppage' AND array_position(v_order,c)<>array_position(v_old,c) THEN
    v_res:=pdc_bay_seq_private.requeue_stopped(c,'bay_resequence');
    IF coalesce((v_res->>'ok')::boolean,false) IS NOT TRUE THEN v_out:=v_res; RAISE EXCEPTION USING errcode='P0424'; END IF;
    v_conv:=v_conv||c;
   END IF;
  END LOOP;
  PERFORM pdc_bay_seq_private.p_init();
  INSERT INTO pg_temp.r424_p(id,vehicle_id,stage_id,bay_id,cur_bay,status,kind,prio,ord,cur_start,cur_end,new_start,new_end,dur,version,resumed)
  SELECT b.id,b.vehicle_id,b.stage_id,v_bay,b.bay_id,b.status::text,
   CASE WHEN b.status='stoppage' THEN 'fixed' ELSE 'seed' END,CASE WHEN b.status='stoppage' THEN 0 ELSE 1 END,o.n,
   CASE WHEN b.bay_id IS NULL THEN NULL ELSE b.scheduled_start_at END,CASE WHEN b.bay_id IS NULL THEN NULL ELSE public.workshop_booking_effective_end_at(b.id) END,
   b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),pdc_bay_seq_private.minutes(b.id,v_bay),b.version,b.id=ANY(v_conv)
  FROM unnest(v_order) WITH ORDINALITY o(id,n) JOIN public.workshop_bookings b ON b.id=o.id;
  -- started (and untouched stopped) jobs in the bay are fixed
  INSERT INTO pg_temp.r424_p(id,vehicle_id,stage_id,bay_id,cur_bay,status,kind,prio,cur_start,cur_end,new_start,new_end,version)
  SELECT b.id,b.vehicle_id,b.stage_id,b.bay_id,b.bay_id,b.status::text,'fixed',0,b.scheduled_start_at,e.e,b.scheduled_start_at,e.e,b.version
  FROM public.workshop_bookings b CROSS JOIN LATERAL (SELECT public.workshop_booking_effective_end_at(b.id) e) e
  WHERE b.bay_id=v_bay AND b.deleted_at IS NULL AND b.status IN ('started','stoppage','planned') AND e.e>clock_timestamp()
   AND NOT (b.id=ANY(v_order))
  ON CONFLICT (id) DO NOTHING;
  UPDATE pg_temp.r424_p SET kind='fixed',prio=0 WHERE status='stoppage' AND NOT resumed;
  SELECT greatest(clock_timestamp(),min(b.scheduled_start_at)) INTO v_anchor FROM public.workshop_bookings b
  WHERE b.id=ANY(v_order) AND b.status='planned' AND b.actual_start_at IS NULL AND NOT (b.id=ANY(v_conv));
  v_anchor:=coalesce(v_anchor,clock_timestamp());
  PERFORM pdc_bay_seq_private.p_place_sequence(v_bay,v_anchor);
  v_res:=pdc_bay_seq_private.p_close();
  IF coalesce((v_res->>'ok')::boolean,false) IS NOT TRUE THEN v_out:=v_res; RAISE EXCEPTION USING errcode='P0424'; END IF;
  v_hash:=pdc_bay_seq_private.p_hash();
  v_out:=jsonb_build_object('ok',true,'preview',NOT p_apply,'plan_hash',v_hash,'mode',p_mode,'booking_id',x.id,'target_booking_id',y.id,
   'bay_number',(SELECT bay_number FROM public.workshop_bays WHERE id=v_bay),'changes',pdc_bay_seq_private.p_changes(),
   'other_bays',(SELECT count(*) FROM pg_temp.r424_p WHERE changed AND bay_id<>v_bay),'resumed_booking_ids',to_jsonb(v_conv));
  IF NOT p_apply THEN RAISE EXCEPTION USING errcode='P0424'; END IF;
  IF p_plan_hash IS DISTINCT FROM v_hash THEN
   v_out:=v_out||jsonb_build_object('ok',false,'error','plan_changed','preview',true); RAISE EXCEPTION USING errcode='P0424';
  END IF;
  v_apply:=pdc_bay_seq_private.p_apply(v_meta||jsonb_build_object('request_id',p_request_id,'mode',p_mode,'moved_booking_id',x.id,'target_booking_id',y.id),'bay_resequenced');
  IF coalesce((v_apply->>'ok')::boolean,false) IS NOT TRUE THEN v_out:=v_apply; RAISE EXCEPTION USING errcode='P0424'; END IF;
  INSERT INTO pdc_bay_seq_private.receipts(request_id,actor_id,actor_email,operation,bay_id,booking_id,target_booking_id,mode,plan_hash,changes,before_rows,after_rows)
  VALUES(p_request_id,auth.uid(),public.current_actor_email(),'resequence',v_bay,x.id,y.id,p_mode,v_hash,v_out->'changes',v_apply->'before_rows',v_apply->'after_rows')
  RETURNING receipt_id INTO v_receipt;
  v_out:=v_out||jsonb_build_object('receipt_id',v_receipt,'booking_version',(SELECT version FROM public.workshop_bookings WHERE id=x.id),'idempotent_replay',false);
  UPDATE pdc_bay_seq_private.receipts SET result=v_out WHERE receipt_id=v_receipt;
 EXCEPTION
  WHEN sqlstate 'P0424' THEN NULL;
  WHEN sqlstate '22023' OR sqlstate '23514' OR sqlstate '23P01' OR sqlstate '55P03' THEN
   v_out:=jsonb_build_object('ok',false,'error',CASE WHEN SQLSTATE='55P03' THEN 'concurrent_queue_change' ELSE 'resequence_rejected' END,
     'message',left(SQLERRM,400),'retry',SQLSTATE='55P03');
 END;
 RETURN v_out;
END $f$;

-- Undo a re-order (or a push-back) within 30 minutes, by the same person. The bookings go back to their earlier bays
-- and order, at their earlier times where those are still ahead (otherwise from now, one after another). A stopped job
-- that was re-planned stays resumed (time worked kept); if it was in Unallocated before, it goes back there.
CREATE FUNCTION public.workshop_undo_bay_resequence_424(p_receipt_id uuid, p_request_id uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE r pdc_bay_seq_private.receipts%rowtype; v_out jsonb; v_apply jsonb; v_res jsonb; v_receipt uuid; x record; v_bay uuid; v_now timestamptz:=clock_timestamp();
BEGIN
 PERFORM pdc_planner_access_private.require_vehicle_planner();
 IF p_receipt_id IS NULL OR p_request_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','invalid_input'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:cascade-move',0));
 SELECT * INTO r FROM pdc_bay_seq_private.receipts WHERE receipt_id=p_receipt_id FOR UPDATE;
 IF NOT FOUND OR r.operation='undo' THEN RETURN jsonb_build_object('ok',false,'error','receipt_not_found'); END IF;
 IF r.actor_id<>auth.uid() THEN RETURN jsonb_build_object('ok',false,'error','undo_actor_mismatch'); END IF;
 IF r.undone_at IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM pdc_bay_seq_private.receipts u WHERE u.receipt_id=r.undo_receipt_id AND u.request_id=p_request_id) THEN
   RETURN (SELECT u.result FROM pdc_bay_seq_private.receipts u WHERE u.receipt_id=r.undo_receipt_id)||jsonb_build_object('idempotent_replay',true);
  END IF;
  RETURN jsonb_build_object('ok',false,'error','already_undone');
 END IF;
 IF r.created_at<v_now-interval '30 minutes' THEN RETURN jsonb_build_object('ok',false,'error','undo_expired'); END IF;
 PERFORM 1 FROM public.workshop_bookings b WHERE b.id IN (SELECT (e->>'id')::uuid FROM jsonb_array_elements(r.after_rows) e) ORDER BY b.id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(r.after_rows) e JOIN public.workshop_bookings b ON b.id=(e->>'id')::uuid
   WHERE b.deleted_at IS NOT NULL OR b.status<>'planned' OR b.actual_start_at IS NOT NULL OR b.bay_id IS DISTINCT FROM (e->>'bay_id')::uuid) THEN
  RETURN jsonb_build_object('ok',false,'error','undo_conflict','message','A job in this change was started, moved or removed since. Refresh and review before retrying.');
 END IF;
 BEGIN
  -- Jobs that were in Unallocated before go back there (return_to_queue keeps their history and time worked).
  FOR x IN SELECT (e->>'id')::uuid id FROM jsonb_array_elements(r.before_rows) e WHERE e->>'bay_id' IS NULL LOOP
   INSERT INTO public.workshop_transition_authorizations(txid,booking_id,transition,authorized_by) VALUES(txid_current(),x.id,'return_to_queue',auth.uid());
   v_res:=public.workshop_return_booking_to_queue(x.id,(SELECT version FROM public.workshop_bookings WHERE id=x.id),NULL,
     jsonb_build_object('source','bay_resequence_undo','receipt_id',r.receipt_id,'release','r424'));
   IF coalesce((v_res->>'ok')::boolean,false) IS NOT TRUE THEN v_out:=v_res; RAISE EXCEPTION USING errcode='P0424'; END IF;
  END LOOP;
  PERFORM pdc_bay_seq_private.p_init();
  INSERT INTO pg_temp.r424_p(id,vehicle_id,stage_id,bay_id,cur_bay,status,kind,prio,ord,cur_start,cur_end,new_start,new_end,want_start,dur,version)
  SELECT b.id,b.vehicle_id,b.stage_id,(e->>'bay_id')::uuid,b.bay_id,b.status::text,'seed',1,
   row_number() OVER (PARTITION BY e->>'bay_id' ORDER BY (e->>'start')::timestamptz,b.id),
   b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),
   (e->>'start')::timestamptz,pdc_bay_seq_private.minutes(b.id,(e->>'bay_id')::uuid),b.version
  FROM jsonb_array_elements(r.before_rows) e JOIN public.workshop_bookings b ON b.id=(e->>'id')::uuid
  WHERE e->>'bay_id' IS NOT NULL;
  -- other jobs in those bays: planned ones may be pushed, started/stopped are fixed
  INSERT INTO pg_temp.r424_p(id,vehicle_id,stage_id,bay_id,cur_bay,status,kind,prio,cur_start,cur_end,new_start,new_end,dur,version)
  SELECT b.id,b.vehicle_id,b.stage_id,b.bay_id,b.bay_id,b.status::text,
   CASE WHEN b.status='planned' AND b.actual_start_at IS NULL THEN 'move' ELSE 'fixed' END,CASE WHEN b.status='planned' AND b.actual_start_at IS NULL THEN 2 ELSE 0 END,
   b.scheduled_start_at,e.e,b.scheduled_start_at,e.e,pdc_bay_seq_private.minutes(b.id,b.bay_id),b.version
  FROM public.workshop_bookings b CROSS JOIN LATERAL (SELECT public.workshop_booking_effective_end_at(b.id) e) e
  WHERE b.bay_id IN (SELECT DISTINCT bay_id FROM pg_temp.r424_p) AND b.deleted_at IS NULL AND b.status IN ('planned','started','stoppage') AND e.e>v_now
  ON CONFLICT (id) DO NOTHING;
  FOR v_bay IN SELECT DISTINCT bay_id FROM pg_temp.r424_p WHERE kind='seed' LOOP
   PERFORM pdc_bay_seq_private.p_place_sequence(v_bay,v_now);
  END LOOP;
  v_res:=pdc_bay_seq_private.p_close();
  IF coalesce((v_res->>'ok')::boolean,false) IS NOT TRUE THEN v_out:=v_res; RAISE EXCEPTION USING errcode='P0424'; END IF;
  v_apply:=pdc_bay_seq_private.p_apply(jsonb_build_object('source','bay_resequence_undo','receipt_id',r.receipt_id,'request_id',p_request_id),'bay_resequence_undone');
  IF coalesce((v_apply->>'ok')::boolean,false) IS NOT TRUE THEN v_out:=v_apply; RAISE EXCEPTION USING errcode='P0424'; END IF;
  v_out:=jsonb_build_object('ok',true,'undone_receipt_id',r.receipt_id,'changes',pdc_bay_seq_private.p_changes());
  INSERT INTO pdc_bay_seq_private.receipts(request_id,actor_id,actor_email,operation,bay_id,booking_id,target_booking_id,mode,changes,before_rows,after_rows,result)
  VALUES(p_request_id,auth.uid(),public.current_actor_email(),'undo',r.bay_id,r.booking_id,r.target_booking_id,'undo',v_out->'changes',
   coalesce(v_apply->'before_rows','[]'::jsonb),coalesce(v_apply->'after_rows','[]'::jsonb),v_out) RETURNING receipt_id INTO v_receipt;
  UPDATE pdc_bay_seq_private.receipts SET undone_at=clock_timestamp(),undone_by=auth.uid(),undo_receipt_id=v_receipt WHERE receipt_id=r.receipt_id;
  v_out:=v_out||jsonb_build_object('receipt_id',v_receipt);
 EXCEPTION
  WHEN sqlstate 'P0424' THEN NULL;
  WHEN sqlstate '22023' OR sqlstate '23514' OR sqlstate '23P01' OR sqlstate '55P03' THEN
   v_out:=jsonb_build_object('ok',false,'error','undo_conflict','message',left(SQLERRM,400));
 END;
 RETURN v_out;
END $f$;

-- Plan for an administrator move: pin the moved booking at its new place and see which of the same vehicle's later
-- stages (and what follows them in their bays) must be pushed back. Nothing is saved here.
CREATE FUNCTION pdc_bay_seq_private.plan_for_move(p_booking_id uuid, p_bay uuid, p_start timestamptz) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
DECLARE b public.workshop_bookings%rowtype; v_min integer; v_res jsonb;
BEGIN
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 v_min:=pdc_bay_seq_private.minutes(b.id,p_bay);
 PERFORM pdc_bay_seq_private.p_init();
 INSERT INTO pg_temp.r424_p(id,vehicle_id,stage_id,bay_id,cur_bay,status,kind,prio,cur_start,cur_end,new_start,new_end,dur,version)
 -- the pin is ordered by where it is going (its old window may be a parked placeholder)
 VALUES(b.id,b.vehicle_id,b.stage_id,p_bay,b.bay_id,b.status::text,'pin',0,NULL,NULL,
  p_start,pdc_bay_seq_private.end_at(p_start,v_min,p_bay),v_min,b.version);
 v_res:=pdc_bay_seq_private.p_close();
 IF coalesce((v_res->>'ok')::boolean,false) IS NOT TRUE THEN RETURN v_res; END IF;
 RETURN jsonb_build_object('ok',true,'changes',pdc_bay_seq_private.p_changes(b.id),
  'touches_target_bay',EXISTS(SELECT 1 FROM pg_temp.r424_p WHERE changed AND id<>b.id AND bay_id=p_bay),
  'count',(SELECT count(*) FROM pg_temp.r424_p WHERE changed AND id<>b.id),'plan_hash',pdc_bay_seq_private.p_hash(b.id));
END $f$;

CREATE FUNCTION pdc_bay_seq_private.push_warning(p_booking_id uuid, p_plan jsonb) RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $f$
 SELECT jsonb_build_object('ok',false,'warning',true,'requires_confirmation',true,'error','later_bookings_warning',
  'booking_id',p_booking_id,'pushes',p_plan->'changes','plan_hash',p_plan->>'plan_hash',
  'message','This job would run into '||(SELECT 'Key '||coalesce(v.key_number,'?') FROM public.workshop_bookings b JOIN public.vehicles v ON v.id=b.vehicle_id WHERE b.id=p_booking_id)
   ||'''s next booking. Push '||CASE WHEN (p_plan->>'count')::integer=1 THEN 'that booking' ELSE (p_plan->>'count')||' bookings' END||' back so nothing overlaps?')
$f$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_bay_seq_private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.workshop_resequence_bay_424(uuid,integer,uuid,text,boolean,text,jsonb,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.workshop_undo_bay_resequence_424(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.workshop_resequence_bay_424(uuid,integer,uuid,text,boolean,text,jsonb,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.workshop_undo_bay_resequence_424(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.administrator_move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype; v_booking public.workshop_bookings%rowtype;
 v_target_stage uuid; v_target_bay uuid; v_ids uuid[]; v_before jsonb; v_after jsonb; v_result jsonb; v_receipt uuid; v_intent jsonb; v_hash text;
 v_resumable boolean:=false; v_resume jsonb; v_move_version integer:=p_expected_version; v_rules jsonb:='[]'::jsonb;
 v_stopped boolean:=false; v_push jsonb; v_push_apply jsonb; v_push_receipt uuid;
begin
 perform pdc_planner_access_private.require_vehicle_planner();
 if p_request_id is null or p_booking_id is null or p_expected_version is null then raise exception 'PDC_244_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 v_intent:=jsonb_build_object('operation','move','booking_id',p_booking_id,'expected_version',p_expected_version,
   'stage_code',public.workshop_canonical_stage_code(p_stage_code),'bay_number',p_bay_number,'scheduled_start_at',p_scheduled_start_at,
   'duration_minutes',p_duration_minutes,'override_reason',p_override_reason,'metadata',coalesce(p_metadata,'{}'::jsonb),'cascade',coalesce(p_cascade,false));
 v_hash:=encode(extensions.digest(convert_to(v_intent::text,'UTF8'),'sha256'),'hex');
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.request_intent is distinct from v_intent or v_existing.request_intent_hash is distinct from v_hash then raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023'; end if;
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 -- r415 (F31): a job that was started, stopped and returned to the queue is resumed (Craig, 21 Oct 2026): the time already
 -- worked is kept (booking history and workshop_booking_resume_ledger_415) and only the remaining hours are planned.
 -- Started, stopped, completed and deleted bookings stay protected.
 v_resumable:=v_booking.deleted_at is null and v_booking.status='queued' and v_booking.bay_id is null
   and v_booking.actual_start_at is not null and v_booking.actual_end_at is null and v_booking.returned_to_queue_at is not null;
 -- r424 (F38): a started job put on STOPPAGE and returned to Unallocated is re-planned the same way: the stoppage
 -- is ended (reason kept in history), the time worked is kept and only the remaining hours are booked.
 v_stopped:=v_booking.deleted_at is null and v_booking.status='stoppage' and v_booking.bay_id is null
   and v_booking.actual_start_at is not null and v_booking.actual_end_at is null and v_booking.returned_to_queue_at is not null;
 if not v_resumable and not v_stopped and (v_booking.deleted_at is not null or v_booking.status not in('queued','planned') or v_booking.actual_start_at is not null or v_booking.actual_end_at is not null) then return jsonb_build_object('ok',false,'error','protected_booking'); end if;
 select id into v_target_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_target_bay from public.workshop_bays where stage_id=v_target_stage and bay_number=p_bay_number and is_active;
 if v_target_stage is null or v_target_bay is null then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 -- r417 (F32): a bay category or vehicle rule that does not match warns instead of refusing. The planner confirms
 -- (metadata bay_rule_confirm.rules) and the override is logged in pdc_bay_rules_private.overrides.
 v_rules:=pdc_bay_rules_private.mismatches(v_booking.vehicle_id,v_booking.work_category,v_target_bay);
 if jsonb_array_length(v_rules)>0 then
   if not pdc_bay_rules_private.confirmed(v_rules,p_metadata) then return pdc_bay_rules_private.warning(v_rules); end if;
   perform pdc_bay_rules_private.log_pending(v_rules,v_booking.vehicle_id,p_booking_id,v_target_bay,v_booking.work_category,'move',p_metadata);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-move:'||p_booking_id::text,0));
 select coalesce(array_agg(x.id order by x.id),'{}'::uuid[]) into v_ids from public.workshop_bookings x
 where x.id=p_booking_id or (x.deleted_at is null and x.status in('queued','planned') and x.bay_id in(v_booking.bay_id,v_target_bay));
 perform 1 from public.workshop_bookings x where x.id=any(v_ids) order by x.id for update;
 v_before:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 begin
 -- r415 (F31): resume and move are one step; if the move is refused the resume is rolled back too.
 if v_stopped then
   v_resume:=pdc_bay_seq_private.requeue_stopped(p_booking_id,'administrator_move');
   if coalesce((v_resume->>'ok')::boolean,false) is not true then v_result:=v_resume; raise exception 'r424: stoppage not ended' using errcode='P0415'; end if;
   v_resumable:=true;
   v_move_version:=(v_resume->>'booking_version')::integer;
 elsif v_resumable then
   v_resume:=public.workshop_resume_returned_booking_415(p_booking_id,p_expected_version,'administrator_move');
   if coalesce((v_resume->>'ok')::boolean,false) is not true then v_result:=v_resume; raise exception 'r415: resume not applied' using errcode='P0415'; end if;
   v_move_version:=(v_resume->>'booking_version')::integer;
 end if;
 -- r424 (F38): if the job would now run into the same vehicle's next stage (e.g. its Electrical booking in Bay 8),
 -- warn and offer to push that stage (and what follows it) back, instead of refusing with vehicle_overlap.
 if not coalesce(p_cascade,false) then
   v_push:=pdc_bay_seq_private.plan_for_move(p_booking_id,v_target_bay,p_scheduled_start_at);
   if coalesce((v_push->>'ok')::boolean,false) and coalesce((v_push->>'count')::integer,0)>0 and not coalesce((v_push->>'touches_target_bay')::boolean,false) then
     if coalesce(p_metadata->'push_later_confirm'->>'plan_hash','') is distinct from v_push->>'plan_hash' then
       v_result:=pdc_bay_seq_private.push_warning(p_booking_id,v_push); raise exception 'r424: push back not confirmed' using errcode='P0415';
     end if;
     v_push_apply:=pdc_bay_seq_private.p_apply(coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'pushed_for_booking_id',p_booking_id),'pushed_for_earlier_stage');
     if coalesce((v_push_apply->>'ok')::boolean,false) is not true then v_result:=v_push_apply; raise exception 'r424: push back not applied' using errcode='P0415'; end if;
     insert into pdc_bay_seq_private.receipts(request_id,actor_id,actor_email,operation,bay_id,booking_id,mode,plan_hash,changes,before_rows,after_rows,result)
     values(p_request_id,v_actor,public.current_actor_email(),'push_later',v_target_bay,p_booking_id,'push_later',v_push->>'plan_hash',v_push->'changes',
       v_push_apply->'before_rows',v_push_apply->'after_rows',jsonb_build_object('ok',true,'changes',v_push->'changes')) returning receipt_id into v_push_receipt;
   end if;
 end if;
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move(p_booking_id,v_move_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 else
   v_result:=public.move_workshop_booking(p_booking_id,v_move_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 end if;
 if (v_resumable or v_push_receipt is not null) and coalesce((v_result->>'ok')::boolean,false) is not true then raise exception 'r415: move refused; resume rolled back' using errcode='P0415'; end if;
 exception when sqlstate 'P0415' then return pdc_bay_rules_private.finish(v_rules,p_booking_id,v_result);
 end;
 if coalesce((v_result->>'ok')::boolean,false) is not true then return pdc_bay_rules_private.finish(v_rules,p_booking_id,v_result); end if;
 v_after:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',p_booking_id,'booking_version',(select version from public.workshop_bookings where id=p_booking_id),'operation_type','move')
   ||case when v_resumable then jsonb_build_object('resumed',v_resume) else '{}'::jsonb end
   ||case when v_push_receipt is not null then jsonb_build_object('pushed_later',v_push->'changes','push_receipt_id',v_push_receipt) else '{}'::jsonb end;
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,
   before_rows,after_rows,result,request_intent,request_intent_hash,before_state,after_state)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),p_booking_id,v_booking.vehicle_id,'move',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_drag_drop'),80),nullif(left(btrim(coalesce(p_override_reason,p_metadata->>'reason','')),500),''),p_cascade,
   v_before->'bookings',v_after->'bookings',v_result,v_intent,v_hash,v_before,v_after) returning receipt_id into v_receipt;
 return pdc_bay_rules_private.finish(v_rules,p_booking_id,v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false));
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.request_intent is not distinct from v_intent and v_existing.request_intent_hash is not distinct from v_hash then return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true); end if;
 raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
end $function$;

CREATE TABLE pdc_bay_seq_private.before_424_pins AS SELECT * FROM pdc_ops.expected_function_md5
 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)';
REVOKE ALL ON pdc_bay_seq_private.before_424_pins FROM PUBLIC, anon, authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at)
SELECT x.sig,md5(p.prosrc),'r424','F38: stopped jobs re-plannable, push-back warn-and-confirm, bay re-order/swap with undo',now()
FROM (VALUES('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'),
 ('public.workshop_resequence_bay_424(uuid,integer,uuid,text,boolean,text,jsonb,uuid)'),('public.workshop_undo_bay_resequence_424(uuid,uuid)'),
 ('pdc_bay_seq_private.next_start(timestamp with time zone,uuid)'),('pdc_bay_seq_private.end_at(timestamp with time zone,integer,uuid)'),
 ('pdc_bay_seq_private.minutes(uuid,uuid)'),('pdc_bay_seq_private.p_init()'),('pdc_bay_seq_private.p_load()'),('pdc_bay_seq_private.p_close()'),
 ('pdc_bay_seq_private.p_place_sequence(uuid,timestamp with time zone)'),('pdc_bay_seq_private.p_changes(uuid)'),('pdc_bay_seq_private.p_hash(uuid)'),
 ('pdc_bay_seq_private.requeue_stopped(uuid,text)'),('pdc_bay_seq_private.place(uuid,uuid,timestamp with time zone,integer,jsonb)'),
 ('pdc_bay_seq_private.p_apply(jsonb,text)'),('pdc_bay_seq_private.plan_for_move(uuid,uuid,timestamp with time zone)'),('pdc_bay_seq_private.push_warning(uuid,jsonb)')) x(sig)
JOIN pg_proc p ON p.oid=x.sig::regprocedure
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=excluded.updated_at
 WHERE expected_function_md5.signature=excluded.signature; -- no-op WHERE for the safeupdate lint; applied text ended before it

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in)
VALUES('bay_resequence_and_stopped_replan','F38',
 'A stopped job returned to Unallocated can be re-planned (time worked kept); running into the same vehicle''s next stage warns and offers to push it back; planners can re-order or swap a bay''s upcoming jobs with no overlaps, a history row for every change, and undo.',
 $c$WITH fx AS (
 SELECT
  (SELECT prosrc LIKE '%pdc_bay_seq_private.requeue_stopped%' AND prosrc LIKE '%pdc_bay_seq_private.plan_for_move%' AND prosrc LIKE '%push_later_confirm%'
   FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'::regprocedure) AS move_ok,
  has_function_privilege('authenticated','public.workshop_resequence_bay_424(uuid,integer,uuid,text,boolean,text,jsonb,uuid)','EXECUTE')
  AND has_function_privilege('authenticated','public.workshop_undo_bay_resequence_424(uuid,uuid)','EXECUTE')
  AND NOT has_function_privilege('anon','public.workshop_resequence_bay_424(uuid,integer,uuid,text,boolean,text,jsonb,uuid)','EXECUTE')
  AND NOT has_function_privilege('anon','public.workshop_undo_bay_resequence_424(uuid,uuid)','EXECUTE') AS rpc_ok,
  NOT has_schema_privilege('authenticated','pdc_bay_seq_private','USAGE') AND NOT has_schema_privilege('anon','pdc_bay_seq_private','USAGE')
  AND NOT has_function_privilege('authenticated','pdc_bay_seq_private.requeue_stopped(uuid,text)','EXECUTE') AS private_ok
), stuck AS (
 -- stopped jobs returned to Unallocated: can be re-planned now (informational)
 SELECT count(*) n FROM public.workshop_bookings b WHERE b.deleted_at IS NULL AND b.status='stoppage' AND b.bay_id IS NULL
  AND b.actual_start_at IS NOT NULL AND b.actual_end_at IS NULL AND b.returned_to_queue_at IS NOT NULL
), ov AS (
 -- no two live bookings overlap in a bay among those a re-order touched in the last 30 days
 SELECT count(*) n FROM public.workshop_bookings a JOIN public.workshop_bookings b ON a.bay_id=b.bay_id AND a.id<b.id
 WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL AND a.status IN ('planned','started','stoppage') AND b.status IN ('planned','started','stoppage')
  AND (a.id IN (SELECT (e->>'id')::uuid FROM pdc_bay_seq_private.receipts r, jsonb_array_elements(r.after_rows) e WHERE r.created_at>now()-interval '30 days')
    OR b.id IN (SELECT (e->>'id')::uuid FROM pdc_bay_seq_private.receipts r, jsonb_array_elements(r.after_rows) e WHERE r.created_at>now()-interval '30 days'))
  AND tstzrange(a.scheduled_start_at,public.workshop_booking_effective_end_at(a.id),'[)') && tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),'[)')
), hist AS (
 -- every booking a re-order changed has its history row
 SELECT count(*) n FROM pdc_bay_seq_private.receipts r, jsonb_array_elements(r.after_rows) e
 WHERE r.operation IN ('resequence','push_later','undo') AND NOT EXISTS(SELECT 1 FROM public.workshop_booking_history h WHERE h.booking_id=(e->>'id')::uuid
   AND h.event_type IN ('bay_resequenced','pushed_for_earlier_stage','bay_resequence_undone') AND h.created_at>=r.created_at-interval '1 minute')
), rc AS (SELECT count(*) FILTER (WHERE operation='resequence') rs, count(*) FILTER (WHERE operation='push_later') pl, count(*) FILTER (WHERE operation='undo') un FROM pdc_bay_seq_private.receipts)
SELECT fx.move_ok AND fx.rpc_ok AND fx.private_ok AND ov.n=0 AND hist.n=0 AS ok,
 'stopped jobs re-plannable: '||CASE WHEN fx.move_ok THEN 'yes' ELSE 'NO' END||'; bay re-order/undo callable by planners only: '||CASE WHEN fx.rpc_ok AND fx.private_ok THEN 'yes' ELSE 'NO' END
 ||'; overlaps after a re-order: '||ov.n||'; changes without history: '||hist.n||'; re-orders: '||rc.rs||', push-backs: '||rc.pl||', undos: '||rc.un
 ||'; stopped jobs in Unallocated waiting: '||stuck.n AS detail
FROM fx,stuck,ov,hist,rc$c$,true,225,'r424');

DO $v$ DECLARE c record; ok boolean; detail text; BEGIN
 FOR c IN SELECT check_name,check_sql FROM pdc_ops.regression_checks WHERE check_name IN('bay_resequence_and_stopped_replan','started_returned_jobs_replannable','bay_rule_mismatch_warns_and_logs') LOOP
  EXECUTE c.check_sql INTO ok,detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r424: check % not green: %',c.check_name,detail; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r424' AND md5(p.prosrc)<>e.prosrc_md5)
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r424')<>17 THEN RAISE EXCEPTION 'r424: pins not in place'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r424: clock tick changed'; END IF;
END $v$;
