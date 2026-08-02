-- Guarded staging-only rollback for migration 124_bulk_jc_stock_workbook_contract.
-- Refuses once any durable Apply receipt exists; recovery after Apply requires a separate procedure.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
set local idle_in_transaction_session_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-124-bulk-workbook-rollback',0));

do $guard$
declare v_count integer; v_head integer; v_name text;
begin
  if current_setting('transaction_read_only')::boolean then raise exception 'rollback_requires_writable_transaction' using errcode='55000'; end if;
  select count(*) into v_count from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd';
  if v_count<>1 then raise exception 'staging_sentinel_mismatch' using errcode='55000'; end if;
  select max(version::integer) into v_head from supabase_migrations.schema_migrations where version~'^[0-9]+$';
  if v_head<>124 then raise exception 'ledger_head_mismatch expected 124 got %',v_head using errcode='55000'; end if;
  select name into v_name from supabase_migrations.schema_migrations where version='124';
  if v_name is distinct from 'bulk_jc_stock_workbook_contract' then raise exception 'migration_124_identity_mismatch' using errcode='55000'; end if;
  if exists(select 1 from supabase_migrations.schema_migrations where case when version~'^[0-9]+$' then version::integer>124 else false end) then raise exception 'later_migrations_present' using errcode='55000'; end if;
  if to_regclass('public.pdc_bulk_workbook_apply_receipts') is null then raise exception 'bulk_contract_apply_receipts_table_missing' using errcode='55000'; end if;
  if exists(select 1 from public.pdc_bulk_workbook_apply_receipts) then raise exception 'bulk_apply_receipts_present_recovery_required' using errcode='55000'; end if;
  if exists(select 1 from public.pdc_authenticated_email_import_receipts where response->>'source'='pdc_bulk_workbook_124' or idempotency_key like 'bulk-workbook:%' or source_uid like 'bulk-workbook:%')
     or exists(select 1 from public.audit_events where metadata->>'source'='pdc_bulk_workbook_124') then
    raise exception 'bulk_operational_writes_present_recovery_required' using errcode='55000';
  end if;
end;
$guard$;

drop function public.read_pdc_bulk_jc_stock_workbook_receipt(uuid);
drop function public.apply_pdc_bulk_jc_stock_workbook(uuid,text,text);
drop function public.preview_pdc_bulk_jc_stock_workbook(text,jsonb);
drop function public.authorize_pdc_bulk_jc_stock_workbook(text,integer,integer);

drop table public.pdc_bulk_workbook_row_receipts,public.pdc_bulk_workbook_apply_receipts,public.pdc_bulk_workbook_quarantine,public.pdc_bulk_workbook_previews,public.pdc_bulk_workbook_authorizations;
drop function public.pdc_bulk_workbook_actor_scope();
drop function public.pdc_bulk_workbook_canonical_payload_sha256(jsonb);
drop function public.pdc_bulk_workbook_reject_mutation();

delete from supabase_migrations.schema_migrations where version='124' and name='bulk_jc_stock_workbook_contract';

do $post$
begin
  if exists(select 1 from supabase_migrations.schema_migrations where version='124') then raise exception 'rollback_ledger_delete_failed' using errcode='55000'; end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('authorize_pdc_bulk_jc_stock_workbook','preview_pdc_bulk_jc_stock_workbook','apply_pdc_bulk_jc_stock_workbook','read_pdc_bulk_jc_stock_workbook_receipt','pdc_bulk_workbook_actor_scope','pdc_bulk_workbook_canonical_payload_sha256','pdc_bulk_workbook_reject_mutation')) then raise exception 'rollback_function_cleanup_failed' using errcode='55000'; end if;
  if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'pdc_bulk_workbook_%') then raise exception 'rollback_table_cleanup_failed' using errcode='55000'; end if;
end;
$post$;
commit;
