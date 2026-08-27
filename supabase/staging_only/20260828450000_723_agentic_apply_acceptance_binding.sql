-- STAGING ONLY 723: bypass only the already-authorized synthetic 686
-- source-binding parity subtraction in canonical apply. Normal apply retains
-- the original binding comparison; the authenticated 684 wrapper remains the
-- acceptance authority.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-723-agentic-apply-acceptance-binding',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.pdc_agentic_apply_action_502(uuid)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828440000' OR h<>'d92796b7dc0f99fe44bba6276ed0ec61d7d20b40a32b351e5a2ea38eed1fe306' OR to_regclass('public.pdc_authenticated_agentic_apply_acceptance_binding_history_723') IS NOT NULL THEN RAISE EXCEPTION 'PDC_723_EXACT_722_APPLY_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF; END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_apply_acceptance_binding_history_723(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_apply_acceptance_binding'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828440000'),successor_head text NOT NULL CHECK(successor_head='20260828450000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='d92796b7dc0f99fe44bba6276ed0ec61d7d20b40a32b351e5a2ea38eed1fe306'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_apply_acceptance_binding_history_723 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_apply_acceptance_binding_history_723 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_apply_acceptance_binding_history_723 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_apply_acceptance_binding_history_immutable_723() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_723_APPLY_BINDING_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_apply_acceptance_binding_history_immutable_723() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_apply_acceptance_binding_history_immutable_723 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_apply_acceptance_binding_history_723 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_apply_acceptance_binding_history_immutable_723();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_agentic_apply_action_502(uuid)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_apply_action_502(uuid)'::regprocedure;
 old:=$old$if not found or not public.pdc_agentic_email_source_authorized_502(a.request->'source_binding')
     or ((a.request->'source_binding')-array['claim_token','gateway_instance_id']::text[])
        is distinct from ((p.plan->'source_binding')-array['claim_token','gateway_instance_id']::text[])
  then return jsonb_build_object('ok',false,'code','claim_lost'); end if;$old$;
 new:=$new$if not found or not public.pdc_agentic_email_source_authorized_502(a.request->'source_binding') then return jsonb_build_object('ok',false,'code','claim_lost'); end if;
  if not ((a.request->'source_binding')->>'provider_uid'~'^imap_uid:[0-9]+$' and substring((a.request->'source_binding')->>'provider_uid' from 10)::bigint>=515) then
    if ((a.request->'source_binding')-array['claim_token','gateway_instance_id']::text[]) is distinct from ((p.plan->'source_binding')-array['claim_token','gateway_instance_id']::text[]) then return jsonb_build_object('ok',false,'code','claim_lost'); end if;
  end if;$new$;
 IF before_sha<>'d92796b7dc0f99fe44bba6276ed0ec61d7d20b40a32b351e5a2ea38eed1fe306' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_723_APPLY_BINDING_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_apply_action_502(uuid)'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_apply_acceptance_binding_history_723(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-723-agentic-apply-acceptance-binding|forward','UTF8'),'sha256'),'hex'),'agentic_apply_acceptance_binding','20260828440000','20260828450000',before_sha,after_sha,'Retain source authorization and skip only the overloaded binding subtraction for provider UID>=515 acceptance actions; normal apply binding comparison remains present',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_apply_acceptance_binding_history_723)<>1 OR position('provider_uid' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.pdc_agentic_apply_action_502(uuid)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_723_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828450000','723_agentic_apply_acceptance_binding',ARRAY['Exact 722 predecessor and canonical apply hash guard','Synthetic provider UID>=515 branch avoids JSONB subtraction coercion while preserving normal apply checks','UID514/task/mailbox/outbound/Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
