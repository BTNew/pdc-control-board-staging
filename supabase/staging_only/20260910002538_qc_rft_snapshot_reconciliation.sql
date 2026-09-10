-- STAGING ONLY: reconcile QC/RFT display fields from the canonical vehicle.
-- CLI-created migration; filename aligned to the applied STAGING ledger version.
-- No vehicle, inspection, photo, receipt, or transport state is mutated.
DO $migration$
DECLARE d text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' THEN
  RAISE EXCEPTION 'STAGING required';
 END IF;
 SELECT pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure) INTO d;
 IF md5(d)<>'c5294ba6b630af5fc1fa8f454eff9ef7' THEN
  RAISE EXCEPTION 'Snapshot changed since review';
 END IF;
 d:=replace(d,
  'row_value||jsonb_build_object(',
  'row_value||jsonb_build_object(
    ''qc_completed_at'',canonical.qc_completed_at,
    ''qc_completed_by'',canonical.qc_completed_by,
    ''rft_transferred_at'',canonical.rft_transferred_at,');
 d:=replace(d,
  'CROSS JOIN LATERAL (',
  'JOIN public.vehicles canonical ON canonical.id=(row_value->>''id'')::uuid
  CROSS JOIN LATERAL (');
 EXECUTE d;
END $migration$;
