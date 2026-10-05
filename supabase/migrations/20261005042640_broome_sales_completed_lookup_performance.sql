-- Keep the identical read-only archive and approved scope; use retained last-seen authority.
DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF; END $guard$;
CREATE OR REPLACE FUNCTION pdc_sales_private.completed_vehicle_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','pdc_sales_private'
AS $fn$
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
 AND (ctx->>'role'='administrator' OR CASE WHEN v.salesperson_manual_override THEN v.salesperson_id
  ELSE source_sp.id END=(ctx->>'salesperson_id')::uuid);
 IF jsonb_array_length(result)>5000 THEN RAISE EXCEPTION 'Completed vehicle list exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'latest_batch_id',batch_id,
  'navision_updated_at',batch_at,'checked_at',now());
END $fn$;
