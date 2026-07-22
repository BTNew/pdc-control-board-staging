-- Migration 045: canonical work-item eligibility and controlled legacy-stage reconciliation.
-- pmb_stage is migration evidence only. It never creates planner authority.

create table if not exists public.legacy_stage_reconciliation_receipts (
  id uuid primary key,
  batch_id text not null check (batch_id ~ '^[A-Za-z0-9._:-]{1,120}$'),
  vehicle_id uuid not null references public.vehicles(id),
  legacy_stage text not null,
  canonical_station text not null references public.workshop_stages(code),
  classification text not null check (classification in (
    'A_SAFE_CREATE','B_ACTIVE_BOOKING','C_COMPLETED_OR_OBSOLETE','D_AMBIGUOUS'
  )),
  reason_code text not null,
  decision_state text not null check (decision_state in (
    'applied','skipped','ambiguous','rolled_back'
  )),
  evidence jsonb not null default '{}'::jsonb,
  proposed_work_item_id uuid,
  applied_work_item_id uuid references public.vehicle_work_items(id),
  work_item_updated_at timestamptz,
  created_at timestamptz not null default now(),
  rolled_back_at timestamptz,
  unique (batch_id, vehicle_id, canonical_station)
);

comment on table public.legacy_stage_reconciliation_receipts is
  'Service-only, sanitized receipts for deterministic legacy pmb_stage reconciliation. Contains no customer or note content.';

alter table public.legacy_stage_reconciliation_receipts enable row level security;
revoke all on table public.legacy_stage_reconciliation_receipts from public, anon, authenticated;

create or replace function public.preview_legacy_stage_reconciliation(p_vehicle_ids uuid[])
returns table(
  vehicle_id uuid,
  current_location text,
  legacy_pmb_stage text,
  canonical_station text,
  classification text,
  reason_code text,
  evidence jsonb,
  proposed_work_item_id uuid
)
language plpgsql stable security definer
set search_path=pg_catalog,public,extensions as $$
declare
  v_requested integer;
begin
  v_requested:=coalesce(cardinality(p_vehicle_ids),0);
  if v_requested<1 or v_requested>100 then
    raise exception 'Reconciliation preview requires 1 to 100 explicit vehicle IDs' using errcode='22023';
  end if;
  if exists(select 1 from unnest(p_vehicle_ids) x where x is null)
     or (select count(distinct x) from unnest(p_vehicle_ids) x)<>v_requested then
    raise exception 'Reconciliation vehicle IDs must be non-null and unique' using errcode='22023';
  end if;
  if (select count(*) from public.vehicles v where v.id=any(p_vehicle_ids))<>v_requested then
    raise exception 'Every reconciliation vehicle ID must resolve exactly once' using errcode='P0002';
  end if;

  return query
  with target as(
    select v.id,v.current_location,v.pmb_stage,v.lifecycle_state,v.deleted_at,
      public.workshop_canonical_stage_code(v.pmb_stage) station
    from public.vehicles v where v.id=any(p_vehicle_ids)
  ), facts as(
    select t.*,
      exists(select 1 from public.workshop_stages s where s.code=t.station and s.active and s.planner_enabled) planner_station,
      (select count(*) from public.vehicle_work_items wi where wi.vehicle_id=t.id and wi.required and not wi.completed
        and public.workshop_stage_code_for_work_key(wi.work_key)=t.station) open_items,
      (select count(*) from public.vehicle_work_items wi where wi.vehicle_id=t.id and wi.required and wi.completed
        and public.workshop_stage_code_for_work_key(wi.work_key)=t.station) completed_items,
      (select count(*) from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
        where b.vehicle_id=t.id and b.deleted_at is null and b.status in('queued','planned','started','stoppage') and s.code=t.station) active_same_bookings,
      (select count(*) from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
        where b.vehicle_id=t.id and b.deleted_at is null and b.status in('queued','planned','started','stoppage') and s.code<>t.station) active_other_bookings,
      exists(select 1 from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
        where b.vehicle_id=t.id and b.deleted_at is null and b.status in('queued','planned','started','stoppage')
          and s.code=t.station and (b.actual_start_at is not null or b.actual_end_at is not null)) booking_completion_markers,
      exists(select 1 from public.audit_events a where a.vehicle_id=t.id and a.table_name='vehicles' and a.action='move'
        and public.workshop_canonical_stage_code(a.after_data->>'pmb_stage')=t.station) audited_legacy_move
    from target t
  ), classified as(
    select f.*,
      case
        when f.lifecycle_state<>'active' or f.deleted_at is not null or f.station is null or not f.planner_station
          then 'D_AMBIGUOUS'
        when f.open_items>1 or f.active_other_bookings>0 then 'D_AMBIGUOUS'
        when f.open_items=1 then 'C_COMPLETED_OR_OBSOLETE'
        when f.active_same_bookings>1 or f.booking_completion_markers then 'D_AMBIGUOUS'
        when f.active_same_bookings=1 then 'B_ACTIVE_BOOKING'
        when f.completed_items>0 then 'C_COMPLETED_OR_OBSOLETE'
        when f.audited_legacy_move then 'A_SAFE_CREATE'
        else 'D_AMBIGUOUS'
      end classification,
      case
        when f.lifecycle_state<>'active' or f.deleted_at is not null then 'vehicle_not_active'
        when f.station is null or not f.planner_station then 'legacy_stage_not_enabled_planner'
        when f.open_items>1 then 'duplicate_open_work_items'
        when f.active_other_bookings>0 then 'conflicting_station_booking'
        when f.open_items=1 then 'canonical_open_work_item_exists'
        when f.active_same_bookings>1 then 'multiple_active_same_station_bookings'
        when f.booking_completion_markers then 'active_status_booking_has_completion_markers'
        when f.active_same_bookings=1 then 'active_booking_represents_job'
        when f.completed_items>0 then 'completed_equivalent_work_exists'
        when f.audited_legacy_move then 'audited_unrepresented_legacy_requirement'
        else 'insufficient_legacy_evidence'
      end reason_code
    from facts f
  )
  select c.id,c.current_location,c.pmb_stage,c.station,c.classification,c.reason_code,
    jsonb_build_object(
      'open_equivalent_work_items',c.open_items,
      'completed_equivalent_work_items',c.completed_items,
      'active_same_station_bookings',c.active_same_bookings,
      'active_other_station_bookings',c.active_other_bookings,
      'booking_completion_markers',c.booking_completion_markers,
      'audited_legacy_move',c.audited_legacy_move,
      'eta_present',case when upper(btrim(coalesce(c.current_location,'')))='IT'
        then (select v.eta_to_kewdale is not null from public.vehicles v where v.id=c.id) else null end
    ),
    extensions.uuid_generate_v5('30c34313-5094-5162-a8e4-37c1787bb840'::uuid,
      c.id::text||':'||c.station||':legacy-pmb-stage-v1')
  from classified c order by c.id;
end $$;
revoke all on function public.preview_legacy_stage_reconciliation(uuid[]) from public,anon,authenticated;

create or replace function public.apply_legacy_stage_reconciliation(p_batch_id text,p_vehicle_ids uuid[])
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions as $$
declare
  r record;
  v_receipt_id uuid;
  v_work_key text;
  v_applied_id uuid;
  v_updated_at timestamptz;
  v_state text;
  v_created boolean;
begin
  if p_batch_id is null or p_batch_id!~'^[A-Za-z0-9._:-]{1,120}$' then
    raise exception 'Invalid reconciliation batch ID' using errcode='22023';
  end if;
  perform 1 from public.vehicles v where v.id=any(p_vehicle_ids) order by v.id for update;

  for r in select * from public.preview_legacy_stage_reconciliation(p_vehicle_ids) loop
    v_receipt_id:=extensions.uuid_generate_v5('9f7a1f72-c4ff-58ab-9c42-7e39d1c54d87'::uuid,
      p_batch_id||':'||r.vehicle_id::text||':'||r.canonical_station);
    v_applied_id:=null; v_updated_at:=null; v_created:=false;

    if exists(select 1 from public.legacy_stage_reconciliation_receipts x where x.id=v_receipt_id) then
      continue;
    end if;

    if r.classification='A_SAFE_CREATE' then
      select s.work_key into v_work_key from public.workshop_stages s
        where s.code=r.canonical_station and s.active and s.planner_enabled;
      begin
        insert into public.vehicle_work_items(id,vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
        values(r.proposed_work_item_id,r.vehicle_id,v_work_key,true,false,null,null,null,now())
        on conflict (vehicle_id,work_key) do nothing
        returning id,updated_at into v_applied_id,v_updated_at;
      exception when unique_violation then
        v_applied_id:=null;
      end;
      v_created:=v_applied_id is not null;
      if not v_created then
        select wi.id,wi.updated_at into v_applied_id,v_updated_at
        from public.vehicle_work_items wi where wi.vehicle_id=r.vehicle_id and wi.required and not wi.completed
          and public.workshop_stage_code_for_work_key(wi.work_key)=r.canonical_station order by wi.id limit 1;
      end if;
      v_state:=case when v_created then 'applied' else 'skipped' end;
    elsif r.classification='D_AMBIGUOUS' then
      v_state:='ambiguous';
    else
      v_state:='skipped';
    end if;

    insert into public.legacy_stage_reconciliation_receipts(
      id,batch_id,vehicle_id,legacy_stage,canonical_station,classification,reason_code,decision_state,
      evidence,proposed_work_item_id,applied_work_item_id,work_item_updated_at)
    values(v_receipt_id,p_batch_id,r.vehicle_id,r.legacy_pmb_stage,r.canonical_station,r.classification,
      case when r.classification='A_SAFE_CREATE' and not v_created then 'canonical_work_item_won_concurrent_insert' else r.reason_code end,
      v_state,r.evidence,r.proposed_work_item_id,case when v_created then v_applied_id else null end,
      case when v_created then v_updated_at else null end);

    insert into public.audit_events(action,table_name,row_id,vehicle_id,before_data,after_data,metadata)
    values('import','legacy_stage_reconciliation_receipts',v_receipt_id,r.vehicle_id,null,
      jsonb_build_object('receipt_id',v_receipt_id,'vehicle_id',r.vehicle_id,'canonical_station',r.canonical_station,
        'classification',r.classification,'reason_code',
        case when r.classification='A_SAFE_CREATE' and not v_created then 'canonical_work_item_won_concurrent_insert' else r.reason_code end,
        'decision_state',v_state,'legacy_stage',r.legacy_pmb_stage),
      jsonb_build_object('source','legacy_pmb_stage_reconciliation_decision','batch_id',p_batch_id,
        'receipt_id',v_receipt_id,'legacy_stage',r.legacy_pmb_stage,'decision',r.classification));

    if v_created then
      insert into public.audit_events(action,table_name,row_id,vehicle_id,before_data,after_data,metadata)
      values('import','vehicle_work_items',v_applied_id,r.vehicle_id,null,
        jsonb_build_object('id',v_applied_id,'vehicle_id',r.vehicle_id,'work_key',v_work_key,'required',true,'completed',false),
        jsonb_build_object('source','legacy_pmb_stage_reconciliation','batch_id',p_batch_id,
          'receipt_id',v_receipt_id,'legacy_stage',r.legacy_pmb_stage,'decision','A_SAFE_CREATE'));
    end if;
  end loop;

  return jsonb_build_object('batch_id',p_batch_id,
    'receipts',(select coalesce(jsonb_agg(jsonb_build_object(
      'receipt_id',x.id,'vehicle_id',x.vehicle_id,'canonical_station',x.canonical_station,
      'classification',x.classification,'reason_code',x.reason_code,'decision_state',x.decision_state,
      'proposed_work_item_id',x.proposed_work_item_id,'applied_work_item_id',x.applied_work_item_id)
      order by x.vehicle_id),'[]'::jsonb)
     from public.legacy_stage_reconciliation_receipts x where x.batch_id=p_batch_id));
end $$;
revoke all on function public.apply_legacy_stage_reconciliation(text,uuid[]) from public,anon,authenticated;

create or replace function public.rollback_legacy_stage_reconciliation(p_batch_id text)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public as $$
declare r record; v_before jsonb; v_after jsonb;
begin
  if p_batch_id is null or p_batch_id!~'^[A-Za-z0-9._:-]{1,120}$' then
    raise exception 'Invalid reconciliation batch ID' using errcode='22023';
  end if;
  for r in select * from public.legacy_stage_reconciliation_receipts
    where batch_id=p_batch_id and decision_state='applied' order by vehicle_id for update loop
    select jsonb_build_object('id',wi.id,'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
      'required',wi.required,'completed',wi.completed,'completed_by',wi.completed_by,
      'completed_at',wi.completed_at,'notes',wi.notes,'updated_at',wi.updated_at)
      into v_before from public.vehicle_work_items wi where wi.id=r.applied_work_item_id for update;
    if v_before is null then
      raise exception 'Reconciled work item is missing; rollback stopped' using errcode='P0002';
    end if;
    if (v_before->>'required')::boolean is not true or (v_before->>'completed')::boolean is true
       or v_before->>'completed_by' is not null or v_before->>'completed_at' is not null
       or v_before->>'notes' is not null or (v_before->>'updated_at')::timestamptz<>r.work_item_updated_at then
      raise exception 'Reconciled work item changed after apply; rollback stopped' using errcode='40001';
    end if;
    update public.vehicle_work_items set required=false,updated_at=now()
      where id=r.applied_work_item_id
      returning jsonb_build_object('id',id,'vehicle_id',vehicle_id,'work_key',work_key,
        'required',required,'completed',completed,'updated_at',updated_at) into v_after;
    insert into public.audit_events(action,table_name,row_id,vehicle_id,before_data,after_data,metadata)
      values('update','vehicle_work_items',r.applied_work_item_id,r.vehicle_id,v_before,v_after,
        jsonb_build_object('source','legacy_pmb_stage_reconciliation_rollback','batch_id',p_batch_id,
          'receipt_id',r.id,'legacy_stage',r.legacy_stage,'decision','rollback'));
    update public.legacy_stage_reconciliation_receipts
      set decision_state='rolled_back',rolled_back_at=now() where id=r.id;
  end loop;
  return jsonb_build_object('batch_id',p_batch_id,'rolled_back',
    (select count(*) from public.legacy_stage_reconciliation_receipts where batch_id=p_batch_id and decision_state='rolled_back'));
end $$;
revoke all on function public.rollback_legacy_stage_reconciliation(text) from public,anon,authenticated;

-- Canonical live relation: an outstanding required work item is the only
-- source of planner-candidate authority. A booking annotates that authority;
-- it does not create it. Legacy pmb_stage is not read here.
create or replace function public.workshop_station_eligibility(p_stage_code text)
returns table(vehicle_id uuid,stage_code text,work_key text,current_location text,
 eta_to_kewdale date,existing_booking boolean,schedule_enabled boolean,disabled_reason text)
language sql stable security definer set search_path=pg_catalog,public as $$
 with station as(
  select s.code,s.work_key from public.workshop_stages s
  where s.code=public.workshop_canonical_stage_code(p_stage_code) and s.active and s.planner_enabled
 ), outstanding as(
  select wi.vehicle_id,st.code,st.work_key from public.vehicle_work_items wi cross join station st
  where public.workshop_stage_code_for_work_key(wi.work_key)=st.code and wi.required and not wi.completed
  group by wi.vehicle_id,st.code,st.work_key
 ), active_booking as(
  select distinct b.vehicle_id,st.code from public.workshop_bookings b
  join public.workshop_stages s on s.id=b.stage_id join station st on st.code=s.code
  where b.deleted_at is null and b.status in('queued','planned','started','stoppage')
 )
 select v.id,o.code,o.work_key,upper(btrim(coalesce(v.current_location,''))),v.eta_to_kewdale,
  (ab.vehicle_id is not null),
  case when upper(btrim(coalesce(v.current_location,''))) in('PMB','YH') then true
       when upper(btrim(coalesce(v.current_location,'')))='IT' and v.eta_to_kewdale is not null then true else false end,
  case when upper(btrim(coalesce(v.current_location,'')))='IT' and v.eta_to_kewdale is null then 'missing_eta'
       when upper(btrim(coalesce(v.current_location,''))) not in('PMB','YH','IT') then 'location_ineligible' else null end
 from outstanding o join public.vehicles v on v.id=o.vehicle_id
 left join active_booking ab on ab.vehicle_id=v.id and ab.code=o.code
 where v.lifecycle_state='active' and v.deleted_at is null
  and upper(btrim(coalesce(v.current_location,''))) in('PMB','YH','IT')
$$;
revoke all on function public.workshop_station_eligibility(text) from public,anon,authenticated;

create or replace function public.get_station_workshop_snapshot(p_stage_code text,p_date_from date,p_date_to date)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_ids uuid[];
begin
 perform public.workshop_require_planner_operator();
 v_stage:=public.workshop_canonical_stage_code(p_stage_code);
 select id into v_stage_id from public.workshop_stages where code=v_stage and active and planner_enabled;
 if v_stage_id is null then raise exception 'Unknown, inactive or planner-disabled workshop station' using errcode='22023'; end if;
 if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to>p_date_from+31 then
  raise exception 'Invalid station planner date range' using errcode='22023'; end if;
 v_from:=p_date_from::timestamp at time zone 'Australia/Perth';
 v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';
 select coalesce(array_agg(distinct q.vehicle_id),'{}'::uuid[]) into v_ids from(
  select e.vehicle_id from public.workshop_station_eligibility(v_stage)e
  union
  select b.vehicle_id from public.workshop_bookings b
   join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
   where b.stage_id=v_stage_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
   and ((b.status in('queued','planned','started','stoppage') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))
 )q;
 return jsonb_build_object(
  'revision',public.workshop_current_station_revision(v_stage),'generated_at',now(),
  'semantics',jsonb_build_object(
    'outstanding_candidates','required canonical work items not completed and location-visible',
    'unscheduled_candidates','outstanding candidates without any active booking',
    'selected_date_bookings','booking rows intersecting the selected planner date'),
  'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
  'counts',jsonb_build_object(
    'outstanding_candidates',(select count(*) from public.workshop_station_eligibility(v_stage)),
    'unscheduled_candidates',(select count(*) from public.workshop_station_eligibility(v_stage)e where not e.existing_booking),
    'selected_date_bookings',(select count(*) from public.workshop_bookings b
      join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
      where b.stage_id=v_stage_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
      and ((b.status in('queued','planned','started','stoppage') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to)))),
  'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,
   'is_physical',s.is_physical,'work_key',s.work_key)) from public.workshop_stages s where s.id=v_stage_id),
  'bays',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',b.bay_number,
   'code',b.code,'display_name',b.display_name) order by b.bay_number),'[]'::jsonb)
   from public.workshop_bays b where b.stage_id=v_stage_id and b.is_active),
  'outstanding_candidates',(select coalesce(jsonb_agg(jsonb_build_object(
    'vehicle_id',e.vehicle_id,'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,
    'disabled_reason',e.disabled_reason) order by e.vehicle_id),'[]'::jsonb)
    from public.workshop_station_eligibility(v_stage)e),
  'bookings',(select coalesce(jsonb_agg(public.workshop_planner_booking_dto(b.id) order by b.scheduled_start_at,b.id),'[]'::jsonb)
   from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
   where b.stage_id=v_stage_id and b.vehicle_id=any(v_ids) and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
   and ((b.status in('queued','planned','started','stoppage') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))),
  'vehicles',(select coalesce(jsonb_agg(jsonb_build_object(
   'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
   'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
   'make',v.make,'model',v.model,'registration',v.registration,'current_location',v.current_location,
   'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
   'eta_to_kewdale',v.eta_to_kewdale,'active_workshop_booking_id',v.active_workshop_booking_id,
   'workshop_status',v.workshop_status,'version',v.version) order by v.stock_number nulls last,v.id),'[]'::jsonb)
   from public.vehicles v where v.id=any(v_ids) and v.lifecycle_state='active' and v.deleted_at is null),
  'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
   'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.vehicle_id,wi.work_key),'[]'::jsonb)
   from public.vehicle_work_items wi where wi.vehicle_id=any(v_ids)
    and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage
  )
 );
end $$;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public,anon,authenticated;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated;
comment on function public.get_station_workshop_snapshot(text,date,date) is
 'Operator/admin-only station DTO. Outstanding candidates are date-independent canonical work-item authority; calendar bookings are selected-date rows.';

create or replace function public.get_workshop_eligibility_snapshot()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
begin
 perform public.workshop_require_planner_operator();
 return jsonb_build_object('generated_at',now(),
  'semantics',jsonb_build_object(
    'count_label','Outstanding requirements',
    'candidate_authority','required canonical work item with completed=false',
    'legacy_pmb_stage_authority',false),
  'stages',(select coalesce(jsonb_agg(jsonb_build_object('code',s.code,'display_name',s.display_name,
   'work_key',s.work_key,'planner_enabled',s.planner_enabled,'revision',public.workshop_current_station_revision(s.code),
   'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb)
    from public.workshop_stage_aliases a where a.stage_code=s.code)) order by s.sort_order),'[]'::jsonb)
   from public.workshop_stages s where s.active and s.planner_enabled),
  'candidates',(select coalesce(jsonb_agg(jsonb_build_object('stage_code',e.stage_code,'work_key',e.work_key,
   'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,
   'vehicle',jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
    'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'make',v.make,'model',v.model,
    'registration',v.registration,'current_location',v.current_location,'pmb_stage',v.pmb_stage,
    'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
    'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version),
   'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
    'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
    from public.vehicle_work_items wi where wi.vehicle_id=v.id
     and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code))
   order by e.stage_code,v.stock_number,v.id),'[]'::jsonb)
   from public.workshop_stages s cross join lateral public.workshop_station_eligibility(s.code)e
   join public.vehicles v on v.id=e.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
   where s.code=e.stage_code and s.active and s.planner_enabled));
end $$;
revoke all on function public.get_workshop_eligibility_snapshot() from public,anon,authenticated;
grant execute on function public.get_workshop_eligibility_snapshot() to authenticated;
comment on function public.get_workshop_eligibility_snapshot() is
 'Operator/admin-only all-station outstanding requirement DTO. Active bookings and legacy pmb_stage do not create candidates.';
