-- r532 (F146). PREVIEW. SQL is not applied. Staging cdsmnqxtyyoeoznmbidd only. Production is not touched.
-- From the fitter's bay, Start and Done on another station's items use the same item path as this bay.
-- When every item of Hoist, Fitting, Fabrication, Electrical, Tyre, Tint or Sublet is Done, that station's
-- work item is ticked the same way completing its bay does, and an unstarted booking for it is released.
-- Untick reopens the station. A booking released this way stays released. Bus 4x4, Parts and Pit keep their own completion.
-- Department 135 is not edited. Pin count stays 241 (the fitter command pin moves in place).
-- Sort 314. Unmerged r531 / F145 owns sorts 312 and 313. r530 / F144 is sort 311. r529 owns sort 310.
-- Undo: supabase/rollbacks/20261026093000_r532_fitter_other_station_ticks.down.sql
-- Command prosrc md5 626ca8b23a2e5f02e2ca8f96a4533d6f. Lines prosrc md5 1a30411bad4fca7f6455559a24c839d1. Helper prosrc md5 e7d9c212bca907b6bc57737493748da2.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r532: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r532: staging only'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='9c30466cfef22ccda3c6d955bf484489'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r532: fitter_job_command is not the r440 version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='9c30466cfef22ccda3c6d955bf484489' AND release='r440')<>1 THEN RAISE EXCEPTION 'r532: pin is not the r440 pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.lines_before_bus_workflow_20260921(uuid,uuid)')) IS DISTINCT FROM 'eb82ad959866f20c4e83e59d7af5043a' THEN RAISE EXCEPTION 'r532: lines_before is not the live body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r532: Department 135 fitter command changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r532: pin count is not 241'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=314 OR check_name='cross_station_ticks_532' OR added_in='r532' OR fault_id='F146') THEN RAISE EXCEPTION 'r532: sort 314 or F146 is taken'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='karratha_gp_po_530' AND fault_id='F144' AND sort_order=311 AND added_in='r530') THEN RAISE EXCEPTION 'r532: r530 / F144 sort 311 is not the live check'; END IF;
 IF to_regclass('pdc_fitter_private.cross_station_tick') IS NOT NULL THEN RAISE EXCEPTION 'r532: already applied'; END IF;
END $g$;

CREATE TABLE pdc_fitter_private.cross_station_tick (
 vehicle_id uuid NOT NULL,
 stage_code text NOT NULL,
 ticked boolean NOT NULL,
 ticked_by uuid,
 ticked_at timestamptz,
 source_booking_id uuid,
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY (vehicle_id, stage_code));
ALTER TABLE pdc_fitter_private.cross_station_tick ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_fitter_private.cross_station_tick FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_fitter_private.cross_station_apply(p_vehicle uuid, p_booking uuid, p_stage text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_key text; v_name text; v_total integer; v_done integer; v_unknown integer; v_owns boolean;
 v_finished boolean; v_all boolean:=false; v_ticked boolean:=false; v_reopened boolean:=false;
 v_reason text; rec record; r jsonb; released jsonb:='[]'::jsonb; failed jsonb:='[]'::jsonb;
BEGIN
 IF p_stage IS NULL OR p_stage NOT IN('HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','TINT','SUBLET') THEN
  RETURN jsonb_build_object('cross_station',jsonb_build_object('stage_code',p_stage,'ticked',false,'reopened',false,'reason','station_uses_its_own_completion'));
 END IF;
 SELECT s.work_key,s.display_name INTO v_key,v_name FROM public.workshop_stages s WHERE s.code=p_stage;
 IF v_key IS NULL THEN
  RETURN jsonb_build_object('cross_station',jsonb_build_object('stage_code',p_stage,'ticked',false,'reopened',false,'reason','station_uses_its_own_completion'));
 END IF;
 SELECT count(*),
  count(*) FILTER (WHERE lat.completed AND lat.scope_hash=src.scope_hash),
  count(*) FILTER (WHERE (src.hours IS NULL OR src.hours<=0) AND src.zero_hour IS DISTINCT FROM true)
 INTO v_total,v_done,v_unknown
 FROM (
  SELECT l->>'line_identity' line_identity,
   md5(jsonb_build_array(l->>'line_identity',l->>'description',l->>'stage_code',l->'estimated_hours',l->>'job_card_number')::text) scope_hash,
   CASE WHEN jsonb_typeof(l->'estimated_hours')='number' THEN (l->>'estimated_hours')::numeric END hours,
   coalesce((l->>'zero_hour_task')::boolean,false) zero_hour
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle)) l
  WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'=p_stage
 ) src
 LEFT JOIN LATERAL (
  SELECT p.completed,p.scope_hash
  FROM pdc_fitter_private.operation_progress p
  JOIN public.workshop_bookings wb ON wb.id=p.booking_id
  WHERE wb.vehicle_id=p_vehicle AND wb.deleted_at IS NULL AND p.line_identity=src.line_identity
  ORDER BY p.updated_at DESC,p.booking_id
  LIMIT 1
 ) lat ON true;
 v_finished:=EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=p_vehicle AND s.code=p_stage AND b.deleted_at IS NULL AND b.status='completed');
 SELECT t.ticked INTO v_owns FROM pdc_fitter_private.cross_station_tick t WHERE t.vehicle_id=p_vehicle AND t.stage_code=p_stage;
 v_owns:=coalesce(v_owns,false);
 IF v_total>0 AND v_done=v_total AND v_unknown=0 THEN v_all:=true;
 ELSIF v_total>0 AND v_done=v_total AND v_unknown>0 THEN v_reason:='hours_need_review';
 END IF;
 IF v_finished THEN
  RETURN jsonb_build_object('cross_station',jsonb_build_object('stage_code',p_stage,'stage_name',v_name,'ticked',false,'reopened',false,'reason','stage_already_finished'));
 END IF;
 IF v_all AND NOT v_owns THEN
  UPDATE public.vehicle_work_items SET completed=true,completed_by=auth.uid(),completed_at=clock_timestamp(),updated_at=clock_timestamp()
   WHERE vehicle_id=p_vehicle AND work_key=v_key AND required;
  IF NOT FOUND THEN
   INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at)
   VALUES(p_vehicle,v_key,true,true,auth.uid(),clock_timestamp())
   ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,completed=true,completed_by=excluded.completed_by,
    completed_at=excluded.completed_at,updated_at=clock_timestamp()
   WHERE public.vehicle_work_items.vehicle_id=excluded.vehicle_id;
  END IF;
  INSERT INTO pdc_fitter_private.cross_station_tick(vehicle_id,stage_code,ticked,ticked_by,ticked_at,source_booking_id,updated_at)
  VALUES(p_vehicle,p_stage,true,auth.uid(),clock_timestamp(),p_booking,clock_timestamp())
  ON CONFLICT(vehicle_id,stage_code) DO UPDATE SET ticked=true,ticked_by=excluded.ticked_by,ticked_at=excluded.ticked_at,
   source_booking_id=excluded.source_booking_id,updated_at=excluded.updated_at
  WHERE pdc_fitter_private.cross_station_tick.vehicle_id=excluded.vehicle_id;
  FOR rec IN SELECT bk.id,bk.version FROM public.workshop_bookings bk JOIN public.workshop_stages s ON s.id=bk.stage_id
   WHERE bk.vehicle_id=p_vehicle AND s.code=p_stage AND bk.deleted_at IS NULL
    AND bk.status IN('planned','queued') AND bk.actual_start_at IS NULL AND bk.id IS DISTINCT FROM p_booking
   ORDER BY bk.id
  LOOP
   BEGIN
    r:=public.cancel_workshop_booking(rec.id,rec.version,'Done in another bay. This station is ticked off.',
     jsonb_build_object('source','cross_station_532','stage_code',p_stage,'from_booking',p_booking));
    IF coalesce((r->>'ok')::boolean,false) THEN released:=released||jsonb_build_array(rec.id);
    ELSE failed:=failed||jsonb_build_array(jsonb_build_object('booking_id',rec.id,'error',r->>'error')); END IF;
   EXCEPTION WHEN OTHERS THEN
    failed:=failed||jsonb_build_array(jsonb_build_object('booking_id',rec.id,'error',SQLSTATE));
   END;
  END LOOP;
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','vehicle_work_items',p_vehicle,p_vehicle,auth.uid(),public.current_actor_email(),
   jsonb_build_object('stage_code',p_stage,'completed',false),
   jsonb_build_object('stage_code',p_stage,'completed',true,'released_bookings',released,'release_failed',failed),
   jsonb_build_object('source','cross_station_532','from_booking',p_booking));
  INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
  VALUES(p_booking,'stage:'||p_stage,NULL,auth.uid(),'cross_station_ticked','{}'::jsonb,
   jsonb_build_object('stage_code',p_stage,'released',released,'failed',failed,'by',auth.uid()));
  v_ticked:=true;
 ELSIF v_all AND v_owns THEN
  v_ticked:=true;
 ELSIF NOT v_all AND v_owns THEN
  UPDATE public.vehicle_work_items SET completed=false,completed_at=NULL,completed_by=NULL,updated_at=clock_timestamp()
   WHERE vehicle_id=p_vehicle AND work_key=v_key AND completed;
  UPDATE pdc_fitter_private.cross_station_tick SET ticked=false,updated_at=clock_timestamp()
   WHERE vehicle_id=p_vehicle AND stage_code=p_stage AND ticked;
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','vehicle_work_items',p_vehicle,p_vehicle,auth.uid(),public.current_actor_email(),
   jsonb_build_object('stage_code',p_stage,'completed',true),
   jsonb_build_object('stage_code',p_stage,'completed',false),
   jsonb_build_object('source','cross_station_532','from_booking',p_booking,'reopened',true));
  INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
  VALUES(p_booking,'stage:'||p_stage,NULL,auth.uid(),'cross_station_reopened','{}'::jsonb,
   jsonb_build_object('stage_code',p_stage,'by',auth.uid()));
  v_reopened:=true;
 END IF;
 RETURN jsonb_build_object('cross_station',jsonb_build_object('stage_code',p_stage,'stage_name',v_name,'ticked',v_ticked,'reopened',v_reopened,'reason',v_reason,'released_bookings',released));
END
$function$;
REVOKE ALL ON FUNCTION pdc_fitter_private.cross_station_apply(uuid,uuid,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION pdc_fitter_private.lines_before_bus_workflow_20260921(p_vehicle_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH source AS (
  SELECT l,md5(jsonb_build_array(l->>'line_identity',l->>'description',
    l->>'stage_code',l->'estimated_hours',l->>'job_card_number')::text) scope_hash
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true)
 ), clock AS (
  -- Booking work timer, read once and only while an item is running here.
  SELECT CASE WHEN EXISTS(SELECT 1 FROM pdc_fitter_private.operation_timing t
    WHERE t.booking_id=p_booking_id AND t.status='running')
   THEN (pdc_fitter_private.timing(p_booking_id,statement_timestamp())#>>'{timer,elapsed_seconds}')::numeric END job_seconds
 )
 SELECT coalesce(jsonb_agg(pdc_fitter_private.conversion_enrich(p_vehicle_id,jsonb_build_object(
  'line_identity',s.l->>'line_identity','description',s.l->>'description',
  'stage_code',s.l->>'stage_code','hours',s.l->'estimated_hours',
  'operation_no',s.l->'operation_no','source_note',s.l->>'review_note',
  'scope_hash',s.scope_hash,'completed',coalesce(p.completed AND p.scope_hash=s.scope_hash,false),
  'note',coalesce(p.note,''),'scope_changed',p.scope_hash IS NOT NULL AND p.scope_hash<>s.scope_hash,
  'updated_at',p.updated_at,'technician_id',p.technician_id
 )||pdc_fitter_private.item_timing(t,s.scope_hash,s.l->'estimated_hours',(SELECT job_seconds FROM clock))
 ) ORDER BY s.l->>'stage_code',s.l->>'operation_no',s.l->>'line_identity'),'[]'::jsonb)
 -- r532 (F146): a Done tick recorded on another bay of this vehicle counts here when this bay has no row of its own.
 FROM source s LEFT JOIN LATERAL (
  SELECT p.completed,p.scope_hash,p.note,p.updated_at,p.technician_id
  FROM pdc_fitter_private.operation_progress p
  JOIN public.workshop_bookings wb ON wb.id=p.booking_id
  WHERE wb.vehicle_id=p_vehicle_id AND wb.deleted_at IS NULL AND p.line_identity=s.l->>'line_identity'
   AND (p.booking_id=p_booking_id OR (p.completed AND p.scope_hash=s.scope_hash
    AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress own
     WHERE own.booking_id=p_booking_id AND own.line_identity=s.l->>'line_identity')))
  ORDER BY (p.booking_id=p_booking_id) DESC, p.updated_at DESC
  LIMIT 1
 ) p ON true
 LEFT JOIN pdc_fitter_private.operation_timing t
   ON t.booking_id=p_booking_id AND t.line_identity=s.l->>'line_identity'
$function$;
CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer; extra jsonb:='{}'::jsonb;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion','item_start','item_reset')
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
   IF p_action='conversion' THEN
     r:=pdc_fitter_private.conversion_save(p_technician_id,b.id,p_line_identity,p_note::jsonb);
   ELSIF p_action IN('item_start','item_reset') THEN
     -- Start / reset an item: timing only; booking row and version unchanged.
     -- r532 (F146): a normal item from another station can be started here. Its own running bay still owns it.
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity
       AND (item->>'stage_code'=d->>'stage_code'
        OR (item->>'external_work' IS DISTINCT FROM 'true' AND coalesce(jsonb_typeof(item->'conversion'),'null')='null'));
     IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->>'stage_code' IS DISTINCT FROM d->>'stage_code'
        AND EXISTS(SELECT 1 FROM public.workshop_bookings ob JOIN public.workshop_stages os ON os.id=ob.stage_id
         WHERE ob.vehicle_id=b.vehicle_id AND ob.deleted_at IS NULL AND os.code=l->>'stage_code' AND ob.status IN('started','stoppage')) THEN
      RETURN jsonb_build_object('ok',false,'error','station_busy');
     END IF;
     r:=pdc_fitter_private.item_timing_save(p_technician_id,b.id,l,substr(p_action,6),p_note);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     -- r532 (F146): same Start / Done path for another station's normal item. The station ticks when every item is Done.
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity
       AND (item->>'stage_code'=d->>'stage_code'
        OR (item->>'external_work' IS DISTINCT FROM 'true' AND coalesce(jsonb_typeof(item->'conversion'),'null')='null'));
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->>'stage_code' IS DISTINCT FROM d->>'stage_code'
        AND EXISTS(SELECT 1 FROM public.workshop_bookings ob JOIN public.workshop_stages os ON os.id=ob.stage_id
         WHERE ob.vehicle_id=b.vehicle_id AND ob.deleted_at IS NULL AND os.code=l->>'stage_code' AND ob.status IN('started','stoppage')) THEN
      RETURN jsonb_build_object('ok',false,'error','station_busy');
     END IF;
     IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
     -- r440 (F51): an internal bay item must be started before it is ticked Done. An item already Done stays Done (a note
     -- save re-sends completed=true and is allowed) and unticking is always allowed. Supplier and conversion lines keep
     -- their own ticks. Same rule for fitters, controllers and admins on this card; refusals are audited.
     IF p_completed AND NOT coalesce((l->>'completed')::boolean,false)
        AND l->>'external_work' IS DISTINCT FROM 'true' AND coalesce(jsonb_typeof(l->'conversion'),'null')='null'
        AND l->>'item_status' IS DISTINCT FROM 'running' THEN
       INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
       VALUES(b.id,p_line_identity,p_technician_id,auth.uid(),'item_done_refused',
        coalesce((SELECT to_jsonb(t) FROM pdc_fitter_private.operation_timing t WHERE t.booking_id=b.id AND t.line_identity=p_line_identity),'{}'::jsonb),
        jsonb_build_object('error','item_not_started','item_status',l->'item_status','release','r440'));
       RETURN jsonb_build_object('ok',false,'error','item_not_started');
     END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp()
      WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
     -- Done stamps the actual time on a started item; untick clears it.
     PERFORM pdc_fitter_private.item_timing_tick(b.id,p_line_identity,l->>'scope_hash',p_completed);
     IF l->>'stage_code' IS DISTINCT FROM d->>'stage_code' THEN
      extra:=pdc_fitter_private.cross_station_apply(b.vehicle_id,b.id,l->>'stage_code');
     END IF;
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
    ||pdc_fitter_private.timing(b.id,clock_timestamp())||coalesce(extra,'{}'::jsonb);
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
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='626ca8b23a2e5f02e2ca8f96a4533d6f',release='r532',note='r532: other-station item ticks (F146)',updated_at=clock_timestamp()
 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='9c30466cfef22ccda3c6d955bf484489' AND release='r440';

UPDATE pdc_ops.regression_checks SET check_sql=replace(check_sql,'e.release=''r440''','e.release=''r532''')
 WHERE check_name='item_start_before_done' AND added_in='r440' AND check_sql LIKE '%e.release=''r440''%';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('cross_station_ticks_532','F146','Fitter other-station ticks (r532): Start and Done on another station use fitter_job_command, a full station ticks its work item, and Department 135 keeps its own command',
  $chk$SELECT
 (SELECT md5(p.prosrc)=(SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND e.release='r532')
   AND p.prosrc ~ 'station_busy' AND p.prosrc ~ 'cross_station_apply' AND p.prosrc ~ 'r440 \(F51\)' AND p.prosrc ~ '''error'',''item_not_started'''
  FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
 AND (SELECT md5(p.prosrc)='e7d9c212bca907b6bc57737493748da2'
  FROM pg_proc p WHERE p.oid=to_regprocedure('pdc_fitter_private.cross_station_apply(uuid,uuid,text)'))
 AND (SELECT prosrc ~ 'r532 \(F146\)' FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.lines_before_bus_workflow_20260921(uuid,uuid)'))
 AND to_regclass('pdc_fitter_private.cross_station_tick') IS NOT NULL
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
  IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
 AS ok,
 'fitter command pin r532, cross-station helper, shared Done read, Department 135 command stays separate' AS detail$chk$,
 true,314,'r532');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='626ca8b23a2e5f02e2ca8f96a4533d6f'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r532: fitter_job_command did not land'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.lines_before_bus_workflow_20260921(uuid,uuid)')) IS DISTINCT FROM '1a30411bad4fca7f6455559a24c839d1' THEN RAISE EXCEPTION 'r532: lines_before did not land'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.cross_station_apply(uuid,uuid,text)')) IS DISTINCT FROM 'e7d9c212bca907b6bc57737493748da2' THEN RAISE EXCEPTION 'r532: helper did not land'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r532: Department 135 fitter command changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r532: pin count is not 241'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='cross_station_ticks_532') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r532: check cross_station_ticks_532 not OK: %', x.detail; END IF;
END $g$;
