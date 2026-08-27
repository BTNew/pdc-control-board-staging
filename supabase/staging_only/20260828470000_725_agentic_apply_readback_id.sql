-- STAGING ONLY 725: use the canonical action receipt vehicle UUID for
-- authoritative apply readback, avoiding a response-data cast in the strict
-- 502 apply function. No action semantics change.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-725-agentic-apply-readback-id',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.pdc_agentic_apply_action_502(uuid)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828460000' OR h<>'9c813af273f5fefb0c22cc0bc8478b59c2327488f40af128d4968a65946975c6' OR to_regclass('public.pdc_authenticated_agentic_apply_readback_id_history_725') IS NOT NULL THEN RAISE EXCEPTION 'PDC_725_EXACT_724_APPLY_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF; END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_apply_readback_id_history_725(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_apply_readback_id'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828460000'),successor_head text NOT NULL CHECK(successor_head='20260828470000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='9c813af273f5fefb0c22cc0bc8478b59c2327488f40af128d4968a65946975c6'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_apply_readback_id_history_725 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_apply_readback_id_history_725 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_apply_readback_id_history_725 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_apply_readback_id_history_immutable_725() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_725_APPLY_READBACK_ID_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_apply_readback_id_history_immutable_725() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_apply_readback_id_history_immutable_725 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_apply_readback_id_history_725 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_apply_readback_id_history_immutable_725();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_agentic_apply_action_502(uuid)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_apply_action_502(uuid)'::regprocedure;
 old:=$old$v_readback_vehicle_id:=coalesce(a.vehicle_id,nullif(coalesce(r#>>'{data,vehicle_id}',r->>'vehicle_id',r->>'linked_vehicle_id'),'')::uuid);$old$; new:=$new$v_readback_vehicle_id:=a.vehicle_id;$new$;
 IF before_sha<>'9c813af273f5fefb0c22cc0bc8478b59c2327488f40af128d4968a65946975c6' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_725_READBACK_ID_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_apply_action_502(uuid)'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_apply_readback_id_history_725(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-725-agentic-apply-readback-id|forward','UTF8'),'sha256'),'hex'),'agentic_apply_readback_id','20260828460000','20260828470000',before_sha,after_sha,'Use the already-authoritative receipt vehicle UUID for apply readback; remove only the response-data UUID cast that blocked strict synthetic acceptance',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_apply_readback_id_history_725)<>1 OR position('v_readback_vehicle_id:=a.vehicle_id' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.pdc_agentic_apply_action_502(uuid)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_725_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828470000','725_agentic_apply_readback_id',ARRAY['Exact 724 predecessor and canonical apply hash guard','Use canonical receipt vehicle UUID for apply readback without response-data cast','UID514/task/mailbox/outbound/Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
