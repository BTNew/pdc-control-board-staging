-- Staging-only finance customer entries and dated settlement statistics.
-- Existing authentication, finance editor checks, ownership and version guards are retained.
DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF; END $guard$;
ALTER TABLE pdc_sales_private.finance_applications DROP CONSTRAINT finance_applications_check;
ALTER TABLE pdc_sales_private.finance_applications ADD CONSTRAINT finance_applications_customer_required
 CHECK(length(btrim(coalesce(data->>'customer','')))>0);
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
END $function$
;
NOTIFY pgrst,'reload schema';
