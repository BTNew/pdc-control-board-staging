-- Read-only projection of PMB facts for orders already authorised by the sales snapshot.
CREATE OR REPLACE FUNCTION pdc_sales_private.snapshot_with_pmb()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE base jsonb; result jsonb;
BEGIN
 base:=pdc_sales_private.snapshot_with_ordering();
 SELECT coalesce(jsonb_agg(e.item||CASE WHEN v.id IS NULL THEN
 jsonb_build_object('parts',NULL,'bay_bookings','[]'::jsonb,'active_workshop_booking_id',NULL)
 ELSE jsonb_build_object(
 'active_workshop_booking_id',v.active_workshop_booking_id,
 'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
 'pmb_stoppage_reason',v.pmb_stoppage_reason,'pmb_stoppage_started_at',v.pmb_stoppage_started_at,'pmb_stoppage_cleared_at',v.pmb_stoppage_cleared_at,
 'rft_confirmed_at',v.rft_confirmed_at,
 'parts',jsonb_build_object(
  'status',pf.data->>'label','complete',pf.data->'parts_complete',
  'snapshot_at',pf.data->>'parts_snapshot_at','confirmed_at',pf.data->>'confirmed_at',
  'updated_at',pu.updated_at,'required',pu.parts_required,'ordered',pu.parts_ordered,
  'received',pu.parts_received,'stoppage',pu.parts_stoppage,'stoppage_reason',pu.parts_stoppage_reason,'eta',pu.worst_eta,
  'jobs',(SELECT coalesce(jsonb_agg(jsonb_build_object('job_number',j->>'job_number','status',j->>'label',
   'backorder',j->'backorder','po_recorded',j->'backorder_with_po','snapshot_at',j->>'parts_snapshot_at')),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(pf.data->'jobs','[]'::jsonb)) j)),
 'bay_bookings',(SELECT coalesce(jsonb_agg(jsonb_build_object(
 'booking_id',b.id,'stage',s.display_name,'stage_code',s.code,'bay',bay.display_name,
 'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
 'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
 'stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
 'progress',pdc_fitter_private.progress(b.id))
 ORDER BY b.scheduled_start_at NULLS LAST,b.id),'[]'::jsonb)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id AND bay.stage_id=b.stage_id
 WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND b.status<>'deleted'
 AND NOT coalesce(b.legacy_ambiguity_quarantined,false))
 ) END ORDER BY e.ord),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(base->'items') WITH ORDINALITY e(item,ord)
 LEFT JOIN public.vehicles v ON v.id=(e.item->>'canonical_vehicle_id')::uuid AND v.deleted_at IS NULL
 LEFT JOIN LATERAL (SELECT u.* FROM public.vehicle_parts_updates u WHERE u.vehicle_id=v.id
 ORDER BY u.updated_at DESC,u.id DESC LIMIT 1) pu ON true
 LEFT JOIN LATERAL (SELECT public.pdc_parts_flags_vehicle_20260911(v.id) data WHERE v.id IS NOT NULL) pf ON true;
 RETURN base||jsonb_build_object('items',result);
END $fn$;
REVOKE ALL ON FUNCTION pdc_sales_private.snapshot_with_pmb() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION pdc_sales_private.snapshot_with_pmb() TO authenticated;
CREATE OR REPLACE FUNCTION public.get_broome_sales_snapshot()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=pg_catalog,pdc_sales_private AS $fn$
 SELECT pdc_sales_private.snapshot_with_pmb()
$fn$;
REVOKE ALL ON FUNCTION public.get_broome_sales_snapshot() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_broome_sales_snapshot() TO authenticated;
