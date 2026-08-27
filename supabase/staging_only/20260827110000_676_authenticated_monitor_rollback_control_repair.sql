-- STAGING ONLY 676: permit the already-reviewed guarded rollback controls
-- to transition enabled=false. The original 674/675 forward controls used a
-- one-way CHECK(enabled), which made their explicit rollback functions
-- unreachable. This additive repair removes only those two control-state
-- checks; it does not alter mailbox data, RLS/ACLs, runtime scope, task state,
-- UID514, vehicles, email or Production.
-- Exact predecessor/runtime anchors:
--   675 trigger p.prosrc: 9fe5f8bb31e15b9047a6c6d9304af2cfab19f9d33ec6161dcf31fbcf92367b43
--   674 scope p.prosrc: 4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629
--   674 runtime helper p.prosrc: de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351
--   sealed .44 runner: 52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd
--   external adapter: a14a2d2b4ad3514a3367246ae9b8705762eda41987f9491980594e9c62e7d036

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-676-authenticated-monitor-rollback-control-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_scope_hash text;
  v_runtime_hash text;
  v_trigger_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_scope_hash FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_active_scope_674(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_runtime_hash FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_runtime_authorized_502(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_trigger_hash FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827109000' AND name='675_authenticated_monitor_enqueue_trigger_compatibility')<>1
     OR to_regclass('public.pdc_email_monitor_authenticated_rollback_control_repair_676') IS NOT NULL
     OR v_scope_hash<>'4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629'
     OR v_runtime_hash<>'de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351'
     OR v_trigger_hash<>'9fe5f8bb31e15b9047a6c6d9304af2cfab19f9d33ec6161dcf31fbcf92367b43'
     OR (SELECT count(*) FROM pg_constraint WHERE conrelid='public.pdc_email_monitor_authenticated_mailbox_activation_controls_674'::regclass AND conname='pdc_email_monitor_authenticated_mailbox_activatio_enabled_check')<>1
     OR (SELECT count(*) FROM pg_constraint WHERE conrelid='public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675'::regclass AND conname='pdc_email_monitor_authenticated_enqueue_trigger_c_enabled_check')<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
  THEN RAISE EXCEPTION 'PDC_676_EXACT_675_PREDECESSOR_OR_ROLLBACK_CONTROL_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

ALTER TABLE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674
  DROP CONSTRAINT pdc_email_monitor_authenticated_mailbox_activatio_enabled_check;
ALTER TABLE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675
  DROP CONSTRAINT pdc_email_monitor_authenticated_enqueue_trigger_c_enabled_check;

CREATE TABLE public.pdc_email_monitor_authenticated_rollback_control_repair_676(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260827109000'),
  successor_head text NOT NULL CHECK(successor_head='20260827110000'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'),
  mailbox_id uuid NOT NULL CHECK(mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'),
  removed_674_enabled_check boolean NOT NULL DEFAULT true CHECK(removed_674_enabled_check),
  removed_675_enabled_check boolean NOT NULL DEFAULT true CHECK(removed_675_enabled_check),
  task_enabled boolean NOT NULL DEFAULT false CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL DEFAULT false CHECK(NOT uid514_processed),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_monitor_authenticated_rollback_control_repair_676 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_rollback_control_repair_676 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_rollback_control_repair_676 FROM public,anon,authenticated,service_role,pdc_email_monitor;
INSERT INTO public.pdc_email_monitor_authenticated_rollback_control_repair_676(predecessor_head,successor_head,actor_id,actor_email,gateway_instance_id,release_name,source_sha,manifest_sha256,mailbox_id)
VALUES('20260827109000','20260827110000','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','12fe383d-5c1e-5801-96e4-f67cf3e3bb57');

DO $post$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.pdc_email_monitor_authenticated_mailbox_activation_controls_674'::regclass AND conname='pdc_email_monitor_authenticated_mailbox_activatio_enabled_check')
     OR EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675'::regclass AND conname='pdc_email_monitor_authenticated_enqueue_trigger_c_enabled_check')
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_rollback_control_repair_676 WHERE singleton AND removed_674_enabled_check AND removed_675_enabled_check AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_676_ROLLBACK_CONTROL_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827110000','676_authenticated_monitor_rollback_control_repair',ARRAY[
  'Require exact applied 675 predecessor, exact 674 scope/runtime and repaired trigger hashes, staging sentinel and absent Production sentinel',
  'Remove only the enabled=true checks that made the already-defined 674 and 675 guarded rollback functions unreachable',
  'Record the repair in a forced-RLS staging control row while preserving exact actor/mailbox/binding and all immutable histories',
  'Keep task, mailbox fetch/flags, UID514, vehicles, outbound email and Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
