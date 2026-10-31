-- r776 (F379) / sort 490 is taken; sort 491. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 31 Oct 2026 10:22: "13073054 - this is showing as leaving? its a Navision linked vehicle?"
-- The r759 leaving rule asked "is the car on Navision" by looking only for Broome Toyota Sales (37047) and Karratha Sales
-- (14450) records. 13073054 (dealer 001234) and 13073092 (dealer 002345) are current, linked Navision records under other
-- dealer codes, so they counted as off Navision and would have been completed. Craig's rule: on Navision = stays, tagged.
-- Fix: "on Navision" = any current Navision record linked to the car or matching its stock, any dealer code.
-- Backup: pdc_backup_r763_20261031.function_sources (archive_569 r774 state as *@r774). Rollback: supabase/rollbacks/20261031102500_r776_on_navision_any_dealer.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)@r774', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r776$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'::regprocedure;
  a1 text := E'  v_on_sales := EXISTS (\n   SELECT 1 FROM public.navision_backend_records n\n   WHERE n.source_system=''microsoft_navision'' AND n.is_current AND n.record_status::text=''current''\n'
          || E'     AND n.dealer_code IN (''37047'',''037047'',''14450'',''014450'')\n'
          || E'     AND public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>''batch'', n.normalized_data->>''stock''))\n         = public.normalize_vehicle_stock_number(v_row.stock_number));\n';
  b1 text := E'  -- r776 (F379): on Navision means any current Navision record linked to the car or matching its stock, whatever the dealer code.\n'
          || E'  v_on_sales := EXISTS (\n   SELECT 1 FROM public.navision_backend_records n\n   WHERE n.source_system=''microsoft_navision'' AND n.is_current AND n.record_status::text=''current''\n'
          || E'     AND (n.canonical_vehicle_id=v_row.vehicle_id\n'
          || E'          OR public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>''batch'', n.normalized_data->>''stock''))\n             = public.normalize_vehicle_stock_number(v_row.stock_number)));\n';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r776: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 491 OR fault_id = 'F379' OR added_in = 'r776') THEN RAISE EXCEPTION 'r776: sort 491 or F379 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r776: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '13eb9a0c31a00ff20dcb34898101ab79' THEN RAISE EXCEPTION 'r776: archive_569 is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r776: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r776: readback differs'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('on_navision_any_dealer_776', 'F379',
    'Upload (r776): a car that left the Revolution list is completed only when no current Navision record (any dealer code) is linked to it or matches its stock; otherwise it stays, tagged.',
    $chk$
SELECT position('r776 (F379)' IN s.src) > 0 AND position('n.canonical_vehicle_id=v_row.vehicle_id' IN s.src) > 0
   AND position($$v_on_sales := EXISTS ($$ || E'\n' || $$   SELECT 1 FROM public.navision_backend_records n$$ || E'\n' || $$   WHERE n.source_system='microsoft_navision' AND n.is_current AND n.record_status::text='current'$$ || E'\n' || $$     AND n.dealer_code IN$$ IN s.src) = 0
 AS ok, 'on Navision = any dealer code, linked or stock match' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)')) s
$chk$, true, 491, 'r776');
END $r776$;
