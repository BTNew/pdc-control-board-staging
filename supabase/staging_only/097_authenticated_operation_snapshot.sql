-- Staging-only migration 097: reassert authenticated operation lines in the Viewer snapshot.
-- No operational rows are mutated; this replaces only the read-snapshot function.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     )
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.pdc_email_vehicle_revision') is null
     or to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') is null then
    raise exception 'PDC_MIGRATION_097_STAGING_OR_DEPENDENCY_MISMATCH';
  end if;
end;
$guard$;

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
      order by substring(ol.operation_no from 3)::integer,ol.created_at,ol.operation_line_id)
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
comment on function public.get_pdc_email_vehicle_location_snapshot() is
  'Staging authenticated-email vehicle snapshot including bounded typed operation lines; read-only and no booking authority.';

commit;
