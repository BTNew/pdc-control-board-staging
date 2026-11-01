-- r814 (F452): night review 1 Nov 2026. Lasting guards for the two most repeated fault patterns in docs/FAULT_LOG.md:
--  1. A rule changed in some functions but not all (F05, F14, F25, F39, F282, F298, F345, F352, F384, F383, F404, F423b).
--     pdc_ops.retired_literals_814 lists codes / rule text that must not exist any more; the check fails if any live function
--     in public or pdc_* (frozen Karratha copies and backups excluded) still contains one. Add a row whenever a rule is retired.
--  2. The import re-opening finished cars (F283, F399, F405, F406, F415, F422): no active car may be admin-completed or show
--     "Delivered - At Dealer" on its most recent Navision record. (Collected cars: check 585.)
CREATE TABLE IF NOT EXISTS pdc_ops.retired_literals_814 (
  literal text PRIMARY KEY,
  reason text NOT NULL,
  retired_in text NOT NULL,
  retired_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON pdc_ops.retired_literals_814 FROM PUBLIC, anon, authenticated;
INSERT INTO pdc_ops.retired_literals_814 (literal, reason, retired_in) VALUES
  ('rft_confirmation_required', 'Email salesperson comes before RFT''d (Craig 1 Nov 19:47)', 'r807'),
  ($l$navisionLocationStatus' = 'OD'$l$, 'OD is on almost every PMB car; only "Delivered - At Dealer" means delivered', 'r812')
ON CONFLICT (literal) DO NOTHING;

DO $r814$
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order IN (601, 602) OR added_in = 'r814') THEN RAISE EXCEPTION 'r814: sort 601/602 taken'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
  ('retired_rules_gone_814', 'F452',
   'Rule changes (r814): no live function in public or pdc_* still contains a retired code or rule text (pdc_ops.retired_literals_814).',
   $chk$
SELECT NOT EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pdc_ops.retired_literals_814 r ON strpos(p.prosrc, r.literal) > 0
  WHERE (n.nspname = 'public' OR (n.nspname LIKE 'pdc\_%' AND n.nspname NOT LIKE 'pdc\_backup%')) AND p.prokind = 'f')
 AS ok,
 coalesce((SELECT string_agg(DISTINCT n.nspname || '.' || p.proname || ' has ' || r.literal, '; ')
   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pdc_ops.retired_literals_814 r ON strpos(p.prosrc, r.literal) > 0
   WHERE (n.nspname = 'public' OR (n.nspname LIKE 'pdc\_%' AND n.nspname NOT LIKE 'pdc\_backup%')) AND p.prokind = 'f'), 'no retired rules left') AS detail
$chk$, true, 601, 'r814'),
  ('finished_cars_stay_finished_814', 'F452',
   'Import (r814): no active car is admin-completed or shows "Delivered - At Dealer" on its most recent Navision record.',
   $chk$
SELECT NOT EXISTS (
  SELECT 1 FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND v.lifecycle_state::text = 'active'
    AND (v.source_payload ? 'admin_completed_800'
      OR EXISTS (SELECT 1 FROM (SELECT n.normalized_data FROM public.navision_backend_records n
                                WHERE n.source_system = 'microsoft_navision'
                                  AND (n.canonical_vehicle_id = v.id OR public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock')) = v.stock_number_normalized)
                                ORDER BY (n.is_current AND n.record_status::text = 'current') DESC, n.updated_at DESC LIMIT 1) x
                 WHERE x.normalized_data->>'toyotaStatus' = 'Delivered - At Dealer')))
 AS ok, 'finished cars stay finished' AS detail
$chk$, true, 602, 'r814');
END $r814$;
