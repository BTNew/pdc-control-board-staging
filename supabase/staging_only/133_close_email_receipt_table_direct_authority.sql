-- Staging-only migration 133: close residual direct receipt-table authority.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception using errcode='P0001',message='PDC_EMAIL_133_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='132' and name='stock_only_authenticated_email_batch_fanout') then
    raise exception using errcode='P0001',message='PDC_EMAIL_133_PREDECESSOR_132_REQUIRED';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='133') then
    raise exception using errcode='P0001',message='PDC_EMAIL_133_VERSION_CONFLICT';
  end if;
  if to_regclass('public.pdc_authenticated_email_import_receipts') is null
     or to_regclass('public.pdc_authenticated_email_batch_receipts') is null then
    raise exception using errcode='P0001',message='PDC_EMAIL_133_DEPENDENCY_MISSING';
  end if;
end
$guard$;

alter table public.pdc_authenticated_email_import_receipts enable row level security;
alter table public.pdc_authenticated_email_batch_receipts enable row level security;
revoke all on table public.pdc_authenticated_email_import_receipts from public,anon,authenticated,service_role;
revoke all on table public.pdc_authenticated_email_batch_receipts from public,anon,authenticated,service_role;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('133','close_email_receipt_table_direct_authority',array[
  'both authenticated email receipt tables retain RLS',
  'public, anon, authenticated and service_role have no direct receipt-table authority',
  'Migration 132 importer and trigger behavior remain unchanged'
]);

commit;
