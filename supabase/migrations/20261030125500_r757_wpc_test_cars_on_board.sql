-- r757 (F363) / sort 469. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 12:52: "just for those vehicles ... the 10 that don't have job cards and never had job cards, just bring
-- them in and put them in WPC if they're linked to Navision, just so we know how long it takes to get from here and
-- make sure they come off the board when they're delivered to dealer". The Vehicle Locations board lists a car only
-- when it has a Revolution job card (import receipt or service lines), a required sublet or a sublet booking, so the
-- ten cars reactivated at WPC this morning (F362) sat in the database and off the page. One anchored line in the
-- board filter: a car tagged source_payload.wpc_test_20261030 = true is listed. Nothing else changes. (Applied as
-- 'authority' first; the Navision detail refresh rewrites authority, so r757b moved the tag to its own key and set it
-- on the ten cars. This file is the combined result.)
-- Rollback: supabase/rollbacks/20261030125500_r757_wpc_test_cars_on_board.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $r757$
DECLARE v_old text; v_new text; v_def text; v_md5 text; v_n integer;
  c_old text := E'      OR EXISTS(SELECT 1 FROM public.pdc_sublet_bookings s WHERE s.vehicle_id=v.id)\n';
  c_new text := E'      OR EXISTS(SELECT 1 FROM public.pdc_sublet_bookings s WHERE s.vehicle_id=v.id)\n      OR coalesce((v.source_payload->>''wpc_test_20261030'')::boolean,false)\n';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r757: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 469 OR fault_id = 'F363' OR added_in = 'r757') THEN RAISE EXCEPTION 'r757: sort 469 or F363 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r757: an import job is running'; END IF;
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure;
  IF v_md5 <> 'd3b6f69bdf3420336403816fc7c60255' THEN RAISE EXCEPTION 'r757: pre168 is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r757: anchor not found once'; END IF;
  v_new := replace(v_old, c_old, c_new);
  v_def := regexp_replace(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure) <> v_new THEN RAISE EXCEPTION 'r757: readback differs'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = v_md5;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, md5(v_new)) WHERE strpos(check_sql, v_md5) > 0;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r757: md5 literal not moved (%)', v_n; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('wpc_test_cars_on_board_757', 'F363',
    'Board (r757): the WPC test cars (source_payload.wpc_test_20261030 = true) are listed by the Vehicle Locations board while active and visible, and the filter line is present.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.get_pdc_email_vehicle_location_snapshot_pre168()')),
  'OR coalesce((v.source_payload->>''wpc_test_20261030'')::boolean,false)') > 0 AS ok,
  'wpc test cars listed by the board filter' AS detail
$chk$, true, 469, 'r757');
  UPDATE public.vehicles SET source_payload = coalesce(source_payload,'{}'::jsonb) || jsonb_build_object('wpc_test_20261030', true)
   WHERE deleted_at IS NULL AND stock_number IN ('13021111','12704245','13021146','13021147','12662987','12661298','12663035','12661300','12662989','12662943');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 10 THEN RAISE EXCEPTION 'r757: tagged % cars, expected 10', v_n; END IF;
  -- The shared board snapshots rebuild on the next read.
  UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = now() WHERE singleton;
END $r757$;
