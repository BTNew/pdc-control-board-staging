begin;

-- Corrective staging-only hardening for the already-applied reset 136.
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='136')
     or to_regclass('public.pdc_staging_reset_batches') is null
     or to_regclass('public.pdc_staging_reset_rows') is null then
    raise exception 'PDC_RESET_137_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;
end;
$guard$;

-- RFT without QC is permitted only while one current canonical Navision record
-- still carries the exact Delivered-to/at-Dealer operational authority.
create or replace function public.pdc_vehicle_has_current_navision_dealer_delivery(p_vehicle_id uuid)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,public
as $authority$
  select count(*)=1
     and bool_and(public.navision_operational_location(r.normalized_data)='Completed')
  from public.navision_backend_records r
  where r.canonical_vehicle_id=p_vehicle_id
    and r.source_system='microsoft_navision'
    and r.is_current
    and r.record_status='current';
$authority$;
revoke all on function public.pdc_vehicle_has_current_navision_dealer_delivery(uuid) from public,anon,authenticated,service_role;

create or replace function public.pdc_enforce_qc_then_rft()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $function$
declare
  v_issues text[];
  v_authoritative_delivered_rft boolean:=public.pdc_vehicle_has_current_navision_dealer_delivery(new.id);
begin
  if (upper(btrim(coalesce(new.current_location,'')))='RFT'
      or lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft')
     and new.qc_completed_at is null and not v_authoritative_delivered_rft then
    raise exception 'RFT vehicles must retain prior QC or current Navision dealer-delivery authority' using errcode='22023';
  end if;
  if old.qc_completed_at is null and new.qc_completed_at is not null then
    if upper(btrim(coalesce(new.current_location,'')))='RFT'
       or lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft' then
      raise exception 'QC sign-off and RFT transfer must be separate audited transitions' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'QC gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;
  if ((upper(btrim(coalesce(old.current_location,''))) is distinct from 'RFT'
       and upper(btrim(coalesce(new.current_location,'')))='RFT')
      or (lower(btrim(coalesce(old.lifecycle_state::text,''))) is distinct from 'rft'
       and lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft'))
     and not v_authoritative_delivered_rft then
    if old.qc_completed_at is null then
      raise exception 'QC sign-off must be completed before RFT transfer' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'RFT gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function public.pdc_enforce_qc_then_rft() from public,anon,authenticated,service_role;

create table if not exists public.pdc_staging_reset_attestations (
  reset_id uuid primary key references public.pdc_staging_reset_batches(reset_id) on delete restrict,
  contract text not null check(contract='pdc_staging_reset_hardening_137'),
  exception_payload_sha256 text not null check(exception_payload_sha256 ~ '^[a-f0-9]{64}$'),
  claimed_backup_manifest_sha256 text not null check(claimed_backup_manifest_sha256 ~ '^[a-f0-9]{64}$'),
  actual_backup_manifest_sha256 text not null check(actual_backup_manifest_sha256 ~ '^[a-f0-9]{64}$'),
  isolated_restore_receipt_sha256 text not null check(isolated_restore_receipt_sha256 ~ '^[a-f0-9]{64}$'),
  execution_identity text not null check(execution_identity='database_owner_migration_runner'),
  authorization_context text not null,
  legacy_attributed_actor_id uuid not null references auth.users(id) on delete restrict,
  legacy_attributed_actor_email text not null,
  corrected_at timestamptz not null default clock_timestamp()
);

alter table public.pdc_staging_reset_attestations enable row level security;
revoke all on table public.pdc_staging_reset_attestations from public,anon,authenticated,service_role;
drop trigger if exists pdc_staging_reset_attestations_immutable on public.pdc_staging_reset_attestations;
create trigger pdc_staging_reset_attestations_immutable before update or delete on public.pdc_staging_reset_attestations
for each row execute function public.pdc_staging_reset_reject_mutation();

-- Remove the mutable marker now that the trigger derives authority live.
update public.vehicles
set source_payload=coalesce(source_payload,'{}'::jsonb)-'reset_location_authority',
    updated_by=null,
    updated_at=clock_timestamp(),
    version=version+1
where source_payload->>'authority'='pdc_staging_workbook_reset_136'
   or deleted_reason='Staging clean reset 136: not in accepted workbook authority set';

-- Fail closed unless all three RFT rows retain current canonical authority.
do $attest$
declare
  v_batch public.pdc_staging_reset_batches%rowtype;
  v_exception_sha text;
  v_reset_count integer;
begin
  select * into strict v_batch from public.pdc_staging_reset_batches
  where contract='pdc_staging_workbook_reset_136' for share;

  select public.pdc_bulk_workbook_canonical_payload_sha256(
    coalesce(jsonb_agg(jsonb_build_object(
      'row_no',source_row_no,
      'job_card_number',job_card_number,
      'stock_number',stock_number,
      'reason',reason,
      'operation_count',operation_count
    ) order by source_row_no),'[]'::jsonb)
  ) into v_exception_sha
  from public.pdc_staging_reset_rows
  where reset_id=v_batch.reset_id and not accepted;

  if v_exception_sha<>'c6450f3b6a43aa05f3ef80441d8f2ece265b05a9c424eb4a834fb60a8e423c88'
     or (select count(*) from public.pdc_staging_reset_rows where reset_id=v_batch.reset_id and not accepted)<>81
     or (select count(distinct stock_number) from public.pdc_staging_reset_rows where reset_id=v_batch.reset_id and not accepted)<>78
     or exists(
       select 1 from public.pdc_staging_reset_rows e
       join public.navision_backend_records r
         on r.source_system='microsoft_navision' and r.is_current and r.record_status='current'
        and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=e.stock_number
       where e.reset_id=v_batch.reset_id and not e.accepted
     ) then
    raise exception 'PDC_RESET_137_EXCEPTION_ATTESTATION_FAILED' using errcode='55000';
  end if;

  select count(*) into v_reset_count
  from public.vehicles v
  where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    and v.current_location='RFT'
    and public.pdc_vehicle_has_current_navision_dealer_delivery(v.id);
  if v_reset_count<>3
     or exists(select 1 from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active'
       and v.visible_on_board and v.current_location='RFT'
       and not public.pdc_vehicle_has_current_navision_dealer_delivery(v.id)) then
    raise exception 'PDC_RESET_137_RFT_AUTHORITY_FAILED' using errcode='55000';
  end if;

  if v_batch.backup_manifest_sha256<>'b624e19411f00eabf9128ea166dd75bb3c43945a2edc9ef716419ce60b6d930a' then
    raise exception 'PDC_RESET_137_LEGACY_BACKUP_CLAIM_CHANGED' using errcode='55000';
  end if;

  insert into public.pdc_staging_reset_attestations(
    reset_id,contract,exception_payload_sha256,claimed_backup_manifest_sha256,
    actual_backup_manifest_sha256,isolated_restore_receipt_sha256,execution_identity,
    authorization_context,legacy_attributed_actor_id,legacy_attributed_actor_email
  ) values(
    v_batch.reset_id,'pdc_staging_reset_hardening_137',v_exception_sha,v_batch.backup_manifest_sha256,
    'b624e1942c621ffed0fa8bbb610a8fa704f0d691a69a0917c666c8930b6d930a',
    '7f7d027f1a0da08982241b9d6f7a553b09908fed93c56f1e934e60a4cee1b439',
    'database_owner_migration_runner','explicit_user_authorized_staging_reset_2026-08-08',
    v_batch.actor_id,v_batch.actor_email
  );

  insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  values('import','pdc_staging_reset_attestations',v_batch.reset_id,null,'database-owner-migration-runner@local.invalid',
    jsonb_build_object('legacy_attributed_actor_id',v_batch.actor_id,'legacy_attributed_actor_email',v_batch.actor_email,
      'claimed_backup_manifest_sha256',v_batch.backup_manifest_sha256),
    jsonb_build_object('execution_identity','database_owner_migration_runner',
      'actual_backup_manifest_sha256','b624e1942c621ffed0fa8bbb610a8fa704f0d691a69a0917c666c8930b6d930a',
      'exception_payload_sha256',v_exception_sha),
    jsonb_build_object('source','pdc_staging_reset_hardening_137','corrects_actor_attribution',true,
      'immutable_reset_history_rewritten',false,'production_changed',false));
end;
$attest$;

commit;
