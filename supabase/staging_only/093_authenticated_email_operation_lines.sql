-- Staging-only migration 093: bounded authenticated job-card operation evidence.
-- Adds typed OP-numbered lines to the existing authenticated-email vehicle path.
-- It may add canonical required-work rows, but never completes work or creates bookings.
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
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.vehicle_parts_updates') is null
     or to_regclass('public.pdc_email_vehicle_revision') is null then
    raise exception 'PDC_MIGRATION_093_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create table if not exists public.pdc_authenticated_email_operation_lines (
  operation_line_id uuid primary key default gen_random_uuid(),
  import_receipt_id uuid not null references public.pdc_authenticated_email_import_receipts(receipt_id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  source_hash text not null check(source_hash ~ '^[a-f0-9]{64}$'),
  source_uid text not null,
  operation_no text not null check(operation_no ~ '^OP([1-9]|[1-9][0-9]{1,2})$'),
  work_key text not null check(work_key in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS')),
  description text not null check(length(description) between 1 and 180 and description=btrim(description)),
  operation_fingerprint text not null check(operation_fingerprint ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  unique(source_hash,operation_no),
  unique(source_hash,operation_fingerprint)
);
alter table public.pdc_authenticated_email_operation_lines enable row level security;
revoke all on table public.pdc_authenticated_email_operation_lines from public,anon,authenticated;

create or replace function public.import_pdc_authenticated_email_operations(
  p_source_hash text,
  p_source_uid text,
  p_operation_lines jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $fn$
declare
  v_actor_id uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));
  v_source_uid text:=btrim(coalesce(p_source_uid,''));
  v_operations jsonb:=coalesce(p_operation_lines,'[]'::jsonb);
  v_receipt public.pdc_authenticated_email_import_receipts%rowtype;
  v_item jsonb;
  v_operation_no text;
  v_work_key text;
  v_description text;
  v_fingerprint text;
  v_line_id uuid;
  v_work_before public.vehicle_work_items%rowtype;
  v_work_after public.vehicle_work_items%rowtype;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
  v_lines_added integer:=0;
  v_work_added integer:=0;
  v_parts_added integer:=0;
  v_resulting_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() or v_actor_id is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_user_roles r
   where r.email=v_actor_email and (r.auth_user_id is null or r.auth_user_id=v_actor_id)
     and r.role='viewer' and r.active and r.account_status='approved'
   for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;

  if v_source_hash !~ '^[a-f0-9]{64}$'
     or length(v_source_uid) not between 1 and 100
     or jsonb_typeof(v_operations) is distinct from 'array'
     or jsonb_array_length(v_operations)>50
     or exists(
       select 1 from jsonb_array_elements(v_operations) x
       where jsonb_typeof(x)<>'object'
          or (select array_agg(k order by k) from jsonb_object_keys(x) k)
             is distinct from array['description','operation_no','work_key']::text[]
          or coalesce(x->>'operation_no','') !~ '^OP([1-9]|[1-9][0-9]{1,2})$'
          or coalesce(x->>'work_key','') not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS')
          or length(coalesce(x->>'description','')) not between 1 and 180
          or x->>'description' is distinct from btrim(x->>'description')
          or x->>'description' ~ '[[:cntrl:]]'
     )
     or (select count(*) from jsonb_array_elements(v_operations))
        <> (select count(distinct x->>'operation_no') from jsonb_array_elements(v_operations) x) then
    return public.navision_backend_response(false,'invalid_operation_lines');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-email-operation-lines:'||v_source_hash,0));
  select * into v_receipt from public.pdc_authenticated_email_import_receipts
   where actor_id=v_actor_id and source_hash=v_source_hash for update;
  if not found or v_receipt.source_uid<>v_source_uid then
    return public.navision_backend_response(false,'source_receipt_not_found');
  end if;
  perform 1 from public.vehicles v
   where v.id=v_receipt.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null for update;
  if not found then return public.navision_backend_response(false,'operational_vehicle_inactive'); end if;

  for v_item in select value from jsonb_array_elements(v_operations) loop
    v_operation_no:=v_item->>'operation_no';
    v_work_key:=v_item->>'work_key';
    v_description:=v_item->>'description';
    v_fingerprint:=encode(extensions.digest(jsonb_build_object(
      'source_hash',v_source_hash,'operation_no',v_operation_no,
      'work_key',v_work_key,'description',v_description
    )::text,'sha256'),'hex');

    insert into public.pdc_authenticated_email_operation_lines(
      import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint
    ) values(
      v_receipt.receipt_id,v_receipt.vehicle_id,v_source_hash,v_source_uid,
      v_operation_no,v_work_key,v_description,v_fingerprint
    ) on conflict(source_hash,operation_fingerprint) do nothing
    returning operation_line_id into v_line_id;
    if found then
      v_lines_added:=v_lines_added+1;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values('insert','pdc_authenticated_email_operation_lines',v_line_id,v_receipt.vehicle_id,v_actor_id,v_actor_email,null,
        jsonb_build_object('operation_no',v_operation_no,'work_key',v_work_key,'description',v_description),
        jsonb_build_object('source','pdc_authenticated_email_operations_093','source_hash',v_source_hash,'no_booking',true));
    end if;

    select * into v_work_before from public.vehicle_work_items
     where vehicle_id=v_receipt.vehicle_id and work_key=v_work_key for update;
    insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
    values(v_receipt.vehicle_id,v_work_key,true,false,null,null,null,clock_timestamp())
    on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp()
      where not public.vehicle_work_items.completed and not public.vehicle_work_items.required
    returning * into v_work_after;
    if found and (v_work_before.id is null or (not v_work_before.completed and not v_work_before.required)) then
      v_work_added:=v_work_added+1;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values(case when v_work_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
        'vehicle_work_items',v_work_after.id,v_receipt.vehicle_id,v_actor_id,v_actor_email,
        case when v_work_before.id is null then null else to_jsonb(v_work_before) end,to_jsonb(v_work_after),
        jsonb_build_object('source','pdc_authenticated_email_operations_093','source_hash',v_source_hash,
          'operation_no',v_operation_no,'required_work',v_work_key,'completed_work_reopened',false,'no_booking',true));
    end if;
    v_work_before:=null; v_work_after:=null;
  end loop;

  if exists(select 1 from jsonb_array_elements(v_operations) x where x->>'work_key'='PARTS') then
    select * into v_parts_before from public.vehicle_parts_updates
     where vehicle_id=v_receipt.vehicle_id order by updated_at desc,id desc limit 1 for update;
    if found then
      if not v_parts_before.parts_required then
        update public.vehicle_parts_updates set parts_required=true,updated_by=v_actor_id,updated_at=clock_timestamp()
         where id=v_parts_before.id returning * into v_parts_after;
      else v_parts_after:=v_parts_before;
      end if;
    else
      insert into public.vehicle_parts_updates(vehicle_id,parts_required,updated_by)
      values(v_receipt.vehicle_id,true,v_actor_id) returning * into v_parts_after;
    end if;
    if v_parts_before.id is null or not v_parts_before.parts_required then
      v_parts_added:=1;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values(case when v_parts_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
        'vehicle_parts_updates',v_parts_after.id,v_receipt.vehicle_id,v_actor_id,v_actor_email,
        case when v_parts_before.id is null then null else to_jsonb(v_parts_before) end,to_jsonb(v_parts_after),
        jsonb_build_object('source','pdc_authenticated_email_operations_093','source_hash',v_source_hash,
          'parts_required',true,'completed_work_reopened',false,'no_booking',true));
    end if;
  end if;

  select revision into v_resulting_revision from public.pdc_email_vehicle_revision where singleton;

  return public.navision_backend_response(true,'operation_lines_imported',jsonb_build_object(
    'vehicle_id',v_receipt.vehicle_id,'source_hash',v_source_hash,
    'operation_lines_received',jsonb_array_length(v_operations),'operation_lines_added',v_lines_added,
    'required_work_added',v_work_added,'parts_required_added',v_parts_added,
    'resulting_revision',v_resulting_revision,'booking_created',false));
end;
$fn$;
revoke all on function public.import_pdc_authenticated_email_operations(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.import_pdc_authenticated_email_operations(text,text,jsonb) to authenticated;

create trigger pdc_email_vehicle_revision_operation_lines
after insert on public.pdc_authenticated_email_operation_lines
for each statement execute function public.bump_pdc_email_vehicle_revision();

create or replace function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb
language plpgsql
stable security definer
set search_path=pg_catalog,public
as $snapshot$
declare v_role text; v_revision bigint; v_rows jsonb;
begin
  v_role:=public.current_pdc_user_role()::text;
  if v_role not in ('viewer','operator','importer','administrator') then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select revision into v_revision from public.pdc_email_vehicle_revision where singleton;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'version',v.version,'permanent_vehicle_id',v.permanent_vehicle_id,
    'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,
    'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,
    'salesperson_reference',v.salesperson_reference,'registration',v.registration,
    'eta_to_kewdale',v.eta_to_kewdale,'current_location',v.current_location,
    'visible_on_board',v.visible_on_board,'source_system',v.source_system,
    'source_record_id',v.source_record_id,'updated_at',v.updated_at,
    'work_items',coalesce((select jsonb_agg(jsonb_build_object(
      'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,
      'completed_at',wi.completed_at,'completed_by',wi.completed_by) order by wi.work_key)
      from public.vehicle_work_items wi where wi.vehicle_id=v.id),'[]'::jsonb),
    'operation_lines',coalesce((select jsonb_agg(jsonb_build_object(
      'operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,
      'source_uid',ol.source_uid,'created_at',ol.created_at)
      order by ol.created_at,substring(ol.operation_no from 3)::integer,ol.operation_line_id)
      from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=v.id),'[]'::jsonb),
    'parts_required',coalesce((select pu.parts_required from public.vehicle_parts_updates pu
      where pu.vehicle_id=v.id order by pu.updated_at desc,pu.id desc limit 1),false),
    'parts_completed',coalesce((select wi.completed from public.vehicle_work_items wi
      where wi.vehicle_id=v.id and wi.work_key='PARTS'),false)
  ) order by coalesce(v.stock_number,v.vin,v.permanent_vehicle_id),v.id),'[]'::jsonb)
  into v_rows from public.vehicles v
  where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    and exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v.id);
  return public.navision_backend_response(true,'ok',jsonb_build_object(
    'revision',coalesce(v_revision,1),'vehicles',v_rows));
end;
$snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public,anon,authenticated;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;

comment on function public.import_pdc_authenticated_email_operations(text,text,jsonb) is
  'Staging-only enrolled-Viewer typed enrichment of an existing authenticated-email receipt with bounded OP-numbered job-card evidence and add-only canonical work; never books or completes work.';

commit;
