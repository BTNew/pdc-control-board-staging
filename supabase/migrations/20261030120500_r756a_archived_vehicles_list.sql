-- r756a (F361) / sort 468. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 11:52: "why can't I see archived vehicles? Should they be accessible to the administrator to see?" 11:55:
-- "Yeah, the archive filter ... so I can see them." An archived car (board_purged_at set, not deleted, lifecycle still
-- active) was on no page: not on the board, not Deleted, not Completed. This reader lists them for staff; the Completed
-- Vehicles page gets an Archived filter and an All view. Read only; nothing moves.
-- Rollback: supabase/rollbacks/20261030120500_r756a_archived_vehicles_list.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $pre756a$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r756a: staging only'; END IF;
  IF to_regprocedure('public.list_archived_vehicles_756()') IS NOT NULL THEN RAISE EXCEPTION 'r756a: already applied'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 468 OR fault_id = 'F361' OR added_in = 'r756a') THEN RAISE EXCEPTION 'r756a: sort 468 or F361 is taken'; END IF;
END $pre756a$;

CREATE FUNCTION public.list_archived_vehicles_756()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
  SELECT CASE WHEN coalesce(public.current_pdc_user_role()::text, '') NOT IN ('viewer', 'operator', 'importer', 'administrator')
    THEN jsonb_build_object('ok', false, 'code', 'unauthorized')
    ELSE jsonb_build_object('ok', true, 'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'vehicle_id', v.id, 'stock_number', v.stock_number, 'key_number', v.key_number, 'job_card_number', v.job_card_number,
        'customer_name', v.customer_name, 'vehicle_description', v.vehicle_description,
        'archived_at', v.board_purged_at, 'reason', v.board_purge_reason,
        'prior_location', coalesce(r.prior->>'current_location', v.current_location),
        'navision_current', EXISTS (SELECT 1 FROM public.navision_backend_records b WHERE b.canonical_vehicle_id = v.id AND b.is_current AND b.record_status = 'current'),
        'navision_status', (SELECT b.normalized_data->>'toyotaStatus' FROM public.navision_backend_records b WHERE b.canonical_vehicle_id = v.id AND b.is_current ORDER BY b.updated_at DESC LIMIT 1))
        ORDER BY v.board_purged_at DESC)
      FROM public.vehicles v
      LEFT JOIN LATERAL (SELECT x.prior FROM pdc_codex_intake_private.service_whole_archive_receipt_569 x WHERE x.vehicle_id = v.id ORDER BY x.archived_at DESC LIMIT 1) r ON true
      WHERE v.deleted_at IS NULL AND v.board_purged_at IS NOT NULL AND v.lifecycle_state = 'active'), '[]'::jsonb)) END;
$fn$;
REVOKE ALL ON FUNCTION public.list_archived_vehicles_756() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_archived_vehicles_756() TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, added_in, enabled, sort_order, description, check_sql) VALUES ('archived_vehicles_visible_756', 'F361', 'r756a', true, 468,
 'Archived vehicles (r756a): staff can list every archived car (board_purged_at set, not deleted, still active); anon cannot.',
$chk$
SELECT has_function_privilege('authenticated', 'public.list_archived_vehicles_756()', 'EXECUTE')
   AND NOT has_function_privilege('anon', 'public.list_archived_vehicles_756()', 'EXECUTE')
   AND (SELECT p.prosecdef AND p.provolatile = 's' FROM pg_proc p WHERE p.oid = 'public.list_archived_vehicles_756()'::regprocedure)
 AS ok, 'archived vehicles reader in place' AS detail
$chk$);
