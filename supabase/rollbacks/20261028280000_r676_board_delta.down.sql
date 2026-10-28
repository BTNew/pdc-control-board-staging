-- r676 rollback. Browsers fall back to the full board when the overload is gone (PGRST202).
DROP FUNCTION IF EXISTS public.get_pdc_email_vehicle_board_snapshot_conditional(text, boolean);
DROP TABLE IF EXISTS pdc_ops.vehicle_board_snapshot_history_676;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'board_delta_676';
