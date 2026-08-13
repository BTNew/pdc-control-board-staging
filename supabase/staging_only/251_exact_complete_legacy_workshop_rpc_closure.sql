-- Staging-only draft migration 251: exact complete legacy Workshop RPC closure.
-- DRAFT ONLY: do not apply while pdc-monitor acceptance is active.
begin;
set local lock_timeout='10s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));

-- Fail closed outside the exact staging project or if migration 250 is not the head.
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     )
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or to_regclass('supabase_migrations.schema_migrations') is null
     or not exists (
       select 1 from supabase_migrations.schema_migrations
       where version='250' and name='revoke_service_role_legacy_workshop_rpc'
     )
     or exists (
       select 1 from supabase_migrations.schema_migrations
       where version ~ '^[0-9]+$' and version::integer>250
     ) then
    raise exception 'PDC_251_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

revoke all on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.resize_workshop_booking(uuid,integer,integer,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.change_booking_bay(uuid,integer,integer,jsonb) from public,anon,authenticated,service_role;

-- Migration 244 canonicalized a null create-cascade value as true in the intent hash,
-- but PL/pgSQL `if null then` selected the non-cascade execution path and the receipt
-- retained null. Keep 244 immutable: move its implementation behind a private predecessor
-- and reject explicit null before any intent, execution or receipt can diverge.
alter function public.administrator_schedule_workshop_vehicle(
  uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean
) rename to administrator_schedule_workshop_vehicle_pre_251;
revoke all on function public.administrator_schedule_workshop_vehicle_pre_251(
  uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean
) from public,anon,authenticated,service_role;

create function public.administrator_schedule_workshop_vehicle(
  p_vehicle_id uuid,p_vehicle_expected_version integer,p_stage_code text,p_bay_number integer,
  p_scheduled_start_at timestamptz,p_duration_minutes integer,p_technician_id uuid,
  p_metadata jsonb,p_request_id uuid,p_cascade boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $schedule_251$
begin
  if p_cascade is null then
    raise exception 'PDC_251_CASCADE_REQUIRED' using errcode='22023';
  end if;
  return public.administrator_schedule_workshop_vehicle_pre_251(
    p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,
    p_scheduled_start_at,p_duration_minutes,p_technician_id,
    p_metadata,p_request_id,p_cascade
  );
end
$schedule_251$;
revoke all on function public.administrator_schedule_workshop_vehicle(
  uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean
) from public,anon,authenticated,service_role;
grant execute on function public.administrator_schedule_workshop_vehicle(
  uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean
) to authenticated;

do $verify$
declare
  signature text;
  endpoint regprocedure;
begin
  foreach signature in array array[
    'public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)',
    'public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)',
    'public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)',
    'public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
    'public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
    'public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
    'public.resize_workshop_booking(uuid,integer,integer,jsonb)',
    'public.change_booking_bay(uuid,integer,integer,jsonb)'
  ] loop
    endpoint:=to_regprocedure(signature);
    if endpoint is null then
      raise exception 'PDC_251_RPC_MISSING:%',signature using errcode='55000';
    end if;
    if has_function_privilege('public',endpoint,'execute')
       or has_function_privilege('anon',endpoint,'execute')
       or has_function_privilege('authenticated',endpoint,'execute')
       or has_function_privilege('service_role',endpoint,'execute') then
      raise exception 'PDC_251_RPC_GRANT_VERIFY_FAILED:%',signature using errcode='55000';
    end if;
  end loop;

  foreach signature in array array[
    'public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)',
    'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)',
    'public.undo_administrator_workshop_booking_move(uuid,integer,uuid)'
  ] loop
    endpoint:=to_regprocedure(signature);
    if endpoint is null then
      raise exception 'PDC_251_ADMIN_ENDPOINT_MISSING:%',signature using errcode='55000';
    end if;
    if has_function_privilege('public',endpoint,'execute')
       or has_function_privilege('anon',endpoint,'execute')
       or has_function_privilege('service_role',endpoint,'execute')
       or not has_function_privilege('authenticated',endpoint,'execute') then
      raise exception 'PDC_251_ADMIN_ENDPOINT_ACL_FAILED:%',signature using errcode='55000';
    end if;
  end loop;
end
$verify$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('251','exact_complete_legacy_workshop_rpc_closure',array[
  'staging-only exact closure: schedule, cascade schedule, pre-087 cascade schedule, move, cascade move, pre-116 cascade move, resize and bay-change RPCs denied to public, anon, authenticated and service_role',
  'Administrator create cascade intent is non-null and identical across request hash, execution path and receipt',
  'Administrator controlled endpoints remain authenticated-only and enforce Administrator authority internally',
  'production untouched'
]);
commit;
