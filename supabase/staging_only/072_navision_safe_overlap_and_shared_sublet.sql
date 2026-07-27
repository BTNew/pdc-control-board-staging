-- Staging-only migration 072.
-- 1. Permit a strongly dealer-matched Navision refresh to place omitted rows in
--    temporary holding instead of falsely blocking the whole import.
-- 2. Make Sublet booking data server-authoritative for canonical email vehicles.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
end;
$guard$;

-- Keep the prior assessment intact and wrap only its large, strongly matched
-- dealer-scope false positive. Missing records still enter reversible holding;
-- cross-dealer, wrong-filename, empty, small and weakly matched files still block.
alter function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb)
  rename to navision_import_safety_assessment_pre072;

create function public.navision_import_safety_assessment(
  p_rows jsonb,
  p_source_system text,
  p_dealer_code text,
  p_source_name text,
  p_preview_data jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,extensions
as $safety$
declare
  v_result jsonb;
  v_reason text;
  v_current integer;
  v_incoming integer;
  v_missing integer;
  v_cross integer;
  v_selected integer;
begin
  v_result:=public.navision_import_safety_assessment_pre072(
    p_rows,p_source_system,p_dealer_code,p_source_name,p_preview_data
  );
  v_reason:=coalesce(v_result->>'reason','');
  v_current:=coalesce((v_result->>'current_count')::integer,0);
  v_incoming:=coalesce((v_result->>'incoming_valid_count')::integer,0);
  v_missing:=coalesce((v_result->>'missing_count')::integer,0);
  v_cross:=coalesce((v_result->>'cross_dealer_matches')::integer,0);
  v_selected:=coalesce((v_result->>'selected_identity_matches')::integer,0);

  if v_reason='suspicious_partial_snapshot'
     and v_current>=100
     and v_incoming>=100
     and v_missing>0
     and v_cross=0
     and v_selected*100>=v_incoming*95 then
    v_result:=jsonb_set(v_result,'{blocking}','false'::jsonb,true);
    v_result:=jsonb_set(v_result,'{reason}','null'::jsonb,true);
    v_result:=jsonb_set(v_result,'{authority}',to_jsonb('navision_import_fail_safe_v2'::text),true);
    v_result:=jsonb_set(v_result,'{bounded_overlap_release}',jsonb_build_object(
      'released',true,
      'minimum_incoming',100,
      'minimum_selected_match_percent',95,
      'missing_destination','temporary_holding',
      'hard_delete',false
    ),true);
  end if;
  return v_result;
end;
$safety$;
revoke all on function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb)
  from public,anon,authenticated;

create table public.pdc_sublet_bookings (
  vehicle_id uuid primary key references public.vehicles(id) on delete cascade,
  provider text not null default '' check(length(provider)<=120),
  provider_email text not null default '' check(length(provider_email)<=254),
  po_sent_date date,
  booking_date date,
  expected_return_date date,
  actual_return_date date,
  notes text not null default '' check(length(notes)<=2000),
  email_sent boolean not null default false,
  version bigint not null default 1 check(version>=1),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid not null references auth.users(id) on delete restrict
);

create table public.pdc_sublet_booking_history (
  history_id bigserial primary key,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null,
  field_name text not null,
  old_value text not null default '',
  new_value text not null default '',
  booking_version bigint not null,
  event_at timestamptz not null default clock_timestamp()
);

alter table public.pdc_sublet_bookings enable row level security;
alter table public.pdc_sublet_booking_history enable row level security;
revoke all on table public.pdc_sublet_bookings from public,anon,authenticated;
revoke all on table public.pdc_sublet_booking_history from public,anon,authenticated;
revoke all on sequence public.pdc_sublet_booking_history_history_id_seq from public,anon,authenticated;

create or replace function public.update_pdc_sublet_booking_field(
  p_vehicle_id uuid,
  p_expected_version bigint,
  p_field text,
  p_value text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $update$
declare
  v_user uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text:=public.current_pdc_user_role()::text;
  v_field text:=lower(btrim(coalesce(p_field,'')));
  v_value text:=btrim(coalesce(p_value,''));
  v_date date;
  v_bool boolean;
  v_before public.pdc_sublet_bookings%rowtype;
  v_after public.pdc_sublet_bookings%rowtype;
  v_old text:='';
  v_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_user is null or v_email='' or v_role not in ('operator','importer','administrator') then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if p_vehicle_id is null or v_field not in (
    'provider','provider_email','po_sent_date','booking_date',
    'expected_return_date','actual_return_date','notes','email_sent'
  ) then
    return public.navision_backend_response(false,'invalid_input');
  end if;
  if (v_field='provider' and length(v_value)>120)
     or (v_field='provider_email' and length(v_value)>254)
     or (v_field='notes' and length(v_value)>2000) then
    return public.navision_backend_response(false,'invalid_input');
  end if;
  if v_field in ('po_sent_date','booking_date','expected_return_date','actual_return_date')
     and v_value<>'' then
    begin
      v_date:=v_value::date;
      if to_char(v_date,'YYYY-MM-DD')<>v_value then
        return public.navision_backend_response(false,'invalid_date');
      end if;
    exception when others then
      return public.navision_backend_response(false,'invalid_date');
    end;
  end if;
  if v_field='email_sent' then
    if lower(v_value) not in ('true','false') then
      return public.navision_backend_response(false,'invalid_boolean');
    end if;
    v_bool:=lower(v_value)='true';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-booking:'||p_vehicle_id::text,0));
  if not exists(
    select 1 from public.vehicles v
    where v.id=p_vehicle_id and v.deleted_at is null and v.lifecycle_state='active'
      and exists(
        select 1 from public.vehicle_work_items wi
        where wi.vehicle_id=v.id and lower(wi.work_key)='sublet'
          and wi.required and not wi.completed
      )
  ) then
    return public.navision_backend_response(false,'sublet_not_required');
  end if;

  select * into v_before from public.pdc_sublet_bookings where vehicle_id=p_vehicle_id for update;
  if not found then
    if coalesce(p_expected_version,0)<>0 then
      return public.navision_backend_response(false,'version_conflict');
    end if;
    insert into public.pdc_sublet_bookings(vehicle_id,updated_by)
    values(p_vehicle_id,v_user) returning * into v_before;
  elsif coalesce(p_expected_version,0)<>v_before.version then
    return public.navision_backend_response(false,'version_conflict',jsonb_build_object('current_version',v_before.version));
  end if;

  v_old:=case v_field
    when 'provider' then v_before.provider
    when 'provider_email' then v_before.provider_email
    when 'po_sent_date' then coalesce(v_before.po_sent_date::text,'')
    when 'booking_date' then coalesce(v_before.booking_date::text,'')
    when 'expected_return_date' then coalesce(v_before.expected_return_date::text,'')
    when 'actual_return_date' then coalesce(v_before.actual_return_date::text,'')
    when 'notes' then v_before.notes
    when 'email_sent' then v_before.email_sent::text
  end;

  update public.pdc_sublet_bookings set
    provider=case when v_field='provider' then v_value else provider end,
    provider_email=case when v_field='provider_email' then v_value else provider_email end,
    po_sent_date=case when v_field='po_sent_date' then v_date else po_sent_date end,
    booking_date=case when v_field='booking_date' then v_date else booking_date end,
    expected_return_date=case when v_field='expected_return_date' then v_date else expected_return_date end,
    actual_return_date=case when v_field='actual_return_date' then v_date else actual_return_date end,
    notes=case when v_field='notes' then v_value else notes end,
    email_sent=case when v_field='email_sent' then v_bool else email_sent end,
    version=version+1,updated_at=clock_timestamp(),updated_by=v_user
  where vehicle_id=p_vehicle_id returning * into v_after;

  insert into public.pdc_sublet_booking_history(
    vehicle_id,actor_id,actor_email,field_name,old_value,new_value,booking_version
  ) values(p_vehicle_id,v_user,v_email,v_field,v_old,v_value,v_after.version);
  update public.pdc_email_vehicle_revision
  set revision=revision+1,updated_at=clock_timestamp()
  where singleton returning revision into v_revision;
  return public.navision_backend_response(true,'updated',jsonb_build_object(
    'vehicle_id',p_vehicle_id,'version',v_after.version,'revision',v_revision
  ));
end;
$update$;
revoke all on function public.update_pdc_sublet_booking_field(uuid,bigint,text,text)
  from public,anon,authenticated;
grant execute on function public.update_pdc_sublet_booking_field(uuid,bigint,text,text)
  to authenticated;

create or replace function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $snapshot$
declare
  v_role text;
  v_revision bigint;
  v_rows jsonb;
begin
  v_role:=public.current_pdc_user_role()::text;
  if v_role not in ('viewer','operator','importer','administrator') then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select revision into v_revision from public.pdc_email_vehicle_revision where singleton;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,
    'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,
    'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,
    'salesperson_reference',v.salesperson_reference,'registration',v.registration,
    'eta_to_kewdale',v.eta_to_kewdale,'current_location',v.current_location,
    'visible_on_board',v.visible_on_board,'source_system',v.source_system,
    'source_record_id',v.source_record_id,'updated_at',v.updated_at,
    'work_items',coalesce((select jsonb_agg(jsonb_build_object(
      'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,
      'completed_at',wi.completed_at,'completed_by',wi.completed_by
    ) order by wi.work_key) from public.vehicle_work_items wi where wi.vehicle_id=v.id),'[]'::jsonb),
    'parts_required',coalesce((select pu.parts_required from public.vehicle_parts_updates pu
      where pu.vehicle_id=v.id order by pu.updated_at desc,pu.id desc limit 1),false),
    'parts_completed',coalesce((select wi.completed from public.vehicle_work_items wi
      where wi.vehicle_id=v.id and wi.work_key='PARTS'),false),
    'sublet_booking',coalesce((select jsonb_build_object(
      'provider',s.provider,'provider_email',s.provider_email,
      'po_sent_date',s.po_sent_date,'booking_date',s.booking_date,
      'expected_return_date',s.expected_return_date,'actual_return_date',s.actual_return_date,
      'notes',s.notes,'email_sent',s.email_sent,'version',s.version,'updated_at',s.updated_at
    ) from public.pdc_sublet_bookings s where s.vehicle_id=v.id),'{}'::jsonb)
  ) order by coalesce(v.stock_number,v.vin,v.permanent_vehicle_id),v.id),'[]'::jsonb)
  into v_rows
  from public.vehicles v
  where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    and exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v.id);
  return public.navision_backend_response(true,'ok',jsonb_build_object(
    'revision',coalesce(v_revision,1),'vehicles',v_rows
  ));
end;
$snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot()
  from public,anon,authenticated;
grant execute on function public.get_pdc_email_vehicle_location_snapshot()
  to authenticated;

commit;
