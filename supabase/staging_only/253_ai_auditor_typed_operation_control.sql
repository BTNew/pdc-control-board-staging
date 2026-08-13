-- Staging-only migration 253: signed typed operation Apply/Undo.
-- Install only through the exact-SHA guarded staging installer after independent approval.
-- Migration 251 remains untouched/unapplied; rejected migration 252 is not a predecessor.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or to_regclass('supabase_migrations.schema_migrations') is null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='250' and name='revoke_service_role_legacy_workshop_rpc' and statements=array['staging-only forward closure: legacy scheduling RPCs denied to public, anon, authenticated and service_role'])
     or exists(select 1 from supabase_migrations.schema_migrations where version='252')
     or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::integer>250)
     or exists(select 1 from supabase_migrations.schema_migrations where version='253') then
    raise exception 'PDC_253_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
  if to_regclass('public.vehicle_workshop_line_adjustments') is null
     or to_regclass('public.pdc_effective_operation_lines') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.audit_events') is null
     or to_regclass('public.pdc_auditor_workshop_revisions') is null
     or to_regclass('public.pdc_auditor_telegram_deliveries_230') is null
     or to_regprocedure('public.pdc_auditor_telegram_actor_scope_225(bigint)') is null
     or to_regprocedure('public.pdc_auditor_reject_history_mutation()') is null then
    raise exception 'PDC_253_DEPENDENCY_MISSING' using errcode='55000';
  end if;
end $guard$;

-- Migration 230 owns the one global Telegram delivery namespace. Extend its
-- source discriminator for typed deliveries while retaining the existing two
-- domains and both natural-key uniqueness constraints.
do $delivery_registry_shape$ declare c record; begin
 for c in select conname from pg_constraint where conrelid='public.pdc_auditor_telegram_deliveries_230'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%source_table%' loop
  execute format('alter table public.pdc_auditor_telegram_deliveries_230 drop constraint %I',c.conname);
 end loop;
 alter table public.pdc_auditor_telegram_deliveries_230 add constraint pdc_auditor_telegram_deliveries_source_253 check(source_table in('pdc_auditor_telegram_instructions_225','pdc_auditor_rule_commands_227','pdc_auditor_signed_deliveries_253'));
end $delivery_registry_shape$;

-- Empty after installation. Key provisioning is deliberately outside every API role and RPC.
create table public.pdc_auditor_gateway_keys_253(
 gateway_instance_id text not null,key_id text not null,hmac_key bytea not null check(octet_length(hmac_key)>=32),
 active boolean not null default true,valid_from timestamptz not null,valid_until timestamptz not null,
 provisioned_by uuid not null references auth.users(id) on delete restrict,provisioned_at timestamptz not null default clock_timestamp(),revoked_at timestamptz,
 primary key(gateway_instance_id,key_id),check(valid_until>valid_from),check((active and revoked_at is null) or (not active and revoked_at is not null)));
create table public.pdc_auditor_signed_deliveries_253(
 delivery_uuid uuid primary key,gateway_instance_id text not null,key_id text not null,nonce text not null check(length(nonce) between 16 and 200),
 issued_at timestamptz not null,expires_at timestamptz not null,instruction_sha256 text not null check(instruction_sha256~'^[a-f0-9]{64}$'),
 selected_scope jsonb not null check(jsonb_typeof(selected_scope)='object'),signature text not null check(signature~'^[a-f0-9]{64}$'),
 telegram_evidence jsonb not null check(jsonb_typeof(telegram_evidence)='object'),purpose text not null check(purpose in('plan','compose','apply','undo','query')),
 request_content_hash text not null check(request_content_hash~'^[a-f0-9]{64}$'),service_identity_id uuid not null,service_auth_user_id uuid not null,
 service_email text not null,authorizing_admin_user_id uuid not null,authorizing_admin_email text not null,dealer_code text not null check(dealer_code in('14450','37047')),
 received_at timestamptz not null default clock_timestamp(),unique(gateway_instance_id,key_id,nonce),
 foreign key(gateway_instance_id,key_id) references public.pdc_auditor_gateway_keys_253(gateway_instance_id,key_id) on delete restrict);
create table public.pdc_auditor_signed_delivery_results_253(delivery_uuid uuid primary key references public.pdc_auditor_signed_deliveries_253 on delete restrict,request_content_hash text not null,stored_result jsonb not null,recorded_at timestamptz not null default clock_timestamp());

create table public.pdc_auditor_typed_plans_253(
 plan_id uuid primary key default gen_random_uuid(),delivery_uuid uuid not null unique references public.pdc_auditor_signed_deliveries_253 on delete restrict,
 action text not null check(action in('add','edit','split','combine','reorder','remove_duplicate','mixed')),mode text not null check(mode in('review','apply')),
 selected_scope jsonb not null,selected_scope_hash text not null,instruction text not null,instruction_sha256 text not null,dealer_code text not null,
 operational_revision text not null,proposal_version integer not null default 1 check(proposal_version>=1),
 typed_item_set_hash text,final_scope jsonb,final_scope_hash text,expected_row_versions jsonb,expected_row_versions_hash text,proposal_hash text unique,
 item_count integer not null check(item_count between 1 and 250),
 proposed_count integer not null default 0,ambiguous_count integer not null default 0,review_only boolean not null,apply_unambiguous boolean not null,
 created_at timestamptz not null default clock_timestamp(),check(review_only=(mode='review')),check(proposed_count+ambiguous_count=item_count));
create table public.pdc_auditor_typed_plan_items_253(
 plan_item_id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.pdc_auditor_typed_plans_253 on delete restrict,
 sequence_no integer not null,operation_action text not null,disposition text not null check(disposition in('proposed','ambiguous')),
 vehicle_id uuid not null references public.vehicles(id) on delete restrict,stock_number text,job_card_number text not null,
 operation_identifier text not null,ordered_position integer not null,source_operation_identifiers text[] not null default '{}',survivor_operation_identifier text,
 old_effective_value jsonb,new_effective_value jsonb not null,reason text not null,server_rule_evidence jsonb not null,ambiguity_code text,
 created_at timestamptz not null default clock_timestamp(),unique(plan_id,sequence_no),check((disposition='ambiguous')=(ambiguity_code is not null)));
create table public.pdc_auditor_typed_runs_253(
 run_id uuid primary key default gen_random_uuid(),plan_id uuid not null unique references public.pdc_auditor_typed_plans_253 on delete restrict,
 apply_delivery_uuid uuid not null unique references public.pdc_auditor_signed_deliveries_253 on delete restrict,proposal_hash text not null,
 run_revision_before text not null,run_revision_after text not null,service_identity_id uuid not null,service_auth_user_id uuid not null,service_email text not null,
 authorizing_admin_user_id uuid not null,authorizing_admin_email text not null,gateway_instance_id text not null,key_id text not null,nonce text not null,
 exact_instruction text not null,instruction_sha256 text not null,applied_count integer not null check(applied_count between 1 and 250),
 undo_state text not null default 'available' check(undo_state in('available','undone')),applied_at timestamptz not null default clock_timestamp());
-- One immutable whole-run receipt per vehicle + job card. No intermediate snapshot is a scope receipt.
create table public.pdc_auditor_typed_scope_receipts_253(
 scope_receipt_id uuid primary key default gen_random_uuid(),run_id uuid not null references public.pdc_auditor_typed_runs_253 on delete restrict,
 vehicle_id uuid not null,job_card_number text not null,before_snapshot jsonb not null,after_snapshot jsonb,recorded_at timestamptz not null default clock_timestamp(),
 unique(run_id,vehicle_id,job_card_number));
-- One row for each actual overlay mutation (split/combine/reorder may produce many per plan item).
create table public.pdc_auditor_typed_change_receipts_253(
 change_receipt_id uuid primary key default gen_random_uuid(),run_id uuid not null references public.pdc_auditor_typed_runs_253 on delete restrict,
 plan_item_id uuid not null references public.pdc_auditor_typed_plan_items_253 on delete restrict,mutation_sequence integer not null,
 vehicle_id uuid not null,job_card_number text not null,operation_identifier text not null,adjustment_id uuid not null,
 overlay_before jsonb,overlay_after jsonb not null,reason text not null,server_rule_evidence jsonb not null,recorded_at timestamptz not null default clock_timestamp(),
 unique(run_id,mutation_sequence));
create table public.pdc_auditor_typed_undo_receipts_253(
 undo_receipt_id uuid primary key default gen_random_uuid(),run_id uuid not null unique references public.pdc_auditor_typed_runs_253 on delete restrict,
 delivery_uuid uuid not null unique references public.pdc_auditor_signed_deliveries_253 on delete restrict,restored_count integer not null,
 exact_before_snapshot_verified boolean not null check(exact_before_snapshot_verified),response jsonb not null,undone_at timestamptz not null default clock_timestamp());

-- Extend 226 by catalog-discovered constraint names; never guess installed names.
alter table public.pdc_auditor_workshop_revisions add column typed_run_id_253 uuid references public.pdc_auditor_typed_runs_253(run_id) on delete restrict;
alter table public.pdc_auditor_workshop_revisions alter column run_id drop not null;
do $revision_constraints$ declare r record; begin
 for r in select c.conname from pg_constraint c where c.conrelid='public.pdc_auditor_workshop_revisions'::regclass and c.contype='c'
   and (pg_get_constraintdef(c.oid) ilike '%event_type%' or pg_get_constraintdef(c.oid) ilike '%rollback_receipt_id%') loop
  execute format('alter table public.pdc_auditor_workshop_revisions drop constraint %I',r.conname);
 end loop;
end $revision_constraints$;
alter table public.pdc_auditor_workshop_revisions add constraint pdc_auditor_workshop_revisions_shape_253 check(
 (event_type='telegram_plan_applied_226' and run_id is not null and rollback_receipt_id is null and typed_run_id_253 is null) or
 (event_type='telegram_run_rolled_back_226' and run_id is not null and rollback_receipt_id is not null and typed_run_id_253 is null) or
 (event_type in('typed_plan_applied_253','typed_run_undone_253') and run_id is null and rollback_receipt_id is null and typed_run_id_253 is not null));
-- Preserve and independently assert the original dealer/environment invariants.
do $revision_invariants$ begin
 if not exists(select 1 from pg_constraint c where c.conrelid='public.pdc_auditor_workshop_revisions'::regclass and c.contype='c' and pg_get_constraintdef(c.oid) ilike '%dealer_code%' and pg_get_constraintdef(c.oid) ilike '%14450%' and pg_get_constraintdef(c.oid) ilike '%37047%')
    or not exists(select 1 from pg_constraint c where c.conrelid='public.pdc_auditor_workshop_revisions'::regclass and c.contype='c' and pg_get_constraintdef(c.oid) ilike '%environment%' and pg_get_constraintdef(c.oid) ilike '%staging%') then raise exception 'PDC_253_REVISION_INVARIANT_MISSING' using errcode='55000';end if;
end $revision_invariants$;
create unique index pdc_auditor_workshop_revisions_typed_once_253 on public.pdc_auditor_workshop_revisions(typed_run_id_253,event_type) where typed_run_id_253 is not null;

-- All history tables are RLS/private. Keys have no INSERT/UPDATE/DELETE grant or provisioning RPC.
do $secure$ declare t text; begin
 foreach t in array array['pdc_auditor_gateway_keys_253','pdc_auditor_signed_deliveries_253','pdc_auditor_signed_delivery_results_253','pdc_auditor_typed_plans_253','pdc_auditor_typed_plan_items_253','pdc_auditor_typed_runs_253','pdc_auditor_typed_scope_receipts_253','pdc_auditor_typed_change_receipts_253','pdc_auditor_typed_undo_receipts_253'] loop
  execute format('alter table public.%I enable row level security',t);execute format('revoke all on table public.%I from public,anon,authenticated,service_role',t);
 end loop;
end $secure$;
revoke insert,update,delete,truncate on public.pdc_auditor_workshop_revisions from public,anon,authenticated,service_role;

-- Exactly two internal seal transitions: plan construction, run final revision/Undo state.
create function public.pdc_auditor_seal_only_253() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $seal$
begin
 if tg_op<>'UPDATE' then raise exception 'PDC_253_IMMUTABLE_HISTORY' using errcode='55000';end if;
 if tg_table_name='pdc_auditor_typed_plans_253' then
  if old.proposed_count=0 and old.ambiguous_count=old.item_count
   and new.proposed_count+new.ambiguous_count=old.item_count and new.typed_item_set_hash is not null and new.final_scope is not null and new.final_scope_hash is not null and new.expected_row_versions is not null and new.expected_row_versions_hash is not null and new.proposal_hash is not null
   and to_jsonb(new)-array['proposed_count','ambiguous_count','typed_item_set_hash','final_scope','final_scope_hash','expected_row_versions','expected_row_versions_hash','proposal_hash']::text[]=to_jsonb(old)-array['proposed_count','ambiguous_count','typed_item_set_hash','final_scope','final_scope_hash','expected_row_versions','expected_row_versions_hash','proposal_hash']::text[] then return new;end if;
 elsif tg_table_name='pdc_auditor_typed_runs_253' then
  if (old.run_revision_after=repeat('0',64) and new.run_revision_after~'^[a-f0-9]{64}$' and new.undo_state='available' and to_jsonb(new)-'run_revision_after'=to_jsonb(old)-'run_revision_after')
    or (old.undo_state='available' and new.undo_state='undone' and new.run_revision_after=old.run_revision_after and to_jsonb(new)-'undo_state'=to_jsonb(old)-'undo_state') then return new;end if;
 elsif tg_table_name='pdc_auditor_typed_scope_receipts_253' then
  if old.after_snapshot is null and new.after_snapshot is not null and to_jsonb(new)-'after_snapshot'=to_jsonb(old)-'after_snapshot' then return new;end if;
 end if;
 raise exception 'PDC_253_IMMUTABLE_HISTORY' using errcode='55000';
end $seal$;
revoke all on function public.pdc_auditor_seal_only_253() from public,anon,authenticated,service_role;
create trigger pdc_auditor_typed_plans_253_immutable before update or delete on public.pdc_auditor_typed_plans_253 for each row execute function public.pdc_auditor_seal_only_253();
create trigger pdc_auditor_typed_runs_253_immutable before update or delete on public.pdc_auditor_typed_runs_253 for each row execute function public.pdc_auditor_seal_only_253();
create trigger pdc_auditor_typed_scope_receipts_253_immutable before update or delete on public.pdc_auditor_typed_scope_receipts_253 for each row execute function public.pdc_auditor_seal_only_253();
do $immutable$ declare t text; begin
 foreach t in array array['pdc_auditor_gateway_keys_253','pdc_auditor_signed_deliveries_253','pdc_auditor_signed_delivery_results_253','pdc_auditor_typed_plan_items_253','pdc_auditor_typed_change_receipts_253','pdc_auditor_typed_undo_receipts_253'] loop
  execute format('create trigger %I before update or delete on public.%I for each row execute function public.pdc_auditor_reject_history_mutation()',t||'_immutable',t);
 end loop;
end $immutable$;

create function public.pdc_auditor_typed_snapshot_253(p_vehicle uuid,p_job_card text) returns jsonb language sql stable security definer set search_path=pg_catalog,public as $snapshot$
 select jsonb_build_object(
 'ordered_effective_set',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order,x.operation_line_identifier) from (select e.operation_line_identifier,e.operation_line_id,e.operation_code,e.description,e.work_key,e.estimated_hours,e.display_order,e.active,e.adjustment_id,e.correction_origin,e.manual_assignment_locked from public.pdc_effective_operation_lines e where e.vehicle_id=p_vehicle and coalesce(e.job_card_number,'')=p_job_card and e.active)x),'[]'::jsonb),
 'aggregate_total_hours',coalesce((select sum(e.estimated_hours) from public.pdc_effective_operation_lines e where e.vehicle_id=p_vehicle and coalesce(e.job_card_number,'')=p_job_card and e.active),0),
 'per_department_hours',coalesce((select jsonb_object_agg(x.work_key,x.hours) from(select e.work_key,sum(e.estimated_hours) hours from public.pdc_effective_operation_lines e where e.vehicle_id=p_vehicle and coalesce(e.job_card_number,'')=p_job_card and e.active group by e.work_key order by e.work_key)x),'{}'::jsonb),
 'required_work_identifiers',coalesce((select jsonb_agg(jsonb_build_object('id',wi.id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed) order by wi.work_key,wi.id) from public.vehicle_work_items wi where wi.vehicle_id=p_vehicle and (wi.required or wi.completed)),'[]'::jsonb)) $snapshot$;
revoke all on function public.pdc_auditor_typed_snapshot_253(uuid,text) from public,anon,authenticated,service_role;

-- Exact logical source overlays use line_key=source:<uuid>. Generated additions use
-- the namespaced auditor:<adjustment_id> identity exposed by the normalized view.
create view public.pdc_auditor_normalized_operation_lines_253 with(security_invoker=false) as
select case when e.operation_line_id is not null then 'source:'||e.operation_line_id::text
            else 'auditor:'||e.adjustment_id::text end operation_ref,e.*,
       ol.source_uid,ol.source_hash,ol.operation_fingerprint
from public.pdc_effective_operation_lines e
left join public.pdc_authenticated_email_operation_lines ol on ol.operation_line_id=e.operation_line_id;
revoke all on public.pdc_auditor_normalized_operation_lines_253 from public,anon,authenticated,service_role;

-- Python json.dumps(sort_keys=True,separators=(',',':'),ensure_ascii=False) equivalent for JSON-compatible values.
create function public.pdc_auditor_canonical_json_253(p_value jsonb) returns text language plpgsql immutable security definer set search_path=pg_catalog,public as $canonical$
declare result text;
begin
 case jsonb_typeof(p_value)
  when 'object' then select '{'||coalesce(string_agg(to_jsonb(k)::text||':'||public.pdc_auditor_canonical_json_253(v),',' order by k),'')||'}' into result from jsonb_each(p_value) e(k,v);
  when 'array' then select '['||coalesce(string_agg(public.pdc_auditor_canonical_json_253(v),',' order by n),'')||']' into result from jsonb_array_elements(p_value) with ordinality e(v,n);
  else result:=p_value::text;
 end case;
 return result;
end $canonical$;
revoke all on function public.pdc_auditor_canonical_json_253(jsonb) from public,anon,authenticated,service_role;

create function public.pdc_auditor_signing_bytes_253(p_envelope jsonb) returns bytea language plpgsql immutable security definer set search_path=pg_catalog,public as $bytes$
declare f text;raw bytea;out bytea:=convert_to(E'pdc-auditor-envelope-253-v1\n','UTF8');first boolean:=true;
begin
 foreach f in array array['gateway_instance_id','delivery_uuid','key_id','nonce','issued_at','expires_at','instruction_sha256','selected_scope','telegram_evidence'] loop
  raw:=case when f in('selected_scope','telegram_evidence') then convert_to(public.pdc_auditor_canonical_json_253(p_envelope->f),'UTF8') else convert_to(p_envelope->>f,'UTF8') end;
  if not first then out:=out||convert_to(E'\n','UTF8');end if;first:=false;
  out:=out||convert_to(f||':'||octet_length(raw)::text||':','UTF8')||raw;
 end loop;return out;
end $bytes$;
revoke all on function public.pdc_auditor_signing_bytes_253(jsonb) from public,anon,authenticated,service_role;

create function public.pdc_auditor_verify_envelope_253(p_purpose text,p_envelope jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $verify$
declare k public.pdc_auditor_gateway_keys_253%rowtype;actor jsonb;signing bytea;reqhash text;d public.pdc_auditor_signed_deliveries_253%rowtype;result jsonb;telegram jsonb;issued timestamptz;expires timestamptz;delivery uuid;
begin
 if jsonb_typeof(p_envelope)<>'object' or (select array_agg(x order by x) from jsonb_object_keys(p_envelope)x) is distinct from array['delivery_uuid','expires_at','gateway_instance_id','instruction_sha256','issued_at','key_id','nonce','selected_scope','signature','telegram_evidence']::text[] then raise exception 'PDC_253_INVALID_ENVELOPE_FIELDS' using errcode='22023';end if;
 if jsonb_typeof(p_envelope->'gateway_instance_id')<>'string'
    or jsonb_typeof(p_envelope->'delivery_uuid')<>'string'
    or jsonb_typeof(p_envelope->'key_id')<>'string'
    or jsonb_typeof(p_envelope->'nonce')<>'string'
    or jsonb_typeof(p_envelope->'instruction_sha256')<>'string'
    or jsonb_typeof(p_envelope->'signature')<>'string' then raise exception 'PDC_253_INVALID_ENVELOPE_VALUE' using errcode='22023';end if;
 telegram:=p_envelope->'telegram_evidence';
 if jsonb_typeof(telegram)<>'object' or (select array_agg(x order by x) from jsonb_object_keys(telegram)x) is distinct from array['bot_identity','instruction_sha256','original_instruction','telegram_chat_id','telegram_message_id','telegram_sender_id','telegram_update_id']::text[] then raise exception 'PDC_253_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';end if;
 if jsonb_typeof(telegram->'bot_identity')<>'string'
    or jsonb_typeof(telegram->'instruction_sha256')<>'string'
    or jsonb_typeof(telegram->'original_instruction')<>'string'
    or jsonb_typeof(telegram->'telegram_chat_id')<>'number'
    or jsonb_typeof(telegram->'telegram_message_id')<>'number'
    or jsonb_typeof(telegram->'telegram_sender_id')<>'number'
    or jsonb_typeof(telegram->'telegram_update_id')<>'number' then raise exception 'PDC_253_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';end if;
 if telegram->>'bot_identity'=''
    or telegram->>'telegram_chat_id' !~ '^[1-9][0-9]{0,18}$'
    or telegram->>'telegram_message_id' !~ '^[1-9][0-9]{0,18}$'
    or telegram->>'telegram_sender_id' !~ '^[1-9][0-9]{0,18}$'
    or telegram->>'telegram_update_id' !~ '^[1-9][0-9]{0,18}$'
    or (telegram->>'telegram_chat_id')::numeric>9223372036854775807
    or (telegram->>'telegram_message_id')::numeric>9223372036854775807
    or (telegram->>'telegram_sender_id')::numeric>9223372036854775807
    or (telegram->>'telegram_update_id')::numeric>9223372036854775807 then raise exception 'PDC_253_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';end if;
 if jsonb_typeof(p_envelope->'issued_at')<>'string' or jsonb_typeof(p_envelope->'expires_at')<>'string' or p_envelope->>'issued_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$' or p_envelope->>'expires_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$' then raise exception 'PDC_253_ENVELOPE_TIME_INVALID' using errcode='22023';end if;
 issued:=(p_envelope->>'issued_at')::timestamptz;expires:=(p_envelope->>'expires_at')::timestamptz;
 if issued>clock_timestamp()+interval '30 seconds' or expires<=clock_timestamp() or expires<=issued or expires-issued>interval '300 seconds' then raise exception 'PDC_253_ENVELOPE_TIME_INVALID' using errcode='22023';end if;
 if lower(p_envelope->>'instruction_sha256')<>lower(telegram->>'instruction_sha256') or lower(p_envelope->>'instruction_sha256')<>encode(extensions.digest(convert_to(telegram->>'original_instruction','UTF8'),'sha256'),'hex') then raise exception 'PDC_253_INSTRUCTION_HASH_MISMATCH' using errcode='22023';end if;
 select * into k from public.pdc_auditor_gateway_keys_253 where gateway_instance_id=p_envelope->>'gateway_instance_id' and key_id=p_envelope->>'key_id' and active and revoked_at is null and issued between valid_from and valid_until for share;
 if not found then raise exception 'PDC_253_GATEWAY_KEY_INVALID' using errcode='42501';end if;
 signing:=public.pdc_auditor_signing_bytes_253(p_envelope);
 if lower(p_envelope->>'signature')<>encode(extensions.hmac(signing,k.hmac_key,'sha256'),'hex') then raise exception 'PDC_253_BAD_SIGNATURE' using errcode='42501';end if;
 delivery:=(p_envelope->>'delivery_uuid')::uuid;reqhash:=encode(extensions.digest(convert_to(p_purpose||'|','UTF8')||signing,'sha256'),'hex');perform pg_advisory_xact_lock(hashtextextended('pdc-253-delivery:'||delivery,0));
 select * into d from public.pdc_auditor_signed_deliveries_253 where delivery_uuid=delivery;
 if found then
  if d.request_content_hash<>reqhash or d.purpose<>p_purpose then raise exception 'PDC_253_CONFLICTING_DELIVERY_REPLAY' using errcode='23505';end if;
  actor:=public.pdc_auditor_telegram_actor_scope_225((telegram->>'telegram_sender_id')::bigint);
  if auth.uid() is distinct from (actor->>'service_user_id')::uuid or lower(btrim(coalesce(auth.jwt()->>'email','')))<>lower(actor->>'service_email') then raise exception 'PDC_253_AUTHENTICATED_AUDITOR_SESSION_REQUIRED' using errcode='42501';end if;
  if (actor->>'service_identity_id')::uuid<>d.service_identity_id or (actor->>'service_user_id')::uuid<>d.service_auth_user_id or actor->>'service_email'<>d.service_email or (actor->>'admin_user_id')::uuid<>d.authorizing_admin_user_id or actor->>'admin_email'<>d.authorizing_admin_email or actor->>'dealer_code'<>d.dealer_code then raise exception 'PDC_253_REPLAY_ACTOR_NO_LONGER_AUTHORIZED' using errcode='42501';end if;
  select stored_result into result from public.pdc_auditor_signed_delivery_results_253 where delivery_uuid=d.delivery_uuid;return jsonb_build_object('delivery_uuid',d.delivery_uuid,'actor',actor,'request_content_hash',reqhash,'stored_result',result,'replay',true);
 end if;
 if exists(select 1 from public.pdc_auditor_signed_deliveries_253 where (gateway_instance_id,key_id,nonce)=(p_envelope->>'gateway_instance_id',p_envelope->>'key_id',p_envelope->>'nonce')) then raise exception 'PDC_253_NONCE_REPLAY' using errcode='23505';end if;
 actor:=public.pdc_auditor_telegram_actor_scope_225((telegram->>'telegram_sender_id')::bigint);
 if auth.uid() is distinct from (actor->>'service_user_id')::uuid or lower(btrim(coalesce(auth.jwt()->>'email','')))<>lower(actor->>'service_email') then raise exception 'PDC_253_AUTHENTICATED_AUDITOR_SESSION_REQUIRED' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-230-message:'||(telegram->>'telegram_chat_id')||':'||(telegram->>'telegram_message_id'),0));
 perform pg_advisory_xact_lock(hashtextextended('pdc-230-update:'||(telegram->>'bot_identity')||':'||(telegram->>'telegram_update_id'),0));
 begin
  insert into public.pdc_auditor_telegram_deliveries_230(delivery_domain,telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,bot_identity,original_instruction,instruction_sha256,source_table,source_id)
  values('operation',(telegram->>'telegram_sender_id')::bigint,(telegram->>'telegram_chat_id')::bigint,(telegram->>'telegram_message_id')::bigint,(telegram->>'telegram_update_id')::bigint,telegram->>'bot_identity',telegram->>'original_instruction',lower(telegram->>'instruction_sha256'),'pdc_auditor_signed_deliveries_253',delivery);
 exception when unique_violation then raise exception 'PDC_253_TELEGRAM_DELIVERY_ALREADY_CONSUMED' using errcode='23505';end;
 insert into public.pdc_auditor_signed_deliveries_253 values(delivery,p_envelope->>'gateway_instance_id',p_envelope->>'key_id',p_envelope->>'nonce',issued,expires,lower(p_envelope->>'instruction_sha256'),p_envelope->'selected_scope',lower(p_envelope->>'signature'),telegram,p_purpose,reqhash,(actor->>'service_identity_id')::uuid,(actor->>'service_user_id')::uuid,actor->>'service_email',(actor->>'admin_user_id')::uuid,actor->>'admin_email',actor->>'dealer_code',clock_timestamp());
 return jsonb_build_object('delivery_uuid',p_envelope->>'delivery_uuid','actor',actor,'request_content_hash',reqhash,'replay',false);
exception when invalid_text_representation or datetime_field_overflow then raise exception 'PDC_253_INVALID_ENVELOPE_VALUE' using errcode='22023';end $verify$;
revoke all on function public.pdc_auditor_verify_envelope_253(text,jsonb) from public,anon,authenticated,service_role;

-- Scope is typed desired intent only. Old values, disposition and proof are always reconstructed here.
-- One PostgreSQL-owned typed-value boundary shared by every planner action.
-- Authenticated callers can execute the signed planner RPC directly, so the
-- Python parser is defence in depth and must never be the only schema guard.
create function public.pdc_auditor_valid_new_value_253(p_value jsonb,p_complete boolean,p_allow_ordered_position boolean,p_require_operation_code boolean default false) returns boolean language sql immutable set search_path=pg_catalog as $valid$
select case when jsonb_typeof(p_value) is distinct from 'object' then false else
 (select count(*) from jsonb_object_keys(p_value)) between 1 and 5
 and not exists(select 1 from jsonb_object_keys(p_value) k where k not in('description','estimated_hours','operation_code','ordered_position','work_key'))
 and (not p_complete or p_value ?& array['description','estimated_hours','work_key'])
 and (not p_require_operation_code or p_value ? 'operation_code')
 and (p_allow_ordered_position or not p_value ? 'ordered_position')
 and (not p_value ? 'description' or (jsonb_typeof(p_value->'description')='string' and length(p_value->>'description') between 1 and 180))
 and (not p_value ? 'estimated_hours' or (jsonb_typeof(p_value->'estimated_hours')='number' and (p_value->>'estimated_hours')::numeric between 0.25 and 999.75 and mod((p_value->>'estimated_hours')::numeric,0.25)=0))
 and (not p_value ? 'work_key' or (jsonb_typeof(p_value->'work_key')='string' and p_value->>'work_key' in('fitting','tint','hoist','electrical','fabrication','tyre','pitInspection')))
 and (not p_value ? 'operation_code' or (jsonb_typeof(p_value->'operation_code')='string' and p_value->>'operation_code' ~ '^[A-Za-z0-9._/-]{1,64}$'))
 and (not p_value ? 'ordered_position' or (jsonb_typeof(p_value->'ordered_position')='number' and (p_value->>'ordered_position')::numeric between 1 and 10000 and trunc((p_value->>'ordered_position')::numeric)=(p_value->>'ordered_position')::numeric)) end;
$valid$;
revoke all on function public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean) from public,anon,authenticated,service_role;

create function public.plan_pdc_auditor_typed_instruction_253(p_action text,p_mode text,p_selected_scope jsonb,p_gateway_envelope jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $plan$
declare verified jsonb;actor jsonb;pid uuid:=gen_random_uuid();item jsonb;derived_items jsonb;selector jsonb;desire jsonb;seq int:=0;proposed int:=0;ambiguous int:=0;vehicle uuid;jc text;oldv jsonb;newv jsonb;disp text;ambiguity text;revision text;scopehash text;proposalhash text;typedhash text;finalscope jsonb;finalscopehash text;expectedversions jsonb;expectedhash text;response jsonb;refs text[];survivor text;effective_count int;proof jsonb;allowed boolean;r record;
begin
 -- The client supplies bounded intent, never candidates, current values, proof or disposition.
 if p_action not in('add','edit','split','combine','reorder','remove_duplicate') or p_mode not in('review','apply')
    or p_selected_scope is distinct from p_gateway_envelope->'selected_scope'
    or jsonb_typeof(p_selected_scope)<>'object'
    or (select array_agg(k order by k) from jsonb_object_keys(p_selected_scope)k) is distinct from array['action','apply_unambiguous','contract','desire','selector']::text[]
    or p_selected_scope->>'contract'<>'pdc-auditor-bounded-intent-253-v1'
    or p_selected_scope->>'action'<>p_action
    or jsonb_typeof(p_selected_scope->'apply_unambiguous')<>'boolean'
    or jsonb_typeof(p_selected_scope->'selector')<>'object'
    or jsonb_typeof(p_selected_scope->'desire')<>'object'
    or p_selected_scope ?| array['items','candidates','old_value','old_effective_value','proof','disposition'] then
  raise exception 'PDC_253_INVALID_BOUNDED_INTENT' using errcode='22023';
 end if;
 selector:=p_selected_scope->'selector';desire:=p_selected_scope->'desire';derived_items:='[]'::jsonb;
 -- Every signed action has one exact selector/desire schema; unknown fields fail closed.
 if (p_action='edit' and selector ? 'category' and ((select array_agg(k order by k) from jsonb_object_keys(selector)k)<>array['category']::text[] or (select array_agg(k order by k) from jsonb_object_keys(desire)k)<>array['new_value']::text[]))
 or (p_action='edit' and not selector ? 'category' and ((select array_agg(k order by k) from jsonb_object_keys(selector)k)<>array['operation_ref']::text[] or (select array_agg(k order by k) from jsonb_object_keys(desire)k)<>array['new_value']::text[]))
 or (p_action='split' and ((select array_agg(k order by k) from jsonb_object_keys(selector)k)<>array['operation_ref']::text[] or (select array_agg(k order by k) from jsonb_object_keys(desire)k)<>array['children']::text[]))
 or (p_action='add' and ((select array_agg(k order by k) from jsonb_object_keys(selector)k)<>array['vehicle_id']::text[] or (select array_agg(k order by k) from jsonb_object_keys(desire)k)<>array['new_value']::text[]))
 or (p_action='combine' and ((select array_agg(k order by k) from jsonb_object_keys(selector)k)<>array['operation_refs']::text[] or (select array_agg(k order by k) from jsonb_object_keys(desire)k)<>array['new_value','survivor_operation_ref']::text[]))
 or (p_action='reorder' and ((select array_agg(k order by k) from jsonb_object_keys(selector)k)<>array['operation_refs']::text[] or (select array_agg(k order by k) from jsonb_object_keys(desire)k)<>array['complete_effective_set']::text[] or desire->'complete_effective_set'<>'true'::jsonb))
 or (p_action='remove_duplicate' and ((select array_agg(k order by k) from jsonb_object_keys(selector)k)<>array['operation_refs']::text[] or (select array_agg(k order by k) from jsonb_object_keys(desire)k)<>array['duplicate_proof','survivor_operation_ref']::text[] or desire->>'duplicate_proof'<>'database_exact')) then raise exception 'PDC_253_EXACT_INTENT_SCHEMA_REQUIRED' using errcode='22023';end if;
 -- Exact selectors are normalized to source:<uuid>/auditor:<uuid>.  Bare UUIDs are rejected.
 if p_action='edit' and selector ? 'category' then null;
 elsif p_action in('edit','split') then
  if (select array_agg(k order by k) from jsonb_object_keys(selector)k)<>array['operation_ref']::text[] or selector->>'operation_ref'!~'^(source|auditor):[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then raise exception 'PDC_253_EXACT_NAMESPACED_REF_REQUIRED' using errcode='22023';end if;
  select jsonb_build_array(jsonb_build_object('action',p_action,'vehicle_id',n.vehicle_id,'job_card_number',coalesce(n.job_card_number,''),'operation_identifier',n.operation_ref,'reason','bounded exact operation intent')||case when p_action='edit' then jsonb_build_object('new_value',desire->'new_value') else jsonb_build_object('children',desire->'children') end) into derived_items from public.pdc_auditor_normalized_operation_lines_253 n where n.operation_ref=selector->>'operation_ref' and n.active;
 elsif p_action in('combine','reorder','remove_duplicate') then
  if jsonb_typeof(selector->'operation_refs')<>'array' or jsonb_array_length(selector->'operation_refs') not between 2 and 100 or exists(select 1 from jsonb_array_elements_text(selector->'operation_refs') x where x!~'^(source|auditor):[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then raise exception 'PDC_253_EXACT_NAMESPACED_REFS_REQUIRED' using errcode='22023';end if;
 if (select count(*) from jsonb_array_elements_text(selector->'operation_refs'))<>(select count(distinct x) from jsonb_array_elements_text(selector->'operation_refs') x) then raise exception 'PDC_253_DUPLICATE_OPERATION_REFS' using errcode='22023';end if;
  select jsonb_build_array(jsonb_build_object('action',p_action,'vehicle_id',(array_agg(n.vehicle_id order by n.operation_ref))[1],'job_card_number',min(coalesce(n.job_card_number,'')),'reason','bounded exact operation-set intent')||case when p_action='reorder' then jsonb_build_object('ordered_operation_identifiers',selector->'operation_refs') when p_action='combine' then jsonb_build_object('operation_identifiers',selector->'operation_refs','survivor_operation_identifier',desire->>'survivor_operation_ref','new_value',desire->'new_value') else jsonb_build_object('operation_identifiers',selector->'operation_refs','survivor_operation_identifier',desire->>'survivor_operation_ref') end) into derived_items from public.pdc_auditor_normalized_operation_lines_253 n where n.active and n.operation_ref in(select jsonb_array_elements_text(selector->'operation_refs')) having count(*)=jsonb_array_length(selector->'operation_refs') and count(distinct n.operation_ref)=jsonb_array_length(selector->'operation_refs') and count(distinct n.vehicle_id)=1 and count(distinct coalesce(n.job_card_number,''))=1;
 elsif p_action='add' then
  if (selector ? 'vehicle_id') is false or (selector->>'vehicle_id')!~'^[0-9a-f-]{36}$' then raise exception 'PDC_253_ADD_SELECTOR_INVALID' using errcode='22023';end if;
  select case when count(distinct coalesce(n.job_card_number,''))=1 then jsonb_build_array(jsonb_build_object('action','add','vehicle_id',selector->>'vehicle_id','job_card_number',min(coalesce(n.job_card_number,'')),'new_value',desire->'new_value','reason','bounded exact add intent')) end into derived_items from public.pdc_auditor_normalized_operation_lines_253 n where n.vehicle_id=(selector->>'vehicle_id')::uuid and n.active;
 end if;
 -- Known category intents are expanded exclusively from current server rows.
 if selector ? 'category' then
  if p_action='edit' and selector->>'category'='long_range_fuel_tank' and desire->'new_value'=jsonb_build_object('work_key','hoist') then select coalesce(jsonb_agg(jsonb_build_object('action','edit','vehicle_id',n.vehicle_id,'job_card_number',coalesce(n.job_card_number,''),'operation_identifier',n.operation_ref,'new_value',desire->'new_value','reason','exact long-range tank mapping') order by n.vehicle_id,n.operation_ref),'[]') into derived_items from public.pdc_auditor_normalized_operation_lines_253 n where n.active and public.pdc_auditor_normalize_identity_225(n.description)~'long range fuel tank';
 elsif p_action='edit' and selector->>'category'='gvm_upgrade' and desire->'new_value' ? 'estimated_hours' then select coalesce(jsonb_agg(jsonb_build_object('action','edit','vehicle_id',n.vehicle_id,'job_card_number',coalesce(n.job_card_number,''),'operation_identifier',n.operation_ref,'new_value',desire->'new_value','reason','exact approved GVM mapping') order by n.vehicle_id,n.operation_ref),'[]') into derived_items from public.pdc_auditor_normalized_operation_lines_253 n where n.active and public.pdc_auditor_normalize_identity_225(n.description)~'(^| )(gvm upgrade|gross vehicle mass upgrade)( |$)' and public.pdc_auditor_normalize_identity_225(n.description)!~'(fuel tank|long range)';
  else raise exception 'PDC_253_UNKNOWN_CATEGORY_INTENT' using errcode='22023';end if;
 end if;
 if derived_items is null or jsonb_array_length(derived_items) not between 1 and 250 then raise exception 'PDC_253_CLARIFICATION_REQUIRED' using errcode='22023';end if;
 verified:=public.pdc_auditor_verify_envelope_253('plan',p_gateway_envelope);actor:=verified->'actor';if coalesce((verified->>'replay')::boolean,false) and verified->'stored_result' is not null then return verified->'stored_result';end if;
 revision:=public.pdc_auditor_operational_revision(actor->>'dealer_code');scopehash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253(p_selected_scope),'UTF8'),'sha256'),'hex');
 insert into public.pdc_auditor_typed_plans_253(plan_id,delivery_uuid,action,mode,selected_scope,selected_scope_hash,instruction,instruction_sha256,dealer_code,operational_revision,item_count,proposed_count,ambiguous_count,review_only,apply_unambiguous) values(pid,(verified->>'delivery_uuid')::uuid,p_action,p_mode,p_selected_scope,scopehash,p_gateway_envelope->'telegram_evidence'->>'original_instruction',p_gateway_envelope->>'instruction_sha256',actor->>'dealer_code',revision,jsonb_array_length(derived_items),0,jsonb_array_length(derived_items),p_mode='review',(p_selected_scope->>'apply_unambiguous')::boolean);
 for item in select value from jsonb_array_elements(derived_items) loop
  seq:=seq+1;disp:='proposed';ambiguity:=null;oldv:=null;proof:='{}';refs:='{}';survivor:=null;
  if item->>'action'<>p_action or length(coalesce(item->>'reason','')) not between 3 and 1000 then raise exception 'PDC_253_INVALID_TYPED_ITEM' using errcode='22023';end if;
  -- Exact action-specific outer schemas and JSON scalar types. No caller old/disposition/proof fields exist.
  allowed:=case p_action
   when 'add' then (select array_agg(k order by k) from jsonb_object_keys(item)k)=array['action','job_card_number','new_value','reason','vehicle_id']::text[]
   when 'edit' then (select array_agg(k order by k) from jsonb_object_keys(item)k)=array['action','job_card_number','new_value','operation_identifier','reason','vehicle_id']::text[]
   when 'split' then (select array_agg(k order by k) from jsonb_object_keys(item)k)=array['action','children','job_card_number','operation_identifier','reason','vehicle_id']::text[]
   when 'combine' then (select array_agg(k order by k) from jsonb_object_keys(item)k)=array['action','job_card_number','new_value','operation_identifiers','reason','survivor_operation_identifier','vehicle_id']::text[]
   when 'reorder' then (select array_agg(k order by k) from jsonb_object_keys(item)k)=array['action','job_card_number','ordered_operation_identifiers','reason','vehicle_id']::text[]
   else (select array_agg(k order by k) from jsonb_object_keys(item)k)=array['action','job_card_number','operation_identifiers','reason','survivor_operation_identifier','vehicle_id']::text[] end;
  if not allowed then raise exception 'PDC_253_ACTION_SCHEMA_MISMATCH' using errcode='22023';end if;
  vehicle:=(item->>'vehicle_id')::uuid;jc:=item->>'job_card_number';if public.pdc_auditor_vehicle_dealer(vehicle)<>actor->>'dealer_code' then raise exception 'PDC_253_ITEM_OUT_OF_SCOPE' using errcode='42501';end if;
  if not exists(select 1 from public.vehicles v where v.id=vehicle and v.deleted_at is null and v.lifecycle_state='active' and v.rft_collected_at is null and upper(btrim(coalesce(v.current_location,'')))<>'COMPLETED') then disp:='ambiguous';ambiguity:='vehicle_protected';end if;
  if p_action='add' then newv:=item->'new_value';if not public.pdc_auditor_valid_new_value_253(newv,true,true,false) then raise exception 'PDC_253_ADD_SCHEMA_INVALID' using errcode='22023';end if;proof:=jsonb_build_object('kind','typed_add','operation_code_server_checked',not exists(select 1 from public.pdc_effective_operation_lines e where e.vehicle_id=vehicle and coalesce(e.job_card_number,'')=jc and upper(coalesce(e.operation_code,''))=upper(coalesce(newv->>'operation_code','')) and coalesce(newv->>'operation_code','')<>''));if not (proof->>'operation_code_server_checked')::boolean then disp:='ambiguous';ambiguity:='operation_code_conflict';end if;
  elsif p_action='edit' then select to_jsonb(e) into oldv from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=vehicle and coalesce(e.job_card_number,'')=jc and e.operation_ref=item->>'operation_identifier';newv:=item->'new_value';if oldv is null then disp:='ambiguous';ambiguity:='operation_not_exact';elsif not public.pdc_auditor_valid_new_value_253(newv,false,true,false) then raise exception 'PDC_253_EDIT_SCHEMA_INVALID' using errcode='22023';end if;proof:=jsonb_build_object('kind','exact_effective_ref','operation_ref',item->>'operation_identifier');
  elsif p_action='split' then select to_jsonb(e) into oldv from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=vehicle and coalesce(e.job_card_number,'')=jc and e.operation_ref=item->>'operation_identifier';newv:=jsonb_build_object('children',item->'children');if oldv is null then disp:='ambiguous';ambiguity:='operation_not_exact';elsif jsonb_typeof(item->'children')<>'array' or jsonb_array_length(item->'children') not between 2 and 20 or exists(select 1 from jsonb_array_elements(item->'children')c where not public.pdc_auditor_valid_new_value_253(c,true,false,false)) then raise exception 'PDC_253_SPLIT_SCHEMA_INVALID' using errcode='22023';elsif (select sum((c->>'estimated_hours')::numeric) from jsonb_array_elements(item->'children')c)<>(oldv->>'estimated_hours')::numeric then disp:='ambiguous';ambiguity:='split_hours_not_conserved';end if;proof:=jsonb_build_object('kind','split_conservation_server_checked');
  else
   refs:=array(select jsonb_array_elements_text(coalesce(case when p_action='reorder' then item->'ordered_operation_identifiers' else item->'operation_identifiers' end,'[]')));survivor:=item->>'survivor_operation_identifier';
   select coalesce(jsonb_agg(to_jsonb(e) order by e.operation_ref),'[]'::jsonb) into oldv from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=vehicle and coalesce(e.job_card_number,'')=jc and e.operation_ref=any(refs) and e.active;
   select count(*) into effective_count from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=vehicle and coalesce(e.job_card_number,'')=jc and e.active;
   if cardinality(refs)<>effective_count and p_action='reorder' then disp:='ambiguous';ambiguity:='reorder_not_complete';elsif cardinality(refs)<2 or cardinality(refs)<>(select count(*) from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=vehicle and coalesce(e.job_card_number,'')=jc and e.operation_ref=any(refs) and e.active) then disp:='ambiguous';ambiguity:='operation_set_not_exact';end if;
   if p_action='reorder' then newv:=jsonb_build_object('ordered_operation_identifiers',to_jsonb(refs));proof:=jsonb_build_object('kind','complete_effective_set','effective_count',effective_count);
   elsif p_action='combine' then newv:=item->'new_value';if not public.pdc_auditor_valid_new_value_253(newv,true,false,true) then raise exception 'PDC_253_COMBINE_SCHEMA_INVALID' using errcode='22023';elsif survivor is null or not survivor=any(refs) or (newv->>'estimated_hours')::numeric<>(select sum(e.estimated_hours) from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=vehicle and e.operation_ref=any(refs)) then disp:='ambiguous';ambiguity:='combine_survivor_or_hours_invalid';end if;proof:=jsonb_build_object('kind','combine_members_server_checked','member_count',cardinality(refs));
   else newv:=jsonb_build_object('active',false);if survivor is null or not survivor=any(refs) or exists(select 1 from public.pdc_auditor_normalized_operation_lines_253 a join public.pdc_auditor_normalized_operation_lines_253 b on b.vehicle_id=a.vehicle_id where a.vehicle_id=vehicle and a.operation_ref=survivor and b.operation_ref=any(refs) and b.operation_ref<>survivor and (a.source_uid is null or a.source_uid<>b.source_uid or a.operation_fingerprint is null or a.operation_fingerprint<>b.operation_fingerprint or a.source_hash=b.source_hash or upper(coalesce(a.operation_code,''))<>upper(coalesce(b.operation_code,'')) or public.pdc_auditor_normalize_identity_225(a.description)<>public.pdc_auditor_normalize_identity_225(b.description) or a.estimated_hours<>b.estimated_hours or a.work_key<>b.work_key or a.description~*'\m(kit|left|right|front|rear|stage|qty|quantity|pair)\M' or b.description~*'\m(kit|left|right|front|rear|stage|qty|quantity|pair)\M')) then disp:='ambiguous';ambiguity:='duplicate_proof_failed';end if;proof:=jsonb_build_object('kind','source_uid_fingerprint_distinct_hash_exact_variant_228','server_validated',ambiguity is null);end if;
  end if;
  if exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=vehicle and wi.completed and (wi.work_key in(select distinct x from jsonb_array_elements_text(to_jsonb(array_remove(array[oldv->>'work_key',newv->>'work_key'],null))) x) or wi.work_key in(select distinct member->>'work_key' from jsonb_array_elements(case when jsonb_typeof(oldv)='array' then oldv else '[]'::jsonb end) member))) or exists(select 1 from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=vehicle and (e.operation_ref=coalesce(item->>'operation_identifier',survivor) or e.operation_ref=any(refs)) and (e.manual_assignment_locked or coalesce(e.correction_origin,'') not in('','ai_auditor'))) then disp:='ambiguous';ambiguity:='manual_or_affected_completed_protected';end if;
  if disp='proposed' then proposed:=proposed+1;else ambiguous:=ambiguous+1;end if;
  insert into public.pdc_auditor_typed_plan_items_253(plan_id,sequence_no,operation_action,disposition,vehicle_id,stock_number,job_card_number,operation_identifier,ordered_position,source_operation_identifiers,survivor_operation_identifier,old_effective_value,new_effective_value,reason,server_rule_evidence,ambiguity_code) select pid,seq,p_action,disp,vehicle,v.stock_number,jc,coalesce(item->>'operation_identifier',survivor,'proposal-item:'||pid||':'||seq),coalesce((newv->>'ordered_position')::int,seq),refs,survivor,oldv,newv,item->>'reason',proof,ambiguity from public.vehicles v where v.id=vehicle;
 end loop;
 if proposed=0 then raise exception 'PDC_253_ZERO_PROPOSED_ITEMS' using errcode='22023';end if;
 -- Seal one immutable final proposal. All hashes are over canonical JSON and bind Apply to
 -- the final ordered typed items, complete scope and authoritative expected row versions.
 typedhash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253(coalesce((select jsonb_agg(to_jsonb(i)-array['created_at']::text[] order by i.sequence_no) from public.pdc_auditor_typed_plan_items_253 i where i.plan_id=pid),'[]'::jsonb)),'UTF8'),'sha256'),'hex');
 finalscope:=coalesce((select jsonb_agg(jsonb_build_object('vehicle_ref','vehicle:'||s.vehicle_id::text,'job_card_ref','job-card:'||s.job_card_number) order by s.vehicle_id,s.job_card_number) from(select distinct vehicle_id,job_card_number from public.pdc_auditor_typed_plan_items_253 where plan_id=pid and disposition='proposed')s),'[]'::jsonb);
 finalscopehash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253(finalscope),'UTF8'),'sha256'),'hex');
 expectedversions:=coalesce((select jsonb_agg(jsonb_build_object('operation_ref',e.operation_ref,'row_version',coalesce(a.version,0)) order by e.operation_ref) from public.pdc_auditor_normalized_operation_lines_253 e left join public.vehicle_workshop_line_adjustments a on a.adjustment_id=e.adjustment_id where e.operation_ref in(select operation_identifier from public.pdc_auditor_typed_plan_items_253 where plan_id=pid and disposition='proposed' union select unnest(source_operation_identifiers) from public.pdc_auditor_typed_plan_items_253 where plan_id=pid and disposition='proposed')),'[]'::jsonb);
 expectedhash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253(expectedversions),'UTF8'),'sha256'),'hex');
 proposalhash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253(jsonb_build_object('contract','pdc-auditor-proposal-253-v1','proposal_id',pid,'proposal_version',1,'dealer_code',actor->>'dealer_code','environment','staging','instruction_sha256',p_gateway_envelope->>'instruction_sha256','typed_item_set_hash',typedhash,'final_scope_hash',finalscopehash,'operational_revision',revision,'expected_row_versions_hash',expectedhash)),'UTF8'),'sha256'),'hex');
 update public.pdc_auditor_typed_plans_253 set proposed_count=proposed,ambiguous_count=ambiguous,typed_item_set_hash=typedhash,final_scope=finalscope,final_scope_hash=finalscopehash,expected_row_versions=expectedversions,expected_row_versions_hash=expectedhash,proposal_hash=proposalhash where plan_id=pid;
 response:=jsonb_build_object('ok',true,'code',case when p_mode='review' then 'typed_review_proposal_created' else 'typed_apply_proposal_created' end,'data',jsonb_build_object('proposal_id',pid,'proposal_version',1,'proposal_hash',proposalhash,'typed_item_set_hash',typedhash,'final_scope_hash',finalscopehash,'expected_row_versions_hash',expectedhash,'operational_revision',revision,'proposed_count',proposed,'ambiguous_count',ambiguous,'apply_unambiguous',(p_selected_scope->>'apply_unambiguous')::boolean));insert into public.pdc_auditor_signed_delivery_results_253 values((verified->>'delivery_uuid')::uuid,verified->>'request_content_hash',response,clock_timestamp());return response;
end $plan$;

-- Compose exactly one sealed proposal of each typed operation into one atomic run.
-- Every member proposal was independently derived by the real Review/Plan path;
-- the caller supplies only immutable proposal identities, never typed items.
create function public.compose_pdc_auditor_typed_plan_253(p_proposals uuid[],p_gateway_envelope jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $compose$
declare verified jsonb;actor jsonb;pid uuid:=gen_random_uuid();member uuid;member_plan public.pdc_auditor_typed_plans_253%rowtype;seq int:=0;revision text;scope jsonb;scopehash text;typedhash text;finalscope jsonb;finalscopehash text;expectedversions jsonb;expectedhash text;proposalhash text;response jsonb;
begin
 if cardinality(p_proposals)<>6 or cardinality(p_proposals)<>(select count(distinct x) from unnest(p_proposals)x)
    or (select array_agg(k order by k) from jsonb_object_keys(p_gateway_envelope->'selected_scope')k)<>array['contract','proposal_ids']::text[]
    or p_gateway_envelope->'selected_scope'->>'contract'<>'pdc-auditor-compose-selection-253-v1'
    or p_gateway_envelope->'selected_scope'->'proposal_ids'<>to_jsonb(p_proposals)
    or p_gateway_envelope->'telegram_evidence'->>'original_instruction'<>'Compose these reviewed corrections' then raise exception 'PDC_253_EXACT_COMPOSE_SELECTION_REQUIRED' using errcode='42501';end if;
 verified:=public.pdc_auditor_verify_envelope_253('compose',p_gateway_envelope);actor:=verified->'actor';if coalesce((verified->>'replay')::boolean,false) and verified->'stored_result' is not null then return verified->'stored_result';end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-253-compose:'||(actor->>'dealer_code'),0));
 revision:=public.pdc_auditor_operational_revision(actor->>'dealer_code');scope:=p_gateway_envelope->'selected_scope';scopehash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253(scope),'UTF8'),'sha256'),'hex');
 if (select array_agg(action order by action) from public.pdc_auditor_typed_plans_253 where plan_id=any(p_proposals)) is distinct from array['add','combine','edit','remove_duplicate','reorder','split']::text[] then raise exception 'PDC_253_COMPOSE_REQUIRES_ALL_SIX_ACTIONS' using errcode='22023';end if;
 insert into public.pdc_auditor_typed_plans_253(plan_id,delivery_uuid,action,mode,selected_scope,selected_scope_hash,instruction,instruction_sha256,dealer_code,operational_revision,item_count,proposed_count,ambiguous_count,review_only,apply_unambiguous) values(pid,(verified->>'delivery_uuid')::uuid,'mixed','apply',scope,scopehash,p_gateway_envelope->'telegram_evidence'->>'original_instruction',p_gateway_envelope->>'instruction_sha256',actor->>'dealer_code',revision,(select sum(proposed_count) from public.pdc_auditor_typed_plans_253 where plan_id=any(p_proposals)),0,(select sum(proposed_count) from public.pdc_auditor_typed_plans_253 where plan_id=any(p_proposals)),false,true);
 foreach member in array p_proposals loop
  select p.* into member_plan from public.pdc_auditor_typed_plans_253 p join public.pdc_auditor_signed_deliveries_253 d on d.delivery_uuid=p.delivery_uuid where p.plan_id=member and p.action<>'mixed' and p.mode in('review','apply') and p.proposed_count>0 and p.ambiguous_count=0 and p.operational_revision=revision and p.dealer_code=actor->>'dealer_code' and d.service_identity_id=(actor->>'service_identity_id')::uuid and d.service_auth_user_id=(actor->>'service_user_id')::uuid and d.service_email=actor->>'service_email' and d.authorizing_admin_user_id=(actor->>'admin_user_id')::uuid and d.authorizing_admin_email=actor->>'admin_email';
  if not found then raise exception 'PDC_253_COMPOSE_MEMBER_INVALID' using errcode='40001';end if;
  insert into public.pdc_auditor_typed_plan_items_253(plan_id,sequence_no,operation_action,disposition,vehicle_id,stock_number,job_card_number,operation_identifier,ordered_position,source_operation_identifiers,survivor_operation_identifier,old_effective_value,new_effective_value,reason,server_rule_evidence,ambiguity_code)
  select pid,seq+row_number() over(order by sequence_no),operation_action,disposition,vehicle_id,stock_number,job_card_number,operation_identifier,ordered_position,source_operation_identifiers,survivor_operation_identifier,old_effective_value,new_effective_value,reason,server_rule_evidence,ambiguity_code from public.pdc_auditor_typed_plan_items_253 where plan_id=member and disposition='proposed' order by sequence_no;
  seq:=seq+member_plan.proposed_count;
 end loop;
 if exists(
  with refs as(
   select i.plan_item_id,ref
   from public.pdc_auditor_typed_plan_items_253 i
   cross join lateral unnest(array_remove(array_prepend(i.operation_identifier,i.source_operation_identifiers),null)) ref
   where i.plan_id=pid and i.disposition='proposed'
  )
  select 1 from refs group by ref having count(distinct plan_item_id)>1
 ) then raise exception 'PDC_253_COMPOSE_OVERLAPPING_OPERATION_SCOPE' using errcode='22023';end if;
 typedhash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253((select jsonb_agg(to_jsonb(i)-array['created_at']::text[] order by i.sequence_no) from public.pdc_auditor_typed_plan_items_253 i where i.plan_id=pid)),'UTF8'),'sha256'),'hex');
 finalscope:=(select jsonb_agg(jsonb_build_object('vehicle_ref','vehicle:'||s.vehicle_id::text,'job_card_ref','job-card:'||s.job_card_number) order by s.vehicle_id,s.job_card_number) from(select distinct vehicle_id,job_card_number from public.pdc_auditor_typed_plan_items_253 where plan_id=pid)s);finalscopehash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253(finalscope),'UTF8'),'sha256'),'hex');
 expectedversions:=coalesce((select jsonb_agg(jsonb_build_object('operation_ref',e.operation_ref,'row_version',coalesce(a.version,0)) order by e.operation_ref) from public.pdc_auditor_normalized_operation_lines_253 e left join public.vehicle_workshop_line_adjustments a on a.adjustment_id=e.adjustment_id where e.operation_ref in(select operation_identifier from public.pdc_auditor_typed_plan_items_253 where plan_id=pid union select unnest(source_operation_identifiers) from public.pdc_auditor_typed_plan_items_253 where plan_id=pid)),'[]'::jsonb);expectedhash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253(expectedversions),'UTF8'),'sha256'),'hex');
 proposalhash:=encode(extensions.digest(convert_to(public.pdc_auditor_canonical_json_253(jsonb_build_object('contract','pdc-auditor-proposal-253-v1','proposal_id',pid,'proposal_version',1,'dealer_code',actor->>'dealer_code','environment','staging','instruction_sha256',p_gateway_envelope->>'instruction_sha256','typed_item_set_hash',typedhash,'final_scope_hash',finalscopehash,'operational_revision',revision,'expected_row_versions_hash',expectedhash)),'UTF8'),'sha256'),'hex');
 update public.pdc_auditor_typed_plans_253 set proposed_count=seq,ambiguous_count=0,typed_item_set_hash=typedhash,final_scope=finalscope,final_scope_hash=finalscopehash,expected_row_versions=expectedversions,expected_row_versions_hash=expectedhash,proposal_hash=proposalhash where plan_id=pid;
 response:=jsonb_build_object('ok',true,'code','typed_mixed_proposal_created','data',jsonb_build_object('proposal_id',pid,'proposal_version',1,'proposal_hash',proposalhash,'typed_item_set_hash',typedhash,'final_scope_hash',finalscopehash,'expected_row_versions_hash',expectedhash,'operational_revision',revision,'proposed_count',seq,'ambiguous_count',0,'apply_unambiguous',true));insert into public.pdc_auditor_signed_delivery_results_253 values((verified->>'delivery_uuid')::uuid,verified->>'request_content_hash',response,clock_timestamp());return response;
end $compose$;

create function public.pdc_auditor_recalculate_required_work_253(p_vehicles uuid[]) returns void language plpgsql security definer set search_path=pg_catalog,public as $recalc$ declare v uuid;begin for v in select distinct unnest(p_vehicles) loop insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at) select v,e.work_key,true,false,null,null,null,clock_timestamp() from(select distinct work_key from public.pdc_effective_operation_lines where vehicle_id=v and active and work_key is not null)e on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp() where not public.vehicle_work_items.completed and not public.vehicle_work_items.required;update public.vehicle_work_items wi set required=false,updated_at=clock_timestamp() where wi.vehicle_id=v and wi.required and not wi.completed and not exists(select 1 from public.pdc_effective_operation_lines e where e.vehicle_id=v and e.active and e.work_key=wi.work_key);end loop;end $recalc$;
revoke all on function public.pdc_auditor_recalculate_required_work_253(uuid[]) from public,anon,authenticated,service_role;

create function public.apply_pdc_auditor_typed_plan_253(p_proposal uuid,p_proposal_version integer,p_proposal_hash text,p_typed_item_set_hash text,p_final_scope_hash text,p_expected_row_versions_hash text,p_gateway_envelope jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $apply$
declare verified jsonb;actor jsonb;plan public.pdc_auditor_typed_plans_253%rowtype;i record;runid uuid:=gen_random_uuid();a public.vehicle_workshop_line_adjustments%rowtype;beforea jsonb;source public.pdc_authenticated_email_operation_lines%rowtype;ref text;child jsonb;pos int;affected uuid[]:='{}';mutation int:=0;response jsonb;stage text;
begin
 verified:=public.pdc_auditor_verify_envelope_253('apply',p_gateway_envelope);actor:=verified->'actor';if coalesce((verified->>'replay')::boolean,false) and verified->'stored_result' is not null then return verified->'stored_result';end if;perform pg_advisory_xact_lock(hashtextextended('pdc-253-proposal:'||p_proposal,0));select * into plan from public.pdc_auditor_typed_plans_253 where plan_id=p_proposal for share;
 if not found or plan.proposal_version<>p_proposal_version or plan.proposal_hash<>p_proposal_hash or plan.typed_item_set_hash<>p_typed_item_set_hash or plan.final_scope_hash<>p_final_scope_hash or plan.expected_row_versions_hash<>p_expected_row_versions_hash or p_gateway_envelope->'selected_scope'<>jsonb_build_object('contract','pdc-auditor-apply-selection-253-v1','proposal_id',p_proposal,'proposal_version',p_proposal_version,'proposal_hash',p_proposal_hash,'typed_item_set_hash',p_typed_item_set_hash,'final_scope_hash',p_final_scope_hash,'expected_row_versions_hash',p_expected_row_versions_hash) then raise exception 'PDC_253_EXACT_FINAL_PROPOSAL_REQUIRED' using errcode='40001';end if;
 if not exists(select 1 from public.pdc_auditor_signed_deliveries_253 d where d.delivery_uuid=plan.delivery_uuid and d.service_identity_id=(actor->>'service_identity_id')::uuid and d.service_auth_user_id=(actor->>'service_user_id')::uuid and d.service_email=actor->>'service_email' and d.authorizing_admin_user_id=(actor->>'admin_user_id')::uuid and d.authorizing_admin_email=actor->>'admin_email' and d.dealer_code=actor->>'dealer_code') then raise exception 'PDC_253_PROPOSAL_ACTOR_MISMATCH' using errcode='42501';end if;if p_gateway_envelope->'telegram_evidence'->>'original_instruction'<>'Apply these corrections' then raise exception 'PDC_253_EXACT_CRAIG_APPLY_REQUIRED' using errcode='42501';end if;if plan.proposed_count<1 then raise exception 'PDC_253_ZERO_PROPOSED_ITEMS' using errcode='22023';end if;if plan.ambiguous_count>0 and not plan.apply_unambiguous then raise exception 'PDC_253_AMBIGUITY_BLOCKS_ATOMIC_SCOPE' using errcode='42501';end if;if public.pdc_auditor_operational_revision(plan.dealer_code)<>plan.operational_revision then raise exception 'PDC_253_PROPOSAL_REVISION_STALE' using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-253-dealer:'||plan.dealer_code,0));
 lock table public.pdc_authenticated_email_operation_lines in share mode;
 if public.pdc_auditor_operational_revision(plan.dealer_code)<>plan.operational_revision then raise exception 'PDC_253_PROPOSAL_REVISION_STALE_AFTER_LOCK' using errcode='40001';end if;
 -- Lock and revalidate every effective reference before any operational write.
 for i in select * from public.pdc_auditor_typed_plan_items_253 where plan_id=p_proposal and disposition='proposed' order by sequence_no loop
  perform 1 from public.vehicles v where v.id=i.vehicle_id and v.deleted_at is null and v.lifecycle_state='active' and v.rft_collected_at is null and upper(btrim(coalesce(v.current_location,'')))<>'COMPLETED' for update;if not found then raise exception 'PDC_253_VEHICLE_PROTECTED' using errcode='42501';end if;perform 1 from public.vehicle_work_items wi where wi.vehicle_id=i.vehicle_id for update;if exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=i.vehicle_id and wi.completed and (wi.work_key in(select distinct x from unnest(array_remove(array[i.old_effective_value->>'work_key',i.new_effective_value->>'work_key'],null))x) or wi.work_key in(select distinct member->>'work_key' from jsonb_array_elements(case when jsonb_typeof(i.old_effective_value)='array' then i.old_effective_value else '[]'::jsonb end) member))) then raise exception 'PDC_253_AFFECTED_COMPLETED_WORK_PROTECTED' using errcode='42501';end if;perform 1 from public.vehicle_workshop_line_adjustments x where x.vehicle_id=i.vehicle_id for update;
  if i.operation_action in('edit','split') and not exists(select 1 from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=i.vehicle_id and coalesce(e.job_card_number,'')=i.job_card_number and e.operation_ref=i.operation_identifier and to_jsonb(e)=i.old_effective_value) then raise exception 'PDC_253_EFFECTIVE_ITEM_CHANGED' using errcode='40001';end if;
 if i.operation_action in('combine','reorder','remove_duplicate') and i.old_effective_value is distinct from coalesce((select jsonb_agg(to_jsonb(e) order by e.operation_ref) from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=i.vehicle_id and coalesce(e.job_card_number,'')=i.job_card_number and e.operation_ref=any(i.source_operation_identifiers) and e.active),'[]'::jsonb) then raise exception 'PDC_253_EFFECTIVE_MEMBER_SET_CHANGED' using errcode='40001';end if;
 if exists(select 1 from public.pdc_auditor_normalized_operation_lines_253 e where e.vehicle_id=i.vehicle_id and (e.operation_ref=i.operation_identifier or e.operation_ref=any(i.source_operation_identifiers)) and (e.manual_assignment_locked or coalesce(e.correction_origin,'') not in('','ai_auditor'))) then raise exception 'PDC_253_MEMBER_PROTECTED' using errcode='42501';end if;
 if i.operation_action='add' and coalesce(i.new_effective_value->>'operation_code','')<>'' and exists(select 1 from public.pdc_effective_operation_lines e where e.vehicle_id=i.vehicle_id and coalesce(e.job_card_number,'')=i.job_card_number and e.active and upper(coalesce(e.operation_code,''))=upper(i.new_effective_value->>'operation_code')) then raise exception 'PDC_253_ADD_OPERATION_CODE_CONFLICT' using errcode='40001';end if;
 end loop;
 -- The final sealed dealer revision is checked only after every source and mutable
 -- scope row is locked, immediately before the first operational/history write.
 if public.pdc_auditor_operational_revision(plan.dealer_code)<>plan.operational_revision then raise exception 'PDC_253_PROPOSAL_REVISION_STALE_AFTER_SCOPE_LOCKS' using errcode='40001';end if;
 insert into public.pdc_auditor_typed_runs_253 values(runid,p_proposal,(verified->>'delivery_uuid')::uuid,p_proposal_hash,plan.operational_revision,repeat('0',64),(actor->>'service_identity_id')::uuid,(actor->>'service_user_id')::uuid,actor->>'service_email',(actor->>'admin_user_id')::uuid,actor->>'admin_email',p_gateway_envelope->>'gateway_instance_id',p_gateway_envelope->>'key_id',p_gateway_envelope->>'nonce',p_gateway_envelope->'telegram_evidence'->>'original_instruction',p_gateway_envelope->>'instruction_sha256',plan.proposed_count,'available',clock_timestamp());
 -- Capture ALL whole-scope before snapshots before the first operation write.
 insert into public.pdc_auditor_typed_scope_receipts_253(run_id,vehicle_id,job_card_number,before_snapshot) select runid,s.vehicle_id,s.job_card_number,public.pdc_auditor_typed_snapshot_253(s.vehicle_id,s.job_card_number) from(select distinct vehicle_id,job_card_number from public.pdc_auditor_typed_plan_items_253 where plan_id=p_proposal and disposition='proposed')s;
 for i in select * from public.pdc_auditor_typed_plan_items_253 where plan_id=p_proposal and disposition='proposed' order by sequence_no loop
  affected:=array_append(affected,i.vehicle_id);
  if i.operation_action='add' then
   stage:=public.workshop_stage_code_for_work_key(i.new_effective_value->>'work_key');insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,job_card_number) values(i.vehicle_id,'auditor:253:'||i.plan_item_id,'manual',stage,i.new_effective_value->>'description',(i.new_effective_value->>'estimated_hours')::numeric,true,1,(actor->>'service_user_id')::uuid,(actor->>'service_user_id')::uuid,nullif(i.new_effective_value->>'operation_code',''),(i.new_effective_value->>'ordered_position')::int,false,'ai_auditor',i.job_card_number) returning * into a;mutation:=mutation+1;insert into public.pdc_auditor_typed_change_receipts_253 values(gen_random_uuid(),runid,i.plan_item_id,mutation,i.vehicle_id,i.job_card_number,'auditor:'||a.adjustment_id::text,a.adjustment_id,null,to_jsonb(a),i.reason,i.server_rule_evidence,clock_timestamp());
  elsif i.operation_action='edit' then
   select * into source from public.pdc_authenticated_email_operation_lines where operation_line_id=case when i.operation_identifier like 'source:%' then substring(i.operation_identifier from 8)::uuid else null end;select to_jsonb(x) into beforea from public.vehicle_workshop_line_adjustments x where x.vehicle_id=i.vehicle_id and (x.line_key=i.operation_identifier or x.adjustment_id=case when i.operation_identifier like 'auditor:%' then substring(i.operation_identifier from 9)::uuid else null end);stage:=public.workshop_stage_code_for_work_key(coalesce(i.new_effective_value->>'work_key',i.old_effective_value->>'work_key'));if i.operation_identifier like 'auditor:%' then update public.vehicle_workshop_line_adjustments set stage_code=stage,description=coalesce(i.new_effective_value->>'description',i.old_effective_value->>'description'),estimated_hours=coalesce((i.new_effective_value->>'estimated_hours')::numeric,(i.old_effective_value->>'estimated_hours')::numeric),operation_code=coalesce(i.new_effective_value->>'operation_code',i.old_effective_value->>'operation_code'),display_order=coalesce((i.new_effective_value->>'ordered_position')::int,(i.old_effective_value->>'display_order')::int),active=true,version=version+1,updated_by=(actor->>'service_user_id')::uuid,updated_at=clock_timestamp(),correction_origin='ai_auditor' where adjustment_id=substring(i.operation_identifier from 9)::uuid returning * into a;else insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number) values(i.vehicle_id,i.operation_identifier,'source',stage,coalesce(i.new_effective_value->>'description',i.old_effective_value->>'description'),coalesce((i.new_effective_value->>'estimated_hours')::numeric,(i.old_effective_value->>'estimated_hours')::numeric),true,1,(actor->>'service_user_id')::uuid,(actor->>'service_user_id')::uuid,coalesce(i.new_effective_value->>'operation_code',i.old_effective_value->>'operation_code'),coalesce((i.new_effective_value->>'ordered_position')::int,(i.old_effective_value->>'display_order')::int),false,'ai_auditor',source.operation_line_id,i.job_card_number) on conflict(vehicle_id,line_key) do update set stage_code=excluded.stage_code,description=excluded.description,estimated_hours=excluded.estimated_hours,operation_code=excluded.operation_code,display_order=excluded.display_order,active=true,version=vehicle_workshop_line_adjustments.version+1,updated_by=excluded.updated_by,updated_at=clock_timestamp(),correction_origin='ai_auditor' returning * into a;end if;mutation:=mutation+1;insert into public.pdc_auditor_typed_change_receipts_253 values(gen_random_uuid(),runid,i.plan_item_id,mutation,i.vehicle_id,i.job_card_number,i.operation_identifier,a.adjustment_id,beforea,to_jsonb(a),i.reason,i.server_rule_evidence,clock_timestamp());
  elsif i.operation_action='split' then
   -- Deactivate exact parent (upserting source overlay if imported), then create deterministic complete children.
   select * into source from public.pdc_authenticated_email_operation_lines where operation_line_id=case when i.operation_identifier like 'source:%' then substring(i.operation_identifier from 8)::uuid else null end;select to_jsonb(x) into beforea from public.vehicle_workshop_line_adjustments x where x.vehicle_id=i.vehicle_id and (x.line_key=i.operation_identifier or x.adjustment_id=case when i.operation_identifier like 'auditor:%' then substring(i.operation_identifier from 9)::uuid else null end);if i.operation_identifier like 'auditor:%' then update public.vehicle_workshop_line_adjustments set active=false,version=version+1,updated_by=(actor->>'service_user_id')::uuid,updated_at=clock_timestamp(),correction_origin='ai_auditor' where adjustment_id=substring(i.operation_identifier from 9)::uuid returning * into a;else insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number) values(i.vehicle_id,i.operation_identifier,'source',public.workshop_stage_code_for_work_key(i.old_effective_value->>'work_key'),i.old_effective_value->>'description',(i.old_effective_value->>'estimated_hours')::numeric,false,1,(actor->>'service_user_id')::uuid,(actor->>'service_user_id')::uuid,i.old_effective_value->>'operation_code',(i.old_effective_value->>'display_order')::int,false,'ai_auditor',source.operation_line_id,i.job_card_number) on conflict(vehicle_id,line_key) do update set active=false,version=vehicle_workshop_line_adjustments.version+1,updated_by=excluded.updated_by,updated_at=clock_timestamp(),correction_origin='ai_auditor' returning * into a;end if;mutation:=mutation+1;insert into public.pdc_auditor_typed_change_receipts_253 values(gen_random_uuid(),runid,i.plan_item_id,mutation,i.vehicle_id,i.job_card_number,i.operation_identifier,a.adjustment_id,beforea,to_jsonb(a),i.reason,i.server_rule_evidence,clock_timestamp());pos:=0;for child in select value from jsonb_array_elements(i.new_effective_value->'children') loop pos:=pos+1;insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,job_card_number) values(i.vehicle_id,'auditor:253:split:'||i.plan_item_id||':'||lpad(pos::text,2,'0'),'manual',public.workshop_stage_code_for_work_key(child->>'work_key'),child->>'description',(child->>'estimated_hours')::numeric,true,1,(actor->>'service_user_id')::uuid,(actor->>'service_user_id')::uuid,nullif(child->>'operation_code',''),(i.old_effective_value->>'display_order')::int+pos-1,false,'ai_auditor',i.job_card_number) returning * into a;mutation:=mutation+1;insert into public.pdc_auditor_typed_change_receipts_253 values(gen_random_uuid(),runid,i.plan_item_id,mutation,i.vehicle_id,i.job_card_number,'auditor:'||a.adjustment_id::text,a.adjustment_id,null,to_jsonb(a),i.reason,i.server_rule_evidence,clock_timestamp());end loop;
  else
   pos:=0;for ref in select unnest(i.source_operation_identifiers) loop pos:=pos+1;beforea:=null;a:=null;source:=null;select to_jsonb(x) into beforea from public.vehicle_workshop_line_adjustments x where x.vehicle_id=i.vehicle_id and (x.adjustment_id=case when ref like 'auditor:%' then substring(ref from 9)::uuid else null end or x.line_key=ref);select * into source from public.pdc_authenticated_email_operation_lines where operation_line_id=case when ref like 'source:%' then substring(ref from 8)::uuid else null end;
    if i.operation_action='reorder' then
     select * into a from public.vehicle_workshop_line_adjustments x where x.vehicle_id=i.vehicle_id and (x.adjustment_id=case when ref like 'auditor:%' then substring(ref from 9)::uuid else null end or x.line_key=ref);if not found then select * into source from public.pdc_authenticated_email_operation_lines where operation_line_id=case when ref like 'source:%' then substring(ref from 8)::uuid else null end;insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number) values(i.vehicle_id,ref,'source',public.workshop_stage_code_for_work_key(source.work_key),source.description,source.estimated_hours,true,1,(actor->>'service_user_id')::uuid,(actor->>'service_user_id')::uuid,source.operation_no,pos,false,'ai_auditor',source.operation_line_id,i.job_card_number) returning * into a;else update public.vehicle_workshop_line_adjustments set display_order=pos,version=version+1,updated_by=(actor->>'service_user_id')::uuid,updated_at=clock_timestamp(),correction_origin='ai_auditor' where adjustment_id=a.adjustment_id returning * into a;end if;
    elsif ref=i.survivor_operation_identifier then
     if i.operation_action='combine' then update public.vehicle_workshop_line_adjustments set description=i.new_effective_value->>'description',estimated_hours=(i.new_effective_value->>'estimated_hours')::numeric,operation_code=i.new_effective_value->>'operation_code',stage_code=public.workshop_stage_code_for_work_key(i.new_effective_value->>'work_key'),active=true,version=version+1,updated_by=(actor->>'service_user_id')::uuid,updated_at=clock_timestamp(),correction_origin='ai_auditor' where vehicle_id=i.vehicle_id and (adjustment_id=case when ref like 'auditor:%' then substring(ref from 9)::uuid else null end or line_key=ref) returning * into a;if not found then select * into source from public.pdc_authenticated_email_operation_lines where operation_line_id=case when ref like 'source:%' then substring(ref from 8)::uuid else null end;insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number) values(i.vehicle_id,ref,'source',public.workshop_stage_code_for_work_key(i.new_effective_value->>'work_key'),i.new_effective_value->>'description',(i.new_effective_value->>'estimated_hours')::numeric,true,1,(actor->>'service_user_id')::uuid,(actor->>'service_user_id')::uuid,i.new_effective_value->>'operation_code',pos,false,'ai_auditor',source.operation_line_id,i.job_card_number) returning * into a;end if;else continue;end if;
    else
     update public.vehicle_workshop_line_adjustments set active=false,version=version+1,updated_by=(actor->>'service_user_id')::uuid,updated_at=clock_timestamp(),correction_origin='ai_auditor' where vehicle_id=i.vehicle_id and (adjustment_id=case when ref like 'auditor:%' then substring(ref from 9)::uuid else null end or line_key=ref) returning * into a;if not found then select * into source from public.pdc_authenticated_email_operation_lines where operation_line_id=case when ref like 'source:%' then substring(ref from 8)::uuid else null end;insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number) values(i.vehicle_id,ref,'source',public.workshop_stage_code_for_work_key(source.work_key),source.description,source.estimated_hours,false,1,(actor->>'service_user_id')::uuid,(actor->>'service_user_id')::uuid,source.operation_no,source.source_row_no,false,'ai_auditor',source.operation_line_id,i.job_card_number) returning * into a;end if;
    end if;mutation:=mutation+1;insert into public.pdc_auditor_typed_change_receipts_253 values(gen_random_uuid(),runid,i.plan_item_id,mutation,i.vehicle_id,i.job_card_number,ref,a.adjustment_id,beforea,to_jsonb(a),i.reason,i.server_rule_evidence,clock_timestamp());
   end loop;
  end if;
 end loop;
 -- Recalculate once per affected vehicle, then seal every complete final scope snapshot.
 perform public.pdc_auditor_recalculate_required_work_253(affected);insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) select 'update','vehicle_workshop_line_adjustments',c.adjustment_id,c.vehicle_id,(actor->>'service_user_id')::uuid,actor->>'service_email',c.overlay_before,c.overlay_after,jsonb_build_object('source','ai_auditor_typed_253','run_id',runid,'plan_id',p_proposal,'operation_identifier',c.operation_identifier,'bookings_changed',false,'dates_changed',false,'vehicle_state_changed',false,'location_changed',false,'completion_changed',false,'users_changed',false,'pricing_changed',false) from public.pdc_auditor_typed_change_receipts_253 c where c.run_id=runid;
 update public.pdc_auditor_typed_scope_receipts_253 s set after_snapshot=public.pdc_auditor_typed_snapshot_253(s.vehicle_id,s.job_card_number) where s.run_id=runid;update public.pdc_auditor_typed_runs_253 set run_revision_after=public.pdc_auditor_operational_revision(plan.dealer_code) where run_id=runid;insert into public.pdc_auditor_workshop_revisions(dealer_code,environment,event_type,run_id,rollback_receipt_id,typed_run_id_253) values(plan.dealer_code,'staging','typed_plan_applied_253',null,null,runid);
 response:=jsonb_build_object('ok',true,'code','typed_plan_applied_253','data',jsonb_build_object('run_id',runid,'applied_count',plan.proposed_count,'queued_ambiguous_count',plan.ambiguous_count,'undo_state','available'));insert into public.pdc_auditor_signed_delivery_results_253 values((verified->>'delivery_uuid')::uuid,verified->>'request_content_hash',response,clock_timestamp());return response;
end $apply$;

create function public.undo_last_pdc_auditor_typed_run_253(p_gateway_envelope jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $undo$
declare verified jsonb;actor jsonb;r public.pdc_auditor_typed_runs_253%rowtype;s record;c record;current jsonb;a public.vehicle_workshop_line_adjustments%rowtype;affected uuid[]:='{}';count int:=0;response jsonb;selected_run uuid;selected_revision text;
begin
 verified:=public.pdc_auditor_verify_envelope_253('undo',p_gateway_envelope);actor:=verified->'actor';if coalesce((verified->>'replay')::boolean,false) and verified->'stored_result' is not null then return verified->'stored_result';end if;if p_gateway_envelope->'telegram_evidence'->>'original_instruction'<>'Undo the selected Auditor run' or (select array_agg(k order by k) from jsonb_object_keys(p_gateway_envelope->'selected_scope')k)<>array['contract','run_id','run_revision_after']::text[] or p_gateway_envelope->'selected_scope'->>'contract'<>'pdc-auditor-undo-selection-253-v1' or p_gateway_envelope->'selected_scope'->>'run_revision_after'!~'^[a-f0-9]{64}$' then raise exception 'PDC_253_EXACT_UNDO_SELECTION_REQUIRED' using errcode='42501';end if;selected_run:=(p_gateway_envelope->'selected_scope'->>'run_id')::uuid;selected_revision:=p_gateway_envelope->'selected_scope'->>'run_revision_after';perform pg_advisory_xact_lock(hashtextextended('pdc-253-undo:'||(actor->>'dealer_code'),0));select x.* into r from public.pdc_auditor_typed_runs_253 x join public.pdc_auditor_typed_plans_253 p using(plan_id) where x.run_id=selected_run and x.run_revision_after=selected_revision and p.dealer_code=actor->>'dealer_code' and x.service_identity_id=(actor->>'service_identity_id')::uuid and x.service_auth_user_id=(actor->>'service_user_id')::uuid and x.service_email=actor->>'service_email' and x.authorizing_admin_user_id=(actor->>'admin_user_id')::uuid and x.authorizing_admin_email=actor->>'admin_email' and x.undo_state='available' for update;if not found then raise exception 'PDC_253_RUN_NOT_UNDOABLE' using errcode='P0002';end if;
 lock table public.pdc_authenticated_email_operation_lines in share mode;
 -- Lock every mutable relation contributing to each final scope before comparing it.
 for s in select * from public.pdc_auditor_typed_scope_receipts_253 where run_id=r.run_id order by vehicle_id,job_card_number loop
  perform 1 from public.vehicles v where v.id=s.vehicle_id for update;
  perform 1 from public.vehicle_work_items wi where wi.vehicle_id=s.vehicle_id for update;
  perform 1 from public.vehicle_workshop_line_adjustments overlay_row where overlay_row.vehicle_id=s.vehicle_id and coalesce(overlay_row.job_card_number,'')=s.job_card_number for update;
  current:=public.pdc_auditor_typed_snapshot_253(s.vehicle_id,s.job_card_number);if current<>s.after_snapshot then raise exception 'PDC_253_STRICT_UNDO_SCOPE_CONFLICT' using errcode='40001';end if;
 end loop;
 for c in select * from public.pdc_auditor_typed_change_receipts_253 where run_id=r.run_id order by mutation_sequence loop perform 1 from public.vehicle_workshop_line_adjustments x where x.adjustment_id=c.adjustment_id and to_jsonb(x)=c.overlay_after for update;if not found then raise exception 'PDC_253_STRICT_UNDO_OVERLAY_CONFLICT' using errcode='40001';end if;end loop;
 for c in select * from public.pdc_auditor_typed_change_receipts_253 where run_id=r.run_id order by mutation_sequence desc loop if c.overlay_before is null then update public.vehicle_workshop_line_adjustments set active=false,version=version+1,updated_by=(actor->>'service_user_id')::uuid,updated_at=clock_timestamp(),correction_origin='ai_auditor_rolled_back' where adjustment_id=c.adjustment_id returning * into a;else update public.vehicle_workshop_line_adjustments set line_key=c.overlay_before->>'line_key',source_kind=c.overlay_before->>'source_kind',stage_code=c.overlay_before->>'stage_code',description=c.overlay_before->>'description',estimated_hours=(c.overlay_before->>'estimated_hours')::numeric,active=(c.overlay_before->>'active')::boolean,operation_code=c.overlay_before->>'operation_code',display_order=nullif(c.overlay_before->>'display_order','')::int,manual_assignment_locked=(c.overlay_before->>'manual_assignment_locked')::boolean,correction_origin=c.overlay_before->>'correction_origin',source_operation_line_id=nullif(c.overlay_before->>'source_operation_line_id','')::uuid,job_card_number=c.overlay_before->>'job_card_number',version=version+1,updated_by=(actor->>'service_user_id')::uuid,updated_at=clock_timestamp() where adjustment_id=c.adjustment_id returning * into a;end if;affected:=array_append(affected,c.vehicle_id);count:=count+1;end loop;
 -- Restore required-work state from the sealed before snapshots. Recalculation is not
 -- exact Undo because it can create requirements that were absent before Apply.
 for s in select * from public.pdc_auditor_typed_scope_receipts_253 where run_id=r.run_id loop
  update public.vehicle_work_items wi set required=false,updated_at=clock_timestamp() where wi.vehicle_id=s.vehicle_id and not wi.completed;
  update public.vehicle_work_items wi set required=true,updated_at=clock_timestamp() where wi.vehicle_id=s.vehicle_id and not wi.completed and wi.id in(select (x->>'id')::uuid from jsonb_array_elements(s.before_snapshot->'required_work_identifiers')x where (x->>'required')::boolean);
  if public.pdc_auditor_typed_snapshot_253(s.vehicle_id,s.job_card_number)<>s.before_snapshot then raise exception 'PDC_253_UNDO_BEFORE_STATE_NOT_RESTORED' using errcode='40001';end if;
 end loop;
 -- Exact seal transition occurs only after all restoration and verification succeeds.
 update public.pdc_auditor_typed_runs_253 set undo_state='undone' where run_id=r.run_id;response:=jsonb_build_object('ok',true,'code','typed_run_undone_253','data',jsonb_build_object('run_id',r.run_id,'restored_count',count,'conflict_count',0,'undo_state','undone'));insert into public.pdc_auditor_typed_undo_receipts_253 values(gen_random_uuid(),r.run_id,(verified->>'delivery_uuid')::uuid,count,true,response,clock_timestamp());insert into public.pdc_auditor_workshop_revisions(dealer_code,environment,event_type,run_id,rollback_receipt_id,typed_run_id_253) values(actor->>'dealer_code','staging','typed_run_undone_253',null,null,r.run_id);insert into public.pdc_auditor_signed_delivery_results_253 values((verified->>'delivery_uuid')::uuid,verified->>'request_content_hash',response,clock_timestamp());return response;
end $undo$;

create function public.query_pdc_auditor_typed_253(p_action text,p_scope jsonb,p_gateway_envelope jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $query$ declare verified jsonb;actor jsonb;data jsonb;keys text[];response jsonb;begin
 keys:=(select array_agg(k order by k) from jsonb_object_keys(p_scope)k);
 if p_scope is distinct from p_gateway_envelope->'selected_scope' or p_scope->>'contract'<>'pdc-auditor-query-selection-253-v1' or (p_action='operation_snapshot' and keys<>array['contract','job_card_number','vehicle_id']::text[]) or (p_action='plan_receipt' and keys<>array['contract','plan_id']::text[]) or (p_action='run_receipt' and keys<>array['contract','run_id']::text[]) or p_action not in('operation_snapshot','plan_receipt','run_receipt') then raise exception 'PDC_253_INVALID_QUERY' using errcode='22023';end if;
 verified:=public.pdc_auditor_verify_envelope_253('query',p_gateway_envelope);actor:=verified->'actor';if coalesce((verified->>'replay')::boolean,false) and verified->'stored_result' is not null then return verified->'stored_result';end if;if p_action='operation_snapshot' then select public.pdc_auditor_typed_snapshot_253((p_scope->>'vehicle_id')::uuid,p_scope->>'job_card_number') into data where public.pdc_auditor_vehicle_dealer((p_scope->>'vehicle_id')::uuid)=actor->>'dealer_code';elsif p_action='plan_receipt' then select jsonb_build_object('plan',to_jsonb(p),'items',coalesce(jsonb_agg(to_jsonb(i) order by i.sequence_no),'[]')) into data from public.pdc_auditor_typed_plans_253 p left join public.pdc_auditor_typed_plan_items_253 i using(plan_id) where p.plan_id=(p_scope->>'plan_id')::uuid and p.dealer_code=actor->>'dealer_code' group by p.plan_id;else select jsonb_build_object('run',to_jsonb(r),'scopes',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.pdc_auditor_typed_scope_receipts_253 s where s.run_id=r.run_id),'changes',(select coalesce(jsonb_agg(to_jsonb(c) order by c.mutation_sequence),'[]') from public.pdc_auditor_typed_change_receipts_253 c where c.run_id=r.run_id)) into data from public.pdc_auditor_typed_runs_253 r join public.pdc_auditor_typed_plans_253 p using(plan_id) where r.run_id=(p_scope->>'run_id')::uuid and p.dealer_code=actor->>'dealer_code';end if;response:=jsonb_build_object('ok',true,'code',p_action,'data',data);insert into public.pdc_auditor_signed_delivery_results_253 values((verified->>'delivery_uuid')::uuid,verified->>'request_content_hash',response,clock_timestamp());return response;end $query$;

-- Human Administrator browser Realtime only: exact auth UUID/email, approved active
-- role and active dealer/environment enrollment. Viewer/Monitor/Importer and the
-- scoped service identity are deliberately denied.
create function public.pdc_auditor_human_admin_revision_read_253(p_dealer text) returns boolean language sql stable security definer set search_path=pg_catalog,public,auth as $read$
 select exists(select 1 from public.pdc_user_roles r join auth.users au on au.id=auth.uid() and lower(coalesce(au.email,''))=lower(btrim(coalesce(auth.jwt()->>'email',''))) join public.pdc_auditor_user_dealer_scopes s on s.auth_user_id=auth.uid() and s.normalized_email=lower(btrim(coalesce(auth.jwt()->>'email',''))) and s.dealer_code=p_dealer and s.environment='staging' and s.active where r.auth_user_id=auth.uid() and lower(r.email)=lower(btrim(coalesce(auth.jwt()->>'email',''))) and r.active and r.account_status='approved' and r.approved_at is not null and r.disabled_at is null and r.role::text='administrator')
$read$;
revoke all on function public.pdc_auditor_human_admin_revision_read_253(text) from public,anon,authenticated,service_role;
grant execute on function public.pdc_auditor_human_admin_revision_read_253(text) to authenticated;
do $revision_read_policy$ declare p record;begin for p in select policyname from pg_policies where schemaname='public' and tablename='pdc_auditor_workshop_revisions' and cmd in('SELECT','ALL') loop execute format('drop policy %I on public.pdc_auditor_workshop_revisions',p.policyname);end loop;end $revision_read_policy$;
revoke all on public.pdc_auditor_workshop_revisions from public,anon,authenticated,service_role;
grant select(revision_id,dealer_code,environment,event_type,run_id,rollback_receipt_id,created_at,typed_run_id_253) on public.pdc_auditor_workshop_revisions to authenticated;
create policy pdc_auditor_workshop_revisions_admin_read_253 on public.pdc_auditor_workshop_revisions for select to authenticated using(environment='staging' and public.pdc_auditor_human_admin_revision_read_253(dealer_code));
revoke all on sequence public.pdc_auditor_workshop_revisions_revision_id_seq from public,anon,authenticated,service_role;

revoke all on function public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb) from public,anon,authenticated,service_role;grant execute on function public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb) to authenticated;
revoke all on function public.compose_pdc_auditor_typed_plan_253(uuid[],jsonb) from public,anon,authenticated,service_role;grant execute on function public.compose_pdc_auditor_typed_plan_253(uuid[],jsonb) to authenticated;
revoke all on function public.apply_pdc_auditor_typed_plan_253(uuid,integer,text,text,text,text,jsonb) from public,anon,authenticated,service_role;grant execute on function public.apply_pdc_auditor_typed_plan_253(uuid,integer,text,text,text,text,jsonb) to authenticated;
revoke all on function public.undo_last_pdc_auditor_typed_run_253(jsonb) from public,anon,authenticated,service_role;grant execute on function public.undo_last_pdc_auditor_typed_run_253(jsonb) to authenticated;
revoke all on function public.query_pdc_auditor_typed_253(text,jsonb,jsonb) from public,anon,authenticated,service_role;grant execute on function public.query_pdc_auditor_typed_253(text,jsonb,jsonb) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('253','ai_auditor_typed_operation_control',array['exact migration-250 name and statement predecessor with migrations 251/252 unused','global migration-230 Telegram message/update reservation plus exact 253 delivery UUID and gateway nonce replay control','exact ISO-UTC ten-field runtime envelope with length-prefixed ordered signing bytes and top-level Telegram evidence','bounded contract/action/selector/desire intent expanded server-side; caller candidates, old values, disposition and proof forbidden','separate signed Apply binds exact plan_id and plan_hash plus exact Craig confirmation instruction','source and auditor namespaces remain disjoint text refs across edit split combine reorder and duplicate operations','migration-228 duplicate proof requires source UID and fingerprint, distinct source hashes and rejects variant quantity kit side and stage ambiguity','only affected current and target work keys protect completed work; unrelated completed departments do not block','logical effective snapshots exclude inactive tombstones and false non-completed requirements while preserving append-only rows and stable effective IDs','strict whole-run Undo preflights final scope receipts once, restores reverse mutations, verifies exact initial logical scopes, then seals undone','Administrator browser Realtime SELECT requires exact active approved role and active auth UUID/email/dealer/environment scope; no DML sequence or key provisioning authority']);
notify pgrst,'reload schema';
commit;
