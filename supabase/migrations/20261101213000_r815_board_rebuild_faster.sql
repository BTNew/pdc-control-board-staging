-- r815 (F453): night review 1 Nov 2026. The Vehicle Locations board rebuild took 5.8 s (18 MB). Two safe cuts, same output:
--  1. pdc_imported_parts_flags_vehicle_20260912 joined every service operation in the database for each car (no vehicle filter on
--     the operations side) and worked out the company/division scope twice per row. It now reads only that car's operations and
--     works the scope out once. Output checked identical for every active / RFT car before release (585 ms -> 383 ms per board).
--  2. Two missing indexes behind ~37 billion rows of sequential reads since the last stats reset:
--     pdc_pilbara_service_operation_history(batch_id) (import triggers, classification, intake readback) and
--     pdc_pilbara_service_operations(repair_order_number) (service scope lookups).
CREATE INDEX IF NOT EXISTS pdc_service_operation_history_batch_815 ON public.pdc_pilbara_service_operation_history (batch_id);
CREATE INDEX IF NOT EXISTS pdc_service_operations_ro_815 ON public.pdc_pilbara_service_operations (repair_order_number);

DO $r815$
DECLARE
  sig regprocedure := 'public.pdc_imported_parts_flags_vehicle_20260912(uuid)'::regprocedure;
  v_old text; v_new text; v_def text;
  a1 text := E' FROM public.pdc_pilbara_service_operations o JOIN public.pdc_pilbara_service_import_rows r ON r.evidence_id=o.raw_evidence_id\n JOIN active a ON a.vehicle_id=o.vehicle_id AND a.ro_number=o.repair_order_number\n AND a.company=(pdc_parts_private.service_scope(r.raw_row,r.stock_number,r.repair_order_number)->>''company'') AND a.division=(pdc_parts_private.service_scope(r.raw_row,r.stock_number,r.repair_order_number)->>''division'')))';
  b1 text := E' FROM public.pdc_pilbara_service_operations o JOIN public.pdc_pilbara_service_import_rows r ON r.evidence_id=o.raw_evidence_id\n'
          || E' CROSS JOIN LATERAL (SELECT pdc_parts_private.service_scope(r.raw_row,r.stock_number,r.repair_order_number) AS sc OFFSET 0) s -- r815 (F453): scope once\n'
          || E' JOIN active a ON a.vehicle_id=o.vehicle_id AND a.ro_number=o.repair_order_number\n AND a.company=(s.sc->>''company'') AND a.division=(s.sc->>''division'')\n'
          || E' WHERE o.vehicle_id=p_vehicle_id))';
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r815: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r815: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('board_rebuild_faster_815', 'F453',
    'Board speed (r815): parts flags read only the car''s own operations; batch and R/O indexes in place.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.pdc_imported_parts_flags_vehicle_20260912(uuid)')), 'WHERE o.vehicle_id=p_vehicle_id') > 0
   AND to_regclass('public.pdc_service_operation_history_batch_815') IS NOT NULL
   AND to_regclass('public.pdc_service_operations_ro_815') IS NOT NULL
 AS ok, 'faster board rebuild in place' AS detail
$chk$, true, 603, 'r815');
END $r815$;
