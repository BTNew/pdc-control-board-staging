-- Restore the section-gated conversion completion path.
-- Does not change start_workshop_work_pre_116.
-- Staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF to_regprocedure('public.start_workshop_work_pre_116(uuid, integer, timestamp with time zone, jsonb)') IS NOT NULL
     AND (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'start_workshop_work_pre_116')
         IS DISTINCT FROM '40ab1b0a75d347b56c69e54c65ddd193' THEN
    RAISE EXCEPTION 'start_workshop_work_pre_116_changed';
  END IF;
  IF position('c->>''id'' IN (''coaster'', ''hiace_commuter'')' IN (
      SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')) = 0 THEN
    RAISE EXCEPTION 'conversion_enrich_not_simple_tick';
  END IF;
END $guard$;

-- SIMPLE TICK RESTORE
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid, p_line jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE c jsonb;
BEGIN
 c:=pdc_fitter_private.conversion_view(p_vehicle,p_line);
 IF c IS NULL THEN RETURN p_line; END IF;
 RETURN p_line||jsonb_build_object('conversion',c,'scope_hash',coalesce(c->>'scope_hash',md5((p_line->>'scope_hash')||':model-review')),
 'completed',coalesce((c->>'complete')::boolean,false),
 'completed_fraction',CASE WHEN (c->>'total_minutes')::numeric>0 THEN least(0.99,(c->>'completed_planned_minutes')::numeric/(c->>'total_minutes')::numeric) ELSE 0 END);
END $fn$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_completion_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $guardfn$
DECLARE bid uuid; vid uuid; stage text; l jsonb; identity text;
BEGIN
 IF TG_TABLE_NAME='workshop_bookings' THEN
  IF NEW.status<>'completed' OR (TG_OP='UPDATE' AND OLD.status='completed') THEN RETURN NEW; END IF;
  bid:=NEW.id; vid:=NEW.vehicle_id; SELECT code INTO stage FROM public.workshop_stages WHERE id=NEW.stage_id;
 ELSIF TG_TABLE_NAME='vehicle_work_items' THEN
  IF NOT NEW.completed OR (TG_OP='UPDATE' AND OLD.completed) THEN RETURN NEW; END IF;
  vid:=NEW.vehicle_id; stage:=CASE WHEN NEW.work_key='bus4x4' THEN 'BUS_4X4' END;
 ELSE
  IF NOT NEW.completed THEN RETURN NEW; END IF;
  SELECT vehicle_id INTO vid FROM public.workshop_bookings WHERE id=NEW.booking_id;
  stage:='BUS_4X4'; identity:=NEW.line_identity;
 END IF;
 IF stage IS DISTINCT FROM 'BUS_4X4' THEN RETURN NEW; END IF;
 FOR l IN SELECT x FROM jsonb_array_elements(pdc_fitter_private.lines(vid,bid)) x
 WHERE x->'conversion' IS NOT NULL AND (identity IS NULL OR x->>'line_identity'=identity) LOOP
  IF NOT coalesce((l->>'completed')::boolean,false) THEN
   RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING errcode='23514';
  END IF;
 END LOOP;
 RETURN NEW;
END $guardfn$;

DO $restore_fitter_line$
DECLARE def text; old_gate text; new_gate text; hits integer;
BEGIN
 new_gate := $new$IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;$new$;
 old_gate := $old$IF l->'conversion' IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;$old$;
 SELECT pg_get_functiondef(p.oid) INTO def
 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command';
 hits := (length(def) - length(replace(def, new_gate, ''))) / length(new_gate);
 IF hits IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'fitter_line_gate_missing'; END IF;
 EXECUTE replace(def, new_gate, old_gate);
END
$restore_fitter_line$;
-- END SIMPLE TICK RESTORE

DO $post$
BEGIN
  IF to_regprocedure('public.start_workshop_work_pre_116(uuid, integer, timestamp with time zone, jsonb)') IS NOT NULL
     AND (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'start_workshop_work_pre_116')
         IS DISTINCT FROM '40ab1b0a75d347b56c69e54c65ddd193' THEN
    RAISE EXCEPTION 'start_workshop_work_pre_116_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS DISTINCT FROM 'bc1d9f840b37882e1d3a115bf81bd411' THEN
    RAISE EXCEPTION 'conversion_enrich_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_completion_guard')
     IS DISTINCT FROM '85469fbced10980106d83b61c38b8e96' THEN
    RAISE EXCEPTION 'conversion_completion_guard_not_restored';
  END IF;
  IF position('coalesce(l#>>''{conversion,id}'','''') NOT IN (''coaster'',''hiace_commuter'')' IN (
      SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')) <> 0 THEN
    RAISE EXCEPTION 'fitter_line_gate_not_restored';
  END IF;
END $post$;
