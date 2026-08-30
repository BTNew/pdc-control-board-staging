-- STAGING ONLY 812: complete the renewed historical public transaction.
-- Root cause found by rollback-only server diagnostics: normal enqueue invokes
-- pdc_monitor_actor_scope(), which requires one active mailbox and raises
-- PDC_255_MONITOR_DEDICATED_IDENTITY_REQUIRED. Historical 778 must remain
-- zero-mailbox, so this successor adds a separately named, exact 673/809-bound
-- enqueue adapter and permits the canonical importer to consume only its exact
-- inactive-mailbox historical observation. Normal live enqueue/import contracts
-- remain unchanged; atomic rollback remains unchanged.
BEGIN;
SET LOCAL lock_timeout='15s'; SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-812-historical-full-transaction',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v_head text; v_renew integer; v_receipts integer; v_obs integer; v_mail integer; v text; vi text; owner_name text; secdef boolean; acl text;
BEGIN
 SELECT (version,name)::text INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 SELECT count(*) INTO v_renew FROM public.pdc_historical_reconciliation_writer_authorizations_809 WHERE active AND expires_at>clock_timestamp();
 SELECT count(*) INTO v_receipts FROM public.pdc_historical_reconciliation_778_receipts;
 SELECT count(*) INTO v_obs FROM public.pdc_historical_provider_observations_778;
 SELECT count(*) INTO v_mail FROM public.monitored_mailboxes WHERE active;
 SELECT p.prosrc,p.proowner::regrole::text,p.prosecdef,p.proacl::text INTO v,owner_name,secdef,acl FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb)'::regprocedure;
 SELECT p.prosrc INTO vi FROM pg_proc p WHERE p.oid='public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_head IS DISTINCT FROM '(20260830232000,811_nested_793_runtime_802_response_successor)' OR v_renew<>5 OR v_receipts<>0 OR v_obs<>0 OR v_mail<>0 OR owner_name IS DISTINCT FROM 'postgres' OR NOT secdef OR acl IS DISTINCT FROM '{postgres=X/postgres}' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '20ee8098061146d720cc63ad9e93fae2bcb6ba11f6d4f13b9268dd69bb42edab' OR encode(extensions.digest(convert_to(vi,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'a4d1ef35a95a5de2f58cece6133897af8486b9f20603877a9245259caf68e612' THEN RAISE EXCEPTION 'PDC_812_CURRENT_HEAD_OR_793_PRESTATE_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.enqueue_pdc_historical_email_intake_812(p_message jsonb, p_attachments jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 s jsonb:=jsonb_build_object('ok',public.pdc_monitor_authenticated_active_scope_673(NULL),'user_id',auth.uid(),'email',lower(btrim(coalesce(auth.jwt()->>'email',''))),'role','importer');v_id uuid;v_new boolean:=false;a jsonb;
 v_mailbox public.monitored_mailboxes%rowtype;v_recipient text;v_authserv text;v_auth jsonb;v_sender text;v_sender_hash text;v_sender_enrolled boolean;
 v_validation text;v_validation_error text;v_storage text;v_graph_attachment text;
BEGIN
 IF jsonb_typeof(p_message) IS DISTINCT FROM 'object' OR jsonb_typeof(p_attachments) IS DISTINCT FROM 'array'
 OR coalesce(p_message->>'graph_message_id',p_message->>'provider_uid','')='' OR lower(coalesce(p_message->>'source_hash',''))!~'^[a-f0-9]{64}$'
 OR jsonb_array_length(p_attachments)>25 THEN RAISE EXCEPTION 'pdc_monitor_identity_required' USING errcode='22023';END IF;
 v_recipient:=lower(btrim(coalesce(p_message->>'recipient_mailbox','')));v_authserv:=lower(btrim(coalesce(p_message->>'provider_authserv_id','')));
 v_auth:=coalesce(p_message->'provider_authentication','null'::jsonb);v_sender:=lower(btrim(coalesce(p_message->>'sender_email','')));
 SELECT * INTO v_mailbox FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'::uuid AND test_mode AND NOT active AND lower(mailbox_address)=v_recipient;
 IF NOT coalesce((s->>'ok')::boolean,false) OR p_message->>'historical_manifest_sha256' IS NULL OR p_message->>'historical_evidence_hash' IS NULL OR (SELECT count(*) FROM public.pdc_historical_writer_authorization_809_resolve(p_message->>'historical_manifest_sha256',p_message->>'provider_uid',p_message->>'source_hash',v_sender,v_auth,p_message->>'stock_number',p_message->>'historical_evidence_hash'))<>1 THEN RAISE EXCEPTION 'pdc_historical_enqueue_authorization_failed' USING errcode='42501'; END IF;
 IF NOT FOUND OR v_authserv<>'mx.google.com' OR jsonb_typeof(v_auth) IS DISTINCT FROM 'object'
 OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_auth)k) IS DISTINCT FROM array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
 OR v_auth->'gmail_authentication_results' IS DISTINCT FROM 'true'::jsonb
 OR NOT(v_auth->'spf_aligned'='true'::jsonb OR v_auth->'dkim_aligned'='true'::jsonb OR v_auth->'dmarc_aligned'='true'::jsonb)
 OR v_auth->>'sender_domain' IS DISTINCT FROM split_part(v_sender,'@',2) THEN RAISE EXCEPTION 'pdc_monitor_provider_binding_invalid' USING errcode='22023';END IF;
 v_sender_hash:=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex');
 v_sender_enrolled:=EXISTS(SELECT 1 FROM public.pdc_monitor_exact_sender_enrollments e WHERE e.active AND e.sender_sha256=v_sender_hash)
    OR public.pdc_historical_writer_authorized_773(lower(coalesce(p_message->>'source_hash','')),btrim(coalesce(p_message->>'provider_uid','')),v_sender,v_auth,p_message->>'stock_number');
 INSERT INTO public.ai_email_intake(graph_message_id,internet_message_id,provider_uid,source_hash,subject,sender_email,sender_name,received_at,raw_body,parsed_text,attachment_names,status,queue_attempts,next_attempt_at,monitored_mailbox_id,recipient_mailbox,provider_authserv_id,provider_authentication,extracted_data,created_at,updated_at)
 VALUES(p_message->>'graph_message_id',p_message->>'internet_message_id',p_message->>'provider_uid',lower(p_message->>'source_hash'),left(p_message->>'subject',1000),v_sender,left(p_message->>'sender_name',300),nullif(p_message->>'received_at','')::timestamptz,p_message->>'raw_body',p_message->>'parsed_text',coalesce(array(SELECT jsonb_array_elements_text(coalesce(p_message->'attachment_names','[]'::jsonb))),array[]::text[]),'received',0,clock_timestamp(),NULL,v_recipient,v_authserv,v_auth,jsonb_build_object('provider_authentication',v_auth,'provider_authserv_id',v_authserv,'sender_enrolled',v_sender_enrolled),clock_timestamp(),clock_timestamp())
 ON CONFLICT(source_hash) WHERE source_hash IS NOT NULL DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id INTO v_id FROM public.ai_email_intake WHERE source_hash=lower(p_message->>'source_hash');
  IF v_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=v_id
   AND i.graph_message_id=p_message->>'graph_message_id' AND coalesce(i.internet_message_id,'')=coalesce(p_message->>'internet_message_id','')
   AND i.provider_uid=p_message->>'provider_uid' AND i.source_hash=lower(p_message->>'source_hash')
   AND lower(i.sender_email)=v_sender AND lower(i.recipient_mailbox)=v_recipient AND i.provider_authserv_id=v_authserv
   AND i.provider_authentication IS NOT DISTINCT FROM v_auth) THEN RAISE EXCEPTION 'pdc_monitor_intake_replay_conflict' USING errcode='55000';END IF;
 ELSE v_new:=true;END IF;
 IF jsonb_array_length(p_attachments)<>(SELECT count(DISTINCT value->>'graph_attachment_id') FROM jsonb_array_elements(p_attachments)) THEN RAISE EXCEPTION 'pdc_monitor_attachment_payload_duplicate' USING errcode='22023';END IF;
 IF NOT v_new AND(
  jsonb_array_length(p_attachments)<>(SELECT count(*) FROM public.ai_email_attachments x WHERE x.intake_id=v_id)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_attachments) supplied(value) LEFT JOIN public.ai_email_attachments x ON x.intake_id=v_id AND x.graph_attachment_id=supplied.value->>'graph_attachment_id' WHERE x.id IS NULL)
  OR EXISTS(SELECT 1 FROM public.ai_email_attachments x WHERE x.intake_id=v_id AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_attachments) supplied(value) WHERE supplied.value->>'graph_attachment_id'=x.graph_attachment_id))
 ) THEN RAISE EXCEPTION 'pdc_monitor_attachment_replay_conflict' USING errcode='55000';END IF;
 FOR a IN SELECT value FROM jsonb_array_elements(p_attachments) LOOP
  v_validation:=btrim(coalesce(a->>'validation_status',''));v_validation_error:=left(btrim(coalesce(a->>'validation_error','')),500);v_storage:=btrim(coalesce(a->>'storage_path',''));v_graph_attachment:=btrim(coalesce(a->>'graph_attachment_id',''));
  IF lower(coalesce(a->>'source_hash',''))!~'^[a-f0-9]{64}$' OR length(btrim(coalesce(a->>'file_name',''))) NOT BETWEEN 1 AND 180
   OR length(v_graph_attachment) NOT BETWEEN 20 AND 300 OR v_graph_attachment NOT LIKE (p_message->>'provider_uid')||':%'
   OR v_validation NOT IN('verified','failed') OR (v_validation='verified' AND v_storage NOT LIKE 'pdc-email-intake-private/%')
   OR (v_validation='failed' AND (v_storage<>'' OR v_validation_error='')) THEN RAISE EXCEPTION 'pdc_monitor_attachment_invalid' USING errcode='22023';END IF;
  INSERT INTO public.ai_email_attachments(intake_id,graph_attachment_id,file_name,content_type,size_bytes,source_hash,storage_path,text_extraction_status,extraction_error,created_at)
  VALUES(v_id,v_graph_attachment,btrim(a->>'file_name'),left(a->>'content_type',200),coalesce((a->>'size_bytes')::bigint,0),lower(a->>'source_hash'),nullif(v_storage,''),CASE WHEN v_validation='verified' THEN 'pending' ELSE 'failed' END,nullif(v_validation_error,''),clock_timestamp())
  ON CONFLICT(intake_id,graph_attachment_id) WHERE graph_attachment_id IS NOT NULL DO NOTHING;
  IF NOT EXISTS(SELECT 1 FROM public.ai_email_attachments x WHERE x.intake_id=v_id AND x.graph_attachment_id=v_graph_attachment
   AND x.file_name=btrim(a->>'file_name') AND coalesce(x.content_type,'')=coalesce(left(a->>'content_type',200),'')
   AND x.size_bytes=coalesce((a->>'size_bytes')::bigint,0) AND x.source_hash=lower(a->>'source_hash') AND coalesce(x.storage_path,'')=v_storage
   AND ((v_validation='verified' AND x.text_extraction_status IN('pending','extracted') AND x.extraction_error IS NULL)
     OR (v_validation='failed' AND x.text_extraction_status='failed' AND coalesce(x.extraction_error,'')=v_validation_error)))
  THEN RAISE EXCEPTION 'pdc_monitor_attachment_replay_conflict' USING errcode='55000';END IF;
 END LOOP;
 IF jsonb_array_length(p_attachments)<>(SELECT count(DISTINCT value->>'graph_attachment_id') FROM jsonb_array_elements(p_attachments)) THEN RAISE EXCEPTION 'pdc_monitor_attachment_payload_duplicate' USING errcode='22023';END IF;
 IF NOT v_new AND jsonb_array_length(p_attachments)<>(SELECT count(*) FROM public.ai_email_attachments x WHERE x.intake_id=v_id) THEN RAISE EXCEPTION 'pdc_monitor_attachment_replay_conflict' USING errcode='55000';END IF;
 UPDATE public.pdc_email_monitor_status SET updated_at=clock_timestamp() WHERE singleton;
 RETURN jsonb_build_object('ok',true,'code',CASE WHEN v_new THEN 'pdc_monitor_intake_enqueued' ELSE 'pdc_monitor_intake_duplicate' END,'intake_id',v_id,'duplicate',NOT v_new,'sender_enrolled',v_sender_enrolled,'actor_email',s->>'email');
END $function$
;
REVOKE ALL ON FUNCTION public.enqueue_pdc_historical_email_intake_812(jsonb,jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.enqueue_pdc_historical_email_intake_812(jsonb,jsonb) TO postgres;
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
         and h.attachment_source_hash=v_attachment_hash and h.sender_email=v_sender
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
CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_succes(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
 v_actor uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_request jsonb:=coalesce(p_request,'null'::jsonb); v_authentication jsonb:=coalesce(v_request->'authentication','null'::jsonb);
 v_manifest text:=lower(btrim(coalesce(v_request->>'manifest_sha256',''))); v_uid text:=btrim(coalesce(v_request->>'provider_uid',''));
 v_parent text:=lower(btrim(coalesce(v_request->>'parent_source_hash',''))); v_sender text:=lower(btrim(coalesce(v_request->>'sender_email','')));
 v_stock text:=public.normalize_vehicle_stock_number(v_request->>'stock_number'); v_items jsonb:=coalesce(v_request->'attachment_manifest','null'::jsonb);
 v_children jsonb:=coalesce(v_request->'job_card_children','null'::jsonb); v_source jsonb:=coalesce(v_request->'source_metadata','null'::jsonb);
 v_authz public.pdc_historical_reconciliation_writer_authorizations_773%rowtype; v_existing public.pdc_historical_reconciliation_778_receipts%rowtype;
 v_intake public.ai_email_intake%rowtype; v_attachment public.ai_email_attachments%rowtype; v_child_receipt public.pdc_jobcard_attachment_import_receipts%rowtype; v_vehicle public.vehicles%rowtype;
 v_enqueue jsonb; v_parent_result jsonb; v_child_result jsonb; v_child_results jsonb:='[]'::jsonb; v_response jsonb;
 v_runtime jsonb; v_manifest_canonical jsonb; v_manifest_hash text; v_request_hash text; v_observation_sha text; v_extraction_hash text;
 v_child jsonb; v_item jsonb; v_intake_id uuid; v_attachment_id uuid; v_receipt_id uuid:=gen_random_uuid(); v_known_vehicle_id uuid; v_known_location text;
 v_boundary_before jsonb; v_boundary_after jsonb; v_related_before jsonb; v_related_after jsonb; v_authz_count integer; v_child_expected integer; v_child_seen integer:=0; v_attachment_count integer;
 v_job_card_count integer:=0; v_sibling_count integer:=0; v_operation_count integer; v_actual_operation_count integer; v_canonical_request text; v_canonical_observation text; v_booking_created boolean:=false; v_completion_created boolean:=false; v_location_scheduled boolean:=false; v_parts_changed boolean:=false; v_status_changed boolean:=false;
 v_proposal public.pdc_ai_intake_proposals%rowtype; v_proposal_id uuid; v_proposal_binding_id uuid:=gen_random_uuid(); v_proposal_observation_match boolean; v_proposal_binding_kind text; v_manifest_text text;
BEGIN
 if jsonb_typeof(v_request)='object' then
   v_request:=jsonb_set(v_request,'{authentication}',public.pdc_historical_authentication_canonical_806(v_request->'authentication'),true);
   v_authentication:=coalesce(v_request->'authentication','null'::jsonb);
 end if;
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_actor<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR v_actor_email<>'sales@broometoyota.com.au'
    OR (coalesce(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true')
    OR jsonb_typeof(v_request) IS DISTINCT FROM 'object'
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_request) k) IS DISTINCT FROM ARRAY[
      'action_type','attachment_manifest','authentication','canonical_request_utf8','evidence_hash','gateway_instance_id','job_card_children',
      'manifest_high_water_uid','manifest_sha256','manifest_uid_count','manifest_uidvalidity','observations','parent_source_hash',
      'provider_uid','release_manifest_sha256','release_name','release_source_sha','sender_email','source_metadata','stock_number','subject','summary']::text[] THEN
   RETURN jsonb_build_object('ok',false,'code','unauthorized');
 END IF;
 IF v_request->>'gateway_instance_id' IS DISTINCT FROM 'pdc-monitor-staging-sales-uid509-v1'
    OR v_request->>'release_name' IS DISTINCT FROM 'pdc-monitor-staging-m502-2026.08.44'
    OR lower(v_request->>'release_source_sha') IS DISTINCT FROM 'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
    OR lower(v_request->>'release_manifest_sha256') IS DISTINCT FROM 'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
    OR v_request->>'manifest_uidvalidity' IS DISTINCT FROM '1' OR v_request->>'manifest_high_water_uid' IS DISTINCT FROM '685' OR v_request->>'manifest_uid_count' IS DISTINCT FROM '669' THEN
   RETURN jsonb_build_object('ok',false,'code','historical_manifest_or_runtime_binding_mismatch');
 END IF;
 v_runtime:=public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227');
 IF v_runtime->>'ok' IS DISTINCT FROM 'true' OR v_runtime->>'actor_id' IS DISTINCT FROM v_actor::text OR v_runtime->>'actor_email' IS DISTINCT FROM v_actor_email OR v_runtime->>'task_enabled' IS DISTINCT FROM 'false' OR v_runtime->>'mailbox_contacted' IS DISTINCT FROM 'false' OR v_runtime->>'production_writes' IS DISTINCT FROM 'false' THEN
   RETURN jsonb_build_object('ok',false,'code','historical_runtime_binding_unavailable');
 END IF;
 IF v_manifest IS DISTINCT FROM 'aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
    OR v_uid!~'^1:[1-9][0-9]{0,5}$' OR v_uid='1:197' OR v_parent!~'^[a-f0-9]{64}$'
    OR v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
    OR jsonb_typeof(v_authentication) IS DISTINCT FROM 'object' OR jsonb_typeof(v_items) IS DISTINCT FROM 'array' OR jsonb_array_length(v_items) NOT BETWEEN 1 AND 25
    OR jsonb_typeof(v_children) IS DISTINCT FROM 'array' OR jsonb_array_length(v_children)>25 OR jsonb_typeof(v_source) IS DISTINCT FROM 'object'
    OR v_request->>'evidence_hash'!~'^[a-f0-9]{64}$' OR length(coalesce(v_request->>'subject','')) NOT BETWEEN 1 AND 300
    OR length(coalesce(v_request->>'summary','')) NOT BETWEEN 5 AND 2000 OR v_request->>'action_type' NOT IN ('board_activate_only','review_only') THEN
   RETURN jsonb_build_object('ok',false,'code','invalid_input');
 END IF;
 IF v_stock='13056899' OR NOT public.is_real_vehicle_stock_number(v_stock) THEN RETURN jsonb_build_object('ok',false,'code','historical_reference_stock_excluded'); END IF;
 IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_source) k) IS DISTINCT FROM ARRAY['attachment_names','graph_message_id','internet_message_id','parsed_text','provider_authserv_id','raw_body','received_at','recipient_mailbox','sender_name','uid','uidvalidity']::text[]
    OR v_source->>'uidvalidity' IS DISTINCT FROM '1' OR v_source->>'uid' IS DISTINCT FROM substring(v_uid FROM '^1:([0-9]+)$')
    OR v_source->>'provider_authserv_id' IS DISTINCT FROM 'mx.google.com' OR v_source->>'received_at' IS NULL OR lower(v_source->>'recipient_mailbox') IS DISTINCT FROM 'pmbcontroller@gmail.com'
    OR v_source->'attachment_names' IS DISTINCT FROM (SELECT jsonb_agg(m->>'filename' ORDER BY ordinality) FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality)) THEN
   RETURN jsonb_build_object('ok',false,'code','invalid_source_metadata');
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality) WHERE jsonb_typeof(x.m) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x.m) k) IS DISTINCT FROM ARRAY['attachment_kind','content_type','filename','ordinal','sha256','size']::text[] OR x.m->>'attachment_kind' NOT IN ('job_card','ambiguous_job_card','non_job_card_sibling') OR x.m->>'content_type' IS NULL OR x.m->>'filename' IS NULL OR x.m->>'sha256'!~'^[a-f0-9]{64}$' OR x.m->>'ordinal'!~'^[1-9][0-9]{0,2}$' OR (x.m->>'ordinal')::integer<>x.ordinality OR x.m->>'size'!~'^[1-9][0-9]{0,7}$') THEN
   RETURN jsonb_build_object('ok',false,'code','invalid_attachment_metadata');
 END IF;
 IF v_request->>'manifest_sha256' IS DISTINCT FROM lower(v_request->>'manifest_sha256') OR v_request->>'parent_source_hash' IS DISTINCT FROM lower(v_request->>'parent_source_hash') OR v_request->>'sender_email' IS DISTINCT FROM lower(v_request->>'sender_email') OR v_request->>'evidence_hash' IS DISTINCT FROM lower(v_request->>'evidence_hash') OR v_request->>'stock_number' IS DISTINCT FROM public.normalize_vehicle_stock_number(v_request->>'stock_number') OR v_source->>'recipient_mailbox' IS DISTINCT FROM lower(v_source->>'recipient_mailbox') OR v_request->'canonical_request_utf8' IS NULL THEN RETURN jsonb_build_object('ok',false,'code','historical_canonical_normalization_mismatch'); END IF;
v_canonical_request:=public.pdc_historical_canonical_request_788(v_request,v_actor,v_actor_email,v_runtime);
IF v_request->>'canonical_request_utf8' IS DISTINCT FROM v_canonical_request THEN RETURN jsonb_build_object('ok',false,'code','historical_canonical_request_mismatch'); END IF;
SELECT count(*) INTO v_authz_count
  FROM public.pdc_historical_writer_authorization_809_resolve(v_manifest,v_uid,v_parent,v_sender,v_authentication,v_stock,v_request->>'evidence_hash') r;
 IF v_authz_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','pdc_778_exact_authorization_failed'); END IF;
 SELECT * INTO v_authz
  FROM public.pdc_historical_writer_authorization_809_resolve(v_manifest,v_uid,v_parent,v_sender,v_authentication,v_stock,v_request->>'evidence_hash');
 IF clock_timestamp()>v_authz.authorized_at+interval '24 hours' THEN RETURN jsonb_build_object('ok',false,'code','historical_authorization_expired'); END IF;
 SELECT jsonb_agg(jsonb_build_object('content_type',m->>'content_type','filename',m->>'filename','sha256',lower(m->>'sha256'),'size',(m->>'size')::bigint) ORDER BY ordinality) INTO v_manifest_canonical FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality);
 SELECT '['||coalesce(string_agg('{"content_type":'||to_jsonb(m->>'content_type')::text||',"filename":'||to_jsonb(m->>'filename')::text||',"sha256":'||to_jsonb(lower(m->>'sha256'))::text||',"size":'||((m->>'size')::bigint)::text||'}',',' ORDER BY ordinality),'')||']' INTO v_manifest_text FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality);
 v_manifest_hash:=encode(extensions.digest(convert_to(v_manifest_text,'UTF8'),'sha256'),'hex');
 IF v_manifest_hash<>v_authz.attachment_manifest_sha256 OR v_manifest_canonical IS DISTINCT FROM v_authz.attachment_manifest OR jsonb_array_length(v_items)<>v_authz.attachment_count THEN RETURN jsonb_build_object('ok',false,'code','historical_attachment_manifest_mismatch'); END IF;
 v_request_hash:=encode(extensions.digest(convert_to(v_canonical_request,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-778:'||v_uid||':'||v_parent,0));
 SELECT * INTO v_existing FROM public.pdc_historical_reconciliation_778_receipts WHERE actor_id=v_actor AND provider_uid=v_uid AND parent_source_hash=v_parent;
 IF FOUND THEN IF v_existing.request_sha256<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','historical_replay_conflict'); END IF; RETURN v_existing.canonical_response; END IF;
 SELECT count(*) INTO v_attachment_count FROM public.vehicles v WHERE v.stock_number_normalized=v_stock AND v.deleted_at IS NULL;
 IF v_attachment_count>1 THEN RAISE EXCEPTION 'PDC_782_IDENTITY_CONFLICT' USING errcode='P0001'; END IF;
 SELECT v.id,v.current_location INTO v_known_vehicle_id,v_known_location FROM public.vehicles v WHERE v.stock_number_normalized=v_stock AND v.deleted_at IS NULL ORDER BY v.id LIMIT 1;
 v_parent_result:=public.submit_pdc_ai_intake_observation_pre135(v_parent, v_request->>'evidence_hash',v_uid,v_sender,v_authentication,(v_source->>'received_at')::timestamptz,v_request->>'subject',v_request->>'action_type',v_stock,v_request->>'summary',v_request->'observations');
 IF NOT coalesce((v_parent_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_789_PARENT_PROPOSAL_FAILED' USING errcode='P0001'; END IF;
 IF (v_parent_result->'data'->>'proposal_id') IS NULL OR (v_parent_result->'data'->>'proposal_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_789_PROPOSAL_ID_READBACK_FAILED' USING errcode='55000'; END IF;
 v_proposal_id:=(v_parent_result->'data'->>'proposal_id')::uuid;
 SELECT * INTO v_proposal FROM public.pdc_ai_intake_proposals WHERE proposal_id=v_proposal_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_789_PROPOSAL_READBACK_FAILED' USING errcode='55000'; END IF;
 IF v_proposal.status::text<>'pending' THEN
   RETURN jsonb_build_object('ok',false,'code','historical_proposal_terminal_conflict','data',jsonb_build_object('proposal_id',v_proposal.proposal_id,'status',v_proposal.status,'review_required',true));
 END IF;
 IF v_proposal.source_hash IS DISTINCT FROM v_parent
    OR v_proposal.evidence_hash IS DISTINCT FROM lower(v_request->>'evidence_hash')
    OR v_proposal.source_uid IS DISTINCT FROM v_uid
    OR lower(v_proposal.sender_address) IS DISTINCT FROM v_sender
    OR v_proposal.authentication IS DISTINCT FROM v_authentication
    OR public.normalize_vehicle_stock_number(v_proposal.stock_number) IS DISTINCT FROM v_stock
    OR v_proposal.source_received_at IS DISTINCT FROM (v_source->>'received_at')::timestamptz
    OR v_proposal.subject IS DISTINCT FROM v_request->>'subject'
    OR v_proposal.action_type IS DISTINCT FROM v_request->>'action_type'
    OR v_proposal.summary IS DISTINCT FROM v_request->>'summary' THEN
   RETURN jsonb_build_object('ok',false,'code','historical_proposal_tuple_conflict','data',jsonb_build_object('proposal_id',v_proposal.proposal_id,'review_required',true,'source_tuple_conflict',true));
 END IF;
 v_proposal_observation_match:=v_proposal.observations IS NOT DISTINCT FROM v_request->'observations';
 v_proposal_binding_kind:=CASE WHEN v_proposal_observation_match THEN 'pending_proposal_observation_match' ELSE 'pending_proposal_observation_mismatch' END;

 IF v_parent_result->>'code'='already_noticed' AND NOT EXISTS(SELECT 1 FROM public.ai_email_intake WHERE source_hash=v_parent ORDER BY created_at DESC LIMIT 1) THEN
   INSERT INTO public.pdc_historical_proposal_compatibility_reviews_793(
     review_id,proposal_id,contract_version,historical_contract_version,authorization_id,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,evidence_hash,sender_email,authentication,stock_number,source_received_at,subject,action_type,summary,request_sha256,proposal_observations,requested_observations,observation_match,review_code
   ) VALUES(
     gen_random_uuid(),v_proposal.proposal_id,'793.1','788.1',v_authz.authorization_id,v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_request->>'evidence_hash',v_sender,v_authentication,v_stock,(v_source->>'received_at')::timestamptz,v_request->>'subject',v_request->>'action_type',v_request->>'summary',v_request_hash,v_proposal.observations,v_request->'observations',v_proposal_observation_match,'historical_proposal_observation_review_required'
   ) ON CONFLICT(proposal_id,request_sha256) DO NOTHING;
   RETURN jsonb_build_object('ok',false,'code','historical_proposal_observation_review_required','data',jsonb_build_object('proposal_id',v_proposal.proposal_id,'review_required',true,'observation_match',v_proposal_observation_match,'intake_present',false));
 END IF;

 v_boundary_before:=public.pdc_historical_782_boundary_snapshot(); v_related_before:=public.pdc_historical_782_unrelated_snapshot(v_known_vehicle_id);
 v_enqueue:=public.enqueue_pdc_historical_email_intake_812(jsonb_build_object('graph_message_id',v_source->>'graph_message_id','internet_message_id',v_source->>'internet_message_id','provider_uid',v_uid,'source_hash',v_parent,'subject',v_request->>'subject','sender_email',v_sender,'sender_name',v_source->>'sender_name','received_at',v_source->>'received_at','raw_body',v_source->>'raw_body','parsed_text',v_source->>'parsed_text','attachment_names',v_source->'attachment_names','recipient_mailbox',lower(v_source->>'recipient_mailbox'),'provider_authserv_id',v_source->>'provider_authserv_id','provider_authentication',v_authentication,'historical_manifest_sha256',v_manifest,'historical_evidence_hash',v_request->>'evidence_hash','historical_parent_source_hash',v_parent,'stock_number',v_stock),(SELECT jsonb_agg(jsonb_build_object('graph_attachment_id',v_uid||':historical-782-'||lpad(x.ordinality::text,3,'0')||'-'||lower(x.m->>'sha256'),'file_name',x.m->>'filename','content_type',x.m->>'content_type','size_bytes',(x.m->>'size')::bigint,'source_hash',lower(x.m->>'sha256'),'storage_path','pdc-email-intake-private/historical-782/'||lpad(x.ordinality::text,3,'0')||'-'||lower(x.m->>'sha256'),'validation_status','verified') ORDER BY x.ordinality) FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality)));
 IF NOT coalesce((v_enqueue->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_782_ENQUEUE_FAILED' USING errcode='P0001'; END IF;
 IF v_enqueue->>'intake_id' !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_782_ENQUEUE_ID_FAILED' USING errcode='55000'; END IF;
 v_intake_id:=(v_enqueue->>'intake_id')::uuid;
 SELECT * INTO v_intake FROM public.ai_email_intake WHERE id=v_intake_id FOR UPDATE;
 IF NOT FOUND OR lower(coalesce(v_intake.source_hash,''))<>v_parent OR v_intake.provider_uid<>v_uid OR lower(coalesce(v_intake.sender_email,''))<>v_sender OR v_intake.received_at IS DISTINCT FROM (v_source->>'received_at')::timestamptz OR v_intake.internet_message_id IS DISTINCT FROM v_source->>'internet_message_id' OR v_intake.graph_message_id IS DISTINCT FROM v_source->>'graph_message_id' OR lower(coalesce(v_intake.recipient_mailbox,''))<>lower(v_source->>'recipient_mailbox') OR v_intake.provider_authserv_id IS DISTINCT FROM v_source->>'provider_authserv_id' OR v_intake.provider_authentication IS DISTINCT FROM v_authentication THEN RAISE EXCEPTION 'PDC_782_INTAKE_BINDING_FAILED' USING errcode='P0001'; END IF;
 IF v_intake.duplicate_of IS NOT NULL OR v_intake.status::text IN ('duplicate_detected','failed','ignored','vehicle_created','vehicle_updated') THEN RAISE EXCEPTION 'PDC_782_OLD_MAIL_COMPLETED' USING errcode='P0001'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
   SELECT count(*) INTO v_attachment_count FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND lower(a.source_hash)=lower(v_item->>'sha256') AND lower(a.file_name)=lower(v_item->>'filename') AND lower(coalesce(a.content_type,''))=lower(v_item->>'content_type') AND a.size_bytes=(v_item->>'size')::bigint AND a.graph_attachment_id=v_uid||':historical-782-'||lpad((v_item->>'ordinal')::integer::text,3,'0')||'-'||lower(v_item->>'sha256');
   IF v_attachment_count<>1 THEN RAISE EXCEPTION 'PDC_782_ATTACHMENT_BINDING_FAILED' USING errcode='P0001'; END IF;
   SELECT * INTO v_attachment FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=v_uid||':historical-782-'||lpad((v_item->>'ordinal')::integer::text,3,'0')||'-'||lower(v_item->>'sha256');
   v_canonical_observation:=public.pdc_historical_canonical_observation_788(v_request,v_runtime,v_authz.authorization_id,v_intake_id,v_attachment.id,(v_item->>'ordinal')::integer,v_item->>'attachment_kind',lower(v_item->>'sha256'),v_request_hash);
   v_observation_sha:=encode(extensions.digest(convert_to(v_canonical_observation,'UTF8'),'sha256'),'hex');
   INSERT INTO public.pdc_historical_provider_observations_778(contract_version,authorization_id,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,intake_id,attachment_id,attachment_source_hash,provider_message_id,provider_authserv_id,authentication,request_sha256,observation_sha256) VALUES('778.1',v_authz.authorization_id,v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_sender,v_stock,v_intake_id,v_attachment.id,lower(v_item->>'sha256'),v_source->>'internet_message_id',v_source->>'provider_authserv_id',v_authentication,v_request_hash,v_observation_sha) ON CONFLICT(intake_id,attachment_id) DO NOTHING;
   IF NOT EXISTS(SELECT 1 FROM public.pdc_historical_provider_observations_778 h WHERE h.intake_id=v_intake_id AND h.attachment_id=v_attachment.id AND h.contract_version='778.1' AND h.authorization_id=v_authz.authorization_id AND h.actor_id=v_actor AND h.actor_email=v_actor_email AND h.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND h.manifest_sha256=v_manifest AND h.provider_uid=v_uid AND h.parent_source_hash=v_parent AND h.sender_email=v_sender AND h.stock_number=v_stock AND h.attachment_source_hash=lower(v_item->>'sha256') AND h.provider_message_id=v_source->>'internet_message_id' AND h.provider_authserv_id=v_source->>'provider_authserv_id' AND h.authentication IS NOT DISTINCT FROM v_authentication AND h.request_sha256=v_request_hash AND h.observation_sha256=v_observation_sha) THEN RAISE EXCEPTION 'PDC_788_OBSERVATION_REPLAY_CONFLICT' USING errcode='55000'; END IF;
   IF v_item->>'attachment_kind'='job_card' THEN v_job_card_count:=v_job_card_count+1; ELSE v_sibling_count:=v_sibling_count+1; END IF;
 END LOOP;
 SELECT count(*) INTO v_child_expected FROM jsonb_array_elements(v_items) m WHERE m->>'attachment_kind' IN ('job_card','ambiguous_job_card');
 IF jsonb_array_length(v_children)<>v_child_expected THEN RAISE EXCEPTION 'PDC_782_CHILD_CARDINALITY_FAILED' USING errcode='P0001'; END IF;
 FOR v_child IN SELECT value FROM jsonb_array_elements(v_children) LOOP
   v_child_seen:=v_child_seen+1;
   IF jsonb_typeof(v_child) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_child) k) IS DISTINCT FROM ARRAY['attachment_hash','attachment_kind','attachment_ordinal','extraction','extraction_hash']::text[] OR v_child->>'attachment_hash'!~'^[a-f0-9]{64}$' OR v_child->>'attachment_ordinal'!~'^[1-9][0-9]{0,2}$' OR v_child->>'extraction_hash'!~'^[a-f0-9]{64}$' OR jsonb_typeof(v_child->'extraction') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PDC_782_CHILD_INVALID' USING errcode='P0001'; END IF;
   SELECT m INTO v_item FROM jsonb_array_elements(v_items) m WHERE (m->>'ordinal')::integer=(v_child->>'attachment_ordinal')::integer;
   IF NOT FOUND OR lower(v_item->>'sha256') IS DISTINCT FROM lower(v_child->>'attachment_hash') OR v_child->>'attachment_kind' IS DISTINCT FROM v_item->>'attachment_kind' THEN RAISE EXCEPTION 'PDC_782_CHILD_OCCURRENCE_MISMATCH' USING errcode='P0001'; END IF;
   IF v_child->>'attachment_kind'='ambiguous_job_card' THEN
     IF NOT(coalesce(jsonb_array_length(v_child->'extraction'->'email_vehicle'->'stock_numbers'),0)>1 OR coalesce(jsonb_array_length(v_child->'extraction'->'email_vehicle'->'vins'),0)>1 OR coalesce(jsonb_array_length(v_child->'extraction'->'email_vehicle'->'conflicts'),0)>0 OR coalesce(jsonb_array_length(v_child->'extraction'->'job_cards'),0)<>1) THEN RAISE EXCEPTION 'PDC_782_AMBIGUITY_NOT_PROVEN' USING errcode='P0001'; END IF;
     v_child_results:=v_child_results||jsonb_build_array(jsonb_build_object('attachment_ordinal',(v_child->>'attachment_ordinal')::integer,'attachment_hash',v_child->>'attachment_hash','result',jsonb_build_object('ok',false,'code','historical_child_ambiguous')));
     CONTINUE;
   END IF;
   SELECT * INTO v_authz FROM public.pdc_historical_reconciliation_writer_authorizations_773 e WHERE e.authorization_id=v_authz.authorization_id;
   IF NOT EXISTS(SELECT 1 FROM public.pdc_historical_job_card_attachments_782 j WHERE j.manifest_sha256=v_manifest AND j.provider_uid=v_uid AND j.parent_source_hash=v_parent AND j.attachment_ordinal=(v_child->>'attachment_ordinal')::integer AND j.attachment_kind='job_card' AND j.attachment_hash=lower(v_child->>'attachment_hash') AND lower(j.content_type)=lower(v_item->>'content_type') AND lower(j.filename)=lower(v_item->>'filename') AND j.size_bytes=(v_item->>'size')::bigint AND j.stock_number=v_stock AND lower(j.job_card_number)=lower(v_child->'extraction'->'email_vehicle'->>'job_card_number') AND j.extraction_hash=lower(v_child->>'extraction_hash')) THEN RAISE EXCEPTION 'PDC_782_JOB_CARD_KIND_MISMATCH' USING errcode='55000'; END IF;
   v_extraction_hash:=encode(extensions.digest(convert_to((v_child->'extraction')::text,'UTF8'),'sha256'),'hex');
   IF lower(v_child->>'extraction_hash') IS DISTINCT FROM v_extraction_hash THEN RAISE EXCEPTION 'PDC_782_EXTRACTION_HASH_FAILED' USING errcode='P0001'; END IF;
   SELECT count(*) INTO v_attachment_count FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=v_uid||':historical-782-'||lpad((v_child->>'attachment_ordinal')::integer::text,3,'0')||'-'||lower(v_child->>'attachment_hash') AND lower(a.source_hash)=lower(v_child->>'attachment_hash') AND lower(a.file_name)=lower(v_item->>'filename') AND lower(coalesce(a.content_type,''))=lower(v_item->>'content_type') AND a.size_bytes=(v_item->>'size')::bigint;
   IF v_attachment_count<>1 THEN RAISE EXCEPTION 'PDC_782_CHILD_ATTACHMENT_NONUNIQUE' USING errcode='P0001'; END IF;
   SELECT * INTO v_attachment FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=v_uid||':historical-782-'||lpad((v_child->>'attachment_ordinal')::integer::text,3,'0')||'-'||lower(v_child->>'attachment_hash');
   v_child_result:=public.import_pdc_jobcard_attachment_canonical(v_intake_id,v_attachment.id,v_parent,lower(v_child->>'attachment_hash'),v_authentication,v_child->'extraction'->'email_vehicle',v_child->'extraction'->'required_work',v_child->'extraction'->'operation_lines');
   IF NOT coalesce((v_child_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_782_CHILD_IMPORT_FAILED' USING errcode='P0001'; END IF;
   SELECT count(*) INTO v_attachment_count FROM public.pdc_jobcard_attachment_import_receipts r WHERE r.intake_id=v_intake_id AND r.attachment_id=v_attachment.id;
   IF v_attachment_count<>1 THEN RAISE EXCEPTION 'PDC_782_CHILD_RECEIPT_FAILED' USING errcode='P0001'; END IF;
   SELECT * INTO v_child_receipt FROM public.pdc_jobcard_attachment_import_receipts r WHERE r.intake_id=v_intake_id AND r.attachment_id=v_attachment.id;
   SELECT * INTO v_vehicle FROM public.vehicles v WHERE v.id=v_child_receipt.vehicle_id;
   IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state::text<>'active' OR v_vehicle.board_purged_at IS NOT NULL OR NOT coalesce(v_vehicle.visible_on_board,false) OR v_vehicle.stock_number_normalized<>v_stock OR upper(btrim(coalesce(v_vehicle.job_card_number,'')))<>upper(v_child->'extraction'->'email_vehicle'->>'job_card_number') THEN RAISE EXCEPTION 'PDC_782_AUTHORITATIVE_STATE_FAILED' USING errcode='P0001'; END IF;
   v_operation_count:=jsonb_array_length(v_child->'extraction'->'operation_lines');
   SELECT count(*) INTO v_actual_operation_count FROM public.pdc_authenticated_email_operation_lines ol WHERE ol.vehicle_id=v_vehicle.id AND ol.source_hash=v_child_receipt.canonical_source_hash AND ol.source_uid=v_child_receipt.source_uid;
   IF v_actual_operation_count<>v_operation_count OR v_child_receipt.operation_count<>v_operation_count OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_child->'extraction'->'operation_lines') x WHERE NOT EXISTS(SELECT 1 FROM public.pdc_authenticated_email_operation_lines ol WHERE ol.vehicle_id=v_vehicle.id AND ol.source_hash=v_child_receipt.canonical_source_hash AND ol.source_uid=v_child_receipt.source_uid AND ol.operation_no=x->>'operation_no' AND ol.work_key=x->>'work_key' AND ol.description=x->>'description' AND ol.estimated_hours IS NOT DISTINCT FROM CASE WHEN jsonb_typeof(x->'estimated_hours')='number' THEN (x->>'estimated_hours')::numeric ELSE NULL END)) THEN RAISE EXCEPTION 'PDC_782_AUTHORITATIVE_STATE_FAILED' USING errcode='55000'; END IF;
   IF v_known_vehicle_id IS NOT NULL AND v_vehicle.current_location IS DISTINCT FROM v_known_location THEN RAISE EXCEPTION 'PDC_782_LOCATION_SIDE_EFFECT' USING errcode='55000'; END IF;
   v_child_results:=v_child_results||jsonb_build_array(jsonb_build_object('attachment_ordinal',(v_child->>'attachment_ordinal')::integer,'attachment_hash',v_child->>'attachment_hash','result',v_child_result,'authoritative_vehicle_id',v_vehicle.id,'authoritative_operation_count',v_actual_operation_count));
 END LOOP;
 v_boundary_after:=public.pdc_historical_782_boundary_snapshot(); v_related_after:=public.pdc_historical_782_unrelated_snapshot(v_vehicle.id);
 v_booking_created:=v_boundary_after->>'workshop_bookings' IS DISTINCT FROM v_boundary_before->>'workshop_bookings' OR v_boundary_after->>'workshop_booking_assignments' IS DISTINCT FROM v_boundary_before->>'workshop_booking_assignments';
 v_completion_created:=v_boundary_after->>'pdc_qc_operation_completions_379' IS DISTINCT FROM v_boundary_before->>'pdc_qc_operation_completions_379';
 v_location_scheduled:=v_booking_created;
 v_parts_changed:=v_boundary_after->>'vehicle_parts_updates' IS DISTINCT FROM v_boundary_before->>'vehicle_parts_updates';
 v_status_changed:=v_related_after->>'vehicles' IS DISTINCT FROM v_related_before->>'vehicles';
 IF v_parts_changed OR v_booking_created OR v_completion_created OR v_location_scheduled THEN RAISE EXCEPTION 'PDC_782_PROTECTED_BOUNDARY_DRIFT' USING errcode='55000'; END IF;
 IF v_status_changed OR v_related_after IS DISTINCT FROM v_related_before THEN RAISE EXCEPTION 'PDC_782_UNRELATED_STATE_DRIFT' USING errcode='55000'; END IF;
IF v_boundary_after IS DISTINCT FROM v_boundary_before THEN RAISE EXCEPTION 'PDC_788_PROTECTED_BOUNDARY_DRIFT' USING errcode='55000'; END IF;
 v_response:=jsonb_build_object('ok',true,'code','historical_reconciliation_782_receipt','data',jsonb_build_object('receipt_id',v_receipt_id,'contract_version','778.1','manifest_sha256',v_manifest,'provider_uid',v_uid,'parent_source_hash',v_parent,'sender_email',v_sender,'stock_number',v_stock,'intake_id',v_intake_id,'attachment_count',jsonb_array_length(v_items),'proposal_id',v_proposal.proposal_id,'proposal_binding_kind',v_proposal_binding_kind,'proposal_observation_match',v_proposal_observation_match,'job_card_count',v_job_card_count,'sibling_count',v_sibling_count,'attachment_receipts',v_child_results,'parent_observation',v_parent_result,'authoritative_state',jsonb_build_object('vehicle_id',v_vehicle.id,'lifecycle_state',v_vehicle.lifecycle_state,'current_location',v_vehicle.current_location,'operation_count',coalesce(v_actual_operation_count,0),'booking_count',0,'completion_count',0,'parts_changed',v_parts_changed),'booking_created',v_booking_created,'completion_created',v_completion_created,'location_scheduled',v_location_scheduled,'parts_changed',v_parts_changed,'status_changed',v_status_changed,'no_booking',NOT v_booking_created,'no_completion',NOT v_completion_created,'no_location_mutation',NOT v_location_scheduled));
 INSERT INTO public.pdc_historical_reconciliation_778_receipts(receipt_id,contract_version,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,request_sha256,intake_id,attachment_count,job_card_count,sibling_count,request_evidence,canonical_response) VALUES(v_receipt_id,'778.1',v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_sender,v_stock,v_request_hash,v_intake_id,jsonb_array_length(v_items),v_job_card_count,v_sibling_count,v_request,v_response);
 INSERT INTO public.pdc_historical_proposal_bindings_789(
   binding_id,receipt_id,proposal_id,contract_version,historical_contract_version,authorization_id,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,evidence_hash,sender_email,authentication,stock_number,source_received_at,subject,action_type,summary,request_sha256,proposal_observations,requested_observations,observation_match,binding_kind
 ) VALUES(
   v_proposal_binding_id,v_receipt_id,v_proposal.proposal_id,'789.1','788.1',v_authz.authorization_id,v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_request->>'evidence_hash',v_sender,v_authentication,v_stock,(v_source->>'received_at')::timestamptz,v_request->>'subject',v_request->>'action_type',v_request->>'summary',v_request_hash,v_proposal.observations,v_request->'observations',v_proposal_observation_match,v_proposal_binding_kind
 );
 INSERT INTO public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata) VALUES('insert','pdc_historical_reconciliation_778_receipts',v_actor,v_actor_email,NULL,v_response->'data',jsonb_build_object('contract','778.1','manifest_sha256',v_manifest,'protected_boundary_before',v_boundary_before,'protected_boundary_after',v_boundary_after,'unrelated_before',v_related_before,'unrelated_after',v_related_after));
 RETURN v_response;
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('ok',false,'code','historical_reconciliation_782_atomic_rollback');
END
$function$
;
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_successor(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_successor(jsonb) TO postgres;
DO $post$
DECLARE v text; vi text; vh text; owner_name text; secdef boolean; acl text;
BEGIN
 SELECT p.prosrc,p.proowner::regrole::text,p.prosecdef,p.proacl::text INTO v,owner_name,secdef,acl FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb)'::regprocedure;
 SELECT p.prosrc INTO vi FROM pg_proc p WHERE p.oid='public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure;
 SELECT p.prosrc INTO vh FROM pg_proc p WHERE p.oid='public.enqueue_pdc_historical_email_intake_812(jsonb,jsonb)'::regprocedure;
 IF owner_name IS DISTINCT FROM 'postgres' OR NOT secdef OR acl IS DISTINCT FROM '{postgres=X/postgres}' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '9965d76b424b91404769dfdd33900c53da077c2c14fcbe4b0fcf3ce44f06bc04' OR encode(extensions.digest(convert_to(vi,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '6b72a9d5c169b68247d8c27df2069273c05503eb87ec83123ddbc6bf15e9e528' OR encode(extensions.digest(convert_to(vh,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '3aafebd348bbec26ec54dca67587fe2a09b3e95c00310c0734bebb2e7970e8d7' OR position('public.enqueue_pdc_historical_email_intake_812(' in v)=0 OR position('public.enqueue_pdc_monitor_runtime_binding_authenticated_766' in v)>0 OR position('pdc_monitor_authenticated_active_scope_673(NULL)' in vi)=0 OR position('pdc_historical_provider_observations_778' in vi)=0 THEN RAISE EXCEPTION 'PDC_812_RUNTIME_OR_IMPORT_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830233000','812_historical_full_transaction_zero_mailbox_successor',ARRAY['replace normal enqueue only for exact historical 778 path with authenticated 673/809 zero-mailbox adapter','permit canonical importer inactive mailbox only when exact historical observation and 673 scope are present','preserve atomic rollback, identity/evidence/RLS/grants/idempotency/isolation and ten conflicts','no historical Apply outbox mailbox task outbound or Production operation']);
COMMIT;
