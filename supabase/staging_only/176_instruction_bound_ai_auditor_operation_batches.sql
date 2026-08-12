-- Staging-only: instruction-bound, reversible AI Auditor operation-line batches.
-- Uses reversible overlays; source evidence and live bookings remain immutable.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-176-auditor-operation-batches',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='175' and name='restricted_ai_auditor_autonomous_corrections')
     or exists(select 1 from supabase_migrations.schema_migrations where version='176') then
    raise exception 'PDC_AUDITOR_176_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

alter table public.vehicle_workshop_line_adjustments
  add column if not exists operation_code text,
  add column if not exists display_order integer,
  add column if not exists manual_assignment_locked boolean not null default false,
  add column if not exists correction_origin text,
  add column if not exists source_operation_line_id uuid references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  add column if not exists job_card_number text;

update public.vehicle_workshop_line_adjustments a
   set manual_assignment_locked=true,
       source_operation_line_id=case when a.line_key ~ '^source:[0-9a-f-]{36}$' then substring(a.line_key from 8)::uuid else a.source_operation_line_id end
 where a.source_kind='source' and coalesce(a.correction_origin,'')<>'ai_auditor';

alter table public.vehicle_workshop_line_adjustments
  drop constraint if exists pdc_auditor_adjustment_operation_code_check,
  add constraint pdc_auditor_adjustment_operation_code_check check(operation_code is null or (operation_code=btrim(operation_code) and length(operation_code) between 1 and 80 and operation_code !~ '[[:cntrl:]]')),
  drop constraint if exists pdc_auditor_adjustment_display_order_check,
  add constraint pdc_auditor_adjustment_display_order_check check(display_order is null or display_order between 1 and 100000),
  drop constraint if exists pdc_auditor_adjustment_origin_check,
  add constraint pdc_auditor_adjustment_origin_check check(correction_origin is null or correction_origin in('ai_auditor','ai_auditor_rolled_back','manual_operator'));

create table public.pdc_auditor_operation_runs(
  run_id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  dealer_code text not null check(dealer_code in('14450','37047')),
  mode text not null check(mode in('apply','rollback')),
  scope jsonb not null,
  authorizing_instruction text not null check(length(btrim(authorizing_instruction)) between 3 and 2000 and authorizing_instruction !~ '[[:cntrl:]]'),
  bot_identity text not null,
  status text not null check(status in('applied','rolled_back')),
  change_count integer not null check(change_count between 0 and 50),
  before_work_requirements jsonb not null default '[]'::jsonb,
  applied_at timestamptz not null default clock_timestamp(),
  rolled_back_at timestamptz,
  rolled_back_by uuid,
  check((status='applied' and rolled_back_at is null and rolled_back_by is null) or (status='rolled_back' and rolled_back_at is not null and rolled_back_by is not null))
);

create table public.pdc_auditor_operation_changes(
  change_id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.pdc_auditor_operation_runs(run_id) on delete restrict,
  sequence_no integer not null check(sequence_no between 1 and 50),
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  stock_number text,
  jc_number text,
  operation_line_identifier text not null,
  adjustment_id uuid not null references public.vehicle_workshop_line_adjustments(adjustment_id) on delete restrict,
  action text not null check(action in('add','edit','delete','split','combine','reorder','move')),
  previous_value jsonb,
  new_value jsonb not null,
  reason text not null check(length(btrim(reason)) between 3 and 1000 and reason !~ '[[:cntrl:]]'),
  authorizing_instruction text not null,
  bot_identity text not null,
  changed_at timestamptz not null default clock_timestamp(),
  unique(run_id,sequence_no),
  unique(run_id,operation_line_identifier)
);

create trigger pdc_auditor_operation_runs_immutable before update or delete on public.pdc_auditor_operation_runs
for each row execute function public.pdc_auditor_reject_history_mutation();
create trigger pdc_auditor_operation_changes_immutable before update or delete on public.pdc_auditor_operation_changes
for each row execute function public.pdc_auditor_reject_history_mutation();

alter table public.pdc_auditor_operation_runs enable row level security;
alter table public.pdc_auditor_operation_changes enable row level security;
revoke all on public.pdc_auditor_operation_runs,public.pdc_auditor_operation_changes from public,anon,authenticated,service_role;

create or replace function public.pdc_auditor_work_key_for_stage(p_stage text)
returns text language sql stable security definer set search_path=pg_catalog,public as $$
 select case upper(btrim(coalesce(p_stage,'')))
  when 'BUS4X4' then 'bus4x4' when 'TINT' then 'tint' when 'HOIST' then 'hoist'
  when 'FITTING' then 'fitting' when 'FAB' then 'fabrication' when 'FABRICATION' then 'fabrication'
  when 'ELEC' then 'electrical' when 'ELECTRICAL' then 'electrical' when 'TYRE' then 'tyre'
  when 'PIT' then 'pitInspection' when 'PIT_INSPECTION' then 'pitInspection'
  when 'PARTS' then 'PARTS' when 'SUBLET' then 'sublet' else null end
$$;
revoke all on function public.pdc_auditor_work_key_for_stage(text) from public,anon,authenticated,service_role;

create or replace view public.pdc_effective_operation_lines with(security_invoker=false) as
with source_rows as(
 select ol.operation_line_id::text operation_line_identifier,ol.operation_line_id,ol.vehicle_id,
  coalesce(a.job_card_number,ol.job_card_number) job_card_number,
  coalesce(a.operation_code,ol.operation_no) operation_code,
  coalesce(public.pdc_auditor_work_key_for_stage(a.stage_code),ol.work_key) work_key,
  coalesce(a.description,ol.description) description,
  coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,
  coalesce(a.display_order,ol.source_row_no) display_order,
  coalesce(a.active,true) active,
  coalesce(a.manual_assignment_locked,false) manual_assignment_locked,
  a.adjustment_id,a.correction_origin
 from public.pdc_authenticated_email_operation_lines ol
 left join public.vehicle_workshop_line_adjustments a on a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text
), added_rows as(
 select a.adjustment_id::text,a.source_operation_line_id,a.vehicle_id,a.job_card_number,a.operation_code,
  public.pdc_auditor_work_key_for_stage(a.stage_code),a.description,a.estimated_hours,a.display_order,a.active,
  a.manual_assignment_locked,a.adjustment_id,a.correction_origin
 from public.vehicle_workshop_line_adjustments a
 where a.correction_origin='ai_auditor' and a.source_operation_line_id is null
)
select * from source_rows union all select * from added_rows;
revoke all on public.pdc_effective_operation_lines from public,anon,authenticated,service_role;

-- Operation-line corrections must never reschedule live bookings. The planner reads
-- effective hours, but scheduled times remain separate until an explicitly authorised booking RPC.
drop trigger if exists workshop_adjustment_booking_duration_sync on public.vehicle_workshop_line_adjustments;
drop trigger if exists pdc_operation_line_booking_duration_sync on public.pdc_authenticated_email_operation_lines;

create or replace function public.review_pdc_auditor_operation_batch(p_instruction text,p_scope jsonb,p_changes jsonb)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $review$
declare v_scope jsonb:=public.pdc_auditor_worker_scope(coalesce(p_scope->>'dealer_code','14450'));v_count integer;v_ambiguous jsonb;v_proposed jsonb;
begin
 if p_scope is null or jsonb_typeof(p_scope)<>'object' or p_changes is null or jsonb_typeof(p_changes)<>'array' then raise exception 'pdc_auditor_batch_invalid' using errcode='22023'; end if;
 v_count:=jsonb_array_length(p_changes); if v_count<1 or v_count>50 then raise exception 'pdc_auditor_batch_size_invalid' using errcode='22023'; end if;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into v_ambiguous from jsonb_array_elements(p_changes) x
  where coalesce(x->>'reason','')='' or coalesce(x->>'action','') not in('add','edit','delete','split','combine','reorder','move')
     or ((x->>'action')<>'add' and coalesce(x->>'operation_line_id','') !~ '^[0-9a-f-]{36}$')
     or coalesce(x->>'work_key','') not in('','bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS','sublet');
 select coalesce(jsonb_agg(x),'[]'::jsonb) into v_proposed from jsonb_array_elements(p_changes) x where not (x <@ v_ambiguous);
 return jsonb_build_object('ok',true,'mode','review','dealer_code',v_scope->>'dealer_code','instruction',p_instruction,
  'proposed_count',jsonb_array_length(v_proposed),'ambiguous_count',jsonb_array_length(v_ambiguous),'proposed',v_proposed,'ambiguous',v_ambiguous,
  'bookings_changed',false,'locations_changed',false,'completion_changed',false);
end
$review$;
revoke all on function public.review_pdc_auditor_operation_batch(text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.review_pdc_auditor_operation_batch(text,jsonb,jsonb) to authenticated;

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
  select distinct coalesce(nullif(x->>'vehicle_id','')::uuid,ol.vehicle_id)
  from jsonb_array_elements(p_changes)x left join public.pdc_authenticated_email_operation_lines ol on ol.operation_line_id=nullif(x->>'operation_line_id','')::uuid
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

create or replace function public.rollback_pdc_auditor_operation_run(p_run_id uuid,p_instruction text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $rollback$
declare v_executor jsonb:=public.pdc_auditor_executor_scope();v_uid uuid:=(v_executor->>'user_id')::uuid;v_email text:=v_executor->>'email';v_run public.pdc_auditor_operation_runs%rowtype;v_change record;v_before jsonb;v_work jsonb;
begin
 if length(btrim(coalesce(p_instruction,'')))<3 then raise exception 'pdc_auditor_rollback_instruction_required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-auditor-rollback:'||p_run_id::text,0));
 select * into v_run from public.pdc_auditor_operation_runs where run_id=p_run_id for update;
 if not found or v_run.status<>'applied' or v_run.dealer_code<>v_executor->>'dealer_code' then raise exception 'pdc_auditor_rollback_unavailable' using errcode='P0002'; end if;
 for v_change in select * from public.pdc_auditor_operation_changes where run_id=p_run_id order by sequence_no desc loop
  if v_change.previous_value is null then
   update public.vehicle_workshop_line_adjustments a set active=false,version=version+1,updated_by=v_uid,updated_at=clock_timestamp(),correction_origin='ai_auditor_rolled_back'
    where a.adjustment_id=v_change.adjustment_id and to_jsonb(a)=v_change.new_value;
   if not found then raise exception 'pdc_auditor_rollback_conflict' using errcode='40001'; end if;
  else
   v_before:=v_change.previous_value;
   update public.vehicle_workshop_line_adjustments a set stage_code=v_before->>'stage_code',description=v_before->>'description',estimated_hours=nullif(v_before->>'estimated_hours','')::numeric,
    active=(v_before->>'active')::boolean,version=(v_before->>'version')::bigint,updated_by=nullif(v_before->>'updated_by','')::uuid,updated_at=(v_before->>'updated_at')::timestamptz,
    operation_code=v_before->>'operation_code',display_order=nullif(v_before->>'display_order','')::integer,manual_assignment_locked=coalesce((v_before->>'manual_assignment_locked')::boolean,false),
    correction_origin=v_before->>'correction_origin',source_operation_line_id=nullif(v_before->>'source_operation_line_id','')::uuid,job_card_number=v_before->>'job_card_number'
   where a.adjustment_id=v_change.adjustment_id and to_jsonb(a)=v_change.new_value;
   if not found then raise exception 'pdc_auditor_rollback_conflict' using errcode='40001'; end if;
  end if;
 end loop;
 for v_work in select value from jsonb_array_elements(v_run.before_work_requirements) loop
  update public.vehicle_work_items set required=(v_work->>'required')::boolean,updated_at=clock_timestamp()
   where vehicle_id=(v_work->>'vehicle_id')::uuid and work_key=v_work->>'work_key' and completed=(v_work->>'completed')::boolean;
 end loop;
 execute 'alter table public.pdc_auditor_operation_runs disable trigger pdc_auditor_operation_runs_immutable';
 update public.pdc_auditor_operation_runs set status='rolled_back',rolled_back_at=clock_timestamp(),rolled_back_by=v_uid where run_id=p_run_id;
 execute 'alter table public.pdc_auditor_operation_runs enable trigger pdc_auditor_operation_runs_immutable';
 insert into public.pdc_auditor_revision(dealer_code,environment,event_type) values(v_run.dealer_code,'staging','operation_batch_rolled_back');
 insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
 values('rollback','pdc_auditor_operation_runs',p_run_id,v_uid,v_email,to_jsonb(v_run),(select to_jsonb(r) from public.pdc_auditor_operation_runs r where r.run_id=p_run_id),
  jsonb_build_object('source','ai_auditor_instruction_batch_176','authorizing_instruction',btrim(p_instruction),'complete_run_rollback',true,'bookings_changed',false));
 return jsonb_build_object('ok',true,'code','pdc_auditor_operation_run_rolled_back','run_id',p_run_id,'change_count',v_run.change_count,'bookings_changed',false);
end
$rollback$;
revoke all on function public.rollback_pdc_auditor_operation_run(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.rollback_pdc_auditor_operation_run(uuid,text) to authenticated;

create or replace function public.get_pdc_auditor_operation_run(p_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_scope jsonb:=public.pdc_auditor_worker_scope('14450');v_result jsonb;
begin
 select jsonb_build_object('run',to_jsonb(r),'changes',coalesce((select jsonb_agg(to_jsonb(c) order by c.sequence_no) from public.pdc_auditor_operation_changes c where c.run_id=r.run_id),'[]'::jsonb))
 into v_result from public.pdc_auditor_operation_runs r where r.run_id=p_run_id and r.dealer_code=v_scope->>'dealer_code';
 return coalesce(v_result,jsonb_build_object('run',null,'changes','[]'::jsonb));
end $$;
revoke all on function public.get_pdc_auditor_operation_run(uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_auditor_operation_run(uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('176','instruction_bound_ai_auditor_operation_batches',array[
 'review/apply instruction-bound operation-line overlays with batch scope and ambiguity isolation',
 'record vehicle stock JC operation identifier old/new reason timestamp bot and authorizing instruction',
 'preserve manual assignment locks unless each change explicitly overrides the lock',
 'recalculate effective department hours and required-work identifiers without changing live bookings locations or completion',
 'rollback a complete unchanged run and publish auditor revision events'
]);
commit;
