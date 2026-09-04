-- STAGING ONLY: audited non-Navision Job Card VIN projection.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904010800-non-navision-vin',0));

DO $guard$
DECLARE v_head text;
BEGIN
 SELECT version INTO v_head FROM supabase_migrations.schema_migrations
 WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR NOT public.pdc_monitor_staging_guard()
    OR v_head IS DISTINCT FROM '20260904010700'
    OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904010700' AND name='deferred_pit_qc_finalization')
    OR to_regclass('public.pdc_non_navision_jobcard_receipts') IS NULL
    OR to_regprocedure('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)') IS NULL
    OR to_regprocedure('public.read_pdc_non_navision_jobcard_receipt(uuid)') IS NULL THEN
  RAISE EXCEPTION 'PDC_20260904010800_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
END
$guard$;

CREATE TABLE public.pdc_non_navision_vin_projection_receipts_20260904(
 receipt_id uuid PRIMARY KEY,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 source_receipt_id uuid NOT NULL REFERENCES public.pdc_non_navision_jobcard_receipts(receipt_id) ON DELETE RESTRICT,
 source_hash text NOT NULL CHECK(source_hash~'^[a-f0-9]{64}$'),
 source_attachment_id uuid NOT NULL REFERENCES public.ai_email_attachments(id) ON DELETE RESTRICT,
 expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
 vehicle_version_before integer NOT NULL CHECK(vehicle_version_before>0),
 vehicle_version_after integer NOT NULL CHECK(vehicle_version_after>=vehicle_version_before),
 vin_before text,
 vin_after text NOT NULL CHECK(vin_after~'^[A-HJ-NPR-Z0-9]{17}$'),
 source_provenance jsonb NOT NULL CHECK(jsonb_typeof(source_provenance)='object'),
 effective_provenance jsonb NOT NULL CHECK(jsonb_typeof(effective_provenance)='object'),
 before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
 after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 actor_role text NOT NULL CHECK(actor_role IN('importer','administrator')),
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key),
 UNIQUE(vehicle_id,source_receipt_id)
);
ALTER TABLE public.pdc_non_navision_vin_projection_receipts_20260904 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_non_navision_vin_projection_receipts_20260904 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_non_navision_vin_projection_receipts_20260904 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_non_navision_vin_projection_immutable_20260904()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $immutable$
BEGIN
 RAISE EXCEPTION 'PDC_20260904010800_VIN_PROJECTION_RECEIPT_IMMUTABLE' USING errcode='55000';
END
$immutable$;
REVOKE ALL ON FUNCTION public.pdc_non_navision_vin_projection_immutable_20260904() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_non_navision_vin_projection_receipts_immutable_20260904
BEFORE UPDATE OR DELETE ON public.pdc_non_navision_vin_projection_receipts_20260904
FOR EACH ROW EXECUTE FUNCTION public.pdc_non_navision_vin_projection_immutable_20260904();

CREATE FUNCTION public.read_pdc_non_navision_vin_projection_20260904(p_receipt_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE uid uuid:=auth.uid();r public.pdc_non_navision_vin_projection_receipts_20260904%rowtype;live public.vehicles%rowtype;
BEGIN
 IF uid IS NULL OR NOT public.pdc_monitor_staging_guard() THEN
  RETURN public.navision_backend_response(false,'unauthorized');
 END IF;
 SELECT * INTO r FROM public.pdc_non_navision_vin_projection_receipts_20260904
 WHERE receipt_id=p_receipt_id AND actor_id=uid;
 IF NOT FOUND THEN RETURN public.navision_backend_response(false,'receipt_not_found');END IF;
 SELECT * INTO live FROM public.vehicles WHERE id=r.vehicle_id;
 IF NOT FOUND THEN RETURN public.navision_backend_response(false,'non_navision_vin_projection_readback_drift');END IF;
 RETURN public.navision_backend_response(true,'non_navision_vin_projection_receipt',jsonb_build_object(
  'receipt_id',r.receipt_id,'vehicle_id',r.vehicle_id,'source_receipt_id',r.source_receipt_id,
  'source_hash',r.source_hash,'source_attachment_id',r.source_attachment_id,
  'expected_vehicle_version',r.expected_vehicle_version,'vehicle_version_before',r.vehicle_version_before,
  'vehicle_version_after',r.vehicle_version_after,'vin_before',r.vin_before,'vin_after',r.vin_after,
  'source_provenance',r.source_provenance,'effective_provenance',r.effective_provenance,
  'before',r.before_state,'after',r.after_state,
  'authoritative_vehicle',jsonb_build_object('id',live.id,'version',live.version,'stock_number',live.stock_number,
   'vin',live.vin,'job_card_number',live.job_card_number,'registration',live.registration,'customer_name',live.customer_name,
   'current_location',live.current_location,'lifecycle_state',live.lifecycle_state,'visible_on_board',live.visible_on_board),
  'replay',false));
END
$read$;
REVOKE ALL ON FUNCTION public.read_pdc_non_navision_vin_projection_20260904(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_non_navision_vin_projection_20260904(uuid) TO authenticated;

CREATE FUNCTION public.project_pdc_non_navision_jobcard_vin_20260904(
 p_vehicle_id uuid,
 p_expected_vehicle_version integer,
 p_source_receipt_id uuid,
 p_expected_source_hash text,
 p_vin text,
 p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $project$
DECLARE
 uid uuid:=auth.uid();actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));actor_role text;
 v_vin text:=upper(btrim(coalesce(p_vin,'')));v_source text:=lower(btrim(coalesce(p_expected_source_hash,'')));
 source_receipt public.pdc_non_navision_jobcard_receipts%rowtype;source_import public.pdc_authenticated_email_import_receipts%rowtype;
 source_intake public.ai_email_intake%rowtype;source_attachment public.ai_email_attachments%rowtype;
 before_vehicle public.vehicles%rowtype;after_vehicle public.vehicles%rowtype;prior public.pdc_non_navision_vin_projection_receipts_20260904%rowtype;
 source_provenance jsonb;effective_provenance jsonb;before_state jsonb;after_state jsonb;
 payload jsonb;request_sha text;receipt uuid:=gen_random_uuid();result jsonb;now_at timestamptz:=clock_timestamp();
BEGIN
 SELECT r.role::text,lower(btrim(r.email)) INTO actor_role,actor_email FROM public.pdc_user_roles r
 WHERE r.auth_user_id=uid AND r.active AND r.account_status='approved' AND r.role::text IN('importer','administrator')
 ORDER BY r.updated_at DESC LIMIT 1;
 IF NOT public.pdc_monitor_staging_guard() OR uid IS NULL OR actor_role IS NULL OR p_vehicle_id IS NULL
    OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_source_receipt_id IS NULL
    OR v_source!~'^[a-f0-9]{64}$' OR v_vin!~'^[A-HJ-NPR-Z0-9]{17}$'
    OR NOT public.is_valid_vehicle_vin(v_vin) OR p_idempotency_key IS NULL THEN
  RETURN public.navision_backend_response(false,'non_navision_vin_projection_invalid_input');
 END IF;
 IF actor_role='importer' AND NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
   WHERE w.user_id=uid AND w.active AND w.revoked_at IS NULL) THEN
  RETURN public.navision_backend_response(false,'unauthorized');
 END IF;
 payload:=jsonb_build_object('contract','pdc-non-navision-jobcard-vin-projection-20260904','vehicle_id',p_vehicle_id,
  'expected_vehicle_version',p_expected_vehicle_version,'source_receipt_id',p_source_receipt_id,
  'expected_source_hash',v_source,'vin',v_vin,'idempotency_key',p_idempotency_key,'actor_id',uid);
 request_sha:=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-20260904010800-idempotency:'||uid::text||':'||p_idempotency_key::text,0));
 SELECT * INTO prior FROM public.pdc_non_navision_vin_projection_receipts_20260904
 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF prior.request_sha256<>request_sha THEN
   RETURN public.navision_backend_response(false,'non_navision_vin_projection_replay_mismatch');
  END IF;
  RETURN jsonb_set(prior.response,'{data,replay}','true'::jsonb,false);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('vehicle-master:vin:'||v_vin,0));
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-20260904010800-vehicle:'||p_vehicle_id::text,0));
 LOCK TABLE public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicles IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicle_aliases IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO source_receipt FROM public.pdc_non_navision_jobcard_receipts
 WHERE receipt_id=p_source_receipt_id FOR SHARE;
 SELECT * INTO source_import FROM public.pdc_authenticated_email_import_receipts
 WHERE receipt_id=source_receipt.canonical_import_receipt_id FOR SHARE;
 SELECT * INTO source_intake FROM public.ai_email_intake WHERE id=source_receipt.intake_id FOR SHARE;
 SELECT * INTO source_attachment FROM public.ai_email_attachments WHERE id=source_receipt.attachment_id FOR SHARE;
 IF source_receipt.receipt_id IS NULL OR source_import.receipt_id IS NULL OR source_intake.id IS NULL OR source_attachment.id IS NULL
    OR source_receipt.actor_id<>uid
    OR source_receipt.vehicle_id<>p_vehicle_id OR source_import.vehicle_id<>p_vehicle_id
    OR source_receipt.source_hash<>v_source OR source_import.source_hash<>v_source OR lower(source_intake.source_hash)<>v_source
    OR source_attachment.intake_id<>source_intake.id OR lower(source_attachment.source_hash)<>source_receipt.attachment_hash
    OR source_attachment.text_extraction_status<>'extracted'
    OR public.pdc_email_exact_identifier_token_count(source_attachment.extracted_text,v_vin)<>1
    OR upper(btrim(coalesce(source_intake.extracted_data#>>'{source_interpretation,vehicle,vin}','')))<>v_vin THEN
  RETURN public.navision_backend_response(false,'non_navision_vin_projection_source_mismatch');
 END IF;
 SELECT * INTO prior FROM public.pdc_non_navision_vin_projection_receipts_20260904
 WHERE vehicle_id=p_vehicle_id AND source_receipt_id=p_source_receipt_id;
 IF FOUND THEN
  RETURN public.navision_backend_response(false,'non_navision_vin_already_projected');
 END IF;
 SELECT * INTO before_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR before_vehicle.deleted_at IS NOT NULL OR before_vehicle.lifecycle_state<>'active'
    OR NOT before_vehicle.visible_on_board OR before_vehicle.board_purged_at IS NOT NULL
    OR before_vehicle.source_system<>'authenticated_email' OR before_vehicle.source_record_id<>source_intake.id::text
    OR upper(btrim(coalesce(before_vehicle.job_card_number,'')))<>upper(btrim(coalesce(source_intake.extracted_data#>>'{source_interpretation,vehicle,job_card_number}',''))) THEN
  RETURN public.navision_backend_response(false,'non_navision_vin_projection_vehicle_mismatch');
 END IF;
 IF before_vehicle.version<>p_expected_vehicle_version THEN
  RETURN public.navision_backend_response(false,'vehicle_version_conflict',jsonb_build_object('vehicle_id',before_vehicle.id,'vehicle_version',before_vehicle.version));
 END IF;
 IF before_vehicle.vin IS NOT NULL AND before_vehicle.vin_normalized<>v_vin THEN
  RETURN public.navision_backend_response(false,'non_navision_existing_vin_mismatch');
 END IF;
 IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id<>p_vehicle_id AND v.vin_normalized=v_vin)
    OR EXISTS(SELECT 1 FROM public.vehicle_aliases a WHERE a.vehicle_id<>p_vehicle_id AND a.alias_type_normalized='vin' AND a.normalized_alias_value=v_vin)
    OR EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.is_current AND n.record_status='current'
      AND public.normalize_vehicle_vin(coalesce(n.normalized_data->>'vin',n.normalized_data->>'vin_number'))=v_vin)
    OR EXISTS(SELECT 1 FROM public.pdc_authenticated_email_import_receipts i WHERE i.vehicle_id<>p_vehicle_id AND public.normalize_vehicle_vin(i.vin)=v_vin) THEN
  RETURN public.navision_backend_response(false,'non_navision_vin_collision');
 END IF;
 source_provenance:=coalesce(source_intake.extracted_data->'source_provenance','{}'::jsonb)
  ||jsonb_build_object('source_hash',v_source,'attachment_hash',source_receipt.attachment_hash,
    'source_receipt_id',source_receipt.receipt_id,'canonical_import_receipt_id',source_receipt.canonical_import_receipt_id,
    'authenticated_source_vin',v_vin);
 effective_provenance:=coalesce(source_intake.extracted_data->'effective_provenance','{}'::jsonb)
  ||jsonb_build_object('vin',jsonb_build_object('value',v_vin,'authority','authenticated_non_navision_job_card',
    'source_receipt_id',source_receipt.receipt_id));
 before_state:=jsonb_build_object('id',before_vehicle.id,'version',before_vehicle.version,'stock_number',before_vehicle.stock_number,
  'vin',before_vehicle.vin,'job_card_number',before_vehicle.job_card_number,'registration',before_vehicle.registration,
  'customer_name',before_vehicle.customer_name,'current_location',before_vehicle.current_location,'lifecycle_state',before_vehicle.lifecycle_state,
  'visible_on_board',before_vehicle.visible_on_board,'salesperson_id',before_vehicle.salesperson_id,'salesperson_reference',before_vehicle.salesperson_reference,
  'source_system',before_vehicle.source_system,'source_record_id',before_vehicle.source_record_id,'source_payload',before_vehicle.source_payload);
 IF before_vehicle.vin IS NULL THEN
  UPDATE public.vehicles SET vin=v_vin,version=version+1,updated_at=now_at,updated_by=uid,
   source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
    'authenticated_source_vin',v_vin,'vin_projection_source_receipt_id',source_receipt.receipt_id,
    'source_provenance',source_provenance,'effective_provenance',effective_provenance)
  WHERE id=p_vehicle_id RETURNING * INTO after_vehicle;
 ELSE
  after_vehicle:=before_vehicle;
 END IF;
 after_state:=jsonb_build_object('id',after_vehicle.id,'version',after_vehicle.version,'stock_number',after_vehicle.stock_number,
  'vin',after_vehicle.vin,'job_card_number',after_vehicle.job_card_number,'registration',after_vehicle.registration,
  'customer_name',after_vehicle.customer_name,'current_location',after_vehicle.current_location,'lifecycle_state',after_vehicle.lifecycle_state,
  'visible_on_board',after_vehicle.visible_on_board,'salesperson_id',after_vehicle.salesperson_id,'salesperson_reference',after_vehicle.salesperson_reference,
  'source_system',after_vehicle.source_system,'source_record_id',after_vehicle.source_record_id,'source_payload',after_vehicle.source_payload);
 result:=public.navision_backend_response(true,'non_navision_vin_projected',jsonb_build_object(
  'receipt_id',receipt,'vehicle_id',after_vehicle.id,'source_receipt_id',source_receipt.receipt_id,'source_hash',v_source,
  'expected_vehicle_version',p_expected_vehicle_version,'vehicle_version_before',before_vehicle.version,'vehicle_version_after',after_vehicle.version,
  'vin_before',before_vehicle.vin,'vin_after',after_vehicle.vin,'source_provenance',source_provenance,
  'effective_provenance',effective_provenance,'before',before_state,'after',after_state,'replay',false));
 INSERT INTO public.pdc_non_navision_vin_projection_receipts_20260904(
  receipt_id,vehicle_id,source_receipt_id,source_hash,source_attachment_id,expected_vehicle_version,
  vehicle_version_before,vehicle_version_after,vin_before,vin_after,source_provenance,effective_provenance,
  before_state,after_state,actor_id,actor_email,actor_role,idempotency_key,request_sha256,response)
 VALUES(receipt,after_vehicle.id,source_receipt.receipt_id,v_source,source_attachment.id,p_expected_vehicle_version,
  before_vehicle.version,after_vehicle.version,before_vehicle.vin,after_vehicle.vin,source_provenance,effective_provenance,
  before_state,after_state,uid,actor_email,actor_role,p_idempotency_key,request_sha,result);
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','pdc_non_navision_vin_projection_receipts_20260904',receipt,after_vehicle.id,uid,actor_email,before_state,after_state,
  jsonb_build_object('source','project_pdc_non_navision_jobcard_vin_20260904','source_receipt_id',source_receipt.receipt_id,
   'source_hash',v_source,'idempotency_key',p_idempotency_key,'lifecycle_mutated',false,'work_mutated',false,
   'booking_mutated',false,'completion_mutated',false,'email_mutated',false));
 RETURN result;
END
$project$;
REVOKE ALL ON FUNCTION public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid) TO authenticated;
COMMENT ON FUNCTION public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid) IS
 'STAGING-only audited source-receipt-bound VIN projection for an exact active non-Navision Job Card vehicle; expected version, immutable receipt, fail-closed all-state collision checks, and no lifecycle/work/booking/completion/email action.';

-- Separate stock lookup identity from the optional authenticated source VIN in
-- the private non-Navision processor. VIN-only identity remains supported.
DO $processor_patch$
DECLARE d text;n text;
BEGIN
 d:=pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure);n:=d;
 n:=replace(n,
  $old$v_stock_candidates uuid[];v_vin_candidates uuid[];v_job_candidates uuid[];v_stock_navision uuid[];v_vin_navision uuid[];v_job_navision uuid[];$old$,
  $new$v_stock_candidates uuid[];v_vin_candidates uuid[];v_job_candidates uuid[];v_stock_navision uuid[];v_vin_navision uuid[];v_job_navision uuid[];
 v_vin_all_vehicle_ids uuid[]:='{}'::uuid[];v_vin_all_alias_vehicle_ids uuid[]:='{}'::uuid[];v_vin_backend_ids uuid[]:='{}'::uuid[];$new$);
 n:=replace(n,
  $old$if cardinality(v_stock_navision)>1 or cardinality(v_vin_navision)>1 or cardinality(v_job_navision)>1 then$old$,
  $new$select coalesce(array_agg(distinct b.id order by b.id),'{}'::uuid[]) into v_vin_backend_ids
 from public.navision_backend_records b where b.is_current and b.record_status='current' and v_vin is not null
  and public.normalize_vehicle_vin(coalesce(b.normalized_data->>'vin',b.normalized_data->>'vin_number'))=v_vin;
 if cardinality(v_vin_backend_ids)>0 then
  return public.navision_backend_response(false,'non_navision_vin_collision',jsonb_build_object('surface','current_backend','candidate_count',cardinality(v_vin_backend_ids)));
 end if;
 if cardinality(v_stock_navision)>1 or cardinality(v_vin_navision)>1 or cardinality(v_job_navision)>1 then$new$);
 n:=replace(n,
  $old$if cardinality(v_stock_candidates)+cardinality(v_vin_candidates)+cardinality(v_job_candidates)=0 then
  v_candidates:='{}'::uuid[];
 elsif (v_stock is not null and cardinality(v_stock_candidates)<>1)
    or (v_vin is not null and cardinality(v_vin_candidates)<>1) or cardinality(v_job_candidates)<>1 then
  return public.navision_backend_response(false,'non_navision_vehicle_identity_disagreement');
 else
  v_candidates:=v_job_candidates;
  if (v_stock is not null and v_stock_candidates[1]<>v_candidates[1])
     or (v_vin is not null and v_vin_candidates[1]<>v_candidates[1]) then
   return public.navision_backend_response(false,'non_navision_vehicle_identity_disagreement');
  end if;
 end if;$old$,
  $new$select coalesce(array_agg(distinct v.id order by v.id),'{}'::uuid[]) into v_vin_all_vehicle_ids
 from public.vehicles v where v_vin is not null and v.vin_normalized=v_vin;
 select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id),'{}'::uuid[]) into v_vin_all_alias_vehicle_ids
 from public.vehicle_aliases a where v_vin is not null and a.alias_type_normalized='vin' and a.normalized_alias_value=v_vin;
 if cardinality(v_stock_candidates)+cardinality(v_vin_candidates)+cardinality(v_job_candidates)=0 then
  if cardinality(v_vin_all_vehicle_ids)>0 or cardinality(v_vin_all_alias_vehicle_ids)>0 then
   return public.navision_backend_response(false,'non_navision_vin_collision',jsonb_build_object('surface','canonical_or_alias'));
  end if;
  v_candidates:='{}'::uuid[];
 elsif v_stock is not null then
  if cardinality(v_stock_candidates)<>1 or cardinality(v_job_candidates)<>1 or v_stock_candidates[1]<>v_job_candidates[1] then
   return public.navision_backend_response(false,'non_navision_vehicle_identity_disagreement');
  end if;
  v_candidates:=v_stock_candidates;
  if v_vin is not null and (
     exists(select 1 from unnest(v_vin_all_vehicle_ids) x where x<>v_candidates[1])
     or exists(select 1 from unnest(v_vin_all_alias_vehicle_ids) x where x<>v_candidates[1])) then
   return public.navision_backend_response(false,'non_navision_vin_collision',jsonb_build_object('surface','canonical_or_alias'));
  end if;
  if v_vin is not null and not exists(select 1 from public.vehicles v where v.id=v_candidates[1] and v.vin_normalized=v_vin) then
   return public.navision_backend_response(false,'non_navision_existing_vin_mismatch');
  end if;
 else
  if cardinality(v_vin_candidates)<>1 or cardinality(v_job_candidates)<>1 or v_vin_candidates[1]<>v_job_candidates[1] then
   return public.navision_backend_response(false,'non_navision_vehicle_identity_disagreement');
  end if;
  v_candidates:=v_vin_candidates;
  if exists(select 1 from unnest(v_vin_all_vehicle_ids) x where x<>v_candidates[1])
     or exists(select 1 from unnest(v_vin_all_alias_vehicle_ids) x where x<>v_candidates[1]) then
   return public.navision_backend_response(false,'non_navision_vin_collision',jsonb_build_object('surface','canonical_or_alias'));
  end if;
 end if;$new$);
 n:=replace(n,
  $old$jsonb_build_object('contract','pmb-non-navision-jobcard-161','source_hash',v_source,'attachment_hash',lower(v_attachment.source_hash))$old$,
  $new$jsonb_build_object('contract','pmb-non-navision-jobcard-161','source_hash',v_source,'attachment_hash',lower(v_attachment.source_hash),
   'lookup_identity',case when v_stock is not null then jsonb_build_object('type','stock_number','value',v_stock) else jsonb_build_object('type','vin','value',v_vin) end,
   'authenticated_source_vin',v_vin,
   'source_provenance',coalesce(v_intake.extracted_data->'source_provenance','{}'::jsonb)
     ||jsonb_build_object('source_receipt_id',v_receipt_id),
   'effective_provenance',coalesce(v_intake.extracted_data->'effective_provenance','{}'::jsonb)
     ||jsonb_build_object('vin',case when v_vin is null then null else jsonb_build_object(
       'value',v_vin,'authority','authenticated_non_navision_job_card','source_receipt_id',v_receipt_id) end))$new$);
 n:=replace(n,
  $old$v_result:=public.navision_backend_response(true,'non_navision_jobcard_imported',jsonb_build_object('vehicle_id',v_vehicle.id,'vehicle_created',v_created,
  'current_location',v_vehicle.current_location,'operation_count',jsonb_array_length(v_lines),'booking_created',false,'completion_created',false));$old$,
  $new$v_result:=public.navision_backend_response(true,'non_navision_jobcard_imported',jsonb_build_object('vehicle_id',v_vehicle.id,'vehicle_created',v_created,
  'current_location',v_vehicle.current_location,'operation_count',jsonb_array_length(v_lines),'booking_created',false,'completion_created',false,
  'source_provenance',coalesce(v_intake.extracted_data->'source_provenance','{}'::jsonb)
    ||jsonb_build_object('source_receipt_id',v_receipt_id),
  'effective_provenance',coalesce(v_intake.extracted_data->'effective_provenance','{}'::jsonb)
    ||jsonb_build_object('vin',case when v_vin is null then null else jsonb_build_object(
      'value',v_vin,'authority','authenticated_non_navision_job_card','source_receipt_id',v_receipt_id) end)));$new$);
 IF n=d OR n NOT LIKE '%v_vin_all_vehicle_ids%' OR n NOT LIKE '%non_navision_existing_vin_mismatch%'
    OR n NOT LIKE '%authenticated_source_vin%' OR n NOT LIKE '%current_backend%' THEN
  RAISE EXCEPTION 'PDC_20260904010800_PROCESSOR_PATCH_ANCHOR_MISSING' USING errcode='55000';
 END IF;
 EXECUTE n;
END
$processor_patch$;
REVOKE ALL ON FUNCTION public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text) FROM public,anon,authenticated,service_role;

-- Extend actor-owned import read-back with normalized VIN and immutable source/effective provenance.
DO $reader_patch$
DECLARE d text;n text;
BEGIN
 d:=pg_get_functiondef('public.read_pdc_non_navision_jobcard_receipt(uuid)'::regprocedure);n:=d;
 n:=replace(n,
  $old$'initial_location',case when v_r.vehicle_created then 'YH' else null end,$old$,
  $new$'initial_location',case when v_r.vehicle_created then 'YH' else null end,
  'stock_number',(select i.stock_number from public.pdc_authenticated_email_import_receipts i where i.receipt_id=v_r.canonical_import_receipt_id),
  'source_vin',(select i.vin from public.pdc_authenticated_email_import_receipts i where i.receipt_id=v_r.canonical_import_receipt_id),
  'canonical_vin',(select v.vin from public.vehicles v where v.id=v_r.vehicle_id),
  'source_provenance',(select coalesce(
    (select p.source_provenance from public.pdc_non_navision_vin_projection_receipts_20260904 p
      where p.source_receipt_id=v_r.receipt_id and p.vehicle_id=v_r.vehicle_id order by p.created_at desc limit 1),
    v_r.response#>'{data,source_provenance}',x.extracted_data->'source_provenance','{}'::jsonb) from public.ai_email_intake x where x.id=v_r.intake_id),
  'effective_provenance',(select coalesce(
    (select p.effective_provenance from public.pdc_non_navision_vin_projection_receipts_20260904 p
      where p.source_receipt_id=v_r.receipt_id and p.vehicle_id=v_r.vehicle_id order by p.created_at desc limit 1),
    v_r.response#>'{data,effective_provenance}',x.extracted_data->'effective_provenance','{}'::jsonb) from public.ai_email_intake x where x.id=v_r.intake_id),$new$);
 IF n=d OR n NOT LIKE '%''source_vin''%' OR n NOT LIKE '%''canonical_vin''%' OR n NOT LIKE '%''source_provenance''%' THEN
  RAISE EXCEPTION 'PDC_20260904010800_READER_PATCH_ANCHOR_MISSING' USING errcode='55000';
 END IF;
 EXECUTE n;
END
$reader_patch$;
REVOKE ALL ON FUNCTION public.read_pdc_non_navision_jobcard_receipt(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_non_navision_jobcard_receipt(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) TO authenticated;

DO $post$
DECLARE inner_def text;reader_def text;
BEGIN
 inner_def:=pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure);
 reader_def:=pg_get_functiondef('public.read_pdc_non_navision_jobcard_receipt(uuid)'::regprocedure);
 IF NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_non_navision_vin_projection_receipts_20260904'::regclass)
    OR has_table_privilege('authenticated','public.pdc_non_navision_vin_projection_receipts_20260904','select')
    OR has_function_privilege('anon','public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid)','execute')
    OR has_function_privilege('service_role','public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid)','execute')
    OR NOT has_function_privilege('authenticated','public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid)','execute')
    OR has_function_privilege('authenticated','public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)','execute')
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='pdc_non_navision_vin_projection_receipts_immutable_20260904' AND tgenabled='O')
    OR inner_def NOT LIKE '%non_navision_existing_vin_mismatch%' OR inner_def NOT LIKE '%authenticated_source_vin%'
    OR reader_def NOT LIKE '%''source_vin''%' OR reader_def NOT LIKE '%''canonical_vin''%'
    OR reader_def NOT LIKE '%pdc_non_navision_vin_projection_receipts_20260904%' THEN
  RAISE EXCEPTION 'PDC_20260904010800_POSTCONDITION_FAILED' USING errcode='55000';
 END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904010800','non_navision_jobcard_vin_projection',ARRAY[
 'Separate stock lookup identity from at most one normalized authenticated source VIN; retain VIN-only and absent-VIN behavior',
 'Project source VIN for new non-Navision creation only after locked collision checks across active/deleted vehicles, all aliases and current backend identities',
 'Reject existing VIN mismatch and exact replay payload mismatch; never overwrite another source identity',
 'Add source/effective provenance to immutable import projection and authoritative actor-owned read-back',
 'Add audited expected-version/source-receipt/idempotency-bound correction action and immutable forced-RLS receipt',
 'No lifecycle, work, booking, completion, Gmail, outbound email or Production mutation'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
