begin;

CREATE OR REPLACE FUNCTION public.workshop_parts_ready(p_vehicle_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (
      select (not p.parts_required) or p.parts_received or
             exists (
               select 1 from public.vehicle_work_items wi
               where wi.vehicle_id = p_vehicle_id
                 and wi.work_key = 'PARTS'
                 and wi.completed = true
             )
      from public.vehicle_parts_updates p
      where p.vehicle_id = p_vehicle_id
      order by p.updated_at desc
      limit 1
    ),
    true
  );
$function$
;

CREATE OR REPLACE FUNCTION public.pdc_qc_gate_issues(p_vehicle_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  with vehicle as (
    select id,upper(btrim(coalesce(current_location,''))) location,
           upper(regexp_replace(btrim(coalesce(pmb_stage,'')),'[^A-Z0-9]+','','g')) stage
    from public.vehicles where id=p_vehicle_id and lifecycle_state='active' and deleted_at is null
  ), outstanding as (
    select string_agg(distinct upper(btrim(wi.work_key)),', ' order by upper(btrim(wi.work_key))) labels
    from public.vehicle_work_items wi
    where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
      and upper(regexp_replace(btrim(coalesce(wi.work_key,'')),'[^A-Z0-9]+','','g'))<>'QC'
  ), active_planner as (
    select string_agg(distinct s.code,', ' order by s.code) labels
    from public.workshop_bookings b
    join public.workshop_stages s on s.id=b.stage_id
    where b.vehicle_id=p_vehicle_id and b.deleted_at is null
      and b.status in ('queued','planned','started','stoppage')
      and s.planner_enabled
  )
  select array_remove(array[
    case when not exists(select 1 from vehicle) then 'active_vehicle_required' end,
    case when (select location from vehicle) not in ('PMB','QC') then 'vehicle_must_be_at_pmb_or_qc_gate' end,
    case when coalesce((select stage from vehicle),'')<>'' then
      'vehicle_still_in_workshop_stage:'||(select stage from vehicle) end,
    case when (select labels from outstanding) is not null then
      'outstanding_required_work:'||(select labels from outstanding) end,
    case when (select labels from active_planner) is not null then
      'active_workshop_booking:'||(select labels from active_planner) end
  ],null::text)
$function$
;

CREATE OR REPLACE FUNCTION public.undo_administrator_workshop_booking_move(p_receipt_id uuid, p_expected_version integer, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare r public.workshop_booking_move_receipts%rowtype; v_booking public.workshop_bookings%rowtype; v_email text;
begin
 perform public.workshop_require_website_administrator_238();
 if p_receipt_id is null or p_expected_version is null or p_request_id is null then raise exception 'PDC_238_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 select * into r from public.workshop_booking_move_receipts where receipt_id=p_receipt_id for update;
 if not found then return jsonb_build_object('ok',false,'error','receipt_not_found'); end if;
 if r.actor_user_id<>auth.uid() then return jsonb_build_object('ok',false,'error','undo_actor_mismatch'); end if;
 if r.undone_at is not null then
   if r.undo_request_id=p_request_id then return r.undo_result||jsonb_build_object('idempotent_replay',true); end if;
   return jsonb_build_object('ok',false,'error','already_undone');
 end if;
 if r.created_at<clock_timestamp()-interval '15 minutes' then return jsonb_build_object('ok',false,'error','undo_expired'); end if;
 select * into v_booking from public.workshop_bookings where id=r.booking_id for update;
 if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 -- Lock every affected row and reject any intervening edit before changing one row.
 perform 1 from public.workshop_bookings w join jsonb_array_elements(r.after_rows) a on a->>'id'=w.id::text order by w.id for update;
 if exists(select 1 from public.workshop_bookings w join jsonb_array_elements(r.after_rows) a on a->>'id'=w.id::text
   where w.version<>(a->>'version')::integer or w.stage_id<>(a->>'stage_id')::uuid or w.bay_id is distinct from (a->>'bay_id')::uuid
      or w.scheduled_start_at<>(a->>'scheduled_start_at')::timestamptz or w.scheduled_end_at<>(a->>'scheduled_end_at')::timestamptz
      or w.status::text<>(a->>'status')) then
   return jsonb_build_object('ok',false,'error','undo_conflict');
 end if;
 -- Restore every booking in one statement. The bay exclusion constraint is
 -- evaluated against the final statement result, avoiding transient overlaps
 -- while reversing a same-bay insertion/cascade.
 update public.workshop_bookings w set
   stage_id=(x.row->>'stage_id')::uuid,bay_id=(x.row->>'bay_id')::uuid,
   scheduled_start_at=(x.row->>'scheduled_start_at')::timestamptz,
   scheduled_end_at=(x.row->>'scheduled_end_at')::timestamptz,
   default_duration_minutes=(x.row->>'default_duration_minutes')::integer,
   version=w.version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
 from jsonb_array_elements(r.before_rows) x(row)
 where w.id=(x.row->>'id')::uuid;
 -- Keep active assignment intervals exactly aligned with their restored booking.
 update public.workshop_booking_assignments a set
   scheduled_start_at=b.scheduled_start_at,scheduled_end_at=b.scheduled_end_at,
   updated_at=clock_timestamp()
 from public.workshop_bookings b
 where a.booking_id=b.id and a.released_at is null
   and exists(select 1 from jsonb_array_elements(r.before_rows) x where x->>'id'=b.id::text);
 select email into v_email from public.pdc_user_roles where auth_user_id=auth.uid();
 insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
 values(r.booking_id,'administrator_booking_move_undone',r.after_rows,r.before_rows,
   jsonb_build_object('source','website_undo','receipt_id',r.receipt_id,'request_id',p_request_id),auth.uid(),coalesce(v_email,auth.jwt()->>'email'));
 update public.workshop_booking_move_receipts set undone_at=clock_timestamp(),undone_by=auth.uid(),undo_request_id=p_request_id,
   undo_result=jsonb_build_object('ok',true,'receipt_id',r.receipt_id,'booking_id',r.booking_id,
     'booking_version',(select version from public.workshop_bookings where id=r.booking_id)) where receipt_id=r.receipt_id;
 return (select undo_result from public.workshop_booking_move_receipts where receipt_id=r.receipt_id);
exception when exclusion_violation then
 return jsonb_build_object('ok',false,'error','undo_conflict');
end;
$function$
;

drop function if exists public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean);

delete from supabase_migrations.schema_migrations where version='243' and name='craig_vehicle_drag_parts_non_blocking';

commit;