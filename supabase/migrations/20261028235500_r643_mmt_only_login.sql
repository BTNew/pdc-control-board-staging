-- r643 (F258) / sort 393. Applied 28 Oct 2026 ~18:21 AWST. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig: the MMT login (pdc_mmt_private.providers) sees only Sublet · MMT. The PostgREST pre-request hook
-- public.pdc_check_fitter_request (also the fitter lock) refuses every other request from that login.
-- Fitter branch unchanged. Not a pinned function; pins stay 241.
-- Undo: supabase/rollbacks/20261028235500_r643_mmt_only_login.down.sql
SET LOCAL lock_timeout = '4s';
CREATE OR REPLACE FUNCTION public.pdc_check_fitter_request()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE path text:=ltrim(coalesce(current_setting('request.path',true),''),'/');
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
 -- r643 (F258): the MMT login reads its own role row and uses the Sublet · MMT page only.
 IF EXISTS(SELECT 1 FROM pdc_mmt_private.providers p WHERE p.active AND p.email=lower(btrim(coalesce(auth.jwt()->>'email','')))) THEN
  IF path='pdc_user_roles' AND current_setting('request.method',true) IN ('GET','HEAD') THEN RETURN; END IF;
  IF path NOT IN ('rpc/get_pdc_mmt_sublet_board_642','rpc/set_pdc_mmt_sublet_tick_642','rpc/record_pdc_login','rpc/record_pdc_usage_20260914')
   OR current_setting('request.method',true) <> 'POST' THEN
    RAISE EXCEPTION 'This account can access Sublet · MMT only' USING errcode='42501';
  END IF;
 END IF;
END $function$;
-- Regression check mmt_only_login_643 (sort 393, F258) inserted at apply time.
