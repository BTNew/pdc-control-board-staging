-- STAGING ONLY 859: fail closed on incomplete attachment storage.
-- A provider-declared failed attachment has no storage object by design. The
-- monitor must surface review_required without attempting an invalid Storage
-- download or processing the remaining attachments as if the set were complete.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-859-incomplete-attachment-storage',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v text;
BEGIN
  SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)'::regprocedure;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260831240000,858_runtime_authority_839_scope_compatibility_successor)'
     OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '32e42eeab56f5dbb39db30146648e6ab155ec937976006f21bfbebebc9ecc609'
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND enabled AND automatic_rule_application AND automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
  THEN RAISE EXCEPTION 'PDC_859_858_ATTACHMENT_STORAGE_PRESTATE_FAILED' USING errcode='55000'; END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.get_pdc_monitor_intake_attachments_735(p_intake_id uuid,p_claim_token uuid,p_gateway_instance_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth
AS $function$
DECLARE
  v_rows jsonb;
  v_attachment_count integer;
  v_readable_count integer;
  v_incomplete_count integer;
BEGIN
 IF NOT public.pdc_email_monitor_runtime_authorized_502(p_gateway_instance_id)
    OR NOT (public.pdc_monitor_authenticated_active_scope_839()->>'gateway_instance_id'=btrim(p_gateway_instance_id))
    OR NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=p_intake_id AND i.locked_by=auth.uid() AND i.status='processing' AND i.claim_token=p_claim_token AND i.gateway_instance_id=btrim(p_gateway_instance_id) AND i.locked_at>=clock_timestamp()-interval '10 minutes')
 THEN RAISE EXCEPTION 'PDC_735_MONITOR_ATTACHMENT_CLAIM_MISSING' USING errcode='42501'; END IF;
 SELECT count(*) INTO v_attachment_count FROM public.ai_email_attachments a WHERE a.intake_id=p_intake_id;
 SELECT count(*) INTO v_readable_count
 FROM public.ai_email_attachments a
 LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id
 WHERE a.intake_id=p_intake_id
   AND (r.outcome='canonical_verified' AND r.canonical_storage_path IS NOT NULL OR r.outcome IS NULL AND a.storage_path IS NOT NULL);
 SELECT count(*) INTO v_incomplete_count
 FROM public.ai_email_attachments a
 LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id
 WHERE a.intake_id=p_intake_id
   AND NOT (r.outcome='canonical_verified' AND r.canonical_storage_path IS NOT NULL OR r.outcome IS NULL AND a.storage_path IS NOT NULL);
 IF v_incomplete_count>0 THEN
   RETURN jsonb_build_object('ok',true,'attachments','[]'::jsonb,'contract','pdc_email_monitor_attachments_735','scope','authenticated-active-839','review_required',true,'attachment_storage_incomplete',true,'attachment_count',v_attachment_count,'readable_attachment_count',v_readable_count,'incomplete_attachment_count',v_incomplete_count,'storage_reconciliation_required',true);
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'file_name',a.file_name,'source_hash',a.source_hash,
   'storage_path',case when r.outcome='canonical_verified' then r.canonical_storage_path else a.storage_path end,
   'storage_reconciliation',coalesce(r.outcome,'unreconciled')) order by a.created_at,a.id),'[]'::jsonb) INTO v_rows
 FROM public.ai_email_attachments a LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id WHERE a.intake_id=p_intake_id;
 RETURN jsonb_build_object('ok',true,'attachments',v_rows,'contract','pdc_email_monitor_attachments_735','scope','authenticated-active-839','review_required',false,'attachment_storage_incomplete',false,'attachment_count',v_attachment_count,'readable_attachment_count',v_readable_count,'incomplete_attachment_count',0);
END
$function$;
REVOKE ALL ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) TO authenticated;

DO $post$
DECLARE v text; acl text; own text; sd boolean;
BEGIN
 SELECT p.prosrc,p.proacl::text,p.proowner::regrole::text,p.prosecdef INTO v,acl,own,sd FROM pg_proc p WHERE p.oid='public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '27a284b6bd148ac195b96d3d18aa88fa315e6c101fac2f3313c4c1bb7ccc6719'
    OR acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' OR own<>'postgres' OR NOT sd
    OR position('attachment_storage_incomplete' in v)=0
    OR position('storage_reconciliation_required' in v)=0
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_859_ATTACHMENT_STORAGE_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831250000','859_incomplete_attachment_storage_fail_closed',ARRAY[
 'Preserve exact authenticated 839 claim/gateway/lock and 735 attachment scope checks',
 'Return bounded review_required empty attachment projection when any attachment lacks canonical storage',
 'Prevent invalid Storage downloads and preserve no-guessing fail-closed processing',
 'Keep authenticated-only execution, pilot/outbound/Production controls, UID514 and mailbox flags unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
