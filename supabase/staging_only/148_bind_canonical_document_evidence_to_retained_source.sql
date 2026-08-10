begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-148-canonical-document-source-binding',0));

do $guard$
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='147' and name='bind_monitor_import_to_activation_stock')
    or exists(select 1 from supabase_migrations.schema_migrations where version='148') then
   raise exception 'PDC_MONITOR_148_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end
$guard$;

do $bind$
declare
 v_definition text;
 v_old text:=$old$and p.source_hash=v_source_hash and lower(p.evidence_hash)=v_evidence_hash and p.source_uid=v_source_uid$old$;
 v_new text:=$new$and p.source_hash=v_source_hash and p.action_type='board_activate_only' and p.source_uid=v_source_uid$new$;
begin
 select pg_get_functiondef('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure) into v_definition;
 if obj_description('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure,'pg_proc') not like 'Staging v6 Monitor importer:%'
    or position(v_old in v_definition)=0 or position($cv6$'contract_version',6$cv6$ in v_definition)=0
    or position('public.normalize_vehicle_stock_number(v_activation.activated_stock_number) is distinct from v_stock' in v_definition)=0
    or position('source_proposal_binding_mismatch' in v_definition)=0
    or position('insert into public.vehicles' in lower(v_definition))>0
    or position('insert into public.navision_board_activations' in lower(v_definition))>0
    or position('update public.navision_board_activations' in lower(v_definition))>0
    or position('vehicle_parts_updates' in lower(v_definition))>0
    or position('workshop_bookings' in lower(v_definition))>0
    or position('pdc_ai_intake_history' in lower(v_definition))>0 then
   raise exception 'PDC_MONITOR_148_EXPLICIT_V6_DRIFT' using errcode='55000';
 end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_definition:=replace(v_definition,$cv6$'contract_version',6$cv6$,$cv7$'contract_version',7$cv7$);
 v_definition:=replace(v_definition,'pdc_monitor_canonical_stock_import_147','pdc_monitor_canonical_stock_import_148');
 execute v_definition;
end
$bind$;

revoke all on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) to authenticated;
comment on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) is
 'Staging v7 Monitor importer: v6 exact retained source/proposal/activation binding; canonical document evidence hash is independently validated and bound immutably by the explicit receipt request hash.';

do $assert$
declare v_definition text;
begin
 select pg_get_functiondef('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure) into v_definition;
 if position('p.action_type=''board_activate_only''' in v_definition)=0
    or position('lower(p.evidence_hash) = v_evidence_hash' in v_definition)>0
    or position($cv7$'contract_version',7$cv7$ in v_definition)=0
    or position('pdc_monitor_canonical_stock_import_148' in v_definition)=0
    or position('public.normalize_vehicle_stock_number(v_activation.activated_stock_number) is distinct from v_stock' in v_definition)=0
    or position('insert into public.vehicles' in lower(v_definition))>0
    or position('insert into public.navision_board_activations' in lower(v_definition))>0
    or position('update public.navision_board_activations' in lower(v_definition))>0
    or position('vehicle_parts_updates' in lower(v_definition))>0
    or position('workshop_bookings' in lower(v_definition))>0
    or position('pdc_ai_intake_history' in lower(v_definition))>0 then
   raise exception 'PDC_MONITOR_148_POSTCONDITION_FAILED' using errcode='55000';
 end if;
end
$assert$;

insert into supabase_migrations.schema_migrations(version,name,statements) values('148','bind_canonical_document_evidence_to_retained_source',array[
 'retain exact claimed source and retained board-activation proposal generation','retain exact sender authentication received time subject Stock normalized work activation Stock and canonical VIN checks','bind the independently validated canonical document hash immutably in the importer receipt and v7 request hash']);
commit;
