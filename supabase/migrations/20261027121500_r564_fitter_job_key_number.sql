-- r564 (F178). Craig approved go-live 27 Oct 2026 08:40 AWST: "Go live #548".
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- r561 / F175 is the slim planner header and took no sort.
-- r562 / F176 / sort 335 is the key gate. r563 / F177 / sort 336 is the arrival age.
-- This replaces get_fitter_jobs only. get_fitter_refresh calls it, so the key comes through.
-- No regression_checks row, so sort 337 stays free. The function is not pinned. Pins stay 241.
-- Department 135 is not edited.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r564: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r564: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r564: pin count is not 241'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.get_fitter_jobs(p_technician_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT EXISTS(SELECT 1 FROM public.workshop_technicians WHERE id=p_technician_id AND active)
 THEN RETURN jsonb_build_object('ok',false,'error','mechanic_unavailable'); END IF;
 RETURN jsonb_build_object('ok',true,'generated_at',statement_timestamp(),'server_now',statement_timestamp(),'technician_id',p_technician_id,
 'bays',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.display_name,
   'number',b.bay_number,'stage',s.display_name,'active',b.is_active) ORDER BY s.sort_order,b.bay_number),'[]'::jsonb)
   FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.default_technician_id=p_technician_id AND s.active AND s.is_physical AND NOT b.is_sublet_row),
 'jobs',(SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',b.id,'version',b.version,'status',b.status,'stage_code',s.code,'stage_name',s.display_name,
    'bay_id',bay.id,'bay_number',bay.bay_number,'bay_name',bay.display_name,'bay_active',bay.is_active,
    'start_at',b.scheduled_start_at,'end_at',b.scheduled_end_at,
    'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
    'stoppage_started_at',b.stoppage_started_at,'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,
    'stoppage_reason',b.stoppage_reason,'vehicle_id',v.id,'stock',v.stock_number,
    'key_number',v.key_number,
    'job_card',v.job_card_number,'customer',v.customer_name,'vehicle',v.vehicle_description,
    'progress',pdc_fitter_private.progress(b.id)
  )||pdc_bus_private.team_payload(b.id) ORDER BY CASE b.status WHEN 'started' THEN 0 WHEN 'stoppage' THEN 1 ELSE 2 END,
   b.scheduled_start_at NULLS LAST,b.id),'[]'::jsonb)
  FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  JOIN public.workshop_bays bay ON bay.id=b.bay_id
  JOIN public.vehicles v ON v.id=b.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
  WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND s.is_physical AND NOT s.is_sublet AND pdc_fitter_private.assigned(b.id,p_technician_id)));
END $function$;

NOTIFY pgrst,'reload schema';

DO $post$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r564: pin count changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='get_fitter_jobs')
    IS DISTINCT FROM '680a53cfaa856a5b241609302ee8a40e' THEN RAISE EXCEPTION 'r564: get_fitter_jobs body is not the expected read'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='get_fitter_refresh' AND strpos(p.prosrc,'get_fitter_jobs')>0) THEN RAISE EXCEPTION 'r564: refresh no longer calls get_fitter_jobs'; END IF;
END $post$;
