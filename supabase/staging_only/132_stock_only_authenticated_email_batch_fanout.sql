-- Staging-only migration 132: replace the disabled Migration 130 RPC with
-- stock-only canonical vehicle creation/update. This contract does not invoke
-- Navision activation reconciliation and therefore cannot fall back to VIN.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception using errcode='P0001',message='PDC_EMAIL_132_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='131' and name='disable_unsafe_authenticated_email_batch_fanout') then
    raise exception using errcode='P0001',message='PDC_EMAIL_132_PREDECESSOR_131_REQUIRED';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='132') then
    raise exception using errcode='P0001',message='PDC_EMAIL_132_VERSION_CONFLICT';
  end if;
end
$guard$;

-- One immutable email source may be consumed by exactly one import contract.
-- The shared advisory lock serializes the legacy single-import function and
-- this batch contract; receipt triggers close both sequential and race paths.
create or replace function public.pdc_email_receipt_single_source_guard()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $source_guard$
begin
  if new.source_hash is null or new.source_hash!~'^[a-f0-9]{64}$' then
    raise exception using errcode='23505',message='PDC_EMAIL_SOURCE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-email-source:'||new.source_hash,0));
  if tg_table_name='pdc_authenticated_email_import_receipts' then
    if exists(select 1 from public.pdc_authenticated_email_batch_receipts r where r.source_hash=new.source_hash) then
      raise exception using errcode='23505',message='PDC_EMAIL_SOURCE_ALREADY_BATCH_CONSUMED';
    end if;
  elsif tg_table_name='pdc_authenticated_email_batch_receipts' then
    if exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.source_hash=new.source_hash) then
      raise exception using errcode='23505',message='PDC_EMAIL_SOURCE_ALREADY_SINGLE_CONSUMED';
    end if;
  else
    raise exception using errcode='P0001',message='PDC_EMAIL_SOURCE_GUARD_WRONG_TABLE';
  end if;
  return new;
end
$source_guard$;
revoke all on function public.pdc_email_receipt_single_source_guard()
from public,anon,authenticated,service_role;

drop trigger if exists pdc_email_single_receipt_source_guard on public.pdc_authenticated_email_import_receipts;
create trigger pdc_email_single_receipt_source_guard
before insert on public.pdc_authenticated_email_import_receipts
for each row execute function public.pdc_email_receipt_single_source_guard();

drop trigger if exists pdc_email_batch_receipt_source_guard on public.pdc_authenticated_email_batch_receipts;
create trigger pdc_email_batch_receipt_source_guard
before insert on public.pdc_authenticated_email_batch_receipts
for each row execute function public.pdc_email_receipt_single_source_guard();

-- Migration 132 supersedes the one-vehicle importer. Keeping it non-executable
-- prevents legacy VIN/work/Parts mutation while preserving its old receipts for
-- projections and immutable-source conflict checks.
revoke all on function public.import_pdc_authenticated_vehicle_email(
  text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb
) from public,anon,authenticated,service_role;

create or replace function public.import_pdc_authenticated_backend_batches(
  p_idempotency_key text,
  p_source_hash text,
  p_evidence_hash text,
  p_source_uid text,
  p_sender_address text,
  p_authentication jsonb,
  p_source_received_at timestamptz,
  p_subject text,
  p_stock_numbers jsonb
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
  v_stocks text[];
  v_backend_ids uuid[]:='{}'::uuid[];
  v_vehicle_ids uuid[]:='{}'::uuid[];
  v_candidate_backend_ids uuid[];
  v_candidate_vehicle_ids uuid[];
  v_vin_vehicle_ids uuid[];
  v_record public.navision_backend_records%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_activation public.navision_board_activations%rowtype;
  v_existing public.pdc_authenticated_email_batch_receipts%rowtype;
  v_request_hash text;
  v_response jsonb;
  v_stock text;
  v_vin text;
  v_vehicle_id uuid;
  v_location text;
  v_customer text;
  v_description text;
  v_before jsonb;
  v_after jsonb;
  v_index integer;
  v_created integer:=0;
  v_updated integer:=0;
begin
  if v_actor_id is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select r.role::text into v_role
  from public.pdc_user_roles r
  where r.email=v_actor_email and (r.auth_user_id is null or r.auth_user_id=v_actor_id)
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

  if v_key!~'^pdc-email-batch-[A-Za-z0-9_-]{16,160}$'
     or v_source_hash!~'^[a-f0-9]{64}$' or v_evidence_hash!~'^[a-f0-9]{64}$'
     or length(v_source_uid) not between 1 and 100
     or v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
     or split_part(v_sender,'@',2) not in ('broometoyota.com.au','pmgwa.com.au')
     or jsonb_typeof(v_auth) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_auth) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2)
     or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not (v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb)
     or length(v_subject) not between 1 and 300
     or jsonb_typeof(coalesce(p_stock_numbers,'null'::jsonb)) is distinct from 'array'
     or jsonb_array_length(p_stock_numbers) not between 1 and 20
     or exists(select 1 from jsonb_array_elements(p_stock_numbers) e where jsonb_typeof(e.value)<>'string') then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  select array_agg(stock order by stock) into v_stocks
  from (select public.normalize_vehicle_stock_number(value) stock from jsonb_array_elements_text(p_stock_numbers)) normalized;
  if exists(select 1 from unnest(v_stocks) stock where not public.is_real_vehicle_stock_number(stock))
     or cardinality(v_stocks)<>(select count(distinct stock) from unnest(v_stocks) stock) then
    return public.navision_backend_response(false,'invalid_stock_set');
  end if;
  if p_source_received_at is null
     or p_source_received_at>clock_timestamp()+interval '5 minutes'
     or p_source_received_at<clock_timestamp()-interval '30 days'
     or v_subject~*'\m(cancelled|canceled|cancellation)\M' then
    return public.navision_backend_response(false,'evidence_expired_or_cancelled');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-email-source:'||v_source_hash,0));
  perform 1 from public.pdc_email_source_claims c
  where c.source_hash=v_source_hash and c.contract_name='pdc_ai_intake_063'
  for update;
  if not found then
    return public.navision_backend_response(false,'source_not_observed');
  end if;
  if exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.source_hash=v_source_hash) then
    return public.navision_backend_response(false,'source_already_consumed');
  end if;

  v_request_hash:=encode(extensions.digest(jsonb_build_object(
    'contract_version',2,'actor_id',v_actor_id,'idempotency_key',v_key,
    'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'source_uid',v_source_uid,
    'sender_address',v_sender,'authentication',v_auth,'source_received_at',p_source_received_at,
    'subject',v_subject,'normalized_stocks',v_stocks
  )::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-email-batch-receipt:'||v_actor_id::text||':'||v_key,0));
  select * into v_existing from public.pdc_authenticated_email_batch_receipts
  where actor_id=v_actor_id and idempotency_key=v_key for update;
  if found then
    if v_existing.request_hash<>v_request_hash then
      return public.navision_backend_response(false,'idempotency_conflict');
    end if;
    return v_existing.response;
  end if;
  select * into v_existing from public.pdc_authenticated_email_batch_receipts
  where source_hash=v_source_hash for update;
  if found then
    if v_existing.request_hash<>v_request_hash then
      return public.navision_backend_response(false,'source_reuse_conflict');
    end if;
    return v_existing.response;
  end if;

  -- Validate the complete fan-out before the first write. Stock is the only
  -- positive identity authority. VIN is checked solely as a conflict guard.
  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  lock table public.vehicles,public.vehicle_aliases in share row exclusive mode;
  for v_index in 1..cardinality(v_stocks) loop
    v_stock:=v_stocks[v_index];
    select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_candidate_backend_ids
    from public.navision_backend_records r
    where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
      and r.is_current and r.record_status='current'
      and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
      and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    if cardinality(v_candidate_backend_ids)=0 then
      return public.navision_backend_response(false,'backend_stock_not_found',jsonb_build_object('stock_index',v_index));
    elsif cardinality(v_candidate_backend_ids)<>1 then
      return public.navision_backend_response(false,'backend_stock_ambiguous',jsonb_build_object('stock_index',v_index,'match_count',cardinality(v_candidate_backend_ids)));
    end if;
    v_backend_ids:=array_append(v_backend_ids,v_candidate_backend_ids[1]);
    select * into v_record from public.navision_backend_records where id=v_candidate_backend_ids[1] for update;
    v_location:=public.navision_operational_location(v_record.normalized_data);
    if v_location='Completed' then
      return public.navision_backend_response(false,'protected_backend_lifecycle',jsonb_build_object('stock_index',v_index));
    end if;

    select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into v_candidate_vehicle_ids
    from (
      select v.id vehicle_id from public.vehicles v where v.stock_number_normalized=v_stock
      union all
      select a.vehicle_id from public.vehicle_aliases a
      where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock
    ) candidates;
    if cardinality(v_candidate_vehicle_ids)>1 then
      return public.navision_backend_response(false,'operational_identity_conflict',jsonb_build_object('stock_index',v_index,'match_count',cardinality(v_candidate_vehicle_ids)));
    end if;
    v_vehicle_id:=case when cardinality(v_candidate_vehicle_ids)=1 then v_candidate_vehicle_ids[1] else null end;
    if v_vehicle_id is not null and exists(
      select 1 from public.vehicles v where v.id=v_vehicle_id and (
        v.lifecycle_state<>'active' or v.deleted_at is not null or v.rft_collected_at is not null
        or upper(btrim(coalesce(v.current_location,'')))='COMPLETED'
        or (not v.visible_on_board and upper(btrim(coalesce(v.current_location,''))) in ('PMB','PIT','QC','RFT'))
      )
    ) then
      return public.navision_backend_response(false,'protected_existing_lifecycle',jsonb_build_object('stock_index',v_index));
    end if;

    v_vin:=case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin')
      then nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),'') else null end;
    if v_vin is not null then
      select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[])
      into v_vin_vehicle_ids
      from (
        select v.id as vehicle_id
        from public.vehicles v
        where v.vin_normalized=v_vin
        union all
        select a.vehicle_id
        from public.vehicle_aliases a
        where a.active
          and a.alias_type_normalized='vin'
          and a.normalized_alias_value=v_vin
      ) vin_candidates;
      if exists(select 1 from unnest(v_vin_vehicle_ids) id where v_vehicle_id is null or id<>v_vehicle_id) then
        return public.navision_backend_response(false,'vin_conflict_non_authoritative',jsonb_build_object('stock_index',v_index));
      end if;
    end if;

    select * into v_activation from public.navision_board_activations
    where backend_record_id=v_record.id for update;
    if found and (
      not v_activation.active or v_activation.completed_at is not null
      or public.normalize_vehicle_stock_number(v_activation.activated_stock_number)<>v_stock
      or (v_activation.canonical_vehicle_id is not null and (v_vehicle_id is null or v_activation.canonical_vehicle_id<>v_vehicle_id))
    ) then
      return public.navision_backend_response(false,'protected_or_conflicting_activation',jsonb_build_object('stock_index',v_index));
    end if;
    if v_record.canonical_vehicle_id is not null and (v_vehicle_id is null or v_record.canonical_vehicle_id<>v_vehicle_id) then
      return public.navision_backend_response(false,'backend_canonical_identity_conflict',jsonb_build_object('stock_index',v_index));
    end if;
    if exists(
      select 1 from public.vehicles v
      where v.source_system_normalized='microsoft_navision'
        and v.source_record_id_normalized=public.normalize_vehicle_source_identifier(v_record.id::text)
        and (v_vehicle_id is null or v.id<>v_vehicle_id)
    ) then
      return public.navision_backend_response(false,'backend_source_identity_conflict',jsonb_build_object('stock_index',v_index));
    end if;
    v_vehicle_ids:=array_append(v_vehicle_ids,v_vehicle_id);
  end loop;

  for v_index in 1..cardinality(v_stocks) loop
    v_stock:=v_stocks[v_index];
    v_vehicle_id:=v_vehicle_ids[v_index];
    select * into v_record from public.navision_backend_records where id=v_backend_ids[v_index] for update;
    v_vin:=case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin')
      then nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),'') else null end;
    v_location:=public.navision_operational_location(v_record.normalized_data);
    v_customer:=coalesce(nullif(btrim(v_record.normalized_data->>'client'),''),nullif(btrim(v_record.normalized_data->>'customerSurname'),''),nullif(btrim(v_record.normalized_data->>'dealerCustomerName'),''),nullif(btrim(v_record.normalized_data->>'toyotaCustomer'),''));
    v_description:=coalesce(nullif(btrim(v_record.normalized_data->>'modelDescription'),''),nullif(btrim(v_record.normalized_data->>'toyotaVehicle'),''),nullif(btrim(v_record.normalized_data->>'vehicle'),''));
    if v_vehicle_id is null then
      v_vehicle_id:=extensions.uuid_generate_v5(
        'b58b5f75-d004-5a76-b9aa-48c801b4ad7d'::uuid,
        'PDC-EMAIL-BATCH:'||v_record.dealer_code||':'||v_stock||':'||v_record.id::text
      );
      insert into public.vehicles(
        id,permanent_vehicle_id,stock_number,vin,toyota_order_number,job_card_number,
        customer_name,vehicle_description,model,registration,lifecycle_state,visible_on_board,
        current_location,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by
      ) values(
        v_vehicle_id,'PDC-EML-'||upper(replace(substr(v_vehicle_id::text,1,24),'-','')),
        v_record.normalized_data->>'batch',v_vin,
        nullif(btrim(v_record.normalized_data->>'order'),''),nullif(btrim(v_record.normalized_data->>'jobCardNumber'),''),
        v_customer,v_description,v_description,nullif(upper(btrim(v_record.normalized_data->>'registration')),''),
        'active',true,v_location,'microsoft_navision',v_record.dealer_code,v_record.id::text,
        jsonb_build_object('authority','pdc_authenticated_email_backend_batch_132','backend_record_id',v_record.id,
          'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'stock_only_authority',true,'vin_identity_authority',false),
        v_actor_id,v_actor_id
      ) returning * into v_vehicle;
      v_created:=v_created+1;
      v_before:=null;
    else
      select * into v_vehicle from public.vehicles where id=v_vehicle_id for update;
      v_before:=to_jsonb(v_vehicle);
      if not v_vehicle.visible_on_board then
        update public.vehicles set visible_on_board=true,version=version+1,updated_by=v_actor_id,
          source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
            'email_batch_match_contract','pdc_authenticated_email_backend_batch_132',
            'email_batch_source_hash',v_source_hash,'email_batch_evidence_hash',v_evidence_hash,
            'stock_only_authority',true,'vin_identity_authority',false)
        where id=v_vehicle_id returning * into v_vehicle;
        v_updated:=v_updated+1;
      end if;
    end if;
    v_vehicle_ids[v_index]:=v_vehicle_id;
    v_after:=to_jsonb(v_vehicle);
    if v_before is null or v_before is distinct from v_after then
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values(case when v_before is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
        'vehicles',v_vehicle_id,v_vehicle_id,v_actor_id,v_actor_email,v_before,v_after,
        jsonb_build_object('source','pdc_authenticated_email_backend_batch_132','backend_record_id',v_record.id,
          'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'stock_only_authority',true,
          'vin_identity_authority',false,'booking_created',false));
    end if;
    if not exists(
      select 1
      from public.vehicles v
      where v.id=v_vehicle_id
        and v.lifecycle_state='active'
        and v.deleted_at is null
        and v.visible_on_board
        and (
          v.stock_number_normalized=v_stock
          or exists(
            select 1 from public.vehicle_aliases a
            where a.vehicle_id=v.id
              and a.active
              and a.alias_type_normalized='stock_number'
              and a.normalized_alias_value=v_stock
          )
        )
    ) then
      raise exception using errcode='P0001',message='PDC_EMAIL_132_POSTCONDITION_FAILED';
    end if;
  end loop;

  v_response:=public.navision_backend_response(true,'backend_batches_imported',jsonb_build_object(
    'requested_count',cardinality(v_stocks),'imported_count',cardinality(v_vehicle_ids),
    'created_count',v_created,'updated_count',v_updated,'booking_created',false,
    'vin_required',false,'identity_authority','unique_current_backend_stock'));
  insert into public.pdc_authenticated_email_batch_receipts(
    actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,
    source_received_at,normalized_stocks,backend_record_ids,vehicle_ids,response
  ) values(v_actor_id,v_key,v_request_hash,v_source_hash,v_evidence_hash,v_source_uid,v_sender,
    p_source_received_at,v_stocks,v_backend_ids,v_vehicle_ids,v_response);
  update public.pdc_email_vehicle_revision
  set revision=revision+1,updated_at=clock_timestamp()
  where singleton;
  return v_response;
exception when unique_violation then
  raise exception using errcode='P0001',message='PDC_EMAIL_132_IDENTITY_OR_RECEIPT_CONFLICT';
end
$import$;

revoke all on function public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamptz,text,jsonb)
from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamptz,text,jsonb)
to authenticated;

-- Vehicle Locations consumes this projection. Include both the original
-- one-vehicle receipt contract and the stock-fan-out receipt contract.
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
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
    'vin',v.vin,'job_card_number',v.job_card_number,'customer_name',v.customer_name,
    'vehicle_description',v.vehicle_description,'salesperson_reference',v.salesperson_reference,
    'registration',v.registration,'eta_to_kewdale',v.eta_to_kewdale,
    'current_location',v.current_location,'visible_on_board',v.visible_on_board,
    'source_system',v.source_system,'source_record_id',v.source_record_id,'updated_at',v.updated_at,
    'work_items',coalesce((select jsonb_agg(jsonb_build_object(
      'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,
      'completed_at',wi.completed_at,'completed_by',wi.completed_by) order by wi.work_key)
      from public.vehicle_work_items wi where wi.vehicle_id=v.id),'[]'::jsonb),
    'parts_required',coalesce((select pu.parts_required from public.vehicle_parts_updates pu
      where pu.vehicle_id=v.id order by pu.updated_at desc,pu.id desc limit 1),false),
    'parts_completed',coalesce((select wi.completed from public.vehicle_work_items wi
      where wi.vehicle_id=v.id and wi.work_key='PARTS'),false)
  ) order by coalesce(v.stock_number,v.vin,v.permanent_vehicle_id),v.id),'[]'::jsonb)
  into v_rows
  from public.vehicles v
  where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    and (
      exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v.id)
      or exists(select 1 from public.pdc_authenticated_email_batch_receipts r where v.id=any(r.vehicle_ids))
    );
  return public.navision_backend_response(true,'ok',jsonb_build_object(
    'revision',coalesce(v_revision,1),'vehicles',v_rows));
end
$snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('132','stock_only_authenticated_email_batch_fanout',array[
  'stock-only direct canonical vehicle import without Navision activation/VIN reconciliation',
  'complete prevalidation, protected lifecycle, aggregate idempotency receipt, Vehicle Locations projection',
  'single-consumption advisory lock and cross-contract receipt guards; legacy one-vehicle importer revoked'
]);

comment on function public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamptz,text,jsonb) is
  'Staging-only: imports one or more exact current Back End stock matches directly into canonical Vehicle Locations; VIN is conflict-only, never identity authority.';
commit;
