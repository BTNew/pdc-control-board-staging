-- STAGING ONLY 20260901070000: action execution/readback follow-up.
-- Appends to 0600; applies no production or mailbox changes.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901070000-typed-action-execution-readback',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260901060000' AND name='pdc_email_ai_typed_action_boundary_hardening_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901070000')
     OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901070000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_work_state_map_20260901(p_vehicle_id uuid,p_action_type text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $work_map$
DECLARE states jsonb; state_key text;
BEGIN
  SELECT jsonb_build_object(
    'bus4x4',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='bus4x4' LIMIT 1),'none'),
    'tint',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='tint' LIMIT 1),'none'),
    'hoist',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='hoist' LIMIT 1),'none'),
    'fitting',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='fitting' LIMIT 1),'none'),
    'fabrication',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='fabrication' LIMIT 1),'none'),
    'electrical',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='electrical' LIMIT 1),'none'),
    'tyre',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='tyre' LIMIT 1),'none'),
    'pitInspection',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='pitinspection' LIMIT 1),'none'),
    'sublet',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='sublet' LIMIT 1),'none'),
    'parts',coalesce((SELECT CASE WHEN completed THEN 'complete' WHEN required THEN 'required' ELSE 'none' END FROM public.vehicle_work_items WHERE vehicle_id=p_vehicle_id AND work_key='PARTS' LIMIT 1),'none')) INTO states;
  IF p_action_type='parts_complete' THEN
    states:=jsonb_set(states,'{parts}','"complete"'::jsonb,true);
  ELSIF p_action_type='required_work_set' THEN
    state_key:=case upper(p_payload->>'work_key') when 'PIT_INSPECTION' then 'pitInspection' when 'BUS_4X4' then 'bus4x4' else lower(p_payload->>'work_key') end;
    states:=jsonb_set(states,ARRAY[state_key],case when (p_payload->>'required')::boolean then '"required"'::jsonb else '"none"'::jsonb end,true);
  END IF;
  RETURN states;
END $work_map$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_work_state_map_20260901(uuid,text,jsonb) FROM public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_action_readback_parity_20260901(p_action_type text,p_payload jsonb,p_result jsonb,p_readback jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,public AS $parity$
SELECT CASE p_action_type
  WHEN 'activate_vehicle' THEN p_readback->'vehicle'->>'source_record_id'=p_payload->>'backend_record_id'
  WHEN 'location_set' THEN upper(p_readback->'vehicle'->>'current_location')=upper(p_payload->>'location')
  WHEN 'parts_eta_set' THEN p_readback#>>'{parts_update,worst_eta}' IS NOT DISTINCT FROM p_payload->>'eta'
  WHEN 'parts_complete' THEN coalesce((p_readback->'work_item'->>'completed')::boolean,false)
  WHEN 'required_work_set' THEN upper(p_readback->'work_item'->>'work_key')=upper(p_payload->>'work_key') AND (p_readback->'work_item'->>'required')::boolean=(p_payload->>'required')::boolean
  WHEN 'work_complete' THEN p_readback->'booking'->>'booking_id'=p_payload->>'booking_id' AND p_readback->'booking'->>'status'='completed' AND coalesce((p_readback->'work_item'->>'completed')::boolean,false)
  WHEN 'booking_set' THEN p_readback->'booking'->>'booking_id' IS NOT NULL AND p_readback->'booking'->'stage'->>'code'=p_payload->>'stage_code' AND (p_readback->'booking'->'bay'->>'bay_number')::integer=(p_payload->>'bay_number')::integer AND p_readback->'booking'->>'scheduled_start_at'=p_payload->>'scheduled_start_at' AND (p_readback->'booking'->>'default_duration_minutes')::integer=(p_payload->>'duration_minutes')::integer AND (p_payload->>'technician_id' IS NULL OR p_readback->'booking'->'assignment'->>'technician_id'=p_payload->>'technician_id')
  WHEN 'booking_move' THEN p_readback->'booking'->>'booking_id'=p_payload->>'booking_id' AND p_readback->'booking'->'stage'->>'code'=p_payload->>'stage_code' AND (p_readback->'booking'->'bay'->>'bay_number')::integer=(p_payload->>'bay_number')::integer AND p_readback->'booking'->>'scheduled_start_at'=p_payload->>'scheduled_start_at' AND (p_readback->'booking'->>'default_duration_minutes')::integer=(p_payload->>'duration_minutes')::integer AND (p_readback->'booking'->>'version')::integer>(p_payload->>'expected_booking_version')::integer
  WHEN 'booking_cancel' THEN p_readback->'booking'->>'booking_id'=p_payload->>'booking_id' AND (p_readback->'booking'->>'deleted_at' IS NOT NULL OR p_readback->'booking'->>'status' IN('deleted','cancelled'))
  WHEN 'note_append' THEN p_readback->'timeline_event'->>'vehicle_id'=p_readback->'vehicle'->>'id' AND p_readback->'timeline_event'->>'ai_summary'=p_payload->>'text' AND p_readback->'timeline_event'->>'original_statement'=p_payload->>'text'
  WHEN 'operation_add' THEN p_readback->'operation'->>'operation_code'=p_payload->>'operation_no' AND p_readback->'operation'->>'description'=p_payload->>'description' AND upper(p_readback->'operation'->>'work_key')=upper(p_payload->>'work_key') AND (p_readback->'operation'->>'estimated_hours')::numeric=(p_payload->>'estimated_hours')::numeric
  WHEN 'operation_update' THEN p_readback->'operation'->>'operation_code'=p_payload->>'operation_no' AND p_readback->'operation'->>'description'=p_payload->>'description' AND upper(p_readback->'operation'->>'work_key')=upper(p_payload->>'work_key') AND (p_readback->'operation'->>'estimated_hours')::numeric=(p_payload->>'estimated_hours')::numeric
  WHEN 'rft_transfer' THEN upper(p_readback->'vehicle'->>'current_location')='RFT'
  WHEN 'rft_collect' THEN p_readback->'vehicle'->>'rft_collected_at' IS NOT NULL
  ELSE false END;
$parity$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_action_readback_parity_20260901(text,jsonb,jsonb,jsonb) FROM public,anon,authenticated,service_role;
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
      BEGIN
      IF action_type='activate_vehicle' THEN canonical_rpc:='public.reconcile_navision_operational_record(uuid,uuid,text)'; result:=public.reconcile_navision_operational_record((item->'payload'->>'backend_record_id')::uuid,actor,lower(coalesce(auth.jwt()->>'email','')));
      ELSIF action_type='operation_add' THEN canonical_rpc:='public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'; result:=public.import_pdc_authenticated_email_operations_with_hours(source_hash,item->'payload'->>'source_uid',jsonb_build_array(jsonb_build_object('operation_no',item->'payload'->>'operation_no','work_key',lower(item->'payload'->>'work_key'),'description',item->'payload'->>'description','estimated_hours',(item->'payload'->>'estimated_hours')::numeric,'estimated_hours_source','job_card')));
      ELSIF action_type='operation_update' THEN canonical_rpc:='public.pdc_email_ai_successor_operation_update_20260901(uuid,integer,text,text,text,text,text,numeric)'; result:=public.pdc_email_ai_successor_operation_update_20260901(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,source_hash,item->'payload'->>'source_uid',item->'payload'->>'operation_no',item->'payload'->>'work_key',item->'payload'->>'description',(item->'payload'->>'estimated_hours')::numeric);
      ELSIF action_type='parts_eta_set' THEN canonical_rpc:='public.update_pdc_parts_eta(uuid,integer,date)'; result:=public.update_pdc_parts_eta(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,(item->'payload'->>'eta')::date);
      ELSIF action_type IN('parts_complete','required_work_set') THEN canonical_rpc:='public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'; result:=public.set_pdc_vehicle_work_states(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,public.pdc_email_ai_successor_work_state_map_20260901(vehicle.id,action_type,item->'payload'));
      ELSIF action_type='booking_set' THEN canonical_rpc:='public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'; result:=public.schedule_vehicle_work(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,item->'payload'->>'stage_code',(item->'payload'->>'bay_number')::integer,(item->'payload'->>'scheduled_start_at')::timestamptz,(item->'payload'->>'duration_minutes')::integer,nullif(item->'payload'->>'technician_id','')::uuid,null,null);
      ELSIF action_type='booking_move' THEN canonical_rpc:='public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'; result:=public.move_workshop_booking((item->'payload'->>'booking_id')::uuid,(item->'payload'->>'expected_booking_version')::integer,item->'payload'->>'stage_code',(item->'payload'->>'bay_number')::integer,(item->'payload'->>'scheduled_start_at')::timestamptz,(item->'payload'->>'duration_minutes')::integer,item->'payload'->>'override_reason','{}'::jsonb);
      ELSIF action_type='booking_cancel' THEN canonical_rpc:='public.cancel_workshop_booking(uuid,integer,text,jsonb)'; result:=public.cancel_workshop_booking((item->'payload'->>'booking_id')::uuid,(item->'payload'->>'expected_booking_version')::integer,item->'payload'->>'reason','{}'::jsonb);
      ELSIF action_type='work_complete' THEN canonical_rpc:='public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)'; result:=public.complete_workshop_work((item->'payload'->>'booking_id')::uuid,(item->'payload'->>'expected_booking_version')::integer,item->'payload'->>'work_key',(item->'payload'->>'completed_at')::timestamptz,'{}'::jsonb);
      ELSIF action_type='note_append' THEN canonical_rpc:='public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'; SELECT to_jsonb(e) INTO result FROM public.append_vehicle_timeline_event(p_vehicle_id=>vehicle.id,p_event_type=>'email_ai_note',p_event_at=>(item->'payload'->>'event_at')::timestamptz,p_source_kind=>'ai'::public.vehicle_timeline_source_kind,p_event_state=>'confirmed'::public.vehicle_timeline_event_state,p_ai_summary=>item->'payload'->>'text',p_original_statement=>item->'payload'->>'text',p_structured_data=>jsonb_build_object('source_receipt_id',source_id,'action_key',action_key),p_source_email_id=>p_plan->>'source_message_id',p_source_thread_id=>p_plan->>'source_thread_id',p_evidence_reference=>'source:'||source_hash,p_source_intake_id=>source_id) e;
      ELSIF action_type='location_set' THEN canonical_rpc:='public.move_vehicle(uuid,integer,text,text,text,text,text)'; SELECT to_jsonb(public.move_vehicle(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer,upper(item->'payload'->>'location'),null,null,null,item->'payload'->>'reason')) INTO result;
      ELSIF action_type='rft_transfer' THEN canonical_rpc:='public.rft_transfer_vehicle(uuid,integer)'; result:=public.rft_transfer_vehicle(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer);
      ELSE canonical_rpc:='public.rft_collect_vehicle(uuid,integer)'; result:=public.rft_collect_vehicle(vehicle.id,(item->'expected_state'->>'vehicle_version')::integer);
      END IF;
      IF coalesce((result->>'ok')::boolean,action_type='note_append' OR action_type='location_set') THEN
        readback:=public.pdc_email_ai_successor_action_readback_20260901(vehicle.id,action_type,item->'payload',result); verification:=jsonb_build_object('checked',true,'parity',public.pdc_email_ai_successor_action_readback_parity_20260901(action_type,item->'payload',result,readback),'field_scope',action_type); after_state:=readback; actual:=result; disposition:=case when (verification->>'parity')::boolean then 'APPLIED_AND_VERIFIED' else 'FAILED_QUEUED_RETRY' end; reason:=case when disposition='APPLIED_AND_VERIFIED' then 'authoritative field-level readback verified' else 'authoritative_readback_field_parity_failed' end;
      ELSE disposition:='FAILED_QUEUED_RETRY'; reason:=coalesce(result->>'error',result->>'code','canonical_action_rejected'); END IF;
      EXCEPTION WHEN others THEN
        disposition:='FAILED_QUEUED_RETRY'; reason:='canonical_'||action_type||'_failed'; result:=jsonb_build_object('ok',false,'code',reason);
      END;
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
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901070000','pdc_email_ai_typed_action_execution_readback_20260901',ARRAY[
 'Required-work execution now sends the complete tri-state canonical state map and preserves unrelated work state',
 'Canonical exceptions are converted into FAILED_QUEUED_RETRY receipts instead of aborting the receipt transaction',
 'Booking set/move readback verifies affected booking stage, bay, time, duration, assignment and version; note/work/timeline remain affected-row projections'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
