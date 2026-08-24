-- STAGING ONLY 363: guarded append-only bootstrap for one synthetic fleet run.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-363-overnight-synthetic-fleet',0));

-- SHARE conflicts with the ROW EXCLUSIVE lock taken by INSERT/UPDATE/DELETE.
-- These transaction-scoped locks close the check-to-commit containment race.
LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;

DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260824230000' AND name='362_align_anderson_plugs_and_job_counts')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260824230000' AND version~'^[0-9]{14}$')
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_363_STAGING_TARGET_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
END $guard$;

CREATE TABLE public.pdc_overnight_synthetic_fleet_registry_363(
 registry_id uuid PRIMARY KEY,
 run_id text NOT NULL CHECK(run_id='HERMES-TEST-RUN-20260824'),
 scenario_no integer NOT NULL CHECK(scenario_no BETWEEN 1 AND 20),
 scenario_name text NOT NULL CHECK(length(scenario_name) BETWEEN 12 AND 120 AND scenario_name~'^HERMES-TEST'),
 vehicle_id uuid NOT NULL UNIQUE REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 stock_number text NOT NULL UNIQUE CHECK(stock_number~'^HERMES-TEST-(00[1-9]|01[0-9]|020)$'),
 customer_name text NOT NULL CHECK(length(customer_name) BETWEEN 12 AND 120 AND customer_name~'^HERMES-TEST'),
 job_card_number text NOT NULL CHECK(length(job_card_number) BETWEEN 12 AND 80 AND job_card_number~'^HERMES-TEST'),
 vehicle_description text NOT NULL CHECK(length(vehicle_description) BETWEEN 12 AND 180 AND vehicle_description~'^HERMES-TEST'),
 spec jsonb NOT NULL CHECK(jsonb_typeof(spec)='object'),
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(run_id,scenario_no),
 UNIQUE(run_id,scenario_name)
);

CREATE TABLE public.pdc_overnight_synthetic_fleet_receipts_363(
 receipt_id uuid PRIMARY KEY,
 run_id text NOT NULL CHECK(run_id='HERMES-TEST-RUN-20260824'),
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);

CREATE TABLE public.pdc_overnight_synthetic_fleet_events_363(
 event_id uuid PRIMARY KEY,
 run_id text NOT NULL CHECK(run_id='HERMES-TEST-RUN-20260824'),
 registry_id uuid NOT NULL REFERENCES public.pdc_overnight_synthetic_fleet_registry_363(registry_id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 idempotency_key uuid NOT NULL,
 event_kind text NOT NULL CHECK(event_kind='bootstrapped'),
 event_payload jsonb NOT NULL CHECK(jsonb_typeof(event_payload)='object'),
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(run_id,vehicle_id,event_kind)
);

ALTER TABLE public.pdc_overnight_synthetic_fleet_registry_363 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_overnight_synthetic_fleet_receipts_363 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_overnight_synthetic_fleet_events_363 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_overnight_synthetic_fleet_registry_363 FROM public,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.pdc_overnight_synthetic_fleet_receipts_363 FROM public,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.pdc_overnight_synthetic_fleet_events_363 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_overnight_synthetic_fleet_append_only_363()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$
BEGIN
 RAISE EXCEPTION 'PDC_363_APPEND_ONLY' USING errcode='55000';
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_overnight_synthetic_fleet_append_only_363() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_overnight_synthetic_fleet_registry_append_only_363 BEFORE UPDATE OR DELETE ON public.pdc_overnight_synthetic_fleet_registry_363
 FOR EACH ROW EXECUTE FUNCTION public.pdc_overnight_synthetic_fleet_append_only_363();
CREATE TRIGGER pdc_overnight_synthetic_fleet_receipts_append_only_363 BEFORE UPDATE OR DELETE ON public.pdc_overnight_synthetic_fleet_receipts_363
 FOR EACH ROW EXECUTE FUNCTION public.pdc_overnight_synthetic_fleet_append_only_363();
CREATE TRIGGER pdc_overnight_synthetic_fleet_events_append_only_363 BEFORE UPDATE OR DELETE ON public.pdc_overnight_synthetic_fleet_events_363
 FOR EACH ROW EXECUTE FUNCTION public.pdc_overnight_synthetic_fleet_append_only_363();

CREATE FUNCTION public.read_pdc_hermes_test_fleet(p_run_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $read$
DECLARE
 v_actor uuid:=auth.uid();
 v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_rows jsonb;
 v_catalog_sha256 text;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' THEN
  RAISE EXCEPTION 'PDC_363_RUN_NOT_ALLOWED' USING errcode='22023';
 END IF;
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r
  WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
    AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved'
 ) THEN RAISE EXCEPTION 'PDC_363_UNAUTHORIZED' USING errcode='42501'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_363_WRONG_ENVIRONMENT' USING errcode='55000';
 END IF;
 SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg(r.spec ORDER BY r.scenario_no),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
 INTO v_catalog_sha256 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id;
 IF (SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id)<>20
   OR v_catalog_sha256<>'0bc2791f0b79bf03018f5d3ec444441253c0aa8a994dd8a31f7bd49f20738d16' THEN
  RAISE EXCEPTION 'PDC_363_READBACK_DRIFT' USING errcode='55000';
 END IF;
 IF EXISTS(
  SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
  LEFT JOIN public.vehicles v ON v.id=r.vehicle_id
  WHERE r.run_id=p_run_id AND (
    r.scenario_no IS DISTINCT FROM (r.spec->>'scenario_no')::integer OR r.scenario_name IS DISTINCT FROM r.spec->>'scenario_name'
    OR r.stock_number IS DISTINCT FROM r.spec->>'stock' OR r.customer_name IS DISTINCT FROM r.spec->>'customer'
    OR r.job_card_number IS DISTINCT FROM r.spec->>'job_card' OR r.vehicle_description IS DISTINCT FROM r.spec->>'description'
    OR r.registry_id IS DISTINCT FROM extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':registry:'||r.scenario_no::text)
    OR r.vehicle_id IS DISTINCT FROM extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':vehicle:'||r.stock_number)
    OR v.id IS NULL OR v.permanent_vehicle_id IS DISTINCT FROM 'HERMES-TEST-PERM-'||lpad(r.scenario_no::text,3,'0')
    OR v.stock_number IS DISTINCT FROM r.stock_number OR v.customer_name IS DISTINCT FROM r.customer_name OR v.job_card_number IS DISTINCT FROM r.job_card_number
    OR v.vehicle_description IS DISTINCT FROM r.vehicle_description OR v.current_location IS DISTINCT FROM coalesce(nullif(r.spec->>'initial_location',''),'Other')
    OR v.eta_to_kewdale IS DISTINCT FROM nullif(r.spec->>'eta','')::date
    OR v.lifecycle_state IS DISTINCT FROM 'active' OR v.visible_on_board IS DISTINCT FROM true OR v.deleted_at IS NOT NULL OR v.board_purged_at IS NOT NULL
    OR v.rft_collected_at IS NOT NULL OR upper(coalesce(v.current_location,''))='COMPLETED'
    OR v.source_system IS DISTINCT FROM 'hermes_overnight_synthetic' OR v.source_batch_id IS DISTINCT FROM p_run_id OR v.source_record_id IS DISTINCT FROM r.stock_number
    OR v.source_payload->>'contract' IS DISTINCT FROM 'pdc-overnight-synthetic-fleet-363/render_only'
    OR v.source_payload->>'run_id' IS DISTINCT FROM p_run_id OR (v.source_payload->>'scenario_no')::integer IS DISTINCT FROM r.scenario_no
    OR v.source_payload->>'scenario_name' IS DISTINCT FROM r.scenario_name OR v.source_payload->>'request_sha256' IS DISTINCT FROM r.request_sha256
    OR (v.source_payload->>'completion_evidence')::boolean IS DISTINCT FROM false
    OR (SELECT count(*) FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id)<>jsonb_array_length(coalesce(r.spec->'work_keys','[]'::jsonb))
    OR EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND (
      wi.work_key IS NULL OR NOT (coalesce(r.spec->'work_keys','[]'::jsonb)?wi.work_key)
      OR wi.id IS DISTINCT FROM extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':work:'||r.stock_number||':'||wi.work_key)
      OR wi.required IS DISTINCT FROM true OR wi.completed IS DISTINCT FROM false OR wi.completed_by IS NOT NULL OR wi.completed_at IS NOT NULL
      OR wi.notes IS DISTINCT FROM coalesce(nullif(btrim(r.spec->>'notes'),''),'HERMES-TEST render-only incomplete synthetic requirement')))
    OR EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id)
    OR EXISTS(SELECT 1 FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id)
    OR EXISTS(SELECT 1 FROM public.pdc_sublet_bookings s WHERE s.vehicle_id=v.id)
    OR EXISTS(SELECT 1 FROM public.vehicle_sublet_providers s WHERE s.vehicle_id=v.id)
    OR EXISTS(SELECT 1 FROM public.pdc_authenticated_email_import_receipts e WHERE e.vehicle_id=v.id)
    OR coalesce(to_jsonb(v)->>'qc_completed_at','')<>'' OR coalesce(to_jsonb(v)->>'rft_at','')<>''
  )) THEN RAISE EXCEPTION 'PDC_363_READBACK_DRIFT' USING errcode='55000'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'registry_id',r.registry_id,'run_id',r.run_id,'scenario_no',r.scenario_no,'scenario_name',r.scenario_name,
   'request_sha256',r.request_sha256,'spec',r.spec,'created_at',r.created_at,
   'vehicle',jsonb_build_object('id',v.id,'version',v.version,'permanent_vehicle_id',v.permanent_vehicle_id,
    'stock_number',v.stock_number,'customer_name',v.customer_name,'job_card_number',v.job_card_number,
    'vehicle_description',v.vehicle_description,'current_location',v.current_location,'eta_to_kewdale',v.eta_to_kewdale,
    'lifecycle_state',v.lifecycle_state,'visible_on_board',v.visible_on_board,'source_system',v.source_system,
    'source_batch_id',v.source_batch_id,'source_record_id',v.source_record_id),
   'work_items',coalesce((SELECT jsonb_agg(jsonb_build_object('id',wi.id,'work_key',wi.work_key,'required',wi.required,
      'completed',wi.completed,'completed_by',wi.completed_by,'completed_at',wi.completed_at,'notes',wi.notes)
      ORDER BY wi.work_key) FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id),'[]'::jsonb)
  ) ORDER BY r.scenario_no),'[]'::jsonb) INTO v_rows
 FROM public.vehicles v
 JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=v.id
 WHERE r.run_id=p_run_id;
 IF jsonb_array_length(v_rows)<>20 THEN RAISE EXCEPTION 'PDC_363_READBACK_DRIFT' USING errcode='55000'; END IF;
 RETURN jsonb_build_object('ok',true,'run_id',p_run_id,'vehicles',v_rows,'count',jsonb_array_length(v_rows));
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_hermes_test_fleet(text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_hermes_test_fleet(text) TO authenticated;

CREATE FUNCTION public.bootstrap_pdc_hermes_test_fleet(p_run_id text,p_idempotency_key uuid,p_specs jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='180s' AS $bootstrap$
DECLARE
 v_actor uuid:=auth.uid();
 v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_specs_sha256 text;
 v_request_sha256 text;
 v_receipt public.pdc_overnight_synthetic_fleet_receipts_363%rowtype;
 v_receipt_id uuid;
 v_spec jsonb;
 v_no integer;
 v_name text;
 v_stock text;
 v_customer text;
 v_job text;
 v_description text;
 v_location text;
 v_eta date;
 v_notes text;
 v_work_keys jsonb;
 v_ids jsonb:='[]'::jsonb;
 v_shared_revision_before bigint;
 v_shared_revision_after bigint;
 v_shared_revision_recheck bigint;
 v_before_vehicle_count bigint;
 v_after_vehicle_count bigint;
 v_before_registry_count bigint;
 v_after_registry_count bigint;
 v_before_notification_count bigint;
 v_after_notification_count bigint;
 v_before_receipt_count bigint;
 v_before_event_count bigint;
 v_before_booking_count bigint;
 v_before_work_count bigint;
 v_before_parts_count bigint;
 v_before_sublet_count bigint;
 v_before_provider_count bigint;
 v_before_email_count bigint;
 v_expected_work_count bigint;
 v_target_vehicle_ids uuid[];
 v_protected_vehicle_count_before bigint;
 v_protected_vehicle_count_after bigint;
 v_protected_digest_before text;
 v_protected_digest_after text;
 v_response jsonb;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' OR p_idempotency_key IS NULL
   OR jsonb_typeof(p_specs) IS DISTINCT FROM 'array' OR jsonb_array_length(p_specs)<>20 THEN
  RAISE EXCEPTION 'PDC_363_INVALID_RUN_OR_EXACT_20_SPECS' USING errcode='22023';
 END IF;
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r
  WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
    AND r.role='administrator' AND r.active AND r.account_status='approved'
  FOR SHARE
 ) THEN RAISE EXCEPTION 'PDC_363_UNAUTHORIZED' USING errcode='42501'; END IF;

 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-363-overnight-synthetic-fleet',0));
 LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
 LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
 LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
 LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
 LOCK TABLE public.vehicle_notifications IN SHARE MODE;
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_363_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;

 IF EXISTS(
  SELECT 1 FROM jsonb_array_elements(p_specs) spec
  WHERE jsonb_typeof(spec)<>'object'
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(spec) k
      WHERE k<>ALL(ARRAY['scenario_no','scenario_name','stock','customer','job_card','description','initial_location','eta','work_keys','notes']))
    OR jsonb_typeof(spec->'scenario_no') IS DISTINCT FROM 'number'
    OR jsonb_typeof(spec->'scenario_name') IS DISTINCT FROM 'string'
    OR jsonb_typeof(spec->'stock') IS DISTINCT FROM 'string'
    OR jsonb_typeof(spec->'customer') IS DISTINCT FROM 'string'
    OR jsonb_typeof(spec->'job_card') IS DISTINCT FROM 'string'
    OR jsonb_typeof(spec->'description') IS DISTINCT FROM 'string'
    OR (spec?'initial_location' AND jsonb_typeof(spec->'initial_location') IS DISTINCT FROM 'string')
    OR (spec?'eta' AND jsonb_typeof(spec->'eta') IS DISTINCT FROM 'string')
    OR (spec?'notes' AND jsonb_typeof(spec->'notes') IS DISTINCT FROM 'string')
    OR (spec?'work_keys' AND jsonb_typeof(spec->'work_keys') IS DISTINCT FROM 'array')
 ) THEN RAISE EXCEPTION 'PDC_363_INVALID_SPEC_SHAPE' USING errcode='22023'; END IF;
 v_specs_sha256:=encode(extensions.digest(convert_to(p_specs::text,'UTF8'),'sha256'),'hex');
 IF v_specs_sha256<>'0bc2791f0b79bf03018f5d3ec444441253c0aa8a994dd8a31f7bd49f20738d16' THEN
  RAISE EXCEPTION 'PDC_363_EXACT_LOGGED_CATALOG_REQUIRED' USING errcode='22023';
 END IF;

 -- The request identity is independent of execution time. Lock and inspect its
 -- immutable receipt before first-write-only validation such as future ETA.
 v_request_sha256:=encode(extensions.digest(convert_to(jsonb_build_object(
   'contract','pdc-overnight-synthetic-fleet-363/render_only','run_id',p_run_id,
   'actor_id',v_actor,'idempotency_key',p_idempotency_key,'specs',p_specs)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-363-receipt:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_overnight_synthetic_fleet_receipts_363
 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_receipt.request_sha256<>v_request_sha256 THEN
   RAISE EXCEPTION 'PDC_363_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023';
  END IF;
  LOCK TABLE public.vehicles IN SHARE MODE;
  LOCK TABLE public.vehicle_aliases IN SHARE MODE;
  LOCK TABLE public.pdc_vehicle_tombstones IN SHARE MODE;
  LOCK TABLE public.navision_backend_records IN SHARE MODE;
  LOCK TABLE public.navision_board_activations IN SHARE MODE;
  LOCK TABLE public.pdc_overnight_synthetic_fleet_registry_363 IN SHARE MODE;
  LOCK TABLE public.pdc_overnight_synthetic_fleet_receipts_363 IN SHARE MODE;
  LOCK TABLE public.pdc_overnight_synthetic_fleet_events_363 IN SHARE MODE;
  LOCK TABLE public.vehicle_work_items IN SHARE MODE;
  LOCK TABLE public.workshop_bookings IN SHARE MODE;
  LOCK TABLE public.vehicle_parts_updates IN SHARE MODE;
  LOCK TABLE public.pdc_sublet_bookings IN SHARE MODE;
  LOCK TABLE public.vehicle_sublet_providers IN SHARE MODE;
  LOCK TABLE public.pdc_authenticated_email_import_receipts IN SHARE MODE;
  SELECT revision INTO v_shared_revision_before
  FROM public.pdc_email_vehicle_revision WHERE singleton FOR UPDATE;
  IF NOT FOUND OR (SELECT count(*) FROM public.pdc_email_vehicle_revision WHERE singleton)<>1 THEN
   RAISE EXCEPTION 'PDC_363_SHARED_REVISION_SINGLETON_MISMATCH' USING errcode='55000';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
         AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
    OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
    OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
    OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
   RAISE EXCEPTION 'PDC_363_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
  PERFORM public.read_pdc_hermes_test_fleet(p_run_id);
  SELECT revision INTO v_shared_revision_after
  FROM public.pdc_email_vehicle_revision WHERE singleton;
  IF v_shared_revision_after IS DISTINCT FROM v_shared_revision_before THEN
   RAISE EXCEPTION 'PDC_363_REPLAY_SHARED_REVISION_CHANGED' USING errcode='55000';
  END IF;
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false)
    || jsonb_build_object('replay_revision',jsonb_build_object(
      'table','public.pdc_email_vehicle_revision','before',v_shared_revision_before,
      'after',v_shared_revision_after,'delta',v_shared_revision_after-v_shared_revision_before));
 END IF;

 -- No immutable receipt exists: all remaining checks are first-write validation.
 IF (SELECT count(DISTINCT (spec->>'scenario_no')::integer) FROM jsonb_array_elements(p_specs) spec
     WHERE (spec->>'scenario_no')~'^([1-9]|1[0-9]|20)$')<>20
   OR EXISTS(SELECT 1 FROM generate_series(1,20) n WHERE NOT EXISTS(
      SELECT 1 FROM jsonb_array_elements(p_specs) spec WHERE spec->>'scenario_no'=n::text)) THEN
  RAISE EXCEPTION 'PDC_363_SCENARIOS_MUST_BE_UNIQUE_1_TO_20' USING errcode='22023';
 END IF;
 IF (SELECT count(DISTINCT spec->>'scenario_name') FROM jsonb_array_elements(p_specs) spec)<>20
   OR (SELECT count(DISTINCT spec->>'stock') FROM jsonb_array_elements(p_specs) spec)<>20 THEN
  RAISE EXCEPTION 'PDC_363_SCENARIO_OR_STOCK_NOT_UNIQUE' USING errcode='22023';
 END IF;

 FOR v_spec IN SELECT value FROM jsonb_array_elements(p_specs) ORDER BY (value->>'scenario_no')::integer LOOP
  v_no:=(v_spec->>'scenario_no')::integer;
  v_name:=btrim(coalesce(v_spec->>'scenario_name',''));
  v_stock:=btrim(coalesce(v_spec->>'stock',''));
  v_customer:=btrim(coalesce(v_spec->>'customer',''));
  v_job:=btrim(coalesce(v_spec->>'job_card',''));
  v_description:=btrim(coalesce(v_spec->>'description',''));
  v_location:=coalesce(nullif(btrim(v_spec->>'initial_location'),''),'Other');
  v_notes:=nullif(btrim(v_spec->>'notes'),'');
  v_work_keys:=coalesce(v_spec->'work_keys','[]'::jsonb);
  IF v_stock IS DISTINCT FROM 'HERMES-TEST-'||lpad(v_no::text,3,'0')
    OR v_spec->>'scenario_name' IS DISTINCT FROM v_name OR v_spec->>'stock' IS DISTINCT FROM v_stock
    OR v_spec->>'customer' IS DISTINCT FROM v_customer OR v_spec->>'job_card' IS DISTINCT FROM v_job
    OR v_spec->>'description' IS DISTINCT FROM v_description
    OR (v_spec?'initial_location' AND v_spec->>'initial_location' IS DISTINCT FROM v_location)
    OR v_name !~ '^HERMES-TEST' OR length(v_name) NOT BETWEEN 12 AND 120
    OR v_customer !~ '^HERMES-TEST' OR length(v_customer) NOT BETWEEN 12 AND 120
    OR v_job !~ '^HERMES-TEST' OR length(v_job) NOT BETWEEN 12 AND 80
    OR v_description !~ '^HERMES-TEST' OR length(v_description) NOT BETWEEN 12 AND 180
    OR v_name~'[[:cntrl:]]' OR v_customer~'[[:cntrl:]]' OR v_job~'[[:cntrl:]]' OR v_description~'[[:cntrl:]]'
    OR v_location NOT IN('Other','IT','YH','PMB')
    OR jsonb_typeof(v_work_keys)<>'array'
    OR (v_notes IS NOT NULL AND (v_spec->>'notes' IS DISTINCT FROM v_notes OR v_notes !~ '^HERMES-TEST'
      OR length(v_notes) NOT BETWEEN 12 AND 240 OR v_notes~'[[:cntrl:]]')) THEN
   RAISE EXCEPTION 'PDC_363_SYNTHETIC_PREFIX_OR_LENGTH_INVALID:%',v_no USING errcode='22023';
  END IF;
  BEGIN v_eta:=nullif(v_spec->>'eta','')::date;
  EXCEPTION WHEN others THEN RAISE EXCEPTION 'PDC_363_ETA_INVALID:%',v_no USING errcode='22023'; END;
  IF v_eta IS NOT NULL AND (v_spec->>'eta' IS DISTINCT FROM v_eta::text OR v_location<>'IT' OR v_eta<=CURRENT_DATE) THEN
   RAISE EXCEPTION 'PDC_363_ETA_ONLY_FUTURE_IT:%',v_no USING errcode='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_work_keys) x WHERE jsonb_typeof(x)<>'string')
    OR jsonb_array_length(v_work_keys)<>(SELECT count(DISTINCT x) FROM jsonb_array_elements_text(v_work_keys) x)
    OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_work_keys) x WHERE x NOT IN(
      SELECT s.work_key FROM public.workshop_stages s WHERE s.active UNION SELECT 'PARTS')) THEN
   RAISE EXCEPTION 'PDC_363_WORK_KEYS_NOT_UNIQUE_CANONICAL_SUBSET:%',v_no USING errcode='22023';
  END IF;
 END LOOP;

 LOCK TABLE public.vehicles IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicle_aliases IN SHARE MODE;
 LOCK TABLE public.pdc_vehicle_tombstones IN SHARE MODE;
 LOCK TABLE public.navision_backend_records IN SHARE MODE;
 LOCK TABLE public.navision_board_activations IN SHARE MODE;
 LOCK TABLE public.pdc_overnight_synthetic_fleet_registry_363 IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.pdc_overnight_synthetic_fleet_receipts_363 IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.pdc_overnight_synthetic_fleet_events_363 IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicle_work_items IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.workshop_bookings IN SHARE MODE;
 LOCK TABLE public.vehicle_parts_updates IN SHARE MODE;
 LOCK TABLE public.pdc_sublet_bookings IN SHARE MODE;
 LOCK TABLE public.vehicle_sublet_providers IN SHARE MODE;
 LOCK TABLE public.pdc_authenticated_email_import_receipts IN SHARE MODE;

 -- Migration 096 installs one AFTER ... FOR EACH STATEMENT trigger on each of
 -- vehicles and vehicle_work_items. Both call bump_pdc_email_vehicle_revision(),
 -- whose only authoritative side effect is +1 on this realtime-published singleton.
 -- Target tables are locked first to preserve trigger lock order; then this row lock
 -- serializes the receipt boundary without disabling triggers or writing revision.
 SELECT revision INTO v_shared_revision_before
 FROM public.pdc_email_vehicle_revision WHERE singleton FOR UPDATE;
 IF NOT FOUND OR (SELECT count(*) FROM public.pdc_email_vehicle_revision WHERE singleton)<>1 THEN
  RAISE EXCEPTION 'PDC_363_SHARED_REVISION_SINGLETON_MISMATCH' USING errcode='55000';
 END IF;

 SELECT array_agg(extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,
   p_run_id||':vehicle:'||(spec->>'stock')) ORDER BY (spec->>'scenario_no')::integer)
 INTO v_target_vehicle_ids FROM jsonb_array_elements(p_specs) spec;

 v_before_vehicle_count:=(SELECT count(*) FROM public.vehicles);
 v_before_registry_count:=(SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_registry_363);
 v_before_notification_count:=(SELECT count(*) FROM public.vehicle_notifications);
 v_before_receipt_count:=(SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_receipts_363);
 v_before_event_count:=(SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_events_363);
 v_before_booking_count:=(SELECT count(*) FROM public.workshop_bookings);
 v_before_work_count:=(SELECT count(*) FROM public.vehicle_work_items);
 v_before_parts_count:=(SELECT count(*) FROM public.vehicle_parts_updates);
 v_before_sublet_count:=(SELECT count(*) FROM public.pdc_sublet_bookings);
 v_before_provider_count:=(SELECT count(*) FROM public.vehicle_sublet_providers);
 v_before_email_count:=(SELECT count(*) FROM public.pdc_authenticated_email_import_receipts);
 SELECT count(*),encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
   INTO v_protected_vehicle_count_before,v_protected_digest_before FROM public.vehicles v
   WHERE NOT (v.id=ANY(v_target_vehicle_ids));
 v_expected_work_count:=(SELECT coalesce(sum(jsonb_array_length(coalesce(spec->'work_keys','[]'::jsonb))),0)
   FROM jsonb_array_elements(p_specs) spec);
 IF v_before_notification_count<>0 THEN RAISE EXCEPTION 'PDC_363_NOTIFICATIONS_NOT_EMPTY' USING errcode='55000'; END IF;

 IF EXISTS(
  SELECT 1 FROM public.vehicles v
  WHERE v.source_system_normalized='hermes_overnight_synthetic'
    OR v.source_batch_id='HERMES-TEST-RUN-20260824'
    OR v.source_record_id ILIKE 'HERMES-TEST-%'
    OR coalesce(v.source_record_id_normalized,'') LIKE 'HERMESTEST%'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_specs) spec
      CROSS JOIN LATERAL (SELECT
        extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':vehicle:'||(spec->>'stock')) vehicle_id,
        'HERMES-TEST-PERM-'||lpad(spec->>'scenario_no',3,'0') permanent_vehicle_id,
        public.normalize_vehicle_stock_number(spec->>'stock') normalized_stock) i
      WHERE v.id=i.vehicle_id OR v.permanent_vehicle_id=i.permanent_vehicle_id
        OR v.stock_number_normalized=i.normalized_stock
        OR v.stock_number=spec->>'stock' OR v.source_record_id_normalized=public.normalize_vehicle_source_identifier(spec->>'stock'))
 ) OR EXISTS(
  SELECT 1 FROM public.vehicle_aliases a
  WHERE a.source_system_normalized='hermes_overnight_synthetic'
    OR a.vehicle_id=ANY(v_target_vehicle_ids)
    OR a.normalized_alias_value LIKE 'HERMESTEST%'
    OR to_jsonb(a)::text ILIKE '%HERMES-TEST-RUN-20260824%'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_specs) spec
      WHERE a.normalized_alias_value IN(public.normalize_vehicle_stock_number(spec->>'stock'),
        public.normalize_vehicle_source_identifier(spec->>'stock'),
        public.normalize_vehicle_source_identifier('HERMES-TEST-PERM-'||lpad(spec->>'scenario_no',3,'0'))))
 ) OR EXISTS(
  SELECT 1 FROM public.pdc_vehicle_tombstones t
  WHERE t.vehicle_id=ANY(v_target_vehicle_ids)
    OR t.normalized_stock LIKE 'HERMESTEST%' OR t.stock_number ILIKE 'HERMES-TEST-%'
    OR to_jsonb(t)::text ILIKE '%HERMES-TEST-RUN-20260824%'
 ) OR EXISTS(
  SELECT 1 FROM public.navision_backend_records n
  WHERE n.canonical_vehicle_id=ANY(v_target_vehicle_ids)
    OR to_jsonb(n)::text ILIKE '%HERMES-TEST-%'
    OR to_jsonb(n)::text ILIKE '%HERMES-TEST-RUN-20260824%'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_specs) spec WHERE to_jsonb(n)::text ILIKE '%'||(spec->>'stock')||'%')
 ) OR EXISTS(
  SELECT 1 FROM public.navision_board_activations a
  WHERE a.activated_stock_number ILIKE 'HERMES-TEST-%'
    OR public.normalize_vehicle_stock_number(a.activated_stock_number) LIKE 'HERMESTEST%'
    OR a.canonical_vehicle_id=ANY(v_target_vehicle_ids)
 ) OR EXISTS(
  SELECT 1 FROM public.vehicle_work_items wi
  JOIN jsonb_array_elements(p_specs) spec ON true
  JOIN LATERAL jsonb_array_elements_text(coalesce(spec->'work_keys','[]'::jsonb)) wk ON true
  WHERE wi.id=extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,
    p_run_id||':work:'||(spec->>'stock')||':'||wk.value)
 ) THEN RAISE EXCEPTION 'PDC_363_SOURCE_NAMESPACE_IDENTITY_ARCHIVE_OR_TOMBSTONE_COLLISION' USING errcode='23505'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363) THEN
  RAISE EXCEPTION 'PDC_363_existing_registry_mismatch' USING errcode='55000';
 END IF;

 -- Authoritative statement 1/2: all 20 vehicles are inserted in one set. The
 -- registry consumes the same materialized input and INSERT ... RETURNING rows,
 -- preserving exact generated versions/scenarios without row-by-row DML.
 WITH input AS MATERIALIZED (
  SELECT spec,(spec->>'scenario_no')::integer scenario_no,btrim(spec->>'scenario_name') scenario_name,
    btrim(spec->>'stock') stock_number,btrim(spec->>'customer') customer_name,
    btrim(spec->>'job_card') job_card_number,btrim(spec->>'description') vehicle_description,
    coalesce(nullif(btrim(spec->>'initial_location'),''),'Other') current_location,
    nullif(spec->>'eta','')::date eta_to_kewdale,
    extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,
      p_run_id||':vehicle:'||btrim(spec->>'stock')) vehicle_id,
    extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,
      p_run_id||':registry:'||(spec->>'scenario_no')) registry_id
  FROM jsonb_array_elements(p_specs) spec
 ), inserted_vehicles AS (
  INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,model,
    lifecycle_state,visible_on_board,current_location,eta_to_kewdale,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by)
  SELECT i.vehicle_id,'HERMES-TEST-PERM-'||lpad(i.scenario_no::text,3,'0'),i.stock_number,i.job_card_number,
    i.customer_name,i.vehicle_description,i.vehicle_description,'active',true,i.current_location,i.eta_to_kewdale,
    'hermes_overnight_synthetic',p_run_id,i.stock_number,
    jsonb_build_object('contract','pdc-overnight-synthetic-fleet-363/render_only','run_id',p_run_id,
      'scenario_no',i.scenario_no,'scenario_name',i.scenario_name,'request_sha256',v_request_sha256,
      'completion_evidence',false),v_actor,v_actor
  FROM input i ORDER BY i.scenario_no
  RETURNING id,version,stock_number
 ), inserted_registry AS (
  INSERT INTO public.pdc_overnight_synthetic_fleet_registry_363(registry_id,run_id,scenario_no,scenario_name,vehicle_id,
    stock_number,customer_name,job_card_number,vehicle_description,spec,request_sha256,actor_id,actor_email)
  SELECT i.registry_id,p_run_id,i.scenario_no,i.scenario_name,v.id,i.stock_number,i.customer_name,
    i.job_card_number,i.vehicle_description,i.spec,v_request_sha256,v_actor,v_email
  FROM input i JOIN inserted_vehicles v ON v.id=i.vehicle_id ORDER BY i.scenario_no
  RETURNING registry_id,scenario_no,scenario_name,vehicle_id,stock_number
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('scenario_no',r.scenario_no,'scenario_name',r.scenario_name,
   'registry_id',r.registry_id,'vehicle_id',r.vehicle_id,'vehicle_version',v.version,'stock_number',r.stock_number)
   ORDER BY r.scenario_no),'[]'::jsonb)
 INTO v_ids FROM inserted_registry r JOIN inserted_vehicles v ON v.id=r.vehicle_id;

 -- Authoritative statement 2/2: every requested canonical work key in one set.
 INSERT INTO public.vehicle_work_items(id,vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
 SELECT extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,
     p_run_id||':work:'||btrim(spec->>'stock')||':'||wk.value),
   extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,
     p_run_id||':vehicle:'||btrim(spec->>'stock')),
   wk.value,true,false,NULL,NULL,
   coalesce(nullif(btrim(spec->>'notes'),''),'HERMES-TEST render-only incomplete synthetic requirement'),clock_timestamp()
 FROM jsonb_array_elements(p_specs) spec
 CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(spec->'work_keys','[]'::jsonb)) wk
 ORDER BY (spec->>'scenario_no')::integer,wk.value;

 SELECT revision INTO v_shared_revision_after
 FROM public.pdc_email_vehicle_revision WHERE singleton;
 IF v_shared_revision_after-v_shared_revision_before<>2 THEN
  RAISE EXCEPTION 'PDC_363_UNEXPECTED_SHARED_REVISION_DELTA before=% after=% expected=2',
    v_shared_revision_before,v_shared_revision_after USING errcode='55000';
 END IF;

 v_after_vehicle_count:=(SELECT count(*) FROM public.vehicles);
 v_after_registry_count:=(SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_registry_363);
 v_after_notification_count:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT count(*),encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
   INTO v_protected_vehicle_count_after,v_protected_digest_after FROM public.vehicles v
   WHERE NOT (v.id=ANY(v_target_vehicle_ids));
 IF v_after_vehicle_count-v_before_vehicle_count<>20 OR v_after_registry_count-v_before_registry_count<>20
   OR v_after_notification_count<>v_before_notification_count
   OR v_protected_vehicle_count_after<>v_protected_vehicle_count_before
   OR v_protected_digest_after IS DISTINCT FROM v_protected_digest_before THEN
  RAISE EXCEPTION 'PDC_363_EXACT_DELTA_POSTCONDITION' USING errcode='55000';
 END IF;
 IF (SELECT count(*) FROM public.workshop_bookings)<>v_before_booking_count
   OR (SELECT count(*) FROM public.vehicle_work_items)<>v_before_work_count+v_expected_work_count
   OR (SELECT count(*) FROM public.vehicle_parts_updates)<>v_before_parts_count
   OR (SELECT count(*) FROM public.pdc_sublet_bookings)<>v_before_sublet_count
   OR (SELECT count(*) FROM public.vehicle_sublet_providers)<>v_before_provider_count
   OR (SELECT count(*) FROM public.pdc_authenticated_email_import_receipts)<>v_before_email_count
   OR EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=b.vehicle_id WHERE r.run_id=p_run_id)
   OR EXISTS(SELECT 1 FROM public.vehicle_parts_updates p JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=p.vehicle_id WHERE r.run_id=p_run_id)
   OR EXISTS(SELECT 1 FROM public.pdc_sublet_bookings s JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=s.vehicle_id WHERE r.run_id=p_run_id)
   OR EXISTS(SELECT 1 FROM public.vehicle_sublet_providers s JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=s.vehicle_id WHERE r.run_id=p_run_id)
   OR EXISTS(SELECT 1 FROM public.pdc_authenticated_email_import_receipts e JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=e.vehicle_id WHERE r.run_id=p_run_id)
   OR EXISTS(SELECT 1 FROM public.vehicles v JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=v.id WHERE r.run_id=p_run_id
      AND (v.lifecycle_state IS DISTINCT FROM 'active' OR v.visible_on_board IS DISTINCT FROM true OR v.deleted_at IS NOT NULL OR v.board_purged_at IS NOT NULL
       OR v.rft_collected_at IS NOT NULL OR upper(coalesce(v.current_location,''))='COMPLETED'
       OR r.registry_id IS DISTINCT FROM extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':registry:'||r.scenario_no::text)
       OR v.id IS DISTINCT FROM extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':vehicle:'||r.stock_number)
       OR v.permanent_vehicle_id IS DISTINCT FROM 'HERMES-TEST-PERM-'||lpad(r.scenario_no::text,3,'0')
       OR v.stock_number IS DISTINCT FROM r.stock_number OR v.customer_name IS DISTINCT FROM r.customer_name OR v.job_card_number IS DISTINCT FROM r.job_card_number
       OR v.vehicle_description IS DISTINCT FROM r.vehicle_description OR v.source_system IS DISTINCT FROM 'hermes_overnight_synthetic'
       OR v.source_batch_id IS DISTINCT FROM p_run_id OR v.source_record_id IS DISTINCT FROM r.stock_number
       OR v.current_location IS DISTINCT FROM coalesce(nullif(r.spec->>'initial_location',''),'Other')
       OR v.eta_to_kewdale IS DISTINCT FROM nullif(r.spec->>'eta','')::date
       OR v.source_payload->>'request_sha256' IS DISTINCT FROM r.request_sha256
       OR (v.source_payload->>'completion_evidence')::boolean IS DISTINCT FROM false
       OR coalesce(to_jsonb(v)->>'qc_completed_at','')<>'' OR coalesce(to_jsonb(v)->>'rft_at','')<>''))
   OR EXISTS(SELECT 1 FROM public.vehicle_work_items wi JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=wi.vehicle_id
      WHERE r.run_id=p_run_id AND (wi.required IS DISTINCT FROM true OR wi.completed IS DISTINCT FROM false OR wi.completed_by IS NOT NULL OR wi.completed_at IS NOT NULL
       OR wi.id IS DISTINCT FROM extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':work:'||r.stock_number||':'||wi.work_key)
       OR wi.notes IS NULL OR wi.notes !~ '^HERMES-TEST' OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_specs) spec
          WHERE (spec->>'scenario_no')::integer=r.scenario_no AND (spec->'work_keys')?wi.work_key))) THEN
  RAISE EXCEPTION 'PDC_363_NO_BOOKING_COMPLETION_QC_RFT_DELETED_EVIDENCE_POSTCONDITION' USING errcode='55000';
 END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
   WHERE r.run_id=p_run_id AND (SELECT count(*) FROM public.vehicle_work_items wi WHERE wi.vehicle_id=r.vehicle_id)
     <>jsonb_array_length(coalesce(r.spec->'work_keys','[]'::jsonb))) THEN
  RAISE EXCEPTION 'PDC_363_CANONICAL_WORK_SET_POSTCONDITION' USING errcode='55000';
 END IF;

 v_receipt_id:=extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,
   p_run_id||':receipt:'||v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',true,'code','synthetic_fleet_bootstrapped','run_id',p_run_id,
   'receipt_id',v_receipt_id,'request_hash',v_request_sha256,'specs_sha256',v_specs_sha256,'replay',false,
   'vehicle_delta',20,'registry_delta',20,'notification_delta',0,
   'shared_revision',jsonb_build_object('table','public.pdc_email_vehicle_revision',
      'before',v_shared_revision_before,'after',v_shared_revision_after,
      'delta',v_shared_revision_after-v_shared_revision_before,'expected_delta',2,
      'authoritative_statements',jsonb_build_array('vehicles_set_insert','vehicle_work_items_set_insert')),
   'protected_vehicle_count_before',v_protected_vehicle_count_before,'protected_vehicle_count_after',v_protected_vehicle_count_after,
   'protected_vehicle_digest_before',v_protected_digest_before,'protected_vehicle_digest_after',v_protected_digest_after,
   'before_counts',jsonb_build_object('vehicles',v_before_vehicle_count,'registry',v_before_registry_count,
      'notifications',v_before_notification_count,'receipts',v_before_receipt_count,'events',v_before_event_count,
      'bookings',v_before_booking_count,'work_items',v_before_work_count,'parts_receipts',v_before_parts_count,
      'sublet_bookings',v_before_sublet_count,'providers',v_before_provider_count,'email_receipts',v_before_email_count),
   'ids_versions_scenarios',v_ids);
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_363_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
 INSERT INTO public.pdc_overnight_synthetic_fleet_receipts_363(receipt_id,run_id,actor_id,actor_email,idempotency_key,request_sha256,response)
 VALUES(v_receipt_id,p_run_id,v_actor,v_email,p_idempotency_key,v_request_sha256,v_response);
 INSERT INTO public.pdc_overnight_synthetic_fleet_events_363(event_id,run_id,registry_id,vehicle_id,actor_id,idempotency_key,event_kind,event_payload)
 SELECT extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':event:'||r.scenario_no::text),
   p_run_id,r.registry_id,r.vehicle_id,v_actor,p_idempotency_key,'bootstrapped',
   jsonb_build_object('request_sha256',v_request_sha256,'scenario_no',r.scenario_no,'scenario_name',r.scenario_name,
     'render_only',true,'booking_created',false,'completion_evidence_created',false)
 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id ORDER BY r.scenario_no;
 IF (SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_receipts_363)<>v_before_receipt_count+1
   OR (SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_events_363)<>v_before_event_count+20
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_363_RECEIPT_EVENT_NOTIFICATION_POSTCONDITION' USING errcode='55000';
 END IF;
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_363_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
 SELECT revision INTO v_shared_revision_recheck
 FROM public.pdc_email_vehicle_revision WHERE singleton;
 IF v_shared_revision_recheck IS DISTINCT FROM v_shared_revision_after
   OR v_shared_revision_recheck-v_shared_revision_before<>2 THEN
  RAISE EXCEPTION 'PDC_363_SHARED_REVISION_DRIFT_BEFORE_RETURN' USING errcode='55000';
 END IF;
 RETURN v_response;
END $bootstrap$;
REVOKE ALL ON FUNCTION public.bootstrap_pdc_hermes_test_fleet(text,uuid,jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.bootstrap_pdc_hermes_test_fleet(text,uuid,jsonb) TO authenticated;

DO $post$
BEGIN
 IF has_function_privilege('public','public.bootstrap_pdc_hermes_test_fleet(text,uuid,jsonb)','EXECUTE')
   OR has_function_privilege('anon','public.bootstrap_pdc_hermes_test_fleet(text,uuid,jsonb)','EXECUTE')
   OR has_function_privilege('service_role','public.bootstrap_pdc_hermes_test_fleet(text,uuid,jsonb)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.bootstrap_pdc_hermes_test_fleet(text,uuid,jsonb)','EXECUTE')
   OR has_function_privilege('public','public.read_pdc_hermes_test_fleet(text)','EXECUTE')
   OR has_function_privilege('anon','public.read_pdc_hermes_test_fleet(text)','EXECUTE')
   OR has_function_privilege('service_role','public.read_pdc_hermes_test_fleet(text)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.read_pdc_hermes_test_fleet(text)','EXECUTE')
   OR has_table_privilege('authenticated','public.pdc_overnight_synthetic_fleet_registry_363','SELECT,INSERT,UPDATE,DELETE')
   OR has_table_privilege('authenticated','public.pdc_overnight_synthetic_fleet_receipts_363','SELECT,INSERT,UPDATE,DELETE')
   OR has_table_privilege('authenticated','public.pdc_overnight_synthetic_fleet_events_363','SELECT,INSERT,UPDATE,DELETE') THEN
  RAISE EXCEPTION 'PDC_363_ACL_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825000000','363_overnight_synthetic_fleet_bootstrap',array[
 'Exact staging sentinel and exact migration 362 head; Monitor, mailboxes, activation writers and notifications contained',
 'Append-only RLS registry, actor-idempotent receipt and event history for HERMES-TEST-RUN-20260824',
 'Authenticated approved Administrator-only exact-20 bootstrap with deterministic UUIDv5 identities and collision closure',
 'Active visible synthetic vehicles plus canonical required=true completed=false work only; no operational evidence side effects',
 'Authoritative registered-fleet readback, exact deltas, immutable responses and least-authority ACL proof'
]);
NOTIFY pgrst,'reload schema';

-- The migration-time SHARE locks are still held here, so this is both an
-- immediate pre-commit revalidation and a guarantee that row DML could not race it.
DO $final_containment$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_363_FINAL_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
END $final_containment$;
COMMIT;
