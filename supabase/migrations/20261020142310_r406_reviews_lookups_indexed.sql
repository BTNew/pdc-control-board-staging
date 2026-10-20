-- r406 (F16): snapshot slowness, audit #7. Staging cdsmnqxtyyoeoznmbidd only.
-- The 91.9M sequential scans on public.pdc_tune_operation_change_reviews (254 rows) came from the
-- per-line (vehicle_id, status, change_kind) lookup in the QC operation helper. That lookup has had
-- an index since 20261019230000_helper_lookup_indexes (applied 20 Oct 2026 07:25 AWST): the counter
-- moved 91,878,161 -> 91,878,195 in the 15 h since, while index scans grew by ~0.4M. Measured on
-- 20 Oct 22:10 AWST: no further index in the location or board snapshot gives a clear win (every
-- remaining sequential scan is on a 1-5 page table). This release adds the regression check only.
-- No function, index, data row, pin or schedule changes.
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r406: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r406: fault_regression_check changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='reviews_lookups_indexed') THEN RAISE EXCEPTION 'r406: already applied'; END IF;
END $g$;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
('reviews_lookups_indexed','F16','The review-table lookups used per line by the QC and snapshot helpers have valid indexes, and pdc_tune_operation_change_reviews is not being sequentially scanned again (fewer than 100000 sequential scans since the r406 baseline of 91878195).','WITH idx AS (
  SELECT count(*) FILTER (WHERE i.indisvalid AND i.indisready) AS ok_n
  FROM pg_catalog.pg_index i
  WHERE i.indexrelid IN (
    SELECT x FROM unnest(ARRAY[
      to_regclass(''public.pdc_tune_op_change_reviews_vehicle_idx''),
      to_regclass(''public.pdc_tune_approved_operation_source_idx''),
      to_regclass(''public.pdc_authenticated_email_operation_lines_vehicle_idx'')]) x WHERE x IS NOT NULL)
), d AS (
  SELECT CASE WHEN s.seq_scan >= 91878195 THEN s.seq_scan - 91878195 ELSE s.seq_scan END AS since
  FROM pg_catalog.pg_stat_user_tables s WHERE s.relid = ''public.pdc_tune_operation_change_reviews''::regclass
)
SELECT idx.ok_n = 3 AND coalesce(d.since, 0) < 100000 AS ok,
  idx.ok_n || ''/3 review lookup indexes valid; '' || coalesce(d.since, 0)
  || '' sequential scans of pdc_tune_operation_change_reviews since r406 (limit 100000; 91.9M before the 20 Oct 07:25 index)'' AS detail
FROM idx LEFT JOIN d ON true',true,195,'r406');

DO $p$ DECLARE r record; BEGIN
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='reviews_lookups_indexed')<>'725010dda682fc1ed9faa1b377fb1491' THEN RAISE EXCEPTION 'r406: check md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r406: frc md5'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='reviews_lookups_indexed') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r406: check not ok: %', r.detail; END IF;
END $p$;
