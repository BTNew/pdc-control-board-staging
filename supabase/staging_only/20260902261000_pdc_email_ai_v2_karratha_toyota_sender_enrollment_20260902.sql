-- STAGING ONLY 20260902261000: enroll only the verified Karratha Toyota
-- sender by exact SHA-256 identity for the retained UID 1:709 PD import.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260902261000-karratha-toyota-sender-enrollment',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]+$')<>20260902260000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version='20260902261000')
     OR to_regclass('public.pdc_monitor_exact_sender_enrollments') IS NULL
     OR EXISTS(SELECT 1 FROM public.pdc_monitor_exact_sender_enrollments
               WHERE sender_sha256='ba17511f3cd912553d2f31744dde2b1be8d916d7dd2c1b94b6d2ce861600f2ae')
  THEN
    RAISE EXCEPTION 'PDC_20260902261000_STAGING_PRECONDITION_FAILED' USING errcode='55000';
  END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_sender_enrollment_history_20260902(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_version text NOT NULL CHECK(predecessor_version='20260902260000'),
  successor_version text NOT NULL CHECK(successor_version='20260902261000'),
  predecessor_hash text NOT NULL CHECK(predecessor_hash~'^[a-f0-9]{64}$'),
  successor_hash text NOT NULL CHECK(successor_hash~'^[a-f0-9]{64}$'),
  enrolled_sender_sha256 text NOT NULL CHECK(enrolled_sender_sha256='ba17511f3cd912553d2f31744dde2b1be8d916d7dd2c1b94b6d2ce861600f2ae'),
  contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_sender_enrollment_history_20260902 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_sender_enrollment_history_20260902 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_v2_sender_enrollment_history_20260902 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.pdc_email_ai_v2_sender_enrollment_history_immutable_20260902()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $immutable$
BEGIN
  RAISE EXCEPTION 'PDC_20260902261000_HISTORY_IMMUTABLE' USING errcode='55000';
END
$immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_sender_enrollment_history_immutable_20260902() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_email_ai_v2_sender_enrollment_history_immutable_20260902
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_sender_enrollment_history_20260902
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_sender_enrollment_history_immutable_20260902();

DO $enroll$
DECLARE
  before_hash text;
  after_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(coalesce(string_agg(
    sender_sha256||'|'||purpose||'|'||active::text,'|' ORDER BY sender_sha256),''),'UTF8'),'sha256'),'hex')
    INTO before_hash
    FROM public.pdc_monitor_exact_sender_enrollments;

  INSERT INTO public.pdc_monitor_exact_sender_enrollments(sender_sha256,purpose,active)
  VALUES('ba17511f3cd912553d2f31744dde2b1be8d916d7dd2c1b94b6d2ce861600f2ae',
         'retained authenticated PD attachment source',true);

  SELECT encode(extensions.digest(convert_to(coalesce(string_agg(
    sender_sha256||'|'||purpose||'|'||active::text,'|' ORDER BY sender_sha256),''),'UTF8'),'sha256'),'hex')
    INTO after_hash
    FROM public.pdc_monitor_exact_sender_enrollments;

  INSERT INTO public.pdc_email_ai_v2_sender_enrollment_history_20260902(
    event_key,predecessor_version,successor_version,predecessor_hash,successor_hash,
    enrolled_sender_sha256,contract,production_writes,mailbox_contacted,outbound_email,action_rpc_invoked)
  VALUES(
    encode(extensions.digest(convert_to(
      'pdc-staging-20260902261000-karratha-toyota-sender-enrollment|forward','UTF8'),
      'sha256'),'hex'),
    '20260902260000','20260902261000',before_hash,after_hash,
    'ba17511f3cd912553d2f31744dde2b1be8d916d7dd2c1b94b6d2ce861600f2ae',
    'Add one exact authenticated sender hash only; preserve the predecessor and table-state hashes; no domain-wide trust or operational import is invoked.',
    false,false,false,false);
END $enroll$;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_monitor_exact_sender_enrollments
      WHERE sender_sha256='ba17511f3cd912553d2f31744dde2b1be8d916d7dd2c1b94b6d2ce861600f2ae'
        AND active)<>1
     OR (SELECT count(*) FROM public.pdc_email_ai_v2_sender_enrollment_history_20260902)<>1
     OR NOT EXISTS(SELECT 1 FROM pg_trigger
                   WHERE tgrelid=to_regclass('public.pdc_email_ai_v2_sender_enrollment_history_20260902')
                     AND tgname='pdc_email_ai_v2_sender_enrollment_history_immutable_20260902'
                     AND NOT tgisinternal AND tgenabled<>'D')
     OR has_table_privilege('public','public.pdc_email_ai_v2_sender_enrollment_history_20260902','SELECT')
     OR has_table_privilege('anon','public.pdc_email_ai_v2_sender_enrollment_history_20260902','SELECT')
     OR has_table_privilege('authenticated','public.pdc_email_ai_v2_sender_enrollment_history_20260902','SELECT')
     OR has_table_privilege('service_role','public.pdc_email_ai_v2_sender_enrollment_history_20260902','SELECT')
     OR has_table_privilege('pdc_email_monitor','public.pdc_email_ai_v2_sender_enrollment_history_20260902','SELECT')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN
    RAISE EXCEPTION 'PDC_20260902261000_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES(
  '20260902261000',
  'pdc_email_ai_v2_karratha_toyota_sender_enrollment_20260902',
  ARRAY[
    'Add only the exact SHA-256 enrollment for the verified retained sender required by UID 1:709',
    'Preserve predecessor and table-state hashes in an immutable forced-RLS history row',
    'Keep domain-wide trust, direct table grants, Production objects, mailbox mutation, outbound email and action RPC invocation absent'
  ]);
NOTIFY pgrst,'reload schema';
COMMIT;
