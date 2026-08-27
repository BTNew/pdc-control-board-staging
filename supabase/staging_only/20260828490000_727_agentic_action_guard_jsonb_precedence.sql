-- STAGING ONLY 727: repair the proven canonical action-receipt trigger
-- JSONB precedence defect. Only source_binding field traversal is parenthesized;
-- all normal immutability and acceptance authority checks remain unchanged.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-727-agentic-action-guard-jsonb',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE trigger_sha text; apply_sha text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO trigger_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_action_guard_502()'::regprocedure;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO apply_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_apply_action_502(uuid)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828480000' OR trigger_sha<>'80e396fc3ab201b0b5621aca7c8eb34f10cabb0dd93af1df4ab6ed787519eaad' OR apply_sha<>'973425b72a0a31240813779e282dcf17f0616f6e8bea4b47d41eefc600551887' OR to_regclass('public.pdc_authenticated_agentic_action_guard_jsonb_history_727') IS NOT NULL THEN RAISE EXCEPTION 'PDC_727_EXACT_726_TRIGGER_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_action_guard_jsonb_history_727(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_action_guard_jsonb_precedence'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828480000'),successor_head text NOT NULL CHECK(successor_head='20260828490000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='80e396fc3ab201b0b5621aca7c8eb34f10cabb0dd93af1df4ab6ed787519eaad'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_action_guard_jsonb_history_727 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_action_guard_jsonb_history_727 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_action_guard_jsonb_history_727 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_action_guard_jsonb_history_immutable_727() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_727_ACTION_GUARD_JSONB_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_action_guard_jsonb_history_immutable_727() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_action_guard_jsonb_history_immutable_727 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_action_guard_jsonb_history_727 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_action_guard_jsonb_history_immutable_727();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_agentic_email_action_guard_502()'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_action_guard_502()'::regprocedure;
 old:=$old$(new.request->'source_binding'-array['claim_token','gateway_instance_id']::text[])
       is distinct from (old.request->'source_binding'-array['claim_token','gateway_instance_id']::text[])$old$;
 new:=$new$((new.request->'source_binding')-array['claim_token','gateway_instance_id']::text[])
       is distinct from ((old.request->'source_binding')-array['claim_token','gateway_instance_id']::text[])$new$;
 IF before_sha<>'80e396fc3ab201b0b5621aca7c8eb34f10cabb0dd93af1df4ab6ed787519eaad' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_727_ACTION_GUARD_JSONB_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_action_guard_502()'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_action_guard_jsonb_history_727(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-727-agentic-action-guard-jsonb|forward','UTF8'),'sha256'),'hex'),'agentic_action_guard_jsonb_precedence','20260828480000','20260828490000',before_sha,after_sha,'Parenthesize only new.request->source_binding and old.request->source_binding before JSONB key deletion; preserve strict receipt immutability, exact actor/source binding, normal apply behavior and replay semantics',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_action_guard_jsonb_history_727)<>1 OR position('(new.request->''source_binding'')-array[''claim_token'',''gateway_instance_id'']::text[]' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_action_guard_502()'::regprocedure))=0 OR position('(old.request->''source_binding'')-array[''claim_token'',''gateway_instance_id'']::text[]' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_action_guard_502()'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_727_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828490000','727_agentic_action_guard_jsonb_precedence',ARRAY['Exact 726 head, trigger hash and canonical apply hash guards','Parenthesize trigger source_binding JSONB key deletion only','UID514/task/mailbox/outbound/Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
