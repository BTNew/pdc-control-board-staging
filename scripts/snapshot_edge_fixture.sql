-- r410 edge-case fixture (rolled back with the test). Each step is in its own sub-block, so a step a guard or
-- trigger refuses is recorded and skipped rather than failing the test. Rows are picked by rule, not by id.
DO $fx$
DECLARE uid uuid := (current_setting('request.jwt.claim.sub'))::uuid; v record; log jsonb := '[]'::jsonb; n integer;
BEGIN
  -- F1 external completion on an active on-board vehicle (pdc_lifecycle 'completed' + external_completion reuse)
  BEGIN
    SELECT * INTO v FROM public.vehicles WHERE deleted_at IS NULL AND visible_on_board AND lifecycle_state='active' AND current_location='PMB'
      AND NOT EXISTS (SELECT 1 FROM public.pdc_external_completion_receipts_20260903 r WHERE r.vehicle_id=vehicles.id) ORDER BY id LIMIT 1;
    INSERT INTO public.pdc_external_completion_receipts_20260903(receipt_id,vehicle_id,expected_vehicle_version,vehicle_version_after,completion_type,operator_approved,reason,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,physical_collection_evidence,response,completed_at,vehicle_version_before_completion)
    VALUES (gen_random_uuid(),v.id,v.version,v.version+1,'external_non_navision_final_collection',true,'r410 fixture external completion',uid,'r410-fixture@pdc.invalid',gen_random_uuid(),encode(sha256(convert_to(gen_random_uuid()::text,'UTF8')),'hex'),'{}','{}','{}','{"fixture":true}','{}',now(),v.version);
    log := log || jsonb_build_object('step','F1 external completion, on-board active','ok',true);
  EXCEPTION WHEN OTHERS THEN log := log || jsonb_build_object('step','F1','ok',false,'error',SQLSTATE||' '||SQLERRM); END;
  -- F2 external completion on a Completed vehicle that the 739/ext1300 appends bring in
  BEGIN
    SELECT * INTO v FROM public.vehicles WHERE deleted_at IS NULL AND lifecycle_state='completed' AND current_location='Completed'
      AND NOT EXISTS (SELECT 1 FROM public.pdc_external_completion_receipts_20260903 r WHERE r.vehicle_id=vehicles.id) ORDER BY id LIMIT 1;
    INSERT INTO public.pdc_external_completion_receipts_20260903(receipt_id,vehicle_id,expected_vehicle_version,vehicle_version_after,completion_type,operator_approved,reason,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,physical_collection_evidence,response,completed_at,vehicle_version_before_completion)
    VALUES (gen_random_uuid(),v.id,v.version,v.version+1,'external_non_navision_final_collection',true,'r410 fixture external completion (completed)',uid,'r410-fixture@pdc.invalid',gen_random_uuid(),encode(sha256(convert_to(gen_random_uuid()::text,'UTF8')),'hex'),'{}','{}','{}','{}','{}',now(),v.version);
    log := log || jsonb_build_object('step','F2 external completion, appended Completed vehicle','ok',true);
  EXCEPTION WHEN OTHERS THEN log := log || jsonb_build_object('step','F2','ok',false,'error',SQLSTATE||' '||SQLERRM); END;
  -- F3 transport receipts (734) collected / delivered on on-board vehicles
  BEGIN
    INSERT INTO public.pdc_rft_transport_lifecycle_receipts_734(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
    SELECT gen_random_uuid(), x.id, x.action, uid, 'r410-fixture@pdc.invalid', gen_random_uuid(), encode(sha256(convert_to(gen_random_uuid()::text,'UTF8')),'hex'),'{}','{}','{}','{}','{}'
    FROM (SELECT id, CASE WHEN row_number() OVER (ORDER BY id) = 1 THEN 'collected' WHEN row_number() OVER (ORDER BY id) = 2 THEN 'delivered' ELSE 'rft_booked' END action
          FROM public.vehicles WHERE deleted_at IS NULL AND visible_on_board AND lifecycle_state='active' AND current_location='YH' ORDER BY id LIMIT 3) x;
    GET DIAGNOSTICS n = ROW_COUNT;
    log := log || jsonb_build_object('step','F3 734 receipts collected/delivered/rft_booked, on-board','ok',true,'rows',n);
  EXCEPTION WHEN OTHERS THEN log := log || jsonb_build_object('step','F3','ok',false,'error',SQLSTATE||' '||SQLERRM); END;
  -- F4 final lifecycle receipt (700) qc_signed_off on an on-board vehicle (691 overlay)
  BEGIN
    INSERT INTO public.pdc_final_pdc_lifecycle_receipts_700(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
    SELECT gen_random_uuid(), id, 'qc_signed_off', uid, 'r410-fixture@pdc.invalid', gen_random_uuid(), encode(sha256(convert_to(gen_random_uuid()::text,'UTF8')),'hex'),'{}','{}','{}','{}','{}'
    FROM public.vehicles WHERE deleted_at IS NULL AND visible_on_board AND lifecycle_state='active' AND current_location='QC' ORDER BY id LIMIT 1;
    log := log || jsonb_build_object('step','F4 700 qc_signed_off, on-board','ok',true);
  EXCEPTION WHEN OTHERS THEN log := log || jsonb_build_object('step','F4','ok',false,'error',SQLSTATE||' '||SQLERRM); END;
  -- F5 lifecycle history: a partial history (YH only) on a vehicle that had none, and PMB+RFT on one with YH
  BEGIN
    INSERT INTO public.pdc_vehicle_lifecycle_history_events_82000(vehicle_id,transition_kind,event_kind,occurred_at,source_table,evidence)
    SELECT id, 'YH', 'latch', now() - interval '3 days', 'r410_fixture', '{}'
    FROM public.vehicles vv WHERE deleted_at IS NULL AND visible_on_board AND current_location='Other'
      AND NOT EXISTS (SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 e WHERE e.vehicle_id=vv.id) ORDER BY id LIMIT 1;
    GET DIAGNOSTICS n = ROW_COUNT;
    INSERT INTO public.pdc_vehicle_lifecycle_history_events_82000(vehicle_id,transition_kind,event_kind,occurred_at,source_table,evidence)
    SELECT w.id, k.t, 'latch', now() - k.ago, 'r410_fixture', '{}'
    FROM (SELECT id FROM public.vehicles vv WHERE deleted_at IS NULL AND visible_on_board AND current_location='YH'
            AND EXISTS (SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 e WHERE e.vehicle_id=vv.id AND e.transition_kind='YH')
            AND NOT EXISTS (SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 e WHERE e.vehicle_id=vv.id AND e.transition_kind<>'YH') ORDER BY id DESC LIMIT 1) w
    CROSS JOIN (VALUES (1,'PMB',interval '1 day'),(2,'RFT',interval '1 hour')) k(o,t,ago) ORDER BY k.o;
    log := log || jsonb_build_object('step','F5 lifecycle history partial + complete','ok',true);
  EXCEPTION WHEN OTHERS THEN log := log || jsonb_build_object('step','F5','ok',false,'error',SQLSTATE||' '||SQLERRM); END;
  -- F6 an off-board vehicle becomes Collected with a 734 collected receipt (739 / ext1300 append path)
  BEGIN
    SELECT * INTO v FROM public.vehicles WHERE deleted_at IS NULL AND NOT visible_on_board AND lifecycle_state='active' AND current_location='Other' ORDER BY id LIMIT 1;
    UPDATE public.vehicles SET current_location='Collected', rft_collected_at=now() WHERE id=v.id;
    INSERT INTO public.pdc_rft_transport_lifecycle_receipts_734(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
    VALUES (gen_random_uuid(), v.id, 'collected', uid, 'r410-fixture@pdc.invalid', gen_random_uuid(), encode(sha256(convert_to(gen_random_uuid()::text,'UTF8')),'hex'),'{}','{}','{}','{}','{}');
    log := log || jsonb_build_object('step','F6 off-board vehicle Collected + 734 receipt (append)','ok',true);
  EXCEPTION WHEN OTHERS THEN log := log || jsonb_build_object('step','F6','ok',false,'error',SQLSTATE||' '||SQLERRM); END;
  -- F7 a null stock number on an on-board vehicle (sort keys fall back to id / vin)
  BEGIN
    UPDATE public.vehicles SET stock_number=NULL WHERE id=(SELECT id FROM public.vehicles WHERE deleted_at IS NULL AND visible_on_board AND lifecycle_state='active' AND current_location='IT' ORDER BY id LIMIT 1);
    log := log || jsonb_build_object('step','F7 null stock number','ok',true);
  EXCEPTION WHEN OTHERS THEN log := log || jsonb_build_object('step','F7','ok',false,'error',SQLSTATE||' '||SQLERRM); END;
  -- F8 two vehicles sharing a stock number (sort ties)
  BEGIN
    UPDATE public.vehicles SET stock_number=(SELECT stock_number FROM public.vehicles WHERE deleted_at IS NULL AND visible_on_board AND current_location='IT' ORDER BY id DESC LIMIT 1)
    WHERE id=(SELECT id FROM public.vehicles WHERE deleted_at IS NULL AND visible_on_board AND current_location='IT' ORDER BY id DESC OFFSET 1 LIMIT 1);
    log := log || jsonb_build_object('step','F8 duplicate stock number','ok',true);
  EXCEPTION WHEN OTHERS THEN log := log || jsonb_build_object('step','F8','ok',false,'error',SQLSTATE||' '||SQLERRM); END;
  INSERT INTO t_res(k,v) VALUES ('fixture', jsonb_build_object('steps',log));
END $fx$;
