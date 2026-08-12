-- Staging-only remediation: durable attachment deduplication targets the partial source-hash index correctly.
begin;
do $guard$ begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='182' and name='exact_auditor_effective_rollback_filter') or exists(select 1 from supabase_migrations.schema_migrations where version='183') then raise exception 'PDC_183_GUARD_MISMATCH';end if;
end $guard$;
create or replace function public.enqueue_pdc_email_intake(p_message jsonb,p_attachments jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_monitor_actor_scope();v_id bigint;v_new boolean:=false;a jsonb;
begin
 if coalesce(p_message->>'graph_message_id',p_message->>'provider_uid','')='' or coalesce(p_message->>'source_hash','')='' then raise exception 'pdc_monitor_identity_required' using errcode='22023';end if;
 insert into public.ai_email_intake(graph_message_id,internet_message_id,provider_uid,source_hash,subject,sender_email,received_at,raw_body,parsed_text,attachment_names,status,queue_attempts,next_attempt_at,created_at,updated_at)
 values(p_message->>'graph_message_id',p_message->>'internet_message_id',p_message->>'provider_uid',p_message->>'source_hash',p_message->>'subject',p_message->>'sender_email',nullif(p_message->>'received_at','')::timestamptz,p_message->>'raw_body',p_message->>'parsed_text',coalesce(array(select jsonb_array_elements_text(coalesce(p_message->'attachment_names','[]'::jsonb))),array[]::text[]),'received',0,clock_timestamp(),clock_timestamp(),clock_timestamp())
 on conflict(source_hash) where source_hash is not null do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.ai_email_intake where source_hash=p_message->>'source_hash';else v_new:=true;end if;
 if v_new then
  for a in select value from jsonb_array_elements(coalesce(p_attachments,'[]'::jsonb)) loop
   insert into public.ai_email_attachments(intake_id,file_name,content_type,size_bytes,source_hash,storage_path,created_at)
   values(v_id,a->>'file_name',a->>'content_type',coalesce((a->>'size_bytes')::bigint,0),a->>'source_hash',a->>'storage_path',clock_timestamp())
   on conflict(source_hash) where source_hash is not null do nothing;
  end loop;
 end if;
 return jsonb_build_object('ok',true,'code',case when v_new then 'pdc_monitor_intake_enqueued' else 'pdc_monitor_intake_duplicate' end,'intake_id',v_id,'duplicate',not v_new,'actor_email',s->>'email');
end $$;
revoke all on function public.enqueue_pdc_email_intake(jsonb,jsonb) from public,anon,authenticated,service_role;grant execute on function public.enqueue_pdc_email_intake(jsonb,jsonb) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('183','fix_monitor_attachment_partial_hash_conflict',array['Bind intake and attachment idempotency to their partial source-hash unique indexes']);
commit;
