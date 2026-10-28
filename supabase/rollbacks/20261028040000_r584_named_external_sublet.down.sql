-- r584 (F198) rollback. Restores the note/fee hook and the two checks.
-- Does not rewrite the six r523 category bodies.
-- Restores every vehicle_work_items row this release inserted or updated.
-- Does not change revolution_service_rows_20261006 or pdc_pilbara_service_apply_v1.
-- Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r584 down: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r584 down: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.note_fee_sublet_521(jsonb)'::regprocedure)<>'ca08696ffbe6a1834e63f8b8faf246e1'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'5adf2ee5c2dc8c11199d314be477a6c1'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure)<>'82c809d15c382e73c0ae5bf135293ebe'
 THEN RAISE EXCEPTION 'r584 down: not the r584 hook'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.note_fee_sublet_521(line jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 -- r521 (F135): whole operation line. description plus operation_code. Not a GP PO item on another line.
 -- Pit fee, a weigh / weighbridge line, a full tank of fuel, or fuel tank certification.
 -- Long-range fuel tank installs, PITS - REFER BRYCE, and certified mesh do not match.
 SELECT regexp_replace(upper(coalesce(line->>'description','')||' '||coalesce(line->>'operation_code','')),'[[:space:]]+',' ','g')
  ~ '(^|[^A-Z0-9])PIT FEES?([^A-Z0-9]|$)|(^|[^A-Z0-9])WEIGH([^A-Z0-9]|$)|(WEIGH|WAY)BRIDGE|FULL TANK OF FUEL|FUEL TANK CERTIF'
$function$;

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5='2813508255aa6f65c7490e54c76cd564', release='r521', note='Pit fee, weigh, full tank of fuel, fuel tank certification (F135)', updated_at=now()
WHERE signature='pdc_work_categories_private.note_fee_sublet_521(jsonb)' AND release='r521' AND prosrc_md5='ca08696ffbe6a1834e63f8b8faf246e1';
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, 'ca08696ffbe6a1834e63f8b8faf246e1', '2813508255aa6f65c7490e54c76cd564')
WHERE check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523');
DELETE FROM pdc_ops.regression_checks WHERE check_name='named_external_sublet_584' AND fault_id='F198' AND sort_order=356;

DO $touch$ BEGIN
 IF to_regclass('pdc_ops.named_external_work_touch_584') IS NULL THEN RAISE EXCEPTION 'r584 down: touch table missing'; END IF;
 UPDATE public.vehicle_work_items w
    SET required=t.prior_required, completed=t.prior_completed, completed_by=t.prior_completed_by,
        completed_at=t.prior_completed_at, notes=t.prior_notes, updated_at=t.prior_updated_at
   FROM pdc_ops.named_external_work_touch_584 t
  WHERE t.existed AND w.id=t.work_item_id;
 ALTER TABLE public.vehicle_work_items DISABLE TRIGGER pdc_772_work_item_no_delete;
 DELETE FROM public.vehicle_work_items w
  USING pdc_ops.named_external_work_touch_584 t
  WHERE NOT t.existed AND w.vehicle_id=t.vehicle_id AND w.work_key='sublet'
    AND w.notes='Required by canonical imported jobcard work'
    AND w.required IS TRUE AND w.completed IS FALSE
    AND w.completed_by IS NULL AND w.completed_at IS NULL;
 ALTER TABLE public.vehicle_work_items ENABLE TRIGGER pdc_772_work_item_no_delete;
 IF (SELECT tgenabled FROM pg_trigger WHERE tgname='pdc_772_work_item_no_delete' AND tgrelid='public.vehicle_work_items'::regclass)<>'O'
 THEN RAISE EXCEPTION 'r584 down: delete trigger not enabled'; END IF;
END $touch$;
DROP TABLE pdc_ops.named_external_work_touch_584;

DO $bf$
DECLARE ids uuid[];
BEGIN
 SELECT coalesce(array_agg(DISTINCT o.vehicle_id), ARRAY[]::uuid[]) INTO ids
 FROM public.pdc_pilbara_service_operations o
 WHERE regexp_replace(upper(coalesce(o.operation_description,'')||' '||coalesce(o.operation_code,'')),'[[:space:]]+',' ','g')
  ~ 'MMT.*SEAT[ -]?COVERS?|(^|[^A-Z0-9])IVMS([^A-Z0-9]|$)|(^|[^A-Z0-9])RADLINK([^A-Z0-9]|$)|REFLECTIVE STRIPES';
 PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ids, false);
 DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = ANY(ids);
 INSERT INTO pdc_work_categories_private.qc_operation_lines_cache(vehicle_id, lines, computed_at)
 SELECT x.vehicle_id, public.pdc_qc_operation_lines_379_uncached(x.vehicle_id), clock_timestamp()
 FROM unnest(ids) AS x(vehicle_id)
 ON CONFLICT (vehicle_id) DO UPDATE
    SET lines = EXCLUDED.lines, computed_at = EXCLUDED.computed_at
    WHERE true;
END
$bf$;

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r584 down: pin count'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.note_fee_sublet_521(jsonb)'::regprocedure)<>'2813508255aa6f65c7490e54c76cd564'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.perth_delivery_sublet_523(jsonb)'::regprocedure)<>'2944c99ffc3c4ce09704b00d66f9fdc4'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'5adf2ee5c2dc8c11199d314be477a6c1'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'c8d16e91e728540542c843751c311a97'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure)<>'82c809d15c382e73c0ae5bf135293ebe'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure)<>'f60ac3617342e6317107e84e014c4c36'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure)<>'bae621855931cc4bca6e326037559da2'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure)<>'0d71cc4ee105b90fa970622a3f4deb5d'
  OR pg_catalog.to_regprocedure('pdc_work_categories_private.named_external_sublet_584(jsonb)') IS NOT NULL
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'9be0883b1a555f48f3c1ba9fa111c891'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'b62fb7c29ffd2a1629f214f696e5cb14'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure)<>'fd05b9eef69498002ac06dd68e01cdff'
  OR (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')<>'r523'
  OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')<>'82c809d15c382e73c0ae5bf135293ebe'
  OR (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.note_fee_sublet_521(jsonb)')<>'r521'
  OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.note_fee_sublet_521(jsonb)')<>'2813508255aa6f65c7490e54c76cd564'
  OR to_regclass('pdc_ops.named_external_work_touch_584') IS NOT NULL
  OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523') AND check_sql LIKE '%2813508255aa6f65c7490e54c76cd564%' AND check_sql LIKE '%5adf2ee5c2dc8c11199d314be477a6c1%' AND check_sql NOT LIKE '%ca08696ffbe6a1834e63f8b8faf246e1%')<>2
  OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='named_external_sublet_584')<>0
  OR (SELECT tgenabled FROM pg_trigger WHERE tgname='pdc_772_work_item_no_delete' AND tgrelid='public.vehicle_work_items'::regclass)<>'O'
 THEN RAISE EXCEPTION 'r584 down: restore md5 mismatch'; END IF;
END $p$;
