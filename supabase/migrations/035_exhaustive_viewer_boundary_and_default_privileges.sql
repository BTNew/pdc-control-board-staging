-- Migration 035: close the complete authenticated-viewer read graph.
--
-- The restricted pilot viewer may read only the exact six-field, exact-batch
-- vehicle RPC plus the minimum self-account metadata needed to authorize and
-- lock the browser session. All broad vehicle, workshop, identity, source,
-- history, audit, configuration and relationship paths require operator or
-- higher. Internal helpers are owner-callable only. Future public functions do
-- not inherit Supabase's generic PUBLIC/anon/authenticated EXECUTE defaults.

begin;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

drop policy if exists ai_intake_config_select_approved on public.ai_intake_config;
create policy ai_intake_config_select_approved on public.ai_intake_config
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists ai_mapping_rules_select_approved on public.ai_mapping_rules;
create policy ai_mapping_rules_select_approved on public.ai_mapping_rules
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists audit_events_select_approved on public.audit_events;
create policy audit_events_select_approved on public.audit_events
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists deleted_completed_select_approved on public.deleted_completed_vehicles;
create policy deleted_completed_select_approved on public.deleted_completed_vehicles
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists import_runs_select_approved on public.import_runs;
create policy import_runs_select_approved on public.import_runs
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists label_print_events_select_approved on public.label_print_events;
create policy label_print_events_select_approved on public.label_print_events
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists salespeople_select_by_role on public.salespeople;
create policy salespeople_select_by_role on public.salespeople
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists sublet_providers_select_by_role on public.sublet_providers;
create policy sublet_providers_select_by_role on public.sublet_providers
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists vehicle_intelligence_summaries_select_viewer on public.vehicle_intelligence_summaries;
create policy vehicle_intelligence_summaries_select_viewer on public.vehicle_intelligence_summaries
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists vehicle_lifecycle_resolver_revision_select_approved on public.vehicle_lifecycle_resolver_revision;
create policy vehicle_lifecycle_resolver_revision_select_approved on public.vehicle_lifecycle_resolver_revision
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists vehicle_master_revision_select_approved on public.vehicle_master_revision;
create policy vehicle_master_revision_select_approved on public.vehicle_master_revision
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists movements_select_approved on public.vehicle_movements;
create policy movements_select_approved on public.vehicle_movements
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists parts_select_approved on public.vehicle_parts_updates;
create policy parts_select_approved on public.vehicle_parts_updates
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists work_items_select_approved on public.vehicle_work_items;
create policy work_items_select_approved on public.vehicle_work_items
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists workshop_bays_select_by_role on public.workshop_bays;
create policy workshop_bays_select_by_role on public.workshop_bays
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists workshop_booking_assignments_select_approved on public.workshop_booking_assignments;
create policy workshop_booking_assignments_select_approved on public.workshop_booking_assignments
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists workshop_booking_history_select_approved on public.workshop_booking_history;
create policy workshop_booking_history_select_approved on public.workshop_booking_history
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists workshop_bookings_select_approved on public.workshop_bookings;
create policy workshop_bookings_select_approved on public.workshop_bookings
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists workshop_parts_overrides_select_approved on public.workshop_parts_overrides;
create policy workshop_parts_overrides_select_approved on public.workshop_parts_overrides
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists workshop_revision_select_approved on public.workshop_revision;
create policy workshop_revision_select_approved on public.workshop_revision
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists workshop_settings_select_approved on public.workshop_settings;
create policy workshop_settings_select_approved on public.workshop_settings
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists workshop_stages_select_approved on public.workshop_stages;
create policy workshop_stages_select_approved on public.workshop_stages
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists workshop_technicians_select_by_role on public.workshop_technicians;
create policy workshop_technicians_select_by_role on public.workshop_technicians
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

drop policy if exists ai_workshop_commands_select_own_or_importer on public.ai_workshop_commands;
create policy ai_workshop_commands_select_own_or_importer on public.ai_workshop_commands
  for select to authenticated
  using (public.is_pdc_role('operator'::public.pdc_role));

-- Existing broad reader RPCs remain operator/importer/administrator callable.
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
  perform public.require_pdc_role('operator');

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

  v_view_sensitive := public.current_pdc_user_role() in ('operator', 'importer', 'administrator');

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
revoke all on function public.get_vehicle_intelligence_snapshot(uuid,text,integer) from public, anon;
grant execute on function public.get_vehicle_intelligence_snapshot(uuid,text,integer) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_workshop_configuration()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb;
begin
  perform public.require_pdc_role('operator');
  select jsonb_object_agg(key, jsonb_build_object('value', value, 'version', version, 'updated_at', updated_at))
  into v_result
  from public.workshop_settings;
  return coalesce(v_result, '{}'::jsonb);
end;
$function$;
revoke all on function public.get_workshop_configuration() from public, anon;
grant execute on function public.get_workshop_configuration() to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.list_salespeople(p_include_inactive boolean DEFAULT false)
 RETURNS SETOF salespeople
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_pdc_role('operator');
  if p_include_inactive and not public.is_pdc_role('operator') then
    p_include_inactive := false;
  end if;
  if p_include_inactive then
    return query select * from public.salespeople order by sort_order, name;
  else
    return query select * from public.salespeople where active order by sort_order, name;
  end if;
end;
$function$;
revoke all on function public.list_salespeople(boolean) from public, anon;
grant execute on function public.list_salespeople(boolean) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.list_sublet_providers(p_include_inactive boolean DEFAULT false)
 RETURNS SETOF sublet_providers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_pdc_role('operator');
  if p_include_inactive and not public.is_pdc_role('operator') then
    p_include_inactive := false;
  end if;
  if p_include_inactive then
    return query select * from public.sublet_providers order by sort_order, name;
  else
    return query select * from public.sublet_providers where active order by sort_order, name;
  end if;
end;
$function$;
revoke all on function public.list_sublet_providers(boolean) from public, anon;
grant execute on function public.list_sublet_providers(boolean) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.list_technicians(p_include_inactive boolean DEFAULT false)
 RETURNS SETOF workshop_technicians
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_pdc_role('operator');
  if p_include_inactive and not public.is_pdc_role('operator') then
    p_include_inactive := false;
  end if;
  if p_include_inactive then
    return query select * from public.workshop_technicians order by sort_order, name;
  else
    return query select * from public.workshop_technicians where active order by sort_order, name;
  end if;
end;
$function$;
revoke all on function public.list_technicians(boolean) from public, anon;
grant execute on function public.list_technicians(boolean) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.list_workshop_bays(p_include_inactive boolean DEFAULT false)
 RETURNS SETOF workshop_bays
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_pdc_role('operator');
  if p_include_inactive and not public.is_pdc_role('operator') then
    p_include_inactive := false;
  end if;
  if p_include_inactive then
    return query select * from public.workshop_bays order by bay_number;
  else
    return query select * from public.workshop_bays where is_active order by bay_number;
  end if;
end;
$function$;
revoke all on function public.list_workshop_bays(boolean) from public, anon;
grant execute on function public.list_workshop_bays(boolean) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.resolve_vehicle_lifecycle_identity(p_vehicle_id text DEFAULT NULL::text, p_stock_number text DEFAULT NULL::text, p_vin text DEFAULT NULL::text, p_job_card_number text DEFAULT NULL::text, p_permanent_vehicle_id text DEFAULT NULL::text, p_toyota_order_number text DEFAULT NULL::text, p_source_system text DEFAULT NULL::text, p_source_record_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role public.pdc_role;
  v_uuid uuid;
  v_stock text;
  v_vin text;
  v_job text;
  v_permanent text;
  v_order text;
  v_source text;
  v_source_record text;
  v_has_input boolean := false;
  v_uuid_candidates uuid[] := '{}'::uuid[];
  v_stock_canonical uuid[] := '{}'::uuid[];
  v_stock_alias uuid[] := '{}'::uuid[];
  v_stock_candidates uuid[] := '{}'::uuid[];
  v_vin_canonical uuid[] := '{}'::uuid[];
  v_vin_alias uuid[] := '{}'::uuid[];
  v_vin_candidates uuid[] := '{}'::uuid[];
  v_job_canonical uuid[] := '{}'::uuid[];
  v_job_alias uuid[] := '{}'::uuid[];
  v_job_candidates uuid[] := '{}'::uuid[];
  v_permanent_candidates uuid[] := '{}'::uuid[];
  v_order_canonical uuid[] := '{}'::uuid[];
  v_order_alias uuid[] := '{}'::uuid[];
  v_order_candidates uuid[] := '{}'::uuid[];
  v_source_canonical uuid[] := '{}'::uuid[];
  v_source_alias uuid[] := '{}'::uuid[];
  v_source_evidence uuid[] := '{}'::uuid[];
  v_source_candidates uuid[] := '{}'::uuid[];
  v_all_candidates uuid[] := '{}'::uuid[];
  v_matched_by text[] := '{}'::text[];
  v_resolved_id uuid;
  v_revision bigint;
  v_vehicle record;
  v_candidate_count integer;
begin
  v_role := public.current_pdc_user_role();
  if v_role is null or not public.is_pdc_role('operator') then
    return jsonb_build_object('outcome', 'unauthorized');
  end if;

  if nullif(btrim(p_vehicle_id), '') is not null then
    v_has_input := true;
    if btrim(p_vehicle_id) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'vehicle_id');
    end if;
    begin
      v_uuid := btrim(p_vehicle_id)::uuid;
    exception when invalid_text_representation then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'vehicle_id');
    end;
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_uuid_candidates
    from public.vehicles v where v.id = v_uuid;
  end if;

  if nullif(btrim(p_stock_number), '') is not null then
    v_has_input := true;
    if not public.is_real_vehicle_stock_number(p_stock_number) then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'stock_number');
    end if;
    v_stock := public.normalize_vehicle_stock_number(p_stock_number);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_stock_canonical
    from public.vehicles v
    where public.is_real_vehicle_stock_number(v.stock_number)
      and v.stock_number_normalized = v_stock;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_stock_alias
    from public.vehicle_aliases a
    where a.active and a.alias_type_normalized = 'stock_number'
      and public.is_real_vehicle_stock_number(a.alias_value)
      and a.normalized_alias_value = v_stock;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_stock_candidates from unnest(v_stock_canonical || v_stock_alias) x;
  end if;

  if nullif(btrim(p_vin), '') is not null then
    v_has_input := true;
    if not public.is_valid_vehicle_vin(p_vin) then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'vin');
    end if;
    v_vin := public.normalize_vehicle_vin(p_vin);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_vin_canonical
    from public.vehicles v
    where public.is_valid_vehicle_vin(v.vin) and v.vin_normalized = v_vin;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_vin_alias
    from public.vehicle_aliases a
    where a.active and a.alias_type_normalized = 'vin'
      and a.normalized_alias_value = v_vin;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_vin_candidates from unnest(v_vin_canonical || v_vin_alias) x;
  end if;

  v_source := public.normalize_vehicle_source_system(p_source_system);
  v_source_record := public.normalize_vehicle_source_identifier(p_source_record_id);
  if v_source_record is not null and v_source is null then
    return jsonb_build_object('outcome', 'invalid_input', 'field', 'source_identity');
  end if;
  if v_source_record is not null then
    v_has_input := true;
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_source_canonical
    from public.vehicles v
    where v.source_system_normalized = v_source
      and v.source_record_id_normalized = v_source_record;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_source_alias
    from public.vehicle_aliases a
    where a.active and a.source_system_normalized = v_source
      and a.alias_type_normalized = 'source_record_id'
      and a.normalized_alias_value = v_source_record;
    select coalesce(array_agg(distinct sr.vehicle_id order by sr.vehicle_id), '{}'::uuid[])
    into v_source_evidence
    from public.vehicle_master_source_records sr
    where sr.vehicle_id is not null
      and public.normalize_vehicle_source_system(sr.source_system) = v_source
      and public.normalize_vehicle_source_identifier(sr.source_record_id) = v_source_record;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_source_candidates
    from unnest(v_source_canonical || v_source_alias || v_source_evidence) x;
  end if;

  if nullif(btrim(p_job_card_number), '') is not null then
    v_has_input := true;
    if v_source is null then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'job_card_source_system');
    end if;
    v_job := public.normalize_vehicle_source_identifier(p_job_card_number);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_job_canonical
    from public.vehicles v
    where v.source_system_normalized = v_source
      and public.normalize_vehicle_source_identifier(v.job_card_number) = v_job;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_job_alias
    from public.vehicle_aliases a
    where a.active and a.source_system_normalized = v_source
      and a.alias_type_normalized = 'job_card_number'
      and a.normalized_alias_value = v_job;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_job_candidates from unnest(v_job_canonical || v_job_alias) x;
  end if;

  if nullif(btrim(p_toyota_order_number), '') is not null then
    v_has_input := true;
    if v_source is null then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'toyota_order_source_system');
    end if;
    v_order := public.normalize_vehicle_source_identifier(p_toyota_order_number);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_order_canonical
    from public.vehicles v
    where v.source_system_normalized = v_source
      and public.normalize_vehicle_source_identifier(v.toyota_order_number) = v_order;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_order_alias
    from public.vehicle_aliases a
    where a.active and a.source_system_normalized = v_source
      and a.alias_type_normalized = 'toyota_order_number'
      and a.normalized_alias_value = v_order;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_order_candidates from unnest(v_order_canonical || v_order_alias) x;
  end if;

  if nullif(btrim(p_permanent_vehicle_id), '') is not null then
    v_has_input := true;
    v_permanent := public.normalize_vehicle_source_identifier(p_permanent_vehicle_id);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_permanent_candidates
    from public.vehicles v
    where public.normalize_vehicle_source_identifier(v.permanent_vehicle_id) = v_permanent;
  end if;

  if not v_has_input then
    return jsonb_build_object('outcome', 'invalid_input', 'field', 'identity');
  end if;

  -- An explicit UUID is the highest-precedence identity. If it does not exist,
  -- another identifier is not allowed to silently replace it.
  if v_uuid is not null and cardinality(v_uuid_candidates) = 0 then
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_all_candidates
    from unnest(v_stock_candidates || v_vin_candidates || v_job_candidates ||
      v_permanent_candidates || v_order_candidates || v_source_candidates) x;
    if cardinality(v_all_candidates) > 0 then
      return jsonb_build_object('outcome', 'conflict', 'reason', 'conflicting_identifiers',
        'candidate_count', cardinality(v_all_candidates));
    end if;
    return jsonb_build_object('outcome', 'not_found');
  end if;

  -- A canonical row and an alias/source-evidence row for the same typed input
  -- must never disagree. This is a conflict, not a precedence choice.
  if cardinality(v_stock_candidates) > 1
     and cardinality(v_stock_canonical) > 0 and cardinality(v_stock_alias) > 0
     and not (v_stock_canonical <@ v_stock_alias and v_stock_alias <@ v_stock_canonical) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'stock_number', 'candidate_count', cardinality(v_stock_candidates));
  end if;
  if cardinality(v_vin_candidates) > 1
     and cardinality(v_vin_canonical) > 0 and cardinality(v_vin_alias) > 0
     and not (v_vin_canonical <@ v_vin_alias and v_vin_alias <@ v_vin_canonical) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'vin', 'candidate_count', cardinality(v_vin_candidates));
  end if;
  if cardinality(v_job_candidates) > 1
     and cardinality(v_job_canonical) > 0 and cardinality(v_job_alias) > 0
     and not (v_job_canonical <@ v_job_alias and v_job_alias <@ v_job_canonical) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'job_card_number', 'candidate_count', cardinality(v_job_candidates));
  end if;
  if cardinality(v_order_candidates) > 1
     and cardinality(v_order_canonical) > 0 and cardinality(v_order_alias) > 0
     and not (v_order_canonical <@ v_order_alias and v_order_alias <@ v_order_canonical) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'toyota_order_number', 'candidate_count', cardinality(v_order_candidates));
  end if;
  if cardinality(v_source_candidates) > 1
     and (
       (cardinality(v_source_canonical) > 0 and cardinality(v_source_alias) > 0
         and not (v_source_canonical <@ v_source_alias and v_source_alias <@ v_source_canonical))
       or (cardinality(v_source_canonical) > 0 and cardinality(v_source_evidence) > 0
         and not (v_source_canonical <@ v_source_evidence and v_source_evidence <@ v_source_canonical))
       or (cardinality(v_source_alias) > 0 and cardinality(v_source_evidence) > 0
         and not (v_source_alias <@ v_source_evidence and v_source_evidence <@ v_source_alias))
     ) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'source_record_id', 'candidate_count', cardinality(v_source_candidates));
  end if;

  foreach v_candidate_count in array array[
    cardinality(v_uuid_candidates), cardinality(v_stock_candidates),
    cardinality(v_vin_candidates), cardinality(v_job_candidates),
    cardinality(v_permanent_candidates), cardinality(v_order_candidates),
    cardinality(v_source_candidates)
  ] loop
    if v_candidate_count > 1 then
      return jsonb_build_object('outcome', 'ambiguous', 'reason', 'multiple_normalized_matches',
        'candidate_count', v_candidate_count);
    end if;
  end loop;

  select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
  into v_all_candidates
  from unnest(
    v_uuid_candidates || v_stock_candidates || v_vin_candidates ||
    v_job_candidates || v_permanent_candidates || v_order_candidates ||
    v_source_candidates
  ) x;

  if cardinality(v_all_candidates) = 0 then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if cardinality(v_all_candidates) > 1 then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'conflicting_identifiers',
      'candidate_count', cardinality(v_all_candidates));
  end if;

  v_resolved_id := v_all_candidates[1];
  if cardinality(v_uuid_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'vehicle_id'); end if;
  if cardinality(v_stock_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'stock_number'); end if;
  if cardinality(v_vin_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'vin'); end if;
  if cardinality(v_job_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'job_card_number'); end if;
  if cardinality(v_permanent_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'permanent_vehicle_id'); end if;
  if cardinality(v_order_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'toyota_order_number'); end if;
  if cardinality(v_source_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'source_record_id'); end if;

  select v.id, v.version, v.qc_completed_at, v.lifecycle_state, (v.deleted_at is not null) as is_archived
  into v_vehicle
  from public.vehicles v
  where v.id = v_resolved_id;

  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  select revision into v_revision
  from public.vehicle_lifecycle_resolver_revision
  where singleton;

  return jsonb_build_object(
    'outcome', 'resolved',
    'vehicle_id', v_vehicle.id,
    'version', v_vehicle.version,
    'qc_completed_at', v_vehicle.qc_completed_at,
    'lifecycle_state', v_vehicle.lifecycle_state,
    'is_archived', v_vehicle.is_archived,
    'resolver_revision', coalesce(v_revision, 1),
    'matched_by', to_jsonb(v_matched_by)
  );
end;
$function$;
revoke all on function public.resolve_vehicle_lifecycle_identity(text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.resolve_vehicle_lifecycle_identity(text,text,text,text,text,text,text,text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.workshop_current_revision()
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_pdc_role('operator'::public.pdc_role);
  return (select revision from public.workshop_revision where id = 1);
end;
$function$;
revoke all on function public.workshop_current_revision() from public, anon;
grant execute on function public.workshop_current_revision() to authenticated, service_role;

-- Internal SECURITY DEFINER helpers are callable only by owners/wrappers.
revoke all on function public.apply_vehicle_master_import(text,text,text,jsonb,integer,text) from public, anon, authenticated;
grant execute on function public.apply_vehicle_master_import(text,text,text,jsonb,integer,text) to service_role;
revoke all on function public.bump_vehicle_intelligence_revision(uuid) from public, anon, authenticated;
grant execute on function public.bump_vehicle_intelligence_revision(uuid) to service_role;
revoke all on function public.workshop_conflict_payload(uuid,text) from public, anon, authenticated;
grant execute on function public.workshop_conflict_payload(uuid,text) to service_role;
revoke all on function public.workshop_find_bay_conflict(uuid,uuid,timestamp with time zone,timestamp with time zone) from public, anon, authenticated;
grant execute on function public.workshop_find_bay_conflict(uuid,uuid,timestamp with time zone,timestamp with time zone) to service_role;
revoke all on function public.workshop_find_technician_conflict(uuid,uuid,timestamp with time zone,timestamp with time zone) from public, anon, authenticated;
grant execute on function public.workshop_find_technician_conflict(uuid,uuid,timestamp with time zone,timestamp with time zone) to service_role;
revoke all on function public.workshop_lock_resources(uuid,uuid) from public, anon, authenticated;
grant execute on function public.workshop_lock_resources(uuid,uuid) to service_role;
revoke all on function public.workshop_normalize_start_date(timestamp with time zone) from public, anon, authenticated;
grant execute on function public.workshop_normalize_start_date(timestamp with time zone) to service_role;
revoke all on function public.workshop_parts_ready(uuid) from public, anon, authenticated;
grant execute on function public.workshop_parts_ready(uuid) to service_role;
revoke all on function public.workshop_resolve_bay_id(text,integer) from public, anon, authenticated;
grant execute on function public.workshop_resolve_bay_id(text,integer) to service_role;
revoke all on function public.workshop_resolve_stage_id(text) from public, anon, authenticated;
grant execute on function public.workshop_resolve_stage_id(text) to service_role;
revoke all on function public.workshop_upsert_primary_assignment(uuid,uuid,timestamp with time zone,timestamp with time zone,text) from public, anon, authenticated;
grant execute on function public.workshop_upsert_primary_assignment(uuid,uuid,timestamp with time zone,timestamp with time zone,text) to service_role;
revoke all on function public.workshop_write_history(uuid,text,jsonb,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.workshop_write_history(uuid,text,jsonb,jsonb,jsonb) to service_role;

commit;
