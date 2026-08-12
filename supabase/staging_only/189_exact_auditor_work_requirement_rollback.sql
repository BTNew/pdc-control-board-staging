-- Staging-only: restore work requirements absent before an Auditor batch during complete rollback.
begin;
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='188') or exists(select 1 from supabase_migrations.schema_migrations where version='189') then raise exception 'PDC_189_GUARD_MISMATCH';end if;end $guard$;
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
 update public.vehicle_work_items wi set required=false,updated_at=clock_timestamp()
 where not wi.completed and wi.vehicle_id in(select distinct c.vehicle_id from public.pdc_auditor_operation_changes c where c.run_id=p_run_id)
 and not exists(select 1 from jsonb_array_elements(v_run.before_work_requirements) b where (b->>'vehicle_id')::uuid=wi.vehicle_id and b->>'work_key'=wi.work_key);
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
insert into supabase_migrations.schema_migrations(version,name,statements) values('189','exact_auditor_work_requirement_rollback',array['Complete-run rollback restores pre-run required work keys including keys that were absent or false before reconciliation']);commit;
