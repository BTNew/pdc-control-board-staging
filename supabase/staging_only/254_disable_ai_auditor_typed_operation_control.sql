-- DESIGN ONLY: forward-only staging containment for migration 253.
-- No down migration is supplied. Re-enable/recovery requires a later reviewed forward migration.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation', 0));
lock table supabase_migrations.schema_migrations in exclusive mode;

do $guard$
declare
  v_head text;
  v_name text;
  v_table text;
  v_function text;
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or (select count(*) from public.pdc_staging_environment_sentinel
          where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'PDC_254_PROJECT_MISMATCH' using errcode = '55000';
  end if;

  select version into v_head
  from supabase_migrations.schema_migrations
  where version ~ '^[0-9]+$'
  order by version::integer desc
  limit 1;
  select name into v_name
  from supabase_migrations.schema_migrations
  where version = '253';
  if v_head is distinct from '253'
     or v_name is distinct from 'ai_auditor_typed_operation_control'
     or (select statements from supabase_migrations.schema_migrations where version = '253') is distinct from array[
       'exact migration-250 name and statement predecessor with migrations 251/252 unused',
       'global migration-230 Telegram message/update reservation plus exact 253 delivery UUID and gateway nonce replay control',
       'exact ISO-UTC ten-field runtime envelope with length-prefixed ordered signing bytes and top-level Telegram evidence',
       'bounded contract/action/selector/desire intent expanded server-side; caller candidates, old values, disposition and proof forbidden',
       'separate signed Apply binds exact plan_id and plan_hash plus exact Craig confirmation instruction',
       'source and auditor namespaces remain disjoint text refs across edit split combine reorder and duplicate operations',
       'migration-228 duplicate proof requires source UID and fingerprint, distinct source hashes and rejects variant quantity kit side and stage ambiguity',
       'only affected current and target work keys protect completed work; unrelated completed departments do not block',
       'logical effective snapshots exclude inactive tombstones and false non-completed requirements while preserving append-only rows and stable effective IDs',
       'strict whole-run Undo preflights final scope receipts once, restores reverse mutations, verifies exact initial logical scopes, then seals undone',
       'Administrator browser Realtime SELECT requires exact active approved role and active auth UUID/email/dealer/environment scope; no DML sequence or key provisioning authority'
     ]::text[]
     or exists(select 1 from supabase_migrations.schema_migrations where version in ('251','252','254'))
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer > 253) then
    raise exception 'PDC_254_EXACT_253_HEAD_NAME_OR_LEDGER_REQUIRED head=% name=%', v_head, v_name using errcode = '55000';
  end if;

  foreach v_table in array array[
    'pdc_auditor_gateway_keys_253',
    'pdc_auditor_signed_deliveries_253',
    'pdc_auditor_signed_delivery_results_253',
    'pdc_auditor_typed_plans_253',
    'pdc_auditor_typed_plan_items_253',
    'pdc_auditor_typed_runs_253',
    'pdc_auditor_typed_scope_receipts_253',
    'pdc_auditor_typed_change_receipts_253',
    'pdc_auditor_typed_undo_receipts_253'
  ] loop
    if to_regclass('public.' || v_table) is null then
      raise exception 'PDC_254_253_TABLE_MISSING %', v_table using errcode = '55000';
    end if;
  end loop;

  foreach v_function in array array[
    'public.pdc_auditor_seal_only_253()',
    'public.pdc_auditor_typed_snapshot_253(uuid,text)',
    'public.pdc_auditor_canonical_json_253(jsonb)',
    'public.pdc_auditor_signing_bytes_253(jsonb)',
    'public.pdc_auditor_verify_envelope_253(text,jsonb)',
    'public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean)',
    'public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb)',
    'public.compose_pdc_auditor_typed_plan_253(uuid[],jsonb)',
    'public.pdc_auditor_recalculate_required_work_253(uuid[])',
    'public.apply_pdc_auditor_typed_plan_253(uuid,integer,text,text,text,text,jsonb)',
    'public.undo_last_pdc_auditor_typed_run_253(jsonb)',
    'public.query_pdc_auditor_typed_253(text,jsonb,jsonb)'
  ] loop
    if to_regprocedure(v_function) is null then
      raise exception 'PDC_254_253_FUNCTION_MISSING %', v_function using errcode = '55000';
    end if;
  end loop;

  if to_regclass('public.pdc_auditor_normalized_operation_lines_253') is null
     or to_regclass('public.pdc_auditor_workshop_revisions_typed_once_253') is null
     or not exists(
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'pdc_auditor_workshop_revisions'
         and column_name = 'typed_run_id_253')
     or not exists(
       select 1 from pg_constraint
       where conrelid = 'public.pdc_auditor_workshop_revisions'::regclass
         and conname = 'pdc_auditor_workshop_revisions_shape_253')
     or not exists(
       select 1 from pg_policies
       where schemaname = 'public' and tablename = 'pdc_auditor_workshop_revisions'
         and policyname = 'pdc_auditor_workshop_revisions_admin_read_253')
     or not exists(
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public'
         and tablename = 'pdc_auditor_workshop_revisions') then
    raise exception 'PDC_254_EXACT_253_CATALOG_STATE_REQUIRED' using errcode = '55000';
  end if;
end $guard$;

-- The gateway must already be stopped. These locks drain any old transaction that
-- entered a 253 RPC before containment and fail safely on unexpected contention.
lock table
  public.pdc_auditor_gateway_keys_253,
  public.pdc_auditor_signed_deliveries_253,
  public.pdc_auditor_signed_delivery_results_253,
  public.pdc_auditor_typed_plans_253,
  public.pdc_auditor_typed_plan_items_253,
  public.pdc_auditor_typed_runs_253,
  public.pdc_auditor_typed_scope_receipts_253,
  public.pdc_auditor_typed_change_receipts_253,
  public.pdc_auditor_typed_undo_receipts_253,
  public.pdc_auditor_workshop_revisions,
  public.vehicle_workshop_line_adjustments,
  public.vehicle_work_items
in access exclusive mode;

-- Re-establish the exact private-object boundary even if ACL/RLS/policy drift
-- occurred after 253. These retained tables have no legitimate API policy;
-- containment removes every policy before enabling RLS and revoking all API ACLs.
-- FORCE RLS is applied after the audited owner-only key revocation below.
do $reharden_private_253$ declare t text; p record; begin
 foreach t in array array[
  'pdc_auditor_gateway_keys_253',
  'pdc_auditor_signed_deliveries_253',
  'pdc_auditor_signed_delivery_results_253',
  'pdc_auditor_typed_plans_253',
  'pdc_auditor_typed_plan_items_253',
  'pdc_auditor_typed_runs_253',
  'pdc_auditor_typed_scope_receipts_253',
  'pdc_auditor_typed_change_receipts_253',
  'pdc_auditor_typed_undo_receipts_253'
 ] loop
  for p in select polname from pg_policy where polrelid=format('public.%I',t)::regclass loop
   execute format('drop policy %I on public.%I',p.polname,t);
  end loop;
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on table public.%I from public,anon,authenticated,service_role',t);
 end loop;
end $reharden_private_253$;
revoke all on public.pdc_auditor_normalized_operation_lines_253 from public,anon,authenticated,service_role;

-- Append-only, non-secret record of every operational key transition.
create table public.pdc_auditor_gateway_key_revocations_254(
  gateway_instance_id text not null,
  key_id text not null,
  disabled_by_migration integer not null default 254 check(disabled_by_migration = 254),
  prior_valid_from timestamptz not null,
  prior_valid_until timestamptz not null,
  prior_provisioned_at timestamptz not null,
  revoked_at timestamptz not null default clock_timestamp(),
  reason text not null check(reason = 'migration_254_forward_only_containment'),
  primary key(gateway_instance_id, key_id),
  foreign key(gateway_instance_id, key_id)
    references public.pdc_auditor_gateway_keys_253(gateway_instance_id, key_id)
    on delete restrict
);
alter table public.pdc_auditor_gateway_key_revocations_254 enable row level security;
revoke all on table public.pdc_auditor_gateway_key_revocations_254 from public, anon, authenticated, service_role;
create trigger pdc_auditor_gateway_key_revocations_254_immutable
before update or delete on public.pdc_auditor_gateway_key_revocations_254
for each row execute function public.pdc_auditor_reject_history_mutation();

insert into public.pdc_auditor_gateway_key_revocations_254(
  gateway_instance_id, key_id, prior_valid_from, prior_valid_until,
  prior_provisioned_at, revoked_at, reason
)
select gateway_instance_id, key_id, valid_from, valid_until,
       provisioned_at, clock_timestamp(), 'migration_254_forward_only_containment'
from public.pdc_auditor_gateway_keys_253
where active or revoked_at is null;

-- 253 made the key table wholly immutable even though active/revoked_at are lifecycle
-- fields. The owner-only migration performs the one audited revocation transition,
-- then restores the immutable trigger before commit. No key bytes or rows are deleted.
drop trigger pdc_auditor_gateway_keys_253_immutable on public.pdc_auditor_gateway_keys_253;
update public.pdc_auditor_gateway_keys_253 k
set active = false,
    revoked_at = r.revoked_at
from public.pdc_auditor_gateway_key_revocations_254 r
where r.gateway_instance_id = k.gateway_instance_id
  and r.key_id = k.key_id;
create trigger pdc_auditor_gateway_keys_253_immutable
before update or delete on public.pdc_auditor_gateway_keys_253
for each row execute function public.pdc_auditor_reject_history_mutation();

-- Fail closed even for an accidental later ACL grant or owner invocation. The original
-- reviewed bodies remain recoverable from immutable migration-253 source, but are not
-- callable again without a later forward migration deliberately restoring/replacing them.
create or replace function public.plan_pdc_auditor_typed_instruction_253(
  p_action text, p_mode text, p_selected_scope jsonb, p_gateway_envelope jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $disabled$
begin raise exception 'PDC_253_DISABLED_BY_MIGRATION_254' using errcode='55000'; end $disabled$;
create or replace function public.compose_pdc_auditor_typed_plan_253(
  p_proposals uuid[], p_gateway_envelope jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $disabled$
begin raise exception 'PDC_253_DISABLED_BY_MIGRATION_254' using errcode='55000'; end $disabled$;
create or replace function public.apply_pdc_auditor_typed_plan_253(
  p_proposal uuid, p_proposal_version integer, p_proposal_hash text,
  p_typed_item_set_hash text, p_final_scope_hash text,
  p_expected_row_versions_hash text, p_gateway_envelope jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $disabled$
begin raise exception 'PDC_253_DISABLED_BY_MIGRATION_254' using errcode='55000'; end $disabled$;
create or replace function public.undo_last_pdc_auditor_typed_run_253(
  p_gateway_envelope jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $disabled$
begin raise exception 'PDC_253_DISABLED_BY_MIGRATION_254' using errcode='55000'; end $disabled$;
create or replace function public.query_pdc_auditor_typed_253(
  p_action text, p_scope jsonb, p_gateway_envelope jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $disabled$
begin raise exception 'PDC_253_DISABLED_BY_MIGRATION_254' using errcode='55000'; end $disabled$;

-- Remove every API-role execution path, including helpers, not only the five PostgREST RPCs.
revoke all on function public.pdc_auditor_seal_only_253() from public, anon, authenticated, service_role;
revoke all on function public.pdc_auditor_typed_snapshot_253(uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.pdc_auditor_canonical_json_253(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.pdc_auditor_signing_bytes_253(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.pdc_auditor_verify_envelope_253(text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean) from public, anon, authenticated, service_role;
revoke all on function public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.compose_pdc_auditor_typed_plan_253(uuid[],jsonb) from public, anon, authenticated, service_role;
revoke all on function public.pdc_auditor_recalculate_required_work_253(uuid[]) from public, anon, authenticated, service_role;
revoke all on function public.apply_pdc_auditor_typed_plan_253(uuid,integer,text,text,text,text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.undo_last_pdc_auditor_typed_run_253(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.query_pdc_auditor_typed_253(text,jsonb,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.pdc_auditor_human_admin_revision_read_253(text) from public, anon, authenticated, service_role;
grant execute on function public.pdc_auditor_human_admin_revision_read_253(text) to authenticated;

-- Preserve migration-229's shared legacy revision transport. Containment removes
-- typed-253 reads only: legacy 226 apply/rollback revisions remain visible to active
-- scoped human Administrators and the table stays in Realtime.
drop policy pdc_auditor_workshop_revisions_admin_read_253 on public.pdc_auditor_workshop_revisions;
revoke all on table public.pdc_auditor_workshop_revisions from public, anon, authenticated, service_role;
revoke all on sequence public.pdc_auditor_workshop_revisions_revision_id_seq from public, anon, authenticated, service_role;
grant select(revision_id,dealer_code,environment,event_type,run_id,rollback_receipt_id,created_at,typed_run_id_253) on public.pdc_auditor_workshop_revisions to authenticated;
create policy pdc_auditor_workshop_revisions_legacy_admin_read_254
on public.pdc_auditor_workshop_revisions for select to authenticated
using(environment='staging'
  and event_type in('telegram_plan_applied_226','telegram_run_rolled_back_226')
  and typed_run_id_253 is null
  and public.pdc_auditor_human_admin_revision_read_253(dealer_code));

create table public.pdc_auditor_disable_events_254(
  singleton boolean primary key check(singleton),
  project_ref text not null check(project_ref = 'cdsmnqxtyyoeoznmbidd'),
  disabled_version integer not null check(disabled_version = 253),
  disabled_name text not null check(disabled_name = 'ai_auditor_typed_operation_control'),
  disabled_by_version integer not null check(disabled_by_version = 254),
  disabled_at timestamptz not null default clock_timestamp(),
  deactivated_key_count integer not null check(deactivated_key_count >= 0),
  available_run_count integer not null check(available_run_count >= 0),
  retained_overlay_count integer not null check(retained_overlay_count >= 0),
  retained_scope_receipt_count integer not null check(retained_scope_receipt_count >= 0),
  retained_change_receipt_count integer not null check(retained_change_receipt_count >= 0),
  legacy_realtime_revision_membership_preserved boolean not null check(legacy_realtime_revision_membership_preserved),
  recovery_contract text not null check(recovery_contract = 'later_reviewed_forward_migration_only')
);
alter table public.pdc_auditor_disable_events_254 enable row level security;
revoke all on table public.pdc_auditor_disable_events_254 from public, anon, authenticated, service_role;
create trigger pdc_auditor_disable_events_254_immutable
before update or delete on public.pdc_auditor_disable_events_254
for each row execute function public.pdc_auditor_reject_history_mutation();

insert into public.pdc_auditor_disable_events_254(
  singleton, project_ref, disabled_version, disabled_name, disabled_by_version,
  deactivated_key_count, available_run_count, retained_overlay_count,
  retained_scope_receipt_count, retained_change_receipt_count,
  legacy_realtime_revision_membership_preserved, recovery_contract
)
select true, 'cdsmnqxtyyoeoznmbidd', 253, 'ai_auditor_typed_operation_control', 254,
       (select count(*) from public.pdc_auditor_gateway_key_revocations_254),
       (select count(*) from public.pdc_auditor_typed_runs_253 where undo_state = 'available'),
       (select count(*) from public.vehicle_workshop_line_adjustments where correction_origin in ('ai_auditor','ai_auditor_rolled_back')),
       (select count(*) from public.pdc_auditor_typed_scope_receipts_253),
       (select count(*) from public.pdc_auditor_typed_change_receipts_253),
       true, 'later_reviewed_forward_migration_only';

insert into supabase_migrations.schema_migrations(version, name, statements)
values(
  '254',
  'disable_ai_auditor_typed_operation_control',
  array[
    'exact staging project and exact migration-253 head/name/catalog guard',
    'drain 253 transactions under a stopped gateway and fail on lock contention',
    'append non-secret key revocation evidence and deactivate every 253 gateway key',
    'replace five public 253 RPC bodies with deterministic disabled stubs and revoke every 253 function from API roles',
    'replace typed revision reads with legacy-only Administrator policy and preserve migration-229 Realtime publication',
    'reharden and retain every 253 private table and normalized view with forced RLS, no policies, no API ACL, and unchanged evidence rows',
    'record immutable disable counts; recovery or re-enable requires a later reviewed forward migration'
  ]
);

do $postconditions$
declare
  v_role text;
  v_function text;
  v_table text;
  v_rls boolean;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    foreach v_function in array array[
      'public.pdc_auditor_seal_only_253()',
      'public.pdc_auditor_typed_snapshot_253(uuid,text)',
      'public.pdc_auditor_canonical_json_253(jsonb)',
      'public.pdc_auditor_signing_bytes_253(jsonb)',
      'public.pdc_auditor_verify_envelope_253(text,jsonb)',
      'public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean)',
      'public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb)',
      'public.compose_pdc_auditor_typed_plan_253(uuid[],jsonb)',
      'public.pdc_auditor_recalculate_required_work_253(uuid[])',
      'public.apply_pdc_auditor_typed_plan_253(uuid,integer,text,text,text,text,jsonb)',
      'public.undo_last_pdc_auditor_typed_run_253(jsonb)',
      'public.query_pdc_auditor_typed_253(text,jsonb,jsonb)'
    ] loop
      if has_function_privilege(v_role, v_function, 'EXECUTE') then
        raise exception 'PDC_254_FUNCTION_AUTHORITY_REMAINS role=% function=%', v_role, v_function using errcode = '55000';
      end if;
    end loop;
    if has_table_privilege(v_role, 'public.pdc_auditor_workshop_revisions', 'INSERT,UPDATE,DELETE')
       or (v_role <> 'authenticated' and has_table_privilege(v_role, 'public.pdc_auditor_workshop_revisions', 'SELECT')) then
      raise exception 'PDC_254_REVISION_AUTHORITY_REMAINS role=%', v_role using errcode = '55000';
    end if;
  end loop;

  foreach v_table in array array[
    'pdc_auditor_gateway_keys_253',
    'pdc_auditor_signed_deliveries_253',
    'pdc_auditor_signed_delivery_results_253',
    'pdc_auditor_typed_plans_253',
    'pdc_auditor_typed_plan_items_253',
    'pdc_auditor_typed_runs_253',
    'pdc_auditor_typed_scope_receipts_253',
    'pdc_auditor_typed_change_receipts_253',
    'pdc_auditor_typed_undo_receipts_253'
  ] loop
    select relrowsecurity into v_rls
    from pg_class where oid=format('public.%I',v_table)::regclass;
    if not v_rls
       or exists(select 1 from pg_policy where polrelid=format('public.%I',v_table)::regclass) then
      raise exception 'PDC_254_PRIVATE_TABLE_RLS_OR_POLICY_REMAINS table=%', v_table using errcode = '55000';
    end if;
    foreach v_role in array array['anon','authenticated','service_role'] loop
      if has_table_privilege(v_role, format('public.%I',v_table), 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'PDC_254_PRIVATE_TABLE_AUTHORITY_REMAINS role=% table=%', v_role, v_table using errcode = '55000';
      end if;
    end loop;
  end loop;
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if has_table_privilege(v_role, 'public.pdc_auditor_normalized_operation_lines_253', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
      raise exception 'PDC_254_PRIVATE_VIEW_AUTHORITY_REMAINS role=%', v_role using errcode = '55000';
    end if;
  end loop;

  if exists(select 1 from public.pdc_auditor_gateway_keys_253 where active or revoked_at is null)
     or (select count(*) from pg_policies where schemaname='public' and tablename='pdc_auditor_workshop_revisions' and policyname='pdc_auditor_workshop_revisions_legacy_admin_read_254') <> 1
     or not has_function_privilege('authenticated','public.pdc_auditor_human_admin_revision_read_253(text)','EXECUTE')
     or not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pdc_auditor_workshop_revisions')
     or not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'vehicle_workshop_line_adjustments')
     or (select count(*) from supabase_migrations.schema_migrations where version = '254' and name = 'disable_ai_auditor_typed_operation_control') <> 1
     or (select count(*) from public.pdc_auditor_disable_events_254 where singleton) <> 1 then
    raise exception 'PDC_254_POSTCONDITION_FAILED' using errcode = '55000';
  end if;
end $postconditions$;

-- Apply FORCE only after all retained-row postconditions so this migration does
-- not depend on the executing owner having BYPASSRLS.
do $force_private_253$ declare t text; v_force boolean; begin
 foreach t in array array[
  'pdc_auditor_gateway_keys_253',
  'pdc_auditor_signed_deliveries_253',
  'pdc_auditor_signed_delivery_results_253',
  'pdc_auditor_typed_plans_253',
  'pdc_auditor_typed_plan_items_253',
  'pdc_auditor_typed_runs_253',
  'pdc_auditor_typed_scope_receipts_253',
  'pdc_auditor_typed_change_receipts_253',
  'pdc_auditor_typed_undo_receipts_253'
 ] loop
  execute format('alter table public.%I force row level security',t);
  select relforcerowsecurity into v_force from pg_class where oid=format('public.%I',t)::regclass;
  if not v_force then
   raise exception 'PDC_254_PRIVATE_TABLE_FORCE_RLS_FAILED table=%',t using errcode = '55000';
  end if;
 end loop;
end $force_private_253$;

notify pgrst, 'reload schema';
commit;
