-- Broome Toyota read-only salesperson site. No vehicle/import/workshop mutations.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
     WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN
  RAISE EXCEPTION 'STAGING environment required';
 END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS pdc_sales_private;
REVOKE ALL ON SCHEMA pdc_sales_private FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA pdc_sales_private TO authenticated;
CREATE TABLE pdc_sales_private.account_scopes (
 user_role_id uuid PRIMARY KEY REFERENCES public.pdc_user_roles(id) ON DELETE CASCADE,
 salesperson_id uuid NOT NULL REFERENCES public.salespeople(id) ON DELETE RESTRICT,
 dealer_code text NOT NULL DEFAULT '37047' CHECK (dealer_code='37047'),
 assigned_by uuid NOT NULL REFERENCES auth.users(id),
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE pdc_sales_private.account_scopes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_sales_private.account_scopes FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_sales_private.context()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pdc_sales_private AS $$
DECLARE r public.pdc_user_roles; sp public.salespeople; scope pdc_sales_private.account_scopes;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 SELECT * INTO r FROM public.pdc_user_roles
 WHERE email=lower(coalesce(auth.jwt()->>'email','')) AND active AND account_status='approved'
 AND (auth_user_id=auth.uid() OR auth_user_id IS NULL);
 IF r.role::text='administrator' THEN
  RETURN jsonb_build_object('role','administrator','display_name',coalesce(r.full_name,r.display_name,r.email),
   'dealer_code','37047','division','Broome Toyota');
 END IF;
 IF r.role::text IS DISTINCT FROM 'salesperson' OR r.auth_user_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Salesperson access required' USING errcode='42501';
 END IF;
 SELECT * INTO scope FROM pdc_sales_private.account_scopes WHERE user_role_id=r.id;
 SELECT * INTO sp FROM public.salespeople WHERE id=scope.salesperson_id AND active;
 IF sp.id IS NULL THEN RAISE EXCEPTION 'Ask an administrator to assign your salesperson access' USING errcode='42501'; END IF;
 RETURN jsonb_build_object('role','salesperson','display_name',sp.name,'salesperson_code',sp.code,
  'salesperson_id',sp.id,'dealer_code',scope.dealer_code,'division','Broome Toyota');
END $$;

CREATE FUNCTION pdc_sales_private.snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pdc_sales_private AS $$
DECLARE ctx jsonb:=pdc_sales_private.context(); rows jsonb; latest timestamptz;
BEGIN
 -- Only current Broome source rows. Identity is the existing immutable Navision
 -- record UUID, which survives updates and gaining a PMB canonical link.
 -- No stock/order/frame cross-matching and no client-selected salesperson scope.
 SELECT max(n.updated_at),coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',n.id,'canonical_vehicle_id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,
  'identity_status',CASE WHEN v.id IS NULL THEN 'awaiting_pmb_link' ELSE 'linked' END,
  'division','Broome Toyota','dealer_code',n.dealer_code,
  'salesperson_code',CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END,
  'salesperson_name',CASE WHEN v.salesperson_manual_override THEN sp.name ELSE source_sp.name END,
  'stock',coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',v.stock_number,''),
  'order',coalesce(n.normalized_data->>'order',v.toyota_order_number,''),
  'production_month',coalesce(n.normalized_data->>'prodMth',''),
  'client',coalesce(nullif(n.normalized_data->>'client',''),v.customer_name,n.normalized_data->>'toyotaCustomer',''),
  'vehicle',coalesce(nullif(n.normalized_data->>'vehicle',''),v.vehicle_description,v.model,''),
  'colour',coalesce(n.normalized_data->>'colourDescription',n.normalized_data->>'colour',''),
  'vin',CASE WHEN public.is_valid_vehicle_vin(v.vin) THEN v.vin ELSE public.pdc_navision_effective_vin_471(n.normalized_data) END,
  'suffix',coalesce(n.normalized_data->>'suffixDescription',n.normalized_data->>'suffix',''),
  'trim',coalesce(n.normalized_data->>'trimDescription',n.normalized_data->>'trim',''),
  'sales_type',coalesce(n.normalized_data->>'salesType',''),
  'customer_category',coalesce(n.normalized_data->>'dealerCustomerCategory',''),
  'toyota_status',coalesce(n.normalized_data->>'navisionSubLocationDescription',n.normalized_data->>'toyotaStatus',''),
  'location_status',coalesce(n.normalized_data->>'navisionLocationStatus',''),
  'kewdale_eta',coalesce(n.normalized_data->>'navisionKewdaleEta',''),
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
 ) ORDER BY n.id),'[]'::jsonb) INTO latest,rows
 FROM public.navision_backend_records n
 LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(n.normalized_data,'Salesperson')),''),
  nullif(n.normalized_data->>'salesperson',''),nullif(n.normalized_data->>'consultant',''),n.normalized_data->>'owner','')),' ',1))
 WHERE n.source_system='microsoft_navision' AND n.dealer_code=ctx->>'dealer_code'
 AND n.is_current AND n.record_status='current'
 AND (n.canonical_vehicle_id IS NULL OR v.id IS NOT NULL)
 AND (ctx->>'role'='administrator' OR
  CASE WHEN v.salesperson_manual_override THEN v.salesperson_id ELSE source_sp.id END=(ctx->>'salesperson_id')::uuid);
 IF jsonb_array_length(rows)>5000 THEN RAISE EXCEPTION 'Vehicle list exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',rows,'navision_updated_at',latest,'checked_at',now());
END $$;

CREATE FUNCTION pdc_sales_private.admin_accounts()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pdc_sales_private AS $$
BEGIN
 IF pdc_sales_private.context()->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
 RETURN jsonb_build_object(
  'accounts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',coalesce(r.full_name,r.display_name,r.email),
   'email',r.email,'status',r.account_status,'salesperson_id',a.salesperson_id) ORDER BY r.email),'[]'::jsonb)
   FROM public.pdc_user_roles r LEFT JOIN pdc_sales_private.account_scopes a ON a.user_role_id=r.id
   WHERE r.auth_user_id IS NOT NULL AND (r.account_status='pending' OR r.role::text='salesperson')),
  'salespeople',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'name',s.name) ORDER BY s.name),'[]'::jsonb)
   FROM public.salespeople s WHERE s.active));
END $$;

CREATE FUNCTION pdc_sales_private.assign_access(p_user_role_id uuid,p_salesperson_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,pdc_sales_private AS $$
DECLARE r public.pdc_user_roles; before_scope jsonb;
BEGIN
 IF pdc_sales_private.context()->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
 SELECT * INTO r FROM public.pdc_user_roles WHERE id=p_user_role_id FOR UPDATE;
 IF r.id IS NULL OR r.auth_user_id IS NULL OR
  NOT (r.account_status='pending' OR (r.account_status='approved' AND r.role::text='salesperson')) THEN
  RAISE EXCEPTION 'Choose a pending registration or an approved salesperson';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.salespeople WHERE id=p_salesperson_id AND active) THEN RAISE EXCEPTION 'Active salesperson required'; END IF;
 SELECT to_jsonb(a) INTO before_scope FROM pdc_sales_private.account_scopes a WHERE user_role_id=r.id;
 IF r.account_status='pending' THEN PERFORM public.admin_approve_user(r.email,'salesperson'::public.pdc_role,'Broome Toyota salesperson access'); END IF;
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by)
 VALUES(r.id,p_salesperson_id,auth.uid()) ON CONFLICT(user_role_id) DO UPDATE
 SET salesperson_id=excluded.salesperson_id,assigned_by=excluded.assigned_by,updated_at=now();
 PERFORM public.audit_pdc_event('role_change'::public.audit_action,'pdc_sales_private.account_scopes',r.id,NULL,
  before_scope,jsonb_build_object('salesperson_id',p_salesperson_id,'dealer_code','37047'),jsonb_build_object('operation','assign_broome_sales_access'));
 RETURN jsonb_build_object('ok',true);
END $$;

CREATE FUNCTION public.get_broome_sales_context() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=pg_catalog AS $$ SELECT pdc_sales_private.context() $$;
CREATE FUNCTION public.get_broome_sales_snapshot() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=pg_catalog AS $$ SELECT pdc_sales_private.snapshot() $$;
CREATE FUNCTION public.get_broome_sales_accounts() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=pg_catalog AS $$ SELECT pdc_sales_private.admin_accounts() $$;
CREATE FUNCTION public.assign_broome_sales_access(p_user_role_id uuid,p_salesperson_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER
SET search_path=pg_catalog AS $$ SELECT pdc_sales_private.assign_access(p_user_role_id,p_salesperson_id) $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_sales_private FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.context(),pdc_sales_private.snapshot(),pdc_sales_private.admin_accounts(),pdc_sales_private.assign_access(uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_broome_sales_context(),public.get_broome_sales_snapshot(),public.get_broome_sales_accounts(),public.assign_broome_sales_access(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_broome_sales_context(),public.get_broome_sales_snapshot(),public.get_broome_sales_accounts(),public.assign_broome_sales_access(uuid,uuid) TO authenticated;
