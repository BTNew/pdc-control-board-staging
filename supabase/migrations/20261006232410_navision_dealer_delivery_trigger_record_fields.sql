-- Trigger rows have different fields. Use separate branches so PostgreSQL
-- resolves only the field belonging to the current trigger's table.
CREATE OR REPLACE FUNCTION public.trigger_reconcile_navision_operational_record() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public' AS $$
DECLARE v_backend_record_id uuid; result jsonb; b public.navision_backend_records%rowtype;
BEGIN
 IF pg_trigger_depth()>1 THEN RETURN NEW; END IF;
 IF TG_TABLE_NAME='navision_board_activations' THEN
  v_backend_record_id:=NEW.backend_record_id;
 ELSE
  v_backend_record_id:=NEW.id;
 END IF;
 result:=public.reconcile_navision_operational_record(v_backend_record_id,auth.uid(),public.current_actor_email());
 SELECT * INTO b FROM public.navision_backend_records WHERE id=v_backend_record_id;
 IF b.canonical_vehicle_id IS NOT NULL AND b.is_current AND b.record_status='current'
 AND lower(regexp_replace(btrim(coalesce(b.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer'
 AND result->>'ok' IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'navision_dealer_delivery_failed: %',result->>'code';
 END IF;
 RETURN NEW;
END $$;
