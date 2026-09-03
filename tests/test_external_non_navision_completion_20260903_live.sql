-- Transactional STAGING integration test. All synthetic rows roll back.
BEGIN;
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='180s';

DO $pre$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903130000' AND name='external_non_navision_completion_20260903')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903131000' AND name='external_completion_workshop_status_not_null_repair_20260903')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903132000' AND name='external_completion_delivery_milestone_scope_20260903')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903133000' AND name='navision_seven_update_retention_ledger_20260903')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903134000' AND name='external_completion_review_repairs_20260903')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903135000' AND name='external_completion_hidden_booking_cancel_20260903')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903136000' AND name='external_completion_residual_booking_soft_delete_20260903')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903137000' AND name='external_completion_booking_history_revision_20260903')<>1
  THEN RAISE EXCEPTION 'EXTERNAL_COMPLETION_LIVE_TEST_EXACT_STAGING_REQUIRED' USING errcode='55000'; END IF;
END $pre$;

SELECT set_config('request.jwt.claim.sub','8a83b715-8d79-4b0e-95b2-02b55da6e8d7',true);
SELECT set_config('request.jwt.claims','{"sub":"8a83b715-8d79-4b0e-95b2-02b55da6e8d7","email":"craig.watson@broometoyota.com.au","role":"authenticated"}',true);

SELECT set_config('pdc.hermes_test_wrapper_vehicle_365','13000000-0000-5000-8000-000000001301',true);
INSERT INTO public.vehicles(
  id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,visible_on_board,current_location,
  rft_transferred_at,rft_collected_at,rft_collected_by,source_payload,version,source_system,source_batch_id,
  source_record_id,date_to_rft,created_by,updated_by)
VALUES(
  '13000000-0000-5000-8000-000000001301','HERMES-TEST-PERM-EXT-1301','HERMES-TEST-EXT-1301','HERMES-TEST-JC-EXT-1301',
  'rft',false,'Collected',clock_timestamp(),clock_timestamp(),'8a83b715-8d79-4b0e-95b2-02b55da6e8d7','{}',7,
  'external_jobcard','HERMES-TEST-EXTERNAL-COMPLETION','HERMES-TEST-EXT-SOURCE-1301',(clock_timestamp() at time zone 'Australia/Perth')::date,
  '8a83b715-8d79-4b0e-95b2-02b55da6e8d7','8a83b715-8d79-4b0e-95b2-02b55da6e8d7');

SELECT set_config('pdc.hermes_test_wrapper_vehicle_365','13000000-0000-5000-8000-000000001302',true);
INSERT INTO public.vehicles(
  id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,visible_on_board,current_location,
  rft_transferred_at,rft_collected_at,rft_collected_by,source_payload,version,source_system,source_batch_id,
  source_record_id,date_to_rft,created_by,updated_by)
VALUES(
  '13000000-0000-5000-8000-000000001302','HERMES-TEST-PERM-NAV-1302','HERMES-TEST-NAV-1302','HERMES-TEST-JC-NAV-1302',
  'rft',false,'Collected',clock_timestamp(),clock_timestamp(),'8a83b715-8d79-4b0e-95b2-02b55da6e8d7','{}',7,
  'microsoft_navision','HERMES-TEST-EXTERNAL-COMPLETION','HERMES-TEST-NAV-SOURCE-1302',(clock_timestamp() at time zone 'Australia/Perth')::date,
  '8a83b715-8d79-4b0e-95b2-02b55da6e8d7','8a83b715-8d79-4b0e-95b2-02b55da6e8d7');

INSERT INTO public.pdc_rft_transport_lifecycle_receipts_734(
  receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,
  request_payload,before_state,after_state,evidence,response)
VALUES
  ('13000000-0000-5000-8000-000000001311','13000000-0000-5000-8000-000000001301','collected','8a83b715-8d79-4b0e-95b2-02b55da6e8d7','craig.watson@broometoyota.com.au','13000000-0000-5000-8000-000000001321',repeat('a',64),'{}','{}','{}',jsonb_build_object('physical_collection_recorded',true,'fixture',true),jsonb_build_object('ok',true,'code','rft_vehicle_collected')),
  ('13000000-0000-5000-8000-000000001312','13000000-0000-5000-8000-000000001302','collected','8a83b715-8d79-4b0e-95b2-02b55da6e8d7','craig.watson@broometoyota.com.au','13000000-0000-5000-8000-000000001322',repeat('b',64),'{}','{}','{}',jsonb_build_object('physical_collection_recorded',true,'fixture',true),jsonb_build_object('ok',true,'code','rft_vehicle_collected'));

SELECT set_config('pdc.hermes_test_wrapper_vehicle_365','13000000-0000-5000-8000-000000001301',true);
ALTER TABLE public.workshop_bookings DISABLE TRIGGER USER;
INSERT INTO public.workshop_bookings(
  id,vehicle_id,stage_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by)
SELECT '13000000-0000-5000-8000-000000001340','13000000-0000-5000-8000-000000001301',s.id,'queued',
       '2100-01-01 01:00:00+00','2100-01-01 02:00:00+00',60,
       '8a83b715-8d79-4b0e-95b2-02b55da6e8d7','8a83b715-8d79-4b0e-95b2-02b55da6e8d7'
FROM public.workshop_stages s ORDER BY s.id LIMIT 1;
ALTER TABLE public.workshop_bookings ENABLE TRIGGER USER;

-- Mutable source markers alone must not suppress the ordinary delivery latch.
UPDATE public.vehicles SET lifecycle_state='completed',current_location='Completed',
  source_payload=jsonb_build_object('completion_authority','external_non_navision_final_collection','external_completion_receipt_id','13000000-0000-5000-8000-000000001399')
WHERE id='13000000-0000-5000-8000-000000001302';
DO $receipt_authority$
BEGIN
  IF (SELECT delivered_to_dealer_date FROM public.vehicles WHERE id='13000000-0000-5000-8000-000000001302') IS NULL THEN
    RAISE EXCEPTION 'RECEIPT_BACKED_MILESTONE_AUTHORIZATION_BYPASSED' USING errcode='55000';
  END IF;
END $receipt_authority$;

SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  first_result jsonb; replay_result jsonb; mismatch_result jsonb; denied_result jsonb; navision_result jsonb;
  snapshot jsonb; external_row jsonb; readback jsonb; receipt_count bigint;
  lifecycle text; location text; board_visible boolean; vehicle_version integer;
  timer_closed timestamptz; duration bigint; delivered_date date; active_booking uuid;
  authority text; has_navision_status boolean;
  workshop_revision_before bigint;
BEGIN
  IF NOT has_function_privilege('authenticated','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
     OR has_function_privilege('anon','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
     OR has_table_privilege('authenticated','public.pdc_external_completion_receipts_20260903','SELECT,INSERT,UPDATE,DELETE,TRUNCATE') THEN
    RAISE EXCEPTION 'EXTERNAL_COMPLETION_ACL_MISMATCH' USING errcode='55000';
  END IF;

  denied_result:=public.complete_external_rft_collection_20260903(
    '13000000-0000-5000-8000-000000001301',7,'external_non_navision_final_collection',false,
    'Operator approved final completion after recorded external collection','13000000-0000-5000-8000-000000001330');
  IF denied_result->>'code'<>'explicit_operator_approval_required' THEN RAISE EXCEPTION 'EXPLICIT_APPROVAL_GUARD_FAILED:%',denied_result USING errcode='55000'; END IF;

  navision_result:=public.complete_external_rft_collection_20260903(
    '13000000-0000-5000-8000-000000001302',7,'external_non_navision_final_collection',true,
    'Operator approved final completion after recorded external collection','13000000-0000-5000-8000-000000001331');
  IF navision_result->>'code'<>'external_non_navision_vehicle_required' THEN RAISE EXCEPTION 'NAVISION_EXCLUSION_FAILED:%',navision_result USING errcode='55000'; END IF;

  SELECT revision INTO workshop_revision_before FROM public.workshop_revision WHERE id=1;
  first_result:=public.complete_external_rft_collection_20260903(
    '13000000-0000-5000-8000-000000001301',7,'external_non_navision_final_collection',true,
    'Operator approved final completion after recorded external collection','13000000-0000-5000-8000-000000001332');
  IF NOT coalesce((first_result->>'ok')::boolean,false) OR first_result->>'code'<>'external_collection_completed'
     OR coalesce((first_result->>'replay')::boolean,true)
     OR (first_result#>>'{data,vehicle_version_after}')::integer<>(first_result#>>'{data,vehicle_version_before_completion}')::integer+1
     OR first_result#>>'{data,cancelled_active_booking_count}'<>'1'
     OR first_result#>>'{data,completion_authority}'<>'external_non_navision_final_collection'
     OR coalesce((first_result#>>'{data,physical_delivery_asserted}')::boolean,true) THEN
    RAISE EXCEPTION 'EXTERNAL_COMPLETION_FIRST_APPLY_FAILED:%',first_result USING errcode='55000';
  END IF;

  replay_result:=public.complete_external_rft_collection_20260903(
    '13000000-0000-5000-8000-000000001301',7,'external_non_navision_final_collection',true,
    'Operator approved final completion after recorded external collection','13000000-0000-5000-8000-000000001332');
  IF NOT coalesce((replay_result->>'ok')::boolean,false) OR NOT coalesce((replay_result->>'replay')::boolean,false)
     OR replay_result#>>'{data,receipt_id}' IS DISTINCT FROM first_result#>>'{data,receipt_id}' THEN
    RAISE EXCEPTION 'EXTERNAL_COMPLETION_REPLAY_FAILED:%',replay_result USING errcode='55000';
  END IF;

  mismatch_result:=public.complete_external_rft_collection_20260903(
    '13000000-0000-5000-8000-000000001301',7,'external_non_navision_final_collection',true,
    'Changed reason must not replay the original completion receipt','13000000-0000-5000-8000-000000001332');
  IF mismatch_result->>'code'<>'idempotency_payload_mismatch' THEN RAISE EXCEPTION 'IDEMPOTENCY_MISMATCH_GUARD_FAILED:%',mismatch_result USING errcode='55000'; END IF;

  SELECT v.lifecycle_state::text,v.current_location,v.visible_on_board,v.version,v.dealer_transit_closed_at,
         v.dealer_transit_duration_seconds,v.delivered_to_dealer_date,v.active_workshop_booking_id,
         v.source_payload->>'completion_authority',v.source_payload?'navision_status_literal'
    INTO lifecycle,location,board_visible,vehicle_version,timer_closed,duration,delivered_date,active_booking,authority,has_navision_status
  FROM public.vehicles v WHERE v.id='13000000-0000-5000-8000-000000001301';
  IF (lifecycle,location,board_visible,vehicle_version,timer_closed,duration,delivered_date,active_booking,authority,has_navision_status)
     IS DISTINCT FROM ('completed','Completed',false,(first_result#>>'{data,vehicle_version_after}')::integer,NULL::timestamptz,NULL::bigint,NULL::date,NULL::uuid,'external_non_navision_final_collection',false) THEN
    RAISE EXCEPTION 'EXTERNAL_COMPLETION_VEHICLE_STATE_FAILED' USING errcode='55000';
  END IF;
  IF (SELECT status::text FROM public.workshop_bookings WHERE id='13000000-0000-5000-8000-000000001340')<>'deleted' THEN
    RAISE EXCEPTION 'RESIDUAL_BOOKING_NOT_CANCELLED' USING errcode='55000';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.workshop_booking_history WHERE booking_id='13000000-0000-5000-8000-000000001340' AND event_type='deleted')
     OR (SELECT revision FROM public.workshop_revision WHERE id=1)<=workshop_revision_before THEN
    RAISE EXCEPTION 'RESIDUAL_BOOKING_HISTORY_OR_REVISION_MISSING' USING errcode='55000';
  END IF;

  readback:=public.read_pdc_external_completion_20260903('13000000-0000-5000-8000-000000001301');
  IF NOT coalesce((readback->>'ok')::boolean,false) OR readback#>>'{data,completion_type}'<>'external_non_navision_final_collection'
     OR coalesce((readback#>>'{data,physical_delivery_asserted}')::boolean,true) THEN
    RAISE EXCEPTION 'EXTERNAL_COMPLETION_RECEIPT_READBACK_FAILED:%',readback USING errcode='55000';
  END IF;

  snapshot:=public.get_pdc_email_vehicle_location_snapshot();
  SELECT x INTO external_row FROM jsonb_array_elements(coalesce(snapshot#>'{data,vehicles}','[]'::jsonb)) x
   WHERE x->>'id'='13000000-0000-5000-8000-000000001301';
  IF external_row IS NULL OR external_row->>'lifecycle_state'<>'completed' OR external_row->>'current_location'<>'Completed'
     OR external_row#>>'{pdc_lifecycle,state}'<>'completed'
     OR external_row#>>'{external_completion,completion_type}'<>'external_non_navision_final_collection'
     OR coalesce((external_row#>>'{external_completion,physical_delivery_asserted}')::boolean,true) THEN
    RAISE EXCEPTION 'EXTERNAL_COMPLETION_SNAPSHOT_READBACK_FAILED:%',external_row USING errcode='55000';
  END IF;

END $test$;
RESET ROLE;

DO $post_readback$
DECLARE readback jsonb; replay_result jsonb;
BEGIN
  readback:=public.read_pdc_external_completion_20260903('13000000-0000-5000-8000-000000001301');
  IF (readback#>'{data,after_state}') IS DISTINCT FROM jsonb_build_object(
       'vehicle',to_jsonb((SELECT x FROM public.vehicles x WHERE x.id='13000000-0000-5000-8000-000000001301')),
       'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734('13000000-0000-5000-8000-000000001301')) THEN
    RAISE EXCEPTION 'IMMUTABLE_RECEIPT_AFTER_STATE_NOT_AUTHORITATIVE' USING errcode='55000';
  END IF;
  UPDATE public.vehicles SET visible_on_board=true WHERE id='13000000-0000-5000-8000-000000001301';
  replay_result:=public.complete_external_rft_collection_20260903(
    '13000000-0000-5000-8000-000000001301',7,'external_non_navision_final_collection',true,
    'Operator approved final completion after recorded external collection','13000000-0000-5000-8000-000000001332');
  IF replay_result->>'code'<>'external_completion_replay_state_drift' THEN
    RAISE EXCEPTION 'REPLAY_DRIFT_GUARD_FAILED:%',replay_result USING errcode='55000';
  END IF;
END $post_readback$;

DO $immutability$
BEGIN
  BEGIN
    UPDATE public.pdc_external_completion_receipts_20260903 SET reason='mutated receipt' WHERE vehicle_id='13000000-0000-5000-8000-000000001301';
    RAISE EXCEPTION 'IMMUTABILITY_TRIGGER_DID_NOT_FIRE' USING errcode='55000';
  EXCEPTION WHEN sqlstate '55000' THEN
    IF SQLERRM<>'PDC_EXTERNAL_COMPLETION_APPEND_ONLY' THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM public.pdc_external_completion_receipts_20260903 WHERE vehicle_id='13000000-0000-5000-8000-000000001301')<>1 THEN
    RAISE EXCEPTION 'EXTERNAL_COMPLETION_DUPLICATE_RECEIPT' USING errcode='55000';
  END IF;
  IF EXISTS(SELECT 1 FROM public.vehicle_notifications WHERE vehicle_id='13000000-0000-5000-8000-000000001301') THEN
    RAISE EXCEPTION 'EXTERNAL_COMPLETION_OUTBOUND_NOTIFICATION_CREATED' USING errcode='55000';
  END IF;
END $immutability$;

SELECT jsonb_build_object(
  'ok',true,
  'code','external_non_navision_completion_live_passed',
  'migration_version','20260903130000',
  'vehicle_id','13000000-0000-5000-8000-000000001301',
  'production_touched',false,
  'physical_delivery_asserted',false,
  'outbound_created',false
) AS evidence;
ROLLBACK;
