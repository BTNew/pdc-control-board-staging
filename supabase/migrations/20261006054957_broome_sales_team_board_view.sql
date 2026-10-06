-- Staging-only, account-specific read access to the Broome vehicle board.
-- Existing own-vehicle snapshot and all write authorization remain unchanged.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
  WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN
  RAISE EXCEPTION 'Staging environment required';
 END IF;
END $$;
ALTER TABLE pdc_sales_private.account_scopes ADD COLUMN can_view_all_salespeople boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION pdc_sales_private.context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE r public.pdc_user_roles; sp public.salespeople; scope pdc_sales_private.account_scopes;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 SELECT * INTO r FROM public.pdc_user_roles
 WHERE email=lower(coalesce(auth.jwt()->>'email','')) AND active AND account_status='approved'
 AND (auth_user_id=auth.uid() OR auth_user_id IS NULL);
 IF r.role::text='administrator' THEN
  RETURN jsonb_build_object('role','administrator','display_name',coalesce(r.full_name,r.display_name,r.email),
   'dealer_code','37047','division','Broome Toyota','can_view_all_salespeople',true);
 END IF;
 IF r.role::text IS DISTINCT FROM 'salesperson' OR r.auth_user_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Salesperson access required' USING errcode='42501';
 END IF;
 SELECT * INTO scope FROM pdc_sales_private.account_scopes WHERE user_role_id=r.id;
 SELECT * INTO sp FROM public.salespeople WHERE id=scope.salesperson_id AND active;
 IF sp.id IS NULL THEN RAISE EXCEPTION 'Ask an administrator to assign your salesperson access' USING errcode='42501'; END IF;
 RETURN jsonb_build_object('role','salesperson','display_name',sp.name,'salesperson_code',sp.code,
  'salesperson_id',sp.id,'dealer_code',scope.dealer_code,'division','Broome Toyota',
  'can_view_all_salespeople',scope.can_view_all_salespeople);
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


CREATE OR REPLACE FUNCTION pdc_sales_private.board_snapshot()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$ SELECT pdc_sales_private.board_visibility_source_snapshot(false); $function$;


CREATE OR REPLACE FUNCTION pdc_sales_private.board_snapshot_with_ordering()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE base jsonb:=pdc_sales_private.board_snapshot(); items jsonb;
BEGIN
 SELECT coalesce(jsonb_agg(e.value||jsonb_build_object(
  'tint_complete',coalesce(p.tint_complete,false),'tint',coalesce(p.tint,false),'build_po',coalesce(p.build_po,false),'build_complete',coalesce(p.build_complete,false),
  'tray_ordered',coalesce(p.tray_ordered,false),'tray_complete',coalesce(p.tray_complete,false),
  'tint_not_required',coalesce(p.tint_not_required,false),'build_not_required',coalesce(p.build_not_required,false),'tray_not_required',coalesce(p.tray_not_required,false),
  'ordering_version',coalesce(p.version,0),'ordering_updated_at',p.updated_at
 ) ORDER BY e.ordinality),'[]'::jsonb) INTO items
 FROM jsonb_array_elements(base->'items') WITH ORDINALITY e(value,ordinality)
 LEFT JOIN pdc_sales_private.ordering_progress p ON p.tracking_id=(e.value->>'tracking_id')::uuid;
 RETURN jsonb_set(base,'{items}',items);
END $function$;


CREATE OR REPLACE FUNCTION pdc_sales_private.board_snapshot_with_pmb()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE base jsonb; result jsonb;
BEGIN
 base:=pdc_sales_private.board_snapshot_with_ordering();
 SELECT coalesce(jsonb_agg(e.item||CASE WHEN v.id IS NULL THEN
 jsonb_build_object('parts',NULL,'bay_bookings','[]'::jsonb,'active_workshop_booking_id',NULL)
 ELSE jsonb_build_object(
 'active_workshop_booking_id',v.active_workshop_booking_id,
 'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
 'pmb_stoppage_reason',v.pmb_stoppage_reason,'pmb_stoppage_started_at',v.pmb_stoppage_started_at,'pmb_stoppage_cleared_at',v.pmb_stoppage_cleared_at,
 'rft_confirmed_at',v.rft_confirmed_at,
 'parts',jsonb_build_object(
  'status',pf.data->>'label','complete',pf.data->'parts_complete',
  'snapshot_at',pf.data->>'parts_snapshot_at','confirmed_at',pf.data->>'confirmed_at',
  'updated_at',pu.updated_at,'required',pu.parts_required,'ordered',pu.parts_ordered,
  'received',pu.parts_received,'stoppage',pu.parts_stoppage,'stoppage_reason',pu.parts_stoppage_reason,'eta',pu.worst_eta,
  'jobs',(SELECT coalesce(jsonb_agg(jsonb_build_object('job_number',j->>'job_number','status',j->>'label',
   'backorder',j->'backorder','po_recorded',j->'backorder_with_po','snapshot_at',j->>'parts_snapshot_at')),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(pf.data->'jobs','[]'::jsonb)) j)),
 'bay_bookings',(SELECT coalesce(jsonb_agg(jsonb_build_object(
 'booking_id',b.id,'stage',s.display_name,'stage_code',s.code,'bay',bay.display_name,
 'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
 'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
 'stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
 'progress',pdc_fitter_private.progress(b.id))
 ORDER BY b.scheduled_start_at NULLS LAST,b.id),'[]'::jsonb)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id AND bay.stage_id=b.stage_id
 WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND b.status<>'deleted'
 AND NOT coalesce(b.legacy_ambiguity_quarantined,false))
 ) END ORDER BY e.ord),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(base->'items') WITH ORDINALITY e(item,ord)
 LEFT JOIN public.vehicles v ON v.id=(e.item->>'canonical_vehicle_id')::uuid AND v.deleted_at IS NULL
 LEFT JOIN LATERAL (SELECT u.* FROM public.vehicle_parts_updates u WHERE u.vehicle_id=v.id
 ORDER BY u.updated_at DESC,u.id DESC LIMIT 1) pu ON true
 LEFT JOIN LATERAL (SELECT public.pdc_parts_flags_vehicle_20260911(v.id) data WHERE v.id IS NOT NULL) pf ON true;
 RETURN base||jsonb_build_object('items',result);
END $function$;


CREATE OR REPLACE FUNCTION pdc_sales_private.board_snapshot_with_autocare()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE base jsonb; items jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 base:=pdc_sales_private.board_snapshot_with_pmb();
 SELECT coalesce(jsonb_agg(e.item||jsonb_build_object(
  'transport_number',coalesce(nullif(btrim(n.normalized_data->>'navisionTransportLoadNo'),''),
    public.navision_original_column_value(n.normalized_data,'Transport Load No.'),''),
  'autocare_dispatched',coalesce(d.dispatched,false) AND NOT (lower(coalesce(e.item->>'toyota_status','')) ~ 'delivered.*dealer|at dealer'),
  'autocare_dispatch_version',coalesce(d.version,0),'autocare_dispatched_at',d.dispatched_at
 ) ORDER BY e.ord),'[]'::jsonb) INTO items
 FROM jsonb_array_elements(base->'items') WITH ORDINALITY e(item,ord)
 LEFT JOIN public.navision_backend_records n ON n.id=(e.item->>'navision_record_id')::uuid
 LEFT JOIN pdc_sales_private.autocare_dispatches d ON d.dealer_code=e.item->>'dealer_code'
  AND d.order_key=upper(btrim(e.item->>'order'));
 RETURN jsonb_set(base,'{items}',items);
END $function$;


CREATE OR REPLACE FUNCTION pdc_sales_private.vehicle_notes_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); items jsonb; result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in to view vehicle notes' USING errcode='42501'; END IF;
 items:=pdc_sales_private.board_visibility_source_snapshot(false)->'items';
 SELECT coalesce(jsonb_agg(jsonb_build_object('tracking_id',n.tracking_id,'notes',n.notes,
 'custom_information',n.custom_information,'version',n.version,'updated_at',n.updated_at) ORDER BY n.tracking_id),'[]'::jsonb)
 INTO result FROM pdc_sales_private.vehicle_notes n
 WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(items) e WHERE e->>'tracking_id'=n.tracking_id::text
 AND NOT coalesce((e->>'identity_conflict')::boolean,false));
 RETURN result;
END $function$;


CREATE OR REPLACE FUNCTION pdc_sales_private.get_builds()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
 SELECT pdc_sales_private.board_visibility_source_snapshot(false)->'items',pdc_sales_private.build_stock_counts() INTO current_items,stock_counts;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',e->>'tracking_id','navision_record_id',e->>'navision_record_id','stock',e->>'stock','order',e->>'order',
  'items',b.data->'items','notes',b.data->'notes','other_lines',b.data->'other_lines','source_rows',b.data->'source_rows',
  'source_file',f.file_name,'source_file_sha256',f.file_sha256,'imported_at',b.imported_at,
  'source_stock',b.source_stock,'build_version',b.version
 ) ORDER BY e->>'stock',e->>'order'),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(current_items) e
 JOIN pdc_sales_private.sales_build_orders b ON b.dealer_code='37047' AND b.order_key=upper(btrim(e->>'order'))
  AND e->>'navision_record_id'=b.source_record_id::text
 JOIN pdc_sales_private.sales_build_import_batches f ON f.id=b.import_batch_id
 WHERE e->>'salesperson_code' IN ('AW','BG','PM','CW') AND NOT coalesce((e->>'identity_conflict')::boolean,false)
 AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
 AND coalesce((stock_counts->>btrim(e->>'stock'))::integer,0)=1;
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales build display exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $function$;


CREATE OR REPLACE FUNCTION pdc_sales_private.hidden_vehicle_snapshot()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$ SELECT pdc_sales_private.board_visibility_source_snapshot(true); $function$;


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

CREATE FUNCTION public.get_broome_sales_board_snapshot()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog
AS $$ SELECT pdc_sales_private.board_snapshot_with_autocare() $$;

CREATE FUNCTION pdc_sales_private.set_board_view_access(p_user_role_id uuid,p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,pdc_sales_private AS $$
DECLARE ctx jsonb:=pdc_sales_private.context(); target public.pdc_user_roles; old_scope jsonb; new_scope jsonb;
BEGIN
 IF auth.uid() IS NULL OR ctx->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
 IF p_enabled IS NULL THEN RAISE EXCEPTION 'Choose enabled or disabled'; END IF;
 SELECT * INTO target FROM public.pdc_user_roles WHERE id=p_user_role_id FOR UPDATE;
 IF target.id IS NULL OR target.role::text<>'salesperson' OR NOT target.active OR target.account_status<>'approved' OR target.auth_user_id IS NULL
 THEN RAISE EXCEPTION 'Approved active salesperson account required'; END IF;
 SELECT to_jsonb(s) INTO old_scope FROM pdc_sales_private.account_scopes s JOIN public.salespeople sp ON sp.id=s.salesperson_id AND sp.active
 WHERE s.user_role_id=target.id AND s.dealer_code='37047' FOR UPDATE OF s;
 IF old_scope IS NULL THEN RAISE EXCEPTION 'Assign Broome salesperson access first'; END IF;
 UPDATE pdc_sales_private.account_scopes SET can_view_all_salespeople=p_enabled,assigned_by=auth.uid(),updated_at=now()
 WHERE user_role_id=target.id AND dealer_code='37047' RETURNING to_jsonb(account_scopes) INTO new_scope;
 PERFORM public.audit_pdc_event('role_change'::public.audit_action,'pdc_sales_private.account_scopes',target.id,NULL,
  old_scope,new_scope,jsonb_build_object('operation','set_broome_sales_board_view_access','can_view_all_salespeople',p_enabled));
 RETURN jsonb_build_object('ok',true,'can_view_all_salespeople',p_enabled);
END $$;
CREATE FUNCTION public.set_broome_sales_board_view_access(p_user_role_id uuid,p_enabled boolean)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog
AS $$ SELECT pdc_sales_private.set_board_view_access(p_user_role_id,p_enabled) $$;

REVOKE ALL ON FUNCTION pdc_sales_private.board_visibility_source_snapshot(boolean),pdc_sales_private.board_snapshot(),
 pdc_sales_private.board_snapshot_with_ordering(),pdc_sales_private.board_snapshot_with_pmb(),
 pdc_sales_private.board_snapshot_with_autocare(),pdc_sales_private.set_board_view_access(uuid,boolean),
 public.get_broome_sales_board_snapshot(),public.set_broome_sales_board_view_access(uuid,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.board_snapshot_with_autocare(),pdc_sales_private.set_board_view_access(uuid,boolean),
 public.get_broome_sales_board_snapshot(),public.set_broome_sales_board_view_access(uuid,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
