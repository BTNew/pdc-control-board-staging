-- r568 (F182) / sort 339. Go-live. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- A Hiace or Coaster Bus 4x4 component's line items can start on one Bus bay and finish on another,
-- the same idea as electrical ticked from a fitting bay (r532). This does not replace fitter_job_command,
-- conversion_save, or set_vehicle_work_category. Pin count stays 241.
-- The Bus 4x4 board tile is one station for every component. This release does not tick that tile,
-- does not cancel or complete a booking, and does not delete, hide, or close a vehicle or a job card.
-- The preview claimed r565 / F179 / sort 339. r565 / F179 / sort 337 is the live panel tick.
-- r567 / F181 / sort 338 is the typed Parts ETA. This release is r568 / F182 / sort 339.
-- Object names stay _565 so the preview prosrc md5s still match.
-- The check uses pg_catalog.strpos because pg_catalog.position(x IN y) does not parse.
-- Undo: supabase/rollbacks/20261027180000_r565_bus_component_split.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r568: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r568: staging only'; END IF;
 IF EXISTS (SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE project_ref='vjdtsswhroyguxyfjdkt') THEN RAISE EXCEPTION 'r568: production sentinel refused'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r568: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r568: fitter_job_command is not the r532 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.conversion_save(uuid,uuid,text,jsonb)')) IS DISTINCT FROM '39b8f50d21d7932e671c31a5d539001d' THEN RAISE EXCEPTION 'r568: conversion_save changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) IS DISTINCT FROM '240e25e96467490d71744490c7a4d75c' THEN RAISE EXCEPTION 'r568: set_vehicle_work_category is not the r538 pin'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=339 OR check_name='bus_component_split_568' OR added_in='r568' OR fault_id='F182') THEN RAISE EXCEPTION 'r568: sort 339 or F182 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='panel_line_completion_565' AND fault_id='F179' AND sort_order=337 AND added_in='r565') THEN RAISE EXCEPTION 'r568: r565 / F179 sort 337 is not the live panel check'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_stoppage_manual_567' AND fault_id='F181' AND sort_order=338 AND added_in='r567') THEN RAISE EXCEPTION 'r568: r567 / F181 sort 338 is not the live check'; END IF;
 IF to_regprocedure('public.get_pdc_bus_component_board_565(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r568: already applied'; END IF;
END $g$;

CREATE FUNCTION public.get_pdc_bus_component_board_565(p_booking uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $board565$
DECLARE
 b public.workshop_bookings;
 stage text;
 busy_map jsonb := '{}'::jsonb;
 items jsonb := '[]'::jsonb;
 rec record;
 enriched jsonb;
 sec jsonb;
 cat text;
 scope text;
 running_bay text;
 running_booking uuid;
 line_done boolean;
BEGIN
 -- r565 (F179): other Bus 4x4 components on this running bay. Read only.
 PERFORM public.require_pdc_role('viewer');
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking AND deleted_at IS NULL;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','booking_not_found'); END IF;
 SELECT s.code INTO stage FROM public.workshop_stages s WHERE s.id=b.stage_id;
 IF stage IS DISTINCT FROM 'BUS_4X4' OR b.work_category IS NULL OR b.work_category IN ('BUS_WHOLE_JOB','BUS_PIT') THEN
  RETURN jsonb_build_object('ok',true,'booking_id',b.id,'own_category',b.work_category,'items','[]'::jsonb,'reason','use_own_card');
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id=b.vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL) THEN
  RETURN jsonb_build_object('ok',false,'code','vehicle_not_found');
 END IF;
 SELECT coalesce(jsonb_object_agg(c.cat, EXISTS (
   SELECT 1 FROM public.workshop_bookings ob
   JOIN public.workshop_stages os ON os.id=ob.stage_id
   WHERE ob.vehicle_id=b.vehicle_id AND ob.deleted_at IS NULL AND os.code='BUS_4X4'
     AND ob.work_category=c.cat AND ob.status IN ('started','stoppage') AND ob.id IS DISTINCT FROM b.id)), '{}'::jsonb)
  INTO busy_map
 FROM (VALUES ('BUS_MECHANICAL'),('BUS_ACCESSORIES'),('BUS_ELECTRICAL'),('BUS_QA')) c(cat);
 FOR rec IN
  SELECT l AS line,
   md5(jsonb_build_array(l->>'line_identity',l->>'description',l->>'stage_code',l->'estimated_hours',l->>'job_card_number')::text) AS scope_hash
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(b.vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true)
    AND l->>'stage_code'='BUS_4X4'
    AND l->>'work_category' IN ('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA')
    AND l->>'work_category' IS DISTINCT FROM b.work_category
  ORDER BY l->>'work_category', l->>'operation_no', l->>'line_identity'
 LOOP
  cat := rec.line->>'work_category';
  scope := rec.scope_hash;
  enriched := pdc_fitter_private.conversion_enrich(b.vehicle_id, jsonb_build_object(
   'line_identity', rec.line->>'line_identity', 'description', rec.line->>'description',
   'stage_code', rec.line->>'stage_code', 'hours', rec.line->'estimated_hours',
   'operation_no', rec.line->'operation_no', 'scope_hash', scope, 'job_card_number', rec.line->>'job_card_number'));
  IF coalesce((enriched#>>'{conversion,needs_review}')::boolean,false) THEN CONTINUE; END IF;
  IF enriched->'conversion'->>'id' IN ('coaster','hiace_commuter') THEN
   FOR sec IN SELECT value FROM jsonb_array_elements(coalesce(enriched->'conversion'->'sections','[]'::jsonb)) LOOP
    items := items || jsonb_build_array(jsonb_build_object(
     'kind','section','category',cat,
     'category_label', CASE cat WHEN 'BUS_MECHANICAL' THEN 'Mechanical' WHEN 'BUS_ACCESSORIES' THEN 'Accessories' WHEN 'BUS_ELECTRICAL' THEN 'Electrical' WHEN 'BUS_QA' THEN 'QA' ELSE cat END,
     'home_busy', coalesce((busy_map->>cat)::boolean,false),
     'line_identity', rec.line->>'line_identity', 'line_description', rec.line->>'description',
     'section_id', sec->>'id', 'section_label', sec->>'label', 'section_description', sec->>'description',
     'status', coalesce(sec->>'status','not_started'),
     'started_booking_id', sec->>'started_booking_id',
     'started_bay', (SELECT coalesce(bay.display_name, 'Bay '||bay.bay_number::text) FROM public.workshop_bookings bk LEFT JOIN public.workshop_bays bay ON bay.id=bk.bay_id WHERE bk.id=(sec->>'started_booking_id')::uuid AND bk.deleted_at IS NULL),
     'finished_booking_id', sec->>'finished_booking_id',
     'finished_bay', (SELECT coalesce(bay.display_name, 'Bay '||bay.bay_number::text) FROM public.workshop_bookings bk LEFT JOIN public.workshop_bays bay ON bay.id=bk.bay_id WHERE bk.id=(sec->>'finished_booking_id')::uuid AND bk.deleted_at IS NULL)));
   END LOOP;
   CONTINUE;
  END IF;
  IF enriched->'conversion' IS NOT NULL THEN CONTINUE; END IF;
  SELECT t.booking_id, coalesce(bay.display_name, 'Bay '||bay.bay_number::text)
   INTO running_booking, running_bay
  FROM pdc_fitter_private.operation_timing t
  JOIN public.workshop_bookings wb ON wb.id=t.booking_id
  LEFT JOIN public.workshop_bays bay ON bay.id=wb.bay_id
  WHERE wb.vehicle_id=b.vehicle_id AND wb.deleted_at IS NULL AND t.line_identity=rec.line->>'line_identity' AND t.status='running'
  ORDER BY t.updated_at DESC
  LIMIT 1;
  line_done := EXISTS (
   SELECT 1 FROM pdc_fitter_private.operation_progress p
   JOIN public.workshop_bookings wb ON wb.id=p.booking_id
   WHERE wb.vehicle_id=b.vehicle_id AND wb.deleted_at IS NULL
     AND p.line_identity=rec.line->>'line_identity' AND p.completed AND p.scope_hash=scope);
  items := items || jsonb_build_array(jsonb_build_object(
   'kind','line','category',cat,
   'category_label', CASE cat WHEN 'BUS_MECHANICAL' THEN 'Mechanical' WHEN 'BUS_ACCESSORIES' THEN 'Accessories' WHEN 'BUS_ELECTRICAL' THEN 'Electrical' WHEN 'BUS_QA' THEN 'QA' ELSE cat END,
   'home_busy', coalesce((busy_map->>cat)::boolean,false),
   'line_identity', rec.line->>'line_identity', 'description', rec.line->>'description',
   'hours', rec.line->'estimated_hours', 'completed', line_done,
   'item_status', CASE WHEN line_done THEN 'done' WHEN running_booking IS NOT NULL THEN 'running' ELSE 'idle' END,
   'started_booking_id', running_booking, 'started_bay', running_bay));
  running_booking := NULL; running_bay := NULL;
 END LOOP;
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'own_category',b.work_category,'items',items);
END
$board565$;

REVOKE ALL ON FUNCTION public.get_pdc_bus_component_board_565(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_bus_component_board_565(uuid) TO authenticated;

CREATE FUNCTION public.set_pdc_bus_component_line_565(p_booking uuid, p_technician uuid, p_line text, p_section text, p_step text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $set565$
DECLARE
 b public.workshop_bookings;
 v public.vehicles;
 stage text;
 line jsonb;
 enriched jsonb;
 conv jsonb;
 sec jsonb;
 cat text;
 scope text;
 sk text;
 oldstate pdc_fitter_private.conversion_state;
 sections jsonb;
 valuej jsonb;
 host_status text;
 host_booking uuid;
 secs numeric;
BEGIN
 -- r565 (F179): start or finish another Bus component from this bay. No booking is cancelled or completed.
 IF auth.uid() IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 PERFORM public.workshop_require_planner_operator();
 IF p_step IS NULL OR p_step NOT IN ('start','done','reset') THEN RETURN jsonb_build_object('ok',false,'code','bad_step'); END IF;
 IF p_line IS NULL OR length(p_line)>200 THEN RETURN jsonb_build_object('ok',false,'code','line_unavailable'); END IF;
 IF p_section IS NOT NULL AND length(p_section)>40 THEN RETURN jsonb_build_object('ok',false,'code','conversion_invalid'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 IF NOT pdc_fitter_private.assigned(p_booking, p_technician) THEN RETURN jsonb_build_object('ok',false,'code','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','booking_not_found'); END IF;
 IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'code','job_not_running'); END IF;
 SELECT s.code INTO stage FROM public.workshop_stages s WHERE s.id=b.stage_id;
 IF stage IS DISTINCT FROM 'BUS_4X4' THEN RETURN jsonb_build_object('ok',false,'code','not_bus'); END IF;
 IF b.work_category IS NULL OR b.work_category IN ('BUS_WHOLE_JOB','BUS_PIT') THEN RETURN jsonb_build_object('ok',false,'code','use_own_ticks'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=b.vehicle_id AND deleted_at IS NULL AND board_purged_at IS NULL;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 SELECT l INTO line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l
  WHERE l->>'line_identity'=p_line AND coalesce((l->>'active')::boolean,true) AND l->>'stage_code'='BUS_4X4';
 IF line IS NULL OR line->>'work_category' NOT IN ('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA') THEN
  RETURN jsonb_build_object('ok',false,'code','line_unavailable');
 END IF;
 cat := line->>'work_category';
 IF cat IS NOT DISTINCT FROM b.work_category THEN RETURN jsonb_build_object('ok',false,'code','use_own_ticks'); END IF;
 IF EXISTS (SELECT 1 FROM public.workshop_bookings ob JOIN public.workshop_stages os ON os.id=ob.stage_id
  WHERE ob.vehicle_id=v.id AND ob.deleted_at IS NULL AND os.code='BUS_4X4' AND ob.work_category=cat
    AND ob.status IN ('started','stoppage') AND ob.id IS DISTINCT FROM b.id) THEN
  RETURN jsonb_build_object('ok',false,'code','component_busy');
 END IF;
 scope := md5(jsonb_build_array(line->>'line_identity',line->>'description',line->>'stage_code',line->'estimated_hours',line->>'job_card_number')::text);
 enriched := pdc_fitter_private.conversion_enrich(v.id, jsonb_build_object(
  'line_identity', line->>'line_identity', 'description', line->>'description', 'stage_code', line->>'stage_code',
  'hours', line->'estimated_hours', 'operation_no', line->'operation_no', 'scope_hash', scope, 'job_card_number', line->>'job_card_number'));
 conv := enriched->'conversion';
 IF coalesce((conv->>'needs_review')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'code','conversion_model_review'); END IF;
 IF nullif(p_section,'') IS NOT NULL THEN
  IF conv->>'id' NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'code','conversion_invalid'); END IF;
  SELECT x INTO sec FROM jsonb_array_elements(conv->'sections') x WHERE x->>'id'=p_section;
  IF sec IS NULL THEN RETURN jsonb_build_object('ok',false,'code','conversion_invalid'); END IF;
  sk := coalesce(conv->>'scope_hash', scope);
  SELECT * INTO oldstate FROM pdc_fitter_private.conversion_state WHERE vehicle_id=v.id AND line_identity=p_line AND scope_hash=sk FOR UPDATE;
  sections := coalesce(oldstate.sections,'{}'::jsonb);
  valuej := coalesce(sections->p_section,'{}'::jsonb);
  IF p_step='start' THEN
   IF coalesce(valuej->>'status','')='complete' THEN RETURN jsonb_build_object('ok',false,'code','conversion_invalid'); END IF;
   IF coalesce(valuej->>'status','')<>'in_progress' THEN
    valuej := valuej || jsonb_build_object('status','in_progress','started_at',clock_timestamp(),'completed_at',NULL,
     'remaining_minutes', sec->'planned_minutes','started_booking_id',b.id,'started_by',auth.uid());
   END IF;
  ELSIF p_step='done' THEN
   IF coalesce(valuej->>'status','')='complete' THEN
    RETURN jsonb_build_object('ok',true,'changed',false,'action','done','category',cat);
   END IF;
   valuej := valuej || jsonb_build_object('status','complete','completed_at',clock_timestamp(),'remaining_minutes',0,
    'finished_booking_id',b.id,'finished_by',auth.uid(),
    'actual_minutes', CASE WHEN valuej->>'status'='in_progress' AND valuej->>'started_at' IS NOT NULL
     THEN to_jsonb(round(pdc_fitter_private.operational_seconds((valuej->>'started_at')::timestamptz, clock_timestamp())/60.0, 2))
     ELSE coalesce(valuej->'actual_minutes','null'::jsonb) END);
  ELSE
   valuej := valuej || jsonb_build_object('status','not_started','started_at',NULL,'completed_at',NULL,'actual_minutes',NULL,
    'remaining_minutes', sec->'planned_minutes','started_booking_id',NULL,'finished_booking_id',NULL);
  END IF;
  valuej := valuej || jsonb_build_object('technician_id',p_technician,'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  sections := jsonb_set(sections, ARRAY[p_section], valuej);
  INSERT INTO pdc_fitter_private.conversion_state(vehicle_id,line_identity,scope_hash,template_id,template_version,sections,metadata,updated_by)
  VALUES (v.id, p_line, sk, conv->>'id', conv->>'version', sections, coalesce(oldstate.metadata,'{}'::jsonb), auth.uid())
  ON CONFLICT (vehicle_id, line_identity, scope_hash) DO UPDATE SET sections=excluded.sections, updated_by=excluded.updated_by, updated_at=clock_timestamp()
   WHERE pdc_fitter_private.conversion_state.vehicle_id=excluded.vehicle_id;
  INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,section_id,technician_id,actor_id,action,before_state,after_state)
  VALUES (b.id, p_line, p_section, p_technician, auth.uid(), 'bus_component_'||p_step, coalesce(to_jsonb(oldstate),'{}'::jsonb), jsonb_build_object('section',valuej,'category',cat));
  PERFORM public.workshop_bump_station_revision('BUS_4X4');
  PERFORM public.workshop_bump_revision();
  RETURN jsonb_build_object('ok',true,'changed',true,'action',p_step,'category',cat,'section',p_section);
 END IF;
 IF conv->>'id' IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'code','use_sections'); END IF;
 SELECT t.booking_id, wb.status INTO host_booking, host_status
 FROM pdc_fitter_private.operation_timing t
 JOIN public.workshop_bookings wb ON wb.id=t.booking_id
 WHERE wb.vehicle_id=v.id AND wb.deleted_at IS NULL AND t.line_identity=p_line AND t.status='running'
 ORDER BY t.updated_at DESC
 LIMIT 1;
 IF host_booking IS NOT NULL AND host_booking IS DISTINCT FROM b.id AND host_status IN ('started','stoppage') THEN
  RETURN jsonb_build_object('ok',false,'code','component_busy');
 END IF;
 IF p_step='start' THEN
  IF host_booking=b.id THEN RETURN jsonb_build_object('ok',true,'changed',false,'action','start','category',cat); END IF;
  IF host_booking IS NOT NULL THEN
   UPDATE pdc_fitter_private.operation_timing SET status='reset', reset_reason='Continued in another bay', updated_by=auth.uid(), updated_at=clock_timestamp()
    WHERE booking_id=host_booking AND line_identity=p_line AND status='running';
  END IF;
  secs := coalesce((pdc_fitter_private.timing(b.id, clock_timestamp())#>>'{timer,elapsed_seconds}')::numeric, 0);
  INSERT INTO pdc_fitter_private.operation_timing(booking_id,line_identity,scope_hash,technician_id,status,started_at,start_elapsed_seconds,updated_by)
  VALUES (b.id, p_line, scope, p_technician, 'running', clock_timestamp(), secs, auth.uid())
  ON CONFLICT (booking_id, line_identity) DO UPDATE SET scope_hash=excluded.scope_hash, technician_id=excluded.technician_id,
   status='running', started_at=excluded.started_at, start_elapsed_seconds=excluded.start_elapsed_seconds, completed_at=NULL,
   actual_seconds=NULL, reset_reason=NULL, updated_by=excluded.updated_by, updated_at=clock_timestamp()
   WHERE pdc_fitter_private.operation_timing.booking_id=excluded.booking_id;
 ELSIF p_step='done' THEN
  IF host_booking IS NULL AND NOT EXISTS (
    SELECT 1 FROM pdc_fitter_private.operation_progress p WHERE p.booking_id=b.id AND p.line_identity=p_line AND p.completed) THEN
   RETURN jsonb_build_object('ok',false,'code','item_not_started');
  END IF;
  IF host_booking=b.id THEN
   PERFORM pdc_fitter_private.item_timing_tick(b.id, p_line, scope, true);
  ELSIF host_booking IS NOT NULL THEN
   UPDATE pdc_fitter_private.operation_timing SET status='done', completed_at=clock_timestamp(),
    actual_seconds=round(pdc_fitter_private.operational_seconds(started_at, clock_timestamp()), 2),
    updated_by=auth.uid(), updated_at=clock_timestamp()
    WHERE booking_id=host_booking AND line_identity=p_line AND status='running';
  END IF;
  INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
  VALUES (b.id, p_line, scope, true, '', p_technician, auth.uid())
  ON CONFLICT (booking_id, line_identity) DO UPDATE SET scope_hash=excluded.scope_hash, completed=true,
   technician_id=excluded.technician_id, updated_by=excluded.updated_by, updated_at=clock_timestamp()
   WHERE pdc_fitter_private.operation_progress.booking_id=excluded.booking_id;
 ELSE
  IF host_booking IS NOT NULL AND host_booking IS DISTINCT FROM b.id THEN
   UPDATE pdc_fitter_private.operation_timing SET status='reset', reset_reason='Reset from another bay', updated_by=auth.uid(), updated_at=clock_timestamp()
    WHERE booking_id=host_booking AND line_identity=p_line AND status='running';
  END IF;
  UPDATE pdc_fitter_private.operation_timing SET status='reset', reset_reason='Reset from another bay', updated_by=auth.uid(), updated_at=clock_timestamp()
   WHERE booking_id=b.id AND line_identity=p_line AND status='running';
  UPDATE pdc_fitter_private.operation_progress SET completed=false, technician_id=p_technician, updated_by=auth.uid(), updated_at=clock_timestamp()
   WHERE booking_id=b.id AND line_identity=p_line AND completed;
 END IF;
 INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,section_id,technician_id,actor_id,action,before_state,after_state)
 VALUES (b.id, p_line, NULL, p_technician, auth.uid(), 'bus_component_'||p_step, '{}'::jsonb, jsonb_build_object('category',cat,'step',p_step));
 PERFORM public.workshop_bump_station_revision('BUS_4X4');
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true,'changed',true,'action',p_step,'category',cat);
END
$set565$;

REVOKE ALL ON FUNCTION public.set_pdc_bus_component_line_565(uuid,uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_bus_component_line_565(uuid,uuid,text,text,text) TO authenticated;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('bus_component_split_568','F182',
 'Bus 4x4 component lines (r568): a running Bus bay can start or finish another component''s line items. A component with its own started or stopped booking stays on that bay. No booking is cancelled or completed, and no vehicle or job card is removed. Pins stay.',
$chk565$
SELECT
 fn.n=2 AND fn.sd=2 AND fn.no_anon AND fn.auth_exec AND fn.path_ok
 AND pins.pin_count=241
 AND pins.fitter_cmd='626ca8b23a2e5f02e2ca8f96a4533d6f'
 AND pins.conv_save='39b8f50d21d7932e671c31a5d539001d'
 AND pins.category_set='240e25e96467490d71744490c7a4d75c'
 AND pins.board_fn='7031ac921d64cf2db16d52f3e8e02140'
 AND pins.set_fn='3ea8b27f10bfc908c410760ed22f4fed'
 AND pg_catalog.strpos(body.prosrc, 'component_busy')>0
 AND pg_catalog.strpos(body.prosrc, 'deleted_at IS NULL')>0
 AND pg_catalog.strpos(body.prosrc, 'BUS_MECHANICAL')>0
 AND pg_catalog.strpos(body.prosrc, 'UPDATE public.vehicles')=0
 AND pg_catalog.strpos(body.prosrc, 'DELETE FROM')=0
 AND pg_catalog.strpos(body.prosrc, 'cancel_workshop_booking')=0
 AND pg_catalog.strpos(body.prosrc, 'complete_workshop_work')=0
 AND pg_catalog.strpos(body.prosrc, 'coalesce')>0
 AND pg_catalog.strpos(body.prosrc, 'pg_catalog.coalesce')=0
 AS ok,
 'pins '||pins.pin_count::text AS detail
FROM (
 SELECT count(*) n,
  count(*) FILTER (WHERE p.prosecdef) sd,
  bool_and(NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')) no_anon,
  bool_and(pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')) auth_exec,
  bool_and(pg_catalog.strpos(coalesce(pg_catalog.array_to_string(p.proconfig,','),''), 'pg_catalog')>0) path_ok
 FROM pg_catalog.pg_proc p
 WHERE p.oid IN (
  pg_catalog.to_regprocedure('public.get_pdc_bus_component_board_565(uuid)'),
  pg_catalog.to_regprocedure('public.set_pdc_bus_component_line_565(uuid,uuid,text,text,text)'))
) fn
CROSS JOIN (
 SELECT
  (SELECT count(*) FROM pdc_ops.expected_function_md5) pin_count,
  (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) fitter_cmd,
  (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('pdc_fitter_private.conversion_save(uuid,uuid,text,jsonb)')) conv_save,
  (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) category_set,
  (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.get_pdc_bus_component_board_565(uuid)')) board_fn,
  (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_pdc_bus_component_line_565(uuid,uuid,text,text,text)')) set_fn
) pins
CROSS JOIN (
 SELECT prosrc FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_pdc_bus_component_line_565(uuid,uuid,text,text,text)')
) body
$chk565$,
true, 339, 'r568');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r568: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r568: fitter command changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.conversion_save(uuid,uuid,text,jsonb)')) IS DISTINCT FROM '39b8f50d21d7932e671c31a5d539001d' THEN RAISE EXCEPTION 'r568: conversion_save changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_bus_component_board_565(uuid)')) IS DISTINCT FROM '7031ac921d64cf2db16d52f3e8e02140' THEN RAISE EXCEPTION 'r568: board read changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_pdc_bus_component_line_565(uuid,uuid,text,text,text)')) IS DISTINCT FROM '3ea8b27f10bfc908c410760ed22f4fed' THEN RAISE EXCEPTION 'r568: setter changed'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 PERFORM set_config('request.jwt.claims','',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bus_component_split_568' AND fault_id='F182' AND sort_order=339 AND added_in='r568') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r568: check bus_component_split_568 not OK: %', y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
