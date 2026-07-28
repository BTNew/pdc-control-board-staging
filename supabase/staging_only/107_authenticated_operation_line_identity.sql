-- Staging-only durable identity for authenticated operation lines.
-- Distinguishes repeated OP numbers from separate authenticated documents and
-- remaps only legacy adjustments whose source operation is unambiguous.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_workshop_line_adjustments') is null
     or to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') is null then
    raise exception 'PDC_MIGRATION_107_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

lock table public.pdc_authenticated_email_operation_lines in share mode;
lock table public.vehicle_workshop_line_adjustments in share row exclusive mode;

with unique_source as (
  select vehicle_id,operation_no,(array_agg(operation_line_id order by operation_line_id))[1] as operation_line_id
  from public.pdc_authenticated_email_operation_lines
  group by vehicle_id,operation_no
  having count(*)=1
), candidates as (
  select a.adjustment_id,a.vehicle_id,a.line_key,
         'source:'||u.operation_line_id::text as new_line_key,
         to_jsonb(a) as before_data
  from public.vehicle_workshop_line_adjustments a
  join unique_source u on u.vehicle_id=a.vehicle_id
    and a.line_key='operation:'||upper(btrim(u.operation_no))
  where not exists (
    select 1 from public.vehicle_workshop_line_adjustments existing
    where existing.vehicle_id=a.vehicle_id
      and existing.line_key='source:'||u.operation_line_id::text
      and existing.adjustment_id<>a.adjustment_id
  )
), changed as (
  update public.vehicle_workshop_line_adjustments a
  set line_key=c.new_line_key,
      source_kind='source',
      version=a.version+1,
      updated_at=clock_timestamp()
  from candidates c
  where a.adjustment_id=c.adjustment_id
  returning a.*,c.before_data,c.line_key as previous_line_key
)
insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
select 'update','vehicle_workshop_line_adjustments',c.adjustment_id,c.vehicle_id,
       null,'migration-107@staging.local',c.before_data,to_jsonb(c)-'before_data'-'previous_line_key',
       jsonb_build_object('source','authenticated_operation_line_identity_107',
         'previous_line_key',c.previous_line_key,'line_key',c.line_key,
         'bookings_changed',false,'parts_changed',false,'completion_changed',false)
from changed c;

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
      'estimated_hours',ol.estimated_hours,'source_uid',ol.source_uid,'created_at',ol.created_at)
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
  'Staging authenticated-email vehicle snapshot including durable operation_line_id and explicit estimated hours; read-only and no booking authority.';

commit;
