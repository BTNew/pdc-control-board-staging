-- Staging-only migration 083: make activated Navision rows canonical operational vehicles.
-- Body Builder lands in PMB unless workflow state has already progressed; At Dealer
-- closes vehicles only when no required work is open. All transitions are audited.
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
  if to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_board_activations') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.audit_events') is null then
    raise exception 'PDC_MIGRATION_083_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

alter table public.navision_board_activations
  add column if not exists canonical_vehicle_id uuid references public.vehicles(id) on delete set null,
  add column if not exists active boolean not null default true,
  add column if not exists completed_at timestamptz,
  add column if not exists completion_reason text,
  add column if not exists completed_by uuid references auth.users(id) on delete set null,
  add column if not exists completed_by_email text;

create index if not exists navision_board_activations_canonical_vehicle_idx
  on public.navision_board_activations(canonical_vehicle_id)
  where canonical_vehicle_id is not null;

create or replace function public.navision_operational_location(p_data jsonb)
returns text
language sql
immutable
parallel safe
set search_path=pg_catalog,public
as $location$
  with source as (
    select public.workshop_normalize_identifier(concat_ws(' ',
      coalesce(p_data->>'toyotaStatus',''),
      coalesce(p_data->>'navisionLocationStatus',''),
      coalesce(p_data->>'navisionSubLocationDescription',''),
      coalesce(p_data->>'internalStatus','')
    )) as value
  )
  select case
    when value like '%ATDEALER%' or value like '%DELIVEREDTODEALER%' then 'Completed'
    when value like '%BODYBUILDER%' or value like '%PERTHMOTORBODIES%' or value like '%PMB%' then 'PMB'
    when value like '%YARDHOLD%' or value='YH' then 'YH'
    when value like '%INTRANSIT%' or value like '%SHIPMENT%' or value like '%WHARF%' then 'IT'
    else 'Other'
  end from source;
$location$;

revoke all on function public.navision_operational_location(jsonb) from public,anon,authenticated;
grant execute on function public.navision_operational_location(jsonb) to authenticated;

create or replace function public.reconcile_navision_operational_record(
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
  v_activation public.navision_board_activations%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_stock text;
  v_vin text;
  v_location text;
  v_vehicle_ids uuid[];
  v_vehicle_id uuid;
  v_customer text;
  v_description text;
  v_open_work integer:=0;
  v_inserted boolean:=false;
  v_changed boolean:=false;
  v_completed boolean:=false;
  v_now timestamptz:=clock_timestamp();
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if p_backend_record_id is null then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('navision-operational-record:'||p_backend_record_id::text,0));
  select * into v_record from public.navision_backend_records
  where id=p_backend_record_id for update;
  if not found or not v_record.is_current or v_record.record_status<>'current' then
    return public.navision_backend_response(true,'record_not_current');
  end if;

  v_stock:=nullif(public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch'),'');
  v_vin:=case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin')
    then nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),'') else null end;
  if v_stock is null then
    return public.navision_backend_response(false,'stock_required');
  end if;
  v_location:=public.navision_operational_location(v_record.normalized_data);

  select coalesce(array_agg(v.id order by v.id),'{}'::uuid[]) into v_vehicle_ids
  from public.vehicles v
  where v.deleted_at is null and (
    v.stock_number_normalized=v_stock
    or (v_vin is not null and v.vin_normalized=v_vin)
  );
  if cardinality(v_vehicle_ids)>1 then
    return public.navision_backend_response(false,'canonical_identity_conflict',jsonb_build_object(
      'backend_record_id',p_backend_record_id,'stock_number',v_stock,'candidate_count',cardinality(v_vehicle_ids)));
  end if;
  if cardinality(v_vehicle_ids)=1 then v_vehicle_id:=v_vehicle_ids[1]; end if;

  select * into v_activation from public.navision_board_activations
  where backend_record_id=p_backend_record_id for update;

  -- Exact current Navision identity activates an already authenticated email vehicle.
  if v_activation.backend_record_id is null and v_vehicle_id is not null and exists(
    select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v_vehicle_id
  ) then
    insert into public.navision_board_activations(
      backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email,
      canonical_vehicle_id,active
    ) values(
      p_backend_record_id,'approved_email_build',v_record.normalized_data->>'batch',p_actor_id,p_actor_email,
      v_vehicle_id,true
    ) returning * into v_activation;
  end if;

  if v_activation.backend_record_id is null then
    return public.navision_backend_response(true,'not_activated');
  end if;

  v_customer:=coalesce(nullif(btrim(v_record.normalized_data->>'client'),''),nullif(btrim(v_record.normalized_data->>'customerSurname'),''),nullif(btrim(v_record.normalized_data->>'dealerCustomerName'),''),nullif(btrim(v_record.normalized_data->>'toyotaCustomer'),''));
  v_description:=coalesce(nullif(btrim(v_record.normalized_data->>'modelDescription'),''),nullif(btrim(v_record.normalized_data->>'toyotaVehicle'),''),nullif(btrim(v_record.normalized_data->>'vehicle'),''));

  if v_vehicle_id is null then
    v_vehicle_id:=extensions.uuid_generate_v5(
      'b58b5f75-d004-5a76-b9aa-48c801b4ad7d'::uuid,
      'NAVISION:'||v_record.dealer_code||':'||v_stock||':'||p_backend_record_id::text
    );
    insert into public.vehicles(
      id,permanent_vehicle_id,stock_number,vin,toyota_order_number,job_card_number,
      customer_name,vehicle_description,model,registration,lifecycle_state,visible_on_board,
      current_location,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by
    ) values(
      v_vehicle_id,'PDC-NAV-'||upper(replace(substr(v_vehicle_id::text,1,24),'-','')),
      v_record.normalized_data->>'batch',v_vin,
      nullif(btrim(v_record.normalized_data->>'order'),''),nullif(btrim(v_record.normalized_data->>'jobCardNumber'),''),
      v_customer,v_description,v_description,nullif(upper(btrim(v_record.normalized_data->>'registration')),''),
      'active',true,case when v_location='Completed' then 'Other' else v_location end,
      'microsoft_navision',v_record.dealer_code,p_backend_record_id::text,
      jsonb_build_object('authority','navision_board_activation_083','navision_record_id',p_backend_record_id,
        'latest_navision_status',v_record.normalized_data->>'toyotaStatus','reconciled_at',v_now),
      p_actor_id,p_actor_id
    ) returning * into v_vehicle;
    v_inserted:=true;
  else
    select * into v_vehicle from public.vehicles where id=v_vehicle_id for update;
  end if;

  select count(*) into v_open_work from public.vehicle_work_items
  where vehicle_id=v_vehicle_id and required and not completed;
  select to_jsonb(v_vehicle) into v_before;

  if v_location='Completed' and v_open_work=0 then
    update public.vehicles set
      stock_number=coalesce(v_record.normalized_data->>'batch',stock_number),
      vin=coalesce(v_vin,vin),
      customer_name=coalesce(v_customer,customer_name),
      vehicle_description=coalesce(v_description,vehicle_description),
      model=coalesce(v_description,model),
      lifecycle_state='completed',visible_on_board=false,current_location='Completed',
      rft_collected_at=coalesce(rft_collected_at,v_now),
      source_system='microsoft_navision',source_batch_id=v_record.dealer_code,source_record_id=p_backend_record_id::text,
      source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
        'authority','navision_board_activation_083','navision_record_id',p_backend_record_id,
        'latest_navision_status',v_record.normalized_data->>'toyotaStatus','completed_reason','Delivered - At Dealer','reconciled_at',v_now),
      version=version+1,updated_by=p_actor_id
    where id=v_vehicle_id
    returning * into v_vehicle;
    update public.navision_board_activations set
      canonical_vehicle_id=v_vehicle_id,active=false,completed_at=coalesce(completed_at,v_now),
      completion_reason='Delivered - At Dealer',completed_by=p_actor_id,completed_by_email=p_actor_email,
      updated_at=v_now
    where backend_record_id=p_backend_record_id;
    v_changed:=true; v_completed:=true;
  elsif v_location='Completed' then
    update public.vehicles set
      visible_on_board=true,
      source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
        'authority','navision_board_activation_083','navision_record_id',p_backend_record_id,
        'latest_navision_status',v_record.normalized_data->>'toyotaStatus','completion_review_required',true,
        'open_required_work',v_open_work,'reconciled_at',v_now),
      version=version+1,updated_by=p_actor_id
    where id=v_vehicle_id returning * into v_vehicle;
    update public.navision_board_activations set canonical_vehicle_id=v_vehicle_id,active=true,updated_at=v_now
    where backend_record_id=p_backend_record_id;
    v_changed:=true;
  elsif v_vehicle.lifecycle_state<>'active'
     or upper(btrim(coalesce(v_vehicle.current_location,''))) in ('PMB','PIT','QC','RFT','COMPLETED') then
    -- Existing workflow progress is authoritative over ordinary Navision movement.
    update public.navision_board_activations set canonical_vehicle_id=v_vehicle_id,active=true,updated_at=v_now
    where backend_record_id=p_backend_record_id;
  else
    update public.vehicles set
      stock_number=coalesce(v_record.normalized_data->>'batch',stock_number),
      vin=coalesce(v_vin,vin),
      toyota_order_number=coalesce(nullif(btrim(v_record.normalized_data->>'order'),''),toyota_order_number),
      job_card_number=coalesce(nullif(btrim(v_record.normalized_data->>'jobCardNumber'),''),job_card_number),
      customer_name=coalesce(v_customer,customer_name),vehicle_description=coalesce(v_description,vehicle_description),model=coalesce(v_description,model),
      current_location=case
        when lifecycle_state<>'active' then current_location
        when upper(btrim(coalesce(current_location,''))) in ('PMB','PIT','QC','RFT','COMPLETED') then current_location
        else v_location end,
      visible_on_board=case when lifecycle_state='active' then true else visible_on_board end,
      source_system='microsoft_navision',source_batch_id=v_record.dealer_code,source_record_id=p_backend_record_id::text,
      source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
        'authority','navision_board_activation_083','navision_record_id',p_backend_record_id,
        'latest_navision_status',v_record.normalized_data->>'toyotaStatus','reconciled_at',v_now),
      version=version+1,updated_by=p_actor_id
    where id=v_vehicle_id returning * into v_vehicle;
    update public.navision_board_activations set canonical_vehicle_id=v_vehicle_id,active=true,completed_at=null,
      completion_reason=null,completed_by=null,completed_by_email=null,updated_at=v_now
    where backend_record_id=p_backend_record_id;
    v_changed:=true;
  end if;

  update public.navision_backend_records set canonical_vehicle_id=v_vehicle_id
  where id=p_backend_record_id and canonical_vehicle_id is distinct from v_vehicle_id;

  select to_jsonb(v_vehicle) into v_after;
  if v_inserted then
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('insert','vehicles',v_vehicle_id,v_vehicle_id,p_actor_id,p_actor_email,null,v_after,
      jsonb_build_object('source','navision_operational_reconcile_083','backend_record_id',p_backend_record_id,'location',v_location));
  elsif v_changed and v_before is distinct from v_after then
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('update','vehicles',v_vehicle_id,v_vehicle_id,p_actor_id,p_actor_email,v_before,v_after,
      jsonb_build_object('source','navision_operational_reconcile_083','backend_record_id',p_backend_record_id,'location',v_location,
        'completed',v_completed,'open_required_work',v_open_work));
  end if;

  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
  update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;

  return public.navision_backend_response(true,case when v_completed then 'completed' else 'reconciled' end,jsonb_build_object(
    'backend_record_id',p_backend_record_id,'vehicle_id',v_vehicle_id,'location',v_location,
    'completed',v_completed,'open_required_work',v_open_work));
end;
$reconcile$;

revoke all on function public.reconcile_navision_operational_record(uuid,uuid,text) from public,anon,authenticated;

create or replace function public.trigger_reconcile_navision_operational_record()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $trigger$
declare v_backend_record_id uuid;
begin
  if pg_trigger_depth()>1 then return new; end if;
  if tg_table_name='navision_board_activations' then
    v_backend_record_id:=new.backend_record_id;
  else
    v_backend_record_id:=new.id;
  end if;
  perform public.reconcile_navision_operational_record(
    v_backend_record_id,auth.uid(),public.current_actor_email()
  );
  return new;
end;
$trigger$;

revoke all on function public.trigger_reconcile_navision_operational_record() from public,anon,authenticated;

drop trigger if exists navision_record_operational_reconcile on public.navision_backend_records;
create trigger navision_record_operational_reconcile
after insert or update of normalized_data,is_current,record_status on public.navision_backend_records
for each row execute function public.trigger_reconcile_navision_operational_record();

drop trigger if exists navision_activation_operational_reconcile on public.navision_board_activations;
create trigger navision_activation_operational_reconcile
after insert or update of active,activated_stock_number on public.navision_board_activations
for each row execute function public.trigger_reconcile_navision_operational_record();

-- Backfill current activated rows and exact authenticated-email matches.
do $backfill$
declare v_id uuid;
begin
  for v_id in
    select distinct r.id
    from public.navision_backend_records r
    left join public.navision_board_activations a on a.backend_record_id=r.id
    left join public.vehicles v on v.deleted_at is null
      and v.stock_number_normalized=public.normalize_vehicle_stock_number(r.normalized_data->>'batch')
    where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
      and r.is_current and r.record_status='current'
      and (a.backend_record_id is not null or exists(
        select 1 from public.pdc_authenticated_email_import_receipts e where e.vehicle_id=v.id
      ))
    order by r.id
  loop
    perform public.reconcile_navision_operational_record(v_id,null,'staging-migration-083');
  end loop;
end;
$backfill$;

-- Approved display projection now exposes canonical operational state, never raw evidence.
create or replace function public.get_navision_visible_snapshot(
  p_source_system text,
  p_dealer_code text,
  p_after_record_id uuid default null,
  p_page_size integer default 200,
  p_expected_revision bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,extensions
as $visible$
declare
  v_role text:=public.current_pdc_user_role()::text;
  v_source_system text:=lower(btrim(coalesce(p_source_system,'')));
  v_dealer_code text:=btrim(coalesce(p_dealer_code,''));
  v_page_size integer;
  v_revision bigint;
  v_result jsonb;
begin
  if not coalesce(v_role=any(array['viewer','operator','importer','administrator']),false) then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if v_source_system<>'microsoft_navision' or v_dealer_code not in ('14450','37047') then
    return public.navision_backend_response(false,'invalid_input',jsonb_build_object('field','scope'));
  end if;
  if p_page_size is null or p_page_size<1 then
    return public.navision_backend_response(false,'invalid_input',jsonb_build_object('field','page_size'));
  end if;
  v_page_size:=least(p_page_size,500);
  select revision into v_revision from public.navision_backend_revision where singleton;
  if p_expected_revision is not null and p_expected_revision<>v_revision then
    return public.navision_backend_response(false,'stale_revision',jsonb_build_object('current_revision',v_revision));
  end if;

  with page as materialized (
    select r.*,a.activation_source,a.activated_stock_number,a.activated_at,a.active as activation_active,
      a.canonical_vehicle_id as activation_vehicle_id,a.completed_at,a.completion_reason,a.completed_by_email,
      v.current_location,v.lifecycle_state::text as lifecycle_state,v.visible_on_board,v.rft_collected_at
    from public.navision_backend_records r
    left join public.navision_board_activations a on a.backend_record_id=r.id
    left join public.vehicles v on v.id=coalesce(a.canonical_vehicle_id,r.canonical_vehicle_id)
    where r.source_system=v_source_system and r.dealer_code=v_dealer_code
      and (p_after_record_id is null or r.id>p_after_record_id)
    order by r.id limit v_page_size+1
  ), selected as materialized (select * from page order by id limit v_page_size)
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
      'board_activated',activation_source is not null and activation_active
        and activated_stock_number=nullif(btrim(coalesce(normalized_data->>'batch','')),''),
      'activation_source',activation_source,'activated_at',activated_at,
      'canonical_vehicle_id',coalesce(activation_vehicle_id,canonical_vehicle_id),
      'current_location',current_location,'lifecycle_state',lifecycle_state,'visible_on_board',visible_on_board,
      'completed_at',coalesce(completed_at,rft_collected_at),'completion_reason',completion_reason,'completed_by_email',completed_by_email
    ) order by id) from selected),'[]'::jsonb),
    'has_more',(select count(*)>v_page_size from page),
    'next_record_id',case when (select count(*)>v_page_size from page) then (select id from selected order by id desc limit 1) else null end,
    'authority','shared_navision_backend_canonical_operational','data_access','approved_staff_display'
  )) into v_result;
  return v_result;
end;
$visible$;

revoke all on function public.get_navision_visible_snapshot(text,text,uuid,integer,bigint) from public,anon,authenticated;
grant execute on function public.get_navision_visible_snapshot(text,text,uuid,integer,bigint) to authenticated;

comment on function public.reconcile_navision_operational_record(uuid,uuid,text) is
  'Staging-only exact-identity reconciliation: activated Navision records become canonical; Body Builder maps to PMB; At Dealer closes only with no open required work.';

commit;
