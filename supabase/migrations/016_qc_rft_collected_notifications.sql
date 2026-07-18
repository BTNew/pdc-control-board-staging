begin;

-- Section 4/5 foundation: QC complete -> RFT atomic transition, a proper
-- notification outbox (idempotent, retryable, auditable) for the
-- salesperson "vehicle ready for transport" notification, and RFT
-- Collected -> Completed Vehicles atomic transition. All state changes go
-- through protected RPCs; the database remains the sole authority for
-- permissions and mutation validation, matching the existing workshop RPC
-- pattern (migrations 003/007/010).

do $$
begin
  if not exists (select 1 from pg_type where typname = 'notification_status') then
    create type public.notification_status as enum ('pending', 'sent', 'failed', 'cancelled');
  end if;
end $$;

-- QC completion / RFT collection markers on vehicles. Kept separate from
-- lifecycle_state (active/rft/completed/deleted) so QC sign-off can be
-- audited independently of the location/lifecycle transition it unlocks.
alter table public.vehicles
  add column if not exists qc_completed_at timestamptz,
  add column if not exists qc_completed_by uuid references auth.users(id),
  add column if not exists rft_collected_by uuid references auth.users(id);

comment on column public.vehicles.qc_completed_at is 'Set atomically by qc_complete_vehicle(); required before RFT transfer.';
comment on column public.vehicles.rft_collected_by is 'Set atomically by rft_collect_vehicle(); who confirmed collection.';

-- Notification outbox: QC-complete (and future) notifications are queued
-- here inside the same transaction as the state change, then a separate
-- worker (send_pending_vehicle_notifications, called by an external/cron
-- process with the service role) delivers them. This decouples unreliable
-- email delivery from the atomic database transaction, and the
-- idempotency_key + unique index below guarantees a double-click on
-- "Complete QC" can never enqueue (or send) a duplicate notification for
-- the same vehicle/event.
create table if not exists public.vehicle_notifications (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  notification_type text not null,
  idempotency_key text not null,
  recipient_email text,
  recipient_name text,
  subject text not null,
  body text not null,
  status public.notification_status not null default 'pending',
  attempts integer not null default 0,
  max_attempts integer not null default 5,
  last_error text,
  last_attempted_at timestamptz,
  sent_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (idempotency_key)
);

create index if not exists vehicle_notifications_vehicle_id_idx on public.vehicle_notifications(vehicle_id);
create index if not exists vehicle_notifications_status_idx on public.vehicle_notifications(status) where status in ('pending', 'failed');

alter table public.vehicle_notifications enable row level security;

drop policy if exists vehicle_notifications_select on public.vehicle_notifications;
create policy vehicle_notifications_select on public.vehicle_notifications
  for select to authenticated
  using (public.current_pdc_user_role() in ('operator', 'administrator', 'importer'));

-- No direct insert/update/delete grants to authenticated users: all writes
-- go through queue_vehicle_notification() / retry_vehicle_notification() /
-- the service-role-only send worker, matching the existing lock-down
-- pattern (migration 005) for other operational tables.
revoke all on public.vehicle_notifications from public, anon, authenticated;
grant select on public.vehicle_notifications to authenticated;

-- Internal helper: enqueue a notification, idempotent on idempotency_key.
-- Returns the existing row's id (never a duplicate) if the key already
-- exists, otherwise inserts a new pending row and returns its id.
create or replace function public.queue_vehicle_notification(
  p_vehicle_id uuid,
  p_notification_type text,
  p_idempotency_key text,
  p_subject text,
  p_body text,
  p_recipient_email text default null,
  p_recipient_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.vehicle_notifications where idempotency_key = p_idempotency_key;
  if v_id is not null then
    return v_id;
  end if;

  insert into public.vehicle_notifications (
    vehicle_id, notification_type, idempotency_key, recipient_email, recipient_name,
    subject, body, created_by
  ) values (
    p_vehicle_id, p_notification_type, p_idempotency_key, p_recipient_email, p_recipient_name,
    p_subject, p_body, auth.uid()
  )
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then
    -- Lost the race to a concurrent identical enqueue; return the winner's row.
    select id into v_id from public.vehicle_notifications where idempotency_key = p_idempotency_key;
  end if;

  return v_id;
end;
$$;

-- qc_complete_vehicle: atomically marks QC complete on the vehicle AND the
-- named work item (if present), records audit, and enqueues (never sends
-- directly - see section 4 "do not perform unreliable email sending inside
-- the main database transaction") the salesperson "ready for transport"
-- notification exactly once per vehicle via an idempotency key derived
-- from the vehicle id (a second click / retry of this RPC is a no-op on
-- the notification side, matching the outbox uniqueness constraint).
create or replace function public.qc_complete_vehicle(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_work_item_key text default 'QC',
  p_completed_summary text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_salesperson record;
  v_notification_id uuid;
  v_subject text;
  v_body text;
begin
  perform public.require_pdc_role('operator');

  select * into v_before from public.vehicles where id = p_vehicle_id for update;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict');
  end if;
  if v_before.qc_completed_at is not null then
    return jsonb_build_object('ok', false, 'error', 'already_qc_complete', 'vehicle', to_jsonb(v_before));
  end if;

  update public.vehicles
  set qc_completed_at = now(),
      qc_completed_by = auth.uid(),
      version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning * into v_after;

  if p_work_item_key is not null and trim(p_work_item_key) <> '' then
    update public.vehicle_work_items
    set completed = true,
        completed_by = auth.uid(),
        completed_at = now(),
        updated_at = now()
    where vehicle_id = p_vehicle_id
      and work_key = upper(trim(p_work_item_key));
  end if;

  perform public.audit_pdc_event(
    'update', 'vehicles', p_vehicle_id, p_vehicle_id,
    to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'qc_complete_vehicle', 'work_item_key', p_work_item_key)
  );

  select s.id, s.name, s.email into v_salesperson
  from public.salespeople s
  where s.id = v_before.salesperson_id and s.active = true;

  v_subject := 'Vehicle ready for transport - ' || coalesce(v_before.stock_number, v_before.permanent_vehicle_id, p_vehicle_id::text);
  v_body := 'The vehicle is complete and ready for transport.' || chr(10) || chr(10)
    || 'Stock number: ' || coalesce(v_before.stock_number, '(none)') || chr(10)
    || 'Key number: ' || coalesce(v_before.pmb_key_tag, '(none)') || chr(10)
    || 'JC number: ' || coalesce(v_before.job_card_number, '(none)') || chr(10)
    || 'Customer: ' || coalesce(v_before.customer_name, '(none)') || chr(10)
    || 'Vehicle: ' || coalesce(v_before.make, '') || ' ' || coalesce(v_before.model, '') || chr(10)
    || 'Completed work: ' || coalesce(p_completed_summary, '(see vehicle record)') || chr(10)
    || 'Current location: ' || coalesce(v_before.current_location, '(unknown)') || chr(10)
    || 'Completion time: ' || to_char(now(), 'YYYY-MM-DD HH24:MI TZ');

  v_notification_id := public.queue_vehicle_notification(
    p_vehicle_id,
    'qc_complete_ready_for_transport',
    'qc_complete:' || p_vehicle_id::text,
    v_subject,
    v_body,
    v_salesperson.email,
    v_salesperson.name
  );

  return jsonb_build_object(
    'ok', true,
    'vehicle', to_jsonb(v_after),
    'notification_id', v_notification_id,
    'notification_has_recipient', v_salesperson.email is not null
  );
end;
$$;

-- rft_transfer_vehicle: atomic PMB -> RFT transition, requires QC complete.
-- Mirrors the existing transferVehiclesToRft() business rules (statusCategory
-- must be pmb-equivalent i.e. lifecycle_state='active', gate must be clear)
-- but as a protected, versioned, auditable RPC instead of a client-side
-- localStorage write.
create or replace function public.rft_transfer_vehicle(
  p_vehicle_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
begin
  perform public.require_pdc_role('operator');

  select * into v_before from public.vehicles where id = p_vehicle_id for update;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict');
  end if;
  if v_before.qc_completed_at is null then
    return jsonb_build_object('ok', false, 'error', 'qc_not_complete');
  end if;
  if v_before.lifecycle_state <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'not_in_active_lifecycle', 'lifecycle_state', v_before.lifecycle_state);
  end if;

  update public.vehicles
  set lifecycle_state = 'rft',
      current_location = 'RFT',
      rft_transferred_at = coalesce(v_before.rft_transferred_at, now()),
      version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning * into v_after;

  insert into public.vehicle_movements (
    vehicle_id, from_location, to_location, from_pmb_stage, to_pmb_stage,
    from_pmb_bay_stage, to_pmb_bay_stage, from_pmb_bay_number, to_pmb_bay_number,
    reason, moved_by
  ) values (
    p_vehicle_id, v_before.current_location, 'RFT', v_before.pmb_stage, v_before.pmb_stage,
    v_before.pmb_bay_stage, v_before.pmb_bay_stage, v_before.pmb_bay_number, v_before.pmb_bay_number,
    'QC complete - transferred to RFT', auth.uid()
  );

  perform public.audit_pdc_event(
    'rft', 'vehicles', p_vehicle_id, p_vehicle_id,
    to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'rft_transfer_vehicle')
  );

  return jsonb_build_object('ok', true, 'vehicle', to_jsonb(v_after));
end;
$$;

-- rft_collect_vehicle: atomic RFT -> Completed transition. Requires a
-- deliberate confirmation on the frontend (client-side); the RPC itself
-- enforces the state machine (only from 'rft') and is naturally idempotent
-- - calling it twice on an already-completed vehicle simply returns
-- already_collected rather than silently double-processing or erroring
-- confusingly.
create or replace function public.rft_collect_vehicle(
  p_vehicle_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
begin
  perform public.require_pdc_role('operator');

  select * into v_before from public.vehicles where id = p_vehicle_id for update;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if v_before.lifecycle_state = 'completed' then
    return jsonb_build_object('ok', false, 'error', 'already_collected', 'vehicle', to_jsonb(v_before));
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict');
  end if;
  if v_before.lifecycle_state <> 'rft' then
    return jsonb_build_object('ok', false, 'error', 'not_in_rft', 'lifecycle_state', v_before.lifecycle_state);
  end if;

  update public.vehicles
  set lifecycle_state = 'completed',
      current_location = 'Completed',
      rft_collected_at = now(),
      rft_collected_by = auth.uid(),
      visible_on_board = false,
      version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning * into v_after;

  insert into public.vehicle_movements (
    vehicle_id, from_location, to_location, from_pmb_stage, to_pmb_stage,
    from_pmb_bay_stage, to_pmb_bay_stage, from_pmb_bay_number, to_pmb_bay_number,
    reason, moved_by
  ) values (
    p_vehicle_id, v_before.current_location, 'Completed', v_before.pmb_stage, v_before.pmb_stage,
    v_before.pmb_bay_stage, v_before.pmb_bay_stage, v_before.pmb_bay_number, v_before.pmb_bay_number,
    'Collected from RFT', auth.uid()
  );

  perform public.audit_pdc_event(
    'update', 'vehicles', p_vehicle_id, p_vehicle_id,
    to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'rft_collect_vehicle')
  );

  return jsonb_build_object('ok', true, 'vehicle', to_jsonb(v_after));
end;
$$;

-- retry_vehicle_notification: authorised users can retry a failed/pending
-- notification manually (e.g. after correcting a missing salesperson
-- email). Resets attempts count is NOT done here - attempts keeps
-- accumulating for observability; status is reset to 'pending' so the
-- worker will pick it up again. Requires administrator (correcting a
-- notification recipient is a step above ordinary operator actions).
create or replace function public.retry_vehicle_notification(
  p_notification_id uuid,
  p_recipient_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.vehicle_notifications%rowtype;
begin
  perform public.require_pdc_role('administrator');

  select * into v_row from public.vehicle_notifications where id = p_notification_id for update;
  if not found then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;

  update public.vehicle_notifications
  set status = 'pending',
      recipient_email = coalesce(p_recipient_email, recipient_email),
      last_error = null,
      updated_at = now()
  where id = p_notification_id
  returning * into v_row;

  perform public.audit_pdc_event(
    'update', 'vehicle_notifications', p_notification_id, v_row.vehicle_id,
    null, to_jsonb(v_row),
    jsonb_build_object('action', 'retry_vehicle_notification')
  );

  return jsonb_build_object('ok', true, 'notification', to_jsonb(v_row));
end;
$$;

-- send_pending_vehicle_notifications: called by a service-role-authenticated
-- worker process (never the browser) to claim a batch of pending/retryable
-- notifications, mark them 'sent' or 'failed' after the caller has actually
-- attempted delivery (see AI_INTAKE / notification worker script), and
-- return the claimed rows so the caller knows what to send. This function
-- only CLAIMS rows (sets status can be set back by mark_vehicle_notification_result);
-- it does not itself talk to an email provider (kept out of SQL by design).
create or replace function public.claim_pending_vehicle_notifications(p_limit integer default 20)
returns setof public.vehicle_notifications
language sql
security definer
set search_path = public
as $$
  select *
  from public.vehicle_notifications
  where status in ('pending', 'failed')
    and attempts < max_attempts
  order by created_at asc
  limit greatest(p_limit, 1);
$$;

create or replace function public.mark_vehicle_notification_result(
  p_notification_id uuid,
  p_success boolean,
  p_error text default null
)
returns public.vehicle_notifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.vehicle_notifications%rowtype;
begin
  update public.vehicle_notifications
  set attempts = attempts + 1,
      last_attempted_at = now(),
      status = case
        when p_success then 'sent'::public.notification_status
        when attempts + 1 >= max_attempts then 'failed'::public.notification_status
        else 'pending'::public.notification_status
      end,
      sent_at = case when p_success then now() else sent_at end,
      last_error = case when p_success then null else p_error end,
      updated_at = now()
  where id = p_notification_id
  returning * into v_row;

  if not found then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;

  return v_row;
end;
$$;

-- Lock down direct table writes, matching migration 005's pattern: only the
-- RPCs above may mutate vehicles/vehicle_notifications/vehicle_movements
-- for these new flows. Grants to `authenticated` are for the callable RPCs
-- only.
revoke all on function public.qc_complete_vehicle(uuid, integer, text, text) from public, anon;
grant execute on function public.qc_complete_vehicle(uuid, integer, text, text) to authenticated;

revoke all on function public.rft_transfer_vehicle(uuid, integer) from public, anon;
grant execute on function public.rft_transfer_vehicle(uuid, integer) to authenticated;

revoke all on function public.rft_collect_vehicle(uuid, integer) from public, anon;
grant execute on function public.rft_collect_vehicle(uuid, integer) to authenticated;

revoke all on function public.retry_vehicle_notification(uuid, text) from public, anon;
grant execute on function public.retry_vehicle_notification(uuid, text) to authenticated;

revoke all on function public.claim_pending_vehicle_notifications(integer) from public, anon, authenticated;
revoke all on function public.mark_vehicle_notification_result(uuid, boolean, text) from public, anon, authenticated;
-- Intentionally NOT granted to `authenticated`: these two are for the
-- service-role-authenticated notification worker only (never the browser).

revoke all on function public.queue_vehicle_notification(uuid, text, text, text, text, text, text) from public, anon, authenticated;

commit;
