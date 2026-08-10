begin;

-- Staging-only repair: Migration 109 accidentally omitted canonical Parts from
-- the with-hours operation allow-list. A single Parts line therefore rejected
-- the whole otherwise-valid document payload as invalid_operation_lines.
do $repair$
declare
  v_definition text;
  v_old_allow_list constant text := '(''bus4x4'',''tint'',''hoist'',''fitting'',''fabrication'',''electrical'',''tyre'',''pitInspection'')';
  v_new_allow_list constant text := '(''bus4x4'',''tint'',''hoist'',''fitting'',''fabrication'',''electrical'',''tyre'',''pitInspection'',''parts'')';
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regprocedure('public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_work_items') is null then
    raise exception 'PDC_OPERATION_PARTS_143_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;

  select pg_get_functiondef('public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'::regprocedure)
    into v_definition;

  -- Refuse to patch an unknown function version or weaken any independent guard.
  if (length(v_definition)-length(replace(v_definition,v_old_allow_list,''))) / length(v_old_allow_list) <> 1
     or position(v_new_allow_list in v_definition) > 0
     or position('pdc_monitor_staging_guard()' in v_definition) = 0
     or position('jsonb_array_length(v_operations) not between 1 and 50' in v_definition) = 0
     or position('source_receipt_not_found' in v_definition) = 0
     or position('operation_identity_conflict' in v_definition) = 0
     or position('estimated_hours_conflict' in v_definition) = 0
     or position('operation_lines_and_hours_already_imported' in v_definition) = 0
     or position('''booking_created'',false' in v_definition) = 0
     or position('''completed_work_reopened'',false' in v_definition) = 0 then
    raise exception 'PDC_OPERATION_PARTS_143_FUNCTION_DRIFT' using errcode='55000';
  end if;

  v_definition := replace(v_definition,v_old_allow_list,v_new_allow_list);
  v_definition := replace(v_definition,'pdc_authenticated_email_operation_hours_109','pdc_authenticated_email_operation_hours_143');
  execute v_definition;
end;
$repair$;

revoke all on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) to authenticated;
comment on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) is
  'Staging-only enrolled-Viewer typed import of bounded authenticated job-card OP lines, including Parts, with job-card/AI hour provenance; job-card hours win; never books or completes work.';

commit;
