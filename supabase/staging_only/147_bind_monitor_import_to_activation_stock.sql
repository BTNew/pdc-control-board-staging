begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-147-monitor-activation-stock-binding',0));

do $guard$
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='146' and name='bind_monitor_import_to_retained_proposal')
    or exists(select 1 from supabase_migrations.schema_migrations where version='147') then
   raise exception 'PDC_MONITOR_147_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end
$guard$;

do $bind$
declare
 v_definition text;
 v_old text:=$old$or v_record.canonical_vehicle_id is distinct from v_activation.canonical_vehicle_id then return public.navision_backend_response(false,'active_canonical_link_required'); end if;$old$;
 v_new text:=$new$or public.normalize_vehicle_stock_number(v_activation.activated_stock_number) is distinct from v_stock
    or v_record.canonical_vehicle_id is distinct from v_activation.canonical_vehicle_id then return public.navision_backend_response(false,'active_canonical_link_required'); end if;$new$;
begin
 select pg_get_functiondef('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure) into v_definition;
 if obj_description('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure,'pg_proc') not like 'Staging v5 Monitor importer:%'
    or position(v_old in v_definition)=0 or position($cv5$'contract_version',5$cv5$ in v_definition)=0
    or position('source_proposal_binding_mismatch' in v_definition)=0
    or position('insert into public.vehicles' in lower(v_definition))>0
    or position('insert into public.navision_board_activations' in lower(v_definition))>0
    or position('update public.navision_board_activations' in lower(v_definition))>0
    or position('vehicle_parts_updates' in lower(v_definition))>0
    or position('workshop_bookings' in lower(v_definition))>0
    or position('pdc_ai_intake_history' in lower(v_definition))>0 then
   raise exception 'PDC_MONITOR_147_EXPLICIT_V5_DRIFT' using errcode='55000';
 end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_definition:=replace(v_definition,$cv5$'contract_version',5$cv5$,$cv6$'contract_version',6$cv6$);
 v_definition:=replace(v_definition,'pdc_monitor_canonical_stock_import_146','pdc_monitor_canonical_stock_import_147');
 execute v_definition;
end
$bind$;

revoke all on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) to authenticated;
comment on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) is
 'Staging v6 Monitor importer: v5 retained-proposal-bound explicit contract plus exact activation.activated_stock_number binding to the unique current Navision Stock.';

do $assert$
declare v_definition text;
begin
 select pg_get_functiondef('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure) into v_definition;
 if position('public.normalize_vehicle_stock_number(v_activation.activated_stock_number) is distinct from v_stock' in v_definition)=0
    or position($cv6$'contract_version',6$cv6$ in v_definition)=0
    or position('pdc_monitor_canonical_stock_import_147' in v_definition)=0
    or position('insert into public.vehicles' in lower(v_definition))>0
    or position('insert into public.navision_board_activations' in lower(v_definition))>0
    or position('update public.navision_board_activations' in lower(v_definition))>0
    or position('vehicle_parts_updates' in lower(v_definition))>0
    or position('workshop_bookings' in lower(v_definition))>0
    or position('pdc_ai_intake_history' in lower(v_definition))>0 then
   raise exception 'PDC_MONITOR_147_POSTCONDITION_FAILED' using errcode='55000';
 end if;
end
$assert$;

insert into supabase_migrations.schema_migrations(version,name,statements) values('147','bind_monitor_import_to_activation_stock',array[
 'require activation activated_stock_number to normalize to the exact retained/current Stock','retain source proposal binding and explicit mutation limits','retain authenticated-only enrolled Viewer execution']);
commit;
