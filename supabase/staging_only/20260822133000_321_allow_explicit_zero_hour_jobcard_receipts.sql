begin;
do $guard$ declare p text;begin
 if to_regclass('public.pdc_production_environment_sentinel') is not null then raise exception 'PDC_321_PRODUCTION_SENTINEL_PRESENT';end if;
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_321_STAGING_GUARD_FAILED';end if;
 select project_ref into p from public.pdc_staging_environment_sentinel where singleton;
 if p is distinct from 'cdsmnqxtyyoeoznmbidd' then raise exception 'PDC_321_PROJECT_MISMATCH';end if;
 if (select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.pdc_jobcard_attachment_import_receipts'::regclass and conname='pdc_jobcard_attachment_import_receipt_estimated_hours_sum_check') is distinct from 'CHECK ((estimated_hours_sum > (0)::numeric))' then raise exception 'PDC_321_OLD_CONSTRAINT_DRIFT';end if;
 if (select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.pdc_jobcard_attachment_import_receipts'::regclass and conname='pdc_jobcard_attachment_import_receipts_estimated_hours_sum_chec') is distinct from 'CHECK (((estimated_hours_sum >= (0)::numeric) AND (estimated_hours_sum <= 49999.50)))' then raise exception 'PDC_321_BOUNDED_ZERO_CONSTRAINT_MISSING';end if;
end $guard$;
alter table public.pdc_jobcard_attachment_import_receipts drop constraint pdc_jobcard_attachment_import_receipt_estimated_hours_sum_check;
insert into supabase_migrations.schema_migrations(version,name,statements) values('20260822133000','321_allow_explicit_zero_hour_jobcard_receipts',array['drop obsolete >0 receipt constraint; retain bounded >=0 constraint']) on conflict(version) do nothing;
commit;
