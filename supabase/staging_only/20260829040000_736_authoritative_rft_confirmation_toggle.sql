-- STAGING ONLY 736: authoritative manual RFT confirmation toggle.
--
-- RFT location and manual RFT confirmation are deliberately separate. A
-- confirmation starts the dealer-transit timer; Email Sales Person remains a
-- later, evidence-producing booking action. Legacy transport paths retain
-- their transport_lifecycle_successor_required fail-closed fences. An allowed untick only reverses
-- the manual confirmation before booking evidence exists and never deletes
-- its receipt/history.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-736-authoritative-rft-confirmation-toggle',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260829030000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260829030000' AND name='737_email_monitor_requeue_receipt_table_binding_repair')<>1
     OR to_regclass('public.pdc_rft_confirmation_receipts_736') IS NOT NULL
     OR to_regprocedure('public.book_rft_transport_734(uuid,integer,uuid)') IS NULL
     OR to_regprocedure('public.collect_rft_transport_734(uuid,integer,uuid)') IS NULL
     OR to_regprocedure('public.pdc_rft_transport_lifecycle_state_734(uuid)') IS NULL
  THEN RAISE EXCEPTION 'PDC_736_STAGING_ONLY' USING errcode='55000'; END IF;
END $guard$;

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS rft_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS rft_confirmed_by uuid REFERENCES auth.users(id);

CREATE TABLE public.pdc_rft_confirmation_receipts_736(
  receipt_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  action text NOT NULL CHECK(action IN('rft_confirmed','rft_unconfirmed')),
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL CHECK(length(btrim(actor_email))>3),
  idempotency_key uuid NOT NULL,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
  before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
  after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
  evidence jsonb NOT NULL CHECK(jsonb_typeof(evidence)='object'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);
CREATE INDEX pdc_rft_confirmation_receipts_736_vehicle_idx
  ON public.pdc_rft_confirmation_receipts_736(vehicle_id,created_at,receipt_id);

CREATE OR REPLACE FUNCTION public.pdc_736_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_736_APPEND_ONLY' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_736_append_only() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_rft_confirmation_receipts_736_append_only
  BEFORE UPDATE OR DELETE ON public.pdc_rft_confirmation_receipts_736
  FOR EACH ROW EXECUTE FUNCTION public.pdc_736_append_only();

ALTER TABLE public.pdc_rft_confirmation_receipts_736 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_confirmation_receipts_736 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_rft_confirmation_receipts_736 FROM public,anon,authenticated,service_role;

-- Keep the existing snapshot contract and add the authoritative manual
-- confirmation/timer fields consumed by both Vehicle Locations and RFT.
CREATE OR REPLACE FUNCTION public.pdc_rft_transport_lifecycle_state_734(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
SELECT coalesce((SELECT jsonb_build_object(
  'state',CASE WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered') THEN 'completed'
    WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected') THEN 'collected'
    WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked') THEN 'rft_booked'
    ELSE lower(v.lifecycle_state::text) END,
  'rft_confirmed',v.rft_confirmed_at IS NOT NULL,
  'rft_confirmed_at',v.rft_confirmed_at,'rft_confirmed_by',v.rft_confirmed_by,
  'rft_booked',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked'),
  'collected',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected'),
  'delivered',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered'),
  'rft_transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at,
  'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,
  'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'current_location',v.current_location,
  'lifecycle_state',v.lifecycle_state::text
) FROM public.vehicles v WHERE v.id=p_vehicle_id),'{}'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.pdc_rft_transport_lifecycle_state_734(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.set_rft_confirmation_736(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_confirmed boolean,p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $toggle$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v public.vehicles%rowtype; old public.pdc_rft_confirmation_receipts_736%rowtype;
  before_state jsonb; after_state jsonb; request_payload jsonb; request_sha text; result jsonb;
  receipt uuid; now_at timestamptz:=clock_timestamp(); action_name text;
  booking_evidence boolean; current_confirmed boolean;
BEGIN
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_confirmed IS NULL OR p_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','rft_confirmation_invalid_input'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  request_payload:=jsonb_build_object('contract','pdc-authoritative-rft-confirmation-736','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'confirmed',p_confirmed,'idempotency_key',p_idempotency_key);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-736-toggle-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_rft_confirmation_receipts_736 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-736-toggle-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF v.version<>p_expected_vehicle_version THEN
    RETURN jsonb_build_object('ok',false,'code','rft_confirmation_stale_version','data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version)); END IF;

  booking_evidence:=v.rft_transport_booked_at IS NOT NULL
    OR v.rft_collected_at IS NOT NULL
    OR v.lifecycle_state::text IN('collected','completed')
    OR upper(btrim(coalesce(v.current_location,''))) IN('COLLECTED','COMPLETED')
    OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action IN('rft_booked','collected','delivered'))
    OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=v.id)
    OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_evidence_734 e WHERE e.vehicle_id=v.id);
  current_confirmed:=v.rft_confirmed_at IS NOT NULL;
  IF NOT p_confirmed AND booking_evidence THEN RETURN jsonb_build_object('ok',false,'code','rft_confirmation_irreversible','data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version,'rft_confirmed',current_confirmed)); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' THEN
    RETURN jsonb_build_object('ok',false,'code','rft_confirmation_invalid_state'); END IF;
  IF current_confirmed=p_confirmed THEN
    RETURN jsonb_build_object('ok',false,'code',case when p_confirmed then 'rft_confirmation_already_set' else 'rft_confirmation_not_set' end,'data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version,'rft_confirmed',current_confirmed,'dealer_transit_started_at',v.dealer_transit_started_at)); END IF;

  before_state:=public.pdc_rft_transport_snapshot_734(v.id);
  action_name:=case when p_confirmed then 'rft_confirmed' else 'rft_unconfirmed' end;
  IF p_confirmed THEN
    UPDATE public.vehicles SET rft_confirmed_at=now_at,rft_confirmed_by=uid,dealer_transit_started_at=coalesce(dealer_transit_started_at,now_at),dealer_transit_closed_at=null,dealer_transit_duration_seconds=null,version=version+1,updated_at=now_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
  ELSE
    -- The timer is open at this point because Email Sales Person evidence is
    -- a hard gate, so clear only the accidental manual confirmation/timer.
    UPDATE public.vehicles SET rft_confirmed_at=null,rft_confirmed_by=null,dealer_transit_started_at=null,dealer_transit_closed_at=null,dealer_transit_duration_seconds=null,version=version+1,updated_at=now_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
  END IF;
  after_state:=public.pdc_rft_transport_snapshot_734(v.id);
  receipt:=extensions.uuid_generate_v5('73600000-0000-5000-8000-000000000736'::uuid,uid::text||':'||action_name||':'||p_idempotency_key::text);
  result:=jsonb_build_object('ok',true,'code',case when p_confirmed then 'rft_confirmed' else 'rft_unconfirmed' end,'replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,'rft_confirmed',p_confirmed,'rft_confirmation_at',v.rft_confirmed_at,'rft_confirmation_by',v.rft_confirmed_by,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text));
  INSERT INTO public.pdc_rft_confirmation_receipts_736(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,action_name,uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,jsonb_build_object('manual_confirmation',p_confirmed,'timer_started_at',v.dealer_transit_started_at,'timer_cleared',not p_confirmed,'booking_evidence_at_request',booking_evidence,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version),result);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state,after_state,jsonb_build_object('action','set_rft_confirmation_736','receipt_id',receipt,'confirmed',p_confirmed,'timer_started_at',v.dealer_transit_started_at,'timer_cleared',not p_confirmed));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=now_at WHERE singleton;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_rft_confirmation_receipts_736 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN jsonb_build_object('ok',false,'code','rft_confirmation_conflict');
END $toggle$;
REVOKE ALL ON FUNCTION public.set_rft_confirmation_736(uuid,integer,boolean,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_rft_confirmation_736(uuid,integer,boolean,uuid) TO authenticated;

-- The current booking successor remains the booking writer, but now cannot be
-- reached before the manual confirmation and never resets its timer start.
DO $patch$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.book_rft_transport_734(uuid,integer,uuid)'::regprocedure) INTO d;
  d:=replace(d,
    $find$IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' OR v.rft_collected_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_rft'); END IF;$find$,
    $replace$IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' OR v.rft_collected_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_rft'); END IF;
  IF v.rft_confirmed_at IS NULL THEN RETURN jsonb_build_object('ok',false,'code','rft_confirmation_required'); END IF;$replace$);
  d:=replace(d,$find$dealer_transit_started_at=booked_at,version=version+1$find$,$replace$dealer_transit_started_at=coalesce(dealer_transit_started_at,booked_at),version=version+1$replace$);
  d:=replace(d,$find$'dealer_transit_started_at',booked_at$find$,$replace$'dealer_transit_started_at',v.dealer_transit_started_at$replace$);
  d:=replace(d,$find$'timer_started_at',booked_at$find$,$replace$'timer_started_at',v.dealer_transit_started_at$replace$);
  d:=replace(d,$find$v.rft_transport_booked_at IS DISTINCT FROM booked_at OR v.dealer_transit_started_at IS DISTINCT FROM booked_at$find$,$replace$v.rft_transport_booked_at IS DISTINCT FROM booked_at OR v.dealer_transit_started_at IS NULL$replace$);
  IF position('rft_confirmation_required' in d)=0 OR position('coalesce(dealer_transit_started_at,booked_at)' in d)=0 THEN
    RAISE EXCEPTION 'PDC_736_BOOKING_SUCCESSOR_PATCH_FAILED' USING errcode='55000'; END IF;
  EXECUTE d;
END $patch$;

DO $post$
BEGIN
  IF NOT has_function_privilege('authenticated','public.set_rft_confirmation_736(uuid,integer,boolean,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.set_rft_confirmation_736(uuid,integer,boolean,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.set_rft_confirmation_736(uuid,integer,boolean,uuid)','EXECUTE')
     OR has_table_privilege('authenticated','public.pdc_rft_confirmation_receipts_736','SELECT,INSERT,UPDATE,DELETE')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_rft_confirmation_receipts_736'::regclass) IS DISTINCT FROM true
     OR position('rft_confirmation_required' in pg_get_functiondef('public.book_rft_transport_734(uuid,integer,uuid)'::regprocedure))=0
     OR position('coalesce(dealer_transit_started_at,booked_at)' in pg_get_functiondef('public.book_rft_transport_734(uuid,integer,uuid)'::regprocedure))=0
     OR has_function_privilege('authenticated','public.book_rft_transport_412(uuid,integer,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.collect_rft_transport_412(uuid,integer,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.book_rft_transport_700(uuid,integer,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.collect_rft_transport_700(uuid,integer,uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'PDC_736_SECURITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260829040000','736_authoritative_rft_confirmation_toggle',ARRAY[
  'Staging-only authoritative RFT confirmation toggle with exact vehicle/version/role/idempotency guards',
  'Tick records append-only manual confirmation and starts the dealer-transit timer while preserving an already-RFT location',
  'Permitted untick appends history and clears only the accidental open timer; booking, email evidence, Collected and Completed are irreversible',
  'Email Sales Person remains confirmation-gated and preserves the tick timestamp; legacy 412/700 paths remain fenced',
  'Forced-RLS append-only receipts and authoritative snapshot/version readback; Production sentinel forbidden'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
