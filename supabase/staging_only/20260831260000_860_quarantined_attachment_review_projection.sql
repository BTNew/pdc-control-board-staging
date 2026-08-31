-- STAGING ONLY 860: convert quarantined attachment paths into an
-- explicit review-only projection for the installed .68 processor. No invalid
-- Storage download may occur and no body-only action may reach canonical work.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-860-quarantined-attachment-review',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v text;
BEGIN
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR NOT public.pdc_monitor_staging_guard()
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260831250000,859_runtime_766_compatibility_and_attachment_path_successor)'
    OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '15b681f031031163de4a9dffa075f17c45a7efd68f355e95e39b117742c0bef3'
    OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND enabled AND automatic_rule_application AND automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
 THEN RAISE EXCEPTION 'PDC_860_859_QUARANTINED_ATTACHMENT_PRESTATE_FAILED' USING errcode='55000'; END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.get_pdc_monitor_intake_attachments_735(p_intake_id uuid,p_claim_token uuid,p_gateway_instance_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth
AS $function$
DECLARE
 v_rows jsonb; v_attachment_count integer; v_readable_count integer; v_incomplete_count integer;
BEGIN
 IF NOT public.pdc_email_monitor_runtime_authorized_502(p_gateway_instance_id)
    OR NOT (public.pdc_monitor_authenticated_active_scope_839()->>'gateway_instance_id'=btrim(p_gateway_instance_id))
    OR NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=p_intake_id AND i.locked_by=auth.uid() AND i.status='processing' AND i.claim_token=p_claim_token AND i.gateway_instance_id=btrim(p_gateway_instance_id) AND i.locked_at>=clock_timestamp()-interval '10 minutes')
 THEN RAISE EXCEPTION 'PDC_735_MONITOR_ATTACHMENT_CLAIM_MISSING' USING errcode='42501'; END IF;
 SELECT count(*) INTO v_attachment_count FROM public.ai_email_attachments a WHERE a.intake_id=p_intake_id;
 SELECT count(*) INTO v_readable_count FROM public.ai_email_attachments a LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id WHERE a.intake_id=p_intake_id AND (r.outcome='canonical_verified' AND r.canonical_storage_path~'^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$' OR r.outcome IS NULL AND a.storage_path~'^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$');
 SELECT count(*) INTO v_incomplete_count FROM public.ai_email_attachments a LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id WHERE a.intake_id=p_intake_id AND NOT (r.outcome='canonical_verified' AND r.canonical_storage_path~'^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$' OR r.outcome IS NULL AND a.storage_path~'^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$');
 IF v_incomplete_count>0 THEN
  RETURN jsonb_build_object('ok',true,'attachments','[]'::jsonb,'contract','pdc_email_monitor_attachments_735','scope','authenticated-active-839','review_required',true,'attachment_storage_incomplete',true,'attachment_count',v_attachment_count,'readable_attachment_count',v_readable_count,'incomplete_attachment_count',v_incomplete_count,'storage_reconciliation_required',true,'board_mutated',false,'mailbox_flags_changed',false,'uid514_processed',false,'production_writes',false);
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'file_name',a.file_name,'source_hash',a.source_hash,'storage_path',case when r.outcome='canonical_verified' then r.canonical_storage_path else a.storage_path end,'storage_reconciliation',coalesce(r.outcome,'unreconciled')) order by a.created_at,a.id),'[]'::jsonb) INTO v_rows FROM public.ai_email_attachments a LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id WHERE a.intake_id=p_intake_id;
 RETURN jsonb_build_object('ok',true,'attachments',v_rows,'contract','pdc_email_monitor_attachments_735','scope','authenticated-active-839','review_required',false,'attachment_storage_incomplete',false,'attachment_count',v_attachment_count,'readable_attachment_count',v_readable_count,'incomplete_attachment_count',0,'board_mutated',false,'mailbox_flags_changed',false,'uid514_processed',false,'production_writes',false);
END
$function$;
REVOKE ALL ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) TO authenticated;

DO $post$
DECLARE v text; acl text; own text; sd boolean;
BEGIN
 SELECT p.prosrc,p.proacl::text,p.proowner::regrole::text,p.prosecdef INTO v,acl,own,sd FROM pg_proc p WHERE p.oid='public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'c923565e04ec80111ca1a417e173c3e53979ae790f3404ff7e88f7aa22eba9ad'
    OR acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' OR own<>'postgres' OR NOT sd
    OR position('attachment_storage_incomplete' in v)=0
    OR position('review_required' in v)=0
 THEN RAISE EXCEPTION 'PDC_860_QUARANTINED_ATTACHMENT_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831260000','860_quarantined_attachment_review_projection',ARRAY[
 'Preserve exact 839 active monitor claim and gateway/lock checks',
 'Convert any quarantined or incomplete attachment set into bounded review_required with an empty attachment projection',
 'Prevent invalid Storage downloads and prevent body-only canonical action processing',
 'Preserve authenticated-only execution, RLS, UID514, outbound false, mailbox flags and Production exclusion'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
