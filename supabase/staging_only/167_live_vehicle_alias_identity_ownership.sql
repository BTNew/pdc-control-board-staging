-- Staging-only append fix: active aliases may belong only to live vehicles.
begin;
do $guard$ begin
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_167_STAGING_ONLY';end if;
 if not exists(select 1 from supabase_migrations.schema_migrations where version='166' and name='operator_apply_and_terminal_quarantine') or exists(select 1 from supabase_migrations.schema_migrations where version>'166') then raise exception 'PDC_167_PREDECESSOR_MISMATCH';end if;
end $guard$;
lock table public.vehicles in share row exclusive mode;
lock table public.vehicle_aliases in share row exclusive mode;
update public.vehicle_aliases a set active=false from public.vehicles owner where owner.id=a.vehicle_id and owner.deleted_at is not null and a.active;
alter table public.vehicle_aliases drop constraint if exists vehicle_aliases_alias_type_alias_value_key;

create or replace function public.enforce_vehicle_alias_identity_uniqueness()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_type text := lower(btrim(new.alias_type));
  v_value text := public.normalize_vehicle_alias_value(new.alias_type, new.alias_value);
  v_source text := public.normalize_vehicle_source_system(new.source_system);
begin
  if new.active and not exists (select 1 from public.vehicles owner where owner.id=new.vehicle_id and owner.deleted_at is null) then
    raise exception 'active vehicle alias requires a live owner' using errcode='23514';
  end if;

  if v_type = 'vin'
     and nullif(btrim(new.alias_value), '') is not null
     and not public.is_valid_vehicle_vin(new.alias_value)
     and (tg_op = 'INSERT'
       or old.alias_type is distinct from new.alias_type
       or old.alias_value is distinct from new.alias_value) then
    raise exception 'invalid VIN alias'
      using errcode = '23514',
            detail = public.vehicle_master_response(false, 'invalid_value', jsonb_build_object('field', 'vin'))::text;
  end if;

  if new.active and (
    (v_type = 'vin' and public.is_valid_vehicle_vin(new.alias_value))
    or (v_type = 'stock_number' and public.is_real_vehicle_stock_number(new.alias_value))
  ) then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:' || v_type || ':' || v_value, 0
    ));
    if exists (
      select 1 from public.vehicle_aliases a
      join public.vehicles owner on owner.id=a.vehicle_id and owner.deleted_at is null
      where a.id <> new.id
        and a.active
        and a.alias_type_normalized = v_type
        and a.normalized_alias_value = v_value
    ) then
      raise exception 'duplicate global vehicle alias'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', v_type))::text;
    end if;
    if exists (
      select 1 from public.vehicles v
      where v.id <> new.vehicle_id
        and v.deleted_at is null
        and (
          (v_type = 'vin'
            and public.is_valid_vehicle_vin(v.vin)
            and v.vin_normalized = v_value)
          or (v_type = 'stock_number'
            and public.is_real_vehicle_stock_number(v.stock_number)
            and v.stock_number_normalized = v_value)
        )
    ) then
      raise exception 'vehicle alias conflicts with another canonical identity'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'conflicting_candidate', jsonb_build_object('field', v_type))::text;
    end if;
  end if;

  if new.active
     and v_type in ('source_record_id', 'toyota_order_number', 'job_card_number')
     and v_source is not null
     and v_value is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:source-alias:' || v_source || ':' || v_type || ':' || v_value, 0
    ));
    if exists (
      select 1 from public.vehicle_aliases a
      join public.vehicles owner on owner.id=a.vehicle_id and owner.deleted_at is null
      where a.id <> new.id
        and a.active
        and a.source_system_normalized = v_source
        and a.alias_type_normalized = v_type
        and a.normalized_alias_value = v_value
    ) then
      raise exception 'duplicate source-scoped vehicle alias'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', v_type, 'source_system', v_source))::text;
    end if;
  end if;

  return new;
end;
$$;
revoke all on function public.enforce_vehicle_alias_identity_uniqueness() from public,anon,authenticated,service_role;
drop trigger if exists vehicle_aliases_enforce_master_identity_uniqueness on public.vehicle_aliases;
create trigger vehicle_aliases_enforce_master_identity_uniqueness
before insert or update of vehicle_id,alias_type,alias_value,active,source_system on public.vehicle_aliases
for each row execute function public.enforce_vehicle_alias_identity_uniqueness();

create or replace function public.deactivate_vehicle_aliases_on_soft_delete()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $deactivate$
begin
 if old.deleted_at is null and new.deleted_at is not null then
  update public.vehicle_aliases set active=false where vehicle_id=new.id and active;
 end if;
 return new;
end
$deactivate$;
revoke all on function public.deactivate_vehicle_aliases_on_soft_delete() from public,anon,authenticated,service_role;
drop trigger if exists vehicles_deactivate_aliases_on_soft_delete on public.vehicles;
create trigger vehicles_deactivate_aliases_on_soft_delete after update of deleted_at on public.vehicles
for each row when(old.deleted_at is null and new.deleted_at is not null)
execute function public.deactivate_vehicle_aliases_on_soft_delete();

create or replace function public.pdc_pmb_workbook_classify_identity(p_stock text,p_registration text,p_job_card text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $identity$
declare v_backend_ids uuid[]:='{}';v_owner_ids uuid[]:='{}';v_backend public.navision_backend_records%rowtype;v_vehicle public.vehicles%rowtype;
begin
 if p_stock='13056899' then return jsonb_build_object('classification','terminal_excluded_stock','reason','explicit_terminal_stock_13056899_exclusion');end if;
 if p_stock is not null and not public.is_real_vehicle_stock_number(p_stock) then return jsonb_build_object('classification','terminal_pair_quarantine','reason','unsupported_stock_identity');end if;
 if p_stock is not null then
  select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_backend_ids from public.navision_backend_records r
   where r.source_system='microsoft_navision' and r.dealer_code in('14450','37047') and r.record_status='current' and r.is_current
     and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=p_stock;
  select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into v_owner_ids from(
   select v.id vehicle_id from public.vehicles v where v.deleted_at is null and public.normalize_vehicle_stock_number(v.stock_number)=p_stock
   union all select a.vehicle_id from public.vehicle_aliases a join public.vehicles alias_owner on alias_owner.id=a.vehicle_id and alias_owner.deleted_at is null where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=p_stock
  ) owners;
  if cardinality(v_backend_ids)>1 or cardinality(v_owner_ids)>1 then return jsonb_build_object('classification','terminal_identity_conflict','reason','stock_identity_not_unique');end if;
  if cardinality(v_backend_ids)=1 then
   select * into strict v_backend from public.navision_backend_records where id=v_backend_ids[1];
   if v_backend.canonical_vehicle_id is null or cardinality(v_owner_ids)<>1 or v_owner_ids[1]<>v_backend.canonical_vehicle_id
     or not exists(select 1 from public.navision_board_activations a where a.backend_record_id=v_backend.id and a.canonical_vehicle_id=v_backend.canonical_vehicle_id and a.active and a.completed_at is null) then
    return jsonb_build_object('classification','terminal_identity_conflict','reason','canonical_stock_activation_or_owner_conflict');
   end if;
   select * into v_vehicle from public.vehicles where id=v_backend.canonical_vehicle_id;
   if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or not v_vehicle.visible_on_board
     or v_vehicle.rft_collected_at is not null or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED'
     or (p_job_card is not null and nullif(upper(btrim(coalesce(v_vehicle.job_card_number,''))),'') is not null and upper(btrim(v_vehicle.job_card_number))<>p_job_card
     and not exists(
       select 1 from public.pdc_pmb_canonical_pair_receipts cr
       join public.pdc_pmb_workbook_pair_reviews prior on prior.pair_id=cr.pair_id
       where cr.backend_record_id=v_backend.id and cr.vehicle_id=v_vehicle.id
         and prior.stock_number=p_stock and prior.job_card_number=p_job_card
         and prior.registration is not distinct from p_registration
     )) then
    return jsonb_build_object('classification','terminal_identity_conflict','reason','protected_or_conflicting_stock_vehicle');
   end if;
   return jsonb_build_object('classification','exact_current_stock','reason','unique_current_stock_active_canonical_vehicle','backend_record_id',v_backend.id,'backend_record_version',v_backend.version,'vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version);
  end if;
  if cardinality(v_owner_ids)=1 then
   select * into v_vehicle from public.vehicles where id=v_owner_ids[1];
   if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or v_vehicle.rft_collected_at is not null
     or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED'
     or (p_job_card is not null and nullif(upper(btrim(coalesce(v_vehicle.job_card_number,''))),'') is not null and upper(btrim(v_vehicle.job_card_number))<>p_job_card) then
    return jsonb_build_object('classification','terminal_identity_conflict','reason','protected_or_conflicting_stock_override_target');
   end if;
   return jsonb_build_object('classification','no_current_stock_manager_override_required','reason','manager_exact_target_required','vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version);
  end if;
  return jsonb_build_object('classification','no_current_stock_manager_override_required','reason','manager_stock_only_create_required');
 end if;
 if p_registration is not null then
  select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into v_owner_ids from(
   select v.id vehicle_id from public.vehicles v where v.deleted_at is null and regexp_replace(upper(btrim(coalesce(v.registration,''))),'[^A-Z0-9]','','g')=p_registration
   union all select a.vehicle_id from public.vehicle_aliases a join public.vehicles alias_owner on alias_owner.id=a.vehicle_id and alias_owner.deleted_at is null where a.active and a.alias_type_normalized='registration' and a.normalized_alias_value=p_registration
  ) owners;
  if cardinality(v_owner_ids)<>1 then return jsonb_build_object('classification','terminal_identity_conflict','reason','registration_identity_not_exactly_one_active_vehicle');end if;
  select * into v_vehicle from public.vehicles where id=v_owner_ids[1];
  if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or v_vehicle.rft_collected_at is not null
    or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED'
    or (p_job_card is not null and nullif(upper(btrim(coalesce(v_vehicle.job_card_number,''))),'') is not null and upper(btrim(v_vehicle.job_card_number))<>p_job_card) then
   return jsonb_build_object('classification','terminal_identity_conflict','reason','protected_or_conflicting_registration_target');
  end if;
  return jsonb_build_object('classification','registration_identity_approval_required','reason','unique_active_registration_manager_approval_required','vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version);
 end if;
 return jsonb_build_object('classification','terminal_pair_quarantine','reason','stock_or_registration_required');
end
$identity$;
revoke all on function public.pdc_pmb_workbook_classify_identity(text,text,text) from public,anon,authenticated,service_role;
update public.navision_backend_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
insert into supabase_migrations.schema_migrations(version,name,statements) values('167','live_vehicle_alias_identity_ownership',array['Deactivate aliases owned by deleted vehicles while retaining alias rows','Require active alias owners and classifier alias candidates to be live vehicles','Allow inactive historical alias rows to coexist with a later active identity owner']);
notify pgrst,'reload schema';
commit;
