-- Preserve ordering when a repair/return is performed in one transaction.
DO $repair$
DECLARE d text; p text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'STAGING required'; END IF;
 SELECT pg_get_functiondef('public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure) INTO d;
 IF md5(d)<>'354d2d210c9d0af2d8494e240f5bc687' THEN RAISE EXCEPTION 'QC entry changed since review'; END IF;
 p:=replace(d,'    reason,moved_by','    reason,moved_by,moved_at');
 p:=replace(p,'''All required work complete - moved to QC Gate'',auth.uid()',
  '''All required work complete - moved to QC Gate'',auth.uid(),clock_timestamp()');
 IF p=d OR position('reason,moved_by,moved_at' IN p)=0 THEN RAISE EXCEPTION 'QC movement clock patch failed'; END IF;
 EXECUTE p;
END $repair$;
