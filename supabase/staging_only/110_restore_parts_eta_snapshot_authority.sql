begin;

-- Migration 109 rebuilt this restricted snapshot for operation hour provenance,
-- but accidentally omitted the previously exposed Parts ETA and Sublet projections.
-- Restore both projections without weakening authenticated-email vehicle scope.
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') is null
     or to_regprocedure('public.update_pdc_parts_eta(uuid,integer,date)') is null
     or to_regclass('public.vehicle_parts_updates') is null
     or to_regclass('public.pdc_sublet_bookings') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null then
    raise exception 'PDC_PARTS_ETA_SNAPSHOT_PREREQUISITE_MISSING';
  end if;
end;
$guard$;

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
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,
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
      where wi.vehicle_id=v.id and wi.work_key='PARTS'),false),
    'parts_update',coalesce((select jsonb_build_object(
      'parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,
      'parts_received',pu.parts_received,'parts_stoppage',pu.parts_stoppage,
      'parts_stoppage_reason',pu.parts_stoppage_reason,'worst_eta',pu.worst_eta,
      'previous_worst_eta',(select prior.worst_eta from public.vehicle_parts_updates prior
        where prior.vehicle_id=v.id and prior.id<>pu.id and prior.worst_eta is not null
        order by prior.updated_at desc,prior.id desc limit 1),
      'updated_by',pu.updated_by,'updated_at',pu.updated_at)
      from public.vehicle_parts_updates pu where pu.vehicle_id=v.id
      order by pu.updated_at desc,pu.id desc limit 1),'{}'::jsonb),
    'sublet_booking',coalesce((select jsonb_build_object(
      'provider',s.provider,'provider_email',s.provider_email,
      'po_sent_date',s.po_sent_date,'booking_date',s.booking_date,
      'expected_return_date',s.expected_return_date,'actual_return_date',s.actual_return_date,
      'notes',s.notes,'email_sent',s.email_sent,'version',s.version,
      'provider_names',coalesce(to_jsonb(s.provider_names),'[]'::jsonb),
      'provider_source',coalesce(s.provider_source,''),'updated_at',s.updated_at)
      from public.pdc_sublet_bookings s where s.vehicle_id=v.id),'{}'::jsonb)
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
  'Restricted authenticated-email vehicle snapshot preserving durable operation identities and hour provenance, Parts ETA/countdown authority and Sublet booking projection.';

commit;
