-- Staging-only migration 206: preserve required Workshop booking-history identity during recoverable archive.
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-206-recoverable-booking-history',0));
do $guard$
begin
 if not public.pdc_monitor_staging_guard()
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='205' and name='admin_recoverable_vehicle_archive')
    or exists(select 1 from supabase_migrations.schema_migrations where version='206') then
  raise exception 'PDC_206_STAGING_OR_LEDGER_MISMATCH' using errcode='55000',detail='wrong_environment_or_predecessor';
 end if;
end $guard$;

create or replace function public.pdc_admin_archive_vehicle(p_vehicle_id uuid,p_expected_version integer,p_confirmation_stock text,p_reason text,p_kind text default 'manual_delete')
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb;v public.vehicles%rowtype;v_after public.vehicles%rowtype;t public.pdc_vehicle_tombstones%rowtype;v_uid uuid;v_email text;v_stock text;v_now timestamptz:=clock_timestamp();v_bookings integer;v_overlays integer;v_activations integer;
begin
 s:=public.pdc_admin_vehicle_actor();if not coalesce((s->>'ok')::boolean,false) then return s;end if;
 v_uid:=(s->'data'->>'actor_id')::uuid;v_email:=s->'data'->>'actor_email';
 if p_vehicle_id is null or p_expected_version is null or p_kind not in('manual_delete','staging_reset') or length(btrim(coalesce(p_reason,''))) not between 8 and 300 then
  return public.navision_backend_response(false,'invalid_input',jsonb_build_object('detail','reason_required_8_300'));
 end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-lifecycle:'||p_vehicle_id::text,0));
 select * into v from public.vehicles where id=p_vehicle_id for update;
 if not found then return public.navision_backend_response(false,'vehicle_not_found');end if;
 v_stock:=public.normalize_vehicle_stock_number(v.stock_number);
 if v_stock is null or p_confirmation_stock is distinct from v_stock then return public.navision_backend_response(false,'invalid_input',jsonb_build_object('detail','confirmation_stock_mismatch','normalized_stock',v_stock));end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-tombstone-stock:'||v_stock,0));
 select * into t from public.pdc_vehicle_tombstones x where x.vehicle_id=v.id
  and not exists(select 1 from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=x.tombstone_id and e.event_kind='restored')
  order by x.deleted_at desc limit 1 for share;
 if found then return public.navision_backend_response(false,'vehicle_already_tombstoned',jsonb_build_object('tombstone_id',t.tombstone_id));end if;
 if v.version<>p_expected_version then return public.navision_backend_response(false,'vehicle_version_conflict',jsonb_build_object('current_version',v.version));end if;
 -- Recheck exact auth-bound active approved Administrator after every potentially blocking lock.
 s:=public.pdc_admin_vehicle_actor();if not coalesce((s->>'ok')::boolean,false) then return s;end if;
 insert into public.pdc_vehicle_tombstones(vehicle_id,normalized_stock,stock_number,tombstone_kind,deleted_by,deleted_by_email,deleted_at,reason,previous_lifecycle_state,previous_location,previous_visible_on_board,previous_status,vehicle_snapshot)
 values(v.id,v_stock,v.stock_number,p_kind,v_uid,v_email,v_now,btrim(p_reason),v.lifecycle_state,v.current_location,v.visible_on_board,v.workshop_status::text,to_jsonb(v)) returning * into t;
 update public.workshop_bookings set deleted_at=v_now,deleted_reason='Vehicle archived: '||btrim(p_reason),version=version+1,updated_by=v_uid,updated_at=v_now
 where vehicle_id=v.id and deleted_at is null;get diagnostics v_bookings=row_count;
 insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email,vehicle_id,purged_booking_id)
 select b.id,'vehicle_archived',null,to_jsonb(b),jsonb_build_object('tombstone_id',t.tombstone_id,'reason',btrim(p_reason)),v_uid,v_email,v.id,b.id
 from public.workshop_bookings b where b.vehicle_id=v.id and b.deleted_at=v_now;
 update public.vehicle_workshop_line_adjustments set active=false,version=version+1,updated_by=v_uid,updated_at=v_now where vehicle_id=v.id and active;get diagnostics v_overlays=row_count;
 update public.navision_board_activations set active=false,completed_at=coalesce(completed_at,v_now),completion_reason=coalesce(completion_reason,'Vehicle archived'),updated_at=v_now where canonical_vehicle_id=v.id and active;get diagnostics v_activations=row_count;
 perform set_config('pdc.vehicle_restore_tombstone',t.tombstone_id::text,true);
 update public.vehicles set stock_number=null,lifecycle_state='deleted',visible_on_board=false,current_location='Other',pmb_stage=null,pmb_bay_stage=null,pmb_bay_number=null,pmb_key_tag=null,
  active_workshop_booking_id=null,workshop_status='queued',deleted_at=v_now,deleted_reason=btrim(p_reason),board_purged_at=v_now,board_purge_reason=btrim(p_reason),board_purged_by=v_uid,
  version=version+1,updated_by=v_uid,updated_at=v_now where id=v.id returning * into v_after;
 insert into public.pdc_vehicle_lifecycle_events(tombstone_id,vehicle_id,normalized_stock,event_kind,actor_id,actor_email,evidence)
 values(t.tombstone_id,v.id,v_stock,case when p_kind='staging_reset' then 'reset' else 'archived' end,v_uid,v_email,jsonb_build_object('bookings_archived',v_bookings,'overlays_deactivated',v_overlays,'activations_deactivated',v_activations));
 insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 values('delete'::public.audit_action,'vehicles',v.id,v.id,v_uid,v_email,to_jsonb(v),to_jsonb(v_after),jsonb_build_object('source','recoverable_vehicle_archive_205','tombstone_id',t.tombstone_id,'mutable_history_preserved',true));
 update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
 update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;
 perform public.workshop_bump_revision();
 return public.navision_backend_response(true,case when p_kind='staging_reset' then 'vehicle_reset' else 'vehicle_soft_deleted' end,jsonb_build_object('vehicle_id',v.id,'vehicle_version',v_after.version,'tombstone_id',t.tombstone_id));
end $$;

insert into supabase_migrations.schema_migrations(version,name,statements) values('206','recoverable_archive_booking_history_identity',array[
 'Archive Workshop bookings without deleting rows',
 'Record required vehicle_id and purged_booking_id in preserved Workshop booking history'
]);
commit;
