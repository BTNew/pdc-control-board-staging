-- STAGING ONLY 363: guarded append-only bootstrap for one synthetic fleet run.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-363-overnight-synthetic-fleet',0));

DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260824230000' AND name='362_align_anderson_plugs_and_job_counts')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260824230000' AND version~'^[0-9]{14}$')
   OR EXISTS(SELECT 1 FROM public.pdc_email_monitor_pilot WHERE enabled OR outbound_email_enabled OR automatic_rule_application OR automatic_authenticated_jobcards)
   OR EXISTS(SELECT 1 FROM public.pdc_email_monitor_status WHERE running_status<>'stopped' OR gateway_instance_id IS NOT NULL)
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
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'PDC_363_WRONG_ENVIRONMENT' USING errcode='55000';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'registry_id',r.registry_id,'run_id',r.run_id,'scenario_no',r.scenario_no,'scenario_name',r.scenario_name,
   'request_sha256',r.request_sha256,'created_at',r.created_at,
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
 v_work_key text;
 v_vehicle_id uuid;
 v_registry_id uuid;
 v_vehicle public.vehicles%rowtype;
 v_ids jsonb:='[]'::jsonb;
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

 LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
 LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
 LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
 LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
 LOCK TABLE public.vehicle_notifications IN SHARE MODE;
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR EXISTS(SELECT 1 FROM public.pdc_email_monitor_pilot WHERE enabled OR outbound_email_enabled OR automatic_rule_application OR automatic_authenticated_jobcards)
   OR EXISTS(SELECT 1 FROM public.pdc_email_monitor_status WHERE running_status<>'stopped' OR gateway_instance_id IS NOT NULL)
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
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
 END IF;

 LOCK TABLE public.vehicles IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicle_aliases IN SHARE MODE;
 LOCK TABLE public.pdc_vehicle_tombstones IN SHARE MODE;
 LOCK TABLE public.navision_backend_records IN SHARE MODE;
 LOCK TABLE public.navision_board_activations IN SHARE MODE;

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
 SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
   INTO v_protected_digest_before FROM public.vehicles v;
 v_expected_work_count:=(SELECT coalesce(sum(jsonb_array_length(coalesce(spec->'work_keys','[]'::jsonb))),0)
   FROM jsonb_array_elements(p_specs) spec);
 IF v_before_notification_count<>0 THEN RAISE EXCEPTION 'PDC_363_NOTIFICATIONS_NOT_EMPTY' USING errcode='55000'; END IF;

 IF EXISTS(
  SELECT 1 FROM jsonb_array_elements(p_specs) spec
  CROSS JOIN LATERAL (SELECT spec->>'stock' stock_number) i
  WHERE EXISTS(SELECT 1 FROM public.vehicles v WHERE v.stock_number_normalized=public.normalize_vehicle_stock_number(i.stock_number)
     OR v.stock_number=i.stock_number OR v.source_record_id_normalized=public.normalize_vehicle_source_identifier(i.stock_number))
    OR EXISTS(SELECT 1 FROM public.vehicle_aliases a WHERE a.normalized_alias_value=public.normalize_vehicle_stock_number(i.stock_number))
    OR EXISTS(SELECT 1 FROM public.pdc_vehicle_tombstones t WHERE to_jsonb(t)::text ILIKE '%'||i.stock_number||'%')
    OR EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE to_jsonb(n)::text ILIKE '%'||i.stock_number||'%')
    OR EXISTS(SELECT 1 FROM public.navision_board_activations a WHERE public.normalize_vehicle_stock_number(a.activated_stock_number)=public.normalize_vehicle_stock_number(i.stock_number))
 ) THEN RAISE EXCEPTION 'PDC_363_STOCK_NORMALIZED_SOURCE_ARCHIVE_OR_TOMBSTONE_COLLISION' USING errcode='23505'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id)
   OR EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r JOIN jsonb_array_elements(p_specs) s
      ON r.scenario_no=(s->>'scenario_no')::integer
      WHERE r.run_id<>p_run_id OR r.stock_number<>s->>'stock' OR r.scenario_name<>s->>'scenario_name') THEN
  RAISE EXCEPTION 'PDC_363_existing_registry_mismatch' USING errcode='55000';
 END IF;

 FOR v_spec IN SELECT value FROM jsonb_array_elements(p_specs) ORDER BY (value->>'scenario_no')::integer LOOP
  v_no:=(v_spec->>'scenario_no')::integer;
  v_name:=btrim(v_spec->>'scenario_name');v_stock:=btrim(v_spec->>'stock');v_customer:=btrim(v_spec->>'customer');
  v_job:=btrim(v_spec->>'job_card');v_description:=btrim(v_spec->>'description');
  v_location:=coalesce(nullif(btrim(v_spec->>'initial_location'),''),'Other');v_eta:=nullif(v_spec->>'eta','')::date;
  v_notes:=coalesce(nullif(btrim(v_spec->>'notes'),''),'HERMES-TEST render-only incomplete synthetic requirement');
  v_work_keys:=coalesce(v_spec->'work_keys','[]'::jsonb);
  v_vehicle_id:=extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':vehicle:'||v_stock);
  v_registry_id:=extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,p_run_id||':registry:'||v_no::text);
  INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,model,
    lifecycle_state,visible_on_board,current_location,eta_to_kewdale,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by)
  VALUES(v_vehicle_id,'HERMES-TEST-PERM-'||lpad(v_no::text,3,'0'),v_stock,v_job,v_customer,v_description,v_description,
    'active',true,v_location,v_eta,'hermes_overnight_synthetic',p_run_id,v_stock,
    jsonb_build_object('contract','pdc-overnight-synthetic-fleet-363/render_only','run_id',p_run_id,'scenario_no',v_no,
      'scenario_name',v_name,'request_sha256',v_request_sha256,'completion_evidence',false),v_actor,v_actor)
  RETURNING * INTO v_vehicle;
  INSERT INTO public.pdc_overnight_synthetic_fleet_registry_363(registry_id,run_id,scenario_no,scenario_name,vehicle_id,
    stock_number,customer_name,job_card_number,vehicle_description,request_sha256,actor_id,actor_email)
  VALUES(v_registry_id,p_run_id,v_no,v_name,v_vehicle.id,v_stock,v_customer,v_job,v_description,v_request_sha256,v_actor,v_email);
  FOR v_work_key IN SELECT value FROM jsonb_array_elements_text(v_work_keys) ORDER BY value LOOP
   INSERT INTO public.vehicle_work_items(id,vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
   VALUES(extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,
     p_run_id||':work:'||v_stock||':'||v_work_key),v_vehicle.id,v_work_key,true,false,NULL,NULL,v_notes,clock_timestamp());
  END LOOP;
  v_ids:=v_ids||jsonb_build_array(jsonb_build_object('scenario_no',v_no,'scenario_name',v_name,'registry_id',v_registry_id,
    'vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version,'stock_number',v_stock));
 END LOOP;

 v_after_vehicle_count:=(SELECT count(*) FROM public.vehicles);
 v_after_registry_count:=(SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_registry_363);
 v_after_notification_count:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
   INTO v_protected_digest_after FROM public.vehicles v
   WHERE NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id AND r.run_id=p_run_id);
 IF v_after_vehicle_count-v_before_vehicle_count<>20 OR v_after_registry_count-v_before_registry_count<>20
   OR v_after_notification_count<>v_before_notification_count
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
      AND (v.lifecycle_state<>'active' OR NOT v.visible_on_board OR v.deleted_at IS NOT NULL OR v.board_purged_at IS NOT NULL
       OR v.rft_collected_at IS NOT NULL OR upper(coalesce(v.current_location,''))='COMPLETED'
       OR v.stock_number<>r.stock_number OR v.customer_name<>r.customer_name OR v.job_card_number<>r.job_card_number
       OR v.vehicle_description<>r.vehicle_description OR v.source_system<>'hermes_overnight_synthetic'
       OR v.source_batch_id<>p_run_id OR v.source_record_id<>r.stock_number
       OR coalesce(to_jsonb(v)->>'qc_completed_at','')<>'' OR coalesce(to_jsonb(v)->>'rft_at','')<>''))
   OR EXISTS(SELECT 1 FROM public.vehicle_work_items wi JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.vehicle_id=wi.vehicle_id
      WHERE r.run_id=p_run_id AND (NOT wi.required OR wi.completed OR wi.completed_by IS NOT NULL OR wi.completed_at IS NOT NULL
       OR wi.notes !~ '^HERMES-TEST' OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_specs) spec
          WHERE (spec->>'scenario_no')::integer=r.scenario_no AND (spec->'work_keys')?wi.work_key))) THEN
  RAISE EXCEPTION 'PDC_363_NO_BOOKING_COMPLETION_QC_RFT_DELETED_EVIDENCE_POSTCONDITION' USING errcode='55000';
 END IF;

 v_receipt_id:=extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,
   p_run_id||':receipt:'||v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',true,'code','synthetic_fleet_bootstrapped','run_id',p_run_id,
   'receipt_id',v_receipt_id,'request_hash',v_request_sha256,'specs_sha256',v_specs_sha256,'replay',false,
   'vehicle_delta',20,'registry_delta',20,'notification_delta',0,
   'protected_vehicle_digest_before',v_protected_digest_before,'protected_vehicle_digest_after',v_protected_digest_after,
   'before_counts',jsonb_build_object('vehicles',v_before_vehicle_count,'registry',v_before_registry_count,
      'notifications',v_before_notification_count,'receipts',v_before_receipt_count,'events',v_before_event_count,
      'bookings',v_before_booking_count,'work_items',v_before_work_count,'parts_receipts',v_before_parts_count,
      'sublet_bookings',v_before_sublet_count,'providers',v_before_provider_count,'email_receipts',v_before_email_count),
   'ids_versions_scenarios',v_ids);
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
COMMIT;
