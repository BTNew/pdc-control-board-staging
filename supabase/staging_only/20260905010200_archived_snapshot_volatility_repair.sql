-- STAGING ONLY: restore archived snapshot volatility after lifecycle wrapper.
-- The wrapper introduced by 20260830093000 was declared STABLE while its
-- administrator scope helper takes a row lock. PostgreSQL executes STABLE
-- functions in a read-only context, so the authenticated read failed with 25006.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-archived-snapshot-volatility-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_admin_archived_vehicle_snapshot(uuid,integer)'::regprocedure) INTO d;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260905010100,navision_projection_cleanup_evidence_parity)'
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260905010200')
     OR to_regprocedure('public.pdc_admin_archived_vehicle_snapshot(uuid,integer)') IS NULL
     OR position('pdc_admin_archived_vehicle_snapshot_pre_82000' in coalesce(d,''))=0
  THEN RAISE EXCEPTION 'PDC_ARCHIVED_SNAPSHOT_VOLATILITY_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_admin_archived_vehicle_snapshot(p_tombstone_id uuid DEFAULT NULL,p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public AS $archive$
DECLARE base jsonb; rows jsonb;
BEGIN
  base:=public.pdc_admin_archived_vehicle_snapshot_pre_82000(p_tombstone_id,p_limit);
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('lifecycle_history',public.pdc_lifecycle_history_payload_82000((x->>'vehicle_id')::uuid)) ORDER BY x->>'deleted_at' DESC),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,items}','[]'::jsonb)) x;
  RETURN jsonb_set(base,'{data,items}',rows,true);
END $archive$;
REVOKE ALL ON FUNCTION public.pdc_admin_archived_vehicle_snapshot(uuid,integer) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_admin_archived_vehicle_snapshot(uuid,integer) TO authenticated;

DO $verify$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_admin_archived_vehicle_snapshot(uuid,integer)'::regprocedure) INTO d;
  IF NOT EXISTS(
       SELECT 1 FROM pg_proc p
       WHERE p.oid=to_regprocedure('public.pdc_admin_archived_vehicle_snapshot(uuid,integer)')
         AND p.provolatile='v'
     )
     OR position('pdc_lifecycle_history_payload_82000' in d)=0
     OR NOT has_function_privilege('authenticated','public.pdc_admin_archived_vehicle_snapshot(uuid,integer)','execute')
     OR has_function_privilege('anon','public.pdc_admin_archived_vehicle_snapshot(uuid,integer)','execute')
     OR has_function_privilege('service_role','public.pdc_admin_archived_vehicle_snapshot(uuid,integer)','execute')
  THEN RAISE EXCEPTION 'PDC_ARCHIVED_SNAPSHOT_VOLATILITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $verify$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260905010200',
  'archived_snapshot_volatility_repair',
  ARRAY[
    'Restore VOLATILE execution for the current lifecycle-enriched administrator archived snapshot wrapper',
    'Preserve authenticated-only execution, fixed search_path and lifecycle-history projection',
    'Production untouched'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
