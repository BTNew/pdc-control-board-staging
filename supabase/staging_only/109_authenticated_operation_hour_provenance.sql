-- Staging-only migration 109: typed job-card versus AI estimate provenance.
-- Explicit job-card hours are authoritative; AI estimates remain visibly distinguishable.
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
    raise exception 'PDC_MIGRATION_109_STAGING_OR_DEPENDENCY_MISMATCH';
  end if;
end;
$guard$;

alter table public.pdc_authenticated_email_operation_lines
  add column if not exists estimated_hours numeric(6,2);
alter table public.pdc_authenticated_email_operation_lines
  add column if not exists estimated_hours_source text;
alter table public.pdc_authenticated_email_operation_lines
  drop constraint if exists pdc_authenticated_email_operation_lines_estimated_hours_check;
alter table public.pdc_authenticated_email_operation_lines
  add constraint pdc_authenticated_email_operation_lines_estimated_hours_check
  check(estimated_hours is null or (estimated_hours between 0 and 999.99));
alter table public.pdc_authenticated_email_operation_lines
  drop constraint if exists pdc_authenticated_email_operation_lines_estimated_hours_source_check;
alter table public.pdc_authenticated_email_operation_lines
  add constraint pdc_authenticated_email_operation_lines_estimated_hours_source_check
  check((estimated_hours is null and estimated_hours_source is null)
     or (estimated_hours is not null and (estimated_hours_source is null or estimated_hours_source in ('job_card','ai_estimate'))));

create or replace function public.import_pdc_authenticated_email_operations_with_hours(
  p_source_hash text,
  p_source_uid text,
  p_operation_lines jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $hours$
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
  v_estimated_hours numeric(6,2);
  v_estimated_hours_source text;
  v_fingerprint text;
  v_line_before public.pdc_authenticated_email_operation_lines%rowtype;
  v_line_after public.pdc_authenticated_email_operation_lines%rowtype;
  v_work_before public.vehicle_work_items%rowtype;
  v_work_after public.vehicle_work_items%rowtype;
  v_identity_conflicts integer:=0;
  v_hours_conflicts integer:=0;
  v_lines_added integer:=0;
  v_hours_added integer:=0;
  v_job_card_hours_corrected integer:=0;
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
             is distinct from array['description','estimated_hours','estimated_hours_source','operation_no','work_key']::text[]
          or coalesce(x->>'operation_no','') !~ '^OP([1-9]|[1-9][0-9]{1,2})$'
          or coalesce(x->>'work_key','') not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection')
          or length(coalesce(x->>'description','')) not between 1 and 180
          or x->>'description' is distinct from btrim(x->>'description')
          or x->>'description' ~ '[[:cntrl:]]'
          or jsonb_typeof(x->'estimated_hours') not in ('number','null')
          or (jsonb_typeof(x->'estimated_hours')='number' and coalesce(x->>'estimated_hours_source','') not in ('job_card','ai_estimate'))
          or (jsonb_typeof(x->'estimated_hours')='null' and x->>'estimated_hours_source' is not null)
          or (jsonb_typeof(x->'estimated_hours')='number' and x->>'estimated_hours_source' is null)
          or (jsonb_typeof(x->'estimated_hours')='number' and ((x->>'estimated_hours')::numeric < 0 or (x->>'estimated_hours')::numeric > 999.99))
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

  select count(*) into v_identity_conflicts
  from jsonb_array_elements(v_operations) x
  join public.pdc_authenticated_email_operation_lines ol
    on ol.source_hash=v_source_hash and ol.operation_no=x->>'operation_no'
  where ol.work_key<>x->>'work_key' or ol.description<>x->>'description';
  if v_identity_conflicts>0 then
    select revision into v_resulting_revision from public.pdc_email_vehicle_revision where singleton;
    return public.navision_backend_response(false,'operation_identity_conflict',jsonb_build_object(
      'vehicle_id',v_receipt.vehicle_id,'source_hash',v_source_hash,
      'conflicting_operation_lines',v_identity_conflicts,'resulting_revision',v_resulting_revision,
      'booking_created',false,'completed_work_reopened',false));
  end if;

  select count(*) into v_hours_conflicts
  from jsonb_array_elements(v_operations) x
  join public.pdc_authenticated_email_operation_lines ol
    on ol.source_hash=v_source_hash and ol.operation_no=x->>'operation_no'
  where ol.estimated_hours is not null and jsonb_typeof(x->'estimated_hours')='number'
    and ol.estimated_hours<>(x->>'estimated_hours')::numeric
    and ol.estimated_hours_source='job_card';
  if v_hours_conflicts>0 then
    select revision into v_resulting_revision from public.pdc_email_vehicle_revision where singleton;
    return public.navision_backend_response(false,'estimated_hours_conflict',jsonb_build_object(
      'vehicle_id',v_receipt.vehicle_id,'source_hash',v_source_hash,
      'conflicting_estimated_hours',v_hours_conflicts,'resulting_revision',v_resulting_revision,
      'booking_created',false,'completed_work_reopened',false));
  end if;

  -- Exact replay must return before any INSERT/UPDATE statement. Revision triggers
  -- are statement-level, so even zero-row DML would otherwise create false drift.
  if not exists(
       select 1 from jsonb_array_elements(v_operations) x
       left join public.pdc_authenticated_email_operation_lines ol
         on ol.source_hash=v_source_hash and ol.operation_no=x->>'operation_no'
       where ol.operation_line_id is null
          or (ol.estimated_hours is null and jsonb_typeof(x->'estimated_hours')='number')
          or (x->>'estimated_hours_source'='job_card' and jsonb_typeof(x->'estimated_hours')='number'
              and ol.estimated_hours_source is distinct from 'job_card')
          or (x->>'estimated_hours_source'='ai_estimate' and ol.estimated_hours_source='ai_estimate'
              and ol.estimated_hours is distinct from (x->>'estimated_hours')::numeric)
     )
     and not exists(
       select 1 from (select distinct x->>'work_key' as work_key from jsonb_array_elements(v_operations) x) requested
       left join public.vehicle_work_items wi
         on wi.vehicle_id=v_receipt.vehicle_id and wi.work_key=requested.work_key
       where wi.id is null or (not wi.completed and not wi.required)
     ) then
    select revision into v_resulting_revision from public.pdc_email_vehicle_revision where singleton;
    return public.navision_backend_response(true,'operation_lines_and_hours_already_imported',jsonb_build_object(
      'vehicle_id',v_receipt.vehicle_id,'source_hash',v_source_hash,
      'operation_lines_received',jsonb_array_length(v_operations),'operation_lines_added',0,
      'estimated_hours_added',0,'job_card_hours_corrected',0,'required_work_added',0,'resulting_revision',v_resulting_revision,
      'booking_created',false,'completed_work_reopened',false));
  end if;

  for v_item in select value from jsonb_array_elements(v_operations) loop
    v_operation_no:=v_item->>'operation_no';
    v_work_key:=v_item->>'work_key';
    v_description:=v_item->>'description';
    v_estimated_hours:=case when jsonb_typeof(v_item->'estimated_hours')='number' then (v_item->>'estimated_hours')::numeric else null end;
    v_estimated_hours_source:=v_item->>'estimated_hours_source';
    v_fingerprint:=encode(extensions.digest(jsonb_build_object(
      'source_hash',v_source_hash,'operation_no',v_operation_no,
      'work_key',v_work_key,'description',v_description
    )::text,'sha256'),'hex');

    v_line_before:=null; v_line_after:=null;
    select * into v_line_before from public.pdc_authenticated_email_operation_lines
     where source_hash=v_source_hash and operation_no=v_operation_no for update;
    if v_line_before.operation_line_id is null then
      insert into public.pdc_authenticated_email_operation_lines(
        import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,estimated_hours,estimated_hours_source,operation_fingerprint
      ) values(v_receipt.receipt_id,v_receipt.vehicle_id,v_source_hash,v_source_uid,
        v_operation_no,v_work_key,v_description,v_estimated_hours,v_estimated_hours_source,v_fingerprint)
      returning * into v_line_after;
      v_lines_added:=v_lines_added+1;
      if v_estimated_hours is not null then v_hours_added:=v_hours_added+1; end if;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values('insert','pdc_authenticated_email_operation_lines',v_line_after.operation_line_id,v_receipt.vehicle_id,v_actor_id,v_actor_email,null,
        jsonb_build_object('operation_no',v_operation_no,'work_key',v_work_key,'description',v_description,
          'estimated_hours',v_estimated_hours,'estimated_hours_source',v_estimated_hours_source),
        jsonb_build_object('source','pdc_authenticated_email_operation_hours_109','source_hash',v_source_hash,'no_booking',true));
    elsif v_estimated_hours is not null and (
       v_line_before.estimated_hours is null
       or (v_estimated_hours_source='job_card' and v_line_before.estimated_hours_source is distinct from 'job_card')
       or (v_estimated_hours_source='ai_estimate' and v_line_before.estimated_hours_source='ai_estimate'
           and v_line_before.estimated_hours is distinct from v_estimated_hours)
    ) then
      update public.pdc_authenticated_email_operation_lines
       set estimated_hours=v_estimated_hours,estimated_hours_source=v_estimated_hours_source
       where operation_line_id=v_line_before.operation_line_id returning * into v_line_after;
      v_hours_added:=v_hours_added+1;
      if v_estimated_hours_source='job_card' and v_line_before.estimated_hours is not null
         and v_line_before.estimated_hours is distinct from v_estimated_hours then
        v_job_card_hours_corrected:=v_job_card_hours_corrected+1;
      end if;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values('update','pdc_authenticated_email_operation_lines',v_line_after.operation_line_id,v_receipt.vehicle_id,v_actor_id,v_actor_email,
        to_jsonb(v_line_before),to_jsonb(v_line_after),
        jsonb_build_object('source','pdc_authenticated_email_operation_hours_109','source_hash',v_source_hash,
          'estimated_hours_updated',true,'estimated_hours_source',v_estimated_hours_source,
          'job_card_hours_corrected',v_estimated_hours_source='job_card','no_booking',true,'completed_work_reopened',false));
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
        jsonb_build_object('source','pdc_authenticated_email_operation_hours_109','source_hash',v_source_hash,
          'operation_no',v_operation_no,'required_work',v_work_key,'completed_work_reopened',false,'no_booking',true));
    end if;
  end loop;

  select revision into v_resulting_revision from public.pdc_email_vehicle_revision where singleton;
  return public.navision_backend_response(true,
    case when v_lines_added=0 and v_hours_added=0 then 'operation_lines_and_hours_already_imported' else 'operation_lines_and_hours_imported' end,
    jsonb_build_object(
      'vehicle_id',v_receipt.vehicle_id,'source_hash',v_source_hash,
      'operation_lines_received',jsonb_array_length(v_operations),'operation_lines_added',v_lines_added,
      'estimated_hours_added',v_hours_added,'job_card_hours_corrected',v_job_card_hours_corrected,'required_work_added',v_work_added,
      'resulting_revision',v_resulting_revision,'booking_created',false,'completed_work_reopened',false));
end;
$hours$;
revoke all on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) to authenticated;
comment on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) is
  'Staging-only enrolled-Viewer typed import of bounded authenticated job-card OP lines with job-card/AI hour provenance; job-card hours win; never books or completes work or Parts.';

drop trigger if exists pdc_email_vehicle_revision_operation_hours on public.pdc_authenticated_email_operation_lines;
create trigger pdc_email_vehicle_revision_operation_hours
after update of estimated_hours,estimated_hours_source on public.pdc_authenticated_email_operation_lines
for each row when (old.estimated_hours is distinct from new.estimated_hours
                or old.estimated_hours_source is distinct from new.estimated_hours_source)
execute function public.bump_pdc_email_vehicle_revision();

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
      'operation_line_id',ol.operation_line_id,
      'operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,
      'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source,
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
  'Staging authenticated-email vehicle snapshot including latest 50 bounded typed operation lines and job-card/AI estimate provenance; read-only and no booking authority.';

commit;
