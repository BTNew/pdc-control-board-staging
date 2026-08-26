-- STAGING ONLY 465: freeze automatic Workshop recovery during Craig's full reset backup/delete window.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-465-freeze-automatic-workshop-recovery',0));
DO $guard$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827014000' AND name='464_contain_fresh_import_full_reset')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827014000')
 THEN RAISE EXCEPTION 'PDC_465_STAGING_HEAD_OR_TARGET_MISMATCH' USING errcode='55000';END IF;
END $guard$;
REVOKE ALL ON FUNCTION public.recover_overdue_planned_workshop_bookings(text,timestamptz) FROM public,anon,authenticated,service_role;
DO $post$ BEGIN
 IF has_function_privilege('authenticated','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','EXECUTE')
 OR EXISTS(SELECT 1 FROM public.pdc_email_monitor_pilot WHERE enabled OR outbound_email_enabled OR automatic_rule_application OR automatic_authenticated_jobcards)
 OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
 OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
 THEN RAISE EXCEPTION 'PDC_465_FREEZE_POSTCONDITION_FAILED' USING errcode='55000';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827015000','465_freeze_automatic_workshop_recovery',ARRAY['Revoke automatic overdue-recovery execution during backup and full operational reset','Station snapshots remain readable through deployed recovery-error containment','Monitor mailbox writers and outbound email remain stopped; Production untouched']);
NOTIFY pgrst,'reload schema';COMMIT;
