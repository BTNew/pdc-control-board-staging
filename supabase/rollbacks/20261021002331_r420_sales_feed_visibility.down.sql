-- Undo r420 (F35): puts the six Sales functions back byte for byte (feed rows linked to a deleted PMB vehicle are dropped again),
-- drops the check helper, the r420 pins and the sales_shows_every_feed_row check. Staging cdsmnqxtyyoeoznmbidd only. No data changes.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r420 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r420 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r420 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r420 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('pdc_sales_private.visibility_source_snapshot(boolean)','e57e0904890225fad39c5e41ee1b14ef'),
  ('pdc_sales_private.board_visibility_source_snapshot(boolean)','37a9d2d92ce5c34e8617a0058cfd3e4f'),
  ('pdc_sales_private.completed_vehicle_snapshot()','f2ab5e92ebde49356a1c7ea83db43101'),
  ('pdc_sales_private.build_stock_counts()','4d0fb31776d0330c0741393a29d74585'),
  ('pdc_sales_private.crm_finance_refs()','4aaf4702df0aa0515485046e05892d0b'),
  ('pdc_sales_private.sales_accessory_candidates()','e533598aa607f2a94bbf4086d05f125c'),
  ('pdc_sales_private.feed_visibility_check_420()','b7c094f36407e23e79acab65dcebdc7e')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>7 THEN RAISE EXCEPTION 'r420 undo: r420 functions are not the expected versions'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r420')<>7 OR NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sales_shows_every_feed_row' AND added_in='r420') THEN RAISE EXCEPTION 'r420 undo: r420 is not applied'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_sales_private.visibility_source_snapshot(p_hidden boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); rows jsonb; latest timestamptz;
BEGIN
 -- Sales-only order identity follows the exact dealer + Toyota order, never stock or customer.
 -- Only the current successful Navision dealer snapshot supplies sales vehicles.
 WITH latest_scope AS MATERIALIZED (
  SELECT b.id FROM public.navision_import_batches b
  WHERE b.source_system='microsoft_navision' AND b.dealer_code=ctx->>'dealer_code'
    AND b.status='applied' AND b.rolled_back_at IS NULL
  ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
 ), source_rows AS (
  SELECT n.*, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) AS order_key
  FROM public.navision_backend_records n JOIN latest_scope applied ON applied.id=n.last_seen_batch_id WHERE source_system='microsoft_navision' AND dealer_code=ctx->>'dealer_code' AND n.is_current AND n.record_status='current'

 ), counted AS (
  SELECT n.*,count(*) OVER (PARTITION BY dealer_code,order_key) AS order_matches FROM source_rows n
 ), feed_values AS (
  SELECT coalesce(o.id,n.id) AS tracking_id,n.id,n.canonical_vehicle_id,n.dealer_code,n.order_key,
   n.normalized_data,n.updated_at,n.created_at,n.is_current,n.record_status,n.order_matches>1 AS identity_conflict
  FROM counted n LEFT JOIN pdc_sales_private.tracked_orders o
   ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
 ), feed AS (
  SELECT n.*,lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi'
   ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) AS cosi_status
  FROM feed_values n
 )
 SELECT max(n.updated_at),coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',n.tracking_id,'navision_record_id',n.id,'identity_conflict',n.identity_conflict,'source_current',n.is_current,'first_seen_at',n.created_at,'canonical_vehicle_id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,
  'sales_hidden',coalesce(h.hidden,false),'sales_visibility_version',coalesce(h.version,0),'sales_visibility_updated_at',h.changed_at,
  'identity_status',CASE WHEN v.id IS NULL THEN 'awaiting_pmb_link' ELSE 'linked' END,
  'division','Broome Toyota','dealer_code',n.dealer_code,'cosi',n.cosi_status IN ('yes','true','1'),
  'salesperson_code',CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END,
  'salesperson_name',CASE WHEN v.salesperson_manual_override THEN sp.name ELSE source_sp.name END,
  'stock',coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',v.stock_number,''),
  'order',coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order'),v.toyota_order_number,''),
  'production_month',coalesce(n.normalized_data->>'prodMth',''),
  'client',coalesce(nullif(n.normalized_data->>'client',''),v.customer_name,n.normalized_data->>'toyotaCustomer',''),
  'vehicle',coalesce(nullif(n.normalized_data->>'vehicle',''),v.vehicle_description,v.model,''),
  'colour',coalesce(n.normalized_data->>'colourDescription',n.normalized_data->>'colour',''),
  'vin',CASE WHEN public.is_valid_vehicle_vin(v.vin) THEN v.vin ELSE pdc_sales_private.source_vin(n.normalized_data) END,
  'suffix',coalesce(n.normalized_data->>'suffixDescription',n.normalized_data->>'suffix',''),
  'trim',coalesce(n.normalized_data->>'trimDescription',n.normalized_data->>'trim','')
 )||jsonb_build_object(
  'sales_type',coalesce(n.normalized_data->>'salesType',''),
  'customer_category',coalesce(n.normalized_data->>'dealerCustomerCategory',''),
  'toyota_status',coalesce(n.normalized_data->>'navisionSubLocationDescription',n.normalized_data->>'toyotaStatus',''),
  'location_status',coalesce(n.normalized_data->>'navisionLocationStatus',''),
  'kewdale_eta',coalesce(nullif(n.normalized_data->>'navisionKewdaleEta',''),v.eta_to_kewdale::text,''),
  'dealer_eta',coalesce(n.normalized_data->>'navisionEtaAtDealerBB',''),
  'port_plant_eta',coalesce(n.normalized_data->>'navisionPortPlantEta',''),
  'pmb_arrival_date',v.date_to_pmb,'dealer_delivered_date',v.delivered_to_dealer_date,
  'transport_booked_at',v.rft_transport_booked_at,'collected_at',v.rft_collected_at,
  'bay_bookings',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'stage',s.display_name,'bay',b.display_name,'status',w.status,
   'scheduled_start_at',w.scheduled_start_at,'scheduled_end_at',w.scheduled_end_at,
   'actual_start_at',w.actual_start_at,'actual_end_at',w.actual_end_at
  ) ORDER BY w.scheduled_start_at,w.id) FROM public.workshop_bookings w
   JOIN public.workshop_stages s ON s.id=w.stage_id LEFT JOIN public.workshop_bays b ON b.id=w.bay_id
   WHERE w.vehicle_id=v.id AND w.deleted_at IS NULL AND NOT w.legacy_ambiguity_quarantined),'[]'::jsonb),
  'navision_notes',coalesce(n.normalized_data->>'navisionDealerComments',''),
  'jita',n.normalized_data->'jitaPartsOrdered',
  'tint',v.sales_tint_raised,'build_po',v.sales_build_po_raised,'build_complete',v.sales_build_complete,
  'tray_ordered',CASE WHEN v.id IS NOT NULL THEN to_jsonb(v.sales_tray_ordered) ELSE n.normalized_data->'trayOrdered' END,
  'tray_complete',CASE WHEN v.id IS NOT NULL THEN to_jsonb(v.sales_tray_complete) ELSE n.normalized_data->'trayFitmentComplete' END,
  'pmb_location',coalesce(nullif(v.location_override,''),v.current_location),
  'pmb_stage',v.pmb_stage,'workshop_status',v.workshop_status,
  'key_number',v.key_number,'job_card',v.job_card_number,
  'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,
  'navision_updated_at',n.updated_at,'pmb_updated_at',v.updated_at
 ) ORDER BY n.tracking_id),'[]'::jsonb) INTO latest,rows
 FROM feed n
 LEFT JOIN LATERAL (SELECT x.* FROM pdc_sales_private.vehicle_visibility x
  WHERE x.tracking_id=n.tracking_id OR (NOT n.identity_conflict AND x.dealer_code=n.dealer_code AND x.order_key=n.order_key)
  ORDER BY (x.tracking_id=n.tracking_id) DESC LIMIT 1) h ON true
 LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(n.normalized_data,'Salesperson')),''),
  nullif(n.normalized_data->>'salesperson',''),nullif(n.normalized_data->>'consultant',''),n.normalized_data->>'owner','')),' ',1))
 WHERE n.cosi_status IN ('yes','true','1')
 AND (p_hidden IS NULL OR coalesce(h.hidden,false)=p_hidden)
 AND (n.canonical_vehicle_id IS NULL OR v.id IS NOT NULL)
 AND (ctx->>'role'='administrator' OR
  CASE WHEN v.salesperson_manual_override THEN v.salesperson_id ELSE source_sp.id END=(ctx->>'salesperson_id')::uuid);
 IF jsonb_array_length(rows)>5000 THEN RAISE EXCEPTION 'Vehicle list exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',rows,'navision_updated_at',latest,'checked_at',now());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.board_visibility_source_snapshot(p_hidden boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); rows jsonb; latest timestamptz;
BEGIN
 -- Sales-only order identity follows the exact dealer + Toyota order, never stock or customer.
 -- Only the current successful Navision dealer snapshot supplies sales vehicles.
 WITH latest_scope AS MATERIALIZED (
  SELECT b.id FROM public.navision_import_batches b
  WHERE b.source_system='microsoft_navision' AND b.dealer_code=ctx->>'dealer_code'
    AND b.status='applied' AND b.rolled_back_at IS NULL
  ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
 ), source_rows AS (
  SELECT n.*, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) AS order_key
  FROM public.navision_backend_records n JOIN latest_scope applied ON applied.id=n.last_seen_batch_id WHERE source_system='microsoft_navision' AND dealer_code=ctx->>'dealer_code' AND n.is_current AND n.record_status='current'

 ), counted AS (
  SELECT n.*,count(*) OVER (PARTITION BY dealer_code,order_key) AS order_matches FROM source_rows n
 ), feed_values AS (
  SELECT coalesce(o.id,n.id) AS tracking_id,n.id,n.canonical_vehicle_id,n.dealer_code,n.order_key,
   n.normalized_data,n.updated_at,n.created_at,n.is_current,n.record_status,n.order_matches>1 AS identity_conflict
  FROM counted n LEFT JOIN pdc_sales_private.tracked_orders o
   ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
 ), feed AS (
  SELECT n.*,lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi'
   ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) AS cosi_status
  FROM feed_values n
 )
 SELECT max(n.updated_at),coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',n.tracking_id,'navision_record_id',n.id,'identity_conflict',n.identity_conflict,'source_current',n.is_current,'first_seen_at',n.created_at,'canonical_vehicle_id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,
  'sales_hidden',coalesce(h.hidden,false),'sales_visibility_version',coalesce(h.version,0),'sales_visibility_updated_at',h.changed_at,
  'identity_status',CASE WHEN v.id IS NULL THEN 'awaiting_pmb_link' ELSE 'linked' END,
  'division','Broome Toyota','dealer_code',n.dealer_code,'cosi',n.cosi_status IN ('yes','true','1'),
  'salesperson_code',CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END,
  'salesperson_name',CASE WHEN v.salesperson_manual_override THEN sp.name ELSE source_sp.name END,
  'stock',coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',v.stock_number,''),
  'order',coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order'),v.toyota_order_number,''),
  'production_month',coalesce(n.normalized_data->>'prodMth',''),
  'client',coalesce(nullif(n.normalized_data->>'client',''),v.customer_name,n.normalized_data->>'toyotaCustomer',''),
  'vehicle',coalesce(nullif(n.normalized_data->>'vehicle',''),v.vehicle_description,v.model,''),
  'colour',coalesce(n.normalized_data->>'colourDescription',n.normalized_data->>'colour',''),
  'vin',CASE WHEN public.is_valid_vehicle_vin(v.vin) THEN v.vin ELSE pdc_sales_private.source_vin(n.normalized_data) END,
  'suffix',coalesce(n.normalized_data->>'suffixDescription',n.normalized_data->>'suffix',''),
  'trim',coalesce(n.normalized_data->>'trimDescription',n.normalized_data->>'trim','')
 )||jsonb_build_object(
  'sales_type',coalesce(n.normalized_data->>'salesType',''),
  'customer_category',coalesce(n.normalized_data->>'dealerCustomerCategory',''),
  'toyota_status',coalesce(n.normalized_data->>'navisionSubLocationDescription',n.normalized_data->>'toyotaStatus',''),
  'location_status',coalesce(n.normalized_data->>'navisionLocationStatus',''),
  'kewdale_eta',coalesce(nullif(n.normalized_data->>'navisionKewdaleEta',''),v.eta_to_kewdale::text,''),
  'dealer_eta',coalesce(n.normalized_data->>'navisionEtaAtDealerBB',''),
  'port_plant_eta',coalesce(n.normalized_data->>'navisionPortPlantEta',''),
  'pmb_arrival_date',v.date_to_pmb,'dealer_delivered_date',v.delivered_to_dealer_date,
  'transport_booked_at',v.rft_transport_booked_at,'collected_at',v.rft_collected_at,
  'bay_bookings',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'stage',s.display_name,'bay',b.display_name,'status',w.status,
   'scheduled_start_at',w.scheduled_start_at,'scheduled_end_at',w.scheduled_end_at,
   'actual_start_at',w.actual_start_at,'actual_end_at',w.actual_end_at
  ) ORDER BY w.scheduled_start_at,w.id) FROM public.workshop_bookings w
   JOIN public.workshop_stages s ON s.id=w.stage_id LEFT JOIN public.workshop_bays b ON b.id=w.bay_id
   WHERE w.vehicle_id=v.id AND w.deleted_at IS NULL AND NOT w.legacy_ambiguity_quarantined),'[]'::jsonb),
  'navision_notes',coalesce(n.normalized_data->>'navisionDealerComments',''),
  'jita',n.normalized_data->'jitaPartsOrdered',
  'tint',v.sales_tint_raised,'build_po',v.sales_build_po_raised,'build_complete',v.sales_build_complete,
  'tray_ordered',CASE WHEN v.id IS NOT NULL THEN to_jsonb(v.sales_tray_ordered) ELSE n.normalized_data->'trayOrdered' END,
  'tray_complete',CASE WHEN v.id IS NOT NULL THEN to_jsonb(v.sales_tray_complete) ELSE n.normalized_data->'trayFitmentComplete' END,
  'pmb_location',coalesce(nullif(v.location_override,''),v.current_location),
  'pmb_stage',v.pmb_stage,'workshop_status',v.workshop_status,
  'key_number',v.key_number,'job_card',v.job_card_number,
  'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,
  'navision_updated_at',n.updated_at,'pmb_updated_at',v.updated_at
 ) ORDER BY n.tracking_id),'[]'::jsonb) INTO latest,rows
 FROM feed n
 LEFT JOIN LATERAL (SELECT x.* FROM pdc_sales_private.vehicle_visibility x
  WHERE x.tracking_id=n.tracking_id OR (NOT n.identity_conflict AND x.dealer_code=n.dealer_code AND x.order_key=n.order_key)
  ORDER BY (x.tracking_id=n.tracking_id) DESC LIMIT 1) h ON true
 LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(n.normalized_data,'Salesperson')),''),
  nullif(n.normalized_data->>'salesperson',''),nullif(n.normalized_data->>'consultant',''),n.normalized_data->>'owner','')),' ',1))
 WHERE n.cosi_status IN ('yes','true','1')
 AND (p_hidden IS NULL OR coalesce(h.hidden,false)=p_hidden)
 AND (n.canonical_vehicle_id IS NULL OR v.id IS NOT NULL)
 AND (ctx->>'role'='administrator' OR coalesce((ctx->>'can_view_all_salespeople')::boolean,false) OR
  CASE WHEN v.salesperson_manual_override THEN v.salesperson_id ELSE source_sp.id END=(ctx->>'salesperson_id')::uuid);
 IF jsonb_array_length(rows)>5000 THEN RAISE EXCEPTION 'Vehicle list exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',rows,'navision_updated_at',latest,'checked_at',now());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.completed_vehicle_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); result jsonb; batch_id uuid; batch_at timestamptz;
BEGIN
 SELECT b.id,b.applied_at INTO batch_id,batch_at FROM public.navision_import_batches b
 WHERE b.source_system='microsoft_navision' AND b.dealer_code=ctx->>'dealer_code'
 AND b.status='applied' AND b.rolled_back_at IS NULL
 ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1;

 WITH source AS MATERIALIZED (
  SELECT n.*,upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),
   public.navision_original_column_value(n.normalized_data,'Order')))) AS order_key,
   b.result_revision AS seen_revision,b.applied_at AS last_seen_at
  FROM public.navision_backend_records n JOIN public.navision_import_batches b ON b.id=n.last_seen_batch_id
  WHERE n.source_system='microsoft_navision' AND n.dealer_code=ctx->>'dealer_code'
  AND b.source_system=n.source_system AND b.dealer_code=n.dealer_code
  AND b.status='applied' AND b.rolled_back_at IS NULL
 ), current_orders AS MATERIALIZED (
  -- Presence, including an unsold/hidden replacement, prevents an old copy of
  -- the same exact Toyota order from appearing in Completed.
  SELECT id,order_key FROM source WHERE last_seen_batch_id=batch_id AND is_current AND record_status='current'
 ), omitted AS (
  SELECT n.*,row_number() OVER(PARTITION BY coalesce(nullif(n.order_key,''),n.id::text)
   ORDER BY n.seen_revision DESC,n.last_seen_at DESC,n.updated_at DESC,n.id DESC) AS rank
  FROM source n WHERE batch_id IS NOT NULL AND n.last_seen_batch_id<>batch_id
  AND NOT EXISTS(SELECT 1 FROM current_orders c WHERE c.id=n.id OR
   (nullif(n.order_key,'') IS NOT NULL AND c.order_key=n.order_key))
 ), feed AS (
  SELECT n.*,coalesce(o.id,n.id) AS tracking_id,lower(btrim(coalesce(
   CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi'
   ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) AS cosi_status
  FROM omitted n LEFT JOIN pdc_sales_private.tracked_orders o ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key
  WHERE n.rank=1
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',n.tracking_id,'navision_record_id',n.id,'source_current',false,'cosi',true,
  'dealer_code',n.dealer_code,'order',coalesce(n.order_key,''),
  'stock',coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',''),
  'client',coalesce(nullif(n.normalized_data->>'client',''),n.normalized_data->>'toyotaCustomer',''),
  'vehicle',coalesce(n.normalized_data->>'vehicle',''),
  'salesperson_code',CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END,
  'salesperson_name',CASE WHEN v.salesperson_manual_override THEN sp.name ELSE source_sp.name END,
  'toyota_status',coalesce(n.normalized_data->>'navisionSubLocationDescription',n.normalized_data->>'toyotaStatus',''),
  'navision_notes',coalesce(n.normalized_data->>'navisionDealerComments',''),
  'notes',coalesce(notes.notes,''),'custom_information',coalesce(notes.custom_information,''),
  'last_seen_at',n.last_seen_at,'completed_at',omission.applied_at,
  'completion_reason','absent_from_navision','customer_delivery_confirmed',false
 ) ORDER BY omission.applied_at DESC NULLS LAST,n.last_seen_at DESC,n.tracking_id),'[]'::jsonb) INTO result
 FROM feed n
 LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(n.normalized_data,'Salesperson')),''),
  nullif(n.normalized_data->>'salesperson',''),nullif(n.normalized_data->>'consultant',''),n.normalized_data->>'owner','')),' ',1))
 LEFT JOIN pdc_sales_private.vehicle_notes notes ON notes.tracking_id=n.tracking_id
 LEFT JOIN LATERAL (
  SELECT b.applied_at FROM public.navision_import_batches b
  WHERE b.source_system=n.source_system AND b.dealer_code=n.dealer_code AND b.status='applied'
  AND b.rolled_back_at IS NULL AND b.result_revision>n.seen_revision
  -- The newest retained backend observation for this exact dealer/order was
  -- selected above. Its last_seen batch is therefore the last presence; the
  -- next successful dealer batch is the first omission. No per-order rescans
  -- of every historical raw spreadsheet row are needed.
  ORDER BY b.result_revision,b.applied_at,b.id LIMIT 1
 ) omission ON true
 WHERE n.cosi_status IN('yes','true','1')
 AND (n.canonical_vehicle_id IS NULL OR v.id IS NOT NULL)
 AND (ctx->>'role'='administrator' OR coalesce((ctx->>'can_view_all_salespeople')::boolean,false) OR CASE WHEN v.salesperson_manual_override THEN v.salesperson_id
  ELSE source_sp.id END=(ctx->>'salesperson_id')::uuid);
 IF jsonb_array_length(result)>5000 THEN RAISE EXCEPTION 'Completed vehicle list exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'latest_batch_id',batch_id,
  'navision_updated_at',batch_at,'checked_at',now());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.build_stock_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); result jsonb;
BEGIN
 IF ctx->>'dealer_code'<>'37047' THEN RAISE EXCEPTION 'Broome sales access required' USING errcode='42501'; END IF;
 WITH latest AS MATERIALIZED (
  SELECT b.id FROM public.navision_import_batches b WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047'
  AND b.status='applied' AND b.rolled_back_at IS NULL ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
 ), source_rows AS (
  SELECT n.*,upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) order_key
  FROM public.navision_backend_records n JOIN latest b ON b.id=n.last_seen_batch_id
  WHERE n.source_system='microsoft_navision' AND n.dealer_code='37047' AND n.is_current AND n.record_status='current'
 ), counted AS (
  SELECT n.*,count(*) OVER(PARTITION BY dealer_code,order_key) order_matches FROM source_rows n
 ), stocks AS (
 SELECT btrim(coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',v.stock_number,'')) AS stock FROM counted n
 LEFT JOIN pdc_sales_private.tracked_orders o ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
 LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN LATERAL (SELECT h.hidden FROM pdc_sales_private.vehicle_visibility h WHERE h.tracking_id=coalesce(o.id,n.id)
  OR (n.order_matches=1 AND h.dealer_code=n.dealer_code AND h.order_key=n.order_key)
  ORDER BY (h.tracking_id=coalesce(o.id,n.id)) DESC LIMIT 1) visibility ON true
 WHERE lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi' ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) IN ('yes','true','1')
 AND (n.canonical_vehicle_id IS NULL OR v.id IS NOT NULL) AND NOT coalesce(visibility.hidden,false)
 )
 SELECT coalesce(jsonb_object_agg(s.stock,s.matches),'{}'::jsonb) INTO result FROM (SELECT stock,count(*) AS matches FROM stocks GROUP BY stock) s;
 RETURN result;
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.crm_finance_refs()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); result jsonb;
BEGIN
 IF NOT (ctx->>'can_edit_finance')::boolean THEN RAISE EXCEPTION 'Finance editor access required' USING errcode='42501'; END IF;
 WITH source_rows AS (
  SELECT n.*,upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) order_key
  FROM public.navision_backend_records n WHERE source_system='microsoft_navision' AND dealer_code='37047'
 ), candidates AS (
  SELECT n.*,count(*) FILTER(WHERE is_current) OVER(PARTITION BY dealer_code,order_key) current_matches FROM source_rows n
 ), counted AS (
  SELECT n.*,count(*) OVER(PARTITION BY dealer_code,order_key) order_matches FROM candidates n
  WHERE n.is_current OR n.current_matches<>1 OR n.order_key IS NULL
 ), feed AS (
  SELECT coalesce(o.id,n.id) tracking_id,n.canonical_vehicle_id,
   CASE WHEN o.imported_at>n.updated_at THEN n.normalized_data||o.data ELSE n.normalized_data END data,
   n.order_matches>1 identity_conflict
  FROM counted n LEFT JOIN pdc_sales_private.tracked_orders o ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
  UNION ALL
  SELECT o.id,NULL::uuid,o.data,EXISTS(SELECT 1 FROM counted n WHERE n.order_key=o.order_key AND n.order_matches>1)
  FROM pdc_sales_private.tracked_orders o WHERE NOT EXISTS(SELECT 1 FROM counted n WHERE n.order_key=o.order_key AND n.order_matches=1)
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',n.tracking_id,'order',coalesce(nullif(n.data->>'order',''),public.navision_original_column_value(n.data,'Order'),v.toyota_order_number,''),
  'stock',coalesce(nullif(n.data->>'batch',''),n.data->>'stock',v.stock_number,''),
  'client',coalesce(nullif(n.data->>'client',''),v.customer_name,n.data->>'toyotaCustomer',''),
  'vehicle',coalesce(nullif(n.data->>'vehicle',''),v.vehicle_description,v.model,''),
  'salesperson_code',CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END,
  'salesperson_name',CASE WHEN v.salesperson_manual_override THEN sp.name ELSE source_sp.name END
 ) ORDER BY n.tracking_id),'[]'::jsonb) INTO result
 FROM feed n LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(n.data,'Salesperson')),''),nullif(n.data->>'salesperson',''),nullif(n.data->>'consultant',''),n.data->>'owner','')),' ',1))
 WHERE NOT n.identity_conflict AND (n.canonical_vehicle_id IS NULL OR v.id IS NOT NULL)
 AND lower(btrim(coalesce(CASE WHEN n.data ? 'cosi' THEN n.data->>'cosi' ELSE public.navision_original_column_value(n.data,'COSI') END,''))) IN ('yes','true','1');
 IF jsonb_array_length(result)>5000 THEN RAISE EXCEPTION 'Finance order list exceeds supported size'; END IF;
 RETURN result;
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.sales_accessory_candidates()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE result jsonb;
BEGIN
  WITH latest AS MATERIALIZED (
    SELECT b.id FROM public.navision_import_batches b WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047'
      AND b.status='applied' AND b.rolled_back_at IS NULL ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
  ), source_rows AS (
    SELECT n.*, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) order_key
    FROM public.navision_backend_records n JOIN latest b ON b.id=n.last_seen_batch_id
    WHERE n.source_system='microsoft_navision' AND n.dealer_code='37047' AND n.is_current AND n.record_status='current'
  ), counted AS (
    SELECT n.*, count(*) OVER (PARTITION BY dealer_code, order_key) order_matches FROM source_rows n
  ), feed AS (
    SELECT coalesce(o.id,n.id) tracking_id, n.id navision_record_id, n.order_key, n.order_matches>1 identity_conflict,
      n.is_current, n.canonical_vehicle_id, v.id vehicle_id,
      upper(btrim(coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',v.stock_number,''))) stock,
      CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END salesperson_code,
      coalesce(h.hidden,false) hidden,
      lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi'
        ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) IN ('yes','true','1') cosi
    FROM counted n
    LEFT JOIN pdc_sales_private.tracked_orders o ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
    LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
    LEFT JOIN LATERAL (SELECT x.hidden FROM pdc_sales_private.vehicle_visibility x
      WHERE x.tracking_id=coalesce(o.id,n.id) OR (n.order_matches=1 AND x.dealer_code=n.dealer_code AND x.order_key=n.order_key)
      ORDER BY (x.tracking_id=coalesce(o.id,n.id)) DESC LIMIT 1) h ON true
    LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
    LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
      nullif(btrim(public.navision_original_column_value(n.normalized_data,'Salesperson')),''),
      nullif(n.normalized_data->>'salesperson',''),nullif(n.normalized_data->>'consultant',''),n.normalized_data->>'owner','')),' ',1))
  )
  SELECT coalesce(jsonb_object_agg(f.stock, f.items),'{}'::jsonb) INTO result FROM (
    SELECT stock, jsonb_agg(jsonb_build_object('tracking_id',tracking_id,'navision_record_id',navision_record_id,'order_key',order_key,
      'identity_conflict',identity_conflict,'source_current',is_current,'salesperson_code',salesperson_code,
      'visible',(cosi AND NOT hidden AND (canonical_vehicle_id IS NULL OR vehicle_id IS NOT NULL)),
      'cosi',cosi,'hidden',hidden,'linked_vehicle_deleted',(canonical_vehicle_id IS NOT NULL AND vehicle_id IS NULL))
      ORDER BY order_key, tracking_id) items
    FROM feed WHERE stock<>'' GROUP BY stock) f;
  RETURN result;
END $function$;

DROP FUNCTION pdc_sales_private.feed_visibility_check_420();
DELETE FROM pdc_ops.regression_checks WHERE check_name='sales_shows_every_feed_row' AND added_in='r420';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r420';

DO $p$ BEGIN
 IF (SELECT count(*) FROM (VALUES
  ('pdc_sales_private.visibility_source_snapshot(boolean)','c51d473d947b4dea1ef457bb57f6d16d'),
  ('pdc_sales_private.board_visibility_source_snapshot(boolean)','2cdd2ec2581551363d39d055e2cf1397'),
  ('pdc_sales_private.completed_vehicle_snapshot()','0166ce1a667d93f7bf4283a80561add2'),
  ('pdc_sales_private.build_stock_counts()','82ee924af02273cb364235a7625ad6eb'),
  ('pdc_sales_private.crm_finance_refs()','1af3213189df1550d202e9f0dc6e274c'),
  ('pdc_sales_private.sales_accessory_candidates()','9e7cb1a8044d8840aa306e813ef63df7')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>6 THEN RAISE EXCEPTION 'r420 undo: Sales functions not restored'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('pdc_sales_private.visibility_source_snapshot(boolean)','{postgres=X/postgres}',true),
  ('pdc_sales_private.board_visibility_source_snapshot(boolean)','{postgres=X/postgres}',true),
  ('pdc_sales_private.completed_vehicle_snapshot()','{postgres=X/postgres,authenticated=X/postgres}',true),
  ('pdc_sales_private.build_stock_counts()','{postgres=X/postgres}',true),
  ('pdc_sales_private.crm_finance_refs()','{postgres=X/postgres}',true),
  ('pdc_sales_private.sales_accessory_candidates()','{postgres=X/postgres}',false)) e(sig,acl,def) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
   WHERE p.proacl::text=e.acl AND p.prosecdef=e.def AND p.provolatile='s' AND p.proowner='postgres'::regrole AND array_to_string(p.proconfig,'|')='search_path=pg_catalog, public, pdc_sales_private')<>6 THEN RAISE EXCEPTION 'r420 undo: owner, grants, security or settings of the Sales functions are not as expected'; END IF;
 IF to_regprocedure('pdc_sales_private.feed_visibility_check_420()') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r420')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r420') THEN RAISE EXCEPTION 'r420 undo: r420 objects remain'; END IF;
END $p$;
