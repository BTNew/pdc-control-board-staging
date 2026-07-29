-- Staging-only migration 115: beta AI auditor read-only foundation.
-- Deployment predecessor identity: live staging ledger 114 = contain_multi_attachment_email_import.
-- Repository migration 110 and its predecessors provide the tracked schema dependencies; live-only
-- staging migrations 111/112/113/114 are verified by ledger identity and are never overwritten by this file.
-- This migration creates auditor-owned append/history data only. It never writes operational tables.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_AUDITOR_115_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is null
     or not exists (
       select 1 from supabase_migrations.schema_migrations
       where version = '114' and name = 'contain_multi_attachment_email_import'
     ) then
    raise exception 'PDC_AUDITOR_115_PREDECESSOR_114_IDENTITY_MISMATCH';
  end if;
  if exists (
       select 1 from supabase_migrations.schema_migrations
       where version = '115' and name <> 'beta_ai_auditor_foundation'
     ) then
    raise exception 'PDC_AUDITOR_115_VERSION_CONFLICT';
  end if;
  if to_regclass('public.vehicles') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.workshop_bookings') is null
     or to_regclass('public.workshop_booking_assignments') is null
     or to_regclass('public.workshop_stages') is null
     or to_regclass('public.workshop_revision') is null
     or to_regclass('public.pdc_email_vehicle_revision') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_workshop_line_adjustments') is null
     or to_regclass('public.vehicle_sublet_providers') is null
     or to_regclass('public.pdc_sublet_bookings') is null
     or to_regprocedure('public.workshop_stage_code_for_work_key(text)') is null
     or to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') is null then
    raise exception 'PDC_AUDITOR_115_DEPENDENCY_110_MISSING';
  end if;
end;
$guard$;

-- Explicit server-owned identity-to-dealer authority. JWT dealer claims are never authority.
create table if not exists public.pdc_auditor_user_dealer_scopes (
  scope_id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  normalized_email text not null check (normalized_email = lower(btrim(normalized_email)) and normalized_email ~ '^[^[:space:]@]+@[^[:space:]@]+$'),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  unique (auth_user_id, normalized_email, dealer_code, environment)
);
create unique index if not exists pdc_auditor_user_one_active_scope_idx
  on public.pdc_auditor_user_dealer_scopes(auth_user_id, normalized_email, environment) where active;

-- Workers are ordinary authenticated users explicitly enrolled in both identity tables.
create table if not exists public.pdc_auditor_worker_identities (
  worker_identity_id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  normalized_email text not null check (normalized_email = lower(btrim(normalized_email)) and normalized_email ~ '^[^[:space:]@]+@[^[:space:]@]+$'),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  unique (auth_user_id, normalized_email, dealer_code, environment)
);
create unique index if not exists pdc_auditor_worker_one_active_identity_idx
  on public.pdc_auditor_worker_identities(auth_user_id, normalized_email, environment) where active;

-- Auditor-owned relationship authority. There is deliberately no client write RPC or
-- direct write grant. Rows are append-only, exact-ID assertions made by a separately
-- approved server-side ceremony; legacy stage/work-key/metadata matches are not authority.
create table if not exists public.pdc_auditor_booking_work_relations (
  relation_id uuid primary key default gen_random_uuid(),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  booking_id uuid not null references public.workshop_bookings(id) on delete restrict,
  work_item_id uuid not null references public.vehicle_work_items(id) on delete restrict,
  relation_kind text not null check (relation_kind in ('explicit_fk','authoritative_relation')),
  relation_action text not null default 'asserted' check (relation_action in ('asserted','revoked')),
  supersedes_relation_id uuid,
  active boolean not null default true,
  source_revision bigint not null check (source_revision >= 1),
  source_recorded_at timestamptz not null,
  recorded_at timestamptz not null default clock_timestamp(),
  unique (relation_id,dealer_code,environment),
  unique (dealer_code,environment,booking_id,source_revision),
  foreign key (supersedes_relation_id,dealer_code,environment)
    references public.pdc_auditor_booking_work_relations(relation_id,dealer_code,environment) on delete restrict,
  check ((supersedes_relation_id is null and relation_action='asserted')
    or supersedes_relation_id is not null),
  check (source_recorded_at <= recorded_at)
);
create unique index if not exists pdc_auditor_booking_work_relations_one_successor_idx
  on public.pdc_auditor_booking_work_relations(supersedes_relation_id) where supersedes_relation_id is not null;
create index if not exists pdc_auditor_booking_work_relations_booking_idx
  on public.pdc_auditor_booking_work_relations(dealer_code,environment,booking_id,active,source_revision desc);
create index if not exists pdc_auditor_booking_work_relations_work_idx
  on public.pdc_auditor_booking_work_relations(dealer_code,environment,work_item_id,active,source_revision desc);

create table if not exists public.pdc_auditor_runs (
  run_id uuid primary key,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  snapshot_generated_at timestamptz not null,
  snapshot_response_revision text not null check (snapshot_response_revision ~ '^[a-f0-9]{64}$'),
  operational_revision text not null check (operational_revision ~ '^[a-f0-9]{64}$'),
  rule_set_hash text not null check (rule_set_hash ~ '^[a-f0-9]{64}$'),
  snapshot_manifest_hash text not null check (snapshot_manifest_hash ~ '^[a-f0-9]{64}$'),
  payload_hash text not null check (payload_hash ~ '^[a-f0-9]{64}$'),
  snapshot_page_count integer not null check (snapshot_page_count between 1 and 5),
  snapshot_vehicle_count integer not null check (snapshot_vehicle_count between 1 and 500),
  snapshot_complete boolean not null check (snapshot_complete),
  model_key text not null check (length(model_key) between 1 and 80 and model_key = btrim(model_key) and model_key !~ '[[:cntrl:]]'),
  status text not null check (status in ('accepted','completed','failed_validation')),
  finding_count integer not null check (finding_count between 0 and 100),
  submitted_at timestamptz not null default clock_timestamp(),
  unique (dealer_code, environment, request_hash),
  unique (run_id, dealer_code, environment)
);

-- One mutable current-state row per server-derived stable recommendation/evidence fingerprint.
create table if not exists public.pdc_auditor_findings (
  finding_id uuid primary key,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  stable_fingerprint text not null check (stable_fingerprint ~ '^[a-f0-9]{64}$'),
  evidence_fingerprint text not null check (evidence_fingerprint ~ '^[a-f0-9]{64}$'),
  rule_key text not null check (rule_key ~ '^[a-z][a-z0-9_]{2,63}$'),
  category text not null check (category in ('station_compatibility','department_mismatch','booking_work_relationship','data_quality','schedule_risk')),
  severity text not null check (severity in ('info','low','medium','high','critical')),
  summary_code text not null check (summary_code ~ '^[a-z][a-z0-9_]{2,79}$'),
  entity_type text not null check (entity_type in ('vehicle','work_item','booking','operation_line','line_adjustment')),
  entity_id uuid not null,
  first_seen_run_id uuid not null,
  last_seen_run_id uuid not null,
  first_detected_at timestamptz not null,
  last_detected_at timestamptz not null,
  last_evidence_change_at timestamptz not null,
  lifecycle_status text not null check (lifecycle_status in ('current','resolved')),
  resolved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (first_seen_run_id, dealer_code, environment)
    references public.pdc_auditor_runs(run_id, dealer_code, environment) on delete restrict,
  foreign key (last_seen_run_id, dealer_code, environment)
    references public.pdc_auditor_runs(run_id, dealer_code, environment) on delete restrict,
  unique (dealer_code, environment, stable_fingerprint),
  unique (finding_id, dealer_code, environment),
  check ((lifecycle_status='current' and resolved_at is null) or (lifecycle_status='resolved' and resolved_at is not null))
);

create table if not exists public.pdc_auditor_finding_occurrences (
  occurrence_id bigint generated always as identity primary key,
  finding_id uuid not null,
  run_id uuid not null,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  detected_at timestamptz not null,
  severity text not null check (severity in ('info','low','medium','high','critical')),
  score numeric(5,2) not null check (score between 0 and 100),
  confidence numeric(4,3) not null check (confidence between 0 and 1),
  scoring_version text not null check (scoring_version ~ '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,39}$'),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (finding_id, dealer_code, environment)
    references public.pdc_auditor_findings(finding_id, dealer_code, environment) on delete restrict,
  foreign key (run_id, dealer_code, environment)
    references public.pdc_auditor_runs(run_id, dealer_code, environment) on delete restrict,
  unique (finding_id, run_id)
);

create table if not exists public.pdc_auditor_finding_history (
  finding_history_id bigint generated always as identity primary key,
  finding_id uuid not null,
  run_id uuid not null,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  event_type text not null check (event_type in ('opened','observed','resolved','reopened')),
  event_at timestamptz not null default clock_timestamp(),
  foreign key (finding_id, dealer_code, environment)
    references public.pdc_auditor_findings(finding_id, dealer_code, environment) on delete restrict,
  foreign key (run_id, dealer_code, environment)
    references public.pdc_auditor_runs(run_id, dealer_code, environment) on delete restrict
);

-- Stable evidence is stored once with the current finding; run sightings live in occurrences.
create table if not exists public.pdc_auditor_finding_evidence (
  evidence_id uuid primary key default gen_random_uuid(),
  finding_id uuid not null,
  occurrence_id bigint not null,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  entity_type text not null check (entity_type in ('vehicle','work_item','booking','operation_line','line_adjustment')),
  entity_id uuid not null,
  signal_code text not null check (signal_code ~ '^[a-z][a-z0-9_]{2,79}$'),
  field_code text not null check (field_code ~ '^[a-z][a-z0-9_]{1,63}$'),
  numeric_value numeric(12,3) check (numeric_value between -99999999.999 and 99999999.999),
  boolean_value boolean,
  timestamp_value timestamptz,
  ordinal smallint not null check (ordinal between 1 and 20),
  created_at timestamptz not null default clock_timestamp(),
  check (num_nonnulls(numeric_value, boolean_value, timestamp_value) <= 1),
  foreign key (finding_id, dealer_code, environment)
    references public.pdc_auditor_findings(finding_id, dealer_code, environment) on delete restrict,
  foreign key (occurrence_id) references public.pdc_auditor_finding_occurrences(occurrence_id) on delete restrict,
  unique (occurrence_id, ordinal)
);

create table if not exists public.pdc_auditor_risk_scores (
  risk_score_id uuid primary key default gen_random_uuid(),
  finding_id uuid not null,
  occurrence_id bigint not null,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  score numeric(5,2) not null check (score between 0 and 100),
  confidence numeric(4,3) not null check (confidence between 0 and 1),
  scoring_version text not null check (scoring_version ~ '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,39}$'),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (occurrence_id) references public.pdc_auditor_finding_occurrences(occurrence_id) on delete restrict,
  foreign key (finding_id, dealer_code, environment)
    references public.pdc_auditor_findings(finding_id, dealer_code, environment) on delete restrict,
  unique (occurrence_id, scoring_version)
);

create table if not exists public.pdc_auditor_rule_config (
  rule_config_id uuid primary key default gen_random_uuid(),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  rule_key text not null check (rule_key ~ '^[a-z][a-z0-9_]{2,63}$'),
  config_version integer not null check (config_version between 1 and 1000000),
  config jsonb not null check (
    jsonb_typeof(config) = 'object'
    and octet_length(config::text) between 2 and 8192
  ),
  provisional boolean not null default true,
  effective_from timestamptz not null default clock_timestamp(),
  effective_to timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  check (effective_to is null or effective_to > effective_from),
  unique (dealer_code, environment, rule_key, config_version)
);

create table if not exists public.pdc_auditor_report_runs (
  report_run_id uuid primary key default gen_random_uuid(),
  run_id uuid not null,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  report_type text not null check (report_type in ('summary_json','dealer_digest_json')),
  report_status text not null check (report_status in ('requested','generated','failed')),
  report_manifest jsonb not null default '{}'::jsonb check (
    jsonb_typeof(report_manifest) = 'object'
    and octet_length(report_manifest::text) <= 4096
    and not (report_manifest ?| array['raw_document','raw_documents','customer_name','customer','notes','description'])
  ),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (run_id, dealer_code, environment)
    references public.pdc_auditor_runs(run_id, dealer_code, environment) on delete restrict
);

-- Revision is an append-only invalidation history. Realtime consumers refetch; events are not authority.
create table if not exists public.pdc_auditor_revision (
  revision_id bigint generated always as identity primary key,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment = 'staging'),
  run_id uuid,
  event_type text not null check (event_type in ('foundation','findings_appended','report_appended','config_appended')),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (run_id, dealer_code, environment)
    references public.pdc_auditor_runs(run_id, dealer_code, environment) on delete restrict
);

create index if not exists pdc_auditor_runs_scope_time_idx on public.pdc_auditor_runs(dealer_code, environment, submitted_at desc);
create index if not exists pdc_auditor_findings_scope_time_idx on public.pdc_auditor_findings(dealer_code, environment, created_at desc);
create index if not exists pdc_auditor_findings_entity_idx on public.pdc_auditor_findings(dealer_code, environment, entity_type, entity_id);
create index if not exists pdc_auditor_evidence_finding_idx on public.pdc_auditor_finding_evidence(finding_id, ordinal);
create index if not exists pdc_auditor_scores_finding_idx on public.pdc_auditor_risk_scores(finding_id, created_at desc);
create index if not exists pdc_auditor_rule_config_current_idx on public.pdc_auditor_rule_config(dealer_code, environment, rule_key, effective_from desc);
create index if not exists pdc_auditor_report_runs_run_idx on public.pdc_auditor_report_runs(run_id, created_at desc);
create index if not exists pdc_auditor_revision_scope_idx on public.pdc_auditor_revision(dealer_code, environment, revision_id desc);

-- Exact actor binding: auth UUID/email, one approved role row and one exact active
-- pdc_auditor_user_dealer_scopes row. A JWT dealer claim is ignored.
create or replace function public.pdc_auditor_actor_scope()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $scope$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text;
  v_dealer text;
  v_count integer;
begin
  if v_uid is null or v_email = '' then
    raise exception 'pdc_auditor_unauthorized' using errcode='42501';
  end if;
  select count(*), min(r.role::text)
    into v_count, v_role
  from public.pdc_user_roles r
  join auth.users au on au.id=v_uid and lower(coalesce(au.email,''))=v_email
  where lower(r.email) = v_email
    and r.auth_user_id = v_uid
    and r.active and r.account_status = 'approved'
    and r.role::text in ('viewer','operator','administrator');
  if v_count <> 1 then
    raise exception 'pdc_auditor_unauthorized' using errcode='42501';
  end if;
  select count(*), min(s.dealer_code)
    into v_count, v_dealer
  from public.pdc_auditor_user_dealer_scopes s
  where s.auth_user_id=v_uid and s.normalized_email=v_email
    and s.environment='staging' and s.active;
  if v_count <> 1 then
    raise exception 'pdc_auditor_scope_unauthorized' using errcode='42501';
  end if;
  return jsonb_build_object('user_id',v_uid,'email',v_email,'role',v_role,
    'dealer_code',v_dealer,'environment','staging');
end;
$scope$;
revoke all on function public.pdc_auditor_actor_scope() from public,anon,authenticated;
grant execute on function public.pdc_auditor_actor_scope() to authenticated;

-- Worker authorization is an authenticated identity plus exact email and exact dealer membership
-- in both server-owned tables. It never trusts a JWT dealer claim.
create or replace function public.pdc_auditor_worker_scope(p_dealer_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $worker$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_count integer;
begin
  if v_uid is null or v_email='' or p_dealer_code not in ('14450','37047') then
    raise exception 'pdc_auditor_worker_unauthorized' using errcode='42501';
  end if;
  select count(*) into v_count
  from public.pdc_auditor_worker_identities w
  join public.pdc_auditor_user_dealer_scopes s
    on s.auth_user_id=w.auth_user_id and s.normalized_email=w.normalized_email
   and s.dealer_code=w.dealer_code and s.environment=w.environment and s.active
  join public.pdc_user_roles r
    on r.auth_user_id=v_uid and lower(r.email)=v_email
   and r.active and r.account_status='approved'
   and r.role::text in ('operator','administrator')
  join auth.users au on au.id=v_uid and lower(coalesce(au.email,''))=v_email
  where w.auth_user_id=v_uid and w.normalized_email=v_email
    and w.dealer_code=p_dealer_code and w.environment='staging' and w.active;
  if v_count <> 1 then
    raise exception 'pdc_auditor_worker_unauthorized' using errcode='42501';
  end if;
  return jsonb_build_object('user_id',v_uid,'email',v_email,
    'dealer_code',p_dealer_code,'environment','staging');
end;
$worker$;
revoke all on function public.pdc_auditor_worker_scope(text) from public,anon,authenticated;

-- Immutable history guard. No update/delete API exists for auditor history/configuration.
create or replace function public.pdc_auditor_reject_history_mutation()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $immutable$
begin
  raise exception 'pdc_auditor_history_is_append_only' using errcode='55000';
end;
$immutable$;
revoke all on function public.pdc_auditor_reject_history_mutation() from public,anon,authenticated;

create or replace function public.pdc_auditor_valid_timestamptz(p_value text)
returns boolean
language plpgsql
immutable
security definer
set search_path=pg_catalog,public
as $valid_timestamp$
begin
  if p_value is null or length(p_value) not between 20 and 40
     or p_value !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
    return false;
  end if;
  perform p_value::timestamptz;
  return true;
exception when invalid_datetime_format or datetime_field_overflow then
  return false;
end;
$valid_timestamp$;
revoke all on function public.pdc_auditor_valid_timestamptz(text) from public,anon,authenticated;

create or replace function public.pdc_auditor_json_has_sensitive_key(p_document jsonb)
returns boolean
language sql
immutable
security definer
set search_path=pg_catalog,public
as $sensitive_key$
  with recursive walk(key,value) as (
    select null::text,p_document
    union all
    select child.key,child.value
    from walk parent
    cross join lateral (
      select object_item.key,object_item.value
      from jsonb_each(case when jsonb_typeof(parent.value)='object' then parent.value else '{}'::jsonb end) object_item
      union all
      select null::text,array_item.value
      from jsonb_array_elements(case when jsonb_typeof(parent.value)='array' then parent.value else '[]'::jsonb end) array_item
    ) child
  )
  select exists(
    select 1 from walk
    where key ~* '^(customer|client|email|phone|vin|registration|notes?|description|reason|subject|body|source_uid|raw_.*|metadata)$'
  )
$sensitive_key$;
revoke all on function public.pdc_auditor_json_has_sensitive_key(jsonb) from public,anon,authenticated;

-- Dealer provenance is derived only from the uniquely scoped current Navision
-- backend record set for the canonical vehicle. vehicles.source_batch_id is not authority.
create or replace function public.pdc_auditor_vehicle_dealer(p_vehicle_id uuid)
returns text
language sql
stable
security definer
set search_path=pg_catalog,public
as $vehicle_dealer$
  select case
    when count(*)>0
     and count(distinct r.dealer_code)=1
     and min(r.dealer_code) in ('14450','37047')
    then min(r.dealer_code)
    else null
  end
  from public.navision_backend_records r
  where r.canonical_vehicle_id=p_vehicle_id
    and r.is_current
    and r.record_status='current'
$vehicle_dealer$;
revoke all on function public.pdc_auditor_vehicle_dealer(uuid) from public,anon,authenticated;

-- Stable, content-bearing revision of every operational family consumed by rules.
-- Full rows are hashed server-side but never returned. This intentionally includes
-- history, mapping, intake and outbox state so a later page/run cannot silently use
-- an older operational state merely because the singleton revisions did not move.
create or replace function public.pdc_auditor_operational_revision(p_dealer_code text)
returns text
language sql
stable
security definer
set search_path=pg_catalog,public
as $operational_revision$
  with scoped as materialized (
    select v.id
    from public.vehicles v
    where v.deleted_at is null
      and public.pdc_auditor_vehicle_dealer(v.id)=p_dealer_code
  ), components as (
    select 'vehicles' k,coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'') v
      from public.vehicles x join scoped s on s.id=x.id
    union all select 'vehicle_work_items',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.vehicle_work_items x join scoped s on s.id=x.vehicle_id
    union all select 'workshop_bookings',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.workshop_bookings x join scoped s on s.id=x.vehicle_id
    union all select 'workshop_booking_assignments',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.workshop_booking_assignments x join public.workshop_bookings b on b.id=x.booking_id join scoped s on s.id=b.vehicle_id
    union all select 'workshop_booking_history',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.workshop_booking_history x join public.workshop_bookings b on b.id=x.booking_id join scoped s on s.id=b.vehicle_id
    union all select 'vehicle_parts_updates',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.vehicle_parts_updates x join scoped s on s.id=x.vehicle_id
    union all select 'vehicle_movements',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.vehicle_movements x join scoped s on s.id=x.vehicle_id
    union all select 'vehicle_master_history',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.vehicle_master_history x join scoped s on s.id=x.vehicle_id
    union all select 'vehicle_master_source_records',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.vehicle_master_source_records x join scoped s on s.id=x.vehicle_id
    union all select 'vehicle_aliases',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.vehicle_aliases x join scoped s on s.id=x.vehicle_id
    union all select 'pdc_authenticated_email_operation_lines',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.pdc_authenticated_email_operation_lines x join scoped s on s.id=x.vehicle_id
    union all select 'vehicle_workshop_line_adjustments',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.vehicle_workshop_line_adjustments x join scoped s on s.id=x.vehicle_id
    union all select 'vehicle_sublet_providers',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.vehicle_sublet_providers x join scoped s on s.id=x.vehicle_id
    union all select 'pdc_sublet_bookings',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.pdc_sublet_bookings x join scoped s on s.id=x.vehicle_id
    union all select 'navision_backend_records',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.navision_backend_records x join scoped s on s.id=x.canonical_vehicle_id
    union all select 'pdc_ai_intake_proposals',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.pdc_ai_intake_proposals x join public.navision_backend_records n on n.id=x.backend_record_id join scoped s on s.id=n.canonical_vehicle_id
    union all select 'pdc_ai_intake_history',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.pdc_ai_intake_history x join public.pdc_ai_intake_proposals p on p.proposal_id=x.proposal_id
      join public.navision_backend_records n on n.id=p.backend_record_id join scoped s on s.id=n.canonical_vehicle_id
    union all select 'vehicle_notifications',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from public.vehicle_notifications x join scoped s on s.id=x.vehicle_id
    union all select 'workshop_reference',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from (select 'stage' kind,to_jsonb(s) row from public.workshop_stages s
            union all select 'bay',to_jsonb(b) from public.workshop_bays b
            union all select 'technician',to_jsonb(t) from public.workshop_technicians t
            union all select 'setting',to_jsonb(w) from public.workshop_settings w) x
    union all select 'revisions',coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')
      from (select 'workshop_revision' kind,to_jsonb(r) row from public.workshop_revision r
            union all select 'workshop_station_revision',to_jsonb(r) from public.workshop_station_revision r
            union all select 'vehicle_master_revision',to_jsonb(r) from public.vehicle_master_revision r
            union all select 'vehicle_lifecycle_resolver_revision',to_jsonb(r) from public.vehicle_lifecycle_resolver_revision r
            union all select 'navision_backend_revision',to_jsonb(r) from public.navision_backend_revision r
            union all select 'pdc_ai_intake_revision',to_jsonb(r) from public.pdc_ai_intake_revision r
            union all select 'pdc_email_vehicle_revision',to_jsonb(r) from public.pdc_email_vehicle_revision r) x
  ), canonical as (select string_agg(k||':'||md5(v),'|' order by k) value from components)
  select md5('pdc-auditor-operational-v1a|'||value)||md5('pdc-auditor-operational-v1b|'||value)
  from canonical
$operational_revision$;
revoke all on function public.pdc_auditor_operational_revision(text) from public,anon,authenticated;

create or replace function public.pdc_auditor_entity_in_scope(
  p_dealer_code text,
  p_entity_type text,
  p_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,public
as $entity_scope$
  select p_dealer_code in ('14450','37047') and case p_entity_type
    when 'vehicle' then exists(
      select 1 from public.vehicles v
      where v.id=p_entity_id and public.pdc_auditor_vehicle_dealer(v.id)=p_dealer_code and v.deleted_at is null)
    when 'work_item' then exists(
      select 1 from public.vehicle_work_items wi join public.vehicles v on v.id=wi.vehicle_id
      where wi.id=p_entity_id and public.pdc_auditor_vehicle_dealer(v.id)=p_dealer_code and v.deleted_at is null)
    when 'booking' then exists(
      select 1 from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id
      where b.id=p_entity_id and public.pdc_auditor_vehicle_dealer(v.id)=p_dealer_code and v.deleted_at is null)
    when 'operation_line' then exists(
      select 1 from public.pdc_authenticated_email_operation_lines ol join public.vehicles v on v.id=ol.vehicle_id
      where ol.operation_line_id=p_entity_id and public.pdc_auditor_vehicle_dealer(v.id)=p_dealer_code and v.deleted_at is null)
    when 'line_adjustment' then exists(
      select 1 from public.vehicle_workshop_line_adjustments a join public.vehicles v on v.id=a.vehicle_id
      where a.adjustment_id=p_entity_id and public.pdc_auditor_vehicle_dealer(v.id)=p_dealer_code and v.deleted_at is null)
    else false
  end
$entity_scope$;
revoke all on function public.pdc_auditor_entity_in_scope(text,text,uuid) from public,anon,authenticated;

drop trigger if exists pdc_auditor_runs_immutable on public.pdc_auditor_runs;
create trigger pdc_auditor_runs_immutable before update or delete on public.pdc_auditor_runs
for each row execute function public.pdc_auditor_reject_history_mutation();
-- pdc_auditor_findings is the narrowly mutable current-state projection; only the
-- SECURITY DEFINER submission function can write it because direct writes are revoked.
drop trigger if exists pdc_auditor_finding_occurrences_immutable on public.pdc_auditor_finding_occurrences;
create trigger pdc_auditor_finding_occurrences_immutable before update or delete on public.pdc_auditor_finding_occurrences
for each row execute function public.pdc_auditor_reject_history_mutation();
drop trigger if exists pdc_auditor_finding_history_immutable on public.pdc_auditor_finding_history;
create trigger pdc_auditor_finding_history_immutable before update or delete on public.pdc_auditor_finding_history
for each row execute function public.pdc_auditor_reject_history_mutation();
drop trigger if exists pdc_auditor_finding_evidence_immutable on public.pdc_auditor_finding_evidence;
create trigger pdc_auditor_finding_evidence_immutable before update or delete on public.pdc_auditor_finding_evidence
for each row execute function public.pdc_auditor_reject_history_mutation();
drop trigger if exists pdc_auditor_risk_scores_immutable on public.pdc_auditor_risk_scores;
create trigger pdc_auditor_risk_scores_immutable before update or delete on public.pdc_auditor_risk_scores
for each row execute function public.pdc_auditor_reject_history_mutation();
drop trigger if exists pdc_auditor_rule_config_immutable on public.pdc_auditor_rule_config;
create trigger pdc_auditor_rule_config_immutable before update or delete on public.pdc_auditor_rule_config
for each row execute function public.pdc_auditor_reject_history_mutation();
drop trigger if exists pdc_auditor_report_runs_immutable on public.pdc_auditor_report_runs;
create trigger pdc_auditor_report_runs_immutable before update or delete on public.pdc_auditor_report_runs
for each row execute function public.pdc_auditor_reject_history_mutation();
drop trigger if exists pdc_auditor_revision_immutable on public.pdc_auditor_revision;
create trigger pdc_auditor_revision_immutable before update or delete on public.pdc_auditor_revision
for each row execute function public.pdc_auditor_reject_history_mutation();
drop trigger if exists pdc_auditor_booking_work_relations_immutable on public.pdc_auditor_booking_work_relations;
create trigger pdc_auditor_booking_work_relations_immutable before update or delete on public.pdc_auditor_booking_work_relations
for each row execute function public.pdc_auditor_reject_history_mutation();

-- Canonical read-only snapshot. Every object is allowlisted and bounded. It never serializes
-- whole rows, raw email/document data, free text, actor/customer identity, or browser state.
create or replace function public.get_pdc_auditor_snapshot(
  p_after_vehicle_id uuid default null,
  p_page_size integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $snapshot$
declare
  v_scope jsonb := public.pdc_auditor_actor_scope();
  v_dealer text := v_scope->>'dealer_code';
  v_limit integer;
  v_items jsonb;
  v_has_more boolean;
  v_next uuid;
  v_workshop_revision bigint;
  v_email_revision bigint;
  v_auditor_revision bigint;
  v_relation_revision bigint;
  v_config_revision bigint;
  v_operational_revision text;
  v_rule_set_hash text;
  v_response_revision text;
  v_configs jsonb;
  v_calendar_config jsonb;
  v_resources jsonb;
  v_total_vehicle_count integer;
  v_page_item_count integer;
begin
  if p_page_size is null or p_page_size < 1 or p_page_size > 100 then
    raise exception 'pdc_auditor_invalid_page_size' using errcode='22023';
  end if;
  v_limit := p_page_size;

  select coalesce(revision,0) into v_workshop_revision from public.workshop_revision where id=1;
  select coalesce(revision,0) into v_email_revision from public.pdc_email_vehicle_revision where singleton;
  select coalesce(max(revision_id),0) into v_auditor_revision
    from public.pdc_auditor_revision where dealer_code=v_dealer and environment='staging';
  select coalesce(max(source_revision),0) into v_relation_revision
    from public.pdc_auditor_booking_work_relations where dealer_code=v_dealer and environment='staging';
  select coalesce(max(config_version),0) into v_config_revision
    from public.pdc_auditor_rule_config where dealer_code=v_dealer and environment='staging';
  v_operational_revision := public.pdc_auditor_operational_revision(v_dealer);
  select md5('pdc-auditor-rules-v1a|'||coalesce(string_agg(c.rule_key||':'||c.config_version||':'||md5(c.config::text),'|' order by c.rule_key,c.config_version),''))
      ||md5('pdc-auditor-rules-v1b|'||coalesce(string_agg(c.rule_key||':'||c.config_version||':'||md5(c.config::text),'|' order by c.rule_key,c.config_version),''))
    into v_rule_set_hash
  from public.pdc_auditor_rule_config c
  where c.dealer_code=v_dealer and c.environment='staging'
    and c.effective_from<=statement_timestamp()
    and (c.effective_to is null or c.effective_to>statement_timestamp());
  v_response_revision := md5(concat_ws('|','pdc-auditor-snapshot-v2a',v_dealer,
    v_workshop_revision,v_email_revision,v_auditor_revision,v_relation_revision,v_config_revision,v_operational_revision,v_rule_set_hash)) ||
    md5(concat_ws('|','pdc-auditor-snapshot-v2b',v_dealer,
    v_workshop_revision,v_email_revision,v_auditor_revision,v_relation_revision,v_config_revision,v_operational_revision,v_rule_set_hash));

  select coalesce(jsonb_agg(jsonb_build_object(
    'rule_key',c.rule_key,'config_version',c.config_version,'provisional',c.provisional,
    'effective_from',c.effective_from,'classification','confirmed',
    'parameters',case c.rule_key
      when 'station_compatibility' then jsonb_build_object(
        'mode',c.config->'mode','unknown_station_action',c.config->'unknown_station_action',
        'booking_work_link_policy',c.config->'booking_work_link_policy')
      when 'department_mismatch_thresholds' then jsonb_build_object(
        'status',c.config->'status','minimum_sample_size',c.config->'minimum_sample_size',
        'warning_ratio',c.config->'warning_ratio','high_ratio',c.config->'high_ratio','action',c.config->'action')
      when 'risk_weights' then jsonb_build_object('versioned',true)
      when 'working_calendar' then jsonb_build_object('versioned',true)
      else '{}'::jsonb end
  ) order by c.rule_key),'[]'::jsonb) into v_configs
  from public.pdc_auditor_rule_config c
  where c.dealer_code=v_dealer and c.environment='staging'
    and c.effective_from<=statement_timestamp()
    and (c.effective_to is null or c.effective_to>statement_timestamp())
    and not exists(select 1 from public.pdc_auditor_rule_config newer
      where newer.dealer_code=c.dealer_code and newer.environment=c.environment
        and newer.rule_key=c.rule_key and newer.effective_from<=statement_timestamp()
        and (newer.effective_to is null or newer.effective_to>statement_timestamp())
        and (newer.config_version,newer.rule_config_id)>(c.config_version,c.rule_config_id));

  select c.config into v_calendar_config
  from public.pdc_auditor_rule_config c
  where c.dealer_code=v_dealer and c.environment='staging' and c.rule_key='working_calendar'
    and c.effective_from<=statement_timestamp()
    and (c.effective_to is null or c.effective_to>statement_timestamp())
  order by c.config_version desc,c.rule_config_id desc limit 1;

  select coalesce(jsonb_agg(resource order by resource->>'resource_type',resource->>'code'),'[]'::jsonb)
    into v_resources
  from (
    (select jsonb_build_object('resource_type','stage','resource_id',s.id,'code',left(s.code,40),
      'active',s.active,'is_physical',s.is_physical,'is_sublet',s.is_sublet,'classification','confirmed') resource
     from public.workshop_stages s order by s.code limit 100)
    union all
    (select jsonb_build_object('resource_type','bay','resource_id',b.id,'code',left(b.code,40),
      'stage_id',b.stage_id,'active',b.is_active,'is_sublet',b.is_sublet_row,'classification','confirmed')
     from public.workshop_bays b order by b.code limit 100)
    union all
    (select jsonb_build_object('resource_type','technician','resource_id',t.id,'code',t.id::text,
      'active',t.active,'role_type',left(t.role_type,32),'compatible_stage_codes',to_jsonb(t.can_fit_stages),
      'classification','confirmed')
     from public.workshop_technicians t order by t.id limit 100)
  ) resources;
  select count(*) into v_total_vehicle_count from public.vehicles v
  where v.deleted_at is null and public.pdc_auditor_vehicle_dealer(v.id)=v_dealer;

  with selected_vehicles as materialized (
    select v.id,v.version,v.key_number,v.stock_number,
      coalesce(v.vehicle_description,v.model,v.make) model_label,
      v.current_location,v.pmb_stage,v.pmb_bay_stage,v.pmb_bay_number,v.eta_to_kewdale,
      v.lifecycle_state::text lifecycle_state,v.visible_on_board,v.workshop_status,
      v.workshop_status_updated_at,v.qc_completed_at,v.rft_transferred_at,v.rft_collected_at,
      v.active_workshop_booking_id,v.created_at,v.updated_at
    from public.vehicles v
    where public.pdc_auditor_vehicle_dealer(v.id)=v_dealer
      and v.deleted_at is null and (p_after_vehicle_id is null or v.id>p_after_vehicle_id)
    order by v.id limit v_limit+1
  ), page as materialized (select * from selected_vehicles order by id limit v_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
    'vehicle_id',p.id,'dealer_code',v_dealer,
    'key_number',left(coalesce(p.key_number,''),80),'stock_number',left(coalesce(p.stock_number,''),80),
    'model',left(coalesce(p.model_label,''),160),'vehicle_version',p.version,
    'lifecycle',jsonb_build_object(
      'state',p.lifecycle_state,'visible_on_board',p.visible_on_board,
      'created_at',p.created_at,'updated_at',p.updated_at,'classification','confirmed'),
    'workshop',jsonb_build_object(
      'status',p.workshop_status,'status_updated_at',p.workshop_status_updated_at,
      'stage_code',left(coalesce(p.pmb_stage,''),40),'bay_stage_code',left(coalesce(p.pmb_bay_stage,''),40),
      'bay_number',left(coalesce(p.pmb_bay_number,''),20),
      'active_booking_id',p.active_workshop_booking_id,'classification','confirmed'),
    'quality',jsonb_build_object(
      'qc_completed_at',p.qc_completed_at,'rft_transferred_at',p.rft_transferred_at,
      'rft_collected_at',p.rft_collected_at,
      'qc_state',case when p.qc_completed_at is null then 'incomplete' else 'completed' end,
      'rft_state',case when p.rft_collected_at is not null then 'collected'
        when p.rft_transferred_at is not null then 'transferred' else 'not_transferred' end,
      'classification','confirmed'),
    'location',jsonb_build_object('code',left(coalesce(p.current_location,''),40),'classification','confirmed'),
    'eta',jsonb_build_object('eta_to_kewdale',p.eta_to_kewdale,
      'classification',case when p.eta_to_kewdale is null then 'unknown' else 'confirmed' end),
    'work_items',coalesce((select jsonb_agg(jsonb_build_object(
      'work_item_id',wi.id,'work_key',left(wi.work_key,64),'required',wi.required,'completed',wi.completed,
      'inactive',not wi.required,'completed_at',wi.completed_at,'updated_at',wi.updated_at,
      'status',case when wi.completed then 'completed' when not wi.required then 'inactive' else 'required' end,
      'hours',jsonb_build_object(
        'confirmed_hours',coalesce(h.confirmed_hours,0),'estimated_hours',coalesce(h.estimated_hours,0),
        'unknown_hours_line_count',coalesce(h.unknown_count,0),'line_count',coalesce(h.line_count,0),
        'provenance',case when coalesce(h.line_count,0)=0 then 'unknown'
          when coalesce(h.unknown_count,0)>0 then 'mixed_or_unknown'
          when coalesce(h.estimated_hours,0)>0 and coalesce(h.confirmed_hours,0)>0 then 'mixed'
          when coalesce(h.confirmed_hours,0)>0 then 'job_card' else 'ai_estimate' end,
        'classification',case when coalesce(h.confirmed_hours,0)>0 then 'confirmed'
          when coalesce(h.estimated_hours,0)>0 then 'estimated' else 'unknown' end)
    ) order by wi.work_key,wi.id)
    from (select * from public.vehicle_work_items wi0 where wi0.vehicle_id=p.id order by wi0.work_key,wi0.id limit 100) wi
    left join lateral (select
      sum(ol.estimated_hours) filter(where ol.estimated_hours_source='job_card') confirmed_hours,
      sum(ol.estimated_hours) filter(where ol.estimated_hours_source='ai_estimate') estimated_hours,
      count(*) filter(where ol.estimated_hours is null or ol.estimated_hours_source is null) unknown_count,
      count(*) line_count
      from public.pdc_authenticated_email_operation_lines ol
      where ol.vehicle_id=wi.vehicle_id and ol.work_key=wi.work_key) h on true
    ),'[]'::jsonb),
    'bookings',coalesce((select jsonb_agg(jsonb_build_object(
      'booking_id',q.booking_id,'stage_code',q.stage_code,'status',q.status,
      'scheduled_start_at',q.scheduled_start_at,'scheduled_end_at',q.scheduled_end_at,
      'actual_start_at',q.actual_start_at,'actual_end_at',q.actual_end_at,
      'duration_minutes',q.duration_minutes,'bay_id',q.bay_id,'booking_version',q.version,
      'stoppage',jsonb_build_object('active',q.status='stoppage','started_at',q.stoppage_started_at,
        'accumulated_minutes',q.stoppage_accumulated_minutes,'classification','confirmed'),
      'assignments',q.assignments,
      'linked_work_item_id',case when q.valid_relation_count=1 and q.all_relation_count=1
          then q.work_item_id else null end,
      'relation_kind',case when q.valid_relation_count=1 and q.all_relation_count=1 then q.relation_kind else null end,
      'relation_source_revision',case when q.valid_relation_count=1 and q.all_relation_count=1 then q.source_revision else null end,
      'relationship_status',case
        when q.revoked_relation_count=1 and q.valid_relation_count=0 and q.all_relation_count=1 then 'revoked_authoritative_relation_unlinked'
        when q.all_relation_count<>q.valid_relation_count or q.valid_relation_count>1 then 'corrupt_or_ambiguous_relation_unlinked'
        when q.valid_relation_count=0 then 'legacy_no_relation_unlinked'
        when q.status not in ('queued','planned','started','stoppage') or not q.work_required or q.work_completed then 'linked_completed_or_inactive'
        when q.active_booking_count_for_work>1 then 'multiple_active_bookings_for_work_item'
        when q.relation_kind='explicit_fk' then 'explicit_linked_active'
        when q.relation_kind='authoritative_relation' then 'exact_authoritative_linked_active'
        else 'corrupt_or_ambiguous_relation_unlinked' end,
      'classification',case when q.valid_relation_count=1 and q.all_relation_count=1 then 'confirmed' else 'unknown' end
    ) order by q.scheduled_start_at,q.booking_id) from (
      select b.id booking_id,s.code stage_code,b.status::text status,b.scheduled_start_at,b.scheduled_end_at,
        b.actual_start_at,b.actual_end_at,b.default_duration_minutes duration_minutes,b.bay_id,b.version,
        b.stoppage_started_at,b.stoppage_accumulated_minutes,
        coalesce((select jsonb_agg(jsonb_build_object(
          'assignment_id',a.id,'technician_id',a.technician_id,'assignment_type',a.assignment_type,
          'scheduled_start_at',a.scheduled_start_at,'scheduled_end_at',a.scheduled_end_at,
          'released_at',a.released_at,'authority_state',case when a.released_at is null then 'active' else 'released' end,
          'classification','confirmed') order by a.scheduled_start_at,a.id)
          from (select * from public.workshop_booking_assignments a0 where a0.booking_id=b.id
            order by a0.scheduled_start_at,a0.id limit 100) a),'[]'::jsonb) assignments,
        rel.all_relation_count,rel.valid_relation_count,rel.revoked_relation_count,rel.work_item_id,rel.relation_kind,rel.source_revision,
        coalesce(rel.work_required,false) work_required,coalesce(rel.work_completed,false) work_completed,
        coalesce(multi.active_booking_count_for_work,0) active_booking_count_for_work
      from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
      left join lateral (
        select count(*) all_relation_count,
          count(*) filter(where r.relation_action='revoked') revoked_relation_count,
          count(*) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and rv.id=wi.vehicle_id and r.dealer_code=v_dealer and r.environment='staging') valid_relation_count,
          (min(wi.id::text) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging'))::uuid work_item_id,
          min(r.relation_kind) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging') relation_kind,
          max(r.source_revision) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging') source_revision,
          bool_and(wi.required) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging') work_required,
          bool_or(wi.completed) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging') work_completed
        from public.pdc_auditor_booking_work_relations r
        join public.vehicle_work_items wi on wi.id=r.work_item_id
        join public.vehicles rv on rv.id=wi.vehicle_id
        where r.booking_id=b.id and r.active
          and not exists(select 1 from public.pdc_auditor_booking_work_relations successor
            where successor.supersedes_relation_id=r.relation_id)
      ) rel on true
      left join lateral (
        select count(*) active_booking_count_for_work
        from public.pdc_auditor_booking_work_relations r2
        join public.workshop_bookings b2 on b2.id=r2.booking_id
        where rel.valid_relation_count=1 and r2.active and r2.relation_action='asserted' and r2.work_item_id=rel.work_item_id
          and not exists(select 1 from public.pdc_auditor_booking_work_relations successor2
            where successor2.supersedes_relation_id=r2.relation_id)
          and r2.dealer_code=v_dealer and r2.environment='staging'
          and b2.deleted_at is null and b2.status::text in ('queued','planned','started','stoppage')
      ) multi on true
      where b.vehicle_id=p.id and b.deleted_at is null
      order by b.scheduled_start_at desc,b.id desc limit 100
    ) q),'[]'::jsonb),
    'parts',coalesce((select jsonb_build_object(
      'scope','vehicle_level','job_specific',false,'vehicle_level',true,'inferred',false,'work_item_id',null,
      'parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,'parts_received',pu.parts_received,
      'parts_stoppage',pu.parts_stoppage,'eta_at',pu.worst_eta,'updated_at',pu.updated_at,
      'classification','confirmed')
      from public.vehicle_parts_updates pu where pu.vehicle_id=p.id order by pu.updated_at desc,pu.id desc limit 1),
      jsonb_build_object('scope','unknown','job_specific',false,'vehicle_level',false,'inferred',false,
        'work_item_id',null,'classification','unknown')),
    'operation_lines',coalesce((select jsonb_agg(jsonb_build_object(
      'operation_line_id',ol.operation_line_id,'operation_no',left(ol.operation_no,8),
      'work_key',left(ol.work_key,64),'estimated_hours',ol.estimated_hours,
      'hours_provenance',coalesce(ol.estimated_hours_source,'unknown'),
      'classification',case when ol.estimated_hours_source='job_card' then 'confirmed'
        when ol.estimated_hours_source='ai_estimate' then 'estimated' else 'unknown' end,
      'created_at',ol.created_at) order by ol.created_at desc,ol.operation_line_id)
      from (select * from public.pdc_authenticated_email_operation_lines ol0 where ol0.vehicle_id=p.id
        order by ol0.created_at desc,ol0.operation_line_id limit 100) ol),'[]'::jsonb),
    'line_adjustments',coalesce((select jsonb_agg(jsonb_build_object(
      'adjustment_id',a.adjustment_id,'source_kind',a.source_kind,'stage_code',a.stage_code,
      'estimated_hours',a.estimated_hours,'active',a.active,'version',a.version,
      'classification','confirmed','created_at',a.created_at,'updated_at',a.updated_at)
      order by a.updated_at desc,a.adjustment_id)
      from (select * from public.vehicle_workshop_line_adjustments a0 where a0.vehicle_id=p.id
        order by a0.updated_at desc,a0.adjustment_id limit 100) a),'[]'::jsonb),
    'sublet',coalesce((select jsonb_build_object(
      'provider_ids',coalesce((select jsonb_agg(vsp.provider_id order by vsp.provider_id)
        from (select * from public.vehicle_sublet_providers vsp0 where vsp0.vehicle_id=p.id
          order by vsp0.provider_id limit 20) vsp),'[]'::jsonb),
      'provider_names',coalesce((select jsonb_agg(left(vsp.canonical_name,120) order by vsp.canonical_name)
        from (select * from public.vehicle_sublet_providers vsp0 where vsp0.vehicle_id=p.id
          order by vsp0.canonical_name limit 20) vsp),'[]'::jsonb),
      'status',case when sb.actual_return_date is not null then 'returned'
        when sb.booking_date is not null then 'booked' when sb.po_sent_date is not null then 'po_sent' else 'unbooked' end,
      'booking_date',sb.booking_date,'expected_return_date',sb.expected_return_date,
      'actual_return_date',sb.actual_return_date,'version',sb.version,'updated_at',sb.updated_at,
      'classification','confirmed') from public.pdc_sublet_bookings sb where sb.vehicle_id=p.id),
      jsonb_build_object('status','unknown','provider_ids','[]'::jsonb,'provider_names','[]'::jsonb,'classification','unknown')),
    'movement_events',coalesce((select jsonb_agg(jsonb_build_object(
      'event_id',m.id,'event_type','movement','occurred_at',m.moved_at,'classification','confirmed')
      order by m.moved_at desc,m.id)
      from (select id,moved_at from public.vehicle_movements m0 where m0.vehicle_id=p.id
        order by m0.moved_at desc,m0.id limit 25) m),'[]'::jsonb),
    'workflow_events',coalesce((select jsonb_agg(jsonb_build_object(
      'event_id',e.id,'event_type',left(e.action::text,32),'entity_type',left(coalesce(e.table_name,''),48),
      'occurred_at',e.created_at,'classification','confirmed') order by e.created_at desc,e.id)
      from (select id,action,table_name,created_at from public.audit_events e0 where e0.vehicle_id=p.id
        order by e0.created_at desc,e0.id limit 100) e),'[]'::jsonb),
    'collection_completeness',jsonb_build_object(
      'work_items',jsonb_build_object('returned',least((select count(*) from public.vehicle_work_items wi where wi.vehicle_id=p.id),100),'total',(select count(*) from public.vehicle_work_items wi where wi.vehicle_id=p.id),'limit',100,'complete',(select count(*) from public.vehicle_work_items wi where wi.vehicle_id=p.id)<=100),
      'bookings',jsonb_build_object('returned',least((select count(*) from public.workshop_bookings b where b.vehicle_id=p.id and b.deleted_at is null),100),'total',(select count(*) from public.workshop_bookings b where b.vehicle_id=p.id and b.deleted_at is null),'limit',100,'complete',(select count(*) from public.workshop_bookings b where b.vehicle_id=p.id and b.deleted_at is null)<=100),
      'operation_lines',jsonb_build_object('returned',least((select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=p.id),100),'total',(select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=p.id),'limit',100,'complete',(select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=p.id)<=100),
      'line_adjustments',jsonb_build_object('returned',least((select count(*) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p.id),100),'total',(select count(*) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p.id),'limit',100,'complete',(select count(*) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p.id)<=100),
      'movement_events',jsonb_build_object('returned',least((select count(*) from public.vehicle_movements m where m.vehicle_id=p.id),25),'total',(select count(*) from public.vehicle_movements m where m.vehicle_id=p.id),'limit',25,'complete',(select count(*) from public.vehicle_movements m where m.vehicle_id=p.id)<=25),
      'workflow_events',jsonb_build_object('returned',least((select count(*) from public.audit_events e where e.vehicle_id=p.id),100),'total',(select count(*) from public.audit_events e where e.vehicle_id=p.id),'limit',100,'complete',(select count(*) from public.audit_events e where e.vehicle_id=p.id)<=100))
  ) order by p.id),'[]'::jsonb) into v_items from page p;

  v_page_item_count := jsonb_array_length(v_items);

  select count(*)>v_limit into v_has_more from (
    select v.id from public.vehicles v
    where public.pdc_auditor_vehicle_dealer(v.id)=v_dealer
      and v.deleted_at is null and (p_after_vehicle_id is null or v.id>p_after_vehicle_id)
    order by v.id limit v_limit+1
  ) bounded;
  if v_has_more then
    select (item->>'vehicle_id')::uuid into v_next from jsonb_array_elements(v_items) item
      order by item->>'vehicle_id' desc limit 1;
  end if;
  return jsonb_build_object(
    'ok',true,'code','pdc_auditor_snapshot','snapshot_contract_version','stage-a-v2',
    'environment','staging','dealer_code',v_dealer,'generated_at',clock_timestamp(),
    'response_revision',v_response_revision,'operational_revision',v_operational_revision,
    'rule_set_hash',v_rule_set_hash,
    'source_revisions',jsonb_build_object(
      'workshop_revision',v_workshop_revision,'pdc_email_vehicle_revision',v_email_revision,
      'auditor_revision',v_auditor_revision,'auditor_relation_revision',v_relation_revision,
      'auditor_config_revision',v_config_revision),
    'working_calendar',jsonb_build_object(
      'timezone','Australia/Perth','working_days',jsonb_build_array('monday','tuesday','wednesday','thursday','friday'),
      'day_start','08:00','day_end','16:00','closures','[]'::jsonb,'breaks','[]'::jsonb,
      'overtime_windows','[]'::jsonb,'source',case when v_calendar_config is null then 'missing_holiday_configuration' else 'auditor_rule_config' end,
      'holiday_configuration_status',case when v_calendar_config is null then 'missing' else 'confirmed' end,
      'classification',case when v_calendar_config is null then 'unknown' else 'confirmed' end)
      || case when v_calendar_config is null then '{}'::jsonb
        else jsonb_build_object('public_holidays',v_calendar_config->'public_holidays') end,
    'active_rule_configs',v_configs,
    'station_compatibility',coalesce((select c->'parameters' from jsonb_array_elements(v_configs) c where c->>'rule_key'='station_compatibility' limit 1),'{}'::jsonb),
    'resources',v_resources,
    'page_manifest',jsonb_build_object('after_vehicle_id',p_after_vehicle_id,'returned_count',v_page_item_count,
      'total_scoped_vehicle_count',v_total_vehicle_count,'page_limit',v_limit,'has_more',v_has_more,
      'next_vehicle_id',v_next,'response_revision',v_response_revision,'operational_revision',v_operational_revision),
    'page_size',v_limit,'has_more',v_has_more,
    'next_vehicle_id',v_next,'items',v_items,
    'relationship_semantics','Only one active exact auditor relation with same dealer and vehicle may link; all legacy, inactive, duplicate, cross-vehicle or cross-dealer cases are unlinked and fail closed.'
  );
end;
$snapshot$;
revoke all on function public.get_pdc_auditor_snapshot(uuid,integer) from public,anon,authenticated;
grant execute on function public.get_pdc_auditor_snapshot(uuid,integer) to authenticated;

-- Authenticated enrolled-worker ingestion: exact keys, bounded arrays, typed evidence,
-- exact user/email/dealer membership, and auditor-owned writes only.
create or replace function public.submit_pdc_auditor_findings(
  p_run jsonb,
  p_findings jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $submit$
declare
  v_run_id uuid;
  v_dealer text;
  v_environment text;
  v_request_hash text;
  v_existing uuid;
  v_existing_payload_hash text;
  v_computed_payload_hash text;
  v_manifest_hash text;
  v_current_snapshot jsonb;
  v_page jsonb;
  v_page_count integer;
  v_vehicle_count integer;
  v_manifest_vehicle_count integer := 0;
  v_previous_last_vehicle_id text;
  v_finding jsonb;
  v_evidence jsonb;
  v_finding_id uuid;
  v_entity_id uuid;
  v_ordinal integer;
  v_fingerprint text;
  v_evidence_fingerprint text;
  v_seen_fingerprints text[] := array[]::text[];
  v_existing_finding uuid;
  v_previous_status text;
  v_previous_evidence_fingerprint text;
  v_occurrence_id bigint;
begin
  if jsonb_typeof(p_run) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(p_run) k)
       is distinct from array['dealer_code','environment','model_key','operational_revision','payload_hash','request_hash','rule_set_hash','run_id','snapshot_complete','snapshot_generated_at','snapshot_page_manifest','snapshot_response_revision','snapshot_vehicle_count']::text[]
     or octet_length(p_run::text)>32768
     or jsonb_typeof(p_findings) is distinct from 'array'
     or jsonb_array_length(p_findings)>100
     or octet_length(p_findings::text)>262144 then
    raise exception 'pdc_auditor_invalid_submission' using errcode='22023';
  end if;
  begin
    v_run_id := (p_run->>'run_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'pdc_auditor_invalid_run_id' using errcode='22023';
  end;
  v_dealer := p_run->>'dealer_code';
  v_environment := p_run->>'environment';
  v_request_hash := p_run->>'request_hash';
  if v_dealer not in ('14450','37047') or v_environment <> 'staging'
     or v_request_hash !~ '^[a-f0-9]{64}$'
     or coalesce(p_run->>'payload_hash','') !~ '^[a-f0-9]{64}$'
     or coalesce(p_run->>'snapshot_response_revision','') !~ '^[a-f0-9]{64}$'
     or coalesce(p_run->>'operational_revision','') !~ '^[a-f0-9]{64}$'
     or coalesce(p_run->>'rule_set_hash','') !~ '^[a-f0-9]{64}$'
     or length(coalesce(p_run->>'model_key','')) not between 1 and 80
     or p_run->>'model_key' <> btrim(p_run->>'model_key')
     or not public.pdc_auditor_valid_timestamptz(p_run->>'snapshot_generated_at') then
    raise exception 'pdc_auditor_invalid_run' using errcode='22023';
  end if;
  perform public.pdc_auditor_worker_scope(v_dealer);

  if p_run->>'snapshot_complete' <> 'true'
     or jsonb_typeof(p_run->'snapshot_page_manifest') is distinct from 'array'
     or jsonb_array_length(p_run->'snapshot_page_manifest') not between 1 and 5
     or jsonb_typeof(p_run->'snapshot_vehicle_count') is distinct from 'number'
     or (p_run->>'snapshot_vehicle_count')::integer not between 1 and 500 then
    raise exception 'pdc_auditor_incomplete_snapshot' using errcode='22023';
  end if;
  v_page_count := jsonb_array_length(p_run->'snapshot_page_manifest');
  for v_page in select value from jsonb_array_elements(p_run->'snapshot_page_manifest') loop
    if jsonb_typeof(v_page) is distinct from 'object'
       or (select array_agg(k order by k) from jsonb_object_keys(v_page) k)
         is distinct from array['after_vehicle_id','first_vehicle_id','has_more','item_count','last_vehicle_id','operational_revision','page_number','response_revision']::text[]
       or jsonb_typeof(v_page->'item_count') is distinct from 'number'
       or (v_page->>'item_count')::integer not between 1 and 100
       or jsonb_typeof(v_page->'page_number') is distinct from 'number'
       or (v_page->>'page_number')::integer <> v_manifest_vehicle_count/100+1
       or v_page->>'response_revision' <> p_run->>'snapshot_response_revision'
       or v_page->>'operational_revision' <> p_run->>'operational_revision'
       or (v_manifest_vehicle_count=0 and jsonb_typeof(v_page->'after_vehicle_id') <> 'null')
       or (v_manifest_vehicle_count>0 and v_page->>'after_vehicle_id' is distinct from v_previous_last_vehicle_id)
       or coalesce(v_page->>'first_vehicle_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or coalesce(v_page->>'last_vehicle_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'pdc_auditor_incomplete_snapshot' using errcode='22023';
    end if;
    v_manifest_vehicle_count := v_manifest_vehicle_count+(v_page->>'item_count')::integer;
    v_previous_last_vehicle_id := v_page->>'last_vehicle_id';
  end loop;
  select value into v_page from jsonb_array_elements(p_run->'snapshot_page_manifest') with ordinality p(value,n)
    order by n desc limit 1;
  if coalesce((v_page->>'has_more')::boolean,true)
     or v_manifest_vehicle_count<>(p_run->>'snapshot_vehicle_count')::integer then
    raise exception 'pdc_auditor_incomplete_snapshot' using errcode='22023';
  end if;
  select count(*) into v_vehicle_count from public.vehicles v
  where v.deleted_at is null and public.pdc_auditor_vehicle_dealer(v.id)=v_dealer;
  if v_vehicle_count<>v_manifest_vehicle_count or v_vehicle_count>500 then
    raise exception 'pdc_auditor_incomplete_snapshot' using errcode='22023';
  end if;
  v_manifest_hash := encode(extensions.digest(convert_to((p_run->'snapshot_page_manifest')::text,'UTF8'),'sha256'),'hex');
  v_computed_payload_hash := encode(extensions.digest(convert_to(
    (p_run-array['payload_hash','request_hash']::text[])::text||'|'||p_findings::text,'UTF8'),'sha256'),'hex');
  if v_computed_payload_hash<>p_run->>'payload_hash' or v_request_hash<>v_computed_payload_hash then
    raise exception 'pdc_auditor_payload_hash_mismatch' using errcode='22023';
  end if;
  -- Complete runs and exact replays are serialized per dealer so lifecycle ordering is stable.
  perform pg_advisory_xact_lock(hashtextextended('pdc-auditor-complete-run:'||v_dealer,0));
  select run_id,payload_hash into v_existing,v_existing_payload_hash from public.pdc_auditor_runs
    where dealer_code=v_dealer and environment=v_environment and request_hash=v_request_hash;
  if found then
    if v_existing <> v_run_id or v_existing_payload_hash<>v_computed_payload_hash then
      raise exception 'pdc_auditor_request_hash_conflict' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'code','exact_replay','run_id',v_existing);
  end if;
  v_current_snapshot := public.get_pdc_auditor_snapshot(null,least(100,v_vehicle_count));
  if v_current_snapshot->>'response_revision' <> p_run->>'snapshot_response_revision'
     or v_current_snapshot->>'operational_revision' <> p_run->>'operational_revision'
     or v_current_snapshot->>'rule_set_hash' <> p_run->>'rule_set_hash' then
    raise exception 'pdc_auditor_snapshot_revision_mismatch' using errcode='22023';
  end if;
  -- Recursive defense in depth: no nested PII/free-text key may be introduced by a future shape.
  if public.pdc_auditor_json_has_sensitive_key(p_findings) then
    raise exception 'pdc_auditor_nested_sensitive_data' using errcode='22023';
  end if;

  if exists (
    select 1 from public.pdc_auditor_runs r
    where r.dealer_code=v_dealer and r.environment=v_environment and r.status='completed'
      and r.snapshot_generated_at >= (p_run->>'snapshot_generated_at')::timestamptz
  ) then
    raise exception 'pdc_auditor_stale_complete_run' using errcode='22023';
  end if;

  -- Validate the complete payload before the first insert.
  for v_finding in select value from jsonb_array_elements(p_findings) loop
    if jsonb_typeof(v_finding)<>'object'
       or (select array_agg(k order by k) from jsonb_object_keys(v_finding) k)
         is distinct from array['category','confidence','detected_at','entity_id','entity_type','evidence','finding_id','risk_score','rule_key','scoring_version','severity','summary_code']::text[]
       or length(coalesce(v_finding->>'rule_key','')) not between 3 and 64
       or coalesce(v_finding->>'rule_key','') !~ '^[a-z][a-z0-9_]{2,63}$'
       or coalesce(v_finding->>'category','') not in ('station_compatibility','department_mismatch','booking_work_relationship','data_quality','schedule_risk')
       or coalesce(v_finding->>'severity','') not in ('info','low','medium','high','critical')
       or coalesce(v_finding->>'summary_code','') !~ '^[a-z][a-z0-9_]{2,79}$'
       or coalesce(v_finding->>'entity_type','') not in ('vehicle','work_item','booking','operation_line','line_adjustment')
       or jsonb_typeof(v_finding->'risk_score')<>'number'
       or (v_finding->>'risk_score')::numeric not between 0 and 100
       or jsonb_typeof(v_finding->'confidence')<>'number'
       or (v_finding->>'confidence')::numeric not between 0 and 1
       or coalesce(v_finding->>'scoring_version','') !~ '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,39}$'
       or not public.pdc_auditor_valid_timestamptz(v_finding->>'detected_at')
       or jsonb_typeof(v_finding->'evidence')<>'array'
       or jsonb_array_length(v_finding->'evidence') not between 1 and 20 then
      raise exception 'pdc_auditor_invalid_finding' using errcode='22023';
    end if;
    begin
      v_finding_id := (v_finding->>'finding_id')::uuid;
      v_entity_id := (v_finding->>'entity_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'pdc_auditor_invalid_finding_id' using errcode='22023';
    end;
    if not public.pdc_auditor_entity_in_scope(v_dealer,v_finding->>'entity_type',v_entity_id) then
      raise exception 'pdc_auditor_entity_out_of_scope' using errcode='42501';
    end if;
    v_ordinal := 0;
    for v_evidence in select value from jsonb_array_elements(v_finding->'evidence') loop
      v_ordinal := v_ordinal+1;
      if jsonb_typeof(v_evidence)<>'object'
         or (select array_agg(k order by k) from jsonb_object_keys(v_evidence) k)
           is distinct from array['boolean_value','entity_id','entity_type','field_code','numeric_value','signal_code','timestamp_value']::text[]
         or coalesce(v_evidence->>'entity_type','') not in ('vehicle','work_item','booking','operation_line','line_adjustment')
         or coalesce(v_evidence->>'signal_code','') !~ '^[a-z][a-z0-9_]{2,79}$'
         or coalesce(v_evidence->>'field_code','') !~ '^[a-z][a-z0-9_]{1,63}$'
         or jsonb_typeof(v_evidence->'numeric_value') not in ('number','null')
         or jsonb_typeof(v_evidence->'boolean_value') not in ('boolean','null')
         or jsonb_typeof(v_evidence->'timestamp_value') not in ('string','null')
         or (jsonb_typeof(v_evidence->'numeric_value')='number'
             and (v_evidence->>'numeric_value')::numeric not between -99999999.999 and 99999999.999)
         or (jsonb_typeof(v_evidence->'timestamp_value')='string'
             and not public.pdc_auditor_valid_timestamptz(v_evidence->>'timestamp_value'))
         or (case when jsonb_typeof(v_evidence->'numeric_value')<>'null' then 1 else 0 end
            + case when jsonb_typeof(v_evidence->'boolean_value')<>'null' then 1 else 0 end
            + case when jsonb_typeof(v_evidence->'timestamp_value')<>'null' then 1 else 0 end)>1 then
        raise exception 'pdc_auditor_invalid_evidence' using errcode='22023';
      end if;
      begin
        v_entity_id := (v_evidence->>'entity_id')::uuid;
      exception when invalid_text_representation then
        raise exception 'pdc_auditor_invalid_evidence_id' using errcode='22023';
      end;
      if not public.pdc_auditor_entity_in_scope(v_dealer,v_evidence->>'entity_type',v_entity_id) then
        raise exception 'pdc_auditor_evidence_out_of_scope' using errcode='42501';
      end if;
    end loop;
    -- Stable rule/entity identity prevents duplicate current recommendations; exact canonical
    -- evidence gets its own fingerprint and append-only occurrence rows on every complete run.
    v_fingerprint := md5(concat_ws('|','pdc-auditor-id-v1a',
      v_finding->>'rule_key',v_finding->>'entity_type',v_finding->>'entity_id'))
      || md5(concat_ws('|','pdc-auditor-id-v1b',
      v_finding->>'rule_key',v_finding->>'entity_type',v_finding->>'entity_id'));
    v_evidence_fingerprint := md5('pdc-auditor-evidence-v1a|'||(v_finding->'evidence')::text)
      || md5('pdc-auditor-evidence-v1b|'||(v_finding->'evidence')::text);
    if v_fingerprint = any(v_seen_fingerprints) then
      raise exception 'pdc_auditor_duplicate_stable_finding' using errcode='22023';
    end if;
    v_seen_fingerprints := array_append(v_seen_fingerprints,v_fingerprint);
  end loop;

  insert into public.pdc_auditor_runs(
    run_id,dealer_code,environment,request_hash,snapshot_generated_at,
    snapshot_response_revision,operational_revision,rule_set_hash,snapshot_manifest_hash,payload_hash,
    snapshot_page_count,snapshot_vehicle_count,snapshot_complete,model_key,status,finding_count
  ) values(
    v_run_id,v_dealer,v_environment,v_request_hash,(p_run->>'snapshot_generated_at')::timestamptz,
    p_run->>'snapshot_response_revision',p_run->>'operational_revision',p_run->>'rule_set_hash',
    v_manifest_hash,v_computed_payload_hash,v_page_count,v_manifest_vehicle_count,true,
    p_run->>'model_key','completed',jsonb_array_length(p_findings)
  );

  for v_finding in select value from jsonb_array_elements(p_findings) loop
    v_finding_id := (v_finding->>'finding_id')::uuid;
    v_entity_id := (v_finding->>'entity_id')::uuid;
    v_fingerprint := md5(concat_ws('|','pdc-auditor-id-v1a',
      v_finding->>'rule_key',v_finding->>'entity_type',v_finding->>'entity_id'))
      || md5(concat_ws('|','pdc-auditor-id-v1b',
      v_finding->>'rule_key',v_finding->>'entity_type',v_finding->>'entity_id'));
    v_evidence_fingerprint := md5('pdc-auditor-evidence-v1a|'||(v_finding->'evidence')::text)
      || md5('pdc-auditor-evidence-v1b|'||(v_finding->'evidence')::text);

    select finding_id,lifecycle_status,evidence_fingerprint
      into v_existing_finding,v_previous_status,v_previous_evidence_fingerprint
      from public.pdc_auditor_findings
      where dealer_code=v_dealer and environment=v_environment and stable_fingerprint=v_fingerprint
      for update;
    if found then
      v_finding_id := v_existing_finding;
      update public.pdc_auditor_findings set
        last_seen_run_id=v_run_id,last_detected_at=(v_finding->>'detected_at')::timestamptz,
        lifecycle_status='current',resolved_at=null,severity=v_finding->>'severity',
        evidence_fingerprint=v_evidence_fingerprint,
        last_evidence_change_at=case when evidence_fingerprint<>v_evidence_fingerprint
          then (v_finding->>'detected_at')::timestamptz else last_evidence_change_at end,
        updated_at=clock_timestamp()
      where finding_id=v_finding_id;
      insert into public.pdc_auditor_finding_history(
        finding_id,run_id,dealer_code,environment,event_type
      ) values(v_finding_id,v_run_id,v_dealer,v_environment,
        case when v_previous_status='resolved' then 'reopened' else 'observed' end);
    else
      insert into public.pdc_auditor_findings(
        finding_id,dealer_code,environment,stable_fingerprint,evidence_fingerprint,rule_key,category,severity,
        summary_code,entity_type,entity_id,first_seen_run_id,last_seen_run_id,
        first_detected_at,last_detected_at,last_evidence_change_at,lifecycle_status
      ) values(
        v_finding_id,v_dealer,v_environment,v_fingerprint,v_evidence_fingerprint,v_finding->>'rule_key',
        v_finding->>'category',v_finding->>'severity',v_finding->>'summary_code',
        v_finding->>'entity_type',v_entity_id,v_run_id,v_run_id,
        (v_finding->>'detected_at')::timestamptz,(v_finding->>'detected_at')::timestamptz,
        (v_finding->>'detected_at')::timestamptz,'current'
      );
      insert into public.pdc_auditor_finding_history(
        finding_id,run_id,dealer_code,environment,event_type
      ) values(v_finding_id,v_run_id,v_dealer,v_environment,'opened');
    end if;

    insert into public.pdc_auditor_finding_occurrences(
      finding_id,run_id,dealer_code,environment,detected_at,severity,score,confidence,scoring_version
    ) values(
      v_finding_id,v_run_id,v_dealer,v_environment,(v_finding->>'detected_at')::timestamptz,
      v_finding->>'severity',(v_finding->>'risk_score')::numeric,
      (v_finding->>'confidence')::numeric,v_finding->>'scoring_version'
    ) returning occurrence_id into v_occurrence_id;
    v_ordinal := 0;
    for v_evidence in select value from jsonb_array_elements(v_finding->'evidence') loop
      v_ordinal := v_ordinal+1;
      insert into public.pdc_auditor_finding_evidence(
        finding_id,occurrence_id,dealer_code,environment,entity_type,entity_id,signal_code,field_code,
        numeric_value,boolean_value,timestamp_value,ordinal
      ) values(
        v_finding_id,v_occurrence_id,v_dealer,v_environment,v_evidence->>'entity_type',
        (v_evidence->>'entity_id')::uuid,v_evidence->>'signal_code',v_evidence->>'field_code',
        case when jsonb_typeof(v_evidence->'numeric_value')='number' then (v_evidence->>'numeric_value')::numeric end,
        case when jsonb_typeof(v_evidence->'boolean_value')='boolean' then (v_evidence->>'boolean_value')::boolean end,
        case when jsonb_typeof(v_evidence->'timestamp_value')='string' then (v_evidence->>'timestamp_value')::timestamptz end,
        v_ordinal
      );
    end loop;
    insert into public.pdc_auditor_risk_scores(
      finding_id,occurrence_id,dealer_code,environment,score,confidence,scoring_version
    ) values(
      v_finding_id,v_occurrence_id,v_dealer,v_environment,(v_finding->>'risk_score')::numeric,
      (v_finding->>'confidence')::numeric,v_finding->>'scoring_version'
    );
  end loop;

  -- A submitted run is complete for its dealer scope. Any previously-current stable finding
  -- absent from this complete run is resolved, while its row/occurrences/history remain.
  with resolved as (
    update public.pdc_auditor_findings f set
      lifecycle_status='resolved',resolved_at=clock_timestamp(),updated_at=clock_timestamp()
    where f.dealer_code=v_dealer and f.environment=v_environment
      and f.lifecycle_status='current'
      and not (f.stable_fingerprint = any(v_seen_fingerprints))
    returning f.finding_id
  )
  insert into public.pdc_auditor_finding_history(
    finding_id,run_id,dealer_code,environment,event_type
  ) select finding_id,v_run_id,v_dealer,v_environment,'resolved' from resolved;
  insert into public.pdc_auditor_revision(dealer_code,environment,run_id,event_type)
    values(v_dealer,v_environment,v_run_id,'findings_appended');
  return jsonb_build_object('ok',true,'code','findings_appended','run_id',v_run_id,
    'finding_count',jsonb_array_length(p_findings));
end;
$submit$;
revoke all on function public.submit_pdc_auditor_findings(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.submit_pdc_auditor_findings(jsonb,jsonb) to authenticated;

-- Stage A administrator-only append of deterministic thresholds. This cannot enable
-- approvals, schedules, delivery or operational mutation.
create or replace function public.append_pdc_auditor_rule_config(
  p_rule_key text,
  p_config jsonb,
  p_provisional boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $config$
declare
  v_scope jsonb := public.pdc_auditor_actor_scope();
  v_dealer text := v_scope->>'dealer_code';
  v_version integer;
  v_id uuid;
begin
  if v_scope->>'role' <> 'administrator' then
    raise exception 'pdc_auditor_admin_required' using errcode='42501';
  end if;
  if p_rule_key not in ('station_compatibility','department_mismatch_thresholds','risk_weights','working_calendar')
     or jsonb_typeof(p_config) is distinct from 'object'
     or octet_length(p_config::text) not between 2 and 8192
     or p_config ?| array['approval','automation','delivery','mailbox','operational_mutation'] then
    raise exception 'pdc_auditor_invalid_rule_config' using errcode='22023';
  end if;
  if p_rule_key='working_calendar' and (
       (select array_agg(k order by k) from jsonb_object_keys(p_config) k)
         is distinct from array['public_holidays']::text[]
       or jsonb_typeof(p_config->'public_holidays') is distinct from 'array'
       or jsonb_array_length(p_config->'public_holidays')>100
       or exists(select 1 from jsonb_array_elements_text(p_config->'public_holidays') h
         where h !~ '^\d{4}-\d{2}-\d{2}$')
     ) then
    raise exception 'pdc_auditor_invalid_working_calendar' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-auditor-config:'||v_dealer||':'||p_rule_key,0));
  select coalesce(max(config_version),0)+1 into v_version
    from public.pdc_auditor_rule_config
    where dealer_code=v_dealer and environment='staging' and rule_key=p_rule_key;
  insert into public.pdc_auditor_rule_config(
    dealer_code,environment,rule_key,config_version,config,provisional
  ) values(v_dealer,'staging',p_rule_key,v_version,p_config,coalesce(p_provisional,true))
  returning rule_config_id into v_id;
  insert into public.pdc_auditor_revision(dealer_code,environment,event_type)
    values(v_dealer,'staging','config_appended');
  return jsonb_build_object('ok',true,'rule_config_id',v_id,'config_version',v_version,
    'dealer_code',v_dealer,'environment','staging');
end;
$config$;
revoke all on function public.append_pdc_auditor_rule_config(text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.append_pdc_auditor_rule_config(text,jsonb,boolean) to authenticated;

-- RLS: browser reads only its exact derived dealer. No direct writes are granted.
do $rls$
declare
  t text;
begin
  foreach t in array array[
    'pdc_auditor_runs','pdc_auditor_findings','pdc_auditor_finding_occurrences',
    'pdc_auditor_finding_history','pdc_auditor_finding_evidence',
    'pdc_auditor_risk_scores','pdc_auditor_rule_config','pdc_auditor_report_runs','pdc_auditor_revision',
    'pdc_auditor_booking_work_relations'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
    execute format('grant select on table public.%I to authenticated',t);
    execute format('drop policy if exists %I on public.%I',t||'_dealer_read',t);
    execute format('create policy %I on public.%I for select to authenticated using (environment = ''staging'' and dealer_code = (public.pdc_auditor_actor_scope()->>''dealer_code''))',t||'_dealer_read',t);
  end loop;
end;
$rls$;

-- Identity enrollment is server-managed and never directly readable or writable by API roles.
alter table public.pdc_auditor_user_dealer_scopes enable row level security;
alter table public.pdc_auditor_worker_identities enable row level security;
revoke all on table public.pdc_auditor_user_dealer_scopes from public,anon,authenticated;
revoke all on table public.pdc_auditor_worker_identities from public,anon,authenticated;

-- Default-deny station compatibility and explicitly provisional mismatch thresholds.
insert into public.pdc_auditor_rule_config(dealer_code,environment,rule_key,config_version,config,provisional)
select d,'staging','station_compatibility',1,
  jsonb_build_object(
    'mode','default_deny','allowed_pairs',jsonb_build_array(),
    'unknown_station_action','flag_and_do_not_link',
    'booking_work_link_policy','explicit_fk_only',
    'canonical_candidates_are_diagnostic_only',true
  ),true
from unnest(array['14450','37047']) d
on conflict(dealer_code,environment,rule_key,config_version) do nothing;
insert into public.pdc_auditor_rule_config(dealer_code,environment,rule_key,config_version,config,provisional)
select d,'staging','department_mismatch_thresholds',1,
  jsonb_build_object(
    'status','provisional','minimum_sample_size',10,
    'warning_ratio',0.20,'high_ratio',0.40,
    'action','flag_only','operational_mutation',false
  ),true
from unnest(array['14450','37047']) d
on conflict(dealer_code,environment,rule_key,config_version) do nothing;
insert into public.pdc_auditor_revision(dealer_code,environment,event_type)
select d,'staging','foundation' from unnest(array['14450','37047']) d
where not exists(
  select 1 from public.pdc_auditor_revision r
  where r.dealer_code=d and r.environment='staging' and r.event_type='foundation'
);

-- Only the dealer-filtered auditor revision history is published. Findings/config remain RPC/RLS reads.
do $publication$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_auditor_revision'
  ) then
    alter publication supabase_realtime add table public.pdc_auditor_revision;
  end if;
end;
$publication$;

comment on function public.get_pdc_auditor_snapshot(uuid,integer) is
  'Staging-only dealer-derived bounded sanitized operational snapshot. Read-only; no customer/raw document/free-text fields and no fabricated booking-work links.';
comment on function public.submit_pdc_auditor_findings(jsonb,jsonb) is
  'Authenticated enrolled-worker bounded typed ingestion with stable lifecycle. Writes auditor-owned current/occurrence/history tables only; never operational or decision state.';

commit;
