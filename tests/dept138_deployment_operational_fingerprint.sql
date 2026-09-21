-- Read-only operational fingerprint for before/after staging deployment.
-- Compare inside the deployment transaction while holding the top-level advisory lock.
-- The new nullable calendar marker is omitted so adding the column alone is neutral.
SELECT jsonb_build_object(
 'vehicles_count',(SELECT count(*) FROM public.vehicles),
 'vehicles_md5',(SELECT md5(coalesce(string_agg(to_jsonb(v)::text,E'\n' ORDER BY v.id),'')) FROM public.vehicles v),
 'bookings_count',(SELECT count(*) FROM public.workshop_bookings),
 'bookings_md5',(SELECT md5(coalesce(string_agg((to_jsonb(b)-'bus_calendar_version')::text,E'\n' ORDER BY b.id),'')) FROM public.workshop_bookings b),
 'operations_count',(SELECT count(*) FROM public.pdc_pilbara_service_operations),
 'operations_md5',(SELECT md5(coalesce(string_agg(to_jsonb(o)::text,E'\n' ORDER BY o.operation_id),'')) FROM public.pdc_pilbara_service_operations o),
 'staff_adjustments_md5',(SELECT md5(coalesce(string_agg(to_jsonb(a)::text,E'\n' ORDER BY a.adjustment_id),'')) FROM public.vehicle_workshop_line_adjustments a),
 'fitter_progress_md5',(SELECT md5(coalesce(string_agg(to_jsonb(p)::text,E'\n' ORDER BY p.booking_id,p.line_identity),'')) FROM pdc_fitter_private.operation_progress p),
 'parts_jobs_md5',(SELECT md5(coalesce(string_agg(to_jsonb(j)::text,E'\n' ORDER BY to_jsonb(j)::text),'')) FROM pdc_parts_private.jobs j)
) AS operational_fingerprint;

