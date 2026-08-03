-- Staging-only migration 130: activate every exact current Back End batch named
-- by one provider-authenticated email. No mailbox access or attachment parsing
-- occurs here; the enrolled monitor submits retained source/authentication proof.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception using errcode='P0001',message='PDC_EMAIL_130_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='129' and name='bulk_stock_only_vehicle_privacy_guard') then
    raise exception using errcode='P0001',message='PDC_EMAIL_130_PREDECESSOR_129_REQUIRED';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='130') then
    raise exception using errcode='P0001',message='PDC_EMAIL_130_VERSION_CONFLICT';
  end if;
  if to_regclass('public.pdc_email_source_claims') is null
     or to_regclass('public.pdc_monitor_stage_activation_writers') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_board_activations') is null
     or to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') is null then
    raise exception using errcode='P0001',message='PDC_EMAIL_130_DEPENDENCY_MISSING';
  end if;
end
$guard$;

create table public.pdc_authenticated_email_batch_receipts (
  receipt_id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  idempotency_key text not null,
  request_hash text not null check(request_hash~'^[a-f0-9]{64}$'),
  source_hash text not null unique check(source_hash~'^[a-f0-9]{64}$'),
  evidence_hash text not null check(evidence_hash~'^[a-f0-9]{64}$'),
  source_uid text not null,
  sender_address text not null,
  source_received_at timestamptz not null,
  normalized_stocks text[] not null check(cardinality(normalized_stocks) between 1 and 20),
  backend_record_ids uuid[] not null,
  vehicle_ids uuid[] not null,
  response jsonb not null check(jsonb_typeof(response)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(actor_id,idempotency_key),
  check(cardinality(normalized_stocks)=cardinality(backend_record_ids)),
  check(cardinality(normalized_stocks)=cardinality(vehicle_ids))
);
alter table public.pdc_authenticated_email_batch_receipts enable row level security;
revoke all on table public.pdc_authenticated_email_batch_receipts from public,anon,authenticated,service_role;

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
  v_record public.navision_backend_records%rowtype;
  v_existing public.pdc_authenticated_email_batch_receipts%rowtype;
  v_existing_activation public.navision_board_activations%rowtype;
  v_request_hash text;
  v_response jsonb;
  v_stock text;
  v_vehicle_id uuid;
  v_revision bigint;
  v_index integer;
  v_inserted integer;
begin
  if v_actor_id is null or v_actor_email='' or not exists(
    select 1 from public.pdc_user_roles r
    where r.email=v_actor_email and (r.auth_user_id is null or r.auth_user_id=v_actor_id)
      and r.role='viewer' and r.active and r.account_status='approved'
  ) or not exists(
    select 1 from public.pdc_monitor_stage_activation_writers w
    where w.user_id=v_actor_id and w.active and w.revoked_at is null
  ) then
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
  from (
    select public.normalize_vehicle_stock_number(value) stock
    from jsonb_array_elements_text(p_stock_numbers)
  ) normalized;
  if exists(select 1 from unnest(v_stocks) stock where not public.is_real_vehicle_stock_number(stock))
     or cardinality(v_stocks)<>(select count(distinct stock) from unnest(v_stocks) stock) then
    return public.navision_backend_response(false,'invalid_stock_set');
  end if;
  if p_source_received_at is null
     or p_source_received_at>clock_timestamp()+interval '5 minutes'
     or p_source_received_at<clock_timestamp()-interval '30 days'
     or concat_ws(' ',v_subject)~*'\m(cancelled|canceled|cancellation)\M' then
    return public.navision_backend_response(false,'evidence_expired_or_cancelled');
  end if;
  if not exists(
    select 1 from public.pdc_email_source_claims c
    where c.source_hash=v_source_hash and c.contract_name='pdc_ai_intake_063'
  ) then
    return public.navision_backend_response(false,'source_not_observed');
  end if;

  v_request_hash:=encode(extensions.digest(jsonb_build_object(
    'contract_version',1,'actor_id',v_actor_id,'idempotency_key',v_key,
    'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'source_uid',v_source_uid,
    'sender_address',v_sender,'authentication',v_auth,'source_received_at',p_source_received_at,
    'subject',v_subject,'normalized_stocks',v_stocks
  )::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-email-batch-receipt:'||v_actor_id::text||':'||v_key,0));
  select * into v_existing from public.pdc_authenticated_email_batch_receipts
  where actor_id=v_actor_id and idempotency_key=v_key;
  if found then
    if v_existing.request_hash<>v_request_hash then
      return public.navision_backend_response(false,'idempotency_conflict');
    end if;
    return v_existing.response;
  end if;
  select * into v_existing from public.pdc_authenticated_email_batch_receipts
  where source_hash=v_source_hash;
  if found then
    if v_existing.request_hash<>v_request_hash then
      return public.navision_backend_response(false,'source_reuse_conflict');
    end if;
    return v_existing.response;
  end if;

  -- Validate every requested stock before the first mutation. One ambiguous,
  -- duplicate or protected lifecycle identity blocks the entire email fan-out.
  lock table public.vehicles,public.vehicle_aliases in share row exclusive mode;
  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  select revision into v_revision from public.navision_backend_revision where singleton for update;
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

    select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into v_candidate_vehicle_ids
    from (
      select v.id vehicle_id from public.vehicles v where v.stock_number_normalized=v_stock
      union all
      select a.vehicle_id from public.vehicle_aliases a
      where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock
    ) candidates;
    if cardinality(v_candidate_vehicle_ids)>1 then
      return public.navision_backend_response(false,'operational_identity_conflict',jsonb_build_object('stock_index',v_index,'match_count',cardinality(v_candidate_vehicle_ids)));
    elsif cardinality(v_candidate_vehicle_ids)=1 and exists(
      select 1 from public.vehicles v where v.id=v_candidate_vehicle_ids[1]
        and (v.lifecycle_state<>'active' or v.deleted_at is not null)
    ) then
      return public.navision_backend_response(false,'protected_existing_lifecycle',jsonb_build_object('stock_index',v_index));
    end if;
    select * into v_existing_activation from public.navision_board_activations
    where backend_record_id=v_candidate_backend_ids[1];
    if found and public.normalize_vehicle_stock_number(v_existing_activation.activated_stock_number)<>v_stock then
      return public.navision_backend_response(false,'activation_identity_conflict',jsonb_build_object('stock_index',v_index));
    end if;
  end loop;

  for v_index in 1..cardinality(v_stocks) loop
    v_stock:=v_stocks[v_index];
    select * into v_record from public.navision_backend_records where id=v_backend_ids[v_index] for update;
    insert into public.navision_board_activations(
      backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email
    ) values(v_record.id,'approved_email_build',v_record.normalized_data->>'batch',v_actor_id,v_actor_email)
    on conflict(backend_record_id) do nothing;
    get diagnostics v_inserted=row_count;
    if v_inserted=1 then
      v_revision:=v_revision+1;
      update public.navision_backend_revision set revision=v_revision,updated_at=clock_timestamp() where singleton;
      insert into public.navision_backend_audit(action,backend_record_id,revision,evidence,actor_id,actor_email)
      values('board_activate',v_record.id,v_revision,jsonb_build_object(
        'activation_source','approved_email_build','contract','pdc_authenticated_email_backend_batch_130',
        'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'automated',true,
        'stock_only_authority',true,'vin_required',false),v_actor_id,v_actor_email);
    else
      perform public.reconcile_navision_operational_record(v_record.id,v_actor_id,v_actor_email);
    end if;
    select v.id into v_vehicle_id from public.vehicles v
    where v.deleted_at is null and v.lifecycle_state='active' and v.stock_number_normalized=v_stock;
    if v_vehicle_id is null or not exists(select 1 from public.vehicles v where v.id=v_vehicle_id and v.visible_on_board) then
      raise exception using errcode='P0001',message='PDC_EMAIL_130_POSTCONDITION_FAILED';
    end if;
    v_vehicle_ids:=array_append(v_vehicle_ids,v_vehicle_id);
  end loop;

  v_response:=public.navision_backend_response(true,'backend_batches_imported',jsonb_build_object(
    'requested_count',cardinality(v_stocks),'imported_count',cardinality(v_vehicle_ids),
    'new_activation_count',(select count(*) from unnest(v_backend_ids) id join public.navision_board_activations a on a.backend_record_id=id where a.activated_at>=transaction_timestamp()),
    'booking_created',false,'vin_required',false,'identity_authority','unique_current_backend_stock'));
  insert into public.pdc_authenticated_email_batch_receipts(
    actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,
    source_received_at,normalized_stocks,backend_record_ids,vehicle_ids,response
  ) values(v_actor_id,v_key,v_request_hash,v_source_hash,v_evidence_hash,v_source_uid,v_sender,
    p_source_received_at,v_stocks,v_backend_ids,v_vehicle_ids,v_response);
  return v_response;
exception when unique_violation then
  return public.navision_backend_response(false,'identity_or_receipt_conflict');
end
$import$;

revoke all on function public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamptz,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamptz,text,jsonb) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('130','authenticated_email_backend_batch_fanout',array[
  'staging-only exact Back End batch fan-out import without VIN requirement',
  'provider-authenticated source claim, enrolled monitor writer, lifecycle and idempotency guards'
]);

comment on function public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamptz,text,jsonb) is
  'Staging-only: fan one provider-authenticated email out into exact current Back End batch activations; VIN is not required and no booking is created.';
commit;
