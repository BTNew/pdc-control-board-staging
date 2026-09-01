-- STAGING ONLY 20260901060000: final typed-boundary hardening.
-- Appends to 0500. No production objects, raw plan-driven SQL, generic DML,
-- service-role authority, receipt rewrites or operational-history rewrites.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901060000-typed-action-boundary-hardening',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260901050000' AND name='pdc_email_ai_typed_action_v2_contract_binding_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901060000')
     OR to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_operation_update_20260901(uuid,integer,text,text,text,text,text,numeric)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901060000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_taxonomy_disposition_20260901(
  p_taxonomy_version text,p_description text,p_work_key text
) RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $taxonomy$
DECLARE d text:=lower(regexp_replace(coalesce(p_description,''),'[^a-z0-9]+',' ','g')); k text:=upper(btrim(coalesce(p_work_key,'')));
BEGIN
  IF p_taxonomy_version !~ '^pdc-operation-taxonomy-(proposed|approved)/v[0-9]+$' THEN RETURN 'unsupported'; END IF;
  IF k NOT IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET') THEN RETURN 'unsupported'; END IF;
  IF d~'(^| )(unresolved|no operation rows|identity conflict)( |$)' THEN RETURN 'unsupported'; END IF;
  IF d~'(^| )(signage|decal|decals|safety stripping|logo|tare|gcm)( |$)' THEN RETURN 'review'; END IF;
  IF k='SUBLET' THEN RETURN 'unsupported'; END IF;
  IF d~'wheel nut indicator' AND k<>'TYRE' THEN RETURN 'conflict'; END IF;
  IF d~'fire extinguisher' AND k<>'FABRICATION' THEN RETURN 'conflict'; END IF;
  IF d~'(^| )(arb )?long (range|ranger)( fuel)? tank( |$)' AND k<>'HOIST' THEN RETURN 'conflict'; END IF;
  IF d~'(^| )12v( |$).*socket|(^| )socket( |$).*12v( |$)' THEN RETURN 'review'; END IF;
  IF d~'safety triangle' OR d~'weather shields?' THEN RETURN 'review'; END IF;
  RETURN 'classified';
END $taxonomy$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_taxonomy_disposition_20260901(text,text,text) FROM public,anon,authenticated,service_role;

-- The validator is the single PostgreSQL-owned taxonomy and payload boundary.
-- Review/unsupported/conflict operation evidence may retain unknown hours, but
-- only planned rows can dispatch and planned rows always require numeric hours.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_validate_v2_instruction_20260901(p_item jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $validate$
DECLARE p jsonb; k text; expected_taxonomy text;
BEGIN
  IF jsonb_typeof(p_item)<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_item) x) IS DISTINCT FROM ARRAY['action_type','audit_event_ref','decision_disposition','evidence_refs','expected_state','identity','instruction_id','payload','provenance','reason','required_evidence','vehicle_id']::text[]
     OR p_item->>'action_type' NOT IN('activate_vehicle','operation_add','operation_update','parts_eta_set','parts_complete','booking_set','booking_move','booking_cancel','required_work_set','work_complete','note_append','location_set','rft_transfer','rft_collect')
     OR p_item->>'decision_disposition' NOT IN('planned','review','unsupported','conflict')
     OR p_item->>'vehicle_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR nullif(btrim(p_item->>'instruction_id'),'') IS NULL
     OR jsonb_typeof(p_item->'payload')<>'object'
     OR jsonb_typeof(p_item->'evidence_refs')<>'array'
     OR jsonb_array_length(p_item->'evidence_refs') NOT BETWEEN 1 AND 20
     OR jsonb_typeof(p_item->'identity')<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_item->'identity') x) IS DISTINCT FROM ARRAY['backend_record_id','stock_number','vehicle_id','vin']::text[]
     OR p_item->'identity'->>'vehicle_id'<>p_item->>'vehicle_id'
     OR (p_item->'identity'->>'stock_number' IS NULL AND p_item->'identity'->>'vin' IS NULL)
     OR (p_item->'identity'->>'backend_record_id' IS NOT NULL AND p_item->'identity'->>'backend_record_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
     OR (p_item->'identity'->>'stock_number' IS NOT NULL AND p_item->'identity'->>'stock_number' !~ '^[A-Z0-9][A-Z0-9-]{3,79}$')
     OR (p_item->'identity'->>'vin' IS NOT NULL AND p_item->'identity'->>'vin' !~ '^[A-HJ-NPR-Z0-9]{17}$')
     OR jsonb_typeof(p_item->'expected_state')<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_item->'expected_state') x) IS DISTINCT FROM ARRAY['backend_revision','vehicle_version']::text[]
     OR p_item->'expected_state'->>'vehicle_version' !~ '^[1-9][0-9]*$'
     OR p_item->'expected_state'->>'backend_revision' !~ '^[0-9]+$'
     OR jsonb_typeof(p_item->'provenance')<>'object'
     OR jsonb_typeof(p_item->'required_evidence')<>'array'
     OR nullif(btrim(p_item->>'audit_event_ref'),'') IS NULL
     OR nullif(btrim(p_item->>'reason'),'') IS NULL
  THEN RETURN false; END IF;

  p:=p_item->'payload';
  IF p_item->>'action_type' IN('operation_add','operation_update') THEN
    expected_taxonomy:=public.pdc_email_ai_successor_taxonomy_disposition_20260901(p->>'taxonomy_version',p->>'description',p->>'work_key');
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['description','estimated_hours','operation_no','source_row_no','source_uid','taxonomy_disposition','taxonomy_version','work_key']::text[]
       OR p->>'operation_no' !~ '^OP[1-9][0-9]{0,2}$'
       OR p->>'source_row_no' !~ '^[1-9][0-9]*$'
       OR p->>'taxonomy_version'<>'pdc-operation-taxonomy-proposed/v1'
       OR p->>'taxonomy_disposition' NOT IN('classified','review','unsupported','conflict')
       OR p->>'taxonomy_disposition'<>expected_taxonomy
       OR nullif(btrim(p->>'source_uid'),'') IS NULL
       OR length(p->>'description') NOT BETWEEN 1 AND 500
       OR p->>'description'<>btrim(p->>'description')
       OR NOT ((jsonb_typeof(p->'estimated_hours')='number' AND (p->>'estimated_hours')::numeric BETWEEN 0 AND 999.99)
               OR (p_item->>'decision_disposition'<>'planned' AND jsonb_typeof(p->'estimated_hours')='null'))
    THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='activate_vehicle' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['backend_record_id','job_card_number','stock_number','vin']::text[]
       OR p->>'backend_record_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       OR p->>'stock_number' !~ '^[A-Z0-9][A-Z0-9-]{3,79}$'
       OR (p->>'vin' IS NOT NULL AND p->>'vin' !~ '^[A-HJ-NPR-Z0-9]{17}$')
       OR (p->>'job_card_number' IS NOT NULL AND nullif(btrim(p->>'job_card_number'),'') IS NULL)
    THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='parts_eta_set' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['eta']::text[]
       OR (jsonb_typeof(p->'eta')<>'null' AND p->>'eta' !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$') THEN RETURN false; END IF;
  ELSIF p_item->>'action_type' IN('parts_complete','rft_transfer','rft_collect') THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['confirmed']::text[] OR jsonb_typeof(p->'confirmed')<>'boolean' OR p->>'confirmed'<>'true' THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='booking_set' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['bay_number','duration_minutes','scheduled_start_at','stage_code','technician_id']::text[]
       OR p->>'bay_number' !~ '^[1-9][0-9]*$' OR p->>'duration_minutes' !~ '^[1-9][0-9]*$' OR (p->>'duration_minutes')::integer<60
       OR p->>'scheduled_start_at' !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T' OR nullif(btrim(p->>'stage_code'),'') IS NULL
       OR (p->>'technician_id' IS NOT NULL AND p->>'technician_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='booking_move' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['booking_id','bay_number','duration_minutes','expected_booking_version','override_reason','scheduled_start_at','stage_code']::text[]
       OR p->>'booking_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' OR p->>'expected_booking_version' !~ '^[1-9][0-9]*$'
       OR p->>'bay_number' !~ '^[1-9][0-9]*$' OR p->>'duration_minutes' !~ '^[1-9][0-9]*$' OR (p->>'duration_minutes')::integer<60
       OR p->>'scheduled_start_at' !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T' OR nullif(btrim(p->>'stage_code'),'') IS NULL
       OR (p->>'override_reason' IS NOT NULL AND nullif(btrim(p->>'override_reason'),'') IS NULL) THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='booking_cancel' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['booking_id','expected_booking_version','reason']::text[]
       OR p->>'booking_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' OR p->>'expected_booking_version' !~ '^[1-9][0-9]*$' OR nullif(btrim(p->>'reason'),'') IS NULL THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='required_work_set' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['required','work_key']::text[]
       OR upper(p->>'work_key') NOT IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET') OR jsonb_typeof(p->'required')<>'boolean' THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='work_complete' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['booking_id','completed_at','expected_booking_version','work_key']::text[]
       OR p->>'booking_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' OR p->>'expected_booking_version' !~ '^[1-9][0-9]*$'
       OR upper(p->>'work_key') NOT IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET') OR p->>'completed_at' !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T' THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='note_append' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['event_at','text']::text[] OR nullif(btrim(p->>'text'),'') IS NULL OR p->>'event_at' !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T' THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='location_set' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['location','reason']::text[] OR upper(p->>'location') NOT IN('YH','PMB','QC','RFT','OTHER','IT') OR nullif(btrim(p->>'reason'),'') IS NULL THEN RETURN false; END IF;
  ELSE RETURN false;
  END IF;
  RETURN true;
END $validate$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb) FROM public,anon,authenticated,service_role;

-- Exact provenance and source/identity binding is checked against the full
-- planner envelope, not merely against an instruction in isolation.
-- provenance_keys_invalid, identity_value_invalid, source_digest_identity_invalid
-- and evidence_digest_identity_invalid are represented by this fail-closed
-- validator; typed_v2_plan_invalid is the strict RPC response code.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_validate_v2_plan_20260901(p_plan jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $plan_validate$
DECLARE item jsonb; ref jsonb; versions jsonb; identity jsonb; provenance jsonb;
BEGIN
  IF jsonb_typeof(p_plan)<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_plan) x) IS DISTINCT FROM ARRAY['aggregate_disposition','attachment_digests','created_at','environment','evidence_digest','instructions','plan_id','planner_failure_reason','planner_status','schema_version','source_digest','source_message_id','source_receipt_id','source_thread_id','versions']::text[]
     OR p_plan->>'schema_version'<>'pdc-email-ai-plan-v1' OR p_plan->>'environment'<>'staging'
     OR p_plan->>'plan_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR p_plan->>'source_receipt_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR p_plan->>'source_digest' !~ '^[a-f0-9]{64}$' OR p_plan->>'evidence_digest' !~ '^[a-f0-9]{64}$'
     OR nullif(btrim(p_plan->>'source_message_id'),'') IS NULL OR nullif(btrim(p_plan->>'source_thread_id'),'') IS NULL
     OR jsonb_typeof(p_plan->'versions')<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_plan->'versions') x) IS DISTINCT FROM ARRAY['business_rule_version','evidence_digest','model_version','planner_version','prompt_version','ruleset_version','source_digest','supabase_action_contract_version','taxonomy_version','transport_release_version']::text[]
     OR p_plan->'versions'->>'supabase_action_contract_version'<>'pdc-email-ai-action-request-v1'
     OR p_plan->'versions'->>'taxonomy_version'<>'pdc-operation-taxonomy-proposed/v1'
     OR p_plan->'versions'->>'source_digest'<>p_plan->>'source_digest'
     OR p_plan->'versions'->>'evidence_digest'<>p_plan->>'evidence_digest'
     OR jsonb_typeof(p_plan->'instructions')<>'array'
  THEN RETURN false; END IF;
  versions:=p_plan->'versions';
  IF (SELECT count(*) FROM jsonb_each_text(versions) WHERE nullif(btrim(value),'') IS NULL)>0 THEN RETURN false; END IF;
  IF jsonb_typeof(p_plan->'attachment_digests')<>'array' THEN RETURN false; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
    IF NOT public.pdc_email_ai_successor_validate_v2_instruction_20260901(item) THEN RETURN false; END IF;
    identity:=item->'identity';
    IF identity->>'vehicle_id'<>item->>'vehicle_id' OR identity->>'vehicle_id'<>item->>'vehicle_id' THEN RETURN false; END IF;
    provenance:=item->'provenance';
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(provenance) x) IS DISTINCT FROM ARRAY['business_rule_version','evidence_digest','model_version','planner_version','prompt_version','ruleset_version','source_digest','supabase_action_contract_version','taxonomy_version','transport_release_version']::text[]
       OR (SELECT count(*) FROM jsonb_each_text(provenance) WHERE nullif(btrim(value),'') IS NULL)>0
       OR provenance->>'source_digest'<>p_plan->>'source_digest' OR provenance->>'evidence_digest'<>p_plan->>'evidence_digest' THEN RETURN false; END IF;
    IF provenance->>'business_rule_version'<>versions->>'business_rule_version' OR provenance->>'model_version'<>versions->>'model_version'
       OR provenance->>'planner_version'<>versions->>'planner_version' OR provenance->>'prompt_version'<>versions->>'prompt_version'
       OR provenance->>'ruleset_version'<>versions->>'ruleset_version' OR provenance->>'taxonomy_version'<>versions->>'taxonomy_version'
       OR provenance->>'transport_release_version'<>versions->>'transport_release_version' OR provenance->>'supabase_action_contract_version'<>versions->>'supabase_action_contract_version' THEN RETURN false; END IF;
    IF jsonb_typeof(item->'evidence_refs')<>'array' THEN RETURN false; END IF;
    FOR ref IN SELECT value FROM jsonb_array_elements(item->'evidence_refs') LOOP
      IF jsonb_typeof(ref)<>'object' OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(ref) x) IS DISTINCT FROM ARRAY['kind','ref','required_for_action']::text[]
         OR nullif(btrim(ref->>'kind'),'') IS NULL OR nullif(btrim(ref->>'ref'),'') IS NULL OR jsonb_typeof(ref->'required_for_action')<>'boolean' THEN RETURN false; END IF;
    END LOOP;
  END LOOP;
  RETURN true;
END $plan_validate$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb) FROM public,anon,authenticated,service_role;

-- The narrow operation overlay uses a valid, already-authorized origin and
-- refuses manual/locked overlays before any update. Taxonomy is recomputed in
-- PostgreSQL, so a fabricated classified Hoist/Sublet update cannot pass.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_operation_update_20260901(p_vehicle_id uuid,p_expected_vehicle_version integer,p_source_hash text,p_source_uid text,p_operation_no text,p_work_key text,p_description text,p_estimated_hours numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $operation_update$
DECLARE v_vehicle public.vehicles%rowtype; v_source public.pdc_authenticated_email_operation_lines%rowtype; v_before jsonb; v_after jsonb; v_overlay public.vehicle_workshop_line_adjustments%rowtype; v_now timestamptz:=clock_timestamp();
BEGIN
  IF public.pdc_email_ai_successor_taxonomy_disposition_20260901('pdc-operation-taxonomy-proposed/v1',p_description,p_work_key)<>'classified' THEN RETURN jsonb_build_object('ok',false,'code','operation_update_taxonomy_rejected'); END IF;
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_vehicle.version<>p_expected_vehicle_version OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state::text<>'active' THEN RETURN jsonb_build_object('ok',false,'code','operation_update_vehicle_conflict'); END IF;
  SELECT * INTO v_source FROM public.pdc_authenticated_email_operation_lines WHERE vehicle_id=p_vehicle_id AND source_hash=lower(btrim(p_source_hash)) AND source_uid=p_source_uid AND operation_no=upper(btrim(p_operation_no)) FOR SHARE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','operation_update_source_not_found'); END IF;
  SELECT * INTO v_overlay FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=p_vehicle_id AND line_key='source:'||v_source.operation_line_id::text FOR UPDATE;
  IF v_overlay.adjustment_id IS NOT NULL AND (coalesce(v_overlay.manual_assignment_locked,false) OR v_overlay.correction_origin='manual_operator') THEN RETURN jsonb_build_object('ok',false,'code','operation_update_protected_manual_overlay'); END IF;
  v_before:=case when v_overlay.adjustment_id is null then to_jsonb(v_source) else to_jsonb(v_overlay) end;
  IF v_overlay.adjustment_id IS NULL THEN
    INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number)
    VALUES(p_vehicle_id,'source:'||v_source.operation_line_id::text,'source',public.workshop_stage_code_for_work_key(upper(btrim(p_work_key))),btrim(p_description),p_estimated_hours,true,1,auth.uid(),auth.uid(),v_source.operation_no,v_source.source_row_no,false,'ai_auditor',v_source.operation_line_id,v_source.job_card_number)
    RETURNING * INTO v_overlay;
  ELSE
    UPDATE public.vehicle_workshop_line_adjustments SET stage_code=public.workshop_stage_code_for_work_key(upper(btrim(p_work_key))),description=btrim(p_description),estimated_hours=p_estimated_hours,active=true,version=version+1,updated_by=auth.uid(),updated_at=v_now,correction_origin='ai_auditor' WHERE adjustment_id=v_overlay.adjustment_id RETURNING * INTO v_overlay;
  END IF;
  UPDATE public.vehicles SET version=version+1,updated_by=auth.uid(),updated_at=v_now WHERE id=p_vehicle_id RETURNING * INTO v_vehicle;
  v_after:=to_jsonb(v_overlay);
  PERFORM public.audit_pdc_event('update'::public.audit_action,'vehicle_workshop_line_adjustments',v_overlay.adjustment_id,p_vehicle_id,v_before,v_after,jsonb_build_object('source','pdc_email_ai_typed_action_surface_20260901','successor_version','20260901060000','operation_update',true,'correction_origin','ai_auditor','source_hash',p_source_hash,'source_uid',p_source_uid,'operation_no',p_operation_no));
  RETURN jsonb_build_object('ok',true,'code','operation_updated','vehicle',to_jsonb(v_vehicle),'operation',v_after,'source_operation_line_id',v_source.operation_line_id,'correction_origin','ai_auditor');
END $operation_update$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_operation_update_20260901(uuid,integer,text,text,text,text,text,numeric) FROM public,anon,authenticated,service_role;

-- Authoritative per-action projection. It never treats a vehicle-presence or
-- canonical-RPC identifier as readback proof.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_action_readback_20260901(p_vehicle_id uuid,p_action_type text,p_payload jsonb,p_result jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $readback$
DECLARE v_vehicle jsonb; v_booking jsonb; v_work jsonb; v_parts jsonb; v_operation jsonb; v_event jsonb; booking_id uuid; event_id uuid;
BEGIN
  SELECT to_jsonb(v) INTO v_vehicle FROM public.vehicles v WHERE v.id=p_vehicle_id;
  IF p_action_type IN('booking_set','booking_move','booking_cancel','work_complete') THEN
    IF coalesce(p_payload->>'booking_id',p_result->'booking'->>'booking_id',p_result->>'booking_id',p_result->>'id') ~ '^[0-9a-f-]{36}$' THEN booking_id:=coalesce(p_payload->>'booking_id',p_result->'booking'->>'booking_id',p_result->>'booking_id',p_result->>'id')::uuid; END IF;
    IF booking_id IS NOT NULL THEN v_booking:=public.workshop_booking_snapshot(booking_id); END IF;
  END IF;
  IF p_action_type IN('required_work_set','work_complete','parts_complete') THEN
    SELECT to_jsonb(w) INTO v_work FROM public.vehicle_work_items w WHERE w.vehicle_id=p_vehicle_id AND upper(w.work_key)=upper(case when p_action_type='parts_complete' then 'PARTS' else p_payload->>'work_key' end) LIMIT 1;
  END IF;
  IF p_action_type='parts_eta_set' THEN SELECT to_jsonb(x) INTO v_parts FROM public.vehicle_parts_updates x WHERE x.vehicle_id=p_vehicle_id ORDER BY x.updated_at DESC,x.id DESC LIMIT 1; END IF;
  IF p_action_type IN('operation_add','operation_update') THEN SELECT to_jsonb(x) INTO v_operation FROM public.pdc_effective_operation_lines x WHERE x.vehicle_id=p_vehicle_id AND x.operation_code=p_payload->>'operation_no' ORDER BY x.active DESC,x.operation_line_id LIMIT 1; END IF;
  IF p_action_type='note_append' THEN
    IF coalesce(p_result->>'id',p_result->>'event_id') ~ '^[0-9a-f-]{36}$' THEN event_id:=coalesce(p_result->>'id',p_result->>'event_id')::uuid; END IF;
    IF event_id IS NOT NULL THEN SELECT to_jsonb(e) INTO v_event FROM public.vehicle_timeline_events e WHERE e.id=event_id AND e.vehicle_id=p_vehicle_id; END IF;
  END IF;
  RETURN jsonb_build_object('vehicle',v_vehicle,'booking',v_booking,'work_item',v_work,'parts_update',v_parts,'operation',v_operation,'timeline_event',v_event);
END $readback$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_action_readback_20260901(uuid,text,jsonb,jsonb) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_action_readback_parity_20260901(p_action_type text,p_payload jsonb,p_result jsonb,p_readback jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,public AS $parity$
SELECT CASE p_action_type
  WHEN 'activate_vehicle' THEN p_readback->'vehicle'->>'source_record_id'=p_payload->>'backend_record_id'
  WHEN 'location_set' THEN upper(p_readback->'vehicle'->>'current_location')=upper(p_payload->>'location')
  WHEN 'parts_eta_set' THEN p_readback#>>'{parts_update,worst_eta}' IS NOT DISTINCT FROM p_payload->>'eta'
  WHEN 'parts_complete' THEN coalesce((p_readback->'work_item'->>'completed')::boolean,false)
  WHEN 'required_work_set' THEN upper(p_readback->'work_item'->>'work_key')=upper(p_payload->>'work_key') AND (p_readback->'work_item'->>'required')::boolean=(p_payload->>'required')::boolean
  WHEN 'work_complete' THEN p_readback->'booking'->>'booking_id'=p_payload->>'booking_id' AND p_readback->'booking'->>'status'='completed' AND coalesce((p_readback->'work_item'->>'completed')::boolean,false)
  WHEN 'booking_set' THEN p_readback->'booking'->>'booking_id' IS NOT NULL AND p_readback->'booking'->'stage'->>'code'=p_payload->>'stage_code' AND (p_readback->'booking'->'bay'->>'bay_number')::integer=(p_payload->>'bay_number')::integer AND p_readback->'booking'->>'scheduled_start_at'=(p_payload->>'scheduled_start_at')
  WHEN 'booking_move' THEN p_readback->'booking'->>'booking_id'=p_payload->>'booking_id' AND p_readback->'booking'->'stage'->>'code'=p_payload->>'stage_code' AND (p_readback->'booking'->'bay'->>'bay_number')::integer=(p_payload->>'bay_number')::integer AND p_readback->'booking'->>'scheduled_start_at'=p_payload->>'scheduled_start_at' AND (p_readback->'booking'->>'version')::integer>(p_payload->>'expected_booking_version')::integer
  WHEN 'booking_cancel' THEN p_readback->'booking'->>'booking_id'=p_payload->>'booking_id' AND (p_readback->'booking'->>'deleted_at' IS NOT NULL OR p_readback->'booking'->>'status' IN('deleted','cancelled'))
  WHEN 'note_append' THEN p_readback->'timeline_event'->>'vehicle_id'=p_readback->'vehicle'->>'id' AND p_readback->'timeline_event'->>'ai_summary'=p_payload->>'text' AND p_readback->'timeline_event'->>'original_statement'=p_payload->>'text'
  WHEN 'operation_add' THEN p_readback->'operation'->>'operation_code'=p_payload->>'operation_no' AND p_readback->'operation'->>'description'=p_payload->>'description' AND upper(p_readback->'operation'->>'work_key')=upper(p_payload->>'work_key') AND (p_readback->'operation'->>'estimated_hours')::numeric=(p_payload->>'estimated_hours')::numeric
  WHEN 'operation_update' THEN p_readback->'operation'->>'operation_code'=p_payload->>'operation_no' AND p_readback->'operation'->>'description'=p_payload->>'description' AND upper(p_readback->'operation'->>'work_key')=upper(p_payload->>'work_key') AND (p_readback->'operation'->>'estimated_hours')::numeric=(p_payload->>'estimated_hours')::numeric
  WHEN 'rft_transfer' THEN upper(p_readback->'vehicle'->>'current_location')='RFT'
  WHEN 'rft_collect' THEN p_readback->'vehicle'->>'rft_collected_at' IS NOT NULL
  ELSE false END;
$parity$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_action_readback_parity_20260901(text,jsonb,jsonb,jsonb) FROM public,anon,authenticated,service_role;

-- New executor: strict preflight is complete before this function is reached.
-- Review evidence is receipted without dispatch; only planned rows call the
-- fixed canonical functions below.
-- authoritative_booking_readback and authoritative_timeline_readback are
-- explicit affected-row projections; estimated_hours IS NULL is valid only
-- for non-planned review evidence and is never dispatched.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_execute_v2_20260901(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $execute$
DECLARE actor uuid:=auth.uid(); ident public.pdc_email_ai_successor_runtime_identities%rowtype; source_id uuid:=(p_plan->>'source_receipt_id')::uuid; source_hash text:=lower(p_plan->>'source_digest'); evidence_hash text:=lower(p_plan->>'evidence_digest'); tx uuid:=gen_random_uuid(); item jsonb; vehicle public.vehicles%rowtype; action_type text; action_key text; before_state jsonb; after_state jsonb; result jsonb; readback jsonb; action_receipt uuid; canonical_rpc text; reason text; disposition text; verification jsonb; actual jsonb; actions jsonb:='[]'::jsonb; dispositions text[]:='{}'; existing public.pdc_email_ai_successor_transaction_receipts%rowtype; plan_hash text:=public.pdc_email_ai_successor_hash(p_plan); readback_ok boolean:=true; aggregate text;
BEGIN
  SELECT * INTO ident FROM public.pdc_email_ai_successor_runtime_identities WHERE auth_user_id=actor AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL FOR SHARE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-email-ai-typed-source:'||source_hash,0));
  SELECT * INTO existing FROM public.pdc_email_ai_successor_transaction_receipts WHERE source_receipt_id=source_id;
  IF FOUND THEN
    IF existing.source_digest<>source_hash OR existing.plan_hash<>plan_hash THEN RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
    RETURN existing.response||jsonb_build_object('replay',true);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=source_id AND lower(coalesce(i.source_hash,''))=source_hash AND i.duplicate_of IS NULL AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->>'source_message_id') AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->>'source_thread_id') AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=evidence_hash) THEN RETURN jsonb_build_object('ok',false,'code','source_receipt_digest_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=(x->>'vehicle_id')::uuid)) THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
    action_type:=item->>'action_type'; action_key:=public.pdc_email_ai_successor_hash(jsonb_build_object('source_digest',source_hash,'receipt_id',source_id,'vehicle_id',item->>'vehicle_id','instruction_id',item->>'instruction_id','action_type',action_type,'payload',item->'payload'));
    SELECT * INTO vehicle FROM public.vehicles WHERE id=(item->>'vehicle_id')::uuid FOR UPDATE;
    before_state:=to_jsonb(vehicle); after_state:=null; result:='{}'::jsonb; actual:='{}'::jsonb; canonical_rpc:=null; verification:=jsonb_build_object('checked',false,'parity',false); disposition:='BLOCKED_EXACT_REASON'; reason:=coalesce(nullif(item->>'reason',''),'not dispatched');
    IF item->>'decision_disposition'<>'planned' THEN
      disposition:=case when item->>'decision_disposition'='review' then 'GENUINELY_AMBIGUOUS' else 'BLOCKED_EXACT_REASON' end;
      reason:=coalesce(nullif(item->>'reason',''),'typed evidence requires review');
    ELSIF vehicle.deleted_at IS NOT NULL OR vehicle.lifecycle_state::text<>'active' OR upper(coalesce(vehicle.current_location,'')) IN('RFT','COMPLETED') OR vehicle.rft_collected_at IS NOT NULL THEN
      reason:='vehicle_is_lifecycle_protected';
    ELSIF action_type IN('operation_add','operation_update') AND item->'payload'->>'taxonomy_disposition'<>'classified' THEN
      reason:='taxonomy_'||(item->'payload'->>'taxonomy_disposition')||'_requires_review'; disposition:='GENUINELY_AMBIGUOUS';
    ELSE
      IF action_type='activate_vehicle' THEN canonical_rpc:='public.reconcile_navision_operational_record(uuid,uuid,text)'; result:=public.reconcile_navision_operational_record((item->'payload'->>'backend_record_id')::uuid,actor,lower(coalesce(auth.jwt()->>'email','')));
      ELSIF action_type='operation_add' THEN canonical_rpc:='public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'; result:=public.import_pdc_authenticated_email_operations_with_hours(source_hash,item->'payload'->>'source_uid',jsonb_build_array(jsonb_build_object('operation_no',item->'payload'->>'operation_no','work_key',lower(item->'payload'->>'work_key'),'description',item->'payload'->>'description','estimated_hours',(item->'payload'->>'estimated_hours')::numeric,'estimated_hours_source','job_card')));
      ELSIF action_type='operation_update' THEN canonical_rpc:='public.pdc_email_ai_successor_operation_update_20260901(uuid,integer,text,text,text,text,text,numeric)'; result:=public.pdc_email_ai_successor_operation_update_20260901(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,source_hash,item->'payload'->>'source_uid',item->'payload'->>'operation_no',item->'payload'->>'work_key',item->'payload'->>'description',(item->'payload'->>'estimated_hours')::numeric);
      ELSIF action_type='parts_eta_set' THEN canonical_rpc:='public.update_pdc_parts_eta(uuid,integer,date)'; result:=public.update_pdc_parts_eta(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,(item->'payload'->>'eta')::date);
      ELSIF action_type='parts_complete' THEN canonical_rpc:='public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'; result:=public.set_pdc_vehicle_work_states(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,jsonb_build_object('parts','complete'));
      ELSIF action_type='booking_set' THEN canonical_rpc:='public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'; result:=public.schedule_vehicle_work(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,item->'payload'->>'stage_code',(item->'payload'->>'bay_number')::integer,(item->'payload'->>'scheduled_start_at')::timestamptz,(item->'payload'->>'duration_minutes')::integer,nullif(item->'payload'->>'technician_id','')::uuid,null,null);
      ELSIF action_type='booking_move' THEN canonical_rpc:='public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'; result:=public.move_workshop_booking((item->'payload'->>'booking_id')::uuid,(item->'payload'->>'expected_booking_version')::integer,item->'payload'->>'stage_code',(item->'payload'->>'bay_number')::integer,(item->'payload'->>'scheduled_start_at')::timestamptz,(item->'payload'->>'duration_minutes')::integer,item->'payload'->>'override_reason','{}'::jsonb);
      ELSIF action_type='booking_cancel' THEN canonical_rpc:='public.cancel_workshop_booking(uuid,integer,text,jsonb)'; result:=public.cancel_workshop_booking((item->'payload'->>'booking_id')::uuid,(item->'payload'->>'expected_booking_version')::integer,item->'payload'->>'reason','{}'::jsonb);
      ELSIF action_type='required_work_set' THEN canonical_rpc:='public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'; result:=public.set_pdc_vehicle_work_states(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,jsonb_build_object(lower(item->'payload'->>'work_key'),(item->'payload'->>'required')::boolean));
      ELSIF action_type='work_complete' THEN canonical_rpc:='public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)'; result:=public.complete_workshop_work((item->'payload'->>'booking_id')::uuid,(item->'payload'->>'expected_booking_version')::integer,item->'payload'->>'work_key',(item->'payload'->>'completed_at')::timestamptz,'{}'::jsonb);
      ELSIF action_type='note_append' THEN canonical_rpc:='public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'; SELECT to_jsonb(e) INTO result FROM public.append_vehicle_timeline_event(p_vehicle_id=>vehicle.id,p_event_type=>'email_ai_note',p_event_at=>(item->'payload'->>'event_at')::timestamptz,p_source_kind=>'ai'::public.vehicle_timeline_source_kind,p_event_state=>'confirmed'::public.vehicle_timeline_event_state,p_ai_summary=>item->'payload'->>'text',p_original_statement=>item->'payload'->>'text',p_structured_data=>jsonb_build_object('source_receipt_id',source_id,'action_key',action_key),p_source_email_id=>p_plan->>'source_message_id',p_source_thread_id=>p_plan->>'source_thread_id',p_evidence_reference=>'source:'||source_hash,p_source_intake_id=>source_id) e;
      ELSIF action_type='location_set' THEN canonical_rpc:='public.move_vehicle(uuid,integer,text,text,text,text,text)'; SELECT to_jsonb(public.move_vehicle(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,upper(item->'payload'->>'location'),null,null,null,item->'payload'->>'reason')) INTO result;
      ELSIF action_type='rft_transfer' THEN canonical_rpc:='public.rft_transfer_vehicle(uuid,integer)'; result:=public.rft_transfer_vehicle(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer);
      ELSE canonical_rpc:='public.rft_collect_vehicle(uuid,integer)'; result:=public.rft_collect_vehicle(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer);
      END IF;
      IF coalesce((result->>'ok')::boolean,action_type='note_append' OR action_type='location_set') THEN
        readback:=public.pdc_email_ai_successor_action_readback_20260901(vehicle.id,action_type,item->'payload',result); verification:=jsonb_build_object('checked',true,'parity',public.pdc_email_ai_successor_action_readback_parity_20260901(action_type,item->'payload',result,readback),'field_scope',action_type); after_state:=readback; actual:=result; disposition:=case when (verification->>'parity')::boolean then 'APPLIED_AND_VERIFIED' else 'FAILED_QUEUED_RETRY' end; reason:=case when disposition='APPLIED_AND_VERIFIED' then 'authoritative field-level readback verified' else 'authoritative_readback_field_parity_failed' end;
      ELSE disposition:='FAILED_QUEUED_RETRY'; reason:=coalesce(result->>'error',result->>'code','canonical_action_rejected'); END IF;

    END IF;
    INSERT INTO public.pdc_email_ai_successor_action_receipts(transaction_id,source_receipt_id,action_key,instruction_id,vehicle_id,action_type,requested,disposition,reason,canonical_rpc,before_state,after_state,verification,taxonomy_version,taxonomy_disposition) VALUES(tx,source_id,action_key,item->>'instruction_id',(item->>'vehicle_id')::uuid,action_type,item->'payload',disposition,reason,canonical_rpc,before_state,after_state,verification,p_plan->'versions'->>'taxonomy_version',item->'payload'->>'taxonomy_disposition') RETURNING action_receipt_id INTO action_receipt;
    PERFORM public.audit_pdc_event('update'::public.audit_action,'pdc_email_ai_successor_action_receipts',action_receipt,(item->>'vehicle_id')::uuid,before_state,after_state,jsonb_build_object('source','pdc_email_ai_typed_action_surface_20260901','successor_version','20260901060000','action_key',action_key,'action_type',action_type,'disposition',disposition));
    actions:=actions||jsonb_build_array(jsonb_build_object('instruction_id',item->>'instruction_id','action_key',action_key,'action_type',action_type,'disposition',disposition,'reason',reason,'canonical_rpc',canonical_rpc,'requested',item->'payload','actual',actual,'before_state',before_state,'after_state',after_state,'verification',verification)); dispositions:=array_append(dispositions,disposition);
  END LOOP;
  readback:=public.get_pdc_email_vehicle_location_snapshot(); readback_ok:=coalesce((readback->>'ok')::boolean,false) AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(actions) x WHERE x->>'disposition' IN('APPLIED_AND_VERIFIED','ALREADY_CORRECT') AND x#>>'{verification,parity}'<>'true');
  aggregate:=case when cardinality(dispositions)=0 then 'NO_ACTIONS' when NOT EXISTS(SELECT 1 FROM unnest(dispositions) d WHERE d NOT IN('APPLIED_AND_VERIFIED','ALREADY_CORRECT')) then 'SUCCESS' else 'PARTIAL_FAILURE' end;
  INSERT INTO public.pdc_email_ai_successor_transaction_receipts(transaction_id,identity_id,source_receipt_id,source_digest,evidence_digest,plan_hash,typed_plan,aggregate_disposition,readback_parity,response) VALUES(tx,ident.identity_id,source_id,source_hash,evidence_hash,plan_hash,p_plan,aggregate,readback_ok,jsonb_build_object('ok',aggregate='SUCCESS' AND readback_ok,'code',case when aggregate='SUCCESS' AND readback_ok then 'pdc_email_ai_typed_action_surface_verified' else 'pdc_email_ai_typed_action_surface_partial_failure' end,'disposition',aggregate,'actions',actions,'readback',readback,'readback_parity',readback_ok,'transaction_id',tx,'production_writes',false,'mailbox_contacted',false,'outbound_email',false));
  RETURN jsonb_build_object('ok',aggregate='SUCCESS' AND readback_ok,'code',case when aggregate='SUCCESS' AND readback_ok then 'pdc_email_ai_typed_action_surface_verified' else 'pdc_email_ai_typed_action_surface_partial_failure' end,'disposition',aggregate,'actions',actions,'readback',readback,'readback_parity',readback_ok,'transaction_id',tx,'production_writes',false,'mailbox_contacted',false,'outbound_email',false);
END $execute$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_execute_v2_20260901(jsonb) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $strict$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); identity_ok boolean;
BEGIN
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard() OR auth.role()<>'authenticated' OR actor IS NULL OR email='' THEN RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  SELECT EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities WHERE auth_user_id=actor AND normalized_email=email AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL) AND NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=actor AND active AND account_status='approved' AND role::text='administrator') INTO identity_ok;
  IF NOT identity_ok THEN RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  IF NOT public.pdc_email_ai_successor_validate_v2_plan_20260901(p_plan) THEN RETURN jsonb_build_object('ok',false,'code','typed_v2_plan_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  RETURN public.pdc_email_ai_successor_execute_v2_20260901(p_plan);
END $strict$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(p_plan jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $$ SELECT public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan) $$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(jsonb) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901060000','pdc_email_ai_typed_action_boundary_hardening_20260901',ARRAY[
 'Operation update uses valid ai_auditor versioned receipt metadata and rejects manual_assignment_locked/manual_operator overlays before mutation',
 'PostgreSQL recomputes the authoritative taxonomy for operation add/update; mixed signage/GVM/decal rows cannot be fabricated as classified Hoist or Sublet',
 'Review evidence with unknown operation hours remains typed and receipted without dispatch; planned rows require numeric hours',
 'Exact source, identity, provenance, digest and version values are checked against the complete v2 envelope before source lookup, canonical dispatch or receipts',
 'Booking set/move/cancel, work complete, note, operation, Parts, location, activation and RFT use affected-row/timeline field-level authoritative readback projections',
 'Strict authenticated-only staging RPC remains the sole enabled entrypoint; public, anon, service_role, Production, mailbox and outbound paths remain denied'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
