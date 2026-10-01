-- Broome sales COSI visibility only; no PDC data, imports, bookings or permissions changed.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING environment required'; END IF;
END $$;

CREATE OR REPLACE FUNCTION pdc_sales_private.snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); rows jsonb; latest timestamptz;
BEGIN
 -- Sales-only order identity follows the exact dealer + Toyota order, never stock or customer.
 -- Missing source rows stay visible with a freshness warning; no PDC records are restored.
 WITH source_rows AS (
  SELECT n.*, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) AS order_key
  FROM public.navision_backend_records n WHERE source_system='microsoft_navision' AND dealer_code=ctx->>'dealer_code'
 ), candidates AS (
  SELECT n.*,count(*) FILTER(WHERE is_current) OVER(PARTITION BY dealer_code,order_key) AS current_matches FROM source_rows n
 ), counted AS (
  SELECT n.*,count(*) OVER (PARTITION BY dealer_code,order_key) AS order_matches FROM candidates n
  WHERE n.is_current OR n.current_matches<>1 OR n.order_key IS NULL
 ), feed_values AS (
  SELECT coalesce(o.id,n.id) AS tracking_id,n.id,n.canonical_vehicle_id,n.dealer_code,
   CASE WHEN o.imported_at>n.updated_at THEN n.normalized_data||o.data ELSE n.normalized_data END AS normalized_data,
   greatest(n.updated_at,o.imported_at) AS updated_at,n.created_at,n.is_current,n.record_status,
   n.order_matches>1 AS identity_conflict
  FROM counted n LEFT JOIN pdc_sales_private.tracked_orders o
   ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
  UNION ALL
  SELECT o.id,NULL::uuid,NULL::uuid,o.dealer_code,o.data,o.imported_at,o.created_at,true,'sales_order',
   EXISTS(SELECT 1 FROM counted n WHERE n.order_key=o.order_key AND n.order_matches>1)
  FROM pdc_sales_private.tracked_orders o WHERE NOT EXISTS(
   SELECT 1 FROM counted n WHERE n.order_key=o.order_key AND n.order_matches=1)
 ), feed AS (
  SELECT n.*,lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi'
   ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) AS cosi_status
  FROM feed_values n
 )
 SELECT max(n.updated_at),coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',n.tracking_id,'navision_record_id',n.id,'identity_conflict',n.identity_conflict,'source_current',n.is_current,'first_seen_at',n.created_at,'canonical_vehicle_id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,
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
 LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(n.normalized_data,'Salesperson')),''),
  nullif(n.normalized_data->>'salesperson',''),nullif(n.normalized_data->>'consultant',''),n.normalized_data->>'owner','')),' ',1))
 WHERE n.cosi_status IN ('yes','true','1')
 AND (n.canonical_vehicle_id IS NULL OR v.id IS NOT NULL)
 AND (ctx->>'role'='administrator' OR
  CASE WHEN v.salesperson_manual_override THEN v.salesperson_id ELSE source_sp.id END=(ctx->>'salesperson_id')::uuid);
 IF jsonb_array_length(rows)>5000 THEN RAISE EXCEPTION 'Vehicle list exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',rows,'navision_updated_at',latest,'checked_at',now());
END $function$
;

CREATE OR REPLACE FUNCTION pdc_sales_private.import_orders(p_rows jsonb, p_apply boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); row_data jsonb; data jsonb; new_order_key text; stock text;
 accepted integer:=0; skipped integer:=0; early integer:=0; changed integer:=0; affected integer; visibility_updates integer:=0; sold boolean;
 keys text[]:=ARRAY[]::text[]; field text;
BEGIN
 IF ctx->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 5000 OR octet_length(p_rows::text)>8000000 THEN RAISE EXCEPTION 'Provide 1 to 5000 Navision rows'; END IF;
 FOR row_data IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  IF jsonb_typeof(row_data) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid Navision row'; END IF;
  IF row_data->>'dealer_code' IS DISTINCT FROM '37047' THEN RAISE EXCEPTION 'A Broome Toyota dealer 37047 export is required'; END IF;
  stock:=nullif(btrim(row_data->>'batch'),'');
  IF upper(coalesce(stock,'')) IN ('0','TBA') THEN stock:=NULL; END IF;
  new_order_key:=upper(btrim(coalesce(row_data->>'order','')));
  sold:=lower(btrim(coalesce(row_data->>'cosi',''))) IN ('yes','true','1');
  IF NOT sold AND EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE dealer_code='37047' AND order_key=new_order_key) THEN
   -- Negative/unknown COSI evidence hides only an existing exact private order.
   -- A cancelled order may no longer have a salesperson; preserve its previous display fields and checklist.
   IF new_order_key=ANY(keys) THEN RAISE EXCEPTION 'Duplicate Toyota order in export: %',new_order_key; END IF;
   keys:=array_append(keys,new_order_key); visibility_updates:=visibility_updates+1;
   IF stock IS NULL THEN skipped:=skipped+1; END IF;
   IF coalesce(p_apply,false) THEN
    UPDATE pdc_sales_private.tracked_orders target SET data=jsonb_set(target.data,'{cosi}',coalesce(row_data->'cosi','null'::jsonb)),imported_at=now(),imported_by=auth.uid()
    WHERE target.dealer_code='37047' AND target.order_key=new_order_key AND
     (target.data->'cosi' IS DISTINCT FROM coalesce(row_data->'cosi','null'::jsonb) OR target.imported_at<(SELECT max(n.updated_at) FROM public.navision_backend_records n WHERE n.source_system='microsoft_navision' AND n.dealer_code='37047' AND upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order'))))=new_order_key));
    GET DIAGNOSTICS affected=ROW_COUNT;changed:=changed+affected;
   END IF;
   CONTINUE;
  END IF;
  IF stock IS NULL AND NOT sold THEN skipped:=skipped+1; CONTINUE; END IF;
  IF length(new_order_key) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Every included vehicle requires its Toyota order number'; END IF;
  IF new_order_key=ANY(keys) THEN RAISE EXCEPTION 'Duplicate Toyota order in export: %',new_order_key; END IF;
  keys:=array_append(keys,new_order_key);
  IF NOT EXISTS(SELECT 1 FROM public.salespeople WHERE active AND upper(code)=upper(btrim(row_data->>'consultant'))) THEN RAISE EXCEPTION 'Included order has no recognised active salesperson'; END IF;
  -- Allowlist only sales display fields. No client-supplied IDs, links, PMB stages or flags.
  data:=jsonb_build_object('order',btrim(row_data->>'order'),'batch',coalesce(stock,''),'cosi',row_data->>'cosi');
  FOREACH field IN ARRAY ARRAY['consultant','client','vehicle','colourDescription','suffixDescription','trimDescription','vin','prodMth','navisionSubLocationDescription','navisionLocationStatus','navisionKewdaleEta','navisionEtaAtDealerBB','navisionPortPlantEta','navisionDealerComments'] LOOP
   IF length(coalesce(row_data->>field,''))>4000 THEN RAISE EXCEPTION 'Navision field exceeds supported length'; END IF;
   data:=data||jsonb_build_object(field,coalesce(row_data->>field,''));
  END LOOP;
  accepted:=accepted+1; IF stock IS NULL THEN early:=early+1; END IF;
  IF coalesce(p_apply,false) THEN
   INSERT INTO pdc_sales_private.tracked_orders AS target(id,dealer_code,order_key,data,imported_by)
   VALUES(coalesce((SELECT min(n.id::text)::uuid FROM public.navision_backend_records n WHERE n.source_system='microsoft_navision' AND n.dealer_code='37047' AND upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order'))))=new_order_key HAVING count(*)=1),gen_random_uuid()),'37047',new_order_key,data,auth.uid())
   ON CONFLICT(dealer_code,order_key) DO UPDATE SET data=excluded.data,imported_at=now(),imported_by=excluded.imported_by
   WHERE target.data IS DISTINCT FROM excluded.data OR target.imported_at<(SELECT max(n.updated_at) FROM public.navision_backend_records n WHERE n.source_system='microsoft_navision' AND n.dealer_code='37047' AND upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order'))))=new_order_key);
   GET DIAGNOSTICS affected=ROW_COUNT;changed:=changed+affected;
  END IF;
 END LOOP;
 IF accepted=0 AND visibility_updates=0 THEN RAISE EXCEPTION 'No eligible stocked or COSI sold orders were found'; END IF;
 RETURN jsonb_build_object('accepted',accepted,'without_stock',early,'skipped_unsold',skipped,'visibility_updates',visibility_updates,'changed',changed,'applied',coalesce(p_apply,false));
END $function$
;
