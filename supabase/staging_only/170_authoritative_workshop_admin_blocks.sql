-- Staging-only migration 170: authoritative administrator downtime blocks.
-- Append-only over migration 142. Admin blocks are versioned operational rows;
-- history and mutation receipts are immutable backup-relevant evidence.
begin;

do $guard$
begin
  if not exists (
    select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
  ) or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'Migration 170 is staging-only';
  end if;
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version='169' and name='vehicle_location_latches_and_milestones'
  ) or exists (
    select 1 from supabase_migrations.schema_migrations where version='170'
  ) or exists (
    select 1 from supabase_migrations.schema_migrations
    where version~'^[0-9]+$' and version::numeric>169
  ) then
    raise exception 'Migration 170 predecessor/target guard failed';
  end if;
  if to_regprocedure('public.workshop_lock_resources(uuid,uuid)') is null
     or to_regprocedure('public.workshop_add_operational_minutes(timestamptz,integer)') is null
     or to_regprocedure('public.workshop_calendar_minute_available(timestamptz)') is null
     or to_regprocedure('public.workshop_upsert_primary_assignment(uuid,uuid,timestamptz,timestamptz,text)') is null
     or to_regprocedure('public.workshop_write_history(uuid,text,jsonb,jsonb,jsonb)') is null
     or to_regprocedure('public.workshop_bump_revision()') is null
     or to_regprocedure('public.workshop_bump_station_revision(text)') is null then
    raise exception 'Migration 170 Workshop dependency missing';
  end if;
end;
$guard$;

create table public.workshop_admin_blocks (
  id uuid primary key default gen_random_uuid(),
  stage_id uuid not null references public.workshop_stages(id) on delete restrict,
  bay_id uuid not null references public.workshop_bays(id) on delete restrict,
  block_type text not null,
  label text,
  scheduled_start_at timestamptz not null,
  scheduled_end_at timestamptz not null,
  duration_minutes integer not null,
  version integer not null default 1,
  deleted_at timestamptz,
  deleted_reason text,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint workshop_admin_blocks_type_check check (block_type in ('training','sick','admin')),
  constraint workshop_admin_blocks_label_check check (label is null or length(btrim(label)) between 1 and 120),
  constraint workshop_admin_blocks_duration_check check (duration_minutes>0),
  constraint workshop_admin_blocks_schedule_check check (scheduled_end_at>scheduled_start_at),
  constraint workshop_admin_blocks_version_check check (version>0)
);
create index workshop_admin_blocks_bay_time_idx
  on public.workshop_admin_blocks(bay_id,scheduled_start_at,scheduled_end_at)
  where deleted_at is null;

-- Reverse authority: ordinary booking RPCs and their validation triggers must
-- not schedule new active work through an existing Admin block. Reuse the
-- canonical workshop-bay advisory namespace so booking-vs-block races serialize.
create function public.workshop_enforce_admin_block_booking_conflict()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if new.bay_id is null or new.deleted_at is not null
     or new.status in ('completed','deleted') then return new; end if;
  perform public.workshop_lock_resources(new.bay_id,null);
  if exists(
    select 1 from public.workshop_admin_blocks a
    where a.bay_id=new.bay_id and a.deleted_at is null
      and a.scheduled_start_at<new.scheduled_end_at
      and a.scheduled_end_at>new.scheduled_start_at
  ) then
    raise exception '%',jsonb_build_object('error','admin_block_conflict','bay_id',new.bay_id)::text
      using errcode='23514';
  end if;
  return new;
end $$;
create trigger workshop_bookings_admin_block_conflict
before insert or update of bay_id,status,scheduled_start_at,scheduled_end_at,deleted_at
on public.workshop_bookings for each row
execute function public.workshop_enforce_admin_block_booking_conflict();

create table public.workshop_admin_block_history (
  id uuid primary key default gen_random_uuid(),
  block_id uuid not null references public.workshop_admin_blocks(id) on delete restrict,
  event_type text not null check (event_type in ('created','moved','resized','deleted')),
  block_version integer not null check (block_version>0),
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  actor_email text,
  created_at timestamptz not null default clock_timestamp()
);
create index workshop_admin_block_history_block_idx
  on public.workshop_admin_block_history(block_id,created_at desc,id);

create table public.workshop_admin_block_receipts (
  receipt_id uuid primary key default gen_random_uuid(),
  block_id uuid not null references public.workshop_admin_blocks(id) on delete restrict,
  mutation_type text not null check (mutation_type in ('create','move','resize','delete')),
  expected_version bigint,
  resulting_version integer not null check (resulting_version>0),
  response jsonb not null,
  metadata jsonb not null default '{}'::jsonb,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  actor_email text,
  created_at timestamptz not null default clock_timestamp()
);
create index workshop_admin_block_receipts_block_idx
  on public.workshop_admin_block_receipts(block_id,created_at desc,receipt_id);

comment on table public.workshop_admin_blocks is
'Backup-required authoritative Workshop administrator downtime. Restore before its history/receipts; never reconstruct from browser state.';
comment on table public.workshop_admin_block_history is
'Backup-required immutable append-only administrator block history. Restore after workshop_admin_blocks.';
comment on table public.workshop_admin_block_receipts is
'Backup-required immutable append-only administrator block mutation receipts. Restore after workshop_admin_blocks.';

create function public.workshop_reject_admin_block_evidence_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  raise exception 'Workshop admin block evidence is append-only' using errcode='55000';
end $$;
create trigger workshop_admin_block_history_immutable
before update or delete on public.workshop_admin_block_history
for each row execute function public.workshop_reject_admin_block_evidence_mutation();
create trigger workshop_admin_block_receipts_immutable
before update or delete on public.workshop_admin_block_receipts
for each row execute function public.workshop_reject_admin_block_evidence_mutation();

alter table public.workshop_admin_blocks enable row level security;
alter table public.workshop_admin_block_history enable row level security;
alter table public.workshop_admin_block_receipts enable row level security;
create policy workshop_admin_blocks_select_administrator on public.workshop_admin_blocks
for select to authenticated using (public.is_pdc_role('administrator'));
create policy workshop_admin_block_history_select_administrator on public.workshop_admin_block_history
for select to authenticated using (public.is_pdc_role('administrator'));
create policy workshop_admin_block_receipts_select_administrator on public.workshop_admin_block_receipts
for select to authenticated using (public.is_pdc_role('administrator'));
revoke all on table public.workshop_admin_blocks,public.workshop_admin_block_history,public.workshop_admin_block_receipts
from public,anon,authenticated,service_role;
grant select on table public.workshop_admin_blocks,public.workshop_admin_block_history,public.workshop_admin_block_receipts
to authenticated,service_role;

create function public.workshop_admin_block_snapshot(p_block_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,public as $$
  select jsonb_build_object(
    'id',a.id,'version',a.version,'block_type',a.block_type,'label',a.label,
    'stage_id',a.stage_id,'stage_code',s.code,
    'bay_id',a.bay_id,'bay_number',b.bay_number,
    'scheduled_start_at',a.scheduled_start_at,'scheduled_end_at',a.scheduled_end_at,
    'duration_minutes',a.duration_minutes,'deleted_at',a.deleted_at,
    'deleted_reason',a.deleted_reason,'created_at',a.created_at,'updated_at',a.updated_at
  )
  from public.workshop_admin_blocks a
  join public.workshop_stages s on s.id=a.stage_id
  join public.workshop_bays b on b.id=a.bay_id
  where a.id=p_block_id
$$;

-- Use the exact same physical-bay advisory-lock namespace as every canonical
-- Workshop booking mutation: workshop_lock_resources() hashes "workshop-bay:<uuid>".
create function public.workshop_admin_lock_physical_bays(p_first uuid,p_second uuid default null)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if p_first is not null and p_second is not null and p_first<>p_second then
    perform public.workshop_lock_resources(least(p_first::text,p_second::text)::uuid,null);
    perform public.workshop_lock_resources(greatest(p_first::text,p_second::text)::uuid,null);
  elsif coalesce(p_first,p_second) is not null then
    perform public.workshop_lock_resources(coalesce(p_first,p_second),null);
  end if;
end $$;

create function public.workshop_admin_validate_interval(
  p_stage_code text,p_bay_number integer,p_start timestamptz,p_duration integer
) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_stage public.workshop_stages%rowtype; v_bay public.workshop_bays%rowtype; v_end timestamptz; v_increment integer;
begin
  select * into v_stage from public.workshop_stages
  where code=upper(btrim(coalesce(p_stage_code,''))) and active and planner_enabled and is_physical;
  if not found then return jsonb_build_object('ok',false,'error','stage_inactive_or_missing'); end if;
  select * into v_bay from public.workshop_bays
  where stage_id=v_stage.id and bay_number=p_bay_number and is_active and not is_sublet_row;
  if not found then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
  select coalesce((value#>>'{}')::integer,15) into v_increment
  from public.workshop_settings where key='scheduling_increment_minutes';
  v_increment:=coalesce(v_increment,15);
  if p_start is null or p_start<>date_trunc('minute',p_start)
     or p_duration is null or p_duration<v_increment or p_duration%v_increment<>0 then
    return jsonb_build_object('ok',false,'error','invalid_schedule_interval');
  end if;
  if not public.workshop_calendar_minute_available(p_start) then
    return jsonb_build_object('ok',false,'error','calendar_unavailable');
  end if;
  v_end:=public.workshop_add_operational_minutes(p_start,p_duration);
  if v_end is null or v_end<=p_start
     or public.workshop_operational_minutes_between(p_start,v_end)<>p_duration then
    return jsonb_build_object('ok',false,'error','calendar_duration_mismatch');
  end if;
  return jsonb_build_object('ok',true,'stage_id',v_stage.id,'stage_code',v_stage.code,
    'bay_id',v_bay.id,'bay_number',v_bay.bay_number,'scheduled_end_at',v_end);
end $$;

-- Repack only status=planned rows. Queued, started, stoppage, completed and
-- deleted rows are fixed and are never UPDATE targets. The caller holds the
-- exact physical-bay lock, so the complete repack is one atomic transaction.
create function public.workshop_admin_repack_planned(
  p_bay_id uuid,p_from timestamptz,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_booking public.workshop_bookings%rowtype; v_start timestamptz; v_end timestamptz;
  v_block_end timestamptz; v_fixed_end timestamptz; v_before jsonb; v_after jsonb;
  v_technician uuid; v_shifted uuid[]:='{}'::uuid[]; v_guard integer;
begin
  for v_booking in
    select * from public.workshop_bookings b
    where b.bay_id=p_bay_id and b.status='planned' and b.deleted_at is null
      and b.scheduled_end_at>p_from
    order by b.scheduled_start_at,b.id for update
  loop
    v_start:=v_booking.scheduled_start_at;
    v_guard:=0;
    loop
      v_guard:=v_guard+1;
      if v_guard>1000 then raise exception 'Workshop admin repack guard exceeded' using errcode='54000'; end if;
      v_end:=public.workshop_add_operational_minutes(v_start,v_booking.default_duration_minutes);
      select max(a.scheduled_end_at) into v_block_end
      from public.workshop_admin_blocks a
      where a.bay_id=p_bay_id and a.deleted_at is null
        and a.scheduled_start_at<v_end and a.scheduled_end_at>v_start;
      select max(b.scheduled_end_at) into v_fixed_end
      from public.workshop_bookings b
      where b.bay_id=p_bay_id and b.id<>v_booking.id and b.deleted_at is null
        and b.status in ('queued','started','stoppage','completed')
        and b.scheduled_start_at<v_end and b.scheduled_end_at>v_start;
      exit when v_block_end is null and v_fixed_end is null;
      v_start:=greatest(coalesce(v_block_end,v_start),coalesce(v_fixed_end,v_start));
    end loop;
    if v_start is distinct from v_booking.scheduled_start_at then
      v_before:=public.workshop_booking_snapshot(v_booking.id);
      update public.workshop_bookings set
        scheduled_start_at=v_start,scheduled_end_at=v_end,updated_by=auth.uid(),
        updated_at=clock_timestamp(),version=version+1
      where id=v_booking.id and status='planned' and deleted_at is null;
      if not found then raise exception 'Concurrent planned queue change' using errcode='40001'; end if;
      select a.technician_id into v_technician from public.workshop_booking_assignments a
      where a.booking_id=v_booking.id and a.released_at is null
      order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1;
      perform public.workshop_upsert_primary_assignment(v_booking.id,v_technician,v_start,v_end,'admin_block_repacked');
      v_after:=public.workshop_booking_snapshot(v_booking.id);
      perform public.workshop_write_history(v_booking.id,'admin_block_repacked',v_before,v_after,
        coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_repack',true));
      v_shifted:=array_append(v_shifted,v_booking.id);
    end if;
  end loop;
  return jsonb_build_object('shifted_booking_ids',to_jsonb(v_shifted),'shifted_count',cardinality(v_shifted));
end $$;

create function public.workshop_admin_write_evidence(
  p_block_id uuid,p_event text,p_expected bigint,p_before jsonb,p_after jsonb,
  p_response jsonb,p_metadata jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_receipt uuid;
begin
  insert into public.workshop_admin_block_history(
    block_id,event_type,block_version,before_data,after_data,metadata,actor_user_id,actor_email
  ) values(p_block_id,p_event,(p_after->>'version')::integer,p_before,p_after,
    coalesce(p_metadata,'{}'::jsonb),auth.uid(),public.current_actor_email());
  insert into public.workshop_admin_block_receipts(
    block_id,mutation_type,expected_version,resulting_version,response,metadata,actor_user_id,actor_email
  ) values(p_block_id,case p_event when 'created' then 'create' when 'moved' then 'move' when 'resized' then 'resize' else 'delete' end,
    p_expected,(p_after->>'version')::integer,p_response,coalesce(p_metadata,'{}'::jsonb),auth.uid(),public.current_actor_email())
  returning receipt_id into v_receipt;
  return v_receipt;
end $$;

create function public.create_workshop_admin_block(
  p_expected_revision bigint,p_stage_code text,p_bay_number integer,p_block_type text,
  p_label text,p_scheduled_start_at timestamptz,p_duration_minutes integer,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_valid jsonb; v_id uuid; v_end timestamptz; v_after jsonb; v_repack jsonb; v_response jsonb; v_revision bigint; v_receipt uuid;
begin
  perform public.require_pdc_role('administrator');
  if lower(btrim(coalesce(p_block_type,''))) not in ('training','sick','admin') then
    return jsonb_build_object('ok',false,'error','invalid_admin_block_type');
  end if;
  if nullif(btrim(coalesce(p_label,'')),'') is not null and length(btrim(p_label))>120 then
    return jsonb_build_object('ok',false,'error','invalid_label');
  end if;
  v_valid:=public.workshop_admin_validate_interval(p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes);
  if not coalesce((v_valid->>'ok')::boolean,false) then return v_valid; end if;
  perform public.workshop_admin_lock_physical_bays((v_valid->>'bay_id')::uuid,null);
  perform 1 from public.workshop_revision where id=1 for update;
  if public.workshop_current_revision()<>p_expected_revision then
    return jsonb_build_object('ok',false,'error','version_conflict','current_revision',public.workshop_current_revision());
  end if;
  v_end:=(v_valid->>'scheduled_end_at')::timestamptz;
  if exists(select 1 from public.workshop_admin_blocks a where a.bay_id=(v_valid->>'bay_id')::uuid and a.deleted_at is null and a.scheduled_start_at<v_end and a.scheduled_end_at>p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','admin_block_conflict');
  end if;
  if exists(select 1 from public.workshop_bookings b where b.bay_id=(v_valid->>'bay_id')::uuid and b.deleted_at is null
    and b.status in ('queued','started','stoppage','completed') and b.scheduled_start_at<v_end and b.scheduled_end_at>p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','fixed_booking_conflict');
  end if;
  insert into public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
  values((v_valid->>'stage_id')::uuid,(v_valid->>'bay_id')::uuid,lower(btrim(p_block_type)),nullif(btrim(coalesce(p_label,'')),''),p_scheduled_start_at,v_end,p_duration_minutes,auth.uid(),auth.uid()) returning id into v_id;
  v_repack:=public.workshop_admin_repack_planned((v_valid->>'bay_id')::uuid,p_scheduled_start_at,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_id',v_id));
  v_after:=public.workshop_admin_block_snapshot(v_id);
  v_revision:=public.workshop_bump_revision();
  perform public.workshop_bump_station_revision(v_valid->>'stage_code');
  v_response:=jsonb_build_object('ok',true,'admin_block',v_after,'revision',v_revision,'repack',v_repack);
  v_receipt:=public.workshop_admin_write_evidence(v_id,'created',p_expected_revision,null,v_after,v_response,p_metadata);
  return v_response||jsonb_build_object('receipt_id',v_receipt);
end $$;

create function public.move_workshop_admin_block(
  p_block_id uuid,p_expected_version integer,p_stage_code text,p_bay_number integer,
  p_scheduled_start_at timestamptz,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_block public.workshop_admin_blocks%rowtype; v_valid jsonb; v_before jsonb; v_after jsonb; v_repack jsonb; v_response jsonb; v_revision bigint; v_receipt uuid; v_old_stage text;
begin
  perform public.require_pdc_role('administrator');
  select * into v_block from public.workshop_admin_blocks where id=p_block_id for update;
  if not found or v_block.deleted_at is not null then return jsonb_build_object('ok',false,'error','admin_block_not_found'); end if;
  if v_block.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
  v_valid:=public.workshop_admin_validate_interval(p_stage_code,p_bay_number,p_scheduled_start_at,v_block.duration_minutes);
  if not coalesce((v_valid->>'ok')::boolean,false) then return v_valid; end if;
  perform public.workshop_admin_lock_physical_bays(v_block.bay_id,(v_valid->>'bay_id')::uuid);
  select code into v_old_stage from public.workshop_stages where id=v_block.stage_id;
  if exists(select 1 from public.workshop_admin_blocks a where a.id<>p_block_id and a.bay_id=(v_valid->>'bay_id')::uuid and a.deleted_at is null and a.scheduled_start_at<(v_valid->>'scheduled_end_at')::timestamptz and a.scheduled_end_at>p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','admin_block_conflict');
  end if;
  if exists(select 1 from public.workshop_bookings b where b.bay_id=(v_valid->>'bay_id')::uuid and b.deleted_at is null and b.status in ('queued','started','stoppage','completed') and b.scheduled_start_at<(v_valid->>'scheduled_end_at')::timestamptz and b.scheduled_end_at>p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','fixed_booking_conflict');
  end if;
  v_before:=public.workshop_admin_block_snapshot(p_block_id);
  update public.workshop_admin_blocks set stage_id=(v_valid->>'stage_id')::uuid,bay_id=(v_valid->>'bay_id')::uuid,
    scheduled_start_at=p_scheduled_start_at,scheduled_end_at=(v_valid->>'scheduled_end_at')::timestamptz,
    updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1 where id=p_block_id;
  v_repack:=public.workshop_admin_repack_planned((v_valid->>'bay_id')::uuid,p_scheduled_start_at,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_id',p_block_id));
  v_after:=public.workshop_admin_block_snapshot(p_block_id);
  v_revision:=public.workshop_bump_revision();
  perform public.workshop_bump_station_revision(v_old_stage);
  if v_old_stage is distinct from (v_valid->>'stage_code') then perform public.workshop_bump_station_revision(v_valid->>'stage_code'); end if;
  v_response:=jsonb_build_object('ok',true,'admin_block',v_after,'revision',v_revision,'repack',v_repack);
  v_receipt:=public.workshop_admin_write_evidence(p_block_id,'moved',p_expected_version,v_before,v_after,v_response,p_metadata);
  return v_response||jsonb_build_object('receipt_id',v_receipt);
end $$;

create function public.resize_workshop_admin_block(
  p_block_id uuid,p_expected_version integer,p_duration_minutes integer,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_block public.workshop_admin_blocks%rowtype; v_stage text; v_bay_number integer; v_valid jsonb; v_before jsonb; v_after jsonb; v_repack jsonb; v_response jsonb; v_revision bigint; v_receipt uuid;
begin
  perform public.require_pdc_role('administrator');
  select * into v_block from public.workshop_admin_blocks where id=p_block_id for update;
  if not found or v_block.deleted_at is not null then return jsonb_build_object('ok',false,'error','admin_block_not_found'); end if;
  if v_block.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
  select s.code,b.bay_number into v_stage,v_bay_number from public.workshop_stages s join public.workshop_bays b on b.stage_id=s.id where s.id=v_block.stage_id and b.id=v_block.bay_id;
  v_valid:=public.workshop_admin_validate_interval(v_stage,v_bay_number,v_block.scheduled_start_at,p_duration_minutes);
  if not coalesce((v_valid->>'ok')::boolean,false) then return v_valid; end if;
  perform public.workshop_admin_lock_physical_bays(v_block.bay_id,null);
  if exists(select 1 from public.workshop_admin_blocks a where a.id<>p_block_id and a.bay_id=v_block.bay_id and a.deleted_at is null and a.scheduled_start_at<(v_valid->>'scheduled_end_at')::timestamptz and a.scheduled_end_at>v_block.scheduled_start_at) then return jsonb_build_object('ok',false,'error','admin_block_conflict'); end if;
  if exists(select 1 from public.workshop_bookings b where b.bay_id=v_block.bay_id and b.deleted_at is null and b.status in ('queued','started','stoppage','completed') and b.scheduled_start_at<(v_valid->>'scheduled_end_at')::timestamptz and b.scheduled_end_at>v_block.scheduled_start_at) then return jsonb_build_object('ok',false,'error','fixed_booking_conflict'); end if;
  v_before:=public.workshop_admin_block_snapshot(p_block_id);
  update public.workshop_admin_blocks set scheduled_end_at=(v_valid->>'scheduled_end_at')::timestamptz,duration_minutes=p_duration_minutes,updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1 where id=p_block_id;
  v_repack:=public.workshop_admin_repack_planned(v_block.bay_id,v_block.scheduled_start_at,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_id',p_block_id));
  v_after:=public.workshop_admin_block_snapshot(p_block_id);
  v_revision:=public.workshop_bump_revision(); perform public.workshop_bump_station_revision(v_stage);
  v_response:=jsonb_build_object('ok',true,'admin_block',v_after,'revision',v_revision,'repack',v_repack);
  v_receipt:=public.workshop_admin_write_evidence(p_block_id,'resized',p_expected_version,v_before,v_after,v_response,p_metadata);
  return v_response||jsonb_build_object('receipt_id',v_receipt);
end $$;

create function public.delete_workshop_admin_block(
  p_block_id uuid,p_expected_version integer,p_reason text default null,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_block public.workshop_admin_blocks%rowtype; v_stage text; v_before jsonb; v_after jsonb; v_response jsonb; v_revision bigint; v_receipt uuid;
begin
  perform public.require_pdc_role('administrator');
  select * into v_block from public.workshop_admin_blocks where id=p_block_id for update;
  if not found or v_block.deleted_at is not null then return jsonb_build_object('ok',false,'error','admin_block_not_found'); end if;
  if v_block.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
  perform public.workshop_admin_lock_physical_bays(v_block.bay_id,null);
  select code into v_stage from public.workshop_stages where id=v_block.stage_id;
  v_before:=public.workshop_admin_block_snapshot(p_block_id);
  update public.workshop_admin_blocks set deleted_at=clock_timestamp(),deleted_reason=nullif(btrim(coalesce(p_reason,'')),''),updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1 where id=p_block_id;
  v_after:=public.workshop_admin_block_snapshot(p_block_id);
  v_revision:=public.workshop_bump_revision(); perform public.workshop_bump_station_revision(v_stage);
  v_response:=jsonb_build_object('ok',true,'admin_block',v_after,'revision',v_revision,'repack',jsonb_build_object('shifted_booking_ids','[]'::jsonb,'shifted_count',0));
  v_receipt:=public.workshop_admin_write_evidence(p_block_id,'deleted',p_expected_version,v_before,v_after,v_response,p_metadata);
  return v_response||jsonb_build_object('receipt_id',v_receipt);
end $$;

-- Add blocks to both authoritative snapshot contracts without adding a second
-- Realtime channel. Existing workshop/station revision rows remain the sole
-- invalidation signals and every mutation above bumps them transactionally.
alter function public.get_workshop_snapshot(date,date) rename to get_workshop_snapshot_pre_170;
create function public.get_workshop_snapshot(p_date_from date default null,p_date_to date default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_snapshot jsonb; v_from timestamptz:=coalesce(p_date_from,current_date-interval '7 days'); v_to timestamptz:=coalesce(p_date_to,current_date+interval '21 days');
begin
  v_snapshot:=public.get_workshop_snapshot_pre_170(p_date_from,p_date_to);
  return v_snapshot||jsonb_build_object('admin_blocks',(select coalesce(jsonb_agg(public.workshop_admin_block_snapshot(a.id) order by a.scheduled_start_at,a.id),'[]'::jsonb) from public.workshop_admin_blocks a where a.deleted_at is null and a.scheduled_start_at<v_to and a.scheduled_end_at>v_from));
end $$;

alter function public.get_station_workshop_snapshot(text,date,date) rename to get_station_workshop_snapshot_pre_170;
create function public.get_station_workshop_snapshot(p_stage_code text,p_date_from date,p_date_to date)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_snapshot jsonb; v_stage text; v_from timestamptz; v_to timestamptz;
begin
  v_snapshot:=public.get_station_workshop_snapshot_pre_170(p_stage_code,p_date_from,p_date_to);
  v_stage:=v_snapshot#>>'{scope,stage_code}';
  v_from:=p_date_from::timestamp at time zone 'Australia/Perth';
  v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';
  return v_snapshot||jsonb_build_object('admin_blocks',(select coalesce(jsonb_agg(public.workshop_admin_block_snapshot(a.id) order by a.scheduled_start_at,a.id),'[]'::jsonb) from public.workshop_admin_blocks a join public.workshop_stages s on s.id=a.stage_id where a.deleted_at is null and s.code=v_stage and a.scheduled_start_at<v_to and a.scheduled_end_at>v_from));
end $$;

revoke all on function public.workshop_enforce_admin_block_booking_conflict(),public.workshop_reject_admin_block_evidence_mutation(),public.workshop_admin_block_snapshot(uuid),public.workshop_admin_lock_physical_bays(uuid,uuid),public.workshop_admin_validate_interval(text,integer,timestamptz,integer),public.workshop_admin_repack_planned(uuid,timestamptz,jsonb),public.workshop_admin_write_evidence(uuid,text,bigint,jsonb,jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb),public.move_workshop_admin_block(uuid,integer,text,integer,timestamptz,jsonb),public.resize_workshop_admin_block(uuid,integer,integer,jsonb),public.delete_workshop_admin_block(uuid,integer,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb),public.move_workshop_admin_block(uuid,integer,text,integer,timestamptz,jsonb),public.resize_workshop_admin_block(uuid,integer,integer,jsonb),public.delete_workshop_admin_block(uuid,integer,text,jsonb) to authenticated;
revoke all on function public.get_workshop_snapshot_pre_170(date,date),public.get_station_workshop_snapshot_pre_170(text,date,date) from public,anon,authenticated;
revoke all on function public.get_workshop_snapshot(date,date) from public,anon,authenticated;
grant execute on function public.get_workshop_snapshot(date,date) to service_role;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public,anon,authenticated;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated,service_role;

comment on function public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb) is 'Administrator-only versioned Admin block creation; exact physical-bay lock, operational calendar validation, planned-only atomic repack, immutable receipt, revision invalidation.';
comment on function public.move_workshop_admin_block(uuid,integer,text,integer,timestamptz,jsonb) is 'Administrator-only versioned Admin block move. Started, stoppage, completed and queued/fixed rows are never moved.';
comment on function public.resize_workshop_admin_block(uuid,integer,integer,jsonb) is 'Administrator-only versioned Admin block resize with planned-only atomic repack.';
comment on function public.delete_workshop_admin_block(uuid,integer,text,jsonb) is 'Administrator-only soft delete; planned bookings retain their confirmed position.';

insert into supabase_migrations.schema_migrations(version,name,statements)
values('170','authoritative_workshop_admin_blocks',array['versioned administrator downtime blocks, immutable history/receipts, planned-only atomic repack, authoritative snapshots'])
on conflict(version) do nothing;

commit;
