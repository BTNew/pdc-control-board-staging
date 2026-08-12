-- Staging-only: persist bounded extracted attachment evidence through the active instance-bound claim.
begin;
set local lock_timeout='5s';set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-191-monitor-extraction',0));
do $guard$ begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or not exists(select 1 from supabase_migrations.schema_migrations where version='190' and name='monitor_claim_tokens_provider_binding_and_scoped_reprocess')
    or exists(select 1 from supabase_migrations.schema_migrations where version='191') then raise exception 'PDC_191_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';end if;
end $guard$;
create or replace function public.record_pdc_monitor_attachment_extraction(p_intake_id uuid,p_attachment_id uuid,p_claim_token uuid,p_gateway_instance_id text,p_source_hash text,p_extracted_text text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_monitor_actor_scope();begin
 if lower(coalesce(p_source_hash,''))!~'^[a-f0-9]{64}$' or length(coalesce(p_extracted_text,'')) not between 1 and 500000 then raise exception 'pdc_monitor_extraction_invalid' using errcode='22023';end if;
 if not exists(select 1 from public.ai_email_intake i where i.id=p_intake_id and i.status='processing' and i.locked_by=(s->>'user_id')::uuid and i.claim_token=p_claim_token and i.gateway_instance_id=btrim(p_gateway_instance_id) and i.locked_at>=clock_timestamp()-interval '10 minutes') then raise exception 'pdc_monitor_extraction_claim_missing' using errcode='42501';end if;
 update public.ai_email_attachments set text_extraction_status='extracted',extracted_text=p_extracted_text,extraction_error=null where id=p_attachment_id and intake_id=p_intake_id and lower(source_hash)=lower(p_source_hash);
 if not found then raise exception 'pdc_monitor_extraction_attachment_missing' using errcode='P0002';end if;
 return jsonb_build_object('ok',true,'intake_id',p_intake_id,'attachment_id',p_attachment_id);
end $$;
revoke all on function public.record_pdc_monitor_attachment_extraction(uuid,uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.record_pdc_monitor_attachment_extraction(uuid,uuid,uuid,text,text,text) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('191','monitor_claim_bound_attachment_extraction',array['Persist bounded extracted attachment text only through the active instance-bound claim for canonical evidence binding']);
commit;
