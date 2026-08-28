-- STAGING ONLY 742: one-time Administrator/controller correction for the
-- exact Craig-authorised Parts-received outcome. This does not alter Auditor
-- dealer scope or migration 738.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel
                   WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$')<>'20260829080000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260829080000'
           AND name='741_rft_transport_email_draft_regex_repair')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260829070000'
           AND name='740_rft_transport_email_draft_read_lock_repair')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260829050000'
           AND name='738_authenticated_parts_received_auditor_wrapper')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version='20260829090000')
     OR to_regclass('public.vehicles') IS NULL
     OR to_regclass('public.vehicle_parts_updates') IS NULL
     OR to_regclass('public.vehicle_work_items') IS NULL
     OR to_regclass('public.audit_events') IS NULL
     OR to_regclass('public.pdc_email_vehicle_revision') IS NULL
     OR to_regprocedure('public.pdc_monitor_staging_guard()') IS NULL
     OR to_regprocedure('public.audit_pdc_event(public.audit_action,text,uuid,uuid,jsonb,jsonb,jsonb)') IS NULL
     OR to_regprocedure('public.pdc_auditor_vehicle_dealer(uuid)') IS NULL
     OR to_regprocedure('public.apply_pdc_staging_parts_received_correction_740(uuid,integer,text,uuid)') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_740_EXACT_STAGING_DEPENDENCY_MISMATCH' USING errcode='55000';
  END IF;
END $guard$;

CREATE TABLE public.pdc_staging_parts_received_correction_authorizations_742(
  correction_id uuid PRIMARY KEY,
  project_ref text NOT NULL CHECK(project_ref='cdsmnqxtyyoeoznmbidd'),
  owner_instruction text NOT NULL CHECK(owner_instruction='Craig Watson authorised STAGING correction for Stock 13016925: mark Parts received once via controller receipt 20260828'),
  operation text NOT NULL CHECK(operation='mark_parts_received_once'),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  stock_number text NOT NULL CHECK(stock_number='13016925'),
  dealer_code text NOT NULL CHECK(dealer_code='37047'),
  expected_version integer NOT NULL CHECK(expected_version=5),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(expires_at>created_at)
);

CREATE TABLE public.pdc_staging_parts_received_correction_receipts_742(
  receipt_id uuid PRIMARY KEY,
  correction_id uuid NOT NULL UNIQUE REFERENCES public.pdc_staging_parts_received_correction_authorizations_742(correction_id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL CHECK(actor_email=lower(btrim(actor_email)) AND length(actor_email)>3),
  dealer_code text NOT NULL CHECK(dealer_code='37047'),
  stock_number text NOT NULL CHECK(stock_number='13016925'),
  expected_version integer NOT NULL CHECK(expected_version=5),
  idempotency_key uuid NOT NULL UNIQUE,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
  before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
  after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  consumed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX pdc_staging_parts_received_correction_receipts_742_vehicle_idx
  ON public.pdc_staging_parts_received_correction_receipts_742(vehicle_id,consumed_at DESC);

CREATE FUNCTION public.pdc_742_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RAISE EXCEPTION 'PDC_742_APPEND_ONLY' USING errcode='55000';
END $$;
REVOKE ALL ON FUNCTION public.pdc_742_append_only() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_staging_parts_received_correction_authorizations_742_append_only
  BEFORE UPDATE OR DELETE ON public.pdc_staging_parts_received_correction_authorizations_742
  FOR EACH ROW EXECUTE FUNCTION public.pdc_742_append_only();
CREATE TRIGGER pdc_staging_parts_received_correction_receipts_742_append_only
  BEFORE UPDATE OR DELETE ON public.pdc_staging_parts_received_correction_receipts_742
  FOR EACH ROW EXECUTE FUNCTION public.pdc_742_append_only();
ALTER TABLE public.pdc_staging_parts_received_correction_authorizations_742 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_staging_parts_received_correction_authorizations_742 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_staging_parts_received_correction_receipts_742 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_staging_parts_received_correction_receipts_742 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_staging_parts_received_correction_authorizations_742 FROM public,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.pdc_staging_parts_received_correction_receipts_742 FROM public,anon,authenticated,service_role;

INSERT INTO public.pdc_staging_parts_received_correction_authorizations_742(
  correction_id,project_ref,owner_instruction,operation,vehicle_id,stock_number,dealer_code,expected_version,expires_at)
VALUES(
  extensions.uuid_generate_v5('74200000-0000-5000-8000-000000000742'::uuid,'stock-13016925-parts-received'),
  'cdsmnqxtyyoeoznmbidd',
  'Craig Watson authorised STAGING correction for Stock 13016925: mark Parts received once via controller receipt 20260828',
  'mark_parts_received_once',
  '13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid,
  '13016925','37047',5,clock_timestamp()+interval '24 hours');

CREATE FUNCTION public.apply_pdc_staging_parts_received_correction_742(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_owner_instruction text,
  p_idempotency_key uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,auth
SET statement_timeout='120s' AS $controller_correction$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_authorization public.pdc_staging_parts_received_correction_authorizations_742%rowtype;
  v_existing public.pdc_staging_parts_received_correction_receipts_742%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
  v_work_before public.vehicle_work_items%rowtype;
  v_work_after public.vehicle_work_items%rowtype;
  v_receipt_id uuid;
  v_revision bigint;
  v_request_payload jsonb;
  v_request_sha text;
  v_before_state jsonb;
  v_after_state jsonb;
  v_result jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR v_actor IS NULL
     OR coalesce(auth.jwt()->>'role','')<>'authenticated'
     OR p_vehicle_id IS NULL
     OR p_expected_version IS NULL
     OR p_idempotency_key IS NULL
  THEN RETURN public.navision_backend_response(false,'controller_unauthorized'); END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.pdc_user_roles r
    JOIN auth.users u ON u.id=r.auth_user_id AND lower(coalesce(u.email,''))=v_email
    WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
      AND r.active AND r.account_status='approved'
      AND r.role::text IN('operator','administrator')
  ) THEN RETURN public.navision_backend_response(false,'controller_unauthorized'); END IF;

  SELECT * INTO v_authorization
  FROM public.pdc_staging_parts_received_correction_authorizations_742
  WHERE operation='mark_parts_received_once'
    AND project_ref='cdsmnqxtyyoeoznmbidd'
    AND vehicle_id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid
  FOR SHARE;
  IF NOT FOUND OR v_authorization.expires_at<=clock_timestamp() THEN
    RETURN public.navision_backend_response(false,'controller_correction_expired');
  END IF;
  IF p_owner_instruction IS DISTINCT FROM v_authorization.owner_instruction THEN
    RETURN public.navision_backend_response(false,'owner_instruction_mismatch');
  END IF;
  IF p_vehicle_id<>v_authorization.vehicle_id THEN
    RETURN public.navision_backend_response(false,'controller_target_mismatch');
  END IF;

  v_request_payload:=jsonb_build_object(
    'contract','pdc-controller-parts-received-740',
    'environment','staging',
    'correction_id',v_authorization.correction_id,
    'owner_instruction',v_authorization.owner_instruction,
    'operation',v_authorization.operation,
    'vehicle_id',p_vehicle_id,
    'stock_number','13016925',
    'dealer_code','37047',
    'expected_version',p_expected_version,
    'idempotency_key',p_idempotency_key);
  v_request_sha:=encode(extensions.digest(convert_to(v_request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-742-controller-idempotency:'||p_idempotency_key::text,0));

  SELECT * INTO v_existing
  FROM public.pdc_staging_parts_received_correction_receipts_742
  WHERE idempotency_key=p_idempotency_key
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_sha256<>v_request_sha
       OR v_existing.vehicle_id<>p_vehicle_id
       OR v_existing.expected_version<>p_expected_version
       OR v_existing.actor_id<>v_actor
    THEN RETURN public.navision_backend_response(false,'controller_replay_conflict'); END IF;
    RETURN jsonb_build_object('ok',true,'code','controller_correction_replayed','replay',true,
      'data',(v_existing.response->'data')||jsonb_build_object('changed',false));
  END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_staging_parts_received_correction_receipts_742
            WHERE correction_id=v_authorization.correction_id) THEN
    RETURN public.navision_backend_response(false,'controller_correction_consumed');
  END IF;
  IF p_expected_version<>v_authorization.expected_version THEN
    RETURN public.navision_backend_response(false,'vehicle_version_conflict');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-742-controller-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' THEN
    RETURN public.navision_backend_response(false,'controller_target_mismatch');
  END IF;
  IF v_vehicle.stock_number<>'13016925'
     OR v_vehicle.source_batch_id<>'37047'
     OR public.pdc_auditor_vehicle_dealer(v_vehicle.id)<>'37047'
  THEN RETURN public.navision_backend_response(false,'controller_target_mismatch'); END IF;
  IF v_vehicle.version<>p_expected_version THEN
    RETURN public.navision_backend_response(false,'vehicle_version_conflict');
  END IF;

  SELECT * INTO v_parts_before FROM public.vehicle_parts_updates
  WHERE vehicle_id=p_vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1;
  SELECT * INTO v_work_before FROM public.vehicle_work_items
  WHERE vehicle_id=p_vehicle_id AND upper(work_key)='PARTS'
  ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE;
  IF NOT coalesce(v_parts_before.parts_required,false) THEN
    RETURN public.navision_backend_response(false,'parts_not_required');
  END IF;
  IF NOT coalesce(v_parts_before.parts_ordered,false) THEN
    RETURN public.navision_backend_response(false,'parts_not_ordered');
  END IF;
  IF coalesce(v_parts_before.parts_received,false) OR coalesce(v_work_before.completed,false) THEN
    RETURN public.navision_backend_response(false,'parts_already_received');
  END IF;

  v_receipt_id:=extensions.uuid_generate_v5(
    '74000000-0000-5000-8000-000000000740'::uuid,
    p_idempotency_key::text);
  v_before_state:=jsonb_build_object(
    'vehicle',jsonb_build_object('id',v_vehicle.id,'stock_number',v_vehicle.stock_number,
      'dealer_code',v_vehicle.source_batch_id,'version',v_vehicle.version,
      'lifecycle_state',v_vehicle.lifecycle_state::text,'current_location',v_vehicle.current_location,
      'visible_on_board',v_vehicle.visible_on_board),
    'parts',case when v_parts_before.id IS NULL then '{}'::jsonb else to_jsonb(v_parts_before) end,
    'work_item',case when v_work_before.id IS NULL then '{}'::jsonb else to_jsonb(v_work_before) end);

  PERFORM set_config('pdc.parts_completion_revision_managed','on',true);
  INSERT INTO public.vehicle_parts_updates(
    vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,
    parts_stoppage_reason,worst_eta,updated_by,updated_at)
  VALUES(p_vehicle_id,true,true,true,false,NULL,NULL,v_actor,clock_timestamp())
  RETURNING * INTO v_parts_after;
  INSERT INTO public.vehicle_work_items(
    vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
  VALUES(p_vehicle_id,'PARTS',true,true,v_actor,clock_timestamp(),
    'Parts received under Craig owner instruction 742',clock_timestamp())
  ON CONFLICT(vehicle_id,work_key) DO UPDATE SET
    required=true,completed=true,completed_by=v_actor,completed_at=clock_timestamp(),
    notes='Parts received under Craig owner instruction 742',updated_at=clock_timestamp()
  RETURNING * INTO v_work_after;
  UPDATE public.vehicles SET version=version+1,updated_by=v_actor
  WHERE id=p_vehicle_id RETURNING * INTO v_vehicle;

  v_after_state:=jsonb_build_object(
    'vehicle',jsonb_build_object('id',v_vehicle.id,'stock_number',v_vehicle.stock_number,
      'dealer_code',v_vehicle.source_batch_id,'version',v_vehicle.version,
      'lifecycle_state',v_vehicle.lifecycle_state::text,'current_location',v_vehicle.current_location,
      'visible_on_board',v_vehicle.visible_on_board),
    'parts',to_jsonb(v_parts_after),'work_item',to_jsonb(v_work_after));
  PERFORM public.audit_pdc_event(
    'update','vehicles',v_vehicle.id,p_vehicle_id,
    v_before_state,v_after_state,jsonb_build_object(
      'contract','pdc-controller-parts-received-742',
      'action','mark_parts_received_once','correction_id',v_authorization.correction_id,
      'owner_instruction',v_authorization.owner_instruction,'operation',v_authorization.operation,
      'dealer_code','37047','stock_number','13016925','expected_version',p_expected_version,
      'idempotency_key',p_idempotency_key,'parts_stoppage_cleared',true,
      'parts_work_completed',true,'changed',true));
  UPDATE public.pdc_email_vehicle_revision
  SET revision=revision+1,updated_at=clock_timestamp()
  WHERE singleton RETURNING revision INTO v_revision;
  IF v_revision IS NULL THEN RAISE EXCEPTION 'PDC_740_REVISION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;

  v_result:=public.navision_backend_response(true,'parts_completed',jsonb_build_object(
    'receipt_id',v_receipt_id,'correction_id',v_authorization.correction_id,
    'vehicle_id',p_vehicle_id,'stock_number','13016925','dealer_code','37047',
    'vehicle_version_before',p_expected_version,'vehicle_version',v_vehicle.version,
    'revision',v_revision,'changed',true));
  INSERT INTO public.pdc_staging_parts_received_correction_receipts_742(
    receipt_id,correction_id,vehicle_id,actor_id,actor_email,dealer_code,stock_number,
    expected_version,idempotency_key,request_sha256,request_payload,before_state,after_state,response)
  VALUES(v_receipt_id,v_authorization.correction_id,p_vehicle_id,v_actor,v_email,'37047',
    '13016925',p_expected_version,p_idempotency_key,v_request_sha,v_request_payload,
    v_before_state,v_after_state,v_result);

  IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_parts_received_correction_receipts_742
                WHERE receipt_id=v_receipt_id)
     OR v_vehicle.version<>p_expected_version+1
     OR NOT coalesce((v_after_state->'parts'->>'parts_received')::boolean,false)
     OR NOT coalesce((v_after_state->'work_item'->>'completed')::boolean,false)
  THEN RAISE EXCEPTION 'PDC_742_RECEIPT_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  RETURN v_result;
END $controller_correction$;
REVOKE ALL ON FUNCTION public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid)
  FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid) TO authenticated;
COMMENT ON FUNCTION public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid) IS
  'Staging-only one-time Administrator/controller correction bound to Craig owner instruction, exact Stock 13016925, canonical UUID, dealer 37047, expected version 5 and expiring immutable authorization; no reusable Auditor scope.';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260829090000','742_controller_parts_received_correction',ARRAY[
    'Create one immutable expiring Craig owner-instruction authorization for exact Stock 13016925 Parts received correction',
    'Expose authenticated Administrator/operator controller wrapper with exact vehicle/dealer/version/role guards',
    'Consume one idempotency-bound immutable receipt, audit one target event, clear linked Parts stoppage/ETA, complete PARTS and publish one revision',
    'No persistent Auditor dealer scope, operator grant, service-role grant, table DML grant or RLS weakening'
  ]);
NOTIFY pgrst,'reload schema';
COMMIT;
