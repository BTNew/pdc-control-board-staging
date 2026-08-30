-- STAGING ONLY 816: bind both historical importer fallbacks to intake sender.
-- 815 was not applied because its postcondition was unreliable during apply.
-- Reapply the same exact one-site stale sender fix from the unchanged 814
-- importer, with normalized occurrence postconditions. Normal active-mailbox
-- behavior, exact historical evidence, atomic rollback, RLS/grants and all
-- conflict/isolation controls remain unchanged.
BEGIN;
SET LOCAL lock_timeout='15s'; SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-816-historical-importer-sender',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v text;
BEGIN
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830235000,814_historical_enqueue_status_drift_successor)' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '6b72a9d5c169b68247d8c27df2069273c05503eb87ec83123ddbc6bf15e9e528' OR (SELECT count(*) FROM public.pdc_historical_reconciliation_writer_authorizations_809 WHERE active AND expires_at>clock_timestamp())<>5 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_778_receipts)<>0 OR (SELECT count(*) FROM public.pdc_historical_provider_observations_778)<>0 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0 THEN RAISE EXCEPTION 'PDC_816_CURRENT_HEAD_OR_IMPORTER_PRESTATE_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.import_pdc_jobcard_attachment_canonical(p_intake_id uuid, p_attachment_id uuid, p_expected_parent_hash text, p_expected_attachment_hash text, p_authentication jsonb, p_email_vehicle jsonb, p_required_work jsonb, p_operation_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '180s'
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_parent_hash text:=lower(btrim(coalesce(p_expected_parent_hash,'')));
  v_canonical_source_hash text;
  v_attachment_hash text:=lower(btrim(coalesce(p_expected_attachment_hash,'')));
  v_auth jsonb:=coalesce(p_authentication,'null'::jsonb);
  v_email_vehicle jsonb:=coalesce(p_email_vehicle,'null'::jsonb);
  v_required_work jsonb:=coalesce(p_required_work,'null'::jsonb);
  v_input_lines jsonb:=coalesce(p_operation_lines,'null'::jsonb);
  v_intake public.ai_email_intake%rowtype;
  v_attachment public.ai_email_attachments%rowtype;
  v_mailbox public.monitored_mailboxes%rowtype;
  v_provider_observation public.pdc_provider_email_observations%rowtype;
  v_existing public.pdc_jobcard_attachment_import_receipts%rowtype;
  v_import_receipt public.pdc_authenticated_email_import_receipts%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_backend public.navision_backend_records%rowtype;
  v_source_uid text;
  v_idempotency_key text;
  v_sender text;
  v_subject text;
  v_stock text;
  v_job_card text;
  v_canonical_lines jsonb;
  v_observations jsonb;
  v_requested_digest text;
  v_operation_digest text;
  v_operation_count integer;
  v_hours_sum numeric(10,2);
  v_line_ids uuid[];
  v_submit jsonb;
  v_vehicle_result jsonb;
  v_hours_result jsonb;
  v_failure jsonb;
  v_proposal_id uuid;
  v_receipt_id uuid:=gen_random_uuid();
  v_response jsonb;
  v_item jsonb;
  v_line public.pdc_authenticated_email_operation_lines%rowtype;
  v_nested_marker boolean:=false;
begin
  if not public.pdc_monitor_staging_guard() or v_actor is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_user_roles r
   where r.auth_user_id=v_actor and lower(r.email)=v_actor_email
     and r.role in('viewer','importer') and r.active and r.account_status='approved' for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;

  if p_intake_id is null or p_attachment_id is null
     or v_parent_hash!~'^[a-f0-9]{64}$' or v_attachment_hash!~'^[a-f0-9]{64}$'
     or jsonb_typeof(v_auth) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_auth) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not(v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb)
     or jsonb_typeof(v_email_vehicle) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_email_vehicle) k)
        is distinct from array['cancelled','conflicts','customer_name','eta_to_kewdale','job_card_number','registration','stock_numbers','toyota_order_number','vehicle_description','vins']::text[]
     or jsonb_typeof(v_required_work) is distinct from 'array'
     or jsonb_array_length(v_required_work) not between 1 and 10
     or exists(select 1 from jsonb_array_elements(v_required_work) x where jsonb_typeof(x)<>'string' or x#>>'{}' not in
       ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS','sublet'))
     or jsonb_array_length(v_required_work)<>(select count(distinct x) from jsonb_array_elements_text(v_required_work) x)
     or jsonb_typeof(v_input_lines) is distinct from 'array'
     or jsonb_array_length(v_input_lines) not between 1 and 50 then
    return public.navision_backend_response(false,'invalid_input');
  end if;
  if exists(
    select 1 from jsonb_array_elements(v_input_lines) with ordinality x(line,ordinality)
    where jsonb_typeof(line)<>'object'
       or (select array_agg(k order by k) from jsonb_object_keys(line) k)
          is distinct from array['description','estimated_hours','operation_no','source_row_no','work_key']::text[]
       or jsonb_typeof(line->'source_row_no')<>'number'
       or coalesce(line->>'source_row_no','')!~'^[1-9][0-9]{0,8}$'
       or line->>'operation_no' !~ '^OP[1-9][0-9]{0,2}$'
       or line->>'work_key' not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS','sublet','owner_supplied_document')
       or length(coalesce(line->>'description','')) not between 1 and 180
       or line->>'description' is distinct from btrim(line->>'description')
       or line->>'description'~'[[:cntrl:]]'
       or jsonb_typeof(line->'estimated_hours') not in ('number','null')
       or (jsonb_typeof(line->'estimated_hours')='number' and ((line->>'estimated_hours')::numeric<0 or (line->>'estimated_hours')::numeric>999.99 or mod((line->>'estimated_hours')::numeric,0.01)<>0))
  ) or jsonb_array_length(v_input_lines)<>(select count(distinct (x->>'source_row_no')::integer) from jsonb_array_elements(v_input_lines) x)
    or jsonb_array_length(v_input_lines)<>(select count(distinct x->>'operation_no') from jsonb_array_elements(v_input_lines) x)
    or exists (select 1 from jsonb_array_elements(v_input_lines) x
       where x->>'work_key'<>'owner_supplied_document'
         and x->>'work_key' not in (select value from jsonb_array_elements_text(v_required_work))) then
    return public.navision_backend_response(false,'invalid_operation_lines_or_required_work_set');
  end if;

  select * into v_intake from public.ai_email_intake where id=p_intake_id for update;
  if not found then return public.navision_backend_response(false,'intake_not_found'); end if;
  select * into v_attachment from public.ai_email_attachments
   where id=p_attachment_id and intake_id=p_intake_id for share;
  if not found then return public.navision_backend_response(false,'attachment_not_found'); end if;
  select * into v_provider_observation from public.pdc_provider_email_observations
   where intake_id=p_intake_id and attachment_id=p_attachment_id for share;
  if (not found
     or v_provider_observation.parent_source_hash<>v_parent_hash
     or v_provider_observation.attachment_source_hash<>v_attachment_hash
     or v_provider_observation.provider_authserv_id<>'mx.google.com'
     or v_provider_observation.authentication is distinct from v_auth)
     and not exists(select 1 from public.pdc_historical_provider_observations_778 h
       where h.intake_id=p_intake_id and h.attachment_id=p_attachment_id
         and h.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
         and h.provider_uid=coalesce(v_intake.provider_uid,'') and h.parent_source_hash=v_parent_hash
         and h.attachment_source_hash=v_attachment_hash and h.sender_email=lower(coalesce(v_intake.sender_email,''))
         and h.actor_id=v_actor and h.actor_email=v_actor_email and h.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
         and public.pdc_historical_writer_authorized_773(v_parent_hash,h.provider_uid,v_sender,v_auth,v_email_vehicle->'stock_numbers'->>0)) then
    return public.navision_backend_response(false,'provider_observation_required_or_mismatch');
  end if;
  select * into v_mailbox from public.monitored_mailboxes
   where id=coalesce(v_intake.monitored_mailbox_id,'12fe383d-5c1e-5801-96e4-f67cf3e3bb57'::uuid) for share;
  if not found
     or lower(btrim(coalesce(v_intake.recipient_mailbox,'')))<>lower(btrim(v_mailbox.mailbox_address))
     or (v_intake.monitored_mailbox_id is not null and not v_mailbox.active)
     or (v_intake.monitored_mailbox_id is null and (
       not public.pdc_monitor_authenticated_active_scope_673(NULL)
       or not exists(select 1 from public.pdc_historical_provider_observations_778 h
          where h.intake_id=p_intake_id and h.attachment_id=p_attachment_id
            and h.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
            and h.provider_uid=coalesce(v_intake.provider_uid,'')
            and h.parent_source_hash=v_parent_hash and h.attachment_source_hash=v_attachment_hash
            and h.actor_id=v_actor and h.actor_email=v_actor_email
            and h.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
            and h.sender_email=lower(coalesce(v_intake.sender_email,''))
            and public.pdc_historical_writer_authorized_773(v_parent_hash,h.provider_uid,lower(coalesce(v_intake.sender_email,'')),v_auth,v_email_vehicle->'stock_numbers'->>0)))) then
    return public.navision_backend_response(false,'monitored_mailbox_binding_mismatch');
  end if;
  if (select count(*) from public.ai_email_attachments a
      where a.id=p_attachment_id and a.intake_id=p_intake_id and lower(a.source_hash)=v_attachment_hash)<>1
     or lower(coalesce(v_intake.source_hash,''))<>v_parent_hash
     or lower(coalesce(v_attachment.source_hash,''))<>v_attachment_hash
     or v_attachment.size_bytes is null or v_attachment.size_bytes not between 1 and 10485760
     or lower(coalesce(v_attachment.content_type,'')) not in (
       'application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
       'application/vnd.ms-excel','text/csv','text/plain') then
    return public.navision_backend_response(false,'attachment_identity_or_type_mismatch');
  end if;
  v_sender:=lower(btrim(coalesce(v_intake.sender_email,'')));
  v_subject:=btrim(coalesce(v_intake.subject,''));
  if v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
     or (not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active
       and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex'))
       and not public.pdc_historical_writer_authorized_773(v_parent_hash,coalesce(v_intake.provider_uid,''),v_sender,v_auth,v_email_vehicle->'stock_numbers'->>0))
     or v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2)
     or length(v_subject) not between 1 and 300 then
    return public.navision_backend_response(false,'sender_authentication_or_subject_invalid');
  end if;
  v_canonical_source_hash:=public.pdc_233_length_prefixed_sha256(array['pdc-attachment-canonical-source','233.1',p_intake_id::text,p_attachment_id::text,v_parent_hash,v_attachment_hash]);
  v_source_uid:='pdc-jc-159:'||encode(extensions.digest(convert_to(
    p_intake_id::text||':'||p_attachment_id::text||':'||v_parent_hash||':'||v_attachment_hash,'UTF8'),'sha256'),'hex');
  v_idempotency_key:='pdc-email-import-'||encode(extensions.digest(convert_to(p_intake_id::text||':'||p_attachment_id::text,'UTF8'),'sha256'),'hex');
  select jsonb_agg(jsonb_build_object(
    'operation_no',line->>'operation_no','work_key',line->>'work_key','description',line->>'description',
    'estimated_hours',case when jsonb_typeof(line->'estimated_hours')='number' then (line->>'estimated_hours')::numeric else null end,'estimated_hours_source',case when jsonb_typeof(line->'estimated_hours')='number' then 'job_card' else 'owner_supplied_document_unknown' end) order by ordinality)
  into v_canonical_lines from jsonb_array_elements(v_input_lines) with ordinality x(line,ordinality);
  v_operation_count:=jsonb_array_length(v_canonical_lines);
  select sum((x->>'estimated_hours')::numeric) into v_hours_sum from jsonb_array_elements(v_canonical_lines) x;
  v_requested_digest:=encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version','159.1','actor_id',v_actor,'intake_id',p_intake_id,'attachment_id',p_attachment_id,
    'parent_source_hash',v_parent_hash,'attachment_source_hash',v_attachment_hash,'source_uid',v_source_uid,
    'authentication',v_auth,'email_vehicle',v_email_vehicle,'required_work',v_required_work,
    'operation_lines',v_input_lines)::text,'UTF8'),'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended('pdc-jobcard-attachment-159:'||p_intake_id::text||':'||p_attachment_id::text,0));
  select * into v_existing from public.pdc_jobcard_attachment_import_receipts
   where actor_id=v_actor and intake_id=p_intake_id and attachment_id=p_attachment_id;
  if found then
    if v_existing.requested_payload_sha256<>v_requested_digest
       or v_existing.parent_source_hash<>v_parent_hash
       or v_existing.attachment_source_hash<>v_attachment_hash then
      return public.navision_backend_response(false,'attachment_replay_conflict');
    end if;
    -- Exact replay returns verified stable readback before any delegated call or DML.
    return public.read_pdc_jobcard_attachment_import_receipt(v_existing.receipt_id);
  end if;

  if v_intake.duplicate_of is not null or v_intake.status in ('duplicate_detected','failed','ignored','vehicle_created')
     or (v_intake.status='vehicle_updated' and v_intake.processing_result->>'uid478_attachment_atomic_contract' is distinct from '233.1'
         and not public.pdc_historical_writer_authorized_773(v_parent_hash,coalesce(v_intake.provider_uid,''),v_sender,v_auth,v_email_vehicle->'stock_numbers'->>0))
     or v_intake.received_at is null or v_intake.received_at>clock_timestamp()+interval '5 minutes'
     or v_intake.received_at<clock_timestamp()-interval '30 days' then
    return public.navision_backend_response(false,'intake_duplicate_consumed_or_stale');
  end if;
  if jsonb_typeof(v_email_vehicle->'stock_numbers')<>'array' or jsonb_array_length(v_email_vehicle->'stock_numbers')<>1
     or jsonb_typeof(v_email_vehicle->'vins')<>'array' or jsonb_array_length(v_email_vehicle->'vins')>1
     or jsonb_typeof(v_email_vehicle->'conflicts')<>'array' or v_email_vehicle->'conflicts'<>'[]'::jsonb
     or v_email_vehicle->'cancelled' is distinct from 'false'::jsonb then
    return public.navision_backend_response(false,'email_vehicle_not_exact_or_conflicted');
  end if;
  v_stock:=public.normalize_vehicle_stock_number(v_email_vehicle->'stock_numbers'->>0);
  v_job_card:=btrim(coalesce(v_email_vehicle->>'job_card_number',''));
  if not public.is_real_vehicle_stock_number(v_stock) or length(v_job_card) not between 1 and 80 or v_job_card~'[[:cntrl:]]' then
    return public.navision_backend_response(false,'invalid_vehicle_identity');
  end if;
  v_observations:=jsonb_build_object(
    'attachment_manifest',jsonb_build_array(jsonb_build_object(
      'attachment_id',v_attachment.id,'source_hash',v_attachment_hash,'file_name',v_attachment.file_name,
      'size_bytes',v_attachment.size_bytes,'content_type',v_attachment.content_type)),
    'authenticated',true,'conflicts','[]'::jsonb,'customer',v_email_vehicle->'customer_name',
    'eta_to_kewdale',v_email_vehicle->'eta_to_kewdale','location_evidence','retained_ai_email_attachment',
    'match_outcome','resolved_navision_exact','match_reason','exact retained job-card attachment adapter',
    'required_work',v_required_work,'sender_domain',split_part(v_sender,'@',2),'vehicle',v_email_vehicle);

  -- Every nested mutation is a PL/pgSQL subtransaction. Any false delegate result
  -- is converted to an exception, rolling back proposal, activation, vehicle/work,
  -- operation lines, receipts, audit and intake update as one atomic unit.
  begin
    v_nested_marker:=true;
    v_submit:=public.submit_pdc_ai_intake_observation(
      v_canonical_source_hash,v_attachment_hash,v_source_uid,v_sender,v_auth,v_intake.received_at,
      v_subject,'board_activate_only',v_stock,'Canonical retained job-card attachment import',v_observations);
    if not coalesce((v_submit->>'ok')::boolean,false)
       or not coalesce((v_submit->'data'->'auto_activation'->>'ok')::boolean,false) then
      v_failure:=case when not coalesce((v_submit->>'ok')::boolean,false)
        then coalesce(v_submit,public.navision_backend_response(false,'observation_failed'))
        else coalesce(v_submit->'data'->'auto_activation',public.navision_backend_response(false,'auto_activation_failed')) end;
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;
    v_proposal_id:=nullif(v_submit->'data'->>'proposal_id','')::uuid;
    if v_proposal_id is null or not exists(select 1 from public.pdc_ai_intake_proposals p where p.proposal_id=v_proposal_id and p.status in ('applied','rejected') and (p.status in ('applied') or (p.result->>'code'='automatically_closed_existing' and p.submitted_by=v_actor and exists(select 1 from public.pdc_generic_current_navision_enrichment_receipts_312 g join public.navision_backend_records b on b.id=g.backend_record_id join public.vehicles v on v.id=g.vehicle_id where g.proposal_id=p.proposal_id and g.policy_version='312.1' and g.source_hash=p.source_hash and g.source_uid=p.source_uid and g.backend_record_id=p.backend_record_id and g.actor_id=p.submitted_by and g.actor_email=v_actor_email and g.response is not distinct from p.result and b.id=p.backend_record_id and b.canonical_vehicle_id=g.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null and v.visible_on_board and v.board_purged_at is null)))) then
      v_failure:=public.navision_backend_response(false,'activation_not_applied');
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;

    v_vehicle_result:=public.import_pdc_authenticated_vehicle_email(
      v_idempotency_key,v_canonical_source_hash,v_attachment_hash,v_source_uid,v_sender,v_auth,
      v_intake.received_at,v_subject,v_email_vehicle,v_required_work);
    if not coalesce((v_vehicle_result->>'ok')::boolean,false) then
      v_failure:=v_vehicle_result;
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;

    v_hours_result:=public.import_pdc_authenticated_email_operations_with_hours(
      v_canonical_source_hash,v_source_uid,v_canonical_lines);
    if not coalesce((v_hours_result->>'ok')::boolean,false) then
      v_failure:=v_hours_result;
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;

    select * into v_import_receipt from public.pdc_authenticated_email_import_receipts
     where actor_id=v_actor and source_hash=v_canonical_source_hash and source_uid=v_source_uid for share;
    if not found then
      v_failure:=public.navision_backend_response(false,'canonical_import_receipt_missing');
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;
    select * into v_vehicle from public.vehicles where id=v_import_receipt.vehicle_id for share;
    select * into v_backend from public.navision_backend_records where id=v_import_receipt.backend_record_id for share;
    if not found or v_vehicle.id is null or v_backend.id is null
       or v_import_receipt.backend_record_version is distinct from v_backend.version
       or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active'
       or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED'
       or upper(btrim(coalesce(v_vehicle.job_card_number,'')))<>upper(v_job_card) then
      v_failure:=public.navision_backend_response(false,'canonical_identity_or_lifecycle_postcondition_failed');
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;
    select coalesce(array_agg(ol.operation_line_id order by (x.line->>'source_row_no')::integer),'{}'::uuid[]),
      coalesce(jsonb_agg(jsonb_build_object(
        'source_row_no',(x.line->>'source_row_no')::integer,'operation_no',ol.operation_no,
        'operation_line_id',ol.operation_line_id,'work_key',ol.work_key,'description',ol.description,
        'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source
      ) order by (x.line->>'source_row_no')::integer),'[]'::jsonb)
    into v_line_ids,v_canonical_lines
    from jsonb_array_elements(v_input_lines) x(line)
    join public.pdc_authenticated_email_operation_lines ol
      on ol.source_hash=v_canonical_source_hash and ol.source_uid=v_source_uid and ol.vehicle_id=v_vehicle.id
     and ol.operation_no=x.line->>'operation_no' and ol.work_key=x.line->>'work_key'
     and ol.description=x.line->>'description' and ol.estimated_hours is not distinct from case when jsonb_typeof(x.line->'estimated_hours')='number' then (x.line->>'estimated_hours')::numeric else null end
     and ol.estimated_hours_source=case when jsonb_typeof(x.line->'estimated_hours')='number' then 'job_card' else 'owner_supplied_document_unknown' end;
    if cardinality(v_line_ids)<>v_operation_count
       or (select count(*) from public.pdc_authenticated_email_operation_lines where source_hash=v_canonical_source_hash)<>v_operation_count then
      v_failure:=public.navision_backend_response(false,'canonical_operation_cardinality_mismatch');
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;
    v_operation_digest:=encode(extensions.digest(convert_to(v_canonical_lines::text,'UTF8'),'sha256'),'hex');
    v_response:=jsonb_build_object(
      'observation',v_submit,'vehicle_import',v_vehicle_result,'operation_import',v_hours_result,
      'booking_created',false,'completion_created',false,'location_scheduled',false);
    insert into public.pdc_jobcard_attachment_import_receipts(
      receipt_id,contract_version,actor_id,actor_email,intake_id,attachment_id,parent_source_hash,
      attachment_source_hash,canonical_source_hash,attachment_size_bytes,attachment_content_type,source_uid,proposal_id,canonical_import_receipt_id,vehicle_id,vehicle_version,
      backend_record_id,backend_record_version,job_card_number,requested_payload_sha256,operation_sha256,
      operation_count,estimated_hours_sum,canonical_operation_line_ids,response
    ) values(
      v_receipt_id,'159.1',v_actor,v_actor_email,p_intake_id,p_attachment_id,v_parent_hash,
      v_attachment_hash,v_canonical_source_hash,v_attachment.size_bytes,lower(v_attachment.content_type),v_source_uid,v_proposal_id,v_import_receipt.receipt_id,v_vehicle.id,v_vehicle.version,
      v_backend.id,v_backend.version,v_job_card,v_requested_digest,v_operation_digest,
      v_operation_count,v_hours_sum,v_line_ids,v_response);
    insert into public.pdc_email_operation_mapping_reviews_478(receipt_id,operation_line_id,operation_no,reason) select v_receipt_id,ol.operation_line_id,ol.operation_no,'station mapping is not established by an existing Craig-approved durable rule' from public.pdc_authenticated_email_operation_lines ol where ol.source_hash=v_canonical_source_hash and ol.work_key='owner_supplied_document' on conflict(operation_line_id) do nothing;
    for v_item in select value from jsonb_array_elements(v_input_lines) loop
      select * into strict v_line from public.pdc_authenticated_email_operation_lines
       where source_hash=v_canonical_source_hash and operation_no=v_item->>'operation_no';
      insert into public.pdc_jobcard_attachment_source_row_receipts(
        receipt_id,source_row_no,operation_no,operation_line_id,work_key,description,
        estimated_hours,estimated_hours_source,line_sha256
      ) values(
        v_receipt_id,(v_item->>'source_row_no')::integer,v_line.operation_no,v_line.operation_line_id,
        v_line.work_key,v_line.description,v_line.estimated_hours,v_line.estimated_hours_source,
        encode(extensions.digest(convert_to(jsonb_build_object(
          'source_row_no',(v_item->>'source_row_no')::integer,'operation_no',v_line.operation_no,
          'operation_line_id',v_line.operation_line_id,'work_key',v_line.work_key,'description',v_line.description,
          'estimated_hours',v_line.estimated_hours,'estimated_hours_source',v_line.estimated_hours_source
        )::text,'UTF8'),'sha256'),'hex'));
    end loop;
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('insert','pdc_jobcard_attachment_import_receipts',v_receipt_id,v_vehicle.id,v_actor,v_actor_email,null,
      jsonb_build_object('receipt_id',v_receipt_id,'intake_id',p_intake_id,'attachment_id',p_attachment_id,
        'operation_count',v_operation_count,'estimated_hours_sum',v_hours_sum),
      jsonb_build_object('source','bounded_jobcard_attachment_canonical_adapter_159','parent_source_hash',v_parent_hash,
        'attachment_source_hash',v_attachment_hash,'no_booking',true,'no_completion',true,'no_location_scheduling',true));
    update public.ai_email_intake set
      status='vehicle_updated',linked_vehicle_id=v_vehicle.id,
      processing_result=coalesce(processing_result,'{}'::jsonb)||jsonb_build_object(
        'jobcard_attachment_import_receipt_id',v_receipt_id,
        'jobcard_attachment_import_contract','159.1',
        'jobcard_attachment_imported_at',clock_timestamp(),'uid478_attachment_atomic_contract','233.1')
    where id=p_intake_id;
  exception when others then
    if sqlerrm='PDC_159_NESTED_FALSE_RESULT' then
      return coalesce(v_failure,public.navision_backend_response(false,'nested_import_failed'));
    end if;
    return public.navision_backend_response(false,'atomic_attachment_import_failed_'||sqlstate,jsonb_build_object('sqlstate',sqlstate,'message',left(sqlerrm,160)));
  end;
  return public.read_pdc_jobcard_attachment_import_receipt(v_receipt_id);
end
$function$
;
REVOKE ALL ON FUNCTION public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) TO postgres;
DO $post$
DECLARE v text; owner_name text; secdef boolean; acl text; old_count integer; intake_count integer;
BEGIN
 SELECT p.prosrc,p.proowner::regrole::text,p.prosecdef,p.proacl::text INTO v,owner_name,secdef,acl FROM pg_proc p WHERE p.oid='public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure;
 old_count:=(length(v)-length(replace(v,'h.sender_email=v_sender','')))/length('h.sender_email=v_sender');
 intake_count:=(length(v)-length(replace(v,'h.sender_email=lower(coalesce(v_intake.sender_email,''))','')))/length('h.sender_email=lower(coalesce(v_intake.sender_email,''))');
 IF owner_name IS DISTINCT FROM 'postgres' OR NOT secdef OR acl IS DISTINCT FROM '{postgres=X/postgres}' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '824118bfa90b509cf23eea078cb8f4a78bfe086df0535354e31471564b71040a' OR old_count<>0 OR intake_count<>2 THEN RAISE EXCEPTION 'PDC_816_HISTORICAL_IMPORTER_SENDER_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830237000','816_historical_importer_sender_binding_successor',ARRAY['replace the stale sender comparison in both historical importer fallback sites using the locked intake sender','preserve normal active-mailbox path, exact evidence, identity, atomic rollback, idempotency, RLS/grants, ten conflicts and zero drift','no historical Apply outbox mailbox task outbound or Production operation']);
COMMIT;
