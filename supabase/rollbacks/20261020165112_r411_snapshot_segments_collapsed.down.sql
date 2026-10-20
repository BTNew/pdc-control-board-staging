-- r411 undo: puts back the exact pre-r411 bodies of pre_691, pre_750 and pre_pilbara_service_v1 (the replaced layers were
-- never dropped, so the old chain is live again at once), removes the r411 pins and check, and restores the pilbara r410 pin.
-- Run between :02 and :45 with lock_timeout 2s. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r411 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r411 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r411 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r411 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_691()','775d90e421042423670990b467f157be'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_750()','714fa7a3a5f79e95f2cd891ba96045cc'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','580bf52022a37d11b78f228c37254c4a')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>3 THEN RAISE EXCEPTION 'r411 undo: a function is not the r411 version; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_691()','{postgres=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_750()','{postgres=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_693()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_767()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole)<>5 THEN RAISE EXCEPTION 'r411 undo: owner, grants, security, volatility or search_path changed'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_691()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r jsonb; rows jsonb; collected_rows jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_700();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  SELECT coalesce(jsonb_agg(x||public.pdc_final_lifecycle_overlay_700((x->>'id')::uuid) ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'key_number',v.key_number,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,'registration',v.registration,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'visible_on_board',v.visible_on_board,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'qc_completed_at',v.qc_completed_at,'qc_completed_by',v.qc_completed_by,'salesperson_id',v.salesperson_id,'salesperson_reference',v.salesperson_reference,'rft_transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,
    'work_items',coalesce((SELECT jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at,'completed_by',wi.completed_by) ORDER BY wi.work_key) FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id),'[]'::jsonb),
    'pdc_lifecycle',public.pdc_final_lifecycle_overlay_700(v.id),
    'qc_finalization',coalesce((SELECT jsonb_build_object('receipt_id',q.receipt_id,'photo_receipt_id',q.evidence->>'photo_receipt_id','signed_off_at',q.created_at,'completed_items',q.evidence->'completed_items') FROM public.pdc_final_pdc_lifecycle_receipts_700 q WHERE q.vehicle_id=v.id AND q.action='qc_signed_off'),'{}'::jsonb),
    'photo',coalesce((SELECT jsonb_build_object('photo_receipt_id',p.photo_receipt_id,'bucket_id',p.bucket_id,'storage_path',p.storage_path,'content_type',p.content_type,'byte_length',p.byte_length,'image_width',p.image_width,'image_height',p.image_height,'sha256',p.sha256,'original_filename',p.original_filename) FROM public.pdc_qc_finalization_photo_evidence_399 p WHERE p.vehicle_id=v.id ORDER BY p.created_at DESC LIMIT 1),'{}'::jsonb),
    'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_intercept_receipts_429 i WHERE i.notification_id=o.notification_id)) FROM public.pdc_rft_transport_salesperson_outbox_412 o WHERE o.vehicle_id=v.id),'{}'::jsonb)
  ) ORDER BY v.rft_collected_at,v.id),'[]'::jsonb) INTO collected_rows
  FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND v.current_location='Collected' AND EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 q WHERE q.vehicle_id=v.id AND q.action='collected') AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE (x->>'id')=v.id::text);
  rows:=rows||collected_rows;
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $function$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_750()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r jsonb; rows jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_739();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('rft_transport_draft',coalesce((SELECT jsonb_build_object(
    'draft_id',d.draft_id,'draft_filename',d.draft_filename,'mime_content_type',d.mime_content_type,
    'mime_byte_length',d.mime_byte_length,'mime_sha256',d.mime_sha256,'photo_receipt_id',d.photo_receipt_id,
    'photo_content_type',d.photo_content_type,'photo_byte_length',d.photo_byte_length,'photo_sha256',d.photo_sha256,
    'status',d.status,'delivery_enabled',false,'intercepted',true,'sent_at',null,'delivered_at',null)
    FROM public.pdc_rft_transport_email_drafts_739 d WHERE d.vehicle_id=(x->>'id')::uuid ORDER BY d.created_at DESC LIMIT 1),'{}'::jsonb)) ORDER BY x->>'stock_number'),'[]'::jsonb)
    INTO rows FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $function$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE base jsonb; rows jsonb; appended jsonb;
BEGIN
  base:=public.get_pdc_email_vehicle_location_snapshot_pre_ext1300();
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  -- r410 (F26): pdc_lifecycle already carries external_completion (the same
  -- pdc_external_completion_json_20260903 of the same id), so it is reused instead of looked up again.
  -- A vehicle missing from public.vehicles gets '{}' with no such key and still uses the direct lookup.
  SELECT coalesce(jsonb_agg(x||jsonb_build_object(
    'pdc_lifecycle',lc.v,
    'external_completion',CASE WHEN lc.v ? 'external_completion' THEN lc.v->'external_completion'
      ELSE public.pdc_external_completion_json_20260903((x->>'id')::uuid) END
  ) ORDER BY coalesce(x->>'stock_number',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,vehicles}','[]'::jsonb)) x
  CROSS JOIN LATERAL (SELECT public.pdc_rft_transport_lifecycle_state_734((x->>'id')::uuid) AS v OFFSET 0) lc;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,
    'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,
    'registration',v.registration,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,
    'visible_on_board',v.visible_on_board,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
    'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'rft_transferred_at',v.rft_transferred_at,
    'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,
    'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,
    'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,'delivered_to_dealer_date',v.delivered_to_dealer_date,
    'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id),
    'external_completion',public.pdc_external_completion_json_20260903(v.id),
    'lifecycle_history',public.pdc_lifecycle_history_payload_82000(v.id)
  ) ORDER BY r.completed_at,r.vehicle_id),'[]'::jsonb) INTO appended
  FROM public.pdc_external_completion_receipts_20260903 r JOIN public.vehicles v ON v.id=r.vehicle_id
  WHERE v.deleted_at IS NULL AND v.lifecycle_state='completed' AND v.current_location='Completed'
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE x->>'id'=v.id::text);
  RETURN jsonb_set(base,'{data,vehicles}',rows||appended,true);
END $function$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='snapshot_segments_collapsed' AND added_in='r411';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r411';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','844c796008c0c49e7328779214eae64f','r410','Snapshot layer pilbara: external_completion reused from pdc_lifecycle (r410, F26)');

DO $p$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r411 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r411 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r411 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_691()','b6c81f618327621e74d8e24160188516'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_750()','d8dfcd8d9579d379eafe712594304a9c'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','844c796008c0c49e7328779214eae64f')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>3 THEN RAISE EXCEPTION 'r411 undo: a function is not back to its pre-r411 version'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre168()','d3b6f69bdf3420336403816fc7c60255'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_169()','b9d15c26231ceb6c0284fc7980878a09'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_174()','ff6ff8b4589ce811faeb97662b22a158'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_310()','2cdf8dfb3943babfb18d7476041c92cf'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_395()','8c37da97120ae46764a21c279a622a73'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_396()','c30cb9b0837aa50ac743745a3c7f2616'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_399()','bcca3e5857f70635cf1a3eb2cff64056'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_412()','8d835e24b24cd8dc4eda0e7748857ee8'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_422()','aa2bd6e7335f6bc873b2d91856179a67'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_429()','f3447cc81a348c8202d138cb3b440bdf'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_700()','33deecc1ae222a28984842862199ec2a'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','733c898847d84a79576f028dd9d1fea6'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_82000()','10a51ee7591f9c1ee65e735108ec9ced'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_ext1300()','b1de398abce363b921d916a91892f2d9'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','2ed0984e0f1a6b6e10ac5601a0014e18'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','623b014b00ab74159639ed23f257f607'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_693()','4f3f4dd8cab754543d3c0cc934ad111f'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_767()','db446d2222101f0028666333779fdf23'),
  ('public.get_pdc_email_vehicle_location_snapshot()','09f6a5c2b02dbf9ae993b80d05c69c98'),
  ('public.get_pdc_email_vehicle_board_snapshot()','a3a635b978cb6b266ea04f03c876672f')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>20 THEN RAISE EXCEPTION 'r411 undo: a kept layer changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_691()','{postgres=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_750()','{postgres=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_693()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_767()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole)<>5 THEN RAISE EXCEPTION 'r411 undo: owner, grants, security, volatility or search_path changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r411') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r411') THEN RAISE EXCEPTION 'r411 undo: r411 rows left'; END IF;
END $p$;
