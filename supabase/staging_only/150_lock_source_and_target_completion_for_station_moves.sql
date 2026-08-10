begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-150-source-station-completion-lock',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='149' and name='move_source_lines_between_workshop_stations')
     or exists(select 1 from supabase_migrations.schema_migrations where version='150') then
    raise exception 'PDC_WORKSHOP_150_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

create or replace function public.move_vehicle_workshop_source_line_stage(
  p_vehicle_id uuid,
  p_adjustment_id uuid,
  p_expected_version bigint,
  p_line_key text,
  p_stage_code text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $move$
declare
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_line_key text:=btrim(coalesce(p_line_key,''));
  v_stage text:=upper(btrim(coalesce(p_stage_code,'')));
  v_operation_line_id uuid;
  v_source public.pdc_authenticated_email_operation_lines%rowtype;
  v_before public.vehicle_workshop_line_adjustments%rowtype;
  v_after public.vehicle_workshop_line_adjustments%rowtype;
  v_source_stage text;
  v_current_stage text;
begin
  perform public.require_pdc_role('operator');
  if v_actor is null or v_email='' then raise exception 'unauthorized' using errcode='42501'; end if;
  if p_expected_version is null or p_expected_version<0
     or v_line_key !~ '^source:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or v_stage !~ '^[A-Z][A-Z0-9_]{1,39}$' then
    raise exception 'invalid_workshop_station_move' using errcode='22023';
  end if;
  v_operation_line_id:=substring(v_line_key from 8)::uuid;

  perform 1 from public.vehicles v
   where v.id=p_vehicle_id and v.lifecycle_state='active' and v.deleted_at is null for update;
  if not found then raise exception 'vehicle_not_found' using errcode='P0001'; end if;

  select * into v_source from public.pdc_authenticated_email_operation_lines ol
   where ol.operation_line_id=v_operation_line_id and ol.vehicle_id=p_vehicle_id for share;
  if not found then raise exception 'workshop_source_line_not_found' using errcode='P0001'; end if;
  v_source_stage:=coalesce(public.workshop_stage_code_for_work_key(v_source.work_key),upper(regexp_replace(btrim(v_source.work_key),'[^a-zA-Z0-9]+','_','g')));

  perform pg_advisory_xact_lock(hashtextextended('vehicle-workshop-line:'||p_vehicle_id::text||':'||v_line_key,0));
  if p_adjustment_id is null then
    if p_expected_version<>0 then raise exception 'stale_line_version' using errcode='40001'; end if;
    if exists(select 1 from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p_vehicle_id and a.line_key=v_line_key) then
      raise exception 'workshop_line_conflict' using errcode='40001';
    end if;
    v_current_stage:=v_source_stage;
  else
    select * into v_before from public.vehicle_workshop_line_adjustments a
     where a.adjustment_id=p_adjustment_id and a.vehicle_id=p_vehicle_id for update;
    if not found then raise exception 'workshop_line_not_found' using errcode='P0001'; end if;
    if not v_before.active then raise exception 'workshop_line_deleted' using errcode='P0001'; end if;
    if v_before.source_kind<>'source' or v_before.line_key<>v_line_key then raise exception 'workshop_line_identity_mismatch' using errcode='22023'; end if;
    if v_before.version<>p_expected_version then raise exception 'stale_line_version' using errcode='40001'; end if;
    v_current_stage:=v_before.stage_code;
  end if;

  perform 1 from public.vehicle_work_items wi
   where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
     and coalesce(public.workshop_stage_code_for_work_key(wi.work_key),upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')))=v_current_stage
   for share;
  if not found then raise exception 'workshop_source_stage_completed_or_unavailable' using errcode='P0001'; end if;

  perform 1 from public.vehicle_work_items wi
   where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
     and coalesce(public.workshop_stage_code_for_work_key(wi.work_key),upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')))=v_stage
   for share;
  if not found then raise exception 'workshop_stage_not_editable' using errcode='P0001'; end if;

  if p_adjustment_id is null then
    insert into public.vehicle_workshop_line_adjustments(
      vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by
    ) values(p_vehicle_id,v_line_key,'source',v_stage,v_source.description,v_source.estimated_hours,true,1,v_actor,v_actor)
    returning * into v_after;
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('insert','vehicle_workshop_line_adjustments',v_after.adjustment_id,p_vehicle_id,v_actor,v_email,null,to_jsonb(v_after),
      jsonb_build_object('source','vehicle_detail_workshop_station_move_150','source_kind','source','line_key',v_line_key,
        'source_stage_code',v_source_stage,'previous_effective_stage_code',v_current_stage,'target_stage_code',v_stage,
        'source_operation_line_id',v_operation_line_id,'hours_changed',false,'bookings_changed',false,
        'parts_changed',false,'completion_changed',false,'location_changed',false));
  else
    update public.vehicle_workshop_line_adjustments
       set stage_code=v_stage,version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
     where adjustment_id=v_before.adjustment_id returning * into v_after;
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('update','vehicle_workshop_line_adjustments',v_after.adjustment_id,p_vehicle_id,v_actor,v_email,to_jsonb(v_before),to_jsonb(v_after),
      jsonb_build_object('source','vehicle_detail_workshop_station_move_150','source_kind','source','line_key',v_line_key,
        'source_stage_code',v_source_stage,'previous_effective_stage_code',v_current_stage,'target_stage_code',v_stage,
        'source_operation_line_id',v_operation_line_id,'hours_changed',false,'bookings_changed',false,
        'parts_changed',false,'completion_changed',false,'location_changed',false));
  end if;

  return jsonb_build_object('ok',true,'code','workshop_source_line_station_moved','data',jsonb_build_object(
    'adjustment_id',v_after.adjustment_id,'line_key',v_after.line_key,'stage_code',v_after.stage_code,
    'description',v_after.description,'estimated_hours',v_after.estimated_hours,'version',v_after.version,
    'vehicle_id',v_after.vehicle_id));
end
$move$;

revoke all on function public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text) from public,anon,authenticated,service_role;
grant execute on function public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text) to authenticated;
comment on function public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text) is
  'Staging operator-only station reassignment for one incomplete effective source operation to one existing incomplete target station. Exact hours and description are preserved; no booking, Parts, completion, vehicle or location mutation.';

do $assert$
declare v_definition text;
begin
  select lower(pg_get_functiondef('public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text)'::regprocedure)) into v_definition;
  if position('workshop_source_stage_completed_or_unavailable' in v_definition)=0
     or position('v_current_stage' in v_definition)=0
     or position('wi.completed' in v_definition)=0
     or position('vehicle_parts_updates' in v_definition)>0
     or position('workshop_bookings' in v_definition)>0
     or position('update public.vehicles' in v_definition)>0
     or position('update public.vehicle_work_items' in v_definition)>0 then
    raise exception 'PDC_WORKSHOP_150_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end
$assert$;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '150','lock_source_and_target_completion_for_station_moves',array[
    'lock and validate the current effective source station as required and incomplete',
    'retain exact line identity optimistic version and target completion checks',
    'preserve station-only audited overlay mutation boundaries'
  ]
);
commit;
