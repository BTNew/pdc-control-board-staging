-- STAGING ONLY: close provenance-history authorization fallback bypass.
BEGIN;
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging:20260904010900-provenance-rpc-auth-hardening',0));

DO $guard$
BEGIN
  IF current_user<>'postgres'
    OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR NOT EXISTS(
      SELECT 1 FROM supabase_migrations.schema_migrations
      WHERE version='20260904010800' AND name='non_navision_jobcard_vin_projection'
    )
    OR EXISTS(
      SELECT 1 FROM supabase_migrations.schema_migrations
      WHERE version~'^[0-9]{14}$' AND version>'20260904010800'
    )
  THEN
    RAISE EXCEPTION 'PDC_20260904010900_STAGING_HEAD_OR_ENVIRONMENT_MISMATCH' USING errcode='55000';
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(
  p_vehicle_id uuid,
  p_dealer_code text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $read$
DECLARE
  uid uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  actor_role text;
  v public.vehicles%rowtype;
  h jsonb;
  dealer text;
  scoped integer;
  synthetic boolean;
BEGIN
  IF NOT public.pdc_lifecycle_history_enabled_82000() OR uid IS NULL OR v_actor_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;

  SELECT r.role::text INTO actor_role
  FROM public.pdc_user_roles r
  WHERE r.auth_user_id=uid
    AND lower(r.email)=v_actor_email
    AND r.active
    AND r.account_status='approved'
  LIMIT 1;

  IF actor_role IS NULL OR actor_role NOT IN('viewer','operator','importer','administrator') THEN
    RETURN jsonb_build_object('ok',false,'code','forbidden');
  END IF;

  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id;
  IF NOT FOUND AND NOT EXISTS(
    SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE vehicle_id=p_vehicle_id
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_not_found');
  END IF;

  dealer:=CASE
    WHEN v.source_batch_id IN('14450','37047') THEN v.source_batch_id
    ELSE (
      SELECT e.dealer_code
      FROM public.pdc_vehicle_lifecycle_history_events_82000 e
      WHERE e.vehicle_id=p_vehicle_id AND e.dealer_code IS NOT NULL
      ORDER BY e.event_id
      LIMIT 1
    )
  END;
  synthetic:=coalesce(v.source_system,'')='hermes_lifecycle_history_acceptance'
    OR coalesce(v.source_batch_id,'') LIKE 'HERMES-TEST-%';

  IF p_dealer_code IS NOT NULL AND p_dealer_code NOT IN('14450','37047') THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_scope');
  END IF;
  IF p_dealer_code IS NOT NULL AND dealer IS DISTINCT FROM p_dealer_code THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied');
  END IF;

  SELECT count(*) INTO scoped
  FROM public.pdc_auditor_user_dealer_scopes s
  WHERE s.auth_user_id=uid
    AND s.normalized_email=v_actor_email
    AND s.environment='staging'
    AND s.active;
  IF NOT synthetic AND scoped>0 AND (
    dealer IS NULL OR NOT EXISTS(
      SELECT 1
      FROM public.pdc_auditor_user_dealer_scopes s
      WHERE s.auth_user_id=uid
        AND s.normalized_email=v_actor_email
        AND s.environment='staging'
        AND s.active
        AND s.dealer_code=dealer
    )
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied');
  END IF;

  h:=public.pdc_lifecycle_history_payload_82000(p_vehicle_id);
  RETURN jsonb_build_object(
    'ok',true,
    'code','lifecycle_history',
    'data',jsonb_build_object(
      'vehicle',jsonb_build_object(
        'vehicle_id',p_vehicle_id,
        'stock_number',coalesce(v.stock_number,h->>'stock_number'),
        'job_card_number',coalesce(v.job_card_number,h->>'job_card_number'),
        'lifecycle_state',v.lifecycle_state::text,
        'deleted_at',v.deleted_at,
        'visible_on_board',v.visible_on_board
      ),
      'lifecycle_history',h,
      'production',false,
      'timezone','Australia/Perth',
      'authority','pdc_vehicle_lifecycle_history_82000'
    )
  );
END $read$;

CREATE OR REPLACE FUNCTION public.get_pdc_vehicle_provenance_history(p_vehicle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $history$
DECLARE
  uid uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  actor_role text;
  base jsonb;
  lifecycle jsonb;
BEGIN
  IF uid IS NULL OR v_actor_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;

  SELECT r.role::text INTO actor_role
  FROM public.pdc_user_roles r
  WHERE r.auth_user_id=uid
    AND lower(r.email)=v_actor_email
    AND r.active
    AND r.account_status='approved'
  LIMIT 1;
  IF actor_role IS NULL OR actor_role NOT IN('viewer','operator','importer','administrator') THEN
    RETURN jsonb_build_object('ok',false,'code','forbidden');
  END IF;

  lifecycle:=public.get_pdc_vehicle_lifecycle_history_82000(p_vehicle_id,NULL);
  IF NOT coalesce((lifecycle->>'ok')::boolean,false) THEN RETURN lifecycle; END IF;

  base:=public.get_pdc_vehicle_provenance_history_pre_82000(p_vehicle_id);
  IF coalesce((base->>'ok')::boolean,false) THEN
    RETURN jsonb_set(base,'{data,lifecycle_history}',lifecycle->'data'->'lifecycle_history',true);
  END IF;
  IF base->>'code' IS DISTINCT FROM 'vehicle_not_found' THEN RETURN base; END IF;

  RETURN jsonb_build_object(
    'ok',true,
    'code','lifecycle_history',
    'data',jsonb_build_object(
      'vehicle',lifecycle->'data'->'vehicle',
      'lifecycle_history',lifecycle->'data'->'lifecycle_history'
    )
  );
END $history$;

REVOKE ALL ON FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_pdc_vehicle_provenance_history(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_provenance_history(uuid) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES(
  '20260904010900',
  'provenance_rpc_auth_hardening',
  ARRAY[
    'Make lifecycle role rejection NULL-safe for missing, inactive, pending and UUID/email-mismatched identities',
    'Require explicit approved authenticated identity and successful dealer-scoped lifecycle authorization before provenance fallback',
    'Preserve predecessor authorization failures and allow retained deleted-history fallback only for vehicle_not_found',
    'Keep provenance and lifecycle RPC execution authenticated-only without changing table ACLs or RLS',
    'STAGING cdsmnqxtyyoeoznmbidd only; Production excluded and operational business data unchanged'
  ]
);

NOTIFY pgrst,'reload schema';
COMMIT;
