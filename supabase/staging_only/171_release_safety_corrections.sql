-- Staging-only append correction for identity, location, Sublet and Admin repack safety.
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-171',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='170' and name='authoritative_workshop_admin_blocks')
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>170)
     or exists(select 1 from supabase_migrations.schema_migrations where version='171') then
    raise exception 'PDC_171_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;
end
$guard$;

-- Active aliases are live-owner identities. Lock owners so alias activation and
-- soft deletion have one serial order, while retaining inactive audit rows.
lock table public.vehicles in share row exclusive mode;
lock table public.vehicle_aliases in share row exclusive mode;
update public.vehicle_aliases a
set active=false,version=a.version+1,updated_at=clock_timestamp()
from public.vehicles owner
where owner.id=a.vehicle_id and owner.deleted_at is not null and a.active;

do $alias_preflight$
begin
  if exists(
    select 1 from public.vehicle_aliases
    where active group by alias_type,alias_value having count(*)>1
  ) then raise exception 'PDC_171_ACTIVE_RAW_ALIAS_DUPLICATE' using errcode='23505'; end if;
end
$alias_preflight$;

drop index if exists public.vehicle_aliases_active_raw_unique_idx;
create unique index vehicle_aliases_active_raw_unique_idx
  on public.vehicle_aliases(alias_type,alias_value) where active;

create or replace function public.enforce_vehicle_alias_identity_uniqueness()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $alias$
declare
  v_type text:=lower(btrim(new.alias_type));
  v_value text:=public.normalize_vehicle_alias_value(new.alias_type,new.alias_value);
  v_source text:=public.normalize_vehicle_source_system(new.source_system);
begin
  if new.active then
    perform 1 from public.vehicles owner
    where owner.id=new.vehicle_id and owner.deleted_at is null for update;
    if not found then
      raise exception 'active vehicle alias requires a live owner' using errcode='23514',
        detail=public.vehicle_master_response(false,'invalid_owner',jsonb_build_object('field','vehicle_id','vehicle_id',new.vehicle_id))::text;
    end if;
  end if;
  if v_type='vin' and nullif(btrim(new.alias_value),'') is not null
     and not public.is_valid_vehicle_vin(new.alias_value)
     and (tg_op='INSERT' or old.alias_type is distinct from new.alias_type or old.alias_value is distinct from new.alias_value) then
    raise exception 'invalid VIN alias' using errcode='23514',
      detail=public.vehicle_master_response(false,'invalid_value',jsonb_build_object('field','vin'))::text;
  end if;
  if new.active and ((v_type='vin' and public.is_valid_vehicle_vin(new.alias_value))
     or (v_type='stock_number' and public.is_real_vehicle_stock_number(new.alias_value))) then
    perform pg_advisory_xact_lock(hashtextextended('vehicle-master:'||v_type||':'||v_value,0));
    if exists(select 1 from public.vehicle_aliases a join public.vehicles owner on owner.id=a.vehicle_id and owner.deleted_at is null
      where a.id<>new.id and a.active and a.alias_type_normalized=v_type and a.normalized_alias_value=v_value) then
      raise exception 'duplicate global vehicle alias' using errcode='23505',
        detail=public.vehicle_master_response(false,'duplicate_candidate',jsonb_build_object('field',v_type))::text;
    end if;
    if exists(select 1 from public.vehicles v where v.id<>new.vehicle_id and v.deleted_at is null and
      ((v_type='vin' and public.is_valid_vehicle_vin(v.vin) and v.vin_normalized=v_value)
       or (v_type='stock_number' and public.is_real_vehicle_stock_number(v.stock_number) and v.stock_number_normalized=v_value))) then
      raise exception 'vehicle alias conflicts with another canonical identity' using errcode='23505',
        detail=public.vehicle_master_response(false,'conflicting_candidate',jsonb_build_object('field',v_type))::text;
    end if;
  end if;
  if new.active and v_type in('source_record_id','toyota_order_number','job_card_number') and v_source is not null and v_value is not null then
    perform pg_advisory_xact_lock(hashtextextended('vehicle-master:source-alias:'||v_source||':'||v_type||':'||v_value,0));
    if exists(select 1 from public.vehicle_aliases a join public.vehicles owner on owner.id=a.vehicle_id and owner.deleted_at is null
      where a.id<>new.id and a.active and a.source_system_normalized=v_source and a.alias_type_normalized=v_type and a.normalized_alias_value=v_value) then
      raise exception 'duplicate source-scoped vehicle alias' using errcode='23505',
        detail=public.vehicle_master_response(false,'duplicate_candidate',jsonb_build_object('field',v_type,'source_system',v_source))::text;
    end if;
  end if;
  return new;
end
$alias$;
revoke all on function public.enforce_vehicle_alias_identity_uniqueness() from public,anon,authenticated,service_role;
drop trigger if exists vehicle_aliases_enforce_master_identity_uniqueness on public.vehicle_aliases;
create trigger vehicle_aliases_enforce_master_identity_uniqueness
before insert or update of vehicle_id,alias_type,alias_value,active,source_system on public.vehicle_aliases
for each row execute function public.enforce_vehicle_alias_identity_uniqueness();

create or replace function public.deactivate_vehicle_aliases_on_soft_delete()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $deactivate$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    update public.vehicle_aliases set active=false,version=version+1,updated_at=clock_timestamp()
      where vehicle_id=new.id and active;
  end if;
  return new;
end
$deactivate$;
revoke all on function public.deactivate_vehicle_aliases_on_soft_delete() from public,anon,authenticated,service_role;

create or replace function public.enforce_vehicle_reactivation_identity_uniqueness()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $reactivation$
declare v_value text;
begin
  if old.deleted_at is not null and new.deleted_at is null then
    if public.is_valid_vehicle_vin(new.vin) then
      v_value:=public.normalize_vehicle_vin(new.vin);
      perform pg_advisory_xact_lock(hashtextextended('vehicle-master:vin:'||v_value,0));
      if exists(select 1 from public.vehicle_aliases a join public.vehicles owner on owner.id=a.vehicle_id and owner.deleted_at is null
        where a.active and a.vehicle_id<>new.id and a.alias_type_normalized='vin' and a.normalized_alias_value=v_value) then
        raise exception 'reactivated VIN conflicts with live vehicle alias' using errcode='23505';
      end if;
    end if;
    if public.is_real_vehicle_stock_number(new.stock_number) then
      v_value:=public.normalize_vehicle_stock_number(new.stock_number);
      perform pg_advisory_xact_lock(hashtextextended('vehicle-master:stock_number:'||v_value,0));
      if exists(select 1 from public.vehicle_aliases a join public.vehicles owner on owner.id=a.vehicle_id and owner.deleted_at is null
        where a.active and a.vehicle_id<>new.id and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_value) then
        raise exception 'reactivated stock number conflicts with live vehicle alias' using errcode='23505';
      end if;
    end if;
  end if;
  return new;
end
$reactivation$;
revoke all on function public.enforce_vehicle_reactivation_identity_uniqueness() from public,anon,authenticated,service_role;
drop trigger if exists vehicles_enforce_reactivation_identity_uniqueness on public.vehicles;
create trigger vehicles_enforce_reactivation_identity_uniqueness
before update of deleted_at on public.vehicles for each row
when(old.deleted_at is not null and new.deleted_at is null)
execute function public.enforce_vehicle_reactivation_identity_uniqueness();

-- A row UPDATE locks the alias before its BEFORE trigger can lock the owner. A
-- soft delete already owns the vehicle row, so it must never wait for such an
-- alias row. NOWAIT converts that inversion into an explicit retry instead of
-- a deadlock; the normal AFTER trigger then performs versioned deactivation.
create or replace function public.prelock_vehicle_aliases_for_soft_delete()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $alias_prelock$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    begin
      perform 1 from public.vehicle_aliases a where a.vehicle_id=old.id and a.active order by a.id for update nowait;
    exception when lock_not_available then
      raise exception 'concurrent alias mutation; retry vehicle deletion' using errcode='40001';
    end;
  end if;
  return new;
end
$alias_prelock$;
revoke all on function public.prelock_vehicle_aliases_for_soft_delete() from public,anon,authenticated,service_role;
drop trigger if exists vehicles_alias_prelock_for_soft_delete on public.vehicles;
create trigger vehicles_alias_prelock_for_soft_delete before update of deleted_at on public.vehicles
for each row when(old.deleted_at is null and new.deleted_at is not null)
execute function public.prelock_vehicle_aliases_for_soft_delete();

-- Restore the helper name used by Migration169 to the established Migration089
-- parser contract, then wrap the reconciler with Migration134's deleted guard.
create or replace function public.navision_kewdale_eta(p_data jsonb)
returns date language sql stable security definer set search_path=pg_catalog,public as $$
  select public.navision_kewdale_eta_from_payload(p_data)
$$;
revoke all on function public.navision_kewdale_eta(jsonb) from public,anon,authenticated,service_role;

-- Restore Migration134's historical-identity short-circuit around the current
-- Migration169 location reconciler instead of replacing its latch behavior.
alter function public.reconcile_navision_operational_record(uuid,uuid,text)
  rename to reconcile_navision_operational_record_pre171;
create function public.reconcile_navision_operational_record(
  p_backend_record_id uuid,p_actor_id uuid default null,p_actor_email text default null
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $reconcile$
declare v_record public.navision_backend_records%rowtype;v_stock text;v_vin text;v_deleted uuid[];
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment');end if;
  if p_backend_record_id is null then return public.navision_backend_response(false,'invalid_input');end if;
  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  perform pg_advisory_xact_lock(hashtextextended('navision-operational-record:'||p_backend_record_id::text,0));
  select * into v_record from public.navision_backend_records where id=p_backend_record_id for update;
  if not found or not v_record.is_current or v_record.record_status<>'current' then
    return public.reconcile_navision_operational_record_pre171(p_backend_record_id,p_actor_id,p_actor_email);
  end if;
  v_stock:=nullif(public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch'),'');
  v_vin:=case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin') then nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),'') end;
  select coalesce(array_agg(v.id order by v.id),'{}'::uuid[]) into v_deleted
  from public.vehicles v where v.deleted_at is not null and
    (v.id=v_record.canonical_vehicle_id or (v_stock is not null and v.stock_number_normalized=v_stock) or (v_vin is not null and v.vin_normalized=v_vin));
  if cardinality(v_deleted)>0 then
    return public.navision_backend_response(true,'historical_vehicle_retained',jsonb_build_object('backend_record_id',p_backend_record_id,'historical_vehicle_count',cardinality(v_deleted),'operational_change',false));
  end if;
  return public.reconcile_navision_operational_record_pre171(p_backend_record_id,p_actor_id,p_actor_email);
end
$reconcile$;
revoke all on function public.reconcile_navision_operational_record(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.reconcile_navision_operational_record_pre171(uuid,uuid,text) from public,anon,authenticated,service_role;

-- Canonical Sublet and Workshop scheduling share one deterministic lock order.
create or replace function public.pdc_lock_canonical_sublet_vehicle(p_vehicle_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $sublet_locks$
begin
  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||p_vehicle_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-booking:'||p_vehicle_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-instance:'||p_vehicle_id::text,0));
end
$sublet_locks$;
revoke all on function public.pdc_lock_canonical_sublet_vehicle(uuid) from public,anon,authenticated,service_role;

create or replace function public.pdc_sublet_away_on_date(p_vehicle_id uuid,p_workshop_date date)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $canonical_away$
 select exists(select 1 from public.pdc_sublet_booking_instances i
   where i.vehicle_id=p_vehicle_id and i.status in('active','returned') and p_workshop_date>=i.out_date
     and (i.status='active' or p_workshop_date<(i.returned_at at time zone 'Australia/Perth')::date));
$canonical_away$;
revoke all on function public.pdc_sublet_away_on_date(uuid,date) from public,anon,authenticated,service_role;

create or replace function public.pdc_canonical_sublet_workshop_overlap_guard()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $canonical_overlap$
declare v_return_date date;
begin
  perform public.pdc_lock_canonical_sublet_vehicle(new.vehicle_id);
  if new.status='cancelled' then return new;end if;
  v_return_date:=case when new.status='returned' then (new.returned_at at time zone 'Australia/Perth')::date else null end;
  if exists(select 1 from public.workshop_bookings b
    where b.vehicle_id=new.vehicle_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage')
      and daterange(new.out_date,v_return_date,'[)') && daterange(
        (b.scheduled_start_at at time zone 'Australia/Perth')::date,
        ((public.workshop_booking_effective_end_at(b.id)-interval '1 microsecond') at time zone 'Australia/Perth')::date+1,'[)')) then
    raise exception '%',jsonb_build_object('error','workshop_booking_conflict','vehicle_id',new.vehicle_id)::text using errcode='23514';
  end if;
  return new;
end
$canonical_overlap$;
revoke all on function public.pdc_canonical_sublet_workshop_overlap_guard() from public,anon,authenticated,service_role;
drop trigger if exists pdc_canonical_sublet_workshop_overlap_guard on public.pdc_sublet_booking_instances;
create trigger pdc_canonical_sublet_workshop_overlap_guard
before insert or update of vehicle_id,out_date,returned_at,status on public.pdc_sublet_booking_instances
for each row execute function public.pdc_canonical_sublet_workshop_overlap_guard();

-- Canonical Sublet cancellation is versioned and evidenced. Vehicle deletion
-- cancels active rows but retains booking/history/receipt evidence.
create or replace function public.cancel_pdc_sublet_booking(p_booking_id uuid,p_expected_version bigint,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $cancel$
declare v_user uuid:=auth.uid();v_vehicle_id uuid;v_before public.pdc_sublet_booking_instances%rowtype;v_after public.pdc_sublet_booking_instances%rowtype;v_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment');end if;
  if not public.pdc_sublet_actor_allowed() then return public.navision_backend_response(false,'unauthorized');end if;
  if length(btrim(coalesce(p_reason,'')))>500 then return public.navision_backend_response(false,'invalid_reason');end if;
  select vehicle_id into v_vehicle_id from public.pdc_sublet_booking_instances where booking_id=p_booking_id;
  if not found then return public.navision_backend_response(false,'booking_not_found');end if;
  perform public.pdc_lock_canonical_sublet_vehicle(v_vehicle_id);
  select * into v_before from public.pdc_sublet_booking_instances where booking_id=p_booking_id for update;
  if not found then return public.navision_backend_response(false,'booking_not_found');end if;
  if v_before.version<>coalesce(p_expected_version,0) then return public.navision_backend_response(false,'version_conflict',jsonb_build_object('current_version',v_before.version));end if;
  if v_before.status='cancelled' then return public.navision_backend_response(true,'already_cancelled',jsonb_build_object('booking',to_jsonb(v_before)));end if;
  if v_before.status<>'active' then return public.navision_backend_response(false,'invalid_cancel_state');end if;
  update public.pdc_sublet_booking_instances set status='cancelled',cancelled_at=clock_timestamp(),cancelled_by=v_user,
    notes=case when nullif(btrim(coalesce(p_reason,'')),'') is null then notes else concat_ws(E'\n',nullif(notes,''),'Cancelled: '||btrim(p_reason)) end,
    version=version+1,updated_at=clock_timestamp(),updated_by=v_user where booking_id=p_booking_id returning * into v_after;
  insert into public.pdc_sublet_booking_instance_history(booking_id,vehicle_id,actor_id,actor_email,action,before_data,after_data,booking_version,evidence)
    values(v_after.booking_id,v_after.vehicle_id,v_user,public.current_actor_email(),'cancelled',to_jsonb(v_before),to_jsonb(v_after),v_after.version,jsonb_build_object('reason',nullif(btrim(coalesce(p_reason,'')),'')));
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton returning revision into v_revision;
  return public.navision_backend_response(true,'cancelled',jsonb_build_object('booking',to_jsonb(v_after),'revision',v_revision));
end
$cancel$;
revoke all on function public.cancel_pdc_sublet_booking(uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.cancel_pdc_sublet_booking(uuid,bigint,text) to authenticated;

create or replace function public.cancel_active_sublets_on_vehicle_delete()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $delete_sublets$
declare v_row public.pdc_sublet_booking_instances%rowtype;v_after public.pdc_sublet_booking_instances%rowtype;v_actor uuid;
begin
  if old.deleted_at is null and new.deleted_at is not null then
    v_actor:=coalesce(auth.uid(),new.updated_by,old.updated_by);
    perform public.pdc_lock_canonical_sublet_vehicle(new.id);
    for v_row in select * from public.pdc_sublet_booking_instances where vehicle_id=new.id and status='active' order by booking_id for update loop
      update public.pdc_sublet_booking_instances set status='cancelled',cancelled_at=clock_timestamp(),cancelled_by=v_actor,
        version=version+1,updated_at=clock_timestamp(),updated_by=v_actor where booking_id=v_row.booking_id returning * into v_after;
      insert into public.pdc_sublet_booking_instance_history(booking_id,vehicle_id,actor_id,actor_email,action,before_data,after_data,booking_version,evidence)
        values(v_after.booking_id,v_after.vehicle_id,v_actor,coalesce(public.current_actor_email(),'system'),'cancelled',to_jsonb(v_row),to_jsonb(v_after),v_after.version,jsonb_build_object('reason','vehicle_soft_delete'));
    end loop;
    if found then update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;end if;
  end if;
  return new;
end
$delete_sublets$;
revoke all on function public.cancel_active_sublets_on_vehicle_delete() from public,anon,authenticated,service_role;
drop trigger if exists vehicles_cancel_active_sublets_on_delete on public.vehicles;
create trigger vehicles_cancel_active_sublets_on_delete before update of deleted_at on public.vehicles
for each row when(old.deleted_at is null and new.deleted_at is not null)
execute function public.cancel_active_sublets_on_vehicle_delete();

-- All canonical instance writers use advisory -> booking-row order. Renamed
-- implementations retain their validation/evidence logic but are no longer
-- directly executable by API roles.
alter function public.update_pdc_sublet_booking(uuid,bigint,date,date,text)
  rename to update_pdc_sublet_booking_pre171;
create function public.update_pdc_sublet_booking(p_booking_id uuid,p_expected_version bigint,p_out_date date,p_expected_return_date date,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $update_wrapper$
declare v_vehicle_id uuid;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment');end if;
  if not public.pdc_sublet_actor_allowed() then return public.navision_backend_response(false,'unauthorized');end if;
  select vehicle_id into v_vehicle_id from public.pdc_sublet_booking_instances where booking_id=p_booking_id;
  if not found then return public.navision_backend_response(false,'booking_not_found');end if;
  perform public.pdc_lock_canonical_sublet_vehicle(v_vehicle_id);
  return public.update_pdc_sublet_booking_pre171(p_booking_id,p_expected_version,p_out_date,p_expected_return_date,p_notes);
end
$update_wrapper$;
revoke all on function public.update_pdc_sublet_booking_pre171(uuid,bigint,date,date,text) from public,anon,authenticated,service_role;
revoke all on function public.update_pdc_sublet_booking(uuid,bigint,date,date,text) from public,anon,authenticated,service_role;
grant execute on function public.update_pdc_sublet_booking(uuid,bigint,date,date,text) to authenticated;

alter function public.return_pdc_sublet_booking(uuid,bigint,timestamptz)
  rename to return_pdc_sublet_booking_pre171;
create function public.return_pdc_sublet_booking(p_booking_id uuid,p_expected_version bigint,p_returned_at timestamptz default clock_timestamp())
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $return_wrapper$
declare v_vehicle_id uuid;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment');end if;
  if not public.pdc_sublet_actor_allowed() then return public.navision_backend_response(false,'unauthorized');end if;
  select vehicle_id into v_vehicle_id from public.pdc_sublet_booking_instances where booking_id=p_booking_id;
  if not found then return public.navision_backend_response(false,'booking_not_found');end if;
  perform public.pdc_lock_canonical_sublet_vehicle(v_vehicle_id);
  return public.return_pdc_sublet_booking_pre171(p_booking_id,p_expected_version,p_returned_at);
end
$return_wrapper$;
revoke all on function public.return_pdc_sublet_booking_pre171(uuid,bigint,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.return_pdc_sublet_booking(uuid,bigint,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.return_pdc_sublet_booking(uuid,bigint,timestamptz) to authenticated;

-- Provider email exact-one resolution is serialized per vehicle. Replay keys are
-- accepted only when every immutable request/evidence field matches the receipt.
create or replace function public.apply_pdc_sublet_email_update(p_replay_key text,p_vehicle_id uuid,p_provider_name text,p_sender_email text,p_language_kind text,p_out_date date,p_expected_return_date date,p_message_id text,p_attachment_sha256 text,p_received_at timestamptz,p_evidence jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $email$
declare v_user uuid:=auth.uid();v_provider_id uuid;v_provider_count int;v_match_count int;v_before public.pdc_sublet_booking_instances%rowtype;v_after public.pdc_sublet_booking_instances%rowtype;v_receipt public.pdc_sublet_email_update_receipts%rowtype;v_revision bigint;v_replay_match boolean;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment');end if;
  if not public.pdc_sublet_actor_allowed() then return public.navision_backend_response(false,'unauthorized');end if;
  if nullif(btrim(coalesce(p_replay_key,'')),'') is null or length(p_replay_key)<16 or p_vehicle_id is null
     or lower(btrim(coalesce(p_sender_email,'')))!~'^[^@[:space:]]+@[^@[:space:]]+$'
     or p_language_kind not in('booking_confirmed','eta_confirmed') or nullif(btrim(coalesce(p_message_id,'')),'') is null
     or p_received_at is null or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object'
     or (p_attachment_sha256 is not null and lower(p_attachment_sha256)!~'^[0-9a-f]{64}$') then
    return public.navision_backend_response(false,'invalid_evidence');
  end if;
  perform public.pdc_lock_canonical_sublet_vehicle(p_vehicle_id);
  select count(distinct p.id),(array_agg(distinct p.id))[1] into v_provider_count,v_provider_id
  from public.sublet_providers p left join public.sublet_provider_aliases a on a.provider_id=p.id
  where p.active and (lower(p.name)=lower(btrim(p_provider_name)) or a.source_key=public.sublet_provider_match_key(p_provider_name));
  if v_provider_count<>1 then return public.navision_backend_response(false,case when v_provider_count=0 then 'provider_not_found' else 'provider_ambiguous' end);end if;
  select * into v_receipt from public.pdc_sublet_email_update_receipts where replay_key=p_replay_key;
  if found then
    v_replay_match:=v_receipt.vehicle_id=p_vehicle_id and v_receipt.provider_id=v_provider_id
      and v_receipt.sender_email=lower(btrim(p_sender_email)) and v_receipt.message_id=p_message_id
      and v_receipt.attachment_sha256 is not distinct from lower(p_attachment_sha256)
      and v_receipt.evidence=coalesce(p_evidence,'{}'::jsonb) and v_receipt.language_kind=p_language_kind
      and v_receipt.applied_out_date is not distinct from p_out_date
      and v_receipt.applied_expected_return_date is not distinct from p_expected_return_date
      and v_receipt.received_at=p_received_at and v_receipt.prior_version=coalesce(p_expected_version,0);
    if not v_replay_match then return public.navision_backend_response(false,'replay_conflict');end if;
    return public.navision_backend_response(true,'replayed',jsonb_build_object('receipt_id',v_receipt.receipt_id,'booking_id',v_receipt.booking_id,'version',v_receipt.resulting_version));
  end if;
  select count(*),(array_agg(booking_id))[1] into v_match_count,v_before.booking_id
  from public.pdc_sublet_booking_instances where vehicle_id=p_vehicle_id and provider_id=v_provider_id and status='active' and lower(provider_email)=lower(btrim(p_sender_email));
  if v_match_count<>1 then return public.navision_backend_response(false,case when v_match_count=0 then 'booking_not_found' else 'booking_ambiguous' end);end if;
  select * into v_before from public.pdc_sublet_booking_instances where booking_id=v_before.booking_id for update;
  if v_before.version<>coalesce(p_expected_version,0) then return public.navision_backend_response(false,'version_conflict',jsonb_build_object('current_version',v_before.version));end if;
  if (p_language_kind='booking_confirmed' and p_out_date is null) or (p_language_kind='eta_confirmed' and p_expected_return_date is null) then return public.navision_backend_response(false,'definitive_value_missing');end if;
  if coalesce(p_out_date,v_before.out_date)>coalesce(p_expected_return_date,v_before.expected_return_date) then return public.navision_backend_response(false,'invalid_date_order');end if;
  update public.pdc_sublet_booking_instances set out_date=coalesce(p_out_date,out_date),expected_return_date=coalesce(p_expected_return_date,expected_return_date),
    source_kind='provider_email',source_ref=p_message_id,source_evidence=p_evidence||jsonb_build_object('message_id',p_message_id,'attachment_sha256',p_attachment_sha256,'sender_email',lower(btrim(p_sender_email))),
    version=version+1,updated_at=clock_timestamp(),updated_by=v_user where booking_id=v_before.booking_id returning * into v_after;
  insert into public.pdc_sublet_email_update_receipts(replay_key,booking_id,vehicle_id,provider_id,provider_name,sender_email,message_id,attachment_sha256,evidence,language_kind,prior_version,resulting_version,applied_out_date,applied_expected_return_date,received_at,applied_by)
    values(p_replay_key,v_after.booking_id,v_after.vehicle_id,v_after.provider_id,v_after.provider_name,lower(btrim(p_sender_email)),p_message_id,lower(p_attachment_sha256),p_evidence,p_language_kind,v_before.version,v_after.version,p_out_date,p_expected_return_date,p_received_at,v_user) returning * into v_receipt;
  insert into public.pdc_sublet_booking_instance_history(booking_id,vehicle_id,actor_id,actor_email,action,before_data,after_data,booking_version,evidence)
    values(v_after.booking_id,v_after.vehicle_id,v_user,public.current_actor_email(),'email_updated',to_jsonb(v_before),to_jsonb(v_after),v_after.version,jsonb_build_object('receipt_id',v_receipt.receipt_id,'message_id',p_message_id,'attachment_sha256',p_attachment_sha256));
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton returning revision into v_revision;
  return public.navision_backend_response(true,'email_updated',jsonb_build_object('receipt_id',v_receipt.receipt_id,'booking_id',v_after.booking_id,'version',v_after.version,'revision',v_revision));
exception when unique_violation then
  select * into v_receipt from public.pdc_sublet_email_update_receipts where replay_key=p_replay_key;
  if not found then raise;end if;
  if v_receipt.vehicle_id<>p_vehicle_id or v_receipt.provider_id<>v_provider_id
     or v_receipt.sender_email<>lower(btrim(p_sender_email)) or v_receipt.message_id<>p_message_id
     or v_receipt.attachment_sha256 is distinct from lower(p_attachment_sha256)
     or v_receipt.evidence<>coalesce(p_evidence,'{}'::jsonb) or v_receipt.language_kind<>p_language_kind
     or v_receipt.applied_out_date is distinct from p_out_date or v_receipt.applied_expected_return_date is distinct from p_expected_return_date
     or v_receipt.received_at<>p_received_at or v_receipt.prior_version<>coalesce(p_expected_version,0) then return public.navision_backend_response(false,'replay_conflict');end if;
  return public.navision_backend_response(true,'replayed',jsonb_build_object('receipt_id',v_receipt.receipt_id,'booking_id',v_receipt.booking_id,'version',v_receipt.resulting_version));
when exclusion_violation then return public.navision_backend_response(false,'sublet_booking_overlap');
end
$email$;
revoke all on function public.apply_pdc_sublet_email_update(text,uuid,text,text,text,date,date,text,text,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function public.apply_pdc_sublet_email_update(text,uuid,text,text,text,date,date,text,text,timestamptz,jsonb,bigint) to authenticated;

-- Migration160's generic Sublet action captured legacy before/after state. Fail
-- that obsolete path closed and require the provider-attested, canonical UUID,
-- payload-bound contract above; all other communication actions are unchanged.
alter function public.process_pdc_email_communication(uuid,text,text,jsonb,text)
  rename to process_pdc_email_communication_pre171;
create function public.process_pdc_email_communication(p_intake_id uuid,p_expected_source_hash text,p_extraction_hash text,p_extraction jsonb,p_actor text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions set statement_timeout='180s' as $communication_wrapper$
begin
  if public.pdc_monitor_staging_guard() and auth.uid() is not null and lower(btrim(coalesce(p_actor,'')))='pdc-monitor'
     and exists(select 1 from public.pdc_user_roles r where r.auth_user_id=auth.uid() and r.role='importer' and r.active and r.account_status='approved')
     and jsonb_typeof(p_extraction)='object' and jsonb_typeof(p_extraction->'actions')='array'
     and exists(select 1 from jsonb_array_elements(p_extraction->'actions')a where a->>'action_type'='set_sublet_booking_date') then
    return public.navision_backend_response(false,'provider_attested_sublet_contract_required');
  end if;
  return public.process_pdc_email_communication_pre171(p_intake_id,p_expected_source_hash,p_extraction_hash,p_extraction,p_actor);
end
$communication_wrapper$;
revoke all on function public.process_pdc_email_communication_pre171(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function public.process_pdc_email_communication(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.process_pdc_email_communication(uuid,text,text,jsonb,text) to authenticated;

-- Admin mutations follow estimate synchronization's advisory-first order. An
-- ordinary booking mutation can already own a row before requesting the bay,
-- so Admin never waits for rows while holding bay locks: it fails retryably.
create or replace function public.workshop_admin_lock_physical_bays(p_first uuid,p_second uuid default null)
returns void language plpgsql security definer set search_path=pg_catalog,public as $admin_locks$
declare v_bay uuid;v_technician uuid;
begin
  for v_bay in select distinct x from unnest(array[p_first,p_second])x where x is not null order by x loop
    perform public.workshop_lock_resources(v_bay,null);
  end loop;
  for v_technician in
    select distinct a.technician_id from public.workshop_booking_assignments a
    join public.workshop_bookings b on b.id=a.booking_id
    where a.released_at is null and b.deleted_at is null and b.bay_id in(p_first,coalesce(p_second,p_first))
      and b.status in('queued','planned','started','stoppage')
    order by a.technician_id
  loop
    perform public.workshop_lock_resources(null,v_technician);
  end loop;
  begin
    perform 1 from public.workshop_bookings b
      where b.bay_id in(p_first,coalesce(p_second,p_first)) and b.deleted_at is null
        and b.status in('queued','planned','started','stoppage')
      order by b.id for update nowait;
  exception when lock_not_available then
    raise exception 'concurrent workshop booking mutation; retry Admin block change' using errcode='40001';
  end;
end
$admin_locks$;
revoke all on function public.workshop_admin_lock_physical_bays(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.workshop_enforce_admin_block_fixed_booking_conflict()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $fixed_guard$
begin
  if new.deleted_at is not null then return new;end if;
  if exists(select 1 from public.workshop_bookings b
    where b.bay_id=new.bay_id and b.deleted_at is null and b.status in('queued','started','stoppage','completed')
      and b.scheduled_start_at<new.scheduled_end_at
      and public.workshop_booking_effective_end_at(b.id)>new.scheduled_start_at) then
    raise exception '%',jsonb_build_object('error','fixed_booking_conflict','bay_id',new.bay_id)::text using errcode='23514';
  end if;
  return new;
end
$fixed_guard$;
revoke all on function public.workshop_enforce_admin_block_fixed_booking_conflict() from public,anon,authenticated,service_role;
drop trigger if exists workshop_admin_blocks_fixed_booking_conflict on public.workshop_admin_blocks;
create trigger workshop_admin_blocks_fixed_booking_conflict
before insert or update of bay_id,scheduled_start_at,scheduled_end_at,deleted_at on public.workshop_admin_blocks
for each row execute function public.workshop_enforce_admin_block_fixed_booking_conflict();

-- Plan all forward-only shifts across every canonical exclusion dimension,
-- then apply them latest-first. This clears each occupied bay/technician
-- interval before the preceding booking moves.
create or replace function public.workshop_admin_repack_planned(p_bay_id uuid,p_from timestamptz,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $repack$
declare
  v_booking public.workshop_bookings%rowtype;v_start timestamptz;v_end timestamptz;v_block_end timestamptz;v_fixed_end timestamptz;v_tech_end timestamptz;
  v_vehicle_end timestamptz;v_leave_date date;v_effective_duration integer;
  v_technician uuid;v_cursor timestamptz:=p_from;v_plan jsonb:='[]'::jsonb;v_item jsonb;v_before jsonb;v_after jsonb;v_shifted uuid[]:='{}'::uuid[];v_guard integer;
begin
  -- The caller owns the bay advisory lock; lock the complete planned set in a deterministic order.
  for v_booking in select * from public.workshop_bookings b
    where b.bay_id=p_bay_id and b.status='planned' and b.deleted_at is null and public.workshop_booking_effective_end_at(b.id)>p_from
    order by b.scheduled_start_at,b.id for update loop
    select a.technician_id into v_technician from public.workshop_booking_assignments a
      where a.booking_id=v_booking.id and a.released_at is null
      order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1;
    v_effective_duration:=public.workshop_booking_effective_duration_minutes(v_booking.id);
    if v_effective_duration is null or v_effective_duration<60 then raise exception 'Invalid effective booking duration' using errcode='22023';end if;
    v_start:=greatest(v_booking.scheduled_start_at,v_cursor);v_guard:=0;
    loop
      v_guard:=v_guard+1;if v_guard>1000 then raise exception 'Workshop admin repack guard exceeded' using errcode='54000';end if;
      v_start:=public.workshop_next_calendar_window(v_start,v_effective_duration);
      v_end:=public.workshop_add_operational_minutes(v_start,v_effective_duration);
      select max(a.scheduled_end_at) into v_block_end from public.workshop_admin_blocks a
        where a.bay_id=p_bay_id and a.deleted_at is null and a.scheduled_start_at<v_end and a.scheduled_end_at>v_start;
      select max(public.workshop_booking_effective_end_at(b.id)) into v_fixed_end from public.workshop_bookings b
        where b.bay_id=p_bay_id and b.id<>v_booking.id and b.deleted_at is null and b.status in('queued','started','stoppage','completed')
          and b.scheduled_start_at<v_end and public.workshop_booking_effective_end_at(b.id)>v_start;
      select max(public.workshop_booking_effective_end_at(b.id)) into v_vehicle_end from public.workshop_bookings b
        where b.vehicle_id=v_booking.vehicle_id and b.id<>v_booking.id and b.deleted_at is null
          and b.status in('queued','planned','started','stoppage')
          and not (b.bay_id=p_bay_id and b.status='planned' and public.workshop_booking_effective_end_at(b.id)>p_from)
          and b.scheduled_start_at<v_end and public.workshop_booking_effective_end_at(b.id)>v_start;
      v_tech_end:=null;
      v_leave_date:=null;
      if v_technician is not null then
        select max(greatest(a.scheduled_end_at,public.workshop_booking_effective_end_at(a.booking_id))) into v_tech_end from public.workshop_booking_assignments a
          join public.workshop_bookings b on b.id=a.booking_id
          where a.technician_id=v_technician and a.released_at is null and a.booking_id<>v_booking.id
            and not (b.bay_id=p_bay_id and b.status='planned' and b.deleted_at is null and public.workshop_booking_effective_end_at(b.id)>p_from)
            and a.scheduled_start_at<v_end and greatest(a.scheduled_end_at,public.workshop_booking_effective_end_at(a.booking_id))>v_start;
        v_leave_date:=public.workshop_technician_leave_date(v_technician,v_start,v_end);
      end if;
      exit when v_block_end is null and v_fixed_end is null and v_vehicle_end is null and v_tech_end is null and v_leave_date is null;
      v_start:=greatest(coalesce(v_block_end,v_start),coalesce(v_fixed_end,v_start),coalesce(v_vehicle_end,v_start),coalesce(v_tech_end,v_start),
        coalesce(((v_leave_date+1)::timestamp at time zone 'Australia/Perth'),v_start));
    end loop;
    v_cursor:=v_end;
    v_plan:=v_plan||jsonb_build_array(jsonb_build_object('booking_id',v_booking.id,'scheduled_start_at',v_start,'scheduled_end_at',v_end,'duration_minutes',v_effective_duration,'technician_id',v_technician));
  end loop;
  for v_item in select value from jsonb_array_elements(v_plan) order by (value->>'scheduled_start_at')::timestamptz desc,(value->>'booking_id')::uuid desc loop
    select * into v_booking from public.workshop_bookings where id=(v_item->>'booking_id')::uuid for update;
    v_start:=(v_item->>'scheduled_start_at')::timestamptz;v_end:=(v_item->>'scheduled_end_at')::timestamptz;
    if v_start is distinct from v_booking.scheduled_start_at then
      v_before:=public.workshop_booking_snapshot(v_booking.id);
      v_effective_duration:=(v_item->>'duration_minutes')::integer;
      update public.workshop_bookings set scheduled_start_at=v_start,scheduled_end_at=v_end,default_duration_minutes=v_effective_duration,updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1
        where id=v_booking.id and status='planned' and deleted_at is null;
      if not found then raise exception 'Concurrent planned queue change' using errcode='40001';end if;
      v_technician:=nullif(v_item->>'technician_id','')::uuid;
      perform public.workshop_upsert_primary_assignment(v_booking.id,v_technician,v_start,v_end,'admin_block_repacked');
      v_after:=public.workshop_booking_snapshot(v_booking.id);
      perform public.workshop_write_history(v_booking.id,'admin_block_repacked',v_before,v_after,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_repack',true));
      v_shifted:=array_append(v_shifted,v_booking.id);
    end if;
  end loop;
  return jsonb_build_object('shifted_booking_ids',to_jsonb(v_shifted),'shifted_count',cardinality(v_shifted));
end
$repack$;
revoke all on function public.workshop_admin_repack_planned(uuid,timestamptz,jsonb) from public,anon,authenticated,service_role;

-- Final postconditions.
do $post$
begin
  if exists(select 1 from public.vehicle_aliases a join public.vehicles v on v.id=a.vehicle_id where a.active and v.deleted_at is not null) then
    raise exception 'PDC_171_ACTIVE_ALIAS_DELETED_OWNER' using errcode='40001';
  end if;
  if exists(select 1 from public.pdc_sublet_booking_instances b join public.vehicles v on v.id=b.vehicle_id where b.status='active' and v.deleted_at is not null) then
    raise exception 'PDC_171_ACTIVE_SUBLET_DELETED_VEHICLE' using errcode='40001';
  end if;
end
$post$;
insert into supabase_migrations.schema_migrations(version,name,statements) values('171','release_safety_corrections',array[
  'serialize active aliases with live owners and guard identity reactivation',
  'restore historical deleted Navision identity retention around location latches',
  'add evidenced Sublet cancellation, deletion bridge, exact-one email serialization and payload-bound replay',
  'plan Admin queue cascades and apply latest-first without bay or technician exclusion collisions'
]);
notify pgrst,'reload schema';
commit;
