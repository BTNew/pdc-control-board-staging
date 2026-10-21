-- r423 undo: restores mark_pdc_parts_received_authenticated_751, save_vehicle_workshop_line_hours_batch_768,
-- get_pdc_sublet_audit_ledgers and pdc_codex_intake_private.workshop_read_actor_scope_20261013 byte for byte, drops the helper,
-- the r423 pins and the check. Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r423 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r423 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r423 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r423 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_auditor_actor_scope()'::regprocedure) IS NULL THEN RAISE EXCEPTION 'r423 undo: auditor scope missing'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid)','76009ec1c98724573d7fa4b8352200c9','2ec4e303b1df9202aaca2ff82a7a3263'),
  ('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)','e21c5c8901714498c71b75ea9caaf812','27cb510615d31f22efd39d88c2f1337f'),
  ('public.get_pdc_sublet_audit_ledgers(uuid,text,text)','ec8797973cf9a6a5dd34942a28810831','d5adb179eda18913ea2c201f56bde19c'),
  ('pdc_codex_intake_private.workshop_read_actor_scope_20261013()','40bf35bd9a5d0986a298f900ffcb941d','109f9e9040eba64a6048078e073a1180')) e(sig,m,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m AND md5(coalesce(p.proacl::text,'')||p.prosecdef::text||p.provolatile::text||p.proowner::regrole::text||coalesce(array_to_string(p.proconfig,'|'),''))=e.a)<>4 THEN RAISE EXCEPTION 'r423 undo: functions are not the r423 versions; not undoing over unknown changes'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_workshop_controller_scope_423()'::regprocedure)<>'beaeee86e392762bda301a334d340604' THEN RAISE EXCEPTION 'r423 undo: helper is not the r423 version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r423')<>5 THEN RAISE EXCEPTION 'r423 undo: r423 pins not as expected'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.mark_pdc_parts_received_authenticated_751(p_vehicle_id uuid, p_stock_number text, p_expected_version integer, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'auth'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_claim_role text:=lower(btrim(coalesce(auth.jwt()->>'role','')));
  v_role text;
  v_role_count integer;
  v_scope_count integer;
  v_actor_dealer text;
  v_dealer text;
  v_stock text:=public.normalize_vehicle_stock_number(p_stock_number);
  v_vehicle public.vehicles%rowtype;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
  v_work_before public.vehicle_work_items%rowtype;
  v_work_after public.vehicle_work_items%rowtype;
  v_existing public.pdc_authenticated_parts_received_receipts_751%rowtype;
  v_receipt_id uuid;
  v_revision_before bigint;
  v_revision_after bigint;
  v_request_payload jsonb;
  v_request_sha text;
  v_before_state jsonb;
  v_after_state jsonb;
  v_result jsonb;
  v_clear_stoppage boolean;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR v_actor IS NULL OR v_claim_role<>'authenticated'
     OR p_vehicle_id IS NULL OR p_expected_version IS NULL
     OR p_idempotency_key IS NULL OR v_stock IS NULL OR v_stock=''
  THEN RETURN public.navision_backend_response(false,'invalid_input'); END IF;

  SELECT count(*),min(r.role::text) INTO v_role_count,v_role
  FROM public.pdc_user_roles r
  JOIN auth.users u ON u.id=v_actor AND lower(coalesce(u.email,''))=v_email
  WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
    AND r.active AND r.account_status='approved'
    AND r.role::text IN('operator','administrator');
  IF v_role_count<>1 OR v_role NOT IN('operator','administrator') THEN
    RETURN public.navision_backend_response(false,'permission_denied');
  END IF;

  v_request_payload:=jsonb_build_object(
    'contract','pdc-authenticated-parts-received-751',
    'environment','staging','vehicle_id',p_vehicle_id,
    'stock_number',v_stock,'expected_version',p_expected_version,
    'idempotency_key',p_idempotency_key);
  v_request_sha:=encode(extensions.digest(convert_to(v_request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-751-idempotency:'||p_idempotency_key::text,0));
  SELECT * INTO v_existing
  FROM public.pdc_authenticated_parts_received_receipts_751
  WHERE idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_sha256<>v_request_sha
       OR v_existing.vehicle_id<>p_vehicle_id
       OR v_existing.expected_version<>p_expected_version
       OR v_existing.actor_id<>v_actor
       OR v_existing.stock_number<>v_stock
    THEN RETURN public.navision_backend_response(false,'parts_receipt_idempotency_conflict'); END IF;
    RETURN jsonb_build_object('ok',true,'code','replayed','replay',true,
      'data',(v_existing.response->'data')||jsonb_build_object('changed',false));
  END IF;

  SELECT * INTO v_vehicle
  FROM public.vehicles
  WHERE id=p_vehicle_id AND stock_number_normalized=v_stock
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.navision_backend_response(false,'vehicle_identity_mismatch');
  END IF;
  IF v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' THEN
    RETURN public.navision_backend_response(false,'not_in_active_lifecycle');
  END IF;
  IF NOT v_vehicle.visible_on_board THEN
    RETURN public.navision_backend_response(false,'vehicle_not_visible');
  END IF;

  v_dealer:=public.pdc_auditor_vehicle_dealer(v_vehicle.id);
  IF v_dealer IS NULL OR v_dealer<>v_vehicle.source_batch_id THEN
    RETURN public.navision_backend_response(false,'canonical_identity_mismatch');
  END IF;
  IF v_role<>'administrator' THEN
    SELECT count(*),min(s.dealer_code) INTO v_scope_count,v_actor_dealer
    FROM public.pdc_auditor_user_dealer_scopes s
    WHERE s.auth_user_id=v_actor AND s.normalized_email=v_email
      AND s.environment='staging' AND s.active;
    IF v_scope_count<>1 OR v_actor_dealer<>v_dealer
       OR NOT public.pdc_auditor_entity_in_scope(v_actor_dealer,'vehicle',v_vehicle.id)
    THEN RETURN public.navision_backend_response(false,'dealer_scope_denied'); END IF;
  END IF;
  IF v_vehicle.version<>p_expected_version THEN
    RETURN public.navision_backend_response(false,'vehicle_version_conflict',
      jsonb_build_object('current_version',v_vehicle.version,'vehicle_id',v_vehicle.id,'stock_number',v_stock));
  END IF;

  SELECT * INTO v_parts_before FROM public.vehicle_parts_updates
  WHERE vehicle_id=v_vehicle.id ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE;
  SELECT * INTO v_work_before FROM public.vehicle_work_items
  WHERE vehicle_id=v_vehicle.id AND upper(work_key)='PARTS'
  ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE;
  IF NOT coalesce(v_parts_before.parts_required,false) THEN
    RETURN public.navision_backend_response(false,'parts_not_required');
  END IF;
  IF NOT coalesce(v_parts_before.parts_ordered,false) THEN
    RETURN public.navision_backend_response(false,'parts_not_ordered');
  END IF;
  IF coalesce(v_parts_before.parts_received,false) OR coalesce(v_work_before.completed,false) THEN
    RETURN public.navision_backend_response(false,'parts_already_received');
  END IF;

  v_receipt_id:=extensions.uuid_generate_v5(
    '75100000-0000-5000-8000-000000000751'::uuid,p_idempotency_key::text);
  v_clear_stoppage:=coalesce(v_parts_before.parts_stoppage,false);
  v_before_state:=jsonb_build_object(
    'vehicle',jsonb_build_object('id',v_vehicle.id,'stock_number',v_vehicle.stock_number,
      'dealer_code',v_dealer,'version',v_vehicle.version,
      'lifecycle_state',v_vehicle.lifecycle_state::text,'current_location',v_vehicle.current_location,
      'visible_on_board',v_vehicle.visible_on_board),
    'parts',case when v_parts_before.id IS NULL then '{}'::jsonb else to_jsonb(v_parts_before) end,
    'work_item',case when v_work_before.id IS NULL then '{}'::jsonb else to_jsonb(v_work_before) end,
    'actor_role',v_role);

  PERFORM set_config('pdc.parts_completion_revision_managed','on',true);
  SELECT revision INTO v_revision_before
  FROM public.pdc_email_vehicle_revision WHERE singleton FOR UPDATE;
  INSERT INTO public.vehicle_parts_updates(
    vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,
    parts_stoppage_reason,worst_eta,updated_by,updated_at)
  VALUES(v_vehicle.id,v_parts_before.parts_required,v_parts_before.parts_ordered,true,
    false,CASE WHEN v_clear_stoppage THEN NULL ELSE v_parts_before.parts_stoppage_reason END,
    CASE WHEN v_clear_stoppage THEN NULL ELSE v_parts_before.worst_eta END,
    v_actor,clock_timestamp()) RETURNING * INTO v_parts_after;
  IF v_work_before.id IS NULL THEN
    INSERT INTO public.vehicle_work_items(
      vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
    VALUES(v_vehicle.id,'PARTS',true,true,v_actor,clock_timestamp(),
      'Parts received from authenticated Parts board',clock_timestamp())
    RETURNING * INTO v_work_after;
  ELSE
    UPDATE public.vehicle_work_items SET required=true,completed=true,
      completed_by=v_actor,completed_at=clock_timestamp(),updated_at=clock_timestamp()
    WHERE id=v_work_before.id RETURNING * INTO v_work_after;
  END IF;
  UPDATE public.vehicles SET version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
  WHERE id=v_vehicle.id RETURNING * INTO v_vehicle;

  v_after_state:=jsonb_build_object(
    'vehicle',jsonb_build_object('id',v_vehicle.id,'stock_number',v_vehicle.stock_number,
      'dealer_code',v_dealer,'version',v_vehicle.version,
      'lifecycle_state',v_vehicle.lifecycle_state::text,'current_location',v_vehicle.current_location,
      'visible_on_board',v_vehicle.visible_on_board),
    'parts',to_jsonb(v_parts_after),'work_item',to_jsonb(v_work_after),
    'actor_role',v_role);
  PERFORM public.audit_pdc_event('insert','vehicle_parts_updates',v_parts_after.id,v_vehicle.id,
    v_before_state->'parts',v_after_state->'parts',jsonb_build_object(
      'contract','pdc-authenticated-parts-received-751','action','mark_parts_received',
      'receipt_id',v_receipt_id,'vehicle_id',v_vehicle.id,'stock_number',v_stock,
      'dealer_code',v_dealer,'actor_role',v_role,'expected_version',p_expected_version,
      'changed',true));
  PERFORM public.audit_pdc_event(case when v_work_before.id IS NULL then 'insert'::public.audit_action else 'update'::public.audit_action end,
    'vehicle_work_items',v_work_after.id,v_vehicle.id,
    case when v_work_before.id IS NULL then NULL else to_jsonb(v_work_before) end,
    to_jsonb(v_work_after),jsonb_build_object(
      'contract','pdc-authenticated-parts-received-751','action','mark_parts_received',
      'receipt_id',v_receipt_id,'vehicle_id',v_vehicle.id,'stock_number',v_stock,
      'dealer_code',v_dealer,'actor_role',v_role,'expected_version',p_expected_version,
      'changed',true));
  UPDATE public.pdc_email_vehicle_revision
  SET revision=revision+1,updated_at=clock_timestamp()
  WHERE singleton RETURNING revision INTO v_revision_after;
  IF v_revision_after IS NULL OR v_revision_after<>v_revision_before+1 THEN
    RAISE EXCEPTION 'PDC_751_REVISION_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;

  v_result:=public.navision_backend_response(true,'parts_completed',jsonb_build_object(
    'receipt_id',v_receipt_id,'vehicle_id',v_vehicle.id,'stock_number',v_stock,
    'dealer_code',v_dealer,'vehicle_version_before',p_expected_version,
    'vehicle_version',v_vehicle.version,'revision_before',v_revision_before,
    'revision',v_revision_after,'changed',true,'parts_received',true,
    'parts_stoppage_cleared',v_clear_stoppage,'location_changed',false,
    'booking_created',false));
  INSERT INTO public.pdc_authenticated_parts_received_receipts_751(
    receipt_id,vehicle_id,actor_id,actor_email,actor_role,dealer_code,stock_number,
    expected_version,idempotency_key,request_sha256,request_payload,before_state,after_state,response)
  VALUES(v_receipt_id,v_vehicle.id,v_actor,v_email,v_role,v_dealer,v_stock,
    p_expected_version,p_idempotency_key,v_request_sha,v_request_payload,v_before_state,v_after_state,v_result);
  IF NOT EXISTS(SELECT 1 FROM public.pdc_authenticated_parts_received_receipts_751
                WHERE receipt_id=v_receipt_id)
     OR v_vehicle.version<>p_expected_version+1
     OR NOT coalesce((v_after_state->'parts'->>'parts_received')::boolean,false)
     OR NOT coalesce((v_after_state->'work_item'->>'completed')::boolean,false)
  THEN RAISE EXCEPTION 'PDC_751_RECEIPT_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  RETURN v_result;
END $function$;

DO $r768$ BEGIN
  EXECUTE $def768$CREATE OR REPLACE FUNCTION public.save_vehicle_workshop_line_hours_batch_768(p_vehicle_id uuid, p_stock_number text, p_job_card_number text, p_expected_vehicle_version bigint, p_estimated_rows jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $def768$ || '$function$' || replace($def768$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_scope jsonb;
  v_vehicle_dealer text;
  v_vehicle public.vehicles%rowtype;
  v_receipt public.vehicle_workshop_hours_batch_receipts_768%rowtype;
  v_rows jsonb:=coalesce(p_estimated_rows,'[]'::jsonb);
  v_canonical_rows jsonb;
  v_request jsonb;
  v_request_hash text;
  v_current_rows jsonb:='[]'::jsonb;
  v_conflicts jsonb:='[]'::jsonb;
  v_changes jsonb:='[]'::jsonb;
  v_revision bigint;
  v_vehicle_after public.vehicles%rowtype;
  v_changed_count integer:=0;
  v_receipt_id uuid:=gen_random_uuid();
BEGIN
  IF v_actor IS NULL OR v_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;
  PERFORM public.require_pdc_role('operator');
  v_scope:=public.pdc_auditor_actor_scope();
  v_vehicle_dealer:=public.pdc_auditor_vehicle_dealer(p_vehicle_id);
  IF v_scope->>'environment' IS DISTINCT FROM 'staging'
     OR NOT public.pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,v_vehicle_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied');
  END IF;

  IF p_vehicle_id IS NULL OR p_idempotency_key IS NULL
    OR nullif(btrim(coalesce(p_stock_number,'')),'') IS NULL
    OR nullif(btrim(coalesce(p_job_card_number,'')),'') IS NULL
    OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
    OR jsonb_typeof(v_rows)<>'array' OR jsonb_array_length(v_rows) NOT BETWEEN 1 AND 250
    OR EXISTS(
      SELECT 1 FROM jsonb_array_elements(v_rows) x
      WHERE jsonb_typeof(x)<>'object'
        OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x) k)
           IS DISTINCT FROM ARRAY['adjustment_id','estimated_hours','expected_line_version','line_key','operation_line_id','stage_code','work_key']::text[]
        OR coalesce(x->>'operation_line_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        OR coalesce(x->>'line_key','')<>('source:'||lower(coalesce(x->>'operation_line_id','')))
        OR coalesce(x->>'work_key','')<>lower(btrim(coalesce(x->>'work_key','')))
        OR coalesce(x->>'work_key','') IN ('parts','pit_inspection','unallocated_mapping_review')
        OR coalesce(x->>'stage_code','')<>upper(btrim(coalesce(x->>'stage_code','')))
        OR coalesce(x->>'stage_code','') !~ '^[A-Z][A-Z0-9_]{1,39}$'
        OR coalesce(x->>'expected_line_version','') !~ '^[0-9]+$'
        OR jsonb_typeof(x->'adjustment_id') IS NULL
        OR (jsonb_typeof(x->'adjustment_id')='string' AND coalesce(x->>'adjustment_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        OR jsonb_typeof(x->'adjustment_id') NOT IN ('string','null')
        OR jsonb_typeof(x->'estimated_hours') IS NULL
        OR jsonb_typeof(x->'estimated_hours') NOT IN ('number','null')
        OR (jsonb_typeof(x->'estimated_hours')='number' AND (
          coalesce(x->>'estimated_hours','') !~ '^(0|[0-9]+)(\.[0-9]{1,2})?$'
          OR (x->>'estimated_hours')::numeric<0 OR (x->>'estimated_hours')::numeric>999.99
        ))
    )
    OR (SELECT count(*) FROM jsonb_array_elements(v_rows))
      <>(SELECT count(DISTINCT lower(x->>'operation_line_id')) FROM jsonb_array_elements(v_rows) x)
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_hours_batch'); END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY lower(x->>'operation_line_id')),'[]'::jsonb)
    INTO v_canonical_rows FROM jsonb_array_elements(v_rows) x;
  v_request:=jsonb_build_object(
    'contract','vehicle_workshop_hours_batch_768.1','actor_id',v_actor,'vehicle_id',p_vehicle_id,
    'stock_number',btrim(p_stock_number),'job_card_number',btrim(p_job_card_number),
    'expected_vehicle_version',p_expected_vehicle_version,'estimated_rows',v_canonical_rows,
    'idempotency_key',p_idempotency_key);
  v_request_hash:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-workshop-hours-batch:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_receipt FROM public.vehicle_workshop_hours_batch_receipts_768
   WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_receipt.request_hash<>v_request_hash THEN
      RETURN jsonb_build_object('ok',false,'code','idempotency_conflict','data',jsonb_build_object('receipt_id',v_receipt.receipt_id));
    END IF;
    RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  SELECT * INTO v_vehicle FROM public.vehicles
   WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF btrim(coalesce(v_vehicle.stock_number::text,''))<>btrim(p_stock_number) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_identity_conflict','data',jsonb_build_object('vehicle_id',p_vehicle_id));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_request_t780 ON COMMIT DROP AS
  SELECT lower(x->>'operation_line_id')::uuid operation_line_id,
    NULLIF(x->>'adjustment_id','')::uuid adjustment_id,
    (x->>'expected_line_version')::bigint expected_line_version,
    x->>'line_key' line_key,upper(x->>'stage_code') stage_code,lower(x->>'work_key') work_key,
    CASE WHEN jsonb_typeof(x->'estimated_hours')='null' THEN NULL ELSE (x->>'estimated_hours')::numeric END estimated_hours
  FROM jsonb_array_elements(v_rows) x;
  CREATE UNIQUE INDEX ON pdc_hours_batch_request_t780(operation_line_id);

  -- Use the same canonical, current category projection as Vehicle Locations.
  -- Legacy classification history can be absent after an accepted source update.
  CREATE TEMP TABLE pdc_hours_batch_source_t780 ON COMMIT DROP AS
  SELECT (l->>'source_line_id')::uuid operation_line_id,p_vehicle_id vehicle_id,
    coalesce(l->>'source_contract','authenticated') source_contract,
    l->>'job_card_number' job_card_number,
    CASE l->>'stage_code' WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(l->>'stage_code') END work_key,
    l->>'stage_code' stage_code,l->>'description' description,
    (l->>'source_estimated_hours')::numeric source_estimated_hours,
    (l->>'estimated_hours')::numeric effective_estimated_hours,
    l->>'operation_no' operation_no,(l->>'original_line_number')::integer display_order
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  JOIN pdc_hours_batch_request_t780 r ON r.line_key=l->>'line_identity'
    AND r.operation_line_id::text=l->>'source_line_id'
  WHERE coalesce((l->>'active')::boolean,true)
    AND NOT coalesce((l->>'completed')::boolean,false)
    AND NOT coalesce((l->>'rejected')::boolean,false)
    AND l->>'source_kind'='authenticated';
  CREATE UNIQUE INDEX ON pdc_hours_batch_source_t780(operation_line_id);

  IF EXISTS(SELECT 1 FROM pdc_hours_batch_request_t780 WHERE work_key='parts' OR stage_code='PARTS') THEN
    RETURN jsonb_build_object('ok',false,'code','parts_not_hour_bearing','data',jsonb_build_object('vehicle_id',p_vehicle_id,'booking_created',false,'parts_mutated',false));
  END IF;

  PERFORM 1 FROM public.vehicle_workshop_line_adjustments a
   JOIN pdc_hours_batch_request_t780 r ON r.line_key=a.line_key
   WHERE a.vehicle_id=p_vehicle_id FOR UPDATE;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'line_key',r.line_key,'work_key',r.work_key,'stage_code',r.stage_code,
    'source_contract',s.source_contract,'source_estimated_hours',s.source_estimated_hours,
    'adjustment_id',a.adjustment_id,'line_version',coalesce(a.version,0),
    'estimated_hours',CASE WHEN a.adjustment_id IS NOT NULL AND a.active THEN a.estimated_hours ELSE s.effective_estimated_hours END,
    'active',coalesce(a.active,true)
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_current_rows
  FROM pdc_hours_batch_request_t780 r
  LEFT JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key;

  IF v_vehicle.version<>p_expected_vehicle_version THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'current_rows',v_current_rows));
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'requested_work_key',r.work_key,'requested_stage_code',r.stage_code,
    'requested_line_version',r.expected_line_version,'source_contract',s.source_contract,
    'current_work_key',s.work_key,'current_stage_code',s.stage_code,
    'current_adjustment_id',a.adjustment_id,'current_line_version',coalesce(a.version,0),
    'reason',CASE
      WHEN s.operation_line_id IS NULL THEN 'operation_line_not_found'
      WHEN coalesce(a.active,true)=false THEN 'operation_line_adjustment_inactive'
      WHEN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) header WHERE header->>'job_card_number'=btrim(p_job_card_number)) THEN 'job_card_identity_conflict'
      WHEN s.work_key<>r.work_key THEN 'work_key_conflict'
      WHEN s.stage_code<>r.stage_code THEN 'stage_identity_conflict'
      WHEN a.adjustment_id IS DISTINCT FROM r.adjustment_id THEN 'adjustment_identity_conflict'
      WHEN coalesce(a.version,0)<>r.expected_line_version THEN 'line_version_conflict'
      ELSE 'row_drift'
    END
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_conflicts
  FROM pdc_hours_batch_request_t780 r
  LEFT JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE s.operation_line_id IS NULL OR coalesce(a.active,true)=false
     OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) header WHERE header->>'job_card_number'=btrim(p_job_card_number))
     OR s.work_key IS DISTINCT FROM r.work_key OR s.stage_code IS DISTINCT FROM r.stage_code
     OR a.adjustment_id IS DISTINCT FROM r.adjustment_id OR coalesce(a.version,0)<>r.expected_line_version;
  IF jsonb_array_length(v_conflicts)>0 THEN
    RETURN jsonb_build_object('ok',false,'code','line_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'conflicts',v_conflicts,'current_rows',v_current_rows));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_changes_t780 ON COMMIT DROP AS
  SELECT r.operation_line_id,r.adjustment_id current_adjustment_id,r.expected_line_version,
    r.line_key,r.stage_code,r.work_key,r.estimated_hours,s.source_contract,s.job_card_number,s.description source_description,
    s.source_estimated_hours,s.effective_estimated_hours source_effective_hours,s.operation_no,s.display_order,
    CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE s.effective_estimated_hours END current_estimated_hours,
    coalesce(a.version,0) current_line_version
  FROM pdc_hours_batch_request_t780 r
  JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE r.estimated_hours IS DISTINCT FROM CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE s.effective_estimated_hours END;
  SELECT count(*) INTO v_changed_count FROM pdc_hours_batch_changes_t780;

  IF v_changed_count>0 THEN
    UPDATE public.vehicle_workshop_line_adjustments a SET
      stage_code=c.stage_code,
      description=c.source_description,
      estimated_hours=c.estimated_hours,
      correction_origin=CASE WHEN c.estimated_hours IS NULL THEN 'manual_operator_unknown' ELSE 'manual_operator' END,
      active=true,
      version=a.version+1,
      updated_by=v_actor,
      updated_at=clock_timestamp()
    FROM pdc_hours_batch_changes_t780 c
    WHERE a.adjustment_id=c.current_adjustment_id
      AND a.vehicle_id=p_vehicle_id;

    INSERT INTO public.vehicle_workshop_line_adjustments(
      vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,active,version,
      created_by,updated_by,source_operation_line_id,job_card_number,operation_code,display_order,manual_assignment_locked
    )
    SELECT p_vehicle_id,c.line_key,'source',c.stage_code,c.source_description,c.estimated_hours,
      CASE WHEN c.estimated_hours IS NULL THEN 'manual_operator_unknown' ELSE 'manual_operator' END,
      true,1,v_actor,v_actor,CASE WHEN c.source_contract='authenticated' THEN c.operation_line_id ELSE NULL END,
      c.job_card_number,c.operation_no,c.display_order,false
    FROM pdc_hours_batch_changes_t780 c WHERE c.current_adjustment_id IS NULL
    ON CONFLICT(vehicle_id,line_key) DO UPDATE SET
      stage_code=excluded.stage_code,description=excluded.description,estimated_hours=excluded.estimated_hours,
      correction_origin=excluded.correction_origin,
      active=true,version=public.vehicle_workshop_line_adjustments.version+1,updated_by=v_actor,updated_at=clock_timestamp();

    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'operation_line_id',c.operation_line_id,'line_key',c.line_key,'work_key',c.work_key,'source_contract',c.source_contract,
      'source_estimated_hours',c.source_estimated_hours,
      'before',jsonb_build_object('adjustment_id',c.current_adjustment_id,'estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      'after',jsonb_build_object('adjustment_id',a.adjustment_id,'estimated_hours',a.estimated_hours,'version',a.version,'correction_origin',a.correction_origin)
    ) ORDER BY c.operation_line_id),'[]'::jsonb) INTO v_changes
    FROM pdc_hours_batch_changes_t780 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    SELECT CASE WHEN c.current_adjustment_id IS NULL THEN 'insert'::public.audit_action ELSE 'update'::public.audit_action END,
      'vehicle_workshop_line_adjustments',a.adjustment_id,p_vehicle_id,v_actor,v_email,
      jsonb_build_object('adjustment_id',c.current_adjustment_id,'operation_line_id',c.operation_line_id,
        'source_contract',c.source_contract,'source_estimated_hours',c.source_estimated_hours,
        'effective_estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      jsonb_build_object('adjustment_id',a.adjustment_id,'operation_line_id',c.operation_line_id,
        'source_contract',c.source_contract,'source_estimated_hours',c.source_estimated_hours,
        'effective_estimated_hours',a.estimated_hours,'version',a.version,'correction_origin',a.correction_origin),
      jsonb_build_object('source','vehicle_workshop_hours_batch_768.1','request_id',p_idempotency_key,
        'request_hash',v_request_hash,'bookings_changed',false,'parts_changed',false,'completion_changed',false)
    FROM pdc_hours_batch_changes_t780 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    UPDATE public.vehicles SET version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
    WHERE id=p_vehicle_id RETURNING * INTO v_vehicle_after;
  ELSE
    v_vehicle_after:=v_vehicle;
  END IF;

  SELECT revision INTO v_revision FROM public.pdc_email_vehicle_revision WHERE singleton;
  v_receipt.response:=jsonb_build_object('ok',true,'code',CASE WHEN v_changed_count>0 THEN 'workshop_hours_batch_saved' ELSE 'workshop_hours_batch_no_changes' END,
    'replay',false,'receipt_id',v_receipt_id,'request_sha256',v_request_hash,'vehicle_id',p_vehicle_id,
    'vehicle_version_before',v_vehicle.version,'vehicle_version_after',v_vehicle_after.version,
    'revision',v_revision,'changed_count',v_changed_count,'changes',v_changes,
    'booking_created',false,'parts_mutated',false,'completion_changed',false);
  INSERT INTO public.vehicle_workshop_hours_batch_receipts_768(
    receipt_id,idempotency_key,actor_id,vehicle_id,request_hash,base_vehicle_version,response)
  VALUES(v_receipt_id,p_idempotency_key,v_actor,p_vehicle_id,v_request_hash,v_vehicle.version,v_receipt.response)
  RETURNING * INTO v_receipt;
  RETURN v_receipt.response;
END $def768$, E'\n', E'\r\n') || '$function$';
END $r768$;


CREATE OR REPLACE FUNCTION public.get_pdc_sublet_audit_ledgers(p_vehicle_id uuid, p_stock_number text, p_job_card_number text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'auth'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_scope jsonb;
  v_dealer text;
  v_vehicle public.vehicles%rowtype;
  v_result jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR v_actor IS NULL
     OR coalesce(auth.jwt()->>'role','')<>'authenticated'
     OR p_vehicle_id IS NULL
     OR nullif(btrim(coalesce(p_stock_number,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_job_card_number,'')),'') IS NULL
  THEN RETURN public.navision_backend_response(false,'invalid_input'); END IF;

  v_scope:=public.pdc_auditor_actor_scope();
  v_dealer:=nullif(btrim(v_scope->>'dealer_code'),'');
  IF coalesce(v_scope->>'environment','')<>'staging'
     OR (v_scope->>'user_id')::uuid IS DISTINCT FROM v_actor
     OR coalesce(v_scope->>'email','')<>v_email
     OR v_dealer IS NULL
  THEN RETURN public.navision_backend_response(false,'dealer_scope_denied'); END IF;

  SELECT * INTO v_vehicle
  FROM public.vehicles
  WHERE id=p_vehicle_id
    AND deleted_at IS NULL
    AND lifecycle_state='active'
    AND visible_on_board
  FOR SHARE;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'vehicle_not_found'); END IF;
  IF v_vehicle.stock_number IS DISTINCT FROM btrim(p_stock_number)
     OR v_vehicle.job_card_number IS DISTINCT FROM btrim(p_job_card_number)
     OR v_vehicle.source_batch_id IS DISTINCT FROM v_dealer
  THEN RETURN public.navision_backend_response(false,'canonical_identity_mismatch'); END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.navision_backend_records r
    WHERE r.id::text=v_vehicle.source_record_id
      AND r.source_system='microsoft_navision'
      AND r.dealer_code=v_dealer
      AND r.is_current
      AND r.record_status='current'
  ) THEN RETURN public.navision_backend_response(false,'dealer_scope_denied'); END IF;

  v_result:=jsonb_build_object(
    'vehicle_id',v_vehicle.id,
    'stock_number',v_vehicle.stock_number,
    'job_card_number',v_vehicle.job_card_number,
    'dealer_code',v_dealer,
    'vehicle_version',v_vehicle.version,
    'active_booking_count',(
      SELECT count(*) FROM public.pdc_sublet_booking_instances b
      WHERE b.vehicle_id=v_vehicle.id AND b.status='active'
    ),
    'booking_instances',coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'booking_id',b.booking_id,
        'vehicle_id',b.vehicle_id,
        'vehicle_version',b.vehicle_version,
        'provider_id',b.provider_id,
        'provider_name',b.provider_name,
        'provider_email',b.provider_email,
        'out_date',b.out_date,
        'expected_return_date',b.expected_return_date,
        'status',b.status,
        'returned_at',b.returned_at,
        'cancelled_at',b.cancelled_at,
        'version',b.version,
        'source_kind',b.source_kind,
        'source_ref',b.source_ref,
        'created_at',b.created_at,
        'updated_at',b.updated_at
      ) ORDER BY b.out_date,b.booking_id)
      FROM public.pdc_sublet_booking_instances b
      WHERE b.vehicle_id=v_vehicle.id
    ),'[]'::jsonb),
    'booking_history',coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'history_id',h.history_id,
        'booking_id',h.booking_id,
        'vehicle_id',h.vehicle_id,
        'actor_id',h.actor_id,
        'actor_email',h.actor_email,
        'action',h.action,
        'booking_version',h.booking_version,
        'before_data',CASE WHEN h.before_data IS NULL THEN NULL ELSE jsonb_build_object(
          'booking_id',h.before_data->'booking_id',
          'vehicle_id',h.before_data->'vehicle_id',
          'provider_id',h.before_data->'provider_id',
          'provider_name',h.before_data->'provider_name',
          'out_date',h.before_data->'out_date',
          'expected_return_date',h.before_data->'expected_return_date',
          'status',h.before_data->'status',
          'version',h.before_data->'version'
        ) END,
        'after_data',jsonb_build_object(
          'booking_id',h.after_data->'booking_id',
          'vehicle_id',h.after_data->'vehicle_id',
          'provider_id',h.after_data->'provider_id',
          'provider_name',h.after_data->'provider_name',
          'out_date',h.after_data->'out_date',
          'expected_return_date',h.after_data->'expected_return_date',
          'status',h.after_data->'status',
          'version',h.after_data->'version'
        ),
        'evidence',h.evidence,
        'event_at',h.event_at
      ) ORDER BY h.event_at,h.history_id)
      FROM public.pdc_sublet_booking_instance_history h
      WHERE h.vehicle_id=v_vehicle.id
    ),'[]'::jsonb),
    'email_update_receipts',coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'receipt_id',r.receipt_id,
        'replay_key',r.replay_key,
        'booking_id',r.booking_id,
        'vehicle_id',r.vehicle_id,
        'provider_id',r.provider_id,
        'provider_name',r.provider_name,
        'sender_email',r.sender_email,
        'message_id',r.message_id,
        'attachment_sha256',r.attachment_sha256,
        'language_kind',r.language_kind,
        'prior_version',r.prior_version,
        'resulting_version',r.resulting_version,
        'applied_out_date',r.applied_out_date,
        'applied_expected_return_date',r.applied_expected_return_date,
        'received_at',r.received_at,
        'applied_at',r.applied_at,
        'applied_by',r.applied_by
      ) ORDER BY r.applied_at,r.receipt_id)
      FROM public.pdc_sublet_email_update_receipts r
      WHERE r.vehicle_id=v_vehicle.id
    ),'[]'::jsonb)
  );
  RETURN public.navision_backend_response(true,'ok',v_result);
END $function$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_actor_scope_20261013()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ DECLARE s jsonb; BEGIN
 s:=pdc_codex_intake_private.workshop_delegated138_identity_20261013(auth.uid(),auth.jwt()->>'email');
 IF s IS NOT NULL THEN RETURN s; END IF;
 RETURN public.pdc_auditor_actor_scope();
END $function$;

DELETE FROM pdc_ops.expected_function_md5 WHERE release='r423';
DELETE FROM pdc_ops.regression_checks WHERE check_name='controllers_use_dealer_scoped_actions' AND added_in='r423';
DROP FUNCTION public.pdc_workshop_controller_scope_423();
DO $p$ BEGIN
 IF (SELECT count(*) FROM (VALUES
  ('public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid)','0354ba054fa3c823fd19f286fc097ca5','2ec4e303b1df9202aaca2ff82a7a3263'),
  ('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)','c16f3b384c19c3e1b120347be72c9af1','27cb510615d31f22efd39d88c2f1337f'),
  ('public.get_pdc_sublet_audit_ledgers(uuid,text,text)','6e1319ffe07ef0721cd940595fb23cc7','d5adb179eda18913ea2c201f56bde19c'),
  ('pdc_codex_intake_private.workshop_read_actor_scope_20261013()','ce8d10d6c6d7076cbc58d7d3c65a03e8','109f9e9040eba64a6048078e073a1180')) e(sig,m,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m AND md5(coalesce(p.proacl::text,'')||p.prosecdef::text||p.provolatile::text||p.proowner::regrole::text||coalesce(array_to_string(p.proconfig,'|'),''))=e.a)<>4 THEN RAISE EXCEPTION 'r423 undo: functions not restored'; END IF;
 IF to_regprocedure('public.pdc_workshop_controller_scope_423()') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r423')
  OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r423') THEN RAISE EXCEPTION 'r423 undo: r423 objects remain'; END IF;
END $p$;
