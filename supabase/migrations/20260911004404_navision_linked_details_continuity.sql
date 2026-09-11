CREATE OR REPLACE FUNCTION public.pdc_refresh_linked_vehicle_from_navision_481_pre_20260905(p_backend_record_id uuid, p_actor_id uuid, p_actor_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE b public.navision_backend_records%rowtype;v public.vehicles%rowtype;before_row jsonb;after_row jsonb;stock text;effective_vin text;customer text;description text;colour text;sales_raw text;sales_code text;sales_id uuid;sales_ref text;changed boolean:=false;BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR p_backend_record_id IS NULL THEN RETURN public.navision_backend_response(false,'wrong_environment_or_invalid_input');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('navision-linked-refresh:'||p_backend_record_id::text,0));SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id FOR UPDATE;
 IF NOT FOUND OR NOT b.is_current OR b.record_status<>'current' OR b.canonical_vehicle_id IS NULL THEN RETURN public.navision_backend_response(true,'no_current_canonical_link',jsonb_build_object('changed',false));END IF;
 stock:=nullif(public.normalize_vehicle_stock_number(b.normalized_data->>'batch'),'');SELECT * INTO v FROM public.vehicles WHERE id=b.canonical_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR stock IS NULL OR v.stock_number_normalized IS DISTINCT FROM stock THEN RETURN public.navision_backend_response(false,'canonical_link_or_stock_mismatch');END IF;
 IF EXISTS(SELECT 1 FROM public.vehicles x WHERE x.id<>v.id AND x.deleted_at IS NULL AND x.stock_number_normalized=stock) THEN RETURN public.navision_backend_response(false,'duplicate_operational_stock_conflict');END IF;
 effective_vin:=public.pdc_navision_effective_vin_471(b.normalized_data);IF effective_vin IS NULL AND public.is_valid_vehicle_vin(v.vin) AND right(public.normalize_vehicle_vin(v.vin),length(public.normalize_vehicle_vin(b.normalized_data->>'vin')))=public.normalize_vehicle_vin(b.normalized_data->>'vin') THEN effective_vin:=v.vin_normalized;END IF;
 customer:=coalesce(nullif(btrim(b.normalized_data->>'client'),''),nullif(btrim(b.normalized_data->>'customerSurname'),''),nullif(btrim(b.normalized_data->>'toyotaCustomer'),''));description:=coalesce(nullif(btrim(b.normalized_data->>'vehicle'),''),nullif(btrim(b.normalized_data->>'modelDescription'),''),nullif(btrim(b.normalized_data->>'toyotaVehicle'),''));colour:=coalesce(nullif(btrim(b.normalized_data->>'colourDescription'),''),nullif(btrim(b.normalized_data->>'colour'),''));sales_raw:=coalesce(public.navision_original_column_value(b.normalized_data,'Salesperson'),nullif(btrim(b.normalized_data->>'salesperson'),''),nullif(btrim(b.normalized_data->>'consultant'),''),nullif(btrim(b.normalized_data->>'owner'),''));sales_code:=upper(split_part(coalesce(sales_raw,''),' ',1));SELECT id,code INTO sales_id,sales_ref FROM public.salespeople WHERE active AND upper(code)=sales_code ORDER BY sort_order,id LIMIT 1;
 before_row:=to_jsonb(v);UPDATE public.vehicles SET stock_number=coalesce(b.normalized_data->>'batch',stock_number),vin=coalesce(effective_vin,vin),toyota_order_number=coalesce(nullif(btrim(b.normalized_data->>'order'),''),toyota_order_number),job_card_number=coalesce(job_card_number,nullif(btrim(b.normalized_data->>'jobCardNumber'),'')),customer_name=coalesce(customer,customer_name),vehicle_description=coalesce(description,vehicle_description),model=coalesce(description,model),registration=coalesce(nullif(upper(btrim(b.normalized_data->>'registration')),''),registration),salesperson_id=CASE WHEN salesperson_manual_override THEN salesperson_id ELSE coalesce(sales_id,salesperson_id) END,salesperson_reference=CASE WHEN salesperson_manual_override THEN salesperson_reference ELSE coalesce(sales_ref,nullif(sales_raw,''),salesperson_reference) END,source_system='microsoft_navision',source_batch_id=b.dealer_code,source_record_id=b.id::text,source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','navision-linked-refresh-481','navision_record_id',b.id,'navision_version',b.version,'navision_updated_at',b.updated_at,'navision_status',b.normalized_data->>'toyotaStatus','navision_colour',colour,'colour',colour,'navision_salesperson',sales_raw,'navision_model',description,'navision_customer',customer,'navision_source_data',b.normalized_data-'navisionRawEvidence'),version=version+1,updated_by=p_actor_id,updated_at=clock_timestamp() WHERE id=v.id AND (stock_number,vin,toyota_order_number,job_card_number,customer_name,vehicle_description,model,registration,salesperson_id,salesperson_reference,source_system,source_batch_id,source_record_id,source_payload) IS DISTINCT FROM (coalesce(b.normalized_data->>'batch',stock_number),coalesce(effective_vin,vin),coalesce(nullif(btrim(b.normalized_data->>'order'),''),toyota_order_number),coalesce(job_card_number,nullif(btrim(b.normalized_data->>'jobCardNumber'),'')),coalesce(customer,customer_name),coalesce(description,vehicle_description),coalesce(description,model),coalesce(nullif(upper(btrim(b.normalized_data->>'registration')),''),registration),CASE WHEN salesperson_manual_override THEN salesperson_id ELSE coalesce(sales_id,salesperson_id) END,CASE WHEN salesperson_manual_override THEN salesperson_reference ELSE coalesce(sales_ref,nullif(sales_raw,''),salesperson_reference) END,'microsoft_navision',b.dealer_code,b.id::text,coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','navision-linked-refresh-481','navision_record_id',b.id,'navision_version',b.version,'navision_updated_at',b.updated_at,'navision_status',b.normalized_data->>'toyotaStatus','navision_colour',colour,'colour',colour,'navision_salesperson',sales_raw,'navision_model',description,'navision_customer',customer,'navision_source_data',b.normalized_data-'navisionRawEvidence')) RETURNING * INTO v;
 changed:=FOUND;IF changed THEN after_row:=to_jsonb(v);INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('update','vehicles',v.id,v.id,p_actor_id,p_actor_email,before_row,after_row,jsonb_build_object('source','navision-linked-refresh-481','backend_record_id',b.id,'backend_version',b.version,'stock_number',stock,'manual_salesperson_override_preserved',v.salesperson_manual_override,'lifecycle_mutated',false,'job_card_overwritten',false));UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;END IF;
 RETURN public.navision_backend_response(true,CASE WHEN changed THEN 'linked_vehicle_refreshed' ELSE 'linked_vehicle_current' END,jsonb_build_object('vehicle_id',b.canonical_vehicle_id,'backend_record_id',b.id,'backend_version',b.version,'changed',changed,'manual_salesperson_override_preserved',v.salesperson_manual_override));END $function$;


CREATE OR REPLACE FUNCTION public.pdc_sync_linked_navision_details_20260911()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $body$
DECLARE result jsonb; matches integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
  IF NEW.source_system <> 'microsoft_navision' OR NOT NEW.is_current OR NEW.record_status <> 'current' OR NEW.canonical_vehicle_id IS NULL THEN RETURN NEW; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id=NEW.canonical_vehicle_id AND v.deleted_at IS NULL) THEN RETURN NEW; END IF;
  SELECT count(*) INTO matches FROM public.navision_backend_records b
   WHERE b.source_system='microsoft_navision' AND b.is_current AND b.record_status='current'
    AND public.normalize_vehicle_stock_number(b.normalized_data->>'batch')=public.normalize_vehicle_stock_number(NEW.normalized_data->>'batch');
  IF matches<>1 THEN RAISE EXCEPTION 'ambiguous_navision_stock'; END IF;
  -- Reuse the private, metadata-only refresh. Existing location/lifecycle routes remain in force.
  result:=public.pdc_refresh_linked_vehicle_from_navision_481_pre_20260905(NEW.id,auth.uid(),auth.jwt()->>'email');
  IF NOT coalesce((result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'navision_details_sync_failed: %',result->>'code'; END IF;
  RETURN NEW;
END $body$;
REVOKE ALL ON FUNCTION public.pdc_sync_linked_navision_details_20260911() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER zzz_pdc_navision_details_continuity
AFTER INSERT OR UPDATE OF normalized_data,is_current,record_status,canonical_vehicle_id
ON public.navision_backend_records FOR EACH ROW
EXECUTE FUNCTION public.pdc_sync_linked_navision_details_20260911();


DO $check$
DECLARE b record; result jsonb; before_count integer; after_version bigint; initial_version bigint; before_state jsonb; after_state jsonb; changed_count integer:=0;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
 FOR b IN SELECT n.id,n.canonical_vehicle_id FROM public.navision_backend_records n JOIN public.vehicles v ON v.id=n.canonical_vehicle_id
 WHERE n.source_system='microsoft_navision' AND n.is_current AND n.record_status='current' AND v.deleted_at IS NULL ORDER BY n.id LOOP
  IF (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision' AND x.is_current AND x.record_status='current' AND public.normalize_vehicle_stock_number(x.normalized_data->>'batch')=(SELECT stock_number_normalized FROM public.vehicles WHERE id=b.canonical_vehicle_id))<>1 THEN RAISE EXCEPTION 'ambiguous_current_stock'; END IF;
  SELECT to_jsonb(v),version INTO before_state,initial_version FROM public.vehicles v WHERE v.id=b.canonical_vehicle_id FOR UPDATE;
  result:=public.pdc_refresh_linked_vehicle_from_navision_481_pre_20260905(b.id,auth.uid(),auth.jwt()->>'email');
  IF NOT coalesce((result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'metadata_refresh_failed %',result; END IF;
  SELECT to_jsonb(v),version INTO after_state,after_version FROM public.vehicles v WHERE v.id=b.canonical_vehicle_id;
  IF (before_state - ARRAY['vin','vin_normalized','model','toyota_order_number','customer_name','vehicle_description','registration','salesperson_id','salesperson_reference','source_system','source_system_normalized','source_batch_id','source_record_id','source_record_id_normalized','source_payload','version','updated_by','updated_at']) IS DISTINCT FROM (after_state - ARRAY['vin','vin_normalized','model','toyota_order_number','customer_name','vehicle_description','registration','salesperson_id','salesperson_reference','source_system','source_system_normalized','source_batch_id','source_record_id','source_record_id_normalized','source_payload','version','updated_by','updated_at']) THEN RAISE EXCEPTION 'operational_state_changed %',b.canonical_vehicle_id; END IF;
  IF after_version>initial_version THEN changed_count:=changed_count+1; END IF;
  PERFORM public.pdc_refresh_linked_vehicle_from_navision_481_pre_20260905(b.id,auth.uid(),auth.jwt()->>'email');
  IF (SELECT version FROM public.vehicles WHERE id=b.canonical_vehicle_id)<>after_version THEN RAISE EXCEPTION 'replay_changed_vehicle %',b.canonical_vehicle_id; END IF;
 END LOOP;
END $check$;
