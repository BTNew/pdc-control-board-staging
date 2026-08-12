-- Staging-only migration 231: close migration-230 installation race and prove registry coverage.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-231-auditor-delivery-registry-reconciliation',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='230')
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>230)
     or exists(select 1 from supabase_migrations.schema_migrations where version='231')
     or to_regclass('public.pdc_auditor_telegram_deliveries_230') is null then
    raise exception 'PDC_231_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

-- Deterministic lock order. SHARE ROW EXCLUSIVE blocks concurrent INSERT/UPDATE/DELETE
-- while allowing reads. Holding all three locks through commit closes the migration-230
-- scan/backfill/trigger-install race before reconciliation begins.
lock table public.pdc_auditor_telegram_instructions_225 in share row exclusive mode;
lock table public.pdc_auditor_rule_commands_227 in share row exclusive mode;
lock table public.pdc_auditor_telegram_deliveries_230 in share row exclusive mode;

-- Fail closed if any cross-domain collision entered during migration 230's installation window.
do $collision$
begin
  if exists(
    select 1
    from public.pdc_auditor_telegram_instructions_225 o
    join public.pdc_auditor_rule_commands_227 r
      on (r.telegram_chat_id,r.telegram_message_id)=(o.telegram_chat_id,o.telegram_message_id)
      or (r.bot_identity,r.telegram_update_id)=(o.bot_identity,o.telegram_update_id)
  ) then
    raise exception 'PDC_231_CROSS_DOMAIN_DELIVERY_CONFLICT' using errcode='23505';
  end if;
end
$collision$;

-- Reconcile any source row that committed after migration 230's backfill snapshot but before
-- its trigger was installed. Existing correctly registered rows are not rewritten.
insert into public.pdc_auditor_telegram_deliveries_230(
  delivery_domain,telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,
  bot_identity,original_instruction,instruction_sha256,source_table,source_id,reserved_at
)
select 'operation',o.telegram_sender_id,o.telegram_chat_id,o.telegram_message_id,o.telegram_update_id,
  o.bot_identity,o.original_instruction,o.instruction_sha256,
  'pdc_auditor_telegram_instructions_225',o.instruction_id,o.received_at
from public.pdc_auditor_telegram_instructions_225 o
where not exists(
  select 1 from public.pdc_auditor_telegram_deliveries_230 d
  where d.source_table='pdc_auditor_telegram_instructions_225' and d.source_id=o.instruction_id
);

insert into public.pdc_auditor_telegram_deliveries_230(
  delivery_domain,telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,
  bot_identity,original_instruction,instruction_sha256,source_table,source_id,reserved_at
)
select 'rule',r.telegram_sender_id,r.telegram_chat_id,r.telegram_message_id,r.telegram_update_id,
  r.bot_identity,r.original_instruction,r.instruction_sha256,
  'pdc_auditor_rule_commands_227',r.command_id,r.received_at
from public.pdc_auditor_rule_commands_227 r
where not exists(
  select 1 from public.pdc_auditor_telegram_deliveries_230 d
  where d.source_table='pdc_auditor_rule_commands_227' and d.source_id=r.command_id
);

-- Exact bidirectional coverage and evidence equality. This detects missing, orphaned,
-- misclassified or altered registry rows rather than relying on counts alone.
do $coverage$
begin
  if exists(
    select 1 from public.pdc_auditor_telegram_instructions_225 o
    left join public.pdc_auditor_telegram_deliveries_230 d
      on d.source_table='pdc_auditor_telegram_instructions_225' and d.source_id=o.instruction_id
    where d.delivery_id is null or d.delivery_domain<>'operation'
      or d.telegram_sender_id<>o.telegram_sender_id or d.telegram_chat_id<>o.telegram_chat_id
      or d.telegram_message_id<>o.telegram_message_id or d.telegram_update_id<>o.telegram_update_id
      or d.bot_identity<>o.bot_identity or d.original_instruction<>o.original_instruction
      or d.instruction_sha256<>o.instruction_sha256
  ) or exists(
    select 1 from public.pdc_auditor_rule_commands_227 r
    left join public.pdc_auditor_telegram_deliveries_230 d
      on d.source_table='pdc_auditor_rule_commands_227' and d.source_id=r.command_id
    where d.delivery_id is null or d.delivery_domain<>'rule'
      or d.telegram_sender_id<>r.telegram_sender_id or d.telegram_chat_id<>r.telegram_chat_id
      or d.telegram_message_id<>r.telegram_message_id or d.telegram_update_id<>r.telegram_update_id
      or d.bot_identity<>r.bot_identity or d.original_instruction<>r.original_instruction
      or d.instruction_sha256<>r.instruction_sha256
  ) or exists(
    select 1 from public.pdc_auditor_telegram_deliveries_230 d
    where (d.source_table='pdc_auditor_telegram_instructions_225' and not exists(
      select 1 from public.pdc_auditor_telegram_instructions_225 o where o.instruction_id=d.source_id
    )) or (d.source_table='pdc_auditor_rule_commands_227' and not exists(
      select 1 from public.pdc_auditor_rule_commands_227 r where r.command_id=d.source_id
    ))
  ) then
    raise exception 'PDC_231_DELIVERY_REGISTRY_COVERAGE_MISMATCH' using errcode='55000';
  end if;
end
$coverage$;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '231','auditor_delivery_registry_reconciliation',array[
    'staging sentinel cdsmnqxtyyoeoznmbidd and exact predecessor 230',
    'deterministically lock operation, rule and global delivery tables against concurrent inserts',
    'fail closed on any cross-domain message or update collision',
    'reconcile migration-230 installation-window source rows into the global registry',
    'assert exact bidirectional one-to-one registry coverage and evidence equality',
    'production untouched'
  ]
);
commit;
