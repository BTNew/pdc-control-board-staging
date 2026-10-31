-- r791 (F399) / sort 575. Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 06:56 AWST: "rule one please"
-- (a car Navision shows as Delivered to Dealer stays completed, even while its Revolution job card is still open).
-- 12710966 was completed on 31 Oct from Navision "Delivered - At Dealer" (dealer 14450); the service import then put it back into
-- New Vehicles because board_every_stock_674 re-activates every hidden car on the file. Same for 12710970, 13003383, 13025962,
-- 13092060, 13092165, 13019220.
--   1. board_every_stock_674 skips a car with a current Navision record (linked or same stock) showing toyotaStatus
--      'Delivered - At Dealer' or location status OD.
--   2. The 7 delivered cars now waiting in New Vehicles go back to completed (review closed with the reason). Their bookings are all
--      already completed; nothing else changes.
-- Rollback: supabase/rollbacks/20261101070000_r791_delivered_stays_completed.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.board_every_stock_674(uuid,boolean)@r791pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r791$
DECLARE v_old text; v_new text; v_def text; r record; n integer := 0; out text := '';
  sig regprocedure := 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure;
  a1 text := $a$      AND NOT (v.lifecycle_state::text = 'active' AND EXISTS (SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id = v.id AND r.status = 'pending'))$a$;
  b1 text := $a$      AND NOT (v.lifecycle_state::text = 'active' AND EXISTS (SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id = v.id AND r.status = 'pending'))
      -- r791 (F399): a car Navision shows as Delivered to Dealer stays completed while its job card is still open.
      AND NOT EXISTS (SELECT 1 FROM public.navision_backend_records n
                      WHERE n.source_system = 'microsoft_navision' AND n.is_current AND n.record_status::text = 'current'
                        AND (n.canonical_vehicle_id = v.id
                             OR public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock')) = v.stock_number_normalized)
                        AND (n.normalized_data->>'toyotaStatus' = 'Delivered - At Dealer' OR n.normalized_data->>'navisionLocationStatus' = 'OD'))$a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r791: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 575 OR fault_id = 'F399' OR added_in = 'r791') THEN RAISE EXCEPTION 'r791: sort 575 or F399 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r791: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '075419db9a4fb1a5777dff2b4225a031' THEN RAISE EXCEPTION 'r791: board_every_stock_674 is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r791: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r791: readback differs'; END IF;

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub','8a83b715-8d79-4b0e-95b2-02b55da6e8d7','email','craig.watson@broometoyota.com.au','role','authenticated')::text, true);
  FOR r IN SELECT v.id, v.stock_number, v.current_location FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews rv ON rv.vehicle_id = v.id AND rv.status = 'pending'
           WHERE v.deleted_at IS NULL AND v.lifecycle_state::text = 'active' AND v.visible_on_board IS NOT TRUE
             AND NOT EXISTS (SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id = v.id AND b.deleted_at IS NULL AND b.status::text <> 'completed')
             AND EXISTS (SELECT 1 FROM public.navision_backend_records n
                         WHERE n.source_system = 'microsoft_navision' AND n.is_current AND n.record_status::text = 'current'
                           AND (n.canonical_vehicle_id = v.id
                                OR public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock')) = v.stock_number_normalized)
                           AND (n.normalized_data->>'toyotaStatus' = 'Delivered - At Dealer' OR n.normalized_data->>'navisionLocationStatus' = 'OD'))
           ORDER BY v.stock_number LOOP
    UPDATE public.pdc_new_vehicle_reviews SET status = 'closed', closed_at = clock_timestamp(),
      closure_reason = 'Craig 1 Nov 2026 (r791): Navision shows Delivered - At Dealer; stays completed while the job card is still open'
    WHERE vehicle_id = r.id AND status = 'pending';
    UPDATE public.vehicles SET lifecycle_state = 'completed', current_location = 'Completed', visible_on_board = false, version = version + 1,
      updated_by = '8a83b715-8d79-4b0e-95b2-02b55da6e8d7', updated_at = clock_timestamp()
    WHERE id = r.id;
    IF r.current_location IS DISTINCT FROM 'Completed' THEN
      INSERT INTO public.vehicle_movements(vehicle_id, from_location, to_location, reason, moved_by, moved_at)
      VALUES (r.id, r.current_location, 'Completed', 'Craig 1 Nov 2026 (r791): Navision shows Delivered - At Dealer', '8a83b715-8d79-4b0e-95b2-02b55da6e8d7', clock_timestamp());
    END IF;
    n := n + 1; out := out || r.stock_number || ' ';
  END LOOP;
  IF n <> 7 THEN RAISE EXCEPTION 'r791: expected 7 delivered cars in New Vehicles, found %: %', n, out; END IF;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('delivered_stays_completed_791', 'F399',
    'Upload (r791): the service import never re-opens a car Navision shows as Delivered - At Dealer (location OD), and none waits in New Vehicles.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.board_every_stock_674(uuid,boolean)')), 'r791 (F399)') > 0
   AND NOT EXISTS (SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews rv ON rv.vehicle_id = v.id AND rv.status = 'pending'
                   WHERE v.deleted_at IS NULL AND EXISTS (SELECT 1 FROM public.navision_backend_records n
                     WHERE n.source_system = 'microsoft_navision' AND n.is_current AND n.record_status::text = 'current' AND n.canonical_vehicle_id = v.id
                       AND (n.normalized_data->>'toyotaStatus' = 'Delivered - At Dealer' OR n.normalized_data->>'navisionLocationStatus' = 'OD')))
 AS ok, 'delivered cars stay completed' AS detail
$chk$, true, 575, 'r791');
  RAISE NOTICE 'r791 completed: %', out;
END $r791$;
