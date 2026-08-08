-- Staging-only migration 135: automatically apply safe AI Intake board-activation proposals
-- submitted by the enrolled PDC monitor. Review-only evidence remains observation-only.
-- Email/proposal fields cannot infer work, Parts, bookings, or operational location;
-- canonical vehicle location remains governed only by current Navision reconciliation.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     )
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists(
       select 1 from supabase_migrations.schema_migrations
       where version='134' and name='navision_preserve_deleted_canonical_identity'
     ) then
    raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_PREDECESSOR_134_REQUIRED';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='135') then
    raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_VERSION_CONFLICT';
  end if;
  if to_regprocedure('public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)') is null
     or to_regprocedure('public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)') is not null
     or to_regprocedure('public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean)') is not null
     or to_regclass('public.pdc_ai_intake_auto_activation_receipts') is not null
     or to_regclass('public.pdc_ai_intake_auto_backlog_receipts') is not null
     or to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') is null
     or to_regclass('public.pdc_ai_intake_proposals') is null
     or to_regclass('public.pdc_ai_intake_history') is null
     or to_regclass('public.pdc_monitor_stage_activation_writers') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_board_activations') is null
     or to_regclass('public.navision_backend_audit') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.vehicle_aliases') is null then
    raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_DEPENDENCY_MISSING';
  end if;
end
$guard$;

create table public.pdc_ai_intake_auto_activation_receipts (
  proposal_id uuid primary key references public.pdc_ai_intake_proposals(proposal_id) on delete restrict,
  policy_version text not null check(policy_version='135.1'),
  request_hash text not null unique check(request_hash~'^[a-f0-9]{64}$'),
  source_hash text not null unique check(source_hash~'^[a-f0-9]{64}$'),
  stock_number text not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null,
  response jsonb not null check(jsonb_typeof(response)='object'),
  created_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_ai_intake_auto_activation_receipts enable row level security;
revoke all on table public.pdc_ai_intake_auto_activation_receipts
  from public,anon,authenticated,service_role;

create table public.pdc_ai_intake_auto_backlog_receipts (
  policy_version text primary key check(policy_version='135.1'),
  input_hash text not null unique check(input_hash~'^[a-f0-9]{64}$'),
  proposal_count integer not null,
  stock_count integer not null,
  applied_count integer not null,
  rejected_count integer not null,
  response jsonb not null check(jsonb_typeof(response)='object'),
  completed_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_ai_intake_auto_backlog_receipts enable row level security;
revoke all on table public.pdc_ai_intake_auto_backlog_receipts
  from public,anon,authenticated,service_role;

create function public.pdc_auto_apply_ai_intake_activation_internal(
  p_proposal_id uuid,
  p_actor_id uuid,
  p_actor_email text,
  p_allow_current_record_refresh boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $auto$
declare
  v_actor_email text:=lower(btrim(coalesce(p_actor_email,'')));
  v_proposal public.pdc_ai_intake_proposals%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_activation public.navision_board_activations%rowtype;
  v_receipt public.pdc_ai_intake_auto_activation_receipts%rowtype;
  v_duplicate public.pdc_ai_intake_proposals%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_stock_ids uuid[]:='{}'::uuid[];
  v_operational_ids uuid[]:='{}'::uuid[];
  v_vin_ids uuid[]:='{}'::uuid[];
  v_navision_revision bigint;
  v_next_navision_revision bigint;
  v_inbox_revision bigint;
  v_transition_count integer:=0;
  v_duplicate_count integer:=0;
  v_vehicle_id uuid;
  v_vin text;
  v_response jsonb;
  v_duplicate_response jsonb;
  v_mutation_error text;
  v_activation_found boolean:=false;
  v_request_hash text;
  v_primary_proposal_id uuid;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if p_proposal_id is null or p_actor_id is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  -- Hold the approved Viewer role and enrolled writer authority through commit.
  perform 1 from public.pdc_user_roles r
  where r.auth_user_id=p_actor_id and r.email=v_actor_email
    and r.role='viewer' and r.active and r.account_status='approved'
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=p_actor_id and w.active and w.revoked_at is null
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-auto:'||p_proposal_id::text,0));

  -- Use the same proposal/inbox lock order as the Administrator decision RPC.
  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-decision:'||p_proposal_id::text,0));
  select revision into v_inbox_revision
  from public.pdc_ai_intake_revision where singleton for update;
  select * into v_proposal
  from public.pdc_ai_intake_proposals
  where proposal_id=p_proposal_id;
  if not found then return public.navision_backend_response(false,'proposal_not_found'); end if;
  if v_proposal.action_type<>'board_activate_only'
     or not public.is_real_vehicle_stock_number(v_proposal.stock_number) then
    return public.navision_backend_response(false,'proposal_not_auto_eligible');
  end if;
  -- Acquire the shared Stock lock before any proposal row lock, then lock the
  -- complete same-Stock fan-in deterministically.
  perform pg_advisory_xact_lock(hashtextextended(
    'navision-board-activate:ai-intake-auto:'||v_proposal.stock_number,0
  ));
  perform proposal_id from public.pdc_ai_intake_proposals
  where status='pending' and action_type='board_activate_only'
    and stock_number=v_proposal.stock_number
  order by proposal_id for update;
  select * into v_proposal
  from public.pdc_ai_intake_proposals
  where proposal_id=p_proposal_id
  for update;
  if not found then return public.navision_backend_response(false,'proposal_not_found'); end if;
  perform 1 from public.pdc_email_source_claims c
  where c.source_hash=v_proposal.source_hash
    and c.contract_name='pdc_ai_intake_063'
    and c.proposal_ref=v_proposal.proposal_id::text
  for share;
  if not found then return public.navision_backend_response(false,'source_claim_conflict'); end if;
  v_request_hash:=encode(digest(jsonb_build_object(
    'policy_version','135.1','proposal_id',v_proposal.proposal_id,
    'fingerprint',v_proposal.fingerprint,'source_hash',v_proposal.source_hash,
    'evidence_hash',v_proposal.evidence_hash,'action_type',v_proposal.action_type,
    'stock_number',v_proposal.stock_number,'backend_record_id',v_proposal.backend_record_id,
    'backend_record_version',v_proposal.backend_record_version,
    'actor_id',p_actor_id,'actor_email',v_actor_email,
    'allow_current_record_refresh',coalesce(p_allow_current_record_refresh,false)
  )::text,'sha256'),'hex');
  select * into v_receipt
  from public.pdc_ai_intake_auto_activation_receipts
  where proposal_id=p_proposal_id;
  if found then
    if v_receipt.policy_version<>'135.1' or v_receipt.request_hash<>v_request_hash
       or v_receipt.actor_id<>p_actor_id or v_receipt.actor_email<>v_actor_email then
      return public.navision_backend_response(false,'auto_receipt_conflict');
    end if;
    return v_receipt.response;
  end if;
  if v_proposal.status<>'pending' then
    return coalesce(v_proposal.result,public.navision_backend_response(true,'proposal_consumed',jsonb_build_object(
      'proposal_id',v_proposal.proposal_id,'status',v_proposal.status,'version',v_proposal.version
    )));
  end if;
  if v_proposal.submitted_by<>p_actor_id or v_proposal.action_type<>'board_activate_only'
     or v_proposal.backend_record_id is null or v_proposal.backend_record_version is null
     or not public.is_real_vehicle_stock_number(v_proposal.stock_number) then
    return public.navision_backend_response(false,'proposal_not_auto_eligible');
  end if;
  if v_proposal.submitted_at<clock_timestamp()-interval '14 days'
     or v_proposal.source_received_at<clock_timestamp()-interval '30 days' then
    return public.navision_backend_response(false,'proposal_expired');
  end if;
  if jsonb_typeof(v_proposal.authentication) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_proposal.authentication) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_proposal.authentication->>'sender_domain' is distinct from split_part(v_proposal.sender_address,'@',2)
     or v_proposal.authentication->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not (v_proposal.authentication->'spf_aligned'='true'::jsonb
             or v_proposal.authentication->'dkim_aligned'='true'::jsonb
             or v_proposal.authentication->'dmarc_aligned'='true'::jsonb)
     or jsonb_typeof(v_proposal.observations) is distinct from 'object'
     or not (v_proposal.observations ?& array[
       'attachment_manifest','authenticated','conflicts','customer','eta_to_kewdale',
       'location_evidence','match_outcome','match_reason','required_work','sender_domain','vehicle'
     ])
     or v_proposal.observations->'authenticated' is distinct from 'true'::jsonb
     or v_proposal.observations->>'sender_domain' is distinct from v_proposal.authentication->>'sender_domain'
     or v_proposal.observations->>'match_outcome' not in ('resolved_navision','resolved_navision_exact') then
    return public.navision_backend_response(false,'proposal_evidence_invalid');
  end if;
  if jsonb_typeof(v_proposal.observations->'conflicts') is distinct from 'array'
     or v_proposal.observations->'conflicts'<>'[]'::jsonb
     or (v_proposal.observations ? 'cancelled' and v_proposal.observations->'cancelled' is distinct from 'false'::jsonb)
     or (v_proposal.observations ? 'canceled' and v_proposal.observations->'canceled' is distinct from 'false'::jsonb)
     or (v_proposal.observations ? 'is_cancelled' and v_proposal.observations->'is_cancelled' is distinct from 'false'::jsonb)
     or (v_proposal.observations ? 'is_canceled' and v_proposal.observations->'is_canceled' is distinct from 'false'::jsonb)
     or concat_ws(' ',v_proposal.subject,v_proposal.summary)~*'\m(cancelled|canceled|cancellation)\M' then
    return public.navision_backend_response(false,'proposal_conflicted_or_cancelled');
  end if;

  -- Select the one deterministic primary after the complete fan-in is locked.
  select proposal_id into v_primary_proposal_id
  from public.pdc_ai_intake_proposals
  where status='pending' and action_type='board_activate_only'
    and stock_number=v_proposal.stock_number
  order by source_received_at desc,submitted_at desc,proposal_id desc
  limit 1;
  if v_primary_proposal_id is distinct from v_proposal.proposal_id then
    return public.navision_backend_response(false,'superseded_pending_proposal',jsonb_build_object(
      'primary_proposal_id',v_primary_proposal_id,'status','pending'
    ));
  end if;
  if exists(
    select 1 from public.pdc_ai_intake_proposals q
    where q.status='pending' and q.action_type='board_activate_only'
      and q.stock_number=v_proposal.stock_number
      and (
        jsonb_typeof(q.observations->'conflicts') is distinct from 'array'
        or q.observations->'conflicts'<>'[]'::jsonb
        or (q.observations ? 'cancelled' and q.observations->'cancelled' is distinct from 'false'::jsonb)
        or (q.observations ? 'canceled' and q.observations->'canceled' is distinct from 'false'::jsonb)
        or (q.observations ? 'is_cancelled' and q.observations->'is_cancelled' is distinct from 'false'::jsonb)
        or (q.observations ? 'is_canceled' and q.observations->'is_canceled' is distinct from 'false'::jsonb)
        or concat_ws(' ',q.subject,q.summary)~*'\m(cancelled|canceled|cancellation)\M'
      )
  ) then
    return public.navision_backend_response(false,'same_stock_evidence_conflict',jsonb_build_object('status','pending'));
  end if;

  -- Match the established Navision store/revision lock order before identity locks.
  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  select revision into v_navision_revision
  from public.navision_backend_revision where singleton for update;
  select * into v_record
  from public.navision_backend_records
  where id=v_proposal.backend_record_id
  for update;
  if not found or not v_record.is_current or v_record.record_status<>'current' then
    return public.navision_backend_response(false,'record_changed');
  end if;
  if v_record.version<>v_proposal.backend_record_version
     and not coalesce(p_allow_current_record_refresh,false) then
    return public.navision_backend_response(false,'record_changed');
  end if;
  if public.navision_operational_location(v_record.normalized_data)='Completed' then
    return public.navision_backend_response(false,'protected_backend_lifecycle');
  end if;
  select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_stock_ids
  from public.navision_backend_records r
  where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
    and r.is_current and r.record_status='current'
    and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
    and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_proposal.stock_number;
  if cardinality(v_stock_ids)<>1 or v_stock_ids[1]<>v_proposal.backend_record_id
     or public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch')<>v_proposal.stock_number then
    return public.navision_backend_response(false,'identity_conflict');
  end if;

  lock table public.vehicles,public.vehicle_aliases in share row exclusive mode;
  perform pg_advisory_xact_lock(hashtextextended(
    'vehicle-master:stock_number:'||v_proposal.stock_number,0
  ));
  select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[])
  into v_operational_ids
  from (
    select v.id vehicle_id from public.vehicles v where v.stock_number_normalized=v_proposal.stock_number
    union all
    select a.vehicle_id from public.vehicle_aliases a
    where a.active and a.alias_type_normalized='stock_number'
      and a.normalized_alias_value=v_proposal.stock_number
  ) candidates;
  if cardinality(v_operational_ids)>1 then
    return public.navision_backend_response(false,'operational_identity_conflict');
  end if;
  v_vehicle_id:=case when cardinality(v_operational_ids)=1 then v_operational_ids[1] else null end;
  if v_vehicle_id is not null then
    select * into v_vehicle from public.vehicles where id=v_vehicle_id for update;
    if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active'
       or not v_vehicle.visible_on_board or v_vehicle.rft_collected_at is not null
       or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED' then
      return public.navision_backend_response(false,'protected_existing_lifecycle');
    end if;
  end if;
  if exists(
    select 1 from public.vehicles v
    where v.deleted_at is not null
      and (v.id=v_record.canonical_vehicle_id or v.stock_number_normalized=v_proposal.stock_number)
  ) then
    return public.navision_backend_response(false,'protected_historical_identity');
  end if;

  v_vin:=case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin')
    then nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),'') else null end;
  if v_vin is not null then
    select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[])
    into v_vin_ids
    from (
      select v.id vehicle_id from public.vehicles v where v.vin_normalized=v_vin
      union all
      select a.vehicle_id from public.vehicle_aliases a
      where a.active and a.alias_type_normalized='vin' and a.normalized_alias_value=v_vin
    ) candidates;
    if exists(select 1 from unnest(v_vin_ids) id where v_vehicle_id is null or id<>v_vehicle_id) then
      return public.navision_backend_response(false,'vin_conflict_non_authoritative');
    end if;
  end if;
  if v_record.canonical_vehicle_id is not null
     and (v_vehicle_id is null or v_record.canonical_vehicle_id<>v_vehicle_id) then
    return public.navision_backend_response(false,'backend_canonical_identity_conflict');
  end if;
  if exists(
    select 1 from public.vehicles v
    where v.source_system_normalized='microsoft_navision'
      and v.source_record_id_normalized=public.normalize_vehicle_source_identifier(v_record.id::text)
      and (v_vehicle_id is null or v.id<>v_vehicle_id)
  ) then
    return public.navision_backend_response(false,'backend_source_identity_conflict');
  end if;

  select * into v_activation
  from public.navision_board_activations
  where backend_record_id=v_proposal.backend_record_id
  for update;
  v_activation_found:=found;
  if v_activation_found and (
    not v_activation.active or v_activation.completed_at is not null
    or public.normalize_vehicle_stock_number(v_activation.activated_stock_number)<>v_proposal.stock_number
    or (v_activation.canonical_vehicle_id is not null
        and (v_vehicle_id is null or v_activation.canonical_vehicle_id<>v_vehicle_id))
  ) then
    return public.navision_backend_response(false,'protected_or_conflicting_activation');
  end if;
  if exists(
    select 1 from public.navision_board_activations a
    where a.backend_record_id<>v_proposal.backend_record_id
      and public.normalize_vehicle_stock_number(a.activated_stock_number)=v_proposal.stock_number
  ) then
    return public.navision_backend_response(false,'activation_identity_conflict');
  end if;

  -- A board-visible operational vehicle means this proposal is stale evidence,
  -- not permission to rewrite that vehicle. Close every same-Stock proposal as no-op.
  if v_vehicle_id is not null then
    v_response:=public.navision_backend_response(true,'automatically_closed_existing',jsonb_build_object(
      'proposal_id',v_proposal.proposal_id,'stock_number',v_proposal.stock_number,
      'vehicle_id',v_vehicle_id,'vehicle_mutated',false,'board_activation_only',false,
      'authority_refreshed',v_record.version<>v_proposal.backend_record_version,
      'proposal_backend_record_version',v_proposal.backend_record_version,
      'current_backend_record_version',v_record.version,
      'authorization_basis','enrolled_monitor_and_live_server_identity'
    ));
    update public.pdc_ai_intake_proposals set
      status='rejected',version=version+1,decided_by=p_actor_id,
      decided_by_email=v_actor_email,decided_at=clock_timestamp(),
      decision_reason='Automatically closed because this Stock is already active on the Control Board.',
      result=v_response
    where proposal_id=v_proposal.proposal_id;
    insert into public.pdc_ai_intake_history(
      proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
      stock_number,action_type,details
    ) values(
      v_proposal.proposal_id,'rejected',p_actor_id,v_actor_email,v_proposal.version+1,
      v_proposal.fingerprint,v_proposal.stock_number,v_proposal.action_type,
      jsonb_build_object('reason','already active on Control Board','result',v_response,
        'automatic',true,'authorization_basis','enrolled_monitor_and_live_server_identity')
    );
    v_transition_count:=1;
    for v_duplicate in
      select * from public.pdc_ai_intake_proposals
      where status='pending' and action_type='board_activate_only'
        and stock_number=v_proposal.stock_number and proposal_id<>v_proposal.proposal_id
      order by proposal_id for update
    loop
      v_duplicate_response:=public.navision_backend_response(true,'automatically_closed_duplicate',jsonb_build_object(
        'proposal_id',v_duplicate.proposal_id,'stock_number',v_duplicate.stock_number,
        'vehicle_id',v_vehicle_id,'vehicle_mutated',false,'board_activation_only',false,
        'primary_proposal_id',v_proposal.proposal_id
      ));
      update public.pdc_ai_intake_proposals set
        status='rejected',version=version+1,decided_by=p_actor_id,
        decided_by_email=v_actor_email,decided_at=clock_timestamp(),
        decision_reason='Automatically closed as duplicate evidence for a Stock already active on the Control Board.',
        result=v_duplicate_response
      where proposal_id=v_duplicate.proposal_id;
      insert into public.pdc_ai_intake_history(
        proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
        stock_number,action_type,details
      ) values(
        v_duplicate.proposal_id,'rejected',p_actor_id,v_actor_email,v_duplicate.version+1,
        v_duplicate.fingerprint,v_duplicate.stock_number,v_duplicate.action_type,
        jsonb_build_object('reason','duplicate evidence for active Stock','result',v_duplicate_response,
          'automatic',true,'primary_proposal_id',v_proposal.proposal_id)
      );
      v_transition_count:=v_transition_count+1;
      v_duplicate_count:=v_duplicate_count+1;
    end loop;
    update public.pdc_ai_intake_revision
    set revision=revision+v_transition_count,updated_at=clock_timestamp()
    where singleton;
    v_response:=jsonb_set(v_response,'{data,duplicate_count}',to_jsonb(v_duplicate_count),true);
    insert into public.pdc_ai_intake_auto_activation_receipts(
      proposal_id,policy_version,request_hash,source_hash,stock_number,actor_id,actor_email,response
    ) values(v_proposal.proposal_id,'135.1',v_request_hash,v_proposal.source_hash,v_proposal.stock_number,p_actor_id,v_actor_email,v_response);
    return v_response;
  end if;

  if v_activation_found then
    return public.navision_backend_response(false,'activation_without_operational_identity');
  end if;

  -- Mutation is a subtransaction: a failed reconcile/postcondition rolls back
  -- activation, operational vehicle, revision and audit while retaining the proposal.
  begin
    insert into public.navision_board_activations(
      backend_record_id,activation_source,activated_stock_number,
      activated_by,activated_by_email,active
    ) values(
      v_record.id,'approved_email_build',v_record.normalized_data->>'batch',
      p_actor_id,v_actor_email,true
    );
    v_next_navision_revision:=v_navision_revision+1;
    update public.navision_backend_revision
    set revision=v_next_navision_revision,updated_at=clock_timestamp()
    where singleton;
    insert into public.navision_backend_audit(
      action,backend_record_id,revision,evidence,actor_id,actor_email
    ) values(
      'board_activate',v_record.id,v_next_navision_revision,
      jsonb_build_object(
        'activation_source','approved_email_build','contract','pdc_ai_intake_auto_135',
        'proposal_id',v_proposal.proposal_id,'source_hash',v_proposal.source_hash,
        'evidence_hash',v_proposal.evidence_hash,'stock_number',v_proposal.stock_number,
        'authority_refreshed',v_record.version<>v_proposal.backend_record_version,
        'proposal_backend_record_version',v_proposal.backend_record_version,
        'current_backend_record_version',v_record.version,
        'automated',true,'stock_only_authority',true,'vin_identity_authority',false,
        'booking_created',false,'work_mutated',false,'parts_mutated',false
      ),p_actor_id,v_actor_email
    );
    select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[])
    into v_operational_ids
    from (
      select v.id vehicle_id from public.vehicles v
      where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
        and v.stock_number_normalized=v_proposal.stock_number
      union all
      select a.vehicle_id from public.vehicle_aliases a
      join public.vehicles v on v.id=a.vehicle_id
      where a.active and a.alias_type_normalized='stock_number'
        and a.normalized_alias_value=v_proposal.stock_number
        and v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    ) candidates;
    if cardinality(v_operational_ids)<>1 then
      raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_POSTCONDITION_FAILED';
    end if;
    v_vehicle_id:=v_operational_ids[1];
  exception when others then
    get stacked diagnostics v_mutation_error=message_text;
    return public.navision_backend_response(false,'automatic_activation_failed',jsonb_build_object(
      'proposal_id',v_proposal.proposal_id,'stock_number',v_proposal.stock_number,
      'failure',v_mutation_error
    ));
  end;

  v_response:=public.navision_backend_response(true,'automatically_applied',jsonb_build_object(
    'proposal_id',v_proposal.proposal_id,'stock_number',v_proposal.stock_number,
    'backend_record_id',v_record.id,'vehicle_id',v_vehicle_id,
    'navision_revision',v_next_navision_revision,'vehicle_mutated',true,
    'authority_refreshed',v_record.version<>v_proposal.backend_record_version,
    'proposal_backend_record_version',v_proposal.backend_record_version,
    'current_backend_record_version',v_record.version,
    'board_activation_only',true,'booking_created',false,'work_mutated',false,
    'parts_mutated',false,'authorization_basis','enrolled_monitor_and_live_server_identity'
  ));
  update public.pdc_ai_intake_proposals set
    status='applied',version=version+1,decided_by=p_actor_id,
    decided_by_email=v_actor_email,decided_at=clock_timestamp(),
    decision_reason='Automatically activated from authenticated email and unique current Navision Stock authority.',
    result=v_response
  where proposal_id=v_proposal.proposal_id;
  insert into public.pdc_ai_intake_history(
    proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
    stock_number,action_type,details
  ) values(
    v_proposal.proposal_id,'applied',p_actor_id,v_actor_email,v_proposal.version+1,
    v_proposal.fingerprint,v_proposal.stock_number,v_proposal.action_type,
    jsonb_build_object('reason','automatic exact-Stock activation','result',v_response,
      'automatic',true,'email_evidence_authoritative',false,
      'authorization_basis','enrolled_monitor_and_live_server_identity')
  );
  v_transition_count:=1;
  for v_duplicate in
    select * from public.pdc_ai_intake_proposals
    where status='pending' and action_type='board_activate_only'
      and stock_number=v_proposal.stock_number and proposal_id<>v_proposal.proposal_id
    order by proposal_id for update
  loop
    v_duplicate_response:=public.navision_backend_response(true,'automatically_closed_duplicate',jsonb_build_object(
      'proposal_id',v_duplicate.proposal_id,'stock_number',v_duplicate.stock_number,
      'vehicle_id',v_vehicle_id,'vehicle_mutated',false,'board_activation_only',false,
      'primary_proposal_id',v_proposal.proposal_id
    ));
    update public.pdc_ai_intake_proposals set
      status='rejected',version=version+1,decided_by=p_actor_id,
      decided_by_email=v_actor_email,decided_at=clock_timestamp(),
      decision_reason='Automatically closed as duplicate evidence after this Stock was activated.',
      result=v_duplicate_response
    where proposal_id=v_duplicate.proposal_id;
    insert into public.pdc_ai_intake_history(
      proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
      stock_number,action_type,details
    ) values(
      v_duplicate.proposal_id,'rejected',p_actor_id,v_actor_email,v_duplicate.version+1,
      v_duplicate.fingerprint,v_duplicate.stock_number,v_duplicate.action_type,
      jsonb_build_object('reason','duplicate evidence after automatic activation','result',v_duplicate_response,
        'automatic',true,'primary_proposal_id',v_proposal.proposal_id)
    );
    v_transition_count:=v_transition_count+1;
    v_duplicate_count:=v_duplicate_count+1;
  end loop;
  update public.pdc_ai_intake_revision
  set revision=revision+v_transition_count,updated_at=clock_timestamp()
  where singleton;
  v_response:=jsonb_set(v_response,'{data,duplicate_count}',to_jsonb(v_duplicate_count),true);
  update public.pdc_ai_intake_proposals set result=v_response
  where proposal_id=v_proposal.proposal_id;
  insert into public.pdc_ai_intake_auto_activation_receipts(
    proposal_id,policy_version,request_hash,source_hash,stock_number,actor_id,actor_email,response
  ) values(v_proposal.proposal_id,'135.1',v_request_hash,v_proposal.source_hash,v_proposal.stock_number,p_actor_id,v_actor_email,v_response);
  return v_response;
end
$auto$;
revoke all on function public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean)
  from public,anon,authenticated,service_role;

alter function public.submit_pdc_ai_intake_observation(
  text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb
) rename to submit_pdc_ai_intake_observation_pre135;
revoke all on function public.submit_pdc_ai_intake_observation_pre135(
  text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb
) from public,anon,authenticated,service_role;

create function public.submit_pdc_ai_intake_observation(
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
set search_path=pg_catalog,public,extensions
as $submit$
declare
  v_submit jsonb;
  v_auto jsonb;
  v_proposal_id uuid;
  v_status text;
  v_actor_id uuid:=auth.uid();
  v_actor_email text:=public.current_actor_email();
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_actor_id is null or nullif(btrim(v_actor_email),'') is null then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_user_roles r
  where r.auth_user_id=v_actor_id and r.email=lower(btrim(v_actor_email))
    and r.role='viewer' and r.active and r.account_status='approved'
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=v_actor_id and w.active and w.revoked_at is null
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  -- Serialize proposal creation with the one-time exact backlog snapshot.
  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-submit-gate:135.1',0));
  v_submit:=public.submit_pdc_ai_intake_observation_pre135(
    p_source_hash,p_evidence_hash,p_source_uid,p_sender_address,p_authentication,
    p_source_received_at,p_subject,p_action_type,p_stock_number,p_summary,p_observations
  );
  if not coalesce((v_submit->>'ok')::boolean,false)
     or lower(btrim(coalesce(p_action_type,'')))<>'board_activate_only' then
    return v_submit;
  end if;
  begin
    v_proposal_id:=(v_submit->'data'->>'proposal_id')::uuid;
  exception when others then
    return v_submit;
  end;
  if v_proposal_id is null then return v_submit; end if;
  v_auto:=public.pdc_auto_apply_ai_intake_activation_internal(
    v_proposal_id,v_actor_id,lower(btrim(v_actor_email)),false
  );
  select status into v_status from public.pdc_ai_intake_proposals where proposal_id=v_proposal_id;
  v_submit:=jsonb_set(v_submit,'{data,status}',to_jsonb(coalesce(v_status,'pending')),true);
  return jsonb_set(v_submit,'{data,auto_activation}',coalesce(v_auto,'null'::jsonb),true);
end
$submit$;
revoke all on function public.submit_pdc_ai_intake_observation(
  text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb
) from public,anon,authenticated,service_role;
grant execute on function public.submit_pdc_ai_intake_observation(
  text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb
) to authenticated;

-- Process the exact reviewed staging backlog as one all-or-nothing batch.
do $backlog$
declare
  v_candidate record;
  v_actor_email text;
  v_result jsonb;
  v_input_hash text;
  v_proposal_count integer;
  v_stock_count integer;
  v_applied_count integer;
  v_rejected_count integer;
  v_stocks text[];
  v_input_proposal_ids uuid[];
  v_lock_proposal_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-auto-backlog:135.1',0));
  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-submit-gate:135.1',0));
  -- Follow the core/Administrator proposal-lock order before taking Inbox.
  -- A concurrent decision finishes first; the complete digest below then
  -- detects and rejects any resulting change to the reviewed input.
  select array_agg(proposal_id order by proposal_id) into v_input_proposal_ids
  from public.pdc_ai_intake_proposals
  where status='pending' and action_type='board_activate_only';
  foreach v_lock_proposal_id in array coalesce(v_input_proposal_ids,'{}'::uuid[]) loop
    perform pg_advisory_xact_lock(hashtextextended(
      'pdc-ai-intake-auto:'||v_lock_proposal_id::text,0
    ));
    perform pg_advisory_xact_lock(hashtextextended(
      'pdc-ai-intake-decision:'||v_lock_proposal_id::text,0
    ));
  end loop;
  -- Drain any in-flight Administrator/core decision before relation locks.
  -- The submit gate has already drained wrappers that performed proposal DML.
  perform 1 from public.pdc_ai_intake_revision where singleton for update;
  -- Freeze every relation contributing to the approved digest. SHARE blocks
  -- concurrent INSERT/UPDATE/DELETE while this transaction hashes and applies.
  lock table public.pdc_email_source_claims,
             public.pdc_ai_intake_proposals,
             public.pdc_user_roles,
             public.pdc_monitor_stage_activation_writers
    in share mode;
  if exists(select 1 from public.pdc_ai_intake_auto_backlog_receipts where policy_version='135.1') then
    raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_BACKLOG_ALREADY_PROCESSED';
  end if;
  select count(*),count(distinct stock_number),array_agg(distinct stock_number order by stock_number),
    array_agg(proposal_id order by proposal_id),
    encode(digest(jsonb_agg(jsonb_build_object(
      'proposal_id',p.proposal_id,'submitted_by',p.submitted_by,'submitted_at',p.submitted_at,
      'fingerprint',p.fingerprint,'source_hash',p.source_hash,'evidence_hash',p.evidence_hash,
      'source_received_at',p.source_received_at,'sender_address',p.sender_address,
      'authentication',p.authentication,'action_type',p.action_type,'stock_number',p.stock_number,
      'backend_record_id',p.backend_record_id,'backend_record_version',p.backend_record_version,
      'subject',p.subject,'summary',p.summary,'observations',p.observations,'version',p.version,
      'source_claim',(
        select jsonb_build_object(
          'source_hash',c.source_hash,'contract_name',c.contract_name,
          'proposal_ref',c.proposal_ref,'claimed_at',c.claimed_at
        ) from public.pdc_email_source_claims c where c.source_hash=p.source_hash
      ),
      'actor_authority',(
        select jsonb_build_object(
          'auth_user_id',r.auth_user_id,'email',r.email,'role',r.role,'active',r.active,
          'account_status',r.account_status,'writer_user_id',w.user_id,
          'writer_active',w.active,'writer_revoked_at',w.revoked_at
        )
        from public.pdc_user_roles r
        join public.pdc_monitor_stage_activation_writers w on w.user_id=r.auth_user_id
        where r.auth_user_id=p.submitted_by
          and r.role='viewer' and r.active and r.account_status='approved'
          and w.active and w.revoked_at is null
        order by r.email limit 1
      )
    ) order by p.proposal_id)::text,'sha256'),'hex')
  into v_proposal_count,v_stock_count,v_stocks,v_input_proposal_ids,v_input_hash
  from public.pdc_ai_intake_proposals p
  where p.status='pending' and p.action_type='board_activate_only';
  if v_proposal_count<>28 or v_stock_count<>12 or v_stocks is distinct from array[
    '12666946','13017926','13045139','13047224','13047225','13047346',
    '13052117','13056859','13056892','13080531','13086228','13086231'
  ]::text[] or v_input_hash<>'bcbf177ae28cb616eb7f671ca8ee4ea82f589cdbcc26fce622737fb92e7df017' then
    raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_BACKLOG_PREFLIGHT_CHANGED';
  end if;
  for v_candidate in
    select distinct on (p.stock_number)
      p.proposal_id,p.stock_number,p.submitted_by,p.source_received_at
    from public.pdc_ai_intake_proposals p
    where p.proposal_id=any(v_input_proposal_ids)
      and p.status='pending' and p.action_type='board_activate_only'
    order by p.stock_number,p.source_received_at desc,p.submitted_at desc,p.proposal_id desc
  loop
    select r.email into v_actor_email
    from public.pdc_user_roles r
    join public.pdc_monitor_stage_activation_writers w
      on w.user_id=r.auth_user_id and w.active and w.revoked_at is null
    where r.auth_user_id=v_candidate.submitted_by
      and r.role='viewer' and r.active and r.account_status='approved'
    order by r.email
    limit 1;
    if v_actor_email is null then
      raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_BACKLOG_ACTOR_MISSING';
    end if;
    v_result:=public.pdc_auto_apply_ai_intake_activation_internal(
      v_candidate.proposal_id,v_candidate.submitted_by,v_actor_email,true
    );
    if not coalesce((v_result->>'ok')::boolean,false) then
      raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_BACKLOG_BLOCKED',
        detail='stock='||v_candidate.stock_number||';code='||coalesce(v_result->>'code','unknown');
    end if;
  end loop;
  select count(*) filter(where status='applied'),count(*) filter(where status='rejected')
  into v_applied_count,v_rejected_count
  from public.pdc_ai_intake_proposals
  where proposal_id=any(v_input_proposal_ids);
  if exists(
       select 1 from public.pdc_ai_intake_proposals
       where proposal_id=any(v_input_proposal_ids) and status='pending'
     ) or v_applied_count<>10 or v_rejected_count<>18 then
    raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_BACKLOG_POSTCONDITION_FAILED';
  end if;
  insert into public.pdc_ai_intake_auto_backlog_receipts(
    policy_version,input_hash,proposal_count,stock_count,applied_count,rejected_count,response
  ) values(
    '135.1',v_input_hash,v_proposal_count,v_stock_count,v_applied_count,v_rejected_count,
    public.navision_backend_response(true,'backlog_applied',jsonb_build_object(
      'policy_version','135.1','input_hash',v_input_hash,'proposal_count',v_proposal_count,
      'stock_count',v_stock_count,'applied_count',v_applied_count,'rejected_count',v_rejected_count,
      'executor','migration_135_staging_ledger_runner'
    ))
  );
end
$backlog$;

comment on function public.submit_pdc_ai_intake_observation(
  text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb
) is 'Staging-only enrolled Monitor observation contract. Safe board_activate_only proposals auto-apply from unique current Navision Stock authority; unsafe proposals remain pending. Review-only evidence never mutates operational data.';
comment on function public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean) is
  'Internal-only Migration 135 auto-activation core. Runtime calls require exact proposal record version; the migration-only backlog pass may revalidate the same current backend record ID. Not executable by authenticated clients.';

insert into supabase_migrations.schema_migrations(version,name,statements)
values('135','ai_intake_verified_stock_auto_activation',array[
  'enrolled Monitor board_activate_only submissions automatically recheck and activate unique current Navision Stock',
  'ambiguous, changed, stale, cancelled, conflicted, completed, historical or protected identities remain pending',
  'successful activation and same-Stock duplicate closure are atomic, audited and revisioned',
  'existing safe pending activation backlog revalidates the same current backend record ID through a migration-only flag',
  'review-only evidence cannot mutate; email/proposal fields cannot infer work, Parts, bookings or location; current Navision reconciliation remains location authority'
]);

commit;
