-- Staging-only exact Stock bridge: attach one active workbook vehicle to one current Navision backend record.
-- This expands no generic DML authority and preserves Manager + independent Administrator approval.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-355-workbook-navision-bridge',0));
DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_355_WRONG_ENVIRONMENT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260824150000' AND name='354_full_vehicle_history_reset')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260824150000' AND version~'^[0-9]{14}$') THEN
  RAISE EXCEPTION 'PDC_355_MIGRATION_HEAD_MISMATCH';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_full_reset_receipts_354 WHERE action_key='craig-full-vehicle-history-reset-20260824') THEN
  RAISE EXCEPTION 'PDC_355_RESET_PREDECESSOR_MISSING';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_verified_backup_manifests WHERE backup_manifest_sha256='0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0') THEN
  RAISE EXCEPTION 'PDC_355_VERIFIED_BACKUP_MISSING';
 END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_pmb_workbook_canonical_candidate(p_pair_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $candidate$
DECLARE
 p public.pdc_pmb_workbook_pair_reviews%rowtype;r public.navision_backend_records%rowtype;v public.vehicles%rowtype;
 a public.navision_board_activations%rowtype;backend_ids uuid[]:='{}';owner_ids uuid[]:='{}';vin_ids uuid[]:='{}';stock text;target_vin text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR p_pair_id IS NULL THEN RETURN jsonb_build_object('eligible',false,'reason','wrong_environment_or_input');END IF;
 SELECT * INTO p FROM public.pdc_pmb_workbook_pair_reviews WHERE pair_id=p_pair_id;
 IF NOT FOUND OR p.stock_number IS NULL
   OR NOT ((p.classification='no_current_stock_manager_override_required' AND p.reason_code='manager_stock_only_create_required')
        OR (p.classification='terminal_identity_conflict' AND p.reason_code='canonical_stock_activation_or_owner_conflict'))
 THEN RETURN jsonb_build_object('eligible',false,'reason','pair_not_canonical_activation_quarantine');END IF;
 stock:=public.normalize_vehicle_stock_number(p.stock_number);
 IF stock='13056899' THEN RETURN jsonb_build_object('eligible',false,'reason','terminal_excluded_stock13056899');END IF;
 SELECT coalesce(array_agg(x.id ORDER BY x.id),'{}'::uuid[]) INTO backend_ids FROM public.navision_backend_records x
 WHERE x.source_system='microsoft_navision' AND x.dealer_code IN('14450','37047') AND x.is_current AND x.record_status='current'
   AND public.normalize_vehicle_stock_number(x.normalized_data->>'batch')=stock;
 IF cardinality(backend_ids)<>1 THEN RETURN jsonb_build_object('eligible',false,'reason','current_navision_stock_not_exactly_one');END IF;
 SELECT * INTO STRICT r FROM public.navision_backend_records WHERE id=backend_ids[1];
 IF public.navision_operational_location(r.normalized_data)='Completed' THEN RETURN jsonb_build_object('eligible',false,'reason','protected_backend_completed');END IF;
 target_vin:=CASE WHEN public.is_valid_vehicle_vin(r.normalized_data->>'vin') THEN public.normalize_vehicle_vin(r.normalized_data->>'vin') ELSE NULL END;
 SELECT coalesce(array_agg(DISTINCT vehicle_id ORDER BY vehicle_id),'{}'::uuid[]) INTO owner_ids FROM(
  SELECT x.id vehicle_id FROM public.vehicles x WHERE x.stock_number_normalized=stock
  UNION ALL SELECT x.vehicle_id FROM public.vehicle_aliases x WHERE x.alias_type_normalized='stock_number' AND x.normalized_alias_value=stock
 ) owners;
 IF target_vin IS NOT NULL THEN
  SELECT coalesce(array_agg(DISTINCT vehicle_id ORDER BY vehicle_id),'{}'::uuid[]) INTO vin_ids FROM(
   SELECT x.id vehicle_id FROM public.vehicles x WHERE x.vin_normalized=target_vin
   UNION ALL SELECT x.vehicle_id FROM public.vehicle_aliases x WHERE x.alias_type_normalized='vin' AND x.normalized_alias_value=target_vin
  ) owners;
 END IF;
 IF r.canonical_vehicle_id IS NULL THEN
  IF EXISTS(SELECT 1 FROM public.navision_board_activations x WHERE x.backend_record_id=r.id OR public.normalize_vehicle_stock_number(x.activated_stock_number)=stock)
    OR EXISTS(SELECT 1 FROM public.vehicles x WHERE x.source_system_normalized='microsoft_navision' AND x.source_record_id_normalized=public.normalize_vehicle_source_identifier(r.id::text)) THEN
   RETURN jsonb_build_object('eligible',false,'reason','existing_navision_identity_surface_conflict');
  END IF;
  IF cardinality(owner_ids)=0 AND cardinality(vin_ids)=0 THEN
   RETURN jsonb_build_object('eligible',true,'action','create_canonical_vehicle','backend_record_id',r.id,'backend_record_version',r.version,
    'target_vehicle_id',NULL,'target_vehicle_version',NULL,'stock_number',stock);
  END IF;
  IF cardinality(owner_ids)=1 THEN
   SELECT * INTO v FROM public.vehicles WHERE id=owner_ids[1];
   IF FOUND AND v.deleted_at IS NULL AND v.lifecycle_state='active' AND v.visible_on_board AND v.board_purged_at IS NULL
     AND v.rft_collected_at IS NULL AND upper(btrim(coalesce(v.current_location,'')))<>'COMPLETED'
     AND v.stock_number_normalized=stock AND v.source_system_normalized='pdc_pmb_workbook'
     AND NOT EXISTS(SELECT 1 FROM unnest(vin_ids) z WHERE z<>v.id)
     AND (target_vin IS NULL OR v.vin_normalized IS NULL OR v.vin_normalized=target_vin) THEN
    RETURN jsonb_build_object('eligible',true,'action','attach_exact_existing_workbook_vehicle','backend_record_id',r.id,
     'backend_record_version',r.version,'target_vehicle_id',v.id,'target_vehicle_version',v.version,'stock_number',stock);
   END IF;
  END IF;
  RETURN jsonb_build_object('eligible',false,'reason','exact_existing_workbook_identity_conflict');
 END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=r.canonical_vehicle_id;
 IF NOT FOUND OR cardinality(owner_ids)<>1 OR owner_ids[1] IS DISTINCT FROM v.id
   OR EXISTS(SELECT 1 FROM unnest(vin_ids) z WHERE z<>v.id)
   OR v.stock_number_normalized IS DISTINCT FROM stock OR v.board_purged_at IS NULL OR v.deleted_at IS NULL
   OR v.lifecycle_state<>'deleted' OR v.visible_on_board OR v.rft_collected_at IS NOT NULL
   OR upper(btrim(coalesce(v.current_location,'')))='COMPLETED'
   OR nullif(btrim(coalesce(v.deleted_reason,'')),'') IS NULL
   OR v.deleted_reason IS DISTINCT FROM v.board_purge_reason OR v.board_purged_by IS NULL
   OR v.pmb_stage IS NOT NULL OR v.pmb_bay_stage IS NOT NULL OR v.pmb_bay_number IS NOT NULL
   OR v.active_workshop_booking_id IS NOT NULL
   OR EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id)
   OR EXISTS(SELECT 1 FROM public.vehicle_work_items x WHERE x.vehicle_id=v.id)
   OR EXISTS(SELECT 1 FROM public.vehicle_parts_updates x WHERE x.vehicle_id=v.id)
   OR EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments x WHERE x.vehicle_id=v.id)
   OR EXISTS(SELECT 1 FROM public.vehicle_sublet_providers x WHERE x.vehicle_id=v.id)
   OR EXISTS(SELECT 1 FROM public.pdc_sublet_bookings x WHERE x.vehicle_id=v.id) THEN
  RETURN jsonb_build_object('eligible',false,'reason','not_exact_complete_board_purge_tombstone');
 END IF;
 SELECT * INTO a FROM public.navision_board_activations WHERE backend_record_id=r.id;
 IF NOT FOUND OR a.canonical_vehicle_id IS DISTINCT FROM v.id OR a.active OR a.completed_at IS NULL
   OR a.completion_reason IS DISTINCT FROM 'Staging board purge'
   OR public.normalize_vehicle_stock_number(a.activated_stock_number) IS DISTINCT FROM stock
   OR EXISTS(SELECT 1 FROM public.navision_board_activations x WHERE x.backend_record_id<>r.id AND public.normalize_vehicle_stock_number(x.activated_stock_number)=stock) THEN
  RETURN jsonb_build_object('eligible',false,'reason','purged_activation_binding_conflict');
 END IF;
 RETURN jsonb_build_object('eligible',true,'action','reactivate_complete_board_purge','backend_record_id',r.id,'backend_record_version',r.version,
  'target_vehicle_id',v.id,'target_vehicle_version',v.version,'stock_number',stock);
END $candidate$;
REVOKE ALL ON FUNCTION public.pdc_pmb_workbook_canonical_candidate(uuid) FROM public,anon,authenticated,service_role;
COMMENT ON FUNCTION public.pdc_pmb_workbook_canonical_candidate(uuid) IS
 'Staging-only fail-closed candidate. Migration355 permits one exact active pdc_pmb_workbook Stock owner to attach to one current non-completed Navision backend record through the existing Manager + independent Administrator canonical activation contract.';

DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_pmb_workbook_canonical_candidate(uuid)'::regprocedure) INTO d;
 IF position('attach_exact_existing_workbook_vehicle' IN d)=0
   OR position('source_system_normalized=''pdc_pmb_workbook''' IN d)=0
   OR position('current_navision_stock_not_exactly_one' IN d)=0
   OR has_function_privilege('authenticated','public.pdc_pmb_workbook_canonical_candidate(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_355_CANDIDATE_INSTALL_POSTCONDITION_FAILED';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260824160000','355_attach_existing_workbook_vehicle_to_navision',array[
 'Require exact staging sentinel, verified pre-reset backup, reset receipt and migration 354 head',
 'Permit only one exact active pdc_pmb_workbook Stock owner to attach to one current non-completed Navision backend record',
 'Preserve Manager approval, independent Administrator countersignature, canonical Apply receipt and fail-closed identity checks',
 'Grant no direct candidate execution, generic DML, Monitor, mailbox, writer or Production authority'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
