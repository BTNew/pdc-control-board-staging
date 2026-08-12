-- Staging-only migration 237: remove minute-by-minute settings re-reads from
-- Workshop scheduling calculations while preserving exact calendar semantics.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='236' and name='complete_authorised_operation_rules')
     or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::numeric>236)
     or exists(select 1 from supabase_migrations.schema_migrations where version='237') then
    raise exception 'PDC_237_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end $guard$;

-- Preserve the exact pre-237 implementation for transactional parity evidence.
-- It is private and cannot become an alternate operational path.
create or replace function public.workshop_add_operational_minutes_pre237(
  p_start timestamptz,
  p_duration_minutes integer
) returns timestamptz
language plpgsql stable security definer
set search_path='pg_catalog','public'
as $fn$
declare
  v_cursor timestamptz:=date_trunc('minute',p_start);
  v_remaining integer:=p_duration_minutes;
  v_limit timestamptz:=date_trunc('minute',p_start)+interval '90 days';
begin
  if p_start is null or p_duration_minutes is null or p_duration_minutes<0 then
    raise exception 'Operational minutes must be non-negative' using errcode='22023';
  end if;
  if p_duration_minutes=0 then return p_start; end if;
  while v_remaining>0 and v_cursor<v_limit loop
    if public.workshop_calendar_minute_available(v_cursor) then
      v_remaining:=v_remaining-1;
    end if;
    v_cursor:=v_cursor+interval '1 minute';
  end loop;
  if v_remaining>0 then
    raise exception 'Operational duration exceeded canonical calendar guard' using errcode='22023';
  end if;
  return v_cursor;
end $fn$;
revoke all on function public.workshop_add_operational_minutes_pre237(timestamptz,integer) from public,anon,authenticated,service_role;

create or replace function public.workshop_add_operational_minutes(
  p_start timestamptz,
  p_duration_minutes integer
) returns timestamptz
language plpgsql stable security definer
set search_path='pg_catalog','public'
as $fn$
declare
  v_origin timestamptz:=date_trunc('minute',p_start);
  v_limit timestamptz:=date_trunc('minute',p_start)+interval '90 days';
  v_settings jsonb;
  v_start time;
  v_end time;
  v_working_week jsonb;
  v_closures jsonb;
  v_breaks jsonb;
  v_overtime jsonb;
  v_result timestamptz;
  v_cursor timestamptz:=date_trunc('minute',p_start);
  v_remaining integer:=p_duration_minutes;
  v_local timestamp;
  v_date date;
  v_clock time;
  v_day text;
  v_workday boolean;
  v_regular boolean;
  v_overtime_ok boolean;
  v_break boolean;
begin
  if p_start is null or p_duration_minutes is null or p_duration_minutes<0 then
    raise exception 'Operational minutes must be non-negative' using errcode='22023';
  end if;
  if p_duration_minutes=0 then return p_start; end if;

  select jsonb_object_agg(key,value)
  into v_settings
  from public.workshop_settings
  where key in('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows');
  begin
    v_start:=(v_settings->>'day_start_time')::time;
    v_end:=(v_settings->>'day_end_time')::time;
  exception when others then
    v_start:=null; v_end:=null;
  end;
  v_working_week:=v_settings->'working_week';
  v_closures:=v_settings->'closures';
  v_breaks:=v_settings->'break_windows';
  v_overtime:=v_settings->'overtime_windows';

  if v_start is null or v_end is null or v_start>=v_end
     or jsonb_typeof(v_working_week)<>'array' or jsonb_typeof(v_closures)<>'array'
     or jsonb_typeof(v_breaks)<>'array' or jsonb_typeof(v_overtime)<>'array' then
    raise exception 'Operational duration exceeded canonical calendar guard' using errcode='22023';
  end if;

  while v_remaining>0 and v_cursor<v_limit loop
    v_local:=v_cursor at time zone 'Australia/Perth';
    v_date:=v_local::date;
    v_clock:=v_local::time;
    v_day:=lower(to_char(v_local,'FMDay'));
    select exists(select 1 from jsonb_array_elements_text(v_working_week) d where lower(d)=v_day)
      into v_workday;
    if v_workday and not exists(
      select 1 from jsonb_array_elements(v_closures) c where c->>'date'=v_date::text
    ) then
      v_regular:=v_clock>=v_start and v_clock<v_end;
      select exists(
        select 1 from jsonb_array_elements(v_overtime) w
        where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
          and ((w ? 'date' and w->>'date'=v_date::text)
            or (not (w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in ('global','working_day',v_day)))
      ) into v_overtime_ok;
      select exists(
        select 1 from jsonb_array_elements(v_breaks) w
        where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
          and ((w ? 'date' and w->>'date'=v_date::text)
            or (not (w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in ('global','working_day',v_day)))
      ) into v_break;
      if (v_regular or v_overtime_ok) and not v_break then
        v_remaining:=v_remaining-1;
      end if;
    end if;
    v_cursor:=v_cursor+interval '1 minute';
  end loop;

  if v_remaining>0 then
    raise exception 'Operational duration exceeded canonical calendar guard' using errcode='22023';
  end if;
  v_result:=v_cursor;
  return v_result;
end $fn$;

-- Consolidate station eligibility, operation-hour evidence, selected bookings,
-- effective end times and vehicle/work-item DTOs into one snapshot query. The
-- pre-237 implementation repeatedly recomputed eligibility and hours per row.
create or replace function public.get_station_workshop_snapshot_pre_170(
  p_stage_code text,
  p_date_from date,
  p_date_to date
) returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','public'
as $fn$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_result jsonb;
begin
  perform public.require_pdc_role('viewer');
  v_stage:=public.workshop_canonical_stage_code(p_stage_code);
  select id into v_stage_id from public.workshop_stages where code=v_stage and active and planner_enabled;
  if v_stage_id is null then raise exception 'Unknown, inactive or planner-disabled workshop station' using errcode='22023'; end if;
  if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to>p_date_from+31 then raise exception 'Invalid station planner date range' using errcode='22023'; end if;
  v_from:=p_date_from::timestamp at time zone 'Australia/Perth';
  v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';

  with
  station as materialized(
    select s.id,s.code,s.display_name,s.is_physical,s.work_key
    from public.workshop_stages s where s.id=v_stage_id
  ),
  eligibility as materialized(
    select * from public.workshop_station_eligibility(v_stage)
  ),
  booking_seed as materialized(
    select b.*
    from public.workshop_bookings b
    join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
    where b.stage_id=v_stage_id and b.deleted_at is null
      and b.status in('queued','planned','started','stoppage','completed')
      and (
        (b.status in('queued','planned') and b.scheduled_start_at<v_to)
        or (b.status in('started','stoppage') and b.scheduled_start_at<v_to)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to)
      )
  ),
  candidate_ids as materialized(
    select vehicle_id from eligibility union select vehicle_id from booking_seed
  ),
  effective_source_lines as materialized(
    select ol.vehicle_id,
      public.workshop_canonical_stage_code(coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key))) stage_code,
      coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours
    from public.pdc_authenticated_email_operation_lines ol
    join public.pdc_authenticated_email_import_receipts r on r.receipt_id=ol.import_receipt_id
    join candidate_ids i on i.vehicle_id=ol.vehicle_id
    left join public.vehicle_workshop_line_adjustments a
      on a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text and a.active
    union all
    select a.vehicle_id,public.workshop_canonical_stage_code(a.stage_code),a.estimated_hours
    from public.vehicle_workshop_line_adjustments a join candidate_ids i on i.vehicle_id=a.vehicle_id
    where a.active and a.source_kind='manual'
  ),
  hours as materialized(
    select vehicle_id,nullif(round(sum(estimated_hours)::numeric,2),0) estimated_hours
    from effective_source_lines where stage_code=v_stage and estimated_hours>0 group by vehicle_id
  ),
  booking_duration as materialized(
    select b.*,case when b.status in('queued','planned','started','stoppage')
      then coalesce(greatest(60,round(h.estimated_hours*60)::integer),b.default_duration_minutes)
      else b.default_duration_minutes end effective_duration
    from booking_seed b left join hours h on h.vehicle_id=b.vehicle_id
  ),
  selected_bookings as materialized(
    select b.*,case when b.status in('queued','planned','started','stoppage')
      then public.workshop_add_operational_minutes(b.scheduled_start_at,b.effective_duration)
      else b.scheduled_end_at end effective_end
    from booking_duration b
  ),
  selected_filtered as materialized(
    select * from selected_bookings b where
      (b.status in('queued','planned') and b.effective_end>v_from)
      or b.status in('started','stoppage')
      or b.status='completed'
  ),
  selected_ids as materialized(
    select vehicle_id from eligibility union select vehicle_id from selected_filtered
  ),
  assignments as materialized(
    select distinct on(a.booking_id) a.booking_id,a.technician_id,t.name technician_name,a.assignment_type
    from public.workshop_booking_assignments a join public.workshop_technicians t on t.id=a.technician_id
    join selected_filtered b on b.id=a.booking_id
    where a.released_at is null
    order by a.booking_id,case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc
  ),
  requirement_rows as materialized(
    select wi.vehicle_id,jsonb_agg(jsonb_build_object(
      'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
      'completed',wi.completed,'completed_at',wi.completed_at
    ) order by wi.work_key) requirements
    from public.vehicle_work_items wi join selected_ids i on i.vehicle_id=wi.vehicle_id
    where wi.required and not wi.completed group by wi.vehicle_id
  ),
  stage_work_items as materialized(
    select wi.* from public.vehicle_work_items wi join selected_ids i on i.vehicle_id=wi.vehicle_id
    where public.workshop_stage_code_for_work_key(wi.work_key)=v_stage
  )
  select jsonb_build_object(
    'revision',public.workshop_current_station_revision(v_stage),'generated_at',now(),
    'semantics',jsonb_build_object(
      'outstanding_candidates','required canonical work items not completed and location-visible',
      'unscheduled_candidates','outstanding candidates without any active booking',
      'selected_date_bookings','scheduled rows intersecting the date plus started or stopped work carried forward until resolved'),
    'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
    'counts',jsonb_build_object(
      'outstanding_candidates',(select count(*) from eligibility),
      'unscheduled_candidates',(select count(*) from eligibility where not existing_booking),
      'selected_date_bookings',(select count(*) from selected_filtered)),
    'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key)) from station s),
    'bays',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',b.bay_number,'code',b.code,'display_name',b.display_name) order by b.bay_number),'[]'::jsonb) from public.workshop_bays b where b.stage_id=v_stage_id and b.is_active),
    'outstanding_candidates',(select coalesce(jsonb_agg(jsonb_build_object(
      'vehicle_id',e.vehicle_id,'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,
      'disabled_reason',e.disabled_reason,'estimated_hours',h.estimated_hours,
      'requirements',coalesce(rr.requirements,'[]'::jsonb)) order by e.vehicle_id),'[]'::jsonb)
      from eligibility e left join hours h on h.vehicle_id=e.vehicle_id left join requirement_rows rr on rr.vehicle_id=e.vehicle_id),
    'bookings',(select coalesce(jsonb_agg(jsonb_build_object(
      'booking_id',b.id,'vehicle_id',b.vehicle_id,
      'stage',jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key),
      'bay',case when bay.id is null then null else jsonb_build_object('id',bay.id,'bay_number',bay.bay_number,'code',bay.code,'display_name',bay.display_name) end,
      'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.effective_end,
      'default_duration_minutes',b.effective_duration,
      'estimated_operation_hours',case when b.status in('queued','planned','started','stoppage') then h.estimated_hours else null end,
      'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
      'stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
      'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,'version',b.version,
      'assignment',case when aa.technician_id is null then null else jsonb_build_object('technician_id',aa.technician_id,'technician_name',aa.technician_name,'assignment_type',aa.assignment_type) end
    ) order by b.scheduled_start_at,b.id),'[]'::jsonb)
      from selected_filtered b join station s on true left join public.workshop_bays bay on bay.id=b.bay_id
      left join hours h on h.vehicle_id=b.vehicle_id left join assignments aa on aa.booking_id=b.id),
    'vehicles',(select coalesce(jsonb_agg(jsonb_build_object(
      'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
      'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
      'customer_name',v.customer_name,'make',v.make,'model',v.model,'registration',v.registration,
      'current_location',v.current_location,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,
      'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
      'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,
      'version',v.version,'workshop_estimated_hours_by_stage',jsonb_build_object(v_stage,h.estimated_hours)
    ) order by v.stock_number nulls last,v.id),'[]'::jsonb)
      from public.vehicles v join selected_ids i on i.vehicle_id=v.id left join hours h on h.vehicle_id=v.id
      where v.lifecycle_state='active' and v.deleted_at is null),
    'work_items',(select coalesce(jsonb_agg(jsonb_build_object(
      'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
      'completed',wi.completed,'completed_at',wi.completed_at
    ) order by wi.vehicle_id,wi.work_key),'[]'::jsonb) from stage_work_items wi)
  ) into v_result;
  return v_result;
end $fn$;

-- Definition and authority postconditions.
do $post$
declare v_acl aclitem[]; v_security boolean; v_config text[];
begin
  select p.prosecdef,p.proconfig,p.proacl into v_security,v_config,v_acl
  from pg_proc p where p.oid='public.workshop_add_operational_minutes(timestamptz,integer)'::regprocedure;
  if not v_security or not ('search_path=pg_catalog, public'=any(v_config)) then
    raise exception 'PDC_237_FUNCTION_SECURITY_POSTCONDITION_FAILED' using errcode='55000';
  end if;
  if has_function_privilege('anon','public.workshop_add_operational_minutes_pre237(timestamptz,integer)','EXECUTE')
     or has_function_privilege('authenticated','public.workshop_add_operational_minutes_pre237(timestamptz,integer)','EXECUTE') then
    raise exception 'PDC_237_PRIVATE_BASELINE_EXPOSED' using errcode='55000';
  end if;
end $post$;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '237','workshop_snapshot_calendar_performance',array[
    'load Workshop calendar settings once per duration calculation',
    'preserve the minute cursor while evaluating cached calendar settings inline',
    'materialize eligibility hours and selected booking sets once per station snapshot'
  ]
);
commit;
