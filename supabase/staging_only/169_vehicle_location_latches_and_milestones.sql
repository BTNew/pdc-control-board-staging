-- Staging-only migration 169: exact Navision location latches and immutable
-- business-date milestones. Parent integration may renumber this branch-local file.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists(
    select 1 from supabase_migrations.schema_migrations
    where version='168' and name='multi_provider_sublet_bookings_and_email_contract'
  ) or exists(select 1 from supabase_migrations.schema_migrations where version>'168')
     or to_regclass('public.vehicles') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_board_activations') is null then
    raise exception 'PDC_MIGRATION_169_DEPENDENCY_OR_SEQUENCE_MISMATCH';
  end if;
end;
$guard$;

alter table public.vehicles
  add column if not exists date_to_pmb date,
  add column if not exists date_to_rft date,
  add column if not exists delivered_to_dealer_date date;

comment on column public.vehicles.date_to_pmb is 'Immutable first Australia/Perth business date the vehicle was manually or exactly Navision-released to PMB.';
comment on column public.vehicles.date_to_rft is 'Immutable first Australia/Perth business date the vehicle reached RFT.';
comment on column public.vehicles.delivered_to_dealer_date is 'Immutable first Australia/Perth business date an already-PMB-latched vehicle received exact Delivered - At Dealer.';

create or replace function public.pdc_vehicle_first_milestones()
returns trigger language plpgsql set search_path=pg_catalog,public as $milestones$
declare v_business_date date:=(clock_timestamp() at time zone 'Australia/Perth')::date;
begin
  if tg_op='INSERT' then
    if upper(btrim(coalesce(new.current_location,''))) in ('PMB','PIT','QC','RFT','COMPLETED') then
      new.date_to_pmb:=coalesce(new.date_to_pmb,v_business_date);
    end if;
    if upper(btrim(coalesce(new.current_location,''))) in ('RFT','COMPLETED') then
      new.date_to_rft:=coalesce(new.date_to_rft,v_business_date);
    end if;
    if lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed' then
      new.delivered_to_dealer_date:=coalesce(new.delivered_to_dealer_date,v_business_date);
    end if;
    return new;
  end if;

  -- Existing facts win over every replay, correction and out-of-order snapshot.
  new.date_to_pmb:=coalesce(old.date_to_pmb,new.date_to_pmb,
    case when upper(btrim(coalesce(new.current_location,''))) in ('PMB','PIT','QC','RFT','COMPLETED') then v_business_date end);
  new.date_to_rft:=coalesce(old.date_to_rft,new.date_to_rft,
    case when upper(btrim(coalesce(new.current_location,''))) in ('RFT','COMPLETED') then v_business_date end);
  new.delivered_to_dealer_date:=coalesce(old.delivered_to_dealer_date,new.delivered_to_dealer_date,
    case when lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed' then v_business_date end);
  return new;
end;
$milestones$;

drop trigger if exists vehicles_first_milestones on public.vehicles;
create trigger vehicles_first_milestones before insert or update on public.vehicles
for each row execute function public.pdc_vehicle_first_milestones();

-- Backfill only provable historical milestones. Never manufacture dealer completion
-- for an active row and never replace an already-recorded first date.
update public.vehicles set
  date_to_pmb=coalesce(date_to_pmb,(coalesce(rft_transferred_at,qc_completed_at,updated_at) at time zone 'Australia/Perth')::date),
  date_to_rft=case when upper(btrim(coalesce(current_location,''))) in ('RFT','COMPLETED')
    then coalesce(date_to_rft,(coalesce(rft_transferred_at,rft_collected_at,updated_at) at time zone 'Australia/Perth')::date) else date_to_rft end,
  delivered_to_dealer_date=case when lower(btrim(coalesce(lifecycle_state::text,'')))='completed'
    and coalesce(source_payload->>'completed_reason','')='Delivered - At Dealer'
    then coalesce(delivered_to_dealer_date,(coalesce(rft_collected_at,updated_at) at time zone 'Australia/Perth')::date)
    else delivered_to_dealer_date end
where date_to_pmb is null and upper(btrim(coalesce(current_location,''))) in ('PMB','PIT','QC','RFT','COMPLETED');

create or replace function public.navision_exact_lifecycle_status(p_data jsonb)
returns text language sql immutable parallel safe set search_path=pg_catalog,public as $status$
  select lower(public.workshop_normalize_identifier(coalesce(
    nullif(btrim(p_data->>'navisionSubLocationDescription'),''),
    nullif(btrim(p_data->>'toyotaStatus'),''),
    nullif(btrim(p_data->>'vehicleStatus'),''),
    nullif(btrim(p_data->>'navisionLocationStatus'),''),''
  )));
$status$;

create or replace function public.navision_operational_location(p_data jsonb)
returns text language plpgsql stable set search_path=pg_catalog,public as $location$
declare
  v_status text:=public.navision_exact_lifecycle_status(p_data);
  v_eta date:=public.navision_kewdale_eta(p_data);
  v_business_date date:=(statement_timestamp() at time zone 'Australia/Perth')::date;
begin
  if v_status='deliveredatdealer' then return 'Completed'; end if;
  if v_status='deliveredatbodybuilder' then return 'PMB'; end if;
  if v_status=any(array['waitingpd2','vehicledelayed','awaitingtrayfit','vehiclewaitingwholesale','vehiclewaitingforwholesale'])
     and v_eta is not null and v_eta < v_business_date then return 'YH'; end if;
  if v_eta is not null and v_status like '%fromtwa%' and (v_status like '%despatch%' or v_status like '%dispatch%') then return 'IT'; end if;
  return 'Other';
end;
$location$;
revoke all on function public.navision_exact_lifecycle_status(jsonb) from public,anon,authenticated;
revoke all on function public.navision_operational_location(jsonb) from public,anon,authenticated;
grant execute on function public.navision_operational_location(jsonb) to authenticated;

create or replace function public.reconcile_navision_operational_record(
  p_backend_record_id uuid,p_actor_id uuid default null,p_actor_email text default null
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $reconcile$
declare
  v_record public.navision_backend_records%rowtype;
  v_activation public.navision_board_activations%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_before jsonb; v_after jsonb;
  v_stock text; v_vin text; v_status text; v_location text; v_target text;
  v_vehicle_ids uuid[]; v_vehicle_id uuid; v_customer text; v_description text;
  v_inserted boolean:=false; v_changed boolean:=false; v_completed boolean:=false;
  v_now timestamptz:=clock_timestamp();
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
  if p_backend_record_id is null then return public.navision_backend_response(false,'invalid_input'); end if;
  perform pg_advisory_xact_lock(hashtextextended('navision-operational-record:'||p_backend_record_id::text,0));
  select * into v_record from public.navision_backend_records where id=p_backend_record_id for update;
  if not found or not v_record.is_current or v_record.record_status<>'current' then return public.navision_backend_response(true,'record_not_current'); end if;

  v_stock:=nullif(public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch'),'');
  v_vin:=case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin') then nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),'') end;
  if v_stock is null then return public.navision_backend_response(false,'stock_required'); end if;
  v_status:=public.navision_exact_lifecycle_status(v_record.normalized_data);
  v_location:=public.navision_operational_location(v_record.normalized_data);

  select coalesce(array_agg(v.id order by v.id),'{}'::uuid[]) into v_vehicle_ids from public.vehicles v
  where v.deleted_at is null and (v.stock_number_normalized=v_stock or (v_vin is not null and v.vin_normalized=v_vin));
  if cardinality(v_vehicle_ids)>1 then return public.navision_backend_response(false,'canonical_identity_conflict',jsonb_build_object('backend_record_id',p_backend_record_id,'stock_number',v_stock,'candidate_count',cardinality(v_vehicle_ids))); end if;
  if cardinality(v_vehicle_ids)=1 then v_vehicle_id:=v_vehicle_ids[1]; end if;

  select * into v_activation from public.navision_board_activations where backend_record_id=p_backend_record_id for update;
  if v_activation.backend_record_id is null and v_vehicle_id is not null and exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v_vehicle_id) then
    insert into public.navision_board_activations(backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email,canonical_vehicle_id,active)
    values(p_backend_record_id,'approved_email_build',v_record.normalized_data->>'batch',p_actor_id,p_actor_email,v_vehicle_id,true) returning * into v_activation;
  end if;
  if v_activation.backend_record_id is null then return public.navision_backend_response(true,'not_activated'); end if;

  v_customer:=coalesce(nullif(btrim(v_record.normalized_data->>'client'),''),nullif(btrim(v_record.normalized_data->>'customerSurname'),''),nullif(btrim(v_record.normalized_data->>'dealerCustomerName'),''),nullif(btrim(v_record.normalized_data->>'toyotaCustomer'),''));
  v_description:=coalesce(nullif(btrim(v_record.normalized_data->>'modelDescription'),''),nullif(btrim(v_record.normalized_data->>'toyotaVehicle'),''),nullif(btrim(v_record.normalized_data->>'vehicle'),''));

  if v_vehicle_id is null then
    v_vehicle_id:=extensions.uuid_generate_v5('b58b5f75-d004-5a76-b9aa-48c801b4ad7d'::uuid,'NAVISION:'||v_record.dealer_code||':'||v_stock||':'||p_backend_record_id::text);
    -- Dealer status cannot complete a vehicle that has never reached PMB.
    v_target:=case when v_location='Completed' then 'Other' else v_location end;
    insert into public.vehicles(id,permanent_vehicle_id,stock_number,vin,toyota_order_number,job_card_number,customer_name,vehicle_description,model,registration,lifecycle_state,visible_on_board,current_location,eta_to_kewdale,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by)
    values(v_vehicle_id,'PDC-NAV-'||upper(replace(substr(v_vehicle_id::text,1,24),'-','')),v_record.normalized_data->>'batch',v_vin,nullif(btrim(v_record.normalized_data->>'order'),''),nullif(btrim(v_record.normalized_data->>'jobCardNumber'),''),v_customer,v_description,v_description,nullif(upper(btrim(v_record.normalized_data->>'registration')),''),'active',true,v_target,public.navision_kewdale_eta(v_record.normalized_data),'microsoft_navision',v_record.dealer_code,p_backend_record_id::text,jsonb_build_object('authority','navision_location_latch_169','navision_record_id',p_backend_record_id,'latest_navision_status',v_record.normalized_data->>'toyotaStatus','reconciled_at',v_now),p_actor_id,p_actor_id)
    returning * into v_vehicle;
    v_inserted:=true;
  else
    select * into v_vehicle from public.vehicles where id=v_vehicle_id for update;
  end if;
  v_before:=to_jsonb(v_vehicle);

  -- Manual completion and manual PMB/QC/RFT progress always outrank snapshots.
  if lower(btrim(coalesce(v_vehicle.lifecycle_state::text,'')))='completed' then
    update public.navision_board_activations set canonical_vehicle_id=v_vehicle_id,active=false,updated_at=v_now where backend_record_id=p_backend_record_id;
  elsif v_location='Completed' and (v_vehicle.date_to_pmb is not null or upper(btrim(coalesce(v_vehicle.current_location,''))) in ('PMB','PIT','QC','RFT','COMPLETED')) then
    update public.vehicles set lifecycle_state='completed',visible_on_board=false,current_location='Completed',rft_collected_at=coalesce(rft_collected_at,v_now),delivered_to_dealer_date=coalesce(delivered_to_dealer_date,(v_now at time zone 'Australia/Perth')::date),source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','navision_location_latch_169','navision_record_id',p_backend_record_id,'latest_navision_status',v_record.normalized_data->>'toyotaStatus','completed_reason','Delivered - At Dealer','reconciled_at',v_now),version=version+1,updated_by=p_actor_id where id=v_vehicle_id returning * into v_vehicle;
    update public.navision_board_activations set canonical_vehicle_id=v_vehicle_id,active=false,completed_at=coalesce(completed_at,v_now),completion_reason='Delivered - At Dealer',completed_by=p_actor_id,completed_by_email=p_actor_email,updated_at=v_now where backend_record_id=p_backend_record_id;
    v_changed:=true; v_completed:=true;
  elsif upper(btrim(coalesce(v_vehicle.current_location,''))) in ('PMB','PIT','QC','RFT') or v_vehicle.date_to_pmb is not null then
    update public.navision_board_activations set canonical_vehicle_id=v_vehicle_id,active=true,updated_at=v_now where backend_record_id=p_backend_record_id;
  else
    -- YH is a latch too: ordinary/TWA snapshots cannot move it back. Before YH,
    -- only exact TWA+ETA may supply IT; scheduling is deliberately absent here.
    v_target:=case
      when upper(btrim(coalesce(v_vehicle.current_location,'')))='YH' and v_location not in ('PMB','Completed') then 'YH'
      when v_location='Completed' then coalesce(nullif(v_vehicle.current_location,''),'Other')
      when v_location='Other' then coalesce(nullif(v_vehicle.current_location,''),'Other')
      else v_location end;
    update public.vehicles set stock_number=coalesce(v_record.normalized_data->>'batch',stock_number),vin=coalesce(v_vin,vin),toyota_order_number=coalesce(nullif(btrim(v_record.normalized_data->>'order'),''),toyota_order_number),job_card_number=coalesce(nullif(btrim(v_record.normalized_data->>'jobCardNumber'),''),job_card_number),customer_name=coalesce(v_customer,customer_name),vehicle_description=coalesce(v_description,vehicle_description),model=coalesce(v_description,model),eta_to_kewdale=coalesce(public.navision_kewdale_eta(v_record.normalized_data),eta_to_kewdale),current_location=v_target,visible_on_board=true,source_system='microsoft_navision',source_batch_id=v_record.dealer_code,source_record_id=p_backend_record_id::text,source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','navision_location_latch_169','navision_record_id',p_backend_record_id,'latest_navision_status',v_record.normalized_data->>'toyotaStatus','reconciled_at',v_now),version=version+1,updated_by=p_actor_id where id=v_vehicle_id returning * into v_vehicle;
    update public.navision_board_activations set canonical_vehicle_id=v_vehicle_id,active=true,updated_at=v_now where backend_record_id=p_backend_record_id;
    v_changed:=true;
  end if;

  update public.navision_backend_records set canonical_vehicle_id=v_vehicle_id where id=p_backend_record_id and canonical_vehicle_id is distinct from v_vehicle_id;
  v_after:=to_jsonb(v_vehicle);
  if v_inserted then
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) values('insert','vehicles',v_vehicle_id,v_vehicle_id,p_actor_id,p_actor_email,null,v_after,jsonb_build_object('source','navision_location_latch_169','backend_record_id',p_backend_record_id,'status',v_status,'location',v_location));
  elsif v_changed and v_before is distinct from v_after then
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) values('update','vehicles',v_vehicle_id,v_vehicle_id,p_actor_id,p_actor_email,v_before,v_after,jsonb_build_object('source','navision_location_latch_169','backend_record_id',p_backend_record_id,'status',v_status,'location',v_location,'completed',v_completed));
  end if;
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
  update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;
  return public.navision_backend_response(true,case when v_completed then 'completed' else 'reconciled' end,jsonb_build_object('backend_record_id',p_backend_record_id,'vehicle_id',v_vehicle_id,'location',v_vehicle.current_location,'completed',v_completed,'date_to_pmb',v_vehicle.date_to_pmb,'date_to_rft',v_vehicle.date_to_rft,'delivered_to_dealer_date',v_vehicle.delivered_to_dealer_date));
end;
$reconcile$;
revoke all on function public.reconcile_navision_operational_record(uuid,uuid,text) from public,anon,authenticated;

-- Manual release records Date to PMB in the same audited transaction.
create or replace function public.pmb_transfer_vehicle(p_vehicle_id uuid,p_expected_version integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $transfer$
declare v_before public.vehicles%rowtype; v_after public.vehicles%rowtype; v_location text; v_now timestamptz:=clock_timestamp();
begin
  perform public.require_pdc_role('operator');
  if p_vehicle_id is null then return jsonb_build_object('ok',false,'error','invalid_vehicle'); end if;
  select * into v_before from public.vehicles where id=p_vehicle_id for update;
  if not found then raise exception 'Vehicle not found' using errcode='P0002'; end if;
  if p_expected_version is null then return jsonb_build_object('ok',false,'error','missing_expected_version'); end if;
  if v_before.version<>p_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
  if v_before.lifecycle_state<>'active' or v_before.deleted_at is not null then return jsonb_build_object('ok',false,'error','not_in_active_lifecycle'); end if;
  v_location:=upper(btrim(coalesce(v_before.current_location,'')));
  if v_location='PMB' then return jsonb_build_object('ok',true,'code','already_at_pmb','vehicle',to_jsonb(v_before)); end if;
  if v_location not in ('YH','IT') then return jsonb_build_object('ok',false,'error','pmb_transfer_requires_yh_or_it'); end if;
  update public.vehicles set current_location='PMB',date_to_pmb=coalesce(date_to_pmb,(v_now at time zone 'Australia/Perth')::date),visible_on_board=true,pmb_stage=null,pmb_bay_stage=null,pmb_bay_number=null,source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('manual_location_authority','PMB','manual_location_updated_at',v_now,'manual_location_updated_by',public.current_actor_email()),version=version+1,updated_by=auth.uid() where id=p_vehicle_id returning * into v_after;
  insert into public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by) values(p_vehicle_id,v_before.current_location,'PMB',v_before.pmb_stage,null,v_before.pmb_bay_stage,null,v_before.pmb_bay_number,null,'Explicit Vehicle Locations release to PMB',auth.uid());
  perform public.audit_pdc_event('move','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('action','pmb_transfer_vehicle','from',v_before.current_location,'to','Released to PMB','date_to_pmb',v_after.date_to_pmb));
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
  update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;
  return jsonb_build_object('ok',true,'code','transferred_to_pmb','vehicle',to_jsonb(v_after));
end;
$transfer$;
revoke all on function public.pmb_transfer_vehicle(uuid,integer) from public,anon;
grant execute on function public.pmb_transfer_vehicle(uuid,integer) to authenticated,service_role;

-- Add durable dates to the all-lifecycle Vehicle Locations/Completed DTO. The
-- existing activation projection remains the authority for shared visibility.
create or replace function public.get_navision_visible_snapshot(
  p_source_system text,p_dealer_code text,p_after_record_id uuid default null,
  p_page_size integer default 200,p_expected_revision bigint default null
) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,extensions as $visible$
declare
  v_role text:=public.current_pdc_user_role()::text;
  v_source_system text:=lower(btrim(coalesce(p_source_system,'')));
  v_dealer_code text:=btrim(coalesce(p_dealer_code,''));
  v_page_size integer; v_revision bigint; v_result jsonb;
begin
  if not coalesce(v_role=any(array['viewer','operator','importer','administrator']),false) then return public.navision_backend_response(false,'unauthorized'); end if;
  if v_source_system<>'microsoft_navision' or v_dealer_code not in ('14450','37047') then return public.navision_backend_response(false,'invalid_input',jsonb_build_object('field','scope')); end if;
  if p_page_size is null or p_page_size<1 then return public.navision_backend_response(false,'invalid_input',jsonb_build_object('field','page_size')); end if;
  v_page_size:=least(p_page_size,500);
  select revision into v_revision from public.navision_backend_revision where singleton;
  if p_expected_revision is not null and p_expected_revision<>v_revision then return public.navision_backend_response(false,'stale_revision',jsonb_build_object('current_revision',v_revision)); end if;
  with page as materialized (
    select r.*,a.activation_source,a.activated_stock_number,a.activated_at,a.active as activation_active,
      a.canonical_vehicle_id as activation_vehicle_id,a.completed_at,a.completion_reason,a.completed_by_email,
      v.current_location,v.lifecycle_state::text as lifecycle_state,v.visible_on_board,v.rft_collected_at,
      v.date_to_pmb,v.date_to_rft,v.delivered_to_dealer_date
    from public.navision_backend_records r
    left join public.navision_board_activations a on a.backend_record_id=r.id
    left join public.vehicles v on v.id=coalesce(a.canonical_vehicle_id,r.canonical_vehicle_id)
    where r.source_system=v_source_system and r.dealer_code=v_dealer_code
      and (p_after_record_id is null or r.id>p_after_record_id)
    order by r.id limit v_page_size+1
  ), selected as materialized(select * from page order by id limit v_page_size)
  select public.navision_backend_response(true,'visible_snapshot',jsonb_build_object(
    'revision',v_revision,'source_system',v_source_system,'dealer_code',v_dealer_code,'page_size',v_page_size,
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'id',id,'dealer_code',dealer_code,'record_status',record_status,'is_current',is_current,'updated_at',updated_at,
      'stock_number',nullif(normalized_data->>'batch',''),
      'customer_name',coalesce(nullif(normalized_data->>'client',''),nullif(normalized_data->>'customerSurname',''),nullif(normalized_data->>'dealerCustomerName',''),nullif(normalized_data->>'toyotaCustomer','')),
      'salesperson',coalesce(public.navision_original_column_value(normalized_data,'Salesperson'),nullif(normalized_data->>'salesperson',''),nullif(normalized_data->>'consultant',''),nullif(normalized_data->>'owner','')),
      'model',coalesce(nullif(normalized_data->>'modelDescription',''),nullif(normalized_data->>'toyotaVehicle',''),nullif(normalized_data->>'vehicle','')),
      'colour',coalesce(nullif(normalized_data->>'colourDescription',''),nullif(normalized_data->>'colour','')),
      'vehicle_status',coalesce(nullif(normalized_data->>'toyotaStatus',''),nullif(normalized_data->>'navisionLocationStatus',''),nullif(normalized_data->>'internalStatus','')),
      'eta_to_kewdale',coalesce(nullif(normalized_data->>'navisionKewdaleEta',''),nullif(normalized_data->>'etaAtDealer','')),
      'board_activated',activation_source is not null and activation_active and activated_stock_number=nullif(btrim(coalesce(normalized_data->>'batch','')),''),
      'activation_source',activation_source,'activated_at',activated_at,
      'canonical_vehicle_id',coalesce(activation_vehicle_id,canonical_vehicle_id),
      'current_location',current_location,'lifecycle_state',lifecycle_state,'visible_on_board',visible_on_board,
      'date_to_pmb',date_to_pmb,'date_to_rft',date_to_rft,'delivered_to_dealer_date',delivered_to_dealer_date,
      'completed_at',coalesce(completed_at,rft_collected_at),'completion_reason',completion_reason,'completed_by_email',completed_by_email
    ) order by id) from selected),'[]'::jsonb),
    'has_more',(select count(*)>v_page_size from page),
    'next_record_id',case when (select count(*)>v_page_size from page) then (select id from selected order by id desc limit 1) end,
    'authority','shared_navision_backend_canonical_operational','data_access','approved_staff_display'
  )) into v_result;
  return v_result;
end;
$visible$;
revoke all on function public.get_navision_visible_snapshot(text,text,uuid,integer,bigint) from public,anon,authenticated;
grant execute on function public.get_navision_visible_snapshot(text,text,uuid,integer,bigint) to authenticated;

-- The authenticated email projection feeds the live Vehicle Locations browser.
-- JSON merge avoids duplicating the large established operation/parts/sublet DTO.
create or replace function public.pdc_vehicle_milestone_json(p_vehicle_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,public as $json$
  select coalesce((select jsonb_build_object('date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'delivered_to_dealer_date',v.delivered_to_dealer_date) from public.vehicles v where v.id=p_vehicle_id),'{}'::jsonb);
$json$;
revoke all on function public.pdc_vehicle_milestone_json(uuid) from public,anon;
grant execute on function public.pdc_vehicle_milestone_json(uuid) to authenticated,service_role;

alter function public.get_pdc_email_vehicle_location_snapshot() rename to get_pdc_email_vehicle_location_snapshot_pre_169;
create function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $email_snapshot$
declare v_response jsonb; v_rows jsonb;
begin
  v_response:=public.get_pdc_email_vehicle_location_snapshot_pre_169();
  if not coalesce((v_response->>'ok')::boolean,false) then return v_response; end if;
  select coalesce(jsonb_agg(row_value||public.pdc_vehicle_milestone_json((row_value->>'id')::uuid)),'[]'::jsonb)
  into v_rows from jsonb_array_elements(coalesce(v_response#>'{data,vehicles}','[]'::jsonb)) row_value;
  return jsonb_set(v_response,'{data,vehicles}',v_rows,true);
end;
$email_snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot_pre_169() from public,anon,authenticated;
revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public,anon,authenticated;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('169','vehicle_location_latches_and_milestones',array['digest-pinned committed installer; staging-only guarded SQL']);
commit;
