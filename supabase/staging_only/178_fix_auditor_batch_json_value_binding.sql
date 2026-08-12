-- Staging-only remediation: bind JSON array elements as JSONB values before UUID casts.
begin;
do $guard$ begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or not exists(select 1 from supabase_migrations.schema_migrations where version='177' and name='pmb_email_monitor_durable_queue_and_scoped_identity')
 or exists(select 1 from supabase_migrations.schema_migrations where version='178') then raise exception 'PDC_178_GUARD_MISMATCH';end if;
end $guard$;
create or replace function public.apply_pdc_auditor_operation_batch(p_request_id uuid,p_instruction text,p_scope jsonb,p_changes jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $apply$
declare
 v_executor jsonb:=public.pdc_auditor_executor_scope();v_dealer text:=v_executor->>'dealer_code';v_uid uuid:=(v_executor->>'user_id')::uuid;v_email text:=v_executor->>'email';
 v_run uuid;v_item jsonb;v_action text;v_reason text;v_operation uuid;v_vehicle uuid;v_source public.pdc_authenticated_email_operation_lines%rowtype;
 v_before public.vehicle_workshop_line_adjustments%rowtype;v_after public.vehicle_workshop_line_adjustments%rowtype;v_existing_run public.pdc_auditor_operation_runs%rowtype;
 v_stage text;v_work_key text;v_affected uuid[]:='{}';v_seq integer:=0;v_before_work jsonb;v_stock text;v_jc text;v_override boolean;v_identifier text;v_has_before boolean;
begin
 if p_request_id is null or p_scope is null or jsonb_typeof(p_scope)<>'object' or p_changes is null or jsonb_typeof(p_changes)<>'array'
    or length(btrim(coalesce(p_instruction,''))) not between 3 and 2000
    or lower(p_instruction) !~ '(^|[^a-z])(apply|change|fix|update|correct)([^a-z]|$)' then
  raise exception 'pdc_auditor_apply_instruction_required' using errcode='22023';
 end if;
 if coalesce(p_scope->>'dealer_code','')<>v_dealer or jsonb_array_length(p_changes)<1 or jsonb_array_length(p_changes)>(v_executor->>'max_corrections_per_run')::integer then
  raise exception 'pdc_auditor_apply_scope_invalid' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-auditor-instruction-batch:'||v_dealer,0));
 select * into v_existing_run from public.pdc_auditor_operation_runs where request_id=p_request_id;
 if found then return jsonb_build_object('ok',true,'code','already_applied','run_id',v_existing_run.run_id,'change_count',v_existing_run.change_count); end if;

 select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed)),'[]'::jsonb)
 into v_before_work from public.vehicle_work_items wi where wi.vehicle_id in(
  select distinct coalesce(nullif(j.value->>'vehicle_id','')::uuid,ol.vehicle_id)
  from jsonb_array_elements(p_changes) as j(value) left join public.pdc_authenticated_email_operation_lines ol on ol.operation_line_id=nullif(j.value->>'operation_line_id','')::uuid
 );
 insert into public.pdc_auditor_operation_runs(request_id,dealer_code,mode,scope,authorizing_instruction,bot_identity,status,change_count,before_work_requirements)
 values(p_request_id,v_dealer,'apply',p_scope,btrim(p_instruction),v_email,'applied',jsonb_array_length(p_changes),v_before_work) returning run_id into v_run;

 for v_item in select value from jsonb_array_elements(p_changes) loop
  v_seq:=v_seq+1;v_action:=v_item->>'action';v_reason:=btrim(coalesce(v_item->>'reason',''));v_override:=coalesce((v_item->>'override_manual_assignment')::boolean,false);
  if v_action not in('add','edit','delete','split','combine','reorder','move') or length(v_reason) not between 3 and 1000 then raise exception 'pdc_auditor_change_invalid' using errcode='22023'; end if;
  if v_action='add' then
   v_before:=null;v_has_before:=false;
   v_vehicle:=nullif(v_item->>'vehicle_id','')::uuid;v_operation:=null;v_identifier:=gen_random_uuid()::text;
   select v.stock_number,v.job_card_number into v_stock,v_jc from public.vehicles v where v.id=v_vehicle and v.deleted_at is null and v.lifecycle_state='active' and public.pdc_auditor_vehicle_dealer(v.id)=v_dealer for share;
   if not found then raise exception 'pdc_auditor_vehicle_not_found' using errcode='P0002'; end if;
   v_work_key:=v_item->>'work_key';v_stage:=public.workshop_stage_code_for_work_key(v_work_key);
   if v_stage is null or length(btrim(coalesce(v_item->>'description',''))) not between 1 and 180 then raise exception 'pdc_auditor_add_invalid' using errcode='22023'; end if;
   insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,
    operation_code,display_order,manual_assignment_locked,correction_origin,job_card_number)
   values(v_vehicle,'auditor:'||v_identifier,'manual',v_stage,btrim(v_item->>'description'),nullif(v_item->>'estimated_hours','')::numeric,true,1,v_uid,v_uid,
    nullif(btrim(coalesce(v_item->>'operation_code','')),''),nullif(v_item->>'display_order','')::integer,false,'ai_auditor',coalesce(nullif(v_item->>'job_card_number',''),v_jc)) returning * into v_after;
  else
   v_operation:=nullif(v_item->>'operation_line_id','')::uuid;
   select * into v_source from public.pdc_authenticated_email_operation_lines where operation_line_id=v_operation for share;
   if not found then raise exception 'pdc_auditor_operation_not_found' using errcode='P0002'; end if;
   v_vehicle:=v_source.vehicle_id;v_identifier:=v_operation::text;
   select v.stock_number,coalesce(v_source.job_card_number,v.job_card_number) into v_stock,v_jc from public.vehicles v where v.id=v_vehicle and v.deleted_at is null and public.pdc_auditor_vehicle_dealer(v.id)=v_dealer for share;
   if not found then raise exception 'pdc_auditor_vehicle_not_found' using errcode='P0002'; end if;
   select * into v_before from public.vehicle_workshop_line_adjustments a where a.vehicle_id=v_vehicle and a.line_key='source:'||v_operation::text for update;
   v_has_before:=found;
   if v_has_before and v_before.manual_assignment_locked and not v_override then raise exception 'pdc_auditor_manual_assignment_locked' using errcode='42501'; end if;
   v_work_key:=coalesce(nullif(v_item->>'work_key',''),public.pdc_auditor_work_key_for_stage(v_before.stage_code),v_source.work_key);
   v_stage:=public.workshop_stage_code_for_work_key(v_work_key);
   if v_stage is null then raise exception 'pdc_auditor_work_key_invalid' using errcode='22023'; end if;
   if not v_has_before then
    insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,
      operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number)
    values(v_vehicle,'source:'||v_operation::text,'source',v_stage,coalesce(nullif(btrim(v_item->>'description'),''),v_source.description),
      coalesce(nullif(v_item->>'estimated_hours','')::numeric,v_source.estimated_hours),v_action<>'delete',1,v_uid,v_uid,
      coalesce(nullif(btrim(v_item->>'operation_code'),''),v_source.operation_no),coalesce(nullif(v_item->>'display_order','')::integer,v_source.source_row_no),false,'ai_auditor',v_operation,v_jc) returning * into v_after;
   else
    update public.vehicle_workshop_line_adjustments set stage_code=v_stage,
      description=coalesce(nullif(btrim(v_item->>'description'),''),description),
      estimated_hours=coalesce(nullif(v_item->>'estimated_hours','')::numeric,estimated_hours),
      operation_code=coalesce(nullif(btrim(v_item->>'operation_code'),''),operation_code),display_order=coalesce(nullif(v_item->>'display_order','')::integer,display_order),
      active=v_action<>'delete',version=version+1,updated_by=v_uid,updated_at=clock_timestamp(),correction_origin='ai_auditor',source_operation_line_id=v_operation,
      manual_assignment_locked=case when v_override then false else manual_assignment_locked end where adjustment_id=v_before.adjustment_id returning * into v_after;
   end if;
  end if;
  v_affected:=array_append(v_affected,v_vehicle);
  insert into public.pdc_auditor_operation_changes(run_id,sequence_no,vehicle_id,stock_number,jc_number,operation_line_identifier,adjustment_id,action,previous_value,new_value,reason,authorizing_instruction,bot_identity)
  values(v_run,v_seq,v_vehicle,v_stock,v_jc,v_identifier,v_after.adjustment_id,v_action,case when not v_has_before then null else to_jsonb(v_before) end,to_jsonb(v_after),v_reason,btrim(p_instruction),v_email);
  insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  values('update','vehicle_workshop_line_adjustments',v_after.adjustment_id,v_vehicle,v_uid,v_email,case when not v_has_before then null else to_jsonb(v_before) end,to_jsonb(v_after),
   jsonb_build_object('source','ai_auditor_instruction_batch_176','run_id',v_run,'reason',v_reason,'authorizing_instruction',btrim(p_instruction),'bookings_changed',false,'location_changed',false,'completion_changed',false));
 end loop;

 for v_vehicle in select distinct unnest(v_affected) loop
  insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
  select v_vehicle,e.work_key,true,false,null,null,null,clock_timestamp() from(select distinct work_key from public.pdc_effective_operation_lines where vehicle_id=v_vehicle and active and work_key is not null)e
  on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp() where not public.vehicle_work_items.completed and not public.vehicle_work_items.required;
  update public.vehicle_work_items wi set required=false,updated_at=clock_timestamp() where wi.vehicle_id=v_vehicle and not wi.completed and wi.required
   and not exists(select 1 from public.pdc_effective_operation_lines e where e.vehicle_id=v_vehicle and e.active and e.work_key=wi.work_key);
 end loop;
 insert into public.pdc_auditor_revision(dealer_code,environment,event_type) values(v_dealer,'staging','operation_batch_applied');
 return jsonb_build_object('ok',true,'code','pdc_auditor_operation_batch_applied','run_id',v_run,'change_count',v_seq,'bookings_changed',false,'locations_changed',false,'completion_changed',false);
end
$apply$;
revoke all on function public.apply_pdc_auditor_operation_batch(uuid,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.apply_pdc_auditor_operation_batch(uuid,text,jsonb,jsonb) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('178','fix_auditor_batch_json_value_binding',array['Bind jsonb_array_elements output to a named JSONB value before optional vehicle and operation UUID casts']);
commit;
