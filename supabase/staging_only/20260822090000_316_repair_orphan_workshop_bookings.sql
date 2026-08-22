begin;

-- Staging-only one-time repair for workshop bookings left active before the
-- recoverable archive RPC began cascading vehicle archives to bookings.
do $repair$
declare
  v_project text;
  v_actor uuid;
  v_email text;
  v_target_count integer;
  v_updated_count integer;
  v_history_count integer;
  v_remaining integer;
  v_now timestamptz := clock_timestamp();
begin
  if to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'PDC_316_PRODUCTION_SENTINEL_PRESENT';
  end if;
  if not public.pdc_monitor_staging_guard() then
    raise exception 'PDC_316_STAGING_GUARD_FAILED';
  end if;
  select project_ref into v_project
  from public.pdc_staging_environment_sentinel
  where singleton;
  if v_project is distinct from 'cdsmnqxtyyoeoznmbidd' then
    raise exception 'PDC_316_PROJECT_MISMATCH';
  end if;

  select auth_user_id, lower(email)
  into v_actor, v_email
  from public.pdc_user_roles
  where role = 'administrator'
    and active
    and account_status = 'approved'
    and lower(email) = 'craig.watson@broometoyota.com.au'
  limit 1;
  if v_actor is null then
    raise exception 'PDC_316_OWNER_ADMIN_MISSING';
  end if;
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_actor, 'role', 'authenticated', 'email', v_email)::text,
    true
  );

  create temporary table pdc_316_orphan_booking_before
  on commit drop
  as
  select b.id as booking_id, b.vehicle_id, to_jsonb(b) as before_data
  from public.workshop_bookings b
  join public.vehicles v on v.id = b.vehicle_id
  where b.deleted_at is null
    and b.status in ('queued','planned','started','stoppage')
    and (v.deleted_at is not null or v.lifecycle_state <> 'active')
  order by b.id
  for update of b;

  select count(*) into v_target_count from pdc_316_orphan_booking_before;
  if v_target_count <> 230 then
    raise exception 'PDC_316_SCOPE_DRIFT expected=230 actual=%', v_target_count;
  end if;

  update public.workshop_bookings b
  set deleted_at = v_now,
      deleted_reason = 'Parent vehicle archived: legacy orphan repair 316',
      version = b.version + 1,
      updated_by = v_actor,
      updated_at = v_now
  from pdc_316_orphan_booking_before t
  where b.id = t.booking_id
    and b.deleted_at is null;
  get diagnostics v_updated_count = row_count;
  if v_updated_count <> v_target_count then
    raise exception 'PDC_316_UPDATE_COUNT_MISMATCH expected=% actual=%', v_target_count, v_updated_count;
  end if;

  insert into public.workshop_booking_history(
    booking_id, event_type, before_data, after_data, metadata,
    actor_user_id, actor_email, vehicle_id, purged_booking_id
  )
  select
    b.id,
    'vehicle_archived',
    t.before_data,
    to_jsonb(b),
    jsonb_build_object(
      'migration', '316_repair_orphan_workshop_bookings',
      'reason', 'Parent vehicle was already archived before booking cascade cleanup existed',
      'scope', 'staging_deleted_parent_only'
    ),
    v_actor,
    v_email,
    b.vehicle_id,
    b.id
  from pdc_316_orphan_booking_before t
  join public.workshop_bookings b on b.id = t.booking_id;
  get diagnostics v_history_count = row_count;
  if v_history_count <> v_target_count then
    raise exception 'PDC_316_HISTORY_COUNT_MISMATCH expected=% actual=%', v_target_count, v_history_count;
  end if;

  perform public.workshop_bump_revision();

  select count(*) into v_remaining
  from public.workshop_bookings b
  join public.vehicles v on v.id = b.vehicle_id
  where b.deleted_at is null
    and b.status in ('queued','planned','started','stoppage')
    and (v.deleted_at is not null or v.lifecycle_state <> 'active');
  if v_remaining <> 0 then
    raise exception 'PDC_316_ORPHANS_REMAIN count=%', v_remaining;
  end if;
end
$repair$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values(
  '20260822090000',
  '316_repair_orphan_workshop_bookings',
  array['staging-only audited orphan workshop booking repair']
)
on conflict (version) do nothing;

commit;
