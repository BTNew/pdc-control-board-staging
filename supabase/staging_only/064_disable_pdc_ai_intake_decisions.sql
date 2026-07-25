-- Staging-only containment migration 064.
-- Disable AI Intake decisions after the late independent review found the
-- provider-authenticated email and durable human-approval receipt chain incomplete.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if exists (
    select 1 from public.pdc_ai_intake_proposals
    where status <> 'pending' or decided_at is not null
  ) then
    raise exception 'PDC_AI_INTAKE_CONTAINMENT_REQUIRES_DECISION_INVENTORY';
  end if;
end;
$guard$;

revoke all on function public.decide_pdc_ai_intake_proposal(uuid,bigint,text,text,text)
from public, anon, authenticated;
drop function public.decide_pdc_ai_intake_proposal(uuid,bigint,text,text,text);

-- Keep authenticated monitor observations proposal-only. Restrict all inbox
-- reads and realtime revision visibility to an exact active Administrator.
drop policy if exists pdc_ai_intake_revision_staff_read on public.pdc_ai_intake_revision;
create policy pdc_ai_intake_revision_admin_read on public.pdc_ai_intake_revision
for select to authenticated
using (public.current_pdc_user_role()::text = 'administrator');

create or replace function public.get_pdc_ai_intake_snapshot(
  p_status text default 'pending',
  p_page_size integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $snapshot$
declare
  v_role text := public.current_pdc_user_role()::text;
  v_status text := lower(btrim(coalesce(p_status,'pending')));
  v_limit integer := greatest(1,least(coalesce(p_page_size,100),250));
  v_revision bigint;
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
  select coalesce(jsonb_agg(to_jsonb(x) order by x.source_received_at desc,x.proposal_id desc),'[]'::jsonb)
  into v_items from (
    select p.proposal_id,p.source_uid,p.sender_address,p.source_received_at,p.subject,
      p.action_type,p.stock_number,p.backend_record_id,p.backend_record_version,
      p.observed_navision_revision,p.summary,p.observations,p.fingerprint,p.status,
      p.version,p.submitted_at,p.decided_by_email,p.decided_at,p.decision_reason,p.result,
      r.normalized_data->>'vehicle' as authoritative_vehicle,
      r.normalized_data->>'dealerCustomerName' as authoritative_customer,
      r.normalized_data->>'navisionLocationStatus' as authoritative_location
    from public.pdc_ai_intake_proposals p
    left join public.navision_backend_records r on r.id=p.backend_record_id
    where v_status='all' or p.status=v_status
    order by p.source_received_at desc,p.proposal_id desc limit v_limit
  ) x;
  select coalesce(jsonb_agg(to_jsonb(h) order by h.event_at desc,h.history_id desc),'[]'::jsonb)
  into v_history from (
    select history_id,proposal_id,event_type,event_at,actor_email,proposal_version,
      fingerprint,stock_number,action_type,details
    from public.pdc_ai_intake_history
    order by event_at desc,history_id desc limit v_limit
  ) h;
  return public.navision_backend_response(true,'snapshot',jsonb_build_object(
    'revision',v_revision,'items',v_items,'history',v_history));
end;
$snapshot$;

revoke all on function public.get_pdc_ai_intake_snapshot(text,integer)
from public, anon, authenticated;
grant execute on function public.get_pdc_ai_intake_snapshot(text,integer) to authenticated;

commit;
