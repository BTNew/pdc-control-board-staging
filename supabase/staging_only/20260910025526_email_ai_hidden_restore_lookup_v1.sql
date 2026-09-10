DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'STAGING only';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.pdc_email_ai_lookup_hidden_restore_context_v1(
  p_stock_number text,
  p_vehicle_id uuid,
  p_backend_record_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
SET statement_timeout TO '30s'
AS $$
DECLARE
  v_stock text:=btrim(coalesce(p_stock_number,''));
  v_vehicle public.vehicles%rowtype;
  v_backend public.navision_backend_records%rowtype;
  v_tombstone public.pdc_vehicle_tombstones%rowtype;
  v_tombstone_count integer:=0;
  v_backend_count integer:=0;
  v_competing_count integer:=0;
  v_restored boolean:=false;
  v_receipt jsonb:=NULL;
  v_review jsonb:=NULL;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  IF v_stock='' OR length(v_stock)>80 OR p_vehicle_id IS NULL OR p_backend_record_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_lookup_request');
  END IF;

  SELECT * INTO v_backend
  FROM public.navision_backend_records
  WHERE id=p_backend_record_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','backend_not_found');
  END IF;
  IF v_backend.source_system<>'microsoft_navision'
     OR NOT v_backend.is_current
     OR v_backend.record_status<>'current'
     OR btrim(coalesce(v_backend.normalized_data->>'batch',v_backend.normalized_data->>'stock',''))<>v_stock
     OR v_backend.canonical_vehicle_id<>p_vehicle_id THEN
    RETURN jsonb_build_object('ok',false,'code','backend_identity_mismatch');
  END IF;

  SELECT count(*) INTO v_backend_count
  FROM public.navision_backend_records x
  WHERE x.source_system='microsoft_navision'
    AND x.dealer_code=v_backend.dealer_code
    AND x.is_current
    AND x.record_status='current'
    AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=v_stock;
  IF v_backend_count<>1 THEN
    RETURN jsonb_build_object('ok',false,'code','backend_identity_ambiguous','data',jsonb_build_object('current_backend_matches',v_backend_count));
  END IF;

  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_not_found');
  END IF;

  SELECT count(*) INTO v_competing_count
  FROM public.vehicles x
  WHERE x.id<>p_vehicle_id
    AND x.deleted_at IS NULL
    AND (
      x.stock_number_normalized=v_stock
      OR (
        nullif(upper(btrim(coalesce(v_backend.normalized_data->>'vin',''))),'') IS NOT NULL
        AND x.vin_normalized=upper(btrim(v_backend.normalized_data->>'vin'))
      )
    );
  IF v_competing_count>0 THEN
    RETURN jsonb_build_object('ok',false,'code','restore_identity_conflict','data',jsonb_build_object('competing_active_identities',v_competing_count));
  END IF;

  SELECT count(*) INTO v_tombstone_count
  FROM public.pdc_vehicle_tombstones t
  WHERE t.vehicle_id=p_vehicle_id AND t.normalized_stock=v_stock;
  IF v_tombstone_count<>1 THEN
    RETURN jsonb_build_object('ok',false,
      'code',CASE WHEN v_tombstone_count=0 THEN 'tombstone_not_found' ELSE 'tombstone_ambiguous' END,
      'data',jsonb_build_object('tombstone_matches',v_tombstone_count));
  END IF;

  SELECT * INTO v_tombstone
  FROM public.pdc_vehicle_tombstones t
  WHERE t.vehicle_id=p_vehicle_id AND t.normalized_stock=v_stock;

  SELECT EXISTS(
    SELECT 1 FROM public.pdc_vehicle_lifecycle_events e
    WHERE e.tombstone_id=v_tombstone.tombstone_id AND e.event_kind='restored'
  ) INTO v_restored;

  SELECT jsonb_build_object(
      'receipt_id',r.receipt_id,
      'idempotency_key',r.idempotency_key,
      'created_at',r.created_at,
      'response',r.response
    )
  INTO v_receipt
  FROM public.pdc_email_ai_new_vehicle_restore_receipts_20260910 r
  WHERE r.vehicle_id=p_vehicle_id
    AND r.tombstone_id=v_tombstone.tombstone_id
    AND r.backend_record_id=p_backend_record_id
  ORDER BY r.created_at DESC
  LIMIT 1;

  SELECT jsonb_build_object(
    'status',r.status,
    'source_kind',r.source_kind,
    'first_job_card',r.first_job_card,
    'received_at',r.received_at
  )
  INTO v_review
  FROM public.pdc_new_vehicle_reviews r
  WHERE r.vehicle_id=p_vehicle_id;

  RETURN jsonb_build_object(
    'ok',true,
    'code','restore_context_found',
    'data',jsonb_build_object(
      'stock_number',v_stock,
      'vehicle_id',p_vehicle_id,
      'backend_record_id',p_backend_record_id,
      'tombstone_id',v_tombstone.tombstone_id,
      'tombstone_kind',v_tombstone.tombstone_kind,
      'deleted_at',v_tombstone.deleted_at,
      'vehicle_lifecycle_state',v_vehicle.lifecycle_state,
      'vehicle_deleted_at',v_vehicle.deleted_at,
      'visible_on_board',v_vehicle.visible_on_board,
      'current_location',v_vehicle.current_location,
      'current_backend_matches',v_backend_count,
      'competing_active_identities',v_competing_count,
      'restore_event_exists',v_restored,
      'restore_receipt',v_receipt,
      'new_vehicle_review',v_review,
      'restore_eligible',(
        v_vehicle.deleted_at IS NOT NULL
        AND v_vehicle.lifecycle_state::text='deleted'
        AND NOT v_vehicle.visible_on_board
        AND NOT v_restored
        AND v_receipt IS NULL
        AND v_backend_count=1
        AND v_competing_count=0
      )
    )
  );
END
$$;

REVOKE ALL ON FUNCTION public.pdc_email_ai_lookup_hidden_restore_context_v1(text,uuid,uuid)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pdc_email_ai_lookup_hidden_restore_context_v1(text,uuid,uuid)
TO authenticated;
