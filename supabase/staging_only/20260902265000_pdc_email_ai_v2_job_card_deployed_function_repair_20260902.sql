-- STAGING ONLY 20260902265000: repair the deployed Job Card parity
-- predecessor for the live enum/status and Navision-null-VIN contracts.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260902265000-job-card-deployed-function-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260902264000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260902265000')
     OR to_regprocedure('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260902265000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_email_ai_v2_job_card_deployed_function_repair_history_20260902(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260902264000'), successor_head text NOT NULL CHECK(successor_head='20260902265000'),
  predecessor_hash text NOT NULL, successor_hash text NOT NULL, contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes), mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email), action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_email_ai_v2_job_card_deployed_function_repair_history_20260902 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_job_card_deployed_function_repair_history_20260902 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_job_card_deployed_function_repair_history_20260902 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_ai_v2_job_card_deployed_function_repair_history_immutable_20260902()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_20260902265000_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_email_ai_v2_job_card_deployed_function_repair_history_immutable_20260902 BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_job_card_deployed_function_repair_history_20260902 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_job_card_deployed_function_repair_history_immutable_20260902();
DO $repair$
DECLARE d text; before_hash text; after_hash text; old text; new text;
BEGIN
  SELECT pg_get_functiondef('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)'::regprocedure), encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,before_hash;
  old:=$old$SELECT count(*) INTO v_booking_count FROM public.workshop_bookings b WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status NOT IN('deleted','cancelled');$old$;
  new:=$new$SELECT count(*) INTO v_booking_count FROM public.workshop_bookings b WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL;$new$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902265000_BOOKING_ENUM_ANCHOR_FAILED' USING errcode='55000'; END IF;
  d:=replace(d,old,new);
  old:=$old$(p_vin IS NOT NULL AND public.normalize_vehicle_vin(v_vehicle.vin)<>public.normalize_vehicle_vin(p_vin))$old$;
  new:=$new$(p_vin IS NOT NULL AND v_vehicle.vin IS NOT NULL AND public.normalize_vehicle_vin(v_vehicle.vin)<>public.normalize_vehicle_vin(p_vin))$new$;
  IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_20260902265000_VIN_NULL_ANCHOR_FAILED' USING errcode='55000'; END IF;
  d:=replace(d,old,new); EXECUTE d;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;
  INSERT INTO public.pdc_email_ai_v2_job_card_deployed_function_repair_history_20260902(event_key,predecessor_head,successor_head,predecessor_hash,successor_hash,contract,production_writes,mailbox_contacted,outbound_email,action_rpc_invoked)
  VALUES(encode(extensions.digest(convert_to('pdc-staging-20260902265000-job-card-deployed-function-repair|forward','UTF8'),'sha256'),'hex'),'20260902264000','20260902265000',before_hash,after_hash,'Use the deployed workshop_booking_status enum contract (deleted_at is authoritative) and allow an attachment-attested VIN to bind a canonical Navision vehicle whose legacy VIN column is null; a populated canonical VIN still must match exactly.',false,false,false,false);
END $repair$;
DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)'::regprocedure) INTO d;
 IF (SELECT count(*) FROM public.pdc_email_ai_v2_job_card_deployed_function_repair_history_20260902)<>1 OR position('b.deleted_at IS NULL;' IN d)=0 OR position('v_vehicle.vin IS NOT NULL' IN d)=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_20260902265000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260902265000','pdc_email_ai_v2_job_card_deployed_function_repair_20260902',ARRAY['Repair the deployed canonical Job Card writer for the real workshop booking enum without broadening booking authority','Permit exact attachment VIN evidence to bind a legacy Navision vehicle with a null VIN while preserving strict conflict checks for populated VINs','Record immutable predecessor/successor function hashes and zero Production/mailbox/outbound/action-RPC proof']);
NOTIFY pgrst,'reload schema'; COMMIT;
