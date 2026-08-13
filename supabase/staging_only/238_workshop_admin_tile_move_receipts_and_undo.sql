-- Staging-only migration 238: narrow website Administrator authority for
-- idempotent Workshop tile moves with immutable receipts and one-step Undo.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='237' and name='workshop_snapshot_calendar_performance')
     or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::numeric>237)
     or exists(select 1 from supabase_migrations.schema_migrations where version='238') then
    raise exception 'PDC_238_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end $guard$;

create table public.workshop_booking_move_receipts (
  receipt_id uuid primary key default gen_random_uuid(),
  request_id uuid not null,
  actor_user_id uuid not null references auth.users(id),
  actor_email text not null,
  booking_id uuid not null references public.workshop_bookings(id),
  source text not null,
  reason text,
  cascade boolean not null,
  before_rows jsonb not null,
  after_rows jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  undone_at timestamptz,
  undone_by uuid references auth.users(id),
  undo_request_id uuid,
  undo_result jsonb,
  unique(actor_user_id,request_id),
  check(jsonb_typeof(before_rows)='array' and jsonb_typeof(after_rows)='array'),
  check(length(source) between 1 and 80),
  check(reason is null or length(reason)<=500)
);

alter table public.workshop_booking_move_receipts enable row level security;
revoke all on table public.workshop_booking_move_receipts from public,anon,authenticated,service_role;

create or replace function public.workshop_require_website_administrator_238()
returns void language plpgsql stable security definer
set search_path='pg_catalog','public'
as $fn$
declare v_role text; v_email text;
begin
  if auth.uid() is null or session_user<>'authenticator' then
    raise exception 'PDC_238_WEBSITE_AUTH_REQUIRED' using errcode='42501';
  end if;
  select lower(role),lower(email) into v_role,v_email
  from public.pdc_user_roles
  where auth_user_id=auth.uid() and active and approved_at is not null and revoked_at is null;
  if v_role<>'administrator' then
    raise exception 'PDC_238_ADMINISTRATOR_REQUIRED' using errcode='42501';
  end if;
  if coalesce(v_email,'')~'(monitor|auditor|viewer|bot|service)' then
    raise exception 'PDC_238_NON_HUMAN_IDENTITY_DENIED' using errcode='42501';
  end if;
end $fn$;
revoke all on function public.workshop_require_website_administrator_238() from public,anon,authenticated,service_role;

create or replace function public.workshop_booking_move_row_238(p_booking public.workshop_bookings)
returns jsonb language sql immutable security definer
set search_path='pg_catalog','public'
as $fn$
 select jsonb_build_object(
   'id',p_booking.id,'stage_id',p_booking.stage_id,'bay_id',p_booking.bay_id,
   'scheduled_start_at',p_booking.scheduled_start_at,'scheduled_end_at',p_booking.scheduled_end_at,
   'default_duration_minutes',p_booking.default_duration_minutes,'status',p_booking.status,
   'version',p_booking.version,'updated_by',p_booking.updated_by,'updated_at',p_booking.updated_at
 );
$fn$;
revoke all on function public.workshop_booking_move_row_238(public.workshop_bookings) from public,anon,authenticated,service_role;

create or replace function public.administrator_move_workshop_booking(
  p_booking_id uuid,p_expected_version integer,p_stage_code text,p_bay_number integer,
  p_scheduled_start_at timestamptz,p_duration_minutes integer,p_override_reason text,
  p_metadata jsonb,p_request_id uuid,p_cascade boolean default false
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public'
as $fn$
declare
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype;
 v_booking public.workshop_bookings%rowtype; v_target_stage uuid; v_target_bay uuid;
 v_before jsonb; v_after jsonb; v_result jsonb; v_receipt uuid;
 v_source text:=left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_drag_drop'),80);
 v_reason text:=nullif(left(btrim(coalesce(p_override_reason,p_metadata->>'reason','')),500),'');
begin
 perform public.workshop_require_website_administrator_238();
 if p_request_id is null or p_booking_id is null or p_expected_version is null then
   raise exception 'PDC_238_REQUIRED_ARGUMENT_MISSING' using errcode='22023';
 end if;
 select * into v_existing from public.workshop_booking_move_receipts
 where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.booking_id<>p_booking_id then raise exception 'PDC_238_IDEMPOTENCY_KEY_REUSE' using errcode='22023'; end if;
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 if v_booking.deleted_at is not null or v_booking.status not in('queued','planned') or v_booking.actual_start_at is not null or v_booking.actual_end_at is not null then
   return jsonb_build_object('ok',false,'error','protected_booking');
 end if;
 select id into v_target_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_target_bay from public.workshop_bays where stage_id=v_target_stage and bay_number=p_bay_number and is_active;
 if v_target_stage is null or v_target_bay is null then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-move:'||p_booking_id::text,0));
 select coalesce(jsonb_agg(public.workshop_booking_move_row_238(x) order by x.scheduled_start_at,x.id),'[]'::jsonb)
 into v_before from public.workshop_bookings x
 where x.id=p_booking_id or (x.deleted_at is null and x.status in('queued','planned') and x.bay_id in(v_booking.bay_id,v_target_bay));
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move(p_booking_id,p_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority','website_administrator'));
 else
   v_result:=public.move_workshop_booking(p_booking_id,p_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority','website_administrator'));
 end if;
 if coalesce((v_result->>'ok')::boolean,false) is not true then return v_result; end if;
 select coalesce(jsonb_agg(public.workshop_booking_move_row_238(x) order by x.scheduled_start_at,x.id),'[]'::jsonb)
 into v_after from public.workshop_bookings x
 where exists(select 1 from jsonb_array_elements(v_before) b where b->>'id'=x.id::text) or x.id=p_booking_id;
 select coalesce(jsonb_agg(b),'[]'::jsonb) into v_before from jsonb_array_elements(v_before) b
 join jsonb_array_elements(v_after) a on a->>'id'=b->>'id' where b is distinct from a;
 select coalesce(jsonb_agg(a),'[]'::jsonb) into v_after from jsonb_array_elements(v_after) a
 join jsonb_array_elements(v_before) b on b->>'id'=a->>'id';
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object(
   'booking_id',p_booking_id,
   'booking_version',(select version from public.workshop_bookings where id=p_booking_id)
 );
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,source,reason,cascade,before_rows,after_rows,result)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),p_booking_id,v_source,v_reason,p_cascade,v_before,v_after,v_result)
 returning receipt_id into v_receipt;
 return v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false);
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.booking_id=p_booking_id then return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true); end if;
 raise;
end;
$fn$;

create or replace function public.undo_administrator_workshop_booking_move(
 p_receipt_id uuid,p_expected_version integer,p_request_id uuid
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public'
as $fn$
declare r public.workshop_booking_move_receipts%rowtype; x jsonb; b public.workshop_bookings%rowtype; v_email text;
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
 select * into b from public.workshop_bookings where id=r.booking_id for update;
 if b.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
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
$fn$;

-- The legacy move endpoints remain private implementation details for the new
-- Administrator wrapper. Removing their authenticated grants closes the former
-- Operator/general-authenticated path without granting a bot role anything.
revoke execute on function public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from authenticated;
revoke execute on function public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from authenticated;
revoke all on function public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean) from public,anon,service_role;
revoke all on function public.undo_administrator_workshop_booking_move(uuid,integer,uuid) from public,anon,service_role;
grant execute on function public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean) to authenticated;
grant execute on function public.undo_administrator_workshop_booking_move(uuid,integer,uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('238','workshop_admin_tile_move_receipts_and_undo',array['staging-only Administrator website tile move receipts, idempotency and guarded one-step Undo']);
commit;
