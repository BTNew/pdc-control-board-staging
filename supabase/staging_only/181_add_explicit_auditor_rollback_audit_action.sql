-- Staging-only remediation: audit complete AI Auditor rollback actions explicitly.
begin;
do $guard$ begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or not exists(select 1 from supabase_migrations.schema_migrations where version='180' and name='publish_auditor_operation_batch_revisions')
 or exists(select 1 from supabase_migrations.schema_migrations where version='181') then raise exception 'PDC_181_GUARD_MISMATCH';end if;
end $guard$;
alter type public.audit_action add value if not exists 'rollback';
insert into supabase_migrations.schema_migrations(version,name,statements) values('181','add_explicit_auditor_rollback_audit_action',array['Add append-only rollback audit action for complete instruction-bound AI Auditor run reversals']);
commit;
