-- r563 (F177) / sort 336. Craig approved go-live 27 Oct 2026 08:40 AWST
-- ("Go live with #547", relayed from his chat with Kajel).
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
--
-- r560 / F174 is the stock side panel (frontend, no sort).
-- r561 / F175 is the slim planner header (frontend, no sort).
-- r562 / F176 / sort 335 is the live key gate (#546).
-- Next free is r563 / F177 / sort 336.
--
-- The PMB age is the earlier of the first key number and the first Tune import
-- (TUNE/PMG:<stock> or a Tune receipt). Where neither exists, keep the board
-- arrival and flag it.
-- The key instant is public.pdc_vehicle_key_assigned_562.assigned_at. r562
-- already stores the earliest of the r460 key audit, audit_events, and a
-- positive numeric service snapshot. This file reads that instant; it does
-- not recompute it. The r562 key gate is unchanged: a keyless vehicle still
-- cannot leave New to PMB. A keyless vehicle with a Tune date shows that age
-- instead of "No key". "No key" remains only when the key instant, the Tune
-- instant, and the board arrival are all missing.
--
-- Read-only staging counts before the preview, location PMB 248: 49 key-earlier,
-- 199 Tune-earlier (14 of them have no key), 0 with neither. QC adds 7 key and
-- 8 Tune (5 of them have no key). Undo does not change vehicles or arrivals.
-- Pin count stays 241.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r563: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r563: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r563: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_key_gate_562' AND fault_id='F176' AND sort_order=335 AND added_in='r562') THEN RAISE EXCEPTION 'r563: r562 / F176 sort 335 is not present'; END IF;
 IF pg_catalog.to_regclass('public.pdc_vehicle_key_assigned_562') IS NULL THEN RAISE EXCEPTION 'r563: key assignment table is missing'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=336 OR fault_id='F177' OR check_name='pmb_arrival_age_563' OR added_in='r563') THEN RAISE EXCEPTION 'r563: sort 336 or F177 is taken'; END IF;
 IF pg_catalog.to_regclass('public.pdc_vehicle_pmb_arrival_age_563') IS NOT NULL THEN RAISE EXCEPTION 'r563: already applied'; END IF;
 PERFORM set_config('pdc.r563_pins', (SELECT count(*)::text FROM pdc_ops.expected_function_md5), true);
 PERFORM set_config('pdc.r563_pmb', (SELECT count(*)::text FROM public.vehicles WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, '')))='PMB'), true);
 PERFORM set_config('pdc.r563_backfill', (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE source='backfill' AND closed_at IS NOT NULL), true);
 PERFORM set_config('pdc.r563_open', (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE closed_at IS NULL), true);
END $g$;

CREATE TABLE public.pdc_vehicle_pmb_arrival_age_563 (
 vehicle_id uuid PRIMARY KEY,
 key_at timestamptz,
 tune_at timestamptz,
 arrived_at timestamptz,
 basis text NOT NULL CHECK (basis IN ('key','tune','fallback')),
 CONSTRAINT pdc_vehicle_pmb_arrival_age_563_basis_ck CHECK (
  (basis = 'fallback' AND arrived_at IS NULL AND key_at IS NULL AND tune_at IS NULL)
  OR (basis = 'key' AND arrived_at IS NOT NULL AND arrived_at = key_at AND (tune_at IS NULL OR key_at <= tune_at))
  OR (basis = 'tune' AND arrived_at IS NOT NULL AND arrived_at = tune_at AND (key_at IS NULL OR tune_at < key_at))
 )
);
ALTER TABLE public.pdc_vehicle_pmb_arrival_age_563 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_vehicle_pmb_arrival_age_563 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.pdc_vehicle_pmb_arrival_age_563 IS 'r563 (F177): PMB age instant. Earlier of the r562 key instant and the first Tune import. fallback means neither was found.';

CREATE FUNCTION pdc_pmb_ack_private.refresh_arrival_age_563(p_vehicle_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'pdc_codex_intake_private' AS $age563$
DECLARE
 v_key timestamptz;
 v_tune timestamptz;
 v_arrived timestamptz;
 v_basis text;
BEGIN
 IF p_vehicle_id IS NULL THEN RETURN; END IF;
 SELECT a.assigned_at INTO v_key FROM public.pdc_vehicle_key_assigned_562 a WHERE a.vehicle_id = p_vehicle_id;
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
 ELSIF v_tune IS NOT NULL AND (v_key IS NULL OR v_tune < v_key) THEN
  v_basis := 'tune'; v_arrived := v_tune;
 ELSE
  v_basis := 'key'; v_arrived := v_key;
 END IF;
 INSERT INTO public.pdc_vehicle_pmb_arrival_age_563 (vehicle_id, key_at, tune_at, arrived_at, basis)
 VALUES (p_vehicle_id, v_key, v_tune, v_arrived, v_basis)
 ON CONFLICT (vehicle_id) DO UPDATE
  SET key_at = EXCLUDED.key_at, tune_at = EXCLUDED.tune_at, arrived_at = EXCLUDED.arrived_at, basis = EXCLUDED.basis
  WHERE public.pdc_vehicle_pmb_arrival_age_563.vehicle_id = EXCLUDED.vehicle_id;
END $age563$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.refresh_arrival_age_563(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION pdc_pmb_ack_private.capture_arrival_age_563() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $cap563$
DECLARE v_id uuid;
BEGIN
 IF TG_TABLE_NAME = 'vehicles' THEN v_id := coalesce(NEW.id, OLD.id);
 ELSE v_id := coalesce(NEW.vehicle_id, OLD.vehicle_id); END IF;
 PERFORM pdc_pmb_ack_private.refresh_arrival_age_563(v_id);
 RETURN NULL;
END $cap563$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.capture_arrival_age_563() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER zz_pdc_arrival_age_563_key
 AFTER INSERT OR UPDATE OR DELETE ON public.pdc_vehicle_key_assigned_562
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.capture_arrival_age_563();
CREATE TRIGGER zz_pdc_arrival_age_563_pmb
 AFTER INSERT ON pdc_codex_intake_private.tune_pmb_complete_receipts
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.capture_arrival_age_563();
CREATE TRIGGER zz_pdc_arrival_age_563_out
 AFTER INSERT ON pdc_codex_intake_private.tune_checkout_receipts
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.capture_arrival_age_563();
CREATE TRIGGER zz_pdc_arrival_age_563_evidence
 AFTER INSERT ON public.pdc_tune_intake_evidence_v5
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.capture_arrival_age_563();
CREATE TRIGGER zz_pdc_arrival_age_563_veh
 AFTER INSERT ON public.vehicles
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.capture_arrival_age_563();
CREATE TRIGGER zz_pdc_arrival_age_563_veh_upd
 AFTER UPDATE OF stock_number, permanent_vehicle_id, source_system, source_payload ON public.vehicles
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.capture_arrival_age_563();

DO $fill$
DECLARE r record;
BEGIN
 FOR r IN
  SELECT v.id FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND (
    upper(btrim(coalesce(v.current_location, ''))) IN ('PMB','QC','PIT','RFT')
    OR upper(btrim(coalesce(v.location_override, ''))) IN ('PMB','QC')
  )
 LOOP
  PERFORM pdc_pmb_ack_private.refresh_arrival_age_563(r.id);
 END LOOP;
END $fill$;

CREATE FUNCTION public.list_pmb_arrival_age_563()
 RETURNS TABLE (vehicle_id uuid, key_at timestamptz, tune_at timestamptz, arrived_at timestamptz, basis text, date_to_pmb date)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $list563$
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
 SELECT v.id, a.key_at, a.tune_at, a.arrived_at, coalesce(a.basis, 'fallback'), v.date_to_pmb
 FROM public.vehicles v
 LEFT JOIN public.pdc_vehicle_pmb_arrival_age_563 a ON a.vehicle_id = v.id
 WHERE v.deleted_at IS NULL AND (
  upper(btrim(coalesce(v.current_location, ''))) IN ('PMB','QC','PIT','RFT')
  OR upper(btrim(coalesce(v.location_override, ''))) IN ('PMB','QC')
  OR a.vehicle_id IS NOT NULL
 );
END $list563$;
REVOKE ALL ON FUNCTION public.list_pmb_arrival_age_563() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_pmb_arrival_age_563() TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('pmb_arrival_age_563', 'F177',
 'The PMB age is the earlier of the key-number instant and the first Tune import. A vehicle with neither is fallback and keeps the board arrival on the client. The pin count stays 241. The check uses search_path pg_catalog, schema-qualified types, and no regprocedure cast.',
 $chk563$
SELECT
  pins.n = 241 AND added.n = 0 AND aged.relrowsecurity
  AND refresh.present AND refresh.tune_row AND refresh.receipt AND refresh.key_table
  AND listfn.present AND listfn.auth_exec AND listfn.anon_blocked
  AND trg.n = 6
  AND ruled.ok
  AS ok,
  'pins=' || pins.n::pg_catalog.text || ' triggers=' || trg.n::pg_catalog.text AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r563') added
CROSS JOIN (
  SELECT c.relrowsecurity FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_vehicle_pmb_arrival_age_563'
) aged
CROSS JOIN (
  SELECT coalesce(bool_and(
    pg_catalog.strpos(p.prosrc, 'TUNE/PMG:') > 0
    AND pg_catalog.strpos(p.prosrc, 'tune_pmb_complete_receipts') > 0
    AND pg_catalog.strpos(p.prosrc, 'pdc_tune_intake_evidence_v5') > 0
    AND pg_catalog.strpos(p.prosrc, 'pdc_vehicle_key_assigned_562') > 0
    AND pg_catalog.strpos(p.prosrc, 'fallback') > 0
  ), false) AS present,
  coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'TUNE/PMG:') > 0), false) AS tune_row,
  coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'tune_pmb_complete_receipts') > 0), false) AS receipt,
  coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'pdc_vehicle_key_assigned_562') > 0), false) AS key_table
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'refresh_arrival_age_563'
) refresh
CROSS JOIN (
  SELECT count(*) > 0 AS present,
    coalesce(bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE')), false) AS auth_exec,
    coalesce(bool_and(NOT has_function_privilege('anon', p.oid, 'EXECUTE')), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'list_pmb_arrival_age_563'
) listfn
CROSS JOIN (
  SELECT count(*) AS n FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  WHERE t.tgname IN (
    'zz_pdc_arrival_age_563_key','zz_pdc_arrival_age_563_pmb','zz_pdc_arrival_age_563_out',
    'zz_pdc_arrival_age_563_evidence','zz_pdc_arrival_age_563_veh','zz_pdc_arrival_age_563_veh_upd'
  ) AND NOT t.tgisinternal
) trg
CROSS JOIN (
  SELECT coalesce(bool_and(
    (basis = 'fallback' AND arrived_at IS NULL)
    OR (basis = 'key' AND arrived_at = key_at AND (tune_at IS NULL OR key_at <= tune_at))
    OR (basis = 'tune' AND arrived_at = tune_at AND (key_at IS NULL OR tune_at < key_at))
  ), false) AS ok
  FROM public.pdc_vehicle_pmb_arrival_age_563
) ruled
$chk563$, true, 336, 'r563');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r563: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r563') THEN RAISE EXCEPTION 'r563: a pin was inserted'; END IF;
 IF current_setting('pdc.r563_pmb', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.vehicles WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, '')))='PMB') THEN RAISE EXCEPTION 'r563: PMB vehicle count changed'; END IF;
 IF current_setting('pdc.r563_backfill', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE source='backfill' AND closed_at IS NOT NULL) THEN RAISE EXCEPTION 'r563: closed backfill count changed'; END IF;
 IF current_setting('pdc.r563_open', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE closed_at IS NULL) THEN RAISE EXCEPTION 'r563: open New to PMB count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563' AND enabled)<>1 THEN RAISE EXCEPTION 'r563: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog', true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r563: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
