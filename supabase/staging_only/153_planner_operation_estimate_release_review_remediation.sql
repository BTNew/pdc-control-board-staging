-- Staging-only remediation for operation-estimate planner duration release review.
-- Restores Viewer reads, selects current operation identity, aligns server intervals,
-- reconciles conflict-free planned bookings, and closes migration ledger entries.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-153-operation-estimate-remediation',0));

do $guard$
declare v_snapshot text;
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='107')
    or not exists(select 1 from supabase_migrations.schema_migrations where version='151' and name='require_exact_workshop_role_for_source_station_moves')
    or exists(select 1 from supabase_migrations.schema_migrations where version in('152','153'))
    or to_regprocedure('public.workshop_vehicle_stage_estimated_hours(uuid,text)') is null
    or (select value from public.workshop_settings where key='default_booking_duration_minutes') is distinct from to_jsonb(60) then
   raise exception 'PDC_WORKSHOP_153_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
 select lower(pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure)) into v_snapshot;
 if position('workshop_require_planner_operator' in v_snapshot)=0 or position('estimated_hours' in v_snapshot)=0 then
   raise exception 'PDC_WORKSHOP_153_PREDECESSOR_MISMATCH' using errcode='55000';
 end if;
end
$guard$;

create or replace function public.workshop_vehicle_stage_estimated_hours(p_vehicle_id uuid,p_stage_code text)
returns numeric language sql stable security definer set search_path=pg_catalog,public as $fn$
 with durable_source as(
  -- Migration 107 deliberately distinguishes repeated OP numbers from separate
  -- authenticated documents. operation_line_id is the immutable identity; the
  -- unique(source_hash,operation_no) constraint rejects same-document duplicates.
  select ol.*
  from public.pdc_authenticated_email_operation_lines ol
  join public.pdc_authenticated_email_import_receipts r on r.receipt_id=ol.import_receipt_id
  where ol.vehicle_id=p_vehicle_id
 ), effective_source as(
  select public.workshop_canonical_stage_code(coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key))) stage_code,
         coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours
  from durable_source ol
  left join public.vehicle_workshop_line_adjustments a
    on a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text and a.active
 ), manual_lines as(
  select public.workshop_canonical_stage_code(a.stage_code) stage_code,a.estimated_hours
  from public.vehicle_workshop_line_adjustments a
  where a.vehicle_id=p_vehicle_id and a.active and a.source_kind='manual'
 )
 select nullif(round(sum(q.estimated_hours)::numeric,2),0)
 from(select * from effective_source union all select * from manual_lines)q
 where q.stage_code=public.workshop_canonical_stage_code(p_stage_code) and q.estimated_hours>0
$fn$;
revoke all on function public.workshop_vehicle_stage_estimated_hours(uuid,text) from public,anon,authenticated,service_role;

create or replace function public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id uuid,p_stage_id uuid)
returns integer language sql stable security definer set search_path=pg_catalog,public as $fn$
 select case when h.hours is null then null else greatest(60,round(h.hours*60)::integer) end
 from public.workshop_stages s
 cross join lateral(select public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,s.code) hours)h
 where s.id=p_stage_id
$fn$;
revoke all on function public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.workshop_booking_effective_duration_minutes(p_booking_id uuid)
returns integer language sql stable security definer set search_path=pg_catalog,public as $fn$
 select case when b.status in('queued','planned','started','stoppage') then
   coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(b.vehicle_id,b.stage_id),b.default_duration_minutes)
  else b.default_duration_minutes end
 from public.workshop_bookings b where b.id=p_booking_id and b.deleted_at is null
$fn$;
revoke all on function public.workshop_booking_effective_duration_minutes(uuid) from public,anon,authenticated,service_role;

create or replace function public.workshop_booking_effective_end_at(p_booking_id uuid)
returns timestamptz language sql stable security definer set search_path=pg_catalog,public as $fn$
 select case when b.status in('queued','planned','started','stoppage') then
   public.workshop_add_operational_minutes(b.scheduled_start_at,public.workshop_booking_effective_duration_minutes(b.id))
  else b.scheduled_end_at end
 from public.workshop_bookings b where b.id=p_booking_id and b.deleted_at is null
$fn$;
revoke all on function public.workshop_booking_effective_end_at(uuid) from public,anon,authenticated,service_role;

create or replace function public.workshop_planner_booking_dto(p_booking_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,public as $fn$
 with aa as(
  select a.booking_id,a.technician_id,t.name technician_name,a.assignment_type
  from public.workshop_booking_assignments a join public.workshop_technicians t on t.id=a.technician_id
  where a.booking_id=p_booking_id and a.released_at is null
  order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1)
 select jsonb_build_object(
  'booking_id',b.id,'vehicle_id',b.vehicle_id,
  'stage',jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key),
  'bay',case when bay.id is null then null else jsonb_build_object('id',bay.id,'bay_number',bay.bay_number,'code',bay.code,'display_name',bay.display_name) end,
  'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',public.workshop_booking_effective_end_at(b.id),
  'default_duration_minutes',public.workshop_booking_effective_duration_minutes(b.id),
  'estimated_operation_hours',case when b.status in('queued','planned','started','stoppage') then public.workshop_vehicle_stage_estimated_hours(b.vehicle_id,s.code) else null end,
  'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
  'stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
  'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,'version',b.version,
  'assignment',case when aa.technician_id is null then null else jsonb_build_object('technician_id',aa.technician_id,'technician_name',aa.technician_name,'assignment_type',aa.assignment_type) end)
 from public.workshop_bookings b
 join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
 join public.workshop_stages s on s.id=b.stage_id left join public.workshop_bays bay on bay.id=b.bay_id
 left join aa on aa.booking_id=b.id where b.id=p_booking_id and b.deleted_at is null
$fn$;
revoke all on function public.workshop_planner_booking_dto(uuid) from public,anon,authenticated,service_role;

do $snapshot$
declare v_definition text;v_patched text;
begin
 select pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure) into v_definition;
 v_patched:=replace(v_definition,'perform public.workshop_require_planner_operator();','perform public.require_pdc_role(''viewer'');');
 v_patched:=replace(v_patched,'b.scheduled_end_at>v_from','public.workshop_booking_effective_end_at(b.id)>v_from');
 if v_patched=v_definition or position('workshop_require_planner_operator' in lower(v_patched))>0
    or position('b.scheduled_end_at>v_from' in replace(v_patched,' ',''))>0 then
   raise exception 'PDC_WORKSHOP_153_SNAPSHOT_PATCH_FAILED' using errcode='55000';
 end if;
 execute v_patched;
end
$snapshot$;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public,anon,authenticated,service_role;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated,service_role;

do $validate$
declare v_definition text;v_patched text;
begin
 select pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure) into v_definition;
 v_patched:=replace(v_definition,'v_active boolean := p_status in (''queued'',''planned'',''started'',''stoppage'');',
  'v_active boolean := p_status in (''queued'',''planned'',''started'',''stoppage''); v_estimated_duration integer; v_candidate_end timestamptz;');
 v_patched:=replace(v_patched,
  'if not found then return jsonb_build_object(''ok'',false,''error'',''station_inactive_or_missing''); end if;',
  'if not found then return jsonb_build_object(''ok'',false,''error'',''station_inactive_or_missing''); end if; v_estimated_duration:=public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,p_stage_id); v_candidate_end:=case when v_estimated_duration is not null then public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) else p_scheduled_end_at end; if p_status in (''queued'',''planned'') and v_estimated_duration is not null and p_duration_minutes<>v_estimated_duration then return jsonb_build_object(''ok'',false,''error'',''operation_estimate_duration_mismatch'',''expected_minutes'',v_estimated_duration); end if;');
 v_patched:=replace(v_patched,'tstzrange(b.scheduled_start_at,b.scheduled_end_at,''[)'')','tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),''[)'')');
 v_patched:=replace(v_patched,'tstzrange(a.scheduled_start_at,a.scheduled_end_at,''[)'')','tstzrange(a.scheduled_start_at,public.workshop_booking_effective_end_at(a.booking_id),''[)'')');
 v_patched:=replace(v_patched,'tstzrange(p_scheduled_start_at,p_scheduled_end_at,''[)'')','tstzrange(p_scheduled_start_at,v_candidate_end,''[)'')');
 v_patched:=replace(v_patched,'workshop_technician_leave_date(p_technician_id,p_scheduled_start_at,p_scheduled_end_at)','workshop_technician_leave_date(p_technician_id,p_scheduled_start_at,v_candidate_end)');
 if v_patched=v_definition or position('operation_estimate_duration_mismatch' in v_patched)=0
    or position('tstzrange(b.scheduled_start_at,b.scheduled_end_at' in replace(v_patched,' ',''))>0
    or position('tstzrange(p_scheduled_start_at,p_scheduled_end_at' in replace(v_patched,' ',''))>0 then
   raise exception 'PDC_WORKSHOP_153_VALIDATOR_PATCH_FAILED' using errcode='55000';
 end if;
 execute v_patched;
end
$validate$;

do $cascade$
declare v_definition text;v_patched text;
begin
 select pg_get_functiondef('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure) into v_definition;
 v_patched:=replace(v_definition,'b.scheduled_end_at>p_scheduled_start_at','public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at');
 v_patched:=replace(v_patched,'v_new_end:=public.workshop_shift_operational_minutes(v_shifted.scheduled_end_at,v_shift_minutes);',
  'v_new_end:=public.workshop_add_operational_minutes(v_new_start,public.workshop_booking_effective_duration_minutes(v_shifted.id));');
 v_patched:=replace(v_patched,'scheduled_end_at=v_new_end,','scheduled_end_at=v_new_end, default_duration_minutes=public.workshop_booking_effective_duration_minutes(v_shifted.id),');
 if v_patched=v_definition or position('b.scheduled_end_at>p_scheduled_start_at' in replace(v_patched,' ',''))>0
    or position('workshop_booking_effective_duration_minutes(v_shifted.id)' in v_patched)=0 then
   raise exception 'PDC_WORKSHOP_153_CASCADE_PATCH_FAILED' using errcode='55000';
 end if;
 execute v_patched;
end
$cascade$;

do $start$
declare v_definition text;v_patched text;v_shifted_end text;
begin
 select pg_get_functiondef('public.start_workshop_work_pre_116(uuid,integer,timestamptz,jsonb)'::regprocedure) into v_definition;
 v_shifted_end:='public.workshop_add_operational_minutes(public.workshop_shift_operational_minutes(v_shifted.scheduled_start_at,v_delta),public.workshop_booking_effective_duration_minutes(v_shifted.id))';
 v_patched:=replace(v_definition,
  'v_new_end:=public.workshop_add_operational_minutes(v_now,v_target.default_duration_minutes);',
  'v_new_end:=public.workshop_add_operational_minutes(v_now,public.workshop_booking_effective_duration_minutes(v_target.id));');
 v_patched:=replace(v_patched,
  'scheduled_end_at=public.workshop_shift_operational_minutes(v_shifted.scheduled_end_at,v_delta),',
  'scheduled_end_at='||v_shifted_end||', default_duration_minutes=public.workshop_booking_effective_duration_minutes(v_shifted.id),');
 v_patched:=replace(v_patched,
  'public.workshop_shift_operational_minutes(v_shifted.scheduled_end_at,v_delta),''start_cascade_shifted''',
  v_shifted_end||',''start_cascade_shifted''');
 v_patched:=replace(v_patched,
  'update public.workshop_bookings set scheduled_start_at=v_now,scheduled_end_at=v_new_end,updated_by=auth.uid()',
  'update public.workshop_bookings set scheduled_start_at=v_now,scheduled_end_at=v_new_end,default_duration_minutes=public.workshop_booking_effective_duration_minutes(v_target.id),updated_by=auth.uid()');
 if v_patched=v_definition or position('v_target.default_duration_minutes' in v_patched)>0
    or position('workshop_shift_operational_minutes(v_shifted.scheduled_end_at,v_delta)' in replace(v_patched,' ',''))>0
    or position('default_duration_minutes=public.workshop_booking_effective_duration_minutes(v_target.id)' in replace(v_patched,' ',''))=0 then
   raise exception 'PDC_WORKSHOP_153_START_PATCH_FAILED' using errcode='55000';
 end if;
 execute v_patched;
end
$start$;

create or replace function public.workshop_sync_vehicle_stage_booking_duration(p_vehicle_id uuid,p_stage_code text,p_reason text)
returns integer language plpgsql security definer set search_path=pg_catalog,public,extensions as $sync$
declare v_stage text:=public.workshop_canonical_stage_code(p_stage_code);v_booking public.workshop_bookings%rowtype;v_minutes integer;v_end timestamptz;v_before jsonb;v_after jsonb;v_count integer:=0;v_id uuid;v_history_actor uuid;v_history_email text;
begin
 if p_vehicle_id is null or v_stage is null then return 0; end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:estimate-sync:'||p_vehicle_id::text,0));
 -- Acquire every affected scheduler resource in the same bay-then-technician order
 -- as booking RPCs before taking booking row locks.
 for v_id in
  select distinct b.bay_id from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
  where b.vehicle_id=p_vehicle_id and s.code=v_stage and b.deleted_at is null and b.status in('queued','planned','started','stoppage') and b.bay_id is not null order by b.bay_id
 loop perform pg_advisory_xact_lock(hashtextextended('workshop-bay:'||v_id::text,0)); end loop;
 for v_id in
  select distinct a.technician_id from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
   join public.workshop_booking_assignments a on a.booking_id=b.id and a.released_at is null
  where b.vehicle_id=p_vehicle_id and s.code=v_stage and b.deleted_at is null and b.status in('queued','planned','started','stoppage') order by a.technician_id
 loop perform pg_advisory_xact_lock(hashtextextended('workshop-technician:'||v_id::text,0)); end loop;
 v_minutes:=coalesce(greatest(60,round(public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,v_stage)*60)::integer),60);
 for v_booking in
  select b.* from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
  where b.vehicle_id=p_vehicle_id and s.code=v_stage and b.deleted_at is null and b.status in('queued','planned','started','stoppage')
  order by b.scheduled_start_at,b.id for update of b
 loop
  v_end:=public.workshop_add_operational_minutes(v_booking.scheduled_start_at,v_minutes);
  if v_booking.default_duration_minutes is distinct from v_minutes or v_booking.scheduled_end_at is distinct from v_end then
   v_before:=public.workshop_booking_snapshot(v_booking.id);
   update public.workshop_bookings set default_duration_minutes=v_minutes,scheduled_end_at=v_end,
    version=version+1 where id=v_booking.id;
   update public.workshop_booking_assignments set scheduled_start_at=v_booking.scheduled_start_at,scheduled_end_at=v_end
    where booking_id=v_booking.id and released_at is null;
   v_after:=public.workshop_booking_snapshot(v_booking.id);
   select u.id,u.email into v_history_actor,v_history_email from auth.users u where u.id=auth.uid();
   if v_history_actor is null then
    select u.id,u.email into v_history_actor,v_history_email from auth.users u where u.id=v_booking.updated_by;
   end if;
   insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
   values(v_booking.id,'operation_estimate_duration_reconciled',v_before,v_after,
    jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,'duration_minutes',v_minutes,
     'initiator_auth_uid',auth.uid(),'initiator_email',public.current_actor_email()),v_history_actor,coalesce(v_history_email,'system-reconciliation@pdc.invalid'));
   v_count:=v_count+1;
  end if;
 end loop;
 return v_count;
end
$sync$;
revoke all on function public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text) from public,anon,authenticated,service_role;

create or replace function public.workshop_reconcile_operation_line_booking_duration()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $trigger$
begin
 if tg_op in('UPDATE','DELETE') then perform public.workshop_sync_vehicle_stage_booking_duration(old.vehicle_id,old.normalized_stage,'authenticated_operation_line_'||lower(tg_op)); end if;
 if tg_op in('UPDATE','INSERT') and (tg_op='INSERT' or new.vehicle_id is distinct from old.vehicle_id or new.normalized_stage is distinct from old.normalized_stage or new.estimated_hours is distinct from old.estimated_hours) then
  perform public.workshop_sync_vehicle_stage_booking_duration(new.vehicle_id,new.normalized_stage,'authenticated_operation_line_'||lower(tg_op));
 end if;
 return null;
end
$trigger$;
revoke all on function public.workshop_reconcile_operation_line_booking_duration() from public,anon,authenticated,service_role;
drop trigger if exists pdc_operation_line_booking_duration_sync on public.pdc_authenticated_email_operation_lines;
create constraint trigger pdc_operation_line_booking_duration_sync after insert or update or delete on public.pdc_authenticated_email_operation_lines
deferrable initially deferred for each row execute function public.workshop_reconcile_operation_line_booking_duration();

create or replace function public.workshop_reconcile_adjustment_booking_duration()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $trigger$
begin
 if tg_op in('UPDATE','DELETE') and old.active then perform public.workshop_sync_vehicle_stage_booking_duration(old.vehicle_id,old.stage_code,'workshop_adjustment_'||lower(tg_op)); end if;
 if tg_op in('UPDATE','INSERT') and new.active and (tg_op='INSERT' or new.vehicle_id is distinct from old.vehicle_id or new.stage_code is distinct from old.stage_code or new.estimated_hours is distinct from old.estimated_hours or new.active is distinct from old.active) then
  perform public.workshop_sync_vehicle_stage_booking_duration(new.vehicle_id,new.stage_code,'workshop_adjustment_'||lower(tg_op));
 end if;
 return null;
end
$trigger$;
revoke all on function public.workshop_reconcile_adjustment_booking_duration() from public,anon,authenticated,service_role;
drop trigger if exists workshop_adjustment_booking_duration_sync on public.vehicle_workshop_line_adjustments;
create constraint trigger workshop_adjustment_booking_duration_sync after insert or update or delete on public.vehicle_workshop_line_adjustments
deferrable initially deferred for each row execute function public.workshop_reconcile_adjustment_booking_duration();

do $assert$
declare v_snapshot text;v_validate text;v_cascade text;v_start text;v_hours numeric;v_minutes integer;v_dto jsonb;v_booking uuid;
begin
 select lower(pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure)) into v_snapshot;
 select lower(pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure)) into v_validate;
 select lower(pg_get_functiondef('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure)) into v_cascade;
 select lower(pg_get_functiondef('public.start_workshop_work_pre_116(uuid,integer,timestamptz,jsonb)'::regprocedure)) into v_start;
 select b.id into v_booking from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id join public.workshop_stages s on s.id=b.stage_id
  where v.stock_number='12661296' and s.code='FITTING' and b.deleted_at is null order by b.created_at desc limit 1;
 select public.workshop_vehicle_stage_estimated_hours(v.id,'FITTING') into v_hours from public.vehicles v where v.stock_number='12661296' and v.deleted_at is null;
 v_minutes:=public.workshop_booking_effective_duration_minutes(v_booking);v_dto:=public.workshop_planner_booking_dto(v_booking);
 if v_hours<>6.50 or v_minutes<>390 or (v_dto->>'default_duration_minutes')::integer<>390
    or position('require_pdc_role(''viewer'')' in v_snapshot)=0
    or position('workshop_require_planner_operator' in v_snapshot)>0
    or position('operation_estimate_duration_mismatch' in v_validate)=0
    or position('v_candidate_end' in v_validate)=0
    or position('workshop_booking_effective_end_at' in v_cascade)=0
    or position('default_duration_minutes=public.workshop_booking_effective_duration_minutes(v_target.id)' in replace(v_start,' ',''))=0
    or not exists(select 1 from pg_trigger where tgname='pdc_operation_line_booking_duration_sync' and not tgisinternal)
    or not exists(select 1 from pg_trigger where tgname='workshop_adjustment_booking_duration_sync' and not tgisinternal) then
   raise exception 'PDC_WORKSHOP_153_POSTCONDITION_FAILED' using errcode='55000';
 end if;
end
$assert$;

insert into supabase_migrations.schema_migrations(version,name,statements) values
 ('152','planner_chip_operation_estimated_hours',array['Applied before ledger closure; exact source SHA-256 5f1a32ab45e2fc695d67e650bf4eab5fd475be5065c48d0549833ac911113b57','Removed three-hour fallback and exposed estimate scalars; superseded by Migration 153 review remediation']),
 ('153','planner_operation_estimate_release_review_remediation',array['Restore Viewer snapshot reads and authenticated/service_role ACL','Preserve Migration 107 durable source operation identities; reject same-document duplicates by source_hash/operation_no and apply overlays by exact operation_line_id UUID','Use effective operation-estimate interval in DTO, snapshot, validation, cascade and start lifecycle','Persist effective durations when starting or cascading legacy estimate-expanded rows while preserving fixed booking starts','Deferred operation-line and adjustment triggers acquire scheduler resources and reconcile persisted booking/assignment intervals or fail the source transaction on conflict','Close Migration 152 and 153 ledger entries']);
commit;
