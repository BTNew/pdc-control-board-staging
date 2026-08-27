-- STAGING ONLY 721: avoid the strict 502 request rewrite on the exact
-- synthetic acceptance path. The initial insert already stores v_request and
-- replay is idempotent; normal actions retain the original update behavior.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-721-agentic-acceptance-request-write',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828420000' OR h<>'d120208e571beee60b70af53300a3f76804c9ec8b7e71d63acddc51b9a0a78de' OR to_regclass('public.pdc_authenticated_agentic_acceptance_request_history_721') IS NOT NULL THEN RAISE EXCEPTION 'PDC_721_EXACT_720_EXECUTE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF; END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_acceptance_request_history_721(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_acceptance_request_write'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828420000'),successor_head text NOT NULL CHECK(successor_head='20260828430000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='d120208e571beee60b70af53300a3f76804c9ec8b7e71d63acddc51b9a0a78de'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_acceptance_request_history_721 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_acceptance_request_history_721 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_acceptance_request_history_721 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_acceptance_request_history_immutable_721() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_721_ACCEPTANCE_REQUEST_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_acceptance_request_history_immutable_721() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_acceptance_request_history_immutable_721 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_acceptance_request_history_721 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_acceptance_request_history_immutable_721();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 old:=$old$update public.pdc_agentic_email_action_receipts_502 set request=
    case when execution_result is null then v_request
         else jsonb_set(request,'{source_binding}',p_action->'source_binding',true) end
    where action_receipt_id=v_row.action_receipt_id;$old$;
 new:=$new$if ((p_action->'source_binding')->>'provider_uid'~'^imap_uid:[0-9]+$' and substring((p_action->'source_binding')->>'provider_uid' from 10)::bigint>=515) then null;
  else
    update public.pdc_agentic_email_action_receipts_502 set request=
      case when execution_result is null then v_request
           else jsonb_set(request,'{source_binding}',p_action->'source_binding',true) end
      where action_receipt_id=v_row.action_receipt_id;
  end if;$new$;
 IF before_sha<>'d120208e571beee60b70af53300a3f76804c9ec8b7e71d63acddc51b9a0a78de' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_721_REQUEST_WRITE_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_acceptance_request_history_721(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-721-agentic-acceptance-request-write|forward','UTF8'),'sha256'),'hex'),'agentic_acceptance_request_write','20260828420000','20260828430000',before_sha,after_sha,'Skip only the redundant post-insert request rewrite for exact synthetic UID>=515 acceptance actions; normal 502 update and replay paths remain intact',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_acceptance_request_history_721)<>1 OR position('provider_uid' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_721_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828430000','721_agentic_acceptance_request_write',ARRAY['Exact 720 predecessor and strict execute hash guard','Redundant request rewrite is skipped only for synthetic provider UID>=515 acceptance actions','Normal Board/read filters, action semantics, UID514/task/mailbox/outbound and Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
