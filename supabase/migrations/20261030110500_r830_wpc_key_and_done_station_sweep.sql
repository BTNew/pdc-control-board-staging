-- r830 (F390, F391) / sorts 477, 478. Staging cdsmnqxtyyoeoznmbidd only.
--
-- F354. Craig 30 Oct 09:59: "why is 13073056 still showing on the fitting schedule, everything is done? fix this and make
-- sure no other cars on the board are scheduled if they are all ticked for that station".
-- The r746 tick trigger missed 13073056's last fitting tick (01:57 UTC); its planned FITTING booking stayed on the planner.
-- A one-minute sweep was applied live at 10:03 AWST as sweep_done_station_bookings_776 (cron
-- staging-done-station-planner-sweep-776). This release renames it to _830, keeps the same body, and adds its check.
--
-- F391. Craig 30 Oct 10:05: "if we change the key number to "WPC" or it goes into the QC Bay and free's up that key
-- number to be reused". 10:20 answers: into QC -> key changes to WPC; once WPC, the age is how long until Autocare
-- collects it, and all historic days (PMB timer, time before fitting, each location) are kept.
--   * WPC is not a key tag: key_token_575('WPC') is NULL, so any number of cars can be WPC and the old number is free.
--   * A car moving into QC (current_location or location_override) with a real key gets key WPC (trigger runs before
--     the r575 active-key guard, so the old number leaves active_key_575 in the same statement).
--   * pdc_key_number_private.vehicle_wpc_830 records when the car became WPC, the number it freed, and the PMB key date.
--     The PMB key date in pdc_vehicle_key_assigned_562 is never moved by WPC, and a typed WPC never resets the PMB age.
--   * list_pmb_key_assigned_562 says has_key = false for WPC (WPC is not in the PMB key bucket).
--   * list_wpc_timers_830() gives the board the WPC start, freed key, PMB key date and Autocare collection time.
-- Cars already in QC with a number are NOT changed here; that is r830b, only on Craig's go-ahead.
-- Rollback: supabase/rollbacks/20261030110500_r830_wpc_key_and_done_station_sweep.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard830$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r830: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r830: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r830: an import job is running'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order IN (477, 478) OR fault_id IN ('F390', 'F391') OR added_in = 'r830') THEN
    RAISE EXCEPTION 'r830: sort 477/478 or F390/F391 is taken'; END IF;
  IF to_regclass('pdc_key_number_private.vehicle_wpc_830') IS NOT NULL THEN RAISE EXCEPTION 'r830: already applied'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_key_number_private.key_token_575(text)'::regprocedure)) <> 'bdf35576db35ecec8a16b40d05d8896d'
     OR md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_pmb_ack_private.refresh_arrival_age_563(uuid)'::regprocedure)) <> 'd104288a99dde96994084b7fc291efb7'
     OR md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.list_pmb_key_assigned_562()'::regprocedure)) <> '4c2334ec15cdce2044925ffd08ddc61e'
     OR md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_work_categories_private.sweep_done_station_bookings_776()'::regprocedure)) <> '429f34d77cfdbd996eee41799fc7a60c'
  THEN RAISE EXCEPTION 'r830: a function changed since the release was written'; END IF;
END $guard830$;

-- F390: rename the live sweep (same body, source label r830_sweep).
CREATE OR REPLACE FUNCTION pdc_work_categories_private.sweep_done_station_bookings_830()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
  v_ids uuid[];
  v_stages text[];
  v_n integer := 0;
  v_stage text;
  v_actor uuid;
  v_email text;
  v_original_claims text := current_setting('request.jwt.claims', true);
BEGIN
  -- r830 (F390): safety net for r746. Every minute, a queued / planned booking on a station whose lines are all ticked
  -- is cleared, in case the tick trigger missed it (13073056 FITTING, 30 Oct 2026).
  v_ids := ARRAY(SELECT DISTINCT vehicle_id FROM public.workshop_bookings
                 WHERE deleted_at IS NULL AND status IN ('queued','planned'));
  IF pg_catalog.cardinality(v_ids) = 0 THEN RETURN 0; END IF;

  SELECT pg_catalog.array_agg(DISTINCT d.stage_code), pg_catalog.array_agg(DISTINCT d.vehicle_id)
    INTO v_stages, v_ids
  FROM pdc_work_categories_private.done_planner_stations_746(v_ids) d
  JOIN public.workshop_bookings wb ON wb.vehicle_id = d.vehicle_id AND wb.stage_id = d.stage_id
   AND wb.deleted_at IS NULL AND wb.status IN ('queued','planned');
  IF v_ids IS NULL THEN RETURN 0; END IF;

  -- Cron has no user: act as the workshop system actor (as workshop_sync_vehicle_stage_booking_duration does), because
  -- workshop_booking_history needs an actor.
  IF auth.uid() IS NULL THEN
    SELECT r.auth_user_id, r.email INTO v_actor, v_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id = r.auth_user_id
    WHERE r.active AND r.account_status = 'approved' AND r.role = 'administrator' AND r.auth_user_id IS NOT NULL
    ORDER BY r.created_at, r.id LIMIT 1;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PDC_830_SYSTEM_ACTOR_MISSING' USING errcode = '55000'; END IF;
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'email', v_email, 'role', 'authenticated')::text, true);
  END IF;

  v_n := pdc_work_categories_private.clear_done_station_bookings_746(v_ids, 'r830_sweep');
  IF v_n > 0 THEN
    FOREACH v_stage IN ARRAY v_stages LOOP
      PERFORM public.workshop_bump_station_revision(v_stage);
    END LOOP;
  END IF;
  PERFORM set_config('request.jwt.claims', coalesce(v_original_claims, ''), true);
  RETURN v_n;
END
$function$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.sweep_done_station_bookings_830() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule('staging-done-station-planner-sweep-776');
SELECT cron.schedule('staging-done-station-planner-sweep-830', '* * * * *',
  'SELECT pdc_work_categories_private.sweep_done_station_bookings_830();');
DROP FUNCTION pdc_work_categories_private.sweep_done_station_bookings_776();

-- F391: WPC is not a key tag.
CREATE OR REPLACE FUNCTION pdc_key_number_private.key_token_575(p_key text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
  -- r830 (F391): WPC means the car has left the PMB key tags (into QC); it is never a key tag, so it never clashes.
  SELECT CASE WHEN t IS NULL OR t ~ '^0+$' OR t = 'WPC' THEN NULL ELSE t END
  FROM (
    SELECT nullif(upper(regexp_replace(btrim(coalesce(p_key, '')), '\s+', '', 'g')), '') AS t
  ) s;
$function$;

-- 13073056 became WPC at 10:05 under the old rule and holds a WPC row; WPC is no longer a token.
DELETE FROM pdc_key_number_private.active_key_575 WHERE token = 'WPC';

CREATE TABLE pdc_key_number_private.vehicle_wpc_830 (
  vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
  wpc_at timestamptz NOT NULL,
  freed_key text,
  cause text NOT NULL CHECK (cause IN ('qc', 'manual', 'backfill')),
  pmb_key_at timestamptz,
  reverted_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
COMMENT ON TABLE pdc_key_number_private.vehicle_wpc_830 IS
  'r830 (F391): when a car''s key became WPC, the key number it freed and its PMB key date. The WPC age runs from wpc_at until Autocare collects it (vehicles.rft_collected_at).';
REVOKE ALL ON pdc_key_number_private.vehicle_wpc_830 FROM PUBLIC, anon, authenticated;

-- Into QC with a real key -> WPC. BEFORE trigger named to run just before zzz_pdc_active_key_575.
CREATE OR REPLACE FUNCTION pdc_key_number_private.qc_key_to_wpc_830()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_old_eff text := '';
  v_new_eff text := upper(btrim(coalesce(nullif(btrim(NEW.location_override), ''), NEW.current_location, '')));
BEGIN
  IF TG_OP = 'UPDATE' THEN
    v_old_eff := upper(btrim(coalesce(nullif(btrim(OLD.location_override), ''), OLD.current_location, '')));
  END IF;
  IF v_new_eff = 'QC' AND v_old_eff <> 'QC'
     AND pdc_key_number_private.key_token_575(NEW.key_number) IS NOT NULL THEN
    PERFORM set_config('pdc.wpc_cause_830', 'qc', true);
    NEW.key_number := 'WPC';
  END IF;
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION pdc_key_number_private.qc_key_to_wpc_830() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER zzy_pdc_qc_key_wpc_830 BEFORE INSERT OR UPDATE OF current_location, location_override ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION pdc_key_number_private.qc_key_to_wpc_830();

-- Record the WPC start (first time only; a revert and a new WPC starts again).
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
  ELSIF v_old_wpc AND NOT v_new_wpc THEN
    UPDATE pdc_key_number_private.vehicle_wpc_830 SET reverted_at = clock_timestamp(), updated_at = clock_timestamp()
    WHERE vehicle_id = NEW.id AND reverted_at IS NULL;
  END IF;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION pdc_key_number_private.capture_wpc_830() FROM PUBLIC, anon, authenticated;
-- No column list: the QC trigger changes key_number in a BEFORE trigger, which UPDATE OF key_number would not see.
CREATE TRIGGER zz_pdc_wpc_830 AFTER UPDATE ON public.vehicles
  FOR EACH ROW WHEN (OLD.key_number IS DISTINCT FROM NEW.key_number)
  EXECUTE FUNCTION pdc_key_number_private.capture_wpc_830();
CREATE TRIGGER zz_pdc_wpc_830_ins AFTER INSERT ON public.vehicles
  FOR EACH ROW WHEN (NEW.key_number IS NOT NULL)
  EXECUTE FUNCTION pdc_key_number_private.capture_wpc_830();

-- 13073056: WPC typed by Craig at 10:05 (freed 269).
INSERT INTO pdc_key_number_private.vehicle_wpc_830 (vehicle_id, wpc_at, freed_key, cause, pmb_key_at)
SELECT a.vehicle_id, a.changed_at, a.old_value, 'manual', k.assigned_at
FROM public.pdc_vehicle_key_number_audit_460 a
JOIN public.vehicles v ON v.id = a.vehicle_id AND upper(btrim(coalesce(v.key_number, ''))) = 'WPC'
LEFT JOIN public.pdc_vehicle_key_assigned_562 k ON k.vehicle_id = a.vehicle_id
WHERE upper(btrim(coalesce(a.new_value, ''))) = 'WPC'
  AND a.changed_at = (SELECT max(b.changed_at) FROM public.pdc_vehicle_key_number_audit_460 b
                      WHERE b.vehicle_id = a.vehicle_id AND upper(btrim(coalesce(b.new_value, ''))) = 'WPC')
ON CONFLICT (vehicle_id) DO NOTHING;

-- A typed WPC never moves the PMB age (r742 reads the latest typed key number).
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
 -- r830 (F391): a typed WPC is not a key receipt.
 SELECT greatest(
   (SELECT a.assigned_at FROM public.pdc_vehicle_key_assigned_562 a WHERE a.vehicle_id = p_vehicle_id),
   (SELECT max(e.created_at) FROM public.audit_events e
     WHERE e.table_name = 'vehicles' AND e.row_id = p_vehicle_id
       AND e.metadata->>'action' = 'update_pdc_vehicle_detail_fields_388'
       AND nullif(btrim(e.metadata->'changed_fields'->>'key_number'), '') IS NOT NULL
       AND upper(btrim(e.metadata->'changed_fields'->>'key_number')) <> 'WPC'),
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

-- WPC is not in the PMB key bucket.
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
 -- r830 (F391): a WPC car has no PMB key.
 RETURN QUERY
 SELECT v.id, a.assigned_at, (btrim(coalesce(v.key_number, '')) <> '' AND upper(btrim(v.key_number)) <> 'WPC')
 FROM public.vehicles v
 LEFT JOIN public.pdc_vehicle_key_assigned_562 a ON a.vehicle_id = v.id
 WHERE v.deleted_at IS NULL
   AND (
     upper(btrim(coalesce(v.current_location, ''))) IN ('PMB','QC','PIT','RFT')
     OR upper(btrim(coalesce(v.location_override, ''))) IN ('PMB','QC')
     OR a.vehicle_id IS NOT NULL
   );
END $function$;

-- The board reads the WPC timers here.
CREATE OR REPLACE FUNCTION public.list_wpc_timers_830()
 RETURNS TABLE(vehicle_id uuid, wpc_at timestamptz, freed_key text, cause text, pmb_key_at timestamptz, collected_at timestamptz)
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
 SELECT w.vehicle_id, w.wpc_at, w.freed_key, w.cause, w.pmb_key_at, v.rft_collected_at
 FROM pdc_key_number_private.vehicle_wpc_830 w
 JOIN public.vehicles v ON v.id = w.vehicle_id
 WHERE w.reverted_at IS NULL AND v.deleted_at IS NULL AND upper(btrim(coalesce(v.key_number, ''))) = 'WPC';
END $function$;
REVOKE ALL ON FUNCTION public.list_wpc_timers_830() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_wpc_timers_830() TO authenticated;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('done_station_sweep_830', 'F390',
  'The one-minute sweep clears any queued / planned booking left on a station whose lines are all ticked, and its last run succeeded.',
  $chk$
SELECT job.active AND job.n = 1 AND coalesce(last.ok, false) AS ok,
  'sweep job ' || CASE WHEN job.active THEN 'active' ELSE 'missing' END || ' | last run ' || coalesce(last.status, 'none') AS detail
FROM (SELECT count(*) AS n, coalesce(bool_and(active), false) AS active FROM cron.job
      WHERE jobname = 'staging-done-station-planner-sweep-830'
        AND command = 'SELECT pdc_work_categories_private.sweep_done_station_bookings_830();') job
LEFT JOIN LATERAL (
  SELECT d.status, d.status = 'succeeded' AS ok FROM cron.job_run_details d JOIN cron.job j USING (jobid)
  WHERE j.jobname = 'staging-done-station-planner-sweep-830' ORDER BY d.start_time DESC LIMIT 1) last ON true
$chk$, true, 477, 'r830');

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('wpc_key_830', 'F391',
  'WPC is not a key tag (never clashes, frees the number); a car moving into QC with a key becomes WPC; the WPC start is recorded and WPC is not in the PMB key bucket.',
  $chk$
SELECT pdc_key_number_private.key_token_575('wpc') IS NULL
   AND NOT EXISTS (SELECT 1 FROM pdc_key_number_private.active_key_575 WHERE token = 'WPC')
   AND trg.n = 3
   AND strpos(lst.src, '<> ''WPC''') > 0
   AND strpos(age.src, '<> ''WPC''') > 0
   AND has_function_privilege('authenticated', 'public.list_wpc_timers_830()', 'EXECUTE')
   AND NOT has_function_privilege('anon', 'public.list_wpc_timers_830()', 'EXECUTE')
   AND missing.n = 0 AS ok,
  'triggers ' || trg.n::text || ' | WPC cars with no start ' || missing.n::text AS detail
FROM (SELECT count(*) AS n FROM pg_trigger WHERE tgrelid = 'public.vehicles'::regclass AND NOT tgisinternal AND tgenabled = 'O'
      AND tgname IN ('zzy_pdc_qc_key_wpc_830', 'zz_pdc_wpc_830', 'zz_pdc_wpc_830_ins')) trg,
     (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.list_pmb_key_assigned_562()')) lst,
     (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('pdc_pmb_ack_private.refresh_arrival_age_563(uuid)')) age,
     (SELECT count(*) AS n FROM public.vehicles v
      WHERE v.deleted_at IS NULL AND upper(btrim(coalesce(v.key_number, ''))) = 'WPC'
        AND NOT EXISTS (SELECT 1 FROM pdc_key_number_private.vehicle_wpc_830 w WHERE w.vehicle_id = v.id AND w.reverted_at IS NULL)) missing
$chk$, true, 478, 'r830');

DO $post830$
DECLARE r record;
BEGIN
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'wpc_key_830') INTO r;
  IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r830: wpc_key_830 red after apply: %', r.detail; END IF;
  IF pdc_key_number_private.key_token_575(' 269 ') IS DISTINCT FROM '269' THEN RAISE EXCEPTION 'r830: key token changed for numbers'; END IF;
END $post830$;
