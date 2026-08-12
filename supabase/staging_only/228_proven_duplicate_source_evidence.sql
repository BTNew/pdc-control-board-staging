-- Staging-only migration 228: make proven duplicate evidence compatible with source uniqueness.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-228-proven-duplicate-source-evidence',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='227')
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>227)
     or exists(select 1 from supabase_migrations.schema_migrations where version='228') then
    raise exception 'PDC_228_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

-- Preserve the exact 225 implementation as a private base function. The public wrapper
-- below can only narrow its duplicate-evidence ambiguity; all other action results pass through.
alter function public.pdc_auditor_plan_candidates_225(text,text,jsonb)
  rename to pdc_auditor_plan_candidates_base_225;
revoke all on function public.pdc_auditor_plan_candidates_base_225(text,text,jsonb)
  from public,anon,authenticated,service_role;

create function public.pdc_auditor_plan_candidates_225(
  p_dealer_code text,p_action text,p_scope jsonb
)
returns table(
  disposition text,operation_action text,vehicle_id uuid,stock_number text,
  job_card_number text,operation_line_id uuid,matched_operation_line_id uuid,
  old_value jsonb,new_value jsonb,match_kind text,match_reason text,
  source_evidence_hash text,exclusion_codes text[],ambiguity_code text
)
language sql stable security definer set search_path=pg_catalog,public
as $wrapper$
with base as materialized (
  select * from public.pdc_auditor_plan_candidates_base_225(p_dealer_code,p_action,p_scope)
), evidence as (
  select b.*,
    d.source_uid duplicate_source_uid,r.source_uid retained_source_uid,
    d.operation_fingerprint duplicate_fingerprint,r.operation_fingerprint retained_fingerprint,
    array_remove(b.exclusion_codes,'duplicated_source_evidence') remaining_exclusions,
    (p_action='duplicate_bullbars'
      and b.operation_action='delete'
      and b.matched_operation_line_id is not null
      and d.source_uid=r.source_uid
      and d.operation_fingerprint=r.operation_fingerprint
      and d.source_hash<>r.source_hash) proven_duplicated_evidence
  from base b
  left join public.pdc_authenticated_email_operation_lines d
    on d.operation_line_id=b.operation_line_id
  left join public.pdc_authenticated_email_operation_lines r
    on r.operation_line_id=b.matched_operation_line_id
)
select
  case when proven_duplicated_evidence and remaining_exclusions='{}'::text[]
       then 'proposed' else disposition end,
  operation_action,vehicle_id,stock_number,job_card_number,operation_line_id,
  matched_operation_line_id,old_value,new_value,match_kind,
  case when proven_duplicated_evidence and remaining_exclusions='{}'::text[]
       then match_reason||' Duplicate source evidence is proven by the same immutable source UID and operation fingerprint; distinct row hashes satisfy source-table uniqueness.'
       else match_reason end,
  source_evidence_hash,
  case when proven_duplicated_evidence then remaining_exclusions else exclusion_codes end,
  case when proven_duplicated_evidence and remaining_exclusions='{}'::text[]
       then null else ambiguity_code end
from evidence
$wrapper$;
revoke all on function public.pdc_auditor_plan_candidates_225(text,text,jsonb)
  from public,anon,authenticated,service_role;

comment on function public.pdc_auditor_plan_candidates_225(text,text,jsonb) is
  'Migration-228 wrapper over immutable 225 planner. A same-vehicle/job-card/code/description bullbar row is proven duplicate only when retained and superseded rows also share source UID and operation fingerprint while having distinct source hashes required by source uniqueness. Variant, quantity, revised, manual, completed and different-evidence rows remain review-only.';

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '228','proven_duplicate_source_evidence',array[
    'staging sentinel cdsmnqxtyyoeoznmbidd and exact predecessor 227',
    'preserve migration-225 candidate function as private base and expose append-only compatibility wrapper',
    'proven duplicate requires same source UID and operation fingerprint plus distinct source hashes required by source uniqueness',
    'all kit side position quantity revised manual completed and different-evidence safeguards remain review-only',
    'no direct grants and no production access'
  ]
);
notify pgrst,'reload schema';
commit;
