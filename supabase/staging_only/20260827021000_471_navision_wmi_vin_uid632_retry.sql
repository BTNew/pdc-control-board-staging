-- STAGING ONLY 471: canonical Navision VIN completion from WMI + suffix and exact UID632 technical retry.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-471-navision-effective-vin-uid632-retry',0));
DO $guard$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827020000' AND name='470_activate_one_shot_fresh_inbox_check')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827020000')
 OR encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex')<>'1017a3244d89e06920c72981a8bac331765fcaa90a9e9d129756f92d4aa5dcd2'
 OR encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_operational_record_pre171(uuid,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex')<>'fe52f10d340fe95f9bb4f95db454192960f432fe71fcadd393bc2173b6987b89'
 OR encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean)'::regprocedure),'UTF8'),'sha256'),'hex')<>'454a812324ec1431afd346cd94ca776bcf4de2d45df4a3ad680437a7addaa0b2'
 OR encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_attachment_batch_receipt_immutable_323()'::regprocedure),'UTF8'),'sha256'),'hex')<>'c7fe573bb6a35ffead7a7646584877521ef29a9ef3cf407f792527ca22796868'
 OR NOT EXISTS(SELECT 1 FROM public.ai_email_intake WHERE id='57de2d60-16f8-480c-89b3-c69505f5fb88'::uuid AND provider_uid='imap_uid:632' AND source_hash='deb5bb36c4b058008b654907362bc55af9aa837dc311c34e125cbaec2e387c7b' AND status='needs_review')
 OR NOT EXISTS(SELECT 1 FROM public.pdc_email_attachment_batch_receipts_323 WHERE batch_receipt_id='1527df81-e868-4b44-8a1d-7e8236345988'::uuid AND intake_id='57de2d60-16f8-480c-89b3-c69505f5fb88'::uuid AND result_sha256='154b289c0fcf7839296112efafcd592e3dff76618a2bee2ffab27ae2d1193e0e')
 THEN RAISE EXCEPTION 'PDC_471_TARGET_HEAD_FUNCTION_OR_UID632_EVIDENCE_MISMATCH' USING errcode='55000';END IF;
END $guard$;
CREATE FUNCTION public.pdc_navision_effective_vin_471(p_data jsonb) RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $vin$ SELECT CASE WHEN public.is_valid_vehicle_vin(p_data->>'vin') THEN nullif(public.normalize_vehicle_vin(p_data->>'vin'),'') WHEN public.is_valid_vehicle_vin(coalesce(p_data->>'wmi','')||coalesce(p_data->>'vin','')) THEN nullif(public.normalize_vehicle_vin(coalesce(p_data->>'wmi','')||coalesce(p_data->>'vin','')),'') ELSE NULL END $vin$;
REVOKE ALL ON FUNCTION public.pdc_navision_effective_vin_471(jsonb) FROM public,anon,authenticated,service_role;
DO $patch$ DECLARE n text;sig regprocedure;d text;p text;BEGIN
 FOREACH n IN ARRAY ARRAY['reconcile_navision_operational_record(uuid,uuid,text)','reconcile_navision_operational_record_pre171(uuid,uuid,text)','pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean)'] LOOP
  sig:=('public.'||n)::regprocedure;d:=pg_get_functiondef(sig);
  p:=regexp_replace(d,'v_vin\s*:=\s*case\s+when\s+public\.is_valid_vehicle_vin\(v_record\.normalized_data->>''vin''\)\s+then\s+nullif\(public\.normalize_vehicle_vin\(v_record\.normalized_data->>''vin''\),\s*''''\)\s*(else\s+null\s+)?end\s*;','v_vin:=public.pdc_navision_effective_vin_471(v_record.normalized_data);','i');
  IF p=d OR p NOT LIKE '%pdc_navision_effective_vin_471(v_record.normalized_data)%' THEN RAISE EXCEPTION 'PDC_471_FUNCTION_PATCH_ANCHOR_MISSING %',n USING errcode='55000';END IF;EXECUTE p;
 END LOOP;
END $patch$;
CREATE TEMP TABLE pdc_471_original_immutable(definition text NOT NULL) ON COMMIT DROP;INSERT INTO pdc_471_original_immutable VALUES(pg_get_functiondef('public.pdc_email_attachment_batch_receipt_immutable_323()'::regprocedure));
CREATE OR REPLACE FUNCTION public.pdc_email_attachment_batch_receipt_immutable_323() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$BEGIN IF tg_op='DELETE' AND old.batch_receipt_id='1527df81-e868-4b44-8a1d-7e8236345988'::uuid THEN RETURN old;END IF;RAISE EXCEPTION 'PDC_ATTACHMENT_BATCH_RECEIPT_IMMUTABLE_323' USING errcode='55000';END$$;
INSERT INTO public.pdc_email_attachment_batch_superseded_325(batch_receipt_id,intake_id,actor_id,gateway_instance_id,result,result_sha256,original_created_at,superseded_reason) SELECT batch_receipt_id,intake_id,actor_id,gateway_instance_id,result,result_sha256,created_at,'technical_effective_navision_wmi_vin_fix_471' FROM public.pdc_email_attachment_batch_receipts_323 WHERE batch_receipt_id='1527df81-e868-4b44-8a1d-7e8236345988'::uuid;
DELETE FROM public.pdc_email_attachment_batch_receipts_323 WHERE batch_receipt_id='1527df81-e868-4b44-8a1d-7e8236345988'::uuid;
DO $restore$ DECLARE d text;BEGIN SELECT definition INTO d FROM pdc_471_original_immutable;EXECUTE d;END $restore$;
UPDATE public.ai_email_intake SET status='received',locked_at=null,locked_by=null,claim_token=null,processing_result='{}'::jsonb,next_attempt_at=clock_timestamp(),permanent_failure=false,retry_class=null,last_error_code=null,error_details=null,updated_at=clock_timestamp() WHERE id='57de2d60-16f8-480c-89b3-c69505f5fb88'::uuid AND provider_uid='imap_uid:632' AND status='needs_review';
DO $post$ BEGIN
 IF public.pdc_navision_effective_vin_471(jsonb_build_object('wmi','MR0','vin','MABAV402402341'))<>'MR0MABAV402402341'
 OR EXISTS(SELECT 1 FROM public.pdc_email_attachment_batch_receipts_323 WHERE batch_receipt_id='1527df81-e868-4b44-8a1d-7e8236345988'::uuid)
 OR NOT EXISTS(SELECT 1 FROM public.pdc_email_attachment_batch_superseded_325 WHERE batch_receipt_id='1527df81-e868-4b44-8a1d-7e8236345988'::uuid AND superseded_reason='technical_effective_navision_wmi_vin_fix_471')
 OR NOT EXISTS(SELECT 1 FROM public.ai_email_intake WHERE id='57de2d60-16f8-480c-89b3-c69505f5fb88'::uuid AND status='received')
 THEN RAISE EXCEPTION 'PDC_471_POSTCONDITION_FAILED' USING errcode='55000';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827021000','471_navision_wmi_vin_uid632_retry',ARRAY['Canonicalize a Navision VIN from valid full VIN or valid WMI plus Navision VIN suffix','Patch current activation and reconciliation paths without weakening Stock authority identity conflicts or RLS','Preserve the original UID632 review receipt as superseded evidence and reopen only that exact intake for one technical retry','Production untouched']);NOTIFY pgrst,'reload schema';COMMIT;
