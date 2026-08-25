-- STAGING ONLY 454: owner-authorised future Inbox monitor activation.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-454-inbox-monitor-activation',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT public.pdc_monitor_staging_guard()
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827003000' AND name='453_workshop_detail_lifecycle_read')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827003000')
 OR NOT EXISTS(SELECT 1 FROM auth.users u JOIN public.pdc_user_roles r ON r.auth_user_id=u.id AND lower(r.email)=lower(u.email)
   WHERE u.id='69846ef4-a74c-4569-9e35-376cf0837888'::uuid AND lower(u.email)='pmbcontroller@gmail.com'
   AND u.raw_app_meta_data->>'pdc_identity_type'='non_human_monitor' AND r.active AND r.account_status='approved' AND r.role::text='importer')
 OR NOT EXISTS(SELECT 1 FROM auth.users u JOIN public.pdc_user_roles r ON r.auth_user_id=u.id
   WHERE u.id='8a83b715-8d79-4b0e-95b2-02b55da6e8d7'::uuid AND lower(u.email)='craig.watson@broometoyota.com.au'
   AND r.active AND r.account_status='approved' AND r.role::text='administrator')
 THEN RAISE EXCEPTION 'PDC_454_STAGING_HEAD_OR_IDENTITY_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

CREATE TABLE IF NOT EXISTS public.pdc_email_monitor_activation_receipts_454(
 receipt_id uuid PRIMARY KEY,
 actor_id uuid NOT NULL,
 approved_by uuid NOT NULL,
 project_ref text NOT NULL CHECK(project_ref='cdsmnqxtyyoeoznmbidd'),
 mailbox_address text NOT NULL CHECK(mailbox_address='pmbcontroller@gmail.com'),
 gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-pmbcontroller-hourly-v1'),
 poll_interval_minutes integer NOT NULL CHECK(poll_interval_minutes=30),
 inbox_uidvalidity bigint NOT NULL CHECK(inbox_uidvalidity=1),
 activation_high_water_uid bigint NOT NULL CHECK(activation_high_water_uid=589),
 future_minimum_uid bigint NOT NULL CHECK(future_minimum_uid=590),
 monitor_sha256 text NOT NULL CHECK(monitor_sha256~'^[a-f0-9]{64}$'),
 bridge_sha256 text NOT NULL CHECK(bridge_sha256~'^[a-f0-9]{64}$'),
 processor_sha256 text NOT NULL CHECK(processor_sha256~'^[a-f0-9]{64}$'),
 manifest_sha256 text NOT NULL CHECK(manifest_sha256~'^[a-f0-9]{64}$'),
 prestate jsonb NOT NULL CHECK(jsonb_typeof(prestate)='object'),
 poststate jsonb NOT NULL CHECK(jsonb_typeof(poststate)='object'),
 production_untouched boolean NOT NULL CHECK(production_untouched),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON public.pdc_email_monitor_activation_receipts_454 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_email_monitor_activation_receipt_immutable_454()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'PDC_454_ACTIVATION_RECEIPT_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_email_monitor_activation_receipt_immutable_454() FROM public,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS pdc_email_monitor_activation_receipt_immutable_454 ON public.pdc_email_monitor_activation_receipts_454;
CREATE TRIGGER pdc_email_monitor_activation_receipt_immutable_454 BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_activation_receipts_454
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_activation_receipt_immutable_454();

DO $activate$
DECLARE
 monitor_id constant uuid:='69846ef4-a74c-4569-9e35-376cf0837888'::uuid;
 owner_id constant uuid:='8a83b715-8d79-4b0e-95b2-02b55da6e8d7'::uuid;
 before_state jsonb;
 after_state jsonb;
BEGIN
 SELECT jsonb_build_object(
   'writer',(SELECT to_jsonb(w) FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=monitor_id),
   'reader',(SELECT to_jsonb(r) FROM public.pdc_monitor_vehicle_identity_readers r WHERE r.user_id=monitor_id),
   'mailbox',(SELECT to_jsonb(m) FROM public.monitored_mailboxes m WHERE lower(m.mailbox_address)='pmbcontroller@gmail.com'),
   'pilot',(SELECT to_jsonb(p) FROM public.pdc_email_monitor_pilot p WHERE p.singleton)
 ) INTO before_state;

 UPDATE public.pdc_monitor_stage_activation_writers
 SET active=true,reason='Craig authorised automatic staging Inbox action monitor with receipt-bound imports and archive after terminal handling',
     granted_by=owner_id,granted_at=clock_timestamp(),revoked_at=NULL
 WHERE user_id=monitor_id;
 IF NOT FOUND THEN
   INSERT INTO public.pdc_monitor_stage_activation_writers(user_id,active,reason,granted_by,granted_at,revoked_at)
   VALUES(monitor_id,true,'Craig authorised automatic staging Inbox action monitor with receipt-bound imports and archive after terminal handling',owner_id,clock_timestamp(),NULL);
 END IF;

 UPDATE public.pdc_monitor_vehicle_identity_readers
 SET active=true,reason='Craig authorised exact staging identity reads for automatic Inbox action monitoring',
     granted_by=owner_id,granted_at=clock_timestamp(),revoked_at=NULL
 WHERE user_id=monitor_id;

 UPDATE public.monitored_mailboxes
 SET active=true,test_mode=true,updated_by=owner_id,updated_at=clock_timestamp()
 WHERE mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com';
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_454_MAILBOX_BINDING_MISSING' USING errcode='55000'; END IF;

 UPDATE public.pdc_email_monitor_pilot
 SET enabled=true,minimum_uid=590,automatic_rule_application=true,automatic_authenticated_jobcards=true,
     outbound_email_enabled=false,ambiguous_to_review=true,exactly_once_required=true,
     authorized_by=owner_id,authorized_by_email='craig.watson@broometoyota.com.au',authorized_at=clock_timestamp(),updated_at=clock_timestamp()
 WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd' AND mailbox_key='pdc_pmb_email';
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_454_PILOT_BINDING_MISSING' USING errcode='55000'; END IF;

 SELECT jsonb_build_object(
   'writer',(SELECT to_jsonb(w) FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=monitor_id),
   'reader',(SELECT to_jsonb(r) FROM public.pdc_monitor_vehicle_identity_readers r WHERE r.user_id=monitor_id),
   'mailbox',(SELECT to_jsonb(m) FROM public.monitored_mailboxes m WHERE lower(m.mailbox_address)='pmbcontroller@gmail.com'),
   'pilot',(SELECT to_jsonb(p) FROM public.pdc_email_monitor_pilot p WHERE p.singleton)
 ) INTO after_state;

 INSERT INTO public.pdc_email_monitor_activation_receipts_454(
   receipt_id,actor_id,approved_by,project_ref,mailbox_address,gateway_instance_id,poll_interval_minutes,
   inbox_uidvalidity,activation_high_water_uid,future_minimum_uid,monitor_sha256,bridge_sha256,processor_sha256,
   manifest_sha256,prestate,poststate,production_untouched)
 VALUES(gen_random_uuid(),monitor_id,owner_id,'cdsmnqxtyyoeoznmbidd','pmbcontroller@gmail.com',
   'pdc-monitor-staging-pmbcontroller-hourly-v1',30,1,589,590,
   '0f51b3e3092524ba4d38bd975fbda7d7d2ad45e9124a6fe688898212e693114d',
   'f829cc4bc8cc4a15436c7bb8b57194c6f86074b1e941bb9ca0aa84f25910a288',
   '3e1e222ea1fba05cb26bd00bb7734c25fe9ae30f270d05036f5c7e0daf084f52',
   'b4d9beea3feecc12587fa4b90aaaf3e0029fd35b936de08e61aea6fcdf8f4c84',before_state,after_state,true);
END $activate$;

DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='69846ef4-a74c-4569-9e35-376cf0837888'::uuid AND active AND revoked_at IS NULL)<>1
 OR (SELECT count(*) FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id='69846ef4-a74c-4569-9e35-376cf0837888'::uuid AND active AND revoked_at IS NULL)<>1
 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND active AND test_mode)<>1
 OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND enabled AND minimum_uid=590 AND automatic_rule_application AND automatic_authenticated_jobcards AND NOT outbound_email_enabled AND ambiguous_to_review AND exactly_once_required)<>1
 OR (SELECT count(*) FROM public.pdc_email_monitor_activation_receipts_454)<>1
 THEN RAISE EXCEPTION 'PDC_454_ACTIVATION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827004000','454_inbox_monitor_activation',ARRAY[
 'Craig-authorised staging Inbox monitor uses the existing isolated pmbcontroller Importer identity and 30-minute future-only UID boundary',
 'Authenticated Job Cards and allowlisted rules may apply only through protected receipt-bound contracts; ambiguity remains review-only',
 'Outbound email remains disabled; Production is untouched; mailbox archive occurs only after terminal processing evidence'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
