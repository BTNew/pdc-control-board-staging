-- Staging-only migration 086.
-- Exact Sublet provider normalisation, durable source evidence, import preview
-- enforcement, canonical multi-provider assignments, and safe bay creation.
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

create or replace function public.sublet_provider_match_key(p_value text)
returns text
language sql
immutable
parallel safe
as $$
  select upper(btrim(regexp_replace(
    regexp_replace(translate(coalesce(p_value,''),'‐‑‒–—―','------'),'\s*-\s*',' - ','g'),
    '\s+',' ','g'
  )));
$$;

create table if not exists public.sublet_provider_aliases (
  source_key text primary key,
  source_display text not null,
  provider_id uuid not null references public.sublet_providers(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint sublet_provider_aliases_key_canonical check(source_key=public.sublet_provider_match_key(source_display))
);

alter table public.sublet_provider_aliases enable row level security;
revoke all on table public.sublet_provider_aliases from public,anon,authenticated;

-- Canonicalise case for approved names already present, then seed missing names.
do $seed$
declare
  v_names text[]:=array[
    '4x4 Mechanic - Ascot','ARB','ARB - Welshpool','Armadale','Ashley Group','Autonomo',
    'AV Auto Elec','Beam Rustproofing','Bull Motor Bodies','Customer Sublet',
    'Electrical - High Wycombe','Great Racks - Bibra Lake','Harness Master','HDD Solutions',
    'Hidrive','Hidrive - Canning Vale','Hunter Mech','Ironman - Canning Vale','Jaram',
    'Jason Signs','Lovells','Malaga Springs and Suspensions','MMT','MRT - Bibra Lake',
    'Norweld','Pedders - Cannington','Pedders - Cockburn','Pedders - Malaga',
    'Perth Ceramic Coating','PK Technology','PTE','Roscoes','Swank','SWAT',
    'TC Boxes - Bayswater','TechFire','TL Engineering','TWD 4x4',
    'Tyrepower - Osborne Park','Tyrepower - West Perth','Ultimate 4x4',
    'Unicorn Transport Equipment','Westrac'
  ];
  v_name text;
  v_order integer;
begin
  select coalesce(max(sort_order),0) into v_order from public.sublet_providers;
  foreach v_name in array v_names loop
    update public.sublet_providers
    set name=v_name,active=true,version=version+1,updated_at=clock_timestamp()
    where lower(name)=lower(v_name) and name is distinct from v_name;
    if not exists(select 1 from public.sublet_providers where lower(name)=lower(v_name)) then
      v_order:=v_order+1;
      insert into public.sublet_providers(name,active,sort_order)
      values(v_name,true,v_order);
    end if;
  end loop;
end;
$seed$;

-- Approved names map to themselves; explicit source aliases map exactly as supplied.
with approved(name) as (values
  ('4x4 Mechanic - Ascot'),('ARB'),('ARB - Welshpool'),('Armadale'),('Ashley Group'),('Autonomo'),
  ('AV Auto Elec'),('Beam Rustproofing'),('Bull Motor Bodies'),('Customer Sublet'),
  ('Electrical - High Wycombe'),('Great Racks - Bibra Lake'),('Harness Master'),('HDD Solutions'),
  ('Hidrive'),('Hidrive - Canning Vale'),('Hunter Mech'),('Ironman - Canning Vale'),('Jaram'),
  ('Jason Signs'),('Lovells'),('Malaga Springs and Suspensions'),('MMT'),('MRT - Bibra Lake'),
  ('Norweld'),('Pedders - Cannington'),('Pedders - Cockburn'),('Pedders - Malaga'),
  ('Perth Ceramic Coating'),('PK Technology'),('PTE'),('Roscoes'),('Swank'),('SWAT'),
  ('TC Boxes - Bayswater'),('TechFire'),('TL Engineering'),('TWD 4x4'),
  ('Tyrepower - Osborne Park'),('Tyrepower - West Perth'),('Ultimate 4x4'),
  ('Unicorn Transport Equipment'),('Westrac')
), aliases(source_display,canonical_name) as (values
  ('ROSCOS','Roscoes'),('Roscoes','Roscoes'),
  ('HarnessMaster','Harness Master'),('Harness Master','Harness Master'),
  ('BEAM','Beam Rustproofing'),('BEAM RUSTPROOFING','Beam Rustproofing'),
  ('Hi-Drive','Hidrive'),('HIDRIVE','Hidrive'),
  ('HIDRIVE CANNING VALE','Hidrive - Canning Vale'),('HIDRIVE - CANNING VALE','Hidrive - Canning Vale'),
  ('PEDDERS CANNINGTON','Pedders - Cannington'),('PEDDERS - CANNINGTON','Pedders - Cannington'),
  ('PEDDERS MALAGA','Pedders - Malaga'),('PEDDERS - MALAGA','Pedders - Malaga'),
  ('PEDDERS - COCKBURN','Pedders - Cockburn'),
  ('TYREPOWER WEST PERTH','Tyrepower - West Perth'),('TYREPOWER - WEST PERTH','Tyrepower - West Perth'),
  ('TYREPOWE OSBORNE PARK','Tyrepower - Osborne Park'),('TYREPOWER OSBORNE PARK','Tyrepower - Osborne Park'),
  ('TYREPOWER - OSBORNE PARK','Tyrepower - Osborne Park'),
  ('MALAGA SPRINGS','Malaga Springs and Suspensions'),('Malaga Springs','Malaga Springs and Suspensions'),
  ('MALAGA SPRINGS AND SUSPENSIONS','Malaga Springs and Suspensions'),
  ('Great Racks','Great Racks - Bibra Lake'),('GREAT RACKS - BIBRA LAKE','Great Racks - Bibra Lake'),
  ('TC Boxes','TC Boxes - Bayswater'),('TC BOXES BAYSWATER','TC Boxes - Bayswater'),
  ('ARB WELSHPOOL','ARB - Welshpool'),('ARB - WELSHPOOL','ARB - Welshpool'),
  ('MRT PERTH','MRT - Bibra Lake'),('MRT - BIBRA LAKE','MRT - Bibra Lake'),
  ('CustomerSublet','Customer Sublet'),('IRONMAN CANNING VALE','Ironman - Canning Vale'),
  ('4X4 MECHANIC - ASCOT','4x4 Mechanic - Ascot'),
  ('ELECTRICAL - 53 FORTRON BLVD HIGH WYCOME','Electrical - High Wycombe'),
  ('JARAM','Jaram'),('ASHLEY GROUP','Ashley Group'),('LOVELLS','Lovells'),('NORWELD','Norweld'),
  ('Westrac','Westrac'),('PTE','PTE'),('MMT','MMT'),('SWANK','Swank')
), all_aliases_raw as (
  select name source_display,name canonical_name from approved
  union all select source_display,canonical_name from aliases
), all_aliases as (
  select min(source_display) source_display,min(canonical_name) canonical_name
  from all_aliases_raw
  group by public.sublet_provider_match_key(source_display)
)
insert into public.sublet_provider_aliases(source_key,source_display,provider_id)
select public.sublet_provider_match_key(a.source_display),a.source_display,p.id
from all_aliases a
join public.sublet_providers p on lower(p.name)=lower(a.canonical_name)
on conflict(source_key) do update set
  source_display=excluded.source_display,provider_id=excluded.provider_id;

-- Known spelling-only provider rows are retained as history but removed from active choices.
update public.sublet_providers p set active=false,version=version+1,updated_at=clock_timestamp()
where active and exists(
  select 1 from public.sublet_provider_aliases a
  join public.sublet_providers canonical on canonical.id=a.provider_id
  where a.source_key=public.sublet_provider_match_key(p.name)
    and canonical.id<>p.id
);

create table if not exists public.vehicle_sublet_providers (
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  provider_id uuid not null references public.sublet_providers(id) on delete restrict,
  canonical_name text not null,
  source_values text[] not null default '{}'::text[],
  source_backend_record_id uuid references public.navision_backend_records(id) on delete set null,
  source_system text not null default 'microsoft_navision',
  imported_at timestamptz not null default clock_timestamp(),
  primary key(vehicle_id,provider_id)
);

alter table public.vehicle_sublet_providers enable row level security;
revoke all on table public.vehicle_sublet_providers from public,anon,authenticated;

alter table public.pdc_sublet_bookings
  add column if not exists provider_source text not null default 'manual',
  add column if not exists provider_names text[] not null default '{}'::text[],
  add column if not exists provider_source_values text[] not null default '{}'::text[];

create or replace function public.mark_manual_sublet_provider_authority()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if new.field_name='provider' then
    update public.pdc_sublet_bookings
    set provider_source='manual',
        provider_names=case when nullif(btrim(new.new_value),'') is null then '{}'::text[] else array[btrim(new.new_value)] end
    where vehicle_id=new.vehicle_id;
  end if;
  return new;
end;
$$;
revoke all on function public.mark_manual_sublet_provider_authority() from public,anon,authenticated;
drop trigger if exists zz_manual_sublet_provider_authority on public.pdc_sublet_booking_history;
create trigger zz_manual_sublet_provider_authority
after insert on public.pdc_sublet_booking_history
for each row execute function public.mark_manual_sublet_provider_authority();

create or replace function public.sublet_provider_import_preview(p_rows jsonb)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,public
as $$
with input_rows as (
  select ordinality::integer row_index,value row_value,
    coalesce(nullif(btrim(value->>'batch'),''),nullif(btrim(value->>'stock'),''),nullif(btrim(value->>'id'),'')) vehicle_ref
  from jsonb_array_elements(case when jsonb_typeof(p_rows)='array' then p_rows else '[]'::jsonb end) with ordinality
), source_values as (
  select r.row_index,r.vehicle_ref,btrim(v.value) original_value,
    public.sublet_provider_match_key(v.value) source_key
  from input_rows r
  cross join lateral jsonb_array_elements_text(
    case
      when jsonb_typeof(r.row_value->'subletProviderSourceValues')='array' then r.row_value->'subletProviderSourceValues'
      when nullif(btrim(r.row_value->>'subletProviderSourceValue'),'') is not null then jsonb_build_array(r.row_value->>'subletProviderSourceValue')
      else '[]'::jsonb
    end
  ) v(value)
  where nullif(btrim(v.value),'') is not null
), mapped as (
  select s.*,case when p.active then a.provider_id end provider_id,
    case when p.active then p.name end normalized_provider
  from source_values s
  left join public.sublet_provider_aliases a on a.source_key=s.source_key
  left join public.sublet_providers p on p.id=a.provider_id
), provider_counts as (
  select normalized_provider,count(*)::integer provider_count
  from mapped where provider_id is not null group by normalized_provider
), multi as (
  select vehicle_ref,array_agg(distinct normalized_provider order by normalized_provider) providers
  from mapped where provider_id is not null group by vehicle_ref
  having count(distinct provider_id)>1
)
select jsonb_build_object(
  'rows',coalesce((select jsonb_agg(jsonb_build_object(
    'row_index',row_index,'vehicle',vehicle_ref,'original_provider_value',original_value,
    'normalised_provider',normalized_provider,'mapped',provider_id is not null
  ) order by row_index,original_value) from mapped),'[]'::jsonb),
  'counts_by_normalised_provider',coalesce((select jsonb_agg(jsonb_build_object(
    'provider',normalized_provider,'count',provider_count
  ) order by normalized_provider) from provider_counts),'[]'::jsonb),
  'unmapped_provider_values',coalesce((select jsonb_agg(value order by value) from (
    select distinct original_value value from mapped where provider_id is null
  ) u),'[]'::jsonb),
  'vehicles_with_multiple_providers',coalesce((select jsonb_agg(jsonb_build_object(
    'vehicle',vehicle_ref,'providers',providers
  ) order by vehicle_ref) from multi),'[]'::jsonb),
  'spelling_variations_create_duplicate_records',false,
  'unknown_count',(select count(*)::integer from mapped where provider_id is null)
);
$$;
revoke all on function public.sublet_provider_import_preview(jsonb) from public,anon,authenticated;

-- Add provider preview to the existing dealer-scoped preview and make unknowns blocking.
do $rename_preview$
begin
  if to_regprocedure('public.preview_navision_backend_import_pre086(jsonb,text,text,text,timestamptz)') is null then
    alter function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)
      rename to preview_navision_backend_import_pre086;
  end if;
end;
$rename_preview$;
revoke all on function public.preview_navision_backend_import_pre086(jsonb,text,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.preview_navision_backend_import_pre076(jsonb,text,text,text,timestamptz) from public,anon,authenticated;

create or replace function public.preview_navision_backend_import(
  p_rows jsonb,p_source_system text,p_dealer_code text,p_source_name text,
  p_source_timestamp timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,extensions
as $$
declare
  v_result jsonb;
  v_data jsonb;
  v_provider jsonb;
  v_scope jsonb;
  v_rows jsonb;
  v_safety jsonb;
begin
  v_scope:=public.navision_scope_rows_for_selected_dealer(p_rows,p_source_system,p_dealer_code);
  v_rows:=case when coalesce((v_scope->>'applied')::boolean,false) then v_scope->'rows' else p_rows end;
  v_result:=public.preview_navision_backend_import_pre086(
    p_rows,p_source_system,p_dealer_code,p_source_name,p_source_timestamp
  );
  if not coalesce((v_result->>'ok')::boolean,false) then return v_result; end if;
  v_provider:=public.sublet_provider_import_preview(v_rows);
  v_data:=coalesce(v_result->'data','{}'::jsonb)||jsonb_build_object('sublet_provider_preview',v_provider);
  if coalesce((v_provider->>'unknown_count')::integer,0)>0 then
    v_safety:=coalesce(v_data->'safety','{}'::jsonb);
    if not coalesce((v_safety->>'blocking')::boolean,false) then
      v_safety:=v_safety||jsonb_build_object('blocking',true,'reason','sublet_provider_review_required');
    end if;
    v_data:=v_data||jsonb_build_object('blocking',true,'sublet_provider_blocking',true,'safety',v_safety);
  end if;
  return jsonb_set(v_result,'{data}',v_data,true);
end;
$$;
revoke all on function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz) from public,anon;
grant execute on function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz) to authenticated;

do $rename_apply$
begin
  if to_regprocedure('public.apply_navision_backend_import_pre086(text,jsonb,text,text,text,timestamptz,text,text,bigint)') is null then
    alter function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
      rename to apply_navision_backend_import_pre086;
  end if;
end;
$rename_apply$;
revoke all on function public.apply_navision_backend_import_pre086(text,jsonb,text,text,text,timestamptz,text,text,bigint) from public,anon,authenticated;
revoke all on function public.apply_navision_backend_import_pre076(text,jsonb,text,text,text,timestamptz,text,text,bigint) from public,anon,authenticated;

create or replace function public.apply_navision_backend_import(
  p_idempotency_key text,p_rows jsonb,p_source_system text,p_dealer_code text,
  p_source_name text,p_source_timestamp timestamptz,p_source_hash text,
  p_preview_hash text,p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $$
declare
  v_scope jsonb;
  v_rows jsonb;
  v_provider jsonb;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then
    return public.apply_navision_backend_import_pre086(
      p_idempotency_key,p_rows,p_source_system,p_dealer_code,p_source_name,
      p_source_timestamp,p_source_hash,p_preview_hash,p_expected_revision
    );
  end if;
  if jsonb_array_length(p_rows)>5000 then
    return public.apply_navision_backend_import_pre086(
      p_idempotency_key,p_rows,p_source_system,p_dealer_code,p_source_name,
      p_source_timestamp,p_source_hash,p_preview_hash,p_expected_revision
    );
  end if;
  v_scope:=public.navision_scope_rows_for_selected_dealer(p_rows,p_source_system,p_dealer_code);
  v_rows:=case when coalesce((v_scope->>'applied')::boolean,false) then v_scope->'rows' else p_rows end;
  v_provider:=public.sublet_provider_import_preview(v_rows);
  if coalesce((v_provider->>'unknown_count')::integer,0)>0 then
    return public.navision_backend_response(false,'sublet_provider_review_required',jsonb_build_object(
      'sublet_provider_preview',v_provider,'blocking',true
    ));
  end if;
  return public.apply_navision_backend_import_pre086(
    p_idempotency_key,p_rows,p_source_system,p_dealer_code,p_source_name,
    p_source_timestamp,p_source_hash,p_preview_hash,p_expected_revision
  );
end;
$$;
revoke all on function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) from public,anon;
grant execute on function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) to authenticated;

create or replace function public.sync_navision_sublet_providers(p_backend_record_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_record public.navision_backend_records%rowtype;
  v_vehicle_id uuid;
  v_actor uuid:=auth.uid();
  v_source_count integer;
  v_unknown integer;
  v_names text[];
  v_sources text[];
  v_first text;
  v_source_json jsonb;
begin
  select * into v_record from public.navision_backend_records where id=p_backend_record_id;
  if not found or not v_record.is_current or v_record.record_status<>'current' then
    return public.navision_backend_response(true,'ignored');
  end if;
  v_source_json:=case
    when jsonb_typeof(v_record.normalized_data->'subletProviderSourceValues')='array' then v_record.normalized_data->'subletProviderSourceValues'
    when nullif(btrim(v_record.normalized_data->>'subletProviderSourceValue'),'') is not null then jsonb_build_array(v_record.normalized_data->>'subletProviderSourceValue')
    else '[]'::jsonb
  end;
  if jsonb_array_length(v_source_json)=0 then
    return public.navision_backend_response(true,'blank_ignored');
  end if;

  select count(*)::integer into v_source_count
  from jsonb_array_elements_text(v_source_json) v(value)
  where nullif(btrim(v.value),'') is not null;
  if v_source_count=0 then return public.navision_backend_response(true,'blank_ignored'); end if;

  select count(*)::integer into v_unknown
  from jsonb_array_elements_text(v_source_json) v(value)
  left join public.sublet_provider_aliases a on a.source_key=public.sublet_provider_match_key(v.value)
  where nullif(btrim(v.value),'') is not null and a.provider_id is null;
  if v_unknown>0 then return public.navision_backend_response(false,'sublet_provider_review_required'); end if;

  v_vehicle_id:=v_record.canonical_vehicle_id;
  if v_vehicle_id is null then
    select a.canonical_vehicle_id into v_vehicle_id from public.navision_board_activations a
    where a.backend_record_id=v_record.id;
  end if;
  if v_vehicle_id is null or not exists(
    select 1 from public.vehicles where id=v_vehicle_id and deleted_at is null and lifecycle_state='active'
  ) then return public.navision_backend_response(true,'vehicle_not_active'); end if;

  delete from public.vehicle_sublet_providers existing
  where existing.vehicle_id=v_vehicle_id
    and existing.source_backend_record_id=v_record.id
    and not exists(
      select 1
      from jsonb_array_elements_text(v_source_json) current_value(value)
      join public.sublet_provider_aliases current_alias
        on current_alias.source_key=public.sublet_provider_match_key(current_value.value)
      where current_alias.provider_id=existing.provider_id
    );

  with mapped as (
    select a.provider_id,p.name,btrim(v.value) source_value
    from jsonb_array_elements_text(v_source_json) v(value)
    join public.sublet_provider_aliases a on a.source_key=public.sublet_provider_match_key(v.value)
    join public.sublet_providers p on p.id=a.provider_id and p.active
    where nullif(btrim(v.value),'') is not null
  ), grouped as (
    select provider_id,name,array_agg(distinct source_value order by source_value) source_values
    from mapped group by provider_id,name
  )
  insert into public.vehicle_sublet_providers(
    vehicle_id,provider_id,canonical_name,source_values,source_backend_record_id,source_system,imported_at
  )
  select v_vehicle_id,provider_id,name,source_values,v_record.id,v_record.source_system,clock_timestamp()
  from grouped
  on conflict(vehicle_id,provider_id) do update set
    canonical_name=excluded.canonical_name,
    source_values=(select array_agg(distinct x order by x) from unnest(
      public.vehicle_sublet_providers.source_values||excluded.source_values
    ) x),
    source_backend_record_id=excluded.source_backend_record_id,
    source_system=excluded.source_system,
    imported_at=excluded.imported_at;

  select array_agg(canonical_name order by canonical_name),
         array_agg(distinct s order by s)
  into v_names,v_sources
  from public.vehicle_sublet_providers p
  cross join lateral unnest(p.source_values) s
  where p.vehicle_id=v_vehicle_id;
  -- array_agg above repeats names for every source; reduce names separately.
  select array_agg(canonical_name order by canonical_name) into v_names
  from (select distinct canonical_name from public.vehicle_sublet_providers where vehicle_id=v_vehicle_id) n;
  v_first:=coalesce(v_names[1],'');

  insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
  values(v_vehicle_id,'sublet',true,false,'Sublet provider evidence imported from Navision')
  on conflict(vehicle_id,work_key) do update set
    required=true,updated_at=clock_timestamp()
  where not public.vehicle_work_items.completed;

  if v_actor is not null then
    insert into public.pdc_sublet_bookings(
      vehicle_id,provider,provider_names,provider_source_values,provider_source,updated_by
    ) values(v_vehicle_id,v_first,v_names,coalesce(v_sources,'{}'::text[]),'navision_import',v_actor)
    on conflict(vehicle_id) do update set
      provider=case when public.pdc_sublet_bookings.provider_source='navision_import'
        or public.pdc_sublet_bookings.provider='' then excluded.provider else public.pdc_sublet_bookings.provider end,
      provider_names=case when public.pdc_sublet_bookings.provider_source='navision_import'
        or public.pdc_sublet_bookings.provider='' then excluded.provider_names else public.pdc_sublet_bookings.provider_names end,
      provider_source_values=excluded.provider_source_values,
      provider_source=case when public.pdc_sublet_bookings.provider_source='navision_import'
        or public.pdc_sublet_bookings.provider='' then 'navision_import' else public.pdc_sublet_bookings.provider_source end,
      version=public.pdc_sublet_bookings.version+1,
      updated_at=clock_timestamp(),updated_by=excluded.updated_by;
  end if;

  insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,after_data,metadata)
  values('update','vehicle_sublet_providers',v_vehicle_id,v_vehicle_id,v_actor,public.current_actor_email(),
    jsonb_build_object('provider_names',v_names,'source_values',v_sources),
    jsonb_build_object('source','navision_sublet_normalisation_086','backend_record_id',v_record.id,
      'duplicate_provider_records_created',false,'planner_created',false));

  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
  return public.navision_backend_response(true,'sublet_providers_synced',jsonb_build_object(
    'vehicle_id',v_vehicle_id,'provider_names',v_names,'source_values',v_sources
  ));
end;
$$;
revoke all on function public.sync_navision_sublet_providers(uuid) from public,anon,authenticated;

create or replace function public.trigger_sync_navision_sublet_providers()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if pg_trigger_depth()>1 then return new; end if;
  perform public.sync_navision_sublet_providers(case when tg_table_name='navision_board_activations'
    then (to_jsonb(new)->>'backend_record_id')::uuid else (to_jsonb(new)->>'id')::uuid end);
  return new;
end;
$$;
revoke all on function public.trigger_sync_navision_sublet_providers() from public,anon,authenticated;

drop trigger if exists zz_navision_record_sublet_sync on public.navision_backend_records;
create trigger zz_navision_record_sublet_sync
after insert or update of normalized_data,is_current,record_status on public.navision_backend_records
for each row execute function public.trigger_sync_navision_sublet_providers();

drop trigger if exists zz_navision_activation_sublet_sync on public.navision_board_activations;
create trigger zz_navision_activation_sublet_sync
after insert or update of active,activated_stock_number,canonical_vehicle_id on public.navision_board_activations
for each row execute function public.trigger_sync_navision_sublet_providers();

-- Enrich the existing restricted snapshot without exposing raw provider evidence broadly.
do $rename_snapshot$
begin
  if to_regprocedure('public.get_pdc_email_vehicle_location_snapshot_pre086()') is null then
    alter function public.get_pdc_email_vehicle_location_snapshot()
      rename to get_pdc_email_vehicle_location_snapshot_pre086;
  end if;
end;
$rename_snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot_pre086() from public,anon,authenticated;

create or replace function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare
  v_result jsonb;
  v_rows jsonb;
begin
  v_result:=public.get_pdc_email_vehicle_location_snapshot_pre086();
  if not coalesce((v_result->>'ok')::boolean,false) then return v_result; end if;
  select coalesce(jsonb_agg(
    r.value||jsonb_build_object('sublet_booking',coalesce(r.value->'sublet_booking','{}'::jsonb)||jsonb_build_object(
      'provider_names',coalesce(to_jsonb(s.provider_names),'[]'::jsonb),
      'provider_source',coalesce(s.provider_source,'')
    )) order by r.ordinality
  ),'[]'::jsonb) into v_rows
  from jsonb_array_elements(coalesce(v_result#>'{data,vehicles}','[]'::jsonb)) with ordinality r(value,ordinality)
  left join public.pdc_sublet_bookings s on s.vehicle_id=(r.value->>'id')::uuid;
  return jsonb_set(v_result,'{data,vehicles}',v_rows,true);
end;
$$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public,anon;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;

-- Safe administrator-only bay creation; Sublet and other planner-disabled stages fail closed.
create or replace function public.add_workshop_bay(p_stage_code text,p_display_name text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_stage public.workshop_stages%rowtype;
  v_name text:=btrim(coalesce(p_display_name,''));
  v_number integer;
  v_bay public.workshop_bays%rowtype;
begin
  perform public.require_pdc_role('administrator');
  select * into v_stage from public.workshop_stages
  where code=upper(btrim(coalesce(p_stage_code,''))) and active and is_physical and not is_sublet
  for update;
  if not found then return jsonb_build_object('ok',false,'error','stage_not_planner_enabled'); end if;
  if v_name='' or length(v_name)>120 then return jsonb_build_object('ok',false,'error','invalid_name'); end if;
  perform pg_advisory_xact_lock(hashtextextended('add-workshop-bay:'||v_stage.id::text,0));
  if exists(select 1 from public.workshop_bays where stage_id=v_stage.id and lower(display_name)=lower(v_name)) then
    return jsonb_build_object('ok',false,'error','duplicate_name');
  end if;
  select coalesce(max(bay_number),0)+1 into v_number from public.workshop_bays where stage_id=v_stage.id;
  insert into public.workshop_bays(
    stage_id,bay_number,code,display_name,is_active,is_sublet_row,created_by,updated_by
  ) values(
    v_stage.id,v_number,v_stage.code||'-'||v_number,v_name,true,false,auth.uid(),auth.uid()
  ) returning * into v_bay;
  perform public.audit_pdc_event('reference_change','workshop_bays',v_bay.id,null,null,to_jsonb(v_bay),
    jsonb_build_object('action','add_workshop_bay','stage_code',v_stage.code));
  return jsonb_build_object('ok',true,'bay',to_jsonb(v_bay));
end;
$$;
revoke all on function public.add_workshop_bay(text,text) from public,anon;
grant execute on function public.add_workshop_bay(text,text) to authenticated;

-- Removing means deactivating. Refuse while any queued/planned/started/stoppage booking uses the bay.
create or replace function public.set_workshop_bay_active(
  p_bay_id uuid,p_expected_version integer,p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_before public.workshop_bays%rowtype;
  v_after public.workshop_bays%rowtype;
begin
  perform public.require_pdc_role('administrator');
  select * into v_before from public.workshop_bays where id=p_bay_id for update;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  if v_before.version<>p_expected_version then
    return jsonb_build_object('ok',false,'error','version_conflict','current',to_jsonb(v_before));
  end if;
  if not p_active and exists(
    select 1 from public.workshop_bookings
    where bay_id=p_bay_id and deleted_at is null and status in ('queued','planned','started','stoppage')
  ) then return jsonb_build_object('ok',false,'error','bay_in_use'); end if;
  if v_before.is_active=p_active then return jsonb_build_object('ok',true,'bay',to_jsonb(v_before),'unchanged',true); end if;
  update public.workshop_bays set is_active=p_active,version=version+1,
    updated_by=auth.uid(),updated_at=clock_timestamp()
  where id=p_bay_id returning * into v_after;
  perform public.audit_pdc_event('reference_change','workshop_bays',v_after.id,null,to_jsonb(v_before),to_jsonb(v_after),
    jsonb_build_object('action',case when p_active then 'activate_workshop_bay' else 'deactivate_workshop_bay' end));
  return jsonb_build_object('ok',true,'bay',to_jsonb(v_after));
end;
$$;
revoke all on function public.set_workshop_bay_active(uuid,integer,boolean) from public,anon;
grant execute on function public.set_workshop_bay_active(uuid,integer,boolean) to authenticated;

commit;
