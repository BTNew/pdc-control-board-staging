-- Staging-only migration 123: exact-run, exact-reason and rule-current AI Auditor decisions.
-- This corrective migration is append-only because migration 122 is already installed.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_AUDITOR_123_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is null
     or not exists (select 1 from supabase_migrations.schema_migrations where version='122' and name='ai_auditor_human_review_decisions') then
    raise exception 'PDC_AUDITOR_123_PREDECESSOR_122_IDENTITY_MISMATCH';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version='123' and name<>'harden_ai_auditor_human_review_binding') then
    raise exception 'PDC_AUDITOR_123_VERSION_CONFLICT';
  end if;
end;
$guard$;

alter table public.pdc_auditor_decisions
  drop constraint if exists pdc_auditor_decisions_finding_id_evidence_fingerprint_key;
alter table public.pdc_auditor_decisions
  add constraint pdc_auditor_decisions_exact_occurrence_key
  unique (finding_id,evidence_fingerprint,finding_last_seen_run_id);

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
    'run_operational_revision',q.run_operational_revision,
    'run_rule_set_hash',q.run_rule_set_hash,
    'run_model_key',q.run_model_key,
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
    select f.*,r.operational_revision run_operational_revision,r.rule_set_hash run_rule_set_hash,
      r.model_key run_model_key,d.decision_id,d.decision,d.reason,d.decided_by_role,d.decided_at,
      case f.severity when 'critical' then 0 when 'high' then 1 when 'medium' then 2 when 'low' then 3 else 4 end severity_order
    from public.pdc_auditor_findings f
    join public.pdc_auditor_runs r
      on r.run_id=f.last_seen_run_id and r.dealer_code=f.dealer_code and r.environment=f.environment
    left join public.pdc_auditor_decisions d
      on d.finding_id=f.finding_id and d.dealer_code=f.dealer_code
      and d.environment=f.environment and d.evidence_fingerprint=f.evidence_fingerprint
      and d.finding_last_seen_run_id=f.last_seen_run_id
    where f.dealer_code=v_dealer and f.environment='staging' and f.lifecycle_status='current'
    order by severity_order,f.last_detected_at desc,f.finding_id
    limit p_limit
  ) q;
  return jsonb_build_object(
    'ok',true,'code','pdc_auditor_review_queue','environment','staging',
    'dealer_code',v_dealer,'can_decide',v_role in ('operator','administrator'),'items',v_items
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
  v_snapshot jsonb;
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

  select * into v_existing
  from public.pdc_auditor_decisions d
  where d.finding_id=p_finding_id and d.dealer_code=v_dealer and d.environment='staging'
    and d.evidence_fingerprint=p_evidence_fingerprint
    and d.finding_last_seen_run_id=p_last_seen_run_id;
  if found then
    if v_existing.decision<>p_decision or v_existing.reason is distinct from v_reason then
      raise exception 'pdc_auditor_already_decided' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'idempotent',true,'decision_id',v_existing.decision_id,
      'status',v_existing.decision,'reason',v_existing.reason,
      'operational_change',false,'execution_reference',null
    );
  end if;

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
  where r.run_id=p_last_seen_run_id and r.dealer_code=v_dealer and r.environment='staging';
  v_snapshot := public.get_pdc_auditor_snapshot(null,1);
  if v_snapshot->>'operational_revision'<>v_run.operational_revision
     or v_snapshot->>'rule_set_hash'<>v_run.rule_set_hash then
    raise exception 'pdc_auditor_finding_stale' using errcode='40001';
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
    'status',p_decision,'reason',v_reason,
    'operational_change',false,'execution_reference',null
  );
end;
$decide$;

revoke all on function public.get_pdc_auditor_review_queue(integer) from public,anon,authenticated;
grant execute on function public.get_pdc_auditor_review_queue(integer) to authenticated;
revoke all on function public.record_pdc_auditor_decision(uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.record_pdc_auditor_decision(uuid,text,uuid,text,text) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('123','harden_ai_auditor_human_review_binding',array['staging-only exact occurrence and freshness hardening']);

comment on function public.record_pdc_auditor_decision(uuid,text,uuid,text,text) is
  'Records one exact-run, exact-reason human disposition after role, dealer, evidence, operational-revision and rule-set freshness checks. Never executes recommendations.';

commit;
