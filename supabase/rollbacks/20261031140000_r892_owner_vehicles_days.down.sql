-- Undo r892 (F442): put back the r891 owner snapshot body (operation-line counts).
SET LOCAL lock_timeout = '4s';

CREATE OR REPLACE FUNCTION public.get_pdc_owner_snapshot_891()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
 v_out jsonb;
BEGIN
 IF NOT public.is_pdc_owner_viewer_891() THEN
  RAISE EXCEPTION 'This page is for owner logins only' USING errcode = '42501';
 END IF;

 WITH v AS (
   SELECT * FROM public.vehicles
   WHERE deleted_at IS NULL AND board_purged_at IS NULL AND visible_on_board
 ), pmb AS (
   SELECT v.id, v.key_number,
     coalesce(nullif(v.model, ''), nullif(v.vehicle_description, ''), 'No model') AS model,
     k.assigned_at,
     extract(epoch FROM now() - k.assigned_at) / 86400 AS days
   FROM v LEFT JOIN public.pdc_vehicle_key_assigned_562 k ON k.vehicle_id = v.id
   WHERE coalesce(v.key_number, '') <> '' AND upper(v.key_number) <> 'WPC'
 ), act AS (
   SELECT DISTINCT vehicle_id FROM public.workshop_bookings
   WHERE deleted_at IS NULL AND status IN ('planned', 'started', 'stoppage') AND bay_id IS NOT NULL
 ), parts AS (
   SELECT DISTINCT vehicle_id FROM public.pdc_parts_stoppage_564 WHERE active
 ), bays AS (
   SELECT coalesce(CASE split_part(b.code, '-', 1)
       WHEN 'FITTING' THEN 'Fitting' WHEN 'HOIST' THEN 'Hoist' WHEN 'ELECTRICAL' THEN 'Electrical'
       WHEN 'FABRICATION' THEN 'Fab' WHEN 'TYRE' THEN 'Tyre' WHEN 'TINT' THEN 'Tint' WHEN 'BUS_4X4' THEN 'Bus4x4' END, 'Other') AS station,
     b.code, b.display_name AS bay,
     count(wb.id) FILTER (WHERE wb.status IN ('planned', 'started', 'stoppage'))::int AS booked,
     count(wb.id) FILTER (WHERE wb.status = 'started')::int AS running,
     count(wb.id) FILTER (WHERE wb.status = 'stoppage')::int AS stopped
   FROM public.workshop_bays b
   LEFT JOIN public.workshop_bookings wb ON wb.bay_id = b.id AND wb.deleted_at IS NULL
   WHERE b.is_active AND NOT b.is_sublet_row
   GROUP BY 1, 2, 3
 )
 SELECT jsonb_build_object(
   'as_of', now(),
   'headline', jsonb_build_object(
     'pmb_total', (SELECT count(*) FROM pmb),
     'avg_days', (SELECT round(avg(days)::numeric, 1) FROM pmb),
     'median_days', (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY days))::numeric, 1) FROM pmb),
     'new_24h', (SELECT count(*) FROM pmb WHERE assigned_at > now() - interval '24 hours'),
     'over_30', (SELECT count(*) FROM pmb WHERE days >= 30),
     'not_scheduled', (SELECT count(*) FROM pmb WHERE id NOT IN (SELECT vehicle_id FROM act)),
     'not_scheduled_30', (SELECT count(*) FROM pmb WHERE id NOT IN (SELECT vehicle_id FROM act) AND days >= 30),
     'parts_at_pmb', (SELECT count(*) FROM parts p JOIN pmb ON pmb.id = p.vehicle_id),
     'parts_all', (SELECT count(*) FROM parts),
     'parts_booked', (SELECT count(*) FROM parts p JOIN pmb ON pmb.id = p.vehicle_id WHERE p.vehicle_id IN (SELECT vehicle_id FROM act)),
     'parts_not_booked', (SELECT count(*) FROM parts p JOIN pmb ON pmb.id = p.vehicle_id WHERE p.vehicle_id NOT IN (SELECT vehicle_id FROM act)),
     'running', (SELECT count(*) FROM public.workshop_bookings WHERE deleted_at IS NULL AND status = 'started'),
     'stopped', (SELECT count(*) FROM public.workshop_bookings WHERE deleted_at IS NULL AND status = 'stoppage'),
     'booked_jobs', (SELECT count(*) FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN ('planned', 'started', 'stoppage') AND bay_id IS NOT NULL),
     'done_today', (SELECT count(*) FROM public.workshop_bookings WHERE deleted_at IS NULL AND status = 'completed'
        AND actual_end_at >= (date_trunc('day', now() AT TIME ZONE 'Australia/Perth') AT TIME ZONE 'Australia/Perth')),
     'done_7d', (SELECT count(*) FROM public.workshop_bookings WHERE deleted_at IS NULL AND status = 'completed' AND actual_end_at > now() - interval '7 days'),
     'final_check', (SELECT count(*) FROM v WHERE current_location = 'QC'),
     'wpc', (SELECT count(*) FROM v WHERE upper(coalesce(key_number, '')) = 'WPC'),
     'rft', (SELECT count(*) FROM v WHERE current_location = 'RFT'),
     'in_transit', (SELECT count(*) FROM v WHERE current_location = 'IT'),
     'yard_hold', (SELECT count(*) FROM v WHERE current_location = 'YH')
   ),
   'stations', (SELECT coalesce(jsonb_agg(s ORDER BY array_position(ARRAY['Fitting','Hoist','Electrical','Tyre','Tint','Fab','Bus4x4','Other'], s.station)), '[]'::jsonb)
     FROM (SELECT station, sum(booked)::int AS booked, sum(running)::int AS running, sum(stopped)::int AS stopped,
             count(*)::int AS bays, (count(*) FILTER (WHERE booked > 0))::int AS bays_with_work
           FROM bays GROUP BY station) s),
   'bays', (SELECT coalesce(jsonb_agg(jsonb_build_object('station', station, 'bay', bay, 'booked', booked, 'running', running, 'stopped', stopped)
             ORDER BY station, booked DESC, code), '[]'::jsonb) FROM bays),
   'age', (SELECT jsonb_agg(jsonb_build_object('bucket', g.bucket, 'cars',
             (SELECT count(*) FROM pmb WHERE pmb.days >= g.lo AND pmb.days < g.hi)) ORDER BY g.ord)
           FROM (VALUES ('Under 7 days', 1, 0, 7), ('7 to 14 days', 2, 7, 14), ('14 to 30 days', 3, 14, 30),
                        ('30 to 60 days', 4, 30, 60), ('60 days +', 5, 60, 100000)) AS g(bucket, ord, lo, hi)),
   'oldest', (SELECT coalesce(jsonb_agg(o ORDER BY o.days DESC), '[]'::jsonb) FROM (
       SELECT pmb.key_number, pmb.model, floor(pmb.days)::int AS days,
         pmb.id IN (SELECT vehicle_id FROM act) AS booked,
         pmb.id IN (SELECT vehicle_id FROM parts) AS waiting_parts
       FROM pmb WHERE pmb.assigned_at IS NOT NULL ORDER BY pmb.assigned_at LIMIT 10) o)
 ) INTO v_out;
 RETURN v_out;
END
$function$;
REVOKE ALL ON FUNCTION public.get_pdc_owner_snapshot_891() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_owner_snapshot_891() TO authenticated;
