-- r440 (F51, Craig via PMB Email 14:31 AWST 21 Oct): fitter bay items need Start before Done.
-- Staging cdsmnqxtyyoeoznmbidd only. Changes one function: public.fitter_job_command, action 'line', refuses to tick an
-- internal bay item Done unless that item is started (item_status 'running'), returns error 'item_not_started' and writes an
-- 'item_done_refused' row to pdc_fitter_private.operation_timing_audit. Already-Done items, note saves on them, unticking,
-- supplier (external) lines and conversion lines are unchanged. No row is changed: items Done without a start stay Done.
-- Not touched: workshop_clock_tick and its cron, the r431 clock helpers, item_timing*, reset_fitter_item_timing, the hidden
-- Karratha copy. Pin #387 for fitter_job_command moves to r440 (undo restores it); adds check item_start_before_done.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r440: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r440: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r440: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r440: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='4952bea1ccb019c7d1dfe0dc873a5c67'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r440: fitter_job_command is not the #387 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='4952bea1ccb019c7d1dfe0dc873a5c67' AND release='#387')<>1 THEN RAISE EXCEPTION 'r440: pin is not the #387 pin'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r440')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='item_start_before_done' OR added_in='r440') THEN RAISE EXCEPTION 'r440: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=241) THEN RAISE EXCEPTION 'r440: sort_order 241 taken'; END IF;
END $g$;

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
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     r:=pdc_fitter_private.item_timing_save(p_technician_id,b.id,l,substr(p_action,6),p_note);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
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
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='9c30466cfef22ccda3c6d955bf484489',release='r440',note='r440: item Done needs Start (F51)',updated_at=clock_timestamp()
 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='4952bea1ccb019c7d1dfe0dc873a5c67' AND release='#387';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('item_start_before_done','F51','Fitter bay items (r440): fitter_job_command carries the Start-before-Done guard (item_not_started, audited as item_done_refused) and matches its pin; since r440 no item ticked Done has a timing row left running or reset (Done was ticked without the item being started); reports refusals in the last 24 h',
  $chk$WITH fn AS (
  SELECT p.prosrc ~ 'r440 \(F51\)' AND p.prosrc ~ '''error'',''item_not_started''' AND p.prosrc ~ '''item_done_refused''' AS guarded,
   md5(p.prosrc)=(SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND e.release='r440') AS pinned
  FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')
), since AS (
  SELECT greatest((SELECT e.updated_at FROM pdc_ops.expected_function_md5 e WHERE e.signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND e.release='r440'),
   statement_timestamp()-interval '7 days') t
), bad AS (
  SELECT count(*) n FROM pdc_fitter_private.operation_progress op
   JOIN pdc_fitter_private.operation_timing ot ON ot.booking_id=op.booking_id AND ot.line_identity=op.line_identity
  WHERE op.completed AND op.updated_at>(SELECT t FROM since) AND ot.status IN ('running','reset') AND ot.updated_at<=op.updated_at
), refused AS (
  SELECT count(*) n FROM pdc_fitter_private.operation_timing_audit a WHERE a.action='item_done_refused' AND a.created_at>statement_timestamp()-interval '24 hours'
), done AS (
  SELECT count(*) n FROM pdc_fitter_private.operation_timing_audit a WHERE a.action='item_done' AND a.created_at>(SELECT t FROM since)
)
SELECT coalesce((SELECT guarded AND pinned FROM fn),false) AND (SELECT n FROM bad)=0 AS ok,
 'guard in fitter_job_command: '||coalesce((SELECT guarded::text FROM fn),'function missing')||', matches r440 pin: '||coalesce((SELECT pinned::text FROM fn),'no')
 ||'; since r440: '||(SELECT n FROM done)||' items ticked Done after Start, '||(SELECT n FROM bad)||' ticked Done while the item was not started'
 ||'; Done refused (Press Start first) in the last 24 h: '||(SELECT n FROM refused) AS detail
$chk$,true,241,'r440');

DO $g$ BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='9c30466cfef22ccda3c6d955bf484489'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r440: fitter_job_command did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r440')<>1 THEN RAISE EXCEPTION 'r440: pin not moved'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='item_start_before_done' AND added_in='r440')<>'909dde10e0882bb95cf31af9bcc6dfe3' THEN RAISE EXCEPTION 'r440: check did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r440: clock tick changed'; END IF;
END $g$;
