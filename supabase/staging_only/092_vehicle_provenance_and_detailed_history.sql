-- Staging-only migration 092: authoritative vehicle provenance and detailed history.
-- Read-only RPC. It exposes bounded operational evidence to approved PDC users.
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
  if to_regclass('public.vehicles') is null
     or to_regclass('public.audit_events') is null
     or to_regclass('public.vehicle_movements') is null
     or to_regclass('public.pdc_authenticated_email_import_receipts') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_import_batches') is null then
    raise exception 'PDC_MIGRATION_092_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create or replace function public.get_pdc_vehicle_provenance_history(p_vehicle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $fn$
declare
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text;
  v_vehicle public.vehicles%rowtype;
begin
  if auth.uid() is null or v_email='' then
    return jsonb_build_object('ok',false,'code','unauthorized');
  end if;
  select role::text into v_role from public.pdc_user_roles
  where email=v_email and active=true;
  if v_role is null then
    return jsonb_build_object('ok',false,'code','forbidden');
  end if;
  select * into v_vehicle from public.vehicles where id=p_vehicle_id;
  if not found then
    return jsonb_build_object('ok',false,'code','vehicle_not_found');
  end if;

  return jsonb_build_object(
    'ok',true,
    'code','ok',
    'data',jsonb_build_object(
      'vehicle',jsonb_build_object(
        'vehicle_id',v_vehicle.id,
        'source_system',coalesce(to_jsonb(v_vehicle)->>'source_system',''),
        'source_record_id',coalesce(to_jsonb(v_vehicle)->>'source_record_id',''),
        'created_at',v_vehicle.created_at,
        'updated_at',v_vehicle.updated_at,
        'version',v_vehicle.version
      ),
      'email_imports',coalesce((
        select jsonb_agg(jsonb_build_object(
          'receipt_id',r.receipt_id,'imported_at',r.created_at,
          'source_received_at',r.source_received_at,'sender_address',r.sender_address,
          'source_uid',r.source_uid,'identity_source',r.identity_source,
          'stock_number',r.stock_number,'vin',r.vin,
          'backend_record_id',r.backend_record_id,'required_work',r.required_work
        ) order by r.created_at desc)
        from (select * from public.pdc_authenticated_email_import_receipts
              where vehicle_id=p_vehicle_id order by created_at desc limit 20) r
      ),'[]'::jsonb),
      'navision_imports',coalesce((
        select jsonb_agg(jsonb_build_object(
          'backend_record_id',n.id,'source_record_id',n.source_record_id,
          'first_seen_at',fb.applied_at,'first_source_name',fb.source_name,
          'last_seen_at',lb.applied_at,'last_source_name',lb.source_name,
          'last_source_timestamp',lb.source_timestamp,'last_revision',lb.result_revision,
          'is_current',n.is_current,'record_version',n.version
        ) order by lb.applied_at desc)
        from public.navision_backend_records n
        join public.navision_import_batches fb on fb.id=n.first_seen_batch_id
        join public.navision_import_batches lb on lb.id=n.last_seen_batch_id
        where n.canonical_vehicle_id=p_vehicle_id
           or n.id in (select backend_record_id from public.pdc_authenticated_email_import_receipts where vehicle_id=p_vehicle_id and backend_record_id is not null)
      ),'[]'::jsonb),
      'movements',coalesce((
        select jsonb_agg(to_jsonb(m) order by m.moved_at desc)
        from (select * from public.vehicle_movements where vehicle_id=p_vehicle_id order by moved_at desc limit 50) m
      ),'[]'::jsonb),
      'audit_events',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',a.id,'action',a.action,'table_name',a.table_name,'row_id',a.row_id,
          'actor_email',a.actor_email,'before_data',a.before_data,'after_data',a.after_data,
          'metadata',a.metadata,'created_at',a.created_at
        ) order by a.created_at desc)
        from (select * from public.audit_events where vehicle_id=p_vehicle_id order by created_at desc limit 100) a
      ),'[]'::jsonb)
    )
  );
end;
$fn$;

revoke all on function public.get_pdc_vehicle_provenance_history(uuid) from public,anon;
grant execute on function public.get_pdc_vehicle_provenance_history(uuid) to authenticated;

commit;
