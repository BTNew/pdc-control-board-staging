-- r401 undo: restores ensure_required_work_20261019 (761267c9) exactly, drops the Pit tick/read RPCs and helper,
-- and removes the r401 pins and check. The tick tables and their rows are KEPT (no data deleted); with the RPCs
-- gone nothing reads or writes them. A later re-apply reuses them (CREATE TABLE IF NOT EXISTS).
DO $g$
DECLARE want jsonb:='{"public.pdc_line_is_pit_401(uuid,jsonb)": "6d071672dd859d7ec3e889ece66624ff", "public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)": "961830f0c389853706fb7239b7b96dc9", "public.get_pdc_pit_line_ticks_401(uuid[])": "2ee29cafcd7b4affaa7929114900c835", "pdc_operation_updates_private.ensure_required_work_20261019(uuid)": "4db6302844ef0da651d165a3716bbbac"}'::jsonb; k text;
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'r401 undo: staging only'; END IF;
 FOR k IN SELECT jsonb_object_keys(want) LOOP
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=k::regprocedure)<>want->>k THEN RAISE EXCEPTION 'r401 undo: % is not the r401 body',k; END IF;
 END LOOP;
END $g$;
CREATE OR REPLACE FUNCTION pdc_operation_updates_private.ensure_required_work_20261019(p_vehicle_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE changed integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'staging_required'; END IF;
 -- Existing deferred mutation paths explicitly reconcile their accepted changes.
 IF current_setting('pdc.defer_workshop_required_work_reconcile',true)='407' THEN RETURN 0; END IF;
 PERFORM 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL
  AND v.lifecycle_state='active' AND v.visible_on_board AND v.qc_completed_at IS NULL
  AND upper(coalesce(v.current_location,'')) NOT IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
  AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='approved')
  AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND o.department IN('138','139')) FOR UPDATE;
 IF NOT FOUND THEN RETURN 0; END IF;
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 SELECT DISTINCT p_vehicle_id,s.work_key,true,false,'Required by canonical imported jobcard work'
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 JOIN public.workshop_stages s ON s.code=CASE WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4' ELSE l->>'stage_code' END
 WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
  AND coalesce(l->>'completed','false')<>'true' AND s.work_key IS NOT NULL
  AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','PIT_INSPECTION')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp()
 WHERE NOT vehicle_work_items.required AND NOT vehicle_work_items.completed;
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed;
END $function$;

DROP FUNCTION public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid);
DROP FUNCTION public.get_pdc_pit_line_ticks_401(uuid[]);
DROP FUNCTION public.pdc_line_is_pit_401(uuid,jsonb);
DELETE FROM pdc_ops.regression_checks WHERE check_name='pit_lines_neutral_and_tickable' AND added_in='r401';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r401' AND signature IN ('public.pdc_line_is_pit_401(uuid,jsonb)','public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)','public.get_pdc_pit_line_ticks_401(uuid[])','pdc_operation_updates_private.ensure_required_work_20261019(uuid)');
DO $p$
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'761267c9806683eca13e79c531b4334a'
  OR md5(pg_get_functiondef('pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure))<>'0726d03e406d873ccdab31ef027f0755'
  OR (SELECT proacl::text FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'{postgres=X/postgres}'
  OR to_regprocedure('public.pdc_line_is_pit_401(uuid,jsonb)') IS NOT NULL OR to_regprocedure('public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)') IS NOT NULL OR to_regprocedure('public.get_pdc_pit_line_ticks_401(uuid[])') IS NOT NULL
  THEN RAISE EXCEPTION 'r401 undo: restore check failed'; END IF;
END $p$;
