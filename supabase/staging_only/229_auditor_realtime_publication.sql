-- Staging-only migration 229: publish authoritative Auditor operation revisions.
begin;
set local lock_timeout='10s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-229-auditor-realtime-publication',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='228')
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>228)
     or exists(select 1 from supabase_migrations.schema_migrations where version='229') then
    raise exception 'PDC_229_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

-- Existing authenticated website channels subscribe to these tables. Publication carries
-- row invalidation only; RLS/SELECT grants remain the read-authority boundary.
do $publication$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
      and schemaname='public' and tablename='vehicle_workshop_line_adjustments') then
    alter publication supabase_realtime add table public.vehicle_workshop_line_adjustments;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
      and schemaname='public' and tablename='pdc_auditor_workshop_revisions') then
    alter publication supabase_realtime add table public.pdc_auditor_workshop_revisions;
  end if;
end
$publication$;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '229','auditor_realtime_publication',array[
    'staging sentinel cdsmnqxtyyoeoznmbidd and exact predecessor 228',
    'publish vehicle_workshop_line_adjustments for authoritative operation overlay invalidation',
    'publish append-only pdc_auditor_workshop_revisions for one run-level apply/rollback revision',
    'publication changes no RLS grants or direct mutation authority',
    'production untouched'
  ]
);
commit;
