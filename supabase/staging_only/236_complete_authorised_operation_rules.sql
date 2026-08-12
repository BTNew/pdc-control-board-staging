-- Staging-only migration 236: complete the authorised future Monitor/Auditor rule inventory.
begin;
set local lock_timeout='20s';set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));
do $guard$
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='235')
    or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::numeric>235)
    or exists(select 1 from supabase_migrations.schema_migrations where version='236') then
   raise exception 'PDC_236_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end $guard$;

do $seed$
declare a uuid;e text;f uuid;v uuid;
begin
 select auth_user_id,lower(email) into a,e from public.pdc_user_roles
  where lower(email)='craig.watson@broometoyota.com.au' and role='administrator'
    and active and account_status='approved' limit 1;
 if a is null then raise exception 'PDC_236_CRAIG_AUTHORIZER_MISSING' using errcode='42501';end if;
 if exists(select 1 from public.pdc_supervised_rule_families where family_key='fill_tank_fuel_fitting') then
   raise exception 'PDC_236_RULE_ALREADY_EXISTS' using errcode='23505';
 end if;
 insert into public.pdc_supervised_rule_families(family_key,title,created_by,created_by_email)
 values('fill_tank_fuel_fitting','Fuel-fill operations to Fitting',a,e) returning family_id into f;
 insert into public.pdc_supervised_rule_versions(
   family_id,version_no,original_telegram_instruction,authorized_by,authorized_by_email,
   proposed_by,effective_from,priority,confidence,match_kind,phrase_category,work_key
 ) values(f,1,'Fill tank of fuel belongs to Fitting.',a,e,a,clock_timestamp(),9700,1.0000,'phrase','fill_tank_of_fuel','fitting')
 returning version_id into v;
 insert into public.pdc_supervised_rule_events(family_id,version_id,event_kind,reason,actor_id,actor_email)
 values(f,v,'activated','seeded from Craig authorised overnight instruction',a,e);
 insert into public.pdc_supervised_rule_aliases(version_id,alias) values
   (v,'fill tank of fuel'),(v,'fill fuel tank'),(v,'full tank of fuel');
 insert into public.pdc_supervised_rule_examples(version_id,example_kind,example_text)
 values(v,'positive','Fill tank of fuel');
end $seed$;

-- Postconditions: all authorised families are active and Pit remains required but not schedulable.
do $post$
begin
 if not exists(
   select 1 from public.pdc_supervised_rule_families f
   join public.pdc_supervised_rule_versions v on v.family_id=f.family_id
   where f.family_key='fill_tank_fuel_fitting' and v.phrase_category='fill_tank_of_fuel'
     and v.work_key='fitting' and v.effective_from<=clock_timestamp() and v.effective_until is null
 ) or not exists(
   select 1 from public.workshop_stages where work_key='pitInspection' and active and not planner_enabled
 ) then raise exception 'PDC_236_POSTCONDITION_FAILED' using errcode='55000';end if;
end $post$;
insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '236','complete_authorised_operation_rules',array[
    'activate Craig-authorised Fill tank of fuel to Fitting phrase rule and aliases without inventing hours or prices',
    'retain existing loose-safety aliases for safety triangle first aid and fire extinguisher',
    'verify Pit Inspection remains active required work with planner_enabled false'
  ]
);
commit;
