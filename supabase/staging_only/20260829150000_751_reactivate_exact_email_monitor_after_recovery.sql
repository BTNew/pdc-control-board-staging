-- STAGING ONLY 751: restore the exact authenticated Email Monitor scope
-- after the authorized 746 recovery lane. No Production, outbound, task, flags,
-- UID514, vehicle or recovery evidence mutation is permitted.
BEGIN;
SET LOCAL lock_timeout='15s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-751-exact-email-monitor-reactivation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260829143000' AND name='750_project_recovered_stock_qc_operation_lines')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260829143000')
 OR to_regclass('public.pdc_email_monitor_reactivation_751') IS NOT NULL
 OR to_regprocedure('public.admin_rollback_pdc_email_monitor_reactivation_751(text)') IS NOT NULL
 OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND NOT enabled)=1
 OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled)=1
 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)=0
 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND NOT active AND test_mode AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND config->>'operational_scope'='staging')<>1
 OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND NOT active AND revoked_at IS NOT NULL)<>1
 OR (SELECT count(*) FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1
 OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
 OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>1
 OR to_regclass('public.pdc_stock_13000769_recovery_receipts_747') IS NULL
 OR to_regclass('public.pdc_qc_retest_photo_evidence_747') IS NULL
 THEN RAISE EXCEPTION 'PDC_751_EXACT_750_REACTIVATION_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_email_monitor_reactivation_751(
 event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind IN('forward_reactivation','rollback')),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260829143000'), successor_head text NOT NULL CHECK(successor_head='20260829150000'),
 actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'), actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
 gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'), release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
 mailbox_id uuid NOT NULL CHECK(mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'), mailbox_address text NOT NULL CHECK(mailbox_address='pmbcontroller@gmail.com'),
 before_mailbox jsonb NOT NULL, after_mailbox jsonb NOT NULL, before_writer jsonb NOT NULL, after_writer jsonb NOT NULL,
 controls_enabled boolean NOT NULL CHECK(controls_enabled=(event_kind='forward_reactivation')),
 writer_enabled boolean NOT NULL CHECK(writer_enabled=(event_kind='forward_reactivation')),
 task_enabled boolean NOT NULL CHECK(NOT task_enabled), mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
 mailbox_flags_changed boolean NOT NULL CHECK(NOT mailbox_flags_changed), uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
 production_writes boolean NOT NULL CHECK(NOT production_writes), performed_by uuid, performed_by_email text,
 rollback_contract text NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_email_monitor_reactivation_751 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_reactivation_751 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_reactivation_751 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_monitor_reactivation_751_immutable() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_751_REACTIVATION_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_email_monitor_reactivation_751_immutable() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_email_monitor_reactivation_751_immutable BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_reactivation_751 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_reactivation_751_immutable();
DO $forward$
DECLARE mb_before jsonb; mb_after jsonb; w_before jsonb; w_after jsonb; mb public.monitored_mailboxes%rowtype; w public.pdc_monitor_stage_activation_writers%rowtype; k text;
BEGIN
 SELECT * INTO mb FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND NOT active AND test_mode AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_751_EXACT_MAILBOX_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
 SELECT * INTO w FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND NOT active AND revoked_at IS NOT NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_751_EXACT_WRITER_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
 mb_before:=to_jsonb(mb); w_before:=to_jsonb(w);
 UPDATE public.monitored_mailboxes SET active=true,updated_at=clock_timestamp() WHERE id=mb.id RETURNING * INTO mb;
 UPDATE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 SET enabled=true,changed_at=clock_timestamp() WHERE singleton;
 UPDATE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 SET enabled=true,changed_at=clock_timestamp() WHERE singleton;
 UPDATE public.pdc_monitor_stage_activation_writers SET active=true,revoked_at=NULL,reason='Craig-authorised exact staging Email Monitor activation 751',granted_at=clock_timestamp() WHERE user_id=w.user_id RETURNING * INTO w;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_751_EXACT_WRITER_UPDATE_FAILED' USING errcode='40001'; END IF;
 mb_after:=to_jsonb(mb); w_after:=to_jsonb(w); k:=encode(extensions.digest(convert_to('pdc-staging-751-exact-email-monitor-reactivation|forward|'||mb.id::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.pdc_email_monitor_reactivation_751(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,gateway_instance_id,release_name,mailbox_id,mailbox_address,before_mailbox,after_mailbox,before_writer,after_writer,controls_enabled,writer_enabled,task_enabled,mailbox_contacted,mailbox_flags_changed,uid514_processed,production_writes,rollback_contract) VALUES(k,'forward_reactivation','20260829143000','20260829150000','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',mb.id,'pmbcontroller@gmail.com',mb_before,mb_after,w_before,w_after,true,true,false,false,false,false,false,'Administrator rollback disables only the exact mailbox, 674/675 controls and exact sales writer; identity reader, recovery evidence and all other state remain intact');
 INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('update','monitored_mailboxes',mb.id,NULL,'staging-management-remediation',mb_before,mb_after,jsonb_build_object('event_type','pdc_email_monitor_reactivated_751','exact_actor','sales@broometoyota.com.au','writer_restored',true,'task_enabled',false,'mailbox_contacted',false,'mailbox_flags_changed',false,'uid514_processed',false,'production_untouched',true));
END $forward$;
CREATE FUNCTION public.admin_rollback_pdc_email_monitor_reactivation_751(p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $$
DECLARE u uuid:=auth.uid(); e text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); mb public.monitored_mailboxes%rowtype; w public.pdc_monitor_stage_activation_writers%rowtype; b jsonb; a jsonb; wb jsonb; wa jsonb; k text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR auth.jwt()->>'role'<>'authenticated' OR length(btrim(coalesce(p_reason,'')))<10 OR (SELECT count(*) FROM public.pdc_user_roles r JOIN auth.users z ON z.id=r.auth_user_id AND lower(z.email)=e WHERE r.auth_user_id=u AND lower(r.email)=e AND r.active AND r.account_status='approved' AND r.role::text='administrator')<>1 THEN RAISE EXCEPTION 'PDC_751_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-751-exact-email-monitor-reactivation',0));
 IF (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1 THEN RAISE EXCEPTION 'PDC_751_ROLLBACK_SCOPE_MISMATCH' USING errcode='55000'; END IF;
 SELECT * INTO mb FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND active AND test_mode AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' FOR UPDATE;
 SELECT * INTO w FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_751_ROLLBACK_WRITER_SCOPE_MISMATCH' USING errcode='55000'; END IF;
 b:=to_jsonb(mb); wb:=to_jsonb(w); UPDATE public.monitored_mailboxes SET active=false,updated_at=clock_timestamp() WHERE id=mb.id RETURNING * INTO mb; UPDATE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 SET enabled=false,changed_at=clock_timestamp() WHERE singleton; UPDATE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 SET enabled=false,changed_at=clock_timestamp() WHERE singleton; UPDATE public.pdc_monitor_stage_activation_writers SET active=false,revoked_at=clock_timestamp() WHERE user_id=w.user_id RETURNING * INTO w; a:=to_jsonb(mb); wa:=to_jsonb(w); k:=encode(extensions.digest(convert_to('pdc-staging-751-exact-email-monitor-reactivation|rollback|'||mb.id::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.pdc_email_monitor_reactivation_751(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,gateway_instance_id,release_name,mailbox_id,mailbox_address,before_mailbox,after_mailbox,before_writer,after_writer,controls_enabled,writer_enabled,task_enabled,mailbox_contacted,mailbox_flags_changed,uid514_processed,production_writes,performed_by,performed_by_email,rollback_contract) SELECT k,'rollback','20260829143000','20260829150000',actor_id,actor_email,gateway_instance_id,release_name,mailbox_id,mailbox_address,b,a,wb,wa,false,false,false,false,false,false,false,u,e,'Administrator rollback disables only the exact mailbox, 674/675 controls and exact sales writer; immutable history remains';
 RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_reactivation_rolled_back_751','task_enabled',false,'mailbox_contacted',false,'mailbox_flags_changed',false,'uid514_processed',false,'production_writes',false);
END $$;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_email_monitor_reactivation_751(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_email_monitor_reactivation_751(text) TO authenticated;
DO $post$ BEGIN
 IF (SELECT count(*) FROM public.pdc_email_monitor_reactivation_751 WHERE event_kind='forward_reactivation' AND controls_enabled AND writer_enabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT mailbox_flags_changed AND NOT uid514_processed AND NOT production_writes)<>1 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1 OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND enabled)<>1 OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND enabled)<>1 OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1 OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT has_function_privilege('authenticated','public.admin_rollback_pdc_email_monitor_reactivation_751(text)','execute') OR has_function_privilege('anon','public.admin_rollback_pdc_email_monitor_reactivation_751(text)','execute') OR has_function_privilege('service_role','public.admin_rollback_pdc_email_monitor_reactivation_751(text)','execute') THEN RAISE EXCEPTION 'PDC_751_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260829150000','751_reactivate_exact_email_monitor_after_recovery',ARRAY['Bind exact 750 recovery head, 744 history, 747/749 recovery evidence and exact inactive mailbox state','Reactivate only pdc_pmb_email, 674/675 controls and the existing sales actor writer; no task, mailbox flags, UID514, pilot, outbound or Production change','Immutable Administrator rollback and forced-RLS evidence preserve all unrelated state']);
NOTIFY pgrST,'reload schema'; COMMIT;
