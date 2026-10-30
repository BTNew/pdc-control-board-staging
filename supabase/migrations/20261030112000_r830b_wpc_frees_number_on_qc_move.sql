-- r830b (F391) follow-up. Staging cdsmnqxtyyoeoznmbidd only. Applied 30 Oct 2026 after r830.
-- Live check after r830: a car moved into QC became WPC but its old number stayed in active_key_575, because the r575
-- guard trigger is UPDATE OF key_number (a location move does not list key_number). The number was not free to reuse.
-- Fix: capture_wpc_830 (AFTER UPDATE, no column list) frees the number and keeps the PMB key date. No car was affected
-- (checked before apply: no WPC car held an active key).
-- Rollback: restore capture_wpc_830 from 20261030110500_r830_wpc_key_and_done_station_sweep.sql and the old check_sql.
SET LOCAL lock_timeout = '6s';
DO $g$ BEGIN
  IF to_regprocedure('pdc_key_number_private.capture_wpc_830()') IS NULL THEN RAISE EXCEPTION 'r830b: r830 not applied'; END IF;
  IF strpos((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_key_number_private.capture_wpc_830()'::regprocedure), 'r830b') > 0 THEN RAISE EXCEPTION 'r830b: already applied'; END IF;
END $g$;
CREATE OR REPLACE FUNCTION pdc_key_number_private.capture_wpc_830()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_new_wpc boolean := upper(btrim(coalesce(NEW.key_number, ''))) = 'WPC';
  v_old_wpc boolean := TG_OP = 'UPDATE' AND upper(btrim(coalesce(OLD.key_number, ''))) = 'WPC';
  v_cause text := coalesce(nullif(current_setting('pdc.wpc_cause_830', true), ''), 'manual');
BEGIN
  IF v_new_wpc AND NOT v_old_wpc THEN
    INSERT INTO pdc_key_number_private.vehicle_wpc_830 (vehicle_id, wpc_at, freed_key, cause, pmb_key_at)
    VALUES (NEW.id, clock_timestamp(),
      CASE WHEN TG_OP = 'UPDATE' THEN nullif(btrim(OLD.key_number), '') END, v_cause,
      (SELECT a.assigned_at FROM public.pdc_vehicle_key_assigned_562 a WHERE a.vehicle_id = NEW.id))
    ON CONFLICT (vehicle_id) DO UPDATE
      SET wpc_at = EXCLUDED.wpc_at, freed_key = EXCLUDED.freed_key, cause = EXCLUDED.cause,
          pmb_key_at = coalesce(pdc_key_number_private.vehicle_wpc_830.pmb_key_at, EXCLUDED.pmb_key_at),
          reverted_at = NULL, updated_at = clock_timestamp()
      WHERE pdc_key_number_private.vehicle_wpc_830.vehicle_id = EXCLUDED.vehicle_id
        AND pdc_key_number_private.vehicle_wpc_830.reverted_at IS NOT NULL;
    PERFORM set_config('pdc.wpc_cause_830', '', true);
    -- r830b: the r575 guard and the r562 key date trigger only fire when key_number is in the UPDATE's SET list. A move
    -- into QC changes the key in a BEFORE trigger, so free the number here and keep the PMB key date (assigned_at).
    DELETE FROM pdc_key_number_private.active_key_575 WHERE vehicle_id = NEW.id;
    UPDATE public.pdc_vehicle_key_assigned_562 SET assigned_key = 'WPC' WHERE vehicle_id = NEW.id;
  ELSIF v_old_wpc AND NOT v_new_wpc THEN
    UPDATE pdc_key_number_private.vehicle_wpc_830 SET reverted_at = clock_timestamp(), updated_at = clock_timestamp()
    WHERE vehicle_id = NEW.id AND reverted_at IS NULL;
  END IF;
  RETURN NULL;
END
$function$;

UPDATE pdc_ops.regression_checks
   SET check_sql = replace(check_sql, '   AND missing.n = 0 AS ok,', '   AND missing.n = 0
   AND NOT EXISTS (SELECT 1 FROM pdc_key_number_private.active_key_575 a JOIN public.vehicles v ON v.id = a.vehicle_id
                   WHERE upper(btrim(coalesce(v.key_number, ''''))) = ''WPC'') AS ok,')
 WHERE check_name = 'wpc_key_830' AND strpos(check_sql, 'active_key_575 a JOIN') = 0;
DO $p$ DECLARE r record; BEGIN
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'wpc_key_830') INTO r;
  IF r.ok IS NOT TRUE OR strpos((SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'wpc_key_830'), 'active_key_575 a JOIN') = 0
  THEN RAISE EXCEPTION 'r830b: check red or not updated: %', r.detail; END IF;
END $p$;
