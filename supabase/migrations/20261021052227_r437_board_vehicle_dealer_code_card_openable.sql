-- r437 (F48, 21 Oct, Craig via PMB Email 13:14 AWST): "The exact vehicle identity is unavailable. Refresh the list and try again.
-- No vehicle was changed." on clicking a vehicle on the board. Staging cdsmnqxtyyoeoznmbidd only.
-- Fault (frontend, app.js openVehicleModal): the vehicle card only opened for Navision Dealer codes 14450 / 37047. Vehicles whose Dealer
-- column is a Toyota head office account (001234 / 002345, imported with the Pilbara and Broome uploads since Sept) were refused on every
-- click, although Workshop detail has served them under the board's dealer scope since #351. Fix is in app.js (PR r437).
-- This migration adds only the regression check board_vehicle_dealer_code_card_openable (F48, sort 237): every board Navision vehicle has a Dealer code the card can
-- open (14450, 37047, 001234, 002345); it goes red if a new code appears. No function, table, vehicle or import row is changed.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r437: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r437: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r437: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r437: fault_regression_check changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='board_vehicle_dealer_code_card_openable' OR added_in='r437') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r437') THEN RAISE EXCEPTION 'r437: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=237) THEN RAISE EXCEPTION 'r437: sort_order 237 taken'; END IF;
END $g$;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('board_vehicle_dealer_code_card_openable','F48','Every board Navision vehicle has a Dealer code the vehicle card can open: dealer 14450 / 37047, or Toyota head office account 001234 / 002345 (opens under the board dealer scope since r437). Red on any other or blank code, which would bring back the "exact vehicle identity is unavailable" toast',
  $chk$WITH board AS (
  SELECT btrim(coalesce(n.dealer_code,'')) code
  FROM public.navision_backend_records n
  JOIN public.vehicles v ON v.id=n.canonical_vehicle_id
  WHERE n.source_system='microsoft_navision' AND n.is_current AND n.record_status='current'
    AND v.deleted_at IS NULL AND v.visible_on_board AND v.lifecycle_state='active'
), agg AS (
  SELECT count(*) total,
   count(*) FILTER (WHERE code IN ('14450','37047')) dealer_rows,
   count(*) FILTER (WHERE code IN ('001234','002345')) head_office_rows,
   string_agg(DISTINCT CASE WHEN code NOT IN ('14450','37047','001234','002345') THEN coalesce(nullif(code,''),'(blank)') END, ', ') unknown_codes,
   count(*) FILTER (WHERE code NOT IN ('14450','37047','001234','002345')) unknown_rows
  FROM board
)
SELECT (SELECT unknown_rows=0 FROM agg) AS ok,
 'board Navision vehicles: '||total||'; dealer 14450/37047: '||dealer_rows||'; Toyota head office 001234/002345 (card opens under the board dealer scope since r437): '||head_office_rows
 ||'; dealer codes the vehicle card cannot open: '||CASE WHEN unknown_rows=0 THEN 'none' ELSE unknown_rows||' vehicles ('||unknown_codes||')' END AS detail
FROM agg
$chk$,true,237,'r437');

DO $g$ BEGIN
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='board_vehicle_dealer_code_card_openable' AND added_in='r437')<>'10e06e3bf42cbc0a4e4b390fb1b2245d' THEN RAISE EXCEPTION 'r437: check did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r437: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r437: fault_regression_check changed'; END IF;
END $g$;
