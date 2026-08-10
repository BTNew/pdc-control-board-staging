begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-151-exact-workshop-role',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='150' and name='lock_source_and_target_completion_for_station_moves')
     or exists(select 1 from supabase_migrations.schema_migrations where version='151') then
    raise exception 'PDC_WORKSHOP_151_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

do $patch$
declare
  v_signature regprocedure:='public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text)'::regprocedure;
  v_definition text;
  v_patched text;
begin
  select pg_get_functiondef(v_signature) into v_definition;
  v_patched:=replace(v_definition,
    'PERFORM public.require_pdc_role(''operator''::public.pdc_role);',
    'PERFORM public.workshop_require_planner_operator();');
  v_patched:=replace(v_patched,
    'PERFORM public.require_pdc_role(''operator'');',
    'PERFORM public.workshop_require_planner_operator();');
  v_patched:=replace(v_patched,
    'perform public.require_pdc_role(''operator''::public.pdc_role);',
    'perform public.workshop_require_planner_operator();');
  v_patched:=replace(v_patched,
    'perform public.require_pdc_role(''operator'');',
    'perform public.workshop_require_planner_operator();');
  if v_patched=v_definition
     or position('public.workshop_require_planner_operator()' in v_patched)=0
     or position('public.require_pdc_role' in v_patched)>0 then
    raise exception 'PDC_WORKSHOP_151_ROLE_PATCH_FAILED' using errcode='55000';
  end if;
  execute v_patched;
end
$patch$;

revoke all on function public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text) from public,anon,authenticated,service_role;
grant execute on function public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text) to authenticated;
comment on function public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text) is
  'Staging exact Operator/Administrator-only station reassignment for one incomplete effective source operation. Importer and Viewer roles fail closed. Exact hours and description are preserved; operational source, bookings, Parts, completion, vehicle and location data are immutable.';

do $assert$
declare v_definition text;
begin
  select lower(pg_get_functiondef('public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text)'::regprocedure)) into v_definition;
  if position('public.workshop_require_planner_operator()' in v_definition)=0
     or position('public.require_pdc_role' in v_definition)>0
     or position('workshop_source_stage_completed_or_unavailable' in v_definition)=0
     or position('workshop_stage_not_editable' in v_definition)=0
     or position('update public.vehicles' in v_definition)>0
     or position('update public.vehicle_work_items' in v_definition)>0
     or position('workshop_bookings' in v_definition)>0
     or position('vehicle_parts_updates' in v_definition)>0 then
    raise exception 'PDC_WORKSHOP_151_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end
$assert$;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '151','require_exact_workshop_role_for_source_station_moves',array[
    'replace inherited Importer-compatible role gate with exact Workshop Operator/Administrator authority',
    'retain authenticated RPC exposure with fail-closed internal exact-role enforcement',
    'preserve source and target completion locks and station-only mutation boundaries'
  ]
);
commit;
