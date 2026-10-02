-- Staff-created finance applications only. Existing PDC tables/functions are untouched.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING environment required'; END IF;
END $$;
CREATE TABLE pdc_sales_private.finance_applications (
 id uuid PRIMARY KEY, tracking_id uuid, salesperson_id uuid REFERENCES public.salespeople(id),
 vehicle jsonb NOT NULL DEFAULT '{}', data jsonb NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_by uuid NOT NULL REFERENCES auth.users(id), updated_by uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(jsonb_typeof(data)='object' AND octet_length(data::text)<=16384),
 CHECK(jsonb_typeof(vehicle)='object' AND octet_length(vehicle::text)<=2000),
 CHECK(tracking_id IS NOT NULL OR length(btrim(vehicle->>'model'))>0)
);
CREATE INDEX finance_applications_owner ON pdc_sales_private.finance_applications(salesperson_id,created_at DESC);
CREATE INDEX finance_applications_tracking ON pdc_sales_private.finance_applications(tracking_id,created_at DESC);
ALTER TABLE pdc_sales_private.finance_applications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_sales_private.finance_applications FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_sales_private.finance_application_json(r pdc_sales_private.finance_applications,p_editor boolean)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $fn$
 SELECT (CASE WHEN p_editor THEN r.data ELSE r.data-ARRAY['financier','finance_comm','dof_daf','mvi','rsa','total_comm','naf'] END)
 ||jsonb_build_object('id',r.id,'tracking_id',r.tracking_id,'vehicle',r.vehicle,'salesperson_code',s.code,'salesperson_name',s.name,
 'version',r.version,'created_at',r.created_at,'updated_at',r.updated_at)
 FROM (SELECT 1) x LEFT JOIN public.salespeople s ON s.id=r.salesperson_id
$fn$;
CREATE FUNCTION pdc_sales_private.finance_pipeline()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); editor boolean:=(ctx->>'can_edit_finance')::boolean; entries jsonb; refs jsonb:='[]'; people jsonb:='[]';
BEGIN
 SELECT coalesce(jsonb_agg(pdc_sales_private.finance_application_json(r,editor) ORDER BY r.created_at,r.id),'[]') INTO entries
 FROM pdc_sales_private.finance_applications r WHERE editor OR r.salesperson_id=(ctx->>'salesperson_id')::uuid;
 IF editor THEN
  refs:=pdc_sales_private.crm_finance_refs();
  SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.code,'name',s.name) ORDER BY s.name),'[]') INTO people FROM public.salespeople s WHERE s.active;
 END IF;
 RETURN jsonb_build_object('context',ctx,'entries',entries,'vehicle_options',refs,'salespeople',people,'checked_at',clock_timestamp());
END $fn$;
CREATE FUNCTION pdc_sales_private.finance_application_save(p_id uuid,p_tracking_id uuid,p_vehicle jsonb,p_salesperson_code text,p_data jsonb,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
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
  SELECT 1 FROM jsonb_object_keys(p_data) x WHERE x NOT IN ('customer','new_used','financier','group_name','approval','finance_comm','dof_daf','mvi','rsa','naf','settlement','notes','access','payout_complete')) THEN RAISE EXCEPTION 'Only the finance pipeline fields can be saved'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-finance-application:'||p_id::text,0));
 SELECT * INTO r FROM pdc_sales_private.finance_applications WHERE id=p_id FOR UPDATE;exists_row:=FOUND;
 IF exists_row THEN
  IF p_tracking_id IS DISTINCT FROM r.tracking_id OR (p_expected_version<>0 AND (p_vehicle IS NOT NULL OR p_salesperson_code IS NOT NULL)) THEN RAISE EXCEPTION 'An existing finance application cannot be linked to a different vehicle'; END IF;
  IF p_expected_version=0 THEN
   IF p_tracking_id IS NULL THEN
    IF jsonb_typeof(p_vehicle) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_each(p_vehicle) x WHERE jsonb_typeof(x.value)<>'string') THEN RAISE EXCEPTION 'Creation retry must retain its original vehicle'; END IF;
    SELECT jsonb_object_agg(key,btrim(value#>>'{}')) INTO v FROM jsonb_each(p_vehicle);
    IF v IS DISTINCT FROM r.vehicle OR p_salesperson_code IS DISTINCT FROM (SELECT code FROM public.salespeople WHERE id=r.salesperson_id) THEN RAISE EXCEPTION 'Creation retry must retain its original vehicle'; END IF;
   ELSIF p_vehicle IS NOT NULL OR p_salesperson_code IS NOT NULL THEN RAISE EXCEPTION 'Existing vehicle details come from its source'; END IF;
  END IF;
  d:=r.data||p_data;v:=r.vehicle;owner_id:=r.salesperson_id;
 ELSE
  IF p_expected_version<>0 THEN RAISE EXCEPTION 'This application does not exist. Refresh.' USING errcode='40001'; END IF;
  d:=jsonb_build_object('customer','','new_used','New','financier','','group_name','Broome','approval','','settlement','','notes','','access','','payout_complete','','finance_comm',NULL,'dof_daf',NULL,'mvi',NULL,'rsa',NULL,'naf',NULL)||p_data;
  IF p_tracking_id IS NOT NULL THEN
   SELECT e INTO item FROM jsonb_array_elements(pdc_sales_private.crm_finance_refs()) e WHERE e->>'tracking_id'=p_tracking_id::text;
   IF item IS NULL THEN RAISE EXCEPTION 'Choose an authorised existing vehicle' USING errcode='42501'; END IF;
   IF p_vehicle IS NOT NULL OR p_salesperson_code IS NOT NULL THEN RAISE EXCEPTION 'Existing vehicle details come from its source'; END IF;
   v:=jsonb_build_object('model',item->>'vehicle','stock',item->>'stock','order',item->>'order');
   SELECT id INTO owner_id FROM public.salespeople WHERE active AND code=item->>'salesperson_code';
   IF owner_id IS NULL THEN RAISE EXCEPTION 'The vehicle requires an assigned active salesperson'; END IF;
  ELSE
   IF jsonb_typeof(p_vehicle) IS DISTINCT FROM 'object' OR octet_length(p_vehicle::text)>2000 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_vehicle) x WHERE x NOT IN ('model','stock','order')) THEN RAISE EXCEPTION 'Enter vehicle model and optional stock/order references'; END IF;
   v:='{}';
   FOR k,val IN SELECT key,value FROM jsonb_each(p_vehicle) LOOP
    IF jsonb_typeof(val)<>'string' OR length(val#>>'{}')>200 THEN RAISE EXCEPTION 'Use bounded vehicle text'; END IF;
    v:=v||jsonb_build_object(k,btrim(val#>>'{}'));
   END LOOP;
   IF btrim(coalesce(v->>'model',''))='' THEN RAISE EXCEPTION 'Enter a vehicle model'; END IF;
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
END $fn$;
CREATE FUNCTION public.get_broome_finance_pipeline() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,pdc_sales_private AS $fn$ SELECT pdc_sales_private.finance_pipeline() $fn$;
CREATE FUNCTION public.save_broome_finance_application(p_id uuid,p_tracking_id uuid,p_vehicle jsonb,p_salesperson_code text,p_data jsonb,p_expected_version integer) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog,pdc_sales_private AS $fn$ SELECT pdc_sales_private.finance_application_save(p_id,p_tracking_id,p_vehicle,p_salesperson_code,p_data,p_expected_version) $fn$;
REVOKE ALL ON FUNCTION pdc_sales_private.finance_application_json(pdc_sales_private.finance_applications,boolean),pdc_sales_private.finance_pipeline(),pdc_sales_private.finance_application_save(uuid,uuid,jsonb,text,jsonb,integer),public.get_broome_finance_pipeline(),public.save_broome_finance_application(uuid,uuid,jsonb,text,jsonb,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.finance_pipeline(),pdc_sales_private.finance_application_save(uuid,uuid,jsonb,text,jsonb,integer),public.get_broome_finance_pipeline(),public.save_broome_finance_application(uuid,uuid,jsonb,text,jsonb,integer) TO authenticated;
