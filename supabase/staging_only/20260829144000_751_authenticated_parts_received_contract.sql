-- STAGING ONLY 751: durable authenticated Parts received contract.
-- Administrator authority is bounded to an exact visible canonical vehicle;
-- non-Administrators remain dealer-scoped. Existing 738/742 one-off paths are
-- preserved and are not widened.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$')<>'20260829143000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260829143000'
           AND name='750_project_recovered_stock_qc_operation_lines')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version='20260829144000')
     OR to_regclass('public.vehicles') IS NULL
     OR to_regclass('public.vehicle_parts_updates') IS NULL
     OR to_regclass('public.vehicle_work_items') IS NULL
     OR to_regclass('public.audit_events') IS NULL
     OR to_regclass('public.pdc_email_vehicle_revision') IS NULL
     OR to_regclass('public.pdc_user_roles') IS NULL
     OR to_regclass('public.pdc_auditor_user_dealer_scopes') IS NULL
     OR to_regprocedure('public.normalize_vehicle_stock_number(text)') IS NULL
     OR to_regprocedure('public.pdc_auditor_vehicle_dealer(uuid)') IS NULL
     OR to_regprocedure('public.pdc_auditor_entity_in_scope(text,text,uuid)') IS NULL
     OR to_regprocedure('public.navision_backend_response(boolean,text,jsonb)') IS NULL
     OR to_regprocedure('public.audit_pdc_event(public.audit_action,text,uuid,uuid,jsonb,jsonb,jsonb)') IS NULL
     OR to_regprocedure('public.pdc_monitor_staging_guard()') IS NULL
     OR to_regclass('public.pdc_authenticated_parts_received_receipts_751') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_751_EXACT_STAGING_DEPENDENCY_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

-- An ordered-but-received row no longer needs a future ETA. Outstanding ordered
-- Parts still require one, preserving the existing queue invariant.
CREATE OR REPLACE FUNCTION public.pdc_parts_order_requires_eta_377()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $eta$
BEGIN
  IF coalesce(NEW.parts_ordered,false)
     AND NOT coalesce(NEW.parts_received,false)
     AND NEW.worst_eta IS NULL THEN
    RAISE EXCEPTION 'PDC_PARTS_ETA_REQUIRED' USING errcode='23514',
      detail=jsonb_build_object('ok',false,'code','parts_eta_required','vehicle_id',NEW.vehicle_id)::text;
  END IF;
  RETURN NEW;
END $eta$;

CREATE TABLE public.pdc_authenticated_parts_received_receipts_751(
  receipt_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL CHECK(actor_email=lower(btrim(actor_email)) AND length(actor_email)>3),
  actor_role text NOT NULL CHECK(actor_role IN('operator','administrator')),
  dealer_code text NOT NULL CHECK(dealer_code IN('14450','37047')),
  stock_number text NOT NULL,
  expected_version integer NOT NULL CHECK(expected_version>=0),
  idempotency_key uuid NOT NULL UNIQUE,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
  before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
  after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(stock_number=public.normalize_vehicle_stock_number(stock_number))
);
CREATE INDEX pdc_authenticated_parts_received_receipts_751_vehicle_idx
  ON public.pdc_authenticated_parts_received_receipts_751(vehicle_id,created_at DESC);

CREATE FUNCTION public.pdc_751_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RAISE EXCEPTION 'PDC_751_APPEND_ONLY' USING errcode='55000';
END $$;
REVOKE ALL ON FUNCTION public.pdc_751_append_only() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_authenticated_parts_received_receipts_751_append_only
  BEFORE UPDATE OR DELETE ON public.pdc_authenticated_parts_received_receipts_751
  FOR EACH ROW EXECUTE FUNCTION public.pdc_751_append_only();
ALTER TABLE public.pdc_authenticated_parts_received_receipts_751 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_authenticated_parts_received_receipts_751 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_authenticated_parts_received_receipts_751 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.mark_pdc_parts_received_authenticated_751(
  p_vehicle_id uuid,
  p_stock_number text,
  p_expected_version integer,
  p_idempotency_key uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,auth
SET statement_timeout='120s' AS $parts_received_751$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_claim_role text:=lower(btrim(coalesce(auth.jwt()->>'role','')));
  v_role text;
  v_role_count integer;
  v_scope_count integer;
  v_actor_dealer text;
  v_dealer text;
  v_stock text:=public.normalize_vehicle_stock_number(p_stock_number);
  v_vehicle public.vehicles%rowtype;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
  v_work_before public.vehicle_work_items%rowtype;
  v_work_after public.vehicle_work_items%rowtype;
  v_existing public.pdc_authenticated_parts_received_receipts_751%rowtype;
  v_receipt_id uuid;
  v_revision_before bigint;
  v_revision_after bigint;
  v_request_payload jsonb;
  v_request_sha text;
  v_before_state jsonb;
  v_after_state jsonb;
  v_result jsonb;
  v_clear_stoppage boolean;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR v_actor IS NULL OR v_claim_role<>'authenticated'
     OR p_vehicle_id IS NULL OR p_expected_version IS NULL
     OR p_idempotency_key IS NULL OR v_stock IS NULL OR v_stock=''
  THEN RETURN public.navision_backend_response(false,'invalid_input'); END IF;

  SELECT count(*),min(r.role::text) INTO v_role_count,v_role
  FROM public.pdc_user_roles r
  JOIN auth.users u ON u.id=v_actor AND lower(coalesce(u.email,''))=v_email
  WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
    AND r.active AND r.account_status='approved'
    AND r.role::text IN('operator','administrator');
  IF v_role_count<>1 OR v_role NOT IN('operator','administrator') THEN
    RETURN public.navision_backend_response(false,'permission_denied');
  END IF;

  v_request_payload:=jsonb_build_object(
    'contract','pdc-authenticated-parts-received-751',
    'environment','staging','vehicle_id',p_vehicle_id,
    'stock_number',v_stock,'expected_version',p_expected_version,
    'idempotency_key',p_idempotency_key);
  v_request_sha:=encode(extensions.digest(convert_to(v_request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-751-idempotency:'||p_idempotency_key::text,0));
  SELECT * INTO v_existing
  FROM public.pdc_authenticated_parts_received_receipts_751
  WHERE idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_sha256<>v_request_sha
       OR v_existing.vehicle_id<>p_vehicle_id
       OR v_existing.expected_version<>p_expected_version
       OR v_existing.actor_id<>v_actor
       OR v_existing.stock_number<>v_stock
    THEN RETURN public.navision_backend_response(false,'parts_receipt_idempotency_conflict'); END IF;
    RETURN jsonb_build_object('ok',true,'code','replayed','replay',true,
      'data',(v_existing.response->'data')||jsonb_build_object('changed',false));
  END IF;

  SELECT * INTO v_vehicle
  FROM public.vehicles
  WHERE id=p_vehicle_id AND stock_number_normalized=v_stock
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.navision_backend_response(false,'vehicle_identity_mismatch');
  END IF;
  IF v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' THEN
    RETURN public.navision_backend_response(false,'not_in_active_lifecycle');
  END IF;
  IF NOT v_vehicle.visible_on_board THEN
    RETURN public.navision_backend_response(false,'vehicle_not_visible');
  END IF;

  v_dealer:=public.pdc_auditor_vehicle_dealer(v_vehicle.id);
  IF v_dealer IS NULL OR v_dealer<>v_vehicle.source_batch_id THEN
    RETURN public.navision_backend_response(false,'canonical_identity_mismatch');
  END IF;
  IF v_role<>'administrator' THEN
    SELECT count(*),min(s.dealer_code) INTO v_scope_count,v_actor_dealer
    FROM public.pdc_auditor_user_dealer_scopes s
    WHERE s.auth_user_id=v_actor AND s.normalized_email=v_email
      AND s.environment='staging' AND s.active;
    IF v_scope_count<>1 OR v_actor_dealer<>v_dealer
       OR NOT public.pdc_auditor_entity_in_scope(v_actor_dealer,'vehicle',v_vehicle.id)
    THEN RETURN public.navision_backend_response(false,'dealer_scope_denied'); END IF;
  END IF;
  IF v_vehicle.version<>p_expected_version THEN
    RETURN public.navision_backend_response(false,'vehicle_version_conflict',
      jsonb_build_object('current_version',v_vehicle.version,'vehicle_id',v_vehicle.id,'stock_number',v_stock));
  END IF;

  SELECT * INTO v_parts_before FROM public.vehicle_parts_updates
  WHERE vehicle_id=v_vehicle.id ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE;
  SELECT * INTO v_work_before FROM public.vehicle_work_items
  WHERE vehicle_id=v_vehicle.id AND upper(work_key)='PARTS'
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
    '75100000-0000-5000-8000-000000000751'::uuid,p_idempotency_key::text);
  v_clear_stoppage:=coalesce(v_parts_before.parts_stoppage,false);
  v_before_state:=jsonb_build_object(
    'vehicle',jsonb_build_object('id',v_vehicle.id,'stock_number',v_vehicle.stock_number,
      'dealer_code',v_dealer,'version',v_vehicle.version,
      'lifecycle_state',v_vehicle.lifecycle_state::text,'current_location',v_vehicle.current_location,
      'visible_on_board',v_vehicle.visible_on_board),
    'parts',case when v_parts_before.id IS NULL then '{}'::jsonb else to_jsonb(v_parts_before) end,
    'work_item',case when v_work_before.id IS NULL then '{}'::jsonb else to_jsonb(v_work_before) end,
    'actor_role',v_role);

  PERFORM set_config('pdc.parts_completion_revision_managed','on',true);
  SELECT revision INTO v_revision_before
  FROM public.pdc_email_vehicle_revision WHERE singleton FOR UPDATE;
  INSERT INTO public.vehicle_parts_updates(
    vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,
    parts_stoppage_reason,worst_eta,updated_by,updated_at)
  VALUES(v_vehicle.id,v_parts_before.parts_required,v_parts_before.parts_ordered,true,
    false,CASE WHEN v_clear_stoppage THEN NULL ELSE v_parts_before.parts_stoppage_reason END,
    CASE WHEN v_clear_stoppage THEN NULL ELSE v_parts_before.worst_eta END,
    v_actor,clock_timestamp()) RETURNING * INTO v_parts_after;
  IF v_work_before.id IS NULL THEN
    INSERT INTO public.vehicle_work_items(
      vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
    VALUES(v_vehicle.id,'PARTS',true,true,v_actor,clock_timestamp(),
      'Parts received from authenticated Parts board',clock_timestamp())
    RETURNING * INTO v_work_after;
  ELSE
    UPDATE public.vehicle_work_items SET required=true,completed=true,
      completed_by=v_actor,completed_at=clock_timestamp(),updated_at=clock_timestamp()
    WHERE id=v_work_before.id RETURNING * INTO v_work_after;
  END IF;
  UPDATE public.vehicles SET version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
  WHERE id=v_vehicle.id RETURNING * INTO v_vehicle;

  v_after_state:=jsonb_build_object(
    'vehicle',jsonb_build_object('id',v_vehicle.id,'stock_number',v_vehicle.stock_number,
      'dealer_code',v_dealer,'version',v_vehicle.version,
      'lifecycle_state',v_vehicle.lifecycle_state::text,'current_location',v_vehicle.current_location,
      'visible_on_board',v_vehicle.visible_on_board),
    'parts',to_jsonb(v_parts_after),'work_item',to_jsonb(v_work_after),
    'actor_role',v_role);
  PERFORM public.audit_pdc_event('insert','vehicle_parts_updates',v_parts_after.id,v_vehicle.id,
    v_before_state->'parts',v_after_state->'parts',jsonb_build_object(
      'contract','pdc-authenticated-parts-received-751','action','mark_parts_received',
      'receipt_id',v_receipt_id,'vehicle_id',v_vehicle.id,'stock_number',v_stock,
      'dealer_code',v_dealer,'actor_role',v_role,'expected_version',p_expected_version,
      'changed',true));
  PERFORM public.audit_pdc_event(case when v_work_before.id IS NULL then 'insert'::public.audit_action else 'update'::public.audit_action end,
    'vehicle_work_items',v_work_after.id,v_vehicle.id,
    case when v_work_before.id IS NULL then NULL else to_jsonb(v_work_before) end,
    to_jsonb(v_work_after),jsonb_build_object(
      'contract','pdc-authenticated-parts-received-751','action','mark_parts_received',
      'receipt_id',v_receipt_id,'vehicle_id',v_vehicle.id,'stock_number',v_stock,
      'dealer_code',v_dealer,'actor_role',v_role,'expected_version',p_expected_version,
      'changed',true));
  UPDATE public.pdc_email_vehicle_revision
  SET revision=revision+1,updated_at=clock_timestamp()
  WHERE singleton RETURNING revision INTO v_revision_after;
  IF v_revision_after IS NULL OR v_revision_after<>v_revision_before+1 THEN
    RAISE EXCEPTION 'PDC_751_REVISION_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;

  v_result:=public.navision_backend_response(true,'parts_completed',jsonb_build_object(
    'receipt_id',v_receipt_id,'vehicle_id',v_vehicle.id,'stock_number',v_stock,
    'dealer_code',v_dealer,'vehicle_version_before',p_expected_version,
    'vehicle_version',v_vehicle.version,'revision_before',v_revision_before,
    'revision',v_revision_after,'changed',true,'parts_received',true,
    'parts_stoppage_cleared',v_clear_stoppage,'location_changed',false,
    'booking_created',false));
  INSERT INTO public.pdc_authenticated_parts_received_receipts_751(
    receipt_id,vehicle_id,actor_id,actor_email,actor_role,dealer_code,stock_number,
    expected_version,idempotency_key,request_sha256,request_payload,before_state,after_state,response)
  VALUES(v_receipt_id,v_vehicle.id,v_actor,v_email,v_role,v_dealer,v_stock,
    p_expected_version,p_idempotency_key,v_request_sha,v_request_payload,v_before_state,v_after_state,v_result);
  IF NOT EXISTS(SELECT 1 FROM public.pdc_authenticated_parts_received_receipts_751
                WHERE receipt_id=v_receipt_id)
     OR v_vehicle.version<>p_expected_version+1
     OR NOT coalesce((v_after_state->'parts'->>'parts_received')::boolean,false)
     OR NOT coalesce((v_after_state->'work_item'->>'completed')::boolean,false)
  THEN RAISE EXCEPTION 'PDC_751_RECEIPT_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  RETURN v_result;
END $parts_received_751$;
REVOKE ALL ON FUNCTION public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid)
  FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid) TO authenticated;
COMMENT ON FUNCTION public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid) IS
  'Staging-only bounded authenticated Parts receipt. Exact UUID plus normalized Stock and expected version are checked server-side; Administrator is allowed on exact visible canonical vehicles, operators remain dealer-scoped; immutable receipt, audit, one revision and idempotent replay are required.';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260829144000','751_authenticated_parts_received_contract',ARRAY[
    'Replace the hard-coded 738/742 Parts completion path with an authenticated exact UUID plus Stock contract',
    'Allow approved Administrators on exact visible canonical vehicles while preserving non-Administrator dealer isolation',
    'Preserve ordered/ETA semantics by requiring ETA only while ordered Parts remain outstanding',
    'Record one immutable receipt, audit the Parts/work transition, increment vehicle version once and publish one Board revision',
    'Reject wrong identity, wrong dealer, stale version, duplicate/conflicting idempotency and direct table access'
  ]);
NOTIFY pgrst,'reload schema';
COMMIT;
