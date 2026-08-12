-- Staging-only: return retained provider authentication evidence from its canonical intake columns when claiming work.
begin;
set local lock_timeout='5s';set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-199-monitor-claim-provider-evidence',0));
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='198' and name='fix_legacy_private_attachment_policy_permissions') or exists(select 1 from supabase_migrations.schema_migrations where version='199') then raise exception 'PDC_199_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';end if;end $guard$;
create or replace function public.claim_pdc_email_intake_batch(p_limit integer,p_gateway_instance_id text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_monitor_actor_scope();rows jsonb;begin
 if p_limit not between 1 and 50 or length(btrim(coalesce(p_gateway_instance_id,''))) not between 3 and 120 then raise exception 'pdc_monitor_claim_invalid' using errcode='22023';end if;
 with candidates as(select id from public.ai_email_intake where status in('received','failed','processing') and not permanent_failure and coalesce(next_attempt_at,'-infinity')<=clock_timestamp() and(status<>'processing' or locked_at<clock_timestamp()-interval '10 minutes') order by received_at nulls last,created_at for update skip locked limit p_limit),
 claimed as(update public.ai_email_intake i set status='processing',locked_at=clock_timestamp(),locked_by=(s->>'user_id')::uuid,claim_token=gen_random_uuid(),gateway_instance_id=btrim(p_gateway_instance_id),last_attempt_at=clock_timestamp(),queue_attempts=queue_attempts+1,error_details=null,last_error_code=null from candidates c where i.id=c.id returning i.id,i.subject,i.sender_email,i.received_at,i.graph_message_id,i.internet_message_id,i.source_hash,i.raw_body,i.parsed_text,i.queue_attempts,i.claim_token,i.gateway_instance_id,i.provider_authentication,i.provider_authserv_id)
 select coalesce(jsonb_agg(to_jsonb(claimed) order by received_at),'[]'::jsonb) into rows from claimed;
 update public.pdc_email_monitor_status set running_status='running',last_started_at=clock_timestamp(),gateway_instance_id=btrim(p_gateway_instance_id),updated_at=clock_timestamp() where singleton;
 return jsonb_build_object('ok',true,'items',rows,'count',jsonb_array_length(rows));
end $$;
revoke all on function public.claim_pdc_email_intake_batch(integer,text) from public,anon,authenticated,service_role;grant execute on function public.claim_pdc_email_intake_batch(integer,text) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('199','claim_monitor_canonical_provider_evidence',array['Claim returns provider_authentication and provider_authserv_id from canonical intake columns rather than legacy extracted_data']);
commit;
