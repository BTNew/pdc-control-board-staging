-- Branch-local staging migration 168 (renumber at integration).
-- Canonical multi-provider Sublet bookings, immutable evidence/history and a
-- fail-closed provider-attested email update contract. No mailbox adapter.
begin;
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-168',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='167' and name='live_vehicle_alias_identity_ownership')
     or exists(select 1 from supabase_migrations.schema_migrations where version>'167')
     or exists(select 1 from supabase_migrations.schema_migrations where version='168')
     or to_regclass('public.pdc_sublet_bookings') is null
     or to_regclass('public.sublet_providers') is null then
    raise exception 'PDC_SUBLET_168_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;
end;
$guard$;

create table public.pdc_sublet_booking_instances (
  booking_id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  vehicle_version bigint not null check(vehicle_version>=1),
  provider_id uuid not null references public.sublet_providers(id) on delete restrict,
  provider_name text not null check(length(btrim(provider_name)) between 1 and 120),
  provider_email text not null default '' check(length(provider_email)<=254),
  out_date date not null,
  expected_return_date date,
  status text not null default 'active' check(status in ('active','returned','cancelled')),
  returned_at timestamptz,
  returned_by uuid references auth.users(id) on delete restrict,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete restrict,
  notes text not null default '' check(length(notes)<=2000),
  source_kind text not null default 'manual' check(source_kind in ('manual','legacy_backfill','navision_import','provider_email')),
  source_ref text not null default '' check(length(source_ref)<=500),
  source_evidence jsonb not null default '{}'::jsonb,
  version bigint not null default 1 check(version>=1),
  created_at timestamptz not null default clock_timestamp(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid not null references auth.users(id) on delete restrict,
  check(expected_return_date is null or expected_return_date>=out_date),
  check((status='returned')=(returned_at is not null)),
  check((status='returned')=(returned_by is not null)),
  check((status='cancelled')=(cancelled_at is not null)),
  check((status='cancelled')=(cancelled_by is not null))
);
create index pdc_sublet_booking_instances_vehicle_idx on public.pdc_sublet_booking_instances(vehicle_id,status,out_date);
create index pdc_sublet_booking_instances_provider_idx on public.pdc_sublet_booking_instances(provider_id,status,out_date);

create table public.pdc_sublet_booking_instance_history (
  history_id bigserial primary key,
  booking_id uuid not null references public.pdc_sublet_booking_instances(booking_id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete restrict,
  actor_email text not null,
  action text not null check(action in ('backfilled','created','updated','returned','cancelled','email_updated')),
  before_data jsonb,
  after_data jsonb not null,
  booking_version bigint not null,
  evidence jsonb not null default '{}'::jsonb,
  event_at timestamptz not null default clock_timestamp()
);

create table public.pdc_sublet_email_update_receipts (
  receipt_id uuid primary key default gen_random_uuid(),
  replay_key text not null unique check(length(replay_key) between 16 and 200),
  booking_id uuid not null references public.pdc_sublet_booking_instances(booking_id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  provider_id uuid not null references public.sublet_providers(id) on delete restrict,
  provider_name text not null,
  sender_email text not null,
  message_id text not null check(length(message_id) between 1 and 500),
  attachment_sha256 text check(attachment_sha256 is null or attachment_sha256 ~ '^[0-9a-f]{64}$'),
  evidence jsonb not null,
  language_kind text not null check(language_kind in ('booking_confirmed','eta_confirmed')),
  prior_version bigint not null,
  resulting_version bigint not null,
  applied_out_date date,
  applied_expected_return_date date,
  received_at timestamptz not null,
  applied_at timestamptz not null default clock_timestamp(),
  applied_by uuid references auth.users(id) on delete restrict
);

alter table public.pdc_sublet_booking_instances enable row level security;
alter table public.pdc_sublet_booking_instance_history enable row level security;
alter table public.pdc_sublet_email_update_receipts enable row level security;
revoke all on table public.pdc_sublet_booking_instances,public.pdc_sublet_booking_instance_history,public.pdc_sublet_email_update_receipts from public,anon,authenticated;
revoke all on sequence public.pdc_sublet_booking_instance_history_history_id_seq from public,anon,authenticated;

-- Immutable audit/evidence ledgers. Even table owners must explicitly disable the
-- trigger during a reviewed restore; application roles can only reach RPCs.
create function public.pdc_reject_sublet_immutable_mutation() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
begin raise exception 'PDC_SUBLET_IMMUTABLE_LEDGER' using errcode='55000'; end $$;
revoke all on function public.pdc_reject_sublet_immutable_mutation() from public,anon,authenticated,service_role;
create trigger pdc_sublet_history_immutable before update or delete on public.pdc_sublet_booking_instance_history for each row execute function public.pdc_reject_sublet_immutable_mutation();
create trigger pdc_sublet_email_receipts_immutable before update or delete on public.pdc_sublet_email_update_receipts for each row execute function public.pdc_reject_sublet_immutable_mutation();

-- Backfill every singular row. Provider resolution is exact through canonical
-- name/alias evidence; unresolved/ambiguous rows abort the migration rather than
-- disappearing or being guessed. Empty legacy placeholders without dates are
-- retained by the explicit legacy bridge below, but are not fabricated as trips.
do $backfill$
declare v_bad bigint; v_actor uuid;
begin
  select count(*) into v_bad from public.pdc_sublet_bookings s
  where s.booking_date is not null and (
    nullif(btrim(s.provider),'') is null or
    (select count(*) from public.sublet_providers p left join public.sublet_provider_aliases a on a.provider_id=p.id
      where p.active and (lower(p.name)=lower(btrim(s.provider)) or a.source_key=public.sublet_provider_match_key(s.provider)))<>1
  );
  if v_bad<>0 then raise exception 'PDC_SUBLET_168_BACKFILL_AMBIGUOUS_ROWS:%',v_bad using errcode='55000'; end if;
  select id into v_actor from auth.users order by created_at,id limit 1;
  if exists(select 1 from public.pdc_sublet_bookings where booking_date is not null) and v_actor is null then
    raise exception 'PDC_SUBLET_168_BACKFILL_ACTOR_MISSING' using errcode='55000';
  end if;
  with resolved as (
    select s.*, (select p.id from public.sublet_providers p left join public.sublet_provider_aliases a on a.provider_id=p.id
      where p.active and (lower(p.name)=lower(btrim(s.provider)) or a.source_key=public.sublet_provider_match_key(s.provider)) limit 1) provider_id,
      v.version vehicle_version
    from public.pdc_sublet_bookings s join public.vehicles v on v.id=s.vehicle_id where s.booking_date is not null
  ), inserted as (
    insert into public.pdc_sublet_booking_instances(vehicle_id,vehicle_version,provider_id,provider_name,provider_email,out_date,expected_return_date,status,returned_at,returned_by,notes,source_kind,source_ref,source_evidence,version,created_at,created_by,updated_at,updated_by)
    select r.vehicle_id,r.vehicle_version,r.provider_id,(select name from public.sublet_providers where id=r.provider_id),r.provider_email,r.booking_date,r.expected_return_date,
      case when r.actual_return_date is null then 'active' else 'returned' end,
      case when r.actual_return_date is null then null else r.actual_return_date::timestamp at time zone 'Australia/Perth' end,
      case when r.actual_return_date is null then null else coalesce(r.updated_by,v_actor) end,r.notes,'legacy_backfill','pdc_sublet_bookings:'||r.vehicle_id::text,
      jsonb_build_object('legacy_version',r.version,'po_sent_date',r.po_sent_date,'email_sent',r.email_sent,'provider_source',r.provider_source),r.version,r.updated_at,coalesce(r.updated_by,v_actor),r.updated_at,coalesce(r.updated_by,v_actor)
    from resolved r returning *
  )
  insert into public.pdc_sublet_booking_instance_history(booking_id,vehicle_id,actor_id,actor_email,action,after_data,booking_version,evidence,event_at)
  select i.booking_id,i.vehicle_id,i.created_by,coalesce((select lower(email) from auth.users where id=i.created_by),'migration'),
    'backfilled',to_jsonb(i),i.version,jsonb_build_object('source','singular_compatibility_backfill'),i.created_at from inserted i;
end;
$backfill$;

-- Same vehicle cannot be physically away on two overlapping bookings. Adjacent
-- intervals are valid: a returned_at business date is available to the next trip.
create function public.pdc_sublet_instance_overlap_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_end date;
begin
  if new.status='cancelled' then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-instance:'||new.vehicle_id::text,0));
  v_end:=case when new.status='returned' then (new.returned_at at time zone 'Australia/Perth')::date else new.expected_return_date+1 end;
  if exists(select 1 from public.pdc_sublet_booking_instances x where x.vehicle_id=new.vehicle_id and x.booking_id<>new.booking_id and x.status<>'cancelled'
    and daterange(x.out_date,case when x.status='returned' then (x.returned_at at time zone 'Australia/Perth')::date else x.expected_return_date+1 end,'[)')
      && daterange(new.out_date,v_end,'[)')) then
    raise exception '%',jsonb_build_object('error','sublet_booking_overlap','vehicle_id',new.vehicle_id,'booking_id',new.booking_id)::text using errcode='23P01';
  end if;
  return new;
end $$;
revoke all on function public.pdc_sublet_instance_overlap_guard() from public,anon,authenticated,service_role;
create trigger pdc_sublet_instance_overlap_guard before insert or update of vehicle_id,out_date,expected_return_date,status,returned_at on public.pdc_sublet_booking_instances for each row execute function public.pdc_sublet_instance_overlap_guard();

create function public.pdc_sublet_actor_allowed() returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
  select auth.uid() is not null and public.current_pdc_user_role()::text in ('operator','importer','administrator')
$$;
revoke all on function public.pdc_sublet_actor_allowed() from public,anon,authenticated,service_role;

create function public.create_pdc_sublet_booking(p_vehicle_id uuid,p_vehicle_version bigint,p_provider_id uuid,p_out_date date,p_expected_return_date date,p_provider_email text default '',p_notes text default '') returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_user uuid:=auth.uid(); v_vehicle public.vehicles%rowtype; v_provider public.sublet_providers%rowtype; v_row public.pdc_sublet_booking_instances%rowtype; v_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
  if not public.pdc_sublet_actor_allowed() then return public.navision_backend_response(false,'unauthorized'); end if;
  if p_vehicle_id is null or p_provider_id is null or p_out_date is null or p_expected_return_date is null or p_expected_return_date<p_out_date or length(btrim(coalesce(p_provider_email,'')))>254 or length(btrim(coalesce(p_notes,'')))>2000 then return public.navision_backend_response(false,'invalid_input'); end if;
  select * into v_vehicle from public.vehicles where id=p_vehicle_id and deleted_at is null and lifecycle_state='active' for update;
  if not found then return public.navision_backend_response(false,'vehicle_not_found'); end if;
  if v_vehicle.version<>p_vehicle_version then return public.navision_backend_response(false,'vehicle_version_conflict',jsonb_build_object('current_version',v_vehicle.version)); end if;
  select * into v_provider from public.sublet_providers where id=p_provider_id and active;
  if not found then return public.navision_backend_response(false,'provider_not_found'); end if;
  insert into public.pdc_sublet_booking_instances(vehicle_id,vehicle_version,provider_id,provider_name,provider_email,out_date,expected_return_date,notes,created_by,updated_by)
    values(v_vehicle.id,v_vehicle.version,v_provider.id,v_provider.name,lower(btrim(coalesce(p_provider_email,''))),p_out_date,p_expected_return_date,btrim(coalesce(p_notes,'')),v_user,v_user) returning * into v_row;
  insert into public.pdc_sublet_booking_instance_history(booking_id,vehicle_id,actor_id,actor_email,action,after_data,booking_version) values(v_row.booking_id,v_row.vehicle_id,v_user,public.current_actor_email(),'created',to_jsonb(v_row),v_row.version);
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton returning revision into v_revision;
  return public.navision_backend_response(true,'created',jsonb_build_object('booking',to_jsonb(v_row),'revision',v_revision));
exception when exclusion_violation then return public.navision_backend_response(false,'sublet_booking_overlap');
end $$;
revoke all on function public.create_pdc_sublet_booking(uuid,bigint,uuid,date,date,text,text) from public,anon,authenticated;
grant execute on function public.create_pdc_sublet_booking(uuid,bigint,uuid,date,date,text,text) to authenticated;

create function public.update_pdc_sublet_booking(p_booking_id uuid,p_expected_version bigint,p_out_date date,p_expected_return_date date,p_notes text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_user uuid:=auth.uid(); v_before public.pdc_sublet_booking_instances%rowtype; v_after public.pdc_sublet_booking_instances%rowtype; v_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
  if not public.pdc_sublet_actor_allowed() then return public.navision_backend_response(false,'unauthorized'); end if;
  select * into v_before from public.pdc_sublet_booking_instances where booking_id=p_booking_id for update;
  if not found then return public.navision_backend_response(false,'booking_not_found'); end if;
  if v_before.version<>coalesce(p_expected_version,0) then return public.navision_backend_response(false,'version_conflict',jsonb_build_object('current_version',v_before.version)); end if;
  if v_before.status<>'active' then return public.navision_backend_response(false,'booking_not_active'); end if;
  if p_out_date is null or p_expected_return_date is null or p_expected_return_date<p_out_date or (p_notes is not null and length(btrim(p_notes))>2000) then return public.navision_backend_response(false,'invalid_input'); end if;
  update public.pdc_sublet_booking_instances set out_date=p_out_date,expected_return_date=p_expected_return_date,notes=coalesce(btrim(p_notes),notes),version=version+1,updated_at=clock_timestamp(),updated_by=v_user where booking_id=p_booking_id returning * into v_after;
  insert into public.pdc_sublet_booking_instance_history(booking_id,vehicle_id,actor_id,actor_email,action,before_data,after_data,booking_version) values(v_after.booking_id,v_after.vehicle_id,v_user,public.current_actor_email(),'updated',to_jsonb(v_before),to_jsonb(v_after),v_after.version);
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton returning revision into v_revision;
  return public.navision_backend_response(true,'updated',jsonb_build_object('booking',to_jsonb(v_after),'revision',v_revision));
exception when exclusion_violation then return public.navision_backend_response(false,'sublet_booking_overlap');
end $$;
revoke all on function public.update_pdc_sublet_booking(uuid,bigint,date,date,text) from public,anon,authenticated;
grant execute on function public.update_pdc_sublet_booking(uuid,bigint,date,date,text) to authenticated;

create function public.return_pdc_sublet_booking(p_booking_id uuid,p_expected_version bigint,p_returned_at timestamptz default clock_timestamp()) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_user uuid:=auth.uid(); v_before public.pdc_sublet_booking_instances%rowtype; v_after public.pdc_sublet_booking_instances%rowtype; v_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
  if not public.pdc_sublet_actor_allowed() then return public.navision_backend_response(false,'unauthorized'); end if;
  select * into v_before from public.pdc_sublet_booking_instances where booking_id=p_booking_id for update;
  if not found then return public.navision_backend_response(false,'booking_not_found'); end if;
  if v_before.version<>coalesce(p_expected_version,0) then return public.navision_backend_response(false,'version_conflict',jsonb_build_object('current_version',v_before.version)); end if;
  if v_before.status='returned' then return public.navision_backend_response(true,'already_returned',jsonb_build_object('booking',to_jsonb(v_before))); end if;
  if v_before.status<>'active' or (p_returned_at at time zone 'Australia/Perth')::date<v_before.out_date then return public.navision_backend_response(false,'invalid_return'); end if;
  update public.pdc_sublet_booking_instances set status='returned',returned_at=p_returned_at,returned_by=v_user,version=version+1,updated_at=clock_timestamp(),updated_by=v_user where booking_id=p_booking_id returning * into v_after;
  insert into public.pdc_sublet_booking_instance_history(booking_id,vehicle_id,actor_id,actor_email,action,before_data,after_data,booking_version) values(v_after.booking_id,v_after.vehicle_id,v_user,public.current_actor_email(),'returned',to_jsonb(v_before),to_jsonb(v_after),v_after.version);
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton returning revision into v_revision;
  return public.navision_backend_response(true,'returned',jsonb_build_object('booking',to_jsonb(v_after),'revision',v_revision));
end $$;
revoke all on function public.return_pdc_sublet_booking(uuid,bigint,timestamptz) from public,anon,authenticated;
grant execute on function public.return_pdc_sublet_booking(uuid,bigint,timestamptz) to authenticated;

-- Exact provider-attested email contract. The caller supplies already-reviewed
-- definitive language; this function does not parse mail and cannot guess a row.
create function public.apply_pdc_sublet_email_update(p_replay_key text,p_vehicle_id uuid,p_provider_name text,p_sender_email text,p_language_kind text,p_out_date date,p_expected_return_date date,p_message_id text,p_attachment_sha256 text,p_received_at timestamptz,p_evidence jsonb,p_expected_version bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_user uuid:=auth.uid(); v_provider_id uuid; v_provider_count int; v_match_count int; v_before public.pdc_sublet_booking_instances%rowtype; v_after public.pdc_sublet_booking_instances%rowtype; v_receipt public.pdc_sublet_email_update_receipts%rowtype; v_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
  if not public.pdc_sublet_actor_allowed() then return public.navision_backend_response(false,'unauthorized'); end if;
  if nullif(btrim(coalesce(p_replay_key,'')),'') is null or length(p_replay_key)<16 or p_vehicle_id is null or lower(btrim(coalesce(p_sender_email,'')))!~'^[^@[:space:]]+@[^@[:space:]]+$' or p_language_kind not in ('booking_confirmed','eta_confirmed') or nullif(btrim(coalesce(p_message_id,'')),'') is null or p_received_at is null or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object' or (p_attachment_sha256 is not null and lower(p_attachment_sha256)!~'^[0-9a-f]{64}$') then return public.navision_backend_response(false,'invalid_evidence'); end if;
  select * into v_receipt from public.pdc_sublet_email_update_receipts where replay_key=p_replay_key;
  if found then return public.navision_backend_response(true,'replayed',jsonb_build_object('receipt_id',v_receipt.receipt_id,'booking_id',v_receipt.booking_id,'version',v_receipt.resulting_version)); end if;
  select count(distinct p.id),(array_agg(distinct p.id))[1] into v_provider_count,v_provider_id from public.sublet_providers p left join public.sublet_provider_aliases a on a.provider_id=p.id where p.active and (lower(p.name)=lower(btrim(p_provider_name)) or a.source_key=public.sublet_provider_match_key(p_provider_name));
  if v_provider_count<>1 then return public.navision_backend_response(false,case when v_provider_count=0 then 'provider_not_found' else 'provider_ambiguous' end); end if;
  select count(*),(array_agg(booking_id))[1] into v_match_count,v_before.booking_id from public.pdc_sublet_booking_instances where vehicle_id=p_vehicle_id and provider_id=v_provider_id and status='active' and lower(provider_email)=lower(btrim(p_sender_email));
  if v_match_count<>1 then return public.navision_backend_response(false,case when v_match_count=0 then 'booking_not_found' else 'booking_ambiguous' end); end if;
  select * into v_before from public.pdc_sublet_booking_instances where booking_id=v_before.booking_id for update;
  if v_before.version<>coalesce(p_expected_version,0) then return public.navision_backend_response(false,'version_conflict',jsonb_build_object('current_version',v_before.version)); end if;
  if (p_language_kind='booking_confirmed' and p_out_date is null) or (p_language_kind='eta_confirmed' and p_expected_return_date is null) then return public.navision_backend_response(false,'definitive_value_missing'); end if;
  if coalesce(p_out_date,v_before.out_date)>coalesce(p_expected_return_date,v_before.expected_return_date) then return public.navision_backend_response(false,'invalid_date_order'); end if;
  update public.pdc_sublet_booking_instances set out_date=coalesce(p_out_date,out_date),expected_return_date=coalesce(p_expected_return_date,expected_return_date),source_kind='provider_email',source_ref=p_message_id,source_evidence=p_evidence||jsonb_build_object('message_id',p_message_id,'attachment_sha256',p_attachment_sha256,'sender_email',lower(btrim(p_sender_email))),version=version+1,updated_at=clock_timestamp(),updated_by=v_user where booking_id=v_before.booking_id returning * into v_after;
  insert into public.pdc_sublet_email_update_receipts(replay_key,booking_id,vehicle_id,provider_id,provider_name,sender_email,message_id,attachment_sha256,evidence,language_kind,prior_version,resulting_version,applied_out_date,applied_expected_return_date,received_at,applied_by) values(p_replay_key,v_after.booking_id,v_after.vehicle_id,v_after.provider_id,v_after.provider_name,lower(btrim(p_sender_email)),p_message_id,lower(p_attachment_sha256),p_evidence,p_language_kind,v_before.version,v_after.version,p_out_date,p_expected_return_date,p_received_at,v_user) returning * into v_receipt;
  insert into public.pdc_sublet_booking_instance_history(booking_id,vehicle_id,actor_id,actor_email,action,before_data,after_data,booking_version,evidence) values(v_after.booking_id,v_after.vehicle_id,v_user,public.current_actor_email(),'email_updated',to_jsonb(v_before),to_jsonb(v_after),v_after.version,jsonb_build_object('receipt_id',v_receipt.receipt_id,'message_id',p_message_id,'attachment_sha256',p_attachment_sha256));
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton returning revision into v_revision;
  return public.navision_backend_response(true,'email_updated',jsonb_build_object('receipt_id',v_receipt.receipt_id,'booking_id',v_after.booking_id,'version',v_after.version,'revision',v_revision));
exception when unique_violation then
  select * into v_receipt from public.pdc_sublet_email_update_receipts where replay_key=p_replay_key;
  return public.navision_backend_response(true,'replayed',jsonb_build_object('receipt_id',v_receipt.receipt_id,'booking_id',v_receipt.booking_id,'version',v_receipt.resulting_version));
when exclusion_violation then return public.navision_backend_response(false,'sublet_booking_overlap');
end $$;
revoke all on function public.apply_pdc_sublet_email_update(text,uuid,text,text,text,date,date,text,text,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function public.apply_pdc_sublet_email_update(text,uuid,text,text,text,date,date,text,text,timestamptz,jsonb,bigint) to authenticated;

-- Explicit read bridge: consumers get all canonical rows plus singular placeholders
-- that had no trip date. The original table remains intact and is not silently
-- rewritten or dropped; its writer is narrowed below for compatibility.
create view public.pdc_sublet_bookings_compatibility_bridge with (security_invoker=true) as
select i.vehicle_id,i.booking_id,i.provider_name provider,i.provider_email,i.out_date booking_date,i.expected_return_date,(i.returned_at at time zone 'Australia/Perth')::date actual_return_date,i.notes,i.status,i.version,i.updated_at
from public.pdc_sublet_booking_instances i
union all
select s.vehicle_id,null::uuid,s.provider,s.provider_email,s.booking_date,s.expected_return_date,s.actual_return_date,s.notes,case when s.actual_return_date is not null then 'returned' when s.booking_date is not null then 'active' else 'cancelled' end,s.version,s.updated_at
from public.pdc_sublet_bookings s where s.booking_date is null;
revoke all on public.pdc_sublet_bookings_compatibility_bridge from public,anon,authenticated;

-- Multi-row snapshot overlay. Preserve the old singular object as a deliberate
-- legacy read bridge while exposing the canonical array and active count.
do $snapshot$
begin
  if to_regprocedure('public.get_pdc_email_vehicle_location_snapshot_pre168()') is null then alter function public.get_pdc_email_vehicle_location_snapshot() rename to get_pdc_email_vehicle_location_snapshot_pre168; end if;
end;$snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot_pre168() from public,anon,authenticated;
create function public.get_pdc_email_vehicle_location_snapshot() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_rows jsonb;
begin
  v_result:=public.get_pdc_email_vehicle_location_snapshot_pre168();
  if not coalesce((v_result->>'ok')::boolean,false) then return v_result; end if;
  select coalesce(jsonb_agg(r.value||jsonb_build_object(
    'sublet_bookings',coalesce((select jsonb_agg(jsonb_build_object('booking_id',b.booking_id,'vehicle_id',b.vehicle_id,'vehicle_version',b.vehicle_version,'provider_id',b.provider_id,'provider_name',b.provider_name,'provider_email',b.provider_email,'out_date',b.out_date,'expected_return_date',b.expected_return_date,'status',b.status,'returned_at',b.returned_at,'returned_by',b.returned_by,'version',b.version,'notes',b.notes,'updated_at',b.updated_at) order by b.out_date,b.created_at,b.booking_id) from public.pdc_sublet_booking_instances b where b.vehicle_id=(r.value->>'id')::uuid),'[]'::jsonb),
    'sublet_active_count',(select count(*) from public.pdc_sublet_booking_instances b where b.vehicle_id=(r.value->>'id')::uuid and b.status='active')
  ) order by r.ordinality),'[]'::jsonb) into v_rows from jsonb_array_elements(coalesce(v_result#>'{data,vehicles}','[]'::jsonb)) with ordinality r(value,ordinality);
  return jsonb_set(v_result,'{data,vehicles}',v_rows,true);
end $$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public,anon;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;

-- Legacy mutation remains callable only when exactly one canonical active booking
-- matches the vehicle; zero/multiple rows fail closed instead of selecting one.
create or replace function public.update_pdc_sublet_booking_field(p_vehicle_id uuid,p_expected_version bigint,p_field text,p_value text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_count int; v_booking public.pdc_sublet_booking_instances%rowtype; v_date date;
begin
  if not public.pdc_sublet_actor_allowed() then return public.navision_backend_response(false,'unauthorized'); end if;
  select count(*),(array_agg(booking_id))[1] into v_count,v_booking.booking_id from public.pdc_sublet_booking_instances where vehicle_id=p_vehicle_id and status='active';
  if v_count<>1 then return public.navision_backend_response(false,case when v_count=0 then 'legacy_booking_not_found' else 'legacy_booking_ambiguous' end); end if;
  select * into v_booking from public.pdc_sublet_booking_instances where booking_id=v_booking.booking_id;
  if lower(btrim(p_field)) not in ('booking_date','expected_return_date') then return public.navision_backend_response(false,'legacy_field_unsupported'); end if;
  begin v_date:=p_value::date; exception when others then return public.navision_backend_response(false,'invalid_date'); end;
  return public.update_pdc_sublet_booking(v_booking.booking_id,p_expected_version,case when lower(btrim(p_field))='booking_date' then v_date else v_booking.out_date end,case when lower(btrim(p_field))='expected_return_date' then v_date else v_booking.expected_return_date end,null);
end $$;
revoke all on function public.update_pdc_sublet_booking_field(uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.update_pdc_sublet_booking_field(uuid,bigint,text,text) to authenticated;

do $postcondition$
begin
  if (select count(*) from public.pdc_sublet_booking_instances where source_kind='legacy_backfill')<>(select count(*) from public.pdc_sublet_bookings where booking_date is not null) then raise exception 'PDC_SUBLET_168_BACKFILL_COUNT_MISMATCH'; end if;
  if exists(select 1 from public.pdc_sublet_booking_instances a join public.pdc_sublet_booking_instances b on a.vehicle_id=b.vehicle_id and a.booking_id<b.booking_id and a.status<>'cancelled' and b.status<>'cancelled' where daterange(a.out_date,case when a.status='returned' then (a.returned_at at time zone 'Australia/Perth')::date else a.expected_return_date+1 end,'[)') && daterange(b.out_date,case when b.status='returned' then (b.returned_at at time zone 'Australia/Perth')::date else b.expected_return_date+1 end,'[)')) then raise exception 'PDC_SUBLET_168_EXISTING_OVERLAP'; end if;
end;$postcondition$;
insert into supabase_migrations.schema_migrations(version,name,statements) values('168','multi_provider_sublet_bookings_and_email_contract',array['branch-local; renumber at integration; staging-only guarded SQL']);
commit;
