-- STAGING ONLY 799: bind 752 rollback idempotency to the exact 675
-- active-mailbox columns. The 798 rollback already succeeded; this successor
-- repairs only its second-call readback path.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='90s';
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-799-repair-798-idempotency',0));

DO $guard$
DECLARE v_hash text;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830211000' AND name='798_repair_752_rollback_history_insert')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260830211000')
     OR to_regprocedure('public.admin_rollback_pdc_email_monitor_reactivation_752(text)') IS NULL
     OR (SELECT count(*) FROM public.pdc_email_monitor_reactivation_752 WHERE event_kind='rollback')<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND NOT active AND test_mode AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND config->>'operational_scope'='staging')<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND NOT enabled AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(mailbox_address)='pmbcontroller@gmail.com')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled AND active_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(active_mailbox_address)='pmbcontroller@gmail.com' AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
  THEN RAISE EXCEPTION 'PDC_799_EXACT_798_IDEMPOTENCY_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_hash
  FROM pg_proc p WHERE p.oid='public.admin_rollback_pdc_email_monitor_reactivation_752(text)'::regprocedure;
  IF v_hash<>'aa953761cf5dbc4f5e43f63b351543bbcab2fe1e1e332c5679b6492575f3c4fb'
  THEN RAISE EXCEPTION 'PDC_799_798_PREDECESSOR_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.admin_rollback_pdc_email_monitor_reactivation_752(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $function$
DECLARE
  v_admin_id uuid:=auth.uid();
  v_admin_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_mailbox public.monitored_mailboxes%rowtype;
  v_writer public.pdc_monitor_stage_activation_writers%rowtype;
  v_forward public.pdc_email_monitor_reactivation_752%rowtype;
  v_existing public.pdc_email_monitor_reactivation_752%rowtype;
  v_before_mailbox jsonb;
  v_after_mailbox jsonb;
  v_before_writer jsonb;
  v_after_writer jsonb;
  v_event_key text;
  v_rollback_count integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_admin_id IS NULL
     OR auth.jwt()->>'role'<>'authenticated'
     OR length(btrim(coalesce(p_reason,'')))<10
     OR (SELECT count(*) FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id AND lower(u.email)=v_admin_email WHERE r.auth_user_id=v_admin_id AND lower(r.email)=v_admin_email AND r.active AND r.account_status='approved' AND r.role::text='administrator')<>1
  THEN RAISE EXCEPTION 'PDC_752_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-752-exact-email-monitor-reactivation',0));
  v_event_key:=encode(extensions.digest(convert_to('pdc-staging-752-exact-email-monitor-reactivation|rollback|12fe383d-5c1e-5801-96e4-f67cf3e3bb57','UTF8'),'sha256'),'hex');
  SELECT * INTO v_existing
  FROM public.pdc_email_monitor_reactivation_752
  WHERE event_key=v_event_key AND event_kind='rollback'
  FOR SHARE;
  IF FOUND THEN
    IF (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
       OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND NOT active AND test_mode AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND config->>'operational_scope'='staging')<>1
       OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>0
       OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND NOT active AND revoked_at IS NOT NULL)<>1
       OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND NOT enabled AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(mailbox_address)='pmbcontroller@gmail.com')<>1
       OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled AND active_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(active_mailbox_address)='pmbcontroller@gmail.com' AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
    THEN RAISE EXCEPTION 'PDC_799_EXISTING_752_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF;
    RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_reactivation_rolled_back_752','idempotent',true,'history_id',v_existing.event_id,'mailbox_active',false,'controls_enabled',false,'writer_enabled',false,'task_enabled',false,'mailbox_contacted',false,'mailbox_flags_changed',false,'uid514_processed',false,'production_writes',false,'rollback_available',true);
  END IF;
  IF (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
  THEN RAISE EXCEPTION 'PDC_752_ROLLBACK_SCOPE_MISMATCH' USING errcode='55000'; END IF;
  SELECT * INTO v_mailbox FROM public.monitored_mailboxes
  WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND active AND test_mode AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_752_ROLLBACK_MAILBOX_SCOPE_MISMATCH' USING errcode='55000'; END IF;
  SELECT * INTO v_writer FROM public.pdc_monitor_stage_activation_writers
  WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_752_ROLLBACK_WRITER_SCOPE_MISMATCH' USING errcode='55000'; END IF;
  SELECT * INTO v_forward FROM public.pdc_email_monitor_reactivation_752
  WHERE event_kind='forward_reactivation'
    AND event_key=encode(extensions.digest(convert_to('pdc-staging-752-exact-email-monitor-reactivation|forward|12fe383d-5c1e-5801-96e4-f67cf3e3bb57','UTF8'),'sha256'),'hex')
    AND mailbox_id=v_mailbox.id AND mailbox_address='pmbcontroller@gmail.com'
    AND controls_enabled AND writer_enabled
    AND NOT task_enabled AND NOT mailbox_contacted AND NOT mailbox_flags_changed AND NOT uid514_processed AND NOT production_writes
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_799_752_FORWARD_HISTORY_MISSING' USING errcode='55000'; END IF;
  v_before_mailbox:=to_jsonb(v_mailbox); v_before_writer:=to_jsonb(v_writer);
  UPDATE public.monitored_mailboxes SET active=false,updated_at=clock_timestamp() WHERE id=v_mailbox.id AND active RETURNING * INTO v_mailbox;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_752_ROLLBACK_MAILBOX_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
  UPDATE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674
  SET enabled=false,changed_at=clock_timestamp()
  WHERE singleton AND enabled AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'
    AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'
    AND lower(mailbox_address)='pmbcontroller@gmail.com'
  RETURNING 1 INTO v_rollback_count;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_799_752_ROLLBACK_674_CONTROL_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
  UPDATE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675
  SET enabled=false,changed_at=clock_timestamp()
  WHERE singleton AND enabled AND active_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'
    AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'
    AND lower(active_mailbox_address)='pmbcontroller@gmail.com'
    AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted
    AND NOT uid514_processed AND NOT production_writes
  RETURNING 1 INTO v_rollback_count;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_799_752_ROLLBACK_675_CONTROL_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
  UPDATE public.pdc_monitor_stage_activation_writers SET active=false,revoked_at=clock_timestamp() WHERE user_id=v_writer.user_id AND active AND revoked_at IS NULL RETURNING * INTO v_writer;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_752_ROLLBACK_WRITER_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
  v_after_mailbox:=to_jsonb(v_mailbox); v_after_writer:=to_jsonb(v_writer);
  SELECT count(*) INTO v_rollback_count FROM public.pdc_email_monitor_reactivation_752 WHERE event_key=v_event_key;
  IF v_rollback_count<>0 THEN RAISE EXCEPTION 'PDC_799_752_ROLLBACK_DUPLICATE_PRECONDITION' USING errcode='55000'; END IF;
  INSERT INTO public.pdc_email_monitor_reactivation_752(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,gateway_instance_id,release_name,mailbox_id,mailbox_address,before_mailbox,after_mailbox,before_writer,after_writer,controls_enabled,writer_enabled,task_enabled,mailbox_contacted,mailbox_flags_changed,uid514_processed,production_writes,performed_by,performed_by_email,rollback_contract)
  VALUES(v_event_key,'rollback',v_forward.predecessor_head,v_forward.successor_head,v_forward.actor_id,v_forward.actor_email,v_forward.gateway_instance_id,v_forward.release_name,v_forward.mailbox_id,v_forward.mailbox_address,v_before_mailbox,v_after_mailbox,v_before_writer,v_after_writer,false,false,false,false,false,false,false,v_admin_id,v_admin_email,'Administrator rollback disables only exact mailbox, 674/675 controls and sales writer; immutable history remains');
  GET DIAGNOSTICS v_rollback_count = ROW_COUNT;
  IF v_rollback_count<>1 THEN RAISE EXCEPTION 'PDC_799_752_ROLLBACK_INSERT_COUNT_MISMATCH' USING errcode='55000'; END IF;
  SELECT count(*) INTO v_rollback_count FROM public.pdc_email_monitor_reactivation_752 WHERE event_key=v_event_key AND event_kind='rollback';
  IF v_rollback_count<>1 THEN RAISE EXCEPTION 'PDC_799_752_ROLLBACK_READBACK_COUNT_MISMATCH' USING errcode='55000'; END IF;
  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','monitored_mailboxes',v_mailbox.id,v_admin_id,v_admin_email,v_before_mailbox,v_after_mailbox,jsonb_build_object('event_type','pdc_email_monitor_reactivation_752_rollback','exact_mailbox_only',true,'writer_disabled',true,'task_enabled',false,'mailbox_contacted',false,'mailbox_flags_changed',false,'uid514_processed',false,'production_untouched',true));
  RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_reactivation_rolled_back_752','idempotent',false,'mailbox_active',false,'controls_enabled',false,'writer_enabled',false,'task_enabled',false,'mailbox_contacted',false,'mailbox_flags_changed',false,'uid514_processed',false,'production_writes',false,'rollback_available',true);
END $function$;

REVOKE ALL ON FUNCTION public.admin_rollback_pdc_email_monitor_reactivation_752(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_email_monitor_reactivation_752(text) TO authenticated;

DO $post$
DECLARE v_hash text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_hash FROM pg_proc p WHERE p.oid='public.admin_rollback_pdc_email_monitor_reactivation_752(text)'::regprocedure;
 IF v_hash='aa953761cf5dbc4f5e43f63b351543bbcab2fe1e1e332c5679b6492575f3c4fb' OR position('controls_675 WHERE singleton AND NOT enabled AND mailbox_id=' in (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.admin_rollback_pdc_email_monitor_reactivation_752(text)'::regprocedure))>0 THEN RAISE EXCEPTION 'PDC_799_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260830212000','799_repair_798_idempotent_675_identity',ARRAY[
  'Bind exact applied 798 rollback state and the exact 675 active mailbox columns',
  'Repair only the 752 rollback idempotency predicate while preserving exact-history-first and duplicate/row-count guards',
  'Preserve 672 containment, immutable evidence, disabled task, closed pilot/outbound controls and Production prohibition'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
