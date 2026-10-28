-- r584 (F198) / sort 356. PREVIEW. Do not merge. Do not apply.
-- Staging cdsmnqxtyyoeoznmbidd only. r583 / F197 / sort 355 is the live line hand-off.
-- The first preview claimed r516 / F130 / sort 302. That triple is taken:
-- sort 302 is outlook_internal_parts_auth_515, F130 / r516 is jita_eta_upload_516.
-- The six category bodies stay at the r523 checksums. This release does not
-- replace suggest, ensure_required_work_20261019, before_import_rules_20261017,
-- route_import_line_20261017, pdc_pending_work_category_20260912 or
-- reviewed_import_choice_139_20261018. Those bodies already return SUBLET when
-- note_fee_sublet_521 matches, before the department gate and before seat-cover
-- keywords. The named phrases are added to that hook.
-- The before_import_rules_20261017 pin stays release r523 and md5 82c809d15c382e73c0ae5bf135293ebe.
-- The note_fee pin stays release r521. Its prosrc md5 moves to ca08696ffbe6a1834e63f8b8faf246e1.
-- note_fee_sublet_521 and perth_delivery_sublet_523 keep the six r523 md5s
-- and take the new hook md5. Perth delivery's body stays 2944c99ffc3c4ce09704b00d66f9fdc4.
-- This release does not replace
-- pdc_codex_intake_private.revolution_service_rows_20261006 (9be0883b1a555f48f3c1ba9fa111c891)
-- or public.pdc_pilbara_service_apply_v1 (b62fb7c29ffd2a1629f214f696e5cb14).
-- Department 135 is not edited. Pin count stays 241. No new pin is inserted.
-- Work-item writes are sublet rows only. The down file reverses those rows
-- from pdc_ops.named_external_work_touch_584. It does not call ensure_required_work.
-- A matching line is labelled with routing_rule note_fee_sublet_521, because the
-- pending body is not edited.
-- Production vjdtsswhroyguxyfjdkt is not a target.
--
-- Craig Watson (23 Oct, about 3:15 pm AWST): a Navision / import line whose
-- description or operation code contains MMT seat covers, IVMS, RADLINK or
-- reflective stripes is an external Sublet. It is never Fitting or another
-- workshop station. Whole operation line only. A GP PO item on another line
-- is not read. A line override, a booking, an owner review or a manual lock
-- still wins. Manage sublets is unchanged.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r584: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r584: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r584: pin count is not 241'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=356 OR fault_id='F198' OR check_name='named_external_sublet_584' OR added_in='r584') THEN RAISE EXCEPTION 'r584: sort 356 or F198 is taken'; END IF;
 IF pg_catalog.to_regprocedure('pdc_work_categories_private.named_external_sublet_584(jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r584: dropped helper must stay absent'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'9be0883b1a555f48f3c1ba9fa111c891'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'b62fb7c29ffd2a1629f214f696e5cb14'
 THEN RAISE EXCEPTION 'r584: service whole import functions changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure)<>'fd05b9eef69498002ac06dd68e01cdff'
 THEN RAISE EXCEPTION 'r584: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'5adf2ee5c2dc8c11199d314be477a6c1'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'c8d16e91e728540542c843751c311a97'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure)<>'82c809d15c382e73c0ae5bf135293ebe'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure)<>'f60ac3617342e6317107e84e014c4c36'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure)<>'bae621855931cc4bca6e326037559da2'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure)<>'0d71cc4ee105b90fa970622a3f4deb5d'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'7e10e4f66633cf5129c5b2c21aa905e0'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_department138_station_20260917(text)'::regprocedure)<>'9f1cf3370971e3a77f5335632d4f3f8c'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'e9ee86ee7214bcfeb920343eb01bca83'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.note_fee_sublet_521(jsonb)'::regprocedure)<>'2813508255aa6f65c7490e54c76cd564'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.perth_delivery_sublet_523(jsonb)'::regprocedure)<>'2944c99ffc3c4ce09704b00d66f9fdc4'
 THEN RAISE EXCEPTION 'r584: base md5 mismatch'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')<>'r523'
  OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')<>'82c809d15c382e73c0ae5bf135293ebe'
 THEN RAISE EXCEPTION 'r584: before_import pin is not r523'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.note_fee_sublet_521(jsonb)')<>'r521'
  OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.note_fee_sublet_521(jsonb)')<>'2813508255aa6f65c7490e54c76cd564'
 THEN RAISE EXCEPTION 'r584: note_fee pin is not r521'; END IF;
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
 -- r584 (F198): MMT seat covers, IVMS, RADLINK, or reflective stripes on that same line. Plain seat covers, DIVMS and reflective striping do not match.
 SELECT regexp_replace(upper(coalesce(line->>'description','')||' '||coalesce(line->>'operation_code','')),'[[:space:]]+',' ','g')
  ~ '(^|[^A-Z0-9])PIT FEES?([^A-Z0-9]|$)|(^|[^A-Z0-9])WEIGH([^A-Z0-9]|$)|(WEIGH|WAY)BRIDGE|FULL TANK OF FUEL|FUEL TANK CERTIF|MMT.*SEAT[ -]?COVERS?|(^|[^A-Z0-9])IVMS([^A-Z0-9]|$)|(^|[^A-Z0-9])RADLINK([^A-Z0-9]|$)|REFLECTIVE STRIPES'
$function$;

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5='ca08696ffbe6a1834e63f8b8faf246e1', note='Pit fee, weigh, fuel, and the r584 named external phrases. Release stays r521 (F198)', updated_at=now()
WHERE signature='pdc_work_categories_private.note_fee_sublet_521(jsonb)'
  AND release='r521' AND prosrc_md5='2813508255aa6f65c7490e54c76cd564';
DO $pin$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5
     WHERE signature='pdc_work_categories_private.note_fee_sublet_521(jsonb)' AND release='r521' AND prosrc_md5='ca08696ffbe6a1834e63f8b8faf246e1')<>1
  OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241
  OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r584')<>0
  OR (SELECT release||prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')<>'r52382c809d15c382e73c0ae5bf135293ebe'
 THEN RAISE EXCEPTION 'r584: pin update'; END IF;
END $pin$;

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, '2813508255aa6f65c7490e54c76cd564', 'ca08696ffbe6a1834e63f8b8faf246e1')
WHERE check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523');
DO $pinswap$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.regression_checks
     WHERE check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523')
       AND check_sql LIKE '%ca08696ffbe6a1834e63f8b8faf246e1%'
       AND check_sql NOT LIKE '%2813508255aa6f65c7490e54c76cd564%'
       AND check_sql LIKE '%5adf2ee5c2dc8c11199d314be477a6c1%'
       AND check_sql LIKE '%c8d16e91e728540542c843751c311a97%'
       AND check_sql LIKE '%82c809d15c382e73c0ae5bf135293ebe%'
       AND check_sql LIKE '%f60ac3617342e6317107e84e014c4c36%'
       AND check_sql LIKE '%bae621855931cc4bca6e326037559da2%'
       AND check_sql LIKE '%0d71cc4ee105b90fa970622a3f4deb5d%')<>2
 THEN RAISE EXCEPTION 'r584: note and Perth checks were not updated'; END IF;
END $pinswap$;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('named_external_sublet_584','F198','MMT seat covers, IVMS, RADLINK and reflective stripes are an external Sublet through the note/fee hook. The six category bodies stay at the r523 checksums (r584).',$c584$
SELECT
 pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"MMT Seat Covers"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"MMT SEAT COVERS"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"MMT CLOTH/COMMUTER SEAT COVERS"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"Fit Navman IVMS"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"ELECTRICAL","description":"FMG IVMS to be fitted"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"reflective stripes"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"Reflective Stripes - Yellow"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"REFLECTIVE STRIPES WHITE"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"ELECTRICAL","description":"RADLINK quote"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"Radlink"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"Leaf springs","operation_code":"RADLINK"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"Canvas seat covers"}'::jsonb)='BUS_ACCESSORIES'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"Canvas seat covers"}'::jsonb)='FITTING'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"DIVMS unit"}'::jsonb) IS DISTINCT FROM 'SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"reflective striping"}'::jsonb)='FITTING'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"PIT AND WEIGH"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"weighbridge"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.note_fee_sublet_521('{"description":"mmt seat covers"}'::jsonb)
 AND pdc_work_categories_private.note_fee_sublet_521('{"description":"  Reflective   Stripes - Yellow"}'::jsonb)
 AND pdc_work_categories_private.note_fee_sublet_521('{"description":"radio quote","operation_code":"radlink"}'::jsonb)
 AND pdc_work_categories_private.note_fee_sublet_521('{"description":"Pit Fee for fuel Tank Certification"}'::jsonb)
 AND NOT pdc_work_categories_private.note_fee_sublet_521('{"description":"Canvas seat covers"}'::jsonb)
 AND NOT pdc_work_categories_private.note_fee_sublet_521('{"description":"DIVMS unit"}'::jsonb)
 AND NOT pdc_work_categories_private.note_fee_sublet_521('{"description":"reflective striping"}'::jsonb)
 AND NOT pdc_work_categories_private.note_fee_sublet_521('{"description":"IVMSX"}'::jsonb)
 AND NOT pdc_work_categories_private.note_fee_sublet_521('{"description":"Leaf springs","operation_code":"SPRING","po_details":"IVMS"}'::jsonb)
 AND NOT pdc_work_categories_private.note_fee_sublet_521('{"description":"PERTH DELIVERY"}'::jsonb)
 AND pdc_work_categories_private.route_import_line_20261017('{"department":"139","description":"Fit Navman IVMS","stage_code":"FITTING","active":true,"estimated_hours":1}'::jsonb,false)->>'work_category'='SUBLET'
 AND pdc_work_categories_private.route_import_line_20261017('{"department":"139","description":"Fit Navman IVMS","stage_code":"FITTING","active":true,"estimated_hours":1}'::jsonb,false)->>'stage_code'='SUBLET'
 AND pdc_work_categories_private.route_import_line_20261017('{"department":"139","description":"Fit Navman IVMS","stage_code":"FITTING","active":true,"estimated_hours":1,"manual":true}'::jsonb,true)->>'stage_code' IS DISTINCT FROM 'SUBLET'
 AND pdc_work_categories_private.route_import_line_20261017('{"department":"139","description":"Canvas seat covers r584 negative","stage_code":"FITTING","active":true,"estimated_hours":1}'::jsonb,false)->>'stage_code'='FITTING'
 AND public.pdc_pending_work_category_20260912('{"department":"139","stage_code":"FITTING","description":"MMT Seat Covers"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"139","stage_code":"ELECTRICAL","description":"Fit Navman IVMS"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"139","stage_code":"FITTING","description":"reflective stripes"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"139","stage_code":"ELECTRICAL","description":"RADLINK quote"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"138","description":"MMT SEAT COVERS"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"138","description":"Reflective Stripes - Yellow"}'::jsonb)->>'routing_rule'='note_fee_sublet_521'
 AND public.pdc_pending_work_category_20260912('{"department":"138","description":"Canvas seat covers"}'::jsonb)->>'stage_code' IS DISTINCT FROM 'SUBLET'
 AND pdc_work_categories_private.reviewed_import_choice_139_20261018('{"department":"139","stage_code":"FITTING","description":"REFLECTIVE STRIPES"}'::jsonb)->>'stage_code'='SUBLET'
 AND pdc_work_categories_private.reviewed_import_choice_139_20261018('{"department":"139","stage_code":"ELECTRICAL","description":"IVMS"}'::jsonb)->>'stage_code'='SUBLET'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)='7e10e4f66633cf5129c5b2c21aa905e0'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.note_fee_sublet_521(jsonb)'::regprocedure)='ca08696ffbe6a1834e63f8b8faf246e1'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.perth_delivery_sublet_523(jsonb)'::regprocedure)='2944c99ffc3c4ce09704b00d66f9fdc4'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)='5adf2ee5c2dc8c11199d314be477a6c1'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)='c8d16e91e728540542c843751c311a97'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure)='82c809d15c382e73c0ae5bf135293ebe'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure)='f60ac3617342e6317107e84e014c4c36'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure)='bae621855931cc4bca6e326037559da2'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure)='0d71cc4ee105b90fa970622a3f4deb5d'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)='9be0883b1a555f48f3c1ba9fa111c891'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)='b62fb7c29ffd2a1629f214f696e5cb14'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure)='fd05b9eef69498002ac06dd68e01cdff'
 AND position('MMT.*SEAT[ -]?COVERS?|(^|[^A-Z0-9])IVMS([^A-Z0-9]|$)|(^|[^A-Z0-9])RADLINK([^A-Z0-9]|$)|REFLECTIVE STRIPES' in h)>0
 AND position('po_details' in h)=0
 AND position('note_fee_sublet_521' in s)>position('PIT[[:space:]]' in s)
 AND position('note_fee_sublet_521' in s)<position('IS DISTINCT FROM ''138''' in s)
 AND position('note_fee_sublet_521' in b)<position('UNALLOCATED_MAPPING_REVIEW' in b)
 AND position('note_fee_sublet_521' in r)<position('SELECT * INTO r FROM pdc_operation_updates_private.ai_routing_20261019' in r)
 AND position('note_fee_sublet_521(p_line)' in p)<position('service_catalogue_hours' in p)
 AND position('service_catalogue_hours' in p)<position('Put them back on Sublet after that overwrite' in p)
 AND position('note_fee_sublet_521' in v)<position('import_rules_139' in v)
 AND (
  SELECT count(*) FROM public.pdc_pilbara_service_operations o
  WHERE regexp_replace(upper(coalesce(o.operation_description,'')||' '||coalesce(o.operation_code,'')),'[[:space:]]+',' ','g') ~ 'MMT.*SEAT[ -]?COVERS?|(^|[^A-Z0-9])IVMS([^A-Z0-9]|$)|(^|[^A-Z0-9])RADLINK([^A-Z0-9]|$)|REFLECTIVE STRIPES'
    AND (
      pdc_work_categories_private.suggest(jsonb_build_object('description',o.operation_description,'operation_code',o.operation_code,'department','139','stage_code','FITTING')) IS DISTINCT FROM 'SUBLET'
      OR pdc_work_categories_private.suggest(jsonb_build_object('description',o.operation_description,'operation_code',o.operation_code,'department','138')) IS DISTINCT FROM 'SUBLET'
    )
 )=0
 AND (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')='r523'
 AND (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')='82c809d15c382e73c0ae5bf135293ebe'
 AND (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.note_fee_sublet_521(jsonb)')='r521'
 AND (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.note_fee_sublet_521(jsonb)')='ca08696ffbe6a1834e63f8b8faf246e1'
 AND NOT EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r584')
 AND pg_catalog.to_regprocedure('pdc_work_categories_private.named_external_sublet_584(jsonb)') IS NULL
 AS ok,
 'named phrases are sublet through the unchanged r523 bodies; note/fee hook only'::text AS detail
FROM (SELECT prosrc AS s FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure) sx
, (SELECT prosrc AS b FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure) bx
, (SELECT prosrc AS r FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure) rx
, (SELECT prosrc AS p FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure) px
, (SELECT prosrc AS v FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure) vx
, (SELECT prosrc AS h FROM pg_proc WHERE oid='pdc_work_categories_private.note_fee_sublet_521(jsonb)'::regprocedure) hx
$c584$,true,356,'r584');

CREATE TABLE pdc_ops.named_external_work_touch_584 (
 vehicle_id uuid PRIMARY KEY,
 work_item_id uuid,
 existed boolean NOT NULL,
 prior_required boolean,
 prior_completed boolean,
 prior_completed_by uuid,
 prior_completed_at timestamptz,
 prior_notes text,
 prior_updated_at timestamptz
);
REVOKE ALL ON TABLE pdc_ops.named_external_work_touch_584 FROM PUBLIC, anon, authenticated;
INSERT INTO pdc_ops.named_external_work_touch_584(vehicle_id, work_item_id, existed, prior_required, prior_completed, prior_completed_by, prior_completed_at, prior_notes, prior_updated_at)
SELECT DISTINCT o.vehicle_id, w.id, w.id IS NOT NULL, w.required, w.completed, w.completed_by, w.completed_at, w.notes, w.updated_at
FROM public.pdc_pilbara_service_operations o
LEFT JOIN public.vehicle_work_items w ON w.vehicle_id=o.vehicle_id AND w.work_key='sublet'
WHERE regexp_replace(upper(coalesce(o.operation_description,'')||' '||coalesce(o.operation_code,'')),'[[:space:]]+',' ','g') ~ 'MMT.*SEAT[ -]?COVERS?|(^|[^A-Z0-9])IVMS([^A-Z0-9]|$)|(^|[^A-Z0-9])RADLINK([^A-Z0-9]|$)|REFLECTIVE STRIPES';

DO $bf$
DECLARE ids uuid[];
 ins integer := 0;
 upd integer := 0;
BEGIN
 SELECT coalesce(array_agg(vehicle_id), ARRAY[]::uuid[]) INTO ids FROM pdc_ops.named_external_work_touch_584;
 PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ids, false);
 DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = ANY(ids);
 INSERT INTO public.vehicle_work_items(vehicle_id, work_key, required, completed, notes)
 SELECT t.vehicle_id, 'sublet', true, false, 'Required by canonical imported jobcard work'
 FROM pdc_ops.named_external_work_touch_584 t
 WHERE NOT t.existed
 ON CONFLICT (vehicle_id, work_key) DO NOTHING;
 GET DIAGNOSTICS ins = ROW_COUNT;
 UPDATE public.vehicle_work_items w
 SET required = true, updated_at = clock_timestamp()
 FROM pdc_ops.named_external_work_touch_584 t
 WHERE t.existed AND w.id = t.work_item_id AND w.required IS NOT TRUE AND w.completed IS NOT TRUE;
 GET DIAGNOSTICS upd = ROW_COUNT;
 INSERT INTO pdc_work_categories_private.qc_operation_lines_cache(vehicle_id, lines, computed_at)
 SELECT t.vehicle_id, public.pdc_qc_operation_lines_379_uncached(t.vehicle_id), clock_timestamp()
 FROM pdc_ops.named_external_work_touch_584 t
 ON CONFLICT (vehicle_id) DO UPDATE
    SET lines = EXCLUDED.lines, computed_at = EXCLUDED.computed_at
    WHERE true;
 RAISE NOTICE 'r584: % vehicles cache-refilled, sublet inserts %, sublet required updates %', cardinality(ids), ins, upd;
END
$bf$;

DO $post$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r584: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r584')<>0 THEN RAISE EXCEPTION 'r584: a category pin moved'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')<>'r523' THEN RAISE EXCEPTION 'r584: before_import pin left r523'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')<>'82c809d15c382e73c0ae5bf135293ebe' THEN RAISE EXCEPTION 'r584: before_import md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.note_fee_sublet_521(jsonb)'::regprocedure)<>'ca08696ffbe6a1834e63f8b8faf246e1'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.perth_delivery_sublet_523(jsonb)'::regprocedure)<>'2944c99ffc3c4ce09704b00d66f9fdc4'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'5adf2ee5c2dc8c11199d314be477a6c1'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'c8d16e91e728540542c843751c311a97'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure)<>'82c809d15c382e73c0ae5bf135293ebe'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure)<>'f60ac3617342e6317107e84e014c4c36'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure)<>'bae621855931cc4bca6e326037559da2'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure)<>'0d71cc4ee105b90fa970622a3f4deb5d'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'9be0883b1a555f48f3c1ba9fa111c891'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'b62fb7c29ffd2a1629f214f696e5cb14'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure)<>'fd05b9eef69498002ac06dd68e01cdff'
 THEN RAISE EXCEPTION 'r584: new md5 mismatch'; END IF;
 PERFORM set_config('request.jwt.claims','',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='named_external_sublet_584') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r584: named_external_sublet_584 failed: %', r.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='note_fee_sublet_521') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r584: note_fee_sublet_521 failed: %', r.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='perth_delivery_sublet_523') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r584: perth_delivery_sublet_523 failed: %', r.detail; END IF;
END $post$;
