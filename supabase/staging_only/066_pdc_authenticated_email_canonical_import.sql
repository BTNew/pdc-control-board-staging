-- Staging-only migration 066: authenticated-email automatic canonical import.
--
-- One unambiguous Stock and/or VIN observation from the enrolled Viewer monitor
-- is consumed once. A unique current Navision identity wins for
-- vehicle/customer/location data;
-- otherwise bounded email fields create or enrich the canonical vehicle at Other.
-- Required-work ticks create canonical work items but never create a booking.
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
  if to_regclass('public.pdc_monitor_stage_activation_writers') is null
     or to_regclass('public.pdc_ai_intake_decision_receipts') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_board_activations') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.vehicle_parts_updates') is null then
    raise exception 'PDC_MIGRATION_066_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create table if not exists public.pdc_authenticated_email_import_receipts (
  receipt_id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  idempotency_key text not null,
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  source_hash text not null unique check (source_hash ~ '^[a-f0-9]{64}$'),
  evidence_hash text not null check (evidence_hash ~ '^[a-f0-9]{64}$'),
  source_uid text not null,
  sender_address text not null,
  source_received_at timestamptz not null,
  stock_number text,
  vin text,
  backend_record_id uuid references public.navision_backend_records(id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  identity_source text not null check (identity_source in ('navision_exact','operational_exact','email_new')),
  required_work jsonb not null check (jsonb_typeof(required_work)='array'),
  response jsonb not null check (jsonb_typeof(response)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(actor_id,idempotency_key)
);

alter table public.pdc_authenticated_email_import_receipts enable row level security;
revoke all on table public.pdc_authenticated_email_import_receipts from public,anon,authenticated;

create or replace function public.import_pdc_authenticated_vehicle_email(
  p_idempotency_key text,
  p_source_hash text,
  p_evidence_hash text,
  p_source_uid text,
  p_sender_address text,
  p_authentication jsonb,
  p_source_received_at timestamptz,
  p_subject text,
  p_email_vehicle jsonb,
  p_required_work jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $import$
declare
  v_actor_id uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text;
  v_key text:=btrim(coalesce(p_idempotency_key,''));
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));
  v_evidence_hash text:=lower(btrim(coalesce(p_evidence_hash,'')));
  v_source_uid text:=btrim(coalesce(p_source_uid,''));
  v_sender text:=lower(btrim(coalesce(p_sender_address,'')));
  v_auth jsonb:=coalesce(p_authentication,'{}'::jsonb);
  v_subject text:=btrim(coalesce(p_subject,''));
  v_email jsonb:=coalesce(p_email_vehicle,'{}'::jsonb);
  v_work jsonb:=coalesce(p_required_work,'[]'::jsonb);
  v_request_hash text;
  v_receipt public.pdc_authenticated_email_import_receipts%rowtype;
  v_proposal public.pdc_ai_intake_proposals%rowtype;
  v_stock text;
  v_vin text;
  v_customer text;
  v_vehicle_description text;
  v_registration text;
  v_job_card text;
  v_order_number text;
  v_eta_text text;
  v_eta date;
  v_nav_stock_ids uuid[]:='{}'::uuid[];
  v_nav_vin_ids uuid[]:='{}'::uuid[];
  v_operational_stock_ids uuid[]:='{}'::uuid[];
  v_operational_vin_ids uuid[]:='{}'::uuid[];
  v_record public.navision_backend_records%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_before_vehicle jsonb;
  v_after_vehicle jsonb;
  v_vehicle_id uuid;
  v_identity_source text;
  v_location text:='Other';
  v_nav_customer text;
  v_nav_vehicle text;
  v_nav_registration text;
  v_nav_job text;
  v_nav_order text;
  v_nav_eta_text text;
  v_work_name text;
  v_work_key text;
  v_work_item_id uuid;
  v_work_before public.vehicle_work_items%rowtype;
  v_work_after public.vehicle_work_items%rowtype;
  v_required_work jsonb:='[]'::jsonb;
  v_parts_requested boolean:=false;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
  v_response jsonb;
  v_inserted integer;
  v_navision_revision bigint;
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

  if v_key !~ '^pdc-email-import-[A-Za-z0-9_-]{16,160}$'
     or v_source_hash !~ '^[a-f0-9]{64}$'
     or v_evidence_hash !~ '^[a-f0-9]{64}$'
     or length(v_source_uid) not between 1 and 100
     or v_sender !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
     or split_part(v_sender,'@',2) not in ('broometoyota.com.au','pmgwa.com.au')
     or jsonb_typeof(v_auth) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_auth) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2)
     or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not (v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb)
     or length(v_subject) not between 1 and 300
     or jsonb_typeof(v_email) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_email) k)
        is distinct from array['cancelled','conflicts','customer_name','eta_to_kewdale','job_card_number','registration','stock_numbers','toyota_order_number','vehicle_description','vins']::text[]
     or jsonb_typeof(v_email->'stock_numbers') is distinct from 'array'
     or jsonb_array_length(v_email->'stock_numbers')>1
     or jsonb_typeof(v_email->'vins') is distinct from 'array'
     or jsonb_array_length(v_email->'vins')>1
     or jsonb_array_length(v_email->'stock_numbers')+jsonb_array_length(v_email->'vins')<1
     or jsonb_typeof(v_email->'conflicts') is distinct from 'array'
     or jsonb_typeof(v_email->'cancelled') is distinct from 'boolean'
     or jsonb_typeof(v_work) is distinct from 'array'
     or jsonb_array_length(v_work)>9
     or exists(select 1 from jsonb_array_elements(v_work) x where jsonb_typeof(x)<>'string')
     or (select count(*) from jsonb_array_elements_text(v_work))
        <> (select count(distinct lower(btrim(x))) from jsonb_array_elements_text(v_work) x) then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  v_stock:=nullif(public.normalize_vehicle_stock_number(v_email->'stock_numbers'->>0),'');
  v_vin:=nullif(public.normalize_vehicle_vin(v_email->'vins'->>0),'');
  v_customer:=nullif(btrim(v_email->>'customer_name'),'');
  v_vehicle_description:=nullif(btrim(v_email->>'vehicle_description'),'');
  v_registration:=nullif(upper(btrim(v_email->>'registration')),'');
  v_job_card:=nullif(btrim(v_email->>'job_card_number'),'');
  v_order_number:=nullif(btrim(v_email->>'toyota_order_number'),'');
  v_eta_text:=nullif(btrim(v_email->>'eta_to_kewdale'),'');
  if (v_stock is not null and not public.is_real_vehicle_stock_number(v_stock))
     or (v_vin is not null and not public.is_valid_vehicle_vin(v_vin))
     or (v_stock is null and v_vin is null)
     or length(coalesce(v_customer,''))>200
     or length(v_vehicle_description)>200
     or length(coalesce(v_registration,''))>20
     or length(coalesce(v_job_card,''))>80
     or length(coalesce(v_order_number,''))>80
     or (v_eta_text is not null and v_eta_text !~ '^\d{4}-\d{2}-\d{2}$') then
    return public.navision_backend_response(false,'invalid_vehicle_evidence');
  end if;
  if v_eta_text is not null then
    v_eta:=to_date(v_eta_text,'YYYY-MM-DD');
    if to_char(v_eta,'YYYY-MM-DD')<>v_eta_text then
      return public.navision_backend_response(false,'invalid_vehicle_evidence');
    end if;
  end if;

  for v_work_name in select value from jsonb_array_elements_text(v_work) loop
    v_work_key:=case lower(btrim(v_work_name))
      when 'bus4x4' then 'bus4x4'
      when 'tint' then 'tint'
      when 'hoist' then 'hoist'
      when 'fitting' then 'fitting'
      when 'fabrication' then 'fabrication'
      when 'electrical' then 'electrical'
      when 'tyre' then 'tyre'
      when 'sublet' then 'sublet'
      when 'pitinspection' then 'pitInspection'
      when 'parts' then 'PARTS'
      else null end;
    if v_work_key is null then
      return public.navision_backend_response(false,'invalid_required_work');
    end if;
    if v_work_key<>'PARTS' and not exists(
      select 1 from public.workshop_stages s where s.work_key=v_work_key and s.active
    ) then
      return public.navision_backend_response(false,'required_work_not_active');
    end if;
    v_required_work:=v_required_work||jsonb_build_array(v_work_key);
    v_parts_requested:=v_parts_requested or v_work_key='PARTS';
  end loop;

  v_request_hash:=encode(extensions.digest(jsonb_build_object(
    'contract_version',1,'actor_id',v_actor_id,'source_hash',v_source_hash,
    'evidence_hash',v_evidence_hash,'source_uid',v_source_uid,'sender_address',v_sender,
    'authentication',v_auth,'source_received_at',p_source_received_at,'subject',v_subject,
    'email_vehicle',v_email,'required_work',v_required_work
  )::text,'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended('pdc-email-import-receipt:'||v_actor_id::text||':'||v_key,0));
  select * into v_receipt from public.pdc_authenticated_email_import_receipts
  where actor_id=v_actor_id and idempotency_key=v_key;
  if found then
    if v_receipt.request_hash<>v_request_hash then
      return public.navision_backend_response(false,'idempotency_conflict');
    end if;
    return v_receipt.response;
  end if;
  select * into v_receipt from public.pdc_authenticated_email_import_receipts
  where source_hash=v_source_hash order by created_at limit 1;
  if found then
    if v_receipt.request_hash<>v_request_hash then
      return public.navision_backend_response(false,'source_reuse_conflict');
    end if;
    return v_receipt.response;
  end if;

  if p_source_received_at is null
     or p_source_received_at>clock_timestamp()+interval '5 minutes'
     or p_source_received_at<clock_timestamp()-interval '30 days' then
    return public.navision_backend_response(false,'evidence_expired');
  end if;
  if (v_email->>'cancelled')::boolean
     or jsonb_array_length(v_email->'conflicts')>0
     or concat_ws(' ',v_subject,v_vehicle_description,v_customer) ~* '\m(cancelled|canceled|cancellation)\M' then
    return public.navision_backend_response(false,'evidence_conflicted_or_cancelled');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-email-source:'||v_source_hash,0));
  if not exists(
    select 1 from public.pdc_email_source_claims c
    where c.source_hash=v_source_hash and c.contract_name='pdc_ai_intake_063'
  ) then
    return public.navision_backend_response(false,'source_not_observed');
  end if;

  -- Match the canonical identity-trigger order and serialize every competing
  -- canonical writer while the Stock+VIN absence/pairing decision is made.
  lock table public.vehicles,public.vehicle_aliases in share row exclusive mode;
  if v_vin is not null then
    perform pg_advisory_xact_lock(hashtextextended('vehicle-master:vin:'||v_vin,0));
  end if;
  if v_stock is not null then
    perform pg_advisory_xact_lock(hashtextextended('vehicle-master:stock_number:'||v_stock,0));
  end if;
  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));

  select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_nav_stock_ids from (
    select r.id from public.navision_backend_records r
    where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
      and r.is_current and r.record_status='current'
      and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
      and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock
  ) q;
  select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_nav_vin_ids from (
    select r.id from public.navision_backend_records r
    where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
      and r.is_current and r.record_status='current'
      and public.is_valid_vehicle_vin(r.normalized_data->>'vin')
      and public.normalize_vehicle_vin(r.normalized_data->>'vin')=v_vin
  ) q;
  if cardinality(v_nav_stock_ids)>1 or cardinality(v_nav_vin_ids)>1
     or (v_stock is not null and v_vin is not null and v_nav_stock_ids is distinct from v_nav_vin_ids) then
    return public.navision_backend_response(false,'navision_identity_conflict',jsonb_build_object(
      'stock_matches',cardinality(v_nav_stock_ids),'vin_matches',cardinality(v_nav_vin_ids)));
  end if;
  if v_stock is not null and cardinality(v_nav_stock_ids)=1 then
    select * into v_record from public.navision_backend_records where id=v_nav_stock_ids[1] for update;
  elsif v_vin is not null and cardinality(v_nav_vin_ids)=1 then
    select * into v_record from public.navision_backend_records where id=v_nav_vin_ids[1] for update;
  end if;

  select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into v_operational_stock_ids from (
    select v.id vehicle_id from public.vehicles v where v.deleted_at is null and v.stock_number_normalized=v_stock
    union all
    select a.vehicle_id from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock
  ) q;
  select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into v_operational_vin_ids from (
    select v.id vehicle_id from public.vehicles v where v.deleted_at is null and v.vin_normalized=v_vin
    union all
    select a.vehicle_id from public.vehicle_aliases a where a.active and a.alias_type_normalized='vin' and a.normalized_alias_value=v_vin
  ) q;
  if cardinality(v_operational_stock_ids)>1 or cardinality(v_operational_vin_ids)>1
     or (v_stock is not null and v_vin is not null and v_operational_stock_ids is distinct from v_operational_vin_ids) then
    return public.navision_backend_response(false,'operational_identity_conflict',jsonb_build_object(
      'stock_matches',cardinality(v_operational_stock_ids),'vin_matches',cardinality(v_operational_vin_ids)));
  end if;
  if v_stock is not null and cardinality(v_operational_stock_ids)=1 then
    v_vehicle_id:=v_operational_stock_ids[1];
  elsif v_vin is not null and cardinality(v_operational_vin_ids)=1 then
    v_vehicle_id:=v_operational_vin_ids[1];
  end if;
  if v_vehicle_id is not null then
    select * into v_vehicle from public.vehicles where id=v_vehicle_id for update;
    if v_vehicle.lifecycle_state<>'active' or v_vehicle.deleted_at is not null then
      return public.navision_backend_response(false,'operational_vehicle_inactive');
    end if;
  end if;

  if found and v_record.id is not null and exists(
    select 1 from public.vehicles v where v.source_system_normalized='microsoft_navision'
      and v.source_record_id_normalized=public.normalize_vehicle_source_identifier(v_record.id::text)
      and (v_vehicle_id is null or v.id<>v_vehicle_id)
  ) then
    return public.navision_backend_response(false,'navision_source_identity_conflict');
  end if;

  if v_record.id is not null then
    v_identity_source:='navision_exact';
    v_stock:=coalesce(nullif(public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch'),''),v_stock);
    v_vin:=coalesce(nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),''),v_vin);
    v_nav_customer:=coalesce(nullif(btrim(v_record.normalized_data->>'client'),''),nullif(btrim(v_record.normalized_data->>'customerSurname'),''),nullif(btrim(v_record.normalized_data->>'dealerCustomerName'),''),nullif(btrim(v_record.normalized_data->>'toyotaCustomer'),''));
    v_nav_vehicle:=coalesce(nullif(btrim(v_record.normalized_data->>'modelDescription'),''),nullif(btrim(v_record.normalized_data->>'toyotaVehicle'),''),nullif(btrim(v_record.normalized_data->>'vehicle'),''));
    v_nav_registration:=nullif(upper(btrim(v_record.normalized_data->>'registration')),'');
    v_nav_job:=nullif(btrim(v_record.normalized_data->>'jobCardNumber'),'');
    v_nav_order:=nullif(btrim(v_record.normalized_data->>'order'),'');
    v_nav_eta_text:=coalesce(nullif(btrim(v_record.normalized_data->>'navisionKewdaleEta'),''),nullif(btrim(v_record.normalized_data->>'etaAtDealer'),''));
    if v_nav_eta_text ~ '^\d{4}-\d{2}-\d{2}$' and to_char(to_date(v_nav_eta_text,'YYYY-MM-DD'),'YYYY-MM-DD')=v_nav_eta_text then
      v_eta:=to_date(v_nav_eta_text,'YYYY-MM-DD');
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
    v_customer:=v_nav_customer;
    v_vehicle_description:=v_nav_vehicle;
    v_registration:=v_nav_registration;
    v_job_card:=v_nav_job;
    v_order_number:=v_nav_order;
  elsif v_vehicle_id is not null then
    v_identity_source:='operational_exact';
    v_stock:=coalesce(v_vehicle.stock_number_normalized,v_stock);
    v_vin:=coalesce(v_vehicle.vin_normalized,v_vin);
  else
    v_identity_source:='email_new';
  end if;

  if v_vehicle_id is null then
    v_vehicle_id:=extensions.uuid_generate_v5(
      'b58b5f75-d004-5a76-b9aa-48c801b4ad7d'::uuid,
      coalesce(v_stock,'NO-STOCK')||':'||coalesce(v_vin,'NO-VIN')||':'||v_source_hash
    );
    insert into public.vehicles(
      id,permanent_vehicle_id,stock_number,vin,toyota_order_number,job_card_number,
      customer_name,vehicle_description,model,registration,lifecycle_state,visible_on_board,
      current_location,eta_to_kewdale,source_system,source_batch_id,source_record_id,
      source_payload,created_by,updated_by
    ) values(
      v_vehicle_id,'PDC-AI-'||upper(substr(v_source_hash,1,24)),
      case when v_record.id is not null then v_record.normalized_data->>'batch' else v_stock end,
      case when v_record.id is not null then v_record.normalized_data->>'vin' else v_vin end,
      v_order_number,v_job_card,v_customer,v_vehicle_description,v_vehicle_description,v_registration,
      'active',true,case when v_record.id is not null then v_location else 'Other' end,v_eta,
      case when v_record.id is not null then 'microsoft_navision' else 'authenticated_email' end,
      case when v_record.id is not null then v_record.dealer_code else 'pdc_authenticated_email_066' end,
      case when v_record.id is not null then v_record.id::text else v_source_hash end,
      jsonb_build_object('intake_contract','pdc_authenticated_email_066','source_hash',v_source_hash,'evidence_hash',v_evidence_hash),
      v_actor_id,v_actor_id
    ) returning * into v_vehicle;
    v_before_vehicle:=null;
  else
    select to_jsonb(v_vehicle) into v_before_vehicle;
    update public.vehicles set
      stock_number=case when v_record.id is not null then v_record.normalized_data->>'batch' else v_stock end,
      vin=case when v_record.id is not null then v_record.normalized_data->>'vin' else v_vin end,
      toyota_order_number=coalesce(v_order_number,toyota_order_number),
      job_card_number=coalesce(v_job_card,job_card_number),
      customer_name=coalesce(v_customer,customer_name),
      vehicle_description=coalesce(v_vehicle_description,vehicle_description),
      model=coalesce(v_vehicle_description,model),registration=coalesce(v_registration,registration),
      eta_to_kewdale=coalesce(v_eta,eta_to_kewdale),visible_on_board=true,
      source_system=case when v_record.id is not null then 'microsoft_navision' else source_system end,
      source_batch_id=case when v_record.id is not null then v_record.dealer_code else source_batch_id end,
      source_record_id=case when v_record.id is not null then v_record.id::text else source_record_id end,
      version=version+1,updated_by=v_actor_id
    where id=v_vehicle_id returning * into v_vehicle;
    -- current_location is deliberately absent: operational location always wins.
  end if;
  select to_jsonb(v_vehicle) into v_after_vehicle;

  insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  values(case when v_before_vehicle is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
    'vehicles',v_vehicle_id,v_vehicle_id,v_actor_id,v_actor_email,v_before_vehicle,v_after_vehicle,
    jsonb_build_object('source','pdc_authenticated_email_066','source_hash',v_source_hash,
      'evidence_hash',v_evidence_hash,'identity_source',v_identity_source,'no_booking',true));

  if v_record.id is not null then
    if exists(select 1 from public.navision_board_activations a where a.backend_record_id=v_record.id
      and public.normalize_vehicle_stock_number(a.activated_stock_number)<>v_stock) then
      return public.navision_backend_response(false,'activation_identity_conflict');
    end if;
    insert into public.navision_board_activations(
      backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email
    ) values(v_record.id,'approved_email_build',v_record.normalized_data->>'batch',v_actor_id,v_actor_email)
    on conflict(backend_record_id) do nothing;
    get diagnostics v_inserted=row_count;
    if v_inserted=1 then
      update public.navision_backend_revision set revision=revision+1,updated_at=clock_timestamp()
      where singleton returning revision into v_navision_revision;
      insert into public.navision_backend_audit(action,backend_record_id,revision,evidence,actor_id,actor_email)
      values('board_activate',v_record.id,v_navision_revision,jsonb_build_object(
        'activation_source','approved_email_build','contract','pdc_authenticated_email_066',
        'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'vehicle_id',v_vehicle_id,
        'automated',true),v_actor_id,v_actor_email);
    end if;
  end if;

  for v_work_key in select value from jsonb_array_elements_text(v_required_work) loop
    select * into v_work_before from public.vehicle_work_items
    where vehicle_id=v_vehicle_id and work_key=v_work_key for update;
    insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
    values(v_vehicle_id,v_work_key,true,false,null,null,null,clock_timestamp())
    on conflict(vehicle_id,work_key) do update set
      required=true,updated_at=clock_timestamp()
      where not public.vehicle_work_items.completed and not public.vehicle_work_items.required
    returning * into v_work_after;
    if found then
      v_work_item_id:=v_work_after.id;
      if v_work_before.id is null or (not v_work_before.completed and not v_work_before.required) then
        insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
        values(case when v_work_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
          'vehicle_work_items',v_work_after.id,v_vehicle_id,v_actor_id,v_actor_email,
          case when v_work_before.id is null then null else to_jsonb(v_work_before) end,to_jsonb(v_work_after),
          jsonb_build_object('source','pdc_authenticated_email_066','source_hash',v_source_hash,
            'evidence_hash',v_evidence_hash,'required_work',v_work_key,'completed_work_reopened',false));
      end if;
    else
      select id into v_work_item_id from public.vehicle_work_items
      where vehicle_id=v_vehicle_id and work_key=v_work_key;
    end if;
    v_work_before:=null; v_work_after:=null;
  end loop;

  if v_parts_requested then
    select * into v_parts_before from public.vehicle_parts_updates
    where vehicle_id=v_vehicle_id order by updated_at desc,id desc limit 1 for update;
    if found then
      if not v_parts_before.parts_required then
        update public.vehicle_parts_updates set parts_required=true,updated_by=v_actor_id,updated_at=clock_timestamp()
        where id=v_parts_before.id returning * into v_parts_after;
      else
        v_parts_after:=v_parts_before;
      end if;
    else
      insert into public.vehicle_parts_updates(vehicle_id,parts_required,updated_by)
      values(v_vehicle_id,true,v_actor_id) returning * into v_parts_after;
    end if;
    if v_parts_before.id is null or not v_parts_before.parts_required then
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values(case when v_parts_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
        'vehicle_parts_updates',v_parts_after.id,v_vehicle_id,v_actor_id,v_actor_email,
        case when v_parts_before.id is null then null else to_jsonb(v_parts_before) end,to_jsonb(v_parts_after),
        jsonb_build_object('source','pdc_authenticated_email_066','source_hash',v_source_hash,
          'evidence_hash',v_evidence_hash,'parts_requested',true));
    end if;
  end if;

  v_response:=public.navision_backend_response(true,'canonical_imported',jsonb_build_object(
    'vehicle_id',v_vehicle_id,'backend_record_id',v_record.id,'identity_source',v_identity_source,
    'stock_number',v_stock,'vin',v_vin,'current_location',v_vehicle.current_location,
    'visible_on_board',v_vehicle.visible_on_board,'required_work',v_required_work,
    'parts_required',v_parts_requested,'booking_created',false));

  insert into public.pdc_authenticated_email_import_receipts(
    actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,
    sender_address,source_received_at,stock_number,vin,backend_record_id,vehicle_id,
    identity_source,required_work,response
  ) values(
    v_actor_id,v_key,v_request_hash,v_source_hash,v_evidence_hash,v_source_uid,
    v_sender,p_source_received_at,v_stock,v_vin,v_record.id,v_vehicle_id,
    v_identity_source,v_required_work,v_response
  );

  select * into v_proposal from public.pdc_ai_intake_proposals
  where source_hash=v_source_hash for update;
  if found and v_proposal.status='pending' then
    update public.pdc_ai_intake_proposals set
      status='applied',version=version+1,decided_by=v_actor_id,decided_by_email=v_actor_email,
      decided_at=clock_timestamp(),decision_reason='Authenticated email automatic vehicle/work import',
      result=v_response
    where proposal_id=v_proposal.proposal_id
    returning * into v_proposal;
    insert into public.pdc_ai_intake_history(
      proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
      stock_number,action_type,details
    ) values(
      v_proposal.proposal_id,'applied',v_actor_id,v_actor_email,v_proposal.version,
      v_proposal.fingerprint,v_stock,v_proposal.action_type,
      jsonb_build_object('automatic_contract','pdc_authenticated_email_066',
        'vehicle_id',v_vehicle_id,'identity_source',v_identity_source,
        'current_location',v_vehicle.current_location,'required_work',v_required_work,
        'booking_created',false)
    );
    update public.pdc_ai_intake_revision set revision=revision+1,updated_at=clock_timestamp()
    where singleton;
  end if;
  return v_response;
exception
  when unique_violation then
    return public.navision_backend_response(false,'identity_or_receipt_conflict');
end;
$import$;

create table if not exists public.pdc_email_vehicle_revision (
  singleton boolean primary key default true check(singleton),
  revision bigint not null default 1 check(revision>=1),
  updated_at timestamptz not null default clock_timestamp()
);
insert into public.pdc_email_vehicle_revision(singleton,revision)
values(true,1) on conflict(singleton) do nothing;
alter table public.pdc_email_vehicle_revision enable row level security;
revoke all on table public.pdc_email_vehicle_revision from public,anon,authenticated;
grant select on table public.pdc_email_vehicle_revision to authenticated;
drop policy if exists pdc_email_vehicle_revision_staff_read on public.pdc_email_vehicle_revision;
create policy pdc_email_vehicle_revision_staff_read on public.pdc_email_vehicle_revision
for select to authenticated
using(public.current_pdc_user_role()::text in ('viewer','operator','importer','administrator'));

create or replace function public.bump_pdc_email_vehicle_revision()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $bump$
begin
  update public.pdc_email_vehicle_revision
  set revision=revision+1,updated_at=clock_timestamp()
  where singleton;
  return null;
end;
$bump$;
revoke all on function public.bump_pdc_email_vehicle_revision() from public,anon,authenticated;

drop trigger if exists pdc_email_vehicle_revision_vehicles on public.vehicles;
create trigger pdc_email_vehicle_revision_vehicles
after insert or update or delete on public.vehicles
for each statement execute function public.bump_pdc_email_vehicle_revision();
drop trigger if exists pdc_email_vehicle_revision_work_items on public.vehicle_work_items;
create trigger pdc_email_vehicle_revision_work_items
after insert or update or delete on public.vehicle_work_items
for each statement execute function public.bump_pdc_email_vehicle_revision();
drop trigger if exists pdc_email_vehicle_revision_parts on public.vehicle_parts_updates;
create trigger pdc_email_vehicle_revision_parts
after insert or update or delete on public.vehicle_parts_updates
for each statement execute function public.bump_pdc_email_vehicle_revision();

do $publication$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(
       select 1 from pg_publication_tables
       where pubname='supabase_realtime' and schemaname='public'
         and tablename='pdc_email_vehicle_revision'
     ) then
    alter publication supabase_realtime add table public.pdc_email_vehicle_revision;
  end if;
end;
$publication$;

create or replace function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $snapshot$
declare
  v_role text;
  v_revision bigint;
  v_rows jsonb;
begin
  v_role:=public.current_pdc_user_role()::text;
  if v_role not in ('viewer','operator','importer','administrator') then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select revision into v_revision from public.pdc_email_vehicle_revision where singleton;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,
    'permanent_vehicle_id',v.permanent_vehicle_id,
    'stock_number',v.stock_number,
    'vin',v.vin,
    'job_card_number',v.job_card_number,
    'customer_name',v.customer_name,
    'vehicle_description',v.vehicle_description,
    'salesperson_reference',v.salesperson_reference,
    'registration',v.registration,
    'eta_to_kewdale',v.eta_to_kewdale,
    'current_location',v.current_location,
    'visible_on_board',v.visible_on_board,
    'source_system',v.source_system,
    'source_record_id',v.source_record_id,
    'updated_at',v.updated_at,
    'work_items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,
        'completed_at',wi.completed_at,'completed_by',wi.completed_by
      ) order by wi.work_key)
      from public.vehicle_work_items wi where wi.vehicle_id=v.id
    ),'[]'::jsonb),
    'parts_required',coalesce((
      select pu.parts_required from public.vehicle_parts_updates pu
      where pu.vehicle_id=v.id order by pu.updated_at desc,pu.id desc limit 1
    ),false),
    'parts_completed',coalesce((
      select wi.completed from public.vehicle_work_items wi
      where wi.vehicle_id=v.id and wi.work_key='PARTS'
    ),false)
  ) order by coalesce(v.stock_number,v.vin,v.permanent_vehicle_id),v.id),'[]'::jsonb)
  into v_rows
  from public.vehicles v
  where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    and exists(
      select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v.id
    );
  return public.navision_backend_response(true,'ok',jsonb_build_object(
    'revision',coalesce(v_revision,1),'vehicles',v_rows
  ));
end;
$snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public,anon,authenticated;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;

-- The monitor first records the authenticated observation, then invokes this
-- idempotent automatic contract. Historical Administrator decisions remain
-- readable and old pending rows can still be handled through migration 065.
revoke all on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)
from public,anon,authenticated;
grant execute on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)
to authenticated;

comment on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) is
  'Staging-only enrolled-Viewer automatic canonical vehicle/work import for one provider-authenticated unambiguous Stock and/or VIN email; creates no bookings.';

commit;
