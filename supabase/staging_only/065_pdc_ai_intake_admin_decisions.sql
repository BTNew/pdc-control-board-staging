-- Staging-only migration 065.
-- Re-enable a narrowly typed Administrator decision path. Email fields remain
-- informational evidence; only the authenticated Administrator decision and
-- live server identity/revision checks authorize board activation.
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
  if to_regprocedure('public.decide_pdc_ai_intake_proposal(uuid,bigint,text,text,text)') is not null then
    raise exception 'PDC_AI_INTAKE_064_CONTAINMENT_NOT_ACTIVE';
  end if;
end;
$guard$;

create table if not exists public.pdc_ai_intake_decision_receipts (
  receipt_id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  idempotency_key text not null,
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  proposal_id uuid not null references public.pdc_ai_intake_proposals(proposal_id) on delete restrict,
  proposal_version bigint not null check (proposal_version >= 1),
  expected_inbox_revision bigint not null check (expected_inbox_revision >= 1),
  expected_action text not null check (expected_action in ('board_activate_only','review_only')),
  decision text not null check (decision in ('apply','reject')),
  expected_navision_revision bigint,
  fingerprint text not null check (fingerprint ~ '^[A-F0-9]{16}$'),
  reason text not null check (length(reason) between 10 and 500),
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(actor_id,idempotency_key)
);

alter table public.pdc_ai_intake_decision_receipts enable row level security;
revoke all on table public.pdc_ai_intake_decision_receipts from public,anon,authenticated;

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
  into v_items from (
    select p.proposal_id,p.source_uid,p.sender_address,p.source_received_at,p.subject,
      p.action_type,p.stock_number,p.backend_record_id,p.backend_record_version,
      p.observed_navision_revision,p.summary,p.observations,p.fingerprint,p.status,
      p.version,p.submitted_at,p.decided_by_email,p.decided_at,p.decision_reason,p.result,
      r.normalized_data->>'vehicle' as authoritative_vehicle,
      r.normalized_data->>'dealercustomername' as authoritative_customer,
      r.normalized_data->>'navisionlocationstatus' as authoritative_location
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
    'revision',v_revision,'navision_revision',v_navision_revision,'items',v_items,'history',v_history));
end;
$snapshot$;

revoke all on function public.get_pdc_ai_intake_snapshot(text,integer) from public,anon,authenticated;
grant execute on function public.get_pdc_ai_intake_snapshot(text,integer) to authenticated;

create or replace function public.decide_pdc_ai_intake_proposal(
  p_idempotency_key text,
  p_proposal_id uuid,
  p_expected_version bigint,
  p_expected_inbox_revision bigint,
  p_expected_action text,
  p_decision text,
  p_fingerprint text,
  p_expected_navision_revision bigint,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $decide$
declare
  v_user_id uuid := auth.uid();
  v_actor_email text := lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text;
  v_key text := btrim(coalesce(p_idempotency_key,''));
  v_action text := lower(btrim(coalesce(p_expected_action,'')));
  v_decision text := lower(btrim(coalesce(p_decision,'')));
  v_fingerprint text := upper(btrim(coalesce(p_fingerprint,'')));
  v_reason text := btrim(coalesce(p_reason,''));
  v_request_hash text;
  v_receipt public.pdc_ai_intake_decision_receipts%rowtype;
  v_proposal public.pdc_ai_intake_proposals%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_inbox_revision bigint;
  v_stock_ids uuid[] := '{}'::uuid[];
  v_navision_revision bigint;
  v_activation public.navision_board_activations%rowtype;
  v_activation_response jsonb;
  v_response jsonb;
  v_next_status text;
  v_next_inbox_revision bigint;
  v_result_navision_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_user_id is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select r.role::text into v_role
  from public.pdc_user_roles r
  where r.email=v_actor_email and r.auth_user_id=v_user_id
    and r.active and r.account_status='approved'
  for share;
  if v_role is distinct from 'administrator' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if v_key !~ '^pdc-ai-intake-[a-zA-Z0-9_-]{16,160}$'
     or p_proposal_id is null
     or p_expected_version is null or p_expected_version<1
     or p_expected_inbox_revision is null or p_expected_inbox_revision<1
     or v_action not in ('board_activate_only','review_only')
     or v_decision not in ('apply','reject')
     or v_fingerprint !~ '^[A-F0-9]{16}$'
     or length(v_reason)<10 or length(v_reason)>500
     or (v_decision='apply' and (v_action<>'board_activate_only' or p_expected_navision_revision is null or p_expected_navision_revision<1)) then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  v_request_hash:=encode(extensions.digest(jsonb_build_object(
    'contract_version',2,'actor_id',v_user_id,'idempotency_key',v_key,
    'proposal_id',p_proposal_id,'expected_version',p_expected_version,
    'expected_inbox_revision',p_expected_inbox_revision,'expected_action',v_action,
    'decision',v_decision,'fingerprint',v_fingerprint,
    'expected_navision_revision',p_expected_navision_revision,'reason',v_reason
  )::text,'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-receipt:'||v_user_id::text||':'||v_key,0));
  select * into v_receipt from public.pdc_ai_intake_decision_receipts
  where actor_id=v_user_id and idempotency_key=v_key;
  if found then
    if v_receipt.request_hash<>v_request_hash then
      return public.navision_backend_response(false,'idempotency_conflict');
    end if;
    return v_receipt.response;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-decision:'||p_proposal_id::text,0));
  select revision into v_inbox_revision from public.pdc_ai_intake_revision
  where singleton for update;
  if v_inbox_revision<>p_expected_inbox_revision then
    return public.navision_backend_response(false,'stale_inbox_revision',jsonb_build_object('current_revision',v_inbox_revision));
  end if;
  select * into v_proposal from public.pdc_ai_intake_proposals
  where proposal_id=p_proposal_id for update;
  if not found then return public.navision_backend_response(false,'proposal_not_found'); end if;
  if v_proposal.status<>'pending' then
    return public.navision_backend_response(false,'proposal_consumed',jsonb_build_object('status',v_proposal.status,'version',v_proposal.version));
  end if;
  if v_proposal.version<>p_expected_version
     or v_proposal.fingerprint<>v_fingerprint
     or v_proposal.action_type<>v_action then
    return public.navision_backend_response(false,'proposal_changed',jsonb_build_object(
      'current_version',v_proposal.version,'current_fingerprint',v_proposal.fingerprint,
      'current_action',v_proposal.action_type));
  end if;

  if v_decision='reject' then
    v_next_status:='rejected';
    v_result_navision_revision:=null;
  else
    if v_proposal.submitted_at < clock_timestamp()-interval '14 days'
       or v_proposal.source_received_at < clock_timestamp()-interval '30 days' then
      return public.navision_backend_response(false,'proposal_expired');
    end if;
    if (jsonb_typeof(v_proposal.observations->'conflicts')='array'
        and jsonb_array_length(v_proposal.observations->'conflicts')>0)
       or concat_ws(' ',v_proposal.subject,v_proposal.summary) ~* '\m(cancelled|canceled|cancellation)\M' then
      return public.navision_backend_response(false,'proposal_conflicted_or_cancelled');
    end if;
    perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
    select revision into v_navision_revision from public.navision_backend_revision
    where singleton for update;
    if v_navision_revision<>p_expected_navision_revision then
      return public.navision_backend_response(false,'stale_navision_revision',jsonb_build_object('current_revision',v_navision_revision));
    end if;
    select * into v_record from public.navision_backend_records
    where id=v_proposal.backend_record_id for update;
    if not found or not v_record.is_current or v_record.record_status<>'current'
       or v_record.version<>v_proposal.backend_record_version then
      return public.navision_backend_response(false,'record_changed');
    end if;
    select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_stock_ids
    from public.navision_backend_records r
    where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
      and r.is_current and r.record_status='current'
      and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
      and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_proposal.stock_number;
    if cardinality(v_stock_ids)<>1 or v_stock_ids[1]<>v_proposal.backend_record_id then
      return public.navision_backend_response(false,'identity_conflict');
    end if;
    if public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch')<>v_proposal.stock_number then
      return public.navision_backend_response(false,'identity_conflict');
    end if;
    -- Keep the negative operational-identity check true through activation
    -- commit. The table locks cover canonical restore/lifecycle writers; the
    -- normalized Stock advisory lock joins the identity-trigger namespace.
    lock table public.vehicles, public.vehicle_aliases in share row exclusive mode;
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:stock_number:' || v_proposal.stock_number, 0
    ));
    if exists(
      select 1 from public.vehicles v where v.stock_number_normalized=v_proposal.stock_number and v.deleted_at is null
      union all
      select 1 from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_proposal.stock_number
    ) then
      return public.navision_backend_response(false,'operational_identity_present');
    end if;
    select * into v_activation from public.navision_board_activations
    where backend_record_id=v_proposal.backend_record_id for update;
    if found then
      if public.normalize_vehicle_stock_number(v_activation.activated_stock_number)<>v_proposal.stock_number then
        return public.navision_backend_response(false,'activation_identity_conflict');
      end if;
      return public.navision_backend_response(false,'already_active');
    end if;
    if exists(
      select 1 from public.navision_board_activations a
      where a.backend_record_id<>v_proposal.backend_record_id
        and public.normalize_vehicle_stock_number(a.activated_stock_number)=v_proposal.stock_number
    ) then
      return public.navision_backend_response(false,'activation_identity_conflict');
    end if;

    v_activation_response:=public.activate_navision_backend_record(
      'ai-intake:'||p_proposal_id::text,
      v_proposal.backend_record_id,
      p_expected_navision_revision,
      'approved_email_build'
    );
    if not coalesce((v_activation_response->>'ok')::boolean,false)
       or v_activation_response->>'code'<>'board_activated' then
      return public.navision_backend_response(false,'activation_failed',jsonb_build_object('activation',v_activation_response));
    end if;
    v_result_navision_revision:=coalesce((v_activation_response->'data'->>'result_revision')::bigint,p_expected_navision_revision);
    v_next_status:='applied';
  end if;

  v_next_inbox_revision:=v_inbox_revision+1;
  v_response:=public.navision_backend_response(true,v_next_status,jsonb_build_object(
    'proposal_id',v_proposal.proposal_id,'proposal_version',v_proposal.version+1,
    'inbox_revision',v_next_inbox_revision,'navision_revision',v_result_navision_revision,
    'action_type',v_proposal.action_type,'decision',v_decision,
    'fingerprint',v_proposal.fingerprint,'stock_number',v_proposal.stock_number,
    'vehicle_mutated',v_decision='apply','board_activation_only',v_decision='apply'));

  update public.pdc_ai_intake_proposals set
    status=v_next_status,version=version+1,decided_by=v_user_id,
    decided_by_email=v_actor_email,decided_at=clock_timestamp(),
    decision_reason=v_reason,result=v_response
  where proposal_id=v_proposal.proposal_id;
  insert into public.pdc_ai_intake_history(
    proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
    stock_number,action_type,details
  ) values(
    v_proposal.proposal_id,v_next_status,v_user_id,v_actor_email,v_proposal.version+1,
    v_proposal.fingerprint,v_proposal.stock_number,v_proposal.action_type,
    jsonb_build_object('reason',v_reason,'result',v_response,'email_evidence_authoritative',false,
      'authorization_basis','authenticated_administrator_decision_and_live_server_identity')
  );
  update public.pdc_ai_intake_revision set
    revision=v_next_inbox_revision,updated_at=clock_timestamp()
  where singleton;
  insert into public.pdc_ai_intake_decision_receipts(
    actor_id,idempotency_key,request_hash,proposal_id,proposal_version,
    expected_inbox_revision,expected_action,decision,expected_navision_revision,
    fingerprint,reason,response
  ) values(
    v_user_id,v_key,v_request_hash,v_proposal.proposal_id,p_expected_version,
    p_expected_inbox_revision,v_action,v_decision,p_expected_navision_revision,
    v_fingerprint,v_reason,v_response
  );
  return v_response;
end;
$decide$;

revoke all on function public.decide_pdc_ai_intake_proposal(text,uuid,bigint,bigint,text,text,text,bigint,text)
from public,anon,authenticated;
grant execute on function public.decide_pdc_ai_intake_proposal(text,uuid,bigint,bigint,text,text,text,bigint,text)
to authenticated;

commit;
