-- Staging-only migration 227: immutable, versioned AI Auditor rules and typed Telegram commands.
-- Depends on 225's exact service/Admin Telegram identity boundary and migration 226.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-227-ai-auditor-versioned-rules',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     )
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or to_regclass('supabase_migrations.schema_migrations') is null
     or not exists (select 1 from supabase_migrations.schema_migrations where version='225')
     or not exists (select 1 from supabase_migrations.schema_migrations where version='226')
     or exists (
       select 1 from supabase_migrations.schema_migrations
       where version ~ '^[0-9]+$' and version::integer>226
     )
     or exists (select 1 from supabase_migrations.schema_migrations where version='227') then
    raise exception 'PDC_227_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
  if to_regclass('public.pdc_auditor_service_identities_225') is null
     or to_regclass('public.pdc_supervised_telegram_identities') is null
     or to_regprocedure('public.pdc_auditor_telegram_actor_scope_225(bigint)') is null
     or to_regprocedure('public.pdc_auditor_reject_history_mutation()') is null
     or to_regprocedure('public.pdc_auditor_normalize_identity_225(text)') is null then
    raise exception 'PDC_227_DEPENDENCY_MISSING' using errcode='55000';
  end if;
end
$guard$;

-- Stable logical identity. Families are append-only; all lifecycle changes are versions.
create table public.pdc_auditor_rule_families_227 (
  rule_logical_id uuid primary key,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  created_by_admin_user_id uuid not null references auth.users(id) on delete restrict,
  created_by_service_identity_id uuid not null references public.pdc_auditor_service_identities_225(service_identity_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

-- Every Telegram delivery is reserved before its domain rows are inserted. The stored
-- canonical request and response make exact replay zero-add; changed reuse is a conflict.
create table public.pdc_auditor_rule_commands_227 (
  command_id uuid primary key,
  action text not null check (action in ('remember','create','correct','disable','undo','show','query')),
  scope jsonb not null check (jsonb_typeof(scope)='object' and octet_length(scope::text)<=16384),
  canonical_request_sha256 text not null check (canonical_request_sha256 ~ '^[a-f0-9]{64}$'),
  telegram_sender_id bigint not null,
  telegram_chat_id bigint not null,
  telegram_message_id bigint not null check (telegram_message_id>0),
  telegram_update_id bigint not null check (telegram_update_id>=0),
  bot_identity text not null check (
    bot_identity=btrim(bot_identity) and length(bot_identity) between 3 and 160
    and bot_identity !~ '[[:cntrl:]]'
  ),
  original_instruction text not null check (
    original_instruction=btrim(original_instruction)
    and length(original_instruction) between 3 and 4000
    and original_instruction !~ '[[:cntrl:]]'
  ),
  instruction_sha256 text not null check (instruction_sha256 ~ '^[a-f0-9]{64}$'),
  service_identity_id uuid not null references public.pdc_auditor_service_identities_225(service_identity_id) on delete restrict,
  service_auth_user_id uuid not null references auth.users(id) on delete restrict,
  service_email text not null,
  authorizing_admin_user_id uuid not null references auth.users(id) on delete restrict,
  authorizing_admin_email text not null,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  response jsonb not null check (jsonb_typeof(response)='object' and octet_length(response::text)<=65536),
  received_at timestamptz not null default clock_timestamp(),
  unique(telegram_chat_id,telegram_message_id),
  unique(telegram_update_id,bot_identity)
);

-- One row is one complete immutable rule version. No price field exists. Null matching
-- values mean that dimension is not asserted; includes/excludes are normalized phrases.
create table public.pdc_auditor_rule_versions_227 (
  rule_version_id uuid primary key,
  rule_logical_id uuid not null references public.pdc_auditor_rule_families_227(rule_logical_id) on delete restrict,
  version_no integer not null check (version_no>=1),
  predecessor_rule_version_id uuid references public.pdc_auditor_rule_versions_227(rule_version_id) on delete restrict,
  supersedes_rule_version_id uuid references public.pdc_auditor_rule_versions_227(rule_version_id) on delete restrict,
  command_id uuid not null unique references public.pdc_auditor_rule_commands_227(command_id) on delete restrict,
  lifecycle_action text not null check (lifecycle_action in ('create','correct','disable','undo')),
  rule_code text not null check (
    rule_code=upper(btrim(rule_code)) and length(rule_code) between 1 and 80
    and rule_code !~ '[[:cntrl:]]'
  ),
  rule_description text not null check (
    rule_description=btrim(rule_description) and length(rule_description) between 3 and 500
    and rule_description !~ '[[:cntrl:]]'
  ),
  rule_category text not null check (
    rule_category=lower(btrim(rule_category)) and rule_category ~ '^[a-z0-9][a-z0-9_]{1,79}$'
  ),
  exact_operation_code text check (
    exact_operation_code=upper(btrim(exact_operation_code))
    and length(exact_operation_code) between 1 and 80 and exact_operation_code !~ '[[:cntrl:]]'
  ),
  exact_normalized_description text check (
    exact_normalized_description=public.pdc_auditor_normalize_identity_225(exact_normalized_description)
    and length(exact_normalized_description) between 2 and 500
  ),
  approved_category text check (
    approved_category=lower(btrim(approved_category)) and approved_category ~ '^[a-z0-9][a-z0-9_]{1,79}$'
  ),
  include_phrases text[] not null default '{}'::text[] check (cardinality(include_phrases)<=50),
  exclude_phrases text[] not null default '{}'::text[] check (cardinality(exclude_phrases)<=50),
  intended_department text check (
    intended_department in ('fitting','tint','hoist','electrical','fabrication','tyre','pitInspection')
  ),
  intended_hours numeric(8,2) check (
    intended_hours between 0.25 and 999.75 and mod(intended_hours,0.25)=0
  ),
  intended_correction jsonb not null check (
    jsonb_typeof(intended_correction)='object'
    and octet_length(intended_correction::text)<=4096
    and not (intended_correction ?| array['price','pricing','parts_price','labour_price','currency','cost'])
  ),
  priority_class text not null check (priority_class in (
    'manual_later','individual_auditor','exact_code','exact_normalized_description',
    'approved_category_phrase','supervised_email','mapping','inference','review'
  )),
  priority_rank smallint generated always as (case priority_class
    when 'manual_later' then 900 when 'individual_auditor' then 800
    when 'exact_code' then 700 when 'exact_normalized_description' then 600
    when 'approved_category_phrase' then 500 when 'supervised_email' then 400
    when 'mapping' then 300 when 'inference' then 200 when 'review' then 100 end) stored,
  individual_auditor_user_id uuid references auth.users(id) on delete restrict,
  original_telegram_instruction text not null check (
    original_telegram_instruction=btrim(original_telegram_instruction)
    and length(original_telegram_instruction) between 3 and 4000
    and original_telegram_instruction !~ '[[:cntrl:]]'
  ),
  instruction_sha256 text not null check (instruction_sha256 ~ '^[a-f0-9]{64}$'),
  authorizing_admin_user_id uuid not null references auth.users(id) on delete restrict,
  bot_identity text not null,
  effective_at timestamptz not null,
  active boolean not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(rule_logical_id,version_no),
  check ((version_no=1 and predecessor_rule_version_id is null and supersedes_rule_version_id is null)
      or (version_no>1 and predecessor_rule_version_id is not null and supersedes_rule_version_id is not null)),
  check (predecessor_rule_version_id is not distinct from supersedes_rule_version_id),
  check ((priority_class='individual_auditor')=(individual_auditor_user_id is not null)),
  check (priority_class<>'exact_code' or exact_operation_code is not null),
  check (priority_class<>'exact_normalized_description' or exact_normalized_description is not null),
  check (priority_class<>'approved_category_phrase'
      or approved_category is not null or cardinality(include_phrases)>0),
  check (exact_operation_code is not null or exact_normalized_description is not null
      or approved_category is not null or cardinality(include_phrases)>0),
  check (not (include_phrases && exclude_phrases))
);
create index pdc_auditor_rule_versions_227_family
  on public.pdc_auditor_rule_versions_227(rule_logical_id,version_no desc);
create index pdc_auditor_rule_versions_227_candidates
  on public.pdc_auditor_rule_versions_227(priority_rank desc,effective_at desc,created_at desc);

-- Immutable examples are tied to the exact version, never moved to a later version.
create table public.pdc_auditor_rule_examples_227 (
  rule_example_id uuid primary key default gen_random_uuid(),
  rule_version_id uuid not null references public.pdc_auditor_rule_versions_227(rule_version_id) on delete restrict,
  example_kind text not null check (example_kind in ('include','exclude','correction')),
  example_text text not null check (
    example_text=btrim(example_text) and length(example_text) between 1 and 1000
    and example_text !~ '[[:cntrl:]]'
  ),
  normalized_example text not null check (
    normalized_example=public.pdc_auditor_normalize_identity_225(normalized_example)
    and length(normalized_example) between 1 and 1000
  ),
  created_at timestamptz not null default clock_timestamp(),
  unique(rule_version_id,example_kind,normalized_example)
);

-- Defense in depth: no direct DML/read grants, including service_role, and no history mutation.
do $secure$
declare t text;
begin
  foreach t in array array[
    'pdc_auditor_rule_families_227','pdc_auditor_rule_commands_227',
    'pdc_auditor_rule_versions_227','pdc_auditor_rule_examples_227'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated,service_role',t);
    execute format(
      'create trigger %I before update or delete on public.%I for each row execute function public.pdc_auditor_reject_history_mutation()',
      t||'_immutable',t
    );
  end loop;
end
$secure$;

-- Additive planner seam. Only the latest version in each family can be effective. A returned
-- Auditor rule blocks older supervised-email/mapping/inference inputs by construction.
create function public.pdc_auditor_rule_candidates_227(
  p_dealer_code text,
  p_operation_code text,
  p_description text,
  p_category text default null,
  p_auditor_user_id uuid default null,
  p_as_of timestamptz default clock_timestamp()
)
returns table(
  rule_logical_id uuid,rule_version_id uuid,version_no integer,rule_code text,
  rule_description text,rule_category text,priority_class text,priority_rank smallint,
  intended_department text,intended_hours numeric,intended_correction jsonb,
  match_reason text,blocks_older_email boolean,effective_at timestamptz
)
language sql stable security definer set search_path=pg_catalog,public
as $candidates$
with latest as (
  select distinct on (v.rule_logical_id) v.*
  from public.pdc_auditor_rule_versions_227 v
  join public.pdc_auditor_rule_families_227 f on f.rule_logical_id=v.rule_logical_id
  where f.environment='staging' and f.dealer_code=p_dealer_code and v.effective_at<=p_as_of
  order by v.rule_logical_id,v.version_no desc
), normalized as (
  select upper(btrim(coalesce(p_operation_code,''))) operation_code,
    public.pdc_auditor_normalize_identity_225(p_description) description,
    lower(btrim(coalesce(p_category,''))) category
), matched as (
  select l.*,
    case
      when l.priority_class='manual_later' and (
        (l.exact_operation_code is not null and l.exact_operation_code=n.operation_code)
        or (l.exact_normalized_description is not null and l.exact_normalized_description=n.description)
        or (l.approved_category is not null and l.approved_category=n.category)
        or exists(select 1 from unnest(l.include_phrases) x where n.description like '%'||x||'%')
      ) then 'later manual Auditor adjustment'
      when l.priority_class='individual_auditor' and l.individual_auditor_user_id=p_auditor_user_id
        and (
          (l.exact_operation_code is not null and l.exact_operation_code=n.operation_code)
          or (l.exact_normalized_description is not null and l.exact_normalized_description=n.description)
          or (l.approved_category is not null and l.approved_category=n.category)
          or exists(select 1 from unnest(l.include_phrases) x where n.description like '%'||x||'%')
        )
        then 'individual Auditor rule'
      when l.priority_class='exact_code'
        and l.exact_operation_code is not null and l.exact_operation_code=n.operation_code
        then 'exact operation code'
      when l.priority_class='exact_normalized_description'
        and l.exact_normalized_description is not null and l.exact_normalized_description=n.description
        then 'exact normalized description'
      when l.priority_class='approved_category_phrase' and (
        (l.approved_category is not null and l.approved_category=n.category
          and (cardinality(l.include_phrases)=0 or exists(
            select 1 from unnest(l.include_phrases) x where n.description like '%'||x||'%'
          )))
        or (l.approved_category is null and exists(
          select 1 from unnest(l.include_phrases) x where n.description like '%'||x||'%'
        ))
      ) then 'approved category/phrase'
    end match_reason,
    n.description candidate_description
  from latest l cross join normalized n
  where l.active
)
select m.rule_logical_id,m.rule_version_id,m.version_no,m.rule_code,
  m.rule_description,m.rule_category,m.priority_class,m.priority_rank,
  m.intended_department,m.intended_hours,m.intended_correction,m.match_reason,
  true,m.effective_at
from matched m
where m.match_reason is not null
  and not exists (
    select 1 from unnest(m.exclude_phrases) x
    where m.candidate_description like '%'||x||'%'
  )
order by m.priority_rank desc,m.effective_at desc,m.version_no desc,m.rule_version_id
$candidates$;
revoke all on function public.pdc_auditor_rule_candidates_227(text,text,text,text,uuid,timestamptz)
  from public,anon,authenticated,service_role;

-- Validate normalized phrase arrays; null and non-string elements are rejected.
create function public.pdc_auditor_rule_phrases_227(p_value jsonb)
returns text[]
language plpgsql immutable security definer set search_path=pg_catalog,public
as $phrases$
declare v_result text[];
begin
  if jsonb_typeof(p_value)<>'array' or jsonb_array_length(p_value)>50
     or exists(select 1 from jsonb_array_elements(p_value) e where jsonb_typeof(e)<>'string') then
    raise exception 'PDC_227_INVALID_PHRASES' using errcode='22023';
  end if;
  select coalesce(array_agg(public.pdc_auditor_normalize_identity_225(value) order by value),'{}'::text[])
    into v_result from jsonb_array_elements_text(p_value);
  if exists(select 1 from unnest(v_result) x where length(x) not between 1 and 240)
     or cardinality(v_result)<>cardinality(array(select distinct x from unnest(v_result) x)) then
    raise exception 'PDC_227_INVALID_PHRASES' using errcode='22023';
  end if;
  return v_result;
end
$phrases$;
revoke all on function public.pdc_auditor_rule_phrases_227(jsonb) from public,anon,authenticated,service_role;

create function public.rule_pdc_auditor_telegram_227(
  p_action text,p_scope jsonb,p_evidence jsonb
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,extensions
as $rule$
declare
  v_actor jsonb;
  v_sender bigint;
  v_chat bigint;
  v_message bigint;
  v_update bigint;
  v_bot text;
  v_text text;
  v_instruction_hash text;
  v_request_hash text;
  v_command_id uuid:=gen_random_uuid();
  v_rule_id uuid;
  v_version_id uuid:=gen_random_uuid();
  v_previous public.pdc_auditor_rule_versions_227%rowtype;
  v_target public.pdc_auditor_rule_versions_227%rowtype;
  v_existing public.pdc_auditor_rule_commands_227%rowtype;
  v_response jsonb;
  v_includes text[];
  v_excludes text[];
  v_examples jsonb;
  v_effective timestamptz;
  v_active boolean;
  v_action text;
  v_predecessor_id uuid;
  v_next_version_no integer;
  v_count integer;
  v_keys text[];
  v_command_scope jsonb;
begin
  if p_action not in ('remember','create','correct','disable','undo','show','query')
     or jsonb_typeof(p_scope) is distinct from 'object' or octet_length(p_scope::text)>16384
     or jsonb_typeof(p_evidence) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(p_evidence) k)
       is distinct from array['bot_identity','instruction_sha256','original_instruction','telegram_chat_id','telegram_message_id','telegram_sender_id','telegram_update_id']::text[] then
    raise exception 'PDC_227_INVALID_COMMAND' using errcode='22023';
  end if;
  begin
    v_sender:=(p_evidence->>'telegram_sender_id')::bigint;
    v_chat:=(p_evidence->>'telegram_chat_id')::bigint;
    v_message:=(p_evidence->>'telegram_message_id')::bigint;
    v_update:=(p_evidence->>'telegram_update_id')::bigint;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'PDC_227_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';
  end;
  v_bot:=p_evidence->>'bot_identity';
  v_text:=p_evidence->>'original_instruction';
  v_instruction_hash:=lower(coalesce(p_evidence->>'instruction_sha256',''));
  if v_message<1 or v_update<0 or length(v_text) not between 3 and 4000
     or v_text<>btrim(v_text) or v_text~'[[:cntrl:]]'
     or length(v_bot) not between 3 and 160 or v_bot<>btrim(v_bot) or v_bot~'[[:cntrl:]]'
     or v_instruction_hash!~'^[a-f0-9]{64}$'
     or v_instruction_hash<>encode(extensions.digest(convert_to(v_text,'UTF8'),'sha256'),'hex') then
    raise exception 'PDC_227_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';
  end if;

  v_command_scope:=p_scope;
  -- This is exactly migration 225's ordinary authenticated service identity plus its
  -- live, verified Administrator Telegram sender lookup. service_role is rejected there.
  v_actor:=public.pdc_auditor_telegram_actor_scope_225(v_sender);
  v_request_hash:=encode(extensions.digest(convert_to(
    concat_ws('|','rule_pdc_auditor_telegram_227_v1',p_action,p_scope::text,v_sender,v_chat,
      v_message,v_update,v_bot,v_text,v_instruction_hash,v_actor::text),'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-227-telegram:'||v_chat||':'||v_message,0));
  select * into v_existing from public.pdc_auditor_rule_commands_227
  where telegram_chat_id=v_chat and telegram_message_id=v_message;
  if found then
    if v_existing.canonical_request_sha256<>v_request_hash
       or v_existing.action<>p_action or v_existing.scope<>v_command_scope
       or v_existing.telegram_sender_id<>v_sender or v_existing.telegram_update_id<>v_update
       or v_existing.bot_identity<>v_bot or v_existing.original_instruction<>v_text
       or v_existing.instruction_sha256<>v_instruction_hash
       or v_existing.service_auth_user_id<>(v_actor->>'service_user_id')::uuid
       or v_existing.authorizing_admin_user_id<>(v_actor->>'admin_user_id')::uuid then
      raise exception 'PDC_227_TELEGRAM_MESSAGE_CONTENT_CONFLICT' using errcode='23505';
    end if;
    return v_existing.response||jsonb_build_object('code','exact_command_replay');
  end if;
  if exists(select 1 from public.pdc_auditor_rule_commands_227
      where telegram_update_id=v_update and bot_identity=v_bot) then
    raise exception 'PDC_227_TELEGRAM_UPDATE_CONFLICT' using errcode='23505';
  end if;

  -- Friendly Telegram selectors resolve to exactly one current family. The bot never
  -- receives or invents rule UUIDs, priorities, effective timestamps or match fields.
  if p_action in ('correct','disable') and p_scope ? 'rule_selector' then
    if lower(p_scope->>'rule_selector') not in ('gvm','gvm upgrade','gvm upgrades')
       or (p_action='correct' and (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
          is distinct from array['estimated_hours','rule_selector']::text[])
       or (p_action='disable' and (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
          is distinct from array['rule_selector']::text[]) then
      raise exception 'PDC_227_RULE_SELECTOR_NOT_SUPPORTED' using errcode='22023';
    end if;
    select count(*),min(v.rule_version_id::text)::uuid into v_count,v_predecessor_id
    from public.pdc_auditor_rule_versions_227 v
    join public.pdc_auditor_rule_families_227 f on f.rule_logical_id=v.rule_logical_id
    where f.dealer_code=v_actor->>'dealer_code' and v.rule_code='GVM_HOURS'
      and not exists(select 1 from public.pdc_auditor_rule_versions_227 n
        where n.rule_logical_id=v.rule_logical_id and n.version_no>v.version_no);
    if v_count<>1 then
      raise exception 'PDC_227_RULE_SELECTOR_AMBIGUOUS_OR_MISSING' using errcode='22023';
    end if;
    select * into strict v_previous from public.pdc_auditor_rule_versions_227
      where rule_version_id=v_predecessor_id;
    if p_action='disable' then
      p_scope:=jsonb_build_object('rule_logical_id',v_previous.rule_logical_id,
        'effective_at',clock_timestamp());
    else
      if jsonb_typeof(p_scope->'estimated_hours')<>'number' then
        raise exception 'PDC_227_INVALID_RULE_HOURS' using errcode='22023';
      end if;
      p_scope:=jsonb_build_object(
        'rule_logical_id',v_previous.rule_logical_id,
        'approved_category',coalesce(v_previous.approved_category,''),
        'effective_at',clock_timestamp(),
        'exact_normalized_description',coalesce(v_previous.exact_normalized_description,''),
        'exact_operation_code',coalesce(v_previous.exact_operation_code,''),
        'examples','[]'::jsonb,'exclude_phrases',to_jsonb(v_previous.exclude_phrases),
        'include_phrases',to_jsonb(v_previous.include_phrases),
        'individual_auditor_user_id',v_previous.individual_auditor_user_id,
        'intended_correction',v_previous.intended_correction||jsonb_build_object('estimated_hours',p_scope->'estimated_hours'),
        'intended_department',coalesce(v_previous.intended_department,''),
        'intended_hours',p_scope->'estimated_hours','priority_class',v_previous.priority_class,
        'rule_category',v_previous.rule_category,'rule_code',v_previous.rule_code,
        'rule_description',v_previous.rule_description||' corrected'
      );
    end if;
  end if;

  -- Telegram sends a narrow user intent.  Expand only the two approved deterministic
  -- categories server-side; the client cannot invent priority, codes, dates or examples.
  if p_action='remember' and p_scope ? 'category' then
    if p_scope=(jsonb_build_object('category','gvm_upgrade','estimated_hours',p_scope->'estimated_hours',
        'include',jsonb_build_array('gvm upgrade','gross vehicle mass upgrade'),
        'exclude',jsonb_build_array('long range fuel tank','fuel tank')))
       and jsonb_typeof(p_scope->'estimated_hours')='number' then
      p_scope:=jsonb_build_object(
        'approved_category','gvm_upgrade','effective_at',clock_timestamp(),
        'exact_normalized_description','','exact_operation_code','',
        'examples',jsonb_build_array(jsonb_build_object('kind','include','text','GVM upgrade'),
          jsonb_build_object('kind','exclude','text','long range fuel tank')),
        'exclude_phrases',p_scope->'exclude','include_phrases',p_scope->'include',
        'individual_auditor_user_id',null,
        'intended_correction',jsonb_build_object('estimated_hours',p_scope->'estimated_hours'),
        'intended_department','hoist','intended_hours',p_scope->'estimated_hours',
        'priority_class','approved_category_phrase','rule_category','gvm_upgrade',
        'rule_code','GVM_HOURS','rule_description','Approved genuine GVM upgrade hours'
      );
    elsif p_scope=(jsonb_build_object('category','long_range_fuel_tank','work_key','hoist',
        'include',jsonb_build_array('long range fuel tank','long-range fuel tank'),
        'exclude',jsonb_build_array('gvm upgrade'))) then
      p_scope:=jsonb_build_object(
        'approved_category','long_range_fuel_tank','effective_at',clock_timestamp(),
        'exact_normalized_description','','exact_operation_code','',
        'examples',jsonb_build_array(jsonb_build_object('kind','include','text','long range fuel tank'),
          jsonb_build_object('kind','exclude','text','GVM upgrade')),
        'exclude_phrases',p_scope->'exclude','include_phrases',p_scope->'include',
        'individual_auditor_user_id',null,
        'intended_correction',jsonb_build_object('work_key','hoist'),
        'intended_department','hoist','intended_hours',null,
        'priority_class','approved_category_phrase','rule_category','long_range_fuel_tank',
        'rule_code','LONG_RANGE_TANK_DEPARTMENT',
        'rule_description','Approved long-range fuel tank department'
      );
    else
      raise exception 'PDC_227_UNAPPROVED_NARROW_RULE_INTENT' using errcode='22023';
    end if;
  end if;

  if p_action in ('remember','create') then
    v_keys:=array['approved_category','effective_at','exact_normalized_description','exact_operation_code',
      'examples','exclude_phrases','include_phrases','individual_auditor_user_id','intended_correction',
      'intended_department','intended_hours','priority_class','rule_category','rule_code','rule_description'];
    if (select array_agg(k order by k) from jsonb_object_keys(p_scope) k) is distinct from v_keys then
      raise exception 'PDC_227_INVALID_CREATE_SCOPE' using errcode='22023';
    end if;
    v_rule_id:=gen_random_uuid();
    v_includes:=public.pdc_auditor_rule_phrases_227(p_scope->'include_phrases');
    v_excludes:=public.pdc_auditor_rule_phrases_227(p_scope->'exclude_phrases');
    v_examples:=p_scope->'examples';
    v_effective:=(p_scope->>'effective_at')::timestamptz;
    v_active:=true;
    v_action:='create';
  elsif p_action='correct' then
    v_keys:=array['approved_category','effective_at','exact_normalized_description','exact_operation_code',
      'examples','exclude_phrases','include_phrases','individual_auditor_user_id','intended_correction',
      'intended_department','intended_hours','priority_class','rule_category','rule_code','rule_description','rule_logical_id'];
    if (select array_agg(k order by k) from jsonb_object_keys(p_scope) k) is distinct from v_keys then
      raise exception 'PDC_227_INVALID_CORRECT_SCOPE' using errcode='22023';
    end if;
    v_rule_id:=(p_scope->>'rule_logical_id')::uuid;
    perform pg_advisory_xact_lock(hashtextextended('pdc-227-rule:'||v_rule_id::text,0));
    select * into strict v_previous from public.pdc_auditor_rule_versions_227
      where rule_logical_id=v_rule_id order by version_no desc limit 1;
    v_includes:=public.pdc_auditor_rule_phrases_227(p_scope->'include_phrases');
    v_excludes:=public.pdc_auditor_rule_phrases_227(p_scope->'exclude_phrases');
    v_examples:=p_scope->'examples';
    v_effective:=(p_scope->>'effective_at')::timestamptz;
    v_active:=true;
    v_action:='correct';
  elsif p_action='disable' then
    if (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
       is distinct from array['effective_at','rule_logical_id']::text[] then
      raise exception 'PDC_227_INVALID_DISABLE_SCOPE' using errcode='22023';
    end if;
    v_rule_id:=(p_scope->>'rule_logical_id')::uuid;
    perform pg_advisory_xact_lock(hashtextextended('pdc-227-rule:'||v_rule_id::text,0));
    select * into strict v_previous from public.pdc_auditor_rule_versions_227
      where rule_logical_id=v_rule_id order by version_no desc limit 1;
    v_effective:=(p_scope->>'effective_at')::timestamptz;
    v_active:=false;
    v_action:='disable';
  elsif p_action='undo' then
    if p_scope<>'{}'::jsonb then
      raise exception 'PDC_227_INVALID_UNDO_SCOPE' using errcode='22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('pdc-227-undo:'||(v_actor->>'dealer_code'),0));
    select v.* into v_previous
    from public.pdc_auditor_rule_versions_227 v
    join public.pdc_auditor_rule_families_227 f on f.rule_logical_id=v.rule_logical_id
    where f.dealer_code=v_actor->>'dealer_code'
      and v.authorizing_admin_user_id=(v_actor->>'admin_user_id')::uuid
      and v.lifecycle_action<>'undo'
      and not exists (
        select 1 from public.pdc_auditor_rule_versions_227 u
        where u.rule_logical_id=v.rule_logical_id and u.lifecycle_action='undo'
          and u.predecessor_rule_version_id=v.rule_version_id
      )
    order by v.created_at desc,v.rule_version_id desc limit 1;
    if not found then
      raise exception 'PDC_227_NOTHING_TO_UNDO' using errcode='22023';
    end if;
    v_rule_id:=v_previous.rule_logical_id;
    if v_previous.version_no=1 then
      v_target:=v_previous;
      v_active:=false;
    else
      select * into strict v_target from public.pdc_auditor_rule_versions_227
      where rule_version_id=v_previous.predecessor_rule_version_id;
      v_active:=v_target.active;
    end if;
    v_effective:=clock_timestamp();
    v_action:='undo';
  elsif p_action in ('show','query') then
    if p_action='show' and p_scope<>'{}'::jsonb then
      raise exception 'PDC_227_INVALID_SHOW_SCOPE' using errcode='22023';
    elsif p_action='query' and (
      (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
        is distinct from array['rule_logical_id']::text[]
    ) then
      raise exception 'PDC_227_INVALID_QUERY_SCOPE' using errcode='22023';
    end if;
    if p_action='show' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.priority_rank desc,q.effective_at desc),'[]'::jsonb)
        into v_examples
      from (
        select distinct on (v.rule_logical_id) v.rule_logical_id,v.rule_version_id,v.version_no,
          v.rule_code,v.rule_description,v.rule_category,v.priority_class,v.priority_rank,
          v.intended_department,v.intended_hours,v.intended_correction,v.active,v.effective_at
        from public.pdc_auditor_rule_versions_227 v
        join public.pdc_auditor_rule_families_227 f on f.rule_logical_id=v.rule_logical_id
        where f.dealer_code=v_actor->>'dealer_code'
        order by v.rule_logical_id,v.version_no desc
      ) q;
    else
      select coalesce(jsonb_agg(to_jsonb(q) order by q.version_no),'[]'::jsonb) into v_examples
      from (
        select v.rule_logical_id,v.rule_version_id,v.version_no,v.predecessor_rule_version_id,
          v.lifecycle_action,v.rule_code,v.rule_description,v.rule_category,v.priority_class,
          v.priority_rank,v.exact_operation_code,v.exact_normalized_description,v.approved_category,
          v.include_phrases,v.exclude_phrases,v.intended_department,v.intended_hours,
          v.intended_correction,v.active,v.effective_at,v.authorizing_admin_user_id,v.bot_identity
        from public.pdc_auditor_rule_versions_227 v
        join public.pdc_auditor_rule_families_227 f on f.rule_logical_id=v.rule_logical_id
        where v.rule_logical_id=(p_scope->>'rule_logical_id')::uuid
          and f.dealer_code=v_actor->>'dealer_code'
      ) q;
    end if;
    v_response:=jsonb_build_object('ok',true,'code',case when p_action='show' then 'rules_shown' else 'rule_history' end,
      'data',jsonb_build_object('rules',v_examples,'pricing_available',false,
        'precedence',jsonb_build_array('manual_later','individual_auditor','exact_code',
          'exact_normalized_description','approved_category_phrase','supervised_email','mapping','inference','review')));
    insert into public.pdc_auditor_rule_commands_227(
      command_id,action,scope,canonical_request_sha256,telegram_sender_id,telegram_chat_id,
      telegram_message_id,telegram_update_id,bot_identity,original_instruction,instruction_sha256,
      service_identity_id,service_auth_user_id,service_email,authorizing_admin_user_id,
      authorizing_admin_email,dealer_code,environment,response
    ) values(v_command_id,p_action,v_command_scope,v_request_hash,v_sender,v_chat,v_message,v_update,v_bot,
      v_text,v_instruction_hash,(v_actor->>'service_identity_id')::uuid,
      (v_actor->>'service_user_id')::uuid,v_actor->>'service_email',
      (v_actor->>'admin_user_id')::uuid,v_actor->>'admin_email',v_actor->>'dealer_code','staging',v_response);
    return v_response;
  end if;

  v_predecessor_id:=v_previous.rule_version_id;
  v_next_version_no:=coalesce(v_previous.version_no,0)+1;

  -- Parse/validate create/correct payload. Disable and undo copy immutable prior payload.
  if v_action in ('create','correct') then
    if jsonb_typeof(v_examples)<>'array' or jsonb_array_length(v_examples)>100
       or exists(select 1 from jsonb_array_elements(v_examples) e
         where jsonb_typeof(e)<>'object'
           or (select array_agg(k order by k) from jsonb_object_keys(e) k)
             is distinct from array['kind','text']::text[]
           or e->>'kind' not in ('include','exclude','correction')
           or length(e->>'text') not between 1 and 1000)
       or p_scope->>'priority_class' not in ('manual_later','individual_auditor','exact_code',
          'exact_normalized_description','approved_category_phrase')
       or jsonb_typeof(p_scope->'intended_correction')<>'object'
       or (p_scope->'intended_correction') ?| array['price','pricing','parts_price','labour_price','currency','cost']
       or (p_scope->>'intended_hours') is not null and (
         (p_scope->>'intended_hours')::numeric not between 0.25 and 999.75
         or mod((p_scope->>'intended_hours')::numeric,0.25)<>0)
       or v_effective is null then
      raise exception 'PDC_227_INVALID_RULE_PAYLOAD' using errcode='22023';
    end if;
  else
    if v_action='undo' and v_previous.version_no>1 then
      v_previous:=v_target;
    end if;
    v_includes:=v_previous.include_phrases;
    v_excludes:=v_previous.exclude_phrases;
    v_examples:='[]'::jsonb;
  end if;

  if v_action='create' then
    insert into public.pdc_auditor_rule_families_227(
      rule_logical_id,dealer_code,environment,created_by_admin_user_id,created_by_service_identity_id
    ) values(v_rule_id,v_actor->>'dealer_code','staging',(v_actor->>'admin_user_id')::uuid,
      (v_actor->>'service_identity_id')::uuid);
  else
    if not exists(select 1 from public.pdc_auditor_rule_families_227
        where rule_logical_id=v_rule_id and dealer_code=v_actor->>'dealer_code') then
      raise exception 'PDC_227_RULE_NOT_FOUND' using errcode='22023';
    end if;
  end if;

  v_response:=jsonb_build_object('ok',true,'code',case v_action
      when 'create' then 'rule_created' when 'correct' then 'rule_corrected'
      when 'disable' then 'rule_disabled' else 'rule_undo_appended' end,
    'data',jsonb_build_object('rule_logical_id',v_rule_id,'rule_version_id',v_version_id,
      'version_no',v_next_version_no,'active',v_active,
      'immutable',true,'pricing_available',false));

  -- Reservation precedes the version insert. Both remain in one transaction, so failure
  -- rolls back both; success makes replay return the stored response without another version.
  insert into public.pdc_auditor_rule_commands_227(
    command_id,action,scope,canonical_request_sha256,telegram_sender_id,telegram_chat_id,
    telegram_message_id,telegram_update_id,bot_identity,original_instruction,instruction_sha256,
    service_identity_id,service_auth_user_id,service_email,authorizing_admin_user_id,
    authorizing_admin_email,dealer_code,environment,response
  ) values(v_command_id,p_action,v_command_scope,v_request_hash,v_sender,v_chat,v_message,v_update,v_bot,
    v_text,v_instruction_hash,(v_actor->>'service_identity_id')::uuid,
    (v_actor->>'service_user_id')::uuid,v_actor->>'service_email',
    (v_actor->>'admin_user_id')::uuid,v_actor->>'admin_email',v_actor->>'dealer_code','staging',v_response);

  insert into public.pdc_auditor_rule_versions_227(
    rule_version_id,rule_logical_id,version_no,predecessor_rule_version_id,supersedes_rule_version_id,
    command_id,lifecycle_action,rule_code,rule_description,rule_category,exact_operation_code,
    exact_normalized_description,approved_category,include_phrases,exclude_phrases,
    intended_department,intended_hours,intended_correction,priority_class,
    individual_auditor_user_id,original_telegram_instruction,instruction_sha256,
    authorizing_admin_user_id,bot_identity,effective_at,active
  ) values(
    v_version_id,v_rule_id,v_next_version_no,v_predecessor_id,
    v_predecessor_id,v_command_id,v_action,
    case when v_action in ('create','correct') then p_scope->>'rule_code' else v_previous.rule_code end,
    case when v_action in ('create','correct') then p_scope->>'rule_description' else v_previous.rule_description end,
    case when v_action in ('create','correct') then p_scope->>'rule_category' else v_previous.rule_category end,
    case when v_action in ('create','correct') then nullif(p_scope->>'exact_operation_code','') else v_previous.exact_operation_code end,
    case when v_action in ('create','correct') then nullif(public.pdc_auditor_normalize_identity_225(p_scope->>'exact_normalized_description'),'') else v_previous.exact_normalized_description end,
    case when v_action in ('create','correct') then nullif(lower(btrim(p_scope->>'approved_category')),'') else v_previous.approved_category end,
    v_includes,v_excludes,
    case when v_action in ('create','correct') then nullif(p_scope->>'intended_department','') else v_previous.intended_department end,
    case when v_action in ('create','correct') then (p_scope->>'intended_hours')::numeric else v_previous.intended_hours end,
    case when v_action in ('create','correct') then p_scope->'intended_correction' else v_previous.intended_correction end,
    case when v_action in ('create','correct') then p_scope->>'priority_class' else v_previous.priority_class end,
    case when v_action in ('create','correct') then (p_scope->>'individual_auditor_user_id')::uuid else v_previous.individual_auditor_user_id end,
    v_text,v_instruction_hash,(v_actor->>'admin_user_id')::uuid,v_bot,v_effective,v_active
  );

  if v_action in ('create','correct') then
    insert into public.pdc_auditor_rule_examples_227(rule_version_id,example_kind,example_text,normalized_example)
    select v_version_id,e->>'kind',e->>'text',public.pdc_auditor_normalize_identity_225(e->>'text')
    from jsonb_array_elements(v_examples) e;
  end if;
  return v_response;
exception
  when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow then
    raise exception 'PDC_227_INVALID_TYPED_VALUE' using errcode='22023';
end
$rule$;
revoke all on function public.rule_pdc_auditor_telegram_227(text,jsonb,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.rule_pdc_auditor_telegram_227(text,jsonb,jsonb) to authenticated;

comment on function public.rule_pdc_auditor_telegram_227(text,jsonb,jsonb) is
  'Staging-only typed, exactly-once Telegram rule command. Exact migration-225 service identity and verified Administrator Telegram sender required. Appends immutable create/correct/disable/undo versions; show/query are immutable receipts. No pricing.';
comment on function public.pdc_auditor_rule_candidates_227(text,text,text,text,uuid,timestamptz) is
  'Private additive planner helper. Deterministic precedence: later manual > individual Auditor > exact code > exact normalized description > approved category/phrase > supervised email > mapping > inference > review. Any returned Auditor rule blocks older email inputs.';

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '227','ai_auditor_versioned_rules',array[
    'staging sentinel cdsmnqxtyyoeoznmbidd and exact predecessor 226',
    'immutable append-only logical rule families, complete versions, examples and Telegram command receipts',
    'typed remember/create correct disable undo show/query RPC bound to exact 225 service identity and verified Administrator Telegram sender',
    'exactly-once Telegram reservation with canonical request conflict detection and stored replay response',
    'deterministic rule candidate helper: manual later, individual Auditor, exact code, exact normalized description, approved category/phrase, supervised email, mapping, inference, review',
    'Auditor candidates explicitly block older email; no pricing fields or authority',
    'strict RLS, immutable UPDATE/DELETE rejection and no direct grants including service_role'
  ]
);
notify pgrst,'reload schema';
commit;
