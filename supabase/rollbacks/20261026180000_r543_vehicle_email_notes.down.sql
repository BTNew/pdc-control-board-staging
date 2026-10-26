-- Undo r543 (F157). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Removes notes this release wrote, then the read, the append, and the message-id index.
-- Does not remove any other timeline row, and does not change append_vehicle_timeline_event.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r543 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r543 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r543 undo: pin count is not 241'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='append_vehicle_timeline_event') IS DISTINCT FROM 'ef3bd3587978f25862546483913231e4' THEN RAISE EXCEPTION 'r543 undo: pinned append changed'; END IF;
END $g$;

DELETE FROM public.vehicle_timeline_events
WHERE structured_data->>'source' = 'email_note_543';

DROP FUNCTION IF EXISTS public.list_vehicle_email_notes_543(uuid);
DROP FUNCTION IF EXISTS public.append_vehicle_email_note_543(uuid, text, text, text, text, text, text, text, timestamp with time zone);
DROP INDEX IF EXISTS public.vehicle_timeline_events_source_email_543;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='vehicle_email_notes_543' AND fault_id='F157' AND sort_order=321 AND added_in='r543';

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r543 undo: pin count changed'; END IF;
 IF to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)') IS NOT NULL THEN RAISE EXCEPTION 'r543 undo: append remains'; END IF;
 IF to_regprocedure('public.list_vehicle_email_notes_543(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r543 undo: read remains'; END IF;
 IF to_regclass('public.vehicle_timeline_events_source_email_543') IS NOT NULL THEN RAISE EXCEPTION 'r543 undo: index remains'; END IF;
 IF EXISTS (SELECT 1 FROM public.vehicle_timeline_events WHERE structured_data->>'source' = 'email_note_543') THEN RAISE EXCEPTION 'r543 undo: a note remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='vehicle_email_notes_543') THEN RAISE EXCEPTION 'r543 undo: check remains'; END IF;
END $p$;
