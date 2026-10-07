-- Attribute unattended delivery reconciliation to the authenticated uploader
-- recorded in the exact current source batch; never infer a user from a bay.
DO $repair$
DECLARE definition text;
BEGIN
 SELECT pg_get_functiondef('public.reconcile_navision_delivery_734(uuid,uuid,text)'::regprocedure) INTO definition;
 IF position('before_state:=public.pdc_rft_transport_snapshot_734(v.id)' IN definition)=0 THEN
  RAISE EXCEPTION 'unexpected_delivery_function';
 END IF;
 EXECUTE replace(definition,'before_state:=public.pdc_rft_transport_snapshot_734(v.id)',
  E'p_actor_id:=coalesce(p_actor_id,auth.uid(),(SELECT actor_id FROM public.navision_import_batches WHERE id=b.last_seen_batch_id));\n'
  ||E' actor_email:=coalesce(nullif(lower(btrim(p_actor_email)),\'\'),nullif(public.current_actor_email(),\'\'),(SELECT actor_email FROM public.navision_import_batches WHERE id=b.last_seen_batch_id),\'system@staging.invalid\');\n'
  ||E' IF p_actor_id IS NULL AND EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v.id AND deleted_at IS NULL AND status IN(\'queued\',\'planned\',\'started\',\'stoppage\')) THEN RETURN public.navision_backend_response(false,\'delivery_actor_missing\'); END IF;\n'
  ||' before_state:=public.pdc_rft_transport_snapshot_734(v.id)');
END $repair$;
