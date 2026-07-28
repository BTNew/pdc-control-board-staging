-- Staging-only shared salesperson roster and exact email default resolution.
-- Source: user-supplied dealer salesperson list (2026-07-28).
-- FO is an explicit alias of SP because both supplied rows use Stephen Peck's
-- same email address and the shared directory enforces unique emails.

begin;

do $block$
declare
  v_conflict text;
begin
  with roster(code,name,email,sort_order) as (values
    ('JB','Jason Battle','jason.battle@pmgwa.com.au',10),
    ('KB','Kevin Bonser','kevin.bonser@pmgwa.com.au',20),
    ('CF','Clint Franklin','clint.franklin@pmgwa.com.au',30),
    ('BH','Brooke Hornby','brooke.hornby@pmgwa.com.au',40),
    ('SL','Scott Lovett','scott.lovett@pmgwa.com.au',50),
    ('SP','Stephen Peck','stephen.peck@pmgwa.com.au',60),
    ('PS','Paul Symmons','paul.symmons@broometoyota.com.au',70),
    ('DW','David Watson','dave@pmgwa.com.au',80),
    ('AW','Andy Weir','andy.weir@broometoyota.com.au',90),
    ('BG','Bryce Guthrie','bryce.guthrie@broometoyota.com.au',100),
    ('PM','Peter Morris','peter.morris@broometoyota.com.au',110),
    ('CW','Craig Watson','craig.watson@broometoyota.com.au',120)
  ), ambiguous as (
    select r.code
    from roster r
    join public.salespeople s on upper(coalesce(s.code,''))=r.code
      or lower(coalesce(s.email,''))=lower(r.email)
      or lower(s.name)=lower(r.name)
    group by r.code
    having count(distinct s.id)>1
  )
  select code into v_conflict from ambiguous limit 1;

  if v_conflict is not null then
    raise exception 'Salesperson roster conflict for code %; no roster changes applied',v_conflict using errcode='23505';
  end if;

  with roster(code,name,email,sort_order) as (values
    ('JB','Jason Battle','jason.battle@pmgwa.com.au',10),('KB','Kevin Bonser','kevin.bonser@pmgwa.com.au',20),
    ('CF','Clint Franklin','clint.franklin@pmgwa.com.au',30),('BH','Brooke Hornby','brooke.hornby@pmgwa.com.au',40),
    ('SL','Scott Lovett','scott.lovett@pmgwa.com.au',50),('SP','Stephen Peck','stephen.peck@pmgwa.com.au',60),
    ('PS','Paul Symmons','paul.symmons@broometoyota.com.au',70),('DW','David Watson','dave@pmgwa.com.au',80),
    ('AW','Andy Weir','andy.weir@broometoyota.com.au',90),('BG','Bryce Guthrie','bryce.guthrie@broometoyota.com.au',100),
    ('PM','Peter Morris','peter.morris@broometoyota.com.au',110),('CW','Craig Watson','craig.watson@broometoyota.com.au',120)
  ), matches as (
    select r.*,(
      select s.id from public.salespeople s
      where upper(coalesce(s.code,''))=r.code
        or lower(coalesce(s.email,''))=lower(r.email)
        or lower(s.name)=lower(r.name)
      limit 1
    ) id from roster r
  )
  update public.salespeople s
  set code=m.code,name=m.name,email=lower(m.email),sort_order=m.sort_order,active=true,
      version=s.version+1,updated_at=now()
  from matches m where m.id=s.id
    and (s.code is distinct from m.code or s.name is distinct from m.name
      or lower(coalesce(s.email,'')) is distinct from lower(m.email)
      or s.sort_order is distinct from m.sort_order or s.active is distinct from true);

  insert into public.salespeople(name,code,email,sort_order,active)
  select r.name,r.code,lower(r.email),r.sort_order,true
  from (values
    ('JB','Jason Battle','jason.battle@pmgwa.com.au',10),('KB','Kevin Bonser','kevin.bonser@pmgwa.com.au',20),
    ('CF','Clint Franklin','clint.franklin@pmgwa.com.au',30),('BH','Brooke Hornby','brooke.hornby@pmgwa.com.au',40),
    ('SL','Scott Lovett','scott.lovett@pmgwa.com.au',50),('SP','Stephen Peck','stephen.peck@pmgwa.com.au',60),
    ('PS','Paul Symmons','paul.symmons@broometoyota.com.au',70),('DW','David Watson','dave@pmgwa.com.au',80),
    ('AW','Andy Weir','andy.weir@broometoyota.com.au',90),('BG','Bryce Guthrie','bryce.guthrie@broometoyota.com.au',100),
    ('PM','Peter Morris','peter.morris@broometoyota.com.au',110),('CW','Craig Watson','craig.watson@broometoyota.com.au',120)
  ) as r(code,name,email,sort_order)
  where not exists (
    select 1 from public.salespeople s
    where upper(coalesce(s.code,''))=r.code
      or lower(coalesce(s.email,''))=lower(r.email)
      or lower(s.name)=lower(r.name));
end $block$;

create or replace function public.pdc_salesperson_id_for_reference(p_reference text)
returns uuid
language plpgsql
stable security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  v_reference text:=btrim(coalesce(p_reference,''));
  v_code text;
  v_id uuid;
begin
  if v_reference='' then return null; end if;
  v_code:=upper(v_reference);
  if v_code~'^\([A-Z0-9]{1,6}\)' then v_code:=substring(v_code from '^\(([A-Z0-9]{1,6})\)');
  elsif v_code~'^[A-Z0-9]{1,6}([[:space:]]|$)' then v_code:=substring(v_code from '^([A-Z0-9]{1,6})');
  end if;
  if v_code='FO' then v_code:='SP'; end if;

  select s.id into v_id from public.salespeople s
  where s.active and upper(coalesce(s.code,''))=v_code;
  if v_id is not null then return v_id; end if;

  select s.id into v_id from public.salespeople s
  where s.active and (lower(s.name)=lower(v_reference) or lower(coalesce(s.email,''))=lower(v_reference));
  return v_id;
end $function$;

revoke all on function public.pdc_salesperson_id_for_reference(text) from public,anon,authenticated;
grant execute on function public.pdc_salesperson_id_for_reference(text) to service_role;

create or replace function public.pdc_default_vehicle_salesperson()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare v_resolved uuid;
begin
  if tg_op='INSERT' then
    if new.salesperson_id is null then
      new.salesperson_id:=public.pdc_salesperson_id_for_reference(new.salesperson_reference);
    end if;
    return new;
  end if;

  if new.salesperson_reference is distinct from old.salesperson_reference
     and new.salesperson_id is not distinct from old.salesperson_id then
    v_resolved:=public.pdc_salesperson_id_for_reference(new.salesperson_reference);
    new.salesperson_id:=v_resolved;
  elsif new.salesperson_id is null then
    new.salesperson_id:=public.pdc_salesperson_id_for_reference(new.salesperson_reference);
  end if;
  return new;
end $function$;

drop trigger if exists pdc_default_vehicle_salesperson_trigger on public.vehicles;
create trigger pdc_default_vehicle_salesperson_trigger
before insert or update of salesperson_reference,salesperson_id on public.vehicles
for each row execute function public.pdc_default_vehicle_salesperson();

-- Backfill only currently unassigned exact references. Existing explicit
-- salesperson assignments are preserved.
update public.vehicles
set salesperson_id=public.pdc_salesperson_id_for_reference(salesperson_reference)
where salesperson_id is null
  and public.pdc_salesperson_id_for_reference(salesperson_reference) is not null;

commit;
