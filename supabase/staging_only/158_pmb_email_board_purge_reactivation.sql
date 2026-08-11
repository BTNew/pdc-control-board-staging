-- Staging-only Migration 158: fresh authenticated exact-Stock evidence may reactivate
-- only the same canonical vehicle tombstoned by the complete staging Board purge.
begin;
do $pre$ begin
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_158_STAGING_ONLY' using errcode='55000';end if;
 if not exists(select 1 from supabase_migrations.schema_migrations where version='157' and name='bounded_pmb_workbook_importer_review') then
  raise exception 'PDC_158_PREDECESSOR_REQUIRED' using errcode='55000';
 end if;
 if exists(select 1 from supabase_migrations.schema_migrations where version='158') then raise exception 'PDC_158_ALREADY_APPLIED' using errcode='55000';end if;
end $pre$;
CREATE OR REPLACE FUNCTION public.submit_pdc_ai_intake_observation_pre135(p_source_hash text, p_evidence_hash text, p_source_uid text, p_sender_address text, p_authentication jsonb, p_source_received_at timestamp with time zone, p_subject text, p_action_type text, p_stock_number text, p_summary text, p_observations jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text := public.current_pdc_user_role()::text;
  v_source_hash text := lower(btrim(coalesce(p_source_hash,'')));
  v_evidence_hash text := lower(btrim(coalesce(p_evidence_hash,'')));
  v_source_uid text := btrim(coalesce(p_source_uid,''));
  v_sender text := lower(btrim(coalesce(p_sender_address,'')));
  v_authentication jsonb := coalesce(p_authentication,'{}'::jsonb);
  v_subject text := btrim(coalesce(p_subject,''));
  v_action text := lower(btrim(coalesce(p_action_type,'')));
  v_stock text;
  v_summary text := btrim(coalesce(p_summary,''));
  v_observations jsonb := coalesce(p_observations,'{}'::jsonb);
  v_backend_ids uuid[] := '{}'::uuid[];
  v_backend public.navision_backend_records%rowtype;
  v_navision_revision bigint;
  v_proposal_id uuid := gen_random_uuid();
  v_dedupe_key text;
  v_fingerprint text;
  v_existing public.pdc_ai_intake_proposals%rowtype;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_user_id is null or v_role not in ('viewer','importer')
     or not exists (
       select 1 from public.pdc_monitor_stage_activation_writers w
       where w.user_id=v_user_id and w.active and w.revoked_at is null
     ) then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if v_source_hash !~ '^[a-f0-9]{64}$'
     or v_evidence_hash !~ '^[a-f0-9]{64}$'
     or length(v_source_uid) < 1 or length(v_source_uid) > 100
     or v_sender !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
     or split_part(v_sender,'@',2) not in ('broometoyota.com.au','pmgwa.com.au')
     or jsonb_typeof(v_authentication) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_authentication) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_authentication->>'sender_domain' is distinct from split_part(v_sender,'@',2)
     or v_authentication->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not (v_authentication->'spf_aligned'='true'::jsonb
             or v_authentication->'dkim_aligned'='true'::jsonb
             or v_authentication->'dmarc_aligned'='true'::jsonb)
     or p_source_received_at is null
     or p_source_received_at > clock_timestamp()+interval '5 minutes'
     or p_source_received_at < clock_timestamp()-interval '120 days'
     or length(v_subject) < 1 or length(v_subject) > 300
     or v_action not in ('board_activate_only','review_only')
     or length(v_summary) < 5 or length(v_summary) > 2000
     or jsonb_typeof(v_observations) is distinct from 'object'
     or length(v_observations::text) > 16000 then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  select revision into v_navision_revision
  from public.navision_backend_revision where singleton;

  if v_action='board_activate_only' then
    if not public.is_real_vehicle_stock_number(p_stock_number) then
      return public.navision_backend_response(false,'invalid_stock');
    end if;
    v_stock:=public.normalize_vehicle_stock_number(p_stock_number);
    select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_backend_ids
    from public.navision_backend_records r
    where r.source_system='microsoft_navision'
      and r.dealer_code in ('14450','37047')
      and r.is_current and r.record_status='current'
      and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
      and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    if cardinality(v_backend_ids)<>1 then
      return public.navision_backend_response(false,'identity_conflict',jsonb_build_object('match_count',cardinality(v_backend_ids)));
    end if;
    select * into v_backend from public.navision_backend_records where id=v_backend_ids[1];
    if exists (
      select 1 from public.vehicles v where v.stock_number_normalized=v_stock and v.deleted_at is null
      union all
      select 1 from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock
    ) then
      return public.navision_backend_response(false,'operational_identity_present');
    end if;
  else
    v_stock:=case when public.is_real_vehicle_stock_number(p_stock_number) then public.normalize_vehicle_stock_number(p_stock_number) else null end;
  end if;

  v_dedupe_key:=encode(digest(jsonb_build_object(
    'contract_version',1,'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,
    'action_type',v_action,'stock_number',v_stock
  )::text,'sha256'),'hex');
  v_fingerprint:=upper(substr(encode(digest(jsonb_build_object(
    'contract_version',1,'proposal_id',v_proposal_id,'dedupe_key',v_dedupe_key,
    'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'source_uid',v_source_uid,
    'sender_address',v_sender,'authentication',v_authentication,'source_received_at',p_source_received_at,'subject',v_subject,
    'action_type',v_action,'stock_number',v_stock,'backend_record_id',v_backend.id,
    'backend_record_version',v_backend.version,'observed_navision_revision',v_navision_revision,
    'summary',v_summary,'observations',v_observations
  )::text,'sha256'),'hex'),1,16));

  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake:'||v_dedupe_key,0));
  select * into v_existing from public.pdc_ai_intake_proposals where dedupe_key=v_dedupe_key;
  if found then
    return public.navision_backend_response(true,'already_noticed',jsonb_build_object(
      'proposal_id',v_existing.proposal_id,'status',v_existing.status,
      'version',v_existing.version,'fingerprint',v_existing.fingerprint));
  end if;

  insert into public.pdc_email_source_claims(source_hash,contract_name,proposal_ref)
  values(v_source_hash,'pdc_ai_intake_063',v_proposal_id::text)
  on conflict(source_hash) do nothing;
  if not found then
    return public.navision_backend_response(false,'source_already_claimed');
  end if;

  insert into public.pdc_ai_intake_proposals(
    proposal_id,dedupe_key,source_hash,evidence_hash,source_uid,sender_address,authentication,
    source_received_at,subject,action_type,stock_number,backend_record_id,
    backend_record_version,observed_navision_revision,summary,observations,
    fingerprint,submitted_by
  ) values(
    v_proposal_id,v_dedupe_key,v_source_hash,v_evidence_hash,v_source_uid,v_sender,v_authentication,
    p_source_received_at,v_subject,v_action,v_stock,v_backend.id,
    v_backend.version,v_navision_revision,v_summary,v_observations,
    v_fingerprint,v_user_id
  );
  insert into public.pdc_ai_intake_history(
    proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
    stock_number,action_type,details
  ) values(
    v_proposal_id,'noticed',v_user_id,public.current_actor_email(),1,v_fingerprint,
    v_stock,v_action,jsonb_build_object('source_uid',v_source_uid,'sender_address',v_sender,'summary',v_summary)
  );
  update public.pdc_ai_intake_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
  return public.navision_backend_response(true,'noticed',jsonb_build_object(
    'proposal_id',v_proposal_id,'status','pending','version',1,'fingerprint',v_fingerprint));
exception when unique_violation then
  return public.navision_backend_response(false,'proposal_conflict');
end;
$function$;

CREATE OR REPLACE FUNCTION public.submit_pdc_ai_intake_observation(p_source_hash text, p_evidence_hash text, p_source_uid text, p_sender_address text, p_authentication jsonb, p_source_received_at timestamp with time zone, p_subject text, p_action_type text, p_stock_number text, p_summary text, p_observations jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_submit jsonb;
  v_auto jsonb;
  v_proposal_id uuid;
  v_status text;
  v_actor_id uuid:=auth.uid();
  v_actor_email text:=public.current_actor_email();
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_actor_id is null or nullif(btrim(v_actor_email),'') is null then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_user_roles r
  where r.auth_user_id=v_actor_id and r.email=lower(btrim(v_actor_email))
    and r.role in('viewer','importer') and r.active and r.account_status='approved'
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=v_actor_id and w.active and w.revoked_at is null
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  -- Serialize proposal creation with the one-time exact backlog snapshot.
  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-submit-gate:135.1',0));
  v_submit:=public.submit_pdc_ai_intake_observation_pre135(
    p_source_hash,p_evidence_hash,p_source_uid,p_sender_address,p_authentication,
    p_source_received_at,p_subject,p_action_type,p_stock_number,p_summary,p_observations
  );
  if not coalesce((v_submit->>'ok')::boolean,false)
     or lower(btrim(coalesce(p_action_type,'')))<>'board_activate_only' then
    return v_submit;
  end if;
  begin
    v_proposal_id:=(v_submit->'data'->>'proposal_id')::uuid;
  exception when others then
    return v_submit;
  end;
  if v_proposal_id is null then return v_submit; end if;
  v_auto:=public.pdc_auto_apply_ai_intake_activation_internal(
    v_proposal_id,v_actor_id,lower(btrim(v_actor_email)),false
  );
  select status into v_status from public.pdc_ai_intake_proposals where proposal_id=v_proposal_id;
  v_submit:=jsonb_set(v_submit,'{data,status}',to_jsonb(coalesce(v_status,'pending')),true);
  return jsonb_set(v_submit,'{data,auto_activation}',coalesce(v_auto,'null'::jsonb),true);
end
$function$;

CREATE OR REPLACE FUNCTION public.pdc_auto_apply_ai_intake_activation_internal(p_proposal_id uuid, p_actor_id uuid, p_actor_email text, p_allow_current_record_refresh boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_actor_email text:=lower(btrim(coalesce(p_actor_email,'')));
  v_proposal public.pdc_ai_intake_proposals%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_activation public.navision_board_activations%rowtype;
  v_receipt public.pdc_ai_intake_auto_activation_receipts%rowtype;
  v_duplicate public.pdc_ai_intake_proposals%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_stock_ids uuid[]:='{}'::uuid[];
  v_operational_ids uuid[]:='{}'::uuid[];
  v_vin_ids uuid[]:='{}'::uuid[];
  v_navision_revision bigint;
  v_next_navision_revision bigint;
  v_inbox_revision bigint;
  v_transition_count integer:=0;
  v_duplicate_count integer:=0;
  v_vehicle_id uuid;
  v_vin text;
  v_response jsonb;
  v_duplicate_response jsonb;
  v_mutation_error text;
  v_activation_found boolean:=false;
  v_reactivating_board_purge boolean:=false;
  v_request_hash text;
  v_primary_proposal_id uuid;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if p_proposal_id is null or p_actor_id is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  -- Hold the approved Viewer role and enrolled writer authority through commit.
  perform 1 from public.pdc_user_roles r
  where r.auth_user_id=p_actor_id and r.email=v_actor_email
    and r.role in('viewer','importer') and r.active and r.account_status='approved'
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=p_actor_id and w.active and w.revoked_at is null
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-auto:'||p_proposal_id::text,0));

  -- Use the same proposal/inbox lock order as the Administrator decision RPC.
  perform pg_advisory_xact_lock(hashtextextended('pdc-ai-intake-decision:'||p_proposal_id::text,0));
  select revision into v_inbox_revision
  from public.pdc_ai_intake_revision where singleton for update;
  select * into v_proposal
  from public.pdc_ai_intake_proposals
  where proposal_id=p_proposal_id;
  if not found then return public.navision_backend_response(false,'proposal_not_found'); end if;
  if v_proposal.action_type<>'board_activate_only'
     or not public.is_real_vehicle_stock_number(v_proposal.stock_number) then
    return public.navision_backend_response(false,'proposal_not_auto_eligible');
  end if;
  -- Acquire the shared Stock lock before any proposal row lock, then lock the
  -- complete same-Stock fan-in deterministically.
  perform pg_advisory_xact_lock(hashtextextended(
    'navision-board-activate:ai-intake-auto:'||v_proposal.stock_number,0
  ));
  perform proposal_id from public.pdc_ai_intake_proposals
  where status='pending' and action_type='board_activate_only'
    and stock_number=v_proposal.stock_number
  order by proposal_id for update;
  select * into v_proposal
  from public.pdc_ai_intake_proposals
  where proposal_id=p_proposal_id
  for update;
  if not found then return public.navision_backend_response(false,'proposal_not_found'); end if;
  perform 1 from public.pdc_email_source_claims c
  where c.source_hash=v_proposal.source_hash
    and c.contract_name='pdc_ai_intake_063'
    and c.proposal_ref=v_proposal.proposal_id::text
  for share;
  if not found then return public.navision_backend_response(false,'source_claim_conflict'); end if;
  v_request_hash:=encode(digest(jsonb_build_object(
    'policy_version','135.1','proposal_id',v_proposal.proposal_id,
    'fingerprint',v_proposal.fingerprint,'source_hash',v_proposal.source_hash,
    'evidence_hash',v_proposal.evidence_hash,'action_type',v_proposal.action_type,
    'stock_number',v_proposal.stock_number,'backend_record_id',v_proposal.backend_record_id,
    'backend_record_version',v_proposal.backend_record_version,
    'actor_id',p_actor_id,'actor_email',v_actor_email,
    'allow_current_record_refresh',coalesce(p_allow_current_record_refresh,false)
  )::text,'sha256'),'hex');
  select * into v_receipt
  from public.pdc_ai_intake_auto_activation_receipts
  where proposal_id=p_proposal_id;
  if found then
    if v_receipt.policy_version<>'135.1' or v_receipt.request_hash<>v_request_hash
       or v_receipt.actor_id<>p_actor_id or v_receipt.actor_email<>v_actor_email then
      return public.navision_backend_response(false,'auto_receipt_conflict');
    end if;
    return v_receipt.response;
  end if;
  if v_proposal.status<>'pending' then
    return coalesce(v_proposal.result,public.navision_backend_response(true,'proposal_consumed',jsonb_build_object(
      'proposal_id',v_proposal.proposal_id,'status',v_proposal.status,'version',v_proposal.version
    )));
  end if;
  if v_proposal.submitted_by<>p_actor_id or v_proposal.action_type<>'board_activate_only'
     or v_proposal.backend_record_id is null or v_proposal.backend_record_version is null
     or not public.is_real_vehicle_stock_number(v_proposal.stock_number) then
    return public.navision_backend_response(false,'proposal_not_auto_eligible');
  end if;
  if v_proposal.submitted_at<clock_timestamp()-interval '14 days'
     or v_proposal.source_received_at<clock_timestamp()-interval '30 days' then
    return public.navision_backend_response(false,'proposal_expired');
  end if;
  if jsonb_typeof(v_proposal.authentication) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_proposal.authentication) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_proposal.authentication->>'sender_domain' is distinct from split_part(v_proposal.sender_address,'@',2)
     or v_proposal.authentication->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not (v_proposal.authentication->'spf_aligned'='true'::jsonb
             or v_proposal.authentication->'dkim_aligned'='true'::jsonb
             or v_proposal.authentication->'dmarc_aligned'='true'::jsonb)
     or jsonb_typeof(v_proposal.observations) is distinct from 'object'
     or not (v_proposal.observations ?& array[
       'attachment_manifest','authenticated','conflicts','customer','eta_to_kewdale',
       'location_evidence','match_outcome','match_reason','required_work','sender_domain','vehicle'
     ])
     or v_proposal.observations->'authenticated' is distinct from 'true'::jsonb
     or v_proposal.observations->>'sender_domain' is distinct from v_proposal.authentication->>'sender_domain'
     or v_proposal.observations->>'match_outcome' not in ('resolved_navision','resolved_navision_exact') then
    return public.navision_backend_response(false,'proposal_evidence_invalid');
  end if;
  if jsonb_typeof(v_proposal.observations->'conflicts') is distinct from 'array'
     or v_proposal.observations->'conflicts'<>'[]'::jsonb
     or (v_proposal.observations ? 'cancelled' and v_proposal.observations->'cancelled' is distinct from 'false'::jsonb)
     or (v_proposal.observations ? 'canceled' and v_proposal.observations->'canceled' is distinct from 'false'::jsonb)
     or (v_proposal.observations ? 'is_cancelled' and v_proposal.observations->'is_cancelled' is distinct from 'false'::jsonb)
     or (v_proposal.observations ? 'is_canceled' and v_proposal.observations->'is_canceled' is distinct from 'false'::jsonb)
     or concat_ws(' ',v_proposal.subject,v_proposal.summary)~*'\m(cancelled|canceled|cancellation)\M' then
    return public.navision_backend_response(false,'proposal_conflicted_or_cancelled');
  end if;

  -- Select the one deterministic primary after the complete fan-in is locked.
  select proposal_id into v_primary_proposal_id
  from public.pdc_ai_intake_proposals
  where status='pending' and action_type='board_activate_only'
    and stock_number=v_proposal.stock_number
  order by source_received_at desc,submitted_at desc,proposal_id desc
  limit 1;
  if v_primary_proposal_id is distinct from v_proposal.proposal_id then
    return public.navision_backend_response(false,'superseded_pending_proposal',jsonb_build_object(
      'primary_proposal_id',v_primary_proposal_id,'status','pending'
    ));
  end if;
  if exists(
    select 1 from public.pdc_ai_intake_proposals q
    where q.status='pending' and q.action_type='board_activate_only'
      and q.stock_number=v_proposal.stock_number
      and (
        jsonb_typeof(q.observations->'conflicts') is distinct from 'array'
        or q.observations->'conflicts'<>'[]'::jsonb
        or (q.observations ? 'cancelled' and q.observations->'cancelled' is distinct from 'false'::jsonb)
        or (q.observations ? 'canceled' and q.observations->'canceled' is distinct from 'false'::jsonb)
        or (q.observations ? 'is_cancelled' and q.observations->'is_cancelled' is distinct from 'false'::jsonb)
        or (q.observations ? 'is_canceled' and q.observations->'is_canceled' is distinct from 'false'::jsonb)
        or concat_ws(' ',q.subject,q.summary)~*'\m(cancelled|canceled|cancellation)\M'
      )
  ) then
    return public.navision_backend_response(false,'same_stock_evidence_conflict',jsonb_build_object('status','pending'));
  end if;

  -- Match the established Navision store/revision lock order before identity locks.
  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  select revision into v_navision_revision
  from public.navision_backend_revision where singleton for update;
  select * into v_record
  from public.navision_backend_records
  where id=v_proposal.backend_record_id
  for update;
  if not found or not v_record.is_current or v_record.record_status<>'current' then
    return public.navision_backend_response(false,'record_changed');
  end if;
  if v_record.version<>v_proposal.backend_record_version
     and not coalesce(p_allow_current_record_refresh,false) then
    return public.navision_backend_response(false,'record_changed');
  end if;
  if public.navision_operational_location(v_record.normalized_data)='Completed' then
    return public.navision_backend_response(false,'protected_backend_lifecycle');
  end if;
  select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_stock_ids
  from public.navision_backend_records r
  where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
    and r.is_current and r.record_status='current'
    and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
    and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_proposal.stock_number;
  if cardinality(v_stock_ids)<>1 or v_stock_ids[1]<>v_proposal.backend_record_id
     or public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch')<>v_proposal.stock_number then
    return public.navision_backend_response(false,'identity_conflict');
  end if;

  lock table public.vehicles,public.vehicle_aliases in share row exclusive mode;
  perform pg_advisory_xact_lock(hashtextextended(
    'vehicle-master:stock_number:'||v_proposal.stock_number,0
  ));
  select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[])
  into v_operational_ids
  from (
    select v.id vehicle_id from public.vehicles v where v.stock_number_normalized=v_proposal.stock_number
    union all
    select a.vehicle_id from public.vehicle_aliases a
    where a.active and a.alias_type_normalized='stock_number'
      and a.normalized_alias_value=v_proposal.stock_number
  ) candidates;
  if cardinality(v_operational_ids)>1 then
    return public.navision_backend_response(false,'operational_identity_conflict');
  end if;
  v_vehicle_id:=case when cardinality(v_operational_ids)=1 then v_operational_ids[1] else null end;
  if v_vehicle_id is not null then
    select * into v_vehicle from public.vehicles where id=v_vehicle_id for update;
    v_reactivating_board_purge:=found
      and v_vehicle.board_purged_at is not null and v_vehicle.deleted_at is not null
      and v_vehicle.lifecycle_state='deleted' and not v_vehicle.visible_on_board
      and v_vehicle.rft_collected_at is null
      and upper(btrim(coalesce(v_vehicle.current_location,'')))<>'COMPLETED'
      and v_record.canonical_vehicle_id=v_vehicle.id;
    if not found or (not v_reactivating_board_purge and (
       v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active'
       or not v_vehicle.visible_on_board or v_vehicle.rft_collected_at is not null
       or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED')) then
      return public.navision_backend_response(false,'protected_existing_lifecycle');
    end if;
  end if;
  if exists(
    select 1 from public.vehicles v
    where v.deleted_at is not null
      and not (v_reactivating_board_purge and v.id=v_vehicle_id)
      and (v.id=v_record.canonical_vehicle_id or v.stock_number_normalized=v_proposal.stock_number)
  ) then
    return public.navision_backend_response(false,'protected_historical_identity');
  end if;

  v_vin:=case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin')
    then nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),'') else null end;
  if v_vin is not null then
    select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[])
    into v_vin_ids
    from (
      select v.id vehicle_id from public.vehicles v where v.vin_normalized=v_vin
      union all
      select a.vehicle_id from public.vehicle_aliases a
      where a.active and a.alias_type_normalized='vin' and a.normalized_alias_value=v_vin
    ) candidates;
    if exists(select 1 from unnest(v_vin_ids) id where v_vehicle_id is null or id<>v_vehicle_id) then
      return public.navision_backend_response(false,'vin_conflict_non_authoritative');
    end if;
  end if;
  if v_record.canonical_vehicle_id is not null
     and (v_vehicle_id is null or v_record.canonical_vehicle_id<>v_vehicle_id) then
    return public.navision_backend_response(false,'backend_canonical_identity_conflict');
  end if;
  if exists(
    select 1 from public.vehicles v
    where v.source_system_normalized='microsoft_navision'
      and v.source_record_id_normalized=public.normalize_vehicle_source_identifier(v_record.id::text)
      and (v_vehicle_id is null or v.id<>v_vehicle_id)
  ) then
    return public.navision_backend_response(false,'backend_source_identity_conflict');
  end if;

  select * into v_activation
  from public.navision_board_activations
  where backend_record_id=v_proposal.backend_record_id
  for update;
  v_activation_found:=found;
  if v_activation_found and not (
    v_reactivating_board_purge
    and v_activation.canonical_vehicle_id=v_vehicle_id
    and public.normalize_vehicle_stock_number(v_activation.activated_stock_number)=v_proposal.stock_number
  ) and (
    not v_activation.active or v_activation.completed_at is not null
    or public.normalize_vehicle_stock_number(v_activation.activated_stock_number)<>v_proposal.stock_number
    or (v_activation.canonical_vehicle_id is not null
        and (v_vehicle_id is null or v_activation.canonical_vehicle_id<>v_vehicle_id))
  ) then
    return public.navision_backend_response(false,'protected_or_conflicting_activation');
  end if;
  if exists(
    select 1 from public.navision_board_activations a
    where a.backend_record_id<>v_proposal.backend_record_id
      and public.normalize_vehicle_stock_number(a.activated_stock_number)=v_proposal.stock_number
  ) then
    return public.navision_backend_response(false,'activation_identity_conflict');
  end if;

  -- A board-visible operational vehicle means this proposal is stale evidence,
  -- not permission to rewrite that vehicle. A complete-board-purge tombstone is
  -- different: fresh exact authenticated evidence may restore that same canonical row.
  if v_vehicle_id is not null and not v_reactivating_board_purge then
    v_response:=public.navision_backend_response(true,'automatically_closed_existing',jsonb_build_object(
      'proposal_id',v_proposal.proposal_id,'stock_number',v_proposal.stock_number,
      'vehicle_id',v_vehicle_id,'vehicle_mutated',false,'board_activation_only',false,
      'authority_refreshed',v_record.version<>v_proposal.backend_record_version,
      'proposal_backend_record_version',v_proposal.backend_record_version,
      'current_backend_record_version',v_record.version,
      'authorization_basis','enrolled_monitor_and_live_server_identity','board_purge_reactivation',v_reactivating_board_purge
    ));
    update public.pdc_ai_intake_proposals set
      status='rejected',version=version+1,decided_by=p_actor_id,
      decided_by_email=v_actor_email,decided_at=clock_timestamp(),
      decision_reason='Automatically closed because this Stock is already active on the Control Board.',
      result=v_response
    where proposal_id=v_proposal.proposal_id;
    insert into public.pdc_ai_intake_history(
      proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
      stock_number,action_type,details
    ) values(
      v_proposal.proposal_id,'rejected',p_actor_id,v_actor_email,v_proposal.version+1,
      v_proposal.fingerprint,v_proposal.stock_number,v_proposal.action_type,
      jsonb_build_object('reason','already active on Control Board','result',v_response,
        'automatic',true,'authorization_basis','enrolled_monitor_and_live_server_identity','board_purge_reactivation',v_reactivating_board_purge)
    );
    v_transition_count:=1;
    for v_duplicate in
      select * from public.pdc_ai_intake_proposals
      where status='pending' and action_type='board_activate_only'
        and stock_number=v_proposal.stock_number and proposal_id<>v_proposal.proposal_id
      order by proposal_id for update
    loop
      v_duplicate_response:=public.navision_backend_response(true,'automatically_closed_duplicate',jsonb_build_object(
        'proposal_id',v_duplicate.proposal_id,'stock_number',v_duplicate.stock_number,
        'vehicle_id',v_vehicle_id,'vehicle_mutated',false,'board_activation_only',false,
        'primary_proposal_id',v_proposal.proposal_id
      ));
      update public.pdc_ai_intake_proposals set
        status='rejected',version=version+1,decided_by=p_actor_id,
        decided_by_email=v_actor_email,decided_at=clock_timestamp(),
        decision_reason='Automatically closed as duplicate evidence for a Stock already active on the Control Board.',
        result=v_duplicate_response
      where proposal_id=v_duplicate.proposal_id;
      insert into public.pdc_ai_intake_history(
        proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
        stock_number,action_type,details
      ) values(
        v_duplicate.proposal_id,'rejected',p_actor_id,v_actor_email,v_duplicate.version+1,
        v_duplicate.fingerprint,v_duplicate.stock_number,v_duplicate.action_type,
        jsonb_build_object('reason','duplicate evidence for active Stock','result',v_duplicate_response,
          'automatic',true,'primary_proposal_id',v_proposal.proposal_id)
      );
      v_transition_count:=v_transition_count+1;
      v_duplicate_count:=v_duplicate_count+1;
    end loop;
    update public.pdc_ai_intake_revision
    set revision=revision+v_transition_count,updated_at=clock_timestamp()
    where singleton;
    v_response:=jsonb_set(v_response,'{data,duplicate_count}',to_jsonb(v_duplicate_count),true);
    insert into public.pdc_ai_intake_auto_activation_receipts(
      proposal_id,policy_version,request_hash,source_hash,stock_number,actor_id,actor_email,response
    ) values(v_proposal.proposal_id,'135.1',v_request_hash,v_proposal.source_hash,v_proposal.stock_number,p_actor_id,v_actor_email,v_response);
    return v_response;
  end if;

  if v_reactivating_board_purge then
    begin
      update public.vehicles set
        lifecycle_state='active',visible_on_board=true,deleted_at=null,deleted_reason=null,
        board_purged_at=null,board_purge_reason=null,board_purged_by=null,
        version=version+1,updated_by=p_actor_id,updated_at=clock_timestamp()
      where id=v_vehicle_id;
      update public.navision_board_activations set
        active=true,activation_source='approved_email_build',
        activated_stock_number=v_record.normalized_data->>'batch',
        activated_at=clock_timestamp(),activated_by=p_actor_id,activated_by_email=v_actor_email,
        canonical_vehicle_id=v_vehicle_id,completed_at=null,completion_reason=null,
        completed_by=null,completed_by_email=null,updated_at=clock_timestamp()
      where backend_record_id=v_record.id;
      perform public.reconcile_navision_operational_record(v_record.id,p_actor_id,v_actor_email);
      select * into v_vehicle from public.vehicles where id=v_vehicle_id for update;
      if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active'
         or not v_vehicle.visible_on_board or v_vehicle.board_purged_at is not null
         or public.normalize_vehicle_stock_number(v_vehicle.stock_number)<>v_proposal.stock_number then
        raise exception using errcode='P0001',message='PDC_AI_INTAKE_158_REACTIVATION_POSTCONDITION_FAILED';
      end if;
      v_next_navision_revision:=v_navision_revision+1;
      update public.navision_backend_revision
      set revision=v_next_navision_revision,updated_at=clock_timestamp()
      where singleton;
      insert into public.navision_backend_audit(action,backend_record_id,revision,evidence,actor_id,actor_email)
      values('board_activate',v_record.id,v_next_navision_revision,
        jsonb_build_object('activation_source','approved_email_build','contract','pdc_ai_intake_auto_158',
          'proposal_id',v_proposal.proposal_id,'source_hash',v_proposal.source_hash,
          'evidence_hash',v_proposal.evidence_hash,'stock_number',v_proposal.stock_number,
          'board_purge_reactivation',true,'canonical_vehicle_id',v_vehicle_id,
          'automated',true,'stock_only_authority',true,'vin_identity_authority',false,
          'booking_created',false,'work_mutated',false,'parts_mutated',false),
        p_actor_id,v_actor_email);
    exception when others then
      get stacked diagnostics v_mutation_error=message_text;
      return public.navision_backend_response(false,'automatic_reactivation_failed',jsonb_build_object(
        'proposal_id',v_proposal.proposal_id,'stock_number',v_proposal.stock_number,'failure',v_mutation_error));
    end;
  else
    if v_activation_found then
      return public.navision_backend_response(false,'activation_without_operational_identity');
    end if;

  -- Mutation is a subtransaction: a failed reconcile/postcondition rolls back
  -- activation, operational vehicle, revision and audit while retaining the proposal.
  begin
    insert into public.navision_board_activations(
      backend_record_id,activation_source,activated_stock_number,
      activated_by,activated_by_email,active
    ) values(
      v_record.id,'approved_email_build',v_record.normalized_data->>'batch',
      p_actor_id,v_actor_email,true
    );
    v_next_navision_revision:=v_navision_revision+1;
    update public.navision_backend_revision
    set revision=v_next_navision_revision,updated_at=clock_timestamp()
    where singleton;
    insert into public.navision_backend_audit(
      action,backend_record_id,revision,evidence,actor_id,actor_email
    ) values(
      'board_activate',v_record.id,v_next_navision_revision,
      jsonb_build_object(
        'activation_source','approved_email_build','contract','pdc_ai_intake_auto_135',
        'proposal_id',v_proposal.proposal_id,'source_hash',v_proposal.source_hash,
        'evidence_hash',v_proposal.evidence_hash,'stock_number',v_proposal.stock_number,
        'authority_refreshed',v_record.version<>v_proposal.backend_record_version,
        'proposal_backend_record_version',v_proposal.backend_record_version,
        'current_backend_record_version',v_record.version,
        'automated',true,'stock_only_authority',true,'vin_identity_authority',false,
        'booking_created',false,'work_mutated',false,'parts_mutated',false
      ),p_actor_id,v_actor_email
    );
    select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[])
    into v_operational_ids
    from (
      select v.id vehicle_id from public.vehicles v
      where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
        and v.stock_number_normalized=v_proposal.stock_number
      union all
      select a.vehicle_id from public.vehicle_aliases a
      join public.vehicles v on v.id=a.vehicle_id
      where a.active and a.alias_type_normalized='stock_number'
        and a.normalized_alias_value=v_proposal.stock_number
        and v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    ) candidates;
    if cardinality(v_operational_ids)<>1 then
      raise exception using errcode='P0001',message='PDC_AI_INTAKE_135_POSTCONDITION_FAILED';
    end if;
    v_vehicle_id:=v_operational_ids[1];
  exception when others then
    get stacked diagnostics v_mutation_error=message_text;
    return public.navision_backend_response(false,'automatic_activation_failed',jsonb_build_object(
      'proposal_id',v_proposal.proposal_id,'stock_number',v_proposal.stock_number,
      'failure',v_mutation_error
    ));
  end;
  end if;

  v_response:=public.navision_backend_response(true,'automatically_applied',jsonb_build_object(
    'proposal_id',v_proposal.proposal_id,'stock_number',v_proposal.stock_number,
    'backend_record_id',v_record.id,'vehicle_id',v_vehicle_id,
    'navision_revision',v_next_navision_revision,'vehicle_mutated',true,
    'authority_refreshed',v_record.version<>v_proposal.backend_record_version,
    'proposal_backend_record_version',v_proposal.backend_record_version,
    'current_backend_record_version',v_record.version,
    'board_activation_only',true,'booking_created',false,'work_mutated',false,
    'parts_mutated',false,'authorization_basis','enrolled_monitor_and_live_server_identity','board_purge_reactivation',v_reactivating_board_purge
  ));
  update public.pdc_ai_intake_proposals set
    status='applied',version=version+1,decided_by=p_actor_id,
    decided_by_email=v_actor_email,decided_at=clock_timestamp(),
    decision_reason='Automatically activated from authenticated email and unique current Navision Stock authority.',
    result=v_response
  where proposal_id=v_proposal.proposal_id;
  insert into public.pdc_ai_intake_history(
    proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
    stock_number,action_type,details
  ) values(
    v_proposal.proposal_id,'applied',p_actor_id,v_actor_email,v_proposal.version+1,
    v_proposal.fingerprint,v_proposal.stock_number,v_proposal.action_type,
    jsonb_build_object('reason','automatic exact-Stock activation','result',v_response,
      'automatic',true,'email_evidence_authoritative',false,
      'authorization_basis','enrolled_monitor_and_live_server_identity','board_purge_reactivation',v_reactivating_board_purge)
  );
  v_transition_count:=1;
  for v_duplicate in
    select * from public.pdc_ai_intake_proposals
    where status='pending' and action_type='board_activate_only'
      and stock_number=v_proposal.stock_number and proposal_id<>v_proposal.proposal_id
    order by proposal_id for update
  loop
    v_duplicate_response:=public.navision_backend_response(true,'automatically_closed_duplicate',jsonb_build_object(
      'proposal_id',v_duplicate.proposal_id,'stock_number',v_duplicate.stock_number,
      'vehicle_id',v_vehicle_id,'vehicle_mutated',false,'board_activation_only',false,
      'primary_proposal_id',v_proposal.proposal_id
    ));
    update public.pdc_ai_intake_proposals set
      status='rejected',version=version+1,decided_by=p_actor_id,
      decided_by_email=v_actor_email,decided_at=clock_timestamp(),
      decision_reason='Automatically closed as duplicate evidence after this Stock was activated.',
      result=v_duplicate_response
    where proposal_id=v_duplicate.proposal_id;
    insert into public.pdc_ai_intake_history(
      proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,
      stock_number,action_type,details
    ) values(
      v_duplicate.proposal_id,'rejected',p_actor_id,v_actor_email,v_duplicate.version+1,
      v_duplicate.fingerprint,v_duplicate.stock_number,v_duplicate.action_type,
      jsonb_build_object('reason','duplicate evidence after automatic activation','result',v_duplicate_response,
        'automatic',true,'primary_proposal_id',v_proposal.proposal_id)
    );
    v_transition_count:=v_transition_count+1;
    v_duplicate_count:=v_duplicate_count+1;
  end loop;
  update public.pdc_ai_intake_revision
  set revision=revision+v_transition_count,updated_at=clock_timestamp()
  where singleton;
  v_response:=jsonb_set(v_response,'{data,duplicate_count}',to_jsonb(v_duplicate_count),true);
  update public.pdc_ai_intake_proposals set result=v_response
  where proposal_id=v_proposal.proposal_id;
  insert into public.pdc_ai_intake_auto_activation_receipts(
    proposal_id,policy_version,request_hash,source_hash,stock_number,actor_id,actor_email,response
  ) values(v_proposal.proposal_id,'135.1',v_request_hash,v_proposal.source_hash,v_proposal.stock_number,p_actor_id,v_actor_email,v_response);
  return v_response;
end
$function$;

revoke all on function public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb) to authenticated;
comment on function public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb) is
 'Staging v158 enrolled Viewer/Importer Monitor observation contract; exact current Stock may reactivate only its same canonical complete-Board-purge tombstone.';
revoke all on function public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean) from public,anon,authenticated,service_role;
comment on function public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean) is
 'Staging v158: verified exact-Stock auto-activation, including same-row complete-Board-purge tombstone reactivation; ordinary deleted/completed identities remain protected.';
insert into supabase_migrations.schema_migrations(version,name,statements) values('158','pmb_email_board_purge_reactivation',array[
 'allow fresh exact authenticated email evidence to reactivate only its same canonical complete-board-purge tombstone',
 'enroll the active Monitor Importer in observation submission and automatic activation',
 'reactivate the existing canonical activation and vehicle atomically before operation-hour receipt import',
 'retain duplicate identity, completed lifecycle, source/proposal, revision and replay protections']);
commit;
