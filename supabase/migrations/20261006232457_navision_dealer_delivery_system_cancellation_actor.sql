DO $repair$
DECLARE definition text;
BEGIN
 SELECT pg_get_functiondef('public.reconcile_navision_delivery_734(uuid,uuid,text)'::regprocedure) INTO definition;
 IF position('updated_by=p_actor_id'||chr(10)||'   WHERE id=booking.id' IN definition)=0 THEN
  RAISE EXCEPTION 'unexpected_delivery_function';
 END IF;
 EXECUTE replace(definition,'updated_by=p_actor_id'||chr(10)||'   WHERE id=booking.id',
  'updated_by=coalesce(p_actor_id,booking.updated_by)'||chr(10)||'   WHERE id=booking.id');
 SELECT pg_get_functiondef('pdc_navision_delivery_private.allowed_booking_cancel(jsonb,jsonb)'::regprocedure) INTO definition;
 EXECUTE replace(definition,'IS NOT DISTINCT FROM c.actor_id',
  'IS NOT DISTINCT FROM coalesce(c.actor_id,(p_old->>''updated_by'')::uuid)');
END $repair$;
