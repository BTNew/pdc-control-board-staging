-- Forward-disable migration 254 must close all migration-253 API authority while
-- retaining every immutable evidence and operational table.
\set ON_ERROR_STOP on

insert into public.pdc_auditor_gateway_keys_253(gateway_instance_id,key_id,hmac_key,active,valid_from,valid_until,provisioned_by)
values('disable-fixture','disable-key',decode(repeat('55',32),'hex'),true,clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 hour','10000000-0000-4000-8000-000000000003');

create temp table disable_before254 as select
 (select count(*) from public.pdc_auditor_gateway_keys_253) keys,
 (select count(*) from public.pdc_auditor_signed_deliveries_253) deliveries,
 (select count(*) from public.pdc_auditor_typed_plans_253) plans,
 (select count(*) from public.pdc_auditor_typed_runs_253) runs,
 (select count(*) from public.vehicle_workshop_line_adjustments) adjustments,
 (select count(*) from public.pdc_auditor_workshop_revisions) revisions;

\i supabase/staging_only/254_disable_ai_auditor_typed_operation_control.sql

do $$declare p record;before_row disable_before254%rowtype;after_row disable_before254%rowtype;begin
 if not exists(select 1 from supabase_migrations.schema_migrations where version='254' and name='disable_ai_auditor_typed_operation_control') then raise exception 'migration 254 ledger missing';end if;
 for p in select oid,proname from pg_proc where oid in(
  'public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb)'::regprocedure,
  'public.compose_pdc_auditor_typed_plan_253(uuid[],jsonb)'::regprocedure,
  'public.apply_pdc_auditor_typed_plan_253(uuid,integer,text,text,text,text,jsonb)'::regprocedure,
  'public.undo_last_pdc_auditor_typed_run_253(jsonb)'::regprocedure,
  'public.query_pdc_auditor_typed_253(text,jsonb,jsonb)'::regprocedure,
  'public.pdc_auditor_human_admin_revision_read_253(text)'::regprocedure
 ) loop
  if has_function_privilege('public',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('service_role',p.oid,'execute') then raise exception '254 left RPC authority %',p.proname;end if;
 end loop;
 if exists(select 1 from pg_policies where schemaname='public' and tablename='pdc_auditor_workshop_revisions' and policyname='pdc_auditor_workshop_revisions_admin_read_253') or has_table_privilege('authenticated','public.pdc_auditor_workshop_revisions','SELECT') then raise exception '254 left revision read authority';end if;
 select * into before_row from disable_before254;
 select (select count(*) from public.pdc_auditor_gateway_keys_253),(select count(*) from public.pdc_auditor_signed_deliveries_253),(select count(*) from public.pdc_auditor_typed_plans_253),(select count(*) from public.pdc_auditor_typed_runs_253),(select count(*) from public.vehicle_workshop_line_adjustments),(select count(*) from public.pdc_auditor_workshop_revisions) into after_row;
 if to_jsonb(after_row)<>to_jsonb(before_row) then raise exception '254 changed retained evidence or operational rows: % -> %',to_jsonb(before_row),to_jsonb(after_row);end if;
end$$;
select 'AI_AUDITOR_254_FORWARD_DISABLE_PASS' result;
