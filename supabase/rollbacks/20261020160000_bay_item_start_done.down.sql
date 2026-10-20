-- Undo 20261020160000_bay_item_start_done: restore fitter_job_command,
-- lines_before_bus_workflow_20260921, progress, conversion_enrich and
-- conversion_save byte-exact (md5 db9db4ca / 6154aaf1 / b388403d / 2f156fdc /
-- fb4d6cd8) and drop the reset RPC and item helpers. operation_timing and its
-- audit stay stored (nothing is deleted). Bus sections go back to one running
-- section per conversion and the in-progress share returns to the job %.
-- Staging cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF position('item_timing_tick' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')) = 0 THEN
    RAISE EXCEPTION 'item_ticks_not_applied';
  END IF;
END $guard$;

-- public.fitter_job_command (md5 db9db4ca)
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
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion')
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
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
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
END $function$;

-- pdc_fitter_private.conversion_save (md5 fb4d6cd8)
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_save(p_tech uuid, p_booking uuid, p_line text, p_change jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; l jsonb; c jsonb; sec jsonb; oldstate pdc_fitter_private.conversion_state;
 beforej jsonb; sections jsonb; meta jsonb; valuej jsonb; mode text:=p_change->>'mode'; k text; v numeric;
 sk text; all_done boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 PERFORM public.workshop_require_planner_operator();
 IF NOT pdc_fitter_private.assigned(p_booking,p_tech) THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking FOR UPDATE;
 IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
 SELECT x INTO l FROM jsonb_array_elements(pdc_fitter_private.lines(b.vehicle_id,b.id)) x WHERE x->>'line_identity'=p_line AND x->>'stage_code'='BUS_4X4';
 IF l IS NULL OR l->'conversion' IS NULL OR coalesce((l#>>'{conversion,needs_review}')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'error','conversion_model_review'); END IF;
 c:=l->'conversion';
 -- Section state lives under the conversion's own scope hash (the one
 -- conversion_view reads). #381 left the line on its source hash.
 sk:=coalesce(c->>'scope_hash',l->>'scope_hash');
 SELECT * INTO oldstate FROM pdc_fitter_private.conversion_state WHERE vehicle_id=b.vehicle_id AND line_identity=p_line AND scope_hash=sk FOR UPDATE;
 beforej:=coalesce(to_jsonb(oldstate),'{}'); sections:=coalesce(oldstate.sections,'{}'); meta:=coalesce(oldstate.metadata,'{}');
 IF mode='section' THEN
  SELECT x INTO sec FROM jsonb_array_elements(c->'sections') x WHERE x->>'id'=p_change->>'section';
  IF sec IS NULL OR coalesce(p_change->>'status','') NOT IN ('not_started','in_progress','complete') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  FOR k IN SELECT unnest(ARRAY['actual_minutes','remaining_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>60000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
  END LOOP;
  IF p_change->>'status'='complete' AND (nullif(btrim(p_change->>'deferred'),'') IS NOT NULL OR nullif(btrim(p_change->>'blocker'),'') IS NOT NULL) THEN RETURN jsonb_build_object('ok',false,'error','conversion_deferred'); END IF;
  IF p_change->>'status'='complete' AND sec->>'id'='12' AND nullif(meta->>'checklist_reference','') IS NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF length(coalesce(p_change->>'note',''))>500 OR length(coalesce(p_change->>'deferred',''))>500 OR length(coalesce(p_change->>'blocker',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  valuej:=jsonb_build_object('status',p_change->>'status','actual_minutes',p_change->'actual_minutes',
    'remaining_minutes',CASE WHEN p_change->>'status'='complete' THEN '0'::jsonb WHEN p_change->>'status'='not_started' THEN sec->'planned_minutes' ELSE coalesce(p_change->'remaining_minutes','null'::jsonb) END,
    'deferred',btrim(coalesce(p_change->>'deferred','')),'blocker',btrim(coalesce(p_change->>'blocker','')),'note',coalesce(p_change->>'note',''),
    'technician_id',p_tech,'technician',(SELECT name FROM public.workshop_technicians WHERE id=p_tech),'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  sections:=jsonb_set(sections,ARRAY[sec->>'id'],valuej);

 ELSIF mode='tick' THEN
  -- Coaster / HiAce: each section is its own simple item. step 'start' begins
  -- it (one section in progress per conversion), 'done' records the actual
  -- workshop time since start, 'reset' unticks it, 'note' saves a note only.
  IF coalesce(c->>'id','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  SELECT x INTO sec FROM jsonb_array_elements(c->'sections') x WHERE x->>'id'=p_change->>'section';
  IF sec IS NULL OR coalesce(p_change->>'step','') NOT IN ('start','done','reset','note') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  IF p_change ? 'note' AND (jsonb_typeof(p_change->'note')<>'string' OR length(p_change->>'note')>500) THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  valuej:=coalesce(sections->(sec->>'id'),'{}');
  IF p_change->>'step'='start' THEN
   IF coalesce(valuej->>'status','')='complete' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   IF EXISTS(SELECT 1 FROM jsonb_each(sections) x WHERE x.key<>sec->>'id' AND x.value->>'status'='in_progress') THEN
    RETURN jsonb_build_object('ok',false,'error','conversion_section_in_progress'); END IF;
   IF coalesce(valuej->>'status','')<>'in_progress' THEN
    valuej:=valuej||jsonb_build_object('status','in_progress','started_at',clock_timestamp(),'completed_at',NULL,'remaining_minutes',sec->'planned_minutes');
   END IF;
  ELSIF p_change->>'step'='note' THEN
   NULL; -- note only, status and times unchanged
  ELSIF p_change->>'step'='done' THEN
   IF coalesce(valuej->>'status','')<>'complete' THEN
   valuej:=valuej||jsonb_build_object('status','complete','completed_at',clock_timestamp(),'remaining_minutes',0,
    'actual_minutes',CASE WHEN valuej->>'status'='in_progress' AND valuej->>'started_at' IS NOT NULL
     THEN to_jsonb(round(pdc_fitter_private.operational_seconds((valuej->>'started_at')::timestamptz,clock_timestamp())/60.0,2))
     ELSE coalesce(valuej->'actual_minutes','null'::jsonb) END);
   END IF;
  ELSE
   valuej:=valuej||jsonb_build_object('status','not_started','started_at',NULL,'completed_at',NULL,'actual_minutes',NULL,'remaining_minutes',sec->'planned_minutes');
  END IF;
  valuej:=valuej||jsonb_build_object('technician_id',p_tech,'technician',(SELECT name FROM public.workshop_technicians WHERE id=p_tech),'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  IF p_change ? 'note' THEN valuej:=valuej||jsonb_build_object('note',p_change->>'note'); END IF;
  sections:=jsonb_set(sections,ARRAY[sec->>'id'],valuej);
 ELSIF mode='planning' THEN
  -- Cumulative additional time is separate from conversion labour. Delay remaining is prospective, not elapsed waiting.
  FOR k IN SELECT unnest(ARRAY['helper_minutes','parts_delay_minutes','waiting_minutes','repair_minutes','rework_minutes','delay_remaining_minutes','available_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>600000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
   meta:=jsonb_set(meta,ARRAY[k],coalesce(p_change->k,'null'::jsonb));
  END LOOP;
  IF p_change->>'promised_at' IS NOT NULL THEN PERFORM (p_change->>'promised_at')::timestamptz; END IF;
  IF length(coalesce(p_change->>'note',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  meta:=meta||jsonb_build_object('promised_at',p_change->>'promised_at','capacity_as_of',clock_timestamp(),'planning_note',coalesce(p_change->>'note',''),
   'comparable',coalesce((p_change->>'comparable')::boolean,true),'planning_updated_by',auth.uid(),'planning_technician_id',p_tech);
 ELSIF mode='checklist' THEN
  IF coalesce(public.current_pdc_user_role()::text,'') NOT IN ('operator','administrator') THEN RETURN jsonb_build_object('ok',false,'error','conversion_controller_required'); END IF;
  IF length(btrim(coalesce(p_change->>'reference','')))<5 OR length(btrim(coalesce(p_change->>'scope','')))<10 OR length(p_change->>'reference')>500 OR length(p_change->>'scope')>1000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF sections#>>'{12,status}'='complete' THEN RETURN jsonb_build_object('ok',false,'error','conversion_reopen_section'); END IF;
  meta:=meta||jsonb_build_object('checklist_reference',btrim(p_change->>'reference'),'checklist_scope',btrim(p_change->>'scope'),'checklist_confirmed_by',auth.uid(),'checklist_confirmed_at',clock_timestamp());
 ELSE RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
 INSERT INTO pdc_fitter_private.conversion_state(vehicle_id,line_identity,scope_hash,template_id,template_version,sections,metadata,updated_by)
 VALUES(b.vehicle_id,p_line,sk,c->>'id',c->>'version',sections,meta,auth.uid())
 ON CONFLICT(vehicle_id,line_identity,scope_hash) DO UPDATE SET sections=excluded.sections,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=clock_timestamp()
  WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
 INSERT INTO pdc_fitter_private.conversion_audit(vehicle_id,line_identity,scope_hash,booking_id,technician_id,actor_id,action,before_state,after_state)
 VALUES(b.vehicle_id,p_line,sk,b.id,p_tech,auth.uid(),mode,beforej,jsonb_build_object('sections',sections,'metadata',meta));
 IF mode='tick' THEN
  -- The bay item is complete when every section is ticked. Ticking a section
  -- never clears an existing whole-item tick; resetting one reopens the item.
  all_done:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c->'sections') x
   WHERE coalesce(sections#>>ARRAY[x->>'id','status'],'')<>'complete');
  IF all_done THEN
   INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
   VALUES(b.id,p_line,l->>'scope_hash',true,coalesce(l->>'note',''),p_tech,auth.uid())
   ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,completed=true,
    technician_id=excluded.technician_id,updated_by=excluded.updated_by,updated_at=clock_timestamp()
    WHERE true;
  ELSIF p_change->>'step'='reset' THEN
   UPDATE pdc_fitter_private.operation_progress SET completed=false,technician_id=p_tech,updated_by=auth.uid(),updated_at=clock_timestamp()
   WHERE booking_id=b.id AND line_identity=p_line AND completed;
  END IF;
 END IF;
 UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true);
END $function$;

-- pdc_fitter_private.conversion_enrich (md5 2f156fdc)
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid, p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE c jsonb; ticked boolean; rows jsonb:='[]'; s jsonb; el numeric; total numeric:=0; credit numeric:=0; done integer:=0; n integer:=0;
BEGIN
 c := pdc_fitter_private.conversion_view(p_vehicle, p_line);
 IF c IS NULL THEN RETURN p_line; END IF;
 -- Matched Coaster and HiAce templates: each section is its own tick. The
 -- source scope hash stays on the line so the item tick matches
 -- operation_progress. Progress = ticked sections' allowances plus the
 -- in-progress section's elapsed workshop time (capped at its allowance).
 -- Review / conflicting conversions keep the section-and-checklist gate.
 IF c->>'id' IN ('coaster', 'hiace_commuter') AND coalesce((c->>'needs_review')::boolean, false) = false THEN
  ticked := coalesce((p_line->>'completed')::boolean, false);
  FOR s IN SELECT value FROM jsonb_array_elements(c->'sections') LOOP
   n := n + 1; total := total + coalesce((s->>'planned_minutes')::numeric, 0);
   IF s->>'status' = 'complete' THEN
    done := done + 1; credit := credit + coalesce((s->>'planned_minutes')::numeric, 0);
   ELSIF s->>'status' = 'in_progress' AND s->>'started_at' IS NOT NULL THEN
    el := round(pdc_fitter_private.operational_seconds((s->>'started_at')::timestamptz, statement_timestamp()) / 60.0, 2);
    s := s || jsonb_build_object('elapsed_minutes', el);
    credit := credit + least(el, coalesce((s->>'planned_minutes')::numeric, 0));
   END IF;
   rows := rows || jsonb_build_array(s);
  END LOOP;
  c := c || jsonb_build_object('sections', rows, 'sections_done', done, 'sections_total', n);
  RETURN p_line || jsonb_build_object('conversion', c, 'completed', ticked,
   'completed_fraction', CASE WHEN ticked THEN 1 WHEN total > 0 THEN least(0.99, round(credit / total, 4)) ELSE 0 END);
 END IF;
 RETURN p_line || jsonb_build_object('conversion', c,
  'scope_hash', coalesce(c->>'scope_hash', md5((p_line->>'scope_hash') || ':model-review')),
  'completed', coalesce((c->>'complete')::boolean, false),
  'completed_fraction', CASE WHEN (c->>'total_minutes')::numeric > 0
   THEN least(0.99, (c->>'completed_planned_minutes')::numeric / (c->>'total_minutes')::numeric)
   ELSE 0 END);
END
$function$;

-- pdc_fitter_private.lines_before_bus_workflow_20260921 (CRLF body, md5 6154aaf1)
DO $restore$
BEGIN
 EXECUTE replace($def$
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
 )
 SELECT coalesce(jsonb_agg(pdc_fitter_private.conversion_enrich(p_vehicle_id,jsonb_build_object(
  'line_identity',s.l->>'line_identity','description',s.l->>'description',
  'stage_code',s.l->>'stage_code','hours',s.l->'estimated_hours',
  'operation_no',s.l->'operation_no','source_note',s.l->>'review_note',
  'scope_hash',s.scope_hash,'completed',coalesce(p.completed AND p.scope_hash=s.scope_hash,false),
  'note',coalesce(p.note,''),'scope_changed',p.scope_hash IS NOT NULL AND p.scope_hash<>s.scope_hash,
  'updated_at',p.updated_at,'technician_id',p.technician_id
 )) ORDER BY s.l->>'stage_code',s.l->>'operation_no',s.l->>'line_identity'),'[]'::jsonb)
 FROM source s LEFT JOIN pdc_fitter_private.operation_progress p
   ON p.booking_id=p_booking_id AND p.line_identity=s.l->>'line_identity'
$function$
$def$, E'\n', E'\r\n');
END $restore$;

-- pdc_fitter_private.progress (CRLF body, md5 b388403d)
DO $restore$
BEGIN
 EXECUTE replace($def$
CREATE OR REPLACE FUNCTION pdc_fitter_private.progress(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text;
BEGIN
 -- Avoid rebuilding operation catalogues for the many bookings with no fitter work.
 IF NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress WHERE booking_id=p_booking_id) AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.conversion_state cs JOIN public.workshop_bookings cb ON cb.vehicle_id=cs.vehicle_id WHERE cb.id=p_booking_id) THEN RETURN NULL; END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 RETURN pdc_fitter_private.summary(pdc_fitter_private.lines(b.vehicle_id,b.id),code);
END $function$
$def$, E'\n', E'\r\n');
END $restore$;

DROP FUNCTION IF EXISTS public.reset_fitter_item_timing(uuid,text,text,text);
DROP FUNCTION IF EXISTS pdc_fitter_private.item_timing_save(uuid,uuid,jsonb,text,text);
DROP FUNCTION IF EXISTS pdc_fitter_private.item_timing_tick(uuid,text,text,boolean);
DROP FUNCTION IF EXISTS pdc_fitter_private.item_timing(pdc_fitter_private.operation_timing,text,jsonb,numeric);

DO $post$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')
     IS DISTINCT FROM 'db9db4ca6a63161d873480edf8a078b6' THEN
    RAISE EXCEPTION 'fitter_job_command_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS DISTINCT FROM 'fb4d6cd82f40ee27476186e0ac5b05f4' THEN
    RAISE EXCEPTION 'conversion_save_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS DISTINCT FROM '2f156fdc1cafc810d60637f50b346f12' THEN
    RAISE EXCEPTION 'conversion_enrich_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines_before_bus_workflow_20260921')
     IS DISTINCT FROM '6154aaf1490f5d49acfc3a5f3232edc2' THEN
    RAISE EXCEPTION 'lines_before_bus_workflow_20260921_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'progress')
     IS DISTINCT FROM 'b388403d94d1adbb5c01fd4cb979ebd2' THEN
    RAISE EXCEPTION 'progress_not_restored';
  END IF;
END $post$;
