-- Staging-only forward correction 248: bind Create Undo history to the
-- authoritative booking before deletion; ON DELETE SET NULL preserves its
-- immutable purged_booking_id audit identity.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));
do $guard$
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='247' and name='workshop_admin_null_role_fail_closed')
    or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::numeric>248)
    or exists(select 1 from supabase_migrations.schema_migrations where version='248' and name<>'workshop_admin_create_undo_history_identity') then
   raise exception 'PDC_248_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end $guard$;

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
 values(r.booking_id,
   case when r.operation_type='create' then 'administrator_booking_create_undone' else 'administrator_booking_move_undone' end,
   r.after_state,r.before_state,jsonb_build_object('source','website_undo','receipt_id',r.receipt_id,'request_id',p_request_id,
     'operation_type',r.operation_type,'authoritative_booking_id',r.booking_id),auth.uid(),coalesce(v_email,auth.jwt()->>'email'));
 -- Derive the durable terminal payload before writing history or consuming the
 -- receipt. These are the only writes after complete state validation/reversal.
 v_result:=jsonb_build_object('ok',true,'receipt_id',r.receipt_id,'booking_id',r.booking_id,'booking_version',v_result_booking_version,
   'vehicle_version',(select version from public.vehicles where id=r.vehicle_id),'operation_type',r.operation_type,'returned_to_unallocated',r.operation_type='create');
 update public.workshop_booking_move_receipts set undone_at=clock_timestamp(),undone_by=auth.uid(),undo_request_id=p_request_id,undo_result=v_result where receipt_id=r.receipt_id;
 perform public.workshop_bump_revision();
 return v_result;
end $fn$;


revoke all on function public.undo_administrator_workshop_booking_move(uuid,integer,uuid) from public,anon,authenticated,service_role;
grant execute on function public.undo_administrator_workshop_booking_move(uuid,integer,uuid) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('248','workshop_admin_create_undo_history_identity',array['staging-only forward correction: Create Undo history binds booking before delete and retains purged_booking_id']) on conflict(version) do update set name=excluded.name,statements=excluded.statements where supabase_migrations.schema_migrations.name=excluded.name;
do $verify$
begin
 if not exists(select 1 from supabase_migrations.schema_migrations where version='248' and name='workshop_admin_create_undo_history_identity') then raise exception 'PDC_248_LEDGER_VERIFY_FAILED'; end if;
 if position('r.booking_id' in pg_get_functiondef('public.undo_administrator_workshop_booking_move(uuid,integer,uuid)'::regprocedure))=0 then raise exception 'PDC_248_BODY_VERIFY_FAILED'; end if;
end $verify$;
commit;
