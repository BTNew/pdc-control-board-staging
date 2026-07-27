-- 071_human_ai_intake_change_summary.sql
-- Staging-only, read-only presentation data for the Administrator AI Intake screen.
-- Preserves the authenticated monitor guard and current role authority from 066.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('public.pdc_ai_intake_proposals') is null
     or to_regclass('public.pdc_ai_intake_history') is null
     or to_regclass('public.audit_events') is null
     or to_regclass('public.navision_backend_audit') is null
     or to_regprocedure('public.current_pdc_user_role()') is null
     or to_regprocedure('public.pdc_monitor_staging_guard()') is null then
    raise exception 'PDC_MIGRATION_071_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create or replace function public.get_pdc_ai_intake_snapshot(
  p_status text default 'pending',
  p_page_size integer default 100
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare
  v_role text := public.current_pdc_user_role()::text;
  v_status text := lower(btrim(coalesce(p_status,'pending')));
  v_limit integer := greatest(1,least(coalesce(p_page_size,100),250));
  v_revision bigint;
  v_navision_revision bigint;
  v_items jsonb;
  v_history jsonb;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if auth.uid() is null or v_role is distinct from 'administrator' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if v_status not in ('pending','applied','rejected','all') then
    return public.navision_backend_response(false,'invalid_status');
  end if;

  select revision into v_revision from public.pdc_ai_intake_revision where singleton;
  select revision into v_navision_revision from public.navision_backend_revision where singleton;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.source_received_at desc,x.proposal_id desc),'[]'::jsonb)
  into v_items
  from (
    select
      p.proposal_id,p.source_uid,p.sender_address,p.source_received_at,p.subject,
      p.action_type,p.stock_number,p.backend_record_id,p.backend_record_version,
      p.observed_navision_revision,p.summary,p.observations,p.fingerprint,p.status,
      p.version,p.submitted_at,p.decided_by_email,p.decided_at,p.decision_reason,p.result,
      r.normalized_data->>'vehicle' as authoritative_vehicle,
      r.normalized_data->>'dealercustomername' as authoritative_customer,
      r.normalized_data->>'navisionlocationstatus' as authoritative_location,
      coalesce(changes.change_events,'[]'::jsonb) as change_events,
      coalesce(board.board_activation_created,false) as board_activation_created
    from public.pdc_ai_intake_proposals p
    left join public.navision_backend_records r on r.id=p.backend_record_id
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'table_name',a.table_name,
          'action',a.action::text,
          'before_data',case a.table_name
            when 'vehicles' then jsonb_build_object(
              'stock_number',a.before_data->'stock_number',
              'customer_name',a.before_data->'customer_name',
              'make',a.before_data->'make',
              'model',a.before_data->'model',
              'vehicle_description',a.before_data->'vehicle_description',
              'current_location',a.before_data->'current_location',
              'registration',a.before_data->'registration',
              'vin',a.before_data->'vin',
              'toyota_order_number',a.before_data->'toyota_order_number',
              'job_card_number',a.before_data->'job_card_number',
              'key_number',a.before_data->'key_number',
              'salesperson_reference',a.before_data->'salesperson_reference',
              'arrival_reference_date',a.before_data->'arrival_reference_date',
              'eta_to_kewdale',a.before_data->'eta_to_kewdale',
              'visible_on_board',a.before_data->'visible_on_board'
            )
            when 'vehicle_work_items' then jsonb_build_object(
              'work_key',a.before_data->'work_key',
              'required',a.before_data->'required',
              'status',a.before_data->'status'
            )
            when 'vehicle_parts_updates' then jsonb_build_object(
              'parts_required',a.before_data->'parts_required',
              'issued',a.before_data->'issued',
              'incomplete',a.before_data->'incomplete'
            )
            else '{}'::jsonb
          end,
          'after_data',case a.table_name
            when 'vehicles' then jsonb_build_object(
              'stock_number',a.after_data->'stock_number',
              'customer_name',a.after_data->'customer_name',
              'make',a.after_data->'make',
              'model',a.after_data->'model',
              'vehicle_description',a.after_data->'vehicle_description',
              'current_location',a.after_data->'current_location',
              'registration',a.after_data->'registration',
              'vin',a.after_data->'vin',
              'toyota_order_number',a.after_data->'toyota_order_number',
              'job_card_number',a.after_data->'job_card_number',
              'key_number',a.after_data->'key_number',
              'salesperson_reference',a.after_data->'salesperson_reference',
              'arrival_reference_date',a.after_data->'arrival_reference_date',
              'eta_to_kewdale',a.after_data->'eta_to_kewdale',
              'visible_on_board',a.after_data->'visible_on_board'
            )
            when 'vehicle_work_items' then jsonb_build_object(
              'work_key',a.after_data->'work_key',
              'required',a.after_data->'required',
              'status',a.after_data->'status'
            )
            when 'vehicle_parts_updates' then jsonb_build_object(
              'parts_required',a.after_data->'parts_required',
              'issued',a.after_data->'issued',
              'incomplete',a.after_data->'incomplete'
            )
            else '{}'::jsonb
          end,
          'created_at',a.created_at
        ) order by a.created_at,a.id
      ) as change_events
      from public.audit_events a
      where a.metadata->>'source_hash'=p.source_hash
        and a.table_name in ('vehicles','vehicle_work_items','vehicle_parts_updates')
    ) changes on true
    left join lateral (
      select exists(
        select 1
        from public.navision_backend_audit n
        where n.action='board_activate'
          and n.evidence->>'source_hash'=p.source_hash
      ) as board_activation_created
    ) board on true
    where v_status='all' or p.status=v_status
    order by p.source_received_at desc,p.proposal_id desc
    limit v_limit
  ) x;

  select coalesce(jsonb_agg(to_jsonb(h) order by h.event_at desc,h.history_id desc),'[]'::jsonb)
  into v_history
  from (
    select history_id,proposal_id,event_type,event_at,actor_email,proposal_version,
      fingerprint,stock_number,action_type,details
    from public.pdc_ai_intake_history
    order by event_at desc,history_id desc
    limit v_limit
  ) h;

  return public.navision_backend_response(true,'snapshot',jsonb_build_object(
    'revision',v_revision,
    'navision_revision',v_navision_revision,
    'items',v_items,
    'history',v_history
  ));
end;
$$;

revoke all on function public.get_pdc_ai_intake_snapshot(text,integer) from public;
grant execute on function public.get_pdc_ai_intake_snapshot(text,integer) to authenticated;

commit;
