-- r410 undo: puts back the exact pre-r410 bodies (the old layers were never dropped), removes the r410 pins and
-- check, and restores operation_station's r407 pin. Run between :02 and :45 with lock_timeout 2s. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r410 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r410 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r410 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r410 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','2ed0984e0f1a6b6e10ac5601a0014e18'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','733c898847d84a79576f028dd9d1fea6'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','623b014b00ab74159639ed23f257f607'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','844c796008c0c49e7328779214eae64f'),
  ('public.pdc_is_pre_delivery_20260910(text)','e672cbcbdda24268013a30401b68d5b0'),
  ('pdc_work_categories_private.import_description_hash_20261017(text)','2077a9f7f13668245b302b2ae80cb965'),
  ('pdc_work_categories_private.stage(text)','91e0fc2be1c7bb92a8f98d2baa0f0b6e'),
  ('public.pdc_department138_station_20260917(text)','9f1cf3370971e3a77f5335632d4f3f8c'),
  ('public.pdc_standard_operation_display_20260910(jsonb)','ef6301a91e9fcbb7a663c2319c5bef9d'),
  ('pdc_parts_private.service_scope(jsonb,text,text)','1db89bd7bae513ec6f165dc0b1a87a80'),
  ('pdc_bus_private.operation_station(uuid)','f7ab4745fb8e97fcd58a209145cfab0f')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>11 THEN RAISE EXCEPTION 'r410 undo: a function is not the r410 version; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.pdc_is_pre_delivery_20260910(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('pdc_work_categories_private.import_description_hash_20261017(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('pdc_work_categories_private.stage(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('public.pdc_department138_station_20260917(text)','{postgres=X/postgres,service_role=X/postgres}truei|search_path=pg_catalog'),
  ('public.pdc_standard_operation_display_20260910(jsonb)','{postgres=X/postgres}falsei|search_path=pg_catalog, public'),
  ('pdc_parts_private.service_scope(jsonb,text,text)','{postgres=X/postgres}falses|search_path=pg_catalog, pdc_parts_private'),
  ('pdc_bus_private.operation_station(uuid)','{postgres=X/postgres}trues|search_path=pg_catalog')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole)<>11 THEN RAISE EXCEPTION 'r410 undo: owner, grants, security, volatility or search_path changed'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_734()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$ DECLARE r jsonb;rows jsonb;t jsonb;BEGIN r:=public.get_pdc_email_vehicle_location_snapshot_pre_693();IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r;END IF;SELECT jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,'registration',v.registration,'current_location',v.current_location,'visible_on_board',v.visible_on_board,'source_system',v.source_system,'source_record_id',v.source_record_id,'updated_at',v.updated_at,'work_items',coalesce((SELECT jsonb_agg(jsonb_build_object('work_key',w.work_key,'required',w.required,'completed',w.completed,'completed_at',w.completed_at,'completed_by',w.completed_by) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),'parts_required',coalesce((SELECT parts_required FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id ORDER BY p.updated_at DESC,p.id DESC LIMIT 1),false),'parts_completed',coalesce((SELECT completed FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id AND upper(w.work_key)='PARTS'),false),'parts_update',coalesce((SELECT jsonb_build_object('parts_required',p.parts_required,'parts_ordered',p.parts_ordered,'parts_received',p.parts_received,'parts_stoppage',p.parts_stoppage,'parts_stoppage_reason',p.parts_stoppage_reason,'worst_eta',p.worst_eta,'updated_at',p.updated_at) FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id ORDER BY p.updated_at DESC,p.id DESC LIMIT 1),'{}'::jsonb),'sublet_booking',coalesce((SELECT jsonb_build_object('provider',b.provider_name,'provider_email',b.provider_email,'booking_date',b.out_date,'expected_return_date',b.expected_return_date,'notes',b.notes,'operation_line_identity',b.operation_line_identity,'operation_description',b.operation_description,'version',b.version,'provider_id',b.provider_id,'booking_id',b.booking_id) FROM public.pdc_sublet_booking_instances b WHERE b.vehicle_id=v.id AND b.status='active' ORDER BY b.out_date,b.booking_id LIMIT 1),'{}'::jsonb),'sublet_bookings',coalesce((SELECT jsonb_agg(jsonb_build_object('booking_id',b.booking_id,'vehicle_id',b.vehicle_id,'vehicle_version',b.vehicle_version,'provider_id',b.provider_id,'provider_name',b.provider_name,'provider_email',b.provider_email,'out_date',b.out_date,'expected_return_date',b.expected_return_date,'status',b.status,'version',b.version,'notes',b.notes,'operation_line_identity',b.operation_line_identity,'operation_description',b.operation_description,'updated_at',b.updated_at) ORDER BY b.out_date,b.booking_id) FROM public.pdc_sublet_booking_instances b WHERE b.vehicle_id=v.id),'[]'::jsonb),'sublet_active_count',(SELECT count(*) FROM public.pdc_sublet_booking_instances b WHERE b.vehicle_id=v.id AND b.status='active')) INTO t FROM public.vehicles v WHERE v.id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid AND public.normalize_vehicle_stock_number(v.stock_number)='13000765' AND v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board AND v.source_system='microsoft_navision' AND v.source_batch_id IN('14450','37047') AND v.source_record_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.id=v.source_record_id::uuid AND n.is_current AND n.record_status='current' AND n.dealer_code=v.source_batch_id AND public.normalize_vehicle_stock_number(n.normalized_data->>'batch')='13000765') AND EXISTS(SELECT 1 FROM public.navision_board_activations a WHERE a.canonical_vehicle_id=v.id AND a.active AND public.normalize_vehicle_stock_number(a.activated_stock_number)='13000765');SELECT coalesce(jsonb_agg(q ORDER BY coalesce(q->>'stock_number',q->>'id')),'[]'::jsonb) INTO rows FROM (SELECT value q FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) u UNION ALL SELECT t WHERE t IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) u WHERE u->>'id'=t->>'id')) z;RETURN jsonb_set(r,'{data,vehicles}',rows,true);END $function$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_739()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r jsonb; rows jsonb; appended jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_734();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734((x->>'id')::uuid),'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'delivery_enabled',o.delivery_enabled,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',true,'evidence',coalesce((SELECT jsonb_build_object('evidence_id',e.evidence_id,'mime_version',e.mime_version,'mime_content_type',e.mime_content_type,'mime_sha256',e.mime_sha256,'photo_receipt_id',e.photo_receipt_id,'photo_bucket_id',e.photo_bucket_id,'photo_storage_path',e.photo_storage_path,'photo_content_type',e.photo_content_type,'photo_byte_length',e.photo_byte_length,'photo_sha256',e.photo_sha256,'intercepted',e.intercepted) FROM public.pdc_rft_transport_email_evidence_734 e WHERE e.notification_id=o.notification_id),'{}'::jsonb)) FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=(x->>'id')::uuid ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb),'dealer_transit_statistic',coalesce((SELECT jsonb_build_object('statistic_id',s.statistic_id,'started_at',s.started_at,'closed_at',s.closed_at,'duration_seconds',s.duration_seconds,'status_literal',s.status_literal) FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE s.vehicle_id=(x->>'id')::uuid),'{}'::jsonb)) ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,'registration',v.registration,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'visible_on_board',v.visible_on_board,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'qc_completed_at',v.qc_completed_at,'qc_completed_by',v.qc_completed_by,'rft_transport_booked_at',v.rft_transport_booked_at,'rft_transport_booked_by',v.rft_transport_booked_by,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,'salesperson_id',v.salesperson_id,'salesperson_reference',sp->>'salesperson_name','salesperson_code',sp->>'salesperson_code','salesperson_name',sp->>'salesperson_name','salesperson_email',sp->>'salesperson_email','work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id),'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'delivery_enabled',o.delivery_enabled,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',true) FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=v.id ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb),'dealer_transit_statistic',coalesce((SELECT jsonb_build_object('statistic_id',s.statistic_id,'started_at',s.started_at,'closed_at',s.closed_at,'duration_seconds',s.duration_seconds,'status_literal',s.status_literal) FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE s.vehicle_id=v.id),'{}'::jsonb)
  ) ORDER BY v.rft_collected_at,v.id),'[]'::jsonb) INTO appended
  FROM public.vehicles v CROSS JOIN LATERAL public.pdc_vehicle_effective_salesperson_json_386(v.id) sp
  WHERE v.deleted_at IS NULL AND v.current_location IN('Collected','Completed') AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 q WHERE q.vehicle_id=v.id AND q.action IN('collected','delivered')) AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE (x->>'id')=v.id::text);
  rows:=rows||coalesce(appended,'[]'::jsonb);
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $function$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_1020()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE base jsonb; rows jsonb;
BEGIN
  base:=public.get_pdc_email_vehicle_location_snapshot_pre_82000();
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('lifecycle_history',h)||jsonb_build_object(
    'first_reached_yard_hold_at',h->'first_reached_yard_hold_at','first_entered_pmb_at',h->'first_entered_pmb_at','first_became_rft_at',h->'first_became_rft_at',
    'elapsed_yard_hold_to_pmb_days',h->'elapsed_yard_hold_to_pmb_days','elapsed_pmb_to_rft_days',h->'elapsed_pmb_to_rft_days','elapsed_yard_hold_to_rft_days',h->'elapsed_yard_hold_to_rft_days'
  ) ORDER BY coalesce(x->>'stock_number',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,vehicles}','[]'::jsonb)) x
  CROSS JOIN LATERAL public.pdc_lifecycle_history_payload_82000((x->>'id')::uuid) h;
  RETURN jsonb_set(base,'{data,vehicles}',rows,true);
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
  SELECT coalesce(jsonb_agg(x||jsonb_build_object(
    'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734((x->>'id')::uuid),
    'external_completion',public.pdc_external_completion_json_20260903((x->>'id')::uuid)
  ) ORDER BY coalesce(x->>'stock_number',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,vehicles}','[]'::jsonb)) x;
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

CREATE OR REPLACE FUNCTION public.pdc_is_pre_delivery_20260910(p_description text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT lower(coalesce(p_description,'')) ~ '(^|[^a-z0-9])(pre[[:space:]‐‑–—-]*delivery|pdi)([^a-z0-9]|$)'
$function$;

-- pdc_work_categories_private.import_description_hash_20261017(text): old body has CRLF line endings; restored byte-exact from base64 so git cannot change them.
DO $b$ BEGIN
 EXECUTE convert_from(decode('Q1JFQVRFIE9SIFJFUExBQ0UgRlVOQ1RJT04gcGRjX3dvcmtfY2F0ZWdvcmllc19wcml2YXRlLmltcG9ydF9kZXNjcmlwdGlvbl9oYXNoXzIwMjYxMDE3KGRlc2NyaXB0aW9uIHRleHQpCiBSRVRVUk5TIHRleHQKIExBTkdVQUdFIHNxbAogSU1NVVRBQkxFCiBTRVQgc2VhcmNoX3BhdGggVE8gJ3BnX2NhdGFsb2cnCkFTICRmdW5jdGlvbiQNCiBTRUxFQ1QgbWQ1KHVwcGVyKHJlZ2V4cF9yZXBsYWNlKGJ0cmltKGNvYWxlc2NlKGRlc2NyaXB0aW9uLCcnKSksJ1xzKycsJyAnLCdnJykpKQ0KJGZ1bmN0aW9uJA==','base64'),'UTF8');
END $b$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.stage(category text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT CASE WHEN category='BUS_PIT' THEN 'PIT_INSPECTION'
 WHEN category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA') THEN 'BUS_4X4' ELSE category END
$function$;

CREATE OR REPLACE FUNCTION public.pdc_department138_station_20260917(p_description text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT pdc_work_categories_private.stage(pdc_work_categories_private.suggest(jsonb_build_object('department','138','description',p_description)))
$function$;

CREATE OR REPLACE FUNCTION public.pdc_standard_operation_display_20260910(p_line jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
SELECT CASE WHEN lower(coalesce(p_line->>'description','')) ~ '\m(fill[[:space:]]+(with[[:space:]]+)?fuel|full[[:space:]]+tank[[:space:]]+(of[[:space:]]+)?fuel|refuel(ling|ing)?)\M' THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',0.17::numeric,'effective_estimated_hours',0.17::numeric,'estimated_minutes',10,
'estimated_hours_source','business_rule_default','hours_provenance','craig_standard_fuel_10_minutes')
WHEN lower(coalesce(p_line->>'description','')) ~ '\mpit[[:space:]]*(and|&)[[:space:]]*weigh\M' THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',0.17::numeric,'effective_estimated_hours',0.17::numeric,'estimated_minutes',10,
'estimated_hours_source','business_rule_default','hours_provenance','craig_standard_pit_and_weigh_10_minutes')
WHEN public.pdc_is_pre_delivery_20260910(p_line->>'description') THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',1.0,'effective_estimated_hours',1.0,'estimated_hours_source','business_rule_default','hours_provenance','craig_standard_pre_delivery_1_hour')
WHEN lower(coalesce(p_line->>'description','')) ~ '\mtint\M'
AND (p_line->'estimated_hours' IS NULL OR p_line->'estimated_hours'='null'::jsonb OR p_line->'estimated_hours'='0'::jsonb) THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',1.0,'effective_estimated_hours',1.0,'estimated_hours_source','business_rule_default','hours_provenance','craig_tint_default_1_hour')
ELSE p_line END
$function$;

-- pdc_parts_private.service_scope(jsonb,text,text): old body has CRLF line endings; restored byte-exact from base64 so git cannot change them.
DO $b$ BEGIN
 EXECUTE convert_from(decode('Q1JFQVRFIE9SIFJFUExBQ0UgRlVOQ1RJT04gcGRjX3BhcnRzX3ByaXZhdGUuc2VydmljZV9zY29wZShyYXcganNvbmIsIHN0b2NrIHRleHQsIHJvIHRleHQpCiBSRVRVUk5TIGpzb25iCiBMQU5HVUFHRSBzcWwKIFNUQUJMRQogU0VUIHNlYXJjaF9wYXRoIFRPICdwZ19jYXRhbG9nJywgJ3BkY19wYXJ0c19wcml2YXRlJwpBUyAkZnVuY3Rpb24kDQogU0VMRUNUIENBU0UgV0hFTiBjb2FsZXNjZShudWxsaWYoYnRyaW0ocmF3LT4+J0NvbXBhbnknKSwnJyksbnVsbGlmKGJ0cmltKHJhdy0+Pidjb21wYW55JyksJycpKSBJUyBOVUxMDQogQU5EIGNvYWxlc2NlKG51bGxpZihidHJpbShyYXctPj4nRGl2aXNpb24nKSwnJyksbnVsbGlmKGJ0cmltKHJhdy0+PidkaXZpc2lvbicpLCcnKSkgSVMgTlVMTA0KIFRIRU4gY29hbGVzY2UoKFNFTEVDVCBqc29uYl9idWlsZF9vYmplY3QoJ2NvbXBhbnknLGMuY29tcGFueSwnZGl2aXNpb24nLGMuZGl2aXNpb24pIEZST00gcGRjX3BhcnRzX3ByaXZhdGUub3duZXJfc2NvcGVfY29uZmlybWF0aW9ucyBjDQogV0hFUkUgYy5zdG9ja19udW1iZXI9YnRyaW0oc3RvY2spIEFORCBjLnJvX251bWJlcj11cHBlcihidHJpbShybykpKSwneyJjb21wYW55IjoiIiwiZGl2aXNpb24iOiIifSc6Ompzb25iKQ0KIEVMU0UganNvbmJfYnVpbGRfb2JqZWN0KCdjb21wYW55Jyxjb2FsZXNjZShudWxsaWYoYnRyaW0ocmF3LT4+J0NvbXBhbnknKSwnJykscmF3LT4+J2NvbXBhbnknLCcnKSwNCiAnZGl2aXNpb24nLGNvYWxlc2NlKG51bGxpZihidHJpbShyYXctPj4nRGl2aXNpb24nKSwnJykscmF3LT4+J2RpdmlzaW9uJywnJykpIEVORA0KJGZ1bmN0aW9uJA==','base64'),'UTF8');
END $b$;

CREATE OR REPLACE FUNCTION pdc_bus_private.operation_station(p_operation_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 -- r407 (F21): the approved description is looked up once per operation (OFFSET 0 keeps
 -- it a single evaluation) instead of once in the result and again in the routing join.
 -- The joined keys are unique (history pkey operation_id; ai_routing pkey
 -- (department, description_hash)), so at most one row, as before.
 SELECT coalesce(h.stage_code,pdc_work_categories_private.stage(r.category),
  public.pdc_department138_station_20260917(d.description))
 FROM public.pdc_pilbara_service_operations o
 CROSS JOIN LATERAL (
  SELECT coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description) AS description
  OFFSET 0) d
 LEFT JOIN pdc_bus_private.operation_routing_history_20261015 h ON h.operation_id=o.operation_id
 LEFT JOIN pdc_operation_updates_private.ai_routing_20261019 r ON r.department=btrim(o.department)
  AND r.description_hash=pdc_work_categories_private.import_description_hash_20261017(d.description)
 WHERE o.operation_id=p_operation_id;
$function$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='snapshot_redundant_passes_removed' AND added_in='r410';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r410';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES ('pdc_bus_private.operation_station(uuid)','a63c9309fd6ae046d37709cfb3666019','r407','Operation station; approved description looked up once (r407, F21)');

DO $p$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r410 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r410 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r410 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','f2fdaab192cabddc1415818c2a3b123b'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','9c27e4da08f6ba975d3d15a2768bcc0d'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','532d487eb41805833e31504cd126af4d'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','092301d0e275176b27740b1cc7501972'),
  ('public.pdc_is_pre_delivery_20260910(text)','055281182d5c51f94291a8f5a9826c9f'),
  ('pdc_work_categories_private.import_description_hash_20261017(text)','136099468c385ae09aab4e43879cfa9e'),
  ('pdc_work_categories_private.stage(text)','622bea0ee56932c041c057927549c678'),
  ('public.pdc_department138_station_20260917(text)','0109ed60a4ea2feb71835633653640a4'),
  ('public.pdc_standard_operation_display_20260910(jsonb)','87169699a45421aa51b80ed658718e4e'),
  ('pdc_parts_private.service_scope(jsonb,text,text)','848892cd570ddfb6bd787af9f0266c56'),
  ('pdc_bus_private.operation_station(uuid)','a63c9309fd6ae046d37709cfb3666019')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>11 THEN RAISE EXCEPTION 'r410 undo: a function is not back to its pre-r410 version'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.pdc_is_pre_delivery_20260910(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('pdc_work_categories_private.import_description_hash_20261017(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('pdc_work_categories_private.stage(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('public.pdc_department138_station_20260917(text)','{postgres=X/postgres,service_role=X/postgres}truei|search_path=pg_catalog'),
  ('public.pdc_standard_operation_display_20260910(jsonb)','{postgres=X/postgres}falsei|search_path=pg_catalog, public'),
  ('pdc_parts_private.service_scope(jsonb,text,text)','{postgres=X/postgres}falses|search_path=pg_catalog, pdc_parts_private'),
  ('pdc_bus_private.operation_station(uuid)','{postgres=X/postgres}trues|search_path=pg_catalog')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole)<>11 THEN RAISE EXCEPTION 'r410 undo: owner, grants, security, volatility or search_path changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r410') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r410') THEN RAISE EXCEPTION 'r410 undo: r410 rows left'; END IF;
END $p$;
