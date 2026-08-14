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

insert into public.pdc_auditor_workshop_revisions(
 dealer_code, environment, event_type, run_id
) values(
 '14450', 'staging', 'telegram_plan_applied_226',
 'e2540000-0000-4000-8000-000000000001'
);

create temp table disable_revision_rows_before254 as
select revision_id, dealer_code, environment, event_type, run_id,
       rollback_receipt_id, created_at, typed_run_id_253
from public.pdc_auditor_workshop_revisions;

-- A contaminated helper ACL plus hostile retained-object ACL/RLS/policy state must
-- be removed by forward containment.
grant execute on function public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean) to authenticated;
do $contaminate$ declare t text; begin
 foreach t in array array[
  'pdc_auditor_gateway_keys_253','pdc_auditor_signed_deliveries_253','pdc_auditor_signed_delivery_results_253',
  'pdc_auditor_typed_plans_253','pdc_auditor_typed_plan_items_253','pdc_auditor_typed_runs_253',
  'pdc_auditor_typed_scope_receipts_253','pdc_auditor_typed_change_receipts_253','pdc_auditor_typed_undo_receipts_253'
 ] loop
  execute format('alter table public.%I disable row level security',t);
  execute format('grant select,insert,update,delete on table public.%I to public,anon,authenticated,service_role',t);
  execute format('create policy hostile_all_254_test on public.%I for all to public using (true) with check (true)',t);
 end loop;
end $contaminate$;
grant select on public.pdc_auditor_normalized_operation_lines_253 to public,anon,authenticated,service_role;
grant select on public.pdc_auditor_workshop_revisions to public,anon,authenticated,service_role;
create policy hostile_shared_revision_254_test on public.pdc_auditor_workshop_revisions for select to public using (true);

select count(*) filter (where typed_run_id_253 is not null) as typed_revision_count_before254,
       count(*) filter (
         where dealer_code='14450'
           and environment='staging'
           and event_type in ('telegram_plan_applied_226','telegram_run_rolled_back_226')
           and typed_run_id_253 is null
       ) as visible_legacy_count_before254
from public.pdc_auditor_workshop_revisions
\gset

create temp table disable_revision_visibility_before254 as
select :visible_legacy_count_before254::bigint as visible_legacy_count_before254;

select case when :typed_revision_count_before254::bigint > 0 then 1 else 1/0 end;

\i supabase/staging_only/254_disable_ai_auditor_typed_operation_control.sql

-- The local fixture is installed by a privileged harness owner. Re-owner only
-- the already-contained private tables to a real non-BYPASS role for the
-- post-migration FORCE RLS visibility probe, then restore immediately.
do $probe_owner$ declare t text; begin
 if (select rolbypassrls from pg_roles where rolname='authenticated') then
  raise exception 'authenticated test owner unexpectedly has BYPASSRLS';
 end if;
 foreach t in array array[
  'pdc_auditor_gateway_keys_253','pdc_auditor_signed_deliveries_253','pdc_auditor_signed_delivery_results_253',
  'pdc_auditor_typed_plans_253','pdc_auditor_typed_plan_items_253','pdc_auditor_typed_runs_253',
  'pdc_auditor_typed_scope_receipts_253','pdc_auditor_typed_change_receipts_253','pdc_auditor_typed_undo_receipts_253'
 ] loop
  execute format('alter table public.%I owner to authenticated',t);
 end loop;
end $probe_owner$;

-- Prove FORCE RLS against the actual table owner, not the BYPASS-capable harness
-- session. The retained rows still exist physically but no private-table policy
-- remains, so the non-BYPASS owner must see zero rows.
do $assert_owner_non_bypass$ begin
 if exists(
  select 1 from pg_class c join pg_roles r on r.oid=c.relowner
  where c.oid='public.pdc_auditor_gateway_keys_253'::regclass and r.rolbypassrls
 ) then raise exception 'private table owner unexpectedly has BYPASSRLS'; end if;
end $assert_owner_non_bypass$;
select format('set role %I',c.relowner::regrole)
from pg_class c where c.oid='public.pdc_auditor_gateway_keys_253'::regclass
\gexec
set row_security=on;
do $assert_owner_zero_visibility$ begin
 if (
  (select count(*) from public.pdc_auditor_gateway_keys_253) +
  (select count(*) from public.pdc_auditor_signed_deliveries_253) +
  (select count(*) from public.pdc_auditor_signed_delivery_results_253) +
  (select count(*) from public.pdc_auditor_typed_plans_253) +
  (select count(*) from public.pdc_auditor_typed_plan_items_253) +
  (select count(*) from public.pdc_auditor_typed_runs_253) +
  (select count(*) from public.pdc_auditor_typed_scope_receipts_253) +
  (select count(*) from public.pdc_auditor_typed_change_receipts_253) +
  (select count(*) from public.pdc_auditor_typed_undo_receipts_253)
 ) <> 0 then raise exception 'non-BYPASS owner retained private-row visibility after FORCE RLS'; end if;
end $assert_owner_zero_visibility$;
reset role;
do $restore_probe_owner$ declare t text; begin
 foreach t in array array[
  'pdc_auditor_gateway_keys_253','pdc_auditor_signed_deliveries_253','pdc_auditor_signed_delivery_results_253',
  'pdc_auditor_typed_plans_253','pdc_auditor_typed_plan_items_253','pdc_auditor_typed_runs_253',
  'pdc_auditor_typed_scope_receipts_253','pdc_auditor_typed_change_receipts_253','pdc_auditor_typed_undo_receipts_253'
 ] loop
  execute format('alter table public.%I owner to %I',t,current_user);
 end loop;
end $restore_probe_owner$;

do $$declare p record;t text;v_role text;v_rls boolean;v_force boolean;v_visible_legacy_count bigint;before_row disable_before254%rowtype;after_row disable_before254%rowtype;begin
 select visible_legacy_count_before254 into v_visible_legacy_count from disable_revision_visibility_before254;
 if not exists(select 1 from supabase_migrations.schema_migrations where version='254' and name='disable_ai_auditor_typed_operation_control') then raise exception 'migration 254 ledger missing';end if;
 for p in select oid,proname from pg_proc where oid in(
  'public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb)'::regprocedure,
  'public.compose_pdc_auditor_typed_plan_253(uuid[],jsonb)'::regprocedure,
  'public.apply_pdc_auditor_typed_plan_253(uuid,integer,text,text,text,text,jsonb)'::regprocedure,
  'public.undo_last_pdc_auditor_typed_run_253(jsonb)'::regprocedure,
  'public.query_pdc_auditor_typed_253(text,jsonb,jsonb)'::regprocedure,
  'public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean)'::regprocedure
 ) loop
  if has_function_privilege('public',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('service_role',p.oid,'execute') then raise exception '254 left RPC authority %',p.proname;end if;
 end loop;
 foreach t in array array[
  'pdc_auditor_gateway_keys_253','pdc_auditor_signed_deliveries_253','pdc_auditor_signed_delivery_results_253',
  'pdc_auditor_typed_plans_253','pdc_auditor_typed_plan_items_253','pdc_auditor_typed_runs_253',
  'pdc_auditor_typed_scope_receipts_253','pdc_auditor_typed_change_receipts_253','pdc_auditor_typed_undo_receipts_253'
 ] loop
  select relrowsecurity,relforcerowsecurity into v_rls,v_force from pg_class where oid=format('public.%I',t)::regclass;
  if not v_rls or not v_force then raise exception '254 did not restore forced RLS for %',t;end if;
  if exists(select 1 from pg_policy where polrelid=format('public.%I',t)::regclass) then raise exception '254 left policy on private table %',t;end if;
  foreach v_role in array array['anon','authenticated','service_role'] loop
   if has_table_privilege(v_role,format('public.%I',t),'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then raise exception '254 left table authority role=% table=%',v_role,t;end if;
  end loop;
 end loop;
 foreach v_role in array array['anon','authenticated','service_role'] loop
  if has_table_privilege(v_role,'public.pdc_auditor_normalized_operation_lines_253','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then raise exception '254 left normalized view authority role=%',v_role;end if;
 end loop;
 if not (select relrowsecurity from pg_class where oid='public.pdc_auditor_workshop_revisions'::regclass)
    or (select count(*) from pg_policy where polrelid='public.pdc_auditor_workshop_revisions'::regclass) <> 1
    or not exists(select 1 from pg_policy where polrelid='public.pdc_auditor_workshop_revisions'::regclass and polname='pdc_auditor_workshop_revisions_legacy_admin_read_254' and polcmd='r' and polpermissive and polroles=array['authenticated'::regrole::oid] and polwithcheck is null)
    or not has_column_privilege('authenticated','public.pdc_auditor_workshop_revisions','revision_id','SELECT')
    or not has_function_privilege('authenticated','public.pdc_auditor_human_admin_revision_read_253(text)','EXECUTE')
    or not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_auditor_workshop_revisions') then raise exception '254 legacy revision transport/policy inventory not preserved';end if;
 set role authenticated;
 perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
 perform set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","email":"craig@example.test","role":"authenticated"}',false);
 if (select count(*) from public.pdc_auditor_workshop_revisions where typed_run_id_253 is not null) <> 0
    or (select count(*) from public.pdc_auditor_workshop_revisions) <> v_visible_legacy_count
    or exists(select 1 from public.pdc_auditor_workshop_revisions where environment<>'staging' or event_type not in ('telegram_plan_applied_226','telegram_run_rolled_back_226') or typed_run_id_253 is not null) then
   raise exception '254 authenticated legacy visibility drift';
 end if;
 reset role;
 set role authenticated;
 perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
 perform set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","email":"auditor@example.test","role":"authenticated"}',false);
 if (select count(*) from public.pdc_auditor_workshop_revisions) <> 0 then
   raise exception '254 non-admin authenticated revision visibility remains';
 end if;
 reset role;
 select * into before_row from disable_before254;
 select (select count(*) from public.pdc_auditor_gateway_keys_253),(select count(*) from public.pdc_auditor_signed_deliveries_253),(select count(*) from public.pdc_auditor_typed_plans_253),(select count(*) from public.pdc_auditor_typed_runs_253),(select count(*) from public.vehicle_workshop_line_adjustments),(select count(*) from public.pdc_auditor_workshop_revisions) into after_row;
 if after_row.keys<>before_row.keys or after_row.deliveries<>before_row.deliveries or after_row.plans<>before_row.plans or after_row.runs<>before_row.runs or after_row.adjustments<>before_row.adjustments or after_row.revisions<>(before_row.revisions + 1) then raise exception '254 changed retained evidence or operational rows: % -> %',to_jsonb(before_row),to_jsonb(after_row);end if;
 if exists((select revision_id, dealer_code, environment, event_type, run_id, rollback_receipt_id, created_at, typed_run_id_253 from public.pdc_auditor_workshop_revisions except all select * from disable_revision_rows_before254) union all (select * from disable_revision_rows_before254 except all select revision_id, dealer_code, environment, event_type, run_id, rollback_receipt_id, created_at, typed_run_id_253 from public.pdc_auditor_workshop_revisions)) then raise exception '254 changed retained revision evidence'; end if;
end$$;
select 'AI_AUDITOR_254_FORWARD_DISABLE_PASS' result;
