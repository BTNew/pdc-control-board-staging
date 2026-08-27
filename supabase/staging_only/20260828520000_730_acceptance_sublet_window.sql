-- STAGING ONLY 730: repair the acceptance Sublet fixture date window.
-- The reviewed six-case action is 2026-09-16; the fixture's existing return
-- date must be on/after that date for the canonical update RPC to accept it.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-730-acceptance-sublet-window',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE create_sha text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO create_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828510000' OR create_sha<>'1a64264717a7db6e73d34a2b1cdaa971d12ca128facefdd51ce69b9d0172c957' OR to_regclass('public.pdc_authenticated_acceptance_sublet_window_history_730') IS NOT NULL THEN RAISE EXCEPTION 'PDC_730_EXACT_729_CREATE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_acceptance_sublet_window_history_730(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='acceptance_sublet_window'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828510000'),successor_head text NOT NULL CHECK(successor_head='20260828520000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='1a64264717a7db6e73d34a2b1cdaa971d12ca128facefdd51ce69b9d0172c957'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_acceptance_sublet_window_history_730 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_acceptance_sublet_window_history_730 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_acceptance_sublet_window_history_730 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_acceptance_sublet_window_history_immutable_730() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_730_ACCEPTANCE_SUBLET_WINDOW_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_acceptance_sublet_window_history_immutable_730() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_acceptance_sublet_window_history_immutable_730 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_acceptance_sublet_window_history_730 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_acceptance_sublet_window_history_immutable_730();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 old:=$old$'2026-09-01','2026-09-10','active','PDC acceptance synthetic fixture'$old$;
 new:=$new$'2026-09-01','2026-09-30','active','PDC acceptance synthetic fixture'$new$;
 IF before_sha<>'1a64264717a7db6e73d34a2b1cdaa971d12ca128facefdd51ce69b9d0172c957' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_730_SUBLET_WINDOW_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 INSERT INTO public.pdc_authenticated_acceptance_sublet_window_history_730(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-730-acceptance-sublet-window|forward','UTF8'),'sha256'),'hex'),'acceptance_sublet_window','20260828510000','20260828520000',before_sha,after_sha,'Set only the synthetic campaign existing Sublet fixture expected return date to 2026-09-30 so the reviewed 2026-09-16 booking-date action satisfies the canonical date-order invariant',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_acceptance_sublet_window_history_730)<>1 OR position('2026-09-30' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_730_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828520000','730_acceptance_sublet_window',ARRAY['Exact 729 create-function hash guard','Synthetic fixture expected return date covers reviewed 2026-09-16 action','UID514/task/mailbox/outbound/Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
