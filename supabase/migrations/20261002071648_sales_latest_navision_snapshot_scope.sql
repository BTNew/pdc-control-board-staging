-- Sales views follow the latest successfully applied dealer export immediately.
-- The PDC seven-update retention ledger and operational records remain unchanged.
DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF; END $guard$;
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
  'vin',CASE WHEN public.is_valid_vehicle_vin(v.vin) THEN v.vin ELSE public.pdc_navision_effective_vin_471(n.normalized_data) END,
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
END $function$
;
