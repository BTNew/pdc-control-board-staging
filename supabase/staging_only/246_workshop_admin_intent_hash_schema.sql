-- Staging-only forward correction 246: schema-qualify SHA-256 intent hashing
-- under the hardened function search_path.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));
do $guard$
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='245' and name='workshop_admin_create_undo_audit_order')
    or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::numeric>246)
    or exists(select 1 from supabase_migrations.schema_migrations where version='246' and name<>'workshop_admin_intent_hash_schema') then
   raise exception 'PDC_246_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end $guard$;

do $replace$
declare v_oid oid; v_def text;
begin
 foreach v_oid in array array[
  'public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'::regprocedure::oid,
  'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'::regprocedure::oid
 ] loop
  v_def:=pg_get_functiondef(v_oid);
  if position($needle$extensions.digest(convert_to(v_intent::text,'UTF8'),'sha256')$needle$ in v_def)=0 then
   v_def:=replace(v_def,$needle$digest(convert_to(v_intent::text,'UTF8'),'sha256')$needle$,$needle$extensions.digest(convert_to(v_intent::text,'UTF8'),'sha256')$needle$);
   if position($needle$extensions.digest(convert_to(v_intent::text,'UTF8'),'sha256')$needle$ in v_def)=0 then raise exception 'PDC_246_HASH_BODY_NOT_FOUND'; end if;
   execute v_def;
  end if;
 end loop;
end $replace$;

revoke all on function public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean) to authenticated;
grant execute on function public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements)
values('246','workshop_admin_intent_hash_schema',array['staging-only forward correction: schema-qualified extensions.digest SHA-256 intent binding'])
on conflict(version) do update set name=excluded.name,statements=excluded.statements
where supabase_migrations.schema_migrations.name=excluded.name;
do $verify$
begin
 if not exists(select 1 from supabase_migrations.schema_migrations where version='246' and name='workshop_admin_intent_hash_schema') then raise exception 'PDC_246_LEDGER_VERIFY_FAILED'; end if;
 if position('extensions.digest' in pg_get_functiondef('public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'::regprocedure))=0 then raise exception 'PDC_246_HASH_VERIFY_FAILED'; end if;
end $verify$;
commit;
