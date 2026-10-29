-- r727 (F337). Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 2026 16:12: "remember if a vehicle has a key number, it needs to be placed at PMB automatically".
-- A key is given when the car comes off the truck, so a keyed car still showing In transit, Yard Hold or Other is wrong.
-- Any insert or update that leaves an active keyed car at IT / YH / Other / blank (location or override) puts it at
-- PMB, the same way the To PMB button does (date to PMB kept or set today, override and bay cleared, a movement row).
-- QC, PIT, RFT and anything past QC are never touched. Imports are not changed; this runs on the vehicle row.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard727$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r727: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r727: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r727: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 475 OR fault_id = 'F337' OR added_in = 'r727') THEN RAISE EXCEPTION 'r727: sort 475 or F337 is taken'; END IF;
  IF to_regprocedure('public.pdc_key_means_pmb_727()') IS NOT NULL THEN RAISE EXCEPTION 'r727: already applied'; END IF;
END $guard727$;

CREATE TEMP TABLE r727_green ON COMMIT DROP AS SELECT check_name FROM pdc_ops.regression_checks WHERE false;
DO $pre727$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks
           WHERE enabled AND (check_sql ILIKE '%pg_trigger%' OR check_sql ILIKE '%current_location%' OR check_sql ILIKE '%pmb_transfer_vehicle%') LOOP
    BEGIN EXECUTE r.check_sql INTO ok, detail; EXCEPTION WHEN OTHERS THEN ok := false; END;
    IF ok IS TRUE THEN INSERT INTO r727_green VALUES (r.check_name); END IF;
  END LOOP;
END $pre727$;

CREATE FUNCTION public.pdc_key_means_pmb_727()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE
  v_loc text := upper(btrim(coalesce(NEW.current_location, '')));
  v_over text := upper(btrim(coalesce(NEW.location_override, '')));
  v_eff text;
BEGIN
  IF btrim(coalesce(NEW.key_number, '')) = '' OR NEW.deleted_at IS NOT NULL OR NEW.board_purged_at IS NOT NULL
     OR NEW.lifecycle_state::text <> 'active'
     OR NEW.qc_completed_at IS NOT NULL OR NEW.rft_transferred_at IS NOT NULL OR NEW.rft_collected_at IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF v_loc = 'YARD HOLD' THEN v_loc := 'YH'; ELSIF v_loc = 'IN TRANSIT' THEN v_loc := 'IT'; END IF;
  IF v_over = 'YARD HOLD' THEN v_over := 'YH'; ELSIF v_over = 'IN TRANSIT' THEN v_over := 'IT'; END IF;
  v_eff := CASE WHEN v_over <> '' THEN v_over ELSE v_loc END;
  -- r727 (F337): a keyed car waiting at IT / YH / Other / blank goes to PMB
  IF v_eff NOT IN ('YH', 'IT', 'OTHER', '') OR v_loc NOT IN ('YH', 'IT', 'OTHER', '', 'PMB') THEN RETURN NEW; END IF;
  NEW.current_location := 'PMB';
  IF v_over <> '' THEN
    NEW.location_override := NULL; NEW.location_override_reason := NULL; NEW.location_override_at := NULL; NEW.location_override_by := NULL;
  END IF;
  NEW.date_to_pmb := coalesce(NEW.date_to_pmb, (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date);
  NEW.pmb_stage := NULL; NEW.pmb_bay_stage := NULL; NEW.pmb_bay_number := NULL;
  IF TG_OP = 'UPDATE' AND upper(btrim(coalesce(nullif(OLD.location_override, ''), OLD.current_location, ''))) = 'PMB' THEN RETURN NEW; END IF; -- already at PMB: no movement row
  PERFORM set_config('pdc.key_pmb_727', NEW.id::text || '|' || CASE WHEN TG_OP = 'INSERT' THEN '' ELSE coalesce(OLD.current_location, '') END, true);
  RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION public.pdc_key_means_pmb_727() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.pdc_key_means_pmb_727_log()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_mark text := coalesce(current_setting('pdc.key_pmb_727', true), '');
BEGIN
  IF v_mark = '' OR split_part(v_mark, '|', 1) <> NEW.id::text THEN RETURN NULL; END IF;
  PERFORM set_config('pdc.key_pmb_727', '', true);
  -- moved_by is required; an import has no signed-in user, so the row's own updater is used (no row if neither is known)
  INSERT INTO public.vehicle_movements (vehicle_id, from_location, to_location, reason, moved_by)
  SELECT NEW.id, nullif(substr(v_mark, length(NEW.id::text) + 2), ''), 'PMB', 'r727: has a key number, placed at PMB automatically', w
  FROM (SELECT coalesce(auth.uid(), NEW.updated_by, NEW.created_by) AS w) x WHERE w IS NOT NULL;
  RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION public.pdc_key_means_pmb_727_log() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER zzzz_pdc_key_means_pmb_727 BEFORE INSERT OR UPDATE OF key_number, current_location, location_override, lifecycle_state, deleted_at
  ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.pdc_key_means_pmb_727();
CREATE TRIGGER zzzz_pdc_key_means_pmb_727_log AFTER INSERT OR UPDATE OF key_number, current_location, location_override, lifecycle_state, deleted_at
  ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.pdc_key_means_pmb_727_log();

-- Every keyed car that is waiting at IT / YH / Other now goes to PMB.
UPDATE public.vehicles SET current_location = current_location
WHERE deleted_at IS NULL AND board_purged_at IS NULL AND lifecycle_state::text = 'active' AND btrim(coalesce(key_number, '')) <> ''
  AND qc_completed_at IS NULL AND rft_transferred_at IS NULL AND rft_collected_at IS NULL
  AND upper(btrim(coalesce(nullif(location_override, ''), current_location, ''))) IN ('YH', 'YARD HOLD', 'IT', 'IN TRANSIT', 'OTHER', '');

DO $check727$
DECLARE ok boolean; detail text; r record;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('key_means_pmb_727', 'F337', 'A car with a key number is never left at In transit, Yard Hold or Other: it is placed at PMB automatically.',
    $chk$
SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.vehicles'::regclass AND tgname = 'zzzz_pdc_key_means_pmb_727' AND tgenabled <> 'D')
   AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.vehicles'::regclass AND tgname = 'zzzz_pdc_key_means_pmb_727_log' AND tgenabled <> 'D')
   AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.board_purged_at IS NULL AND v.lifecycle_state::text = 'active'
         AND btrim(coalesce(v.key_number, '')) <> '' AND v.qc_completed_at IS NULL AND v.rft_transferred_at IS NULL AND v.rft_collected_at IS NULL
         AND upper(btrim(coalesce(nullif(v.location_override, ''), v.current_location, ''))) IN ('YH', 'YARD HOLD', 'IT', 'IN TRANSIT', 'OTHER', ''))
 AS ok, 'every keyed car is at PMB or later' AS detail
$chk$, true, 475, 'r727');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'key_means_pmb_727') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r727: check red: %', detail; END IF;
  FOR r IN SELECT c.check_name, c.check_sql FROM pdc_ops.regression_checks c WHERE c.check_name IN (SELECT g.check_name FROM r727_green g) LOOP
    EXECUTE r.check_sql INTO ok, detail;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r727: check % went red: %', r.check_name, detail; END IF;
  END LOOP;
END $check727$;
