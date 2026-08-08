-- Staging-only migration 140: complete the Sublet lifecycle and make physical
-- Sublet absence authoritative for Workshop scheduling.
-- Expected return is planning only. Availability resumes on actual return.
begin;

select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-140',0));

-- Bind this migration to the exact staging environment and predecessor.
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='139' and name='navision_from_twa_it_parity')
     or exists(select 1 from supabase_migrations.schema_migrations where version='140')
     or to_regclass('public.pdc_sublet_bookings') is null
     or to_regclass('public.workshop_bookings') is null
     or to_regprocedure('public.update_pdc_sublet_booking_field(uuid,bigint,text,text)') is null
     or to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') is null
     or to_regprocedure('public.workshop_candidate_schedule_gate(uuid,text,timestamp with time zone)') is null then
    raise exception 'PDC_SUBLET_140_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;
end;
$guard$;

create or replace function public.pdc_sublet_away_on_date(p_vehicle_id uuid, p_workshop_date date)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,public
as $away$
  select exists(
    select 1
    from public.pdc_sublet_bookings s
    where s.vehicle_id=p_vehicle_id
      and s.booking_date is not null
      and p_workshop_date>=s.booking_date
      and (s.actual_return_date is null or p_workshop_date<s.actual_return_date)
  );
$away$;
revoke all on function public.pdc_sublet_away_on_date(uuid,date) from public,anon,authenticated,service_role;
comment on function public.pdc_sublet_away_on_date(uuid,date) is
  'True from Sublet outgoing date until (but not including) actual return date. Expected return is planning only.';

create or replace function public.pdc_workshop_booking_sublet_away_guard()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $guard$
declare
  v_start_date date;
  v_end_date date;
begin
  if new.deleted_at is not null or new.status::text not in ('planned','started','stoppage') then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||new.vehicle_id::text,0));
  v_start_date:=(new.scheduled_start_at at time zone 'Australia/Perth')::date;
  v_end_date:=((new.scheduled_end_at-interval '1 microsecond') at time zone 'Australia/Perth')::date;
  if exists(
    select 1 from generate_series(v_start_date,v_end_date,interval '1 day') d
    where public.pdc_sublet_away_on_date(new.vehicle_id,d::date)
  ) then
    raise exception '%',jsonb_build_object(
      'error','sublet_away','vehicle_id',new.vehicle_id,
      'scheduled_start_date',v_start_date,'scheduled_end_date',v_end_date
    )::text using errcode='23514';
  end if;
  return new;
end;
$guard$;
revoke all on function public.pdc_workshop_booking_sublet_away_guard() from public,anon,authenticated,service_role;
drop trigger if exists pdc_workshop_booking_sublet_away_guard on public.workshop_bookings;
create trigger pdc_workshop_booking_sublet_away_guard
before insert or update of vehicle_id,status,scheduled_start_at,scheduled_end_at,deleted_at
on public.workshop_bookings for each row execute function public.pdc_workshop_booking_sublet_away_guard();

create or replace function public.pdc_sublet_booking_workshop_overlap_guard()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $guard$
begin
  if new.booking_date is null and (new.expected_return_date is not null or new.actual_return_date is not null) then
    raise exception '%',jsonb_build_object('error','invalid_date_order','reason','booking_date_required','vehicle_id',new.vehicle_id)::text using errcode='23514';
  end if;
  if new.expected_return_date is not null and new.expected_return_date<new.booking_date then
    raise exception '%',jsonb_build_object('error','invalid_date_order','reason','expected_before_booking','vehicle_id',new.vehicle_id)::text using errcode='23514';
  end if;
  if new.actual_return_date is not null and new.actual_return_date<new.booking_date then
    raise exception '%',jsonb_build_object('error','invalid_date_order','reason','actual_before_booking','vehicle_id',new.vehicle_id)::text using errcode='23514';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||new.vehicle_id::text,0));
  if new.booking_date is not null and exists(
    select 1
    from public.workshop_bookings b
    where b.vehicle_id=new.vehicle_id
      and b.deleted_at is null
      and b.status::text in ('planned','started','stoppage')
      and daterange(
        new.booking_date,
        new.actual_return_date,
        '[)'
      ) && daterange(
        (b.scheduled_start_at at time zone 'Australia/Perth')::date,
        ((b.scheduled_end_at-interval '1 microsecond') at time zone 'Australia/Perth')::date+1,
        '[)'
      )
  ) then
    raise exception '%',jsonb_build_object('error','workshop_booking_conflict','vehicle_id',new.vehicle_id)::text using errcode='23514';
  end if;
  return new;
end;
$guard$;
revoke all on function public.pdc_sublet_booking_workshop_overlap_guard() from public,anon,authenticated,service_role;
drop trigger if exists pdc_sublet_booking_workshop_overlap_guard on public.pdc_sublet_bookings;
create trigger pdc_sublet_booking_workshop_overlap_guard
before insert or update of booking_date,expected_return_date,actual_return_date
on public.pdc_sublet_bookings for each row execute function public.pdc_sublet_booking_workshop_overlap_guard();

-- Keep the readable scheduling gate aligned with the trigger invariant. The
-- trigger remains the final authority for multi-day intervals and every write path.
create or replace function public.workshop_candidate_schedule_gate(
  p_vehicle_id uuid,
  p_stage_code text,
  p_scheduled_start_at timestamptz
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $gate$
declare v_stage_code text; v_candidate record; v_schedule_date date;
begin
  v_stage_code:=public.workshop_canonical_stage_code(p_stage_code);
  select e.* into v_candidate from public.workshop_station_eligibility(v_stage_code)e where e.vehicle_id=p_vehicle_id;
  if not found then return jsonb_build_object('ok',false,'error','vehicle_not_eligible_for_station'); end if;
  if coalesce(v_candidate.existing_booking,false) then return jsonb_build_object('ok',false,'error','active_booking_exists'); end if;
  v_schedule_date:=(p_scheduled_start_at at time zone 'Australia/Perth')::date;
  if public.pdc_sublet_away_on_date(p_vehicle_id,v_schedule_date) then
    return jsonb_build_object('ok',false,'error','sublet_away','sublet_date',v_schedule_date);
  end if;
  if v_candidate.current_location='IT' and v_candidate.eta_to_kewdale is not null
     and v_schedule_date<v_candidate.eta_to_kewdale then
    return jsonb_build_object('ok',false,'error','it_before_eta');
  end if;
  return jsonb_build_object('ok',true);
end;
$gate$;
revoke all on function public.workshop_candidate_schedule_gate(uuid,text,timestamptz) from public,anon,authenticated;

-- Replace the shared Sublet writer: validate the prospective row server-side,
-- permit retained history rows, serialize against workshop scheduling, and
-- preserve the existing version/history/revision contract.
create or replace function public.update_pdc_sublet_booking_field(
  p_vehicle_id uuid,
  p_expected_version bigint,
  p_field text,
  p_value text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $update$
declare
  v_user uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text:=public.current_pdc_user_role()::text;
  v_field text:=lower(btrim(coalesce(p_field,'')));
  v_value text:=btrim(coalesce(p_value,''));
  v_date date;
  v_bool boolean;
  v_before public.pdc_sublet_bookings%rowtype;
  v_after public.pdc_sublet_bookings%rowtype;
  v_exists boolean:=false;
  v_old text:='';
  v_revision bigint;
  v_next_booking_date date;
  v_next_expected_return_date date;
  v_next_actual_return_date date;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
  if v_user is null or v_email='' or v_role not in ('operator','importer','administrator') then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if p_vehicle_id is null or v_field not in (
    'provider','provider_email','po_sent_date','booking_date',
    'expected_return_date','actual_return_date','notes','email_sent'
  ) then return public.navision_backend_response(false,'invalid_input'); end if;
  if (v_field='provider' and length(v_value)>120)
     or (v_field='provider_email' and length(v_value)>254)
     or (v_field='notes' and length(v_value)>2000) then
    return public.navision_backend_response(false,'invalid_input');
  end if;
  if v_field in ('po_sent_date','booking_date','expected_return_date','actual_return_date') and v_value<>'' then
    begin
      v_date:=v_value::date;
      if to_char(v_date,'YYYY-MM-DD')<>v_value then return public.navision_backend_response(false,'invalid_date'); end if;
    exception when others then return public.navision_backend_response(false,'invalid_date');
    end;
  end if;
  if v_field='email_sent' then
    if lower(v_value) not in ('true','false') then return public.navision_backend_response(false,'invalid_boolean'); end if;
    v_bool:=lower(v_value)='true';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||p_vehicle_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-booking:'||p_vehicle_id::text,0));
  if not exists(
    select 1 from public.vehicles v
    where v.id=p_vehicle_id and v.deleted_at is null and v.lifecycle_state='active'
      and (
        exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=v.id and lower(wi.work_key)='sublet' and wi.required)
        or exists(select 1 from public.pdc_sublet_bookings s where s.vehicle_id=v.id)
      )
  ) then return public.navision_backend_response(false,'sublet_not_required'); end if;

  select * into v_before from public.pdc_sublet_bookings where vehicle_id=p_vehicle_id for update;
  v_exists:=found;
  if not v_exists and coalesce(p_expected_version,0)<>0 then
    return public.navision_backend_response(false,'version_conflict');
  elsif v_exists and coalesce(p_expected_version,0)<>v_before.version then
    return public.navision_backend_response(false,'version_conflict',jsonb_build_object('current_version',v_before.version));
  end if;

  v_next_booking_date:=case when v_field='booking_date' then v_date else v_before.booking_date end;
  v_next_expected_return_date:=case when v_field='expected_return_date' then v_date else v_before.expected_return_date end;
  v_next_actual_return_date:=case when v_field='actual_return_date' then v_date else v_before.actual_return_date end;
  if v_next_booking_date is null and (v_next_expected_return_date is not null or v_next_actual_return_date is not null) then
    return public.navision_backend_response(false,'invalid_date_order',jsonb_build_object('reason','booking_date_required'));
  end if;
  if v_next_expected_return_date is not null and v_next_expected_return_date<v_next_booking_date then
    return public.navision_backend_response(false,'invalid_date_order',jsonb_build_object('reason','expected_before_booking'));
  end if;
  if v_next_actual_return_date is not null and v_next_actual_return_date<v_next_booking_date then
    return public.navision_backend_response(false,'invalid_date_order',jsonb_build_object('reason','actual_before_booking'));
  end if;
  if v_next_booking_date is not null and exists(
    select 1 from public.workshop_bookings b
    where b.vehicle_id=p_vehicle_id and b.deleted_at is null and b.status::text in ('planned','started','stoppage')
      and daterange(v_next_booking_date,v_next_actual_return_date,'[)') && daterange(
        (b.scheduled_start_at at time zone 'Australia/Perth')::date,
        ((b.scheduled_end_at-interval '1 microsecond') at time zone 'Australia/Perth')::date+1,
        '[)'
      )
  ) then return public.navision_backend_response(false,'workshop_booking_conflict'); end if;

  if not v_exists then
    insert into public.pdc_sublet_bookings(vehicle_id,updated_by) values(p_vehicle_id,v_user) returning * into v_before;
  end if;
  v_old:=case v_field
    when 'provider' then v_before.provider
    when 'provider_email' then v_before.provider_email
    when 'po_sent_date' then coalesce(v_before.po_sent_date::text,'')
    when 'booking_date' then coalesce(v_before.booking_date::text,'')
    when 'expected_return_date' then coalesce(v_before.expected_return_date::text,'')
    when 'actual_return_date' then coalesce(v_before.actual_return_date::text,'')
    when 'notes' then v_before.notes
    when 'email_sent' then v_before.email_sent::text
  end;
  update public.pdc_sublet_bookings set
    provider=case when v_field='provider' then v_value else provider end,
    provider_email=case when v_field='provider_email' then v_value else provider_email end,
    po_sent_date=case when v_field='po_sent_date' then v_date else po_sent_date end,
    booking_date=case when v_field='booking_date' then v_date else booking_date end,
    expected_return_date=case when v_field='expected_return_date' then v_date else expected_return_date end,
    actual_return_date=case when v_field='actual_return_date' then v_date else actual_return_date end,
    notes=case when v_field='notes' then v_value else notes end,
    email_sent=case when v_field='email_sent' then v_bool else email_sent end,
    version=version+1,updated_at=clock_timestamp(),updated_by=v_user
  where vehicle_id=p_vehicle_id returning * into v_after;
  insert into public.pdc_sublet_booking_history(vehicle_id,actor_id,actor_email,field_name,old_value,new_value,booking_version)
  values(p_vehicle_id,v_user,v_email,v_field,v_old,v_value,v_after.version);
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp()
  where singleton returning revision into v_revision;
  return public.navision_backend_response(true,'updated',jsonb_build_object(
    'vehicle_id',p_vehicle_id,'version',v_after.version,'revision',v_revision
  ));
end;
$update$;
revoke all on function public.update_pdc_sublet_booking_field(uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.update_pdc_sublet_booking_field(uuid,bigint,text,text) to authenticated;

-- Extend the existing staging-authority snapshot to every canonical vehicle with
-- required Sublet work or retained Sublet history, not only email-receipt rows.
create or replace function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $snapshot$
declare v_role text; v_revision bigint; v_rows jsonb;
begin
  v_role:=public.current_pdc_user_role()::text;
  if v_role not in ('viewer','operator','importer','administrator') then return public.navision_backend_response(false,'unauthorized'); end if;
  select revision into v_revision from public.pdc_email_vehicle_revision where singleton;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,
    'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,
    'salesperson_reference',v.salesperson_reference,'registration',v.registration,'eta_to_kewdale',v.eta_to_kewdale,
    'current_location',v.current_location,'visible_on_board',v.visible_on_board,'source_system',v.source_system,
    'source_record_id',v.source_record_id,'updated_at',v.updated_at,
    'work_items',coalesce((select jsonb_agg(jsonb_build_object('work_key',wi.work_key,'required',wi.required,'completed',wi.completed,
      'completed_at',wi.completed_at,'completed_by',wi.completed_by) order by wi.work_key) from public.vehicle_work_items wi where wi.vehicle_id=v.id),'[]'::jsonb),
    'operation_lines',coalesce((select jsonb_agg(jsonb_build_object(
      'operation_line_id',ol.operation_line_id,'operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,
      'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source,'source_uid',ol.source_uid,
      'job_card_number',ol.job_card_number,'source_row_no',ol.source_row_no,'source_contract',ol.source_contract,
      'source_ref',case when ol.job_card_number is null then ol.operation_no else 'JC '||ol.job_card_number||' / '||ol.operation_no end,
      'created_at',ol.created_at) order by ol.source_row_no,
        case when ol.operation_no like 'OP%' then substring(ol.operation_no from 3)::integer else substring(ol.operation_no from 3 for 3)::integer end,
        ol.operation_line_id) from (select line.* from public.pdc_authenticated_email_operation_lines line
          where line.vehicle_id=v.id order by line.created_at desc,line.operation_line_id desc limit 50) ol),'[]'::jsonb),
    'parts_required',coalesce((select pu.parts_required from public.vehicle_parts_updates pu where pu.vehicle_id=v.id order by pu.updated_at desc,pu.id desc limit 1),false),
    'parts_completed',coalesce((select wi.completed from public.vehicle_work_items wi where wi.vehicle_id=v.id and wi.work_key='PARTS'),false),
    'parts_update',coalesce((select jsonb_build_object('parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,
      'parts_received',pu.parts_received,'parts_stoppage',pu.parts_stoppage,'parts_stoppage_reason',pu.parts_stoppage_reason,
      'worst_eta',pu.worst_eta,'previous_worst_eta',(select prior.worst_eta from public.vehicle_parts_updates prior where prior.vehicle_id=v.id and prior.id<>pu.id and prior.worst_eta is not null order by prior.updated_at desc,prior.id desc limit 1),
      'updated_by',pu.updated_by,'updated_at',pu.updated_at) from public.vehicle_parts_updates pu where pu.vehicle_id=v.id order by pu.updated_at desc,pu.id desc limit 1),'{}'::jsonb),
    'sublet_booking',coalesce((select jsonb_build_object('provider',s.provider,'provider_email',s.provider_email,
      'po_sent_date',s.po_sent_date,'booking_date',s.booking_date,'expected_return_date',s.expected_return_date,
      'actual_return_date',s.actual_return_date,'notes',s.notes,'email_sent',s.email_sent,'version',s.version,
      'provider_names',coalesce(to_jsonb(s.provider_names),'[]'::jsonb),'provider_source',coalesce(s.provider_source,''),'updated_at',s.updated_at)
      from public.pdc_sublet_bookings s where s.vehicle_id=v.id),'{}'::jsonb)
  ) order by coalesce(v.stock_number,v.vin,v.permanent_vehicle_id),v.id),'[]'::jsonb) into v_rows
  from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    and (
      exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v.id)
      or exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=v.id and lower(wi.work_key)='sublet' and wi.required)
      or exists(select 1 from public.pdc_sublet_bookings s where s.vehicle_id=v.id)
    );
  return public.navision_backend_response(true,'ok',jsonb_build_object('revision',coalesce(v_revision,1),'vehicles',v_rows));
end;
$snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public,anon,authenticated;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;

-- Refuse activation if existing data already violates the new invariant.
do $postcondition$
begin
  if exists(
    select 1 from public.pdc_sublet_bookings s join public.workshop_bookings b on b.vehicle_id=s.vehicle_id
    where s.booking_date is not null and b.deleted_at is null and b.status::text in ('planned','started','stoppage')
      and daterange(s.booking_date,s.actual_return_date,'[)') && daterange(
        (b.scheduled_start_at at time zone 'Australia/Perth')::date,
        ((b.scheduled_end_at-interval '1 microsecond') at time zone 'Australia/Perth')::date+1,
        '[)'
      )
  ) then raise exception 'PDC_SUBLET_140_EXISTING_WORKSHOP_CONFLICT' using errcode='55000'; end if;
end;
$postcondition$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('140','sublet_return_calendar_and_workshop_availability',array['digest-pinned committed installer; staging-only guarded SQL']);

commit;
