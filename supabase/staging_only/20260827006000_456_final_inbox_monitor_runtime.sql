-- STAGING ONLY 456: bind the final tested Inbox-action runtime bytes.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-456-final-inbox-runtime',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827005000' AND name='455_inbox_review_and_archive_runtime')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827005000')
 OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE user_id='69846ef4-a74c-4569-9e35-376cf0837888'::uuid AND active AND revoked_at IS NULL)
 OR NOT EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE mailbox_key='pdc_pmb_email' AND active AND test_mode)
 THEN RAISE EXCEPTION 'PDC_456_STAGING_HEAD_OR_MONITOR_MISMATCH' USING errcode='55000';END IF;
END $pre$;
CREATE TABLE public.pdc_email_monitor_final_runtime_receipts_456(
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),project_ref text NOT NULL CHECK(project_ref='cdsmnqxtyyoeoznmbidd'),
 actor_id uuid NOT NULL CHECK(actor_id='69846ef4-a74c-4569-9e35-376cf0837888'::uuid),
 monitor_sha256 text NOT NULL CHECK(monitor_sha256~'^[a-f0-9]{64}$'),bridge_sha256 text NOT NULL CHECK(bridge_sha256~'^[a-f0-9]{64}$'),
 processor_sha256 text NOT NULL CHECK(processor_sha256~'^[a-f0-9]{64}$'),manifest_sha256 text NOT NULL CHECK(manifest_sha256~'^[a-f0-9]{64}$'),
 terminal_archive_policy text NOT NULL CHECK(terminal_archive_policy='archive only complete, duplicate or irrelevant terminal outcomes; review and status-only remain in Inbox'),
 unsupported_attachment_policy text NOT NULL CHECK(unsupported_attachment_policy='retain as failed evidence for review'),
 idle_replay_policy text NOT NULL CHECK(idle_replay_policy='bound pending Inbox items are not re-enqueued every cycle'),
 production_untouched boolean NOT NULL CHECK(production_untouched),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
REVOKE ALL ON public.pdc_email_monitor_final_runtime_receipts_456 FROM public,anon,authenticated,service_role;
CREATE FUNCTION public.pdc_email_monitor_final_runtime_immutable_456() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'PDC_456_RUNTIME_RECEIPT_IMMUTABLE' USING errcode='55000';END $$;
REVOKE ALL ON FUNCTION public.pdc_email_monitor_final_runtime_immutable_456() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_monitor_final_runtime_immutable_456 BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_final_runtime_receipts_456 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_final_runtime_immutable_456();
INSERT INTO public.pdc_email_monitor_final_runtime_receipts_456(project_ref,actor_id,monitor_sha256,bridge_sha256,processor_sha256,manifest_sha256,terminal_archive_policy,unsupported_attachment_policy,idle_replay_policy,production_untouched)
VALUES('cdsmnqxtyyoeoznmbidd','69846ef4-a74c-4569-9e35-376cf0837888',
 '8c7556de9c4cbc2a0b5bf34ceca430e9c7f9426405b067b3df338805ff6d54a8','b12a2a9b8d601cac4e66b3d54930807860f5fa54f6c60e1878cf38f9c033860d',
 '89de3a94ef6d8ec4840f60017d40747b76f2080e316b9eeb28a105b33a1b01a3','1500c7e0f4753705290784031ba07adf4ef03cd6025e779028b437030b53cf74',
 'archive only complete, duplicate or irrelevant terminal outcomes; review and status-only remain in Inbox','retain as failed evidence for review','bound pending Inbox items are not re-enqueued every cycle',true);
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_email_monitor_final_runtime_receipts_456)<>1
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.pdc_email_monitor_final_runtime_receipts_456'::regclass AND tgname='pdc_email_monitor_final_runtime_immutable_456' AND NOT tgisinternal)
 OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND enabled AND automatic_rule_application AND automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
 THEN RAISE EXCEPTION 'PDC_456_POSTCONDITION_FAILED' USING errcode='55000';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827006000','456_final_inbox_monitor_runtime',ARRAY[
 'Final tested runtime hashes bind terminal-only Gmail Inbox archive and pending-review retention',
 'Unsupported attachments remain retained review evidence and status-only emails no longer degrade the worker',
 'Idle replay is silent and idempotent; outbound email disabled; Production untouched'
]);
COMMIT;
