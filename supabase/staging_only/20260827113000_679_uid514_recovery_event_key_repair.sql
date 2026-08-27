-- STAGING ONLY 679: separate 677 control history from the first recovery effect.
-- Migration 677 pre-seeded its immutable forward-control history with the same
-- deterministic event key later used by the actual recovery call. This additive
-- repair changes only that key literal, so the exact first enqueue can record
-- one real forward effect and replay it idempotently. No data/evidence is
-- deleted or rewritten; UID514 remains unprocessed during this migration.

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-679-uid514-recovery-event-key-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_enqueue_hash text;
  v_authorize_hash text;
  v_claim_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_enqueue_hash FROM pg_proc p WHERE p.oid='public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_authorize_hash FROM pg_proc p WHERE p.oid='public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_claim_hash FROM pg_proc p WHERE p.oid='public.claim_pdc_uid514_recovery_257(text,integer)'::regprocedure;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827112000' AND name='678_uid514_authorize_attachment_count_repair')<>1
     OR to_regclass('public.pdc_uid514_recovery_event_key_repair_history_679') IS NOT NULL
     OR v_enqueue_hash<>'a9145c49eb36c6db9cc9a697d57f8aa942e9502869711bd897382c63bf3ace86'
     OR v_authorize_hash<>'1c1a0d485659d5b6d614e2c03f7dbf93f9f87c39de1f9aa63b23ac9576718a82'
     OR v_claim_hash<>'fe30c884f0db02f7d31d629e12af0e29bcdd2505a6451b2873f05364c5727e69'
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_controls_677 WHERE singleton AND enabled AND recovery_event_id=25751401 AND mailbox_uidvalidity=1 AND mailbox_uid=514 AND parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_history_677 WHERE event_kind='forward_uid514_recovery')<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0
  THEN RAISE EXCEPTION 'PDC_679_EXACT_678_OR_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_uid514_recovery_event_key_repair_history_679(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind='forward_recovery_event_key_repair'),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260827112000'),
  successor_head text NOT NULL CHECK(successor_head='20260827114000'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  jwt_role text NOT NULL CHECK(jwt_role='authenticated'),
  server_application_role text NOT NULL CHECK(server_application_role='importer'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'),
  planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'),
  trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'),
  recovery_event_id integer NOT NULL CHECK(recovery_event_id=25751401),
  parent_source_hash text NOT NULL CHECK(parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280'),
  predecessor_enqueue_sha256 text NOT NULL CHECK(predecessor_enqueue_sha256='a9145c49eb36c6db9cc9a697d57f8aa942e9502869711bd897382c63bf3ace86'),
  successor_enqueue_sha256 text NOT NULL CHECK(successor_enqueue_sha256~'^[a-f0-9]{64}$'),
  before_definition text NOT NULL,
  after_definition text NOT NULL,
  observed_mime_part_count integer NOT NULL CHECK(observed_mime_part_count=7),
  retained_authenticated_attachment_count integer NOT NULL CHECK(retained_authenticated_attachment_count=4),
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_uid514_recovery_event_key_repair_history_immutable_679()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_679_UID514_EVENT_KEY_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_uid514_recovery_event_key_repair_history_immutable_679
BEFORE UPDATE OR DELETE ON public.pdc_uid514_recovery_event_key_repair_history_679
FOR EACH ROW EXECUTE FUNCTION public.pdc_uid514_recovery_event_key_repair_history_immutable_679();
ALTER TABLE public.pdc_uid514_recovery_event_key_repair_history_679 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_recovery_event_key_repair_history_679 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_recovery_event_key_repair_history_679 FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $repair$
DECLARE
  v_before text;
  v_after text;
  v_sha text;
  v_event_key text:=encode(extensions.digest(convert_to('pdc-staging-679-uid514-recovery-event-key-repair|forward|25751401','UTF8'),'sha256'),'hex');
  v_old text:='pdc-staging-677-uid514-exact-recovery-successor|forward|25751401';
  v_new text:='pdc-staging-677-uid514-exact-recovery-successor|recovery|25751401';
BEGIN
  SELECT pg_get_functiondef('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure) INTO v_before;
  IF position(v_old IN v_before)=0 THEN RAISE EXCEPTION 'PDC_679_ENQUEUE_EVENT_KEY_SOURCE_DRIFT' USING errcode='55000'; END IF;
  v_after:=replace(v_before,v_old,v_new);
  EXECUTE v_after;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_sha FROM pg_proc p WHERE p.oid='public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure;
  INSERT INTO public.pdc_uid514_recovery_event_key_repair_history_679(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,recovery_event_id,parent_source_hash,predecessor_enqueue_sha256,successor_enqueue_sha256,before_definition,after_definition,observed_mime_part_count,retained_authenticated_attachment_count,task_enabled,mailbox_contacted,uid514_processed,production_writes)
  VALUES(v_event_key,'forward_recovery_event_key_repair','20260827112000','20260827114000','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',25751401,'440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280','a9145c49eb36c6db9cc9a697d57f8aa942e9502869711bd897382c63bf3ace86',v_sha,v_before,v_after,7,4,false,false,false,false);
END
$repair$;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_uid514_recovery_event_key_repair_history_679 WHERE event_kind='forward_recovery_event_key_repair')<>1
     OR position('pdc-staging-677-uid514-exact-recovery-successor|recovery|25751401' IN pg_get_functiondef('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure))=0
     OR position('pdc-staging-677-uid514-exact-recovery-successor|forward|25751401' IN pg_get_functiondef('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure))>0
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0
     OR (SELECT count(*) FROM public.pdc_uid514_attachment_selection_673 WHERE recovery_event_id=25751401)<>0
     OR (SELECT count(*) FROM public.vehicles WHERE stock_number='13016925')<>0
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_679_UID514_EVENT_KEY_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827114000','679_uid514_recovery_event_key_repair',ARRAY[
 'Require exact applied 678 predecessor and current 677 runtime/authorize/claim function anchors',
 'Separate the immutable 677 forward-control history key from the exact first UID514 recovery effect key',
 'Preserve one exact enqueue/authorization effect and idempotent replay without deleting or rewriting any evidence',
 'Keep exact actor/binding/mailbox/planner/trust, seven MIME parts/four PDFs, task disabled, UID514 unprocessed and Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
