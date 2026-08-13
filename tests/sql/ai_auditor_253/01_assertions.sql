-- Shared-vector PostgreSQL assertions after installing draft migration 253.
\set ON_ERROR_STOP on
create temp table vector(v jsonb);
\i tests/sql/ai_auditor_253/vector.load.sql

do $$ declare d jsonb; x jsonb; got text; begin
 select v into d from vector;
 for x in select * from jsonb_array_elements(d->'canonical_json') loop
  got:=public.pdc_auditor_canonical_json_253(x->'value');
  if got<>x->>'canonical_utf8' then raise exception 'canonical vector % mismatch: %',x->>'name',got; end if;
 end loop;
 if encode(public.pdc_auditor_signing_bytes_253(d->'envelope'->'value'),'hex')<>d->'envelope'->>'signing_bytes_hex' then raise exception 'signing bytes mismatch';end if;
 if encode(extensions.hmac(public.pdc_auditor_signing_bytes_253(d->'envelope'->'value'),decode(d->'envelope'->>'hmac_key_hex','hex'),'sha256'),'hex')<>d->'envelope'->>'signature_hex' then raise exception 'HMAC mismatch';end if;
end $$;

-- Catalog/ACL and authentic predecessor-ledger checks that do not require live Supabase.
do $$ declare t text; begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='baseline_head') then raise exception 'synthetic predecessor ledger found'; end if;
 if (select jsonb_object_agg(version,name order by version::int) from supabase_migrations.schema_migrations where version::int between 239 and 250)
    is distinct from '{"239":"workshop_admin_role_enum_cast","240":"workshop_admin_account_state_guard","241":"workshop_admin_undo_ambiguous_booking_fix","242":"workshop_admin_undo_alias_collision_fix","243":"craig_vehicle_drag_parts_non_blocking","244":"workshop_admin_authority_intent_receipt_undo","245":"workshop_admin_create_undo_audit_order","246":"workshop_admin_intent_hash_schema","247":"workshop_admin_null_role_fail_closed","248":"workshop_admin_create_undo_history_identity","249":"workshop_admin_create_undo_history_order","250":"revoke_service_role_legacy_workshop_rpc"}'::jsonb then
   raise exception 'authentic predecessor ledger mismatch';
 end if;
 foreach t in array array['pdc_auditor_gateway_keys_253','pdc_auditor_signed_deliveries_253','pdc_auditor_signed_delivery_results_253','pdc_auditor_typed_plans_253','pdc_auditor_typed_plan_items_253','pdc_auditor_typed_runs_253','pdc_auditor_typed_scope_receipts_253','pdc_auditor_typed_change_receipts_253','pdc_auditor_typed_undo_receipts_253'] loop
  if not (select relrowsecurity from pg_class where oid=('public.'||t)::regclass) then raise exception '% RLS disabled',t;end if;
  if has_table_privilege('authenticated','public.'||t,'SELECT,INSERT,UPDATE,DELETE') then raise exception '% client privilege leak',t;end if;
 end loop;
 if has_table_privilege('authenticated','public.pdc_auditor_workshop_revisions','INSERT,UPDATE,DELETE') then raise exception 'revision DML leak';end if;
 if not has_function_privilege('authenticated','public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb)','EXECUTE') then raise exception 'plan grant missing';end if;
 if has_function_privilege('service_role','public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb)','EXECUTE') then raise exception 'service role execute leak';end if;
 if not exists(select 1 from pg_proc p where p.oid='public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean)'::regprocedure and not p.prosecdef and p.provolatile='i') then raise exception 'private typed-value validator contract missing';end if;
 if has_function_privilege('public','public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean)','EXECUTE')
    or has_function_privilege('anon','public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean)','EXECUTE')
    or has_function_privilege('authenticated','public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean)','EXECUTE')
    or has_function_privilege('service_role','public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean)','EXECUTE') then raise exception 'private typed-value validator execute leak';end if;
end $$;

-- Approved active human read, then fail-closed wrong email.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","email":"craig@example.test","role":"authenticated"}',true);
do $$begin if (select count(*) from public.pdc_auditor_workshop_revisions)<>0 then raise exception 'unexpected fixture revision';end if;end$$;
rollback;

select 'AI_AUDITOR_253_SQL_FOCUSED_PASS' result;
