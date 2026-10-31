-- r780 (F384) / sort 567. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 31 Oct 2026 11:30: "13073117 - ive also moved fab job from this and its showing it needs it on the vehicle location screen.
-- make sure when we remove fab/elec jobs etc.. they are removed from the bookings and "still needs" etc.." (also 13017855, 13109749)
-- A line move writes pdc_work_categories_private.line_overrides and correctly sets the work item (fabrication required=false),
-- but the vehicle location snapshot (pdc_ops.vehicle_location_snapshot_compute_554) only applied vehicle_workshop_line_adjustments
-- to operation_lines, so moved lines still carried work_key 'fabrication' and the screen kept showing the old station.
-- Fix: operation_lines take the line_overrides category first (BUS_* -> bus4x4), source_work_key keeps the original.
-- The four checks that pin the compute md5 are moved to the new md5 (a release must update the pin it changes).
-- Backup: pdc_backup_r763_20261031.function_sources (*@r780pre). Rollback: supabase/rollbacks/20261031113500_r780_snapshot_follows_line_moves.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_ops.vehicle_location_snapshot_compute_554()@r780pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_ops.vehicle_location_snapshot_compute_554()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r780$
DECLARE v_old text; v_new text; v_def text; v_md5 text; sig regprocedure := 'pdc_ops.vehicle_location_snapshot_compute_554()'::regprocedure;
  a1 text := $a$public.pdc_standard_operation_display_20260910(CASE WHEN btrim(op->>'department')='138' THEN$a$;
  b1 text := $a$public.pdc_standard_operation_display_20260910(CASE WHEN lo.category IS NOT NULL THEN op||jsonb_build_object(
     'source_work_key',coalesce(op->'source_work_key',op->'work_key'),
     'work_key',CASE WHEN lo.category LIKE 'BUS\_%' THEN 'bus4x4' ELSE lower(lo.category) END,
     'classification',CASE WHEN lo.category LIKE 'BUS\_%' THEN 'BUS_4X4' ELSE lo.category END,'station_assignment_source','line_override')
   WHEN btrim(op->>'department')='138' THEN$a$;
  a2 text := $a$     AND a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET'))
  ) ORDER BY$a$;
  b2 text := $a$     AND a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
   -- r780 (F384): a line moved to another station (line_overrides) shows under that station.
   LEFT JOIN pdc_work_categories_private.line_overrides lo ON lo.vehicle_id=(row_value->>'id')::uuid
     AND lo.line_identity='source:'||(op->>'operation_line_id'))
  ) ORDER BY$a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r780: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 567 OR fault_id = 'F384' OR added_in = 'r780') THEN RAISE EXCEPTION 'r780: sort 567 or F384 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r780: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r780: compute_554 is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r780: anchor 1 not found once'; END IF;
  IF (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1 THEN RAISE EXCEPTION 'r780: anchor 2 not found once'; END IF;
  v_new := replace(replace(v_old, a1, b1), a2, b2);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r780: readback differs'; END IF;
  v_md5 := md5(v_new);
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,
      $q$to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()'))='e7f77fad301b8a87ef548472a8f790a6'$q$,
      $q$to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()'))='$q$ || v_md5 || $q$'$q$)
  WHERE check_name IN ('board_identity_open_454','snapshot_outer_single_eval','read_once_snapshots_554','snapshot_segments_collapsed');
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('board_identity_open_454','snapshot_outer_single_eval','read_once_snapshots_554','snapshot_segments_collapsed')
      AND position(v_md5 IN check_sql) > 0) <> 4 THEN RAISE EXCEPTION 'r780: pins not moved on all 4 checks'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('snapshot_follows_line_moves_780', 'F384',
    'Vehicle location (r780): a line moved to another station shows under that station on the location screen (operation_lines take line_overrides first), so a station with no lines left is not shown as still needed.',
    $chk$
SELECT position('r780 (F384)' IN s.src) > 0 AND position('pdc_work_categories_private.line_overrides lo' IN s.src) > 0
   AND position($$CASE WHEN lo.category IS NOT NULL THEN$$ IN s.src) > 0
 AS ok, 'location snapshot applies line moves' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()')) s
$chk$, true, 567, 'r780');
END $r780$;
