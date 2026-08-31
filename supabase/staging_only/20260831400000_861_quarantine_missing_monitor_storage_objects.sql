-- STAGING ONLY: quarantine missing Storage objects in the authenticated
-- attachment projection. Retain every intake/attachment row; return a review
-- result instead of issuing a doomed object read that fails the whole cycle.
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-861-storage-object-projection',0));
DO $$ BEGIN
 IF current_setting('app.environment',true)='production'
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831390000' AND name='860_append_missing_monitor_attachments_on_replay')<>1
 THEN RAISE EXCEPTION 'PDC_861_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.get_pdc_monitor_intake_attachments_735(p_intake_id uuid,p_claim_token uuid,p_gateway_instance_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public','auth'
AS $function$
DECLARE v_rows jsonb;v_attachment_count integer;v_readable_count integer;v_incomplete_count integer;
BEGIN
 IF NOT public.pdc_email_monitor_runtime_authorized_502(p_gateway_instance_id)
 OR NOT(public.pdc_monitor_authenticated_active_scope_839()->>'gateway_instance_id'=btrim(p_gateway_instance_id))
 OR NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=p_intake_id AND i.locked_by=auth.uid() AND i.status='processing' AND i.claim_token=p_claim_token AND i.gateway_instance_id=btrim(p_gateway_instance_id) AND i.locked_at>=clock_timestamp()-interval '10 minutes')
 THEN RAISE EXCEPTION 'PDC_735_MONITOR_ATTACHMENT_CLAIM_MISSING' USING errcode='42501';END IF;
 SELECT count(*) INTO v_attachment_count FROM public.ai_email_attachments a WHERE a.intake_id=p_intake_id;
 SELECT count(*) INTO v_readable_count FROM public.ai_email_attachments a LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id LEFT JOIN storage.objects o ON o.bucket_id=split_part(coalesce(r.canonical_storage_path,a.storage_path),'/',1) AND o.name=substring(coalesce(r.canonical_storage_path,a.storage_path) from position('/' in coalesce(r.canonical_storage_path,a.storage_path))+1) WHERE a.intake_id=p_intake_id AND (r.outcome='canonical_verified' AND coalesce(r.canonical_storage_path~'^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$',false) OR r.outcome IS NULL AND coalesce(a.storage_path~'^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$',false)) AND o.name IS NOT NULL;
 SELECT count(*) INTO v_incomplete_count FROM public.ai_email_attachments a LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id LEFT JOIN storage.objects o ON o.bucket_id=split_part(coalesce(r.canonical_storage_path,a.storage_path),'/',1) AND o.name=substring(coalesce(r.canonical_storage_path,a.storage_path) from position('/' in coalesce(r.canonical_storage_path,a.storage_path))+1) WHERE a.intake_id=p_intake_id AND NOT(r.outcome='permanent_fail_closed' OR ((r.outcome='canonical_verified' AND coalesce(r.canonical_storage_path~'^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$',false) OR r.outcome IS NULL AND coalesce(a.storage_path~'^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$',false)) AND o.name IS NOT NULL));
 IF v_incomplete_count>0 THEN RETURN jsonb_build_object('ok',true,'attachments','[]'::jsonb,'contract','pdc_email_monitor_attachments_735','scope','authenticated-active-839','review_required',true,'attachment_storage_incomplete',true,'attachment_count',v_attachment_count,'readable_attachment_count',v_readable_count,'incomplete_attachment_count',v_incomplete_count,'storage_reconciliation_required',true,'board_mutated',false,'mailbox_flags_changed',false,'uid514_processed',false,'production_writes',false);END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'file_name',a.file_name,'source_hash',a.source_hash,'storage_path',case when r.outcome='canonical_verified' then r.canonical_storage_path else a.storage_path end,'storage_reconciliation',coalesce(r.outcome,'unreconciled')) order by a.created_at,a.id),'[]'::jsonb) INTO v_rows FROM public.ai_email_attachments a LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id WHERE a.intake_id=p_intake_id;
 RETURN jsonb_build_object('ok',true,'attachments',v_rows,'contract','pdc_email_monitor_attachments_735','scope','authenticated-active-839','review_required',false,'attachment_storage_incomplete',false,'attachment_count',v_attachment_count,'readable_attachment_count',v_readable_count,'incomplete_attachment_count',0,'board_mutated',false,'mailbox_flags_changed',false,'uid514_processed',false,'production_writes',false);
END $function$;
REVOKE ALL ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831400000','861_quarantine_missing_monitor_storage_objects',ARRAY['Detect absent storage.objects rows in the authenticated attachment projection','Preserve append-only intake and attachment evidence','Return review_required without Board, mailbox, UID514, outbound or Production mutation']);
NOTIFY pgrst,'reload schema';
COMMIT;
