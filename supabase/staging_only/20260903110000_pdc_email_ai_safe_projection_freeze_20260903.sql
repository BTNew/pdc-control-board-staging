-- STAGING-only freeze of the deterministic safe inbox projection dependency.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903110000-email-ai-safe-projection-freeze',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text; v_safe_sha text; v_helper text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  v_safe_sha:=encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_safe_plan(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex');
  v_helper:=pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure);
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR v_head<>'20260903100000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903100000' AND name='pdc_email_ai_actual_jwt_replay_lockdown_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903110000')
     OR v_safe_sha<>'9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086'
     OR position('t.transaction_id IN(' IN v_helper)=0
     OR position('9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086' IN v_helper)=0
  THEN RAISE EXCEPTION 'PDC_20260903110000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_safe_projection_freeze_history_20260903(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260903100000'),
  successor_head text NOT NULL CHECK(successor_head='20260903110000'),
  safe_plan_sha256_before text NOT NULL CHECK(safe_plan_sha256_before='9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086'),
  safe_plan_sha256_after text NOT NULL CHECK(safe_plan_sha256_after='9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086'),
  contract text NOT NULL,
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_safe_projection_freeze_history_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_safe_projection_freeze_history_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_safe_projection_freeze_history_20260903 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_safe_projection_freeze_history_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_safe_projection_freeze_history_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_actual_jwt_replay_parity_history_immutable_20260903();

CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_safe_plan(p_plan jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_result jsonb:=coalesce(p_plan,'{}'::jsonb);v_items jsonb:='[]'::jsonb;v_item jsonb;v_refs jsonb;v_ref text;
BEGIN
 IF jsonb_typeof(v_result)<>'object' THEN RETURN '{}'::jsonb; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_result->'instructions','[]'::jsonb)) LOOP
  v_refs:='[]'::jsonb;
  FOR v_ref IN SELECT value FROM jsonb_array_elements_text(coalesce(v_item->'evidence_refs','[]'::jsonb)) LOOP
   v_refs:=v_refs||jsonb_build_array(case when v_ref ~ '^(correspondence|attachment)-digest:[a-f0-9]{64}$' then v_ref else 'legacy-evidence-reference' end);
  END LOOP;
  v_items:=v_items||jsonb_build_array((v_item-'evidence_refs')||jsonb_build_object('evidence_refs',v_refs));
 END LOOP;
 RETURN jsonb_set(v_result,'{instructions}',v_items,true);
END $function$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_safe_plan(jsonb) FROM public,anon,authenticated,service_role;

DO $record$
DECLARE v_safe_sha text;
BEGIN
  v_safe_sha:=encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_safe_plan(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex');
  IF v_safe_sha<>'9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086' THEN
    RAISE EXCEPTION 'PDC_20260903110000_SAFE_PLAN_SOURCE_HASH_MISMATCH' USING errcode='55000';
  END IF;
  INSERT INTO public.pdc_email_ai_safe_projection_freeze_history_20260903(
    event_key,predecessor_head,successor_head,safe_plan_sha256_before,safe_plan_sha256_after,
    contract,production_writes,mailbox_contacted,outbound_email
  ) VALUES(
    encode(extensions.digest(convert_to('pdc-staging|20260903110000|safe-projection-freeze','UTF8'),'sha256'),'hex'),
    '20260903100000','20260903110000',v_safe_sha,v_safe_sha,
    'Define the exact deterministic redaction-only safe-plan source used by the successor inbox, pin its pg_get_functiondef SHA-256, revoke direct runtime execution, and retain the three-transaction allowlist in the separately ungranted replay helper.',
    false,false,false
  );
END $record$;

DO $post$
DECLARE v_safe_sha text; v_helper text;
BEGIN
  v_safe_sha:=encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_safe_plan(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex');
  v_helper:=pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure);
  IF (SELECT count(*) FROM public.pdc_email_ai_safe_projection_freeze_history_20260903)<>1
     OR v_safe_sha<>'9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086'
     OR position('t.transaction_id IN(' IN v_helper)=0
     OR position('public.pdc_email_ai_successor_safe_plan(t.typed_plan)=p_plan' IN v_helper)=0
     OR has_function_privilege('authenticated','public.pdc_email_ai_successor_safe_plan(jsonb)','execute')
     OR has_function_privilege('service_role','public.pdc_email_ai_successor_safe_plan(jsonb)','execute')
     OR has_function_privilege('anon','public.pdc_email_ai_successor_safe_plan(jsonb)','execute')
     OR has_function_privilege('authenticated','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260903110000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260903110000','pdc_email_ai_safe_projection_freeze_20260903',ARRAY[
  'Define in checked-in migration source the exact deterministic safe-plan projection used by authenticated inbox readback',
  'Pin the canonical pg_get_functiondef SHA-256 before and after replacement and at replay time',
  'Revoke direct safe-plan runtime execution while preserving owner execution through the protected inbox and replay wrappers',
  'Retain the exact three-transaction compatibility allowlist and all immutable source/evidence bindings',
  'Production, mailbox and outbound paths remain untouched and disabled'
 ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
