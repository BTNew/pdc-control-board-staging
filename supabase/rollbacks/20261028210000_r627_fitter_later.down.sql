-- Undo r627 (F242): remove fitter Later. Staging cdsmnqxtyyoeoznmbidd only. Later marks are dropped; items were never ticked.
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'fitter_later_627' AND added_in = 'r627';
CREATE OR REPLACE FUNCTION public.get_fitter_job(p_technician_id uuid, p_booking_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text; lines jsonb; progress jsonb;
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 lines:=pdc_fitter_private.lines(b.vehicle_id,b.id);
 progress:=pdc_fitter_private.summary(lines,code);
 progress:=pdc_work_categories_private.line_handoff_progress_583(b.vehicle_id, code, lines, progress);
 lines:=pdc_work_categories_private.line_handoff_annotate_583(b.vehicle_id, code, lines);
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'version',b.version,
   'work_category',b.work_category,'vehicle_id',b.vehicle_id,'supplier_lines','[]'::jsonb,'status',b.status,'stage_code',code,'stoppage_reason',b.stoppage_reason,'lines',lines,
   'progress',progress,
   'handoff_targets', pdc_work_categories_private.line_handoff_targets_583(),
   'catalog_hash',md5((SELECT coalesce(jsonb_agg(l->>'scope_hash' ORDER BY l->>'line_identity'),'[]'::jsonb)::text
      FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'=code)))
   ||pdc_fitter_private.timing(b.id,statement_timestamp())||pdc_bus_private.team_payload(b.id);
END $function$;
-- Fitter gate back to the r616 text (without rpc/set_line_later_627).
CREATE OR REPLACE FUNCTION public.pdc_check_fitter_request()
 RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $function$
DECLARE path text:=ltrim(coalesce(current_setting('request.path',true),''),'/');
BEGIN
 IF EXISTS(SELECT 1 FROM public.pdc_user_roles
   WHERE (auth_user_id=auth.uid() OR email=lower(auth.jwt()->>'email')) AND role::text='fitter') THEN
  IF path='pdc_user_roles' AND current_setting('request.method',true) IN ('GET','HEAD') THEN RETURN; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=auth.uid()
    AND email=lower(auth.jwt()->>'email') AND active AND account_status='approved' AND role::text='fitter')
   OR path NOT IN ('rpc/get_fitter_roster','rpc/get_fitter_jobs','rpc/get_fitter_job','rpc/get_fitter_refresh','rpc/fitter_job_command','rpc/record_pdc_usage_20260914','rpc/handoff_operation_line_583','rpc/undo_line_handoff_583','rpc/list_line_handoffs_583')
   OR current_setting('request.method',true) <> 'POST' THEN
    RAISE EXCEPTION 'This account can access Fitters bay only' USING errcode='42501';
  END IF;
 END IF;
END $function$;
DROP TRIGGER IF EXISTS keep_station_open_627 ON public.vehicle_work_items;
DROP FUNCTION IF EXISTS pdc_work_categories_private.keep_station_open_627();
DROP FUNCTION IF EXISTS pdc_work_categories_private.line_later_627(uuid, text, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.set_line_later_627(uuid, text, text, text);
DROP TABLE IF EXISTS public.pdc_line_later_627;
DROP TABLE IF EXISTS public.pdc_line_later_history_627;
