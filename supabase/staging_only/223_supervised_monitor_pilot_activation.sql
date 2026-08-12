-- Staging-only migration 223: authorize the supervised PMB Email Monitor pilot.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-223-supervised-monitor-pilot',0));
select public.pdc_monitor_staging_guard();
do $guard$ begin
 if not public.pdc_monitor_staging_guard()
 or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or to_regclass('public.pdc_production_environment_sentinel') is not null
 or not exists(select 1 from supabase_migrations.schema_migrations where version='222' and name='supervised_review_standard_hours')
 or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::integer>222)
 or exists(select 1 from supabase_migrations.schema_migrations where version='223')
 then raise exception 'PDC_223_STAGING_OR_LEDGER_MISMATCH' using errcode='55000'; end if;
end $guard$;

create table public.pdc_email_monitor_pilot(
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 project_ref text not null check(project_ref='cdsmnqxtyyoeoznmbidd'),
 mailbox_key text not null references public.monitored_mailboxes(mailbox_key) on delete restrict,
 minimum_uid bigint not null check(minimum_uid>=471),
 outbound_email_enabled boolean not null default false check(not outbound_email_enabled),
 automatic_rule_application boolean not null default true,
 automatic_authenticated_jobcards boolean not null default true,
 ambiguous_to_review boolean not null default true,
 exactly_once_required boolean not null default true,
 authorized_by uuid not null references auth.users(id) on delete restrict,
 authorized_by_email text not null check(lower(authorized_by_email)='craig.watson@broometoyota.com.au'),
 authorized_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_email_monitor_pilot enable row level security;
revoke all on table public.pdc_email_monitor_pilot from public,anon,authenticated,service_role;

insert into public.pdc_email_monitor_pilot(enabled,project_ref,mailbox_key,minimum_uid,authorized_by,authorized_by_email)
select true,'cdsmnqxtyyoeoznmbidd','pdc_pmb_email',471,r.auth_user_id,lower(r.email)
from public.pdc_user_roles r
where lower(r.email)='craig.watson@broometoyota.com.au' and r.role='administrator' and r.active and r.account_status='approved'
limit 1;

update public.monitored_mailboxes
set active=true,test_mode=true,
 config=config||jsonb_build_object(
  'owner_profile','pdc-monitor','operational_scope','staging','contains_credentials',false,
  'supervised_pilot_enabled',true,'minimum_uid',471,'outbound_email_enabled',false,
  'exactly_once_required',true,'authorized_by','craig.watson@broometoyota.com.au'),
 updated_at=clock_timestamp()
where mailbox_key='pdc_pmb_email' and provider='gmail' and lower(mailbox_address)='pmbcontroller@gmail.com';

create function public.pdc_email_monitor_pilot_intake_guard_223() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare p public.pdc_email_monitor_pilot%rowtype;m public.monitored_mailboxes%rowtype;u bigint;
begin
 if new.monitored_mailbox_id is null then return new;end if;
 select * into m from public.monitored_mailboxes where id=new.monitored_mailbox_id;
 if not found or m.mailbox_key<>'pdc_pmb_email' then return new;end if;
 select * into p from public.pdc_email_monitor_pilot where singleton;
 if not found or not p.enabled or p.project_ref<>'cdsmnqxtyyoeoznmbidd' or not public.pdc_monitor_staging_guard()
 or to_regclass('public.pdc_production_environment_sentinel') is not null then
  raise exception 'pdc_monitor_pilot_not_authorized' using errcode='42501';
 end if;
 if not m.active or not m.test_mode or lower(m.mailbox_address)<>'pmbcontroller@gmail.com' then
  raise exception 'pdc_monitor_mailbox_not_bound' using errcode='42501';
 end if;
 if coalesce(new.provider_uid,'')!~'^imap_uid:[0-9]+$' then
  raise exception 'pdc_monitor_uid_evidence_required' using errcode='22023';
 end if;
 u:=substring(new.provider_uid from '^imap_uid:([0-9]+)$')::bigint;
 if u<p.minimum_uid then raise exception 'pdc_monitor_uid_before_pilot_floor' using errcode='42501';end if;
 return new;
end$$;
revoke all on function public.pdc_email_monitor_pilot_intake_guard_223() from public,anon,authenticated,service_role;
create trigger pdc_email_monitor_pilot_intake_guard_223 before insert on public.ai_email_intake
for each row execute function public.pdc_email_monitor_pilot_intake_guard_223();

create or replace function public.get_pdc_email_monitor_status() returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_status public.pdc_email_monitor_status%rowtype;v_pilot public.pdc_email_monitor_pilot%rowtype;v_queue integer;v_failed integer;v_review integer;
begin
 perform public.require_pdc_role('viewer');
 select * into v_status from public.pdc_email_monitor_status where singleton;
 select * into v_pilot from public.pdc_email_monitor_pilot where singleton;
 select count(*) into v_queue from public.ai_email_intake where status in('received','processing','failed') and not permanent_failure;
 select count(*) into v_failed from public.ai_email_intake where status='failed';
 select count(*) into v_review from public.pdc_supervised_review_queue where resolved_at is null;
 return jsonb_build_object(
  'environment','staging','project_ref',v_pilot.project_ref,'pilot_enabled',v_pilot.enabled,
  'mailbox_key',v_pilot.mailbox_key,'minimum_uid',v_pilot.minimum_uid,
  'outbound_email_enabled',v_pilot.outbound_email_enabled,
  'automatic_rule_application',v_pilot.automatic_rule_application,
  'automatic_authenticated_jobcards',v_pilot.automatic_authenticated_jobcards,
  'ambiguous_to_review',v_pilot.ambiguous_to_review,'exactly_once_required',v_pilot.exactly_once_required,
  'running_status',v_status.running_status,'last_started_at',v_status.last_started_at,
  'last_successful_run',v_status.last_successful_run,'last_finished_at',v_status.last_finished_at,
  'queue_count',v_queue,'failed_count',v_failed,'review_count',v_review,
  'last_error',v_status.last_error,'last_error_code',v_status.last_error_code,
  'gateway_instance_id',v_status.gateway_instance_id,'updated_at',v_status.updated_at);
end$$;
revoke all on function public.get_pdc_email_monitor_status() from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_email_monitor_status() to authenticated;

update public.pdc_email_monitor_status
set running_status='stopped',last_error='Pilot authorised; awaiting pdc-monitor profile-local service activation.',
 last_error_code='runtime_handoff_required',updated_at=clock_timestamp()
where singleton;

insert into supabase_migrations.schema_migrations(version,name,statements) values('223','supervised_monitor_pilot_activation',array[
 'Craig-authorized staging-only PMB Email Monitor supervised-learning pilot',
 'Hard reject IMAP UID below 471 and retain exactly-once queue authority',
 'Enable automatic approved rules and authenticated unambiguous job cards',
 'Route ambiguity to review and expose full authenticated status telemetry',
 'Keep outbound email disabled and production sentinel forbidden']);
notify pgrst,'reload schema';
commit;
