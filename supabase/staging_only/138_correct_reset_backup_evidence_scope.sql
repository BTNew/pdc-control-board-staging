begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='136')
     or not exists(select 1 from supabase_migrations.schema_migrations where version='137')
     or to_regclass('public.pdc_staging_reset_attestations') is null then
    raise exception 'PDC_RESET_138_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;
end;
$guard$;

create table if not exists public.pdc_staging_reset_evidence_corrections (
  reset_id uuid primary key references public.pdc_staging_reset_attestations(reset_id) on delete restrict,
  contract text not null check(contract='pdc_staging_reset_evidence_scope_138'),
  superseded_receipt_sha256 text not null check(superseded_receipt_sha256 ~ '^[a-f0-9]{64}$'),
  data_integrity_receipt_sha256 text not null check(data_integrity_receipt_sha256 ~ '^[a-f0-9]{64}$'),
  exact_csv_headers_verified boolean not null check(exact_csv_headers_verified),
  full_schema_restore_verified boolean not null check(not full_schema_restore_verified),
  disaster_recovery_receipt boolean not null check(not disaster_recovery_receipt),
  limitation text not null check(limitation='Pre-reset artifact verifies exact CSV headers, hashes, row counts and logical foreign-key consistency only; it does not independently restore or verify types, constraints, defaults, sequences, indexes, triggers, RLS, grants, views or functions.'),
  corrected_by text not null check(corrected_by='database_owner_migration_runner'),
  corrected_at timestamptz not null default clock_timestamp()
);

alter table public.pdc_staging_reset_evidence_corrections enable row level security;
revoke all on table public.pdc_staging_reset_evidence_corrections from public,anon,authenticated,service_role;
drop trigger if exists pdc_staging_reset_evidence_corrections_immutable on public.pdc_staging_reset_evidence_corrections;
create trigger pdc_staging_reset_evidence_corrections_immutable before update or delete on public.pdc_staging_reset_evidence_corrections
for each row execute function public.pdc_staging_reset_reject_mutation();

do $correct$
declare
  v_att public.pdc_staging_reset_attestations%rowtype;
begin
  select * into strict v_att from public.pdc_staging_reset_attestations;
  if v_att.isolated_restore_receipt_sha256<>'7f7d027f1a0da08982241b9d6f7a553b09908fed93c56f1e934e60a4cee1b439' then
    raise exception 'PDC_RESET_138_SUPERSEDED_RECEIPT_MISMATCH' using errcode='55000';
  end if;

  insert into public.pdc_staging_reset_evidence_corrections(
    reset_id,contract,superseded_receipt_sha256,data_integrity_receipt_sha256,
    exact_csv_headers_verified,full_schema_restore_verified,disaster_recovery_receipt,limitation,corrected_by
  ) values(
    v_att.reset_id,'pdc_staging_reset_evidence_scope_138',v_att.isolated_restore_receipt_sha256,
    'a46427bc6ac0df0a0bfac5b2ed48ad11fe2eb0a92a714076b61df5e27de93bdb',
    true,false,false,
    'Pre-reset artifact verifies exact CSV headers, hashes, row counts and logical foreign-key consistency only; it does not independently restore or verify types, constraints, defaults, sequences, indexes, triggers, RLS, grants, views or functions.',
    'database_owner_migration_runner'
  );

  insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  values('import','pdc_staging_reset_evidence_corrections',v_att.reset_id,null,'database-owner-migration-runner@local.invalid',
    jsonb_build_object('superseded_receipt_sha256',v_att.isolated_restore_receipt_sha256,'prior_classification','isolated_restore_receipt'),
    jsonb_build_object('data_integrity_receipt_sha256','a46427bc6ac0df0a0bfac5b2ed48ad11fe2eb0a92a714076b61df5e27de93bdb',
      'full_schema_restore_verified',false,'disaster_recovery_receipt',false),
    jsonb_build_object('source','pdc_staging_reset_evidence_scope_138','corrects_evidence_scope',true,
      'immutable_reset_history_rewritten',false,'production_changed',false));
end;
$correct$;

commit;
