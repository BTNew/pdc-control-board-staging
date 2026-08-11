-- Staging-only remediation: restore service-role provider authority and expose canonical key numbers.
begin;
set local lock_timeout='10s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-174',0));
do $guard$
begin
  if not public.pdc_monitor_staging_guard() then raise exception 'Migration 174 is staging-only'; end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='173' and name='enrolled_importer_provider_attestation') then raise exception 'Migration 174 requires exact predecessor 173'; end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version::integer>173) or exists(select 1 from supabase_migrations.schema_migrations where version='174') then raise exception 'Migration 174 refuses repeated or newer ledger state'; end if;
end
$guard$;

-- Restore the original two-authority boundary. Caller-supplied Gmail authentication
-- claims remain service-role-only and cannot be self-attested by the Importer actor.
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
begin
  if not public.pdc_monitor_staging_guard() or auth.role()<>'service_role'
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
    provider_message_id,provider_authserv_id,authentication,request_sha256
  ) values('159.2',p_intake_id,p_attachment_id,v_parent,v_attachment_hash,v_message_id,v_authserv,v_auth,v_request)
  returning * into v_existing;
  return public.navision_backend_response(true,'provider_observation_attested',jsonb_build_object(
    'observation_id',v_existing.observation_id,'request_sha256',v_existing.request_sha256));
end
$attest$;
revoke all on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) to service_role;

-- The calendar must receive the canonical key number rather than guessing it client-side.
create or replace function public.pdc_vehicle_key_number_json(p_vehicle_id uuid)
returns jsonb
language sql stable security definer
set search_path=pg_catalog,public
as $key$
  select coalesce((select jsonb_build_object('key_number',v.key_number) from public.vehicles v where v.id=p_vehicle_id),'{}'::jsonb);
$key$;
revoke all on function public.pdc_vehicle_key_number_json(uuid) from public,anon,authenticated;
grant execute on function public.pdc_vehicle_key_number_json(uuid) to service_role;

alter function public.get_pdc_email_vehicle_location_snapshot() rename to get_pdc_email_vehicle_location_snapshot_pre_174;
create function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb
language plpgsql stable security definer
set search_path=pg_catalog,public
as $snapshot$
declare v_response jsonb; v_rows jsonb;
begin
  v_response:=public.get_pdc_email_vehicle_location_snapshot_pre_174();
  if not coalesce((v_response->>'ok')::boolean,false) then return v_response; end if;
  select coalesce(jsonb_agg(row_value||public.pdc_vehicle_key_number_json((row_value->>'id')::uuid)),'[]'::jsonb)
    into v_rows
    from jsonb_array_elements(coalesce(v_response#>'{data,vehicles}','[]'::jsonb)) row_value;
  return jsonb_set(v_response,'{data,vehicles}',v_rows,true);
end
$snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot_pre_174() from public,anon,authenticated;
revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public,anon,authenticated;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('174','restore_provider_attestation_boundary_and_key_snapshot',array['restore service-role attestation boundary; expose canonical key_number in authenticated snapshot']);
commit;
