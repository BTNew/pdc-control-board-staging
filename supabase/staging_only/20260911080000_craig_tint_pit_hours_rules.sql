-- Already applied in STAGING on 2026-09-11; records Craig's effective-hours rules.
-- Preserve original source hours, grants, station assignments and staff actions.
CREATE OR REPLACE FUNCTION public.pdc_review_positive_hours_20260911(p_line jsonb, p_assignment jsonb)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
WITH value AS (SELECT CASE WHEN p_assignment ? 'estimated_hours' THEN p_assignment->'estimated_hours' ELSE p_line->'estimated_hours' END j),
parsed AS (SELECT CASE WHEN jsonb_typeof(j)='number' THEN (j#>>'{}')::numeric ELSE NULL END h FROM value)
SELECT CASE WHEN h>0 AND h<=999.99 AND (h=round(h,2) OR
(lower(coalesce(p_line->>'description','')) ~ '\mpit[[:space:]]*(and|&)[[:space:]]*weigh\M' AND abs(h-10::numeric/60)<0.000000000001))
AND (NOT public.pdc_is_pre_delivery_20260910(p_line->>'description') OR h=1) THEN h ELSE NULL END FROM parsed
$function$;

CREATE OR REPLACE FUNCTION public.pdc_standard_operation_display_20260910(p_line jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
SELECT CASE WHEN lower(coalesce(p_line->>'description','')) ~ '\mpit[[:space:]]*(and|&)[[:space:]]*weigh\M' THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',10::numeric/60,'effective_estimated_hours',10::numeric/60,'estimated_minutes',10,
'estimated_hours_source','business_rule_default','hours_provenance','craig_standard_pit_and_weigh_10_minutes')
WHEN public.pdc_is_pre_delivery_20260910(p_line->>'description') THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',1.0,'effective_estimated_hours',1.0,'estimated_hours_source','business_rule_default','hours_provenance','craig_standard_pre_delivery_1_hour')
WHEN lower(coalesce(p_line->>'description','')) ~ '\mtint\M'
AND (p_line->'estimated_hours' IS NULL OR p_line->'estimated_hours'='null'::jsonb OR p_line->'estimated_hours'='0'::jsonb) THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',1.0,'effective_estimated_hours',1.0,'estimated_hours_source','business_rule_default','hours_provenance','craig_tint_default_1_hour')
ELSE p_line END
$function$;

CREATE OR REPLACE FUNCTION public.pdc_standard_operation_hours_20260910(p_description text, p_hours numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
SELECT CASE WHEN lower(coalesce(p_description,'')) ~ '\mpit[[:space:]]*(and|&)[[:space:]]*weigh\M' THEN 10::numeric/60
WHEN public.pdc_is_pre_delivery_20260910(p_description) THEN 1.0 WHEN lower(coalesce(p_description,'')) ~ '\mtint\M' AND (p_hours IS NULL OR p_hours=0) THEN 1.0 ELSE p_hours END
$function$;
