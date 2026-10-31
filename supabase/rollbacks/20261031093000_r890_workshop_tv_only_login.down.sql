-- Undo r890 (F440): the workshop TV login goes back to a plain operator. Restores the r711 pre-request hook
-- (md5 of pg_get_functiondef before r890: f561ff7915c67b82a6a29e87be67db39), drops the Tyre / Tint trigger,
-- the TV list and the regression check. No booking data changes.
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'workshop_tv_only_login_890' AND added_in = 'r890';
DROP TRIGGER IF EXISTS workshop_booking_047_tv_tyre_tint_890 ON public.workshop_bookings;
CREATE OR REPLACE FUNCTION public.pdc_check_fitter_request()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE path text:=ltrim(coalesce(current_setting('request.path',true),''),'/');
 v_provider text;
BEGIN
 IF EXISTS(SELECT 1 FROM public.pdc_user_roles
   WHERE (auth_user_id=auth.uid() OR email=lower(auth.jwt()->>'email')) AND role::text='fitter') THEN
  IF path='pdc_user_roles' AND current_setting('request.method',true) IN ('GET','HEAD') THEN RETURN; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=auth.uid()
    AND email=lower(auth.jwt()->>'email') AND active AND account_status='approved' AND role::text='fitter')
   OR path NOT IN ('rpc/get_fitter_roster','rpc/get_fitter_jobs','rpc/get_fitter_job','rpc/get_fitter_refresh','rpc/fitter_job_command','rpc/record_pdc_usage_20260914','rpc/handoff_operation_line_583','rpc/undo_line_handoff_583','rpc/list_line_handoffs_583','rpc/set_line_later_627')
   OR current_setting('request.method',true) <> 'POST' THEN
    RAISE EXCEPTION 'This account can access Fitters bay only' USING errcode='42501';
  END IF;
 END IF;
 -- r643 (F258) / r711 (F321): a sublet provider login reads its own role row and uses its own page only.
 SELECT p.provider INTO v_provider FROM pdc_mmt_private.providers p
  WHERE p.active AND p.email=lower(btrim(coalesce(auth.jwt()->>'email',''))) LIMIT 1;
 IF v_provider IS NOT NULL THEN
  IF path='pdc_user_roles' AND current_setting('request.method',true) IN ('GET','HEAD') THEN RETURN; END IF;
  IF v_provider='MMT' AND (path NOT IN ('rpc/get_pdc_mmt_sublet_board_642','rpc/set_pdc_mmt_sublet_tick_642','rpc/record_pdc_login','rpc/record_pdc_usage_20260914')
   OR current_setting('request.method',true) <> 'POST') THEN
    RAISE EXCEPTION 'This account can access Sublet · MMT only' USING errcode='42501';
  END IF;
  IF v_provider='PSC' AND (path NOT IN ('rpc/get_pdc_psc_sublet_board_711','rpc/set_pdc_psc_sublet_tick_711','rpc/record_pdc_login','rpc/record_pdc_usage_20260914')
   OR current_setting('request.method',true) <> 'POST') THEN
    RAISE EXCEPTION 'This account can access Sublet · PSC only' USING errcode='42501';
  END IF;
 END IF;
END $function$;
DROP FUNCTION IF EXISTS pdc_tv_private.tyre_tint_only_890();
DROP FUNCTION IF EXISTS pdc_tv_private.is_tv_request_890();
DROP TABLE IF EXISTS pdc_tv_private.displays;
DROP SCHEMA IF EXISTS pdc_tv_private;
