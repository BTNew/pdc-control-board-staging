-- Staging-only forward migration 244: close every legacy booking scheduling RPC,
-- bind Administrator receipts to complete intent/state, and make create Undo exact.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='243' and name='craig_vehicle_drag_parts_non_blocking')
     or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::numeric>244)
     or exists(select 1 from supabase_migrations.schema_migrations where version='244' and name<>'workshop_admin_authority_intent_receipt_undo') then
    raise exception 'PDC_244_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end $guard$;

create or replace function public.workshop_require_website_administrator_238()
returns void language plpgsql stable security definer set search_path='pg_catalog','public' as $fn$
declare v_role text; v_email text;
begin
  if auth.uid() is null or session_user<>'authenticator' then raise exception 'PDC_244_WEBSITE_AUTH_REQUIRED' using errcode='42501'; end if;
  select lower(role::text),lower(email) into v_role,v_email from public.pdc_user_roles
  where auth_user_id=auth.uid() and active and approved_at is not null and disabled_at is null and account_status::text='approved';
  if v_role<>'administrator' then raise exception 'PDC_244_ADMINISTRATOR_REQUIRED' using errcode='42501'; end if;
  if coalesce(v_email,'')~'(monitor|auditor|viewer|bot|service|import)' then
    raise exception 'PDC_244_NON_HUMAN_IDENTITY_DENIED' using errcode='42501';
  end if;
  if exists(select 1 from public.pdc_auditor_executor_identities x where x.auth_user_id=auth.uid() and x.active and x.disabled_at is null)
     or exists(select 1 from public.pdc_auditor_service_identities_225 x where x.auth_user_id=auth.uid() and x.active and x.revoked_at is null)
     or exists(select 1 from public.pdc_auditor_worker_identities x where x.auth_user_id=auth.uid() and x.active)
     or exists(select 1 from public.pdc_monitor_stage_activation_writers x where x.user_id=auth.uid() and x.active and x.revoked_at is null)
     or exists(select 1 from public.pdc_monitor_vehicle_identity_readers x where x.user_id=auth.uid() and x.active and x.revoked_at is null) then
    raise exception 'PDC_244_NON_HUMAN_IDENTITY_DENIED' using errcode='42501';
  end if;
end;
$fn$;
revoke all on function public.workshop_require_website_administrator_238() from public,anon,authenticated,service_role;

alter table public.workshop_booking_move_receipts
  add column if not exists request_intent jsonb,
  add column if not exists request_intent_hash text,
  add column if not exists before_state jsonb,
  add column if not exists after_state jsonb;
-- A durable receipt must retain the authoritative booking UUID after Create
-- Undo physically removes that booking. The historical FK would otherwise
-- either block deletion or erase the immutable subject identity.
alter table public.workshop_booking_move_receipts
  drop constraint if exists workshop_booking_move_receipts_booking_id_fkey;

create or replace function public.workshop_admin_state_244(p_booking_ids uuid[],p_vehicle_id uuid)
returns jsonb language sql stable security definer set search_path='pg_catalog','public' as $fn$
  select jsonb_build_object(
    'bookings',coalesce((select jsonb_agg(to_jsonb(b) order by b.id) from public.workshop_bookings b where b.id=any(coalesce(p_booking_ids,'{}'::uuid[]))),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(to_jsonb(a) order by a.id) from public.workshop_booking_assignments a where a.booking_id=any(coalesce(p_booking_ids,'{}'::uuid[]))),'[]'::jsonb),
    'vehicle',(select to_jsonb(v) from public.vehicles v where v.id=p_vehicle_id)
  );
$fn$;
revoke all on function public.workshop_admin_state_244(uuid[],uuid) from public,anon,authenticated,service_role;

create or replace function public.workshop_admin_receipt_immutable_244()
returns trigger language plpgsql set search_path='pg_catalog','public' as $fn$
begin
  if tg_op='DELETE' then
    raise exception 'PDC_244_RECEIPT_IMMUTABLE' using errcode='55000';
  end if;
  if to_jsonb(new)-array['undone_at','undone_by','undo_request_id','undo_result']
     is distinct from to_jsonb(old)-array['undone_at','undone_by','undo_request_id','undo_result'] then
    raise exception 'PDC_244_RECEIPT_IMMUTABLE' using errcode='55000';
  end if;
  if old.undone_at is not null and to_jsonb(new) is distinct from to_jsonb(old) then
    raise exception 'PDC_244_RECEIPT_TERMINAL' using errcode='55000';
  end if;
  return new;
end $fn$;
drop trigger if exists workshop_admin_receipt_immutable_244 on public.workshop_booking_move_receipts;
create trigger workshop_admin_receipt_immutable_244 before update or delete on public.workshop_booking_move_receipts
for each row execute function public.workshop_admin_receipt_immutable_244();
revoke all on function public.workshop_admin_receipt_immutable_244() from public,anon,authenticated,service_role;

create or replace function public.administrator_schedule_workshop_vehicle(
 p_vehicle_id uuid,p_vehicle_expected_version integer,p_stage_code text,p_bay_number integer,
 p_scheduled_start_at timestamptz,p_duration_minutes integer,p_technician_id uuid,
 p_metadata jsonb,p_request_id uuid,p_cascade boolean default true)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $fn$
declare
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype;
 v_stage uuid; v_bay uuid; v_result jsonb; v_booking_id uuid; v_booking_version integer; v_receipt uuid;
 v_ids_before uuid[]; v_ids_after uuid[]; v_before jsonb; v_after jsonb; v_intent jsonb; v_hash text; v_intent_hash_source text;
begin
 perform public.workshop_require_website_administrator_238();
 if p_request_id is null or p_vehicle_id is null or p_vehicle_expected_version is null then raise exception 'PDC_244_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 v_intent:=jsonb_build_object('operation','create','vehicle_id',p_vehicle_id,'vehicle_expected_version',p_vehicle_expected_version,
   'stage_code',public.workshop_canonical_stage_code(p_stage_code),'bay_number',p_bay_number,'scheduled_start_at',p_scheduled_start_at,
   'duration_minutes',p_duration_minutes,'technician_id',p_technician_id,'metadata',coalesce(p_metadata,'{}'::jsonb),'cascade',coalesce(p_cascade,true));
 v_hash:=encode(digest(convert_to(v_intent::text,'UTF8'),'sha256'),'hex');
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.request_intent is distinct from v_intent or v_existing.request_intent_hash is distinct from v_hash then
     raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
   end if;
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select id into v_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_bay from public.workshop_bays where stage_id=v_stage and bay_number=p_bay_number and is_active;
 if v_stage is null or v_bay is null then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-create:'||p_vehicle_id::text,0));
 perform 1 from public.vehicles where id=p_vehicle_id for update;
 select coalesce(array_agg(b.id order by b.id),'{}'::uuid[]) into v_ids_before from public.workshop_bookings b
 where b.deleted_at is null and b.status='planned' and b.bay_id=v_bay and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at;
 perform 1 from public.workshop_bookings b where b.id=any(v_ids_before) order by b.id for update;
 v_before:=public.workshop_admin_state_244(v_ids_before,p_vehicle_id);
 if p_cascade then
   v_result:=public.cascade_workshop_schedule('insert',p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,
     p_duration_minutes,p_technician_id,p_duration_minutes,null,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority','website_administrator'));
 else
   v_result:=public.schedule_vehicle_work(p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,
     p_duration_minutes,p_technician_id,null,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority','website_administrator'));
 end if;
 if coalesce((v_result->>'ok')::boolean,false) is not true then return v_result; end if;
 v_booking_id:=nullif(v_result->'booking'->>'booking_id','')::uuid;
 if v_booking_id is null then raise exception 'PDC_244_AUTHORITATIVE_BOOKING_ID_MISSING' using errcode='55000'; end if;
 if not exists(select 1 from public.workshop_bookings where id=v_booking_id and vehicle_id=p_vehicle_id and stage_id=v_stage) then
   raise exception 'PDC_244_AUTHORITATIVE_BOOKING_ID_INVALID' using errcode='55000';
 end if;
 v_ids_after:=array(select distinct x from unnest(v_ids_before||array[v_booking_id]) x order by x);
 v_after:=public.workshop_admin_state_244(v_ids_after,p_vehicle_id);
 select version into v_booking_version from public.workshop_bookings where id=v_booking_id;
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',v_booking_id,'booking_version',v_booking_version,'operation_type','create');
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,
   before_rows,after_rows,result,request_intent,request_intent_hash,before_state,after_state)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),v_booking_id,p_vehicle_id,'create',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_unallocated_drag'),80),nullif(left(btrim(coalesce(p_metadata->>'reason','')),500),''),p_cascade,
   v_before->'bookings',v_after->'bookings',v_result,v_intent,v_hash,v_before,v_after) returning receipt_id into v_receipt;
 return v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false);
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.request_intent is not distinct from v_intent and v_existing.request_intent_hash is not distinct from v_hash then
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
end $fn$;

create or replace function public.administrator_move_workshop_booking(
 p_booking_id uuid,p_expected_version integer,p_stage_code text,p_bay_number integer,p_scheduled_start_at timestamptz,
 p_duration_minutes integer,p_override_reason text,p_metadata jsonb,p_request_id uuid,p_cascade boolean default false)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $fn$
declare
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype; v_booking public.workshop_bookings%rowtype;
 v_target_stage uuid; v_target_bay uuid; v_ids uuid[]; v_before jsonb; v_after jsonb; v_result jsonb; v_receipt uuid; v_intent jsonb; v_hash text;
begin
 perform public.workshop_require_website_administrator_238();
 if p_request_id is null or p_booking_id is null or p_expected_version is null then raise exception 'PDC_244_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 v_intent:=jsonb_build_object('operation','move','booking_id',p_booking_id,'expected_version',p_expected_version,
   'stage_code',public.workshop_canonical_stage_code(p_stage_code),'bay_number',p_bay_number,'scheduled_start_at',p_scheduled_start_at,
   'duration_minutes',p_duration_minutes,'override_reason',p_override_reason,'metadata',coalesce(p_metadata,'{}'::jsonb),'cascade',coalesce(p_cascade,false));
 v_hash:=encode(digest(convert_to(v_intent::text,'UTF8'),'sha256'),'hex');
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.request_intent is distinct from v_intent or v_existing.request_intent_hash is distinct from v_hash then raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023'; end if;
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 if v_booking.deleted_at is not null or v_booking.status not in('queued','planned') or v_booking.actual_start_at is not null or v_booking.actual_end_at is not null then return jsonb_build_object('ok',false,'error','protected_booking'); end if;
 select id into v_target_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_target_bay from public.workshop_bays where stage_id=v_target_stage and bay_number=p_bay_number and is_active;
 if v_target_stage is null or v_target_bay is null then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-move:'||p_booking_id::text,0));
 select coalesce(array_agg(x.id order by x.id),'{}'::uuid[]) into v_ids from public.workshop_bookings x
 where x.id=p_booking_id or (x.deleted_at is null and x.status in('queued','planned') and x.bay_id in(v_booking.bay_id,v_target_bay));
 perform 1 from public.workshop_bookings x where x.id=any(v_ids) order by x.id for update;
 v_before:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move(p_booking_id,p_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority','website_administrator'));
 else
   v_result:=public.move_workshop_booking(p_booking_id,p_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority','website_administrator'));
 end if;
 if coalesce((v_result->>'ok')::boolean,false) is not true then return v_result; end if;
 v_after:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',p_booking_id,'booking_version',(select version from public.workshop_bookings where id=p_booking_id),'operation_type','move');
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,
   before_rows,after_rows,result,request_intent,request_intent_hash,before_state,after_state)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),p_booking_id,v_booking.vehicle_id,'move',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_drag_drop'),80),nullif(left(btrim(coalesce(p_override_reason,p_metadata->>'reason','')),500),''),p_cascade,
   v_before->'bookings',v_after->'bookings',v_result,v_intent,v_hash,v_before,v_after) returning receipt_id into v_receipt;
 return v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false);
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.request_intent is not distinct from v_intent and v_existing.request_intent_hash is not distinct from v_hash then return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true); end if;
 raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
end $fn$;

create or replace function public.undo_administrator_workshop_booking_move(p_receipt_id uuid,p_expected_version integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $fn$
declare r public.workshop_booking_move_receipts%rowtype; v_current jsonb; v_ids uuid[]; v_before_booking jsonb; v_before_vehicle jsonb; v_result jsonb; v_email text; v_result_booking_version integer;
begin
 perform public.workshop_require_website_administrator_238();
 if p_receipt_id is null or p_expected_version is null or p_request_id is null then raise exception 'PDC_244_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 select * into r from public.workshop_booking_move_receipts where receipt_id=p_receipt_id for update;
 if not found then return jsonb_build_object('ok',false,'error','receipt_not_found'); end if;
 if r.actor_user_id<>auth.uid() then return jsonb_build_object('ok',false,'error','undo_actor_mismatch'); end if;
 if r.undone_at is not null then
   if r.undo_request_id=p_request_id then return r.undo_result||jsonb_build_object('idempotent_replay',true); end if;
   return jsonb_build_object('ok',false,'error','already_undone');
 end if;
 if r.created_at<clock_timestamp()-interval '15 minutes' then return jsonb_build_object('ok',false,'error','undo_expired'); end if;
 if r.before_state is null or r.after_state is null or r.request_intent is null then return jsonb_build_object('ok',false,'error','legacy_receipt_not_exactly_reversible'); end if;
 select array_agg((x->>'id')::uuid order by (x->>'id')::uuid) into v_ids from jsonb_array_elements(r.after_state->'bookings') x;
 perform 1 from public.workshop_bookings b where b.id=any(v_ids) order by b.id for update;
 perform 1 from public.workshop_booking_assignments a where a.booking_id=any(v_ids) order by a.id for update;
 perform 1 from public.vehicles v where v.id=r.vehicle_id for update;
 v_current:=public.workshop_admin_state_244(v_ids,r.vehicle_id);
 if v_current is distinct from r.after_state then return jsonb_build_object('ok',false,'error','undo_conflict','message','Booking, assignment or vehicle state changed after the Administrator action. Refresh and review before retrying.'); end if;
 if (select version from public.workshop_bookings where id=r.booking_id)<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 -- Restore every pre-existing booking business field. Audit/version advances while operational state returns exactly.
 update public.workshop_bookings b set
   vehicle_id=(x.row->>'vehicle_id')::uuid,stage_id=(x.row->>'stage_id')::uuid,bay_id=(x.row->>'bay_id')::uuid,status=(x.row->>'status')::public.workshop_booking_status,
   scheduled_start_at=(x.row->>'scheduled_start_at')::timestamptz,scheduled_end_at=(x.row->>'scheduled_end_at')::timestamptz,default_duration_minutes=(x.row->>'default_duration_minutes')::integer,
   actual_start_at=(x.row->>'actual_start_at')::timestamptz,actual_end_at=(x.row->>'actual_end_at')::timestamptz,actual_duration_minutes=(x.row->>'actual_duration_minutes')::integer,
   stoppage_reason=x.row->>'stoppage_reason',stoppage_started_at=(x.row->>'stoppage_started_at')::timestamptz,stoppage_accumulated_minutes=(x.row->>'stoppage_accumulated_minutes')::integer,
   returned_to_queue_at=(x.row->>'returned_to_queue_at')::timestamptz,deleted_at=(x.row->>'deleted_at')::timestamptz,deleted_reason=x.row->>'deleted_reason',source=x.row->>'source',
   metadata_legacy_plan_id=x.row->>'metadata_legacy_plan_id',metadata=coalesce(x.row->'metadata','{}'::jsonb),eta_at_booking=(x.row->>'eta_at_booking')::date,
   eta_risk_status=x.row->>'eta_risk_status',eta_risk_detected_at=(x.row->>'eta_risk_detected_at')::timestamptz,legacy_ambiguity_quarantined=(x.row->>'legacy_ambiguity_quarantined')::boolean,
   version=b.version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
 from jsonb_array_elements(r.before_state->'bookings') x(row) where b.id=(x.row->>'id')::uuid;
 -- Restore assignments that existed before, and release only assignments created by this action.
 update public.workshop_booking_assignments a set technician_id=(x.row->>'technician_id')::uuid,assignment_type=(x.row->>'assignment_type')::public.workshop_assignment_type,
   assigned_at=(x.row->>'assigned_at')::timestamptz,assigned_by=(x.row->>'assigned_by')::uuid,scheduled_start_at=(x.row->>'scheduled_start_at')::timestamptz,
   scheduled_end_at=(x.row->>'scheduled_end_at')::timestamptz,released_at=(x.row->>'released_at')::timestamptz,notes=x.row->>'notes',updated_at=clock_timestamp()
 from jsonb_array_elements(r.before_state->'assignments') x(row) where a.id=(x.row->>'id')::uuid;
 update public.workshop_booking_assignments a set released_at=clock_timestamp(),updated_at=clock_timestamp()
 where a.booking_id=any(v_ids) and not exists(select 1 from jsonb_array_elements(r.before_state->'assignments') x where x->>'id'=a.id::text) and a.released_at is null;
 if r.operation_type='create' then
   -- Assignments and transition authorisations cascade. History retains its
   -- immutable before/after state and the receipt retains the booking UUID.
   delete from public.workshop_bookings where id=r.booking_id;
   if found then v_result_booking_version:=null; end if;
 else
   select version into v_result_booking_version from public.workshop_bookings where id=r.booking_id;
 end if;
 v_before_vehicle:=r.before_state->'vehicle';
 update public.vehicles v set
   current_location=v_before_vehicle->>'current_location',pmb_stage=v_before_vehicle->>'pmb_stage',pmb_bay_stage=v_before_vehicle->>'pmb_bay_stage',pmb_bay_number=v_before_vehicle->>'pmb_bay_number',
   active_workshop_booking_id=(v_before_vehicle->>'active_workshop_booking_id')::uuid,workshop_status=v_before_vehicle->>'workshop_status',
   workshop_status_updated_at=(v_before_vehicle->>'workshop_status_updated_at')::timestamptz,workshop_status_updated_by=(v_before_vehicle->>'workshop_status_updated_by')::uuid,
   visible_on_board=(v_before_vehicle->>'visible_on_board')::boolean,version=v.version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
 where v.id=r.vehicle_id;
 select email into v_email from public.pdc_user_roles where auth_user_id=auth.uid();
 insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
 values(r.booking_id,case when r.operation_type='create' then 'administrator_booking_create_undone' else 'administrator_booking_move_undone' end,
   r.after_state,r.before_state,jsonb_build_object('source','website_undo','receipt_id',r.receipt_id,'request_id',p_request_id,'operation_type',r.operation_type),auth.uid(),coalesce(v_email,auth.jwt()->>'email'));
 -- Derive the durable terminal payload before writing history or consuming the
 -- receipt. These are the only writes after complete state validation/reversal.
 v_result:=jsonb_build_object('ok',true,'receipt_id',r.receipt_id,'booking_id',r.booking_id,'booking_version',v_result_booking_version,
   'vehicle_version',(select version from public.vehicles where id=r.vehicle_id),'operation_type',r.operation_type,'returned_to_unallocated',r.operation_type='create');
 update public.workshop_booking_move_receipts set undone_at=clock_timestamp(),undone_by=auth.uid(),undo_request_id=p_request_id,undo_result=v_result where receipt_id=r.receipt_id;
 perform public.workshop_bump_revision();
 return v_result;
end $fn$;

-- Legacy booking scheduling endpoints are private implementation details only.
revoke all on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb) from public,anon,authenticated;
revoke all on function public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from public,anon,authenticated;
revoke all on function public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from public,anon,authenticated;
revoke all on function public.resize_workshop_booking(uuid,integer,integer,jsonb) from public,anon,authenticated;
revoke all on function public.change_booking_bay(uuid,integer,integer,jsonb) from public,anon,authenticated;
revoke all on function public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.undo_administrator_workshop_booking_move(uuid,integer,uuid) from public,anon,authenticated,service_role;
grant execute on function public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean) to authenticated;
grant execute on function public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean) to authenticated;
grant execute on function public.undo_administrator_workshop_booking_move(uuid,integer,uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('244','workshop_admin_authority_intent_receipt_undo',array['staging-only forward authority closure, complete intent/state receipts and exact create Undo'])
on conflict(version) do update set name=excluded.name,statements=excluded.statements
where supabase_migrations.schema_migrations.name=excluded.name;

do $verify$
begin
 if not exists(select 1 from supabase_migrations.schema_migrations where version='244' and name='workshop_admin_authority_intent_receipt_undo') then raise exception 'PDC_244_LEDGER_VERIFY_FAILED'; end if;
 if has_function_privilege('authenticated','public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)','EXECUTE')
    or has_function_privilege('authenticated','public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)','EXECUTE')
    or has_function_privilege('authenticated','public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)','EXECUTE')
    or has_function_privilege('authenticated','public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb)','EXECUTE')
    or has_function_privilege('authenticated','public.resize_workshop_booking(uuid,integer,integer,jsonb)','EXECUTE')
    or has_function_privilege('authenticated','public.change_booking_bay(uuid,integer,integer,jsonb)','EXECUTE') then raise exception 'PDC_244_LEGACY_GRANT_VERIFY_FAILED'; end if;
 if not has_function_privilege('authenticated','public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)','EXECUTE')
    or not has_function_privilege('authenticated','public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)','EXECUTE')
    or not has_function_privilege('authenticated','public.undo_administrator_workshop_booking_move(uuid,integer,uuid)','EXECUTE') then raise exception 'PDC_244_ADMIN_GRANT_VERIFY_FAILED'; end if;
 if public.workshop_parts_ready(gen_random_uuid()) is not true then raise exception 'PDC_244_PARTS_NON_GATE_VERIFY_FAILED'; end if;
end $verify$;
commit;
