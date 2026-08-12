-- Staging-only migration 205: recoverable Administrator vehicle lifecycle and one-use Email Monitor recreation.
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-205-recoverable-vehicle-archive',0));

do $guard$
begin
 if not public.pdc_monitor_staging_guard()
    or to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='204' and name='align_monitor_enqueue_acl_and_upload_policy')
    or exists(select 1 from supabase_migrations.schema_migrations where version='205') then
  raise exception 'PDC_205_STAGING_OR_LEDGER_MISMATCH' using errcode='55000',detail='wrong_environment_or_predecessor';
 end if;
end
$guard$;

create table public.pdc_vehicle_tombstones(
 tombstone_id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null,
 normalized_stock text not null,
 stock_number text not null,
 tombstone_kind text not null check(tombstone_kind in('manual_delete','staging_reset')),
 deleted_by uuid not null references auth.users(id) on delete restrict,
 deleted_by_email text not null,
 deleted_at timestamptz not null default clock_timestamp(),
 reason text not null check(length(btrim(reason)) between 8 and 300),
 previous_lifecycle_state public.vehicle_lifecycle_state not null,
 previous_location text,
 previous_visible_on_board boolean not null,
 previous_status text,
 vehicle_snapshot jsonb not null check(jsonb_typeof(vehicle_snapshot)='object')
);
create index pdc_vehicle_tombstones_stock_idx on public.pdc_vehicle_tombstones(normalized_stock,deleted_at desc);
create index pdc_vehicle_tombstones_vehicle_idx on public.pdc_vehicle_tombstones(vehicle_id,deleted_at desc);
create index pdc_vehicle_tombstones_archive_idx on public.pdc_vehicle_tombstones(deleted_at desc,tombstone_id);

create table public.pdc_vehicle_lifecycle_events(
 event_id bigint generated always as identity primary key,
 tombstone_id uuid not null references public.pdc_vehicle_tombstones(tombstone_id) on delete restrict,
 vehicle_id uuid not null,
 normalized_stock text not null,
 event_kind text not null check(event_kind in('archived','reset','restored','recreation_authorized','recreation_consumed')),
 actor_id uuid not null references auth.users(id) on delete restrict,
 actor_email text not null,
 event_at timestamptz not null default clock_timestamp(),
 evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(evidence)='object')
);
create index pdc_vehicle_lifecycle_events_tombstone_idx on public.pdc_vehicle_lifecycle_events(tombstone_id,event_id);

create table public.pdc_vehicle_recreation_permissions(
 permission_id uuid primary key default gen_random_uuid(),
 tombstone_id uuid not null references public.pdc_vehicle_tombstones(tombstone_id) on delete restrict,
 normalized_stock text not null,
 intended_source_system text not null default 'authenticated_email' check(intended_source_system='authenticated_email'),
 authorized_by uuid not null references auth.users(id) on delete restrict,
 authorized_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null,
 consumed_at timestamptz,
 consumed_vehicle_id uuid,
 check(expires_at>authorized_at and expires_at<=authorized_at+interval '2 hours'),
 check((consumed_at is null and consumed_vehicle_id is null) or (consumed_at is not null and consumed_vehicle_id is not null))
);
create unique index pdc_vehicle_recreation_one_open_idx on public.pdc_vehicle_recreation_permissions(tombstone_id) where consumed_at is null;

alter table public.pdc_vehicle_tombstones enable row level security;
alter table public.pdc_vehicle_lifecycle_events enable row level security;
alter table public.pdc_vehicle_recreation_permissions enable row level security;
revoke all on public.pdc_vehicle_tombstones,public.pdc_vehicle_lifecycle_events,public.pdc_vehicle_recreation_permissions from public,anon,authenticated,service_role;

create or replace function public.pdc_vehicle_archive_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 raise exception 'PDC_VEHICLE_ARCHIVE_IMMUTABLE' using errcode='55000',detail='immutable_audit_trail';
end $$;
revoke all on function public.pdc_vehicle_archive_immutable() from public,anon,authenticated,service_role;
create trigger pdc_vehicle_tombstones_immutable before update or delete on public.pdc_vehicle_tombstones for each row execute function public.pdc_vehicle_archive_immutable();
create trigger pdc_vehicle_lifecycle_events_immutable before update or delete on public.pdc_vehicle_lifecycle_events for each row execute function public.pdc_vehicle_archive_immutable();
-- Permissions may only transition once from unconsumed to consumed inside the vehicle trigger.
create or replace function public.pdc_vehicle_recreation_permission_guard()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if tg_op='DELETE' or old.tombstone_id is distinct from new.tombstone_id or old.normalized_stock is distinct from new.normalized_stock
    or old.intended_source_system is distinct from new.intended_source_system or old.authorized_by is distinct from new.authorized_by
    or old.authorized_at is distinct from new.authorized_at or old.expires_at is distinct from new.expires_at
    or old.consumed_at is not null or new.consumed_at is null or new.consumed_vehicle_id is null then
  raise exception 'PDC_VEHICLE_RECREATION_PERMISSION_IMMUTABLE' using errcode='55000',detail='immutable_or_invalid_consumption';
 end if;
 return new;
end $$;
revoke all on function public.pdc_vehicle_recreation_permission_guard() from public,anon,authenticated,service_role;
create trigger pdc_vehicle_recreation_permission_guard before update or delete on public.pdc_vehicle_recreation_permissions for each row execute function public.pdc_vehicle_recreation_permission_guard();

create or replace function public.pdc_admin_vehicle_actor()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_role text;
begin
 if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
 if v_uid is null or v_email='' then return public.navision_backend_response(false,'administrator_required'); end if;
 select r.role::text into v_role from public.pdc_user_roles r
 where r.auth_user_id=v_uid and lower(r.email)=v_email and r.active and r.account_status='approved' for share;
 if v_role is distinct from 'administrator' then return public.navision_backend_response(false,'administrator_required'); end if;
 return public.navision_backend_response(true,'administrator',jsonb_build_object('actor_id',v_uid,'actor_email',v_email));
end $$;
revoke all on function public.pdc_admin_vehicle_actor() from public,anon,authenticated,service_role;

create or replace function public.pdc_vehicle_archive_recreation_gate()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_stock text;v_t public.pdc_vehicle_tombstones%rowtype;v_p public.pdc_vehicle_recreation_permissions%rowtype;v_source text;
begin
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_205_NOT_STAGING' using errcode='55000',detail='wrong_environment'; end if;
 v_stock:=coalesce(new.stock_number_normalized,public.normalize_vehicle_stock_number(new.stock_number));
 if tg_op='UPDATE' then
  select * into v_t from public.pdc_vehicle_tombstones t where t.vehicle_id=old.id
   and not exists(select 1 from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=t.tombstone_id and e.event_kind='restored')
   order by t.deleted_at desc limit 1 for share;
  if found then
   v_stock:=v_t.normalized_stock;
   perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-tombstone-stock:'||v_stock,0));
  end if;
 end if;
 if v_t.tombstone_id is null then
  if v_stock is null then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-tombstone-stock:'||v_stock,0));
  select * into v_t from public.pdc_vehicle_tombstones t where t.normalized_stock=v_stock
   and not exists(select 1 from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=t.tombstone_id and e.event_kind='restored')
   order by t.deleted_at desc limit 1 for share;
 end if;
 if not found then return new; end if;
 if exists(select 1 from public.pdc_vehicle_recreation_permissions p where p.tombstone_id=v_t.tombstone_id and p.consumed_at is not null and p.consumed_vehicle_id=new.id) then return new; end if;
 if tg_op='UPDATE' and new.id=v_t.vehicle_id and current_setting('pdc.vehicle_restore_tombstone',true)=v_t.tombstone_id::text then return new; end if;
 if tg_op='UPDATE' then
  raise exception 'PDC_VEHICLE_TOMBSTONED' using errcode='55000',detail='vehicle_tombstoned';
 end if;
 v_source:=lower(btrim(coalesce(new.source_system,'')));
 if v_source<>'authenticated_email' then
  raise exception 'PDC_RECREATION_AUTHORIZATION_REQUIRED' using errcode='55000',detail='recreation_authorization_required';
 end if;
 select * into v_p from public.pdc_vehicle_recreation_permissions
 where tombstone_id=v_t.tombstone_id and normalized_stock=v_stock and intended_source_system='authenticated_email' and consumed_at is null
 order by authorized_at desc limit 1 for update;
 if not found then raise exception 'PDC_RECREATION_AUTHORIZATION_REQUIRED' using errcode='55000',detail='recreation_authorization_required'; end if;
 if v_p.expires_at<=clock_timestamp() then raise exception 'PDC_RECREATION_AUTHORIZATION_EXPIRED' using errcode='55000',detail='recreation_authorization_expired'; end if;
 update public.pdc_vehicle_recreation_permissions set consumed_at=clock_timestamp(),consumed_vehicle_id=new.id where permission_id=v_p.permission_id;
 insert into public.pdc_vehicle_lifecycle_events(tombstone_id,vehicle_id,normalized_stock,event_kind,actor_id,actor_email,evidence)
 values(v_t.tombstone_id,new.id,v_stock,'recreation_consumed',v_p.authorized_by,'email-monitor',jsonb_build_object('permission_id',v_p.permission_id,'source_system',v_source));
 return new;
end $$;
revoke all on function public.pdc_vehicle_archive_recreation_gate() from public,anon,authenticated,service_role;
drop trigger if exists pdc_vehicle_archive_recreation_gate on public.vehicles;
create trigger pdc_vehicle_archive_recreation_gate before insert or update of stock_number,stock_number_normalized,source_system,lifecycle_state,deleted_at,visible_on_board on public.vehicles
for each row execute function public.pdc_vehicle_archive_recreation_gate();

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
 insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
 select b.id,'vehicle_archived',null,to_jsonb(b),jsonb_build_object('tombstone_id',t.tombstone_id,'reason',btrim(p_reason)),v_uid,v_email
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

create or replace function public.pdc_admin_reset_staging_test_vehicle(p_vehicle_id uuid,p_expected_version integer,p_confirmation_stock text,p_reason text)
returns jsonb language sql security definer set search_path=pg_catalog,public as $$select public.pdc_admin_archive_vehicle(p_vehicle_id,p_expected_version,p_confirmation_stock,p_reason,'staging_reset')$$;

create or replace function public.pdc_admin_restore_vehicle(p_tombstone_id uuid,p_confirmation_stock text,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb;t public.pdc_vehicle_tombstones%rowtype;v public.vehicles%rowtype;v_after public.vehicles%rowtype;v_uid uuid;v_email text;v_now timestamptz:=clock_timestamp();
begin
 s:=public.pdc_admin_vehicle_actor();if not coalesce((s->>'ok')::boolean,false) then return s;end if;v_uid:=(s->'data'->>'actor_id')::uuid;v_email:=s->'data'->>'actor_email';
 if p_tombstone_id is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300 then return public.navision_backend_response(false,'invalid_input',jsonb_build_object('detail','reason_required_8_300'));end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-tombstone:'||p_tombstone_id::text,0));
 select * into t from public.pdc_vehicle_tombstones where tombstone_id=p_tombstone_id for update;
 if not found or exists(select 1 from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=t.tombstone_id and e.event_kind='restored') then return public.navision_backend_response(false,'vehicle_not_tombstoned');end if;
 if p_confirmation_stock is distinct from t.normalized_stock then return public.navision_backend_response(false,'invalid_input',jsonb_build_object('detail','confirmation_stock_mismatch','normalized_stock',t.normalized_stock));end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-lifecycle:'||t.vehicle_id::text,0));
 select * into v from public.vehicles where id=t.vehicle_id for update;
 if not found then return public.navision_backend_response(false,'restore_state_conflict',jsonb_build_object('detail','original_vehicle_uuid_missing'));end if;
 if exists(select 1 from public.vehicles x where x.id<>t.vehicle_id and x.stock_number_normalized=t.normalized_stock) then return public.navision_backend_response(false,'restore_identity_conflict');end if;
 s:=public.pdc_admin_vehicle_actor();if not coalesce((s->>'ok')::boolean,false) then return s;end if;
 perform set_config('pdc.vehicle_restore_tombstone',t.tombstone_id::text,true);
 update public.vehicles set stock_number=t.stock_number,lifecycle_state=t.previous_lifecycle_state,visible_on_board=t.previous_visible_on_board,current_location=t.previous_location,
  pmb_stage=t.vehicle_snapshot->>'pmb_stage',pmb_bay_stage=t.vehicle_snapshot->>'pmb_bay_stage',pmb_bay_number=t.vehicle_snapshot->>'pmb_bay_number',pmb_key_tag=t.vehicle_snapshot->>'pmb_key_tag',
  workshop_status=coalesce(t.previous_status,'queued'),active_workshop_booking_id=null,
  deleted_at=null,deleted_reason=null,board_purged_at=null,board_purge_reason=null,board_purged_by=null,version=version+1,updated_by=v_uid,updated_at=v_now
 where id=t.vehicle_id returning * into v_after;
 -- Tombstones remain immutable; the append-only restore event closes active tombstone state.
 insert into public.pdc_vehicle_lifecycle_events(tombstone_id,vehicle_id,normalized_stock,event_kind,actor_id,actor_email,evidence)
 values(t.tombstone_id,t.vehicle_id,t.normalized_stock,'restored',v_uid,v_email,jsonb_build_object('reason',btrim(p_reason),'same_vehicle_uuid',true,'bookings_reactivated',false,'overlays_reactivated',false));
 insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 values('restore'::public.audit_action,'vehicles',v.id,v.id,v_uid,v_email,to_jsonb(v),to_jsonb(v_after),jsonb_build_object('source','recoverable_vehicle_restore_205','tombstone_id',t.tombstone_id));
 update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;perform public.workshop_bump_revision();
 return public.navision_backend_response(true,'vehicle_restored',jsonb_build_object('vehicle_id',v_after.id,'vehicle_version',v_after.version,'tombstone_id',t.tombstone_id,'bookings_reactivated',false));
end $$;

create or replace function public.pdc_admin_allow_vehicle_recreation_once(p_tombstone_id uuid,p_confirmation_stock text,p_reason text,p_ttl_minutes integer default 30)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb;t public.pdc_vehicle_tombstones%rowtype;p public.pdc_vehicle_recreation_permissions%rowtype;v_uid uuid;v_email text;
begin
 s:=public.pdc_admin_vehicle_actor();if not coalesce((s->>'ok')::boolean,false) then return s;end if;v_uid:=(s->'data'->>'actor_id')::uuid;v_email:=s->'data'->>'actor_email';
 if p_tombstone_id is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300 or p_ttl_minutes not between 1 and 120 then return public.navision_backend_response(false,'invalid_input');end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-tombstone:'||p_tombstone_id::text,0));select * into t from public.pdc_vehicle_tombstones where tombstone_id=p_tombstone_id for share;
 if not found or exists(select 1 from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=t.tombstone_id and e.event_kind='restored') then return public.navision_backend_response(false,'vehicle_not_tombstoned');end if;
 if p_confirmation_stock is distinct from t.normalized_stock then return public.navision_backend_response(false,'invalid_input',jsonb_build_object('detail','confirmation_stock_mismatch'));end if;
 if t.tombstone_kind<>'staging_reset' then return public.navision_backend_response(false,'manual_tombstone_restore_required');end if;
 if exists(select 1 from public.pdc_vehicle_recreation_permissions x where x.tombstone_id=t.tombstone_id and x.consumed_at is not null) then return public.navision_backend_response(false,'recreation_authorization_consumed');end if;
 insert into public.pdc_vehicle_recreation_permissions(tombstone_id,normalized_stock,authorized_by,expires_at)
 values(t.tombstone_id,t.normalized_stock,v_uid,clock_timestamp()+make_interval(mins=>p_ttl_minutes)) returning * into p;
 insert into public.pdc_vehicle_lifecycle_events(tombstone_id,vehicle_id,normalized_stock,event_kind,actor_id,actor_email,evidence)
 values(t.tombstone_id,t.vehicle_id,t.normalized_stock,'recreation_authorized',v_uid,v_email,jsonb_build_object('permission_id',p.permission_id,'source_system','authenticated_email','reason',btrim(p_reason),'expires_at',p.expires_at));
 return public.navision_backend_response(true,'recreation_authorized_once',jsonb_build_object('permission_id',p.permission_id,'tombstone_id',t.tombstone_id,'expires_at',p.expires_at));
end $$;

create or replace function public.pdc_admin_archived_vehicle_snapshot(p_tombstone_id uuid default null,p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare s jsonb;rows jsonb;
begin
 s:=public.pdc_admin_vehicle_actor();if not coalesce((s->>'ok')::boolean,false) then return s;end if;
 if p_limit not between 1 and 200 then return public.navision_backend_response(false,'invalid_input');end if;
 select coalesce(jsonb_agg(x order by x.deleted_at desc,x.tombstone_id),'[]'::jsonb) into rows from (
  select t.tombstone_id,t.vehicle_id,t.stock_number,t.normalized_stock,t.tombstone_kind,t.deleted_by_email,t.deleted_at,t.reason,t.previous_lifecycle_state,t.previous_location,t.previous_visible_on_board,t.previous_status,t.vehicle_snapshot,
   (select coalesce(jsonb_agg(e order by e.event_id),'[]'::jsonb) from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=t.tombstone_id) lifecycle_events
  from public.pdc_vehicle_tombstones t where (p_tombstone_id is null or t.tombstone_id=p_tombstone_id) order by t.deleted_at desc limit p_limit
 )x;
 return public.navision_backend_response(true,'archived_vehicle_snapshot',jsonb_build_object('items',rows));
end $$;

revoke all on function public.pdc_admin_archive_vehicle(uuid,integer,text,text,text),public.pdc_admin_reset_staging_test_vehicle(uuid,integer,text,text),public.pdc_admin_restore_vehicle(uuid,text,text),public.pdc_admin_allow_vehicle_recreation_once(uuid,text,text,integer),public.pdc_admin_archived_vehicle_snapshot(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.pdc_admin_archive_vehicle(uuid,integer,text,text,text),public.pdc_admin_reset_staging_test_vehicle(uuid,integer,text,text),public.pdc_admin_restore_vehicle(uuid,text,text),public.pdc_admin_allow_vehicle_recreation_once(uuid,text,text,integer),public.pdc_admin_archived_vehicle_snapshot(uuid,integer) to authenticated;

do $realtime$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='vehicles') then alter publication supabase_realtime add table public.vehicles;end if;
end $realtime$;

insert into supabase_migrations.schema_migrations(version,name,statements) values('205','admin_recoverable_vehicle_archive',array[
 'Recoverable Administrator archive/reset tombstones preserving operational and immutable source history',
 'Same-UUID explicit restore without automatic booking or overlay reactivation',
 'Atomic one-use reset-only authenticated_email recreation permission and tombstone trigger gate',
 'Administrator archive snapshot, immutable lifecycle events, strict ACL and Realtime revision signals'
]);
commit;
