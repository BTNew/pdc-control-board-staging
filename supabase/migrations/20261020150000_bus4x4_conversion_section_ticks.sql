-- Coaster and HiAce 4x4 conversions: each section is its own tick box in a
-- dropdown under the job (Start -> animated bar -> Done, actual time kept).
-- Replaces the single 40-hour checkbox from #381. The item completes when all
-- sections are done; an item already ticked whole under #381 stays ticked.
-- Changes only pdc_fitter_private.conversion_enrich and conversion_save.
-- Section rows key on the conversion scope hash that conversion_view reads.
-- start_workshop_work_pre_116, fitter_job_command, the completion guard,
-- conversion_view/catalog, apply_service_pmb_complete, finish_tune_checkout
-- and workshop_clock_tick are not touched.
--
-- Rollback: supabase/rollbacks/20261020150000_bus4x4_conversion_section_ticks.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'start_workshop_work_pre_116')
     IS DISTINCT FROM '40ab1b0a75d347b56c69e54c65ddd193' THEN
    RAISE EXCEPTION 'start_workshop_work_pre_116_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_view')
     IS DISTINCT FROM '45b3b8f43a2a630cca14466c1a9e1567' THEN
    RAISE EXCEPTION 'conversion_view_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_completion_guard')
     IS DISTINCT FROM 'befe9ecce7ea624be54b9c637a8b15df' THEN
    RAISE EXCEPTION 'conversion_completion_guard_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')
     IS DISTINCT FROM 'db9db4ca6a63161d873480edf8a078b6' THEN
    RAISE EXCEPTION 'fitter_job_command_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'operational_seconds')
     IS DISTINCT FROM '650b7df281eb4526c6d99ee497313515' THEN
    RAISE EXCEPTION 'operational_seconds_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_catalog')
     IS DISTINCT FROM 'b7789961f5e49d09b854ce7582d34e83' THEN
    RAISE EXCEPTION 'conversion_catalog_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'apply_service_pmb_complete')
     IS DISTINCT FROM 'eea5bb523c2538742db52508665191d3' THEN
    RAISE EXCEPTION 'apply_service_pmb_complete_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'finish_tune_checkout')
     IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82' THEN
    RAISE EXCEPTION 'finish_tune_checkout_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS DISTINCT FROM '5bc5a3372f0d9ce7e25d1717ec027f6e' THEN
    RAISE EXCEPTION 'conversion_enrich_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS DISTINCT FROM 'c49e4557e6b5d978352476e36589731b' THEN
    RAISE EXCEPTION 'conversion_save_changed';
  END IF;
END $guard$;

-- SECTION TICKS APPLY
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid, p_line jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
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
$fn$;

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
-- END SECTION TICKS APPLY

DO $post$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'start_workshop_work_pre_116')
     IS DISTINCT FROM '40ab1b0a75d347b56c69e54c65ddd193' THEN
    RAISE EXCEPTION 'start_workshop_work_pre_116_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_view')
     IS DISTINCT FROM '45b3b8f43a2a630cca14466c1a9e1567' THEN
    RAISE EXCEPTION 'conversion_view_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_completion_guard')
     IS DISTINCT FROM 'befe9ecce7ea624be54b9c637a8b15df' THEN
    RAISE EXCEPTION 'conversion_completion_guard_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')
     IS DISTINCT FROM 'db9db4ca6a63161d873480edf8a078b6' THEN
    RAISE EXCEPTION 'fitter_job_command_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'operational_seconds')
     IS DISTINCT FROM '650b7df281eb4526c6d99ee497313515' THEN
    RAISE EXCEPTION 'operational_seconds_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_catalog')
     IS DISTINCT FROM 'b7789961f5e49d09b854ce7582d34e83' THEN
    RAISE EXCEPTION 'conversion_catalog_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'apply_service_pmb_complete')
     IS DISTINCT FROM 'eea5bb523c2538742db52508665191d3' THEN
    RAISE EXCEPTION 'apply_service_pmb_complete_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'finish_tune_checkout')
     IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82' THEN
    RAISE EXCEPTION 'finish_tune_checkout_changed';
  END IF;
  IF position('''sections_done''' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')) = 0 THEN
    RAISE EXCEPTION 'conversion_enrich_not_applied';
  END IF;
  IF position('mode=''tick''' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')) = 0 THEN
    RAISE EXCEPTION 'conversion_save_not_applied';
  END IF;
END $post$;
