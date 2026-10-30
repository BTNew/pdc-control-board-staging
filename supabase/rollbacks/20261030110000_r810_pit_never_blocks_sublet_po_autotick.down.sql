-- Rollback r810 (F370). PO ticks already written stay (they are audited sublet-done ticks and can be unticked on the board);
-- this only stops new automatic ticks and restores the previous station icon and its check.
SET LOCAL lock_timeout = '6s';
DROP TRIGGER IF EXISTS zz_sublet_po_autotick_810 ON public.pdc_panel_line_completion_565;
DROP TRIGGER IF EXISTS zz_sublet_po_autotick_810 ON public.pdc_qc_operation_completions_379;
DROP FUNCTION IF EXISTS pdc_work_categories_private.after_line_tick_po_810();
DROP FUNCTION IF EXISTS pdc_work_categories_private.sublet_po_autotick_810(uuid, text, uuid, text);
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'sublet_po_autotick_810' AND added_in = 'r810';
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $s$AND l->>'line_identity' IS NOT NULL
      AND NOT public.pdc_line_is_pit_401(raw.vehicle_id, l)$s$, $s$AND l->>'line_identity' IS NOT NULL$s$)
WHERE check_name = 'station_icon_completion_578';
-- Restore the pre-r810 icon body: remove the one pit line.
DO $rb$
DECLARE v_def text := pg_get_functiondef('pdc_work_categories_private.station_icon_completion_578(uuid[])'::regprocedure);
BEGIN
  v_def := replace(v_def, E'\n   AND NOT public.pdc_line_is_pit_401(raw.vehicle_id, l) -- r810 (F370): pit lines are optional and never hold an icon red', '');
  EXECUTE v_def;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_work_categories_private.station_icon_completion_578(uuid[])'::regprocedure)) <> 'cf57cbb27020c460288ddf11b54c3478'
    THEN RAISE EXCEPTION 'r810 rollback: icon body did not restore exactly'; END IF;
END $rb$;
UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;
