begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

do $repair$
declare
  v_signature constant regprocedure := 'public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)'::regprocedure;
  v_definition text;
  v_marker text;
  v_replacement text;
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='132' and name='stock_only_authenticated_email_batch_fanout')
     or not exists(select 1 from supabase_migrations.schema_migrations where version='143' and name='authenticated_operation_parts_allowance')
     or to_regprocedure('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)') is null
     or to_regprocedure('public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)') is null then
    raise exception 'PDC_MONITOR_IMPORTER_144_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;
  if has_function_privilege('authenticated',v_signature,'EXECUTE') then
    raise exception 'PDC_MONITOR_IMPORTER_144_LEGACY_EXECUTE_UNEXPECTED' using errcode='55000';
  end if;

  select pg_get_functiondef(v_signature) into v_definition;
  if position('pdc_monitor_staging_guard()' in v_definition)=0
     or position('pdc_monitor_stage_activation_writers' in v_definition)=0
     or position('pdc_email_source_claims' in v_definition)=0
     or position('pdc_authenticated_email_import_receipts' in v_definition)=0
     or position('booking_created' in v_definition)=0
     or position('current_location is deliberately absent' in lower(v_definition))=0
     or position('email_new' in v_definition)=0 then
    raise exception 'PDC_MONITOR_IMPORTER_144_LEGACY_FUNCTION_DRIFT' using errcode='55000';
  end if;

  v_marker := 'or jsonb_array_length(v_email->''stock_numbers'')>1';
  if (length(v_definition)-length(replace(v_definition,v_marker,'')))/length(v_marker)<>1 then
    raise exception 'PDC_MONITOR_IMPORTER_144_STOCK_CARDINALITY_DRIFT' using errcode='55000';
  end if;
  v_definition:=replace(v_definition,v_marker,'or jsonb_array_length(v_email->''stock_numbers'') is distinct from 1');

  v_marker := 'when ''parts'' then ''PARTS''';
  if (length(v_definition)-length(replace(v_definition,v_marker,'')))/length(v_marker)<>1 then
    raise exception 'PDC_MONITOR_IMPORTER_144_PARTS_MAPPING_DRIFT' using errcode='55000';
  end if;
  v_definition:=replace(v_definition,v_marker,'when ''parts'' then ''parts''');
  v_definition:=replace(v_definition,'if v_work_key<>''PARTS'' and not exists(','if v_work_key<>''parts'' and not exists(');
  v_definition:=replace(v_definition,'v_parts_requested:=v_parts_requested or v_work_key=''PARTS'';','v_parts_requested:=false;');

  v_marker := ') q;
  select coalesce(array_agg(id order by id),''{}''::uuid[]) into v_nav_vin_ids from (';
  v_replacement := ') q;
  if cardinality(v_nav_stock_ids)=0 then
    return public.navision_backend_response(false,''backend_stock_not_found'');
  elsif cardinality(v_nav_stock_ids)<>1 then
    return public.navision_backend_response(false,''backend_stock_ambiguous'',jsonb_build_object(''match_count'',cardinality(v_nav_stock_ids)));
  end if;
  select coalesce(array_agg(id order by id),''{}''::uuid[]) into v_nav_vin_ids from (';
  if (length(v_definition)-length(replace(v_definition,v_marker,'')))/length(v_marker)<>1 then
    raise exception 'PDC_MONITOR_IMPORTER_144_NAVISION_MATCH_DRIFT' using errcode='55000';
  end if;
  v_definition:=replace(v_definition,v_marker,v_replacement);

  v_marker := 'v_job_card:=v_nav_job;';
  v_replacement := 'if v_nav_job is not null and v_job_card is not null and upper(btrim(v_nav_job))<>upper(btrim(v_job_card)) then
      return public.navision_backend_response(false,''job_card_source_conflict'');
    end if;
    v_job_card:=coalesce(v_nav_job,v_job_card);';
  if (length(v_definition)-length(replace(v_definition,v_marker,'')))/length(v_marker)<>1 then
    raise exception 'PDC_MONITOR_IMPORTER_144_JOB_CARD_SOURCE_DRIFT' using errcode='55000';
  end if;
  v_definition:=replace(v_definition,v_marker,v_replacement);

  v_marker := 'select to_jsonb(v_vehicle) into v_before_vehicle;
    update public.vehicles set';
  v_replacement := 'select to_jsonb(v_vehicle) into v_before_vehicle;
    if nullif(btrim(coalesce(v_vehicle.job_card_number,'''')),'''') is not null
       and v_job_card is not null
       and upper(btrim(v_vehicle.job_card_number))<>upper(btrim(v_job_card)) then
      return public.navision_backend_response(false,''operational_job_card_conflict'');
    end if;
    update public.vehicles set';
  if (length(v_definition)-length(replace(v_definition,v_marker,'')))/length(v_marker)<>1 then
    raise exception 'PDC_MONITOR_IMPORTER_144_EXISTING_JOB_CARD_DRIFT' using errcode='55000';
  end if;
  v_definition:=replace(v_definition,v_marker,v_replacement);
  v_definition:=replace(v_definition,
    'job_card_number=case when v_record.id is not null then v_nav_job else coalesce(v_job_card,job_card_number) end,',
    'job_card_number=case when v_record.id is not null then coalesce(v_job_card,job_card_number) else coalesce(v_job_card,job_card_number) end,');
  v_definition:=replace(v_definition,'''contract_version'',1','''contract_version'',3');
  v_definition:=replace(v_definition,'''pdc_navision_stock_authority_096''','''pdc_monitor_canonical_stock_import_144''');
  v_definition:=replace(v_definition,'''pdc_authenticated_email_066''','''pdc_monitor_canonical_stock_import_144''');

  execute v_definition;
end
$repair$;

revoke all on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)
from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)
to authenticated;
revoke all on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)
from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)
to authenticated;

comment on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) is
  'Staging v3 canonical Monitor importer: enrolled approved Viewer; exactly one unique current Navision Stock; VIN conflict-only; receipt/work requirements only; no booking, completion reopening, location scheduling or email-new fallback.';

insert into supabase_migrations.schema_migrations(version,name,statements)
values('144','restore_narrow_pdc_monitor_canonical_importer',array[
  'replace legacy importer body with exact-current-Navision-Stock-only contract v3',
  'restore authenticated execute while retaining enrolled Viewer gate',
  'remove service-role execute from canonical vehicle and with-hours RPCs'
]);

commit;
