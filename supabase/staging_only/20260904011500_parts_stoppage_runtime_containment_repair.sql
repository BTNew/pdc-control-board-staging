-- STAGING ONLY: repair Parts STOPPAGE runtime containment for the active monitor configuration.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904011500-parts-stoppage-runtime-containment',0));

CREATE TABLE public.pdc_parts_stoppage_verification_cleanup_20260904(
  cleanup_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_key text NOT NULL CHECK(task_key='t_fd63d897'),
  vehicle_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  actor_email text NOT NULL CHECK(actor_email='functional.pdc.staging@example.com'),
  before_vehicle jsonb NOT NULL CHECK(jsonb_typeof(before_vehicle)='object'),
  before_parts jsonb NOT NULL CHECK(jsonb_typeof(before_parts)='array'),
  receipt_evidence jsonb NOT NULL CHECK(jsonb_typeof(receipt_evidence)='array' AND jsonb_array_length(receipt_evidence)>0),
  audit_evidence jsonb NOT NULL CHECK(jsonb_typeof(audit_evidence)='array' AND jsonb_array_length(audit_evidence)>0),
  cleanup_reason text NOT NULL CHECK(length(btrim(cleanup_reason))>=20),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_parts_stoppage_verification_cleanup_20260904 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_parts_stoppage_verification_cleanup_20260904 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_parts_stoppage_verification_cleanup_20260904 FROM public,anon,authenticated,service_role;
CREATE FUNCTION public.pdc_parts_stoppage_verification_cleanup_immutable_20260904()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$
BEGIN RAISE EXCEPTION 'PDC_PARTS_STOPPAGE_VERIFICATION_CLEANUP_IMMUTABLE' USING errcode='55000'; END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_parts_stoppage_verification_cleanup_immutable_20260904() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_parts_stoppage_verification_cleanup_immutable_20260904
BEFORE UPDATE OR DELETE ON public.pdc_parts_stoppage_verification_cleanup_20260904
FOR EACH ROW EXECUTE FUNCTION public.pdc_parts_stoppage_verification_cleanup_immutable_20260904();

DO $repair$
DECLARE
  definition text;
  definition_sha256 text;
  repaired text;
  receipt_count_before bigint;
  audit_count_before bigint;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT jsonb_build_array(version,name) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM jsonb_build_array('20260904011400','pdc14_location_replay_partial_cleanup_identifier_repair')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904011500')
     OR to_regprocedure('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)') IS NULL
     OR (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure)<>'postgres'
     OR to_regclass('public.pdc_parts_stoppage_receipts_376') IS NULL THEN
    RAISE EXCEPTION 'PDC_20260904011500_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
  END IF;

  SELECT pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),
         encode(extensions.digest(convert_to(pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
         (SELECT count(*) FROM public.pdc_parts_stoppage_receipts_376),
         (SELECT count(*) FROM public.audit_events)
    INTO definition,definition_sha256,receipt_count_before,audit_count_before;

  IF definition_sha256<>'d2a2e96c38633fec639a3cd6b2ef0adb18d96ff3640a2f08ef19feb7c19ea82f' THEN
    RAISE EXCEPTION 'PDC_20260904011500_EXACT_FUNCTION_MISMATCH:%',definition_sha256 USING errcode='55000';
  END IF;

  repaired:=replace(definition,'OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)','');
  repaired:=replace(repaired,'OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)','');

  IF repaired=definition
     OR position('EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)' in repaired)>0
     OR position('EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)' in repaired)>0
     OR position('NOT public.pdc_monitor_staging_guard()' in repaired)=0
     OR position('v_notifications_after<>v_notifications_before' in repaired)=0
     OR position('PDC_376_UNAUTHORIZED' in repaired)=0
     OR position('PDC_376_IDEMPOTENCY_PAYLOAD_MISMATCH' in repaired)=0
     OR position('PDC_376_REPLAY_CONTAINMENT_MISMATCH' in repaired)=0
     OR position('PDC_376_POSTCONDITION_FAILED' in repaired)=0 THEN
    RAISE EXCEPTION 'PDC_20260904011500_REPAIR_NOT_EXACT' USING errcode='55000';
  END IF;

  EXECUTE repaired;

  -- Preserve SECURITY DEFINER containment and the explicit writer ACL.
  REVOKE ALL ON FUNCTION public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text) FROM public,anon,authenticated,service_role;
  GRANT EXECUTE ON FUNCTION public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text) TO authenticated;

  IF (SELECT count(*) FROM public.pdc_parts_stoppage_receipts_376)<>receipt_count_before
     OR (SELECT count(*) FROM public.audit_events)<>audit_count_before THEN
    RAISE EXCEPTION 'PDC_20260904011500_APPEND_ONLY_HISTORY_CHANGED' USING errcode='55000';
  END IF;
END $repair$;

DO $post$
DECLARE
  definition text;
BEGIN
  SELECT pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure)
    INTO definition;
  IF position('EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)' in definition)>0
     OR position('EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)' in definition)>0
     OR position('NOT public.pdc_monitor_staging_guard()' in definition)=0
     OR position('v_notifications_after<>v_notifications_before' in definition)=0
     OR (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure)<>'postgres'
     OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure)
     OR (SELECT p.proconfig FROM pg_proc p WHERE p.oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure)
        IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, extensions','statement_timeout=90s']::text[]
     OR has_function_privilege('public','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','EXECUTE')
     OR has_function_privilege('service_role','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','EXECUTE')
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.pdc_parts_stoppage_receipts_376'::regclass)
     OR NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_parts_stoppage_verification_cleanup_20260904'::regclass)
     OR has_table_privilege('authenticated','public.pdc_parts_stoppage_verification_cleanup_20260904','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('public','public.pdc_parts_stoppage_receipts_376','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon','public.pdc_parts_stoppage_receipts_376','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated','public.pdc_parts_stoppage_receipts_376','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('service_role','public.pdc_parts_stoppage_receipts_376','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'PDC_20260904011500_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904011500','parts_stoppage_runtime_containment_repair',ARRAY[
  'Exact-SHA repair removes obsolete active-mailbox and active-writer rejection from the Parts STOPPAGE runtime path',
  'Monitor staging guard and zero notification-count delta containment remain mandatory',
  'Authorization lifecycle expected-version idempotency replay audit receipt RLS and explicit EXECUTE ACL contracts remain unchanged',
  'Forced-RLS append-only bounded verification cleanup evidence permits zero mutable Auth role vehicle work and Parts rows'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
