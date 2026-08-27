-- STAGING ONLY 719: use the exact synthetic provider-UID boundary as the
-- acceptance parity switch, avoiding JSONB marker expression coercion inside
-- the strict 502 function. The 684 wrapper already proves the full marker set.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-719-agentic-acceptance-uid-parity',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828400000' OR h<>'ede47069d6c67c0918be55cf11ec98d1532c127e9a3056546309328a7edd2cf3' OR to_regclass('public.pdc_authenticated_agentic_acceptance_uid_parity_history_719') IS NOT NULL THEN RAISE EXCEPTION 'PDC_719_EXACT_718_EXECUTE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF; END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_acceptance_uid_parity_history_719(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_acceptance_uid_parity'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828400000'),successor_head text NOT NULL CHECK(successor_head='20260828410000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='ede47069d6c67c0918be55cf11ec98d1532c127e9a3056546309328a7edd2cf3'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_acceptance_uid_parity_history_719 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_acceptance_uid_parity_history_719 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_acceptance_uid_parity_history_719 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_acceptance_uid_parity_history_immutable_719() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_719_ACCEPTANCE_UID_PARITY_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_acceptance_uid_parity_history_immutable_719() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_acceptance_uid_parity_history_immutable_719 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_acceptance_uid_parity_history_719 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_acceptance_uid_parity_history_immutable_719();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 old:=$old$if (exists(select 1 from public.pdc_agentic_email_context_receipts_502 q where q.context_receipt_id=v_plan.context_receipt_id and q.actor_id=auth.uid() and q.canonical_evidence->'acceptance_context_projection'->>'contract_version'='pdc-acceptance-context-projection-703.1')) then null;
  elsif v_row.request is distinct from v_request then$old$;
 new:=$new$if (p_action->'source_binding'->>'provider_uid'~'^imap_uid:[0-9]+$' and substring(p_action->'source_binding'->>'provider_uid' from 10)::bigint>=515) then null;
  elsif v_row.request is distinct from v_request then$new$;
 IF before_sha<>'ede47069d6c67c0918be55cf11ec98d1532c127e9a3056546309328a7edd2cf3' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_719_UID_PARITY_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_acceptance_uid_parity_history_719(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-719-agentic-acceptance-uid-parity|forward','UTF8'),'sha256'),'hex'),'agentic_acceptance_uid_parity','20260828400000','20260828410000',before_sha,after_sha,'Switch only the exact synthetic UID>=515 acceptance path to the already-proven immutable action flow; the 684 wrapper remains the actor/gateway/release/planner/trust/fixture authority',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_acceptance_uid_parity_history_719)<>1 OR position($needle$p_action->'source_binding'->>'provider_uid'$needle$ IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_719_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828410000','719_agentic_acceptance_uid_parity',ARRAY['Exact 718 predecessor and strict execute hash guard','Use exact synthetic provider UID>=515 as the already-authorized acceptance parity switch','Normal Board/read filters, UID514/task/mailbox/outbound and Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
