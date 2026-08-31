-- STAGING ONLY 862: requeue the exact failed monitor intake after the
-- reviewed 859-861 incomplete-storage repair. This is a bounded retry of one
-- existing row; it does not change source/evidence/attachments or create data.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-862-requeue-692',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
 SELECT (version||','||name)::text INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR NOT public.pdc_monitor_staging_guard()
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260831270000,861_null_storage_predicate_successor'
    OR (SELECT count(*) FROM public.ai_email_intake WHERE id='0172352b-6045-4ab4-83ba-c8069c9ab8de'::uuid AND provider_uid='imap_uid:692' AND status='failed' AND source_hash='cdc66328f62d3eac365127763ac13ed01da83fe16ca951029d17360db6553565' AND queue_attempts=2 AND permanent_failure AND retry_class='permanent' AND locked_at IS NULL AND locked_by IS NULL AND claim_token IS NULL AND gateway_instance_id IS NULL AND last_error_code='worker_exception')<>1
    OR (SELECT count(*) FROM public.pdc_monitor_requeue_targets_735 WHERE intake_id='0172352b-6045-4ab4-83ba-c8069c9ab8de'::uuid)<>0
    OR (SELECT count(*) FROM public.pdc_monitor_requeue_receipts_735 WHERE intake_id='0172352b-6045-4ab4-83ba-c8069c9ab8de'::uuid)<>0
    OR to_regclass('public.pdc_monitor_exact_requeue_history_862') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_862_EXACT_861_REQUEUE_PRESTATE_FAILED' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_monitor_exact_requeue_history_862(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='exact_retry_after_storage_repair'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260831270000'),
 successor_head text NOT NULL CHECK(successor_head='20260831280000'),
 intake_id uuid NOT NULL UNIQUE REFERENCES public.ai_email_intake(id) ON DELETE RESTRICT,
 provider_uid text NOT NULL CHECK(provider_uid='imap_uid:692'),
 source_hash text NOT NULL CHECK(source_hash='cdc66328f62d3eac365127763ac13ed01da83fe16ca951029d17360db6553565'),
 before_state jsonb NOT NULL,
 after_state jsonb NOT NULL,
 source_evidence_unchanged boolean NOT NULL CHECK(source_evidence_unchanged),
 attachments_unchanged boolean NOT NULL CHECK(attachments_unchanged),
 task_enabled boolean NOT NULL CHECK(NOT task_enabled),
 mailbox_flags_changed boolean NOT NULL CHECK(NOT mailbox_flags_changed),
 uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
 outbound_email_sent boolean NOT NULL CHECK(NOT outbound_email_sent),
 production_writes boolean NOT NULL CHECK(NOT production_writes),
 rollback_contract text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_monitor_exact_requeue_history_862 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_monitor_exact_requeue_history_862 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_monitor_exact_requeue_history_862 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_monitor_exact_requeue_history_immutable_862()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_862_EXACT_REQUEUE_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_monitor_exact_requeue_history_immutable_862() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_monitor_exact_requeue_history_immutable_862 BEFORE UPDATE OR DELETE ON public.pdc_monitor_exact_requeue_history_862 FOR EACH ROW EXECUTE FUNCTION public.pdc_monitor_exact_requeue_history_immutable_862();

DO $requeue$
DECLARE v_before jsonb; v_after jsonb; v_id uuid; v_event_key text; v_attachment_count integer;
BEGIN
 SELECT to_jsonb(i),i.id INTO v_before,v_id FROM public.ai_email_intake i WHERE i.id='0172352b-6045-4ab4-83ba-c8069c9ab8de'::uuid AND i.provider_uid='imap_uid:692' AND i.status='failed' AND i.permanent_failure FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_862_EXACT_REQUEUE_TARGET_LOST' USING errcode='55000'; END IF;
 SELECT count(*) INTO v_attachment_count FROM public.ai_email_attachments WHERE intake_id=v_id;
 UPDATE public.ai_email_intake SET status='received',permanent_failure=false,retry_class=null,next_attempt_at=clock_timestamp(),locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null,error_details=null,last_error_code=null WHERE id=v_id AND status='failed' AND permanent_failure RETURNING to_jsonb(public.ai_email_intake.*) INTO v_after;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_862_EXACT_REQUEUE_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
 v_event_key:=encode(extensions.digest(convert_to('pdc-monitor-staging-862-requeue-692|forward|'||v_id::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.pdc_monitor_exact_requeue_history_862(event_key,event_kind,predecessor_head,successor_head,intake_id,provider_uid,source_hash,before_state,after_state,source_evidence_unchanged,attachments_unchanged,task_enabled,mailbox_flags_changed,uid514_processed,outbound_email_sent,production_writes,rollback_contract)
 VALUES(v_event_key,'exact_retry_after_storage_repair','20260831270000','20260831280000',v_id,'imap_uid:692','cdc66328f62d3eac365127763ac13ed01da83fe16ca951029d17360db6553565',v_before,v_after,true,(v_attachment_count=3),false,false,false,false,false,'Exact one-row retry after reviewed storage-path repairs; preserves source/evidence/attachments and records rollback/readback without task, mailbox-flag, UID514, outbound or Production action');
 INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','ai_email_intake',v_id,NULL,'staging-management-remediation',v_before,v_after,jsonb_build_object('event_type','pdc_monitor_exact_requeue_862','provider_uid','imap_uid:692','source_evidence_unchanged',true,'attachments_unchanged',v_attachment_count=3,'task_enabled',false,'mailbox_flags_changed',false,'uid514_processed',false,'outbound_email_sent',false,'production_untouched',true));
END
$requeue$;

DO $post$
BEGIN
 IF (SELECT count(*) FROM public.ai_email_intake WHERE id='0172352b-6045-4ab4-83ba-c8069c9ab8de'::uuid AND provider_uid='imap_uid:692' AND status='received' AND source_hash='cdc66328f62d3eac365127763ac13ed01da83fe16ca951029d17360db6553565' AND queue_attempts=2 AND NOT permanent_failure AND retry_class IS NULL AND next_attempt_at IS NOT NULL AND locked_at IS NULL AND locked_by IS NULL AND claim_token IS NULL AND gateway_instance_id IS NULL)<>1
    OR (SELECT count(*) FROM public.pdc_monitor_exact_requeue_history_862 WHERE event_kind='exact_retry_after_storage_repair' AND source_evidence_unchanged AND attachments_unchanged AND NOT task_enabled AND NOT mailbox_flags_changed AND NOT uid514_processed AND NOT outbound_email_sent AND NOT production_writes)<>1
    OR (SELECT count(*) FROM public.ai_email_attachments WHERE intake_id='0172352b-6045-4ab4-83ba-c8069c9ab8de'::uuid)<>3
    OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND enabled AND automatic_rule_application AND automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_862_EXACT_REQUEUE_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831280000','862_exact_retry_after_storage_repair',ARRAY['Requeue only the exact failed imap_uid:692 intake after 859-861 storage repairs','Preserve source hash evidence attachment count and all attachment rows','Record forced-RLS immutable before/after retry evidence','Keep task UID514 mailbox flags outbound and Production controls fail-closed']);
NOTIFY pgrst,'reload schema';
COMMIT;
