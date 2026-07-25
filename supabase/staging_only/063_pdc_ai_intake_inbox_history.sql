-- Staging-only migration 063: server-authoritative PMB inbox observations,
-- proposal decisions, and durable AI Intake history.
--
-- The enrolled PMB monitor may submit immutable observations only. It cannot
-- mutate vehicles. Authenticated administrators may apply the one supported
-- typed adjustment (board_activate_only) or reject a proposal from the website.
-- All other email findings remain review_only.

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
  if to_regclass('public.pdc_monitor_stage_activation_writers') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_board_activations') is null
     or to_regclass('public.navision_backend_revision') is null then
    raise exception 'PDC_MIGRATION_063_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create table if not exists public.pdc_ai_intake_proposals (
  proposal_id uuid primary key default gen_random_uuid(),
  dedupe_key text not null unique,
  source_hash text not null,
  evidence_hash text not null,
  source_uid text not null,
  sender_address text not null,
  authentication jsonb not null,
  source_received_at timestamptz not null,
  subject text not null,
  action_type text not null check (action_type in ('board_activate_only','review_only')),
  stock_number text,
  backend_record_id uuid references public.navision_backend_records(id) on delete restrict,
  backend_record_version bigint,
  observed_navision_revision bigint,
  summary text not null,
  observations jsonb not null default '{}'::jsonb,
  fingerprint text not null unique,
  status text not null default 'pending' check (status in ('pending','applied','rejected')),
  version bigint not null default 1 check (version >= 1),
  submitted_by uuid not null references auth.users(id) on delete restrict,
  submitted_at timestamptz not null default clock_timestamp(),
  decided_by uuid references auth.users(id) on delete restrict,
  decided_by_email text,
  decided_at timestamptz,
  decision_reason text,
  result jsonb,
  check (source_hash ~ '^[a-f0-9]{64}$'),
  check (evidence_hash ~ '^[a-f0-9]{64}$'),
  check (fingerprint ~ '^[A-F0-9]{16}$'),
  check (sender_address = lower(sender_address)),
  check (jsonb_typeof(authentication) = 'object'),
  check (jsonb_typeof(observations) = 'object'),
  check (
    (action_type = 'board_activate_only' and stock_number is not null and backend_record_id is not null and backend_record_version is not null)
    or action_type = 'review_only'
  ),
  check (
    (status = 'pending' and decided_by is null and decided_at is null and decision_reason is null and result is null)
    or (status in ('applied','rejected') and decided_by is not null and decided_at is not null and decision_reason is not null and result is not null)
  )
);

create table if not exists public.pdc_email_source_claims (
  source_hash text primary key check (source_hash ~ '^[a-f0-9]{64}$'),
  contract_name text not null check (contract_name in ('pdc_stage_activation_060','pdc_ai_intake_063')),
  proposal_ref text not null,
  claimed_at timestamptz not null default clock_timestamp()
);

create index if not exists pdc_ai_intake_proposals_status_received_idx
  on public.pdc_ai_intake_proposals(status, source_received_at desc, proposal_id desc);
create index if not exists pdc_ai_intake_proposals_stock_idx
  on public.pdc_ai_intake_proposals(stock_number) where stock_number is not null;

create table if not exists public.pdc_ai_intake_history (
  history_id bigint generated always as identity primary key,
  proposal_id uuid not null references public.pdc_ai_intake_proposals(proposal_id) on delete restrict,
  event_type text not null check (event_type in ('noticed','applied','rejected')),
  event_at timestamptz not null default clock_timestamp(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text,
  proposal_version bigint not null check (proposal_version >= 1),
  fingerprint text not null,
  stock_number text,
  action_type text not null,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object')
);
create index if not exists pdc_ai_intake_history_event_idx
  on public.pdc_ai_intake_history(event_at desc, history_id desc);

create table if not exists public.pdc_ai_intake_revision (
  singleton boolean primary key default true check (singleton),
  revision bigint not null default 1 check (revision >= 1),
  updated_at timestamptz not null default clock_timestamp()
);
insert into public.pdc_ai_intake_revision(singleton, revision)
values(true, 1) on conflict(singleton) do nothing;

alter table public.pdc_ai_intake_proposals enable row level security;
alter table public.pdc_ai_intake_history enable row level security;
alter table public.pdc_ai_intake_revision enable row level security;
alter table public.pdc_email_source_claims enable row level security;
revoke all on table public.pdc_ai_intake_proposals from public, anon, authenticated;
revoke all on table public.pdc_ai_intake_history from public, anon, authenticated;
revoke all on table public.pdc_ai_intake_revision from public, anon, authenticated;
revoke all on table public.pdc_email_source_claims from public, anon, authenticated;
grant select on table public.pdc_ai_intake_revision to authenticated;

create or replace function public.pdc_claim_legacy_stage_activation_source()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $claim$
begin
  insert into public.pdc_email_source_claims(source_hash,contract_name,proposal_ref)
  values(new.source_hash,'pdc_stage_activation_060',new.proposal_id)
  on conflict(source_hash) do nothing;
  if not found and not exists(
    select 1 from public.pdc_email_source_claims c
    where c.source_hash=new.source_hash and c.contract_name='pdc_stage_activation_060' and c.proposal_ref=new.proposal_id
  ) then
    raise exception 'PDC_EMAIL_SOURCE_ALREADY_CLAIMED';
  end if;
  return new;
end;
$claim$;
revoke all on function public.pdc_claim_legacy_stage_activation_source() from public,anon,authenticated;
drop trigger if exists pdc_claim_legacy_stage_activation_source on public.pdc_monitor_stage_activation_approvals;
create trigger pdc_claim_legacy_stage_activation_source
before insert on public.pdc_monitor_stage_activation_approvals
for each row execute function public.pdc_claim_legacy_stage_activation_source();

insert into public.pdc_email_source_claims(source_hash,contract_name,proposal_ref,claimed_at)
select source_hash,'pdc_stage_activation_060',proposal_id,approved_at
from public.pdc_monitor_stage_activation_approvals
on conflict(source_hash) do nothing;

drop policy if exists pdc_ai_intake_revision_staff_read on public.pdc_ai_intake_revision;
create policy pdc_ai_intake_revision_staff_read on public.pdc_ai_intake_revision
for select to authenticated
using (public.current_pdc_user_role()::text in ('viewer','operator','importer','administrator'));

create or replace function public.submit_pdc_ai_intake_observation(
  p_source_hash text,
  p_evidence_hash text,
  p_source_uid text,
  p_sender_address text,
  p_authentication jsonb,
  p_source_received_at timestamptz,
  p_subject text,
  p_action_type text,
  p_stock_number text,
  p_summary text,
  p_observations jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $submit$
declare
  v_user_id uuid := auth.uid();
  v_role text := public.current_pdc_user_role()::text;
  v_source_hash text := lower(btrim(coalesce(p_source_hash,'')));
  v_evidence_hash text := lower(btrim(coalesce(p_evidence_hash,'')));
  v_source_uid text := btrim(coalesce(p_source_uid,''));
  v_sender text := lower(btrim(coalesce(p_sender_address,'')));
  v_authentication jsonb := coalesce(p_authentication,'{}'::jsonb);
  v_subject text := btrim(coalesce(p_subject,''));
  v_action text := lower(btrim(coalesce(p_action_type,'')));
  v_stock text;
  v_summary text := btrim(coalesce(p_summary,''));
  v_observations jsonb := coalesce(p_observations,'{}'::jsonb);
  v_backend_ids uuid[] := '{}'::uuid[];
  v_backend public.navision_backend_records%rowtype;
  v_navision_revision bigint;
  v_proposal_id uuid := gen_random_uuid();
  v_dedupe_key text;
  v_fingerprint text;
  v_existing public.pdc_ai_intake_proposals%rowtype;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_user_id is null or v_role is distinct from 'viewer'
     or not exists (
       select 1 from public.pdc_monitor_stage_activation_writers w
       where w.user_id=v_user_id and w.active and w.revoked_at is null
     ) then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if v_source_hash !~ '^[a-f0-9]{64}$'
     or v_evidence_hash !~ '^[a-f0-9]{64}$'
     or length(v_source_uid) < 1 or length(v_source_uid) > 100
     or v_sender !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
     or split_part(v_sender,'@',2) not in ('broometoyota.com.au','pmgwa.com.au')
     or jsonb_typeof(v_authentication) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_authentication) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_authentication->>'sender_domain' is distinct from split_part(v_sender,'@',2)
     or v_authentication->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not (v_authentication->'spf_aligned'='true'::jsonb
             or v_authentication->'dkim_aligned'='true'::jsonb
             or v_authentication->'dmarc_aligned'='true'::jsonb)
     or p_source_received_at is null
     or p_source_received_at > clock_timestamp()+interval '5 minutes'
     or p_source_received_at < clock_timestamp()-interval '120 days'
     or length(v_subject) < 1 or length(v_subject) > 300
     or v_action not in ('board_activate_only','review_only')
     or length(v_summary) < 5 or length(v_summary) > 2000
     or jsonb_typeof(v_observations) is distinct from 'object'
     or length(v_observations::text) > 16000 then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  select revision into v_navision_revision
  from public.navision_backend_revision where singleton;

  if v_action='board_activate_only' then
    if not public.is_real_vehicle_stock_number(p_stock_number) then
      return public.navision_backend_response(false,'invalid_stock');
    end if;
    v_stock:=public.normalize_vehicle_stock_number(p_stock_number);
    select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_backend_ids
    from public.navision_backend_records r
    where r.source_system='microsoft_navision'
      and r.dealer_code in ('14450','37047')
      and r.is_current and r.record_status='current'
      and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
      and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    if cardinality(v_backend_ids)<>1 then
      return public.navision_backend_response(false,'identity_conflict',jsonb_build_object('match_count',cardinality(v_backend_ids)));
    end if;
    select * into v_backend from public.navision_backend_records where id=v_backend_ids[1];
    if exists (
      select 1 from public.vehicles v where v.stock_number_normalized=v_stock and v.deleted_at is null
      union all
      select 1 from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock
    ) then
      return public.navision_backend_response(false,'operational_identity_present');
    end if;
  else
    v_stock:=case when public.is_real_vehicle_stock_number(p_stock_number) then public.normalize_vehicle_stock_number(p_stock_number) else null end;
  end if;

  v_dedupe_key:=encode(digest(jsonb_build_object(
    'contract_version',1,'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,
    'action_type',v_action,'stock_number',v_stock
  )::text,'sha256'),'hex');
  v_fingerprint:=upper(substr(encode(digest(jsonb_build_object(
    'contract_version',1,'proposal_id',v_proposal_id,'dedupe_key',v_dedupe_key,
    'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'source_uid',v_source_uid,
    'sender_address',v_sender,'authentication',v_authentication,'source_received_at',p_source_received_at,'subject',v_subject,
    'action_type',v_action,'stock_number',v_stock,'backend_record_id',v_backend.id,
    'backend_record_version',v_backend.version,'observed_navision_revision',v_navision_revision,
    'summary',v_summary,'observations',v_observations
  )::text,'sha256'),'hex'),1,16));

  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake:'||v_dedupe_key,0));
  select * into v_existing from public.pdc_ai_intake_proposals where dedupe_key=v_dedupe_key;
  if found then
    return public.navision_backend_response(true,'already_noticed',jsonb_build_object(
      'proposal_id',v_existing.proposal_id,'status',v_existing.status,
      'version',v_existing.version,'fingerprint',v_existing.fingerprint));
  end if;

  insert into public.pdc_email_source_claims(source_hash,contract_name,proposal_ref)
  values(v_source_hash,'pdc_ai_intake_063',v_proposal_id::text)
  on conflict(source_hash) do nothing;
  if not found then
    return public.navision_backend_response(false,'source_already_claimed');
  end if;

  insert into public.pdc_ai_intake_proposals(
    proposal_id,dedupe_key,source_hash,evidence_hash,source_uid,sender_address,authentication,
    source_received_at,subject,action_type,stock_number,backend_record_id,
    backend_record_version,observed_navision_revision,summary,observations,
    fingerprint,submitted_by
  ) values(
    v_proposal_id,v_dedupe_key,v_source_hash,v_evidence_hash,v_source_uid,v_sender,v_authentication,
    p_source_received_at,v_subject,v_action,v_stock,v_backend.id,
    v_backend.version,v_navision_revision,v_summary,v_observations,
    v_fingerprint,v_user_id
  );
  insert into public.pdc_ai_intake_history(
    proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
    stock_number,action_type,details
  ) values(
    v_proposal_id,'noticed',v_user_id,public.current_actor_email(),1,v_fingerprint,
    v_stock,v_action,jsonb_build_object('source_uid',v_source_uid,'sender_address',v_sender,'summary',v_summary)
  );
  update public.pdc_ai_intake_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
  return public.navision_backend_response(true,'noticed',jsonb_build_object(
    'proposal_id',v_proposal_id,'status','pending','version',1,'fingerprint',v_fingerprint));
exception when unique_violation then
  return public.navision_backend_response(false,'proposal_conflict');
end;
$submit$;

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
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
  if auth.uid() is null or v_role is null or v_role not in ('viewer','operator','importer','administrator') then
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

create or replace function public.decide_pdc_ai_intake_proposal(
  p_proposal_id uuid,
  p_expected_version bigint,
  p_fingerprint text,
  p_decision text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $decide$
declare
  v_user_id uuid := auth.uid();
  v_role text := public.current_pdc_user_role()::text;
  v_actor_email text := public.current_actor_email();
  v_decision text := lower(btrim(coalesce(p_decision,'')));
  v_reason text := btrim(coalesce(p_reason,''));
  v_fingerprint text := upper(btrim(coalesce(p_fingerprint,'')));
  v_proposal public.pdc_ai_intake_proposals%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_stock_ids uuid[] := '{}'::uuid[];
  v_revision bigint;
  v_result_revision bigint;
  v_result jsonb;
  v_event text;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
  if v_user_id is null or v_role is distinct from 'administrator' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if p_proposal_id is null or p_expected_version is null or p_expected_version<1
     or v_fingerprint !~ '^[A-F0-9]{16}$'
     or v_decision not in ('apply','reject')
     or length(v_reason)<10 or length(v_reason)>500 then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-decision:'||p_proposal_id::text,0));
  select * into v_proposal from public.pdc_ai_intake_proposals
  where proposal_id=p_proposal_id for update;
  if not found then return public.navision_backend_response(false,'proposal_not_found'); end if;
  if v_proposal.version<>p_expected_version or v_proposal.fingerprint<>v_fingerprint then
    return public.navision_backend_response(false,'proposal_changed',jsonb_build_object(
      'current_version',v_proposal.version,'current_fingerprint',v_proposal.fingerprint));
  end if;
  if v_proposal.status<>'pending' then
    return public.navision_backend_response(true,'already_decided',jsonb_build_object(
      'status',v_proposal.status,'version',v_proposal.version,'result',v_proposal.result));
  end if;

  if v_decision='reject' then
    v_result:=public.navision_backend_response(true,'rejected',jsonb_build_object('proposal_id',v_proposal.proposal_id));
    v_event:='rejected';
  else
    if v_proposal.action_type<>'board_activate_only' then
      return public.navision_backend_response(false,'action_not_supported');
    end if;
    perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
    lock table public.vehicles,public.vehicle_aliases in share row exclusive mode;
    select revision into v_revision from public.navision_backend_revision where singleton for update;
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
    if exists (
      select 1 from public.vehicles v where v.stock_number_normalized=v_proposal.stock_number and v.deleted_at is null
      union all
      select 1 from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_proposal.stock_number
    ) then
      return public.navision_backend_response(false,'operational_identity_present');
    end if;
    if exists (
      select 1 from public.navision_board_activations a
      where a.backend_record_id<>v_proposal.backend_record_id
        and public.normalize_vehicle_stock_number(a.activated_stock_number)=v_proposal.stock_number
    ) then
      return public.navision_backend_response(false,'activation_identity_conflict');
    end if;
    if exists (
      select 1 from public.navision_board_activations a
      where a.backend_record_id=v_proposal.backend_record_id
        and public.normalize_vehicle_stock_number(a.activated_stock_number)<>v_proposal.stock_number
    ) then
      return public.navision_backend_response(false,'activation_identity_conflict');
    end if;

    if exists(select 1 from public.navision_board_activations a where a.backend_record_id=v_proposal.backend_record_id) then
      v_result_revision:=v_revision;
      v_result:=public.navision_backend_response(true,'already_activated',jsonb_build_object(
        'proposal_id',v_proposal.proposal_id,'backend_record_id',v_proposal.backend_record_id,
        'result_revision',v_result_revision,'activated',true));
    else
      insert into public.navision_board_activations(
        backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email
      ) values(
        v_proposal.backend_record_id,'approved_email_build',v_record.normalized_data->>'batch',
        v_user_id,v_actor_email
      );
      v_result_revision:=v_revision+1;
      update public.navision_backend_revision set revision=v_result_revision,updated_at=clock_timestamp() where singleton;
      insert into public.navision_backend_audit(action,backend_record_id,revision,evidence,actor_id,actor_email)
      values('board_activate',v_proposal.backend_record_id,v_result_revision,jsonb_build_object(
        'activation_source','ai_intake_approved_email','proposal_id',v_proposal.proposal_id,
        'fingerprint',v_proposal.fingerprint,'source_hash',v_proposal.source_hash,
        'evidence_hash',v_proposal.evidence_hash,'source_uid',v_proposal.source_uid,
        'sender_address',v_proposal.sender_address,'source_received_at',v_proposal.source_received_at,
        'stock_number',v_proposal.stock_number,'approved_by',v_user_id,
        'approval_reason',v_reason,'automated',false),v_user_id,v_actor_email);
      v_result:=public.navision_backend_response(true,'board_activated',jsonb_build_object(
        'proposal_id',v_proposal.proposal_id,'backend_record_id',v_proposal.backend_record_id,
        'result_revision',v_result_revision,'activated',true));
    end if;
    v_event:='applied';
  end if;

  update public.pdc_ai_intake_proposals set
    status=v_event,version=version+1,decided_by=v_user_id,decided_by_email=v_actor_email,
    decided_at=clock_timestamp(),decision_reason=v_reason,result=v_result
  where proposal_id=v_proposal.proposal_id;
  insert into public.pdc_ai_intake_history(
    proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
    stock_number,action_type,details
  ) values(
    v_proposal.proposal_id,v_event,v_user_id,v_actor_email,v_proposal.version+1,
    v_proposal.fingerprint,v_proposal.stock_number,v_proposal.action_type,
    jsonb_build_object('reason',v_reason,'result',v_result)
  );
  update public.pdc_ai_intake_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
  return v_result;
end;
$decide$;

revoke all on function public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.get_pdc_ai_intake_snapshot(text,integer) from public,anon,authenticated;
revoke all on function public.decide_pdc_ai_intake_proposal(uuid,bigint,text,text,text) from public,anon,authenticated;
grant execute on function public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb) to authenticated;
grant execute on function public.get_pdc_ai_intake_snapshot(text,integer) to authenticated;
grant execute on function public.decide_pdc_ai_intake_proposal(uuid,bigint,text,text,text) to authenticated;

do $realtime$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(
       select 1 from pg_publication_tables
       where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_ai_intake_revision'
     ) then
    alter publication supabase_realtime add table public.pdc_ai_intake_revision;
  end if;
end;
$realtime$;

commit;
