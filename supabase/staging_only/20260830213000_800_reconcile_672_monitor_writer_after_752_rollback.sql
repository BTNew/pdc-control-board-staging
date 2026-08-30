-- STAGING ONLY 800: reconcile the exact 672 Monitor writer after the
-- contained 752 rollback retired it alongside the mailbox. No mailbox,
-- pilot, task, UID514, vehicle or Production state is enabled.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='90s';
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-800-672-writer-reconciliation',0));

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830212000' AND name='799_repair_798_idempotent_675_identity')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260830212000')
     OR to_regclass('public.pdc_monitor_672_writer_reconciliation_800') IS NOT NULL
     OR to_regprocedure('public.admin_reconcile_pdc_monitor_672_writer_800(text)') IS NOT NULL
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND NOT enabled AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled AND active_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND pilot_remains_disabled)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>0
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND NOT active AND revoked_at IS NOT NULL)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_reactivation_752 WHERE event_kind='rollback' AND event_key=encode(extensions.digest(convert_to('pdc-staging-752-exact-email-monitor-reactivation|rollback|12fe383d-5c1e-5801-96e4-f67cf3e3bb57','UTF8'),'sha256'),'hex') AND predecessor_head='20260829144000' AND successor_head='20260829151000' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_address='pmbcontroller@gmail.com' AND controls_enabled=false AND writer_enabled=false AND NOT task_enabled AND NOT mailbox_contacted AND NOT mailbox_flags_changed AND NOT uid514_processed AND NOT production_writes AND before_mailbox->>'active'='true' AND after_mailbox->>'active'='false' AND before_writer->>'active'='true' AND after_writer->>'active'='false')<>1
  THEN RAISE EXCEPTION 'PDC_800_EXACT_799_672_WRITER_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_monitor_672_writer_reconciliation_800(
  reconciliation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind='writer_reconciliation'),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260830212000'),
  successor_head text NOT NULL CHECK(successor_head='20260830213000'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  role text NOT NULL CHECK(role='importer'),
  reader_id uuid NOT NULL CHECK(reader_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  writer_id uuid NOT NULL CHECK(writer_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  before_reader jsonb NOT NULL,
  after_reader jsonb NOT NULL,
  before_writer jsonb NOT NULL,
  after_writer jsonb NOT NULL,
  mailbox_active boolean NOT NULL CHECK(NOT mailbox_active),
  controls_enabled boolean NOT NULL CHECK(NOT controls_enabled),
  pilot_enabled boolean NOT NULL CHECK(NOT pilot_enabled),
  automatic_enabled boolean NOT NULL CHECK(NOT automatic_enabled),
  outbound_email_enabled boolean NOT NULL CHECK(NOT outbound_email_enabled),
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  performed_by uuid NOT NULL,
  performed_by_email text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_monitor_672_writer_reconciliation_800 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_monitor_672_writer_reconciliation_800 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_monitor_672_writer_reconciliation_800 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_monitor_672_writer_reconciliation_800_immutable() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_800_WRITER_RECONCILIATION_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_monitor_672_writer_reconciliation_800_immutable() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_monitor_672_writer_reconciliation_800_immutable BEFORE UPDATE OR DELETE ON public.pdc_monitor_672_writer_reconciliation_800 FOR EACH ROW EXECUTE FUNCTION public.pdc_monitor_672_writer_reconciliation_800_immutable();

CREATE FUNCTION public.admin_reconcile_pdc_monitor_672_writer_800(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $function$
DECLARE
  v_admin_id uuid:=auth.uid();
  v_admin_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_writer public.pdc_monitor_stage_activation_writers%rowtype;
  v_reader public.pdc_monitor_vehicle_identity_readers%rowtype;
  v_existing public.pdc_monitor_672_writer_reconciliation_800%rowtype;
  v_before_writer jsonb;
  v_after_writer jsonb;
  v_before_reader jsonb;
  v_after_reader jsonb;
  v_after_writer jsonb;
  v_event_key text:=encode(extensions.digest(convert_to('pdc-staging-800-672-writer-reconciliation|df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','UTF8'),'sha256'),'hex');
  v_affected integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_admin_id IS NULL OR auth.jwt()->>'role'<>'authenticated'
     OR length(btrim(coalesce(p_reason,'')))<10
     OR (SELECT count(*) FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id AND lower(u.email)=v_admin_email WHERE r.auth_user_id=v_admin_id AND lower(r.email)=v_admin_email AND r.active AND r.account_status='approved' AND r.role::text='administrator')<>1
  THEN RAISE EXCEPTION 'PDC_800_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-800-672-writer-reconciliation',0));
  SELECT * INTO v_existing FROM public.pdc_monitor_672_writer_reconciliation_800 WHERE event_key=v_event_key FOR SHARE;
  IF FOUND THEN
    IF (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
    OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND NOT active AND test_mode AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND config->>'operational_scope'='staging')<>1
    OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>0
    OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1
       OR (SELECT count(*) FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1
       OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND NOT enabled AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(mailbox_address)='pmbcontroller@gmail.com')<>1
       OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled AND active_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(active_mailbox_address)='pmbcontroller@gmail.com' AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
    THEN RAISE EXCEPTION 'PDC_800_EXISTING_WRITER_RECONCILIATION_STATE_DRIFT' USING errcode='55000'; END IF;
    RETURN jsonb_build_object('ok',true,'code','pdc_monitor_672_writer_reconciled_800','idempotent',true,'reconciliation_id',v_existing.reconciliation_id,'writer_active',true,'reader_active',true,'mailbox_active',false,'controls_enabled',false,'pilot_enabled',false,'automatic_enabled',false,'outbound_email_enabled',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'production_writes',false);
  END IF;
  IF (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_reactivation_752 WHERE event_kind='rollback' AND event_key=encode(extensions.digest(convert_to('pdc-staging-752-exact-email-monitor-reactivation|rollback|12fe383d-5c1e-5801-96e4-f67cf3e3bb57','UTF8'),'sha256'),'hex') AND predecessor_head='20260829144000' AND successor_head='20260829151000' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_address='pmbcontroller@gmail.com' AND controls_enabled=false AND writer_enabled=false AND NOT task_enabled AND NOT mailbox_contacted AND NOT mailbox_flags_changed AND NOT uid514_processed AND NOT production_writes AND before_mailbox->>'active'='true' AND after_mailbox->>'active'='false' AND before_writer->>'active'='true' AND after_writer->>'active'='false')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND NOT enabled AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled AND active_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active_mailbox_address='pmbcontroller@gmail.com' AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
  THEN RAISE EXCEPTION 'PDC_800_CONTAINMENT_PRECONDITION_FAILED' USING errcode='55000'; END IF;
  IF (SELECT count(*) FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1
  THEN RAISE EXCEPTION 'PDC_800_EXACT_READER_CARDINALITY_MISMATCH' USING errcode='55000'; END IF;
  SELECT * INTO v_reader FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_800_EXACT_READER_SCOPE_MISMATCH' USING errcode='55000'; END IF;
  IF (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba-47f6-ba16-44d6ae2c2a4b' AND NOT active AND revoked_at IS NOT NULL)<>1
  THEN RAISE EXCEPTION 'PDC_800_EXACT_RETIRED_WRITER_CARDINALITY_MISMATCH' USING errcode='55000'; END IF;
  SELECT * INTO v_writer FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba-47f6-ba16-44d6ae2c2a4b' AND NOT active AND revoked_at IS NOT NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_800_EXACT_WRITER_SCOPE_MISMATCH' USING errcode='55000'; END IF;
  IF (SELECT count(*) FROM public.pdc_user_roles WHERE auth_user_id=v_writer.user_id AND active AND account_status='approved' AND role::text='importer')<>1
  OR (SELECT count(*) FROM public.pdc_user_roles WHERE auth_user_id=v_writer.user_id AND active)<>1
  OR EXISTS(SELECT 1 FROM public.pdc_auditor_worker_identities WHERE auth_user_id=v_writer.user_id AND active)
  OR EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes WHERE auth_user_id=v_writer.user_id AND active)
  OR EXISTS(SELECT 1 FROM public.pdc_auditor_executor_identities WHERE auth_user_id=v_writer.user_id AND active AND expires_at>clock_timestamp())
  OR EXISTS(SELECT 1 FROM public.pdc_auditor_service_identities_225 WHERE auth_user_id=v_writer.user_id AND active)
  THEN RAISE EXCEPTION 'PDC_800_MONITOR_IMPORTER_ROLE_REQUIRED' USING errcode='42501'; END IF;
  v_before_reader:=to_jsonb(v_reader); v_before_writer:=to_jsonb(v_writer);
  UPDATE public.pdc_monitor_stage_activation_writers SET active=true,revoked_at=NULL,reason='672 containment writer reconciliation 800: '||left(btrim(p_reason),700),granted_by=v_admin_id,granted_at=clock_timestamp() WHERE user_id=v_writer.user_id AND NOT active AND revoked_at IS NOT NULL RETURNING * INTO v_writer;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_800_WRITER_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected<>1 THEN RAISE EXCEPTION 'PDC_800_WRITER_UPDATE_COUNT_MISMATCH' USING errcode='40001'; END IF;
  IF (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id=v_writer.user_id AND active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id=v_reader.user_id AND active AND revoked_at IS NULL)<>1
  THEN RAISE EXCEPTION 'PDC_800_WRITER_POSTCARDINALITY_FAILED' USING errcode='55000'; END IF;
  SELECT * INTO v_reader FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id=v_reader.user_id AND active AND revoked_at IS NULL FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_800_READER_POSTREADBACK_FAILED' USING errcode='40001'; END IF;
  v_after_reader:=to_jsonb(v_reader); v_after_writer:=to_jsonb(v_writer);
  INSERT INTO public.pdc_monitor_672_writer_reconciliation_800(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,role,reader_id,writer_id,before_reader,after_reader,before_writer,after_writer,mailbox_active,controls_enabled,pilot_enabled,automatic_enabled,outbound_email_enabled,task_enabled,mailbox_contacted,uid514_processed,production_writes,performed_by,performed_by_email) VALUES(v_event_key,'writer_reconciliation','20260830212000','20260830213000',v_writer.user_id,'sales@broometoyota.com.au','importer',v_reader.user_id,v_writer.user_id,v_before_reader,v_after_reader,v_before_writer,v_after_writer,false,false,false,false,false,false,false,false,false,v_admin_id,v_admin_email) RETURNING * INTO v_existing;
  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('update','pdc_monitor_stage_activation_writers',v_writer.user_id,v_admin_id,v_admin_email,v_before_writer,v_after_writer,jsonb_build_object('event_type','pdc_monitor_672_writer_reconciled_800','exact_monitor_only',true,'reader_preserved',true,'mailbox_active',false,'task_enabled',false,'pilot_enabled',false,'outbound_email_enabled',false,'production_untouched',true));
  RETURN jsonb_build_object('ok',true,'code','pdc_monitor_672_writer_reconciled_800','idempotent',false,'reconciliation_id',v_existing.reconciliation_id,'writer_active',true,'reader_active',true,'mailbox_active',false,'controls_enabled',false,'pilot_enabled',false,'automatic_enabled',false,'outbound_email_enabled',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'production_writes',false);
END $function$;
REVOKE ALL ON FUNCTION public.admin_reconcile_pdc_monitor_672_writer_800(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.admin_reconcile_pdc_monitor_672_writer_800(text) TO authenticated;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_monitor_672_writer_reconciliation_800)<>0
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
  THEN RAISE EXCEPTION 'PDC_800_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830213000','800_reconcile_672_monitor_writer_after_752_rollback',ARRAY[
  'Bind exact 799 head, inactive sole mailbox, disabled 674/675 controls, active reader and retired exact importer writer',
  'Add an Administrator-gated exact Monitor writer reconciliation with immutable forced-RLS before/after audit',
  'Preserve 672 containment, disabled task, closed pilot/automatic/outbound controls and no mailbox/UID514/Production action'
]);
NOTIFY pgrST,'reload schema';
COMMIT;
