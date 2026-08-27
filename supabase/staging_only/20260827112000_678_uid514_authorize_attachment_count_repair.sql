-- STAGING ONLY 678: repair the exact UID514 authorization cardinality.
-- The already-applied 677 recovery successor correctly provides the narrow
-- enqueue capability but exposed a pre-existing 673/670 mismatch: the
-- authorization function inserted attachment_count=4 while the seven-part
-- table contract requires attachment_count=7. This append-only repair changes
-- only that exact literal under an exact source-hash guard. UID514 remains
-- unprocessed; no vehicle, mailbox, task, email or Production action occurs.
--
-- Exact predecessor/runtime anchors:
--   677 migration source: ad921292bdafb3bfc25413df8c1faa803442f0c645799aac3cd42af76b0da85f
--   676 trigger p.prosrc after 677: 0f93e7bc36549e14f4a5231e57a2a23b1168f6d2a32d3f4678da811cdca77955
--   676 claim p.prosrc after 677: fe30c884f0db02f7d31d629e12af0e29bcdd2505a6451b2873f05364c5727e69
--   enqueue p.prosrc: eb91ff09afac2c66d2abf461b57dd9c8d1c6fc5aac13843d74c0ce192b8dd88a
--   authorization p.prosrc: ef925445ee7ccfd3dbfeba4c2e437e4c49e477269137ac5bbd1e744d9cf56962
--   674 active scope p.prosrc: 4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629
--   674 runtime helper p.prosrc: de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-678-uid514-authorization-cardinality-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_trigger_hash text;
  v_claim_hash text;
  v_enqueue_hash text;
  v_authorize_hash text;
  v_scope_hash text;
  v_runtime_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_trigger_hash FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_claim_hash FROM pg_proc p WHERE p.oid='public.claim_pdc_uid514_recovery_257(text,integer)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_enqueue_hash FROM pg_proc p WHERE p.oid='public.enqueue_pdc_email_intake(jsonb,jsonb)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_authorize_hash FROM pg_proc p WHERE p.oid='public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_scope_hash FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_active_scope_674(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_runtime_hash FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_runtime_authorized_502(text)'::regprocedure;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827111000' AND name='677_uid514_exact_recovery_successor')<>1
     OR to_regclass('public.pdc_uid514_recovery_authorize_repair_history_678') IS NOT NULL
     OR v_trigger_hash<>'0f93e7bc36549e14f4a5231e57a2a23b1168f6d2a32d3f4678da811cdca77955'
     OR v_claim_hash<>'fe30c884f0db02f7d31d629e12af0e29bcdd2505a6451b2873f05364c5727e69'
     OR v_enqueue_hash<>'eb91ff09afac2c66d2abf461b57dd9c8d1c6fc5aac13843d74c0ce192b8dd88a'
     OR v_authorize_hash<>'ef925445ee7ccfd3dbfeba4c2e437e4c49e477269137ac5bbd1e744d9cf56962'
     OR v_scope_hash<>'4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629'
     OR v_runtime_hash<>'de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351'
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_controls_677 WHERE singleton AND enabled AND parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' AND mailbox_uidvalidity=1 AND mailbox_uid=514 AND recovery_event_id=25751401 AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_history_677 WHERE event_kind='forward_uid514_recovery')<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0
  THEN RAISE EXCEPTION 'PDC_678_EXACT_677_OR_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_uid514_recovery_authorize_repair_history_678(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind='forward_authorize_attachment_count_repair'),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260827111000'),
  successor_head text NOT NULL CHECK(successor_head='20260827112000'),
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
  parent_source_hash text NOT NULL CHECK(parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280'),
  predecessor_authorize_sha256 text NOT NULL CHECK(predecessor_authorize_sha256='ef925445ee7ccfd3dbfeba4c2e437e4c49e477269137ac5bbd1e744d9cf56962'),
  successor_authorize_sha256 text NOT NULL CHECK(successor_authorize_sha256~'^[a-f0-9]{64}$'),
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
CREATE FUNCTION public.pdc_uid514_recovery_authorize_repair_history_immutable_678()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_678_UID514_AUTHORIZE_REPAIR_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_uid514_recovery_authorize_repair_history_immutable_678
BEFORE UPDATE OR DELETE ON public.pdc_uid514_recovery_authorize_repair_history_678
FOR EACH ROW EXECUTE FUNCTION public.pdc_uid514_recovery_authorize_repair_history_immutable_678();
ALTER TABLE public.pdc_uid514_recovery_authorize_repair_history_678 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_recovery_authorize_repair_history_678 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_recovery_authorize_repair_history_678 FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $repair$
DECLARE
  v_before text;
  v_after text;
  v_needle text:=E',\'13016925\',\'J139125482\',4)';
  v_event_key text:=encode(extensions.digest(convert_to('pdc-staging-678-uid514-authorization-cardinality-repair|forward|25751401','UTF8'),'sha256'),'hex');
  v_sha text;
BEGIN
  SELECT pg_get_functiondef('public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure) INTO v_before;
  IF position(v_needle IN v_before)=0 THEN RAISE EXCEPTION 'PDC_678_AUTHORIZE_SOURCE_DRIFT' USING errcode='55000'; END IF;
  v_after:=replace(v_before,v_needle,E',\'13016925\',\'J139125482\',7)');
  EXECUTE v_after;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_sha FROM pg_proc p WHERE p.oid='public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure;
  INSERT INTO public.pdc_uid514_recovery_authorize_repair_history_678(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,parent_source_hash,predecessor_authorize_sha256,successor_authorize_sha256,before_definition,after_definition,observed_mime_part_count,retained_authenticated_attachment_count,task_enabled,mailbox_contacted,uid514_processed,production_writes)
  VALUES(v_event_key,'forward_authorize_attachment_count_repair','20260827111000','20260827112000','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227','440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280','ef925445ee7ccfd3dbfeba4c2e437e4c49e477269137ac5bbd1e744d9cf56962',v_sha,v_before,v_after,7,4,false,false,false,false);
END
$repair$;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_uid514_recovery_authorize_repair_history_678 WHERE event_kind='forward_authorize_attachment_count_repair')<>1
     OR position(',''13016925'',''J139125482'',7)' IN pg_get_functiondef('public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure))=0
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0
     OR (SELECT count(*) FROM public.pdc_uid514_attachment_selection_673 WHERE recovery_event_id=25751401)<>0
     OR (SELECT count(*) FROM public.vehicles WHERE stock_number='13016925')<>0
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_678_UID514_AUTHORIZE_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827112000','678_uid514_authorize_attachment_count_repair',ARRAY[
 'Require exact applied 677 recovery successor and exact current 674 scope/runtime, trigger, claim, enqueue and authorization hashes',
 'Repair only the existing UID514 authorization literal from attachment_count=4 to the seven-part contract value 7',
 'Record immutable forced-RLS repair history with predecessor and successor authorization function hashes',
 'Keep exact actor/binding/mailbox/planner/trust, UID514 intake/authorization/selection/vehicle counts at zero, task disabled and Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
