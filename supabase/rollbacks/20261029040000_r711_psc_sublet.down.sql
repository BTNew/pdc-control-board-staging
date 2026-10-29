-- Undo r711 (F321): remove Sublet · PSC. PSC Built/Invoiced rows stay in pdc_mmt_private.builds (harmless; no page
-- reads them). PSC Complete ticks stay on the board as ordinary sublet done ticks. Restores the r643 hook
-- (md5 494db85fba899c69f02a8e8836068779) and the r642 MMT role helper. Remove any PSC login rows first.
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'psc_sublet_711' AND added_in = 'r711';
DELETE FROM pdc_mmt_private.providers WHERE provider = 'PSC';
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
CREATE OR REPLACE FUNCTION pdc_mmt_private.actor_role_642()
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  WITH me AS (
    SELECT r.role::text AS role FROM public.pdc_user_roles r
    WHERE r.auth_user_id = auth.uid() AND lower(r.email) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
      AND r.active AND r.account_status = 'approved'
  )
  SELECT CASE
    WHEN auth.uid() IS NULL THEN NULL
    WHEN EXISTS (SELECT 1 FROM me WHERE role IN ('administrator')) THEN 'administrator'
    WHEN EXISTS (SELECT 1 FROM me WHERE role IN ('operator')) THEN 'operator'
    WHEN EXISTS (SELECT 1 FROM me) AND EXISTS (SELECT 1 FROM pdc_mmt_private.providers p
         WHERE p.active AND p.email = lower(btrim(coalesce(auth.jwt()->>'email', ''))))
      THEN 'sublet_provider'
    WHEN EXISTS (SELECT 1 FROM me WHERE role IN ('fitter')) THEN 'fitter'
    WHEN EXISTS (SELECT 1 FROM me) THEN 'viewer'
  END
$fn$;
REVOKE ALL ON FUNCTION pdc_mmt_private.actor_role_642() FROM PUBLIC, anon, authenticated;
DROP FUNCTION IF EXISTS public.set_pdc_psc_sublet_tick_711(uuid, text, text, boolean, integer);
DROP FUNCTION IF EXISTS public.get_pdc_psc_sublet_board_711();
DROP FUNCTION IF EXISTS pdc_mmt_private.actor_role_711(text);
DROP FUNCTION IF EXISTS pdc_mmt_private.psc_line_711(text);
ALTER TABLE pdc_mmt_private.history DROP COLUMN IF EXISTS provider;
ALTER TABLE pdc_mmt_private.providers DROP COLUMN IF EXISTS provider;
DO $$ BEGIN
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_check_fitter_request()'::regprocedure)) <> '494db85fba899c69f02a8e8836068779' THEN
    RAISE EXCEPTION 'r711 undo: hook md5 mismatch';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r711 undo: pin count'; END IF;
END $$;
