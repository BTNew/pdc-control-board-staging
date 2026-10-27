-- r568 (F182) undo. Drops the two new functions and check bus_component_split_568.
-- Does not rewrite a vehicle, a booking, a conversion section, or a line tick. A component started
-- in one bay and finished in another keeps that history. Pin count stays 241.
-- Object names stay _565. The live panel check r565 / F179 stays.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r568 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r568 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r568 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r568 undo: fitter command changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.conversion_save(uuid,uuid,text,jsonb)')) IS DISTINCT FROM '39b8f50d21d7932e671c31a5d539001d' THEN RAISE EXCEPTION 'r568 undo: conversion_save changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) IS DISTINCT FROM '240e25e96467490d71744490c7a4d75c' THEN RAISE EXCEPTION 'r568 undo: category save changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_bus_component_board_565(uuid)')) IS DISTINCT FROM '7031ac921d64cf2db16d52f3e8e02140' THEN RAISE EXCEPTION 'r568 undo: board read changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_pdc_bus_component_line_565(uuid,uuid,text,text,text)')) IS DISTINCT FROM '3ea8b27f10bfc908c410760ed22f4fed' THEN RAISE EXCEPTION 'r568 undo: setter changed'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='bus_component_split_568' AND fault_id='F182' AND sort_order=339 AND added_in='r568';
DROP FUNCTION IF EXISTS public.set_pdc_bus_component_line_565(uuid,uuid,text,text,text);
DROP FUNCTION IF EXISTS public.get_pdc_bus_component_board_565(uuid);

DO $g$ BEGIN
 IF to_regprocedure('public.get_pdc_bus_component_board_565(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r568 undo: board read still present'; END IF;
 IF to_regprocedure('public.set_pdc_bus_component_line_565(uuid,uuid,text,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'r568 undo: setter still present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bus_component_split_568' OR fault_id='F182' OR added_in='r568') THEN RAISE EXCEPTION 'r568 undo: check still present'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r568 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r568 undo: fitter command changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.conversion_save(uuid,uuid,text,jsonb)')) IS DISTINCT FROM '39b8f50d21d7932e671c31a5d539001d' THEN RAISE EXCEPTION 'r568 undo: conversion_save changed'; END IF;
END $g$;
