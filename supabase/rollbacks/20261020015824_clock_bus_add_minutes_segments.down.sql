-- Restore the minute-by-minute Bus add_minutes (md5 2222e170...).
CREATE OR REPLACE FUNCTION pdc_bus_private.add_minutes(p_start timestamp with time zone, p_minutes integer, p_bay_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE cursor_at timestamptz:=date_trunc('minute',p_start); remaining integer:=p_minutes; max_at timestamptz:=p_start+interval '366 days';
BEGIN
 IF p_start IS NULL OR p_minutes IS NULL OR p_minutes<0 OR p_minutes>59999 THEN RAISE EXCEPTION 'Invalid duration' USING errcode='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id AND s.code='BUS_4X4')
 THEN RETURN public.workshop_add_operational_minutes(p_start,p_minutes); END IF;
 WHILE remaining>0 AND cursor_at<max_at LOOP
  IF pdc_bus_private.minute_available(cursor_at,p_bay_id) THEN remaining:=remaining-1; END IF;
  cursor_at:=cursor_at+interval '1 minute';
 END LOOP;
 IF remaining>0 THEN RAISE EXCEPTION 'Bus shift duration exceeded calendar guard'; END IF;
 RETURN cursor_at;
END $function$;
DO $p$ BEGIN IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.add_minutes(timestamptz,integer,uuid)'::regprocedure) IS DISTINCT FROM '2222e170c317f1a8361dcd4058d14c89' THEN RAISE EXCEPTION 'add_minutes_not_restored'; END IF; END $p$;
