-- Staging-only migration 099: bounded authenticated PD accessories-table work lines.
-- Adds only immutable line evidence and missing required-work flags; never books or completes work.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.pdc_authenticated_email_import_receipts') is null
     or to_regclass('public.pdc_monitor_stage_activation_writers') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') is null then
    raise exception 'PDC_MIGRATION_099_STAGING_OR_DEPENDENCY_MISMATCH';
  end if;
end;
$guard$;

alter table public.pdc_authenticated_email_operation_lines
  drop constraint if exists pdc_authenticated_email_operation_lines_operation_no_check;
alter table public.pdc_authenticated_email_operation_lines
  add constraint pdc_authenticated_email_operation_lines_operation_no_check
  check(operation_no ~ '^(OP([1-9]|[1-9][0-9]{1,2})|PD[0-9]{3}-[A-F0-9]{8})$');

create or replace function public.import_pdc_authenticated_email_pd_lines(
  p_source_hash text,
  p_source_uid text,
  p_operation_lines jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $pd$
declare
  v_actor_id uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));
  v_source_uid text:=btrim(coalesce(p_source_uid,''));
  v_operations jsonb:=coalesce(p_operation_lines,'[]'::jsonb);
  v_receipt public.pdc_authenticated_email_import_receipts%rowtype;
  v_item jsonb;
  v_line_key text;
  v_work_key text;
  v_description text;
  v_fingerprint text;
  v_line_id uuid;
  v_work_before public.vehicle_work_items%rowtype;
  v_work_after public.vehicle_work_items%rowtype;
  v_existing integer:=0;
  v_conflicting integer:=0;
  v_lines_added integer:=0;
  v_work_added integer:=0;
  v_resulting_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() or v_actor_id is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_user_roles r
   where r.email=v_actor_email and (r.auth_user_id is null or r.auth_user_id=v_actor_id)
     and r.role='viewer' and r.active and r.account_status='approved' for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;

  if v_source_hash !~ '^[a-f0-9]{64}$'
     or length(v_source_uid) not between 1 and 100
     or jsonb_typeof(v_operations) is distinct from 'array'
     or jsonb_array_length(v_operations) not between 1 and 50
     or exists(
       select 1 from jsonb_array_elements(v_operations) x
       where jsonb_typeof(x)<>'object'
          or (select array_agg(k order by k) from jsonb_object_keys(x) k)
             is distinct from array['description','operation_no','work_key']::text[]
          or coalesce(x->>'operation_no','') !~ '^PD[0-9]{3}-[A-F0-9]{8}$'
          or coalesce(x->>'work_key','') not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection')
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

  select count(*) into v_conflicting
  from jsonb_array_elements(v_operations) x
  join public.pdc_authenticated_email_operation_lines ol
    on ol.source_hash=v_source_hash and ol.operation_no=x->>'operation_no'
  where ol.operation_fingerprint<>encode(extensions.digest(jsonb_build_object(
    'source_hash',v_source_hash,'operation_no',x->>'operation_no',
    'work_key',x->>'work_key','description',x->>'description'
  )::text,'sha256'),'hex');
  if v_conflicting>0 then
    select revision into v_resulting_revision from public.pdc_email_vehicle_revision where singleton;
    return public.navision_backend_response(false,'operation_identity_conflict',jsonb_build_object(
      'vehicle_id',v_receipt.vehicle_id,'source_hash',v_source_hash,
      'conflicting_operation_lines',v_conflicting,'resulting_revision',v_resulting_revision,
      'booking_created',false,'completed_work_reopened',false));
  end if;

  select count(*) into v_existing
  from jsonb_array_elements(v_operations) x
  where exists(
    select 1 from public.pdc_authenticated_email_operation_lines ol
    where ol.source_hash=v_source_hash and ol.operation_no=x->>'operation_no'
      and ol.operation_fingerprint=encode(extensions.digest(jsonb_build_object(
        'source_hash',v_source_hash,'operation_no',x->>'operation_no',
        'work_key',x->>'work_key','description',x->>'description'
      )::text,'sha256'),'hex')
  );
  if v_existing=jsonb_array_length(v_operations) then
    select revision into v_resulting_revision from public.pdc_email_vehicle_revision where singleton;
    return public.navision_backend_response(true,'pd_lines_already_imported',jsonb_build_object(
      'vehicle_id',v_receipt.vehicle_id,'source_hash',v_source_hash,
      'operation_lines_received',jsonb_array_length(v_operations),'operation_lines_added',0,
      'required_work_added',0,'resulting_revision',v_resulting_revision,'booking_created',false));
  end if;

  for v_item in select value from jsonb_array_elements(v_operations) loop
    v_line_key:=v_item->>'operation_no';
    v_work_key:=v_item->>'work_key';
    v_description:=v_item->>'description';
    v_fingerprint:=encode(extensions.digest(jsonb_build_object(
      'source_hash',v_source_hash,'operation_no',v_line_key,
      'work_key',v_work_key,'description',v_description
    )::text,'sha256'),'hex');
    v_line_id:=null;
    insert into public.pdc_authenticated_email_operation_lines(
      import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint
    ) values(v_receipt.receipt_id,v_receipt.vehicle_id,v_source_hash,v_source_uid,
      v_line_key,v_work_key,v_description,v_fingerprint)
    on conflict(source_hash,operation_fingerprint) do nothing
    returning operation_line_id into v_line_id;
    if v_line_id is not null then
      v_lines_added:=v_lines_added+1;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values('insert','pdc_authenticated_email_operation_lines',v_line_id,v_receipt.vehicle_id,v_actor_id,v_actor_email,null,
        jsonb_build_object('operation_no',v_line_key,'work_key',v_work_key,'description',v_description),
        jsonb_build_object('source','pdc_authenticated_email_pd_lines_099','source_hash',v_source_hash,'no_booking',true));
    end if;

    v_work_before:=null; v_work_after:=null;
    select * into v_work_before from public.vehicle_work_items
     where vehicle_id=v_receipt.vehicle_id and work_key=v_work_key for update;
    insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
    values(v_receipt.vehicle_id,v_work_key,true,false,null,null,null,clock_timestamp())
    on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp()
      where not public.vehicle_work_items.completed and not public.vehicle_work_items.required
    returning * into v_work_after;
    if v_work_after.id is not null and (v_work_before.id is null or (not v_work_before.completed and not v_work_before.required)) then
      v_work_added:=v_work_added+1;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values(case when v_work_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
        'vehicle_work_items',v_work_after.id,v_receipt.vehicle_id,v_actor_id,v_actor_email,
        case when v_work_before.id is null then null else to_jsonb(v_work_before) end,to_jsonb(v_work_after),
        jsonb_build_object('source','pdc_authenticated_email_pd_lines_099','source_hash',v_source_hash,
          'operation_no',v_line_key,'required_work',v_work_key,'completed_work_reopened',false,'no_booking',true));
    end if;
  end loop;

  select revision into v_resulting_revision from public.pdc_email_vehicle_revision where singleton;
  return public.navision_backend_response(true,'pd_lines_imported',jsonb_build_object(
    'vehicle_id',v_receipt.vehicle_id,'source_hash',v_source_hash,
    'operation_lines_received',jsonb_array_length(v_operations),'operation_lines_added',v_lines_added,
    'required_work_added',v_work_added,'resulting_revision',v_resulting_revision,'booking_created',false));
end;
$pd$;
revoke all on function public.import_pdc_authenticated_email_pd_lines(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.import_pdc_authenticated_email_pd_lines(text,text,jsonb) to authenticated;
comment on function public.import_pdc_authenticated_email_pd_lines(text,text,jsonb) is
  'Staging-only enrolled-Viewer typed importer for bounded authenticated PD accessories-table workshop lines; never books or completes work.';

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
      order by case when ol.operation_no like 'OP%' then 0 else 1 end,
        case when ol.operation_no like 'OP%' then substring(ol.operation_no from 3)::integer
             else substring(ol.operation_no from 3 for 3)::integer end,
        ol.created_at,ol.operation_line_id)
      from (select line.* from public.pdc_authenticated_email_operation_lines line
        where line.vehicle_id=v.id order by line.created_at desc,line.operation_line_id desc limit 50) ol),'[]'::jsonb),
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
comment on function public.get_pdc_email_vehicle_location_snapshot() is
  'Staging authenticated-email vehicle snapshot including the latest 50 bounded typed PD/job-card lines; read-only and no booking authority.';

comment on table public.pdc_authenticated_email_operation_lines is
  'Immutable authenticated email work-line evidence: source OP numbers or deterministic PD accessories-table row references.';
commit;
