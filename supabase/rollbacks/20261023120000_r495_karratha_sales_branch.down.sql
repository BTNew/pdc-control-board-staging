-- r495 undo (F108). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Only needed if 20261023120000_r495_karratha_sales_branch.sql was applied.
-- Restores the Sales functions r495 replaced and their pins, drops the 7 new functions and check sales_branch_495,
-- drops sales_branches and salesperson_branches, and narrows the three dealer CHECKs back to '37047'.
-- Finance functions were not replaced (Craig 23 Oct). This file rewrites them only with the same pre-r495 bodies.
-- CF and SL are the existing Broome rows. Undo puts their emails back (clint.franklin@pmgwa.com.au, scott.lovett@pmgwa.com.au)
-- and removes only their Karratha 14450 mapping. Their Broome account scope is not touched and the people are not deleted.
-- RK/JS/DB placeholders inserted by r495 (those three ids only) are removed when unused. A skipped placeholder was never inserted.
-- The undo REFUSES if a placeholder is on a Sales account or a vehicle, or if any other Karratha data remains
-- (a Karratha Sales account, a hidden vehicle, an Autocare dispatch, or any other salesperson mapping). Those other rows are not deleted.
-- To switch Karratha off without deleting data:
--   UPDATE pdc_sales_private.sales_branches SET active=false WHERE dealer_code='14450';  (Karratha requests are then refused; Broome unaffected)
-- Revert the r495 PR as well (the Website drop-down then has no Karratha Toyota entry).
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r495 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r495 undo: staging only'; END IF;
 PERFORM set_config('pdc.r495_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r495_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r495_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r495_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r495 undo: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.context()')) IS DISTINCT FROM 'b95e3c7a8081c0cc49fcf68ba8071686' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.context() is not the r495 version; not undoing over unknown changes'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.visibility_source_snapshot(boolean)')) IS DISTINCT FROM '4a50d3bd71ae2178298bebce34e85d9f' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.visibility_source_snapshot(boolean) is not the r495 version; not undoing over unknown changes'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.board_visibility_source_snapshot(boolean)')) IS DISTINCT FROM '085cea9cec2ff1102591969416869784' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.board_visibility_source_snapshot(boolean) is not the r495 version; not undoing over unknown changes'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.crm_finance_refs()')) IS DISTINCT FROM '4aaf4702df0aa0515485046e05892d0b' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.crm_finance_refs() is not the pre-r495 version (this release does not replace finance)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_pipeline()')) IS DISTINCT FROM '372dcae199c750594923e2269f661e43' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.finance_pipeline() is not the pre-r495 version (this release does not replace finance)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_visibility_check_435()')) IS DISTINCT FROM 'b618db56602ab648872951306a5ad273' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.finance_visibility_check_435() is not the pre-r495 version (this release does not replace finance)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_builds()')) IS DISTINCT FROM '1f8a3b4c3d8d827bece9d0eb2bb20e8a' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.get_builds() is not the r495 version; not undoing over unknown changes'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_accessories()')) IS DISTINCT FROM '2f7f060cdaca01cc2763a15b921debf8' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.get_accessories() is not the r495 version; not undoing over unknown changes'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_application_save(uuid,uuid,jsonb,text,jsonb,integer)')) IS DISTINCT FROM 'bbeb49580363dcf5acc4dfac35d1e226' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.finance_application_save(uuid,uuid,jsonb,text,jsonb,integer) is not the pre-r495 version (this release does not replace finance)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.set_board_view_access(uuid,boolean)')) IS DISTINCT FROM '3e9fbb1b8bbd0ae26c885fa050143265' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.set_board_view_access(uuid,boolean) is not the r495 version; not undoing over unknown changes'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.admin_accounts()')) IS DISTINCT FROM 'fd9d90752b2d3a744c7853ba5b8fc5af' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.admin_accounts() is not the r495 version; not undoing over unknown changes'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)')) IS DISTINCT FROM 'a9dc1a0fdfa58c46159175c9eb72e0e7' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean) is not the r495 version; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r495')<>12 OR NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495' AND added_in='r495') THEN RAISE EXCEPTION 'r495 undo: r495 is not applied'; END IF;
 UPDATE public.salespeople SET email='clint.franklin@pmgwa.com.au' WHERE upper(btrim(code))='CF' AND lower(btrim(name))='clint franklin' AND lower(btrim(email))='clint.franklin@karrathatoyota.com.au';
 UPDATE public.salespeople SET email='scott.lovett@pmgwa.com.au' WHERE upper(btrim(code))='SL' AND lower(btrim(name))='scott lovett' AND lower(btrim(email))='scott@karrathatoyota.com.au';
 IF NOT EXISTS (SELECT 1 FROM public.salespeople WHERE upper(btrim(code))='CF' AND lower(btrim(name))='clint franklin' AND lower(btrim(email))='clint.franklin@pmgwa.com.au')
    OR NOT EXISTS (SELECT 1 FROM public.salespeople WHERE upper(btrim(code))='SL' AND lower(btrim(name))='scott lovett' AND lower(btrim(email))='scott.lovett@pmgwa.com.au') THEN
  RAISE EXCEPTION 'r495 undo: CF or SL is not back on the Broome email this release replaced. Emails were not left half-changed.';
 END IF;
 DELETE FROM pdc_sales_private.salesperson_branches WHERE dealer_code='14450' AND salesperson_id IN (SELECT id FROM public.salespeople WHERE (upper(btrim(code))='CF' AND lower(btrim(name))='clint franklin') OR (upper(btrim(code))='SL' AND lower(btrim(name))='scott lovett'));
 IF EXISTS (SELECT 1 FROM pdc_sales_private.account_scopes a WHERE a.salesperson_id IN ('c4950003-0000-4000-a000-000000000003','c4950004-0000-4000-a000-000000000004','c4950005-0000-4000-a000-000000000005'))
    OR EXISTS (SELECT 1 FROM public.vehicles v WHERE v.salesperson_id IN ('c4950003-0000-4000-a000-000000000003','c4950004-0000-4000-a000-000000000004','c4950005-0000-4000-a000-000000000005')) THEN
  RAISE EXCEPTION 'r495 undo: an RK/JS/DB placeholder is in use (Sales access or a vehicle). Nothing else is removed; switch the branch off instead (see header).';
 END IF;
 DELETE FROM pdc_sales_private.salesperson_branches WHERE salesperson_id IN ('c4950003-0000-4000-a000-000000000003','c4950004-0000-4000-a000-000000000004','c4950005-0000-4000-a000-000000000005');
 DELETE FROM public.salespeople WHERE id IN ('c4950003-0000-4000-a000-000000000003','c4950004-0000-4000-a000-000000000004','c4950005-0000-4000-a000-000000000005') AND NOT EXISTS (SELECT 1 FROM pdc_sales_private.account_scopes a WHERE a.salesperson_id=salespeople.id) AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.salesperson_id=salespeople.id);
 IF EXISTS (SELECT 1 FROM public.salespeople WHERE id IN ('c4950003-0000-4000-a000-000000000003','c4950004-0000-4000-a000-000000000004','c4950005-0000-4000-a000-000000000005')) THEN
  RAISE EXCEPTION 'r495 undo: an RK/JS/DB placeholder could not be removed.';
 END IF;
 IF EXISTS(SELECT 1 FROM pdc_sales_private.account_scopes WHERE dealer_code<>'37047') OR EXISTS(SELECT 1 FROM pdc_sales_private.vehicle_visibility WHERE dealer_code<>'37047')
    OR EXISTS(SELECT 1 FROM pdc_sales_private.autocare_dispatches WHERE dealer_code<>'37047')
    OR EXISTS(SELECT 1 FROM pdc_sales_private.salesperson_branches) THEN
  RAISE EXCEPTION 'r495 undo: Karratha Sales data exists (accounts / hidden vehicles / dispatches / roster beyond the unused seed). Nothing else is deleted by this undo; switch the branch off instead (see header) or ask Craig.';
 END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495' AND added_in='r495';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r495' AND signature IN ('pdc_sales_private.parse_branch_header_495(text)', 'pdc_sales_private.requested_branch_495()', 'pdc_sales_private.branch_info_495(text)', 'pdc_sales_private.assign_branch_access_495(uuid,uuid,text)', 'pdc_sales_private.set_salesperson_branch_495(uuid,text,boolean)', 'public.assign_pdc_sales_branch_access(uuid,uuid,text)', 'public.set_pdc_salesperson_branch(uuid,text,boolean)');

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
 -- r432 (F43): a controller (operator) whose account has a Sales record link uses Sales as that salesperson, with the
 -- same scope as a salesperson (own vehicles unless can_view_all_salespeople). It is never treated as administrator here.
 IF coalesce(r.role::text,'') NOT IN ('salesperson','operator') OR r.auth_user_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Salesperson access required' USING errcode='42501';
 END IF;
 SELECT * INTO scope FROM pdc_sales_private.account_scopes WHERE user_role_id=r.id;
 SELECT * INTO sp FROM public.salespeople WHERE id=scope.salesperson_id AND active;
 IF sp.id IS NULL AND r.role::text='operator' THEN RAISE EXCEPTION 'Salesperson access required' USING errcode='42501'; END IF;
 IF sp.id IS NULL THEN RAISE EXCEPTION 'Ask an administrator to assign your salesperson access' USING errcode='42501'; END IF;
 RETURN jsonb_build_object('role','salesperson','display_name',sp.name,'salesperson_code',sp.code,
  'salesperson_id',sp.id,'dealer_code',scope.dealer_code,'division','Broome Toyota',
  'can_view_all_salespeople',scope.can_view_all_salespeople,'account_role',r.role::text);
END $function$;

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
 -- r420 (F35): a feed row stays on Sales whatever its PMB state; a deleted PMB vehicle reads as awaiting PMB link.
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
 -- r420 (F35): a feed row stays on Sales whatever its PMB state; a deleted PMB vehicle reads as awaiting PMB link.
 AND (ctx->>'role'='administrator' OR coalesce((ctx->>'can_view_all_salespeople')::boolean,false) OR
  CASE WHEN v.salesperson_manual_override THEN v.salesperson_id ELSE source_sp.id END=(ctx->>'salesperson_id')::uuid);
 IF jsonb_array_length(rows)>5000 THEN RAISE EXCEPTION 'Vehicle list exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',rows,'navision_updated_at',latest,'checked_at',now());
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
 WHERE NOT n.identity_conflict -- r420 (F35): PMB state never hides a feed row
 AND lower(btrim(coalesce(CASE WHEN n.data ? 'cosi' THEN n.data->>'cosi' ELSE public.navision_original_column_value(n.data,'COSI') END,''))) IN ('yes','true','1');
 IF jsonb_array_length(result)>5000 THEN RAISE EXCEPTION 'Finance order list exceeds supported size'; END IF;
 RETURN result;
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.finance_pipeline()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); editor boolean:=(ctx->>'can_edit_finance')::boolean; entries jsonb; refs jsonb:='[]'; people jsonb:='[]';
BEGIN
 SELECT coalesce(jsonb_agg(pdc_sales_private.finance_application_json(r,editor) ORDER BY r.created_at,r.id),'[]') INTO entries
 -- r435 (F46): a salesperson with "view all salespeople" (can_view_all_salespeople) sees every finance entry, read-only, with the
 -- same non-editor field masking (no financier or commission figures); finance editors and administrators are unchanged.
 FROM pdc_sales_private.finance_applications r WHERE editor OR coalesce((ctx->>'can_view_all_salespeople')::boolean,false)
  OR r.salesperson_id=(ctx->>'salesperson_id')::uuid;
 IF editor THEN
  refs:=pdc_sales_private.crm_finance_refs();
  SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.code,'name',s.name) ORDER BY s.name),'[]') INTO people FROM public.salespeople s WHERE s.active;
 END IF;
 RETURN jsonb_build_object('context',ctx,'entries',entries,'vehicle_options',refs,'salespeople',people,'checked_at',clock_timestamp());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.finance_visibility_check_435(OUT ok boolean, OUT detail text)
 RETURNS record
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE prev text:=current_setting('request.jwt.claims',true); a record; f jsonb; total int; want int; got int; n int:=0; nva int:=0; bad text:='';
BEGIN
 -- r435 (F46): runs pdc_sales_private.finance_pipeline() as each approved Sales account (salesperson, or controller with a Sales
 -- record link) and compares what it returns with what it should: everything for view-all or finance editors, otherwise only that
 -- salesperson's own entries; non-editors never get financier or commission fields. Read-only; restores the caller's claims.
 SELECT count(*) INTO total FROM pdc_sales_private.finance_applications;
 FOR a IN SELECT r.id, r.email, r.auth_user_id, x.salesperson_id, x.can_view_all_salespeople va,
   EXISTS(SELECT 1 FROM pdc_sales_private.crm_finance_editors e WHERE e.user_role_id=r.id AND e.enabled) ed
  FROM public.pdc_user_roles r JOIN pdc_sales_private.account_scopes x ON x.user_role_id=r.id
  JOIN public.salespeople s ON s.id=x.salesperson_id AND s.active
  WHERE r.active AND r.account_status='approved' AND r.auth_user_id IS NOT NULL AND r.role::text IN ('salesperson','operator') AND x.dealer_code='37047'
  ORDER BY r.id
 LOOP
  n:=n+1; IF a.va THEN nva:=nva+1; END IF;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',a.auth_user_id,'email',a.email,'role','authenticated')::text,true);
  BEGIN
   f:=pdc_sales_private.finance_pipeline();
  EXCEPTION WHEN OTHERS THEN
   bad:=bad||' account '||left(a.id::text,8)||' error: '||SQLERRM||';'; f:=NULL;
  END;
  IF f IS NOT NULL THEN
   got:=jsonb_array_length(f->'entries');
   IF a.va OR a.ed THEN want:=total;
   ELSE SELECT count(*) INTO want FROM pdc_sales_private.finance_applications WHERE salesperson_id=a.salesperson_id; END IF;
   IF got<>want THEN bad:=bad||' account '||left(a.id::text,8)||' sees '||got||' of '||want||';'; END IF;
   IF NOT a.ed AND EXISTS(SELECT 1 FROM jsonb_array_elements(f->'entries') e WHERE e ?| ARRAY['financier','finance_comm','dof_daf','mvi','rsa','total_comm','naf']) THEN
    bad:=bad||' account '||left(a.id::text,8)||' (not a finance editor) gets financier/commission fields;';
   END IF;
  END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(prev,''),true);
 ok:=(bad='' AND n>0);
 detail:=format('%s Sales accounts; %s with view-all see all %s finance entries; the rest see only their own; non-editors get no commission fields%s',
  n,nva,total,CASE WHEN bad<>'' THEN ' | BAD:'||bad WHEN n=0 THEN ' | BAD: no Sales accounts found' ELSE '' END);
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

CREATE OR REPLACE FUNCTION pdc_sales_private.get_accessories()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
 SELECT pdc_sales_private.board_visibility_source_snapshot(false)->'items',pdc_sales_private.build_stock_counts() INTO current_items,stock_counts;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'tracking_id',e->>'tracking_id','navision_record_id',e->>'navision_record_id','stock',e->>'stock','order',e->>'order','quote',st.quote,
   'source_file',r.file_name,'snapshot_at',st.snapshot_at,'derived',d.ticks,'status_version',st.version,
   'display',jsonb_build_object(
     'tint',jsonb_build_object('state',d.ticks->'tint'->>'state','source','derived','reason',d.ticks->'tint'->>'reason'),
     'build_po',jsonb_build_object('state',d.ticks->'build'->>'state','source','derived','reason',d.ticks->'build'->>'reason'),
     'tray_ordered',jsonb_build_object('state',d.ticks->'tray'->>'state','source','derived','reason',d.ticks->'tray'->>'reason')),
   'lines',d.lines,
   -- r418: yard hold delay. at_or_past_yard_hold lifts every delay; delay_lifted_lines flags the order row.
   -- r427: yard hold is read from the whole stage order (board location, PMB dates and the Navision/Toyota stage).
   'at_or_past_yard_hold',pdc_sales_private.accessory_yard_hold_reached(e),'delay_lifted_lines',d.lifted
  ) ORDER BY e->>'stock',e->>'order'),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(current_items) e
 JOIN pdc_sales_private.sales_accessory_vehicle_status st ON st.dealer_code='37047' AND st.order_key=upper(btrim(e->>'order'))
  AND e->>'navision_record_id'=st.navision_record_id::text
 JOIN pdc_sales_private.sales_accessory_receipts r ON r.id=st.receipt_id
 CROSS JOIN LATERAL (
   SELECT pdc_sales_private.sales_accessory_ticks_delayed(coalesce(jsonb_agg(jsonb_build_object('line_class',l.line_class,'po_state',l.po_state,'delay_active',x.delay='delayed')),'[]'::jsonb)) ticks,
     coalesce(jsonb_agg(jsonb_build_object('group',l.line_class,'line',l.po_line,'item',l.description,'type',l.txn_type,
       'sublet',l.sub_type,'po',l.po_number,'po_state',l.po_state,'notes',l.notes,'in_house',l.in_house,'line_key',l.line_key,'delay',x.delay)
       ORDER BY array_position(ARRAY['build','tray','tint','admin'],l.line_class), l.source_row),'[]'::jsonb) lines,
     count(*) FILTER (WHERE x.delay='lifted') lifted
   FROM pdc_sales_private.sales_accessory_lines l
   LEFT JOIN pdc_sales_private.sales_accessory_line_delays dl ON dl.dealer_code=l.dealer_code AND dl.order_key=l.order_key AND dl.line_key=l.line_key
   CROSS JOIN LATERAL (SELECT CASE WHEN dl.line_key IS NULL OR l.po_state<>'blank' THEN 'none'
     WHEN pdc_sales_private.accessory_yard_hold_reached(e) THEN 'lifted' ELSE 'delayed' END delay) x
   WHERE l.dealer_code='37047' AND l.order_key=st.order_key AND l.superseded_receipt_id IS NULL) d
 WHERE e->>'salesperson_code' IN ('AW','BG','PM','CW') AND NOT coalesce((e->>'identity_conflict')::boolean,false)
 AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
 AND coalesce((stock_counts->>btrim(e->>'stock'))::integer,0)=1;
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales accessory display exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.finance_application_save(p_id uuid, p_tracking_id uuid, p_vehicle jsonb, p_salesperson_code text, p_data jsonb, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); r pdc_sales_private.finance_applications; d jsonb; v jsonb; item jsonb; owner_id uuid; k text; val jsonb; amount numeric; total numeric:=0; exists_row boolean;
BEGIN
 PERFORM 1 FROM public.pdc_user_roles WHERE id=(ctx->>'user_role_id')::uuid FOR SHARE;
 ctx:=pdc_sales_private.crm_context();
 IF NOT (ctx->>'can_edit_finance')::boolean THEN RAISE EXCEPTION 'Finance editor access required' USING errcode='42501'; END IF;
 IF ctx->>'role'<>'administrator' THEN
  PERFORM 1 FROM pdc_sales_private.crm_finance_editors WHERE user_role_id=(ctx->>'user_role_id')::uuid AND enabled FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Finance editor access changed' USING errcode='42501'; END IF;
 END IF;
 IF p_id IS NULL OR p_expected_version IS NULL OR p_expected_version<0 THEN RAISE EXCEPTION 'Application identity and version required'; END IF;
 IF jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR octet_length(p_data::text)>16384 OR EXISTS(
  SELECT 1 FROM jsonb_object_keys(p_data) x WHERE x NOT IN ('customer','new_used','financier','group_name','approval','finance_comm','dof_daf','mvi','rsa','naf','settlement','settlement_date','notes','access','payout_complete')) THEN RAISE EXCEPTION 'Only the finance pipeline fields can be saved'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-finance-application:'||p_id::text,0));
 SELECT * INTO r FROM pdc_sales_private.finance_applications WHERE id=p_id FOR UPDATE;exists_row:=FOUND;
 IF p_expected_version=0 AND p_tracking_id IS NULL AND p_vehicle IS NULL THEN p_vehicle:='{}'::jsonb; END IF;
 IF exists_row THEN
  IF p_tracking_id IS DISTINCT FROM r.tracking_id OR (p_expected_version<>0 AND (p_vehicle IS NOT NULL OR p_salesperson_code IS NOT NULL)) THEN RAISE EXCEPTION 'An existing finance application cannot be linked to a different vehicle'; END IF;
  IF p_expected_version=0 THEN
   IF p_tracking_id IS NULL THEN
    IF jsonb_typeof(p_vehicle) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_each(p_vehicle) x WHERE jsonb_typeof(x.value)<>'string') THEN RAISE EXCEPTION 'Creation retry must retain its original vehicle'; END IF;
    SELECT coalesce(jsonb_object_agg(key,btrim(value#>>'{}')),'{}'::jsonb) INTO v FROM jsonb_each(p_vehicle);
    IF v IS DISTINCT FROM r.vehicle OR p_salesperson_code IS DISTINCT FROM (SELECT code FROM public.salespeople WHERE id=r.salesperson_id) THEN RAISE EXCEPTION 'Creation retry must retain its original vehicle'; END IF;
   ELSIF p_vehicle IS NOT NULL OR p_salesperson_code IS NOT NULL THEN RAISE EXCEPTION 'Existing vehicle details come from its source'; END IF;
  END IF;
  d:=r.data||p_data;v:=r.vehicle;owner_id:=r.salesperson_id;
 ELSE
  IF p_expected_version<>0 THEN RAISE EXCEPTION 'This application does not exist. Refresh.' USING errcode='40001'; END IF;
  d:=jsonb_build_object('customer','','new_used','New','financier','','group_name','Broome','approval','','settlement','','settlement_date','','notes','','access','','payout_complete','','finance_comm',NULL,'dof_daf',NULL,'mvi',NULL,'rsa',NULL,'naf',NULL)||p_data;
  IF p_tracking_id IS NOT NULL THEN
   SELECT e INTO item FROM jsonb_array_elements(pdc_sales_private.crm_finance_refs()) e WHERE e->>'tracking_id'=p_tracking_id::text;
   IF item IS NULL THEN RAISE EXCEPTION 'Choose an authorised existing vehicle' USING errcode='42501'; END IF;
   IF p_vehicle IS NOT NULL OR p_salesperson_code IS NOT NULL THEN RAISE EXCEPTION 'Existing vehicle details come from its source'; END IF;
   v:=jsonb_build_object('model',item->>'vehicle','stock',item->>'stock','order',item->>'order');
   SELECT id INTO owner_id FROM public.salespeople WHERE active AND code=item->>'salesperson_code';
   IF owner_id IS NULL THEN RAISE EXCEPTION 'The vehicle requires an assigned active salesperson'; END IF;
  ELSE
   IF jsonb_typeof(p_vehicle) IS DISTINCT FROM 'object' OR octet_length(p_vehicle::text)>2000 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_vehicle) x WHERE x NOT IN ('model','stock','order')) THEN RAISE EXCEPTION 'Use bounded optional vehicle references'; END IF;
   v:='{}';
   FOR k,val IN SELECT key,value FROM jsonb_each(p_vehicle) LOOP
    IF jsonb_typeof(val)<>'string' OR length(val#>>'{}')>200 THEN RAISE EXCEPTION 'Use bounded vehicle text'; END IF;
    v:=v||jsonb_build_object(k,btrim(val#>>'{}'));
   END LOOP;
   -- Customer-only finance applications need no vehicle model.
   SELECT id INTO owner_id FROM public.salespeople WHERE active AND code=p_salesperson_code;
   IF p_salesperson_code IS NOT NULL AND owner_id IS NULL THEN RAISE EXCEPTION 'Choose an active salesperson or leave unassigned'; END IF;
  END IF;
 END IF;
 FOR k,val IN SELECT key,value FROM jsonb_each(d) WHERE key<>'total_comm' LOOP
  IF k IN ('finance_comm','dof_daf','mvi','rsa','naf') THEN
   IF val='null'::jsonb THEN CONTINUE; END IF;
   IF jsonb_typeof(val)<>'number' THEN RAISE EXCEPTION 'Finance amounts must be numbers or blank'; END IF;
   amount:=(val#>>'{}')::numeric;
   IF amount<0 OR amount>999999999.99 OR amount<>round(amount,2) THEN RAISE EXCEPTION 'Use a positive amount with up to two decimal places'; END IF;
  ELSE
   IF jsonb_typeof(val)<>'string' OR length(val#>>'{}')>(CASE WHEN k='notes' THEN 4000 ELSE 200 END) THEN RAISE EXCEPTION 'Use bounded finance text'; END IF;
   d:=d||jsonb_build_object(k,btrim(val#>>'{}'));
  END IF;
 END LOOP;
 IF coalesce(d->>'customer','')='' THEN RAISE EXCEPTION 'Enter the customer name'; END IF;
 IF d->>'new_used' NOT IN ('New','Used') OR d->>'group_name' NOT IN ('Broome','Port Hedland') THEN RAISE EXCEPTION 'Choose New/Used and a group'; END IF;
 FOREACH k IN ARRAY ARRAY['approval','settlement','access','payout_complete'] LOOP
  IF d->>k NOT IN ('','Yes','No') THEN RAISE EXCEPTION 'Choose Yes, No or blank'; END IF;
 END LOOP;
 IF p_data ? 'financier' THEN
  d:=d||jsonb_build_object('financier',upper(btrim(d->>'financier')));
  IF d->>'financier' NOT IN ('','TFS','TFM','FARADAY','OTHER') THEN RAISE EXCEPTION 'Choose TFS, TFM, FARADAY or OTHER'; END IF;
 END IF;
 IF d->>'settlement'='Yes' THEN
  IF NOT (p_data ? 'settlement_date') AND nullif(d->>'settlement_date','') IS NULL
   AND (NOT exists_row OR r.data->>'settlement' IS DISTINCT FROM 'Yes') THEN
   d:=d||jsonb_build_object('settlement_date',(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date::text);
  END IF;
  IF p_data ? 'settlement_date' AND nullif(d->>'settlement_date','') IS NULL THEN RAISE EXCEPTION 'Choose the settlement date'; END IF;
  IF nullif(d->>'settlement_date','') IS NOT NULL THEN
   IF d->>'settlement_date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' OR
    ((d->>'settlement_date')::date)::text<>(d->>'settlement_date') OR
    (d->>'settlement_date')::date>(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date OR
    (d->>'settlement_date')::date<'1900-01-01'::date THEN RAISE EXCEPTION 'Use a valid settlement date up to today'; END IF;
  END IF;
 ELSE
  d:=d||jsonb_build_object('settlement_date','');
 END IF;
 FOREACH k IN ARRAY ARRAY['finance_comm','dof_daf','mvi','rsa'] LOOP total:=total+coalesce((d->>k)::numeric,0); END LOOP;
 d:=d||jsonb_build_object('total_comm',total);
 IF exists_row THEN
  -- A lost creation response can be retried without making a second application.
  IF p_expected_version=0 AND r.version=1 AND r.created_by=auth.uid() AND d=r.data THEN RETURN jsonb_build_object('record',pdc_sales_private.finance_application_json(r,true)); END IF;
  IF r.version<>p_expected_version THEN RAISE EXCEPTION 'This finance entry changed. Refresh before saving your edits.' USING errcode='40001'; END IF;
  UPDATE pdc_sales_private.finance_applications SET data=d,version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE id=p_id RETURNING * INTO r;
 ELSE
  INSERT INTO pdc_sales_private.finance_applications(id,tracking_id,salesperson_id,vehicle,data,created_by,updated_by) VALUES(p_id,p_tracking_id,owner_id,v,d,auth.uid(),auth.uid()) RETURNING * INTO r;
 END IF;
 RETURN jsonb_build_object('record',pdc_sales_private.finance_application_json(r,true));
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.set_board_view_access(p_user_role_id uuid, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
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
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.admin_accounts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
BEGIN
 IF pdc_sales_private.context()->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
 RETURN jsonb_build_object(
  'accounts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',coalesce(r.full_name,r.display_name,r.email),
   'email',r.email,'status',r.account_status,'salesperson_id',a.salesperson_id) ORDER BY r.email),'[]'::jsonb)
   FROM public.pdc_user_roles r LEFT JOIN pdc_sales_private.account_scopes a ON a.user_role_id=r.id
   WHERE r.auth_user_id IS NOT NULL AND (r.account_status='pending' OR r.role::text='salesperson')),
  'salespeople',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'name',s.name) ORDER BY s.name),'[]'::jsonb)
   FROM public.salespeople s WHERE s.active));
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.link_salesperson_scope_429(p_user_role_id uuid, p_operation text, p_strict boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE r public.pdc_user_roles; cur pdc_sales_private.account_scopes; sp_ids uuid[]; v_sp uuid; v_actor uuid;
BEGIN
 -- r429 (F41). Called only from admin_change_role (strict) and admin_approve_user (not strict); not granted to app roles.
 SELECT * INTO r FROM public.pdc_user_roles WHERE id=p_user_role_id;
 IF r.id IS NULL OR r.role::text<>'salesperson' THEN RETURN NULL; END IF;
 SELECT * INTO cur FROM pdc_sales_private.account_scopes WHERE user_role_id=r.id;
 IF cur.user_role_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.salespeople s WHERE s.id=cur.salesperson_id AND s.active) THEN
  RETURN cur.salesperson_id;  -- already linked: never re-point an existing link
 END IF;
 SELECT array_agg(s.id) INTO sp_ids FROM public.salespeople s
  WHERE s.active AND s.email IS NOT NULL AND lower(btrim(s.email))=lower(btrim(r.email));
 v_actor:=auth.uid();
 IF coalesce(cardinality(sp_ids),0)<>1 OR v_actor IS NULL THEN
  IF p_strict THEN
   IF v_actor IS NULL THEN RAISE EXCEPTION 'Sign in required to link Sales access' USING errcode='42501'; END IF;
   IF coalesce(cardinality(sp_ids),0)=0 THEN
    RAISE EXCEPTION 'No active salesperson record has the email %, so their Sales access cannot be linked. Add them to the salespeople list (or correct the email there) first, then change the role again.', r.email USING errcode='22023';
   END IF;
   RAISE EXCEPTION 'More than one active salesperson record has the email %. Fix the salespeople list first, then change the role again.', r.email USING errcode='22023';
  END IF;
  RETURN NULL;
 END IF;
 v_sp:=sp_ids[1];
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by)
 VALUES(r.id,v_sp,v_actor) ON CONFLICT(user_role_id) DO UPDATE
 SET salesperson_id=excluded.salesperson_id,assigned_by=excluded.assigned_by,updated_at=now()
 WHERE account_scopes.user_role_id=excluded.user_role_id;
 PERFORM public.audit_pdc_event('role_change'::public.audit_action,'pdc_sales_private.account_scopes',r.id,NULL,
  CASE WHEN cur.user_role_id IS NULL THEN NULL ELSE to_jsonb(cur) END,
  jsonb_build_object('salesperson_id',v_sp,'dealer_code','37047'),
  jsonb_build_object('operation','assign_broome_sales_access','via',p_operation,'release','r429','matched_by','salespeople email'));
 RETURN v_sp;
END
$function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='f46074748e6fcb748b97b072d1160b4e',release='r432',note='restored by r495 undo (r432 version)',updated_at=now() WHERE signature='pdc_sales_private.context()' AND release='r495';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='e57e0904890225fad39c5e41ee1b14ef',release='r420',note='restored by r495 undo (r420 version)',updated_at=now() WHERE signature='pdc_sales_private.visibility_source_snapshot(boolean)' AND release='r495';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='37a9d2d92ce5c34e8617a0058cfd3e4f',release='r420',note='restored by r495 undo (r420 version)',updated_at=now() WHERE signature='pdc_sales_private.board_visibility_source_snapshot(boolean)' AND release='r495';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='6249e21543ac7caf096e3175c81406c4',release='r427',note='restored by r495 undo (r427 version)',updated_at=now() WHERE signature='pdc_sales_private.get_accessories()' AND release='r495';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='280d0afd36816510053cd6ea8fe154b1',release='r429b',note='restored by r495 undo (r429b version)',updated_at=now() WHERE signature='pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)' AND release='r495';
DROP FUNCTION public.assign_pdc_sales_branch_access(uuid,uuid,text);
DROP FUNCTION public.set_pdc_salesperson_branch(uuid,text,boolean);
DROP FUNCTION pdc_sales_private.assign_branch_access_495(uuid,uuid,text);
DROP FUNCTION pdc_sales_private.set_salesperson_branch_495(uuid,text,boolean);
DROP FUNCTION pdc_sales_private.branch_info_495(text);
DROP FUNCTION pdc_sales_private.requested_branch_495();
DROP FUNCTION pdc_sales_private.parse_branch_header_495(text);
DROP TABLE pdc_sales_private.salesperson_branches;
DROP TABLE pdc_sales_private.sales_branches;
ALTER TABLE pdc_sales_private.account_scopes DROP CONSTRAINT account_scopes_dealer_code_check;
ALTER TABLE pdc_sales_private.account_scopes ADD CONSTRAINT account_scopes_dealer_code_check CHECK (dealer_code = '37047');
ALTER TABLE pdc_sales_private.vehicle_visibility DROP CONSTRAINT vehicle_visibility_dealer_code_check;
ALTER TABLE pdc_sales_private.vehicle_visibility ADD CONSTRAINT vehicle_visibility_dealer_code_check CHECK (dealer_code = '37047');
ALTER TABLE pdc_sales_private.autocare_dispatches DROP CONSTRAINT autocare_dispatches_dealer_code_check;
ALTER TABLE pdc_sales_private.autocare_dispatches ADD CONSTRAINT autocare_dispatches_dealer_code_check CHECK (dealer_code = '37047');
DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.context()')) IS DISTINCT FROM 'f46074748e6fcb748b97b072d1160b4e' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.context() not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.visibility_source_snapshot(boolean)')) IS DISTINCT FROM 'e57e0904890225fad39c5e41ee1b14ef' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.visibility_source_snapshot(boolean) not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.board_visibility_source_snapshot(boolean)')) IS DISTINCT FROM '37a9d2d92ce5c34e8617a0058cfd3e4f' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.board_visibility_source_snapshot(boolean) not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.crm_finance_refs()')) IS DISTINCT FROM '4aaf4702df0aa0515485046e05892d0b' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.crm_finance_refs() not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_pipeline()')) IS DISTINCT FROM '372dcae199c750594923e2269f661e43' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.finance_pipeline() not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_visibility_check_435()')) IS DISTINCT FROM 'b618db56602ab648872951306a5ad273' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.finance_visibility_check_435() not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_builds()')) IS DISTINCT FROM '2c23751b84a788ae49eb58169ed89159' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.get_builds() not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_accessories()')) IS DISTINCT FROM '6249e21543ac7caf096e3175c81406c4' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.get_accessories() not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_application_save(uuid,uuid,jsonb,text,jsonb,integer)')) IS DISTINCT FROM 'bbeb49580363dcf5acc4dfac35d1e226' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.finance_application_save(uuid,uuid,jsonb,text,jsonb,integer) not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.set_board_view_access(uuid,boolean)')) IS DISTINCT FROM '1338c8ccee286f34ba7e60ff061f380b' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.set_board_view_access(uuid,boolean) not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.admin_accounts()')) IS DISTINCT FROM '42649fa165a7a40e625e15a1cd0051ab' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.admin_accounts() not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)')) IS DISTINCT FROM '280d0afd36816510053cd6ea8fe154b1' THEN RAISE EXCEPTION 'r495 undo: pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean) not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r495_tick') THEN RAISE EXCEPTION 'r495 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r495_frc') THEN RAISE EXCEPTION 'r495 undo: fault_regression_check changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r495') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r495')
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r495_pins')::int-7 THEN RAISE EXCEPTION 'r495 undo: did not fully undo'; END IF;
 IF to_regclass('pdc_sales_private.sales_branches') IS NOT NULL OR to_regprocedure('pdc_sales_private.requested_branch_495()') IS NOT NULL THEN RAISE EXCEPTION 'r495 undo: objects remain'; END IF;
END $g$;
