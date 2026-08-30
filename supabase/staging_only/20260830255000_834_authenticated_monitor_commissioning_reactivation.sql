-- STAGING ONLY 834: re-enable the exact pre-provisioned monitor test mailbox
-- and its already-reviewed 674/675 control rows for Craig-authorized
-- commissioning. No task enablement, UID514 processing, vehicle mutation,
-- outbound email, mailbox flag mutation or Production access occurs here.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-834-authenticated-monitor-commissioning-reactivation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
  SELECT (version||','||name) INTO v_head
    FROM supabase_migrations.schema_migrations
   WHERE version~'^[0-9]{14}$'
   ORDER BY version::bigint DESC LIMIT 1;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_head IS DISTINCT FROM '20260830254000,833_historical_operation_hours_correction_successor'
     OR (SELECT count(*) FROM public.monitored_mailboxes)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND NOT active AND test_mode AND config->>'owner_profile'='pdc-monitor' AND config->>'contains_credentials'='false' AND config->>'operational_scope'='staging')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND NOT enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND mailbox_address='pmbcontroller@gmail.com' AND provider='gmail' AND test_mode AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR to_regclass('public.pdc_email_monitor_authenticated_mailbox_reactivation_history_834') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_834_EXACT_833_COMMISSIONING_PRESTATE_FAILED' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_email_monitor_authenticated_mailbox_reactivation_history_834(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind='commissioning_reactivation'),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260830254000'),
  successor_head text NOT NULL CHECK(successor_head='20260830255000'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  mailbox_id uuid NOT NULL CHECK(mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'),
  mailbox_key text NOT NULL CHECK(mailbox_key='pdc_pmb_email'),
  mailbox_address text NOT NULL CHECK(mailbox_address='pmbcontroller@gmail.com'),
  provider text NOT NULL CHECK(provider='gmail'),
  before_mailbox_state jsonb NOT NULL,
  after_mailbox_state jsonb NOT NULL,
  before_activation_control jsonb NOT NULL,
  after_activation_control jsonb NOT NULL,
  before_enqueue_control jsonb NOT NULL,
  after_enqueue_control jsonb NOT NULL,
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_flags_changed boolean NOT NULL CHECK(NOT mailbox_flags_changed),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  outbound_email_sent boolean NOT NULL CHECK(NOT outbound_email_sent),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  rollback_contract text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_monitor_authenticated_mailbox_reactivation_history_834 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_mailbox_reactivation_history_834 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_mailbox_reactivation_history_834 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.pdc_email_monitor_authenticated_mailbox_reactivation_history_immutable_834()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_834_AUTHENTICATED_MAILBOX_REACTIVATION_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_monitor_authenticated_mailbox_reactivation_history_immutable_834() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_email_monitor_authenticated_mailbox_reactivation_history_immutable_834
BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_authenticated_mailbox_reactivation_history_834
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_authenticated_mailbox_reactivation_history_immutable_834();

DO $activate$
DECLARE
  v_before_mailbox jsonb;
  v_after_mailbox jsonb;
  v_before_activation jsonb;
  v_after_activation jsonb;
  v_before_enqueue jsonb;
  v_after_enqueue jsonb;
  v_mailbox public.monitored_mailboxes%rowtype;
  v_event_key text;
BEGIN
  SELECT * INTO v_mailbox FROM public.monitored_mailboxes
   WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'
     AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com'
     AND lower(provider)='gmail' AND NOT active AND test_mode
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_834_EXACT_MAILBOX_REACTIVATION_SCOPE_FAILED' USING errcode='55000'; END IF;
  v_before_mailbox:=to_jsonb(v_mailbox);
  SELECT to_jsonb(c) INTO v_before_activation FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 c WHERE singleton FOR UPDATE;
  SELECT to_jsonb(c) INTO v_before_enqueue FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 c WHERE singleton FOR UPDATE;
  UPDATE public.monitored_mailboxes
     SET active=true,test_mode=true,
         config=jsonb_build_object('owner_profile','pdc-monitor','contains_credentials',false,'operational_scope','staging'),
         updated_at=clock_timestamp()
   WHERE id=v_mailbox.id AND NOT active
   RETURNING * INTO v_mailbox;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_834_MAILBOX_REACTIVATION_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
  v_after_mailbox:=to_jsonb(v_mailbox);
  UPDATE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674
     SET enabled=true,changed_at=clock_timestamp() WHERE singleton AND NOT enabled;
  UPDATE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675
     SET enabled=true,changed_at=clock_timestamp() WHERE singleton AND NOT enabled;
  SELECT to_jsonb(c) INTO v_after_activation FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 c WHERE singleton;
  SELECT to_jsonb(c) INTO v_after_enqueue FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 c WHERE singleton;
  v_event_key:=encode(extensions.digest(convert_to('pdc-staging-834-authenticated-monitor-commissioning-reactivation|forward|12fe383d-5c1e-5801-96e4-f67cf3e3bb57','UTF8'),'sha256'),'hex');
  INSERT INTO public.pdc_email_monitor_authenticated_mailbox_reactivation_history_834(
    event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,gateway_instance_id,release_name,
    mailbox_id,mailbox_key,mailbox_address,provider,before_mailbox_state,after_mailbox_state,
    before_activation_control,after_activation_control,before_enqueue_control,after_enqueue_control,
    task_enabled,mailbox_flags_changed,uid514_processed,outbound_email_sent,production_writes,rollback_contract)
  VALUES(v_event_key,'commissioning_reactivation','20260830254000','20260830255000',
    'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
    v_mailbox.id,'pdc_pmb_email','pmbcontroller@gmail.com','gmail',v_before_mailbox,v_after_mailbox,
    v_before_activation,v_after_activation,v_before_enqueue,v_after_enqueue,false,false,false,false,false,
    'Exact staging commissioning reactivation only; guarded rollback may disable the exact mailbox and controls while preserving immutable evidence/history; no task enablement, UID514, vehicle, flag, outbound or Production action');
  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','monitored_mailboxes',v_mailbox.id,NULL,'staging-management-remediation',v_before_mailbox,v_after_mailbox,
    jsonb_build_object('event_type','pdc_email_monitor_authenticated_mailbox_reactivated_834','authorized_by','Craig Watson','actor_id','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','gateway_instance_id','pdc-monitor-staging-sales-uid509-v1','exact_mailbox_only',true,'task_enabled',false,'mailbox_flags_changed',false,'uid514_processed',false,'outbound_email_sent',false,'production_untouched',true));
END
$activate$;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND active AND test_mode AND config->>'owner_profile'='pdc-monitor' AND config->>'contains_credentials'='false' AND config->>'operational_scope'='staging')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND enabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND enabled AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_reactivation_history_834 WHERE event_kind='commissioning_reactivation' AND NOT task_enabled AND NOT mailbox_flags_changed AND NOT uid514_processed AND NOT outbound_email_sent AND NOT production_writes)<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_834_AUTHENTICATED_MONITOR_COMMISSIONING_REACTIVATION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830255000','834_authenticated_monitor_commissioning_reactivation',ARRAY[
 'Reactivate only the exact pre-provisioned pdc_pmb_email staging mailbox for Craig-authorized commissioning',
 'Re-enable only the existing exact 674 mailbox-activation and 675 authenticated enqueue controls',
 'Record forced-RLS immutable before/after mailbox and control evidence with guarded rollback contract',
 'Keep Scheduled Task disabled, pilot automatic rules and outbound email disabled, UID514 untouched and Production excluded'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
