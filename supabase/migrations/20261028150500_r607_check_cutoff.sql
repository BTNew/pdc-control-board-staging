-- r607 (F221) follow-up. Staging cdsmnqxtyyoeoznmbidd only.
-- The unallocated_drop_place_607 check counted running-job resizes from 15:00 AWST; r607 went live at
-- 12:06 AWST (ledger 20261028040619). Count from the apply time instead. Check text only.
SET LOCAL lock_timeout = '2s';
DO $c607$
DECLARE n integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'r607 cutoff: staging only'; END IF;
  UPDATE pdc_ops.regression_checks
  SET check_sql=replace(check_sql,'h.created_at>''2026-10-28 07:00:00+00''','h.created_at>''2026-10-28 04:06:00+00''')
  WHERE check_name='unallocated_drop_place_607' AND added_in='r607' AND strpos(check_sql,'2026-10-28 07:00:00+00')>0;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>1 THEN RAISE EXCEPTION 'r607 cutoff: check not updated'; END IF;
END $c607$;
