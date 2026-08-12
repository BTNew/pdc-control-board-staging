-- Staging-only migration 230: close cross-domain Telegram replay and arbitrary rule creation.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-230-auditor-authorization-hardening',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='229')
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>229)
     or exists(select 1 from supabase_migrations.schema_migrations where version='230') then
    raise exception 'PDC_230_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

-- One immutable reservation domain for every Telegram delivery, regardless of which RPC
-- consumes it. This prevents a valid operation instruction being repurposed as a rule
-- instruction (or the reverse) while preserving exact replay inside the owning RPC.
create table public.pdc_auditor_telegram_deliveries_230 (
  delivery_id uuid primary key default gen_random_uuid(),
  delivery_domain text not null check (delivery_domain in ('operation','rule')),
  telegram_sender_id bigint not null,
  telegram_chat_id bigint not null,
  telegram_message_id bigint not null check (telegram_message_id>0),
  telegram_update_id bigint not null check (telegram_update_id>=0),
  bot_identity text not null,
  original_instruction text not null,
  instruction_sha256 text not null check (instruction_sha256~'^[a-f0-9]{64}$'),
  source_table text not null check (source_table in ('pdc_auditor_telegram_instructions_225','pdc_auditor_rule_commands_227')),
  source_id uuid not null,
  reserved_at timestamptz not null default clock_timestamp(),
  unique(telegram_chat_id,telegram_message_id),
  unique(bot_identity,telegram_update_id),
  unique(source_table,source_id)
);

-- Existing staging history must already be globally collision-free.
do $history$
begin
  if exists(
    select 1 from public.pdc_auditor_telegram_instructions_225 o
    join public.pdc_auditor_rule_commands_227 r
      on (r.telegram_chat_id,r.telegram_message_id)=(o.telegram_chat_id,o.telegram_message_id)
      or (r.bot_identity,r.telegram_update_id)=(o.bot_identity,o.telegram_update_id)
  ) then
    raise exception 'PDC_230_EXISTING_CROSS_DOMAIN_DELIVERY_CONFLICT' using errcode='23505';
  end if;
end
$history$;

insert into public.pdc_auditor_telegram_deliveries_230(
  delivery_domain,telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,
  bot_identity,original_instruction,instruction_sha256,source_table,source_id,reserved_at
)
select 'operation',telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,
  bot_identity,original_instruction,instruction_sha256,'pdc_auditor_telegram_instructions_225',instruction_id,received_at
from public.pdc_auditor_telegram_instructions_225;

insert into public.pdc_auditor_telegram_deliveries_230(
  delivery_domain,telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,
  bot_identity,original_instruction,instruction_sha256,source_table,source_id,reserved_at
)
select 'rule',telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,
  bot_identity,original_instruction,instruction_sha256,'pdc_auditor_rule_commands_227',command_id,received_at
from public.pdc_auditor_rule_commands_227;

create function public.pdc_auditor_reserve_delivery_230()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $trigger$
declare v_domain text;
begin
  v_domain:=case TG_TABLE_NAME
    when 'pdc_auditor_telegram_instructions_225' then 'operation'
    when 'pdc_auditor_rule_commands_227' then 'rule'
    else null end;
  if v_domain is null then
    raise exception 'PDC_230_INVALID_DELIVERY_SOURCE' using errcode='55000';
  end if;
  -- These locks serialize both uniqueness dimensions across the two source tables.
  perform pg_advisory_xact_lock(hashtextextended('pdc-230-message:'||NEW.telegram_chat_id||':'||NEW.telegram_message_id,0));
  perform pg_advisory_xact_lock(hashtextextended('pdc-230-update:'||NEW.bot_identity||':'||NEW.telegram_update_id,0));
  begin
    insert into public.pdc_auditor_telegram_deliveries_230(
      delivery_domain,telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,
      bot_identity,original_instruction,instruction_sha256,source_table,source_id
    ) values(v_domain,NEW.telegram_sender_id,NEW.telegram_chat_id,NEW.telegram_message_id,
      NEW.telegram_update_id,NEW.bot_identity,NEW.original_instruction,NEW.instruction_sha256,
      TG_TABLE_NAME,case when v_domain='operation'
        then (to_jsonb(NEW)->>'instruction_id')::uuid
        else (to_jsonb(NEW)->>'command_id')::uuid end);
  exception when unique_violation then
    raise exception 'PDC_230_TELEGRAM_DELIVERY_ALREADY_CONSUMED' using errcode='23505';
  end;
  return NEW;
end
$trigger$;
revoke all on function public.pdc_auditor_reserve_delivery_230() from public,anon,authenticated,service_role;
create trigger pdc_auditor_reserve_delivery_230
before insert on public.pdc_auditor_telegram_instructions_225
for each row execute function public.pdc_auditor_reserve_delivery_230();
create trigger pdc_auditor_rule_reserve_delivery_230
before insert on public.pdc_auditor_rule_commands_227
for each row execute function public.pdc_auditor_reserve_delivery_230();

alter table public.pdc_auditor_telegram_deliveries_230 enable row level security;
revoke all on public.pdc_auditor_telegram_deliveries_230 from public,anon,authenticated,service_role;
create trigger pdc_auditor_telegram_deliveries_immutable_230
before update or delete on public.pdc_auditor_telegram_deliveries_230
for each row execute function public.pdc_auditor_reject_history_mutation();

-- Replace the redundant sender predicate with an explicit enrolled, active, approved
-- Administrator check. Craig is enrolled as 7828138290; another sender is accepted only
-- after explicit Administrator enrollment, which is the documented Craig/authorised-Admin policy.
alter function public.pdc_auditor_telegram_actor_scope_225(bigint)
  rename to pdc_auditor_telegram_actor_scope_base_225;
revoke all on function public.pdc_auditor_telegram_actor_scope_base_225(bigint)
  from public,anon,authenticated,service_role;
create function public.pdc_auditor_telegram_actor_scope_225(p_telegram_sender_id bigint)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth
as $scope$
declare v_actor jsonb; v_count integer;
begin
  v_actor:=public.pdc_auditor_telegram_actor_scope_base_225(p_telegram_sender_id);
  select count(*) into v_count
  from public.pdc_supervised_telegram_identities i
  join auth.users au on au.id=i.auth_user_id and lower(coalesce(au.email,''))=lower(i.actor_email)
  join public.pdc_user_roles r on r.auth_user_id=i.auth_user_id
    and lower(r.email)=lower(i.actor_email) and r.role::text='administrator'
    and r.active and r.account_status='approved'
  where i.telegram_sender_id=p_telegram_sender_id and i.active
    and i.auth_user_id=(v_actor->>'admin_user_id')::uuid
    and lower(i.actor_email)=lower(v_actor->>'admin_email');
  if v_count<>1 then
    raise exception 'PDC_230_TELEGRAM_ADMINISTRATOR_REQUIRED' using errcode='42501';
  end if;
  return v_actor;
end
$scope$;
revoke all on function public.pdc_auditor_telegram_actor_scope_225(bigint)
  from public,anon,authenticated,service_role;

-- Keep migration 227 immutable. Its original implementation becomes private and is wrapped
-- by a strict natural-language boundary. No caller can submit create or internal match/priority fields.
alter function public.rule_pdc_auditor_telegram_227(text,jsonb,jsonb)
  rename to rule_pdc_auditor_telegram_base_227;
revoke all on function public.rule_pdc_auditor_telegram_base_227(text,jsonb,jsonb)
  from public,anon,authenticated,service_role;

create function public.rule_pdc_auditor_telegram_227(p_action text,p_scope jsonb,p_evidence jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $rule$
declare
  v_text text:=lower(regexp_replace(btrim(coalesce(p_evidence->>'original_instruction','')),E'\\s+',' ','g'));
  v_hours numeric;
begin
  if p_action='create' or p_action='query' then
    raise exception 'PDC_230_RULE_ACTION_NOT_EXPOSED' using errcode='42501';
  elsif p_action='remember' then
    if p_scope->>'category' not in ('gvm_upgrade','long_range_fuel_tank') then
      raise exception 'PDC_230_UNAPPROVED_RULE_SCOPE' using errcode='22023';
    end if;
    if p_scope->>'category'='gvm_upgrade' then
      if (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
           is distinct from array['category','estimated_hours','exclude','include']::text[] then
        raise exception 'PDC_230_UNAPPROVED_RULE_SCOPE' using errcode='22023';
      end if;
      if jsonb_typeof(p_scope->'estimated_hours')<>'number'
         or p_scope->'include'<>jsonb_build_array('gvm upgrade','gross vehicle mass upgrade')
         or p_scope->'exclude'<>jsonb_build_array('long range fuel tank','fuel tank')
         or v_text !~ '^(remember|learn):? '
         or v_text !~ '\mgvm\M'
         or v_text !~ '\m[0-9]+([.][0-9]{1,2})? (hours?|hrs?)\M' then
        raise exception 'PDC_230_RULE_INSTRUCTION_SCOPE_MISMATCH' using errcode='22023';
      end if;
      select (regexp_match(v_text,'\m([0-9]+([.][0-9]{1,2})?) (hours?|hrs?)\M'))[1]::numeric into v_hours;
      if v_hours<>(p_scope->>'estimated_hours')::numeric then
        raise exception 'PDC_230_RULE_INSTRUCTION_SCOPE_MISMATCH' using errcode='22023';
      end if;
    else
      if (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
           is distinct from array['category','exclude','include','work_key']::text[] then
        raise exception 'PDC_230_UNAPPROVED_RULE_SCOPE' using errcode='22023';
      end if;
      if p_scope->>'work_key'<>'hoist'
         or p_scope->'include'<>jsonb_build_array('long range fuel tank','long-range fuel tank')
         or p_scope->'exclude'<>jsonb_build_array('gvm upgrade')
         or v_text !~ '^(remember|learn):? '
         or v_text !~ 'long[- ]range fuel tank' then
        raise exception 'PDC_230_RULE_INSTRUCTION_SCOPE_MISMATCH' using errcode='22023';
      end if;
    end if;
  elsif p_action='correct' then
    if (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
         is distinct from array['estimated_hours','rule_selector']::text[]
       or lower(p_scope->>'rule_selector') not in ('gvm','gvm upgrade','gvm upgrades')
       or jsonb_typeof(p_scope->'estimated_hours')<>'number'
       or v_text !~ '^correct the (gvm|gvm upgrade|gvm upgrades) rule .*[0-9]+([.][0-9]{1,2})? (hours?|hrs?)' then
      raise exception 'PDC_230_RULE_INSTRUCTION_SCOPE_MISMATCH' using errcode='22023';
    end if;
    select (regexp_match(v_text,'\m([0-9]+([.][0-9]{1,2})?) (hours?|hrs?)\M'))[1]::numeric into v_hours;
    if v_hours<>(p_scope->>'estimated_hours')::numeric then
      raise exception 'PDC_230_RULE_INSTRUCTION_SCOPE_MISMATCH' using errcode='22023';
    end if;
  elsif p_action='disable' then
    if p_scope<>jsonb_build_object('rule_selector',p_scope->>'rule_selector')
       or lower(p_scope->>'rule_selector') not in ('gvm','gvm upgrade','gvm upgrades')
       or v_text not in ('disable the gvm rule','disable the gvm upgrade rule','disable the gvm upgrades rule') then
      raise exception 'PDC_230_RULE_INSTRUCTION_SCOPE_MISMATCH' using errcode='22023';
    end if;
  elsif p_action='undo' then
    if p_scope<>'{}'::jsonb or v_text not in ('undo my last rule','undo the last rule','undo last rule') then
      raise exception 'PDC_230_RULE_INSTRUCTION_SCOPE_MISMATCH' using errcode='22023';
    end if;
  elsif p_action='show' then
    if p_scope<>'{}'::jsonb or v_text not in ('show auditor rules','show learned rules','show rules') then
      raise exception 'PDC_230_RULE_INSTRUCTION_SCOPE_MISMATCH' using errcode='22023';
    end if;
  else
    raise exception 'PDC_230_RULE_ACTION_NOT_EXPOSED' using errcode='42501';
  end if;
  return public.rule_pdc_auditor_telegram_base_227(p_action,p_scope,p_evidence);
end
$rule$;
revoke all on function public.rule_pdc_auditor_telegram_227(text,jsonb,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.rule_pdc_auditor_telegram_227(text,jsonb,jsonb) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '230','auditor_authorization_hardening',array[
    'staging sentinel cdsmnqxtyyoeoznmbidd and exact predecessor 229',
    'global immutable Telegram delivery reservation across operation and rule RPC domains',
    'explicit active enrolled Administrator sender verification without redundant predicate',
    'reject caller-authored create/query and all internal rule payloads',
    'bind narrow remember/correct/disable/show/undo scopes to exact natural-language instruction',
    'production untouched'
  ]
);
notify pgrst,'reload schema';
commit;
