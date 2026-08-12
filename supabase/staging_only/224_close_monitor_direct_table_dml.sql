-- Staging-only migration 224: close direct monitor table DML and retain RPC-only runtime authority.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-224-monitor-rpc-only-authority',0));
select public.pdc_monitor_staging_guard();
do $guard$
begin
 if not public.pdc_monitor_staging_guard()
 or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or to_regclass('public.pdc_production_environment_sentinel') is not null
 or not exists(select 1 from supabase_migrations.schema_migrations where version='223' and name='supervised_monitor_pilot_activation')
 or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::integer>223)
 or exists(select 1 from supabase_migrations.schema_migrations where version='224')
 then raise exception 'PDC_224_STAGING_OR_LEDGER_MISMATCH' using errcode='55000'; end if;
 if to_regclass('public.ai_email_intake') is null
 or to_regclass('public.ai_email_attachments') is null
 or to_regclass('public.monitored_mailboxes') is null
 or to_regprocedure('public.enqueue_pdc_email_intake(jsonb,jsonb)') is null
 or to_regprocedure('public.claim_pdc_email_intake_batch(integer,text)') is null
 or to_regprocedure('public.record_pdc_email_monitor_cycle(text,text,text)') is null
 then raise exception 'PDC_224_MONITOR_RUNTIME_DEPENDENCY_MISSING' using errcode='55000'; end if;
end
$guard$;

-- SECURITY DEFINER RPC owners retain internal table access. Runtime identities receive
-- only explicitly granted EXECUTE and cannot bypass provider, UID, claim, hash,
-- attachment-atomic, idempotency, status or pilot guards with direct table writes.
revoke insert,update,delete,truncate,references,trigger on table public.ai_email_intake from public,anon,authenticated,service_role;
revoke insert,update,delete,truncate,references,trigger on table public.ai_email_attachments from public,anon,authenticated,service_role;
revoke insert,update,delete,truncate,references,trigger on table public.monitored_mailboxes from public,anon,authenticated,service_role;

do $verify$
declare r name;t name;p text;
begin
 foreach r in array array['anon'::name,'authenticated'::name,'service_role'::name] loop
  foreach t in array array['ai_email_intake'::name,'ai_email_attachments'::name,'monitored_mailboxes'::name] loop
   foreach p in array array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
    if has_table_privilege(r,format('public.%I',t),p) then
     raise exception 'PDC_224_DIRECT_TABLE_PRIVILEGE_REMAINS role=% table=% privilege=%',r,t,p using errcode='55000';
    end if;
   end loop;
  end loop;
 end loop;
 if has_function_privilege('service_role','public.enqueue_pdc_email_intake(jsonb,jsonb)'::regprocedure,'EXECUTE')
 or not has_function_privilege('authenticated','public.enqueue_pdc_email_intake(jsonb,jsonb)'::regprocedure,'EXECUTE')
 or not exists(select 1 from public.pdc_email_monitor_pilot where singleton and enabled and project_ref='cdsmnqxtyyoeoznmbidd' and minimum_uid>=471 and not outbound_email_enabled and exactly_once_required)
 then raise exception 'PDC_224_RPC_OR_PILOT_AUTHORITY_MISMATCH' using errcode='55000'; end if;
end
$verify$;

update public.pdc_email_monitor_status
set running_status='stopped',last_error='Credential-free runtime handoff published; awaiting pdc-monitor profile-local installation and explicit start.',
 last_error_code='runtime_handoff_required',updated_at=clock_timestamp()
where singleton;

insert into supabase_migrations.schema_migrations(version,name,statements) values('224','close_monitor_direct_table_dml',array[
 'Revoke direct DML on Monitor intake, attachment and mailbox tables from runtime-facing roles',
 'Preserve authenticated access only through reviewed security-definer canonical RPCs',
 'Assert UID floor, exactly-once and outbound-email-disabled pilot invariants',
 'Keep runtime stopped pending separate pdc-monitor profile installation and explicit start']);
notify pgrst,'reload schema';
commit;
