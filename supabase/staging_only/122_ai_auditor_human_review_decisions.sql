-- Staging-only migration 122: human review decisions for AI Auditor findings.
-- Approve/Deny records an immutable disposition only. It cannot execute, preview,
-- delegate, schedule, or mutate any operational record.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_AUDITOR_122_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is null
     or not exists (
       select 1 from supabase_migrations.schema_migrations
       where version='121' and name='beta_ai_auditor_foundation'
     ) then
    raise exception 'PDC_AUDITOR_122_PREDECESSOR_121_IDENTITY_MISMATCH';
  end if;
  if exists (
       select 1 from supabase_migrations.schema_migrations
       where version='122' and name<>'ai_auditor_human_review_decisions'
     ) then
    raise exception 'PDC_AUDITOR_122_VERSION_CONFLICT';
  end if;
  if to_regclass('public.pdc_auditor_findings') is null
     or to_regclass('public.pdc_auditor_runs') is null
     or to_regclass('public.pdc_auditor_revision') is null
     or to_regprocedure('public.pdc_auditor_actor_scope()') is null
     or to_regprocedure('public.pdc_auditor_operational_revision(text)') is null
     or to_regprocedure('public.pdc_auditor_reject_history_mutation()') is null then
    raise exception 'PDC_AUDITOR_122_FOUNDATION_MISSING';
  end if;
end;
$guard$;

create table if not exists public.pdc_auditor_decisions (
  decision_id uuid primary key default gen_random_uuid(),
  finding_id uuid not null,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  evidence_fingerprint text not null check (evidence_fingerprint ~ '^[a-f0-9]{64}$'),
  finding_last_seen_run_id uuid not null,
  decision text not null check (decision in ('approved','denied')),
  reason text,
  decided_by_user_id uuid not null,
  decided_by_role text not null check (decided_by_role in ('operator','administrator')),
  decided_at timestamptz not null default clock_timestamp(),
  operational_change boolean not null default false check (not operational_change),
  execution_reference text check (execution_reference is null),
  foreign key (finding_id,dealer_code,environment)
    references public.pdc_auditor_findings(finding_id,dealer_code,environment) on delete restrict,
  foreign key (finding_last_seen_run_id,dealer_code,environment)
    references public.pdc_auditor_runs(run_id,dealer_code,environment) on delete restrict,
  unique (finding_id,evidence_fingerprint),
  check ((decision='denied' and reason is not null and length(reason) between 3 and 500)
      or (decision='approved' and (reason is null or length(reason) between 1 and 500))),
  check (reason is null or reason=btrim(reason))
);

create index if not exists pdc_auditor_decisions_scope_time_idx
  on public.pdc_auditor_decisions(dealer_code,environment,decided_at desc);

alter table public.pdc_auditor_revision
  drop constraint if exists pdc_auditor_revision_event_type_check;
alter table public.pdc_auditor_revision
  add constraint pdc_auditor_revision_event_type_check
  check (event_type in ('foundation','findings_appended','report_appended','config_appended','decision_recorded'));

drop trigger if exists pdc_auditor_decisions_immutable on public.pdc_auditor_decisions;
create trigger pdc_auditor_decisions_immutable
before update or delete on public.pdc_auditor_decisions
for each row execute function public.pdc_auditor_reject_history_mutation();

create or replace function public.get_pdc_auditor_review_queue(p_limit integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $queue$
declare
  v_scope jsonb := public.pdc_auditor_actor_scope();
  v_dealer text := v_scope->>'dealer_code';
  v_role text := v_scope->>'role';
  v_items jsonb;
begin
  if p_limit is null or p_limit<1 or p_limit>200 then
    raise exception 'pdc_auditor_invalid_review_limit' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'finding_id',q.finding_id,
    'stable_fingerprint',q.stable_fingerprint,
    'evidence_fingerprint',q.evidence_fingerprint,
    'last_seen_run_id',q.last_seen_run_id,
    'rule_key',q.rule_key,
    'category',q.category,
    'severity',q.severity,
    'summary_code',q.summary_code,
    'entity_type',q.entity_type,
    'entity_id',q.entity_id,
    'first_detected_at',q.first_detected_at,
    'last_detected_at',q.last_detected_at,
    'lifecycle_status',q.lifecycle_status,
    'decision',case when q.decision_id is null then null else jsonb_build_object(
      'decision_id',q.decision_id,'status',q.decision,'reason',q.reason,
      'decided_by_role',q.decided_by_role,'decided_at',q.decided_at,
      'operational_change',false) end
  ) order by q.severity_order,q.last_detected_at desc,q.finding_id),'[]'::jsonb)
  into v_items
  from (
    select f.*,d.decision_id,d.decision,d.reason,d.decided_by_role,d.decided_at,
      case f.severity when 'critical' then 0 when 'high' then 1 when 'medium' then 2 when 'low' then 3 else 4 end severity_order
    from public.pdc_auditor_findings f
    left join public.pdc_auditor_decisions d
      on d.finding_id=f.finding_id and d.dealer_code=f.dealer_code
      and d.environment=f.environment and d.evidence_fingerprint=f.evidence_fingerprint
    where f.dealer_code=v_dealer and f.environment='staging'
      and f.lifecycle_status='current'
    order by severity_order,f.last_detected_at desc,f.finding_id
    limit p_limit
  ) q;
  return jsonb_build_object(
    'ok',true,'code','pdc_auditor_review_queue','environment','staging',
    'dealer_code',v_dealer,'can_decide',v_role in ('operator','administrator'),
    'items',v_items
  );
end;
$queue$;

create or replace function public.record_pdc_auditor_decision(
  p_finding_id uuid,
  p_evidence_fingerprint text,
  p_last_seen_run_id uuid,
  p_decision text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $decide$
declare
  v_scope jsonb := public.pdc_auditor_actor_scope();
  v_uid uuid := (v_scope->>'user_id')::uuid;
  v_role text := v_scope->>'role';
  v_dealer text := v_scope->>'dealer_code';
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
  v_finding public.pdc_auditor_findings%rowtype;
  v_run public.pdc_auditor_runs%rowtype;
  v_existing public.pdc_auditor_decisions%rowtype;
  v_decision_id uuid;
begin
  if v_role not in ('operator','administrator') then
    raise exception 'pdc_auditor_decision_forbidden' using errcode='42501';
  end if;
  if p_finding_id is null or p_last_seen_run_id is null
     or coalesce(p_evidence_fingerprint,'') !~ '^[a-f0-9]{64}$'
     or p_decision not in ('approved','denied')
     or (p_decision='denied' and (v_reason is null or length(v_reason) not between 3 and 500))
     or (p_decision='approved' and v_reason is not null and length(v_reason)>500) then
    raise exception 'pdc_auditor_invalid_decision' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-auditor-decision:'||p_finding_id::text,0));
  select * into v_finding
  from public.pdc_auditor_findings f
  where f.finding_id=p_finding_id and f.dealer_code=v_dealer and f.environment='staging'
  for update;
  if not found then
    raise exception 'pdc_auditor_finding_not_found' using errcode='P0002';
  end if;
  if v_finding.lifecycle_status<>'current'
     or v_finding.evidence_fingerprint<>p_evidence_fingerprint
     or v_finding.last_seen_run_id<>p_last_seen_run_id then
    raise exception 'pdc_auditor_finding_stale' using errcode='40001';
  end if;
  select * into strict v_run
  from public.pdc_auditor_runs r
  where r.run_id=v_finding.last_seen_run_id
    and r.dealer_code=v_dealer and r.environment='staging';
  if public.pdc_auditor_operational_revision(v_dealer)<>v_run.operational_revision then
    raise exception 'pdc_auditor_finding_stale' using errcode='40001';
  end if;

  select * into v_existing
  from public.pdc_auditor_decisions d
  where d.finding_id=p_finding_id and d.evidence_fingerprint=p_evidence_fingerprint;
  if found then
    if v_existing.decision<>p_decision then
      raise exception 'pdc_auditor_already_decided' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'idempotent',true,'decision_id',v_existing.decision_id,
      'status',v_existing.decision,'operational_change',false,'execution_reference',null
    );
  end if;

  insert into public.pdc_auditor_decisions(
    finding_id,dealer_code,environment,evidence_fingerprint,finding_last_seen_run_id,
    decision,reason,decided_by_user_id,decided_by_role
  ) values(
    p_finding_id,v_dealer,'staging',p_evidence_fingerprint,p_last_seen_run_id,
    p_decision,v_reason,v_uid,v_role
  ) returning decision_id into v_decision_id;
  insert into public.pdc_auditor_revision(dealer_code,environment,run_id,event_type)
    values(v_dealer,'staging',p_last_seen_run_id,'decision_recorded');

  return jsonb_build_object(
    'ok',true,'idempotent',false,'decision_id',v_decision_id,
    'status',p_decision,'operational_change',false,'execution_reference',null
  );
end;
$decide$;

alter table public.pdc_auditor_decisions enable row level security;
revoke all on table public.pdc_auditor_decisions from public,anon,authenticated;
grant select on table public.pdc_auditor_decisions to authenticated;
drop policy if exists pdc_auditor_decisions_dealer_read on public.pdc_auditor_decisions;
create policy pdc_auditor_decisions_dealer_read on public.pdc_auditor_decisions
for select to authenticated
using(environment='staging' and dealer_code=(public.pdc_auditor_actor_scope()->>'dealer_code'));

revoke all on function public.get_pdc_auditor_review_queue(integer) from public,anon,authenticated;
grant execute on function public.get_pdc_auditor_review_queue(integer) to authenticated;
revoke all on function public.record_pdc_auditor_decision(uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.record_pdc_auditor_decision(uuid,text,uuid,text,text) to authenticated;

comment on table public.pdc_auditor_decisions is
  'Immutable human Approve/Deny dispositions for exact current auditor evidence. Never an operational execution authority.';
comment on function public.record_pdc_auditor_decision(uuid,text,uuid,text,text) is
  'Records one human disposition after role, dealer, evidence, run and operational-revision checks. Returns operational_change=false and cannot execute recommendations.';

commit;
