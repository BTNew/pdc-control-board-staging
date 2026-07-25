-- Staging-only migration 067: continuously enrich email-created vehicle cards from Navision.
--
-- A PD-document email may create the canonical vehicle immediately. Later email
-- imports continue to enrich the same exact Stock/VIN identity through migration
-- 066. This migration adds a bounded scheduler RPC so later Navision records also
-- refresh those cards without waiting for another email. It never creates a
-- booking or changes required/completed work.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('public.pdc_authenticated_email_import_receipts') is null
     or to_regclass('public.pdc_monitor_stage_activation_writers') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_board_activations') is null
     or to_regclass('public.vehicles') is null then
    raise exception 'PDC_MIGRATION_067_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create or replace function public.reconcile_pdc_email_vehicles_from_navision()
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $reconcile$
declare
  v_actor_id uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text;
  v_vehicle public.vehicles%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_stock text;
  v_vin text;
  v_stock_ids uuid[];
  v_vin_ids uuid[];
  v_candidate_id uuid;
  v_location text;
  v_customer text;
  v_description text;
  v_registration text;
  v_job text;
  v_order text;
  v_eta_text text;
  v_eta date;
  v_changed integer:=0;
  v_unchanged integer:=0;
  v_unmatched integer:=0;
  v_conflicted integer:=0;
  v_activation_inserted integer:=0;
  v_inserted integer;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_actor_id is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select r.role::text into v_role
  from public.pdc_user_roles r
  where r.email=v_actor_email
    and (r.auth_user_id is null or r.auth_user_id=v_actor_id)
    and r.role='viewer' and r.active and r.account_status='approved'
  for share;
  if v_role is distinct from 'viewer' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=v_actor_id and w.active and w.revoked_at is null
  for share;
  if not found then
    return public.navision_backend_response(false,'unauthorized');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-email-navision-reconcile',0));
  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));

  for v_vehicle in
    select v.*
    from public.vehicles v
    where v.deleted_at is null and v.lifecycle_state='active'
      and exists(
        select 1 from public.pdc_authenticated_email_import_receipts r
        where r.vehicle_id=v.id
      )
    order by v.id
    for update
  loop
    v_stock:=nullif(public.normalize_vehicle_stock_number(v_vehicle.stock_number),'');
    v_vin:=nullif(public.normalize_vehicle_vin(v_vehicle.vin),'');
    v_stock_ids:='{}'::uuid[];
    v_vin_ids:='{}'::uuid[];
    v_candidate_id:=null;

    if v_stock is not null then
      select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_stock_ids
      from public.navision_backend_records r
      where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
        and r.is_current and r.record_status='current'
        and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
        and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    end if;
    if v_vin is not null then
      select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_vin_ids
      from public.navision_backend_records r
      where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
        and r.is_current and r.record_status='current'
        and public.is_valid_vehicle_vin(r.normalized_data->>'vin')
        and public.normalize_vehicle_vin(r.normalized_data->>'vin')=v_vin;
    end if;

    if cardinality(v_stock_ids)>1 or cardinality(v_vin_ids)>1
       or (cardinality(v_stock_ids)=1 and cardinality(v_vin_ids)=1 and v_stock_ids[1]<>v_vin_ids[1]) then
      v_conflicted:=v_conflicted+1;
      continue;
    end if;
    if cardinality(v_stock_ids)=1 then
      v_candidate_id:=v_stock_ids[1];
    elsif cardinality(v_vin_ids)=1 then
      v_candidate_id:=v_vin_ids[1];
    else
      v_unmatched:=v_unmatched+1;
      continue;
    end if;

    if exists(
      select 1 from public.vehicles other
      where other.id<>v_vehicle.id and other.deleted_at is null
        and other.source_system_normalized='microsoft_navision'
        and other.source_record_id_normalized=public.normalize_vehicle_source_identifier(v_candidate_id::text)
    ) then
      v_conflicted:=v_conflicted+1;
      continue;
    end if;

    select * into v_record from public.navision_backend_records where id=v_candidate_id for update;
    v_stock:=coalesce(nullif(public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch'),''),v_stock);
    v_vin:=coalesce(nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),''),v_vin);
    v_customer:=coalesce(nullif(btrim(v_record.normalized_data->>'client'),''),nullif(btrim(v_record.normalized_data->>'customerSurname'),''),nullif(btrim(v_record.normalized_data->>'dealerCustomerName'),''),nullif(btrim(v_record.normalized_data->>'toyotaCustomer'),''));
    v_description:=coalesce(nullif(btrim(v_record.normalized_data->>'modelDescription'),''),nullif(btrim(v_record.normalized_data->>'toyotaVehicle'),''),nullif(btrim(v_record.normalized_data->>'vehicle'),''));
    v_registration:=nullif(upper(btrim(v_record.normalized_data->>'registration')),'');
    v_job:=nullif(btrim(v_record.normalized_data->>'jobCardNumber'),'');
    v_order:=nullif(btrim(v_record.normalized_data->>'order'),'');
    v_eta_text:=coalesce(nullif(btrim(v_record.normalized_data->>'navisionKewdaleEta'),''),nullif(btrim(v_record.normalized_data->>'etaAtDealer'),''));
    if v_eta_text ~ '^\d{4}-\d{2}-\d{2}$' and to_char(to_date(v_eta_text,'YYYY-MM-DD'),'YYYY-MM-DD')=v_eta_text then
      v_eta:=to_date(v_eta_text,'YYYY-MM-DD');
    else
      v_eta:=null;
    end if;
    v_location:=case
      when public.workshop_normalize_identifier(v_record.normalized_data->>'navisionSubLocationDescription') like '%DESPATCHEDFROMBODYBUILDER%' then 'RFT'
      when public.workshop_normalize_identifier(v_record.normalized_data->>'navisionLocationStatus') in ('PMB','PERTHMOTORBODIES','KEWDALE')
        or public.workshop_normalize_identifier(v_record.normalized_data->>'navisionSubLocationDescription') like '%BODYBUILDER%' then 'PMB'
      when public.workshop_normalize_identifier(v_record.normalized_data->>'navisionLocationStatus') in ('YH','YARDHOLD')
        or public.workshop_normalize_identifier(v_record.normalized_data->>'navisionSubLocationDescription') like '%YARDHOLD%' then 'YH'
      when public.workshop_normalize_identifier(v_record.normalized_data->>'navisionLocationStatus') in ('IT','INTRANSIT')
        or public.workshop_normalize_identifier(v_record.normalized_data->>'navisionSubLocationDescription') ~ '(TRANSIT|SHIPMENT|WHARF)' then 'IT'
      when public.workshop_normalize_identifier(v_record.normalized_data->>'navisionLocationStatus') in ('RFT','READYFORTRANSFER')
        or public.workshop_normalize_identifier(v_record.normalized_data->>'navisionSubLocationDescription') like '%ATDEALER%' then 'RFT'
      else 'Other' end;

    select to_jsonb(v_vehicle) into v_before;
    update public.vehicles set
      stock_number=coalesce(v_record.normalized_data->>'batch',stock_number),
      vin=coalesce(v_record.normalized_data->>'vin',vin),
      toyota_order_number=coalesce(v_order,toyota_order_number),
      job_card_number=coalesce(v_job,job_card_number),
      customer_name=coalesce(v_customer,customer_name),
      vehicle_description=coalesce(v_description,vehicle_description),
      model=coalesce(v_description,model),
      registration=coalesce(v_registration,registration),
      eta_to_kewdale=coalesce(v_eta,eta_to_kewdale),
      current_location=v_location,
      visible_on_board=true,
      source_system='microsoft_navision',
      source_batch_id=v_record.dealer_code,
      source_record_id=v_record.id::text,
      source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
        'navision_reconciled_at',clock_timestamp(),'navision_record_id',v_record.id),
      version=version+1,updated_by=v_actor_id
    where id=v_vehicle.id
      and (stock_number is distinct from coalesce(v_record.normalized_data->>'batch',stock_number)
        or vin is distinct from coalesce(v_record.normalized_data->>'vin',vin)
        or toyota_order_number is distinct from coalesce(v_order,toyota_order_number)
        or job_card_number is distinct from coalesce(v_job,job_card_number)
        or customer_name is distinct from coalesce(v_customer,customer_name)
        or vehicle_description is distinct from coalesce(v_description,vehicle_description)
        or registration is distinct from coalesce(v_registration,registration)
        or eta_to_kewdale is distinct from coalesce(v_eta,eta_to_kewdale)
        or current_location is distinct from v_location
        or not visible_on_board
        or source_system_normalized is distinct from 'microsoft_navision'
        or source_record_id_normalized is distinct from public.normalize_vehicle_source_identifier(v_record.id::text))
    returning to_jsonb(public.vehicles.*) into v_after;

    if found then
      v_changed:=v_changed+1;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values('update','vehicles',v_vehicle.id,v_vehicle.id,v_actor_id,v_actor_email,v_before,v_after,
        jsonb_build_object('source','pdc_email_navision_reconcile_067','backend_record_id',v_record.id,'no_booking',true));
    else
      v_unchanged:=v_unchanged+1;
    end if;

    insert into public.navision_board_activations(
      backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email
    ) values(v_record.id,'approved_email_build',v_record.normalized_data->>'batch',v_actor_id,v_actor_email)
    on conflict(backend_record_id) do nothing;
    get diagnostics v_inserted=row_count;
    v_activation_inserted:=v_activation_inserted+v_inserted;
  end loop;

  if v_changed>0 then
    update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp()
    where singleton;
  end if;
  if v_activation_inserted>0 then
    update public.navision_backend_revision set revision=revision+1,updated_at=clock_timestamp()
    where singleton;
  end if;

  return public.navision_backend_response(true,'navision_reconciled',jsonb_build_object(
    'changed',v_changed,'unchanged',v_unchanged,'unmatched',v_unmatched,
    'conflicted',v_conflicted,'activations_created',v_activation_inserted,
    'booking_created',false,'work_changed',false));
end;
$reconcile$;

revoke all on function public.reconcile_pdc_email_vehicles_from_navision() from public,anon,authenticated;
grant execute on function public.reconcile_pdc_email_vehicles_from_navision() to authenticated;

comment on function public.reconcile_pdc_email_vehicles_from_navision() is
  'Staging-only enrolled-Viewer reconciliation: refreshes email-imported cards from exact current Navision data; creates no bookings and changes no work state.';

commit;
