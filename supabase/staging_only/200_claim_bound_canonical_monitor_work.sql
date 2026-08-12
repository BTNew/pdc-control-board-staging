-- Staging-only: bridge active durable queue claims to the legacy canonical adapter without weakening stale-worker guards.
begin;
set local lock_timeout='5s';set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-200-claimed-canonical-work',0));
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='199' and name='claim_monitor_canonical_provider_evidence') or exists(select 1 from supabase_migrations.schema_migrations where version='200') then raise exception 'PDC_200_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';end if;end $guard$;
create or replace function public.process_claimed_pdc_email_intake_work(p_intake_id uuid,p_claim_token uuid,p_gateway_instance_id text,p_expected_source_hash text,p_extraction_hash text,p_extraction jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public set statement_timeout='180s' as $$
declare s jsonb:=public.pdc_monitor_actor_scope();r jsonb;begin
 perform 1 from public.ai_email_intake i where i.id=p_intake_id and i.status='processing' and i.locked_by=(s->>'user_id')::uuid and i.claim_token=p_claim_token and i.gateway_instance_id=btrim(p_gateway_instance_id) and i.locked_at>=clock_timestamp()-interval '10 minutes' for update;
 if not found then raise exception 'pdc_monitor_work_claim_missing' using errcode='42501';end if;
 update public.ai_email_intake set status='received' where id=p_intake_id;
 begin
  r:=public.process_email_intake_work(p_intake_id,p_expected_source_hash,p_extraction_hash,p_extraction,'pdc-monitor');
 exception when others then
  update public.ai_email_intake set status='processing' where id=p_intake_id and claim_token=p_claim_token and gateway_instance_id=btrim(p_gateway_instance_id);
  raise;
 end;
 update public.ai_email_intake set status='processing' where id=p_intake_id and claim_token=p_claim_token and gateway_instance_id=btrim(p_gateway_instance_id);
 if not found then raise exception 'pdc_monitor_work_claim_lost' using errcode='42501';end if;
 return r;
end $$;
revoke all on function public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb) from public,anon,authenticated,service_role;grant execute on function public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('200','claim_bound_canonical_monitor_work',array['Require active unique claim token and gateway instance before canonical processing','Temporarily bridge durable processing state to legacy canonical adapter and restore queue ownership before terminal result recording']);
commit;
