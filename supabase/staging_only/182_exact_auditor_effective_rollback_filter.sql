-- Staging-only remediation: exact effective rollback while immutable adjustment history is retained.
begin;
do $guard$ begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='181' and name='add_explicit_auditor_rollback_audit_action') or exists(select 1 from supabase_migrations.schema_migrations where version='182') then raise exception 'PDC_182_GUARD_MISMATCH';end if;
end $guard$;
create or replace view public.pdc_effective_operation_lines with(security_invoker=false) as
with source_rows as(
 select ol.operation_line_id::text operation_line_identifier,ol.operation_line_id,ol.vehicle_id,
  coalesce(a.job_card_number,ol.job_card_number) job_card_number,
  coalesce(a.operation_code,ol.operation_no) operation_code,
  coalesce(public.pdc_auditor_work_key_for_stage(a.stage_code),ol.work_key) work_key,
  coalesce(a.description,ol.description) description,
  coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,
  coalesce(a.display_order,ol.source_row_no) display_order,
  coalesce(a.active,true) active,
  coalesce(a.manual_assignment_locked,false) manual_assignment_locked,
  a.adjustment_id,a.correction_origin
 from public.pdc_authenticated_email_operation_lines ol
 left join public.vehicle_workshop_line_adjustments a on a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text and a.correction_origin is distinct from 'ai_auditor_rolled_back'
), added_rows as(
 select a.adjustment_id::text,a.source_operation_line_id,a.vehicle_id,a.job_card_number,a.operation_code,
  public.pdc_auditor_work_key_for_stage(a.stage_code),a.description,a.estimated_hours,a.display_order,a.active,
  a.manual_assignment_locked,a.adjustment_id,a.correction_origin
 from public.vehicle_workshop_line_adjustments a
 where a.correction_origin='ai_auditor' and a.source_operation_line_id is null and a.active
)
select * from source_rows union all select * from added_rows;
revoke all on public.pdc_effective_operation_lines from public,anon;grant select on public.pdc_effective_operation_lines to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('182','exact_auditor_effective_rollback_filter',array['Ignore rolled-back source overlays and inactive added lines in effective Work and Bookings operation lines while retaining immutable history']);commit;
