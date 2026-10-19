-- Synthetic cache proof. The transaction rolls back.

CREATE SCHEMA IF NOT EXISTS pdc_work_categories_private;
CREATE SCHEMA IF NOT EXISTS pdc_operation_updates_private;
CREATE SCHEMA IF NOT EXISTS pdc_bus_private;
CREATE SCHEMA IF NOT EXISTS pdc_codex_intake_private;
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;

CREATE TABLE public.vehicles (id uuid PRIMARY KEY, marker text);
CREATE TABLE public.workshop_stages (id uuid PRIMARY KEY, work_key text, code text, marker text);
CREATE TABLE public.workshop_stage_aliases (id uuid PRIMARY KEY, marker text);
CREATE TABLE public.workshop_bookings (
  id uuid PRIMARY KEY, vehicle_id uuid, stage_id uuid, deleted_at timestamptz, status text,
  work_category text, work_category_scope jsonb, created_at timestamptz, marker text
);
CREATE TABLE public.vehicle_work_items (id uuid PRIMARY KEY, vehicle_id uuid, work_key text, completed boolean, marker text);
CREATE TABLE public.vehicle_workshop_line_adjustments (
  vehicle_id uuid, line_key text, manual_assignment_locked boolean, correction_origin text,
  estimated_hours numeric, marker text
);
CREATE TABLE public.pdc_tune_operation_change_reviews (
  vehicle_id uuid, source_operation_id uuid, change_kind text, status text, approved_at timestamptz, marker text
);
CREATE TABLE public.pdc_authenticated_email_operation_lines (operation_line_id uuid PRIMARY KEY, vehicle_id uuid, marker text);
CREATE TABLE public.pdc_new_vehicle_reviews (vehicle_id uuid, marker text);
CREATE TABLE public.pdc_pilbara_service_operations (operation_id uuid PRIMARY KEY, vehicle_id uuid, marker text);
CREATE TABLE public.pdc_pilbara_service_operation_history (operation_id uuid, marker text);
CREATE TABLE public.pdc_pilbara_service_classification_current (operation_id uuid, marker text);
CREATE TABLE public.pdc_pilbara_service_classification_history (operation_id uuid, marker text);
CREATE TABLE public.pdc_pilbara_service_import_batches (batch_id uuid PRIMARY KEY, marker text);
CREATE TABLE public.pdc_pilbara_service_import_rows (vehicle_id uuid, marker text);
CREATE TABLE public.pdc_qc_operation_completions_379 (vehicle_id uuid, marker text);
CREATE TABLE public.pdc_qc_operation_rejections_381 (vehicle_id uuid, marker text);
CREATE TABLE public.navision_backend_records (id uuid PRIMARY KEY, canonical_vehicle_id uuid, marker text);
CREATE TABLE pdc_work_categories_private.import_baseline_20261017 (vehicle_id uuid, line_identity text, source_signature text, marker text);
CREATE TABLE pdc_work_categories_private.import_rules_20261017 (description_hash text, category text, marker text);
CREATE TABLE pdc_work_categories_private.import_rules_139_20261018 (marker text);
CREATE TABLE pdc_work_categories_private.line_overrides (vehicle_id uuid, marker text);
CREATE TABLE pdc_work_categories_private.owner_line_reviews (vehicle_id uuid, line_identity text, source_signature text, marker text);
CREATE TABLE pdc_operation_updates_private.ai_routing_20261019 (marker text);
CREATE TABLE pdc_bus_private.operation_routing_history_20261015 (operation_id uuid, marker text);

CREATE FUNCTION pdc_work_categories_private.before_import_rules_20261017(p_vehicle_id uuid) RETURNS jsonb
LANGUAGE sql STABLE AS $$ SELECT '[]'::jsonb $$;
CREATE FUNCTION pdc_work_categories_private.route_import_line_20261017(line jsonb, preserve boolean) RETURNS jsonb
LANGUAGE sql STABLE AS $$ SELECT line $$;
CREATE FUNCTION pdc_work_categories_private.import_description_hash_20261017(description text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT description $$;
CREATE FUNCTION pdc_work_categories_private.source_signature(line jsonb) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT 'sig' $$;

CREATE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
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

BEGIN;
\ir ../supabase/migrations/20261019232000_qc_operation_lines_cache.sql

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379_uncached(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $double$
  SELECT jsonb_build_object(
    'pdc_bus_private.operation_routing_history_20261015', (SELECT t.marker FROM pdc_bus_private.operation_routing_history_20261015 t JOIN public.pdc_pilbara_service_operations o ON o.operation_id = t.operation_id WHERE o.vehicle_id = p_vehicle_id LIMIT 1),
    'pdc_operation_updates_private.ai_routing_20261019', (SELECT marker FROM pdc_operation_updates_private.ai_routing_20261019 LIMIT 1),
    'pdc_work_categories_private.import_baseline_20261017', (SELECT marker FROM pdc_work_categories_private.import_baseline_20261017 WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'pdc_work_categories_private.import_rules_139_20261018', (SELECT marker FROM pdc_work_categories_private.import_rules_139_20261018 LIMIT 1),
    'pdc_work_categories_private.import_rules_20261017', (SELECT marker FROM pdc_work_categories_private.import_rules_20261017 LIMIT 1),
    'pdc_work_categories_private.line_overrides', (SELECT marker FROM pdc_work_categories_private.line_overrides WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'pdc_work_categories_private.owner_line_reviews', (SELECT marker FROM pdc_work_categories_private.owner_line_reviews WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.navision_backend_records', (SELECT marker FROM public.navision_backend_records LIMIT 1),
    'public.pdc_authenticated_email_operation_lines', (SELECT marker FROM public.pdc_authenticated_email_operation_lines WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.pdc_new_vehicle_reviews', (SELECT marker FROM public.pdc_new_vehicle_reviews WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.pdc_pilbara_service_classification_current', (SELECT t.marker FROM public.pdc_pilbara_service_classification_current t JOIN public.pdc_pilbara_service_operations o ON o.operation_id = t.operation_id WHERE o.vehicle_id = p_vehicle_id LIMIT 1),
    'public.pdc_pilbara_service_classification_history', (SELECT t.marker FROM public.pdc_pilbara_service_classification_history t JOIN public.pdc_pilbara_service_operations o ON o.operation_id = t.operation_id WHERE o.vehicle_id = p_vehicle_id LIMIT 1),
    'public.pdc_pilbara_service_import_batches', (SELECT marker FROM public.pdc_pilbara_service_import_batches LIMIT 1),
    'public.pdc_pilbara_service_import_rows', (SELECT marker FROM public.pdc_pilbara_service_import_rows WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.pdc_pilbara_service_operation_history', (SELECT t.marker FROM public.pdc_pilbara_service_operation_history t JOIN public.pdc_pilbara_service_operations o ON o.operation_id = t.operation_id WHERE o.vehicle_id = p_vehicle_id LIMIT 1),
    'public.pdc_pilbara_service_operations', (SELECT marker FROM public.pdc_pilbara_service_operations WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.pdc_qc_operation_completions_379', (SELECT marker FROM public.pdc_qc_operation_completions_379 WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.pdc_qc_operation_rejections_381', (SELECT marker FROM public.pdc_qc_operation_rejections_381 WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.pdc_tune_operation_change_reviews', (SELECT marker FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.vehicle_work_items', (SELECT marker FROM public.vehicle_work_items WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.vehicle_workshop_line_adjustments', (SELECT marker FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.vehicles', (SELECT marker FROM public.vehicles WHERE id = p_vehicle_id),
    'public.workshop_bookings', (SELECT marker FROM public.workshop_bookings WHERE vehicle_id = p_vehicle_id LIMIT 1),
    'public.workshop_stage_aliases', (SELECT marker FROM public.workshop_stage_aliases LIMIT 1),
    'public.workshop_stages', (SELECT marker FROM public.workshop_stages LIMIT 1)
  );
$double$;

INSERT INTO public.vehicles (id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO public.workshop_stages (id, work_key, code, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'fit', 'FITTING', 'base');
INSERT INTO public.workshop_stage_aliases (id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'base');
INSERT INTO public.workshop_bookings (id, vehicle_id, stage_id, status, created_at, marker)
  VALUES ('a1000000-0000-4000-8000-0000000000c2', 'a1000000-0000-4000-8000-0000000000c1', 'a1000000-0000-4000-8000-0000000000c2', 'planned', now(), 'base');
INSERT INTO public.vehicle_work_items (id, vehicle_id, work_key, completed, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'a1000000-0000-4000-8000-0000000000c1', 'fit', false, 'base');
INSERT INTO public.vehicle_workshop_line_adjustments (vehicle_id, line_key, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'line', 'base');
INSERT INTO public.pdc_tune_operation_change_reviews (vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO public.pdc_authenticated_email_operation_lines (operation_line_id, vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO public.pdc_new_vehicle_reviews (vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO public.pdc_pilbara_service_operations (operation_id, vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO public.pdc_pilbara_service_operation_history (operation_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'base');
INSERT INTO public.pdc_pilbara_service_classification_current (operation_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'base');
INSERT INTO public.pdc_pilbara_service_classification_history (operation_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'base');
INSERT INTO public.pdc_pilbara_service_import_batches (batch_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'base');
INSERT INTO public.pdc_pilbara_service_import_rows (vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO public.pdc_qc_operation_completions_379 (vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO public.pdc_qc_operation_rejections_381 (vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO public.navision_backend_records (id, canonical_vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO pdc_work_categories_private.import_baseline_20261017 (vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO pdc_work_categories_private.import_rules_20261017 (description_hash, category, marker) VALUES ('h', 'BUS_QA', 'base');
INSERT INTO pdc_work_categories_private.import_rules_139_20261018 (marker) VALUES ('base');
INSERT INTO pdc_work_categories_private.line_overrides (vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO pdc_work_categories_private.owner_line_reviews (vehicle_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c1', 'base');
INSERT INTO pdc_operation_updates_private.ai_routing_20261019 (marker) VALUES ('base');
INSERT INTO pdc_bus_private.operation_routing_history_20261015 (operation_id, marker) VALUES ('a1000000-0000-4000-8000-0000000000c2', 'base');

INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
SELECT v.id, public.pdc_qc_operation_lines_379_uncached(v.id), statement_timestamp()
FROM public.vehicles v;

DO $proof$
DECLARE
  vid uuid := 'a1000000-0000-4000-8000-0000000000c1';
  previous jsonb;
  fresh jsonb;
  rel text;
BEGIN
  IF public.pdc_qc_operation_lines_379(vid) IS DISTINCT FROM public.pdc_qc_operation_lines_379_uncached(vid) THEN
    RAISE EXCEPTION 'cached lines did not match the uncached lines';
  END IF;
  FOREACH rel IN ARRAY ARRAY[
    'pdc_bus_private.operation_routing_history_20261015',
    'pdc_operation_updates_private.ai_routing_20261019',
    'pdc_work_categories_private.import_baseline_20261017',
    'pdc_work_categories_private.import_rules_139_20261018',
    'pdc_work_categories_private.import_rules_20261017',
    'pdc_work_categories_private.line_overrides',
    'pdc_work_categories_private.owner_line_reviews',
    'public.navision_backend_records',
    'public.pdc_authenticated_email_operation_lines',
    'public.pdc_new_vehicle_reviews',
    'public.pdc_pilbara_service_classification_current',
    'public.pdc_pilbara_service_classification_history',
    'public.pdc_pilbara_service_import_batches',
    'public.pdc_pilbara_service_import_rows',
    'public.pdc_pilbara_service_operation_history',
    'public.pdc_pilbara_service_operations',
    'public.pdc_qc_operation_completions_379',
    'public.pdc_qc_operation_rejections_381',
    'public.pdc_tune_operation_change_reviews',
    'public.vehicle_work_items',
    'public.vehicle_workshop_line_adjustments',
    'public.vehicles',
    'public.workshop_bookings',
    'public.workshop_stage_aliases',
    'public.workshop_stages'
  ]
  LOOP
    previous := public.pdc_qc_operation_lines_379_uncached(vid);
    INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
    VALUES (vid, previous, statement_timestamp())
    ON CONFLICT (vehicle_id) DO UPDATE SET lines = EXCLUDED.lines, computed_at = EXCLUDED.computed_at;
    EXECUTE format('UPDATE %s SET marker = marker || %L', rel, '-next');
    fresh := public.pdc_qc_operation_lines_379(vid);
    IF fresh IS DISTINCT FROM public.pdc_qc_operation_lines_379_uncached(vid)
       OR fresh = previous
       OR EXISTS (SELECT 1 FROM pdc_work_categories_private.qc_operation_lines_cache c WHERE c.vehicle_id = vid) THEN
      RAISE EXCEPTION 'input % left a stale cache previous % fresh %', rel, previous, fresh;
    END IF;
  END LOOP;
END
$proof$;
ROLLBACK;
