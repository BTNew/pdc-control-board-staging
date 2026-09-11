-- Department 138 defaults to Bus 4x4, but an explicit staff station choice wins.
DO $migration$
DECLARE original text; revised text; marker text := 'CASE WHEN o.department=''138'' THEN ''BUS_4X4'' ELSE coalesce(a.stage_code,';
BEGIN
 original:=pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure);
 IF (length(original)-length(replace(original,marker,'')))/length(marker)<>2 THEN
  RAISE EXCEPTION 'department_station_projection_contract_changed';
 END IF;
 revised:=replace(original,marker,'CASE WHEN a.active AND a.manual_assignment_locked THEN a.stage_code WHEN o.department=''138'' THEN ''BUS_4X4'' ELSE coalesce(a.stage_code,');
 EXECUTE revised;
END $migration$;
