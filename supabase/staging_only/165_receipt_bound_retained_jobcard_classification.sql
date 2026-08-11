-- Staging-only append fix: a separately approved canonical activation receipt may authorize
-- a retained job card to bind to its exact active Stock vehicle even when the vehicle carries an older job-card label.
begin;
do $guard$ begin
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_165_STAGING_ONLY'; end if;
 if not exists(select 1 from supabase_migrations.schema_migrations where version='164' and name='canonical_activation_shared_vehicle_pairs') or exists(select 1 from supabase_migrations.schema_migrations where version>'164') then raise exception 'PDC_165_PREDECESSOR_MISMATCH'; end if;
end $guard$;
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
   union all select a.vehicle_id from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=p_stock
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
   union all select a.vehicle_id from public.vehicle_aliases a where a.active and a.alias_type_normalized='registration' and a.normalized_alias_value=p_registration
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

revoke all on function public.pdc_pmb_workbook_classify_identity(text,text,text) from public,anon,authenticated,service_role;
-- Invalidate previews made under the prior classifier without changing backend records.
update public.navision_backend_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
insert into supabase_migrations.schema_migrations(version,name,statements) values('165','receipt_bound_retained_jobcard_classification',array['Permit an exact prior canonical pair receipt to resolve only its retained Stock/job-card/registration tuple; invalidate earlier previews.']);
notify pgrst,'reload schema';
commit;
