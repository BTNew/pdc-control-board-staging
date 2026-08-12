-- Staging-only remediation: publish operation batch apply/rollback revisions.
begin;
do $guard$ begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or not exists(select 1 from supabase_migrations.schema_migrations where version='179' and name='allow_source_precision_in_auditor_operation_overlays')
 or exists(select 1 from supabase_migrations.schema_migrations where version='180') then raise exception 'PDC_180_GUARD_MISMATCH';end if;
end $guard$;
alter table public.pdc_auditor_revision drop constraint pdc_auditor_revision_event_type_check;
alter table public.pdc_auditor_revision add constraint pdc_auditor_revision_event_type_check check(event_type in('foundation','findings_appended','report_appended','config_appended','decision_recorded','operation_batch_applied','operation_batch_rolled_back'));
insert into supabase_migrations.schema_migrations(version,name,statements) values('180','publish_auditor_operation_batch_revisions',array['Allow explicit operation batch apply and rollback revision event types for Realtime consumers']);
commit;
