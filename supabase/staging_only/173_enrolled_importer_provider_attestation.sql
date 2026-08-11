-- Staging-only enrolled Importer provider-attestation permission remediation.
begin;
set local lock_timeout='10s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-173',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='172' and name='sublet_calendar_return_station_completion')
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>172)
     or exists(select 1 from supabase_migrations.schema_migrations where version='173')
     or to_regprocedure('public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)') is null then
    raise exception 'PDC_173_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;
end
$guard$;

alter table public.pdc_provider_email_observations
  add column attested_by uuid,
  add column attested_authority text;

create or replace function public.attest_pdc_provider_email_observation(
  p_intake_id uuid,
  p_attachment_id uuid,
  p_expected_parent_hash text,
  p_expected_attachment_hash text,
  p_provider_message_id text,
  p_provider_authserv_id text,
  p_authentication jsonb
) returns jsonb
language plpgsql security definer
set search_path=pg_catalog,public,extensions
as $attest$
declare
  v_intake public.ai_email_intake%rowtype;
  v_attachment public.ai_email_attachments%rowtype;
  v_mailbox public.monitored_mailboxes%rowtype;
  v_existing public.pdc_provider_email_observations%rowtype;
  v_parent text:=lower(btrim(coalesce(p_expected_parent_hash,'')));
  v_attachment_hash text:=lower(btrim(coalesce(p_expected_attachment_hash,'')));
  v_message_id text:=btrim(coalesce(p_provider_message_id,''));
  v_authserv text:=lower(btrim(coalesce(p_provider_authserv_id,'')));
  v_auth jsonb:=coalesce(p_authentication,'null'::jsonb);
  v_sender text;
  v_request text;
  v_actor uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_authority text:=auth.role();
  v_enrolled_importer boolean:=false;
begin
  if v_authority='authenticated' and v_actor is not null and v_actor_email<>'' then
    select exists(
      select 1
      from public.pdc_user_roles r
      join public.pdc_monitor_stage_activation_writers w on w.user_id=r.auth_user_id
      where r.auth_user_id=v_actor and lower(r.email)=v_actor_email
        and r.role='importer' and r.active and r.account_status='approved'
        and w.active and w.revoked_at is null
    ) into v_enrolled_importer;
  end if;

  if not public.pdc_monitor_staging_guard()
     or not(v_authority='service_role' or v_enrolled_importer)
     or p_intake_id is null or p_attachment_id is null
     or v_parent!~'^[a-f0-9]{64}$' or v_attachment_hash!~'^[a-f0-9]{64}$'
     or length(v_message_id) not between 1 and 1024 or v_authserv<>'mx.google.com'
     or jsonb_typeof(v_auth) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_auth) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not(v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb) then
    return public.navision_backend_response(false,'provider_observation_invalid');
  end if;

  select * into v_intake from public.ai_email_intake where id=p_intake_id for share;
  if not found then return public.navision_backend_response(false,'intake_not_found'); end if;
  select * into v_attachment from public.ai_email_attachments where id=p_attachment_id and intake_id=p_intake_id for share;
  if not found then return public.navision_backend_response(false,'attachment_not_found'); end if;
  select * into v_mailbox from public.monitored_mailboxes where id=v_intake.monitored_mailbox_id for share;
  v_sender:=lower(btrim(coalesce(v_intake.sender_email,'')));
  if not found or not v_mailbox.active
     or lower(btrim(coalesce(v_intake.recipient_mailbox,'')))<>lower(btrim(v_mailbox.mailbox_address))
     or lower(coalesce(v_intake.source_hash,''))<>v_parent
     or lower(coalesce(v_attachment.source_hash,''))<>v_attachment_hash
     or v_message_id is distinct from coalesce(nullif(btrim(v_intake.internet_message_id),''),v_intake.graph_message_id)
     or v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2)
     or not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active
       and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')) then
    return public.navision_backend_response(false,'provider_observation_binding_mismatch');
  end if;

  v_request:=encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version','159.2','intake_id',p_intake_id,'attachment_id',p_attachment_id,
    'parent_source_hash',v_parent,'attachment_source_hash',v_attachment_hash,
    'provider_message_id',v_message_id,'provider_authserv_id',v_authserv,'authentication',v_auth
  )::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-provider-email-observation-159:'||p_intake_id::text,0));
  select * into v_existing from public.pdc_provider_email_observations where intake_id=p_intake_id;
  if found then
    if v_existing.request_sha256<>v_request or v_existing.attachment_id<>p_attachment_id then
      return public.navision_backend_response(false,'provider_observation_replay_conflict');
    end if;
    return public.navision_backend_response(true,'provider_observation_already_attested',jsonb_build_object(
      'observation_id',v_existing.observation_id,'request_sha256',v_existing.request_sha256));
  end if;

  insert into public.pdc_provider_email_observations(
    contract_version,intake_id,attachment_id,parent_source_hash,attachment_source_hash,
    provider_message_id,provider_authserv_id,authentication,request_sha256,attested_by,attested_authority
  ) values('159.2',p_intake_id,p_attachment_id,v_parent,v_attachment_hash,v_message_id,v_authserv,v_auth,v_request,
    case when v_authority='authenticated' then v_actor else null end,v_authority)
  returning * into v_existing;
  return public.navision_backend_response(true,'provider_observation_attested',jsonb_build_object(
    'observation_id',v_existing.observation_id,'request_sha256',v_existing.request_sha256));
end
$attest$;

revoke all on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) to authenticated,service_role;

do $post$
begin
  if has_function_privilege('anon','public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)','EXECUTE')
     or not has_function_privilege('service_role','public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)','EXECUTE') then
    raise exception 'PDC_173_ATTESTATION_ACL_INVALID' using errcode='42501';
  end if;
end
$post$;

insert into supabase_migrations.schema_migrations(version,name,statements) values('173','enrolled_importer_provider_attestation',array[
  'permit only approved enrolled Importers or service role to attest provider evidence',
  'retain exact mailbox sender message hash authentication and replay bindings',
  'record the attesting actor and authority on immutable observation evidence'
]);
notify pgrst,'reload schema';
commit;
