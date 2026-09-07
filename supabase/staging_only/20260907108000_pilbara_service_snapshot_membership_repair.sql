-- STAGING-only append repair: include active Pilbara Service vehicles in the
-- authenticated vehicle snapshot even when they have no email-import receipt.
-- Service operations remain read-only provenance and do not create receipts.
BEGIN;

DO $guard$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR to_regclass('public.pdc_pilbara_service_operations') IS NULL
     OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot_pre168()') IS NULL
     OR NOT EXISTS(
       SELECT 1 FROM supabase_migrations.schema_migrations
       WHERE (version,name)=('20260907107000','pilbara_service_null_safe_head_guard')
     )
     OR EXISTS(
       SELECT 1 FROM supabase_migrations.schema_migrations
       WHERE version~'^[0-9]{14}$' AND version::bigint>20260907107000
     ) THEN
    RAISE EXCEPTION 'PDC_PILBARA_SNAPSHOT_MEMBERSHIP_STAGING_OR_HEAD_MISMATCH';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre168()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $snapshot$
DECLARE v_role text; v_revision bigint; v_rows jsonb;
BEGIN
  v_role:=public.current_pdc_user_role()::text;
  IF v_role NOT IN ('viewer','operator','importer','administrator') THEN
    RETURN public.navision_backend_response(false,'unauthorized');
  END IF;
  SELECT revision INTO v_revision FROM public.pdc_email_vehicle_revision WHERE singleton;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,
    'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,
    'salesperson_reference',v.salesperson_reference,'registration',v.registration,'eta_to_kewdale',v.eta_to_kewdale,
    'current_location',v.current_location,'visible_on_board',v.visible_on_board,'source_system',v.source_system,
    'source_record_id',v.source_record_id,'updated_at',v.updated_at,
    'work_items',coalesce((SELECT jsonb_agg(jsonb_build_object('work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at,'completed_by',wi.completed_by) ORDER BY wi.work_key) FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id),'[]'::jsonb),
    'operation_lines',coalesce((SELECT jsonb_agg(jsonb_build_object('operation_line_id',ol.operation_line_id,'operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source,'source_uid',ol.source_uid,'job_card_number',ol.job_card_number,'source_row_no',ol.source_row_no,'source_contract',ol.source_contract,'source_ref',CASE WHEN ol.job_card_number IS NULL THEN ol.operation_no ELSE 'JC '||ol.job_card_number||' / '||ol.operation_no END,'created_at',ol.created_at) ORDER BY ol.source_row_no,CASE WHEN ol.operation_no LIKE 'OP%' THEN substring(ol.operation_no FROM 3)::integer ELSE substring(ol.operation_no FROM 3 FOR 3)::integer END,ol.operation_line_id) FROM (SELECT line.* FROM public.pdc_authenticated_email_operation_lines line WHERE line.vehicle_id=v.id ORDER BY line.created_at DESC,line.operation_line_id DESC LIMIT 50) ol),'[]'::jsonb),
    'parts_required',coalesce((SELECT pu.parts_required FROM public.vehicle_parts_updates pu WHERE pu.vehicle_id=v.id ORDER BY pu.updated_at DESC,pu.id DESC LIMIT 1),false),
    'parts_completed',coalesce((SELECT wi.completed FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND wi.work_key='PARTS'),false),
    'parts_update',coalesce((SELECT jsonb_build_object('parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,'parts_received',pu.parts_received,'parts_stoppage',pu.parts_stoppage,'parts_stoppage_reason',pu.parts_stoppage_reason,'worst_eta',pu.worst_eta,'previous_worst_eta',(SELECT prior.worst_eta FROM public.vehicle_parts_updates prior WHERE prior.vehicle_id=v.id AND prior.id<>pu.id AND prior.worst_eta IS NOT NULL ORDER BY prior.updated_at DESC,prior.id DESC LIMIT 1),'updated_by',pu.updated_by,'updated_at',pu.updated_at) FROM public.vehicle_parts_updates pu WHERE pu.vehicle_id=v.id ORDER BY pu.updated_at DESC,pu.id DESC LIMIT 1),'{}'::jsonb),
    'sublet_booking',coalesce((SELECT jsonb_build_object('provider',s.provider,'provider_email',s.provider_email,'po_sent_date',s.po_sent_date,'booking_date',s.booking_date,'expected_return_date',s.expected_return_date,'actual_return_date',s.actual_return_date,'notes',s.notes,'email_sent',s.email_sent,'version',s.version,'provider_names',coalesce(to_jsonb(s.provider_names),'[]'::jsonb),'provider_source',coalesce(s.provider_source,''),'updated_at',s.updated_at) FROM public.pdc_sublet_bookings s WHERE s.vehicle_id=v.id),'{}'::jsonb)
  ) ORDER BY coalesce(v.stock_number,v.vin,v.permanent_vehicle_id),v.id),'[]'::jsonb) INTO v_rows
  FROM public.vehicles v
  WHERE v.deleted_at IS NULL
    AND (
      (v.lifecycle_state IN('active','rft') AND v.visible_on_board)
      OR (
        v.lifecycle_state='completed' AND v.rft_collected_at IS NOT NULL
        AND EXISTS(
          SELECT 1 FROM public.pdc_rft_transport_action_receipts_412 handover
          WHERE handover.vehicle_id=v.id AND handover.action='collected'
        )
      )
    )
    AND (
      EXISTS(SELECT 1 FROM public.pdc_authenticated_email_import_receipts r WHERE r.vehicle_id=v.id)
      OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id)
      OR EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND lower(wi.work_key)='sublet' AND wi.required)
      OR EXISTS(SELECT 1 FROM public.pdc_sublet_bookings s WHERE s.vehicle_id=v.id)
      OR EXISTS(
        SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
        WHERE r.run_id='HERMES-TEST-RUN-20260824' AND r.vehicle_id=v.id AND r.stock_number=v.stock_number
          AND v.stock_number~'^HERMES-TEST-(00[1-9]|01[0-9]|020)$'
          AND v.source_system='hermes_overnight_synthetic' AND v.source_batch_id=r.run_id AND v.source_record_id=r.stock_number
          AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
      )
    );
  RETURN public.navision_backend_response(true,'ok',jsonb_build_object(
    'revision',coalesce(v_revision,1),'vehicles',v_rows
  ));
END
$snapshot$;

REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre168()
FROM PUBLIC,anon,authenticated,service_role;

UPDATE public.pdc_email_vehicle_revision
SET revision=revision+1,updated_at=clock_timestamp()
WHERE singleton;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES(
  '20260907108000',
  'pilbara_service_snapshot_membership_repair',
  ARRAY[
    'Include active visible vehicles with Pilbara Service operations in the existing authenticated snapshot membership predicate.',
    'Preserve the existing receipt, Sublet, completed-RFT and synthetic-fixture snapshot paths.',
    'Do not create email receipts or alter vehicle identity, lifecycle, Service operations, Production, or outbound email.'
  ]
);

NOTIFY pgrst,'reload schema';
COMMIT;
