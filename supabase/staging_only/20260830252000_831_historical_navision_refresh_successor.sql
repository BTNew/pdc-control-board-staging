-- STAGING ONLY 831: use Navision reconciliation wrapper with linked refresh.
-- pre171 creates the deterministic vehicle but leaves fresh detail-location
-- fields absent. Existing pre700 invokes that primitive plus the approved 481
-- linked-vehicle refresh, satisfying the unchanged parity trigger.
BEGIN;
SET LOCAL lock_timeout='15s'; SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-831-navision-refresh',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v text;
BEGIN
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830249000,828_historical_replay_order_successor)' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '1dfa773a939bd4a580b8ff646c94f661cb147d3c569de0081b4dbafa1f13e7e4' OR position('reconcile_navision_operational_record_pre171(v_record.id,p_actor_id,v_actor_email)' in v)=0 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_writer_authorizations_809 WHERE active AND expires_at>clock_timestamp())<>5 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_778_receipts)<>4 OR (SELECT coalesce(array_agg(provider_uid ORDER BY provider_uid),'{}'::text[]) FROM public.pdc_historical_reconciliation_778_receipts) IS DISTINCT FROM ARRAY['1:133','1:137','1:168','1:172']::text[] OR (SELECT count(*) FROM public.pdc_historical_provider_observations_778)<>20 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0 THEN RAISE EXCEPTION 'PDC_831_CURRENT_HEAD_OR_NAVISION_PRESTATE_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.pdc_auto_apply_ai_intake_activation_internal_pre310(p_proposal_id uuid, p_actor_id uuid, p_actor_email text, p_allow_current_record_refresh boolean DEFAULT false)
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
  v_historical_context jsonb:=coalesce(nullif(current_setting('pdc.historical_context',true),''),'{}')::jsonb;
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
     or (v_proposal.source_received_at<clock_timestamp()-interval '30 days' and not coalesce((v_historical_context->>'canonical_source_uid'=v_proposal.source_uid and v_historical_context->>'actor_id'=p_actor_id::text and public.pdc_historical_writer_authorized_773(v_historical_context->>'parent_source_hash',v_historical_context->>'provider_uid',lower(btrim(coalesce(v_historical_context->>'sender_email',''))),v_historical_context->'authentication',public.normalize_vehicle_stock_number(v_historical_context->>'stock_number'))),false)) then
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
      and not (
        v_historical_context->>'canonical_source_uid'=v_proposal.source_uid
        and v_historical_context->>'actor_id'=p_actor_id::text
        and v_historical_context->>'parent_source_hash'=q.source_hash
        and v_historical_context->>'provider_uid'=q.source_uid
        and public.pdc_historical_writer_authorized_773(v_historical_context->>'parent_source_hash',v_historical_context->>'provider_uid',lower(btrim(coalesce(v_historical_context->>'sender_email',''))),v_historical_context->'authentication',public.normalize_vehicle_stock_number(v_historical_context->>'stock_number'))
      )
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
      and v_record.canonical_vehicle_id=v_vehicle.id
      and v_proposal.source_received_at>v_vehicle.board_purged_at;
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

  v_vin:=public.pdc_navision_effective_vin_471(v_record.normalized_data);
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
  ) and not public.uid514_exact_canonical_import_compatibility_307(
    v_proposal.stock_number,v_proposal.observations->'vehicle'->'vins'->>0,
    v_proposal.observations->'vehicle'->>'job_card_number',v_proposal.source_uid,
    v_proposal.source_hash,v_proposal.evidence_hash
  ) then
    return public.navision_backend_response(false,'activation_identity_conflict');
  end if;

  -- A board-visible operational vehicle means this proposal is stale evidence,
  -- not permission to rewrite that vehicle. The private UID514 gate accepts exactly one
  -- audited reinstated identity and never activates or mutates that vehicle at this stage.
  if v_vehicle_id is not null and public.uid514_exact_canonical_import_compatibility_307(
    v_proposal.stock_number,v_proposal.observations->'vehicle'->'vins'->>0,
    v_proposal.observations->'vehicle'->>'job_card_number',v_proposal.source_uid,
    v_proposal.source_hash,v_proposal.evidence_hash
  ) then
    v_response:=public.navision_backend_response(true,'uid514_exact_existing_identity_accepted',jsonb_build_object(
      'proposal_id',v_proposal.proposal_id,'stock_number',v_proposal.stock_number,'vehicle_id',v_vehicle_id,
      'vehicle_mutated',false,'board_activation_only',false,'reinstatement_receipt_required',true,
      'historical_job_card_preserved','J139125093','incoming_job_card','J139125482'));
    update public.pdc_ai_intake_proposals set status='applied',version=version+1,decided_by=p_actor_id,
      decided_by_email=v_actor_email,decided_at=clock_timestamp(),
      decision_reason='Exact owner-authorized UID514 canonical import compatibility gate.',result=v_response
    where proposal_id=v_proposal.proposal_id;
    insert into public.pdc_ai_intake_history(proposal_id,event_type,actor_id,actor_email,proposal_version,fingerprint,stock_number,action_type,details)
    values(v_proposal.proposal_id,'applied',p_actor_id,v_actor_email,v_proposal.version+1,v_proposal.fingerprint,
      v_proposal.stock_number,v_proposal.action_type,jsonb_build_object('contract','uid514_exact_canonical_import_compatibility_307',
      'vehicle_mutated',false,'historical_job_card_preserved','J139125093','incoming_job_card','J139125482','result',v_response));
    update public.pdc_ai_intake_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
    insert into public.pdc_ai_intake_auto_activation_receipts(proposal_id,policy_version,request_hash,source_hash,stock_number,actor_id,actor_email,response)
    values(v_proposal.proposal_id,'135.1',v_request_hash,v_proposal.source_hash,v_proposal.stock_number,p_actor_id,v_actor_email,v_response);
    return v_response;
  end if;
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
    perform public.reconcile_navision_operational_record_pre_700(v_record.id,p_actor_id,v_actor_email);
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
$function$
;
REVOKE ALL ON FUNCTION public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean) TO postgres;
DO $post$
DECLARE v text; owner_name text; secdef boolean; acl text;
BEGIN
 SELECT p.prosrc,p.proowner::regrole::text,p.prosecdef,p.proacl::text INTO v,owner_name,secdef,acl FROM pg_proc p WHERE p.oid='public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'be0a30b3dce60f7c2259dbac02a8b74fbd81c374f1d1a6e94d24eb1d6076251b' OR owner_name<>'postgres' OR NOT secdef OR acl<>'{postgres=X/postgres}' THEN RAISE EXCEPTION 'PDC_831_NAVISION_REFRESH_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830252000','831_historical_navision_refresh_successor',ARRAY['replace only the historical pre171 call with the existing pre700 Navision reconciliation wrapper and 481 linked refresh','preserve unchanged PDC_NAVISION parity enforcement and atomic rollback','preserve exact identity evidence auth RLS grants idempotency ten conflicts zero mailbox and no outbound','no historical Apply outbox mailbox task or Production operation']);
COMMIT;
