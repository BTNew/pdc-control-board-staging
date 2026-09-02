-- STAGING ONLY 20260902266000: validate conflicting source-bound
-- Job Card requests before returning the exact replay response.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260902266000-job-card-replay-validation-order',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260902265000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260902266000')
     OR to_regprocedure('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260902266000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_email_ai_v2_job_card_replay_validation_history_20260902(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260902265000'), successor_head text NOT NULL CHECK(successor_head='20260902266000'),
  predecessor_hash text NOT NULL, successor_hash text NOT NULL, contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes), mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email), action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_email_ai_v2_job_card_replay_validation_history_20260902 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_job_card_replay_validation_history_20260902 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_job_card_replay_validation_history_20260902 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_job_card_replay_validation_history_immutable_20260902()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_20260902266000_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_job_card_replay_validation_history_immutable_20260902 BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_job_card_replay_validation_history_20260902 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_job_card_replay_validation_history_immutable_20260902();
DO $repair$
DECLARE d text; before_hash text; after_hash text; old text; new text;
BEGIN
  SELECT pg_get_functiondef('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)'::regprocedure), encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,before_hash;
  old:=$old$  SELECT * INTO v_existing FROM public.pdc_email_ai_v2_job_card_parity_corrections_20260902 WHERE source_receipt_id=p_source_receipt_id FOR SHARE;
  IF FOUND THEN
    IF v_existing.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict'); END IF;
    RETURN v_existing.response||jsonb_build_object('correction_replay',true);
  END IF;
$old$;
  new:=$new$  -- Exact replay is checked after source, identity, attachment, provider,
  -- operation and booking validation so conflicting retries fail closed with
  -- their precise reason instead of being hidden by the replay row.
$new$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902266000_REPLAY_BLOCK_ANCHOR_FAILED' USING errcode='55000'; END IF;
  d:=replace(d,old,new);
  old:=$old$  v_response:=jsonb_build_object('ok',true,'code',case when v_before->>'job_card_number' IS NULL THEN 'job_card_parity_corrected' ELSE 'job_card_already_correct' END,$old$;
  new:=$new$  SELECT * INTO v_existing FROM public.pdc_email_ai_v2_job_card_parity_corrections_20260902 WHERE source_receipt_id=p_source_receipt_id FOR SHARE;
  IF FOUND THEN
    IF v_existing.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict'); END IF;
    RETURN v_existing.response||jsonb_build_object('correction_replay',true);
  END IF;
  v_response:=jsonb_build_object('ok',true,'code',case when v_before->>'job_card_number' IS NULL THEN 'job_card_parity_corrected' ELSE 'job_card_already_correct' END,$new$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902266000_REPLAY_INSERT_ANCHOR_FAILED' USING errcode='55000'; END IF;
  d:=replace(d,old,new); EXECUTE d;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;
  INSERT INTO public.pdc_email_ai_v2_job_card_replay_validation_history_20260902(event_key,predecessor_head,successor_head,predecessor_hash,successor_hash,contract,production_writes,mailbox_contacted,outbound_email,action_rpc_invoked)
  VALUES(encode(extensions.digest(convert_to('pdc-staging-20260902266000-job-card-replay-validation-order|forward','UTF8'),'sha256'),'hex'),'20260902265000','20260902266000',before_hash,after_hash,'Validate source, identity, attachment, provider, operation, lifecycle and booking bindings before exact correction replay; conflicting retries remain fail closed.',false,false,false,false);
END $repair$;
DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)'::regprocedure) INTO d;
 IF (SELECT count(*) FROM public.pdc_email_ai_v2_job_card_replay_validation_history_20260902)<>1 OR position('conflicting retries fail closed' IN d)=0 OR position('v_existing.request_hash<>v_request_hash' IN d)=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_20260902266000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260902266000','pdc_email_ai_v2_job_card_replay_validation_order_20260902',ARRAY['Exact replay is returned only after validating the source, identity, attachment, provider observation, operation and zero-booking contract','Wrong Stock/VIN/source/attachment and protected Job Card retries remain fail closed with precise bounded errors','Immutable predecessor/successor hash history and zero Production/mailbox/outbound/action-RPC proof are recorded']);
NOTIFY pgrst,'reload schema';
COMMIT;
