-- Applied to staging 30 Oct 2026 08:04 AWST (Craig approved). r740 added a workshop_bookings-only check to the shared
-- QC lines cache trigger that read OLD.stage_id on every table it is attached to. plpgsql does not short-circuit
-- record field lookups, so updates to vehicle_work_items etc. failed with 'record "old" has no field "stage_id"'
-- (Workshop TV Stop / job completion). Fix: nest the column checks inside the TG_TABLE_NAME test.
-- Lesson: in a trigger shared across tables, table-specific columns go inside their own TG_TABLE_NAME IF,
-- and test an UPDATE on every attached table before go-live.
DO $m$
DECLARE d text; n text;
BEGIN
  d := pg_get_functiondef('pdc_work_categories_private.invalidate_qc_operation_lines_cache'::regproc);
  n := replace(d,
$o$  IF TG_TABLE_NAME = 'workshop_bookings' AND TG_OP = 'UPDATE'
     AND OLD.vehicle_id IS NOT DISTINCT FROM NEW.vehicle_id AND OLD.stage_id IS NOT DISTINCT FROM NEW.stage_id
     AND OLD.status IS NOT DISTINCT FROM NEW.status AND OLD.deleted_at IS NOT DISTINCT FROM NEW.deleted_at
     AND OLD.work_category IS NOT DISTINCT FROM NEW.work_category AND OLD.work_category_scope IS NOT DISTINCT FROM NEW.work_category_scope
     AND OLD.created_at IS NOT DISTINCT FROM NEW.created_at THEN
    -- r740 (F345): a time, bay, duration or technician change does not alter the QC lines; keep the cache.
    RETURN NULL;
  END IF;$o$,
$r$  IF TG_TABLE_NAME = 'workshop_bookings' AND TG_OP = 'UPDATE' THEN
    -- 30 Oct fix (Craig approved 08:04): nested so OLD.stage_id etc. are only read on workshop_bookings (plpgsql does not short-circuit field lookups).
    IF OLD.vehicle_id IS NOT DISTINCT FROM NEW.vehicle_id AND OLD.stage_id IS NOT DISTINCT FROM NEW.stage_id
     AND OLD.status IS NOT DISTINCT FROM NEW.status AND OLD.deleted_at IS NOT DISTINCT FROM NEW.deleted_at
     AND OLD.work_category IS NOT DISTINCT FROM NEW.work_category AND OLD.work_category_scope IS NOT DISTINCT FROM NEW.work_category_scope
     AND OLD.created_at IS NOT DISTINCT FROM NEW.created_at THEN
      -- r740 (F345): a time, bay, duration or technician change does not alter the QC lines; keep the cache.
      RETURN NULL;
    END IF;
  END IF;$r$);
  IF n = d THEN RAISE EXCEPTION 'pattern not found, function changed'; END IF;
  EXECUTE n;
END $m$;
