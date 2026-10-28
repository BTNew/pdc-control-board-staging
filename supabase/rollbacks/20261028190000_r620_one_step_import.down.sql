-- Undo r620 (F235): remove the one-step import. Staging cdsmnqxtyyoeoznmbidd only.
-- Import receipts and board writes made by finished jobs stay (they are ordinary import batches).
SET LOCAL lock_timeout = '4s';
SELECT cron.unschedule('pdc-import-620-worker') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pdc-import-620-worker');
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'one_step_import_620' AND added_in = 'r620';
DROP SCHEMA IF EXISTS pdc_import_620 CASCADE;
DO $$ BEGIN
  IF (SELECT banned_until FROM auth.users WHERE id = '0640d2f1-9f97-4e20-8a4f-cb6069b005df') IS DISTINCT FROM '2126-08-21T11:05:10.641388+00:00'::timestamptz THEN
    RAISE EXCEPTION 'r620 undo: importer is not in its normal banned state';
  END IF;
END $$;
