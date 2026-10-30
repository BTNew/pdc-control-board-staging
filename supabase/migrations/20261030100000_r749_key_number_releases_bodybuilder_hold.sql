-- r749 (F354) / sort 462. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 08:22: "Age is when it recieved a key number, which is when its TO PMB happens or keynumber is added."
-- 09:54: "13047269 is still showing in 'New to pmb'". The car arrived from the body builder on 29 Oct 07:31 (r574 hold:
-- stays in New to PMB until someone presses To PMB) and got key 641 at 08:00, but nobody pressed To PMB, so the hold
-- stayed open and the car sat in New to PMB with its key. Under Craig's rule a key number IS the arrival at PMB, so a
-- key number now releases a body-builder hold the same way To PMB does (release_action 'key_number'). Three cars had
-- an open hold with a key (13047269, 13077203, 13109753); they are released here.
-- Rollback: supabase/rollbacks/20261030100000_r749_key_number_releases_bodybuilder_hold.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $pre745$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r749: staging only'; END IF;
  IF to_regprocedure('pdc_pmb_ack_private.release_hold_on_key_745(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r749: already applied'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 462 OR fault_id = 'F354' OR added_in = 'r749') THEN RAISE EXCEPTION 'r749: sort 462 or F354 is taken'; END IF;
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'bodybuilder_hold_574_release_chk' AND conrelid = 'pdc_pmb_ack_private.bodybuilder_hold_574'::regclass)
     <> $c$CHECK ((((released_at IS NULL) AND (released_by IS NULL) AND (release_action IS NULL)) OR ((released_at IS NOT NULL) AND (released_by IS NOT NULL) AND (release_action = 'to_pmb'::text))))$c$
    THEN RAISE EXCEPTION 'r749: hold release check is not the r574 text'; END IF;
END $pre745$;

-- A key number release may come from a trigger with no signed-in actor, so released_by is optional for it.
ALTER TABLE pdc_pmb_ack_private.bodybuilder_hold_574 DROP CONSTRAINT bodybuilder_hold_574_release_chk;
ALTER TABLE pdc_pmb_ack_private.bodybuilder_hold_574 ADD CONSTRAINT bodybuilder_hold_574_release_chk CHECK (
  (released_at IS NULL AND released_by IS NULL AND release_action IS NULL)
  OR (released_at IS NOT NULL AND release_action = 'to_pmb' AND released_by IS NOT NULL)
  OR (released_at IS NOT NULL AND release_action = 'key_number'));

CREATE FUNCTION pdc_pmb_ack_private.release_hold_on_key_745(p_vehicle_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE r record; n integer := 0;
BEGIN
 IF p_vehicle_id IS NULL THEN RETURN 0; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = p_vehicle_id AND v.deleted_at IS NULL AND btrim(coalesce(v.key_number, '')) <> '') THEN RETURN 0; END IF;
 FOR r IN SELECT a.arrival_id FROM public.pdc_pmb_arrival_557 a
   JOIN pdc_pmb_ack_private.bodybuilder_hold_574 h ON h.arrival_id = a.arrival_id AND h.released_at IS NULL
   WHERE a.vehicle_id = p_vehicle_id AND a.closed_at IS NULL AND a.source = 'bodybuilder'
   ORDER BY a.arrival_at FOR UPDATE OF a, h
 LOOP
  -- Same release as push_new_to_pmb_562 (To PMB); the arrival guard accepts it because the key is on the car.
  PERFORM set_config('pdc.bodybuilder_to_pmb_574', r.arrival_id::text, true);
  UPDATE public.pdc_pmb_arrival_557 SET closed_at = clock_timestamp() WHERE arrival_id = r.arrival_id AND closed_at IS NULL;
  UPDATE pdc_pmb_ack_private.bodybuilder_hold_574
   SET released_at = clock_timestamp(), released_by = auth.uid(), release_action = 'key_number'
   WHERE arrival_id = r.arrival_id AND released_at IS NULL;
  n := n + 1;
 END LOOP;
 IF n > 0 THEN PERFORM pdc_pmb_ack_private.drop_read_caches_557(); END IF;
 RETURN n;
END $fn$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.release_hold_on_key_745(uuid) FROM PUBLIC, anon, authenticated;

-- A key typed or imported onto a car at PMB releases its hold. zz_ so it runs after capture_557 opens one in the same update.
CREATE FUNCTION pdc_pmb_ack_private.key_releases_hold_745()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $t$
BEGIN
 PERFORM pdc_pmb_ack_private.release_hold_on_key_745(NEW.id);
 RETURN NULL;
END $t$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.key_releases_hold_745() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER zz_pdc_key_releases_hold_745 AFTER UPDATE OF key_number ON public.vehicles
 FOR EACH ROW WHEN (btrim(coalesce(NEW.key_number, '')) <> '' AND NEW.key_number IS DISTINCT FROM OLD.key_number)
 EXECUTE FUNCTION pdc_pmb_ack_private.key_releases_hold_745();

-- A hold opened for a car that already has a key is released at commit (the hold row lands after the arrival row).
CREATE FUNCTION pdc_pmb_ack_private.hold_opened_with_key_745()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $t$
BEGIN
 PERFORM pdc_pmb_ack_private.release_hold_on_key_745(NEW.vehicle_id);
 RETURN NULL;
END $t$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.hold_opened_with_key_745() FROM PUBLIC, anon, authenticated;
CREATE CONSTRAINT TRIGGER zz_pdc_hold_opened_with_key_745 AFTER INSERT ON pdc_pmb_ack_private.bodybuilder_hold_574
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.hold_opened_with_key_745();

-- The three cars sitting in New to PMB with a key.
DO $data745$
DECLARE r record; n integer := 0;
BEGIN
  FOR r IN SELECT DISTINCT a.vehicle_id FROM public.pdc_pmb_arrival_557 a JOIN public.vehicles v ON v.id = a.vehicle_id
           WHERE a.source = 'bodybuilder' AND a.closed_at IS NULL AND v.deleted_at IS NULL AND btrim(coalesce(v.key_number, '')) <> '' LOOP
    n := n + pdc_pmb_ack_private.release_hold_on_key_745(r.vehicle_id);
  END LOOP;
  IF n <> 3 THEN RAISE EXCEPTION 'r749: expected to release 3 holds, released %', n; END IF;
END $data745$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, added_in, enabled, sort_order, description, check_sql) VALUES ('key_number_releases_bodybuilder_hold_745', 'F354', 'r749', true, 462,
 'Body-builder hold (r749): a key number releases the hold, so no car with a key number waits in New to PMB on an open body-builder hold; both release triggers are in place.',
$chk745$
SELECT NOT EXISTS (
    SELECT 1 FROM public.pdc_pmb_arrival_557 a JOIN public.vehicles v ON v.id = a.vehicle_id
    WHERE a.source = 'bodybuilder' AND a.closed_at IS NULL AND v.deleted_at IS NULL AND btrim(coalesce(v.key_number, '')) <> ''
      AND a.arrival_at < now() - interval '5 minutes')
  AND (SELECT count(*) FROM pg_trigger WHERE tgname IN ('zz_pdc_key_releases_hold_745', 'zz_pdc_hold_opened_with_key_745')) = 2
  AND NOT has_function_privilege('authenticated', 'pdc_pmb_ack_private.release_hold_on_key_745(uuid)', 'EXECUTE')
 AS ok, 'no keyed car waits on a body-builder hold' AS detail
$chk745$);

DO $post745$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('key_number_releases_bodybuilder_hold_745','regression_checks_self_test','protected_function_md5s') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r749: % red after apply: %', r.check_name, left(r.detail, 200); END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.pdc_pmb_arrival_557 WHERE vehicle_id = 'b0f151b1-bd84-44e1-9b58-95cca94a2ffe' AND closed_at IS NULL) THEN RAISE EXCEPTION 'r749: 13047269 still open'; END IF;
END $post745$;
