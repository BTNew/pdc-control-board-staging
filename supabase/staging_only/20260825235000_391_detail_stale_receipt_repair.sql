-- STAGING ONLY 391: record stale detail receipts without null version rows.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-391-detail-stale-receipt-repair',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825234000' AND name='390_synthetic_detail_snapshot_identity')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825234000')
   OR to_regprocedure('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)') IS NULL THEN
  RAISE EXCEPTION 'PDC_391_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $pre$;
DO $repair$
DECLARE v_def text; v_old text; v_new text;
BEGIN
 SELECT pg_get_functiondef('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'::regprocedure) INTO v_def;
 v_old:=$old$IF NOT FOUND OR v_before.deleted_at IS NOT NULL THEN
   v_response:=jsonb_build_object('ok',false,'code','vehicle_not_found');$old$;
 v_new:=$new$IF NOT FOUND OR v_before.deleted_at IS NOT NULL THEN
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
   v_response:=jsonb_build_object('ok',false,'code','vehicle_not_found');$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'PDC_391_NOT_FOUND_REPAIR_ANCHOR_MISSING'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 v_old:=$old$ELSIF v_before.version<>p_expected_vehicle_version THEN
   -- Stable contract error: PDC_388_VEHICLE_VERSION_CONFLICT.
   v_response:=jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v_before.id,'vehicle_version',v_before.version));$old$;
 v_new:=$new$ELSIF v_before.version<>p_expected_vehicle_version THEN
   -- Stable contract error: PDC_388_VEHICLE_VERSION_CONFLICT.
   v_after:=v_before;
   v_response:=jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v_before.id,'vehicle_version',v_before.version));$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'PDC_391_STALE_REPAIR_ANCHOR_MISSING'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 EXECUTE v_def;
END $repair$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825235000','391_detail_stale_receipt_repair',ARRAY['Stale detail sessions now return a receipt-backed version conflict with a non-null current version and missing vehicles fail closed before receipt insertion']);
NOTIFY pgrst,'reload schema';
COMMIT;
