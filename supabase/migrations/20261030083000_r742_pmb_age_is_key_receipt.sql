-- r742 (F347) / sort 459. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 08:22: "Age is when it recieved a key number, which is when its TO PMB happens or keynumber is added."
-- 13047269 showed 58 days in New to PMB: the r708 key-list sync had set its key date to the Navision Date In (2 Sep)
-- over the live key add on the board (29 Oct 08:00), and r563 took the earlier of key and first-seen-in-Tune anyway.
-- New rule: the PMB age is the key receipt. Key receipt = the latest of the key date on record, the latest key number
-- typed on the board by staff (update_pdc_vehicle_detail_fields_388 audit), and the latest explicit To PMB release.
-- Tune first-seen is only the fallback when the car has no key. An explicit To PMB release now refreshes the age.
-- Rehearsed rolled back: 129 active cars move to a later date (most from the 6 Oct board start to their key date).
-- Rollback: supabase/rollbacks/20261030083000_r742_pmb_age_is_key_receipt.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $pre742$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r742: staging only'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'pdc_pmb_ack_private.refresh_arrival_age_563(uuid)'::regprocedure) IS DISTINCT FROM '1ba2a701b2deffe378b921b65441f14e'
    THEN RAISE EXCEPTION 'r742: refresh_arrival_age_563 is not the r563 body'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature LIKE '%refresh_arrival_age_563%') THEN RAISE EXCEPTION 'r742: refresh is pinned, not expected'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'pmb_arrival_age_563' AND strpos(check_sql, $a$OR (basis = 'tune' AND arrived_at = tune_at AND (key_at IS NULL OR tune_at < key_at))$a$) > 0 AND strpos(check_sql, $a$OR (basis = 'key' AND arrived_at = key_at AND (tune_at IS NULL OR key_at <= tune_at))$a$) > 0 AND strpos(check_sql, 'AND trg.n = 6') > 0) <> 1
    THEN RAISE EXCEPTION 'r742: check anchors missing'; END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'zz_pdc_arrival_age_563_move') THEN RAISE EXCEPTION 'r742: move trigger exists'; END IF;
END $pre742$;

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

-- An explicit To PMB release refreshes the age (the existing zz_ triggers cover key, PMB arrival, evidence and vehicle rows).
CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.capture_move_arrival_age_742()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $t$
BEGIN
 IF NEW.to_location = 'PMB' THEN PERFORM pdc_pmb_ack_private.refresh_arrival_age_563(NEW.vehicle_id); END IF;
 RETURN NULL;
END $t$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.capture_move_arrival_age_742() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER zz_pdc_arrival_age_563_move AFTER INSERT ON public.vehicle_movements
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.capture_move_arrival_age_742();

UPDATE pdc_ops.regression_checks
SET check_sql = replace(replace(replace(replace(check_sql,
   $a$OR (basis = 'tune' AND arrived_at = tune_at AND (key_at IS NULL OR tune_at < key_at))$a$,
   $a$OR (basis = 'tune' AND arrived_at = tune_at AND key_at IS NULL)$a$),
   $a$OR (basis = 'key' AND arrived_at = key_at AND (tune_at IS NULL OR key_at <= tune_at))$a$,
   $a$OR (basis = 'key' AND arrived_at = key_at)$a$),
   'AND trg.n = 6', 'AND trg.n = 7'),
   $a$'zz_pdc_arrival_age_563_evidence','zz_pdc_arrival_age_563_veh','zz_pdc_arrival_age_563_veh_upd'$a$,
   $a$'zz_pdc_arrival_age_563_evidence','zz_pdc_arrival_age_563_veh','zz_pdc_arrival_age_563_veh_upd','zz_pdc_arrival_age_563_move'$a$),
 description = 'PMB arrival age (r563, r742): the age is the key receipt (latest of key date, staff key add, explicit To PMB); Tune first-seen only when there is no key; seven zz_ triggers keep it fresh; the list RPC is for staff only.'
WHERE check_name = 'pmb_arrival_age_563';

-- The table rule follows: key wins whenever a key exists.
ALTER TABLE public.pdc_vehicle_pmb_arrival_age_563 DROP CONSTRAINT pdc_vehicle_pmb_arrival_age_563_basis_ck;
ALTER TABLE public.pdc_vehicle_pmb_arrival_age_563 ADD CONSTRAINT pdc_vehicle_pmb_arrival_age_563_basis_ck CHECK (
  (basis = 'fallback' AND arrived_at IS NULL AND key_at IS NULL AND tune_at IS NULL)
  OR (basis = 'key' AND arrived_at IS NOT NULL AND arrived_at = key_at)
  OR (basis = 'tune' AND arrived_at IS NOT NULL AND arrived_at = tune_at AND key_at IS NULL)) NOT VALID;

-- Recompute every row under the new rule.
DO $recompute742$
DECLARE r record; n integer := 0;
BEGIN
  FOR r IN SELECT vehicle_id FROM public.pdc_vehicle_pmb_arrival_age_563 LOOP
    PERFORM pdc_pmb_ack_private.refresh_arrival_age_563(r.vehicle_id); n := n + 1;
  END LOOP;
  IF n < 100 THEN RAISE EXCEPTION 'r742: only % rows recomputed', n; END IF;
END $recompute742$;
ALTER TABLE public.pdc_vehicle_pmb_arrival_age_563 VALIDATE CONSTRAINT pdc_vehicle_pmb_arrival_age_563_basis_ck;

DO $post742$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('pmb_arrival_age_563','regression_checks_self_test','protected_function_md5s') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r742: % red after apply: %', r.check_name, left(r.detail, 200); END IF;
  END LOOP;
  IF (SELECT basis FROM public.pdc_vehicle_pmb_arrival_age_563 WHERE vehicle_id = 'b0f151b1-bd84-44e1-9b58-95cca94a2ffe') <> 'key'
     OR (SELECT arrived_at FROM public.pdc_vehicle_pmb_arrival_age_563 WHERE vehicle_id = 'b0f151b1-bd84-44e1-9b58-95cca94a2ffe') < '2026-10-29 07:00+08'
    THEN RAISE EXCEPTION 'r742: 13047269 still dated before 29 Oct'; END IF;
END $post742$;
