-- STAGING ONLY 20260901233000: refresh the v2 capability immediately before
-- timeline dispatch. This is a narrow compatibility successor; all prior
-- receipts and operator/planner guards remain unchanged.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901233000-v2-canonical-note-capability-refresh',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901232000 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901233000') OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL THEN RAISE EXCEPTION 'PDC_20260901233000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_email_ai_v2_canonical_note_capability_history_20260901(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 predecessor_head text NOT NULL CHECK(predecessor_head='20260901232000'), successor_head text NOT NULL CHECK(successor_head='20260901233000'),
 predecessor_hash text NOT NULL, successor_hash text NOT NULL, repair_contract text NOT NULL,
 production_writes boolean NOT NULL CHECK(NOT production_writes), mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted), outbound_email boolean NOT NULL CHECK(NOT outbound_email), action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked), created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_email_ai_v2_canonical_note_capability_history_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_canonical_note_capability_history_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_canonical_note_capability_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_canonical_note_capability_history_immutable_20260901() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_20260901233000_NOTE_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_canonical_note_capability_history_immutable_20260901 BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_canonical_note_capability_history_20260901 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_canonical_note_capability_history_immutable_20260901();
DO $repair$
DECLARE d text; old text; new text; before_hash text; after_hash text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure), encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,before_hash;
 old:=$old$ELSIF action_type='note_append' THEN canonical_rpc:=$old$;
 new:=$new$ELSIF action_type='note_append' THEN PERFORM set_config('pdc.monitor.v2_canonical_action_capability_20260902','pdc-email-ai-v2|'||source_id::text||'|'||action_key,true); canonical_rpc:=$new$;
 IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260901233000_NOTE_ANCHOR_FAILED' USING errcode='55000'; END IF;
 d:=replace(d,old,new);
 EXECUTE d;
 SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;
 INSERT INTO public.pdc_email_ai_v2_canonical_note_capability_history_20260901(event_key,predecessor_head,successor_head,predecessor_hash,successor_hash,repair_contract,production_writes,mailbox_contacted,outbound_email,action_rpc_invoked) VALUES(encode(extensions.digest(convert_to('pdc-staging-20260901233000-v2-canonical-note-capability-refresh|forward','UTF8'),'sha256'),'hex'),'20260901232000','20260901233000',before_hash,after_hash,'Refresh the actor-bound dotted transaction-local capability immediately before note_append canonical dispatch; retain strict source/action binding and canonical timeline authority.',false,false,false,false);
END $repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_email_ai_v2_canonical_note_capability_history_20260901)<>1 OR position('ELSIF action_type=''note_append'' THEN PERFORM set_config' IN (SELECT pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure)))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_20260901233000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901233000','pdc_email_ai_v2_canonical_note_capability_refresh_20260901',ARRAY['Refresh the dotted actor-bound transaction-local capability immediately before canonical note_append dispatch','Preserve planner/operator guard for direct callers, strict source binding, per-action receipts, field-level readback and zero Production/mailbox/outbound/action-RPC state']);
NOTIFY pgrst,'reload schema'; COMMIT;
