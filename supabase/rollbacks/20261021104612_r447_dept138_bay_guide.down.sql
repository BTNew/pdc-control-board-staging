-- r447 undo (F60): restores pdc_work_categories_private.preferred_bay (baseline, md5 9a785c3f4301213c4dae78e3717611ee) and
-- allowed_bay (#386, md5 a9e529f8e2153924fd8a5d323084f1c1) byte for byte, puts their pins back, re-enables the r399 grid checks
-- and drops bus_bay_guide_447. The 'r447_grandfathered' override rows are removed (the old rule accepts those bookings again).
-- Bookings placed after r447 that the old rule would warn about (e.g. Mechanical in Bay 5, Accessories in Bay 1) are kept where
-- they are with an 'applied' override row tagged 'r447_undo_kept', so the validator and the clock tick keep accepting them.
-- Overrides that planners confirmed while r447 was live stay (history). Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r447 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r447 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r447 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r447 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'5e0484d7690c91912b80fcef099d268a' OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'bb83ffbf0580d6a384dc28b04d9361ea' THEN RAISE EXCEPTION 'r447 undo: functions are not the r447 versions; nothing restored'; END IF;
END $g$;

DROP TABLE IF EXISTS pg_temp.r447_new_ok;
CREATE TEMP TABLE r447_new_ok ON COMMIT DROP AS
SELECT b.id booking_id,b.vehicle_id,b.bay_id,bay.bay_number,b.work_category
FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id JOIN public.workshop_stages s ON s.id=b.stage_id AND s.code='BUS_4X4'
WHERE b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
 AND pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number);

CREATE OR REPLACE FUNCTION pdc_work_categories_private.preferred_bay(category text, bay integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT CASE category WHEN 'BUS_MECHANICAL' THEN bay IN(1,2,3,4)
 WHEN 'BUS_ELECTRICAL' THEN bay IN(8,9) WHEN 'BUS_ACCESSORIES' THEN bay=10 WHEN 'BUS_QA' THEN bay=7 ELSE false END
$function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.allowed_bay(category text, bay integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT pdc_work_categories_private.preferred_bay(category,bay)
  OR (bay IN (9,10) AND category IN ('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES'))
$function$;

DELETE FROM pdc_bay_rules_private.overrides WHERE source='r447_grandfathered';

INSERT INTO pdc_bay_rules_private.overrides(actor_id,actor_email,vehicle_id,booking_id,bay_id,bay_number,stage_code,work_category,rule,message,action,source,outcome,finished_at)
SELECT '00000000-0000-0000-0000-000000000000'::uuid,'r447 undo (no person)',o.vehicle_id,o.booking_id,o.bay_id,o.bay_number,'BUS_4X4',o.work_category,'category_bay_mismatch',
 format('Booked in Bay %s while the r447 bay guide was live (%s work went there without a warning). Kept where it was placed when r447 was undone.',o.bay_number,pdc_bay_rules_private.category_label(o.work_category)),
 'move','r447_undo_kept','applied',clock_timestamp()
FROM r447_new_ok o
WHERE NOT pdc_work_categories_private.allowed_bay(o.work_category,o.bay_number)
 AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides x WHERE x.booking_id=o.booking_id AND x.bay_id=o.bay_id
  AND x.rule='category_bay_mismatch' AND x.outcome='applied' AND x.revoked_at IS NULL);

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='9a785c3f4301213c4dae78e3717611ee',release='baseline',note='preferred bays',updated_at='2026-10-20T10:55:01.195622+00:00'
 WHERE signature='pdc_work_categories_private.preferred_bay(text,integer)' AND prosrc_md5='5e0484d7690c91912b80fcef099d268a' AND release='r447';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='a9e529f8e2153924fd8a5d323084f1c1',release='#386',note='Bays 9/10 accept MECH/ELEC/ACC',updated_at='2026-10-20T10:55:01.195622+00:00'
 WHERE signature='pdc_work_categories_private.allowed_bay(text,integer)' AND prosrc_md5='bb83ffbf0580d6a384dc28b04d9361ea' AND release='r447';
UPDATE pdc_ops.regression_checks SET enabled=true WHERE check_name IN ('bays_9_10_accept_mech_elec_acc','bus_bay_category_grid') AND added_in='r399' AND NOT enabled;
DELETE FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447' AND added_in='r447';

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'9a785c3f4301213c4dae78e3717611ee' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447 undo: preferred_bay not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'a9e529f8e2153924fd8a5d323084f1c1' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447 undo: allowed_bay not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r447') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r447')
    OR EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides WHERE source='r447_grandfathered')
    OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('bays_9_10_accept_mech_elec_acc','bus_bay_category_grid') AND enabled)<>2
 THEN RAISE EXCEPTION 'r447 undo: r447 rows remain'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
   WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
    AND NOT pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number)
    AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o WHERE o.booking_id=b.id AND o.bay_id=b.bay_id AND o.rule='category_bay_mismatch' AND o.outcome='applied' AND o.revoked_at IS NULL))
 THEN RAISE EXCEPTION 'r447 undo: an active booking would break the restored rule without an override'; END IF;
END $g$;
