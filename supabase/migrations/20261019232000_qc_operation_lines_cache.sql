-- Cache pdc_qc_operation_lines_379 per vehicle.
-- The wrapper stays STABLE, so a miss reads the unchanged body and does not write.
-- Triggers and the backfill fill pdc_work_categories_private.qc_operation_lines_cache.
-- Input tables were taken from FROM/JOIN references in the transitive call graph.
-- None of those function bodies read the clock or the signed-in user.
-- Scheduling and receipt authority are unchanged.
-- Rollback: supabase/rollbacks/20261019232000_qc_operation_lines_cache.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
DECLARE
  src text;
  definer boolean;
  volatility "char";
  config text[];
  lang text;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  SELECT p.prosrc, p.prosecdef, p.provolatile, p.proconfig, l.lanname
    INTO src, definer, volatility, config, lang
  FROM pg_proc p
  JOIN pg_language l ON l.oid = p.prolang
  WHERE p.oid = 'public.pdc_qc_operation_lines_379(uuid)'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM 'b677d7bfdf67c046fd05922da249325c'
     OR definer IS DISTINCT FROM true
     OR volatility IS DISTINCT FROM 's'
     OR lang IS DISTINCT FROM 'sql'
     OR config IS DISTINCT FROM ARRAY['search_path=pg_catalog'] THEN
    RAISE EXCEPTION 'reviewed_qc_operation_lines_changed';
  END IF;
END
$guard$;

SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379_uncached(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 WITH source AS MATERIALIZED(
  SELECT l,ord FROM jsonb_array_elements(pdc_work_categories_private.before_import_rules_20261017(p_vehicle_id)) WITH ORDINALITY x(l,ord)
 ), routed AS(
 SELECT ord,pdc_work_categories_private.route_import_line_20261017(
  CASE WHEN a.manual_assignment_locked IS FALSE AND a.correction_origin='job_card_source_correction'
   THEN l||jsonb_build_object('estimated_hours',a.estimated_hours,
    'zero_hour_task',a.estimated_hours=0 AND EXISTS(SELECT 1 FROM pdc_work_categories_private.import_rules_20261017 r
     WHERE r.description_hash=pdc_work_categories_private.import_description_hash_20261017(l->>'description') AND r.category='BUS_QA'))
   ELSE l END,
  h.source_signature=pdc_work_categories_private.source_signature(l)
  OR coalesce((l->>'category_version')::integer,0)>0
  OR coalesce(a.manual_assignment_locked,false)
  OR EXISTS(SELECT 1 FROM pdc_work_categories_private.owner_line_reviews r
   WHERE r.vehicle_id=p_vehicle_id AND r.line_identity=l->>'line_identity'
   AND r.source_signature=pdc_work_categories_private.source_signature(l))
  OR EXISTS(SELECT 1 FROM public.vehicle_work_items w JOIN public.workshop_stages s ON s.work_key=w.work_key
   WHERE w.vehicle_id=p_vehicle_id AND w.completed AND s.code=l->>'stage_code')
  OR EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage','completed')
    AND ((b.work_category IS NOT NULL AND b.work_category_scope ? (l->>'line_identity'))
     OR (b.work_category IS NULL AND s.code=l->>'stage_code'
      AND NOT (a.manual_assignment_locked IS FALSE AND a.correction_origin='job_card_source_correction' AND EXISTS(
       SELECT 1 FROM public.pdc_tune_operation_change_reviews q
       WHERE q.vehicle_id=p_vehicle_id AND 'source:'||q.source_operation_id::text=l->>'line_identity'
        AND q.change_kind='added' AND q.status='approved' AND q.approved_at>b.created_at)))))
 ) l
 FROM source
 LEFT JOIN pdc_work_categories_private.import_baseline_20261017 h ON h.vehicle_id=p_vehicle_id AND h.line_identity=l->>'line_identity'
 LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=l->>'line_identity'
 ) SELECT coalesce(jsonb_agg(l ORDER BY ord),'[]'::jsonb) FROM routed
$function$;

REVOKE ALL ON FUNCTION public.pdc_qc_operation_lines_379_uncached(uuid) FROM PUBLIC;
DO $revoke_uncached$
DECLARE role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE 'REVOKE ALL ON FUNCTION public.pdc_qc_operation_lines_379_uncached(uuid) FROM ' || quote_ident(role_name);
    END IF;
  END LOOP;
END
$revoke_uncached$;

CREATE TABLE pdc_work_categories_private.qc_operation_lines_cache (
  vehicle_id uuid PRIMARY KEY,
  lines jsonb NOT NULL,
  computed_at timestamptz NOT NULL
);
REVOKE ALL ON TABLE pdc_work_categories_private.qc_operation_lines_cache FROM PUBLIC;
DO $revoke_cache$
DECLARE role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE 'REVOKE ALL ON TABLE pdc_work_categories_private.qc_operation_lines_cache FROM ' || quote_ident(role_name);
    END IF;
  END LOOP;
END
$revoke_cache$;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $wrapper$
  SELECT coalesce(
    (SELECT c.lines
     FROM pdc_work_categories_private.qc_operation_lines_cache c
     WHERE c.vehicle_id = p_vehicle_id),
    public.pdc_qc_operation_lines_379_uncached(p_vehicle_id)
  );
$wrapper$;

CREATE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $invalidate$
DECLARE
  op_id uuid;
BEGIN
  IF TG_OP = 'TRUNCATE' OR TG_TABLE_NAME IN ('ai_routing_20261019', 'import_rules_139_20261018', 'import_rules_20261017', 'navision_backend_records', 'pdc_pilbara_service_import_batches', 'workshop_stage_aliases', 'workshop_stages') THEN
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache;
    RETURN NULL;
  END IF;
  IF TG_TABLE_NAME = 'vehicles' THEN
    IF TG_OP = 'INSERT' THEN
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = NEW.id;
    ELSIF TG_OP = 'UPDATE' THEN
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id IN (OLD.id, NEW.id);
    ELSE
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = OLD.id;
    END IF;
    RETURN NULL;
  END IF;
  IF TG_TABLE_NAME IN ('operation_routing_history_20261015', 'pdc_pilbara_service_classification_current', 'pdc_pilbara_service_classification_history', 'pdc_pilbara_service_operation_history') THEN
    IF TG_OP = 'DELETE' THEN op_id := OLD.operation_id; ELSE op_id := NEW.operation_id; END IF;
    IF TG_OP = 'UPDATE' AND OLD.operation_id IS DISTINCT FROM NEW.operation_id THEN
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache c
      WHERE c.vehicle_id IN (
        SELECT o.vehicle_id FROM public.pdc_pilbara_service_operations o
        WHERE o.operation_id IN (OLD.operation_id, NEW.operation_id)
      );
      IF NOT EXISTS (
        SELECT 1 FROM public.pdc_pilbara_service_operations o
        WHERE o.operation_id IN (OLD.operation_id, NEW.operation_id)
      ) THEN
        DELETE FROM pdc_work_categories_private.qc_operation_lines_cache;
      END IF;
    ELSIF EXISTS (
      SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.operation_id = op_id
    ) THEN
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache c
      WHERE c.vehicle_id IN (
        SELECT o.vehicle_id FROM public.pdc_pilbara_service_operations o WHERE o.operation_id = op_id
      );
    ELSE
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache;
    END IF;
    RETURN NULL;
  END IF;
  IF TG_OP = 'INSERT' THEN
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = NEW.vehicle_id;
  ELSIF TG_OP = 'UPDATE' THEN
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id IN (OLD.vehicle_id, NEW.vehicle_id);
  ELSE
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = OLD.vehicle_id;
  END IF;
  RETURN NULL;
END
$invalidate$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache() FROM PUBLIC;

CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON pdc_bus_private.operation_routing_history_20261015
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON pdc_bus_private.operation_routing_history_20261015
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON pdc_operation_updates_private.ai_routing_20261019
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON pdc_operation_updates_private.ai_routing_20261019
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON pdc_work_categories_private.import_baseline_20261017
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON pdc_work_categories_private.import_baseline_20261017
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON pdc_work_categories_private.import_rules_139_20261018
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON pdc_work_categories_private.import_rules_139_20261018
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON pdc_work_categories_private.import_rules_20261017
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON pdc_work_categories_private.import_rules_20261017
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON pdc_work_categories_private.line_overrides
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON pdc_work_categories_private.line_overrides
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON pdc_work_categories_private.owner_line_reviews
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON pdc_work_categories_private.owner_line_reviews
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.navision_backend_records
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.navision_backend_records
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_authenticated_email_operation_lines
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_authenticated_email_operation_lines
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_new_vehicle_reviews
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_new_vehicle_reviews
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_pilbara_service_classification_current
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_pilbara_service_classification_current
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_pilbara_service_classification_history
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_pilbara_service_classification_history
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_pilbara_service_import_batches
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_pilbara_service_import_batches
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_pilbara_service_import_rows
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_pilbara_service_import_rows
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_pilbara_service_operation_history
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_pilbara_service_operation_history
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_pilbara_service_operations
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_pilbara_service_operations
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_qc_operation_completions_379
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_qc_operation_completions_379
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_qc_operation_rejections_381
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_qc_operation_rejections_381
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.pdc_tune_operation_change_reviews
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.pdc_tune_operation_change_reviews
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.vehicle_work_items
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.vehicle_work_items
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.vehicle_workshop_line_adjustments
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.vehicle_workshop_line_adjustments
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.vehicles
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.workshop_bookings
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.workshop_bookings
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.workshop_stage_aliases
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.workshop_stage_aliases
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.workshop_stages
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.workshop_stages
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();

INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
SELECT v.id, public.pdc_qc_operation_lines_379_uncached(v.id), statement_timestamp()
FROM public.vehicles v
ON CONFLICT (vehicle_id) DO UPDATE
  SET lines = EXCLUDED.lines, computed_at = EXCLUDED.computed_at;

DO $check$
DECLARE src text; uncached text; volatility "char";
BEGIN
  SELECT p.prosrc, p.provolatile INTO src, volatility
  FROM pg_proc p
  WHERE p.oid = 'public.pdc_qc_operation_lines_379(uuid)'::regprocedure;
  SELECT prosrc INTO uncached
  FROM pg_proc
  WHERE oid = 'public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure;
  IF volatility IS DISTINCT FROM 's'
     OR position('qc_operation_lines_cache' in src) = 0
     OR position('insert' in lower(src)) > 0
     OR md5(replace(uncached, chr(13), '')) IS DISTINCT FROM 'b677d7bfdf67c046fd05922da249325c' THEN
    RAISE EXCEPTION 'qc_operation_lines_cache_rewrite_mismatch';
  END IF;
END
$check$;
