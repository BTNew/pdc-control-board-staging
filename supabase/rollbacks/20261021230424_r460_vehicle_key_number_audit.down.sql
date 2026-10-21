-- r460 undo (F73): removes the key-number edit RPCs, the audit capture triggers on vehicles, the audit and receipt tables,
-- the private schema, the check and the 6 pins. Staging cdsmnqxtyyoeoznmbidd only, in a :02-:45 window.
-- BEFORE RUNNING: export the audit (it is dropped here), e.g.
--   COPY (SELECT * FROM public.pdc_vehicle_key_number_audit_460 ORDER BY changed_at) TO STDOUT WITH CSV HEADER;
--   (or: select json_agg(a order by changed_at) from public.pdc_vehicle_key_number_audit_460 a;  and save the result)
-- Undoes r460 and r460b (the pin fix) together.
-- Vehicle key values are data and are NOT reverted: vehicles.key_number keeps whatever it holds (the export shows each
-- change's old value if one must be put back). The service import keeps updating key_number as before r460.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r460 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r460 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) AND md5(p.prosrc)=e.prosrc_md5 WHERE e.release='r460')<>6
    THEN RAISE EXCEPTION 'r460 undo: the r460 functions are not the pinned versions'; END IF;
 PERFORM set_config('pdc.r460_pins_before_undo',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 PERFORM set_config('pdc.r460_tick_before_undo',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
END $g$;
DROP TRIGGER zz_pdc_key_number_audit_460_upd ON public.vehicles;
DROP TRIGGER zz_pdc_key_number_audit_460_ins ON public.vehicles;
DROP FUNCTION public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid);
DROP FUNCTION public.get_pdc_vehicle_key_number_460(uuid);
DROP FUNCTION pdc_key_number_private.release_set_key_number_460(uuid,integer,text,text,text,uuid);
DROP FUNCTION pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid);
DROP FUNCTION pdc_key_number_private.capture_460();
DROP TABLE public.pdc_vehicle_key_number_receipts_460;
DROP TABLE public.pdc_vehicle_key_number_audit_460;
DROP FUNCTION pdc_key_number_private.append_only_460();
DROP SCHEMA pdc_key_number_private;
DELETE FROM pdc_ops.regression_checks WHERE check_name='vehicle_key_number_audit_460' AND added_in='r460';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r460';
DO $g$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r460_pins_before_undo')::int-6
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.vehicles'::regclass AND tgname LIKE '%key_number_audit_460%')
    OR to_regnamespace('pdc_key_number_private') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='vehicle_key_number_audit_460') THEN RAISE EXCEPTION 'r460 undo: not fully removed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>current_setting('pdc.r460_tick_before_undo') THEN RAISE EXCEPTION 'r460 undo: clock tick changed'; END IF;
END $g$;
