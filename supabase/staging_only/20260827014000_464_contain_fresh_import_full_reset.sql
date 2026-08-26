-- STAGING ONLY 464: contain every automatic writer before Craig's fresh-import full reset.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-464-fresh-import-reset-containment',0));
DO $guard$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827013000' AND name='463_operation_estimate_planned_cascade')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827013000')
 THEN RAISE EXCEPTION 'PDC_464_STAGING_HEAD_OR_TARGET_MISMATCH' USING errcode='55000';END IF;
END $guard$;
UPDATE public.pdc_email_monitor_pilot SET enabled=false,outbound_email_enabled=false,automatic_rule_application=false,automatic_authenticated_jobcards=false,updated_at=clock_timestamp() WHERE singleton;
UPDATE public.monitored_mailboxes SET active=false,test_mode=true,config=(config-'supervised_pilot_enabled')||jsonb_build_object('supervised_pilot_enabled',false,'outbound_email_enabled',false,'containment','craig-fresh-import-full-reset-20260826'),updated_at=clock_timestamp() WHERE active OR mailbox_key='pdc_pmb_email';
UPDATE public.pdc_monitor_stage_activation_writers SET active=false,revoked_at=coalesce(revoked_at,clock_timestamp()),reason='Craig fresh-import full staging reset 2026-08-26: writer authority revoked' WHERE active OR revoked_at IS NULL;
UPDATE public.pdc_email_monitor_status SET running_status='stopped',gateway_instance_id=null,last_finished_at=coalesce(last_finished_at,clock_timestamp()),last_error='Staging monitor stopped for Craig fresh-import full reset.',last_error_code='staging_fresh_import_reset_contained',updated_at=clock_timestamp() WHERE singleton;
REVOKE ALL ON FUNCTION public.pdc_admin_run_staging_cleanse_348() FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.purge_all_staging_board_vehicles(text,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.purge_vehicle_from_board(uuid,integer,text) FROM public,anon,authenticated,service_role;
DO $verify$ BEGIN
 IF EXISTS(SELECT 1 FROM public.pdc_email_monitor_pilot WHERE enabled OR outbound_email_enabled OR automatic_rule_application OR automatic_authenticated_jobcards)
 OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
 OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
 OR EXISTS(SELECT 1 FROM public.pdc_email_monitor_status WHERE running_status<>'stopped' OR gateway_instance_id IS NOT NULL)
 THEN RAISE EXCEPTION 'PDC_464_CONTAINMENT_POSTCONDITION_FAILED' USING errcode='55000';END IF;
END $verify$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827014000','464_contain_fresh_import_full_reset',ARRAY['Stop mailbox monitor automatic actions writers gateway and outbound email before reset','Retain replay fences configuration references and approved identities','Revoke generic cleanse and purge paths; Production untouched']);
NOTIFY pgrst,'reload schema';COMMIT;
