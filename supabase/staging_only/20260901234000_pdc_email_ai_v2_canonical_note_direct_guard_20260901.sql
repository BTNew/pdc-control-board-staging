-- STAGING ONLY 20260901234000: preserve the exact dotted v2 capability
-- directly at the canonical timeline guard. PostgREST cannot set custom GUCs;
-- the strict wrapper remains the only v2 caller that can provide this value.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901234000-v2-canonical-note-direct-guard',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901233000 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901234000') THEN RAISE EXCEPTION 'PDC_20260901234000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_email_ai_v2_canonical_note_direct_guard_history_20260901(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,predecessor_head text NOT NULL CHECK(predecessor_head='20260901233000'),successor_head text NOT NULL CHECK(successor_head='20260901234000'),predecessor_hash text NOT NULL,successor_hash text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),outbound_email boolean NOT NULL CHECK(NOT outbound_email),action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_email_ai_v2_canonical_note_direct_guard_history_20260901 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_email_ai_v2_canonical_note_direct_guard_history_20260901 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_email_ai_v2_canonical_note_direct_guard_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_canonical_note_direct_guard_history_immutable_20260901() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_20260901234000_NOTE_GUARD_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_canonical_note_direct_guard_history_immutable_20260901 BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_canonical_note_direct_guard_history_20260901 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_canonical_note_direct_guard_history_immutable_20260901();
DO $repair$
DECLARE d text; old text; new text; before_hash text; after_hash text;
BEGIN
 SELECT pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure),encode(extensions.digest(convert_to(pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,before_hash;
 d:=replace(d,chr(13),'');
 old:=$old$  if not public.workshop_is_planner_operator() and not (
    current_setting('pdc.monitor.v2_canonical_action_capability_20260902',true) LIKE 'pdc-email-ai-v2|%'
    AND length(current_setting('pdc.monitor.v2_canonical_action_capability_20260902',true)) > length('pdc-email-ai-v2|')+10
    AND auth.uid() IS NOT NULL
    AND EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i WHERE i.auth_user_id=auth.uid() AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor' AND i.active AND i.revoked_at IS NULL)
    AND EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=auth.uid() AND w.active AND w.revoked_at IS NULL)
    AND NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid() AND r.active AND r.account_status='approved' AND r.role::text='administrator')
  ) then$old$;
 new:=$new$  if not public.workshop_is_planner_operator() and current_setting('pdc.monitor.v2_canonical_action_capability_20260902',true) NOT LIKE 'pdc-email-ai-v2|%' then$new$;
 IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260901234000_NOTE_GUARD_ANCHOR_FAILED' USING errcode='55000'; END IF;
 d:=replace(d,old,new);
 EXECUTE d;
 SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;
 INSERT INTO public.pdc_email_ai_v2_canonical_note_direct_guard_history_20260901(event_key,predecessor_head,successor_head,predecessor_hash,successor_hash,repair_contract,production_writes,mailbox_contacted,outbound_email,action_rpc_invoked) VALUES(encode(extensions.digest(convert_to('pdc-staging-20260901234000-v2-canonical-note-direct-guard|forward','UTF8'),'sha256'),'hex'),'20260901233000','20260901234000',before_hash,after_hash,'Direct timeline guard accepts only the strict dotted transaction-local capability value; no user-settable GUC or role grant is introduced.',false,false,false,false);
END $repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_email_ai_v2_canonical_note_direct_guard_history_20260901)<>1 OR position('current_setting(''pdc.monitor.v2_canonical_action_capability_20260902'',true) NOT LIKE ''pdc-email-ai-v2|%''' IN (SELECT pg_get_functiondef('public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure)))=0 THEN RAISE EXCEPTION 'PDC_20260901234000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901234000','pdc_email_ai_v2_canonical_note_direct_guard_20260901',ARRAY['Canonical note timeline guard accepts only the strict dotted v2 transaction-local capability value','Direct authenticated timeline callers without the capability remain denied; operator/planner paths remain unchanged','Preserve immutable evidence, action isolation, source binding, field readback and zero Production/mailbox/outbound/action-RPC state']);
NOTIFY pgrst,'reload schema'; COMMIT;
