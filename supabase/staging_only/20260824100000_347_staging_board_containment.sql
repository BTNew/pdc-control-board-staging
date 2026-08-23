-- STAGING ONLY 347: durable PDC Board containment before authorised cleanse.
-- This migration disables every Monitor pilot/mailbox/writer path, records an
-- immutable pre-containment receipt, and rejects shared-Board QA fixtures.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-347-board-containment',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or to_regclass('public.pdc_staging_environment_sentinel') is null
     or (select count(*) from public.pdc_staging_environment_sentinel
         where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260822170000'
                     and name='346_serialize_cascade_before_resource_locks')
     or exists(select 1 from supabase_migrations.schema_migrations
               where version='20260824100000') then
    raise exception 'PDC_347_STAGING_SENTINEL_OR_PREDECESSOR_MISMATCH'
      using errcode='55000';
  end if;
end
$guard$;

create table public.pdc_staging_containment_receipts_347(
  receipt_id uuid primary key,
  project_ref text not null check(project_ref='cdsmnqxtyyoeoznmbidd'),
  action_key text not null unique check(action_key='craig-staging-board-containment-20260824'),
  applied_at timestamptz not null default clock_timestamp(),
  applied_by text not null check(applied_by='database_migration_owner'),
  prestate jsonb not null check(jsonb_typeof(prestate)='object'),
  poststate jsonb not null check(jsonb_typeof(poststate)='object'),
  prestate_sha256 text not null check(prestate_sha256~'^[a-f0-9]{64}$')
);
alter table public.pdc_staging_containment_receipts_347 enable row level security;
revoke all on table public.pdc_staging_containment_receipts_347
  from public,anon,authenticated,service_role;

create function public.pdc_staging_containment_receipt_immutable_347()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  raise exception 'PDC_347_CONTAINMENT_RECEIPT_IMMUTABLE' using errcode='55000';
end
$$;
revoke all on function public.pdc_staging_containment_receipt_immutable_347()
  from public,anon,authenticated,service_role;
create trigger pdc_staging_containment_receipt_immutable_347
before update or delete on public.pdc_staging_containment_receipts_347
for each row execute function public.pdc_staging_containment_receipt_immutable_347();

create function public.pdc_reject_shared_board_qa_fixture_347()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if lower(btrim(coalesce(new.source_system,''))) in ('qa_website_500','qa_wcb_synthetic')
     and new.deleted_at is null and new.board_purged_at is null then
    raise exception 'PDC_347_SHARED_BOARD_QA_FIXTURE_FORBIDDEN'
      using errcode='42501',
            hint='Run routine QA against local/disposable fixtures, not the shared staging Board.';
  end if;
  return new;
end
$$;
revoke all on function public.pdc_reject_shared_board_qa_fixture_347()
  from public,anon,authenticated,service_role;
create trigger pdc_reject_shared_board_qa_fixture_347
before insert or update of source_system,deleted_at,board_purged_at
on public.vehicles for each row
execute function public.pdc_reject_shared_board_qa_fixture_347();

do $contain$
declare
  v_pre jsonb;
  v_post jsonb;
begin
  v_pre:=jsonb_build_object(
    'vehicles_total',(select count(*) from public.vehicles),
    'vehicles_operational',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null),
    'workshop_bookings',(select count(*) from public.workshop_bookings),
    'vehicle_work_items',(select count(*) from public.vehicle_work_items),
    'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),
    'running_status',(select running_status from public.pdc_email_monitor_status where singleton),
    'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
    'active_monitor_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
    'failed_intakes',(select count(*) from public.ai_email_intake where status='failed')
  );

  update public.pdc_email_monitor_pilot
     set enabled=false,
         outbound_email_enabled=false,
         automatic_rule_application=false,
         automatic_authenticated_jobcards=false,
         updated_at=clock_timestamp()
   where singleton;

  update public.monitored_mailboxes
     set active=false,
         test_mode=true,
         config=(config-'supervised_pilot_enabled')||jsonb_build_object(
           'supervised_pilot_enabled',false,
           'outbound_email_enabled',false,
           'containment','craig-disabled-until-separately-authorised'),
         updated_at=clock_timestamp()
   where active or mailbox_key='pdc_pmb_email';

  update public.pdc_monitor_stage_activation_writers
     set active=false,
         revoked_at=coalesce(revoked_at,clock_timestamp()),
         reason='Craig staging containment 2026-08-24: disabled until separately authorised'
   where active or revoked_at is null;

  update public.pdc_email_monitor_status
     set running_status='stopped',
         gateway_instance_id=null,
         last_finished_at=coalesce(last_finished_at,clock_timestamp()),
         last_error='Staging Monitor disabled by Craig containment rule; no mailbox or writer authority.',
         last_error_code='staging_contained_no_mailbox',
         updated_at=clock_timestamp()
   where singleton;

  v_post:=jsonb_build_object(
    'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),
    'outbound_email_enabled',(select outbound_email_enabled from public.pdc_email_monitor_pilot where singleton),
    'automatic_rule_application',(select automatic_rule_application from public.pdc_email_monitor_pilot where singleton),
    'automatic_authenticated_jobcards',(select automatic_authenticated_jobcards from public.pdc_email_monitor_pilot where singleton),
    'running_status',(select running_status from public.pdc_email_monitor_status where singleton),
    'gateway_instance_id',(select gateway_instance_id from public.pdc_email_monitor_status where singleton),
    'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
    'active_monitor_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
    'qa_fixture_guard',true
  );

  if (v_post->>'pilot_enabled')::boolean
     or (v_post->>'outbound_email_enabled')::boolean
     or (v_post->>'automatic_rule_application')::boolean
     or (v_post->>'automatic_authenticated_jobcards')::boolean
     or v_post->>'running_status'<>'stopped'
     or v_post->>'gateway_instance_id' is not null
     or (v_post->>'active_mailboxes')::integer<>0
     or (v_post->>'active_monitor_writers')::integer<>0 then
    raise exception 'PDC_347_CONTAINMENT_POSTCONDITION_FAILED' using errcode='55000';
  end if;

  insert into public.pdc_staging_containment_receipts_347(
    receipt_id,project_ref,action_key,applied_by,prestate,poststate,prestate_sha256)
  values(
    gen_random_uuid(),'cdsmnqxtyyoeoznmbidd','craig-staging-board-containment-20260824',
    'database_migration_owner',v_pre,v_post,
    encode(extensions.digest(convert_to(v_pre::text,'UTF8'),'sha256'),'hex'));
end
$contain$;

create function public.get_pdc_staging_containment_status_347()
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public as $$
begin
  perform public.require_pdc_role('viewer');
  return jsonb_build_object(
    'environment','staging',
    'project_ref','cdsmnqxtyyoeoznmbidd',
    'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),
    'outbound_email_enabled',(select outbound_email_enabled from public.pdc_email_monitor_pilot where singleton),
    'automatic_rule_application',(select automatic_rule_application from public.pdc_email_monitor_pilot where singleton),
    'automatic_authenticated_jobcards',(select automatic_authenticated_jobcards from public.pdc_email_monitor_pilot where singleton),
    'running_status',(select running_status from public.pdc_email_monitor_status where singleton),
    'gateway_instance_id',(select gateway_instance_id from public.pdc_email_monitor_status where singleton),
    'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
    'active_monitor_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
    'operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null),
    'visible_operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null and visible_on_board),
    'workshop_bookings',(select count(*) from public.workshop_bookings),
    'vehicle_work_items',(select count(*) from public.vehicle_work_items),
    'qa_fixture_guard',exists(select 1 from pg_trigger where tgrelid='public.vehicles'::regclass and tgname='pdc_reject_shared_board_qa_fixture_347' and not tgisinternal),
    'contained_at',(select applied_at from public.pdc_staging_containment_receipts_347 where action_key='craig-staging-board-containment-20260824'));
end
$$;
revoke all on function public.get_pdc_staging_containment_status_347()
  from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_staging_containment_status_347() to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260824100000','347_staging_board_containment',array[
  'Exact staging sentinel and exact predecessor; Production sentinel forbidden',
  'Disable Monitor pilot, automatic rules/jobcards, outbound mail, mailbox and every stage writer',
  'Set runtime status stopped and clear gateway identity',
  'Reject qa_website_500 and qa_wcb_synthetic fixtures from the shared staging Board',
  'Preserve immutable pre/post containment receipt and expose typed authenticated status'
]);
notify pgrst,'reload schema';
commit;
