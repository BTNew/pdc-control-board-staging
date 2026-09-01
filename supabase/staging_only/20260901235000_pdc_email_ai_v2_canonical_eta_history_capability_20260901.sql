-- STAGING ONLY 20260901235000: carry the exact v2 canonical capability into
-- the nested ETA-history helper used by note timeline readback. No role grant or
-- direct-table access is added; ordinary importer/admin checks remain.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901235000-v2-canonical-eta-history-capability',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901234000 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901235000') OR to_regprocedure('public.record_vehicle_eta_history(uuid,text,date,text,public.vehicle_timeline_event_state,numeric,text,text,text,timestamptz,uuid,uuid)') IS NULL THEN RAISE EXCEPTION 'PDC_20260901235000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_email_ai_v2_canonical_eta_history_capability_history_20260901(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,predecessor_head text NOT NULL CHECK(predecessor_head='20260901234000'),successor_head text NOT NULL CHECK(successor_head='20260901235000'),predecessor_hash text NOT NULL,successor_hash text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),outbound_email boolean NOT NULL CHECK(NOT outbound_email),action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_email_ai_v2_canonical_eta_history_capability_history_20260901 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_email_ai_v2_canonical_eta_history_capability_history_20260901 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_email_ai_v2_canonical_eta_history_capability_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_canonical_eta_history_capability_history_immutable_20260901() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_20260901235000_ETA_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_canonical_eta_history_capability_history_immutable_20260901 BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_canonical_eta_history_capability_history_20260901 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_canonical_eta_history_capability_history_immutable_20260901();
DO $repair$
DECLARE d text; old text; new text; before_hash text; after_hash text;
BEGIN
 SELECT pg_get_functiondef('public.record_vehicle_eta_history(uuid,text,date,text,public.vehicle_timeline_event_state,numeric,text,text,text,timestamptz,uuid,uuid)'::regprocedure),encode(extensions.digest(convert_to(pg_get_functiondef('public.record_vehicle_eta_history(uuid,text,date,text,public.vehicle_timeline_event_state,numeric,text,text,text,timestamptz,uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,before_hash;
 old:=$old$if public.current_pdc_user_role() not in ('importer', 'administrator') then$old$;
 new:=$new$if public.current_pdc_user_role() not in ('importer', 'administrator') and not public.pdc_email_ai_v2_canonical_action_capability_20260902() then$new$;
 IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260901235000_ETA_HISTORY_GUARD_ANCHOR_FAILED' USING errcode='55000'; END IF;
 d:=replace(d,old,new);
 EXECUTE d;
 SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.record_vehicle_eta_history(uuid,text,date,text,public.vehicle_timeline_event_state,numeric,text,text,text,timestamptz,uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;
 INSERT INTO public.pdc_email_ai_v2_canonical_eta_history_capability_history_20260901(event_key,predecessor_head,successor_head,predecessor_hash,successor_hash,repair_contract,production_writes,mailbox_contacted,outbound_email,action_rpc_invoked) VALUES(encode(extensions.digest(convert_to('pdc-staging-20260901235000-v2-canonical-eta-history-capability|forward','UTF8'),'sha256'),'hex'),'20260901234000','20260901235000',before_hash,after_hash,'Nested record_vehicle_eta_history accepts only the actor-bound v2 capability for strict note timeline dispatch; importer/administrator authority remains unchanged.',false,false,false,false);
END $repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_email_ai_v2_canonical_eta_history_capability_history_20260901)<>1 OR position('pdc_email_ai_v2_canonical_action_capability_20260902()' IN (SELECT pg_get_functiondef('public.record_vehicle_eta_history(uuid,text,date,text,public.vehicle_timeline_event_state,numeric,text,text,text,timestamptz,uuid,uuid)'::regprocedure)))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_20260901235000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901235000','pdc_email_ai_v2_canonical_eta_history_capability_20260901',ARRAY['Nested ETA-history helper accepts the exact actor-bound v2 capability for note timeline dispatch','Importer/administrator guards remain for direct or ordinary paths; receipts/source binding/readback and zero Production/mailbox/outbound/action-RPC state are preserved']);
NOTIFY pgrst,'reload schema'; COMMIT;
