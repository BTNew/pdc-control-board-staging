-- STAGING ONLY 364: project the exact registry-bound overnight fleet through Vehicle Locations.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-364-overnight-synthetic-projection',0));

-- Close containment races even though this migration changes only one read contract.
LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;
LOCK TABLE public.pdc_overnight_synthetic_fleet_registry_363 IN SHARE MODE;
LOCK TABLE public.vehicles IN SHARE MODE;

DO $guard$
DECLARE v_pre168_sha text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825000000' AND name='363_overnight_synthetic_fleet_bootstrap')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260825000000' AND version~'^[0-9]{14}$')
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR (SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_registry_363 WHERE run_id='HERMES-TEST-RUN-20260824')<>20 THEN
  RAISE EXCEPTION 'PDC_364_STAGING_TARGET_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
 SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure),'UTF8'),'sha256'),'hex')
 INTO v_pre168_sha;
 IF v_pre168_sha IS DISTINCT FROM '0fc5dadf39c25c2779a61e19552b606de35327c524f7111461b13c54436b9d48' THEN
  RAISE EXCEPTION 'PDC_364_PRE168_FUNCTION_DRIFT' USING errcode='55000';
 END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre168()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
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
    'work_items',coalesce((SELECT jsonb_agg(jsonb_build_object('work_key',wi.work_key,'required',wi.required,'completed',wi.completed,
      'completed_at',wi.completed_at,'completed_by',wi.completed_by) ORDER BY wi.work_key) FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id),'[]'::jsonb),
    'operation_lines',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'operation_line_id',ol.operation_line_id,'operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,
      'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source,'source_uid',ol.source_uid,
      'job_card_number',ol.job_card_number,'source_row_no',ol.source_row_no,'source_contract',ol.source_contract,
      'source_ref',CASE WHEN ol.job_card_number IS NULL THEN ol.operation_no ELSE 'JC '||ol.job_card_number||' / '||ol.operation_no END,
      'created_at',ol.created_at) ORDER BY ol.source_row_no,
        CASE WHEN ol.operation_no LIKE 'OP%' THEN substring(ol.operation_no FROM 3)::integer ELSE substring(ol.operation_no FROM 3 FOR 3)::integer END,
        ol.operation_line_id) FROM (SELECT line.* FROM public.pdc_authenticated_email_operation_lines line
          WHERE line.vehicle_id=v.id ORDER BY line.created_at DESC,line.operation_line_id DESC LIMIT 50) ol),'[]'::jsonb),
    'parts_required',coalesce((SELECT pu.parts_required FROM public.vehicle_parts_updates pu WHERE pu.vehicle_id=v.id ORDER BY pu.updated_at DESC,pu.id DESC LIMIT 1),false),
    'parts_completed',coalesce((SELECT wi.completed FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND wi.work_key='PARTS'),false),
    'parts_update',coalesce((SELECT jsonb_build_object('parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,
      'parts_received',pu.parts_received,'parts_stoppage',pu.parts_stoppage,'parts_stoppage_reason',pu.parts_stoppage_reason,
      'worst_eta',pu.worst_eta,'previous_worst_eta',(SELECT prior.worst_eta FROM public.vehicle_parts_updates prior WHERE prior.vehicle_id=v.id AND prior.id<>pu.id AND prior.worst_eta IS NOT NULL ORDER BY prior.updated_at DESC,prior.id DESC LIMIT 1),
      'updated_by',pu.updated_by,'updated_at',pu.updated_at) FROM public.vehicle_parts_updates pu WHERE pu.vehicle_id=v.id ORDER BY pu.updated_at DESC,pu.id DESC LIMIT 1),'{}'::jsonb),
    'sublet_booking',coalesce((SELECT jsonb_build_object('provider',s.provider,'provider_email',s.provider_email,
      'po_sent_date',s.po_sent_date,'booking_date',s.booking_date,'expected_return_date',s.expected_return_date,
      'actual_return_date',s.actual_return_date,'notes',s.notes,'email_sent',s.email_sent,'version',s.version,
      'provider_names',coalesce(to_jsonb(s.provider_names),'[]'::jsonb),'provider_source',coalesce(s.provider_source,''),'updated_at',s.updated_at)
      FROM public.pdc_sublet_bookings s WHERE s.vehicle_id=v.id),'{}'::jsonb)
  ) ORDER BY coalesce(v.stock_number,v.vin,v.permanent_vehicle_id),v.id),'[]'::jsonb) INTO v_rows
  FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND v.visible_on_board
    AND (
      EXISTS(SELECT 1 FROM public.pdc_authenticated_email_import_receipts r WHERE r.vehicle_id=v.id)
      OR EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND lower(wi.work_key)='sublet' AND wi.required)
      OR EXISTS(SELECT 1 FROM public.pdc_sublet_bookings s WHERE s.vehicle_id=v.id)
      OR EXISTS(
        SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
        WHERE r.run_id='HERMES-TEST-RUN-20260824' AND r.vehicle_id=v.id
          AND r.stock_number=v.stock_number AND r.customer_name=v.customer_name
          AND r.job_card_number=v.job_card_number AND r.vehicle_description=v.vehicle_description
          AND v.stock_number~'^HERMES-TEST-(00[1-9]|01[0-9]|020)$'
          AND v.source_system='hermes_overnight_synthetic'
          AND v.source_batch_id=r.run_id AND v.source_record_id=r.stock_number
          AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
      )
    );
  RETURN public.navision_backend_response(true,'ok',jsonb_build_object('revision',coalesce(v_revision,1),'vehicles',v_rows));
END;
$snapshot$;
-- CREATE OR REPLACE preserves the exact predecessor owner and ACL. Do not
-- broaden or narrow this private helper's authority in the projection repair.

DO $postcondition$
BEGIN
 IF (SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_registry_363 r
     JOIN public.vehicles v ON v.id=r.vehicle_id
     WHERE r.run_id='HERMES-TEST-RUN-20260824' AND v.deleted_at IS NULL AND v.lifecycle_state='active' AND v.visible_on_board
       AND r.stock_number=v.stock_number AND r.customer_name=v.customer_name AND r.job_card_number=v.job_card_number
       AND r.vehicle_description=v.vehicle_description AND v.source_system='hermes_overnight_synthetic'
       AND v.source_batch_id=r.run_id AND v.source_record_id=r.stock_number
       AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only')<>20
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_364_POSTCONDITION_FAILED' USING errcode='55000';
 END IF;
END $postcondition$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825010000','364_overnight_synthetic_snapshot_projection',ARRAY['exact guarded staging-only Vehicle Locations projection for registry-bound HERMES-TEST fleet']);
COMMIT;
