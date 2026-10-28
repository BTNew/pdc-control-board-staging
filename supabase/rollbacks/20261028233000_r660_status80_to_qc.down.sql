-- Undo r660 (F270): restore the r511 Status 80 function. Staging only.
-- Recreate pdc_codex_intake_private.apply_service_pmb_complete(uuid) from git (migration that set md5 9808feb2a0a93a79b0d67aebdca0a4aa, r511),
-- then: UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='9808feb2a0a93a79b0d67aebdca0a4aa', release='r511' WHERE signature='pdc_codex_intake_private.apply_service_pmb_complete(uuid)';
-- and replace '7c024b6656ada3772dada066968962f2' with '9808feb2a0a93a79b0d67aebdca0a4aa' in pdc_ops.regression_checks.check_sql;
-- DELETE FROM pdc_ops.regression_checks WHERE check_name='status80_to_qc_660';
-- Ticks already written stay (they are normal panel ticks and can be unticked).
SELECT 1;
