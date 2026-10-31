-- r796 (F406) / sort 578. Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 07:49 AWST: "put them on there correct location".
-- 13047346, 13048522 and 13048526 showed Navision "Delivered - At Dealer" (OD) and then dropped off Navision (record no longer
-- current). r791 only looked at CURRENT Navision records, so the service import kept re-opening them into New Vehicles.
-- board_every_stock_674 now reads the car's best Navision record: the current one if there is one, otherwise the most recent.
-- If that shows Delivered - At Dealer or OD, the car stays completed. 13000779 (last record Ready For Transport) is unaffected.
-- Rollback: supabase/rollbacks/20261101075500_r796_delivered_then_dropped.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.board_every_stock_674(uuid,boolean)@r796pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r796$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure;
  a1 text := $a$      AND NOT EXISTS (SELECT 1 FROM public.navision_backend_records n
                      WHERE n.source_system = 'microsoft_navision' AND n.is_current AND n.record_status::text = 'current'
                        AND (n.canonical_vehicle_id = v.id
                             OR public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock')) = v.stock_number_normalized)
                        AND (n.normalized_data->>'toyotaStatus' = 'Delivered - At Dealer' OR n.normalized_data->>'navisionLocationStatus' = 'OD'))$a$;
  b1 text := $a$      -- r796 (F406): the current Navision record if any, else the most recent one (car delivered, then dropped off Navision).
      AND NOT EXISTS (SELECT 1 FROM (SELECT n.normalized_data FROM public.navision_backend_records n
                      WHERE n.source_system = 'microsoft_navision'
                        AND (n.canonical_vehicle_id = v.id
                             OR public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock')) = v.stock_number_normalized)
                      ORDER BY (n.is_current AND n.record_status::text = 'current') DESC, n.updated_at DESC LIMIT 1) n
                      WHERE n.normalized_data->>'toyotaStatus' = 'Delivered - At Dealer' OR n.normalized_data->>'navisionLocationStatus' = 'OD')$a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r796: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 578 OR fault_id = 'F406' OR added_in = 'r796') THEN RAISE EXCEPTION 'r796: sort 578 or F406 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r796: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '9c0dd65faf1aa7d5ab659c296e80e3ec' THEN RAISE EXCEPTION 'r796: board_every_stock_674 is not the r791 body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r796: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r796: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE position(md5(v_old) IN check_sql) > 0;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('delivered_then_dropped_796', 'F406',
    'Upload (r796): a car whose last Navision record showed Delivered - At Dealer (OD) stays completed after it drops off Navision.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.board_every_stock_674(uuid,boolean)')), 'r796 (F406)') > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.board_every_stock_674(uuid,boolean)')), 'r791 (F399)') > 0
 AS ok, 'delivered then dropped stays completed' AS detail
$chk$, true, 578, 'r796');
END $r796$;
