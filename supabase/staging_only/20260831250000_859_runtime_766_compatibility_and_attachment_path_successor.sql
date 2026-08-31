-- STAGING ONLY: append-only successor after 858.
-- Restore the protected .68 766 response projection while validating the
-- current 858+ chain through the exact authenticated 839 scope.  Also make
-- attachment reads fail closed for malformed paths without mutating intake,
-- Board data, mailbox flags, or processing state.
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-859-runtime-766-compatibility-and-attachment-path',0));
DO $$ BEGIN
 IF current_setting('app.environment',true)='production'
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831240000' AND name='858_runtime_authority_839_scope_compatibility_successor')<>1
 OR to_regprocedure('public.pdc_monitor_authenticated_active_scope_839()') IS NULL
 OR to_regprocedure('public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)') IS NULL
 OR to_regclass('public.pdc_email_monitor_current_head_compatibility_controls_766') IS NULL
 THEN RAISE EXCEPTION 'PDC_859_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_766(
 p_mode text,p_gateway_instance_id text,p_release_name text,p_source_sha text,
 p_manifest_sha256 text,p_semantic_planner_sha256 text DEFAULT NULL,
 p_semantic_planner_trust_receipt_sha256 text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','auth','extensions'
AS $function$
DECLARE s jsonb; h text; c public.pdc_email_monitor_current_head_compatibility_controls_766%rowtype;
BEGIN
 s:=public.pdc_monitor_authenticated_active_scope_839();
 IF lower(btrim(coalesce(p_mode,'')))<>'active'
 OR p_gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
 OR p_release_name<>'pdc-monitor-staging-m502-2026.08.44'
 OR lower(p_source_sha)<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
 OR lower(p_manifest_sha256)<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
 OR lower(p_semantic_planner_sha256)<>'7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'
 OR lower(p_semantic_planner_trust_receipt_sha256)<>'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'
 THEN RETURN jsonb_build_object('ok',false,'code','runtime_binding_mismatch','production_writes',false); END IF;
 SELECT version INTO h FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 SELECT * INTO c FROM public.pdc_email_monitor_current_head_compatibility_controls_766 WHERE singleton AND enabled;
 IF h IS NULL OR h::bigint<20260831240000
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260831240000' AND name='858_runtime_authority_839_scope_compatibility_successor')
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260831250000' AND name='859_runtime_766_compatibility_and_attachment_path_successor')
 OR c.actor_id IS NULL OR c.actor_id IS DISTINCT FROM (s->>'actor_id')::uuid
 OR c.actor_email IS DISTINCT FROM s->>'actor_email'
 OR c.gateway_instance_id IS DISTINCT FROM s->>'gateway_instance_id'
 OR c.release_name IS DISTINCT FROM s->>'release_name'
 OR c.source_sha IS DISTINCT FROM s->>'source_sha'
 OR c.manifest_sha256 IS DISTINCT FROM s->>'manifest_sha256'
 OR c.planner_sha256 IS DISTINCT FROM s->>'semantic_planner_sha256'
 OR c.trust_receipt_sha256 IS DISTINCT FROM s->>'semantic_planner_trust_receipt_sha256'
 OR c.jwt_role<>'authenticated' OR c.server_application_role<>'importer'
 OR c.task_enabled OR c.mailbox_contacted OR c.uid514_processed OR c.production_writes
 OR (s->>'active_mailbox_count')::integer<>1
 THEN RETURN jsonb_build_object('ok',false,'code','current_head_or_canonical_contract_mismatch','production_writes',false); END IF;
 RETURN jsonb_build_object('ok',true,'code','runtime_binding_verified_authenticated_766','mode','active','operational',true,'activation_ready',true,
  'actor_id',s->>'actor_id','actor_email',s->>'actor_email','jwt_role',s->>'jwt_role','server_application_role',s->>'server_application_role',
  'gateway_instance_id',s->>'gateway_instance_id','release_name',s->>'release_name','source_sha',s->>'source_sha','manifest_sha256',s->>'manifest_sha256',
  'semantic_planner_sha256',s->>'semantic_planner_sha256','semantic_planner_trust_receipt_sha256',s->>'semantic_planner_trust_receipt_sha256',
  'planner_commissioned',true,'writer_active',true,'mailbox_id',s->>'mailbox_id','mailbox_active',true,'active_mailbox_count',s->>'active_mailbox_count',
  'migration_head',766,'compatibility_successor_head',766,'current_staging_migration_head',h::bigint,'current_head_compatibility_successor',859,
  'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false);
END
$function$;

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
   'storage_path',case
      when r.outcome='permanent_fail_closed' then null
      when r.outcome='canonical_verified' and r.canonical_storage_path ~ '^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$' then r.canonical_storage_path
      when a.storage_path ~ '^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$' then a.storage_path
      else null end,
   'storage_reconciliation',case when r.outcome='permanent_fail_closed' then 'permanent_fail_closed' when r.outcome='canonical_verified' then 'canonical_verified' when a.storage_path ~ '^pdc-email-intake-private/[a-f0-9]{64}/[^/]+$' then coalesce(r.outcome,'unreconciled') else 'path_quarantined' end) order by a.created_at,a.id),'[]'::jsonb) INTO v_rows
 FROM public.ai_email_attachments a LEFT JOIN public.pdc_email_monitor_storage_reconciliations_735 r ON r.attachment_id=a.id WHERE a.intake_id=p_intake_id;
 RETURN jsonb_build_object('ok',true,'attachments',v_rows,'contract','pdc_email_monitor_attachments_735','scope','authenticated-active-839','board_mutated',false,'mailbox_flags_changed',false);
END
$function$;
REVOKE ALL ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831250000','859_runtime_766_compatibility_and_attachment_path_successor',ARRAY['Append-only successor after 858','Preserve legacy .68 766 response projection: migration_head=766 and compatibility_successor_head=766','Internally validate exact live 858+ chain, authenticated 839 scope, approved actor/gateway/release, one staging mailbox, outbound-off pilot, UID514 terminal safety and Production exclusion','Normalize attachment storage paths per message; malformed paths are quarantined in the read projection only with no Board mutation or mailbox flags']);
NOTIFY pgrst,'reload schema';
COMMIT;
