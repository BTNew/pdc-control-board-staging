-- r809 rollback: stop line changes cancelling overrides. The one retro cancel (key 102 Tint, history row actor
-- craig.watson 1 Nov 19:14) stays cancelled; re-set it on the board if wanted.
DROP TRIGGER IF EXISTS zz_override_newest_wins_809 ON public.pdc_panel_line_completion_565;
DROP FUNCTION IF EXISTS pdc_work_categories_private.override_newest_wins_809();
DROP FUNCTION IF EXISTS pdc_work_categories_private.cancel_override_809(uuid, text, timestamptz, uuid, text, text, timestamptz);
DROP FUNCTION IF EXISTS pdc_work_categories_private.line_work_key_809(uuid, text);
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'override_newest_wins_809';
