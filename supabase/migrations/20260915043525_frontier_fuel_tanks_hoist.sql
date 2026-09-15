-- Frontier is ARB's long-range fuel tank range. Keep this specific routing
-- ahead of the broad ARB Fitting default. No operation/source data is changed.
DO $migration$
DECLARE definition text; old_predicate text := $old$ELSIF department<>'138' AND d ~ '\yLONG[ -]?RANG(?:E|ER)\y.*\yTANKS?\y' THEN$old$;
 new_predicate text := $new$ELSIF department<>'138' AND (d ~ '\yLONG[ -]?RANG(?:E|ER)\y.*\yTANKS?\y' OR d ~ '\yARB\y.*\yFRONTIER\y.*\yTANKS?\y') THEN$new$;
BEGIN
 SELECT pg_get_functiondef('public.pdc_pending_work_category_20260912(jsonb)'::regprocedure) INTO definition;
 IF strpos(definition,new_predicate)>0 THEN RETURN; END IF;
 IF (length(definition)-length(replace(definition,old_predicate,'')))/length(old_predicate)<>1 THEN
  RAISE EXCEPTION 'Expected exactly one long-range-tank routing branch; review function before applying';
 END IF;
 EXECUTE replace(definition,old_predicate,new_predicate);
END $migration$;

-- Verify classification and source-hour preservation without creating records.
DO $tests$
DECLARE item jsonb; actual jsonb;
BEGIN
 FOR item IN SELECT value FROM jsonb_array_elements('[
  {"description":"ARB FRONTIER 133L DIESEL TANK","department":"139","stage_code":"FITTING","source_estimated_hours":1.9,"estimated_hours":1.9,"expected":"HOIST"},
  {"description":"ARB Frontier replacement fuel tank","department":"138","stage_code":"BUS_4X4","source_estimated_hours":2,"estimated_hours":2,"expected":"BUS_4X4"},
  {"description":"ARB Roof Rack","department":"139","stage_code":"FITTING","source_estimated_hours":1,"estimated_hours":1,"expected":"FITTING"},
  {"description":"ARB Long Range Fuel Tank","department":"139","stage_code":"FITTING","source_estimated_hours":2.5,"estimated_hours":2.5,"expected":"HOIST"},
  {"description":"SUBLET ARB Frontier fuel tank supplier fitted","department":"139","stage_code":"SUBLET","source_estimated_hours":2,"estimated_hours":2,"expected":"SUBLET"}
 ]'::jsonb) LOOP
  actual:=public.pdc_pending_work_category_20260912(item);
  IF actual->>'stage_code' IS DISTINCT FROM item->>'expected' OR actual->'source_estimated_hours' IS DISTINCT FROM item->'source_estimated_hours' OR actual->'estimated_hours' IS DISTINCT FROM item->'estimated_hours' THEN
   RAISE EXCEPTION 'Frontier routing regression: % -> %',item,actual;
  END IF;
 END LOOP;
END $tests$;

