-- Staging-only authoritative Vehicle Detail Workshop line editing.
-- Imported/source labour remains immutable; operator edits are audited overlays.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('public.vehicles') is null or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.audit_events') is null or to_regclass('public.pdc_email_vehicle_revision') is null then
    raise exception 'PDC_MIGRATION_101_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create table if not exists public.vehicle_workshop_line_adjustments (
  adjustment_id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  line_key text not null check(length(line_key) between 8 and 220 and line_key=btrim(line_key) and line_key !~ '[[:cntrl:]]'),
  source_kind text not null check(source_kind in ('source','display','manual')),
  stage_code text not null check(stage_code ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  description text not null check(length(description) between 1 and 180 and description=btrim(description) and description !~ '[[:cntrl:]]'),
  estimated_hours numeric(6,2) not null check(estimated_hours between 0.25 and 999.75 and mod(estimated_hours,0.25)=0),
  active boolean not null default true,
  version bigint not null default 1 check(version>0),
  created_by uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_by uuid not null,
  updated_at timestamptz not null default clock_timestamp(),
  unique(vehicle_id,line_key)
);
alter table public.vehicle_workshop_line_adjustments enable row level security;
revoke all on table public.vehicle_workshop_line_adjustments from public,anon,authenticated;

create or replace function public.upsert_vehicle_workshop_line_adjustment(
  p_vehicle_id uuid,
  p_adjustment_id uuid,
  p_expected_version bigint,
  p_line_key text,
  p_stage_code text,
  p_description text,
  p_estimated_hours numeric
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $fn$
declare
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_vehicle public.vehicles%rowtype;
  v_before public.vehicle_workshop_line_adjustments%rowtype;
  v_after public.vehicle_workshop_line_adjustments%rowtype;
  v_line_key text:=btrim(coalesce(p_line_key,''));
  v_stage text:=upper(btrim(coalesce(p_stage_code,'')));
  v_description text:=btrim(coalesce(p_description,''));
  v_source_kind text;
begin
  perform public.require_pdc_role('operator');
  if v_actor is null or v_email='' then raise exception 'unauthorized' using errcode='42501'; end if;
  if p_expected_version is null or p_expected_version<0
     or v_stage !~ '^[A-Z][A-Z0-9_]{1,39}$'
     or length(v_description) not between 1 and 180 or v_description ~ '[[:cntrl:]]'
     or p_estimated_hours is null or p_estimated_hours<0.25 or p_estimated_hours>999.75
     or mod(p_estimated_hours,0.25)<>0 then
    raise exception 'invalid_workshop_line' using errcode='22023';
  end if;

  select * into v_vehicle from public.vehicles v
   where v.id=p_vehicle_id and v.lifecycle_state='active' and v.deleted_at is null for update;
  if not found then raise exception 'vehicle_not_found' using errcode='P0001'; end if;
  perform 1 from public.vehicle_work_items wi
   where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
     and coalesce(public.workshop_stage_code_for_work_key(wi.work_key),upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')))=v_stage;
  if not found then raise exception 'workshop_stage_not_editable' using errcode='P0001'; end if;

  if p_adjustment_id is null then
    if v_line_key='' then
      if p_expected_version<>v_vehicle.version then raise exception 'stale_vehicle_version' using errcode='40001'; end if;
      v_source_kind:='manual';
      v_line_key:='manual:'||gen_random_uuid()::text;
    else
      if p_expected_version<>0 then raise exception 'stale_line_version' using errcode='40001'; end if;
      if v_line_key !~ '^(source|operation|display):' or length(v_line_key)>220 then
        raise exception 'invalid_workshop_line_key' using errcode='22023';
      end if;
      v_source_kind:=case when v_line_key like 'display:%' then 'display' else 'source' end;
    end if;
    perform pg_advisory_xact_lock(hashtextextended('vehicle-workshop-line:'||p_vehicle_id::text||':'||v_line_key,0));
    if exists(select 1 from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p_vehicle_id and a.line_key=v_line_key) then
      raise exception 'workshop_line_conflict' using errcode='40001';
    end if;
    insert into public.vehicle_workshop_line_adjustments(
      vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by
    ) values(p_vehicle_id,v_line_key,v_source_kind,v_stage,v_description,p_estimated_hours,v_actor,v_actor)
    returning * into v_after;
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('insert','vehicle_workshop_line_adjustments',v_after.adjustment_id,p_vehicle_id,v_actor,v_email,null,to_jsonb(v_after),
      jsonb_build_object('source','vehicle_detail_workshop_line_101','source_kind',v_after.source_kind,'line_key',v_after.line_key,'bookings_changed',false,'parts_changed',false,'completion_changed',false));
  else
    select * into v_before from public.vehicle_workshop_line_adjustments a
     where a.adjustment_id=p_adjustment_id and a.vehicle_id=p_vehicle_id for update;
    if not found then raise exception 'workshop_line_not_found' using errcode='P0001'; end if;
    if v_before.version<>p_expected_version then raise exception 'stale_line_version' using errcode='40001'; end if;
    if not v_before.active then raise exception 'workshop_line_deleted' using errcode='P0001'; end if;
    if v_line_key<>'' and v_line_key<>v_before.line_key then raise exception 'workshop_line_identity_mismatch' using errcode='22023'; end if;
    update public.vehicle_workshop_line_adjustments set
      stage_code=v_stage,description=v_description,estimated_hours=p_estimated_hours,
      version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
     where adjustment_id=v_before.adjustment_id returning * into v_after;
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('update','vehicle_workshop_line_adjustments',v_after.adjustment_id,p_vehicle_id,v_actor,v_email,to_jsonb(v_before),to_jsonb(v_after),
      jsonb_build_object('source','vehicle_detail_workshop_line_101','source_kind',v_after.source_kind,'line_key',v_after.line_key,'bookings_changed',false,'parts_changed',false,'completion_changed',false));
  end if;
  return jsonb_build_object('ok',true,'code','workshop_line_saved','data',jsonb_build_object(
    'adjustment_id',v_after.adjustment_id,'line_key',v_after.line_key,'source_kind',v_after.source_kind,
    'stage_code',v_after.stage_code,'description',v_after.description,'estimated_hours',v_after.estimated_hours,
    'active',v_after.active,'version',v_after.version,'vehicle_id',v_after.vehicle_id));
end;
$fn$;
revoke all on function public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric) from public,anon,authenticated;
grant execute on function public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric) to authenticated,service_role;

create or replace function public.delete_vehicle_workshop_line_adjustment(
  p_vehicle_id uuid,p_adjustment_id uuid,p_expected_version bigint
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $fn$
declare
  v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_before public.vehicle_workshop_line_adjustments%rowtype; v_after public.vehicle_workshop_line_adjustments%rowtype;
begin
  perform public.require_pdc_role('operator');
  if v_actor is null or v_email='' then raise exception 'unauthorized' using errcode='42501'; end if;
  select * into v_before from public.vehicle_workshop_line_adjustments a
   where a.adjustment_id=p_adjustment_id and a.vehicle_id=p_vehicle_id for update;
  if not found or not v_before.active then raise exception 'workshop_line_not_found' using errcode='P0001'; end if;
  if v_before.version<>p_expected_version then raise exception 'stale_line_version' using errcode='40001'; end if;
  update public.vehicle_workshop_line_adjustments set active=false,version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
   where adjustment_id=p_adjustment_id returning * into v_after;
  insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  values('delete','vehicle_workshop_line_adjustments',v_after.adjustment_id,p_vehicle_id,v_actor,v_email,to_jsonb(v_before),to_jsonb(v_after),
    jsonb_build_object('source','vehicle_detail_workshop_line_101','source_kind',v_after.source_kind,'line_key',v_after.line_key,'bookings_changed',false,'parts_changed',false,'completion_changed',false));
  return jsonb_build_object('ok',true,'code','workshop_line_deleted','data',jsonb_build_object('adjustment_id',v_after.adjustment_id,'version',v_after.version));
end;
$fn$;
revoke all on function public.delete_vehicle_workshop_line_adjustment(uuid,uuid,bigint) from public,anon,authenticated;
grant execute on function public.delete_vehicle_workshop_line_adjustment(uuid,uuid,bigint) to authenticated,service_role;

create or replace function public.get_vehicle_workshop_detail(p_vehicle_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public
as $fn$
declare v_vehicle_version bigint;
begin
  perform public.require_pdc_role('viewer');
  select v.version into v_vehicle_version from public.vehicles v
   where v.id=p_vehicle_id and v.lifecycle_state='active' and v.deleted_at is null;
  if not found then raise exception 'vehicle_not_found' using errcode='P0001'; end if;
  return jsonb_build_object(
    'vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle_version,'generated_at',now(),
    'requirements',coalesce((select jsonb_agg(jsonb_build_object(
      'work_item_id',wi.id,'work_key',wi.work_key,
      'stage_code',coalesce(public.workshop_stage_code_for_work_key(wi.work_key),case lower(btrim(wi.work_key)) when 'parts' then 'PARTS' when 'sublet' then 'SUBLET' else upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')) end),
      'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at)
      order by coalesce(s.sort_order,999),wi.work_key,wi.id)
      from public.vehicle_work_items wi left join public.workshop_stages s on s.code=public.workshop_stage_code_for_work_key(wi.work_key)
      where wi.vehicle_id=p_vehicle_id and wi.required),'[]'::jsonb),
    'bookings',coalesce((select jsonb_agg(jsonb_build_object(
      'booking_id',b.id,'booking_version',b.version,'stage_code',s.code,'stage_name',s.display_name,
      'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',b.status,
      'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
      'default_duration_minutes',b.default_duration_minutes,'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at)
      order by s.sort_order,b.scheduled_start_at,b.id)
      from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id left join public.workshop_bays bay on bay.id=b.bay_id
      where b.vehicle_id=p_vehicle_id and b.deleted_at is null and b.status in ('queued','planned','started','stoppage','completed')),'[]'::jsonb),
    'line_adjustments',coalesce((select jsonb_agg(jsonb_build_object(
      'adjustment_id',a.adjustment_id,'line_key',a.line_key,'source_kind',a.source_kind,'stage_code',a.stage_code,
      'description',a.description,'estimated_hours',a.estimated_hours,'version',a.version,'created_at',a.created_at,'updated_at',a.updated_at)
      order by a.created_at,a.adjustment_id) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p_vehicle_id and a.active),'[]'::jsonb)
  );
end;
$fn$;
revoke all on function public.get_vehicle_workshop_detail(uuid) from public,anon,authenticated;
grant execute on function public.get_vehicle_workshop_detail(uuid) to authenticated,service_role;

create trigger pdc_email_vehicle_revision_workshop_line_adjustments
after insert or update or delete on public.vehicle_workshop_line_adjustments
for each statement execute function public.bump_pdc_email_vehicle_revision();

comment on table public.vehicle_workshop_line_adjustments is
  'Audited operator overlays and manual lines for Vehicle Detail Workshop work; immutable imported evidence, bookings, Parts and completion remain separate.';
comment on function public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric) is
  'Administrator/Controller authoritative add/edit for Vehicle Detail Workshop lines with line/vehicle optimistic concurrency and no scheduling side effects.';
commit;
