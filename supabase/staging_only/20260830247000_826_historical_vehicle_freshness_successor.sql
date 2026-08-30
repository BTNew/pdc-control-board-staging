-- STAGING ONLY 826: gate authenticated vehicle evidence freshness by auth context.
-- The bounded historical child path carries verified context from 822. Preserve
-- ordinary 30-day evidence expiry and cancellation rejection; bypass freshness
-- only for matching derived source UID/actor with exact 773 authorization.
BEGIN;
SET LOCAL lock_timeout='15s'; SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-826-historical-vehicle-freshness',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v text;
BEGIN
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830246000,825_historical_vehicle_creation_normalized_guard_successor)' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '68eae3f93bb73b6f06f3bef3fdadfd37b22ce6396ac43cb60989de4afc4eb8ec' OR position('p_source_received_at<clock_timestamp()-interval ''30 days''' in lower(v))=0 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_writer_authorizations_809 WHERE active AND expires_at>clock_timestamp())<>5 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_778_receipts)<>0 OR (SELECT count(*) FROM public.pdc_historical_provider_observations_778)<>0 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0 THEN RAISE EXCEPTION 'PDC_826_CURRENT_HEAD_OR_VEHICLE_PRESTATE_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.import_pdc_authenticated_vehicle_email(p_idempotency_key text, p_source_hash text, p_evidence_hash text, p_source_uid text, p_sender_address text, p_authentication jsonb, p_source_received_at timestamp with time zone, p_subject text, p_email_vehicle jsonb, p_required_work jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
 v_actor_id uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_key text:=btrim(coalesce(p_idempotency_key,'')); v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));
 v_evidence_hash text:=lower(btrim(coalesce(p_evidence_hash,''))); v_source_uid text:=btrim(coalesce(p_source_uid,''));
 v_sender text:=lower(btrim(coalesce(p_sender_address,''))); v_auth jsonb:=coalesce(p_authentication,'{}'::jsonb);
 v_subject text:=btrim(coalesce(p_subject,'')); v_email jsonb:=coalesce(p_email_vehicle,'{}'::jsonb); v_work jsonb:=coalesce(p_required_work,'[]'::jsonb);
 v_historical_context jsonb:=coalesce(nullif(current_setting('pdc.historical_context',true),''),'{}')::jsonb;
 v_stock text; v_extracted_vin text; v_job_card text; v_request_hash text; v_required_work jsonb:='[]'::jsonb;
 v_work_name text; v_work_key text; v_backend_ids uuid[]; v_vehicle_ids uuid[]; v_record public.navision_backend_records%rowtype;
 v_activation public.navision_board_activations%rowtype; v_vehicle public.vehicles%rowtype; v_receipt public.pdc_authenticated_email_import_receipts%rowtype;
 v_work_before public.vehicle_work_items%rowtype; v_work_after public.vehicle_work_items%rowtype; v_response jsonb; v_before_vehicle jsonb;
begin
 if not public.pdc_monitor_staging_guard() or v_actor_id is null or v_actor_email='' then return public.navision_backend_response(false,'unauthorized'); end if;
 perform 1 from public.pdc_user_roles r where r.auth_user_id=v_actor_id and lower(r.email)=v_actor_email
   and r.role in('viewer','importer') and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'unauthorized'); end if;
 perform 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=v_actor_id and w.active and w.revoked_at is null for share;
 if not found then return public.navision_backend_response(false,'unauthorized'); end if;
 if v_key!~'^pdc-email-import-[A-Za-z0-9_-]{16,160}$' or v_source_hash!~'^[a-f0-9]{64}$' or v_evidence_hash!~'^[a-f0-9]{64}$'
    or length(v_source_uid) not between 1 and 100
    or v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
    or split_part(v_sender,'@',2) not in ('broometoyota.com.au','pmgwa.com.au')
    or jsonb_typeof(v_auth) is distinct from 'object'
    or (select array_agg(k order by k) from jsonb_object_keys(v_auth) k) is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
    or v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2) or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb
    or not (v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb)
    or length(v_subject) not between 1 and 300 or jsonb_typeof(v_email) is distinct from 'object'
    or (select array_agg(k order by k) from jsonb_object_keys(v_email) k) is distinct from array['cancelled','conflicts','customer_name','eta_to_kewdale','job_card_number','registration','stock_numbers','toyota_order_number','vehicle_description','vins']::text[]
    or jsonb_typeof(v_email->'stock_numbers') is distinct from 'array' or jsonb_array_length(v_email->'stock_numbers')<>1
    or jsonb_typeof(v_email->'vins') is distinct from 'array' or jsonb_array_length(v_email->'vins')>1
    or jsonb_typeof(v_email->'conflicts') is distinct from 'array' or jsonb_array_length(v_email->'conflicts')>0
    or v_email->'cancelled' is distinct from 'false'::jsonb or jsonb_typeof(v_work) is distinct from 'array' or jsonb_array_length(v_work)>10
    or exists(select 1 from jsonb_array_elements(v_work) x where jsonb_typeof(x)<>'string')
    or (select count(*) from jsonb_array_elements_text(v_work))<>(select count(distinct lower(btrim(x))) from jsonb_array_elements_text(v_work) x) then
   return public.navision_backend_response(false,'invalid_input');
 end if;
 v_stock:=public.normalize_vehicle_stock_number(v_email->'stock_numbers'->>0); v_extracted_vin:=nullif(public.normalize_vehicle_vin(v_email->'vins'->>0),'');
 v_job_card:=nullif(btrim(v_email->>'job_card_number'),'');
 if not public.is_real_vehicle_stock_number(v_stock) or length(coalesce(v_job_card,'')) not between 1 and 80 or v_job_card~'[[:cntrl:]]'
    or (v_extracted_vin is not null and not public.is_valid_vehicle_vin(v_extracted_vin)) then return public.navision_backend_response(false,'invalid_vehicle_evidence'); end if;
 if p_source_received_at is null or p_source_received_at>clock_timestamp()+interval '5 minutes' or (p_source_received_at<clock_timestamp()-interval '30 days' and not coalesce((v_historical_context->>'canonical_source_uid'=v_source_uid and v_historical_context->>'actor_id'=v_actor_id::text and public.pdc_historical_writer_authorized_773(v_historical_context->>'parent_source_hash',v_historical_context->>'provider_uid',lower(btrim(coalesce(v_historical_context->>'sender_email',''))),v_historical_context->'authentication',public.normalize_vehicle_stock_number(v_historical_context->>'stock_number'))),false))
    or concat_ws(' ',v_subject,v_email->>'vehicle_description',v_email->>'customer_name')~*'\m(cancelled|canceled|cancellation)\M' then
   return public.navision_backend_response(false,'evidence_expired_or_cancelled');
 end if;
 for v_work_name in select value from jsonb_array_elements_text(v_work) loop
   v_work_key:=case lower(btrim(v_work_name)) when 'bus4x4' then 'bus4x4' when 'tint' then 'tint' when 'hoist' then 'hoist'
     when 'fitting' then 'fitting' when 'fabrication' then 'fabrication' when 'electrical' then 'electrical' when 'tyre' then 'tyre'
     when 'sublet' then 'sublet' when 'pitinspection' then 'pitInspection' when 'parts' then 'PARTS' else null end;
   if v_work_key is null or (v_work_key<>'PARTS' and not exists(select 1 from public.workshop_stages s where s.work_key=v_work_key and s.active)) then
     return public.navision_backend_response(false,'invalid_required_work');
   end if;
   v_required_work:=v_required_work||jsonb_build_array(v_work_key);
 end loop;
 v_request_hash:=encode(extensions.digest(jsonb_build_object('contract_version',7,'actor_id',v_actor_id,'idempotency_key',v_key,
   'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'source_uid',v_source_uid,'sender_address',v_sender,'authentication',v_auth,
   'source_received_at',p_source_received_at,'subject',v_subject,'email_vehicle',v_email,'required_work',v_required_work)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('pdc-email-source:'||v_source_hash,0));
 perform pg_advisory_xact_lock(hashtextextended('pdc-email-import-receipt:'||v_actor_id::text||':'||v_key,0));
 select * into v_receipt from public.pdc_authenticated_email_import_receipts where actor_id=v_actor_id and idempotency_key=v_key for update;
 if found then
   if v_receipt.request_hash<>v_request_hash then return public.navision_backend_response(false,'idempotency_conflict'); end if;
   return v_receipt.response;
 end if;
 select * into v_receipt from public.pdc_authenticated_email_import_receipts where source_hash=v_source_hash for update;
 if found then
   if v_receipt.request_hash<>v_request_hash then return public.navision_backend_response(false,'source_reuse_conflict'); end if;
   return v_receipt.response;
 end if;
 if exists(select 1 from public.pdc_authenticated_email_batch_receipts r where r.source_hash=v_source_hash) then return public.navision_backend_response(false,'source_already_batch_consumed'); end if;
 perform 1
 from public.pdc_email_source_claims c
 join public.pdc_ai_intake_proposals p on p.proposal_id::text=c.proposal_ref
 where c.source_hash=v_source_hash and c.contract_name='pdc_ai_intake_063'
   and p.source_hash=v_source_hash and p.action_type='board_activate_only' and p.source_uid=v_source_uid
   and lower(p.sender_address)=v_sender and p.authentication=v_auth and p.source_received_at=p_source_received_at
   and p.subject=v_subject and public.normalize_vehicle_stock_number(p.stock_number)=v_stock
   and jsonb_typeof(p.observations->'required_work')='array'
   and jsonb_array_length(p.observations->'required_work')=jsonb_array_length(v_required_work)
   and not exists(
     select 1 from jsonb_array_elements_text(p.observations->'required_work') x
     cross join lateral (select case lower(btrim(x)) when 'bus4x4' then 'bus4x4' when 'tint' then 'tint' when 'hoist' then 'hoist'
       when 'fitting' then 'fitting' when 'fabrication' then 'fabrication' when 'electrical' then 'electrical' when 'tyre' then 'tyre'
       when 'sublet' then 'sublet' when 'pitinspection' then 'pitInspection' when 'parts' then 'PARTS' else null end as work_key) m
     where m.work_key is null or not (v_required_work ? m.work_key)
   )
 for update of c,p;
 if not found then return public.navision_backend_response(false,'source_proposal_binding_mismatch'); end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_backend_ids from public.navision_backend_records r
  where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047') and r.is_current and r.record_status='current'
    and public.is_real_vehicle_stock_number(r.normalized_data->>'batch') and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
 if cardinality(v_backend_ids)=0 then return public.navision_backend_response(false,'backend_stock_not_found');
 elsif cardinality(v_backend_ids)<>1 then return public.navision_backend_response(false,'backend_stock_ambiguous',jsonb_build_object('match_count',cardinality(v_backend_ids))); end if;
 select * into v_record from public.navision_backend_records where id=v_backend_ids[1] for update;
 select * into v_activation from public.navision_board_activations where backend_record_id=v_record.id for update;
 if not found then
  select * into v_vehicle from public.vehicles where id=v_record.canonical_vehicle_id for update;
  if not found or v_record.canonical_vehicle_id is null then return public.navision_backend_response(false,'active_canonical_link_required'); end if;
  if v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or not v_vehicle.visible_on_board then return public.navision_backend_response(false,'active_canonical_link_required'); end if;
  perform 1
  from public.pdc_ai_intake_proposals p
  join public.pdc_generic_current_navision_enrichment_receipts_312 g on g.proposal_id=p.proposal_id
  where p.source_hash=v_source_hash and p.source_uid=v_source_uid and p.backend_record_id=v_record.id
    and p.submitted_by=v_actor_id and p.status='rejected' and p.result->>'code'='automatically_closed_existing'
    and g.policy_version='312.1' and g.source_hash=v_source_hash and g.source_uid=v_source_uid
    and g.backend_record_id=v_record.id and g.vehicle_id=v_record.canonical_vehicle_id
    and g.actor_id=v_actor_id and g.actor_email=v_actor_email
    and g.response is not distinct from p.result
  for update of p;
  if not found then return public.navision_backend_response(false,'source_proposal_binding_mismatch'); end if;
 else
  if not v_activation.active or v_activation.completed_at is not null
     or public.normalize_vehicle_stock_number(v_activation.activated_stock_number) is distinct from v_stock
     or v_record.canonical_vehicle_id is distinct from v_activation.canonical_vehicle_id then return public.navision_backend_response(false,'active_canonical_link_required'); end if;
  select * into v_vehicle from public.vehicles where id=v_activation.canonical_vehicle_id for update;
 end if;
 if not found or v_vehicle.lifecycle_state<>'active' or v_vehicle.deleted_at is not null or v_vehicle.rft_collected_at is not null
    or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED' or not v_vehicle.visible_on_board
    or public.normalize_vehicle_stock_number(v_vehicle.stock_number)<>v_stock then return public.navision_backend_response(false,'protected_or_conflicting_vehicle'); end if;
 select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into v_vehicle_ids from (
   select v.id vehicle_id from public.vehicles v where v.deleted_at is null and v.stock_number_normalized=v_stock
   union all select a.vehicle_id from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock
 ) owners;
 if cardinality(v_vehicle_ids)<>1 or v_vehicle_ids[1]<>v_vehicle.id then return public.navision_backend_response(false,'operational_stock_owner_conflict'); end if;
 if v_extracted_vin is not null and v_vehicle.vin_normalized is distinct from v_extracted_vin then if public.pdc_authenticated_pdf_matches_navision_suffix_473(v_record.normalized_data,v_extracted_vin) and (v_vehicle.vin_normalized is null or v_vehicle.vin_normalized=public.normalize_vehicle_vin(v_record.normalized_data->>'vin')) then if exists(select 1 from public.vehicles x where x.id<>v_vehicle.id and x.vin_normalized=v_extracted_vin) or exists(select 1 from public.vehicle_aliases a where a.vehicle_id<>v_vehicle.id and a.active and a.alias_type_normalized='vin' and a.normalized_alias_value=v_extracted_vin) then return public.navision_backend_response(false,'operational_vin_owner_conflict'); end if; v_before_vehicle:=to_jsonb(v_vehicle); update public.vehicles set vin=v_extracted_vin,version=version+1,updated_by=v_actor_id,updated_at=clock_timestamp() where id=v_vehicle.id returning * into v_vehicle; insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) values('update','vehicles',v_vehicle.id,v_vehicle.id,v_actor_id,v_actor_email,v_before_vehicle,to_jsonb(v_vehicle),jsonb_build_object('source','authenticated_pdf_navision_suffix_473','source_hash',v_source_hash,'backend_record_id',v_record.id,'stock_number',v_stock,'navision_suffix',v_record.normalized_data->>'vin','pdf_full_vin_completed',true,'booking_created',false)); else return public.navision_backend_response(false,'vin_conflict_non_authoritative__op_'||coalesce(v_vehicle.vin_normalized,'NULL')||'__suffix_'||case when public.pdc_authenticated_pdf_matches_navision_suffix_473(v_record.normalized_data,v_extracted_vin) then 'true' else 'false' end,jsonb_build_object('operational_vin',v_vehicle.vin_normalized,'backend_vin',v_record.normalized_data->>'vin','backend_wmi',v_record.normalized_data->>'wmi','backend_vds',v_record.normalized_data->>'vdsNumber','backend_frame',v_record.normalized_data->>'frame','extracted_vin',v_extracted_vin,'suffix_match',public.pdc_authenticated_pdf_matches_navision_suffix_473(v_record.normalized_data,v_extracted_vin))); end if; end if;
 if nullif(btrim(coalesce(v_vehicle.job_card_number,'')),'') is not null and upper(btrim(v_vehicle.job_card_number))<>upper(v_job_card) then
   if not public.uid514_exact_canonical_import_compatibility_307(v_stock,v_extracted_vin,v_job_card,v_source_uid,v_source_hash,v_evidence_hash) then
     return public.navision_backend_response(false,'operational_job_card_conflict');
   end if;
   v_before_vehicle:=to_jsonb(v_vehicle);
   update public.vehicles set job_card_number=v_job_card,version=version+1,updated_by=v_actor_id,updated_at=clock_timestamp() where id=v_vehicle.id returning * into v_vehicle;
   insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
   values('update','vehicles',v_vehicle.id,v_vehicle.id,v_actor_id,v_actor_email,v_before_vehicle,to_jsonb(v_vehicle),
     jsonb_build_object('source','uid514_exact_canonical_import_compatibility_307','source_hash',v_source_hash,
       'historical_job_card_preserved','J139125093','incoming_job_card','J139125482','reinstatement_receipt_required',true,'no_booking',true));
 elsif nullif(btrim(coalesce(v_vehicle.job_card_number,'')),'') is null then
   v_before_vehicle:=to_jsonb(v_vehicle);
   update public.vehicles set job_card_number=v_job_card,version=version+1,updated_by=v_actor_id where id=v_vehicle.id returning * into v_vehicle;
   insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
   values('update','vehicles',v_vehicle.id,v_vehicle.id,v_actor_id,v_actor_email,v_before_vehicle,to_jsonb(v_vehicle),
     jsonb_build_object('source','pdc_monitor_canonical_stock_import_148','source_hash',v_source_hash,'jc_link_only',true,'no_booking',true));
 end if;
 for v_work_key in select value from jsonb_array_elements_text(v_required_work) loop
   v_work_before:=null; v_work_after:=null;
   select * into v_work_before from public.vehicle_work_items where vehicle_id=v_vehicle.id and work_key=v_work_key for update;
   insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
   values(v_vehicle.id,v_work_key,true,false,null,null,null,clock_timestamp())
   on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp()
     where not public.vehicle_work_items.completed and not public.vehicle_work_items.required returning * into v_work_after;
   if v_work_after.id is not null and (v_work_before.id is null or (not v_work_before.completed and not v_work_before.required)) then
     insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
     values(case when v_work_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,'vehicle_work_items',v_work_after.id,v_vehicle.id,
       v_actor_id,v_actor_email,case when v_work_before.id is null then null else to_jsonb(v_work_before) end,to_jsonb(v_work_after),
       jsonb_build_object('source','pdc_monitor_canonical_stock_import_148','source_hash',v_source_hash,'completed_work_reopened',false,'no_booking',true));
   end if;
 end loop;
 v_response:=public.navision_backend_response(true,'canonical_receipt_and_work_imported',jsonb_build_object('vehicle_id',v_vehicle.id,'backend_record_id',v_record.id,
   'stock_number',v_stock,'job_card_number',v_job_card,'required_work',v_required_work,'identity_source','navision_exact','booking_created',false,'completed_work_reopened',false));
 insert into public.pdc_authenticated_email_import_receipts(actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,
   source_received_at,stock_number,vin,backend_record_id,backend_record_version,vehicle_id,identity_source,required_work,response)
 values(v_actor_id,v_key,v_request_hash,v_source_hash,v_evidence_hash,v_source_uid,v_sender,p_source_received_at,v_stock,v_extracted_vin,v_record.id,v_record.version,v_vehicle.id,'navision_exact',v_required_work,v_response);
 return v_response;
exception when unique_violation then
 return public.navision_backend_response(false,'identity_or_receipt_conflict');
end
$function$
;
REVOKE ALL ON FUNCTION public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb) TO postgres;
DO $post$
DECLARE v text; owner_name text; secdef boolean; acl text;
BEGIN
 SELECT p.prosrc,p.proowner::regrole::text,p.prosecdef,p.proacl::text INTO v,owner_name,secdef,acl FROM pg_proc p WHERE p.oid='public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'91c4f74aa8be3a1a76aef8b06ce0e66772ed62163dd0a7d83e2a3bd873e49748' OR owner_name<>'postgres' OR NOT secdef OR acl<>'{postgres=X/postgres}' THEN RAISE EXCEPTION 'PDC_826_HISTORICAL_VEHICLE_FRESHNESS_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830247000','826_historical_vehicle_freshness_successor',ARRAY['preserve ordinary 30-day authenticated vehicle evidence expiry and cancellation rejection','allow only matching verified historical context with exact 773 authorization beyond 30 days','preserve exact identity evidence atomic rollback idempotency RLS/grants ten conflicts and zero mailbox','no historical Apply outbox mailbox task outbound or Production operation']);
COMMIT;
