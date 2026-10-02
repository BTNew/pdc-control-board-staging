-- Repair the new private CRM observer's local variable; no PDC function or data changes.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING environment required'; END IF;
END $$;
CREATE OR REPLACE FUNCTION pdc_sales_private.crm_observe(p_items jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); item jsonb; v_facts jsonb; prior pdc_sales_private.crm_observations; group_key text; old_group jsonb; new_group jsonb; event_key text; title text; inserted integer;
BEGIN
 -- This internal function only observes server-authorised snapshots, never client data.
 FOR item IN SELECT value FROM jsonb_array_elements(p_items) ORDER BY value->>'tracking_id' LOOP
  v_facts:=jsonb_build_object('stock',coalesce(item->>'stock',''),
   'eta',jsonb_build_object('kewdale_eta',item->>'kewdale_eta','dealer_eta',item->>'dealer_eta','port_plant_eta',item->>'port_plant_eta'),
   'location',jsonb_build_object('toyota_status',item->>'toyota_status','location_status',item->>'location_status','pmb_location',item->>'pmb_location','pmb_stage',item->>'pmb_stage','workshop_status',item->>'workshop_status','pmb_arrival_date',item->>'pmb_arrival_date','dealer_delivered_date',item->>'dealer_delivered_date'),
   'workshop',coalesce(item->'bay_bookings','[]'::jsonb),
   'parts',CASE WHEN jsonb_typeof(item->'parts')='object' THEN (item->'parts')-ARRAY['snapshot_at','confirmed_at','updated_at','jobs'] ELSE 'null'::jsonb END);
  INSERT INTO pdc_sales_private.crm_observations(tracking_id,facts) VALUES((item->>'tracking_id')::uuid,v_facts) ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS inserted=ROW_COUNT;
  SELECT * INTO prior FROM pdc_sales_private.crm_observations WHERE tracking_id=(item->>'tracking_id')::uuid FOR UPDATE;
  IF inserted=1 THEN
   INSERT INTO pdc_sales_private.crm_timeline(tracking_id,event_type,title,details,is_alert,observed_by)
   VALUES(prior.tracking_id,'tracking_started','Tracking started',jsonb_build_object('observed',v_facts),false,auth.uid());
   CONTINUE;
  END IF;
  FOREACH group_key IN ARRAY ARRAY['stock','eta','location','workshop','parts'] LOOP
   old_group:=prior.facts->group_key; new_group:=v_facts->group_key;
   IF old_group IS NOT DISTINCT FROM new_group THEN CONTINUE; END IF;
   IF group_key='stock' THEN
    event_key:=CASE WHEN coalesce(prior.facts->>'stock','')='' AND coalesce(v_facts->>'stock','')<>'' THEN 'stock_allocated' ELSE 'stock_changed' END;
    title:=CASE WHEN event_key='stock_allocated' THEN 'Stock number allocated' ELSE 'Stock number changed' END;
   ELSE
    event_key:=CASE group_key WHEN 'eta' THEN 'eta_changed' WHEN 'location' THEN 'location_changed' WHEN 'workshop' THEN 'workshop_changed' ELSE 'parts_changed' END;
    title:=CASE group_key WHEN 'eta' THEN 'ETA changed' WHEN 'location' THEN 'Vehicle location or status changed' WHEN 'workshop' THEN 'Workshop booking or progress changed' ELSE 'Parts status changed' END;
   END IF;
   INSERT INTO pdc_sales_private.crm_timeline(tracking_id,event_type,title,details,observed_by)
   VALUES(prior.tracking_id,event_key,title,jsonb_build_object('before',old_group,'after',new_group),auth.uid());
  END LOOP;
  IF prior.facts IS DISTINCT FROM v_facts THEN UPDATE pdc_sales_private.crm_observations SET facts=v_facts,last_observed_at=clock_timestamp() WHERE tracking_id=prior.tracking_id; END IF;
 END LOOP;
END $fn$;
REVOKE ALL ON FUNCTION pdc_sales_private.crm_observe(jsonb) FROM PUBLIC,anon,authenticated,service_role;
