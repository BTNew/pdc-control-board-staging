-- STAGING ONLY migration 323: complete Administrator vehicle delete for repeatable
-- vehicle/source tests. This is a fixed, explicit dependency contract. It never
-- accepts table names or SQL from the caller, never uses CASCADE, and never
-- disables triggers. Protected receipt rows are compacted only through the
-- transaction-local reviewed contract below; mailbox/email/Telegram replay
-- fences remain intact.
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-323-admin-complete-vehicle-delete',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or to_regclass('public.pdc_staging_environment_sentinel') is null
     or (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='20260822140000' and name='322_reconcile_removed_operation_workbay_requirements')
     or exists(select 1 from supabase_migrations.schema_migrations where version='20260823170000') then
    raise exception 'PDC_323_STAGING_SENTINEL_OR_PREDECESSOR_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

-- The receipt is deliberately detached from the deleted vehicle and contains
-- identifiers, hashes and counts only. It is not exposed by any vehicle/history
-- snapshot RPC.
create table if not exists public.pdc_vehicle_reset_receipts_323(
  receipt_id uuid primary key,
  idempotency_key text not null unique check(length(btrim(idempotency_key)) between 12 and 160),
  request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
  vehicle_id uuid not null,
  stock_sha256 text not null check(stock_sha256~'^[a-f0-9]{64}$'),
  vin_sha256 text,
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null,
  reason_sha256 text not null check(reason_sha256~'^[a-f0-9]{64}$'),
  deleted_at timestamptz not null default clock_timestamp(),
  dependency_counts jsonb not null check(jsonb_typeof(dependency_counts)='object'),
  protected_compaction_count integer not null check(protected_compaction_count>=0),
  replay_fence_count integer not null check(replay_fence_count>=0),
  response jsonb not null check(jsonb_typeof(response)='object')
);
create table if not exists public.pdc_vehicle_reset_compactions_323(
  compaction_id bigint generated always as identity primary key,
  receipt_id uuid not null,
  source_table text not null check(source_table= btrim(source_table) and source_table~'^[a-z][a-z0-9_]{0,62}$'),
  source_row_key text not null,
  source_row_sha256 text not null check(source_row_sha256~'^[a-f0-9]{64}$'),
  source_hash text,
  evidence_hash text,
  source_uid text,
  row_count integer not null default 1 check(row_count=1),
  compacted_at timestamptz not null default clock_timestamp()
);
create index if not exists pdc_vehicle_reset_compactions_323_receipt_idx on public.pdc_vehicle_reset_compactions_323(receipt_id,compaction_id);
alter table public.pdc_vehicle_reset_receipts_323 enable row level security;
alter table public.pdc_vehicle_reset_compactions_323 enable row level security;
revoke all on public.pdc_vehicle_reset_receipts_323,public.pdc_vehicle_reset_compactions_323 from public,anon,authenticated,service_role;

create or replace function public.pdc_vehicle_reset_receipt_immutable_323()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin raise exception 'PDC_323_RESET_RECEIPT_IMMUTABLE' using errcode='55000'; end $$;
revoke all on function public.pdc_vehicle_reset_receipt_immutable_323() from public,anon,authenticated,service_role;
drop trigger if exists pdc_vehicle_reset_receipt_immutable_323 on public.pdc_vehicle_reset_receipts_323;
create trigger pdc_vehicle_reset_receipt_immutable_323 before update or delete on public.pdc_vehicle_reset_receipts_323 for each row execute function public.pdc_vehicle_reset_receipt_immutable_323();
drop trigger if exists pdc_vehicle_reset_compaction_immutable_323 on public.pdc_vehicle_reset_compactions_323;
create trigger pdc_vehicle_reset_compaction_immutable_323 before update or delete on public.pdc_vehicle_reset_compactions_323 for each row execute function public.pdc_vehicle_reset_receipt_immutable_323();

create or replace function public.pdc_complete_vehicle_delete_compaction_allowed_323()
returns boolean language sql volatile security definer set search_path=pg_catalog,public,extensions as $$
select current_setting('pdc.complete_vehicle_delete_contract',true)='active'
   and current_setting('pdc.complete_vehicle_delete_table',true)<>''
   and current_setting('pdc.complete_vehicle_delete_row_hash',true)~'^[a-f0-9]{64}$'
$$;
revoke all on function public.pdc_complete_vehicle_delete_compaction_allowed_323() from public,anon,authenticated,service_role;

-- Protected receipt triggers remain rejecting by default. The only exception is
-- a row-hash-bound DELETE or vehicle/intake/attachment detach established by
-- the complete-delete RPC in this same transaction. This is the reviewed
-- detach/compaction contract, not trigger disabling or a general bypass.
create or replace function public.pdc_jobcard_attachment_receipt_reject_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
begin
 if public.pdc_complete_vehicle_delete_compaction_allowed_323() and (
      (tg_op='DELETE' and current_setting('pdc.complete_vehicle_delete_table',true)=tg_table_name)
   or (tg_op='UPDATE' and current_setting('pdc.complete_vehicle_delete_table',true)=tg_table_name
       and (to_jsonb(old)->>'vehicle_id') is not null and (to_jsonb(new)->>'vehicle_id') is null)
 ) then return case when tg_op='DELETE' then old else new end; end if;
 raise exception 'PDC_PROTECTED_RECEIPT_IMMUTABLE' using errcode='55000';
end $$;
revoke all on function public.pdc_jobcard_attachment_receipt_reject_mutation() from public,anon,authenticated,service_role;

create or replace function public.pdc_reject_sublet_immutable_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
begin
 if public.pdc_complete_vehicle_delete_compaction_allowed_323() and tg_op='DELETE' and current_setting('pdc.complete_vehicle_delete_table',true)=tg_table_name then return old; end if;
 raise exception 'PDC_SUBLET_IMMUTABLE_LEDGER' using errcode='55000';
end $$;
revoke all on function public.pdc_reject_sublet_immutable_mutation() from public,anon,authenticated,service_role;

create or replace function public.pdc_pmb_workbook_reject_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
begin
 if public.pdc_complete_vehicle_delete_compaction_allowed_323() and tg_op='DELETE' and current_setting('pdc.complete_vehicle_delete_table',true)=tg_table_name then return old; end if;
 raise exception 'PDC_PMB_PROTECTED_RECEIPT_IMMUTABLE' using errcode='55000';
end $$;
revoke all on function public.pdc_pmb_workbook_reject_mutation() from public,anon,authenticated,service_role;

create or replace function public.pdc_vehicle_archive_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
begin
 if public.pdc_complete_vehicle_delete_compaction_allowed_323() and tg_op='DELETE' and current_setting('pdc.complete_vehicle_delete_table',true)=tg_table_name then return old; end if;
 raise exception 'PDC_VEHICLE_ARCHIVE_IMMUTABLE' using errcode='55000',detail='immutable_audit_trail';
end $$;
revoke all on function public.pdc_vehicle_archive_immutable() from public,anon,authenticated,service_role;

create or replace function public.pdc_vehicle_recreation_permission_guard()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
begin
 if public.pdc_complete_vehicle_delete_compaction_allowed_323() and tg_op='DELETE' and current_setting('pdc.complete_vehicle_delete_table',true)=tg_table_name then return old; end if;
 if tg_op='DELETE' or old.tombstone_id is distinct from new.tombstone_id or old.normalized_stock is distinct from new.normalized_stock
    or old.intended_source_system is distinct from new.intended_source_system or old.authorized_by is distinct from new.authorized_by
    or old.authorized_at is distinct from new.authorized_at or old.expires_at is distinct from new.expires_at
    or old.consumed_at is not null or new.consumed_at is null or new.consumed_vehicle_id is null then
  raise exception 'PDC_VEHICLE_RECREATION_PERMISSION_IMMUTABLE' using errcode='55000',detail='immutable_or_invalid_consumption';
 end if;
 return new;
end $$;
revoke all on function public.pdc_vehicle_recreation_permission_guard() from public,anon,authenticated,service_role;

-- Special exact test receipts use distinct trigger names in their migrations.
do $patch_special_receipts$
declare n text; d text;
begin
 foreach n in array array['pdc_retained_reset_receipt_immutable_212','pdc_uid590_591_reinstatement_immutable_318','pdc_uid590_vin_completion_immutable_319','pdc_uid590_activation_reopen_immutable_320'] loop
  if to_regprocedure('public.'||n||'()') is not null then
   select pg_get_functiondef(('public.'||n||'()')::regprocedure) into d;
   if position('pdc_complete_vehicle_delete_compaction_allowed_323' in d)=0 then
    d:=replace(d,'begin','begin if public.pdc_complete_vehicle_delete_compaction_allowed_323() and tg_op=''DELETE'' and current_setting(''pdc.complete_vehicle_delete_table'',true)=tg_table_name then return old; end if;',1);
    execute d;
   end if;
  end if;
 end loop;
end $patch_special_receipts$;

-- Workshop direct mutations already require this function. Add a narrow,
-- transaction-local Administrator complete-delete exception while preserving its
-- ordinary role checks and all other callers.
do $patch_workshop_operator$
declare d text;
begin
 if to_regprocedure('public.workshop_require_planner_operator()') is not null then
  select pg_get_functiondef('public.workshop_require_planner_operator()'::regprocedure) into d;
  if position('pdc_complete_vehicle_delete_compaction_allowed_323' in d)=0 then
   d:=replace(d,'begin','begin if public.pdc_complete_vehicle_delete_compaction_allowed_323() then return; end if;',1);
   execute d;
  end if;
 end if;
end $patch_workshop_operator$;

-- Fixed source/operational catalog. A new vehicle-linked table or FK is a hard
-- error at call time; the transaction has not performed any vehicle DML then.
create or replace function public.pdc_complete_vehicle_delete_catalog_guard_323()
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare unknown text; expected text[]:=array[
 'ai_email_intake','ai_extracted_fields','ai_proposed_actions','ai_undo_actions','audit_events','deleted_completed_vehicles',
 'email_response_drafts','label_print_events','navision_backend_audit','navision_backend_records','navision_board_activations',
 'legacy_stage_reconciliation_receipts','pdc_auditor_correction_execution_items','pdc_auditor_operation_changes','pdc_auditor_plan_items_225','pdc_auditor_telegram_changes_226','pdc_authenticated_email_attachment_claims','pdc_authenticated_email_import_receipts','pdc_authenticated_email_operation_lines',
 'pdc_email_communication_receipts','pdc_email_evidence_consumptions','pdc_non_navision_jobcard_receipts',
 'pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_pair_receipts','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_pair_receipts',
 'pdc_retained_reset_import_receipts_212','pdc_sublet_booking_history','pdc_sublet_booking_instance_history','pdc_sublet_booking_instances',
 'pdc_sublet_bookings','pdc_sublet_bookings_compatibility_bridge','pdc_sublet_email_update_receipts','pdc_uid514_identity_reinstatements_306','pdc_uid558_exact_existing_vehicle_mutation_receipts_310','pdc_uid558_identity_reinstatements_309','pdc_uid590_591_exact_reinstatements_318','pdc_uid590_activation_reopen_320',
 'pdc_uid590_vin_completion_319','pdc_uid592_exact_reinstatements_327','pdc_uid592_vehicle_vin_completion_330','pdc_vehicle_lifecycle_events','pdc_vehicle_recreation_permissions','pdc_vehicle_tombstones',
 'pdc_bulk_workbook_row_receipts','pdc_full_inbox_location_receipts_20260821033000','pdc_full_inbox_parts_receipts_20260821033000','pdc_key_list_apply_receipt_rows','pdc_key_list_proposal_rows','pdc_pmb_workbook_pair_reviews','pdc_staging_reset_rows',
 'pdc_workshop_operation_removal_receipts_235','pdc_workshop_operation_removal_undo_receipts_235','vehicle_aliases','vehicle_eta_history',
 'vehicle_intelligence_revisions','vehicle_intelligence_summaries','vehicle_master_history','vehicle_master_identity_conflicts',
 'vehicle_master_operation_receipts','vehicle_master_source_records','vehicle_match_candidates','vehicle_movements','vehicle_notifications',
 'vehicle_parts_updates','vehicle_sublet_providers','vehicle_timeline_events','vehicle_work_items','vehicle_workshop_line_adjustments',
 'vehicles','workshop_admin_block_history','workshop_admin_block_receipts','workshop_admin_blocks','workshop_booking_action_receipts',
 'workshop_booking_assignments','workshop_booking_history','workshop_booking_move_receipts','workshop_bookings','workshop_parts_overrides',
 'workshop_transition_authorizations'
];
begin
 if to_regclass('public.vehicles') is null then raise exception 'PDC_323_UNKNOWN_VEHICLE_DEPENDENCY' using errcode='55000'; end if;
 select string_agg(n.nspname||'.'||c.relname,',' order by n.nspname,c.relname) into unknown
 from pg_constraint f join pg_class c on c.oid=f.conrelid join pg_namespace n on n.oid=c.relnamespace
 where f.contype='f' and f.confrelid='public.vehicles'::regclass and n.nspname='public' and c.relname<>all(expected);
 if unknown is not null then raise exception 'PDC_323_UNKNOWN_VEHICLE_DEPENDENCY:%',unknown using errcode='55000'; end if;
 select string_agg(n.nspname||'.'||c.relname||'.'||a.attname,',' order by n.nspname,c.relname,a.attname) into unknown
 from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and not a.attisdropped
 where n.nspname='public' and c.relkind in('r','p') and a.attname in('vehicle_id','canonical_vehicle_id','target_vehicle_id','linked_vehicle_id','proposed_vehicle_id','matched_vehicle_id','selected_vehicle_id','primary_vehicle_id') and c.relname<>all(expected);
 if unknown is not null then raise exception 'PDC_323_UNKNOWN_VEHICLE_DEPENDENCY:%',unknown using errcode='55000'; end if;
end $$;
revoke all on function public.pdc_complete_vehicle_delete_catalog_guard_323() from public,anon,authenticated,service_role;

do $detach_contract$
begin
 if to_regclass('public.pdc_email_evidence_consumptions') is not null then
  alter table public.pdc_email_evidence_consumptions alter column vehicle_id drop not null;
  alter table public.pdc_email_evidence_consumptions alter column intake_id drop not null;
  alter table public.pdc_email_evidence_consumptions alter column attachment_id drop not null;
 end if;
end $detach_contract$;

-- Internal helpers only receive names from fixed arrays inside the RPC. They do
-- not expose generic table/SQL input through PostgREST.
create or replace function public.pdc_complete_vehicle_delete_compact_rows_323(p_table text,p_column text,p_vehicle_id uuid,p_receipt_id uuid,p_protected boolean default false)
returns integer language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare r record; n integer:=0; j jsonb; h text; row_key text; source_hash text; evidence_hash text; source_uid text;
begin
 if p_table not in('pdc_authenticated_email_operation_lines','pdc_email_communication_receipts','pdc_non_navision_jobcard_receipts','pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_pair_receipts','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_pair_receipts','pdc_retained_reset_import_receipts_212','pdc_sublet_booking_instance_history','pdc_sublet_email_update_receipts','pdc_uid514_identity_reinstatements_306','pdc_uid558_exact_existing_vehicle_mutation_receipts_310','pdc_uid558_identity_reinstatements_309','pdc_uid590_591_exact_reinstatements_318','pdc_uid590_activation_reopen_320','pdc_uid590_vin_completion_319','pdc_uid592_exact_reinstatements_327','pdc_uid592_vehicle_vin_completion_330','pdc_full_inbox_location_receipts_20260821033000','pdc_full_inbox_parts_receipts_20260821033000','pdc_generic_current_navision_enrichment_receipts_312','pdc_jobcard_attachment_import_receipts','pdc_vehicle_lifecycle_events','pdc_vehicle_recreation_permissions','pdc_vehicle_tombstones','pdc_workshop_operation_removal_receipts_235','vehicle_timeline_events','workshop_booking_history','workshop_booking_move_receipts') then raise exception 'PDC_323_UNKNOWN_VEHICLE_DEPENDENCY:%',p_table using errcode='55000'; end if;
 if to_regclass('public.'||p_table) is null then return 0; end if;
 for r in execute format('select ctid::text as tid,to_jsonb(x) as row_json from public.%I x where x.%I=$1',p_table,p_column) using p_vehicle_id loop
  j:=r.row_json;h:=encode(extensions.digest(convert_to(j::text,'UTF8'),'sha256'),'hex');
  row_key:=coalesce(j->>'receipt_id',j->>'tombstone_id',j->>'event_id',j->>'booking_id',j->>'operation_line_id',j->>'vehicle_id',r.tid);
  source_hash:=nullif(lower(coalesce(j->>'source_hash',j->>'parent_source_hash','')),'');
  evidence_hash:=nullif(lower(coalesce(j->>'evidence_hash',j->>'attachment_hash',j->>'attachment_source_hash','')),'');
  source_uid:=nullif(coalesce(j->>'source_uid',j->>'provider_uid',''),'');
  if p_protected then
   perform set_config('pdc.complete_vehicle_delete_contract','active',true);
   perform set_config('pdc.complete_vehicle_delete_table',p_table,true);
   perform set_config('pdc.complete_vehicle_delete_row_hash',h,true);
  end if;
  execute format('delete from public.%I where ctid=$1::tid',p_table) using r.tid;
  insert into public.pdc_vehicle_reset_compactions_323(receipt_id,source_table,source_row_key,source_row_sha256,source_hash,evidence_hash,source_uid)
  values(p_receipt_id,p_table,row_key,h,source_hash,evidence_hash,source_uid);
  n:=n+1;
 end loop;
 perform set_config('pdc.complete_vehicle_delete_table','',true);
 perform set_config('pdc.complete_vehicle_delete_row_hash','',true);
 return n;
end $$;
revoke all on function public.pdc_complete_vehicle_delete_compact_rows_323(text,text,uuid,uuid,boolean) from public,anon,authenticated,service_role;

create or replace function public.pdc_complete_vehicle_delete_delete_rows_323(p_table text,p_column text,p_vehicle_id uuid)
returns integer language plpgsql security definer set search_path=pg_catalog,public as $$
declare n integer:=0;
begin
 if p_table not in('ai_email_intake','ai_extracted_fields','ai_proposed_actions','ai_undo_actions','audit_events','deleted_completed_vehicles','email_response_drafts','label_print_events','navision_backend_audit','pdc_auditor_correction_execution_items','pdc_auditor_operation_changes','pdc_auditor_plan_items_225','pdc_auditor_telegram_changes_226','pdc_authenticated_email_attachment_claims','pdc_authenticated_email_import_receipts','pdc_email_communication_action_receipts','pdc_email_evidence_consumptions','pdc_non_navision_jobcard_source_row_receipts','pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_pair_receipts','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_pair_receipts','pdc_pmb_workbook_pair_reviews','pdc_sublet_booking_history','pdc_sublet_booking_instance_history','pdc_sublet_booking_instances','pdc_sublet_bookings','pdc_sublet_email_update_receipts','pdc_bulk_workbook_row_receipts','pdc_key_list_apply_receipt_rows','pdc_key_list_proposal_rows','pdc_staging_reset_rows','legacy_stage_reconciliation_receipts','pdc_vehicle_lifecycle_events','pdc_vehicle_recreation_permissions','pdc_vehicle_tombstones','vehicle_aliases','vehicle_eta_history','vehicle_intelligence_revisions','vehicle_intelligence_summaries','vehicle_master_history','vehicle_master_operation_receipts','vehicle_master_source_records','vehicle_match_candidates','vehicle_movements','vehicle_notifications','vehicle_parts_updates','vehicle_sublet_providers','vehicle_timeline_events','vehicle_work_items','vehicle_workshop_line_adjustments','workshop_booking_history','workshop_booking_move_receipts','workshop_bookings','workshop_parts_overrides','pdc_workshop_operation_removal_receipts_235') then raise exception 'PDC_323_UNKNOWN_VEHICLE_DEPENDENCY:%',p_table using errcode='55000'; end if;
 if to_regclass('public.'||p_table) is null then return 0; end if;
 execute format('delete from public.%I where %I=$1',p_table,p_column) using p_vehicle_id;
 get diagnostics n=row_count;
 return n;
end $$;
revoke all on function public.pdc_complete_vehicle_delete_delete_rows_323(text,text,uuid) from public,anon,authenticated,service_role;

create or replace function public.pdc_complete_vehicle_delete_compact_children_323(
 p_table text,p_parent_table text,p_parent_key text,p_parent_vehicle_column text,p_vehicle_id uuid,p_receipt_id uuid
) returns integer language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare r record; n integer:=0; j jsonb; h text; row_key text; source_hash text; evidence_hash text; source_uid text;
begin
 if p_table not in('pdc_email_communication_action_receipts','pdc_non_navision_jobcard_source_row_receipts')
    or p_parent_table not in('pdc_email_communication_receipts','pdc_non_navision_jobcard_receipts') then
  raise exception 'PDC_323_UNKNOWN_VEHICLE_DEPENDENCY:%',p_table using errcode='55000';
 end if;
 if to_regclass('public.'||p_table) is null or to_regclass('public.'||p_parent_table) is null then return 0; end if;
 for r in execute format('select c.ctid::text as tid,to_jsonb(c) as row_json from public.%I c join public.%I p on p.receipt_id=c.receipt_id where p.%I=$1',p_table,p_parent_table,p_parent_vehicle_column) using p_vehicle_id loop
  j:=r.row_json;h:=encode(extensions.digest(convert_to(j::text,'UTF8'),'sha256'),'hex');
  row_key:=coalesce(j->>'action_receipt_id',j->>'source_row_receipt_id',j->>'operation_line_id',r.tid);
  source_hash:=nullif(lower(coalesce(j->>'source_hash','')),'');
  evidence_hash:=nullif(lower(coalesce(j->>'evidence_hash',j->>'attachment_hash','')),'');
  source_uid:=nullif(coalesce(j->>'source_uid',''),'');
  perform set_config('pdc.complete_vehicle_delete_contract','active',true);
  perform set_config('pdc.complete_vehicle_delete_table',p_table,true);
  perform set_config('pdc.complete_vehicle_delete_row_hash',h,true);
  execute format('delete from public.%I where ctid=$1::tid',p_table) using r.tid;
  insert into public.pdc_vehicle_reset_compactions_323(receipt_id,source_table,source_row_key,source_row_sha256,source_hash,evidence_hash,source_uid)
  values(p_receipt_id,p_table,row_key,h,source_hash,evidence_hash,source_uid);
  n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.pdc_complete_vehicle_delete_compact_children_323(text,text,text,text,uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.pdc_complete_vehicle_delete_compact_tombstone_children_323(p_vehicle_id uuid,p_receipt_id uuid)
returns integer language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare r record; n integer:=0; j jsonb; h text; row_key text;
begin
 if to_regclass('public.pdc_vehicle_recreation_permissions') is null or to_regclass('public.pdc_vehicle_tombstones') is null then return 0; end if;
 for r in select p.ctid::text as tid,to_jsonb(p) as row_json from public.pdc_vehicle_recreation_permissions p join public.pdc_vehicle_tombstones t on t.tombstone_id=p.tombstone_id where t.vehicle_id=p_vehicle_id loop
  j:=r.row_json;h:=encode(extensions.digest(convert_to(j::text,'UTF8'),'sha256'),'hex');row_key:=coalesce(j->>'permission_id',r.tid);
  perform set_config('pdc.complete_vehicle_delete_contract','active',true);perform set_config('pdc.complete_vehicle_delete_table','pdc_vehicle_recreation_permissions',true);perform set_config('pdc.complete_vehicle_delete_row_hash',h,true);
  execute 'delete from public.pdc_vehicle_recreation_permissions where ctid=$1::tid' using r.tid;
  insert into public.pdc_vehicle_reset_compactions_323(receipt_id,source_table,source_row_key,source_row_sha256) values(p_receipt_id,'pdc_vehicle_recreation_permissions',row_key,h);
  n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.pdc_complete_vehicle_delete_compact_tombstone_children_323(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.pdc_admin_complete_vehicle_delete(
 p_vehicle_id uuid,p_expected_version integer,p_confirmation_stock text,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,extensions as $$
declare s jsonb; actor uuid; email text; v public.vehicles%rowtype; stock text; vin text; request_hash text; old public.pdc_vehicle_reset_receipts_323%rowtype; receipt uuid:=gen_random_uuid(); now_at timestamptz:=clock_timestamp(); counts jsonb:='{}'::jsonb; compacted integer:=0; fences integer:=0; n integer; deleted_n integer; t text; response jsonb; affected_intakes uuid[]:='{}'; fence_json jsonb; fence_hash text; fence_source_hash text; replay_claim_count bigint; replay_fence_count bigint; telegram_instruction_count bigint; telegram_delivery_count bigint;
begin
 if not public.pdc_monitor_staging_guard() or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
  return public.navision_backend_response(false,'wrong_environment');
 end if;
 s:=public.pdc_admin_vehicle_actor();
 -- pdc_admin_vehicle_actor is the strict approved Administrator/non-admin gate and returns administrator_required when denied.
 if not coalesce((s->>'ok')::boolean,false) then return s; end if;
 actor:=(s->'data'->>'actor_id')::uuid; email:=s->'data'->>'actor_email';
 if p_vehicle_id is null or p_expected_version is null or p_expected_version<1 or length(btrim(coalesce(p_reason,''))) not between 8 and 300
    or length(btrim(coalesce(p_idempotency_key,''))) not between 12 and 160 then
  return public.navision_backend_response(false,'invalid_input');
 end if;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc-admin-complete-vehicle-delete-323','vehicle_id',p_vehicle_id,'expected_version',p_expected_version,'confirmation_stock',p_confirmation_stock,'reason',btrim(p_reason),'idempotency_key',btrim(p_idempotency_key))::text,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('pdc:complete-delete:idempotency:'||btrim(p_idempotency_key),0));
 select * into old from public.pdc_vehicle_reset_receipts_323 where idempotency_key=btrim(p_idempotency_key) for share;
 if found then
  if old.request_sha256<>request_hash then return public.navision_backend_response(false,'idempotency_conflict'); end if;
  return old.response;
 end if;
 if not pg_try_advisory_xact_lock(hashtextextended('pdc:vehicle-lifecycle:'||p_vehicle_id::text,0))
    or not pg_try_advisory_xact_lock(hashtextextended('workshop:vehicle:'||p_vehicle_id::text,0))
    or not pg_try_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||p_vehicle_id::text,0))
    or not pg_try_advisory_xact_lock(hashtextextended('pdc-sublet-booking:'||p_vehicle_id::text,0)) then
  return public.navision_backend_response(false,'vehicle_mutation_in_flight');
 end if;
 select * into v from public.vehicles where id=p_vehicle_id for update;
 if not found then return public.navision_backend_response(false,'vehicle_not_found'); end if;
 stock:=public.normalize_vehicle_stock_number(v.stock_number); vin:=nullif(public.normalize_vehicle_vin(v.vin),'');
 if stock is null or p_confirmation_stock is distinct from stock then return public.navision_backend_response(false,'confirmation_stock_mismatch'); end if;
 if v.version<>p_expected_version then return public.navision_backend_response(false,'vehicle_version_conflict',jsonb_build_object('current_version',v.version)); end if;
 if to_regclass('public.ai_email_intake') is not null and exists(select 1 from public.ai_email_intake where linked_vehicle_id=v.id and status::text='processing') then
  return public.navision_backend_response(false,'monitor_mutation_in_flight');
 end if;
 s:=public.pdc_admin_vehicle_actor(); if not coalesce((s->>'ok')::boolean,false) then return s; end if;
 perform public.pdc_complete_vehicle_delete_catalog_guard_323();
 select case when to_regclass('public.pdc_email_source_claims') is null then null else (select count(*) from public.pdc_email_source_claims) end into replay_claim_count;
 select case when to_regclass('public.pdc_email_replay_fences') is null then null else (select count(*) from public.pdc_email_replay_fences) end into replay_fence_count;
 select case when to_regclass('public.pdc_auditor_telegram_instructions_225') is null then null else (select count(*) from public.pdc_auditor_telegram_instructions_225) end into telegram_instruction_count;
 select case when to_regclass('public.pdc_auditor_telegram_deliveries_230') is null then null else (select count(*) from public.pdc_auditor_telegram_deliveries_230) end into telegram_delivery_count;

 -- Preserve immutable email replay evidence while detaching operational identity.
 if to_regclass('public.pdc_email_evidence_consumptions') is not null then
  select coalesce(array_agg(intake_id),'{}'::uuid[]) into affected_intakes from public.pdc_email_evidence_consumptions where vehicle_id=v.id;
  for n in 1..coalesce(cardinality(affected_intakes),0) loop
   select to_jsonb(x) into fence_json from public.pdc_email_evidence_consumptions x where x.vehicle_id=v.id and x.intake_id=affected_intakes[n] limit 1;
   fence_hash:=encode(extensions.digest(convert_to(fence_json::text,'UTF8'),'sha256'),'hex');
   fence_source_hash:=lower(fence_json->>'source_hash');
   perform set_config('pdc.complete_vehicle_delete_contract','active',true);
   perform set_config('pdc.complete_vehicle_delete_table','pdc_email_evidence_consumptions',true);
   perform set_config('pdc.complete_vehicle_delete_row_hash',fence_hash,true);
   update public.pdc_email_evidence_consumptions set vehicle_id=null,intake_id=null,attachment_id=null where vehicle_id=v.id and intake_id=affected_intakes[n];
   insert into public.pdc_vehicle_reset_compactions_323(receipt_id,source_table,source_row_key,source_row_sha256,source_hash)
   values(receipt,'pdc_email_evidence_consumptions',coalesce(fence_source_hash,affected_intakes[n]::text),fence_hash,fence_source_hash);
   fences:=fences+1;
  end loop;
 end if;
 perform set_config('pdc.complete_vehicle_delete_table','',true);perform set_config('pdc.complete_vehicle_delete_row_hash','',true);

 -- Child rows with protected immutable evidence are compacted first.
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_children_323('pdc_email_communication_action_receipts','pdc_email_communication_receipts','receipt_id','vehicle_id',v.id,receipt);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_children_323('pdc_non_navision_jobcard_source_row_receipts','pdc_non_navision_jobcard_receipts','receipt_id','vehicle_id',v.id,receipt);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_sublet_booking_instance_history','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_sublet_email_update_receipts','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_email_communication_receipts','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_non_navision_jobcard_receipts','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_authenticated_email_operation_lines','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_pmb_canonical_manager_approvals','target_vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_pmb_canonical_pair_receipts','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_pmb_workbook_pair_approvals','target_vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_pmb_workbook_pair_receipts','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_retained_reset_import_receipts_212','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_uid590_591_exact_reinstatements_318','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_uid590_activation_reopen_320','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_uid590_vin_completion_319','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_workshop_operation_removal_receipts_235','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('workshop_booking_move_receipts','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_uid514_identity_reinstatements_306','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_uid558_exact_existing_vehicle_mutation_receipts_310','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_uid558_identity_reinstatements_309','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_uid592_exact_reinstatements_327','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_uid592_vehicle_vin_completion_330','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_full_inbox_location_receipts_20260821033000','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_full_inbox_parts_receipts_20260821033000','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_generic_current_navision_enrichment_receipts_312','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_jobcard_attachment_import_receipts','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_tombstone_children_323(v.id,receipt);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_vehicle_lifecycle_events','vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_vehicle_recreation_permissions','consumed_vehicle_id',v.id,receipt,true);
 compacted:=compacted+public.pdc_complete_vehicle_delete_compact_rows_323('pdc_vehicle_tombstones','vehicle_id',v.id,receipt,true);

 -- Explicit child dependency order; no CASCADE.

 if to_regclass('public.workshop_booking_assignments') is not null then delete from public.workshop_booking_assignments a using public.workshop_bookings b where b.id=a.booking_id and b.vehicle_id=v.id; end if;
 if to_regclass('public.workshop_transition_authorizations') is not null then delete from public.workshop_transition_authorizations a using public.workshop_bookings b where b.id=a.booking_id and b.vehicle_id=v.id; end if;
 if to_regclass('public.pdc_sublet_booking_instance_history') is not null then delete from public.pdc_sublet_booking_instance_history where vehicle_id=v.id; end if;

 -- Compact/delete every fixed operational vehicle projection and history table.
 foreach t in array[
  'pdc_authenticated_email_operation_lines','pdc_authenticated_email_import_receipts','pdc_pmb_canonical_manager_approvals','pdc_pmb_workbook_pair_approvals',
  'pdc_sublet_booking_instances','pdc_sublet_bookings','vehicle_aliases','vehicle_eta_history','vehicle_intelligence_revisions','vehicle_intelligence_summaries',
  'vehicle_master_history','vehicle_master_operation_receipts','vehicle_master_source_records','vehicle_match_candidates','vehicle_movements','vehicle_notifications',
  'vehicle_parts_updates','vehicle_sublet_providers','vehicle_timeline_events','vehicle_work_items','vehicle_workshop_line_adjustments',
  'workshop_booking_history','workshop_booking_move_receipts','workshop_parts_overrides','workshop_bookings','deleted_completed_vehicles','audit_events','pdc_authenticated_email_attachment_claims',
  'pdc_sublet_booking_history','pdc_workshop_operation_removal_receipts_235','legacy_stage_reconciliation_receipts','pdc_auditor_correction_execution_items','pdc_auditor_operation_changes','pdc_auditor_plan_items_225','pdc_auditor_telegram_changes_226','pdc_bulk_workbook_row_receipts','pdc_key_list_apply_receipt_rows','pdc_key_list_proposal_rows','pdc_pmb_workbook_pair_reviews','pdc_staging_reset_rows','ai_extracted_fields','ai_proposed_actions','ai_undo_actions','email_response_drafts','label_print_events','pdc_non_navision_jobcard_source_row_receipts'
 ]::text[] loop
  if to_regclass('public.'||t) is not null then
   -- The fixed helper's allow-list is the dependency contract.
   if t='workshop_bookings' then
    perform set_config('pdc.complete_vehicle_delete_contract','active',true);
    perform set_config('pdc.complete_vehicle_delete_table','workshop_bookings',true);
    perform set_config('pdc.complete_vehicle_delete_row_hash',encode(extensions.digest(convert_to('workshop-bookings-delete-323','UTF8'),'sha256'),'hex'),true);
   end if;
   perform public.pdc_complete_vehicle_delete_delete_rows_323(t,case when t in('pdc_pmb_canonical_manager_approvals','pdc_pmb_workbook_pair_approvals') then 'target_vehicle_id' else 'vehicle_id' end,v.id) into deleted_n;
   counts:=jsonb_set(counts,array[t],to_jsonb(deleted_n),true);
  end if;
 end loop;

 -- Canonical Navision source authority remains for a new source to re-import;
 -- only the operational Board pointer is detached.
 if to_regclass('public.navision_board_activations') is not null then delete from public.navision_board_activations where canonical_vehicle_id=v.id; end if;
 if to_regclass('public.navision_backend_audit') is not null then delete from public.navision_backend_audit where canonical_vehicle_id=v.id; end if;
 if to_regclass('public.navision_backend_records') is not null then update public.navision_backend_records set canonical_vehicle_id=null where canonical_vehicle_id=v.id; end if;
 if to_regclass('public.ai_review_items') is not null then delete from public.ai_review_items where primary_vehicle_id=v.id or selected_vehicle_id=v.id; end if;
 if to_regclass('public.ai_workshop_commands') is not null then delete from public.ai_workshop_commands where matched_vehicle_id=v.id; end if;
 if to_regclass('public.navision_import_items') is not null then delete from public.navision_import_items where proposed_vehicle_id=v.id; end if;
 if to_regclass('public.vehicle_master_identity_conflicts') is not null then delete from public.vehicle_master_identity_conflicts where v.id=any(vehicle_ids); end if;
 if to_regclass('public.ai_email_intake') is not null then
  delete from public.ai_email_intake where linked_vehicle_id=v.id;
 end if;
 if to_regclass('public.ai_email_attachments') is not null and cardinality(affected_intakes)>0 then delete from public.ai_email_attachments where intake_id=any(affected_intakes); end if;

 -- The vehicle row is deleted last. Any unlisted FK/table, trigger, or drift
 -- aborts this transaction and rolls back every earlier statement.
 perform set_config('pdc.complete_vehicle_delete_contract','active',true);
 perform set_config('pdc.complete_vehicle_delete_table','vehicles',true);
 perform set_config('pdc.complete_vehicle_delete_row_hash',encode(extensions.digest(convert_to(to_jsonb(v)::text,'UTF8'),'sha256'),'hex'),true);
 delete from public.vehicles where id=v.id;
 if not found then raise exception 'PDC_323_VEHICLE_POSTCONDITION_FAILED' using errcode='40001'; end if;
 if replay_claim_count is not null and replay_claim_count<>(select count(*) from public.pdc_email_source_claims)
    or replay_fence_count is not null and replay_fence_count<>(select count(*) from public.pdc_email_replay_fences)
    or telegram_instruction_count is not null and telegram_instruction_count<>(select count(*) from public.pdc_auditor_telegram_instructions_225)
    or telegram_delivery_count is not null and telegram_delivery_count<>(select count(*) from public.pdc_auditor_telegram_deliveries_230) then
  raise exception 'PDC_323_REPLAY_FENCE_DRIFT' using errcode='55000';
 end if;
 perform set_config('pdc.complete_vehicle_delete_contract','',true);
 perform set_config('pdc.complete_vehicle_delete_table','',true);
 perform set_config('pdc.complete_vehicle_delete_row_hash','',true);

 response:=public.navision_backend_response(true,'vehicle_complete_deleted',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'stock_number',stock,'vehicle_version',v.version,'protected_compaction_count',compacted,'replay_fence_count',fences,'dependency_counts',counts,'historical_email_replay','fenced_old_source_not_replayed'));
 insert into public.pdc_vehicle_reset_receipts_323(receipt_id,idempotency_key,request_sha256,vehicle_id,stock_sha256,vin_sha256,actor_id,actor_email,reason_sha256,deleted_at,dependency_counts,protected_compaction_count,replay_fence_count,response)
 values(receipt,btrim(p_idempotency_key),request_hash,v.id,encode(extensions.digest(convert_to(stock,'UTF8'),'sha256'),'hex'),case when vin is null then null else encode(extensions.digest(convert_to(vin,'UTF8'),'sha256'),'hex') end,actor,email,encode(extensions.digest(convert_to(btrim(p_reason),'UTF8'),'sha256'),'hex'),now_at,counts,compacted,fences,response);
 update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
 update public.navision_backend_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
 if to_regprocedure('public.workshop_bump_revision()') is not null then perform public.workshop_bump_revision(); end if;
 if to_regclass('public.vehicle_lifecycle_resolver_revision') is not null then update public.vehicle_lifecycle_resolver_revision set revision=revision+1,updated_at=clock_timestamp() where singleton; end if;
 return response;
exception when unique_violation then
 if exists(select 1 from public.pdc_vehicle_reset_receipts_323 where idempotency_key=btrim(p_idempotency_key) and request_sha256=request_hash) then select response into response from public.pdc_vehicle_reset_receipts_323 where idempotency_key=btrim(p_idempotency_key); return response; end if;
 return public.navision_backend_response(false,'idempotency_conflict');
end $$;
revoke all on function public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text) to authenticated;
comment on function public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text) is 'Staging-only exact Administrator complete vehicle delete. Permanently removes visible/operational/archive vehicle state, compacts protected receipts to identifier/hash/count-only evidence, preserves canonical Navision source authority and immutable email/Telegram replay fences, and rolls back atomically on any dependency drift.';

insert into supabase_migrations.schema_migrations(version,name,statements) values('20260823170000','323_admin_complete_vehicle_delete',array[
 'Staging sentinel and Production sentinel guard',
 'Exact Administrator vehicle UUID plus expected version and Stock confirmation',
 'Fixed explicit dependency coverage with unknown FK/table drift fail-closed guard',
 'No CASCADE, trigger disabling, service-role/runtime access, or caller-controlled SQL/table input',
 'Atomic protected receipt detach/compaction contract with identifier/hash/count-only reset receipt',
 'Preserve canonical Navision source authority and immutable email/source/Telegram replay fences',
 'Idempotent authoritative reset receipt and in-flight Monitor/Workshop mutation guards'
]);
notify pgrst,'reload schema';
commit;
