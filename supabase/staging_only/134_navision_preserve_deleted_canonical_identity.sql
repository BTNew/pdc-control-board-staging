-- Staging-only migration 134: preserve manually deleted canonical vehicle identity during Navision refreshes.
-- Ordinary Navision evidence may continue to update the shared backend row, but it must not recreate
-- or reopen a soft-deleted operational vehicle. The existing reconciler is retained byte-for-byte
-- behind a bounded wrapper so every non-historical path keeps Migration 083 behavior.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     )
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception using errcode='P0001',message='PDC_NAVISION_134_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists(
       select 1 from supabase_migrations.schema_migrations
       where version='133' and name='close_email_receipt_table_direct_authority'
     ) then
    raise exception using errcode='P0001',message='PDC_NAVISION_134_PREDECESSOR_133_REQUIRED';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='134') then
    raise exception using errcode='P0001',message='PDC_NAVISION_134_VERSION_CONFLICT';
  end if;
  if to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') is null
     or to_regprocedure('public.trigger_reconcile_navision_operational_record()') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_board_activations') is null
     or to_regclass('public.vehicles') is null then
    raise exception using errcode='P0001',message='PDC_NAVISION_134_DEPENDENCY_MISSING';
  end if;
  if to_regprocedure('public.reconcile_navision_operational_record_pre134(uuid,uuid,text)') is not null then
    raise exception using errcode='P0001',message='PDC_NAVISION_134_PREVIOUS_WRAPPER_PRESENT';
  end if;
end
$guard$;

alter function public.reconcile_navision_operational_record(uuid,uuid,text)
  rename to reconcile_navision_operational_record_pre134;
revoke all on function public.reconcile_navision_operational_record_pre134(uuid,uuid,text)
  from public,anon,authenticated;

create function public.reconcile_navision_operational_record(
  p_backend_record_id uuid,
  p_actor_id uuid default null,
  p_actor_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $reconcile$
declare
  v_record public.navision_backend_records%rowtype;
  v_stock text;
  v_vin text;
  v_deleted_vehicle_ids uuid[];
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if p_backend_record_id is null then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  -- Serialize with the retained reconciler. Advisory locks are transaction-reentrant.
  perform pg_advisory_xact_lock(hashtextextended('navision-operational-record:'||p_backend_record_id::text,0));
  select * into v_record
  from public.navision_backend_records
  where id=p_backend_record_id
  for update;
  if not found or not v_record.is_current or v_record.record_status<>'current' then
    return public.reconcile_navision_operational_record_pre134(
      p_backend_record_id,p_actor_id,p_actor_email
    );
  end if;

  v_stock:=nullif(public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch'),'');
  v_vin:=case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin')
    then nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),'') else null end;

  -- A prior manual deletion is authoritative over an ordinary Navision refresh. Match the
  -- retained canonical pointer first, with normalized Stock/VIN as defense for older rows.
  select coalesce(array_agg(v.id order by v.id),'{}'::uuid[])
  into v_deleted_vehicle_ids
  from public.vehicles v
  where v.deleted_at is not null
    and (
      v.id=v_record.canonical_vehicle_id
      or (v_stock is not null and v.stock_number_normalized=v_stock)
      or (v_vin is not null and v.vin_normalized=v_vin)
    );

  if cardinality(v_deleted_vehicle_ids)>0 then
    return public.navision_backend_response(true,'historical_vehicle_retained',jsonb_build_object(
      'backend_record_id',p_backend_record_id,
      'historical_vehicle_count',cardinality(v_deleted_vehicle_ids),
      'operational_change',false
    ));
  end if;

  return public.reconcile_navision_operational_record_pre134(
    p_backend_record_id,p_actor_id,p_actor_email
  );
end;
$reconcile$;

revoke all on function public.reconcile_navision_operational_record(uuid,uuid,text)
  from public,anon,authenticated;

-- PostgreSQL triggers retain the original function OID across a rename, so recreate both
-- triggers explicitly to bind them to the guarded Migration 134 wrapper.
drop trigger if exists navision_record_operational_reconcile on public.navision_backend_records;
create trigger navision_record_operational_reconcile
after insert or update of normalized_data,is_current,record_status on public.navision_backend_records
for each row execute function public.trigger_reconcile_navision_operational_record();

drop trigger if exists navision_activation_operational_reconcile on public.navision_board_activations;
create trigger navision_activation_operational_reconcile
after insert or update of active,activated_stock_number on public.navision_board_activations
for each row execute function public.trigger_reconcile_navision_operational_record();

comment on function public.reconcile_navision_operational_record(uuid,uuid,text) is
  'Staging-only Navision operational reconciler. Preserves soft-deleted canonical vehicle identity without recreating or reopening it; all other paths delegate unchanged to the retained Migration 083 reconciler.';
comment on function public.reconcile_navision_operational_record_pre134(uuid,uuid,text) is
  'Retained pre-Migration-134 operational reconciler. Internal only; called through the historical-identity guard.';

insert into supabase_migrations.schema_migrations(version,name,statements)
values('134','navision_preserve_deleted_canonical_identity',array[
  'ordinary Navision refreshes preserve soft-deleted canonical vehicle identity',
  'historical identity returns success without operational vehicle mutation',
  'all non-historical operational reconciliation delegates to the retained Migration 083 function',
  'Navision record and activation triggers are rebound to the guarded wrapper'
]);

commit;
