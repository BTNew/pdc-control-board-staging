-- Staging-only remediation: preserve valid zero-hour source lines during department-only overlays.
begin;
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='185') or exists(select 1 from supabase_migrations.schema_migrations where version='186') then raise exception 'PDC_186_GUARD_MISMATCH';end if;end $guard$;
alter table public.vehicle_workshop_line_adjustments drop constraint vehicle_workshop_line_adjustments_estimated_hours_check;
alter table public.vehicle_workshop_line_adjustments add constraint vehicle_workshop_line_adjustments_estimated_hours_check check(estimated_hours is null or (estimated_hours between 0 and 999.99 and estimated_hours=round(estimated_hours,2)));
insert into supabase_migrations.schema_migrations(version,name,statements) values('186','preserve_zero_hour_source_lines_in_department_overlays',array['Permit a valid zero-hour source line when only its department is corrected; direct hour edits still require positive values']);commit;
