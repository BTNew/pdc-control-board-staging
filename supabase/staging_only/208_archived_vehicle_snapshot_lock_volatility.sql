-- Staging-only migration 208: permit archived snapshot authority validation to take its auth-bound role lock.
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-208-archived-snapshot-volatility',0));
do $guard$
begin
 if not public.pdc_monitor_staging_guard()
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='207' and name='admin_vehicle_actor_lock_volatility')
    or exists(select 1 from supabase_migrations.schema_migrations where version='208') then
  raise exception 'PDC_208_STAGING_OR_LEDGER_MISMATCH' using errcode='55000',detail='wrong_environment_or_predecessor';
 end if;
end $guard$;

create or replace function public.pdc_admin_archived_vehicle_snapshot(p_tombstone_id uuid default null,p_limit integer default 100)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public as $$
declare s jsonb;rows jsonb;
begin
 s:=public.pdc_admin_vehicle_actor();if not coalesce((s->>'ok')::boolean,false) then return s;end if;
 if p_limit not between 1 and 200 then return public.navision_backend_response(false,'invalid_input');end if;
 select coalesce(jsonb_agg(x order by x.deleted_at desc,x.tombstone_id),'[]'::jsonb) into rows from (
  select t.tombstone_id,t.vehicle_id,t.stock_number,t.normalized_stock,t.tombstone_kind,t.deleted_by_email,t.deleted_at,t.reason,t.previous_lifecycle_state,t.previous_location,t.previous_visible_on_board,t.previous_status,t.vehicle_snapshot,
   (select coalesce(jsonb_agg(e order by e.event_id),'[]'::jsonb) from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=t.tombstone_id) lifecycle_events
  from public.pdc_vehicle_tombstones t where (p_tombstone_id is null or t.tombstone_id=p_tombstone_id) order by t.deleted_at desc limit p_limit
 )x;
 return public.navision_backend_response(true,'archived_vehicle_snapshot',jsonb_build_object('items',rows));
end $$;
revoke all on function public.pdc_admin_archived_vehicle_snapshot(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.pdc_admin_archived_vehicle_snapshot(uuid,integer) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('208','archived_vehicle_snapshot_lock_volatility',array[
 'Declare Administrator archived-vehicle snapshot VOLATILE so auth-bound role locking is legal',
 'Retain authenticated entry ACL with exact Administrator validation inside the security-definer function'
]);
commit;
