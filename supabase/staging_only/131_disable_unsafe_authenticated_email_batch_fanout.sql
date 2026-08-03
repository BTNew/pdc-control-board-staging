-- Staging-only migration 131: immediately disable Migration 130's batch RPC
-- while stock-only reconciliation and lifecycle blockers are corrected.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception using errcode='P0001',message='PDC_EMAIL_131_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='130' and name='authenticated_email_backend_batch_fanout') then
    raise exception using errcode='P0001',message='PDC_EMAIL_131_PREDECESSOR_130_REQUIRED';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='131') then
    raise exception using errcode='P0001',message='PDC_EMAIL_131_VERSION_CONFLICT';
  end if;
end $$;

revoke all on function public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamptz,text,jsonb)
from public,anon,authenticated,service_role;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('131','disable_unsafe_authenticated_email_batch_fanout',array[
  'disabled Migration 130 execute authority pending stock-only reconciliation and lifecycle hardening'
]);

comment on function public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamptz,text,jsonb) is
  'Disabled on staging by Migration 131 pending fail-closed stock-only reconciliation, protected activation lifecycle, and revision/audit parity fixes.';
commit;
