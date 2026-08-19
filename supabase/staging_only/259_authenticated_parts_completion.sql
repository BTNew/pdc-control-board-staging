-- Staging-only migration 259: receipt-backed authenticated Parts completion.
-- Mark Received is the canonical Parts completion transition for shared email rows.
begin;
set local lock_timeout='10s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or (select count(*) from public.pdc_staging_environment_sentinel
         where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.vehicle_parts_updates') is null
     or to_regclass('public.audit_events') is null
     or to_regclass('public.pdc_email_vehicle_revision') is null
     or to_regprocedure('public.require_pdc_role(public.pdc_role)') is null
     or to_regprocedure('public.navision_backend_response(boolean,text,jsonb)') is null
     or exists(select 1 from supabase_migrations.schema_migrations where version='259')
  then raise exception 'PDC_259_EXACT_STAGING_DEPENDENCY_MISMATCH' using errcode='55000'; end if;
end $guard$;

create or replace function public.mark_pdc_parts_complete(
  p_vehicle_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $parts_complete$
declare
  v_vehicle_before public.vehicles%rowtype;
  v_vehicle_after public.vehicles%rowtype;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
  v_work_before public.vehicle_work_items%rowtype;
  v_work_after public.vehicle_work_items%rowtype;
  v_receipt_id uuid;
  v_revision bigint;
  v_actor uuid:=auth.uid();
  v_expected_version integer:=p_expected_version;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  perform public.require_pdc_role('operator');
  if v_actor is null or p_vehicle_id is null or v_expected_version is null then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  select * into v_vehicle_before
  from public.vehicles where id=p_vehicle_id for update;
  if not found then return public.navision_backend_response(false,'vehicle_not_found'); end if;
  if v_vehicle_before.lifecycle_state<>'active' or v_vehicle_before.deleted_at is not null then
    return public.navision_backend_response(false,'not_in_active_lifecycle');
  end if;

  -- A repeated click with the same expected version returns the original
  -- receipt, even though the first completion incremented the vehicle version.
  select case when a.metadata->>'receipt_id' ~* '^[0-9a-f-]{36}$'
              then (a.metadata->>'receipt_id')::uuid end
    into v_receipt_id
  from public.audit_events a
  where a.vehicle_id=p_vehicle_id
    and a.metadata->>'action'='mark_pdc_parts_complete'
    and a.metadata->>'expected_version'=v_expected_version::text
  order by a.created_at desc,a.id desc limit 1;
  if v_receipt_id is not null then
    return public.navision_backend_response(true,'replayed',jsonb_build_object(
      'receipt_id',v_receipt_id,'vehicle_id',p_vehicle_id,
      'vehicle_version',v_vehicle_before.version,'changed',false));
  end if;

  if v_vehicle_before.version<>v_expected_version then
    return public.navision_backend_response(false,'vehicle_version_conflict');
  end if;

  select * into v_parts_before from public.vehicle_parts_updates
  where vehicle_id=p_vehicle_id order by updated_at desc,id desc limit 1;
  select * into v_work_before from public.vehicle_work_items
  where vehicle_id=p_vehicle_id and upper(work_key)='PARTS' for update;
  if coalesce(v_parts_before.parts_received,false) or coalesce(v_work_before.completed,false) then
    return public.navision_backend_response(false,'parts_already_received');
  end if;

  v_receipt_id:=gen_random_uuid();
  insert into public.vehicle_parts_updates(
    vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,
    parts_stoppage_reason,worst_eta,updated_by,updated_at
  ) values(
    p_vehicle_id,true,coalesce(v_parts_before.parts_ordered,true),true,false,
    null,null,v_actor,clock_timestamp()
  ) returning * into v_parts_after;

  insert into public.vehicle_work_items(
    vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at
  ) values(
    p_vehicle_id,'PARTS',true,true,v_actor,clock_timestamp(),
    coalesce(v_work_before.notes,'Parts received on Parts board'),clock_timestamp()
  ) on conflict(vehicle_id,work_key) do update set
    required=true,completed=true,completed_by=v_actor,completed_at=clock_timestamp(),updated_at=clock_timestamp()
  returning * into v_work_after;

  update public.vehicles set version=version+1,updated_by=v_actor
  where id=p_vehicle_id returning * into v_vehicle_after;

  perform public.audit_pdc_event(
    'insert','vehicle_parts_updates',v_parts_after.id,p_vehicle_id,
    case when v_parts_before.id is null then null else to_jsonb(v_parts_before) end,
    to_jsonb(v_parts_after),jsonb_build_object(
      'action','mark_pdc_parts_complete','receipt_id',v_receipt_id,
      'expected_version',v_expected_version,'changed',true));
  perform public.audit_pdc_event(
    case when v_work_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
    'vehicle_work_items',v_work_after.id,p_vehicle_id,
    case when v_work_before.id is null then null else to_jsonb(v_work_before) end,
    to_jsonb(v_work_after),jsonb_build_object(
      'action','mark_pdc_parts_complete','receipt_id',v_receipt_id,
      'expected_version',v_expected_version,'changed',true));
  update public.pdc_email_vehicle_revision
  set revision=revision+1,updated_at=clock_timestamp()
  where singleton returning revision into v_revision;

  return public.navision_backend_response(true,'parts_completed',jsonb_build_object(
    'receipt_id',v_receipt_id,'vehicle_id',p_vehicle_id,
    'vehicle_version',v_vehicle_after.version,'revision',v_revision,'changed',true));
end;
$parts_complete$;
revoke all on function public.mark_pdc_parts_complete(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.mark_pdc_parts_complete(uuid,integer) to authenticated;
comment on function public.mark_pdc_parts_complete(uuid,integer) is
  'Staging-only authenticated operator Parts completion. Atomically records received Parts state, completes PARTS work, clears active stoppage/ETA, increments vehicle version, writes audit receipts and one shared revision.';

insert into supabase_migrations.schema_migrations(version,name,statements) values('259','authenticated_parts_completion',array[
 'Add receipt-backed authenticated mark_pdc_parts_complete(uuid,integer)',
 'Complete canonical PARTS work and clear active Parts stoppage/ETA atomically',
 'Publish one pdc_email_vehicle_revision update and return exact replay receipts'
]);
commit;
