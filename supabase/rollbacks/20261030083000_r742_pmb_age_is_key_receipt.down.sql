-- r742 rollback: age goes back to the earlier of key date and Tune first-seen (r563), the To PMB trigger is dropped,
-- the check is restored and every row recomputed. Staging cdsmnqxtyyoeoznmbidd only.
DROP TRIGGER IF EXISTS zz_pdc_arrival_age_563_move ON public.vehicle_movements;
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.capture_move_arrival_age_742();
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
END $function$;
UPDATE pdc_ops.regression_checks
SET check_sql = replace(replace(replace(replace(check_sql,
   $a$OR (basis = 'tune' AND arrived_at = tune_at AND key_at IS NULL)$a$,
   $a$OR (basis = 'tune' AND arrived_at = tune_at AND (key_at IS NULL OR tune_at < key_at))$a$),
   $a$OR (basis = 'key' AND arrived_at = key_at)$a$,
   $a$OR (basis = 'key' AND arrived_at = key_at AND (tune_at IS NULL OR key_at <= tune_at))$a$),
   'AND trg.n = 7', 'AND trg.n = 6'),
   $a$,'zz_pdc_arrival_age_563_move'$a$, ''),
 description = 'PMB arrival age (r563): the earlier of key date and Tune first-seen; six zz_ triggers keep it fresh; the list RPC is for staff only.'
WHERE check_name = 'pmb_arrival_age_563';
ALTER TABLE public.pdc_vehicle_pmb_arrival_age_563 DROP CONSTRAINT pdc_vehicle_pmb_arrival_age_563_basis_ck;
ALTER TABLE public.pdc_vehicle_pmb_arrival_age_563 ADD CONSTRAINT pdc_vehicle_pmb_arrival_age_563_basis_ck CHECK (
  (basis = 'fallback' AND arrived_at IS NULL AND key_at IS NULL AND tune_at IS NULL)
  OR (basis = 'key' AND arrived_at IS NOT NULL AND arrived_at = key_at AND (tune_at IS NULL OR key_at <= tune_at))
  OR (basis = 'tune' AND arrived_at IS NOT NULL AND arrived_at = tune_at AND (key_at IS NULL OR tune_at < key_at))) NOT VALID;
DO $$ DECLARE r record; BEGIN FOR r IN SELECT vehicle_id FROM public.pdc_vehicle_pmb_arrival_age_563 LOOP PERFORM pdc_pmb_ack_private.refresh_arrival_age_563(r.vehicle_id); END LOOP; END $$;
ALTER TABLE public.pdc_vehicle_pmb_arrival_age_563 VALIDATE CONSTRAINT pdc_vehicle_pmb_arrival_age_563_basis_ck;
