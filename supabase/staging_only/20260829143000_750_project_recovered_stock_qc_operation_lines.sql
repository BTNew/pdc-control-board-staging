-- STAGING ONLY 750: expose the restored Stock 13000769 operation-line
-- projection through the existing Board RPC so mobile QC can render all 17
-- lines. The pre-750 implementation remains callable under its versioned name.
BEGIN;
SET LOCAL lock_timeout='30s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-747-recover-stock-13000769',0));
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260829142000' AND name='749_append_qc_retest_photo_evidence')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260829142000')
  THEN RAISE EXCEPTION 'PDC_750_STAGING_OR_PREDECESSOR_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;
ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_750;
CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r jsonb; rows jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_750();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  SELECT coalesce(jsonb_agg(
    x || CASE WHEN (x->>'id')='d777b071-a2b0-5367-893b-aa83a07fcfce' THEN jsonb_build_object(
      'operation_lines',coalesce(public.pdc_qc_operation_lines_379((x->>'id')::uuid),'[]'::jsonb),
      'qc_retest',jsonb_build_object(
        'cycle_id',(SELECT cycle_id FROM public.pdc_qc_retest_events_747 e WHERE e.vehicle_id=(x->>'id')::uuid AND e.event_kind='recovered_to_qc' ORDER BY e.created_at DESC LIMIT 1),
        'fresh_cycle_open',NOT EXISTS(SELECT 1 FROM public.pdc_qc_retest_events_747 e WHERE e.vehicle_id=(x->>'id')::uuid AND e.event_kind='qc_signed_off_to_rft'),
        'fresh_photo_accepted',EXISTS(SELECT 1 FROM public.pdc_qc_retest_events_747 e WHERE e.vehicle_id=(x->>'id')::uuid AND e.event_kind='fresh_photo_accepted'),
        'prior_qc_evidence_superseded',EXISTS(SELECT 1 FROM public.pdc_qc_retest_supersessions_747 s WHERE s.vehicle_id=(x->>'id')::uuid))
    ) ELSE '{}'::jsonb END
    ORDER BY x->>'stock_number'),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260829143000','750_project_recovered_stock_qc_operation_lines',ARRAY['Preserve the pre-750 Board snapshot implementation under an append-only versioned alias','Project exactly 17 authoritative QC operation lines and retest markers for canonical Stock 13000769 only','No other vehicle projection, production target or immutable evidence is modified']);
NOTIFY pgrst,'reload schema';
COMMIT;
