-- STAGING ONLY 767: authenticated QC vehicle rejection into PMB Fix First.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-767-qc-vehicle-reject',0));
DO $pre$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR NOT public.pdc_monitor_staging_guard()
    OR v_head IS DISTINCT FROM '20260830050000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830050000' AND name='766_monitor_current_head_compatibility')<>1
    OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
    OR NOT EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active AND mailbox_key='pdc_pmb_email' AND test_mode)
    OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>1
    OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
    RAISE EXCEPTION 'PDC_767_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
END $pre$;

CREATE TABLE public.pdc_qc_vehicle_rejection_receipts_767(
  receipt_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  stock_number text NOT NULL CHECK(length(btrim(stock_number)) BETWEEN 1 AND 40),
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  idempotency_key uuid NOT NULL,
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 240),
  expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
  after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_qc_vehicle_rejection_receipts_767 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_qc_vehicle_rejection_receipts_767 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_qc_vehicle_rejection_receipts_767 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_qc_vehicle_rejection_history_767(
  history_id uuid PRIMARY KEY,
  receipt_id uuid NOT NULL REFERENCES public.pdc_qc_vehicle_rejection_receipts_767(receipt_id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  stock_number text NOT NULL,
  action text NOT NULL CHECK(action='reject_to_pmb_stoppage'),
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 240),
  before_state jsonb,
  after_state jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_qc_vehicle_rejection_history_767 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_qc_vehicle_rejection_history_767 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_qc_vehicle_rejection_history_767 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_qc_vehicle_rejection_append_only_767()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $append$
BEGIN
  RAISE EXCEPTION 'PDC_767_REJECTION_EVIDENCE_APPEND_ONLY' USING errcode='55000';
END $append$;
REVOKE ALL ON FUNCTION public.pdc_qc_vehicle_rejection_append_only_767() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_qc_vehicle_rejection_receipts_append_only_767
  BEFORE UPDATE OR DELETE ON public.pdc_qc_vehicle_rejection_receipts_767
  FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_vehicle_rejection_append_only_767();
CREATE TRIGGER pdc_qc_vehicle_rejection_history_append_only_767
  BEFORE UPDATE OR DELETE ON public.pdc_qc_vehicle_rejection_history_767
  FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_vehicle_rejection_append_only_767();

CREATE FUNCTION public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(
  p_vehicle_id uuid,
  p_stock_number text,
  p_expected_vehicle_version integer,
  p_reason text,
  p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
SET lock_timeout='10s'
SET statement_timeout='90s' AS $reject$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_stock text:=btrim(coalesce(p_stock_number,''));
  v_reason text:=regexp_replace(btrim(coalesce(p_reason,'')),'\\s+',' ','g');
  v_vehicle public.vehicles%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_receipt public.pdc_qc_vehicle_rejection_receipts_767%rowtype;
  v_request jsonb;
  v_sha text;
  v_receipt_id uuid;
  v_history_id uuid;
  v_response jsonb;
  v_notifications_before bigint;
  v_notifications_after bigint;
BEGIN
  IF p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
    OR p_idempotency_key IS NULL OR length(v_stock) NOT BETWEEN 1 AND 40
    OR length(v_reason) NOT BETWEEN 3 AND 240 THEN
    RAISE EXCEPTION 'PDC_767_INVALID_INPUT' USING errcode='22023';
  END IF;
  IF v_actor IS NULL OR v_email='' OR NOT EXISTS(
    SELECT 1 FROM public.pdc_user_roles r
    WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
      AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved'
    FOR SHARE
  ) THEN
    RAISE EXCEPTION 'PDC_767_UNAUTHORIZED' USING errcode='42501';
  END IF;
  v_request:=jsonb_build_object(
    'contract','pdc-qc-vehicle-reject-to-pmb-stoppage-766',
    'vehicle_id',p_vehicle_id,
    'stock_number',v_stock,
    'expected_vehicle_version',p_expected_vehicle_version,
    'reason',v_reason,
    'idempotency_key',p_idempotency_key,
    'actor_id',v_actor
  );
  v_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-766-qc-reject:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_receipt FROM public.pdc_qc_vehicle_rejection_receipts_767 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_receipt.request_sha256<>v_sha OR v_receipt.actor_email<>v_email THEN
      RAISE EXCEPTION 'PDC_767_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023';
    END IF;
    RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-766-qc-reject-vehicle:'||p_vehicle_id::text,0));
  LOCK TABLE public.vehicle_notifications IN SHARE MODE;
  v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_767_VEHICLE_NOT_FOUND' USING errcode='P0002'; END IF;
  IF regexp_replace(upper(btrim(coalesce(v_vehicle.stock_number,''))),'[^A-Z0-9]','','g')<>regexp_replace(upper(v_stock),'[^A-Z0-9]','','g') THEN
    RAISE EXCEPTION 'PDC_767_STOCK_MISMATCH' USING errcode='22023';
  END IF;
  IF v_vehicle.version<>p_expected_vehicle_version THEN
    RAISE EXCEPTION 'PDC_767_VEHICLE_VERSION_CONFLICT' USING errcode='40001';
  END IF;
  IF v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' OR upper(btrim(coalesce(v_vehicle.current_location,'')))<>'QC' THEN
    RAISE EXCEPTION 'PDC_767_VEHICLE_NOT_ACTIVE_QC' USING errcode='22023';
  END IF;
  v_before:=jsonb_build_object(
    'vehicle_id',v_vehicle.id,'stock_number',v_vehicle.stock_number,'customer_name',v_vehicle.customer_name,
    'version',v_vehicle.version,'current_location',v_vehicle.current_location,'pmb_stage',v_vehicle.pmb_stage,
    'workshop_status',v_vehicle.workshop_status,'pmb_stoppage_reason',v_vehicle.pmb_stoppage_reason,
    'pmb_stoppage_started_at',v_vehicle.pmb_stoppage_started_at,'pmb_stoppage_started_by',v_vehicle.pmb_stoppage_started_by,
    'qc_completed_at',v_vehicle.qc_completed_at,'qc_completed_by',v_vehicle.qc_completed_by,
    'active_workshop_booking_id',v_vehicle.active_workshop_booking_id
  );
  UPDATE public.vehicles SET
    current_location='PMB',
    pmb_stage=NULL,
    pmb_bay_stage=NULL,
    pmb_bay_number=NULL,
    pmb_stoppage_reason=v_reason,
    pmb_stoppage_started_at=clock_timestamp(),
    pmb_stoppage_started_by=v_actor,
    pmb_stoppage_cleared_at=NULL,
    pmb_stoppage_cleared_by=NULL,
    workshop_status='stoppage',
    workshop_status_updated_at=clock_timestamp(),
    workshop_status_updated_by=v_actor,
    date_to_pmb=coalesce(date_to_pmb,(clock_timestamp() at time zone 'Australia/Perth')::date),
    qc_completed_at=NULL,
    qc_completed_by=NULL,
    version=version+1,
    updated_at=clock_timestamp(),
    updated_by=v_actor
  WHERE id=p_vehicle_id RETURNING * INTO v_vehicle;
  v_after:=jsonb_build_object(
    'vehicle_id',v_vehicle.id,'stock_number',v_vehicle.stock_number,'customer_name',v_vehicle.customer_name,
    'version',v_vehicle.version,'current_location',v_vehicle.current_location,'pmb_stage',v_vehicle.pmb_stage,
    'workshop_status',v_vehicle.workshop_status,'pmb_stoppage_reason',v_vehicle.pmb_stoppage_reason,
    'pmb_stoppage_started_at',v_vehicle.pmb_stoppage_started_at,'pmb_stoppage_started_by',v_vehicle.pmb_stoppage_started_by,
    'pmb_stoppage_cleared_at',v_vehicle.pmb_stoppage_cleared_at,'pmb_stoppage_cleared_by',v_vehicle.pmb_stoppage_cleared_by,
    'qc_completed_at',v_vehicle.qc_completed_at,'qc_completed_by',v_vehicle.qc_completed_by,
    'active_workshop_booking_id',v_vehicle.active_workshop_booking_id,
    'qc_fix_status','Pending QC fixes','qc_fix_reason',v_reason
  );
  v_receipt_id:=extensions.uuid_generate_v5('76600000-0000-5000-8000-000000000766'::uuid,v_actor::text||':'||p_idempotency_key::text);
  v_history_id:=extensions.uuid_generate_v5('76600000-0000-5000-8000-000000000766'::uuid,v_actor::text||':'||p_idempotency_key::text||':history');
  v_response:=jsonb_build_object(
    'ok',true,'code','qc_vehicle_rejected_to_pmb_stoppage','replay',false,
    'receipt_id',v_receipt_id,'request_sha256',v_sha,'vehicle_id',v_vehicle.id,
    'stock_number',v_vehicle.stock_number,'vehicle_version_before',p_expected_vehicle_version,
    'vehicle_version_after',v_vehicle.version,'status','Pending QC fixes','current_location','PMB',
    'workshop_status','stoppage','reason',v_reason,'notification_delta',0
  );
  INSERT INTO public.pdc_qc_vehicle_rejection_receipts_767(
    receipt_id,vehicle_id,stock_number,actor_id,actor_email,idempotency_key,reason,expected_vehicle_version,
    request_sha256,before_state,after_state,response
  ) VALUES(v_receipt_id,v_vehicle.id,v_vehicle.stock_number,v_actor,v_email,p_idempotency_key,v_reason,p_expected_vehicle_version,v_sha,v_before,v_after,v_response);
  INSERT INTO public.pdc_qc_vehicle_rejection_history_767(
    history_id,receipt_id,vehicle_id,stock_number,action,actor_id,actor_email,reason,before_state,after_state
  ) VALUES(v_history_id,v_receipt_id,v_vehicle.id,v_vehicle.stock_number,'reject_to_pmb_stoppage',v_actor,v_email,v_reason,v_before,v_after);
  PERFORM public.audit_pdc_event('update','vehicles',v_vehicle.id,v_vehicle.id,v_before,v_after,
    jsonb_build_object('action','reject_pdc_qc_vehicle_to_pmb_stoppage_767','receipt_id',v_receipt_id,'reason',v_reason,'notification_enqueued',false));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  v_notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
  IF v_notifications_after<>v_notifications_before
    OR v_vehicle.current_location IS DISTINCT FROM 'PMB'
    OR v_vehicle.workshop_status IS DISTINCT FROM 'stoppage'
    OR v_vehicle.pmb_stoppage_reason IS DISTINCT FROM v_reason
    OR v_vehicle.version<>p_expected_vehicle_version+1 THEN
    RAISE EXCEPTION 'PDC_767_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
  RETURN v_response;
END $reject$;
REVOKE ALL ON FUNCTION public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid) TO authenticated;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_767;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE r jsonb; rows jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_767();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  SELECT coalesce(jsonb_agg(
    x || CASE WHEN x->>'current_location'='PMB' AND q.receipt_id IS NOT NULL THEN jsonb_build_object(
      'qc_fix',jsonb_build_object('status','Pending QC fixes','reason',q.reason,'receipt_id',q.receipt_id,
        'vehicle_id',q.vehicle_id,'stock_number',q.stock_number,'expected_vehicle_version',q.expected_vehicle_version,
        'created_at',q.created_at,'history_preserved',true))
    ELSE '{}'::jsonb END ORDER BY x->>'stock_number'),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x
  LEFT JOIN LATERAL (
    SELECT z.receipt_id,z.vehicle_id,z.stock_number,z.reason,z.expected_vehicle_version,z.created_at
    FROM public.pdc_qc_vehicle_rejection_receipts_767 z
    WHERE z.vehicle_id=(x->>'id')::uuid
    ORDER BY z.created_at DESC,z.receipt_id DESC LIMIT 1
  ) q ON true;
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated,service_role;

DO $post$
BEGIN
  IF to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR NOT public.pdc_monitor_staging_guard()
    OR has_table_privilege('public','public.pdc_qc_vehicle_rejection_receipts_767','SELECT,INSERT,UPDATE,DELETE')
    OR has_table_privilege('anon','public.pdc_qc_vehicle_rejection_receipts_767','SELECT,INSERT,UPDATE,DELETE')
    OR has_table_privilege('authenticated','public.pdc_qc_vehicle_rejection_receipts_767','SELECT,INSERT,UPDATE,DELETE')
    OR has_table_privilege('service_role','public.pdc_qc_vehicle_rejection_receipts_767','SELECT,INSERT,UPDATE,DELETE')
    OR has_function_privilege('public','public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
    RAISE EXCEPTION 'PDC_767_ACL_OR_PRODUCTION_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830060000','767_qc_vehicle_reject_to_pmb_stoppage',ARRAY[
 'Authenticated QC-only vehicle rejection bound to exact UUID, Stock, expected version and idempotency request receipt',
 'Immutable rejection receipt and audit history preserve open QC cycle and completed operation truth',
 'Rejected vehicle moves to PMB with workshop STOPPAGE and authoritative Pending QC fixes projection',
 'Snapshot projects canonical QC fix status/reason only while the vehicle remains in PMB',
 'Production sentinel and outbound notification postconditions remain protected'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
