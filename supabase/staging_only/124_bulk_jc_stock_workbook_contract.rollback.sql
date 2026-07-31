-- Guarded staging-only rollback for migration 124_bulk_jc_stock_workbook_contract.
-- Authorized by Craig on 2026-07-31 after mandatory release-baseline safety stop.
-- This rollback is permitted only before any Preview/Apply claim or operational write.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local idle_in_transaction_session_timeout = '60s';

select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-124-bulk-workbook-rollback',0));

DO $guard$
declare
  v_count integer;
  v_head integer;
  v_name text;
begin
  if current_setting('transaction_read_only')::boolean then
    raise exception 'rollback_requires_writable_transaction' using errcode='55000';
  end if;

  select count(*) into v_count
  from public.pdc_staging_environment_sentinel
  where singleton and project_ref='cdsmnqxtyyoeoznmbidd';
  if v_count<>1 then
    raise exception 'staging_sentinel_mismatch' using errcode='55000';
  end if;

  select max(version::integer) into v_head
  from supabase_migrations.schema_migrations
  where version~'^[0-9]+$';
  if v_head<>124 then
    raise exception 'ledger_head_mismatch expected 124 got %',v_head using errcode='55000';
  end if;

  select name into v_name
  from supabase_migrations.schema_migrations
  where version='124';
  if v_name is distinct from 'bulk_jc_stock_workbook_contract' then
    raise exception 'migration_124_identity_mismatch' using errcode='55000';
  end if;

  if exists(select 1 from supabase_migrations.schema_migrations where version in ('125','126','127','128')) then
    raise exception 'later_migrations_present' using errcode='55000';
  end if;

  select count(*) into v_count
  from public.pdc_bulk_workbook_authorizations
  where authorization_reference='craig-31-july-2026-retained-workbook'
    and status='available'
    and claimed_at is null
    and claimed_workbook_sha256 is null
    and claimed_payload_sha256 is null
    and claimed_preview_id is null;
  if v_count<>1 or (select count(*) from public.pdc_bulk_workbook_authorizations)<>1 then
    raise exception 'bulk_authorization_not_pristine' using errcode='55000';
  end if;

  if (select count(*) from public.pdc_bulk_workbook_previews)<>0
     or (select count(*) from public.pdc_bulk_workbook_quarantine)<>0
     or (select count(*) from public.pdc_bulk_workbook_apply_receipts)<>0
     or (select count(*) from public.pdc_bulk_workbook_row_receipts)<>0 then
    raise exception 'bulk_contract_runtime_rows_present' using errcode='55000';
  end if;

  if exists(
    select 1 from public.pdc_authenticated_email_import_receipts
    where response->>'source'='pdc_bulk_workbook_124'
       or idempotency_key like 'bulk-workbook:%'
       or source_uid like 'bulk-workbook:%'
  ) then
    raise exception 'bulk_operational_import_receipts_present' using errcode='55000';
  end if;

  if exists(
    select 1 from public.vehicles
    where source_system='bulk_workbook_manager_override'
       or source_record_id like 'bulk:%'
       or permanent_vehicle_id like 'BULK:%'
  ) then
    raise exception 'bulk_created_vehicles_present' using errcode='55000';
  end if;

  if exists(
    select 1 from public.audit_events
    where metadata->>'source'='pdc_bulk_workbook_124'
  ) then
    raise exception 'bulk_audit_events_present' using errcode='55000';
  end if;

  select count(*) into v_count
  from public.pdc_monitor_vehicle_identity_readers i
  join public.pdc_monitor_stage_activation_writers w on w.user_id=i.user_id
  join public.pdc_user_roles r on r.auth_user_id=i.user_id
  where i.active and i.revoked_at is null
    and w.active and w.revoked_at is null
    and r.role='viewer' and r.active and r.account_status='approved';
  if v_count<>1 then
    raise exception 'monitor_viewer_identity_guard_failed' using errcode='55000';
  end if;
end;
$guard$;

-- Callable contract first, then its private helpers and storage.
drop function public.read_pdc_bulk_jc_stock_workbook_receipt(uuid);
drop function public.apply_pdc_bulk_jc_stock_workbook(uuid,text,text);
drop function public.preview_pdc_bulk_jc_stock_workbook(text,jsonb);

drop table
  public.pdc_bulk_workbook_row_receipts,
  public.pdc_bulk_workbook_apply_receipts,
  public.pdc_bulk_workbook_quarantine,
  public.pdc_bulk_workbook_previews,
  public.pdc_bulk_workbook_authorizations;

drop function public.pdc_bulk_workbook_actor_scope();
drop function public.pdc_bulk_workbook_canonical_payload_sha256(jsonb);
drop function public.pdc_bulk_workbook_reject_mutation();

delete from supabase_migrations.schema_migrations
where version='124' and name='bulk_jc_stock_workbook_contract';

DO $post$
begin
  if exists(select 1 from supabase_migrations.schema_migrations where version='124') then
    raise exception 'rollback_ledger_delete_failed' using errcode='55000';
  end if;
  if exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'preview_pdc_bulk_jc_stock_workbook',
      'apply_pdc_bulk_jc_stock_workbook',
      'read_pdc_bulk_jc_stock_workbook_receipt',
      'pdc_bulk_workbook_actor_scope',
      'pdc_bulk_workbook_canonical_payload_sha256',
      'pdc_bulk_workbook_reject_mutation'
    )
  ) then
    raise exception 'rollback_function_cleanup_failed' using errcode='55000';
  end if;
  if exists(
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname like 'pdc_bulk_workbook_%'
  ) then
    raise exception 'rollback_table_cleanup_failed' using errcode='55000';
  end if;
end;
$post$;

commit;
