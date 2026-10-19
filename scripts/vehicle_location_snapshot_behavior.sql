-- Synthetic comparison of the old repeated helper calls and the rewritten once-per-operation calls.
-- No staff or customer rows.
CREATE SCHEMA IF NOT EXISTS pdc_bus_private;
CREATE TABLE IF NOT EXISTS public.snapshot_probe (
  station_calls integer NOT NULL DEFAULT 0,
  tune_calls integer NOT NULL DEFAULT 0,
  pre_calls integer NOT NULL DEFAULT 0,
  dept_calls integer NOT NULL DEFAULT 0
);
TRUNCATE public.snapshot_probe;
INSERT INTO public.snapshot_probe DEFAULT VALUES;

CREATE TABLE IF NOT EXISTS public.snapshot_station_map (operation_id uuid PRIMARY KEY, station text);
CREATE TABLE IF NOT EXISTS public.snapshot_tune_map (operation_id uuid PRIMARY KEY, description text);
TRUNCATE public.snapshot_station_map;
TRUNCATE public.snapshot_tune_map;

CREATE OR REPLACE FUNCTION pdc_bus_private.operation_station(p_id uuid) RETURNS text
LANGUAGE plpgsql VOLATILE AS $$
BEGIN
  UPDATE public.snapshot_probe SET station_calls = station_calls + 1;
  PERFORM md5(i::text) FROM generate_series(1, 40) i;
  RETURN (SELECT station FROM public.snapshot_station_map WHERE operation_id = p_id);
END $$;

CREATE OR REPLACE FUNCTION public.pdc_tune_approved_operation_source_20260912(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE AS $$
DECLARE description text;
BEGIN
  UPDATE public.snapshot_probe SET tune_calls = tune_calls + 1;
  SELECT snapshot_tune_map.description INTO description FROM public.snapshot_tune_map WHERE operation_id = p_id;
  IF description IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('operation_description', description);
END $$;

CREATE OR REPLACE FUNCTION public.pdc_is_pre_delivery_20260910(p_text text) RETURNS boolean
LANGUAGE plpgsql VOLATILE AS $$
BEGIN
  UPDATE public.snapshot_probe SET pre_calls = pre_calls + 1;
  RETURN coalesce(p_text, '') ILIKE '%pre-delivery%';
END $$;

CREATE OR REPLACE FUNCTION public.pdc_department138_station_20260917(p_text text) RETURNS text
LANGUAGE plpgsql VOLATILE AS $$
BEGIN
  UPDATE public.snapshot_probe SET dept_calls = dept_calls + 1;
  IF coalesce(p_text, '') ILIKE '%tint%' THEN RETURN 'TINT'; END IF;
  RETURN 'REVIEW';
END $$;

CREATE OR REPLACE FUNCTION public.pdc_standard_operation_display_20260910(p_line jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$ SELECT p_line $$;

CREATE TABLE IF NOT EXISTS public.pdc_pilbara_service_operations (
  operation_id uuid PRIMARY KEY,
  vehicle_id uuid,
  department text,
  original_line_number integer,
  semantic_hash text,
  repair_order_number text,
  operation_description text,
  effective_estimated_hours numeric,
  hours_provenance text,
  source_estimated_hours numeric,
  parts_on_backorder_raw text,
  parts_semantics text,
  proposed_station text,
  stock_number text,
  source_order integer
);
CREATE TABLE IF NOT EXISTS public.pdc_pilbara_service_classification_current (
  operation_id uuid,
  classification_id uuid
);
CREATE TABLE IF NOT EXISTS public.pdc_pilbara_service_classification_history (
  classification_id uuid,
  category text,
  method text,
  confidence numeric,
  rationale text,
  source_description_hash text,
  classifier_version text
);
TRUNCATE public.pdc_pilbara_service_classification_history;
TRUNCATE public.pdc_pilbara_service_classification_current;
TRUNCATE public.pdc_pilbara_service_operations;

INSERT INTO public.pdc_pilbara_service_operations
  (operation_id, vehicle_id, department, original_line_number, semantic_hash, repair_order_number, operation_description,
   effective_estimated_hours, hours_provenance, source_estimated_hours, parts_on_backorder_raw, parts_semantics,
   proposed_station, stock_number, source_order)
VALUES
  ('00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '138', 1, 'abcdef1234567890', 'RO1', 'Mechanical', 1.5, 'source_explicit', 1.5, '', '', 'REVIEW', 'S1', 1),
  ('00000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '138', 2, 'abcdef1234567890', 'RO1', 'Tint glass', 0.5, 'source_explicit', 0.5, '', '', 'REVIEW', 'S1', 2),
  ('00000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '138', 3, 'abcdef1234567890', 'RO1', 'Tyres', 0.5, 'source_explicit', 0.5, '', '', 'REVIEW', 'S1', 3),
  ('00000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', '138', 4, 'abcdef1234567890', 'RO1', 'Window tint extra', NULL, 'owner_supplied_document_unknown', NULL, '', '', 'REVIEW', 'S1', 4),
  ('00000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000001', '139', 5, 'abcdef1234567890', 'RO2', 'Source text', 1, 'pre_delivery_default_1_5', NULL, '', '', 'HOIST', 'S1', 5),
  ('00000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000001', '139', 6, 'abcdef1234567890', 'RO2', 'Hoist work', 2, 'source_explicit', 2, '', '', 'ELECTRICAL', 'S1', 6);

INSERT INTO public.snapshot_station_map VALUES
  ('00000000-0000-0000-0000-000000000001', 'BUS_4X4'),
  ('00000000-0000-0000-0000-000000000002', 'TINT'),
  ('00000000-0000-0000-0000-000000000003', 'TYRE');
INSERT INTO public.snapshot_tune_map VALUES
  ('00000000-0000-0000-0000-000000000005', 'Approved pre-delivery fit');
INSERT INTO public.pdc_pilbara_service_classification_current VALUES
  ('00000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000006');
INSERT INTO public.pdc_pilbara_service_classification_history VALUES
  ('20000000-0000-0000-0000-000000000006', 'HOIST', 'reviewed', 1, 'History category', 'hash', 'v1');

CREATE OR REPLACE FUNCTION public.snapshot_service_lines(p_mode text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE AS $$
DECLARE result jsonb;
BEGIN
  IF p_mode = 'old' THEN
    SELECT coalesce(jsonb_agg(public.pdc_standard_operation_display_20260910(jsonb_build_object(
      'operation_line_id',o.operation_id,'department',o.department,
      'operation_no','PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
      'work_key',CASE CASE WHEN o.department='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(CASE WHEN o.department='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END) END,
      'job_card_number',o.repair_order_number,'description',coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description),
      'estimated_hours',o.effective_estimated_hours,
      'estimated_hours_source',CASE o.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'classification',CASE WHEN o.department='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END
    )) ORDER BY o.source_order), '[]'::jsonb) INTO result
    FROM public.pdc_pilbara_service_operations o
    LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
    LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id);
  ELSE
    SELECT coalesce(jsonb_agg(public.pdc_standard_operation_display_20260910(jsonb_build_object(
      'operation_line_id',classified.operation_id,'department',classified.department,
      'operation_no','PD'||lpad(classified.original_line_number::text,3,'0')||'-'||upper(substr(classified.semantic_hash,1,8)),
      'work_key',CASE classified.station_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(classified.station_code) END,
      'job_card_number',classified.repair_order_number,'description',coalesce(classified.approved_source->>'operation_description',classified.operation_description),
      'estimated_hours',classified.effective_estimated_hours,
      'estimated_hours_source',CASE classified.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'classification',classified.station_code
    )) ORDER BY classified.source_order), '[]'::jsonb) INTO result
    FROM (
      SELECT sourced.*,
        CASE WHEN sourced.department='138' THEN pdc_bus_private.operation_station(sourced.operation_id)
             WHEN public.pdc_is_pre_delivery_20260910(coalesce(sourced.approved_source->>'operation_description',sourced.operation_description)) THEN 'FITTING'
             ELSE coalesce(sourced.category,sourced.proposed_station,'REVIEW') END AS station_code
      FROM (
        SELECT o.*, h.category, h.method, h.confidence, h.rationale, h.source_description_hash, h.classifier_version,
          public.pdc_tune_approved_operation_source_20260912(o.operation_id) AS approved_source
        FROM public.pdc_pilbara_service_operations o
        LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
        LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
      ) sourced
    ) classified;
  END IF;
  RETURN result;
END $$;

DO $compare$
DECLARE old_rows jsonb; new_rows jsonb; old_probe record; new_probe record; started timestamptz; old_ms numeric; new_ms numeric; line jsonb;
BEGIN
  UPDATE public.snapshot_probe SET station_calls = 0, tune_calls = 0, pre_calls = 0, dept_calls = 0;
  started := clock_timestamp();
  old_rows := public.snapshot_service_lines('old');
  old_ms := extract(epoch FROM clock_timestamp() - started) * 1000;
  SELECT * INTO old_probe FROM public.snapshot_probe;
  UPDATE public.snapshot_probe SET station_calls = 0, tune_calls = 0, pre_calls = 0, dept_calls = 0;
  started := clock_timestamp();
  new_rows := public.snapshot_service_lines('new');
  new_ms := extract(epoch FROM clock_timestamp() - started) * 1000;
  SELECT * INTO new_probe FROM public.snapshot_probe;
  IF old_rows IS DISTINCT FROM new_rows THEN RAISE EXCEPTION 'service_lines_changed'; END IF;
  IF new_probe.station_calls >= old_probe.station_calls OR new_probe.tune_calls >= old_probe.tune_calls OR new_probe.pre_calls >= old_probe.pre_calls THEN
    RAISE EXCEPTION 'helper_calls_not_reduced';
  END IF;
  IF new_probe.dept_calls <> 0 THEN RAISE EXCEPTION 'service_path_used_description_station'; END IF;
  FOR line IN SELECT value FROM jsonb_array_elements(new_rows) LOOP
    IF line->>'operation_line_id' = '00000000-0000-0000-0000-000000000001' AND (line->>'classification' <> 'BUS_4X4' OR line->>'work_key' <> 'bus4x4') THEN RAISE EXCEPTION 'bus_category'; END IF;
    IF line->>'operation_line_id' = '00000000-0000-0000-0000-000000000002' AND (line->>'classification' <> 'TINT' OR line->>'work_key' <> 'tint') THEN RAISE EXCEPTION 'tint_category'; END IF;
    IF line->>'operation_line_id' = '00000000-0000-0000-0000-000000000003' AND (line->>'classification' <> 'TYRE' OR line->>'work_key' <> 'tyre') THEN RAISE EXCEPTION 'tyre_category'; END IF;
    IF line->>'operation_line_id' = '00000000-0000-0000-0000-000000000004' AND (line->>'classification' IS NOT NULL OR line->>'work_key' IS NOT NULL) THEN RAISE EXCEPTION 'null_station_must_stay_null'; END IF;
    IF line->>'operation_line_id' = '00000000-0000-0000-0000-000000000005' AND (line->>'classification' <> 'FITTING' OR line->>'work_key' <> 'fitting' OR line->>'description' <> 'Approved pre-delivery fit' OR line->>'estimated_hours_source' <> 'business_rule_default') THEN RAISE EXCEPTION 'pre_delivery'; END IF;
    IF line->>'operation_line_id' = '00000000-0000-0000-0000-000000000006' AND (line->>'classification' <> 'HOIST' OR line->>'work_key' <> 'hoist') THEN RAISE EXCEPTION 'history_category'; END IF;
  END LOOP;
  RAISE NOTICE 'service lines old % ms calls station % tune % pre %; new % ms calls station % tune % pre %',
    round(old_ms, 1), old_probe.station_calls, old_probe.tune_calls, old_probe.pre_calls,
    round(new_ms, 1), new_probe.station_calls, new_probe.tune_calls, new_probe.pre_calls;
END
$compare$;

DO $lines$
DECLARE row_value jsonb := jsonb_build_object('id','10000000-0000-0000-0000-000000000001','queued_bayless',true,'operation_lines', jsonb_build_array(
  jsonb_build_object('department','138','operation_line_id','00000000-0000-0000-0000-000000000002','description','Tint glass'),
  jsonb_build_object('department','139','operation_line_id','00000000-0000-0000-0000-000000000006','description','Hoist','work_key','keep-me')
));
old_lines jsonb; new_lines jsonb; merged jsonb;
BEGIN
  UPDATE public.snapshot_probe SET station_calls = 0, dept_calls = 0;
  SELECT coalesce(jsonb_agg(CASE WHEN btrim(op->>'department')='138' THEN op||jsonb_build_object('work_key',CASE coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) WHEN 'TINT' THEN 'tint' WHEN 'TYRE' THEN 'tyre' ELSE 'bus4x4' END,'classification',coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description'))) ELSE op END ORDER BY ordinal), '[]'::jsonb)
    INTO old_lines
  FROM jsonb_array_elements(row_value->'operation_lines') WITH ORDINALITY x(op, ordinal);
  IF (SELECT station_calls FROM public.snapshot_probe) <> 2 OR (SELECT dept_calls FROM public.snapshot_probe) <> 0 THEN RAISE EXCEPTION 'old_line_calls'; END IF;
  UPDATE public.snapshot_probe SET station_calls = 0, dept_calls = 0;
  SELECT coalesce(jsonb_agg(CASE WHEN btrim(op->>'department')='138' THEN op||jsonb_build_object('work_key',CASE dept138.station_code WHEN 'TINT' THEN 'tint' WHEN 'TYRE' THEN 'tyre' ELSE 'bus4x4' END,'classification',dept138.station_code) ELSE op END ORDER BY ordinal), '[]'::jsonb)
    INTO new_lines
  FROM jsonb_array_elements(row_value->'operation_lines') WITH ORDINALITY x(op, ordinal)
  LEFT JOIN LATERAL (
    SELECT coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) AS station_code
    WHERE btrim(op->>'department')='138'
  ) dept138 ON true;
  IF old_lines IS DISTINCT FROM new_lines THEN RAISE EXCEPTION 'operation_lines_changed'; END IF;
  IF (SELECT station_calls FROM public.snapshot_probe) <> 1 THEN RAISE EXCEPTION 'new_line_calls'; END IF;
  merged := row_value || jsonb_build_object('operation_lines', new_lines);
  IF (merged->>'queued_bayless')::boolean IS DISTINCT FROM true OR merged#>>'{operation_lines,1,work_key}' IS DISTINCT FROM 'keep-me' OR merged#>>'{operation_lines,0,classification}' IS DISTINCT FROM 'TINT' THEN
    RAISE EXCEPTION 'returned_row_keys';
  END IF;
END
$lines$;
