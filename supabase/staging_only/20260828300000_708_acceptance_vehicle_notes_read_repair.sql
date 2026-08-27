-- STAGING ONLY 708: repair the exact acceptance-only vehicle read to use the
-- existing JSON projection for optional notes. No normal snapshot path changes.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-708-acceptance-vehicle-notes-read',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_acceptance_vehicle_projection_703(uuid,uuid)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828290000' OR h<>'e0cdad706dfaa23c0ac8d8316918f9e005f372510b0a1e0c0c479a49e2d75e29' OR to_regclass('public.pdc_authenticated_acceptance_vehicle_notes_history_708') IS NOT NULL THEN RAISE EXCEPTION 'PDC_708_EXACT_707_VEHICLE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_acceptance_vehicle_notes_history_708(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='acceptance_vehicle_notes_read_repair'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828290000'),successor_head text NOT NULL CHECK(successor_head='20260828300000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='e0cdad706dfaa23c0ac8d8316918f9e005f372510b0a1e0c0c479a49e2d75e29'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_acceptance_vehicle_notes_history_708 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_acceptance_vehicle_notes_history_708 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_acceptance_vehicle_notes_history_708 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_acceptance_vehicle_notes_history_immutable_708() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_708_VEHICLE_NOTES_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_acceptance_vehicle_notes_history_immutable_708() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_acceptance_vehicle_notes_history_immutable_708 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_acceptance_vehicle_notes_history_708 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_acceptance_vehicle_notes_history_immutable_708();
DO $repair$
DECLARE d text; before_sha text; after_sha text; old text; new text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_monitor_authenticated_acceptance_vehicle_projection_703(uuid,uuid)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_acceptance_vehicle_projection_703(uuid,uuid)'::regprocedure;
 old:=$old$'notes',v.notes$old$; new:=$new$'notes',(to_jsonb(v)->'notes')$new$;
 IF before_sha<>'e0cdad706dfaa23c0ac8d8316918f9e005f372510b0a1e0c0c479a49e2d75e29' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_708_NOTES_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_acceptance_vehicle_projection_703(uuid,uuid)'::regprocedure;
 INSERT INTO public.pdc_authenticated_acceptance_vehicle_notes_history_708(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-708-acceptance-vehicle-notes-read|forward','UTF8'),'sha256'),'hex'),'acceptance_vehicle_notes_read_repair','20260828290000','20260828300000',before_sha,after_sha,'Read optional notes through the vehicle JSON projection because the base vehicle table has no notes column; retain exact synthetic scope and canonical Parts/ETA/Sublet state',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_acceptance_vehicle_notes_history_708)<>1 OR position('(to_jsonb(v)->''notes'')' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_acceptance_vehicle_projection_703(uuid,uuid)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_708_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828300000','708_acceptance_vehicle_notes_read_repair',ARRAY['Exact 707 predecessor and acceptance vehicle projection hash guard','Use to_jsonb(vehicle)->notes for optional notes in the acceptance-only authoritative read','Normal Board and non-acceptance vehicle reads unchanged; UID514/task/mailbox/outbound/Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
