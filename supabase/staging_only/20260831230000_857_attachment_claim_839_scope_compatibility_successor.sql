-- STAGING ONLY: exact attachment claim compatibility successor after 856.
-- Replace the stale 674 scope check with the exact current authenticated 839 scope.
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-857-attachment-scope',0));
DO $$ BEGIN
 IF current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831220000' AND name='856_active_scope_enabled_pilot_compatibility_successor')<>1
 THEN RAISE EXCEPTION 'PDC_857_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.get_pdc_monitor_intake_attachments_735(p_intake_id uuid,p_claim_token uuid,p_gateway_instance_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $function$
DECLARE v_rows jsonb;
BEGIN
 IF NOT public.pdc_email_monitor_runtime_authorized_502(p_gateway_instance_id)
    OR NOT (public.pdc_monitor_authenticated_active_scope_839()->>'gateway_instance_id'=btrim(p_gateway_instance_id))
    OR NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=p_intake_id AND i.locked_by=auth.uid() AND i.status='processing' AND i.claim_token=p_claim_token AND i.gateway_instance_id=btrim(p_gateway_instance_id) AND i.locked_at>=clock_timestamp()-interval '10 minutes')
 THEN RAISE EXCEPTION 'PDC_735_MONITOR_ATTACHMENT_CLAIM_MISSING' USING errcode='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'file_name',a.file_name,'source_hash',a.source_hash,
   'storage_path',case when r.outcome='permanent_fail_closed' then null when r.outcome='canonical_verified' then r.canonical_storage_path else a.storage_path end,
   'storage_reconciliation',coalesce(r.outcome,'unreconciled')) order by a.created_at,a.id),'[]'::jsonb) INTO v_rows
 FROM public.ai_email_attachments a LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id WHERE a.intake_id=p_intake_id;
 RETURN jsonb_build_object('ok',true,'attachments',v_rows,'contract','pdc_email_monitor_attachments_735','scope','authenticated-active-839');
END
$function$;
REVOKE ALL ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831230000','857_attachment_claim_839_scope_compatibility_successor',ARRAY['Use exact current authenticated 839 scope for attachment claim','Preserve claim token, gateway, lock age, storage reconciliation, RLS and no Production path']);
NOTIFY pgrst,'reload schema';
COMMIT;
