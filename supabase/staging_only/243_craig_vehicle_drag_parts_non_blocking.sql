begin;

-- Parts remains authoritative operational state, but is no longer a workflow
-- eligibility predicate. All historical Parts rows, warnings and audits remain.
create or replace function public.workshop_parts_ready(p_vehicle_id uuid)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,public
as $$ select true $$;

comment on function public.workshop_parts_ready(uuid) is
 'Staging 243: compatibility predicate. Parts is tracked and reported but never blocks booking, movement, start, completion, QC or RFT.';

-- QC/RFT checks physical required work only. PARTS and QC are separately
-- tracked statuses and are not outstanding physical workshop operations.
create or replace function public.pdc_qc_gate_issues(p_vehicle_id uuid)
returns text[]
language sql
stable
security definer
set search_path=pg_catalog,public
as $$
  with vehicle as (
    select id,upper(btrim(coalesce(current_location,''))) location,
           upper(regexp_replace(btrim(coalesce(pmb_stage,'')),'[^A-Z0-9]+','','g')) stage
    from public.vehicles where id=p_vehicle_id and lifecycle_state='active' and deleted_at is null
  ), outstanding as (
    select string_agg(distinct upper(btrim(wi.work_key)),', ' order by upper(btrim(wi.work_key))) labels
    from public.vehicle_work_items wi
    where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
      and upper(regexp_replace(btrim(coalesce(wi.work_key,'')),'[^A-Z0-9]+','','g')) not in ('QC','PARTS')
  ), active_planner as (
    select string_agg(distinct s.code,', ' order by s.code) labels
    from public.workshop_bookings b
    join public.workshop_stages s on s.id=b.stage_id
    where b.vehicle_id=p_vehicle_id and b.deleted_at is null
      and b.status in ('queued','planned','started','stoppage') and s.planner_enabled
  )
  select array_remove(array[
    case when not exists(select 1 from vehicle) then 'active_vehicle_required' end,
    case when (select location from vehicle) not in ('PMB','QC') then 'vehicle_must_be_at_pmb_or_qc_gate' end,
    case when coalesce((select stage from vehicle),'')<>'' then 'vehicle_still_in_workshop_stage:'||(select stage from vehicle) end,
    case when (select labels from outstanding) is not null then 'outstanding_required_work:'||(select labels from outstanding) end,
    case when (select labels from active_planner) is not null then 'active_workshop_booking:'||(select labels from active_planner) end
  ],null::text)
$$;

alter table public.workshop_booking_move_receipts
  add column if not exists operation_type text not null default 'move',
  add column if not exists vehicle_id uuid references public.vehicles(id);

alter table public.workshop_booking_move_receipts drop constraint if exists workshop_booking_move_receipts_operation_type_check;
alter table public.workshop_booking_move_receipts add constraint workshop_booking_move_receipts_operation_type_check
  check (operation_type in ('move','create'));

create or replace function public.administrator_schedule_workshop_vehicle(
 p_vehicle_id uuid,p_vehicle_expected_version integer,p_stage_code text,p_bay_number integer,
 p_scheduled_start_at timestamptz,p_duration_minutes integer,p_technician_id uuid,
 p_metadata jsonb,p_request_id uuid,p_cascade boolean default true)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype;
 v_stage uuid; v_bay uuid; v_before jsonb; v_after jsonb; v_result jsonb;
 v_booking_id uuid; v_booking_version integer; v_receipt uuid;
begin
 perform public.workshop_require_website_administrator_238();
 if p_request_id is null or p_vehicle_id is null or p_vehicle_expected_version is null then
   raise exception 'PDC_243_REQUIRED_ARGUMENT_MISSING' using errcode='22023';
 end if;
 select * into v_existing from public.workshop_booking_move_receipts
 where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.vehicle_id is distinct from p_vehicle_id or v_existing.operation_type<>'create' then
     raise exception 'PDC_243_IDEMPOTENCY_KEY_REUSE' using errcode='22023';
   end if;
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select id into v_stage from public.workshop_stages
 where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_bay from public.workshop_bays where stage_id=v_stage and bay_number=p_bay_number and is_active;
 if v_stage is null or v_bay is null then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-create:'||p_vehicle_id::text,0));
 select coalesce(jsonb_agg(public.workshop_booking_move_row_238(x) order by x.scheduled_start_at,x.id),'[]'::jsonb)
 into v_before from public.workshop_bookings x
 where x.deleted_at is null and x.status='planned' and x.bay_id=v_bay
   and public.workshop_booking_effective_end_at(x.id)>p_scheduled_start_at;
 if p_cascade then
   v_result:=public.cascade_workshop_schedule('insert',p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,
     p_scheduled_start_at,p_duration_minutes,p_technician_id,p_duration_minutes,null,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority','website_administrator'));
 else
   v_result:=public.schedule_vehicle_work(p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,
     p_scheduled_start_at,p_duration_minutes,p_technician_id,null,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority','website_administrator'));
 end if;
 if coalesce((v_result->>'ok')::boolean,false) is not true then return v_result; end if;
 v_booking_id:=coalesce(nullif(v_result->>'booking_id','')::uuid,nullif(v_result->'booking'->>'id','')::uuid);
 if v_booking_id is null then
   select id into v_booking_id from public.workshop_bookings
   where vehicle_id=p_vehicle_id and deleted_at is null and stage_id=v_stage
   order by created_at desc,id desc limit 1;
 end if;
 select version into v_booking_version from public.workshop_bookings where id=v_booking_id;
 select coalesce(jsonb_agg(public.workshop_booking_move_row_238(x) order by x.scheduled_start_at,x.id),'[]'::jsonb)
 into v_after from public.workshop_bookings x
 where x.id=v_booking_id or exists(select 1 from jsonb_array_elements(v_before) b where b->>'id'=x.id::text);
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',v_booking_id,'booking_version',v_booking_version,'operation_type','create');
 insert into public.workshop_booking_move_receipts(
   request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,before_rows,after_rows,result)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),v_booking_id,p_vehicle_id,'create',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_unallocated_drag'),80),
   nullif(left(btrim(coalesce(p_metadata->>'reason','')),500),''),p_cascade,v_before,v_after,v_result)
 returning receipt_id into v_receipt;
 return v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false);
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.vehicle_id=p_vehicle_id and v_existing.operation_type='create' then
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 raise;
end $$;

create or replace function public.undo_administrator_workshop_booking_move(p_receipt_id uuid,p_expected_version integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.workshop_booking_move_receipts%rowtype; v_booking public.workshop_bookings%rowtype; v_email text; v_result jsonb;
begin
 perform public.workshop_require_website_administrator_238();
 if p_receipt_id is null or p_expected_version is null or p_request_id is null then raise exception 'PDC_243_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 select * into r from public.workshop_booking_move_receipts where receipt_id=p_receipt_id for update;
 if not found then return jsonb_build_object('ok',false,'error','receipt_not_found'); end if;
 if r.actor_user_id<>auth.uid() then return jsonb_build_object('ok',false,'error','undo_actor_mismatch'); end if;
 if r.undone_at is not null then
   if r.undo_request_id=p_request_id then return r.undo_result||jsonb_build_object('idempotent_replay',true); end if;
   return jsonb_build_object('ok',false,'error','already_undone');
 end if;
 if r.created_at<clock_timestamp()-interval '15 minutes' then return jsonb_build_object('ok',false,'error','undo_expired'); end if;
 select * into v_booking from public.workshop_bookings where id=r.booking_id for update;
 if not found or v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 perform 1 from public.workshop_bookings w join jsonb_array_elements(r.after_rows) a on a->>'id'=w.id::text order by w.id for update;
 if exists(select 1 from public.workshop_bookings w join jsonb_array_elements(r.after_rows) a on a->>'id'=w.id::text
   where w.version<>(a->>'version')::integer or w.stage_id<>(a->>'stage_id')::uuid or w.bay_id is distinct from (a->>'bay_id')::uuid
      or w.scheduled_start_at<>(a->>'scheduled_start_at')::timestamptz or w.scheduled_end_at<>(a->>'scheduled_end_at')::timestamptz
      or w.status::text<>(a->>'status')) then return jsonb_build_object('ok',false,'error','undo_conflict'); end if;
 if r.operation_type='create' then
   update public.workshop_bookings set deleted_at=clock_timestamp(),deleted_reason='Administrator Undo to Unallocated',version=version+1,
     updated_by=auth.uid(),updated_at=clock_timestamp() where id=r.booking_id;
   update public.workshop_booking_assignments set released_at=clock_timestamp(),updated_at=clock_timestamp()
     where booking_id=r.booking_id and released_at is null;
 end if;
 update public.workshop_bookings w set
   stage_id=(x.row->>'stage_id')::uuid,bay_id=(x.row->>'bay_id')::uuid,
   scheduled_start_at=(x.row->>'scheduled_start_at')::timestamptz,scheduled_end_at=(x.row->>'scheduled_end_at')::timestamptz,
   default_duration_minutes=(x.row->>'default_duration_minutes')::integer,version=w.version+1,
   updated_by=auth.uid(),updated_at=clock_timestamp()
 from jsonb_array_elements(r.before_rows) x(row) where w.id=(x.row->>'id')::uuid;
 update public.workshop_booking_assignments a set scheduled_start_at=b.scheduled_start_at,scheduled_end_at=b.scheduled_end_at,updated_at=clock_timestamp()
 from public.workshop_bookings b where a.booking_id=b.id and a.released_at is null
 and exists(select 1 from jsonb_array_elements(r.before_rows) x where x->>'id'=b.id::text);
 select email into v_email from public.pdc_user_roles where auth_user_id=auth.uid();
 insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
 values(r.booking_id,case when r.operation_type='create' then 'administrator_booking_create_undone' else 'administrator_booking_move_undone' end,
   r.after_rows,r.before_rows,jsonb_build_object('source','website_undo','receipt_id',r.receipt_id,'request_id',p_request_id,'operation_type',r.operation_type),
   auth.uid(),coalesce(v_email,auth.jwt()->>'email'));
 v_result:=jsonb_build_object('ok',true,'receipt_id',r.receipt_id,'booking_id',r.booking_id,
   'booking_version',(select version from public.workshop_bookings where id=r.booking_id),'operation_type',r.operation_type,
   'returned_to_unallocated',r.operation_type='create');
 update public.workshop_booking_move_receipts set undone_at=clock_timestamp(),undone_by=auth.uid(),undo_request_id=p_request_id,undo_result=v_result
 where receipt_id=r.receipt_id;
 perform public.workshop_bump_revision();
 return v_result;
exception when exclusion_violation then return jsonb_build_object('ok',false,'error','undo_conflict');
end $$;

revoke all on function public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean) from public,anon,authenticated;
grant execute on function public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean) to authenticated;
revoke all on function public.undo_administrator_workshop_booking_move(uuid,integer,uuid) from public,anon,authenticated;
grant execute on function public.undo_administrator_workshop_booking_move(uuid,integer,uuid) to authenticated;

commit;
