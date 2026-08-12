-- Staging-only remediation: operation-line overlays preserve valid two-decimal job-card hours.
begin;
do $guard$ begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or not exists(select 1 from supabase_migrations.schema_migrations where version='178' and name='fix_auditor_batch_json_value_binding')
 or exists(select 1 from supabase_migrations.schema_migrations where version='179') then raise exception 'PDC_179_GUARD_MISMATCH';end if;
end $guard$;
alter table public.vehicle_workshop_line_adjustments drop constraint if exists vehicle_workshop_line_adjustments_estimated_hours_check;
alter table public.vehicle_workshop_line_adjustments add constraint vehicle_workshop_line_adjustments_estimated_hours_check check(estimated_hours is null or (estimated_hours between 0.01 and 999.99 and estimated_hours=round(estimated_hours,2)));
insert into supabase_migrations.schema_migrations(version,name,statements) values('179','allow_source_precision_in_auditor_operation_overlays',array['Permit valid positive two-decimal source operation hours in reversible overlays instead of requiring quarter-hour rounding']);
commit;
