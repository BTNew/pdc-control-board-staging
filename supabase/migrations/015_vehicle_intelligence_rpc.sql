begin;

create or replace function public.bump_vehicle_intelligence_revision(p_vehicle_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_revision bigint;
begin
  insert into public.vehicle_intelligence_revisions (vehicle_id, revision, updated_by, updated_at)
  values (p_vehicle_id, 1, auth.uid(), now())
  on conflict (vehicle_id)
  do update set revision = public.vehicle_intelligence_revisions.revision + 1,
                updated_by = auth.uid(),
                updated_at = now()
  returning revision into v_revision;

  return v_revision;
end;
$$;

create or replace function public.rebuild_vehicle_intelligence_summary(p_vehicle_id uuid)
returns public.vehicle_intelligence_summaries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vehicle public.vehicles%rowtype;
  v_latest_event public.vehicle_timeline_events%rowtype;
  v_eta public.vehicle_eta_history%rowtype;
  v_revision bigint;
  v_open_reviews integer := 0;
  v_draft_count integer := 0;
  v_summary_text text;
  v_summary_json jsonb;
  v_row public.vehicle_intelligence_summaries%rowtype;
begin
  if public.current_pdc_user_role() not in ('importer', 'administrator', 'operator') then
    raise exception 'PDC role importer required' using errcode = '42501';
  end if;

  select * into v_vehicle
  from public.vehicles
  where id = p_vehicle_id;

  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;

  select * into v_latest_event
  from public.vehicle_timeline_events
  where vehicle_id = p_vehicle_id
  order by event_at desc, created_at desc
  limit 1;

  select * into v_eta
  from public.vehicle_eta_history
  where vehicle_id = p_vehicle_id
    and superseded_by is null
  order by created_at desc
  limit 1;

  select coalesce(revision, 1) into v_revision
  from public.vehicle_intelligence_revisions
  where vehicle_id = p_vehicle_id;

  if v_revision is null then
    v_revision := 1;
  end if;

  select count(*) into v_open_reviews
  from public.ai_review_items
  where coalesce(selected_vehicle_id, primary_vehicle_id) = p_vehicle_id
    and status = 'pending';

  select count(*) into v_draft_count
  from public.email_response_drafts
  where vehicle_id = p_vehicle_id
    and status in ('draft', 'approved', 'edited');

  v_summary_text := concat_ws(E'\n',
    concat('Current location: ', coalesce(v_vehicle.current_location, 'Unknown')),
    concat('Current workflow stage: ', coalesce(v_vehicle.pmb_stage, 'Unknown')),
    concat('Current workshop status: ', coalesce(v_vehicle.workshop_status, 'Unknown')),
    case when v_eta.id is not null then concat('Current ETA (', v_eta.eta_type, '): ', coalesce(to_char(v_eta.eta_value, 'YYYY-MM-DD'), v_eta.eta_value_text, 'Unknown')) else null end,
    case when v_latest_event.id is not null then concat('Latest update: ', coalesce(v_latest_event.ai_summary, v_latest_event.event_type)) else 'Latest update: None recorded' end,
    case when v_open_reviews > 0 then concat('Open AI reviews: ', v_open_reviews::text) else null end,
    case when v_draft_count > 0 then concat('Open drafts: ', v_draft_count::text) else null end
  );

  v_summary_json := jsonb_build_object(
    'vehicleId', v_vehicle.id,
    'currentLocation', v_vehicle.current_location,
    'currentStage', v_vehicle.pmb_stage,
    'currentBayStage', v_vehicle.pmb_bay_stage,
    'currentBayNumber', v_vehicle.pmb_bay_number,
    'workshopStatus', v_vehicle.workshop_status,
    'latestImportantUpdate', case when v_latest_event.id is null then null else jsonb_build_object(
      'eventId', v_latest_event.id,
      'eventType', v_latest_event.event_type,
      'eventAt', v_latest_event.event_at,
      'summary', coalesce(v_latest_event.ai_summary, v_latest_event.event_type),
      'confidenceLabel', v_latest_event.confidence_label,
      'eventState', v_latest_event.event_state
    ) end,
    'currentEta', case when v_eta.id is null then null else jsonb_build_object(
      'etaId', v_eta.id,
      'etaType', v_eta.eta_type,
      'etaValue', v_eta.eta_value,
      'etaValueText', v_eta.eta_value_text,
      'etaState', v_eta.eta_state,
      'originalWording', v_eta.original_wording,
      'receivedAt', v_eta.received_at,
      'supplierName', v_eta.supplier_name
    ) end,
    'openReviewCount', v_open_reviews,
    'openDraftCount', v_draft_count,
    'keyRisks', jsonb_build_array()
  );

  insert into public.vehicle_intelligence_summaries (
    vehicle_id,
    revision,
    summary_text,
    summary_json,
    latest_event_id,
    latest_rebuilt_at,
    updated_by
  ) values (
    p_vehicle_id,
    v_revision,
    v_summary_text,
    v_summary_json,
    v_latest_event.id,
    now(),
    auth.uid()
  )
  on conflict (vehicle_id)
  do update set revision = excluded.revision,
                summary_text = excluded.summary_text,
                summary_json = excluded.summary_json,
                latest_event_id = excluded.latest_event_id,
                latest_rebuilt_at = excluded.latest_rebuilt_at,
                updated_by = excluded.updated_by
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function public.append_vehicle_timeline_event(
  p_vehicle_id uuid,
  p_event_type text,
  p_event_at timestamptz default now(),
  p_source_kind public.vehicle_timeline_source_kind default 'email',
  p_event_state public.vehicle_timeline_event_state default 'confirmed',
  p_ai_summary text default null,
  p_original_statement text default null,
  p_structured_data jsonb default '{}'::jsonb,
  p_source_system text default null,
  p_source_mailbox text default null,
  p_source_email_id text default null,
  p_source_thread_id text default null,
  p_sender_name text default null,
  p_sender_email text default null,
  p_recipient_mailbox text default null,
  p_supplier_name text default null,
  p_subject text default null,
  p_vehicle_match_confidence numeric default null,
  p_relevance_confidence numeric default null,
  p_classification_confidence numeric default null,
  p_action_confidence numeric default null,
  p_confidence_label text default 'manual_review_required',
  p_automatic_update boolean default false,
  p_previous_values jsonb default '{}'::jsonb,
  p_new_values jsonb default '{}'::jsonb,
  p_approval_status text default null,
  p_evidence_reference text default null,
  p_source_intake_id uuid default null,
  p_source_analysis_result_id uuid default null,
  p_review_item_id uuid default null,
  p_correction_of_event_id uuid default null,
  p_supersedes_event_id uuid default null
)
returns public.vehicle_timeline_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.vehicle_timeline_events%rowtype;
  v_revision bigint;
begin
  if public.current_pdc_user_role() not in ('importer', 'administrator', 'operator') then
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
$$;

create or replace function public.record_vehicle_eta_history(
  p_vehicle_id uuid,
  p_eta_type text,
  p_eta_value date default null,
  p_eta_value_text text default null,
  p_eta_state public.vehicle_timeline_event_state default 'confirmed',
  p_confidence numeric default null,
  p_original_wording text default null,
  p_source_label text default null,
  p_supplier_name text default null,
  p_received_at timestamptz default null,
  p_source_intake_id uuid default null,
  p_source_timeline_event_id uuid default null
)
returns public.vehicle_eta_history
language plpgsql
security definer
set search_path = public
as $$
declare
  v_previous public.vehicle_eta_history%rowtype;
  v_row public.vehicle_eta_history%rowtype;
  v_revision bigint;
begin
  if public.current_pdc_user_role() not in ('importer', 'administrator') then
    raise exception 'PDC role importer required' using errcode = '42501';
  end if;

  perform 1 from public.vehicles where id = p_vehicle_id;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;

  select * into v_previous
  from public.vehicle_eta_history
  where vehicle_id = p_vehicle_id
    and eta_type = p_eta_type
    and superseded_by is null
  order by created_at desc
  limit 1
  for update;

  insert into public.vehicle_eta_history (
    vehicle_id,
    source_intake_id,
    source_timeline_event_id,
    eta_type,
    eta_value,
    eta_value_text,
    eta_state,
    confidence,
    original_wording,
    source_label,
    supplier_name,
    received_at,
    previous_eta_id,
    created_by
  ) values (
    p_vehicle_id,
    p_source_intake_id,
    p_source_timeline_event_id,
    p_eta_type,
    p_eta_value,
    p_eta_value_text,
    p_eta_state,
    p_confidence,
    p_original_wording,
    p_source_label,
    p_supplier_name,
    p_received_at,
    v_previous.id,
    auth.uid()
  ) returning * into v_row;

  if v_previous.id is not null then
    update public.vehicle_eta_history
    set superseded_by = v_row.id
    where id = v_previous.id;
  end if;

  v_revision := public.bump_vehicle_intelligence_revision(p_vehicle_id);
  perform public.rebuild_vehicle_intelligence_summary(p_vehicle_id);

  perform public.audit_pdc_event(
    'update',
    'vehicle_eta_history',
    v_row.id,
    p_vehicle_id,
    case when v_previous.id is null then null else to_jsonb(v_previous) end,
    to_jsonb(v_row),
    jsonb_build_object('vehicle_intelligence_revision', v_revision)
  );

  return v_row;
end;
$$;

create or replace function public.create_ai_review_item(
  p_intake_id uuid,
  p_analysis_result_id uuid,
  p_primary_vehicle_id uuid default null,
  p_candidate_vehicle_ids uuid[] default '{}',
  p_proposed_action_ids uuid[] default '{}',
  p_review_reason text default 'manual_review_required',
  p_review_payload jsonb default '{}'::jsonb,
  p_proposed_changes jsonb default '{}'::jsonb
)
returns public.ai_review_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.ai_review_items%rowtype;
begin
  if public.current_pdc_user_role() not in ('importer', 'administrator') then
    raise exception 'PDC role importer required' using errcode = '42501';
  end if;

  insert into public.ai_review_items (
    intake_id,
    analysis_result_id,
    primary_vehicle_id,
    status,
    review_reason,
    review_payload,
    proposed_changes,
    proposed_action_ids,
    candidate_vehicle_ids,
    created_by,
    updated_by
  ) values (
    p_intake_id,
    p_analysis_result_id,
    p_primary_vehicle_id,
    'pending',
    p_review_reason,
    coalesce(p_review_payload, '{}'::jsonb),
    coalesce(p_proposed_changes, '{}'::jsonb),
    coalesce(p_proposed_action_ids, '{}'),
    coalesce(p_candidate_vehicle_ids, '{}'),
    auth.uid(),
    auth.uid()
  ) returning * into v_row;

  perform public.audit_pdc_event(
    'insert',
    'ai_review_items',
    v_row.id,
    p_primary_vehicle_id,
    null,
    to_jsonb(v_row),
    jsonb_build_object('source', 'vehicle_intelligence_review')
  );

  return v_row;
end;
$$;

create or replace function public.approve_ai_review_item(
  p_review_item_id uuid,
  p_selected_vehicle_id uuid default null,
  p_selected_action_ids uuid[] default null,
  p_decision_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.ai_review_items%rowtype;
  v_after public.ai_review_items%rowtype;
  v_vehicle_id uuid;
  v_status public.ai_review_decision_status;
  v_revision bigint := null;
begin
  perform public.require_pdc_role('operator');

  select * into v_before
  from public.ai_review_items
  where id = p_review_item_id
  for update;

  if not found then
    raise exception 'Review item not found' using errcode = 'P0002';
  end if;

  if v_before.status <> 'pending' then
    raise exception 'Review item is not pending' using errcode = 'P0001';
  end if;

  v_vehicle_id := coalesce(p_selected_vehicle_id, v_before.selected_vehicle_id, v_before.primary_vehicle_id);
  v_status := case
    when p_selected_action_ids is not null
         and cardinality(p_selected_action_ids) > 0
         and cardinality(p_selected_action_ids) < cardinality(v_before.proposed_action_ids)
      then 'partially_approved'::public.ai_review_decision_status
    else 'approved'::public.ai_review_decision_status
  end;

  update public.ai_review_items
  set selected_vehicle_id = v_vehicle_id,
      status = v_status,
      decision_notes = coalesce(p_decision_notes, decision_notes),
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      updated_by = auth.uid(),
      version = version + 1,
      approval_metadata = approval_metadata || jsonb_build_object(
        'selectedActionIds', coalesce(to_jsonb(p_selected_action_ids), 'null'::jsonb),
        'decisionType', v_status::text
      )
  where id = p_review_item_id
  returning * into v_after;

  if cardinality(v_before.proposed_action_ids) > 0 then
    if p_selected_action_ids is null then
      update public.ai_proposed_actions
      set status = 'approved',
          approved_by = auth.uid(),
          approved_at = now(),
          updated_at = now()
      where id = any(v_before.proposed_action_ids);
    else
      update public.ai_proposed_actions
      set status = case when id = any(p_selected_action_ids)
                        then 'approved'::public.ai_proposed_action_status
                        else 'superseded'::public.ai_proposed_action_status
                   end,
          approved_by = case when id = any(p_selected_action_ids) then auth.uid() else approved_by end,
          approved_at = case when id = any(p_selected_action_ids) then now() else approved_at end,
          updated_at = now()
      where id = any(v_before.proposed_action_ids);
    end if;
  end if;

  perform public.audit_pdc_event(
    'update',
    'ai_review_items',
    v_after.id,
    v_vehicle_id,
    to_jsonb(v_before),
    to_jsonb(v_after),
    jsonb_build_object('decision', v_status)
  );

  if v_vehicle_id is not null then
    perform public.append_vehicle_timeline_event(
      p_vehicle_id => v_vehicle_id,
      p_event_type => 'ai_review_approved',
      p_source_kind => 'ai',
      p_event_state => 'manual',
      p_ai_summary => coalesce(p_decision_notes, 'AI review approved'),
      p_structured_data => jsonb_build_object('reviewItemId', v_after.id, 'status', v_status),
      p_review_item_id => v_after.id,
      p_approval_status => v_status::text,
      p_automatic_update => false,
      p_confidence_label => 'review_recommended'
    );

    select revision into v_revision
    from public.vehicle_intelligence_revisions
    where vehicle_id = v_vehicle_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'review_item_id', v_after.id,
    'status', v_after.status,
    'vehicle_id', v_vehicle_id,
    'revision', v_revision
  );
end;
$$;

create or replace function public.reject_ai_review_item(
  p_review_item_id uuid,
  p_reason text default null,
  p_mark_irrelevant boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.ai_review_items%rowtype;
  v_after public.ai_review_items%rowtype;
  v_vehicle_id uuid;
  v_revision bigint := null;
begin
  perform public.require_pdc_role('operator');

  select * into v_before
  from public.ai_review_items
  where id = p_review_item_id
  for update;

  if not found then
    raise exception 'Review item not found' using errcode = 'P0002';
  end if;

  if v_before.status <> 'pending' then
    raise exception 'Review item is not pending' using errcode = 'P0001';
  end if;

  v_vehicle_id := coalesce(v_before.selected_vehicle_id, v_before.primary_vehicle_id);

  update public.ai_review_items
  set status = case when p_mark_irrelevant
                    then 'irrelevant'::public.ai_review_decision_status
                    else 'rejected'::public.ai_review_decision_status
               end,
      decision_notes = coalesce(p_reason, decision_notes),
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      updated_by = auth.uid(),
      version = version + 1
  where id = p_review_item_id
  returning * into v_after;

  if cardinality(v_before.proposed_action_ids) > 0 then
    update public.ai_proposed_actions
    set status = 'rejected',
        updated_at = now()
    where id = any(v_before.proposed_action_ids);
  end if;

  perform public.audit_pdc_event(
    'update',
    'ai_review_items',
    v_after.id,
    v_vehicle_id,
    to_jsonb(v_before),
    to_jsonb(v_after),
    jsonb_build_object('decision', v_after.status)
  );

  if v_vehicle_id is not null then
    perform public.append_vehicle_timeline_event(
      p_vehicle_id => v_vehicle_id,
      p_event_type => case when p_mark_irrelevant then 'ai_review_marked_irrelevant' else 'ai_review_rejected' end,
      p_source_kind => 'ai',
      p_event_state => 'manual',
      p_ai_summary => coalesce(p_reason, 'AI review rejected'),
      p_structured_data => jsonb_build_object('reviewItemId', v_after.id, 'status', v_after.status),
      p_review_item_id => v_after.id,
      p_approval_status => v_after.status::text,
      p_automatic_update => false,
      p_confidence_label => 'review_recommended'
    );

    select revision into v_revision
    from public.vehicle_intelligence_revisions
    where vehicle_id = v_vehicle_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'review_item_id', v_after.id,
    'status', v_after.status,
    'vehicle_id', v_vehicle_id,
    'revision', v_revision
  );
end;
$$;

create or replace function public.list_ai_review_queue(p_status text default 'pending')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
begin
  perform public.require_pdc_role('operator');

  select coalesce(jsonb_agg(jsonb_build_object(
    'reviewItemId', r.id,
    'status', r.status,
    'reviewReason', r.review_reason,
    'intakeId', r.intake_id,
    'analysisResultId', r.analysis_result_id,
    'vehicleId', coalesce(r.selected_vehicle_id, r.primary_vehicle_id),
    'candidateVehicleIds', r.candidate_vehicle_ids,
    'proposedActionIds', r.proposed_action_ids,
    'proposedChanges', r.proposed_changes,
    'decisionNotes', r.decision_notes,
    'createdAt', r.created_at,
    'subject', i.subject,
    'senderEmail', i.sender_email,
    'receivedAt', i.received_at,
    'mailbox', coalesce(i.recipient_mailbox, m.mailbox_address),
    'confidenceLabel', a.confidence_label,
    'vehicleMatchConfidence', a.vehicle_match_confidence,
    'relevanceConfidence', a.relevance_confidence,
    'classificationConfidence', a.classification_confidence,
    'actionConfidence', a.action_confidence,
    'classifications', a.classifications,
    'warnings', a.warnings
  ) order by r.created_at desc), '[]'::jsonb)
  into v_rows
  from public.ai_review_items r
  left join public.ai_email_intake i on i.id = r.intake_id
  left join public.monitored_mailboxes m on m.id = i.monitored_mailbox_id
  left join public.ai_email_analysis_results a on a.id = r.analysis_result_id
  where p_status is null or r.status::text = p_status;

  return v_rows;
end;
$$;

create or replace function public.get_vehicle_intelligence_snapshot(
  p_vehicle_id uuid,
  p_sort text default 'desc',
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
  perform public.require_pdc_role('viewer');

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
$$;

revoke all on function public.bump_vehicle_intelligence_revision(uuid) from public, anon;
revoke all on function public.rebuild_vehicle_intelligence_summary(uuid) from public, anon;
revoke all on function public.append_vehicle_timeline_event(uuid, text, timestamptz, public.vehicle_timeline_source_kind, public.vehicle_timeline_event_state, text, text, jsonb, text, text, text, text, text, text, text, text, text, numeric, numeric, numeric, numeric, text, boolean, jsonb, jsonb, text, text, uuid, uuid, uuid, uuid, uuid) from public, anon;
revoke all on function public.record_vehicle_eta_history(uuid, text, date, text, public.vehicle_timeline_event_state, numeric, text, text, text, timestamptz, uuid, uuid) from public, anon;
revoke all on function public.create_ai_review_item(uuid, uuid, uuid, uuid[], uuid[], text, jsonb, jsonb) from public, anon;
revoke all on function public.approve_ai_review_item(uuid, uuid, uuid[], text) from public, anon;
revoke all on function public.reject_ai_review_item(uuid, text, boolean) from public, anon;
revoke all on function public.list_ai_review_queue(text) from public, anon;
revoke all on function public.get_vehicle_intelligence_snapshot(uuid, text, integer) from public, anon;

grant execute on function public.rebuild_vehicle_intelligence_summary(uuid) to authenticated;
grant execute on function public.append_vehicle_timeline_event(uuid, text, timestamptz, public.vehicle_timeline_source_kind, public.vehicle_timeline_event_state, text, text, jsonb, text, text, text, text, text, text, text, text, text, numeric, numeric, numeric, numeric, text, boolean, jsonb, jsonb, text, text, uuid, uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.record_vehicle_eta_history(uuid, text, date, text, public.vehicle_timeline_event_state, numeric, text, text, text, timestamptz, uuid, uuid) to authenticated;
grant execute on function public.create_ai_review_item(uuid, uuid, uuid, uuid[], uuid[], text, jsonb, jsonb) to authenticated;
grant execute on function public.approve_ai_review_item(uuid, uuid, uuid[], text) to authenticated;
grant execute on function public.reject_ai_review_item(uuid, text, boolean) to authenticated;
grant execute on function public.list_ai_review_queue(text) to authenticated;
grant execute on function public.get_vehicle_intelligence_snapshot(uuid, text, integer) to authenticated;

commit;
