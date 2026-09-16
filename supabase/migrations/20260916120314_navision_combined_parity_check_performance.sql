-- A changed Navision row can affect only its old/new stock matches and old/new
-- canonical vehicles. A changed vehicle can affect only that vehicle's parity.
-- Retain deferred enforcement and the original complete parity predicate.
CREATE INDEX IF NOT EXISTS navision_parity_exact_stock_current_idx
ON public.navision_backend_records ((nullif(upper(regexp_replace(coalesce(normalized_data->>'batch',normalized_data->>'stock',''),'[^A-Z0-9]','','g')),'')))
WHERE is_current AND record_status='current';

CREATE OR REPLACE FUNCTION public.pdc_enforce_navision_vehicle_parity_494()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public' AS $fn$
DECLARE v_check jsonb; ids uuid[]; vehicle_id uuid; old_stock text; new_stock text; old_link uuid; new_link uuid;
BEGIN
 IF TG_TABLE_SCHEMA<>'public' OR TG_TABLE_NAME NOT IN('vehicles','navision_backend_records') THEN
  RAISE EXCEPTION 'Unexpected Navision parity trigger target' USING errcode='55000';
 END IF;
 IF TG_TABLE_NAME='vehicles' THEN
  ids:=ARRAY[NEW.id];
 ELSE
  IF TG_OP<>'INSERT' THEN
   old_stock:=nullif(upper(regexp_replace(coalesce(OLD.normalized_data->>'batch',OLD.normalized_data->>'stock',''),'[^A-Z0-9]','','g')),'');
   old_link:=OLD.canonical_vehicle_id;
  END IF;
  IF TG_OP<>'DELETE' THEN
   new_stock:=nullif(upper(regexp_replace(coalesce(NEW.normalized_data->>'batch',NEW.normalized_data->>'stock',''),'[^A-Z0-9]','','g')),'');
   new_link:=NEW.canonical_vehicle_id;
  END IF;
  SELECT coalesce(array_agg(v.id ORDER BY v.id),'{}'::uuid[]) INTO ids
  FROM public.vehicles v WHERE v.deleted_at IS NULL
   AND (v.stock_number_normalized=ANY(ARRAY[old_stock,new_stock]) OR v.id=ANY(ARRAY[old_link,new_link]));
 END IF;
 FOREACH vehicle_id IN ARRAY ids LOOP
  v_check:=public.pdc_navision_vehicle_parity_494(vehicle_id);
  IF coalesce((v_check->>'ok')::boolean,false) IS NOT TRUE THEN
   RAISE EXCEPTION 'PDC_NAVISION_VEHICLE_LINK_OR_REFRESH_INCOMPLETE: %',v_check USING errcode='23514';
  END IF;
 END LOOP;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION public.pdc_enforce_navision_vehicle_parity_494() FROM PUBLIC,anon,authenticated,service_role;
DO $verify$
BEGIN
 IF public.pdc_navision_vehicle_parity_494(NULL)->>'ok' IS DISTINCT FROM 'true'
 OR (SELECT count(*) FROM pg_trigger WHERE tgname IN('zz_navision_all_vehicle_parity_494','zz_vehicle_navision_parity_494') AND tgenabled='O' AND tgdeferrable AND tginitdeferred)<>2
 THEN RAISE EXCEPTION 'Navision parity baseline or deferred guards invalid'; END IF;
END $verify$;
