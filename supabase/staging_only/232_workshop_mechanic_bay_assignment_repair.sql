-- Staging-only migration 232: repair mechanic/bay reference mutations and make bay defaults exclusive/history-preserving.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';

-- Exact staging-only and append-only guards.
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='231')
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>231)
     or exists(select 1 from supabase_migrations.schema_migrations where version='232') then
    raise exception 'PDC_232_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end $guard$;

-- The statement-level Realtime trigger introduced by migration 044 used an
-- unbounded UPDATE. Staging's safe-update guard correctly rejects that shape,
-- causing every technician insert and bay update to fail with SQLSTATE 21000.
create or replace function public.workshop_bump_all_station_revisions()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $fn$
begin
  update public.workshop_station_revision
     set revision=revision+1,updated_at=now()
   where stage_code in (select code from public.workshop_stages);
  insert into public.workshop_station_revision(stage_code,revision,updated_at)
  select code,1,now() from public.workshop_stages
  on conflict(stage_code) do nothing;
  return null;
end $fn$;
revoke all on function public.workshop_bump_all_station_revisions() from public,anon,authenticated,service_role;

-- One active default bay per mechanic. A bay already has only one default column.
create unique index if not exists workshop_bays_one_default_bay_per_technician
  on public.workshop_bays(default_technician_id)
  where default_technician_id is not null;

create table if not exists public.workshop_bay_default_technician_history(
  id uuid primary key default gen_random_uuid(),
  bay_id uuid not null references public.workshop_bays(id),
  technician_id uuid references public.workshop_technicians(id),
  previous_technician_id uuid references public.workshop_technicians(id),
  action text not null check(action in ('assigned','changed','cleared')),
  bay_version integer not null,
  actor_id uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  evidence jsonb not null default '{}'::jsonb
);
create index if not exists workshop_bay_default_history_bay_time_idx
  on public.workshop_bay_default_technician_history(bay_id,changed_at desc);
create index if not exists workshop_bay_default_history_technician_time_idx
  on public.workshop_bay_default_technician_history(technician_id,changed_at desc);
alter table public.workshop_bay_default_technician_history enable row level security;
revoke all on table public.workshop_bay_default_technician_history from public,anon,authenticated,service_role;
grant select on table public.workshop_bay_default_technician_history to authenticated;
drop policy if exists workshop_bay_default_history_read on public.workshop_bay_default_technician_history;
create policy workshop_bay_default_history_read on public.workshop_bay_default_technician_history
 for select to authenticated using(public.current_pdc_user_role() in ('operator','administrator'));

create or replace function public.workshop_record_bay_default_history_232()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $fn$
begin
  if old.default_technician_id is not distinct from new.default_technician_id then return new; end if;
  insert into public.workshop_bay_default_technician_history(
    bay_id,technician_id,previous_technician_id,action,bay_version,actor_id,evidence)
  values(new.id,new.default_technician_id,old.default_technician_id,
    case when new.default_technician_id is null then 'cleared'
         when old.default_technician_id is null then 'assigned' else 'changed' end,
    new.version,auth.uid(),jsonb_build_object('source','workshop_bays_trigger_232'));
  return new;
end $fn$;
revoke all on function public.workshop_record_bay_default_history_232() from public,anon,authenticated,service_role;
drop trigger if exists workshop_record_bay_default_history_232 on public.workshop_bays;
create trigger workshop_record_bay_default_history_232
 after update of default_technician_id on public.workshop_bays
 for each row execute function public.workshop_record_bay_default_history_232();

create or replace function public.set_bay_default_technician(
  p_bay_id uuid,p_expected_version integer,p_technician_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $fn$
declare
  v_before public.workshop_bays%rowtype;
  v_after public.workshop_bays%rowtype;
  v_technician public.workshop_technicians%rowtype;
  v_other public.workshop_bays%rowtype;
begin
  perform public.require_pdc_role('administrator');
  perform pg_advisory_xact_lock(hashtextextended('pdc:bay-default-technician',0));

  select * into v_before from public.workshop_bays where id=p_bay_id for update;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  if v_before.version<>p_expected_version then
    -- An exact repeat is idempotently successful even if the caller retained the old version.
    if v_before.default_technician_id is not distinct from p_technician_id then
      return jsonb_build_object('ok',true,'idempotent',true,'bay',to_jsonb(v_before));
    end if;
    return jsonb_build_object('ok',false,'error','version_conflict','current',to_jsonb(v_before));
  end if;
  if v_before.default_technician_id is not distinct from p_technician_id then
    return jsonb_build_object('ok',true,'idempotent',true,'bay',to_jsonb(v_before));
  end if;

  if p_technician_id is not null then
    select * into v_technician from public.workshop_technicians where id=p_technician_id for update;
    if not found then return jsonb_build_object('ok',false,'error','technician_not_found'); end if;
    if not v_technician.active then return jsonb_build_object('ok',false,'error','technician_inactive'); end if;
    select * into v_other from public.workshop_bays
      where default_technician_id=p_technician_id and id<>p_bay_id for update;
    if found then
      return jsonb_build_object('ok',false,'error','technician_already_assigned_to_bay',
        'conflict',jsonb_build_object('bay_id',v_other.id,'bay_code',v_other.code,'bay_number',v_other.bay_number));
    end if;
  end if;

  update public.workshop_bays
     set default_technician_id=p_technician_id,version=version+1,
         updated_by=auth.uid(),updated_at=now()
   where id=p_bay_id and version=p_expected_version
   returning * into v_after;
  if not found then return jsonb_build_object('ok',false,'error','version_conflict'); end if;

  perform public.audit_pdc_event('reference_change','workshop_bays',v_after.id,null,to_jsonb(v_before),to_jsonb(v_after),
    jsonb_build_object('action','set_bay_default_technician','migration',232));
  return jsonb_build_object('ok',true,'idempotent',false,'bay',to_jsonb(v_after));
end $fn$;
revoke all on function public.set_bay_default_technician(uuid,integer,uuid) from public,anon,service_role;
grant execute on function public.set_bay_default_technician(uuid,integer,uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('232','workshop_mechanic_bay_assignment_repair',array['staging-only migration 232'])
on conflict(version) do nothing;
commit;
