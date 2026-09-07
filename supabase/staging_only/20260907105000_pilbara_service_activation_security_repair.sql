-- STAGING ONLY: restore direct activation authorization and isolate the Pilbara apply path.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-pilbara-service-activation-security-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM '(20260907104000,pilbara_service_pre_delivery_link_gate)'
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260907105000')
  THEN RAISE EXCEPTION 'PDC_20260907105000_STAGING_PREDECESSOR_OR_SCOPE_GUARD_FAILED' USING ERRCODE='55000';
  END IF;
END
$guard$;

-- Preserve the already-applied activation implementation as an owner-only primitive.
ALTER FUNCTION public.activate_navision_backend_record(text,uuid,bigint,text)
  RENAME TO pdc_activate_navision_backend_record_internal_v1;
REVOKE ALL ON FUNCTION public.pdc_activate_navision_backend_record_internal_v1(text,uuid,bigint,text)
  FROM PUBLIC,anon,authenticated,service_role;

-- Restore the ordinary direct RPC contract: viewers cannot activate records directly.
CREATE OR REPLACE FUNCTION public.activate_navision_backend_record(
  p_idempotency_key text,
  p_backend_record_id uuid,
  p_expected_revision bigint,
  p_activation_source text DEFAULT 'manual'::text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $direct$
DECLARE v_role text:=public.current_pdc_user_role()::text;
BEGIN
  IF NOT coalesce(v_role = any(array['operator','importer','administrator']), false) THEN
    RETURN public.navision_backend_response(false,'unauthorized');
  END IF;
  RETURN public.pdc_activate_navision_backend_record_internal_v1(
    p_idempotency_key,p_backend_record_id,p_expected_revision,p_activation_source);
END
$direct$;
REVOKE ALL ON FUNCTION public.activate_navision_backend_record(text,uuid,bigint,text)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.activate_navision_backend_record(text,uuid,bigint,text) TO authenticated;

-- This capability has no API grant. Only the owner-executed apply function below can reach it.
CREATE FUNCTION public.pdc_pilbara_service_activate_backend_record_v1(
  p_preview_batch_id uuid,
  p_source_hash text,
  p_backend_record_id uuid,
  p_expected_revision bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $private$
DECLARE
  v_role text:=public.current_pdc_user_role()::text;
  v_actor uuid:=auth.uid();
  v_preview public.pdc_pilbara_service_import_batches%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_stock_number text;
  v_key text;
BEGIN
  IF current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN public.navision_backend_response(false,'wrong_environment');
  END IF;
  IF v_actor IS NULL OR NOT coalesce(v_role='viewer',false)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i
       WHERE i.auth_user_id=v_actor
         AND i.normalized_email=lower(btrim(coalesce(auth.jwt()->>'email','')))
         AND i.environment='staging'
         AND i.identity_purpose='pdc_email_ai_transaction_successor'
         AND i.active AND i.revoked_at IS NULL)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
       WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL) THEN
    RETURN public.navision_backend_response(false,'unauthorized');
  END IF;

  SELECT * INTO v_preview
  FROM public.pdc_pilbara_service_import_batches
  WHERE batch_id=p_preview_batch_id AND batch_kind='preview'
  FOR SHARE;
  IF NOT FOUND
     OR v_preview.source_hash<>lower(btrim(p_source_hash))
     OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false)
     OR (v_preview.response->'matched'->>'stocks')::integer<>21
     OR (v_preview.response->'matched'->>'lines')::integer<>122
     OR (v_preview.response->'unmatched'->>'stocks')::integer<>16
     OR (v_preview.response->'unmatched'->>'lines')::integer<>39
     OR (v_preview.response->'ambiguous'->>'stocks')::integer<>0
     OR v_preview.quarantined_line_count<>40
     OR v_preview.conflict_count<>0
     OR (SELECT count(*) FROM public.pdc_pilbara_service_import_rows r
         WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged'))<>122
     OR (SELECT count(DISTINCT r.backend_record_id) FROM public.pdc_pilbara_service_import_rows r
         WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged'))<>21
     OR (SELECT count(DISTINCT btrim(r.stock_number)) FROM public.pdc_pilbara_service_import_rows r
         WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged'))<>21 THEN
    RETURN public.navision_backend_response(false,'apply_not_eligible');
  END IF;

  SELECT b.* INTO v_record
  FROM public.navision_backend_records b
  WHERE b.id=p_backend_record_id
    AND b.source_system='microsoft_navision'
    AND b.dealer_code='37047'
    AND b.is_current
    AND b.record_status='current'
    AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r
      WHERE r.batch_id=v_preview.batch_id
        AND r.backend_record_id=p_backend_record_id
        AND r.decision IN('insert','unchanged'))
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.navision_backend_response(false,'activation_out_of_scope');
  END IF;

  v_stock_number:=btrim(coalesce(v_record.normalized_data->>'batch',v_record.normalized_data->>'stock',''));
  IF v_stock_number=''
     OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r
       WHERE r.batch_id=v_preview.batch_id
         AND r.backend_record_id=p_backend_record_id
         AND r.decision IN('insert','unchanged')
         AND btrim(r.stock_number)<>v_stock_number)
     OR (SELECT count(*) FROM public.navision_backend_records b
         WHERE b.source_system='microsoft_navision'
           AND b.dealer_code='37047'
           AND b.is_current
           AND b.record_status='current'
           AND btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=v_stock_number)<>1
     OR (SELECT count(*) FROM public.vehicles v
         WHERE v.deleted_at IS NULL AND btrim(v.stock_number)=v_stock_number)>1
     OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r
       WHERE r.batch_id=v_preview.batch_id
         AND r.backend_record_id=p_backend_record_id
         AND r.decision IN('insert','unchanged')
         AND ((r.vehicle_id IS NULL AND EXISTS(SELECT 1 FROM public.vehicles v
                WHERE v.deleted_at IS NULL AND btrim(v.stock_number)=v_stock_number))
           OR (r.vehicle_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.vehicles v
                WHERE v.deleted_at IS NULL AND v.id=r.vehicle_id AND btrim(v.stock_number)=v_stock_number)))) THEN
    RETURN public.navision_backend_response(false,'activation_cardinality_changed');
  END IF;

  v_key:='pilbara-service-v1-'||substr(v_preview.source_hash,1,24)||'-'||p_backend_record_id::text;
  RETURN public.pdc_activate_navision_backend_record_internal_v1(
    v_key,p_backend_record_id,p_expected_revision,'approved_email_build');
END
$private$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_activate_backend_record_v1(uuid,text,uuid,bigint)
  FROM PUBLIC,anon,authenticated,service_role;

-- Replace only the reviewed activation call in the already-applied SECURITY DEFINER apply body.
DO $repair_apply$
DECLARE
  v_definition text;
  v_old text:=$old$    v_activation:=public.activate_navision_backend_record(
      'pilbara-service-v1-'||substr(v_preview.source_hash,1,24)||'-'||substr(v_backend::text,1,8),
      v_backend,v_revision,'approved_email_build');$old$;
  v_new text:=$new$    v_activation:=public.pdc_pilbara_service_activate_backend_record_v1(
      v_preview.batch_id,v_preview.source_hash,v_backend,v_revision);$new$;
BEGIN
  SELECT pg_get_functiondef('public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)
    INTO v_definition;
  IF v_definition IS NULL
     OR strpos(v_definition,v_old)=0
     OR strpos(replace(v_definition,v_old,''),v_old)>0
     OR strpos(v_definition,'SECURITY DEFINER')=0 THEN
    RAISE EXCEPTION 'PDC_20260907105000_APPLY_SOURCE_ANCHOR_FAILED' USING ERRCODE='55000';
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);
END
$repair_apply$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260907105000','pilbara_service_activation_security_repair',ARRAY[
  'restore direct activate_navision_backend_record authorization to operator importer and administrator roles only',
  'isolate scoped Pilbara viewer activation behind an ACL-closed SECURITY DEFINER path with exact preview source dealer current-record and cardinality bounds',
  'bind each activation receipt idempotency key to the complete backend UUID and route only the Pilbara apply function through the private path'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
