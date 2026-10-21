-- r421 (F36, Craig 21 Oct, permissions review item 2): importer = viewer + Navision import. Staging cdsmnqxtyyoeoznmbidd only.
-- Before: is_pdc_role('operator') accepted importers, so an importer passed every controller-level server action
-- (require_pdc_role('operator'): locations, PMB/PIT transfers, parts, vehicle detail, work states, QC ready/sign-off, yard hold,
-- line adjustments, bookings) and seven functions listed importer next to operator.
-- After: importers pass a controller gate only inside the email-monitor canonical action contracts that already existed
-- (pdc_monitor_canonical_action = 'pdc-email-ai-693' set by the r693 executor, or the v2 capability), via the new private
-- helper pdc_importer_monitor_action_421(). The Navision import itself (preview/apply/upload profile, snapshots, export,
-- reconciliation, ETA history) checks importer/administrator directly and is unchanged.
-- Changed (same owner, grants, SECURITY DEFINER, volatility and settings, guarded): is_pdc_role, pdc_sublet_actor_allowed,
-- save_pdc_online_state(_batch), activate_navision_backend_record ("show on Vehicle Locations"), append_vehicle_timeline_event,
-- get_vehicle_intelligence_snapshot (sensitive fields). Not touched: the clock tick, the monitor-identity functions, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r421: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r421: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r421: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r421: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.is_pdc_role(pdc_role)','6b951e82d7a262d846df7ead80fc9ef2','8609863ae82e85e9edb7847bf2957606'),
  ('public.pdc_sublet_actor_allowed()','dec90f7ce54cab652b37367cab69f969','1c75a53411ee6262c0143ada12c6d2b2'),
  ('public.save_pdc_online_state(text,jsonb,bigint,text)','959f45f25174c37935a61fe147cdf4ea','ca8e0514e90d5c9c3e27c027ef3208ce'),
  ('public.save_pdc_online_state_batch(jsonb,text)','bcffc5de50e396ba9e14ca3f4d829b2c','ca8e0514e90d5c9c3e27c027ef3208ce'),
  ('public.activate_navision_backend_record(text,uuid,bigint,text)','06e82ace7433848a95dec41e95205231','27cb510615d31f22efd39d88c2f1337f'),
  ('public.append_vehicle_timeline_event(uuid,text,timestamp with time zone,vehicle_timeline_source_kind,vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)','0d529c8a8cdfd5c5b48c6bf1f0a9f93a','3cb754a2ffb942b8adcaba96c13786a3'),
  ('public.get_vehicle_intelligence_snapshot(uuid,text,integer)','3f7b333f93c2ecc89359a38e7535d7de','282eda4fef6a92c22f0e600515f093e8')) e(sig,m,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m AND md5(coalesce(p.proacl::text,'')||p.prosecdef::text||p.provolatile::text||p.proowner::regrole::text||coalesce(array_to_string(p.proconfig,'|'),''))=e.a)<>7 THEN RAISE EXCEPTION 'r421: functions are not the expected versions'; END IF;
 IF to_regprocedure('public.pdc_importer_monitor_action_421()') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r421')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='importer_viewer_plus_import' OR added_in='r421') THEN RAISE EXCEPTION 'r421: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=223) THEN RAISE EXCEPTION 'r421: sort_order 223 taken'; END IF;
 IF to_regprocedure('public.pdc_email_ai_v2_canonical_action_capability_20260902()') IS NULL THEN RAISE EXCEPTION 'r421: monitor capability function missing'; END IF;
END $g$;

CREATE FUNCTION public.pdc_importer_monitor_action_421()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 -- r421 (F36): an importer only gets controller-level server actions inside the existing email-monitor canonical
 -- action contracts (r693 transaction setting or the v2 capability). Everything else an importer does is viewer + import.
 SELECT coalesce(current_setting('pdc_monitor_canonical_action', true), '') = 'pdc-email-ai-693'
     OR coalesce(public.pdc_email_ai_v2_canonical_action_capability_20260902(), false)
$function$;
REVOKE ALL ON FUNCTION public.pdc_importer_monitor_action_421() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_pdc_role(required_role pdc_role)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select case
 when public.current_pdc_user_role()::text='fitter' then
  CASE required_role::text WHEN 'viewer' THEN pdc_fitter_private.authorized_request(false)
   WHEN 'operator' THEN pdc_fitter_private.authorized_request(true) ELSE false END
 when public.current_pdc_user_role()='administrator' then true
 when required_role='viewer' and public.current_pdc_user_role() in ('viewer','operator','importer','administrator') then true
 when required_role='operator' and public.current_pdc_user_role() in ('operator','administrator') then true
 when required_role='operator' and public.current_pdc_user_role()='importer' and public.pdc_importer_monitor_action_421() then true
 when required_role='importer' and public.current_pdc_user_role() in ('importer','administrator') then true
 when required_role='administrator' and public.current_pdc_user_role()='administrator' then true
 else false end;
$function$;

CREATE OR REPLACE FUNCTION public.pdc_sublet_actor_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select auth.uid() is not null and (coalesce(public.current_pdc_user_role()::text in ('operator','administrator'),false) or (public.current_pdc_user_role()::text='importer' and public.pdc_importer_monitor_action_421()))
$function$;

CREATE OR REPLACE FUNCTION public.save_pdc_online_state(p_state_key text, p_payload jsonb, p_expected_version bigint, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_key text := btrim(coalesce(p_state_key, ''));
  v_idempotency text := lower(btrim(coalesce(p_idempotency_key, '')));
  v_actor uuid := auth.uid();
  v_role text := public.current_pdc_user_role()::text;
  v_request_hash text;
  v_existing public.pdc_online_state_receipts%rowtype;
  v_row public.pdc_online_operational_state%rowtype;
  v_old_payload jsonb := '[]'::jsonb;
  v_payload jsonb := p_payload;
  v_item jsonb;
  v_normalized jsonb := '[]'::jsonb;
  v_manual_id text;
  v_permanent_id text;
  v_vehicle public.vehicles%rowtype;
  v_old_item jsonb;
  v_old_manual_id text;
  v_new_ids text[] := '{}'::text[];
  v_revision bigint;
  v_response jsonb;
begin
  if auth.role() is distinct from 'authenticated'
    or auth.uid() is null
    or not exists (
      select 1 from public.pdc_user_roles r
      where r.auth_user_id = auth.uid()
        and lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
        and r.active is true
        and r.account_status::text = 'approved'
        and (r.role::text in ('operator', 'administrator') or (r.role::text = 'importer' and public.pdc_importer_monitor_action_421()))
    ) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if not public.pdc_online_state_key_allowed(v_key) then
    return jsonb_build_object('ok', false, 'error', 'invalid_state_key');
  end if;
  if v_payload is null or octet_length(v_payload::text) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;
  if p_expected_version is null or p_expected_version < 0 then
    return jsonb_build_object('ok', false, 'error', 'expected_version_required');
  end if;
  if v_idempotency !~ '^pdc-online-[a-f0-9]{32}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_idempotency_key');
  end if;

  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'contract_version', 1,
    'environment', 'staging',
    'project_ref', 'cdsmnqxtyyoeoznmbidd',
    'state_key', v_key,
    'payload', v_payload,
    'expected_version', p_expected_version,
    'actor_id', v_actor
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended('pdc-online-state:' || v_key, 0));
  select * into v_existing from public.pdc_online_state_receipts
  where idempotency_key = v_idempotency;
  if found then
    if v_existing.request_hash <> v_request_hash then
      return jsonb_build_object('ok', false, 'error', 'idempotency_conflict');
    end if;
    return v_existing.response;
  end if;

  select * into v_row from public.pdc_online_operational_state
  where state_key = v_key for update;
  if found then
    if v_row.version <> p_expected_version then
      return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current_version', v_row.version);
    end if;
    v_old_payload := v_row.payload;
  elsif p_expected_version <> 0 then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current_version', 0);
  end if;

  -- Manual browser-created rows become canonical shared vehicles in the same
  -- transaction. Their server UUID/version is written back into the stored
  -- document so Workshop/QC/RFT actions resolve the exact online vehicle.
  if v_key = 'vehicleTrackingCoreNavisionOnlyVehicles:v1' then
    if jsonb_typeof(v_payload) is distinct from 'array' or jsonb_array_length(v_payload) > 10000 then
      return jsonb_build_object('ok', false, 'error', 'invalid_vehicle_array');
    end if;
    for v_item in select value from jsonb_array_elements(v_payload)
    loop
      if jsonb_typeof(v_item) is distinct from 'object' then
        raise exception using errcode = 'PDC01', message = 'invalid_vehicle_row';
      end if;
      v_manual_id := btrim(coalesce(v_item->>'id', ''));
      if v_manual_id !~ '^(manual|qa)-[A-Za-z0-9_.:-]{1,120}$' then
        raise exception using errcode = 'PDC01', message = 'invalid_manual_vehicle_id';
      end if;
      v_permanent_id := 'ONLINE:' || v_manual_id;
      v_new_ids := array_append(v_new_ids, v_manual_id);
      select * into v_vehicle
      from public.vehicles
      where permanent_vehicle_id = v_permanent_id
      for update;
      if found then
        update public.vehicles set
          stock_number = nullif(btrim(v_item->>'stock'), ''),
          vin = nullif(btrim(coalesce(v_item->>'vin', v_item->>'VIN')), ''),
          toyota_order_number = nullif(btrim(coalesce(v_item->>'orderNumber', v_item->>'toyotaOrderNumber')), ''),
          job_card_number = nullif(btrim(coalesce(v_item->>'pdcJobcard', v_item->>'jobCardNumber')), ''),
          customer_name = nullif(btrim(coalesce(v_item->>'client', v_item->>'customerName')), ''),
          make = nullif(btrim(v_item->>'make'), ''),
          model = nullif(btrim(coalesce(v_item->>'vehicle', v_item->>'model')), ''),
          lifecycle_state = 'active',
          visible_on_board = true,
          deleted_at = null,
          deleted_reason = null,
          source_payload = v_item || jsonb_build_object('online_state_key', v_key),
          version = version + 1,
          updated_by = v_actor
        where id = v_vehicle.id
        returning * into v_vehicle;
      else
        insert into public.vehicles (
          permanent_vehicle_id, stock_number, vin, toyota_order_number,
          job_card_number, customer_name, make, model, lifecycle_state,
          visible_on_board, current_location, pmb_stage, source_payload,
          created_by, updated_by
        ) values (
          v_permanent_id,
          nullif(btrim(v_item->>'stock'), ''),
          nullif(btrim(coalesce(v_item->>'vin', v_item->>'VIN')), ''),
          nullif(btrim(coalesce(v_item->>'orderNumber', v_item->>'toyotaOrderNumber')), ''),
          nullif(btrim(coalesce(v_item->>'pdcJobcard', v_item->>'jobCardNumber')), ''),
          nullif(btrim(coalesce(v_item->>'client', v_item->>'customerName')), ''),
          nullif(btrim(v_item->>'make'), ''),
          nullif(btrim(coalesce(v_item->>'vehicle', v_item->>'model')), ''),
          'active', true,
          case upper(btrim(coalesce(v_item->>'pdcLocation', v_item->>'manualLocation', '')))
            when 'YH' then 'YH' when 'PMB' then 'PMB' when 'RFT' then 'RFT' else null end,
          nullif(upper(btrim(coalesce(v_item->>'pmbStage', ''))), ''),
          v_item || jsonb_build_object('online_state_key', v_key),
          v_actor, v_actor
        ) returning * into v_vehicle;
      end if;
      v_normalized := v_normalized || jsonb_build_array(v_item || jsonb_build_object(
        'sharedVehicleId', v_vehicle.id,
        'shared_vehicle_id', v_vehicle.id,
        'permanentVehicleId', v_vehicle.permanent_vehicle_id,
        'sharedVehicleVersion', v_vehicle.version,
        'sourceSystem', 'pdc_online_manual',
        'sourceRecordId', v_manual_id
      ));
    end loop;
    for v_old_item in select value from jsonb_array_elements(
      case when jsonb_typeof(v_old_payload) = 'array' then v_old_payload else '[]'::jsonb end
    ) loop
      v_old_manual_id := btrim(coalesce(v_old_item->>'id', ''));
      if v_old_manual_id ~ '^(manual|qa)-[A-Za-z0-9_.:-]{1,120}$'
         and not (v_old_manual_id = any(v_new_ids)) then
        update public.vehicles set lifecycle_state = 'deleted', visible_on_board = false,
          deleted_at = now(), deleted_reason = 'Removed from online Vehicle Locations',
          version = version + 1, updated_by = v_actor
        where permanent_vehicle_id = 'ONLINE:' || v_old_manual_id
          and lifecycle_state <> 'deleted';
      end if;
    end loop;
    v_payload := v_normalized;
  end if;

  insert into public.pdc_online_operational_state(
    state_key, payload, version, updated_by, updated_by_email
  ) values (v_key, v_payload, 1, v_actor, public.current_actor_email())
  on conflict (state_key) do update set
    payload = excluded.payload,
    version = public.pdc_online_operational_state.version + 1,
    updated_by = v_actor,
    updated_by_email = public.current_actor_email(),
    updated_at = now()
  where true
  returning * into v_row;

  update public.pdc_online_state_revision
  set revision = revision + 1, updated_at = now()
  where singleton returning revision into v_revision;

  perform public.audit_pdc_event(
    'reference_change',
    'pdc_online_operational_state',
    null,
    null,
    jsonb_build_object('state_key', v_key, 'version', p_expected_version),
    jsonb_build_object('state_key', v_key, 'version', v_row.version),
    jsonb_build_object('authority', 'supabase_online_only', 'revision', v_revision)
  );

  v_response := jsonb_build_object(
    'ok', true,
    'state_key', v_key,
    'payload', v_payload,
    'version', v_row.version,
    'revision', v_revision,
    'authority', 'supabase_online_only'
  );
  insert into public.pdc_online_state_receipts(
    idempotency_key, state_key, request_hash, response, actor_id
  ) values (v_idempotency, v_key, v_request_hash, v_response, v_actor);
  return v_response;
exception
  when sqlstate 'PDC01' then
    return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_pdc_online_state_batch(p_items jsonb, p_batch_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_batch_key text := lower(btrim(coalesce(p_batch_key, '')));
  v_item jsonb;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_index integer := 0;
  v_keys text[] := '{}'::text[];
  v_key text;
  v_idempotency text;
begin
  if auth.role() is distinct from 'authenticated'
    or auth.uid() is null
    or not exists (
      select 1 from public.pdc_user_roles r
      where r.auth_user_id = auth.uid()
        and lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
        and r.active is true
        and r.account_status::text = 'approved'
        and (r.role::text in ('operator', 'administrator') or (r.role::text = 'importer' and public.pdc_importer_monitor_action_421()))
    ) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if v_batch_key !~ '^pdc-batch-[a-f0-9]{32}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_batch_key');
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 20 then
    return jsonb_build_object('ok', false, 'error', 'invalid_batch_items');
  end if;

  begin
    for v_item in select value from jsonb_array_elements(p_items)
    loop
      v_index := v_index + 1;
      if jsonb_typeof(v_item) is distinct from 'object' then
        raise exception using errcode = 'P0001', message = 'invalid_batch_item';
      end if;
      v_key := btrim(coalesce(v_item->>'state_key', ''));
      if not public.pdc_online_state_key_allowed(v_key) then
        raise exception using errcode = 'P0001', message = 'invalid_state_key';
      end if;
      if v_key = any(v_keys) then
        raise exception using errcode = 'P0001', message = 'duplicate_state_key';
      end if;
      v_keys := array_append(v_keys, v_key);
      if not (v_item ? 'expected_version') or (v_item->>'expected_version') !~ '^[0-9]+$' then
        raise exception using errcode = 'P0001', message = 'expected_version_required';
      end if;
      v_idempotency := 'pdc-online-' || substr(
        encode(extensions.digest(v_batch_key || ':' || v_index::text, 'sha256'), 'hex'),
        1, 32
      );
      v_result := public.save_pdc_online_state(
        v_key,
        v_item->'payload',
        (v_item->>'expected_version')::bigint,
        v_idempotency
      );
      if coalesce((v_result->>'ok')::boolean, false) is not true then
        raise exception using errcode = 'P0001', message = coalesce(v_result->>'error', 'batch_item_failed');
      end if;
      v_results := v_results || jsonb_build_array(v_result);
    end loop;
    return jsonb_build_object(
      'ok', true,
      'authority', 'supabase_online_only',
      'results', v_results,
      'revision', coalesce((v_results->(jsonb_array_length(v_results) - 1)->>'revision')::bigint, 0)
    );
  exception
    when others then
      return jsonb_build_object(
        'ok', false,
        'error', 'batch_failed',
        'detail', sqlerrm
      );
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION public.activate_navision_backend_record(p_idempotency_key text, p_backend_record_id uuid, p_expected_revision bigint, p_activation_source text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE v_role text:=public.current_pdc_user_role()::text;
BEGIN
  IF NOT (coalesce(v_role = any(array['operator','administrator']), false) OR (coalesce(v_role,'')='importer' AND public.pdc_importer_monitor_action_421())) THEN
    RETURN public.navision_backend_response(false,'unauthorized');
  END IF;
  RETURN public.pdc_activate_navision_backend_record_internal_v1(
    p_idempotency_key,p_backend_record_id,p_expected_revision,p_activation_source);
END
$function$;

CREATE OR REPLACE FUNCTION public.append_vehicle_timeline_event(p_vehicle_id uuid, p_event_type text, p_event_at timestamp with time zone DEFAULT now(), p_source_kind vehicle_timeline_source_kind DEFAULT 'email'::vehicle_timeline_source_kind, p_event_state vehicle_timeline_event_state DEFAULT 'confirmed'::vehicle_timeline_event_state, p_ai_summary text DEFAULT NULL::text, p_original_statement text DEFAULT NULL::text, p_structured_data jsonb DEFAULT '{}'::jsonb, p_source_system text DEFAULT NULL::text, p_source_mailbox text DEFAULT NULL::text, p_source_email_id text DEFAULT NULL::text, p_source_thread_id text DEFAULT NULL::text, p_sender_name text DEFAULT NULL::text, p_sender_email text DEFAULT NULL::text, p_recipient_mailbox text DEFAULT NULL::text, p_supplier_name text DEFAULT NULL::text, p_subject text DEFAULT NULL::text, p_vehicle_match_confidence numeric DEFAULT NULL::numeric, p_relevance_confidence numeric DEFAULT NULL::numeric, p_classification_confidence numeric DEFAULT NULL::numeric, p_action_confidence numeric DEFAULT NULL::numeric, p_confidence_label text DEFAULT 'manual_review_required'::text, p_automatic_update boolean DEFAULT false, p_previous_values jsonb DEFAULT '{}'::jsonb, p_new_values jsonb DEFAULT '{}'::jsonb, p_approval_status text DEFAULT NULL::text, p_evidence_reference text DEFAULT NULL::text, p_source_intake_id uuid DEFAULT NULL::uuid, p_source_analysis_result_id uuid DEFAULT NULL::uuid, p_review_item_id uuid DEFAULT NULL::uuid, p_correction_of_event_id uuid DEFAULT NULL::uuid, p_supersedes_event_id uuid DEFAULT NULL::uuid)
 RETURNS vehicle_timeline_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_event public.vehicle_timeline_events%rowtype;
  v_revision bigint;
begin
  if auth.uid() IS NULL OR NOT coalesce((
    EXISTS (SELECT 1 FROM public.pdc_user_roles r
      WHERE r.auth_user_id=auth.uid()
        AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
        AND r.active AND r.account_status='approved'
        AND (r.role::text IN ('operator','administrator') OR (r.role::text='importer' AND public.pdc_importer_monitor_action_421())))
    OR (EXISTS (SELECT 1 FROM public.pdc_user_roles r
      WHERE r.auth_user_id=auth.uid()
        AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
        AND r.active AND r.account_status='approved' AND r.role::text='fitter')
      AND coalesce(pdc_fitter_private.authorized_request(true),false))
    OR coalesce(public.pdc_email_ai_v2_canonical_action_capability_20260902(),false)
  ),false) then
    raise exception 'PDC role importer required' using errcode = '42501';
  end if;

  perform 1 from public.vehicles where id = p_vehicle_id;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;

  insert into public.vehicle_timeline_events (
    vehicle_id,
    event_type,
    event_at,
    source_kind,
    event_state,
    source_system,
    source_mailbox,
    source_email_id,
    source_thread_id,
    sender_name,
    sender_email,
    recipient_mailbox,
    supplier_name,
    subject,
    ai_summary,
    original_statement,
    structured_data,
    vehicle_match_confidence,
    relevance_confidence,
    classification_confidence,
    action_confidence,
    confidence_label,
    automatic_update,
    previous_values,
    new_values,
    approval_status,
    evidence_reference,
    source_intake_id,
    source_analysis_result_id,
    review_item_id,
    correction_of_event_id,
    supersedes_event_id,
    created_by
  ) values (
    p_vehicle_id,
    p_event_type,
    coalesce(p_event_at, now()),
    p_source_kind,
    p_event_state,
    p_source_system,
    p_source_mailbox,
    p_source_email_id,
    p_source_thread_id,
    p_sender_name,
    p_sender_email,
    p_recipient_mailbox,
    p_supplier_name,
    p_subject,
    p_ai_summary,
    p_original_statement,
    coalesce(p_structured_data, '{}'::jsonb),
    p_vehicle_match_confidence,
    p_relevance_confidence,
    p_classification_confidence,
    p_action_confidence,
    p_confidence_label,
    coalesce(p_automatic_update, false),
    coalesce(p_previous_values, '{}'::jsonb),
    coalesce(p_new_values, '{}'::jsonb),
    p_approval_status,
    p_evidence_reference,
    p_source_intake_id,
    p_source_analysis_result_id,
    p_review_item_id,
    p_correction_of_event_id,
    p_supersedes_event_id,
    auth.uid()
  ) returning * into v_event;

  v_revision := public.bump_vehicle_intelligence_revision(p_vehicle_id);
  perform public.rebuild_vehicle_intelligence_summary(p_vehicle_id);

  perform public.audit_pdc_event(
    'update',
    'vehicle_timeline_events',
    v_event.id,
    p_vehicle_id,
    null,
    to_jsonb(v_event),
    jsonb_build_object('vehicle_intelligence_revision', v_revision)
  );

  return v_event;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_vehicle_intelligence_snapshot(p_vehicle_id uuid, p_sort text DEFAULT 'desc'::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_vehicle public.vehicles%rowtype;
  v_summary public.vehicle_intelligence_summaries%rowtype;
  v_revision bigint := 1;
  v_timeline jsonb;
  v_eta jsonb;
  v_open_reviews integer := 0;
  v_draft_count integer := 0;
  v_view_sensitive boolean := false;
begin
  perform public.workshop_require_planner_operator();

  select * into v_vehicle
  from public.vehicles
  where id = p_vehicle_id;

  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;

  select * into v_summary
  from public.vehicle_intelligence_summaries
  where vehicle_id = p_vehicle_id;

  select coalesce(revision, 1) into v_revision
  from public.vehicle_intelligence_revisions
  where vehicle_id = p_vehicle_id;

  v_view_sensitive := coalesce(public.current_pdc_user_role()::text in ('operator', 'administrator'), false) OR (coalesce(public.current_pdc_user_role()::text,'') = 'importer' AND public.pdc_importer_monitor_action_421());

  select count(*) into v_open_reviews
  from public.ai_review_items
  where coalesce(selected_vehicle_id, primary_vehicle_id) = p_vehicle_id
    and status = 'pending';

  select count(*) into v_draft_count
  from public.email_response_drafts
  where vehicle_id = p_vehicle_id
    and status in ('draft', 'approved', 'edited');

  select coalesce(jsonb_agg(jsonb_build_object(
    'eventId', e.id,
    'eventType', e.event_type,
    'eventAt', e.event_at,
    'recordedAt', e.recorded_at,
    'sourceKind', e.source_kind,
    'eventState', e.event_state,
    'sourceSystem', e.source_system,
    'sourceMailbox', e.source_mailbox,
    'sourceEmailId', case when v_view_sensitive then e.source_email_id else null end,
    'sourceThreadId', case when v_view_sensitive then e.source_thread_id else null end,
    'senderName', e.sender_name,
    'senderEmail', case when v_view_sensitive then e.sender_email else null end,
    'recipientMailbox', case when v_view_sensitive then e.recipient_mailbox else null end,
    'supplierName', e.supplier_name,
    'subject', e.subject,
    'aiSummary', e.ai_summary,
    'originalStatement', case when v_view_sensitive then e.original_statement else null end,
    'structuredData', e.structured_data,
    'vehicleMatchConfidence', e.vehicle_match_confidence,
    'relevanceConfidence', e.relevance_confidence,
    'classificationConfidence', e.classification_confidence,
    'actionConfidence', e.action_confidence,
    'confidenceLabel', e.confidence_label,
    'automaticUpdate', e.automatic_update,
    'previousValues', e.previous_values,
    'newValues', e.new_values,
    'approvalStatus', e.approval_status,
    'evidenceReference', case when v_view_sensitive then e.evidence_reference else null end,
    'reviewItemId', e.review_item_id,
    'correctionOfEventId', e.correction_of_event_id,
    'supersedesEventId', e.supersedes_event_id
  )), '[]'::jsonb)
  into v_timeline
  from (
    select *
    from public.vehicle_timeline_events
    where vehicle_id = p_vehicle_id
    order by
      case when lower(coalesce(p_sort, 'desc')) = 'asc' then event_at end asc,
      case when lower(coalesce(p_sort, 'desc')) <> 'asc' then event_at end desc,
      case when lower(coalesce(p_sort, 'desc')) = 'asc' then created_at end asc,
      case when lower(coalesce(p_sort, 'desc')) <> 'asc' then created_at end desc
    limit greatest(1, least(coalesce(p_limit, 100), 500))
  ) e;

  select coalesce(jsonb_agg(jsonb_build_object(
    'etaId', h.id,
    'etaType', h.eta_type,
    'etaValue', h.eta_value,
    'etaValueText', h.eta_value_text,
    'etaState', h.eta_state,
    'confidence', h.confidence,
    'originalWording', case when v_view_sensitive then h.original_wording else null end,
    'sourceLabel', h.source_label,
    'supplierName', h.supplier_name,
    'receivedAt', h.received_at,
    'previousEtaId', h.previous_eta_id,
    'supersededBy', h.superseded_by,
    'createdAt', h.created_at
  ) order by h.created_at desc), '[]'::jsonb)
  into v_eta
  from public.vehicle_eta_history h
  where h.vehicle_id = p_vehicle_id;

  return jsonb_build_object(
    'vehicleId', p_vehicle_id,
    'revision', coalesce(v_revision, 1),
    'summary', case when v_summary.vehicle_id is null then null else jsonb_build_object(
      'summaryText', v_summary.summary_text,
      'summaryJson', v_summary.summary_json,
      'latestEventId', v_summary.latest_event_id,
      'latestRebuiltAt', v_summary.latest_rebuilt_at
    ) end,
    'timeline', v_timeline,
    'etaHistory', v_eta,
    'openReviewCount', v_open_reviews,
    'openDraftCount', v_draft_count
  );
end;
$function$;

SELECT set_config('search_path','pg_catalog',true);
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note)
SELECT p.oid::regprocedure::text, md5(p.prosrc), 'r421', e.note
FROM (VALUES
 ('public.pdc_importer_monitor_action_421()','importer controller exception only inside monitor canonical actions'),
 ('public.is_pdc_role(public.pdc_role)','operator gate: importer only via monitor exception (was 6b951e82d7a262d846df7ead80fc9ef2)'),
 ('public.pdc_sublet_actor_allowed()','sublet writes: importer only via monitor exception (was dec90f7ce54cab652b37367cab69f969)'),
 ('public.save_pdc_online_state(text,jsonb,bigint,text)','importer only via monitor exception (was 959f45f25174c37935a61fe147cdf4ea)'),
 ('public.save_pdc_online_state_batch(jsonb,text)','importer only via monitor exception (was bcffc5de50e396ba9e14ca3f4d829b2c)'),
 ('public.activate_navision_backend_record(text,uuid,bigint,text)','show on Vehicle Locations: controller/admin (was 06e82ace7433848a95dec41e95205231)'),
 ('public.get_vehicle_intelligence_snapshot(uuid,text,integer)','sensitive fields: controller/admin (was 3f7b333f93c2ecc89359a38e7535d7de)')
) e(sig,note) JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.sig)
UNION ALL
SELECT p.oid::regprocedure::text, md5(p.prosrc), 'r421', 'timeline append: importer only via monitor exception (was 0d529c8a8cdfd5c5b48c6bf1f0a9f93a)'
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='append_vehicle_timeline_event';
SELECT set_config('search_path','"$user", public, extensions',true);

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('importer_viewer_plus_import','F36','Importer = viewer + Navision import: no controller-level gate lists importer next to operator, and the seven gates that used to let importers through now allow them only inside the email-monitor canonical action contracts (private helper).',
 $chk$WITH f AS (
 SELECT p.proname::text n, p.prosrc s FROM pg_catalog.pg_proc p WHERE p.oid IN (
  to_regprocedure('public.is_pdc_role(public.pdc_role)'), to_regprocedure('public.pdc_sublet_actor_allowed()'),
  to_regprocedure('public.save_pdc_online_state(text,jsonb,bigint,text)'), to_regprocedure('public.save_pdc_online_state_batch(jsonb,text)'),
  to_regprocedure('public.activate_navision_backend_record(text,uuid,bigint,text)'),
  to_regprocedure('public.get_vehicle_intelligence_snapshot(uuid,text,integer)'))
 UNION ALL
 SELECT p.proname::text, p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='append_vehicle_timeline_event'
), x AS (
 SELECT count(*) total,
  count(*) FILTER (WHERE s ~* '[(\[]\s*''operator''\s*,\s*''importer''') ladder,
  count(*) FILTER (WHERE position('pdc_importer_monitor_action_421()' IN s)>0) gated
 FROM f
), h AS (
 SELECT coalesce((SELECT p.prosecdef AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
  FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.pdc_importer_monitor_action_421()')),false) ok
)
SELECT x.total=7 AND x.ladder=0 AND x.gated=7 AND h.ok AS ok,
 'importer gates: '||x.gated||' of 7 use the monitor-only exception; importer still on the controller ladder in '||x.ladder
 ||'; helper private: '||CASE WHEN h.ok THEN 'yes' ELSE 'NO' END AS detail
FROM x, h$chk$,true,223,'r421');

DO $p$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM (VALUES
  ('public.is_pdc_role(pdc_role)','39a794b23d1d63117cf549d78acba4de','8609863ae82e85e9edb7847bf2957606'),
  ('public.pdc_sublet_actor_allowed()','a3519a51ab5be4dd0646d8b15bbb101a','1c75a53411ee6262c0143ada12c6d2b2'),
  ('public.save_pdc_online_state(text,jsonb,bigint,text)','bdc55e25a001201923ab06d72f71d448','ca8e0514e90d5c9c3e27c027ef3208ce'),
  ('public.save_pdc_online_state_batch(jsonb,text)','7c6b66c56b8429cae810431a271ba2d6','ca8e0514e90d5c9c3e27c027ef3208ce'),
  ('public.activate_navision_backend_record(text,uuid,bigint,text)','8e6489995c3b14afb93a29e5c5d9b638','27cb510615d31f22efd39d88c2f1337f'),
  ('public.append_vehicle_timeline_event(uuid,text,timestamp with time zone,vehicle_timeline_source_kind,vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)','ef3bd3587978f25862546483913231e4','3cb754a2ffb942b8adcaba96c13786a3'),
  ('public.get_vehicle_intelligence_snapshot(uuid,text,integer)','eabe1cbf0e50225b2ecb5fe893dff791','282eda4fef6a92c22f0e600515f093e8')) e(sig,m,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m AND md5(coalesce(p.proacl::text,'')||p.prosecdef::text||p.provolatile::text||p.proowner::regrole::text||coalesce(array_to_string(p.proconfig,'|'),''))=e.a)<>7 THEN RAISE EXCEPTION 'r421: new function bodies or attributes are not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_importer_monitor_action_421()'::regprocedure)<>'8c87fb69db9e89f639177bab101fe7a5'
  OR (SELECT coalesce(proacl::text,'') FROM pg_proc WHERE oid='public.pdc_importer_monitor_action_421()'::regprocedure)<>'{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r421: helper md5 or grants not as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r421')<>8 THEN RAISE EXCEPTION 'r421: pins not written'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='importer_viewer_plus_import') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r421: importer_viewer_plus_import not ok: %', r.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r421: protected_function_md5s not ok: %', r.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
