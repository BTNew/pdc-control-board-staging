-- r890 (F440) / sort 910. Staging cdsmnqxtyyoeoznmbidd only. Applied 31 Oct 2026 ~11:05 AWST (Craig: "go live").
-- Craig 31 Oct 2026: the workshop TV (touch screen) presses Start / Stop on Tyre and Tint jobs and nothing else.
-- Before: workshopdisplay@pmgwa.com.au is a full operator, so the TV password could override stations, sign off
-- Final check, set keys or move bookings (3 such edits on 30 Oct 09:13 to 09:14 AWST, sublet tick + job categories).
-- 1. pdc_tv_private.displays lists the TV login(s).
-- 2. The PostgREST pre-request hook refuses every request from a TV login except the three calls workshop-tv.js
--    makes (get_pdc_workshop_tv_605, start_workshop_work, complete_workshop_work), plus its own role row and
--    record_pdc_login / record_pdc_usage_20260914 for a board sign-in that is sent on to the TV page.
-- 3. A BEFORE UPDATE trigger refuses a status change made by a TV login on any booking that is not TINT or TYRE.
-- The account keeps role operator (start/complete need it). Fitter, MMT and PSC branches unchanged.
-- Not a pinned function; pins unchanged.
-- Undo: supabase/rollbacks/20261031093000_r890_workshop_tv_only_login.down.sql
SET LOCAL lock_timeout = '4s';

CREATE SCHEMA IF NOT EXISTS pdc_tv_private;
REVOKE ALL ON SCHEMA pdc_tv_private FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS pdc_tv_private.displays (
  email text PRIMARY KEY CHECK (email = lower(btrim(email))),
  active boolean NOT NULL DEFAULT true,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON pdc_tv_private.displays FROM PUBLIC, anon, authenticated;
INSERT INTO pdc_tv_private.displays (email, note)
VALUES ('workshopdisplay@pmgwa.com.au', 'r890: workshop TV, Tyre and Tint Start / Stop only')
ON CONFLICT (email) DO NOTHING;

-- True when the current request is signed in as a TV login.
CREATE OR REPLACE FUNCTION pdc_tv_private.is_tv_request_890()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT EXISTS(SELECT 1 FROM pdc_tv_private.displays d
  WHERE d.active AND d.email = lower(btrim(coalesce(auth.jwt()->>'email',''))))
$function$;
REVOKE ALL ON FUNCTION pdc_tv_private.is_tv_request_890() FROM PUBLIC, anon, authenticated;

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
 -- r890 (F440): a workshop TV login shows the TV board and presses Start / Stop only.
 IF pdc_tv_private.is_tv_request_890() THEN
  IF path='pdc_user_roles' AND current_setting('request.method',true) IN ('GET','HEAD') THEN RETURN; END IF;
  IF path NOT IN ('rpc/get_pdc_workshop_tv_605','rpc/start_workshop_work','rpc/complete_workshop_work','rpc/record_pdc_login','rpc/record_pdc_usage_20260914')
   OR current_setting('request.method',true) <> 'POST' THEN
    RAISE EXCEPTION 'This account can access the workshop TV only' USING errcode='42501';
  END IF;
 END IF;
END $function$;

-- r890 (F440): a TV login may start or complete Tyre and Tint bookings only.
CREATE OR REPLACE FUNCTION pdc_tv_private.tyre_tint_only_890()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v_code text;
BEGIN
 IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
 IF NOT pdc_tv_private.is_tv_request_890() THEN RETURN NEW; END IF;
 SELECT upper(s.code) INTO v_code FROM public.workshop_stages s WHERE s.id = NEW.stage_id;
 IF coalesce(v_code,'') NOT IN ('TINT','TYRE') THEN
  RAISE EXCEPTION 'The workshop TV can start and complete Tyre and Tint jobs only' USING errcode='42501';
 END IF;
 RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION pdc_tv_private.tyre_tint_only_890() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS workshop_booking_047_tv_tyre_tint_890 ON public.workshop_bookings;
CREATE TRIGGER workshop_booking_047_tv_tyre_tint_890
 BEFORE UPDATE ON public.workshop_bookings
 FOR EACH ROW EXECUTE FUNCTION pdc_tv_private.tyre_tint_only_890();

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('workshop_tv_only_login_890', 'F440', 'Workshop TV login limited to Tyre / Tint Start / Stop',
$check$
SELECT position('is_tv_request_890' IN (SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_check_fitter_request()'::regprocedure)) > 0
   AND position('rpc/get_fitter_roster' IN (SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_check_fitter_request()'::regprocedure)) > 0
   AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'workshop_booking_047_tv_tyre_tint_890'
               AND tgrelid = 'public.workshop_bookings'::regclass AND tgenabled <> 'D')
   AND EXISTS (SELECT 1 FROM pdc_tv_private.displays WHERE active) AS ok,
 'Workshop TV login limited to Tyre / Tint Start / Stop' AS detail
$check$, true, 910, 'r890')
ON CONFLICT DO NOTHING;
