-- r411 (F27): snapshot stage 2 - collapse the inner snapshot layers into three segment functions; output unchanged.
-- Staging cdsmnqxtyyoeoznmbidd only. Builds on r410 (F26).
-- Before: pre168 -> 169 -> 174 -> 310 -> 395 -> 396 -> 399 -> 412 -> 422 -> 429 -> 700 -> 691 -> 693 -> 734 -> 739 -> 750
--         -> 767 -> 82000 -> 1020 -> ext1300 -> pilbara -> outer; each layer re-aggregated the whole vehicle array
--         (jsonb_agg + jsonb_set of ~25 MB) and the next one exploded it again.
-- After:  pre168 -> pre_691 (169..691 in one pass) -> 693 -> pre_750 (739+750) -> 767 -> pre_pilbara_service_v1
--         (82000, ext1300, pilbara) -> outer.
-- Each segment applies every old layer's own per-row expression, verbatim and in the same order, to the same row (one
-- LATERAL step per layer, OFFSET 0 so nothing is evaluated twice), with the same inner joins (422, 429), the same filter
-- (399), the same appended row sets (691, 739, ext1300, pilbara; verbatim) and the same sorts. A JSON null element is
-- carried as 'null'::jsonb exactly as jsonb_agg -> jsonb_array_elements did.
-- Not touched: the hard-coded vehicle special cases (pre_693 13000765, pre_767 d777b071: unchanged and still in the chain,
-- now pinned), every grant (CREATE OR REPLACE keeps owner, ACL, SECURITY DEFINER, STABLE, search_path; guarded), the clock
-- tick, the outer location and board functions, and stage 4. The 13 replaced layer functions are kept unchanged for undo.
-- Location and board snapshot JSON were byte-identical (overall, per department, per vehicle and order; administrator and
-- operator logins; with and without the edge fixture) in the rolled-back tests.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r411: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r411: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r411: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r411: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_691()','b6c81f618327621e74d8e24160188516'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_750()','d8dfcd8d9579d379eafe712594304a9c'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','844c796008c0c49e7328779214eae64f')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>3 THEN RAISE EXCEPTION 'r411: a function to change is not the expected version'; END IF;
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
  ('public.get_pdc_email_vehicle_board_snapshot()','a3a635b978cb6b266ea04f03c876672f')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>20 THEN RAISE EXCEPTION 'r411: a layer this release relies on (kept unchanged) is not the expected version'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_691()','{postgres=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_750()','{postgres=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_693()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_767()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole)<>5 THEN RAISE EXCEPTION 'r411: owner, grants, security, volatility or search_path changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='snapshot_segments_collapsed' OR added_in='r411') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r411') THEN RAISE EXCEPTION 'r411: already applied'; END IF;
 IF (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()')<>'844c796008c0c49e7328779214eae64fr410' THEN RAISE EXCEPTION 'r411: pilbara pin is not r410'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=199) THEN RAISE EXCEPTION 'r411: sort_order 199 taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_691()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$

-- r411 (F27): one pass for layers 169,174,310,395,396,399,412,422,429,700,691 (stage 2 of SNAPSHOT_PLAN.md).
-- Each lateral step below is that layer's own per-row expression, verbatim, applied in the same order to the
-- same row, with the same inner join (422, 429) and filter (399). The old layer functions are unchanged and
-- no longer called from here; old body of this function: r411 down migration.
DECLARE v_base jsonb; rows jsonb; collected_rows jsonb;
BEGIN
  v_base:=public.get_pdc_email_vehicle_location_snapshot_pre168();
  IF NOT coalesce((v_base->>'ok')::boolean,false) THEN RETURN v_base; END IF;
  SELECT coalesce(jsonb_agg(l11.o ORDER BY coalesce(coalesce(l10.o,'null'::jsonb)->>'stock_number',coalesce(l10.o,'null'::jsonb)->>'vin',coalesce(l10.o,'null'::jsonb)->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(v_base#>'{data,vehicles}','[]'::jsonb)) WITH ORDINALITY e(x0,ord)
  CROSS JOIN LATERAL (SELECT r.value||jsonb_build_object(
    'sublet_bookings',coalesce((select jsonb_agg(jsonb_build_object('booking_id',b.booking_id,'vehicle_id',b.vehicle_id,'vehicle_version',b.vehicle_version,'provider_id',b.provider_id,'provider_name',b.provider_name,'provider_email',b.provider_email,'out_date',b.out_date,'expected_return_date',b.expected_return_date,'status',b.status,'returned_at',b.returned_at,'returned_by',b.returned_by,'version',b.version,'notes',b.notes,'operation_line_identity',b.operation_line_identity,'operation_description',b.operation_description,'updated_at',b.updated_at) order by b.out_date,b.created_at,b.booking_id) from public.pdc_sublet_booking_instances b where b.vehicle_id=(r.value->>'id')::uuid),'[]'::jsonb),
    'sublet_active_count',(select count(*) from public.pdc_sublet_booking_instances b where b.vehicle_id=(r.value->>'id')::uuid and b.status='active')
  ) AS o FROM (SELECT e.x0 AS value, e.ord AS ordinality) r OFFSET 0) l1
  CROSS JOIN LATERAL (SELECT row_value||public.pdc_vehicle_milestone_json((row_value->>'id')::uuid) AS o FROM (SELECT coalesce(l1.o,'null'::jsonb) AS row_value) row_value OFFSET 0) l2
  CROSS JOIN LATERAL (SELECT 
    x
    || public.pdc_vehicle_key_number_json((x->>'id')::uuid)
    || public.pdc_vehicle_operational_json((x->>'id')::uuid) AS o FROM (SELECT coalesce(l2.o,'null'::jsonb) AS x) x OFFSET 0) l3
  CROSS JOIN LATERAL (SELECT x || public.pdc_vehicle_sales_dashboard_json((x->>'id')::uuid) || public.pdc_vehicle_effective_salesperson_json_386((x->>'id')::uuid) AS o FROM (SELECT coalesce(l3.o,'null'::jsonb) AS x) x OFFSET 0) l4
  CROSS JOIN LATERAL (SELECT 
    vehicle||jsonb_build_object(
      'qc_operation_lines',public.pdc_qc_operation_lines_379((vehicle->>'id')::uuid)
    ) AS o FROM (SELECT coalesce(l4.o,'null'::jsonb) AS vehicle) rw OFFSET 0) l5
  CROSS JOIN LATERAL (SELECT vehicle AS o FROM (SELECT coalesce(l5.o,'null'::jsonb) AS vehicle) rw
  WHERE NOT EXISTS(
    SELECT 1 FROM public.pdc_owner_supplied_document_receipts_396 r
    JOIN public.pdc_owner_supplied_document_undo_receipts_396 u ON u.receipt_id=r.receipt_id
    WHERE r.vehicle_id=(vehicle->>'id')::uuid
      AND NOT EXISTS(
        SELECT 1 FROM public.pdc_authenticated_email_import_receipts sibling
        WHERE sibling.vehicle_id=r.vehicle_id AND sibling.receipt_id<>r.canonical_import_receipt_id
      )
  ) OFFSET 0) l6
  CROSS JOIN LATERAL (SELECT vehicle||jsonb_build_object('qc_finalization',coalesce((SELECT jsonb_build_object('receipt_id',r.receipt_id,'photo_receipt_id',r.photo_receipt_id,'actor_id',r.actor_id,'actor_email',r.actor_email,'signed_off_at',r.created_at,'vehicle_version_before',r.vehicle_version_before,'vehicle_version_after',r.vehicle_version_after,'salesperson',r.salesperson_snapshot,'completed_items',r.completed_items_snapshot,'outbox_status',o.delivery_status,'outbox_notification_id',o.notification_id,'outbox_sent_at',o.sent_at,'outbox_delivered_at',o.delivered_at) FROM public.pdc_qc_finalization_receipts_399 r LEFT JOIN public.pdc_qc_salesperson_update_outbox_399 o ON o.finalization_receipt_id=r.receipt_id WHERE r.vehicle_id=(vehicle->>'id')::uuid ORDER BY r.created_at DESC LIMIT 1),'null'::jsonb)) AS o FROM (SELECT coalesce(l6.o,'null'::jsonb) AS vehicle) rw OFFSET 0) l7
  CROSS JOIN LATERAL (SELECT x||jsonb_build_object('rft_transport_booked_at',v.rft_transport_booked_at,'rft_transport_booked_by',v.rft_transport_booked_by,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,
   'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'mandatory',true) FROM public.pdc_rft_transport_salesperson_outbox_412 o WHERE o.vehicle_id=v.id ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb)) AS o FROM (SELECT coalesce(l7.o,'null'::jsonb) AS x) x JOIN public.vehicles v ON v.id=(x->>'id')::uuid OFFSET 0) l8
  CROSS JOIN LATERAL (SELECT x||jsonb_build_object('pmb_stoppage_reason',v.pmb_stoppage_reason,'pmb_stoppage_started_at',v.pmb_stoppage_started_at,'pmb_stoppage_started_by',v.pmb_stoppage_started_by,'pmb_stoppage_cleared_at',v.pmb_stoppage_cleared_at,'pmb_stoppage_cleared_by',v.pmb_stoppage_cleared_by,
   'workshop_bookings',coalesce((SELECT jsonb_agg(j.value||jsonb_build_object('version',b.version) ORDER BY j.ordinality) FROM jsonb_array_elements(coalesce(x->'workshop_bookings','[]'::jsonb)) WITH ORDINALITY j(value,ordinality) JOIN public.workshop_bookings b ON b.id=(j.value->>'booking_id')::uuid),'[]'::jsonb)) AS o FROM (SELECT coalesce(l8.o,'null'::jsonb) AS x) x JOIN public.vehicles v ON v.id=(x->>'id')::uuid OFFSET 0) l9
  CROSS JOIN LATERAL (SELECT x||jsonb_build_object('rft_transport_outbox',coalesce(x->'rft_transport_outbox','{}'::jsonb)||coalesce((SELECT jsonb_build_object('intercept_receipt_id',i.receipt_id,'intercepted_at',i.created_at,'intercept_outcome',i.outcome) FROM public.pdc_rft_transport_email_intercept_receipts_429 i WHERE i.vehicle_id=(x->>'id')::uuid ORDER BY i.created_at DESC LIMIT 1),'{}'::jsonb),'navision_colour',coalesce((SELECT coalesce(nullif(btrim(b.normalized_data->>'colourDescription'),''),nullif(btrim(b.normalized_data->>'colour'),'')) FROM public.navision_backend_records b WHERE b.canonical_vehicle_id=(x->>'id')::uuid AND b.is_current AND b.record_status='current' ORDER BY b.updated_at DESC,b.id LIMIT 1),''),'navision_salesperson_raw',coalesce((SELECT coalesce(public.navision_original_column_value(b.normalized_data,'Salesperson'),b.normalized_data->>'salesperson',b.normalized_data->>'consultant',b.normalized_data->>'owner') FROM public.navision_backend_records b WHERE b.canonical_vehicle_id=(x->>'id')::uuid AND b.is_current AND b.record_status='current' ORDER BY b.updated_at DESC,b.id LIMIT 1),'') ) AS o FROM (SELECT coalesce(l9.o,'null'::jsonb) AS x) x OFFSET 0) l10
  CROSS JOIN LATERAL (SELECT x||public.pdc_final_lifecycle_overlay_700((x->>'id')::uuid) AS o FROM (SELECT coalesce(l10.o,'null'::jsonb) AS x) x OFFSET 0) l11;
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
  RETURN jsonb_set(v_base,'{data,vehicles}',rows,true);
END
$function$;
CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_750()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$

-- r411 (F27): one function for pre_739 then pre_750 (stage 2 of SNAPSHOT_PLAN.md), reading pre_693 directly
-- (pre_734 is a pass-through to it since r410). pre_739's per-row merge, sort and appended rows are verbatim,
-- and pre_750's per-row merge runs over that array in the same order with the same sort. Old body: r411 down migration.
DECLARE r jsonb; rows jsonb; appended jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_693();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'delivery_enabled',o.delivery_enabled,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',true,'evidence',coalesce((SELECT jsonb_build_object('evidence_id',e.evidence_id,'mime_version',e.mime_version,'mime_content_type',e.mime_content_type,'mime_sha256',e.mime_sha256,'photo_receipt_id',e.photo_receipt_id,'photo_bucket_id',e.photo_bucket_id,'photo_storage_path',e.photo_storage_path,'photo_content_type',e.photo_content_type,'photo_byte_length',e.photo_byte_length,'photo_sha256',e.photo_sha256,'intercepted',e.intercepted) FROM public.pdc_rft_transport_email_evidence_734 e WHERE e.notification_id=o.notification_id),'{}'::jsonb)) FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=(x->>'id')::uuid ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb),'dealer_transit_statistic',coalesce((SELECT jsonb_build_object('statistic_id',s.statistic_id,'started_at',s.started_at,'closed_at',s.closed_at,'duration_seconds',s.duration_seconds,'status_literal',s.status_literal) FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE s.vehicle_id=(x->>'id')::uuid),'{}'::jsonb)) ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,'registration',v.registration,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'visible_on_board',v.visible_on_board,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'qc_completed_at',v.qc_completed_at,'qc_completed_by',v.qc_completed_by,'rft_transport_booked_at',v.rft_transport_booked_at,'rft_transport_booked_by',v.rft_transport_booked_by,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,'salesperson_id',v.salesperson_id,'salesperson_reference',sp->>'salesperson_name','salesperson_code',sp->>'salesperson_code','salesperson_name',sp->>'salesperson_name','salesperson_email',sp->>'salesperson_email','work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id),'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'delivery_enabled',o.delivery_enabled,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',true) FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=v.id ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb),'dealer_transit_statistic',coalesce((SELECT jsonb_build_object('statistic_id',s.statistic_id,'started_at',s.started_at,'closed_at',s.closed_at,'duration_seconds',s.duration_seconds,'status_literal',s.status_literal) FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE s.vehicle_id=v.id),'{}'::jsonb)
  ) ORDER BY v.rft_collected_at,v.id),'[]'::jsonb) INTO appended
  FROM public.vehicles v CROSS JOIN LATERAL public.pdc_vehicle_effective_salesperson_json_386(v.id) sp
  WHERE v.deleted_at IS NULL AND v.current_location IN('Collected','Completed') AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 q WHERE q.vehicle_id=v.id AND q.action IN('collected','delivered')) AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE (x->>'id')=v.id::text);
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('rft_transport_draft',coalesce((SELECT jsonb_build_object(
    'draft_id',d.draft_id,'draft_filename',d.draft_filename,'mime_content_type',d.mime_content_type,
    'mime_byte_length',d.mime_byte_length,'mime_sha256',d.mime_sha256,'photo_receipt_id',d.photo_receipt_id,
    'photo_content_type',d.photo_content_type,'photo_byte_length',d.photo_byte_length,'photo_sha256',d.photo_sha256,
    'status',d.status,'delivery_enabled',false,'intercepted',true,'sent_at',null,'delivered_at',null)
    FROM public.pdc_rft_transport_email_drafts_739 d WHERE d.vehicle_id=(x->>'id')::uuid ORDER BY d.created_at DESC LIMIT 1),'{}'::jsonb)) ORDER BY x->>'stock_number' ),'[]'::jsonb) INTO rows
  FROM (SELECT x FROM jsonb_array_elements(rows||coalesce(appended,'[]'::jsonb)) WITH ORDINALITY e(x,ord) ORDER BY ord) x;
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END
$function$;
CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$

-- r411 (F27): one function for pre_82000, pre_ext1300 and pre_pilbara_service_v1 (stage 2 of SNAPSHOT_PLAN.md),
-- reading pre_767 directly (pre_1020 is a pass-through to pre_82000 since r410). Each step is that layer's own
-- per-row expression, verbatim, in the same order; the appended rows of ext1300 and pilbara are verbatim.
-- The old layer functions are unchanged; old body of this function: r411 down migration.
DECLARE base jsonb; rows jsonb; ext_appended jsonb; appended jsonb;
BEGIN
  base:=public.get_pdc_email_vehicle_location_snapshot_pre_767();
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  SELECT coalesce(jsonb_agg(l2.o ORDER BY coalesce(coalesce(l1.o,'null'::jsonb)->>'stock_number',coalesce(l1.o,'null'::jsonb)->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,vehicles}','[]'::jsonb)) WITH ORDINALITY e(x0,ord)
  CROSS JOIN LATERAL (SELECT 
    x || CASE WHEN x->>'current_location'='PMB' AND q.receipt_id IS NOT NULL THEN jsonb_build_object(
      'qc_fix',jsonb_build_object('status','Pending QC fixes','reason',q.reason,'receipt_id',q.receipt_id,
        'vehicle_id',q.vehicle_id,'stock_number',q.stock_number,'expected_vehicle_version',q.expected_vehicle_version,
        'created_at',q.created_at,'history_preserved',true))
    ELSE '{}'::jsonb END AS o FROM (SELECT e.x0 AS x) x
  LEFT JOIN LATERAL (
    SELECT z.receipt_id,z.vehicle_id,z.stock_number,z.reason,z.expected_vehicle_version,z.created_at
    FROM public.pdc_qc_vehicle_rejection_receipts_767 z
    WHERE z.vehicle_id=(x->>'id')::uuid
    ORDER BY z.created_at DESC,z.receipt_id DESC LIMIT 1
  ) q ON true OFFSET 0) l1
  CROSS JOIN LATERAL (SELECT x||jsonb_build_object('lifecycle_history',coalesce(h,'{}'::jsonb))||jsonb_build_object(
   'first_reached_yard_hold_at',h->'first_reached_yard_hold_at','first_entered_pmb_at',h->'first_entered_pmb_at','first_became_rft_at',h->'first_became_rft_at',
   'elapsed_yard_hold_to_pmb_days',h->'elapsed_yard_hold_to_pmb_days','elapsed_pmb_to_rft_days',h->'elapsed_pmb_to_rft_days','elapsed_yard_hold_to_rft_days',h->'elapsed_yard_hold_to_rft_days') AS o FROM (SELECT coalesce(l1.o,'null'::jsonb) AS x) x
  LEFT JOIN LATERAL public.pdc_lifecycle_history_payload_82000((x->>'id')::uuid) h ON true OFFSET 0) l2;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'key_number',v.key_number,'job_card_number',v.job_card_number,
   'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'make',v.make,'model',v.model,'registration',v.registration,
   'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'visible_on_board',v.visible_on_board,'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,
   'delivered_to_dealer_date',v.delivered_to_dealer_date,'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,
   'qc_completed_at',v.qc_completed_at,'qc_completed_by',v.qc_completed_by,'source_system',v.source_system,'source_record_id',v.source_record_id,
   'pdc_lifecycle',jsonb_build_object('state',case when v.current_location='Completed' or v.lifecycle_state::text='completed' then 'completed' when v.current_location='Collected' then 'collected' else lower(v.lifecycle_state::text) end,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'rft_collected_at',v.rft_collected_at,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds),
   'lifecycle_history',h,'first_reached_yard_hold_at',h->'first_reached_yard_hold_at','first_entered_pmb_at',h->'first_entered_pmb_at','first_became_rft_at',h->'first_became_rft_at',
   'elapsed_yard_hold_to_pmb_days',h->'elapsed_yard_hold_to_pmb_days','elapsed_pmb_to_rft_days',h->'elapsed_pmb_to_rft_days','elapsed_yard_hold_to_rft_days',h->'elapsed_yard_hold_to_rft_days',
   'work_items',coalesce((select jsonb_agg(to_jsonb(w) order by w.work_key) from public.vehicle_work_items w where w.vehicle_id=v.id),'[]'::jsonb)
 ) ORDER BY coalesce(v.rft_collected_at,v.updated_at),v.id),'[]'::jsonb) INTO ext_appended
 FROM public.vehicles v
 LEFT JOIN LATERAL public.pdc_lifecycle_history_payload_82000(v.id) h ON true
 WHERE v.deleted_at IS NULL AND (v.current_location IN('Collected','Completed') OR v.lifecycle_state::text='completed')
   AND (h IS NOT NULL OR EXISTS(select 1 from public.pdc_final_pdc_lifecycle_receipts_700 q where q.vehicle_id=v.id) OR EXISTS(select 1 from public.pdc_rft_transport_lifecycle_receipts_734 q where q.vehicle_id=v.id))
   AND NOT EXISTS(select 1 from jsonb_array_elements(rows) x where (x->>'id')=v.id::text);
  SELECT coalesce(jsonb_agg(l4.o ORDER BY coalesce(coalesce(l3.o,'null'::jsonb)->>'stock_number',coalesce(l3.o,'null'::jsonb)->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(rows||coalesce(ext_appended,'[]'::jsonb)) WITH ORDINALITY e(x0,ord)
  CROSS JOIN LATERAL (SELECT x||jsonb_build_object('validated_operation_source',public.pdc_email_ai_v2_validated_operation_source_20260902((x->>'id')::uuid)) AS o FROM (SELECT e.x0 AS x) x OFFSET 0) l3
  CROSS JOIN LATERAL (SELECT x||jsonb_build_object(
    'pdc_lifecycle',lc.v,
    'external_completion',CASE WHEN lc.v ? 'external_completion' THEN lc.v->'external_completion'
      ELSE public.pdc_external_completion_json_20260903((x->>'id')::uuid) END
  ) AS o FROM (SELECT coalesce(l3.o,'null'::jsonb) AS x) x
  CROSS JOIN LATERAL (SELECT public.pdc_rft_transport_lifecycle_state_734((x->>'id')::uuid) AS v OFFSET 0) lc OFFSET 0) l4;
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
END
$function$;
DELETE FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()' AND release='r410';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
('public.get_pdc_email_vehicle_location_snapshot_pre_691()','775d90e421042423670990b467f157be','r411','Snapshot segment 1: layers 169-691 in one pass over pre168 (r411, F27)'),
('public.get_pdc_email_vehicle_location_snapshot_pre_750()','714fa7a3a5f79e95f2cd891ba96045cc','r411','Snapshot segment 2: layers 739+750 in one function over pre_693 (r411, F27)'),
('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','580bf52022a37d11b78f228c37254c4a','r411','Snapshot segment 3: layers 82000, ext1300, pilbara in one function over pre_767 (r411, F27)'),
('public.get_pdc_email_vehicle_location_snapshot_pre_693()','4f3f4dd8cab754543d3c0cc934ad111f','r411','Snapshot layer pre_693: hard-coded 13000765 special case, unchanged; stage 4 for Craig (pinned r411, F27)'),
('public.get_pdc_email_vehicle_location_snapshot_pre_767()','db446d2222101f0028666333779fdf23','r411','Snapshot layer pre_767: hard-coded d777b071 special case, unchanged; stage 4 for Craig (pinned r411, F27)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
('snapshot_segments_collapsed','F27','Snapshot stage 2 stays in place: pre_691 runs layers 169-691 in one pass over pre168, pre_750 runs 739+750 over pre_693, the pilbara layer runs 82000, ext1300 and pilbara over pre_767; the special-case layers pre_693 (13000765) and pre_767 (d777b071) are unchanged in the chain; the 13 replaced old layer functions still exist for undo; all SECURITY DEFINER STABLE with the fixed search_path.','WITH want(sig, calls, not_calls, kind) AS (VALUES
    (''public.get_pdc_email_vehicle_location_snapshot_pre_691()'', ''get_pdc_email_vehicle_location_snapshot_pre168()'', ''get_pdc_email_vehicle_location_snapshot_pre_700()'', ''segment''),
    (''public.get_pdc_email_vehicle_location_snapshot_pre_750()'', ''get_pdc_email_vehicle_location_snapshot_pre_693()'', ''get_pdc_email_vehicle_location_snapshot_pre_739()'', ''segment''),
    (''public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()'', ''get_pdc_email_vehicle_location_snapshot_pre_767()'', ''get_pdc_email_vehicle_location_snapshot_pre_ext1300()'', ''segment''),
    (''public.get_pdc_email_vehicle_location_snapshot_pre_693()'', ''get_pdc_email_vehicle_location_snapshot_pre_691()'', NULL, ''special''),
    (''public.get_pdc_email_vehicle_location_snapshot_pre_767()'', ''get_pdc_email_vehicle_location_snapshot_pre_750()'', NULL, ''special''),
    (''public.get_pdc_email_vehicle_location_snapshot()'', ''get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()'', NULL, ''outer'')
), p AS (
  SELECT w.*, pr.oid IS NOT NULL AS present, pr.prosrc, pr.prosecdef, pr.provolatile::text AS v,
         coalesce(array_to_string(pr.proconfig, ''|''), '''') = ''search_path=pg_catalog, public'' AS sp
  FROM want w LEFT JOIN pg_catalog.pg_proc pr ON pr.oid = to_regprocedure(w.sig)
), s AS (
  SELECT count(*) FILTER (WHERE NOT present OR NOT prosecdef OR v <> ''s'' OR NOT sp
           OR prosrc NOT LIKE ''%'' || calls || ''%'' OR (not_calls IS NOT NULL AND prosrc LIKE ''%'' || not_calls || ''%'')) AS bad,
         bool_and(prosrc LIKE ''%r411 (F27)%'') FILTER (WHERE kind = ''segment'') AS segments_r411,
         bool_and(prosrc LIKE ''%13000765%'') FILTER (WHERE sig LIKE ''%pre_693()'') AS c693,
         bool_and(prosrc LIKE ''%d777b071-a2b0-5367-893b-aa83a07fcfce%'') FILTER (WHERE sig LIKE ''%pre_767()'') AS c767
  FROM p
), kept AS (
  SELECT count(*) AS n FROM unnest(ARRAY[''169'',''174'',''310'',''395'',''396'',''399'',''412'',''422'',''429'',''700'',''739'',''82000'',''ext1300'']) l
  JOIN pg_catalog.pg_proc pr ON pr.oid = to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot_pre'' || CASE WHEN l = ''168'' THEN '''' ELSE ''_'' END || l || ''()'')
)
SELECT s.bad = 0 AND coalesce(s.segments_r411, false) AND coalesce(s.c693, false) AND coalesce(s.c767, false) AND kept.n = 13 AS ok,
  s.bad || '' of 6 snapshot functions not in the r411 call order (pre168 -> pre_691 -> 693 -> 750 -> 767 -> pilbara -> outer) or not SECURITY DEFINER STABLE with the fixed search_path; ''
  || CASE WHEN coalesce(s.segments_r411, false) THEN ''segments are r411 bodies'' ELSE ''segments are NOT the r411 bodies'' END || ''; ''
  || CASE WHEN coalesce(s.c693, false) AND coalesce(s.c767, false) THEN ''special cases 13000765 (693) and d777b071 (767) still in place'' ELSE ''a special-case layer changed'' END || ''; ''
  || kept.n || ''/13 old layer functions kept for undo'' AS detail
FROM s, kept',true,199,'r411');

DO $p$ DECLARE r record; BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r411: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r411: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r411: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_691()','775d90e421042423670990b467f157be'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_750()','714fa7a3a5f79e95f2cd891ba96045cc'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','580bf52022a37d11b78f228c37254c4a')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>3 THEN RAISE EXCEPTION 'r411: a function is not the r411 version'; END IF;
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
  ('public.get_pdc_email_vehicle_board_snapshot()','a3a635b978cb6b266ea04f03c876672f')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>20 THEN RAISE EXCEPTION 'r411: a kept layer changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_691()','{postgres=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_750()','{postgres=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_693()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_767()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole)<>5 THEN RAISE EXCEPTION 'r411: owner, grants, security, volatility or search_path changed'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='snapshot_segments_collapsed')<>'0212fb0a088ccb59178dd1f5fbbafc2c' THEN RAISE EXCEPTION 'r411: check md5'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r411' AND md5(p.prosrc)=e.prosrc_md5)<>5 THEN RAISE EXCEPTION 'r411: pins'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='snapshot_segments_collapsed') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r411: check not ok: %', r.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='snapshot_redundant_passes_removed') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r411: r410 check not ok: %', r.detail; END IF;
END $p$;
