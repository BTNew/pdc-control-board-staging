-- Rollback for r748 (F354, F355). Restores the r575/r742/r562 bodies and removes WPC handling.
-- The done-station sweep is kept running under its live r776 name (it was applied live before r748); WPC keys already
-- on cars stay as typed (with this rollback WPC is a key tag again, so only one car may hold it: check first).
SET LOCAL lock_timeout = '6s';
DO $pre$
BEGIN
  IF (SELECT count(*) FROM public.vehicles v
      WHERE pdc_key_number_private.board_scope_575(v.id, v.deleted_at, v.board_purged_at, v.visible_on_board, v.lifecycle_state::text)
        AND upper(btrim(coalesce(v.key_number, ''))) = 'WPC') > 1 THEN
    RAISE EXCEPTION 'r748 rollback: more than one board car is WPC; WPC would clash under r575. Clear them first.';
  END IF;
END $pre$;

DELETE FROM pdc_ops.regression_checks WHERE check_name IN ('done_station_sweep_748', 'wpc_key_748');
DROP TRIGGER IF EXISTS zzy_pdc_qc_key_wpc_748 ON public.vehicles;
DROP TRIGGER IF EXISTS zz_pdc_wpc_748 ON public.vehicles;
DROP TRIGGER IF EXISTS zz_pdc_wpc_748_ins ON public.vehicles;
DROP FUNCTION IF EXISTS pdc_key_number_private.qc_key_to_wpc_748();
DROP FUNCTION IF EXISTS pdc_key_number_private.capture_wpc_748();
DROP FUNCTION IF EXISTS public.list_wpc_timers_748();
DROP TABLE IF EXISTS pdc_key_number_private.vehicle_wpc_748;

CREATE OR REPLACE FUNCTION pdc_key_number_private.key_token_575(p_key text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
  SELECT CASE WHEN t IS NULL OR t ~ '^0+$' THEN NULL ELSE t END
  FROM (
    SELECT nullif(upper(regexp_replace(btrim(coalesce(p_key, '')), '\s+', '', 'g')), '') AS t
  ) s;
$function$;
INSERT INTO pdc_key_number_private.active_key_575(token, vehicle_id, stock_number)
SELECT 'WPC', v.id, v.stock_number FROM public.vehicles v
WHERE pdc_key_number_private.board_scope_575(v.id, v.deleted_at, v.board_purged_at, v.visible_on_board, v.lifecycle_state::text)
  AND upper(btrim(coalesce(v.key_number, ''))) = 'WPC'
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.refresh_arrival_age_563(p_vehicle_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_codex_intake_private'
AS $function$
DECLARE
 v_key timestamptz;
 v_tune timestamptz;
 v_arrived timestamptz;
 v_basis text;
BEGIN
 IF p_vehicle_id IS NULL THEN RETURN; END IF;
 -- r742 (F347): the key receipt is the latest of the key date on record, the latest key number typed on the board by
 -- staff, and the latest explicit To PMB release. greatest() ignores NULLs.
 SELECT greatest(
   (SELECT a.assigned_at FROM public.pdc_vehicle_key_assigned_562 a WHERE a.vehicle_id = p_vehicle_id),
   (SELECT max(e.created_at) FROM public.audit_events e
     WHERE e.table_name = 'vehicles' AND e.row_id = p_vehicle_id
       AND e.metadata->>'action' = 'update_pdc_vehicle_detail_fields_388'
       AND nullif(btrim(e.metadata->'changed_fields'->>'key_number'), '') IS NOT NULL),
   (SELECT max(m.moved_at) FROM public.vehicle_movements m
     WHERE m.vehicle_id = p_vehicle_id AND m.to_location = 'PMB' AND m.reason = 'Explicit Vehicle Locations release to PMB'))
 INTO v_key
 WHERE EXISTS (SELECT 1 FROM public.pdc_vehicle_key_assigned_562 a WHERE a.vehicle_id = p_vehicle_id);
 SELECT min(src.seen_at) INTO v_tune FROM (
  SELECT min(tv.created_at) AS seen_at
  FROM public.vehicles board
  JOIN public.vehicles tv ON tv.stock_number = board.stock_number
  WHERE board.id = p_vehicle_id AND tv.deleted_at IS NULL
    AND nullif(btrim(tv.stock_number), '') IS NOT NULL
    AND (tv.permanent_vehicle_id = 'TUNE/PMG:' || tv.stock_number OR tv.source_system = 'tune_pmg' OR tv.source_payload->>'intake_source_system' = 'tune_pmg')
  UNION ALL
  SELECT min(least(r.snapshot_at, r.recorded_at)) FROM pdc_codex_intake_private.tune_pmb_complete_receipts r WHERE r.vehicle_id = p_vehicle_id
  UNION ALL
  SELECT min(least(c.snapshot_at, c.recorded_at)) FROM pdc_codex_intake_private.tune_checkout_receipts c WHERE c.vehicle_id = p_vehicle_id
  UNION ALL
  SELECT min(e.created_at) FROM public.pdc_tune_intake_evidence_v5 e WHERE e.vehicle_id = p_vehicle_id
 ) src;
 IF v_key IS NULL AND v_tune IS NULL THEN
  v_basis := 'fallback'; v_arrived := NULL;
 ELSIF v_key IS NULL THEN
  v_basis := 'tune'; v_arrived := v_tune;
 ELSE
  v_basis := 'key'; v_arrived := v_key;
 END IF;
 INSERT INTO public.pdc_vehicle_pmb_arrival_age_563 (vehicle_id, key_at, tune_at, arrived_at, basis)
 VALUES (p_vehicle_id, v_key, v_tune, v_arrived, v_basis)
 ON CONFLICT (vehicle_id) DO UPDATE
  SET key_at = EXCLUDED.key_at, tune_at = EXCLUDED.tune_at, arrived_at = EXCLUDED.arrived_at, basis = EXCLUDED.basis
  WHERE public.pdc_vehicle_pmb_arrival_age_563.vehicle_id = EXCLUDED.vehicle_id;
END $function$;

CREATE OR REPLACE FUNCTION public.list_pmb_key_assigned_562()
 RETURNS TABLE(vehicle_id uuid, assigned_at timestamp with time zone, has_key boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE v_actor uuid := auth.uid();
BEGIN
 IF v_actor IS NULL OR NOT EXISTS (
   SELECT 1 FROM public.pdc_user_roles r
   WHERE r.auth_user_id = v_actor AND r.active AND r.account_status = 'approved'
     AND lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
 ) THEN
  RETURN;
 END IF;
 RETURN QUERY
 SELECT v.id, a.assigned_at, (btrim(coalesce(v.key_number, '')) <> '')
 FROM public.vehicles v
 LEFT JOIN public.pdc_vehicle_key_assigned_562 a ON a.vehicle_id = v.id
 WHERE v.deleted_at IS NULL
   AND (
     upper(btrim(coalesce(v.current_location, ''))) IN ('PMB','QC','PIT','RFT')
     OR upper(btrim(coalesce(v.location_override, ''))) IN ('PMB','QC')
     OR a.vehicle_id IS NOT NULL
   );
END $function$;

DO $post$
BEGIN
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_key_number_private.key_token_575(text)'::regprocedure)) <> 'bdf35576db35ecec8a16b40d05d8896d'
     OR md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_pmb_ack_private.refresh_arrival_age_563(uuid)'::regprocedure)) <> 'd104288a99dde96994084b7fc291efb7'
     OR md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.list_pmb_key_assigned_562()'::regprocedure)) <> '4c2334ec15cdce2044925ffd08ddc61e'
  THEN RAISE EXCEPTION 'r748 rollback: restored bodies do not match the originals'; END IF;
END $post$;
-- Sweep: put the r776 name back so the cron keeps running.
ALTER FUNCTION pdc_work_categories_private.sweep_done_station_bookings_748() RENAME TO sweep_done_station_bookings_776;
SELECT cron.unschedule('staging-done-station-planner-sweep-748');
SELECT cron.schedule('staging-done-station-planner-sweep-776', '* * * * *',
  'SELECT pdc_work_categories_private.sweep_done_station_bookings_776();');
