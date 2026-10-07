DO $repair$
DECLARE definition text;
BEGIN
 SELECT pg_get_functiondef('public.reconcile_navision_delivery_734(uuid,uuid,text)'::regprocedure) INTO definition;
 EXECUTE replace(definition,'SELECT actor_email FROM public.navision_import_batches WHERE id=b.last_seen_batch_id',
  'SELECT imported.actor_email FROM public.navision_import_batches imported WHERE imported.id=b.last_seen_batch_id');
END $repair$;
