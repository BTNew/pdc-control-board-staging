-- STAGING ONLY 900: exact, dealer-scoped Sublet ledger read bridge.
-- No booking, work-item, vehicle, history, or receipt mutation is performed.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-sublet-auditor-read-900',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$')<>'20260830081000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260830081000'
           AND name='stock_13017855_restore_navision_parity_successor')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version='20260830090000')
     OR to_regclass('public.vehicles') IS NULL
     OR to_regclass('public.navision_backend_records') IS NULL
     OR to_regclass('public.pdc_sublet_booking_instances') IS NULL
     OR to_regclass('public.pdc_sublet_booking_instance_history') IS NULL
     OR to_regclass('public.pdc_sublet_email_update_receipts') IS NULL
     OR to_regprocedure('public.pdc_monitor_staging_guard()') IS NULL
     OR to_regprocedure('public.pdc_auditor_actor_scope()') IS NULL
     OR to_regprocedure('public.navision_backend_response(boolean,text,jsonb)') IS NULL
     OR to_regprocedure('public.get_pdc_sublet_audit_ledgers(uuid,text,text)') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_900_EXACT_STAGING_DEPENDENCY_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE FUNCTION public.get_pdc_sublet_audit_ledgers(
  p_vehicle_id uuid,
  p_stock_number text,
  p_job_card_number text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,auth
SET statement_timeout='120s' AS $read$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_scope jsonb;
  v_dealer text;
  v_vehicle public.vehicles%rowtype;
  v_result jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR v_actor IS NULL
     OR coalesce(auth.jwt()->>'role','')<>'authenticated'
     OR p_vehicle_id IS NULL
     OR nullif(btrim(coalesce(p_stock_number,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_job_card_number,'')),'') IS NULL
  THEN RETURN public.navision_backend_response(false,'invalid_input'); END IF;

  v_scope:=public.pdc_auditor_actor_scope();
  v_dealer:=nullif(btrim(v_scope->>'dealer_code'),'');
  IF coalesce(v_scope->>'environment','')<>'staging'
     OR (v_scope->>'user_id')::uuid IS DISTINCT FROM v_actor
     OR coalesce(v_scope->>'email','')<>v_email
     OR v_dealer IS NULL
  THEN RETURN public.navision_backend_response(false,'dealer_scope_denied'); END IF;

  SELECT * INTO v_vehicle
  FROM public.vehicles
  WHERE id=p_vehicle_id
    AND deleted_at IS NULL
    AND lifecycle_state='active'
    AND visible_on_board
  FOR SHARE;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'vehicle_not_found'); END IF;
  IF v_vehicle.stock_number IS DISTINCT FROM btrim(p_stock_number)
     OR v_vehicle.job_card_number IS DISTINCT FROM btrim(p_job_card_number)
     OR v_vehicle.source_batch_id IS DISTINCT FROM v_dealer
  THEN RETURN public.navision_backend_response(false,'canonical_identity_mismatch'); END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.navision_backend_records r
    WHERE r.id=v_vehicle.source_record_id
      AND r.source_system='microsoft_navision'
      AND r.dealer_code=v_dealer
      AND r.is_current
      AND r.record_status='current'
  ) THEN RETURN public.navision_backend_response(false,'dealer_scope_denied'); END IF;

  v_result:=jsonb_build_object(
    'vehicle_id',v_vehicle.id,
    'stock_number',v_vehicle.stock_number,
    'job_card_number',v_vehicle.job_card_number,
    'dealer_code',v_dealer,
    'vehicle_version',v_vehicle.version,
    'active_booking_count',(
      SELECT count(*) FROM public.pdc_sublet_booking_instances b
      WHERE b.vehicle_id=v_vehicle.id AND b.status='active'
    ),
    'booking_instances',coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'booking_id',b.booking_id,
        'vehicle_id',b.vehicle_id,
        'vehicle_version',b.vehicle_version,
        'provider_id',b.provider_id,
        'provider_name',b.provider_name,
        'provider_email',b.provider_email,
        'out_date',b.out_date,
        'expected_return_date',b.expected_return_date,
        'status',b.status,
        'returned_at',b.returned_at,
        'cancelled_at',b.cancelled_at,
        'version',b.version,
        'source_kind',b.source_kind,
        'source_ref',b.source_ref,
        'created_at',b.created_at,
        'updated_at',b.updated_at
      ) ORDER BY b.out_date,b.booking_id)
      FROM public.pdc_sublet_booking_instances b
      WHERE b.vehicle_id=v_vehicle.id
    ),'[]'::jsonb),
    'booking_history',coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'history_id',h.history_id,
        'booking_id',h.booking_id,
        'vehicle_id',h.vehicle_id,
        'actor_id',h.actor_id,
        'actor_email',h.actor_email,
        'action',h.action,
        'booking_version',h.booking_version,
        'before_data',CASE WHEN h.before_data IS NULL THEN NULL ELSE jsonb_build_object(
          'booking_id',h.before_data->'booking_id',
          'vehicle_id',h.before_data->'vehicle_id',
          'provider_id',h.before_data->'provider_id',
          'provider_name',h.before_data->'provider_name',
          'out_date',h.before_data->'out_date',
          'expected_return_date',h.before_data->'expected_return_date',
          'status',h.before_data->'status',
          'version',h.before_data->'version'
        ) END,
        'after_data',jsonb_build_object(
          'booking_id',h.after_data->'booking_id',
          'vehicle_id',h.after_data->'vehicle_id',
          'provider_id',h.after_data->'provider_id',
          'provider_name',h.after_data->'provider_name',
          'out_date',h.after_data->'out_date',
          'expected_return_date',h.after_data->'expected_return_date',
          'status',h.after_data->'status',
          'version',h.after_data->'version'
        ),
        'evidence',h.evidence,
        'event_at',h.event_at
      ) ORDER BY h.event_at,h.history_id)
      FROM public.pdc_sublet_booking_instance_history h
      WHERE h.vehicle_id=v_vehicle.id
    ),'[]'::jsonb),
    'email_update_receipts',coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'receipt_id',r.receipt_id,
        'replay_key',r.replay_key,
        'booking_id',r.booking_id,
        'vehicle_id',r.vehicle_id,
        'provider_id',r.provider_id,
        'provider_name',r.provider_name,
        'sender_email',r.sender_email,
        'message_id',r.message_id,
        'attachment_sha256',r.attachment_sha256,
        'language_kind',r.language_kind,
        'prior_version',r.prior_version,
        'resulting_version',r.resulting_version,
        'applied_out_date',r.applied_out_date,
        'applied_expected_return_date',r.applied_expected_return_date,
        'received_at',r.received_at,
        'applied_at',r.applied_at,
        'applied_by',r.applied_by
      ) ORDER BY r.applied_at,r.receipt_id)
      FROM public.pdc_sublet_email_update_receipts r
      WHERE r.vehicle_id=v_vehicle.id
    ),'[]'::jsonb)
  );
  RETURN public.navision_backend_response(true,'ok',v_result);
END $read$;

REVOKE ALL ON FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text)
  FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text)
  TO authenticated;
COMMENT ON FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text) IS
  'Staging-only exact UUID/Stock/Job Card, active canonical vehicle, dealer-scoped authenticated read of Sublet instances, immutable booking history and email receipts; direct table SELECT remains denied.';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260830090000','sublet_auditor_read_ledger',ARRAY[
    'Exact staging sentinel and 20260830080000 predecessor guard',
    'Dealer-scoped authenticated exact UUID/Stock/Job Card Sublet instance/history/receipt read RPC',
    'Direct SELECT on immutable Sublet ledgers remains denied',
    'Projection-only closure; no repair RPC and no stored work-item mutation'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
