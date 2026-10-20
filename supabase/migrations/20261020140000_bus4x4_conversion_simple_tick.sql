-- Coaster and HiAce 4x4 conversions complete from the same fitter checkbox as
-- the other bay items. Section rows, audit history and the catalog allowances
-- stay. Booking duration is untouched: it still comes from the operation's
-- approved hours, not from the 62h 45m / 38h section allowances.
--
-- start_workshop_work_pre_116 is pinned and not replaced (#380).
-- apply_service_pmb_complete, finish_tune_checkout and conversion_save are
-- pinned and not replaced. Sub Status 80/99 still skip QC, RFT and completed
-- vehicles, and Sub Status 99 still leaves qc / qc_signoff work items open.
--
-- Rollback: supabase/rollbacks/20261020140000_bus4x4_conversion_simple_tick.down.sql
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
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS DISTINCT FROM 'bc1d9f840b37882e1d3a115bf81bd411' THEN
    RAISE EXCEPTION 'conversion_enrich_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_completion_guard')
     IS DISTINCT FROM '85469fbced10980106d83b61c38b8e96' THEN
    RAISE EXCEPTION 'conversion_completion_guard_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')
     IS DISTINCT FROM 'ba8e6f44809966ab8980361e1c31de97' THEN
    RAISE EXCEPTION 'fitter_job_command_changed';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command') <> 1 THEN
    RAISE EXCEPTION 'fitter_job_command_overload';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_catalog')
     IS DISTINCT FROM 'b7789961f5e49d09b854ce7582d34e83' THEN
    RAISE EXCEPTION 'conversion_catalog_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS DISTINCT FROM 'c49e4557e6b5d978352476e36589731b' THEN
    RAISE EXCEPTION 'conversion_save_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'minutes')
     IS DISTINCT FROM '0c8423441e81705290d74f4a85c78ea2' THEN
    RAISE EXCEPTION 'booking_minutes_changed';
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
END $guard$;

-- SIMPLE TICK APPLY
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid, p_line jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
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
$fn$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_completion_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE bid uuid; vid uuid; stage text; l jsonb; identity text;
BEGIN
 IF TG_TABLE_NAME = 'workshop_bookings' THEN
  IF NEW.status <> 'completed' OR (TG_OP = 'UPDATE' AND OLD.status = 'completed') THEN RETURN NEW; END IF;
  bid := NEW.id; vid := NEW.vehicle_id; SELECT code INTO stage FROM public.workshop_stages WHERE id = NEW.stage_id;
 ELSIF TG_TABLE_NAME = 'vehicle_work_items' THEN
  IF NOT NEW.completed OR (TG_OP = 'UPDATE' AND OLD.completed) THEN RETURN NEW; END IF;
  vid := NEW.vehicle_id; stage := CASE WHEN NEW.work_key = 'bus4x4' THEN 'BUS_4X4' END;
 ELSE
  IF NOT NEW.completed THEN RETURN NEW; END IF;
  SELECT vehicle_id INTO vid FROM public.workshop_bookings WHERE id = NEW.booking_id;
  stage := 'BUS_4X4'; identity := NEW.line_identity;
 END IF;
 IF stage IS DISTINCT FROM 'BUS_4X4' THEN RETURN NEW; END IF;
 FOR l IN SELECT x FROM jsonb_array_elements(pdc_fitter_private.lines(vid, bid)) x
  WHERE x->'conversion' IS NOT NULL AND (identity IS NULL OR x->>'line_identity' = identity) LOOP
  IF NOT coalesce((l->>'completed')::boolean, false) THEN
   -- A ticked Coaster or HiAce parent is complete. Work-item and booking rows
   -- have no line_identity; only the progress branch may read that field.
   -- The progress insert itself is not visible to lines() yet.
   IF l#>>'{conversion,id}' IN ('coaster', 'hiace_commuter')
      AND coalesce((l#>>'{conversion,needs_review}')::boolean, false) = false THEN
    IF TG_TABLE_NAME = 'operation_progress' THEN
     IF NEW.completed AND NEW.line_identity = l->>'line_identity' THEN
      NULL;
     ELSIF EXISTS (
      SELECT 1 FROM pdc_fitter_private.operation_progress p
      JOIN public.workshop_bookings wb ON wb.id = p.booking_id
      WHERE wb.vehicle_id = vid AND wb.deleted_at IS NULL
        AND p.line_identity = l->>'line_identity' AND p.completed
        AND p.scope_hash = l->>'scope_hash') THEN
      NULL;
     ELSE
      RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING ERRCODE = '23514';
     END IF;
    ELSIF EXISTS (
     SELECT 1 FROM pdc_fitter_private.operation_progress p
     JOIN public.workshop_bookings wb ON wb.id = p.booking_id
     WHERE wb.vehicle_id = vid AND wb.deleted_at IS NULL
       AND p.line_identity = l->>'line_identity' AND p.completed
       AND p.scope_hash = l->>'scope_hash') THEN
     NULL;
    ELSE
     RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING ERRCODE = '23514';
    END IF;
   ELSE
    RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING ERRCODE = '23514';
   END IF;
  END IF;
 END LOOP;
 RETURN NEW;
END
$fn$;

DO $patch_fitter_line$
DECLARE def text; old_gate text; new_gate text; hits integer;
BEGIN
 old_gate := $old$IF l->'conversion' IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;$old$;
 new_gate := $new$IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;$new$;
 SELECT pg_get_functiondef(p.oid) INTO def
 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command';
 hits := (length(def) - length(replace(def, old_gate, ''))) / length(old_gate);
 IF hits IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'fitter_line_gate_missing'; END IF;
 EXECUTE replace(def, old_gate, new_gate);
END
$patch_fitter_line$;
-- END SIMPLE TICK APPLY

DO $post$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'start_workshop_work_pre_116')
     IS DISTINCT FROM '40ab1b0a75d347b56c69e54c65ddd193' THEN
    RAISE EXCEPTION 'start_workshop_work_pre_116_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_catalog')
     IS DISTINCT FROM 'b7789961f5e49d09b854ce7582d34e83' THEN
    RAISE EXCEPTION 'conversion_catalog_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS DISTINCT FROM 'c49e4557e6b5d978352476e36589731b' THEN
    RAISE EXCEPTION 'conversion_save_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'minutes')
     IS DISTINCT FROM '0c8423441e81705290d74f4a85c78ea2' THEN
    RAISE EXCEPTION 'booking_minutes_changed';
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
  IF position('coalesce(l#>>''{conversion,id}'','''') NOT IN (''coaster'',''hiace_commuter'')' IN (
      SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')) = 0 THEN
    RAISE EXCEPTION 'fitter_line_gate_not_applied';
  END IF;
  IF position('c->>''id'' IN (''coaster'', ''hiace_commuter'')' IN (
      SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')) = 0 THEN
    RAISE EXCEPTION 'conversion_enrich_not_applied';
  END IF;
END $post$;
