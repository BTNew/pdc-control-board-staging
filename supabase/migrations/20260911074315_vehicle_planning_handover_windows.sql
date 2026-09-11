CREATE FUNCTION public.get_pdc_vehicle_planning_windows(p_vehicle_id uuid DEFAULT NULL,p_changed_since timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $function$
DECLARE windows jsonb; warnings jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
 PERFORM public.workshop_require_planner_operator();
 SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',b.id,'start_at',b.scheduled_start_at,
  'end_at',CASE WHEN b.status::text IN('started','stoppage') THEN greatest(b.scheduled_end_at,now()) ELSE b.scheduled_end_at END)
  ORDER BY b.scheduled_start_at),'[]') INTO windows
 FROM public.workshop_bookings b WHERE p_vehicle_id IS NOT NULL AND b.vehicle_id=p_vehicle_id
  AND b.deleted_at IS NULL AND b.status::text NOT IN('completed','cancelled','deleted');
 SELECT coalesce(jsonb_agg(q.body),'[]') INTO warnings FROM (
  SELECT jsonb_build_object('stock',v.stock_number,'first_stage',sa.code,'first_bay',ba.bay_number,
   'next_stage',sb.code,'next_bay',bb.bay_number,'end_at',a.scheduled_end_at,'next_start',b.scheduled_start_at,
   'overlap',a.scheduled_end_at>b.scheduled_start_at) body
  FROM public.workshop_bookings a JOIN public.workshop_bookings b ON b.vehicle_id=a.vehicle_id AND (b.scheduled_start_at,b.id)>(a.scheduled_start_at,a.id)
  JOIN public.vehicles v ON v.id=a.vehicle_id JOIN public.workshop_stages sa ON sa.id=a.stage_id JOIN public.workshop_stages sb ON sb.id=b.stage_id
  JOIN public.workshop_bays ba ON ba.id=a.bay_id JOIN public.workshop_bays bb ON bb.id=b.bay_id
  WHERE p_vehicle_id IS NULL AND p_changed_since IS NOT NULL AND (a.updated_at>=p_changed_since OR b.updated_at>=p_changed_since)
   AND a.deleted_at IS NULL AND b.deleted_at IS NULL AND v.deleted_at IS NULL
   AND a.status::text NOT IN('completed','cancelled','deleted') AND b.status::text NOT IN('completed','cancelled','deleted')
   AND a.bay_id<>b.bay_id AND b.scheduled_end_at>=now()
   AND a.scheduled_end_at+interval '5 hours'>b.scheduled_start_at
  ORDER BY b.scheduled_start_at LIMIT 100
 ) q;
 RETURN jsonb_build_object('ok',true,'windows',windows,'warnings',warnings,'buffer_minutes',300);
END $function$;
REVOKE ALL ON FUNCTION public.get_pdc_vehicle_planning_windows(uuid,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_planning_windows(uuid,timestamptz) TO authenticated;
