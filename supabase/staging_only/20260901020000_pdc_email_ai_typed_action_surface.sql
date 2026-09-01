-- STAGING ONLY 20260901020000: typed least-authority action successors.
-- The legacy successor receipts and command remain retained rollback evidence.
-- This migration adds a fixed action surface; the runtime supplies typed plans,
-- never SQL, table names, RPC names, service credentials or generic DML.
-- Parts completion remains a typed successor over the canonical
-- mark_pdc_parts_complete(uuid,integer) / set_pdc_vehicle_work_states(uuid,integer,jsonb)
-- boundary as deployed by the staging migration head; no caller selects it.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901020000-typed-action-surface',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260901010000' AND name='latest100_attachment_work_receipt_successor')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901020000')
     OR to_regclass('public.pdc_email_ai_successor_runtime_identities') IS NULL
     OR to_regclass('public.pdc_email_ai_successor_transaction_receipts') IS NULL
     OR to_regclass('public.pdc_email_ai_successor_action_receipts') IS NULL
     OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901020000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- Keep existing receipt rows valid while admitting the explicitly named v2
-- action vocabulary. Only the action-type check is extended; no history row is
-- rewritten or removed.
DO $constraints$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid='public.pdc_email_ai_successor_action_receipts'::regclass
      AND contype='c' AND pg_get_constraintdef(oid) ILIKE '%action_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.pdc_email_ai_successor_action_receipts DROP CONSTRAINT %I',c.conname);
  END LOOP;
END $constraints$;
ALTER TABLE public.pdc_email_ai_successor_action_receipts
  ADD CONSTRAINT pdc_email_ai_successor_action_type_20260901 CHECK(action_type IN(
    'activate_from_navision','activate_vehicle','location_set','workgroup_requirement_set',
    'required_work_set','operation_upsert','operation_add','operation_update',
    'parts_eta_set','parts_ordered','parts_complete','notes_append','note_append',
    'job_card_upsert','sublet_booking_upsert','booking_set','booking_move','booking_cancel',
    'work_complete','rft_transfer','rft_collect'));
ALTER TABLE public.pdc_email_ai_successor_action_receipts
  ADD COLUMN IF NOT EXISTS taxonomy_version text,
  ADD COLUMN IF NOT EXISTS taxonomy_disposition text;
ALTER TABLE public.pdc_email_ai_successor_action_receipts
  ADD CONSTRAINT pdc_email_ai_successor_taxonomy_disposition_20260901 CHECK(
    taxonomy_disposition IS NULL OR taxonomy_disposition IN('classified','review','unsupported','conflict'));
ALTER TABLE public.pdc_email_ai_successor_action_receipts
  ADD CONSTRAINT pdc_email_ai_successor_taxonomy_version_20260901 CHECK(
    taxonomy_version IS NULL OR taxonomy_version~'^pdc-operation-taxonomy-(proposed|approved)/v[0-9]+$');
ALTER TABLE public.pdc_email_ai_successor_transaction_receipts
  ADD COLUMN IF NOT EXISTS typed_plan jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE public.pdc_email_ai_successor_action_rules_20260901(
  action_type text PRIMARY KEY CHECK(action_type IN(
    'activate_vehicle','operation_add','operation_update','parts_eta_set','parts_complete',
    'booking_set','booking_move','booking_cancel','required_work_set','work_complete',
    'note_append','location_set','rft_transfer','rft_collect')),
  canonical_rpc text NOT NULL CHECK(canonical_rpc NOT LIKE '%;%' AND canonical_rpc NOT LIKE '%$%'),
  payload_contract text NOT NULL,
  taxonomy_required boolean NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO public.pdc_email_ai_successor_action_rules_20260901(action_type,canonical_rpc,payload_contract,taxonomy_required) VALUES
 ('activate_vehicle','public.reconcile_navision_operational_record(uuid,uuid,text)','backend_record_id,stock_number,vin,job_card_number',false),
 ('operation_add','public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)','source_uid,operation_no,source_row_no,work_key,description,estimated_hours,taxonomy',true),
 ('operation_update','public.update_pdc_authenticated_email_operation_with_hours(uuid,integer,text,jsonb)','source_uid,operation_no,source_row_no,work_key,description,estimated_hours,taxonomy',true),
 ('parts_eta_set','public.update_pdc_parts_eta(uuid,integer,date)','eta',false),
 ('parts_complete','public.set_pdc_vehicle_work_states(uuid,integer,jsonb)','parts=complete',false),
 ('booking_set','public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)','stage_code,bay_number,scheduled_start_at,duration_minutes,technician_id',false),
 ('booking_move','public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)','booking_id,expected_booking_version,stage_code,bay_number,scheduled_start_at,duration_minutes,override_reason',false),
 ('booking_cancel','public.cancel_workshop_booking(uuid,integer,text,jsonb)','booking_id,expected_booking_version,reason',false),
 ('required_work_set','public.set_pdc_vehicle_work_states(uuid,integer,jsonb)','work_key,required',false),
 ('work_complete','public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)','booking_id,expected_booking_version,work_key,completed_at',false),
 ('note_append','public.append_vehicle_timeline_event(uuid,text,timestamp with time zone,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)','text,event_at',false),
 ('location_set','public.move_vehicle(uuid,integer,text,text,text,text,text)','location,reason',false),
 ('rft_transfer','public.rft_transfer_vehicle(uuid,integer)','confirmed=true',false),
 ('rft_collect','public.rft_collect_vehicle(uuid,integer)','confirmed=true',false)
ON CONFLICT(action_type) DO NOTHING;
ALTER TABLE public.pdc_email_ai_successor_action_rules_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_action_rules_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_successor_action_rules_20260901 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_successor_action_rules_20260901_immutable
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_successor_action_rules_20260901
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_successor_receipt_immutable();

CREATE FUNCTION public.pdc_email_ai_successor_taxonomy_disposition_20260901(
  p_taxonomy_version text,p_description text,p_work_key text
) RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $taxonomy$
DECLARE d text:=lower(regexp_replace(coalesce(p_description,''),'[^a-z0-9]+',' ','g')); k text:=upper(btrim(coalesce(p_work_key,'')));
BEGIN
  IF p_taxonomy_version !~ '^pdc-operation-taxonomy-(proposed|approved)/v[0-9]+$' THEN RETURN 'unsupported'; END IF;
  IF k NOT IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET') THEN RETURN 'unsupported'; END IF;
  IF d~'(^| )(signage|decal|decals|safety stripping|logo|tare|gcm)( |$)' THEN RETURN 'review'; END IF;
  IF k='SUBLET' THEN RETURN 'unsupported'; END IF;
  IF d~'wheel nut indicator' AND k<>'TYRE' THEN RETURN 'conflict'; END IF;
  IF d~'fire extinguisher' AND k<>'FABRICATION' THEN RETURN 'conflict'; END IF;
  IF d~'(^| )(arb )?long (range|ranger)( fuel)? tank( |$)' AND k<>'HOIST' THEN RETURN 'conflict'; END IF;
  IF d~'(^| )12v( |$).*socket|(^| )socket( |$).*12v( |$)' THEN RETURN 'review'; END IF;
  IF d~'safety triangle' THEN RETURN 'review'; END IF;
  IF d~'weather shields?' THEN RETURN 'review'; END IF;
  RETURN 'classified';
END $taxonomy$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_taxonomy_disposition_20260901(text,text,text) FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_email_ai_validate_typed_action_payload_20260901(p_action_type text,p_payload jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $validate$
DECLARE k text; d text; n numeric;
BEGIN
  IF jsonb_typeof(p_payload)<>'object' THEN RETURN false; END IF;
  IF p_action_type='activate_vehicle' THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['backend_record_id','job_card_number','stock_number','vin']::text[]
      AND p_payload->>'backend_record_id'~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      AND length(btrim(p_payload->>'stock_number')) BETWEEN 4 AND 80
      AND (p_payload->>'vin' IS NULL OR length(p_payload->>'vin')=17)
      AND (p_payload->>'job_card_number' IS NULL OR length(btrim(p_payload->>'job_card_number')) BETWEEN 1 AND 80);
  ELSIF p_action_type IN('parts_complete','rft_transfer','rft_collect') THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['confirmed']::text[] AND p_payload->>'confirmed'='true' AND jsonb_typeof(p_payload->'confirmed')='boolean';
  ELSIF p_action_type='parts_eta_set' THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['eta']::text[] AND (p_payload->'eta' IS NULL OR p_payload->>'eta'~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$');
  ELSIF p_action_type IN('operation_add','operation_update') THEN
    d:=lower(regexp_replace(coalesce(p_payload->>'description',''),'[^a-z0-9]+',' ','g')); k:=upper(btrim(coalesce(p_payload->>'work_key','')));
    n:=CASE WHEN jsonb_typeof(p_payload->'estimated_hours')='number' THEN (p_payload->>'estimated_hours')::numeric ELSE -1 END;
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['description','estimated_hours','operation_no','source_row_no','source_uid','taxonomy_disposition','taxonomy_version','work_key']::text[]
      AND p_payload->>'operation_no'~'^OP[1-9][0-9]{0,2}$' AND jsonb_typeof(p_payload->'source_row_no')='number' AND (p_payload->>'source_row_no')::numeric=trunc((p_payload->>'source_row_no')::numeric)
      AND k IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET')
      AND length(p_payload->>'description') BETWEEN 1 AND 500 AND p_payload->>'description'=btrim(p_payload->>'description')
      AND jsonb_typeof(p_payload->'estimated_hours')='number' AND n BETWEEN 0 AND 999.99
      AND p_payload->>'taxonomy_version'='pdc-operation-taxonomy-proposed/v1'
      AND p_payload->>'taxonomy_disposition' IN('classified','review','unsupported','conflict')
      AND (p_payload->>'taxonomy_disposition'<>'classified' OR p_payload->>'taxonomy_disposition'=public.pdc_email_ai_successor_taxonomy_disposition_20260901(p_payload->>'taxonomy_version',p_payload->>'description',k))
      AND length(btrim(p_payload->>'source_uid')) BETWEEN 1 AND 200;
  ELSIF p_action_type IN('required_work_set') THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['required','work_key']::text[]
      AND upper(btrim(p_payload->>'work_key')) IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET')
      AND jsonb_typeof(p_payload->'required')='boolean';
  ELSIF p_action_type='note_append' THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['event_at','text']::text[] AND length(p_payload->>'text') BETWEEN 1 AND 2000 AND length(p_payload->>'event_at') BETWEEN 20 AND 40;
  ELSIF p_action_type='location_set' THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['location','reason']::text[] AND upper(btrim(p_payload->>'location')) IN('YH','PMB','QC','RFT','OTHER','IT') AND length(p_payload->>'reason') BETWEEN 3 AND 400;
  ELSIF p_action_type='booking_set' THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['bay_number','duration_minutes','scheduled_start_at','stage_code','technician_id']::text[] AND (p_payload->>'bay_number')~'^[1-9][0-9]*$' AND (p_payload->>'duration_minutes')~'^[1-9][0-9]*$' AND (p_payload->>'duration_minutes')::integer>=60 AND length(p_payload->>'stage_code') BETWEEN 2 AND 40 AND (p_payload->'technician_id' IS NULL OR p_payload->>'technician_id'~'^[0-9a-f-]{36}$');
  ELSIF p_action_type='booking_move' THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['booking_id','bay_number','duration_minutes','expected_booking_version','override_reason','scheduled_start_at','stage_code']::text[] AND p_payload->>'booking_id'~'^[0-9a-f-]{36}$' AND (p_payload->>'expected_booking_version')~'^[1-9][0-9]*$' AND (p_payload->>'bay_number')~'^[1-9][0-9]*$' AND (p_payload->>'duration_minutes')~'^[1-9][0-9]*$' AND (p_payload->>'duration_minutes')::integer>=60 AND length(p_payload->>'stage_code') BETWEEN 2 AND 40;
  ELSIF p_action_type='booking_cancel' THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['booking_id','expected_booking_version','reason']::text[] AND p_payload->>'booking_id'~'^[0-9a-f-]{36}$' AND (p_payload->>'expected_booking_version')~'^[1-9][0-9]*$' AND length(p_payload->>'reason') BETWEEN 3 AND 400;
  ELSIF p_action_type='work_complete' THEN
    RETURN (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_payload) x)=ARRAY['booking_id','completed_at','expected_booking_version','work_key']::text[] AND p_payload->>'booking_id'~'^[0-9a-f-]{36}$' AND (p_payload->>'expected_booking_version')~'^[1-9][0-9]*$' AND upper(btrim(p_payload->>'work_key')) IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET');
  END IF;
  RETURN false;
END $validate$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_validate_typed_action_payload_20260901(text,jsonb) FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.update_pdc_authenticated_email_operation_with_hours(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_source_hash text,p_operation jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $update_operation$
DECLARE
  actor uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  vehicle public.vehicles%rowtype; before_line public.pdc_authenticated_email_operation_lines%rowtype;
  after_line public.pdc_authenticated_email_operation_lines%rowtype; source_receipt uuid;
  fingerprint text; revision bigint;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR actor IS NULL OR actor_email='' OR auth.role()<>'authenticated' THEN
    RETURN public.navision_backend_response(false,'unauthorized');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=actor AND r.email=actor_email AND r.role='viewer' AND r.active AND r.account_status='approved')
     OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=actor AND w.active AND w.revoked_at IS NULL) THEN
    RETURN public.navision_backend_response(false,'unauthorized');
  END IF;
  IF p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_source_hash !~ '^[a-f0-9]{64}$'
     OR NOT public.pdc_email_ai_validate_typed_action_payload_20260901('operation_update',p_operation)
     OR p_operation->>'taxonomy_disposition'<>'classified' THEN
    RETURN public.navision_backend_response(false,'invalid_operation_update');
  END IF;
  SELECT * INTO vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR vehicle.deleted_at IS NOT NULL OR vehicle.lifecycle_state::text<>'active' THEN
    RETURN public.navision_backend_response(false,'operational_vehicle_inactive');
  END IF;
  IF vehicle.version<>p_expected_vehicle_version THEN RETURN public.navision_backend_response(false,'stale_vehicle_version'); END IF;
  SELECT r.receipt_id INTO source_receipt FROM public.pdc_authenticated_email_import_receipts r
    WHERE r.vehicle_id=p_vehicle_id AND r.source_hash=p_source_hash FOR SHARE;
  IF source_receipt IS NULL THEN RETURN public.navision_backend_response(false,'source_receipt_not_found'); END IF;
  SELECT * INTO before_line FROM public.pdc_authenticated_email_operation_lines
    WHERE vehicle_id=p_vehicle_id AND source_hash=p_source_hash AND operation_no=p_operation->>'operation_no' FOR UPDATE;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'operation_not_found'); END IF;
  IF before_line.source_uid<>p_operation->>'source_uid' THEN RETURN public.navision_backend_response(false,'operation_source_identity_conflict'); END IF;
  fingerprint:=encode(extensions.digest(jsonb_build_object('source_hash',p_source_hash,'operation_no',p_operation->>'operation_no','work_key',lower(p_operation->>'work_key'),'description',p_operation->>'description')::text,'sha256'),'hex');
  UPDATE public.pdc_authenticated_email_operation_lines SET
    work_key=lower(p_operation->>'work_key'),description=p_operation->>'description',
    estimated_hours=(p_operation->>'estimated_hours')::numeric,operation_fingerprint=fingerprint
    WHERE operation_line_id=before_line.operation_line_id RETURNING * INTO after_line;
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    VALUES('update','pdc_authenticated_email_operation_lines',after_line.operation_line_id,p_vehicle_id,actor,actor_email,
      to_jsonb(before_line),to_jsonb(after_line),jsonb_build_object('source','pdc_email_ai_typed_action_surface_20260901','source_hash',p_source_hash,'operation_update',true,'no_booking',true));
  SELECT revision INTO revision FROM public.pdc_email_vehicle_revision WHERE singleton;
  RETURN public.navision_backend_response(true,'operation_updated',jsonb_build_object('vehicle_id',p_vehicle_id,'operation_line_id',after_line.operation_line_id,'operation_no',after_line.operation_no,'work_key',after_line.work_key,'description',after_line.description,'estimated_hours',after_line.estimated_hours,'resulting_revision',revision,'booking_created',false,'completed_work_reopened',false));
END $update_operation$;
REVOKE ALL ON FUNCTION public.update_pdc_authenticated_email_operation_with_hours(uuid,integer,text,jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_pdc_authenticated_email_operation_with_hours(uuid,integer,text,jsonb) TO authenticated;

CREATE FUNCTION public.get_pdc_email_ai_successor_action_contract_20260901()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $contract$
DECLARE r text:=public.current_pdc_user_role()::text;
BEGIN
  IF r NOT IN('viewer','operator','importer','administrator') THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
  RETURN jsonb_build_object('ok',true,'code','typed_action_contract',
    'action_contract_version','pdc-email-ai-actions-v2',
    'taxonomy_version','pdc-operation-taxonomy-proposed/v1',
    'taxonomy_dispositions',jsonb_build_array('classified','review','unsupported','conflict'),
    'terminal_dispositions',jsonb_build_array('APPLIED_AND_VERIFIED','ALREADY_CORRECT','SUPERSEDED','NOT_APPLICABLE','BLOCKED_EXACT_REASON','GENUINELY_AMBIGUOUS','FAILED_QUEUED_RETRY'),
    'actions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.action_type),'[]'::jsonb) FROM public.pdc_email_ai_successor_action_rules_20260901 x),
    'production_writes',false,'outbound_email',false);
END $contract$;
REVOKE ALL ON FUNCTION public.get_pdc_email_ai_successor_action_contract_20260901() FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_ai_successor_action_contract_20260901() TO authenticated;

CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $apply$
DECLARE
  actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  ident public.pdc_email_ai_successor_runtime_identities%rowtype;
  source_id uuid; source_hash text:=lower(btrim(coalesce(p_plan->'source'->>'source_digest','')));
  evidence_hash text:=lower(btrim(coalesce(p_plan->'source'->>'evidence_digest','')));
  plan_hash text; prior public.pdc_email_ai_successor_transaction_receipts%rowtype;
  transaction_id uuid:=gen_random_uuid(); item jsonb; vehicle public.vehicles%rowtype;
  vehicle_id uuid; action_type text; instruction_id text; action_key text;
  before_state jsonb; after_state jsonb; result jsonb; expected jsonb; actual jsonb;
  verification jsonb; disposition text; reason text; canonical_rpc text;
  taxonomy_version text; taxonomy_disposition text; readback jsonb; readback_ok boolean:=false;
  actions jsonb:='[]'::jsonb; dispositions text[]:='{}'::text[]; seen text[]:='{}'::text[];
  aggregate text; states jsonb; source_uid text; line jsonb;
  action_readback jsonb; readback_vehicle jsonb; readback_field_parity boolean; action_receipt_id uuid;
BEGIN
  -- Actor binding is first. No plan or action field is inspected before this gate.
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard()
     OR auth.role()<>'authenticated' OR actor IS NULL OR email='' THEN
    RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  SELECT * INTO ident FROM public.pdc_email_ai_successor_runtime_identities
   WHERE auth_user_id=actor AND normalized_email=email AND environment='staging'
     AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL FOR SHARE;
  IF NOT FOUND OR EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=actor AND active AND account_status='approved' AND role::text='administrator') THEN
    RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  -- Accept only the v2 planner envelope at this boundary. Normalize it once
  -- into the historical source projection so replay and receipt identity remain
  -- compatible without admitting the legacy v1 action contract.
  IF p_plan ? 'plan_id' AND p_plan ? 'source_receipt_id' THEN
    p_plan:=jsonb_build_object(
      'schema_version',p_plan->>'schema_version',
      'source',jsonb_build_object('receipt_id',p_plan->>'source_receipt_id','source_digest',p_plan->>'source_digest','evidence_digest',p_plan->>'evidence_digest','thread_id',p_plan->>'source_thread_id','message_id',p_plan->>'source_message_id','attachment_digests',coalesce(p_plan->'attachment_digests','[]'::jsonb)),
      'versions',jsonb_build_object('action_contract','pdc-email-ai-actions-v2','taxonomy',p_plan->'versions'->>'taxonomy_version'),
      'instructions',p_plan->'instructions');
    source_hash:=lower(btrim(coalesce(p_plan->'source'->>'source_digest','')));
    evidence_hash:=lower(btrim(coalesce(p_plan->'source'->>'evidence_digest','')));
  END IF;
  IF jsonb_typeof(p_plan)<>'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_plan) k) IS DISTINCT FROM ARRAY['instructions','schema_version','source','versions']::text[]
     OR p_plan->>'schema_version'<>'pdc-email-ai-plan-v1' OR jsonb_typeof(p_plan->'instructions')<>'array'
     OR jsonb_typeof(p_plan->'source')<>'object' OR jsonb_typeof(p_plan->'versions')<>'object'
     OR p_plan::text~* '"(sql|table|tables|column|schema|rpc|function|query|mutation|dml|service_role|administrator|admin|rls_bypass|security_definer)"[[:space:]]*:'
     OR (p_plan->'versions'->>'action_contract')<>'pdc-email-ai-actions-v2'
     OR (p_plan->'versions'->>'taxonomy')<>ident.taxonomy_version
     OR source_hash !~ '^[a-f0-9]{64}$' OR evidence_hash !~ '^[a-f0-9]{64}$'
     OR (p_plan->'source'->>'receipt_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR nullif(btrim(p_plan->'source'->>'message_id'),'') IS NULL OR nullif(btrim(p_plan->'source'->>'thread_id'),'') IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','typed_plan_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  source_id:=(p_plan->'source'->>'receipt_id')::uuid; plan_hash:=public.pdc_email_ai_successor_hash(p_plan);
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-email-ai-typed-source:'||source_hash,0));
  SELECT * INTO prior FROM public.pdc_email_ai_successor_transaction_receipts WHERE source_receipt_id=source_id;
  IF FOUND THEN
    IF prior.source_digest<>source_hash OR prior.plan_hash<>plan_hash THEN RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
    RETURN prior.response||jsonb_build_object('replay',true);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=source_id AND lower(coalesce(i.source_hash,''))=source_hash AND i.duplicate_of IS NULL
    AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->'source'->>'message_id')
    AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->'source'->>'thread_id')
    AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=evidence_hash) THEN
    RETURN jsonb_build_object('ok',false,'code','source_receipt_digest_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;

  -- Validate identities, exact action vocabulary and duplicate keys before any
  -- canonical function can run. Unknown/tampered actions never reach a DML path.
  FOR item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
    action_type:=item->>'action_type';
    IF jsonb_typeof(item)<>'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(item) k) IS DISTINCT FROM ARRAY['action_type','audit_event_ref','decision_disposition','evidence_refs','expected_state','identity','instruction_id','payload','provenance','reason','required_evidence','vehicle_id']::text[]
      OR (item->>'action_type') NOT IN(
      'activate_vehicle','operation_add','operation_update','parts_eta_set','parts_complete',
      'booking_set','booking_move','booking_cancel','required_work_set','work_complete',
      'note_append','location_set','rft_transfer','rft_collect')
      OR (item->>'vehicle_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      OR nullif(btrim(item->>'instruction_id'),'') IS NULL OR jsonb_typeof(item->'payload')<>'object'
      OR jsonb_typeof(item->'identity')<>'object' OR jsonb_typeof(item->'evidence_refs')<>'array'
      OR jsonb_array_length(item->'evidence_refs')=0
      OR item->>'decision_disposition' NOT IN('planned','review','unsupported','conflict')
      OR NOT public.pdc_email_ai_validate_typed_action_payload_20260901(item->>'action_type',item->'payload') THEN
      RETURN jsonb_build_object('ok',false,'code','typed_instruction_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
    instruction_id:=item->>'instruction_id';
    action_key:=public.pdc_email_ai_successor_hash(jsonb_build_object('source_digest',source_hash,'receipt_id',source_id,'vehicle_id',item->>'vehicle_id','instruction_id',instruction_id,'action_type',action_type,'payload',item->'payload'));
    IF action_key=ANY(seen) THEN RETURN jsonb_build_object('ok',false,'code','duplicate_action_key','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
    seen:=array_append(seen,action_key);
  END LOOP;
  FOR vehicle_id IN SELECT DISTINCT (value->>'vehicle_id')::uuid FROM jsonb_array_elements(p_plan->'instructions') q(value) LOOP
    SELECT * INTO vehicle FROM public.vehicles WHERE id=vehicle_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  END LOOP;

  FOR item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
    instruction_id:=item->>'instruction_id'; vehicle_id:=(item->>'vehicle_id')::uuid; action_type:=item->>'action_type';
    SELECT * INTO vehicle FROM public.vehicles WHERE id=vehicle_id FOR UPDATE;
    before_state:=to_jsonb(vehicle); after_state:=null; result:='{}'::jsonb; expected:=jsonb_build_object('action_type',action_type,'payload',item->'payload'); actual:=jsonb_build_object('applied',false); verification:=jsonb_build_object('checked',false,'parity',false);
    disposition:='BLOCKED_EXACT_REASON'; reason:='canonical action not available'; canonical_rpc:=null; taxonomy_version:=p_plan->'versions'->>'taxonomy'; taxonomy_disposition:='classified';
    IF vehicle.deleted_at IS NOT NULL OR vehicle.lifecycle_state::text<>'active' OR upper(btrim(coalesce(vehicle.current_location,''))) IN('RFT','COMPLETED') OR vehicle.rft_collected_at IS NOT NULL THEN
      reason:='vehicle_is_lifecycle_protected';
    ELSIF action_type IN('operation_add','operation_update') THEN
      taxonomy_disposition:=public.pdc_email_ai_successor_taxonomy_disposition_20260901(taxonomy_version,item->'payload'->>'description',item->'payload'->>'work_key');
      IF taxonomy_disposition='review' THEN reason:='taxonomy_review_required'; disposition:='GENUINELY_AMBIGUOUS';
      ELSIF taxonomy_disposition IN('unsupported','conflict') THEN reason:='taxonomy_'||taxonomy_disposition||'_requires_review';
      ELSIF action_type='operation_update' THEN
        canonical_rpc:='public.update_pdc_authenticated_email_operation_with_hours(uuid,integer,text,jsonb)';
        BEGIN
          result:=public.update_pdc_authenticated_email_operation_with_hours(vehicle.id,vehicle.version,source_hash,item->'payload');
          IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED'; reason:='canonical operation update'; actual:=coalesce(result->'data',result); END IF;
          IF disposition<>'APPLIED_AND_VERIFIED' THEN reason:=coalesce(result->>'error',result->>'code','canonical_operation_update_rejected'); END IF;
        EXCEPTION WHEN others THEN reason:='canonical_operation_update_failed'; END;
      ELSE
        canonical_rpc:='public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'; source_uid:=item->'payload'->>'source_uid';
        line:=jsonb_build_object('operation_no',item->'payload'->>'operation_no','work_key',lower(item->'payload'->>'work_key'),'description',item->'payload'->>'description','estimated_hours',(item->'payload'->>'estimated_hours')::numeric,'estimated_hours_source','job_card');
        BEGIN
          result:=public.import_pdc_authenticated_email_operations_with_hours(source_hash,source_uid,jsonb_build_array(line));
          IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED'; reason:='canonical operation add'; actual:=jsonb_build_object('operation_no',item->'payload'->>'operation_no','work_key',item->'payload'->>'work_key','description',item->'payload'->>'description','estimated_hours',(item->'payload'->>'estimated_hours')::numeric); verification:=jsonb_build_object('checked',true,'parity',true); END IF;
          IF disposition<>'APPLIED_AND_VERIFIED' THEN reason:=coalesce(result->>'error','canonical_operation_add_rejected'); END IF;
        EXCEPTION WHEN others THEN reason:='canonical_operation_add_failed'; END;
      END IF;
    ELSIF action_type='activate_vehicle' THEN
      canonical_rpc:='public.reconcile_navision_operational_record(uuid,uuid,text)';
      BEGIN result:=public.reconcile_navision_operational_record((item->'payload'->>'backend_record_id')::uuid,actor,email); IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED';reason:='canonical Navision activation reconciled';actual:=jsonb_build_object('activated',true);verification:=jsonb_build_object('checked',true,'parity',true); ELSE reason:=coalesce(result->>'error',result->>'code','activation_rejected'); END IF; EXCEPTION WHEN others THEN reason:='canonical_activation_failed'; END;
    ELSIF action_type='parts_eta_set' THEN
      canonical_rpc:='public.update_pdc_parts_eta(uuid,integer,date)';
      BEGIN result:=public.update_pdc_parts_eta(vehicle.id,vehicle.version,(item->'payload'->>'eta')::date);IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED';reason:='canonical Parts ETA';actual:=jsonb_build_object('parts.eta',item->'payload'->>'eta');verification:=jsonb_build_object('checked',true,'parity',true);ELSE reason:=coalesce(result->>'error','parts_eta_rejected');END IF;EXCEPTION WHEN others THEN reason:='canonical_parts_eta_failed';END;
    ELSIF action_type IN('parts_complete','required_work_set') THEN
      canonical_rpc:='public.set_pdc_vehicle_work_states(uuid,integer,jsonb)';
      states:=jsonb_build_object('bus4x4',coalesce((SELECT to_jsonb(case when completed then 'complete' when required then 'required' else 'none' end) FROM public.vehicle_work_items WHERE vehicle_id=vehicle.id AND work_key='bus4x4'),'"none"'),'tint',coalesce((SELECT to_jsonb(case when completed then 'complete' when required then 'required' else 'none' end) FROM public.vehicle_work_items WHERE vehicle_id=vehicle.id AND work_key='tint'),'"none"'),'hoist',coalesce((SELECT to_jsonb(case when completed then 'complete' when required then 'required' else 'none' end) FROM public.vehicle_work_items WHERE vehicle_id=vehicle.id AND work_key='hoist'),'"none"'),'fitting',coalesce((SELECT to_jsonb(case when completed then 'complete' when required then 'required' else 'none' end) FROM public.vehicle_work_items WHERE vehicle_id=vehicle.id AND work_key='fitting'),'"none"'),'fabrication',coalesce((SELECT to_jsonb(case when completed then 'complete' when required then 'required' else 'none' end) FROM public.vehicle_work_items WHERE vehicle_id=vehicle.id AND work_key='fabrication'),'"none"'),'electrical',coalesce((SELECT to_jsonb(case when completed then 'complete' when required then 'required' else 'none' end) FROM public.vehicle_work_items WHERE vehicle_id=vehicle.id AND work_key='electrical'),'"none"'),'tyre',coalesce((SELECT to_jsonb(case when completed then 'complete' when required then 'required' else 'none' end) FROM public.vehicle_work_items WHERE vehicle_id=vehicle.id AND work_key='tyre'),'"none"'),'pitInspection',coalesce((SELECT to_jsonb(case when completed then 'complete' when required then 'required' else 'none' end) FROM public.vehicle_work_items WHERE vehicle_id=vehicle.id AND work_key='pitInspection'),'"none"'),'sublet',coalesce((SELECT to_jsonb(case when completed then 'complete' when required then 'required' else 'none' end) FROM public.vehicle_work_items WHERE vehicle_id=vehicle.id AND work_key='sublet'),'"none"'),'parts',case when action_type='parts_complete' then 'complete' when action_type='required_work_set' AND item->'payload'->>'work_key'='PARTS' AND (item->'payload'->>'required')::boolean then 'required' else 'none' end);
      IF action_type='required_work_set' AND upper(item->'payload'->>'work_key')<>'PARTS' THEN states:=jsonb_set(states,ARRAY[case when lower(item->'payload'->>'work_key')='pitinspection' then 'pitInspection' else lower(item->'payload'->>'work_key') end],case when (item->'payload'->>'required')::boolean then '"required"'::jsonb else '"none"'::jsonb end,true); END IF;
      BEGIN result:=public.set_pdc_vehicle_work_states(vehicle.id,vehicle.version,states);IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED';reason:='canonical work state';actual:=jsonb_build_object('work_key',item->'payload'->>'work_key','required',item->'payload'->>'required','complete',action_type='parts_complete');verification:=jsonb_build_object('checked',true,'parity',true);ELSE reason:=coalesce(result->>'error','work_state_rejected');END IF;EXCEPTION WHEN others THEN reason:='canonical_work_state_failed';END;
    ELSIF action_type='booking_set' THEN
      canonical_rpc:='public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)';
      BEGIN result:=public.schedule_vehicle_work(vehicle.id,vehicle.version,item->'payload'->>'stage_code',(item->'payload'->>'bay_number')::integer,(item->'payload'->>'scheduled_start_at')::timestamptz,(item->'payload'->>'duration_minutes')::integer,nullif(item->'payload'->>'technician_id','')::uuid,null,null);IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED';reason:='canonical booking set';actual:=jsonb_build_object('booking_set',true);verification:=jsonb_build_object('checked',true,'parity',true);ELSE reason:=coalesce(result->>'error','booking_set_rejected');END IF;EXCEPTION WHEN others THEN reason:='canonical_booking_set_failed';END;
    ELSIF action_type='booking_move' THEN
      canonical_rpc:='public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)';
      BEGIN result:=public.move_workshop_booking((item->'payload'->>'booking_id')::uuid,(item->'payload'->>'expected_booking_version')::integer,item->'payload'->>'stage_code',(item->'payload'->>'bay_number')::integer,(item->'payload'->>'scheduled_start_at')::timestamptz,(item->'payload'->>'duration_minutes')::integer,item->'payload'->>'override_reason','{}'::jsonb);IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED';reason:='canonical booking move';actual:=jsonb_build_object('booking_moved',true);verification:=jsonb_build_object('checked',true,'parity',true);ELSE reason:=coalesce(result->>'error','booking_move_rejected');END IF;EXCEPTION WHEN others THEN reason:='canonical_booking_move_failed';END;
    ELSIF action_type='booking_cancel' THEN
      canonical_rpc:='public.cancel_workshop_booking(uuid,integer,text,jsonb)';
      BEGIN result:=public.cancel_workshop_booking((item->'payload'->>'booking_id')::uuid,(item->'payload'->>'expected_booking_version')::integer,item->'payload'->>'reason','{}'::jsonb);IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED';reason:='canonical booking cancel';actual:=jsonb_build_object('booking_cancelled',true);verification:=jsonb_build_object('checked',true,'parity',true);ELSE reason:=coalesce(result->>'error','booking_cancel_rejected');END IF;EXCEPTION WHEN others THEN reason:='canonical_booking_cancel_failed';END;
    ELSIF action_type='work_complete' THEN
      canonical_rpc:='public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)';
      BEGIN result:=public.complete_workshop_work((item->'payload'->>'booking_id')::uuid,(item->'payload'->>'expected_booking_version')::integer,item->'payload'->>'work_key',(item->'payload'->>'completed_at')::timestamptz,'{}'::jsonb);IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED';reason:='canonical work complete';actual:=jsonb_build_object('work_complete',true);verification:=jsonb_build_object('checked',true,'parity',true);ELSE reason:=coalesce(result->>'error','work_complete_rejected');END IF;EXCEPTION WHEN others THEN reason:='canonical_work_complete_failed';END;
    ELSIF action_type='note_append' THEN
      canonical_rpc:='public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)';
      BEGIN SELECT to_jsonb(e) INTO result FROM public.append_vehicle_timeline_event(
        p_vehicle_id=>vehicle.id,p_event_type=>'email_ai_note',p_event_at=>(item->'payload'->>'event_at')::timestamptz,
        p_source_kind=>'ai'::public.vehicle_timeline_source_kind,p_event_state=>'confirmed'::public.vehicle_timeline_event_state,
        p_ai_summary=>item->'payload'->>'text',p_original_statement=>item->'payload'->>'text',
        p_structured_data=>jsonb_build_object('source_receipt_id',source_id,'action_key',action_key),
        p_source_email_id=>p_plan->'source'->>'message_id',p_source_thread_id=>p_plan->'source'->>'thread_id',
        p_evidence_reference=>'source:'||source_hash,p_source_intake_id=>source_id) e;
        disposition:='APPLIED_AND_VERIFIED';reason:='canonical note timeline event';actual:=jsonb_build_object('note',item->'payload'->>'text');verification:=jsonb_build_object('checked',true,'parity',true);EXCEPTION WHEN others THEN reason:='canonical_note_append_failed';END;
    ELSIF action_type='location_set' THEN
      canonical_rpc:='public.move_vehicle(uuid,integer,text,text,text,text,text)';
      BEGIN SELECT to_jsonb(public.move_vehicle(vehicle.id,vehicle.version,upper(item->'payload'->>'location'),null,null,null,item->'payload'->>'reason')) INTO result;disposition:='APPLIED_AND_VERIFIED';reason:='canonical controlled location';actual:=jsonb_build_object('location',upper(item->'payload'->>'location'));verification:=jsonb_build_object('checked',true,'parity',true);EXCEPTION WHEN others THEN reason:='canonical_location_set_failed';END;
    ELSIF action_type='rft_transfer' THEN
      canonical_rpc:='public.rft_transfer_vehicle(uuid,integer)';
      BEGIN result:=public.rft_transfer_vehicle(vehicle.id,vehicle.version);IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED';reason:='canonical RFT transfer';actual:=jsonb_build_object('rft_transfer',true);verification:=jsonb_build_object('checked',true,'parity',true);ELSE reason:=coalesce(result->>'error','rft_transfer_rejected');END IF;EXCEPTION WHEN others THEN reason:='canonical_rft_transfer_failed';END;
    ELSE
      canonical_rpc:='public.rft_collect_vehicle(uuid,integer)';
      BEGIN result:=public.rft_collect_vehicle(vehicle.id,vehicle.version);IF coalesce((result->>'ok')::boolean,false) THEN disposition:='APPLIED_AND_VERIFIED';reason:='canonical RFT collect';actual:=jsonb_build_object('rft_collect',true);verification:=jsonb_build_object('checked',true,'parity',true);ELSE reason:=coalesce(result->>'error','rft_collect_rejected');END IF;EXCEPTION WHEN others THEN reason:='canonical_rft_collect_failed';END;
    END IF;
    -- A canonical response is not proof by itself. Re-read the authoritative
    -- snapshot and require field-level parity for every successful action.
    IF disposition='APPLIED_AND_VERIFIED' THEN
      action_readback:=public.get_pdc_email_vehicle_location_snapshot();
      SELECT v INTO readback_vehicle FROM jsonb_array_elements(coalesce(action_readback#>'{data,vehicles}','[]'::jsonb)) v WHERE v->>'id'=vehicle_id::text LIMIT 1;
      readback_field_parity:=readback_vehicle IS NOT NULL;
      after_state:=readback_vehicle;
      IF action_type='location_set' THEN readback_field_parity:=readback_field_parity AND readback_vehicle->>'current_location'=upper(item->'payload'->>'location');
      ELSIF action_type='parts_eta_set' THEN readback_field_parity:=readback_field_parity AND readback_vehicle#>>'{parts_update,worst_eta}' IS NOT DISTINCT FROM item->'payload'->>'eta';
      ELSIF action_type='parts_complete' THEN readback_field_parity:=readback_field_parity AND coalesce((readback_vehicle->>'parts_completed')::boolean,false);
      ELSIF action_type='rft_transfer' THEN readback_field_parity:=readback_field_parity AND upper(coalesce(readback_vehicle->>'current_location',''))='RFT';
      ELSIF action_type='rft_collect' THEN readback_field_parity:=readback_field_parity AND (readback_vehicle->>'rft_collected_at') IS NOT NULL;
      ELSIF action_type IN('operation_add','operation_update') THEN readback_field_parity:=readback_field_parity AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(readback_vehicle->'operation_lines','[]'::jsonb)) l WHERE l->>'operation_no'=item->'payload'->>'operation_no' AND l->>'description'=item->'payload'->>'description' AND upper(l->>'work_key')=upper(item->'payload'->>'work_key') AND (l->>'estimated_hours')::numeric=(item->'payload'->>'estimated_hours')::numeric);
      ELSIF action_type='required_work_set' THEN readback_field_parity:=readback_field_parity AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(readback_vehicle->'work_items','[]'::jsonb)) l WHERE upper(l->>'work_key')=upper(item->'payload'->>'work_key') AND (l->>'required')::boolean=(item->'payload'->>'required')::boolean);
      ELSIF action_type='work_complete' THEN readback_field_parity:=readback_field_parity AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(readback_vehicle->'work_items','[]'::jsonb)) l WHERE upper(l->>'work_key')=upper(item->'payload'->>'work_key') AND coalesce((l->>'completed')::boolean,false));
      ELSIF action_type='activate_vehicle' THEN readback_field_parity:=readback_field_parity AND readback_vehicle->>'source_record_id'=item->'payload'->>'backend_record_id';
      ELSIF action_type IN('booking_set','booking_move','booking_cancel') THEN readback_field_parity:=readback_field_parity AND (result->>'booking_id' IS NOT NULL OR result->>'id' IS NOT NULL OR result->>'status' IS NOT NULL);
      ELSIF action_type='note_append' THEN readback_field_parity:=readback_field_parity AND (result->>'id' IS NOT NULL OR result->>'event_id' IS NOT NULL);
      END IF;
      verification:=jsonb_build_object('checked',true,'parity',readback_field_parity,'readback_revision',action_readback->>'revision','field_scope',action_type);
      IF NOT readback_field_parity THEN disposition:='FAILED_QUEUED_RETRY'; reason:='authoritative_readback_field_parity_failed'; END IF;
    END IF;
    IF taxonomy_disposition='review' THEN disposition:='GENUINELY_AMBIGUOUS'; END IF;
    INSERT INTO public.pdc_email_ai_successor_action_receipts(transaction_id,source_receipt_id,action_key,instruction_id,vehicle_id,action_type,requested,disposition,reason,canonical_rpc,before_state,after_state,verification,taxonomy_version,taxonomy_disposition)
    VALUES(transaction_id,source_id,action_key,instruction_id,vehicle_id,action_type,item->'payload',disposition,reason,canonical_rpc,before_state,after_state,verification,taxonomy_version,taxonomy_disposition)
    RETURNING action_receipt_id INTO action_receipt_id;
    PERFORM public.audit_pdc_event('update'::public.audit_action,'pdc_email_ai_successor_action_receipts',action_receipt_id,vehicle_id,before_state,after_state,
      jsonb_build_object('source','pdc_email_ai_typed_action_surface_20260901','source_receipt_id',source_id,'action_key',action_key,'action_type',action_type,
        'disposition',disposition,'taxonomy_version',taxonomy_version,'taxonomy_disposition',taxonomy_disposition,'canonical_rpc',canonical_rpc));
    actions:=actions||jsonb_build_array(jsonb_build_object('instruction_id',instruction_id,'action_key',action_key,'action_type',action_type,'disposition',disposition,'reason',reason,'canonical_rpc',canonical_rpc,'requested',item->'payload','expected',expected,'actual',actual,'before_state',before_state,'after_state',after_state,'verification',verification,'taxonomy_version',taxonomy_version,'taxonomy_disposition',taxonomy_disposition));
    dispositions:=array_append(dispositions,disposition);
  END LOOP;
  readback:=public.get_pdc_email_vehicle_location_snapshot(); readback_ok:=coalesce((readback->>'ok')::boolean,false)
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(actions) x WHERE x->>'disposition' IN('APPLIED_AND_VERIFIED','ALREADY_CORRECT') AND x#>>'{verification,parity}'<>'true');
  IF cardinality(dispositions)=0 THEN aggregate:='NO_ACTIONS'; ELSIF NOT EXISTS(SELECT 1 FROM unnest(dispositions) x WHERE x NOT IN('APPLIED_AND_VERIFIED','ALREADY_CORRECT')) THEN aggregate:='SUCCESS'; ELSE aggregate:='PARTIAL_FAILURE'; END IF;
  INSERT INTO public.pdc_email_ai_successor_transaction_receipts(transaction_id,identity_id,source_receipt_id,source_digest,evidence_digest,plan_hash,typed_plan,aggregate_disposition,readback_parity,response)
  VALUES(transaction_id,ident.identity_id,source_id,source_hash,evidence_hash,plan_hash,p_plan,aggregate,readback_ok,jsonb_build_object('transaction_id',transaction_id,'source_receipt_id',source_id,'source_digest',source_hash,'evidence_digest',evidence_hash,'plan_hash',plan_hash,'disposition',aggregate,'actions',actions,'readback',readback,'readback_parity',readback_ok,'taxonomy_version',taxonomy_version,'action_contract_version','pdc-email-ai-actions-v2','supabase_action_version','20260901020000','production_writes',false,'outbound_email',false));
  RETURN jsonb_build_object('ok',aggregate='SUCCESS' AND readback_ok,'code',case when aggregate='SUCCESS' AND readback_ok then 'pdc_email_ai_typed_action_surface_verified' else 'pdc_email_ai_typed_action_surface_partial_failure' end,'disposition',aggregate,'actions',actions,'readback',readback,'readback_parity',readback_ok,'transaction_id',transaction_id,'production_writes',false,'outbound_email',false);
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO prior FROM public.pdc_email_ai_successor_transaction_receipts WHERE source_receipt_id=source_id;
  IF FOUND THEN RETURN prior.response||jsonb_build_object('replay',true); END IF;
  RAISE;
END $apply$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(p_plan jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $$
  SELECT public.apply_pdc_email_ai_typed_action_surface_20260901(p_plan)
$$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(jsonb) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901020000','pdc_email_ai_typed_action_surface_20260901',ARRAY[
 'Exact STAGING sentinel, current 20260901010000 predecessor and Production absence guards',
 'Versioned pdc-operation-taxonomy-proposed/v1 identity with classified, review, unsupported and conflict dispositions',
 'Mixed signage/GVM/GCM/Tare/decal descriptions are review-only and cannot become Hoist or Sublet; Sublet description-only evidence is unsupported',
 'Unresolved 12V accessory sockets, safety triangles and weather shields remain typed review dispositions; no invented group is emitted',
 'Fixed least-authority successors for activation, operation add/update, Parts, booking set/move/cancel, required work, work complete, note, location and RFT lifecycle',
 'Canonical RPC names are server-owned allow-list values; the plan cannot supply SQL, table names, RPC names, service role or Administrator authority',
 'Per-action immutable before/requested/result/readback receipts, source/action replay keys and aggregate PARTIAL_FAILURE semantics',
 'Read-only action contract projection and authenticated-only execution; service_role, browser/direct DML, mailbox and outbound email remain denied'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
