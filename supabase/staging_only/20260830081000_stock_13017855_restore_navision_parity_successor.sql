-- STAGING ONLY 773: parity-safe successor for the exact 13017855 restore.
-- Patches only the existing 772 restore body so the restored Navision-linked row
-- satisfies the current deferred parity contract without recreating source data.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-stock-13017855-restore-parity-773',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260830080000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830080000' AND name='stock_13017855_integrity_and_lifecycle_guards')<>1
    OR to_regprocedure('public.restore_stock_13017855_archived_vehicle_772(uuid,uuid,integer,text,text,text,text)') IS NULL
    OR exists(select 1 from supabase_migrations.schema_migrations where version='20260830081000')
 THEN RAISE EXCEPTION 'PDC_773_EXACT_772_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;
DO $patch$
DECLARE d text; n text;
BEGIN
 SELECT pg_get_functiondef('public.restore_stock_13017855_archived_vehicle_772(uuid,uuid,integer,text,text,text,text)'::regprocedure) INTO d;
 IF (length(d)-length(replace(d,'UPDATE public.vehicles SET stock_number=t.stock_number','')))/length('UPDATE public.vehicles SET stock_number=t.stock_number')<>1
    OR position('navision_updated_at' in d)>0 THEN
  RAISE EXCEPTION 'PDC_773_RESTORE_PATCH_ANCHOR_DRIFT' USING errcode='55000';
 END IF;
 n:=replace(d,'UPDATE public.vehicles SET stock_number=t.stock_number',
   'UPDATE public.vehicles SET source_payload=coalesce(v.source_payload,''{}''::jsonb)||jsonb_build_object(''navision_version'',(select x.version from public.navision_backend_records x where x.id=''e39eb741-cf03-44f2-8a75-54362ecc8a26''::uuid),''navision_status'',(select x.normalized_data->>''toyotaStatus'' from public.navision_backend_records x where x.id=''e39eb741-cf03-44f2-8a75-54362ecc8a26''::uuid),''navision_updated_at'',(select x.updated_at from public.navision_backend_records x where x.id=''e39eb741-cf03-44f2-8a75-54362ecc8a26''::uuid)),stock_number=t.stock_number');
 EXECUTE n;
 SELECT pg_get_functiondef('public.restore_stock_13017855_archived_vehicle_772(uuid,uuid,integer,text,text,text,text)'::regprocedure) INTO d;
 IF position('navision_updated_at' in d)=0 OR position('e39eb741-cf03-44f2-8a75-54362ecc8a26' in d)=0 THEN RAISE EXCEPTION 'PDC_773_RESTORE_PATCH_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $patch$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830081000','stock_13017855_restore_navision_parity_successor',ARRAY[
 'Exact append-only successor after 20260830080000/stock_13017855_integrity_and_lifecycle_guards',
 'Refresh only the linked Navision source projection version/status/timestamp from backend record e39eb741-cf03-44f2-8a75-54362ecc8a26 during exact restore',
 'Preserve archived UUID, tombstone, expected version 19, source operation evidence, Parts receipt, booking history and all 772 guards',
 'Production sentinel and production data remain untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
