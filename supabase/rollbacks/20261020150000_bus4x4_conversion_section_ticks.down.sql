-- Undo 20261020150000_bus4x4_conversion_section_ticks: restore the #381
-- conversion_enrich and conversion_save bodies. Section rows recorded by the
-- tick mode and any item ticks stay stored (nothing is deleted).
-- Staging cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF position('''sections_done''' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')) = 0
   OR position('mode=''tick''' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')) = 0 THEN
    RAISE EXCEPTION 'section_ticks_not_applied';
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid, p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE c jsonb; ticked boolean;
BEGIN
 c := pdc_fitter_private.conversion_view(p_vehicle, p_line);
 IF c IS NULL THEN RETURN p_line; END IF;
 -- Matched Coaster and HiAce templates follow the parent checkbox. The
 -- source scope hash stays on the line so the tick matches operation_progress.
 -- Review / conflicting conversions keep the section-and-checklist gate.
 IF c->>'id' IN ('coaster', 'hiace_commuter') AND coalesce((c->>'needs_review')::boolean, false) = false THEN
  ticked := coalesce((p_line->>'completed')::boolean, false);
  RETURN p_line || jsonb_build_object('conversion', c, 'completed', ticked,
   'completed_fraction', CASE WHEN ticked THEN 1 ELSE 0 END);
 END IF;
 RETURN p_line || jsonb_build_object('conversion', c,
  'scope_hash', coalesce(c->>'scope_hash', md5((p_line->>'scope_hash') || ':model-review')),
  'completed', coalesce((c->>'complete')::boolean, false),
  'completed_fraction', CASE WHEN (c->>'total_minutes')::numeric > 0
   THEN least(0.99, (c->>'completed_planned_minutes')::numeric / (c->>'total_minutes')::numeric)
   ELSE 0 END);
END
$function$;

-- The saved #381 body uses CRLF line endings; rebuild them so the restored
-- prosrc md5 is exactly c49e4557.
DO $restore$
BEGIN
 EXECUTE replace($def$CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_save(p_tech uuid, p_booking uuid, p_line text, p_change jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; l jsonb; c jsonb; sec jsonb; oldstate pdc_fitter_private.conversion_state;
 beforej jsonb; sections jsonb; meta jsonb; valuej jsonb; mode text:=p_change->>'mode'; k text; v numeric;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 PERFORM public.workshop_require_planner_operator();
 IF NOT pdc_fitter_private.assigned(p_booking,p_tech) THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking FOR UPDATE;
 IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
 SELECT x INTO l FROM jsonb_array_elements(pdc_fitter_private.lines(b.vehicle_id,b.id)) x WHERE x->>'line_identity'=p_line AND x->>'stage_code'='BUS_4X4';
 IF l IS NULL OR l->'conversion' IS NULL OR coalesce((l#>>'{conversion,needs_review}')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'error','conversion_model_review'); END IF;
 c:=l->'conversion';
 SELECT * INTO oldstate FROM pdc_fitter_private.conversion_state WHERE vehicle_id=b.vehicle_id AND line_identity=p_line AND scope_hash=l->>'scope_hash' FOR UPDATE;
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
 VALUES(b.vehicle_id,p_line,l->>'scope_hash',c->>'id',c->>'version',sections,meta,auth.uid())
 ON CONFLICT(vehicle_id,line_identity,scope_hash) DO UPDATE SET sections=excluded.sections,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 INSERT INTO pdc_fitter_private.conversion_audit(vehicle_id,line_identity,scope_hash,booking_id,technician_id,actor_id,action,before_state,after_state)
 VALUES(b.vehicle_id,p_line,l->>'scope_hash',b.id,p_tech,auth.uid(),mode,beforej,jsonb_build_object('sections',sections,'metadata',meta));
 UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true);
END $function$$def$, E'\n', E'\r\n');
END $restore$;

DO $post$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS DISTINCT FROM '5bc5a3372f0d9ce7e25d1717ec027f6e' THEN
    RAISE EXCEPTION 'conversion_enrich_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS DISTINCT FROM 'c49e4557e6b5d978352476e36589731b' THEN
    RAISE EXCEPTION 'conversion_save_not_restored';
  END IF;
END $post$;
