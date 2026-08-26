-- STAGING ONLY 467: bind the reset Inbox fence to direct read-only Gmail cutoff evidence.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-467-mailbox-cutoff-correction',0));
DO $guard$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827016000' AND name='466_fresh_import_full_operational_reset')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827016000')
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_replay_fences_466 WHERE fence_key='email:Inbox' AND uidvalidity=1 AND denied_through=630 AND first_eligible=631)
 OR EXISTS(SELECT 1 FROM public.pdc_email_monitor_pilot WHERE enabled OR outbound_email_enabled OR automatic_rule_application OR automatic_authenticated_jobcards)
 OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
 OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
 THEN RAISE EXCEPTION 'PDC_467_TARGET_HEAD_FENCE_OR_CONTAINMENT_MISMATCH' USING errcode='55000';END IF;
END $guard$;
UPDATE public.pdc_staging_replay_fences_466 SET denied_through=631,first_eligible=632 WHERE fence_key='email:Inbox' AND uidvalidity=1 AND denied_through=630 AND first_eligible=631;
UPDATE public.pdc_email_monitor_pilot SET minimum_uid=632,updated_at=clock_timestamp() WHERE singleton;
UPDATE public.monitored_mailboxes SET config=(config-'deferred_exact_uid')||jsonb_build_object('inbox_uidvalidity',1,'historical_denied_through_uid',631,'future_only_minimum_uid',632,'containment','craig-fresh-import-reset-mailbox-cutoff-verified-20260826'),updated_at=clock_timestamp() WHERE mailbox_key='pdc_pmb_email';
CREATE TABLE public.pdc_staging_mailbox_cutoff_receipts_467(receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),project_ref text NOT NULL CHECK(project_ref='cdsmnqxtyyoeoznmbidd'),folder text NOT NULL CHECK(folder='Inbox'),uidvalidity bigint NOT NULL CHECK(uidvalidity=1),denied_through bigint NOT NULL CHECK(denied_through=631),first_eligible bigint NOT NULL CHECK(first_eligible=632),cutoff_uid_internaldate timestamptz NOT NULL CHECK(cutoff_uid_internaldate='2026-08-26 01:15:21+00'::timestamptz),containment_observed_at timestamptz NOT NULL CHECK(cutoff_uid_internaldate<=containment_observed_at),source text NOT NULL CHECK(source='direct_read_only_gmail_inbox_uid_scan'),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_staging_mailbox_cutoff_receipts_467 ENABLE ROW LEVEL SECURITY;REVOKE ALL ON public.pdc_staging_mailbox_cutoff_receipts_467 FROM public,anon,authenticated,service_role;
CREATE FUNCTION public.pdc_staging_mailbox_cutoff_receipt_immutable_467() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$BEGIN RAISE EXCEPTION 'PDC_467_CUTOFF_RECEIPT_IMMUTABLE' USING errcode='55000';END$$;
REVOKE ALL ON FUNCTION public.pdc_staging_mailbox_cutoff_receipt_immutable_467() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_staging_mailbox_cutoff_receipt_immutable_467 BEFORE UPDATE OR DELETE ON public.pdc_staging_mailbox_cutoff_receipts_467 FOR EACH ROW EXECUTE FUNCTION public.pdc_staging_mailbox_cutoff_receipt_immutable_467();
INSERT INTO public.pdc_staging_mailbox_cutoff_receipts_467(project_ref,folder,uidvalidity,denied_through,first_eligible,cutoff_uid_internaldate,containment_observed_at,source) SELECT 'cdsmnqxtyyoeoznmbidd','Inbox',1,631,632,'2026-08-26 01:15:21+00'::timestamptz,'2026-08-26 01:15:59.970328+00'::timestamptz,'direct_read_only_gmail_inbox_uid_scan';
DO $post$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_replay_fences_466 WHERE fence_key='email:Inbox' AND uidvalidity=1 AND denied_through=631 AND first_eligible=632)
 OR (SELECT minimum_uid FROM public.pdc_email_monitor_pilot WHERE singleton)<>632
 OR (SELECT count(*) FROM public.pdc_staging_mailbox_cutoff_receipts_467)<>1
 OR EXISTS(SELECT 1 FROM public.pdc_email_monitor_pilot WHERE enabled OR outbound_email_enabled OR automatic_rule_application OR automatic_authenticated_jobcards)
 OR has_function_privilege('authenticated','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','EXECUTE')
 THEN RAISE EXCEPTION 'PDC_467_POSTCONDITION_FAILED' USING errcode='55000';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827017000','467_bind_direct_inbox_reset_cutoff',ARRAY['Bind Inbox UIDVALIDITY 1 and cutoff UID 631 from a direct read-only Gmail Inbox scan','Advance fresh-only minimum to UID 632 and retain automatic importer and recovery containment','Record immutable-access cutoff evidence without message content; Production untouched']);NOTIFY pgrst,'reload schema';COMMIT;
