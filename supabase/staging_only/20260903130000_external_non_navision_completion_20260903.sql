-- STAGING ONLY: operator-approved external/non-Navision completion.
-- This append-only successor completes only an already-recorded physical RFT
-- collection. It does not assert delivery, close the dealer-transit interval,
-- mutate Navision authority, or enqueue outbound communication.
BEGIN;
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-external-completion-20260903130000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260903125000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903125000' AND name='pdc_email_ai_final_acceptance_fixture_refresh_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903130000')
     OR to_regclass('public.vehicles') IS NULL
     OR to_regclass('public.workshop_bookings') IS NULL
     OR to_regclass('public.pdc_rft_transport_lifecycle_receipts_734') IS NULL
     OR to_regprocedure('public.cancel_workshop_booking(uuid,integer,text,jsonb)') IS NULL
     OR to_regprocedure('public.pdc_rft_transport_lifecycle_state_734(uuid)') IS NULL
     OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') IS NULL
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_EXACT_STAGING_125000_PRESTATE_REQUIRED' USING errcode='55000';
  END IF;
END $guard$;

CREATE TABLE public.pdc_external_completion_receipts_20260903(
  receipt_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL UNIQUE REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
  vehicle_version_after integer NOT NULL CHECK(vehicle_version_after=expected_vehicle_version+1),
  completion_type text NOT NULL CHECK(completion_type='external_non_navision_final_collection'),
  operator_approved boolean NOT NULL CHECK(operator_approved),
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 12 AND 500),
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL CHECK(length(btrim(actor_email))>3),
  idempotency_key uuid NOT NULL,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
  before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
  after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
  physical_collection_evidence jsonb NOT NULL CHECK(jsonb_typeof(physical_collection_evidence)='object'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  completed_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);
CREATE INDEX pdc_external_completion_receipts_vehicle_created_20260903
  ON public.pdc_external_completion_receipts_20260903(vehicle_id,created_at);

CREATE OR REPLACE FUNCTION public.pdc_external_completion_append_only_20260903()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_APPEND_ONLY' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_external_completion_append_only_20260903() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_external_completion_receipts_append_only_20260903
  BEFORE UPDATE OR DELETE ON public.pdc_external_completion_receipts_20260903
  FOR EACH ROW EXECUTE FUNCTION public.pdc_external_completion_append_only_20260903();
ALTER TABLE public.pdc_external_completion_receipts_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_external_completion_receipts_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_external_completion_receipts_20260903 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_external_completion_json_20260903(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
SELECT coalesce((SELECT jsonb_build_object(
  'receipt_id',r.receipt_id,
  'completion_type',r.completion_type,
  'operator_approved',r.operator_approved,
  'reason',r.reason,
  'completed_at',r.completed_at,
  'completed_by',r.actor_email,
  'physical_collection_evidence',r.physical_collection_evidence,
  'physical_delivery_asserted',false,
  'navision_delivery_authority_used',false
) FROM public.pdc_external_completion_receipts_20260903 r WHERE r.vehicle_id=p_vehicle_id),'{}'::jsonb)
$$;
REVOKE ALL ON FUNCTION public.pdc_external_completion_json_20260903(uuid) FROM public,anon,authenticated,service_role;

-- Preserve the exact Navision-delivered branch while allowing an external
-- completion receipt to outrank the older collected receipt in read models.
CREATE OR REPLACE FUNCTION public.pdc_rft_transport_lifecycle_state_734(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
SELECT coalesce((SELECT jsonb_build_object(
  'state',CASE
    WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered') THEN 'completed'
    WHEN EXISTS(SELECT 1 FROM public.pdc_external_completion_receipts_20260903 r WHERE r.vehicle_id=v.id) THEN 'completed'
    WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected') THEN 'collected'
    WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked') THEN 'rft_booked'
    ELSE lower(v.lifecycle_state::text) END,
  'rft_confirmed',v.rft_confirmed_at IS NOT NULL,
  'rft_confirmed_at',v.rft_confirmed_at,'rft_confirmed_by',v.rft_confirmed_by,
  'rft_booked',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked'),
  'collected',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected'),
  'delivered',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered'),
  'external_completed',EXISTS(SELECT 1 FROM public.pdc_external_completion_receipts_20260903 r WHERE r.vehicle_id=v.id),
  'rft_transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at,
  'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,
  'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'current_location',v.current_location,
  'lifecycle_state',v.lifecycle_state::text,
  'external_completion',public.pdc_external_completion_json_20260903(v.id)
) FROM public.vehicles v WHERE v.id=p_vehicle_id),'{}'::jsonb)
$$;
REVOKE ALL ON FUNCTION public.pdc_rft_transport_lifecycle_state_734(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.complete_external_rft_collection_20260903(
  p_vehicle_id uuid,
  p_expected_vehicle_version integer,
  p_completion_type text,
  p_operator_approved boolean,
  p_reason text,
  p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $complete$
DECLARE
  uid uuid:=auth.uid();
  actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v public.vehicles%rowtype;
  old public.pdc_external_completion_receipts_20260903%rowtype;
  b public.workshop_bookings%rowtype;
  collected public.pdc_rft_transport_lifecycle_receipts_734%rowtype;
  request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb;
  collection_evidence jsonb; result jsonb; booking_result jsonb;
  receipt uuid; completed_at timestamptz:=clock_timestamp(); cancelled integer:=0;
  notifications_before bigint; outbox_412_before bigint; outbox_734_before bigint;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
     OR p_completion_type IS NULL OR p_operator_approved IS NULL OR p_idempotency_key IS NULL
     OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 500 THEN
    RETURN jsonb_build_object('ok',false,'code','external_completion_invalid_input');
  END IF;
  IF p_completion_type<>'external_non_navision_final_collection' THEN
    RETURN jsonb_build_object('ok',false,'code','external_completion_type_required');
  END IF;
  IF NOT p_operator_approved THEN
    RETURN jsonb_build_object('ok',false,'code','explicit_operator_approval_required');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  request_payload:=jsonb_build_object(
    'contract','pdc-external-non-navision-final-collection-20260903',
    'vehicle_id',p_vehicle_id,
    'expected_vehicle_version',p_expected_vehicle_version,
    'completion_type',p_completion_type,
    'operator_approved',p_operator_approved,
    'reason',btrim(p_reason),
    'idempotency_key',p_idempotency_key,
    'actor_id',uid
  );
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-external-completion-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_external_completion_receipts_20260903 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-external-completion-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  SELECT * INTO old FROM public.pdc_external_completion_receipts_20260903 WHERE vehicle_id=v.id;
  IF FOUND THEN RETURN jsonb_build_object('ok',false,'code','external_completion_already_recorded','data',jsonb_build_object('receipt_id',old.receipt_id,'vehicle_id',v.id,'vehicle_version',v.version)); END IF;
  IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version)); END IF;
  IF coalesce(v.source_system_normalized,lower(regexp_replace(coalesce(v.source_system,''),'[^a-z0-9]+','','g'))) IN('navision','microsoft_navision','microsoftnavision')
     OR EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id AND n.is_current AND n.record_status='current') THEN
    RETURN jsonb_build_object('ok',false,'code','external_non_navision_vehicle_required');
  END IF;
  SELECT * INTO collected FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected' FOR SHARE;
  IF NOT FOUND OR v.rft_collected_at IS NULL OR v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'COLLECTED' THEN
    RETURN jsonb_build_object('ok',false,'code','recorded_external_collection_required');
  END IF;
  IF v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL OR v.delivered_to_dealer_date IS NOT NULL
     OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered') THEN
    RETURN jsonb_build_object('ok',false,'code','navision_delivery_state_not_external');
  END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id AND x.status::text='started') THEN
    RETURN jsonb_build_object('ok',false,'code','started_booking_must_be_completed_before_external_completion');
  END IF;

  notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
  outbox_412_before:=(SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412);
  outbox_734_before:=(SELECT count(*) FROM public.pdc_rft_transport_email_outbox_734);
  before_state:=jsonb_build_object('vehicle',to_jsonb(v),'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id));
  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN('completed','deleted','cancelled') ORDER BY id FOR UPDATE LOOP
    booking_result:=public.cancel_workshop_booking(b.id,b.version,'External/non-Navision vehicle completed after recorded collection',jsonb_build_object('source','complete_external_rft_collection_20260903'));
    IF NOT coalesce((booking_result->>'ok')::boolean,false) THEN
      RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_BOOKING_CANCEL_FAILED:%',coalesce(booking_result->>'error',booking_result->>'code','unknown') USING errcode='40001';
    END IF;
    cancelled:=cancelled+1;
  END LOOP;

  receipt:=extensions.uuid_generate_v5('13000000-0000-5000-8000-000000001300'::uuid,uid::text||':'||p_idempotency_key::text);
  collection_evidence:=jsonb_build_object(
    'rft_collection_receipt_id',collected.receipt_id,
    'rft_collected_at',v.rft_collected_at,
    'rft_collected_by',v.rft_collected_by,
    'receipt_evidence',collected.evidence,
    'physical_collection_recorded',true,
    'physical_delivery_asserted',false
  );
  UPDATE public.vehicles SET
    lifecycle_state='completed',current_location='Completed',visible_on_board=false,
    pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,active_workshop_booking_id=NULL,
    workshop_status=NULL,workshop_status_updated_at=completed_at,workshop_status_updated_by=uid,
    source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
      'completion_authority','external_non_navision_final_collection',
      'external_completion_receipt_id',receipt,
      'external_completion_at',completed_at,
      'physical_collection_recorded',true,
      'physical_delivery_asserted',false),
    version=version+1,updated_at=completed_at,updated_by=uid
  WHERE id=v.id RETURNING * INTO v;
  after_state:=jsonb_build_object('vehicle',to_jsonb(v),'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id));
  result:=jsonb_build_object('ok',true,'code','external_collection_completed','replay',false,'data',jsonb_build_object(
    'receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,
    'completion_type',p_completion_type,'completion_authority','external_non_navision_final_collection','completed_at',completed_at,
    'current_location','Completed','lifecycle_state','completed','cancelled_active_booking_count',cancelled,
    'physical_collection_recorded',true,'physical_delivery_asserted',false,'navision_delivery_authority_used',false,
    'dealer_transit_closed_at',null,'dealer_transit_duration_seconds',null,'delivered_to_dealer_date',null));
  INSERT INTO public.pdc_external_completion_receipts_20260903(
    receipt_id,vehicle_id,expected_vehicle_version,vehicle_version_after,completion_type,operator_approved,reason,
    actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,
    physical_collection_evidence,response,completed_at)
  VALUES(receipt,v.id,p_expected_vehicle_version,v.version,p_completion_type,true,btrim(p_reason),uid,actor_email,
    p_idempotency_key,request_sha,request_payload,before_state,after_state,collection_evidence,result,completed_at);
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,reason,moved_by)
  VALUES(v.id,'Collected','Completed','Approved external/non-Navision completion after recorded physical collection; delivery not asserted',uid);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state->'vehicle',to_jsonb(v),jsonb_build_object(
    'action','complete_external_rft_collection_20260903','receipt_id',receipt,'completion_type',p_completion_type,
    'operator_approved',true,'reason',btrim(p_reason),'physical_collection_recorded',true,'physical_delivery_asserted',false,
    'navision_delivery_authority_used',false,'cancelled_active_booking_count',cancelled));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=completed_at WHERE singleton;
  IF v.lifecycle_state<>'completed' OR v.current_location<>'Completed' OR v.visible_on_board
     OR v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL OR v.delivered_to_dealer_date IS NOT NULL
     OR v.active_workshop_booking_id IS NOT NULL
     OR EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id AND x.status::text NOT IN('completed','deleted','cancelled'))
     OR (SELECT count(*) FROM public.vehicle_notifications)<>notifications_before
     OR (SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412)<>outbox_412_before
     OR (SELECT count(*) FROM public.pdc_rft_transport_email_outbox_734)<>outbox_734_before THEN
    RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_external_completion_receipts_20260903 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND AND old.request_sha256=request_sha THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN jsonb_build_object('ok',false,'code','external_completion_conflict');
END $complete$;
REVOKE ALL ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.read_pdc_external_completion_20260903(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); r public.pdc_external_completion_receipts_20260903%rowtype;
BEGIN
  IF uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles x WHERE x.auth_user_id=uid AND lower(x.email)=actor_email AND x.active AND x.account_status='approved' AND x.role IN('viewer','operator','importer','administrator')) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  SELECT * INTO r FROM public.pdc_external_completion_receipts_20260903 WHERE vehicle_id=p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','external_completion_not_found'); END IF;
  RETURN jsonb_build_object('ok',true,'code','external_completion','data',jsonb_build_object(
    'receipt_id',r.receipt_id,'vehicle_id',r.vehicle_id,'completion_type',r.completion_type,'operator_approved',r.operator_approved,
    'reason',r.reason,'completed_at',r.completed_at,'completed_by',r.actor_email,'physical_collection_evidence',r.physical_collection_evidence,
    'before_state',r.before_state,'after_state',r.after_state,'response',r.response,
    'physical_delivery_asserted',false,'navision_delivery_authority_used',false,'production',false));
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_external_completion_20260903(uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_external_completion_20260903(uuid) TO authenticated;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_ext1300;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE base jsonb; rows jsonb; appended jsonb;
BEGIN
  base:=public.get_pdc_email_vehicle_location_snapshot_pre_ext1300();
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object(
    'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734((x->>'id')::uuid),
    'external_completion',public.pdc_external_completion_json_20260903((x->>'id')::uuid)
  ) ORDER BY coalesce(x->>'stock_number',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,vehicles}','[]'::jsonb)) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,
    'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,
    'registration',v.registration,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,
    'visible_on_board',v.visible_on_board,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
    'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'rft_transferred_at',v.rft_transferred_at,
    'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,
    'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,
    'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,'delivered_to_dealer_date',v.delivered_to_dealer_date,
    'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id),
    'external_completion',public.pdc_external_completion_json_20260903(v.id),
    'lifecycle_history',public.pdc_lifecycle_history_payload_82000(v.id)
  ) ORDER BY r.completed_at,r.vehicle_id),'[]'::jsonb) INTO appended
  FROM public.pdc_external_completion_receipts_20260903 r JOIN public.vehicles v ON v.id=r.vehicle_id
  WHERE v.deleted_at IS NULL AND v.lifecycle_state='completed' AND v.current_location='Completed'
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE x->>'id'=v.id::text);
  RETURN jsonb_set(base,'{data,vehicles}',rows||appended,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_ext1300(),public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

DO $post$
BEGIN
  IF NOT has_function_privilege('authenticated','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
     OR has_function_privilege('anon','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
     OR has_function_privilege('service_role','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
     OR NOT has_function_privilege('authenticated','public.read_pdc_external_completion_20260903(uuid)','execute')
     OR has_table_privilege('authenticated','public.pdc_external_completion_receipts_20260903','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_external_completion_receipts_20260903'::regclass) IS DISTINCT FROM true
     OR NOT has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','execute') THEN
    RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_SECURITY_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260903130000','external_non_navision_completion_20260903',ARRAY[
  'Append-only exact successor after deployed STAGING head 20260903125000; Production sentinel and Production project are excluded',
  'Authenticated operator/administrator approval requires exact vehicle UUID, current version, typed external_non_navision_final_collection intent, reason and idempotency key',
  'Only external/non-Navision vehicles with immutable 734 physical collection evidence may complete; current canonical Navision identity and Navision-delivered state are rejected',
  'Completion hides the active Board row, clears residual non-started allocations and bay pointers, retains booking/audit/movement history, and exposes immutable receipt readback',
  'No physical delivery is asserted: dealer transit close, duration and delivered-to-dealer date remain null; Navision OD reconciliation definitions and tables are unchanged',
  'Forced RLS and direct-table denial contain receipts; authoritative snapshot projects one Completed row and typed external completion provenance; outbound counts must remain unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
