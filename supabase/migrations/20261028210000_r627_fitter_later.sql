-- r627 (F242) / sort 380. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026: on the fitter tablet, an item that can't be done in this booking can be marked "Later" (reason +
-- optional note). The item stays NOT done and outstanding for its station (station icon stays not green, QC stays
-- blocked, outstanding station hours still count it), but it no longer blocks completing this bay booking. The mark is
-- per booking: when the item is booked again it shows as a normal item. Same idea as sending a line to another
-- department (r583), kept at the same station.
-- Changes: one table + history, set_line_later_627 (fitter on their own booking, or controller), a progress/annotate
-- helper, get_fitter_job calls it (so fitter_job_command 'complete' uses it unchanged), and the fitter request gate
-- allows the new RPC. fitter_job_command, summary, lines, progress and Department 135 are untouched. Pins stay 241.
-- Undo: supabase/rollbacks/20261028210000_r627_fitter_later.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard627$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r627: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r627: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r627: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 380 OR fault_id = 'F242' OR added_in = 'r627' OR check_name = 'fitter_later_627') THEN
    RAISE EXCEPTION 'r627: sort 380 or F242 is taken';
  END IF;
  IF to_regclass('public.pdc_line_later_627') IS NOT NULL THEN RAISE EXCEPTION 'r627: table exists'; END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.vehicle_work_items'::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'r627: vehicle_work_items has triggers now'; END IF;
  -- The two functions replaced here must be exactly what this release was written against.
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_check_fitter_request()'::regprocedure)) <> '11c9967c8fe76e4ba8fe0bd88f20ed1f' THEN RAISE EXCEPTION 'r627: fitter gate changed'; END IF;
  IF strpos((SELECT prosrc FROM pg_proc WHERE oid = 'public.get_fitter_job(uuid,uuid)'::regprocedure),
     'lines:=pdc_work_categories_private.line_handoff_annotate_583(b.vehicle_id, code, lines);') = 0 THEN RAISE EXCEPTION 'r627: get_fitter_job changed'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure)) <> 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r627: dept 135 changed'; END IF;
END $guard627$;

CREATE TABLE public.pdc_line_later_627 (
  booking_id uuid NOT NULL REFERENCES public.workshop_bookings(id),
  line_identity text NOT NULL,
  vehicle_id uuid NOT NULL,
  stage_code text NOT NULL,
  reason text NOT NULL CHECK (reason IN ('parts', 'time', 'other_trade', 'other')),
  note text CHECK (note IS NULL OR length(note) <= 300),
  actor_id uuid, actor_email text, actor_role text,
  marked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (booking_id, line_identity)
);
CREATE TABLE public.pdc_line_later_history_627 (
  history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id uuid NOT NULL, line_identity text NOT NULL, vehicle_id uuid NOT NULL, stage_code text NOT NULL,
  action text NOT NULL CHECK (action IN ('later', 'clear')), reason text, note text,
  actor_id uuid, actor_email text, actor_role text, acted_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_line_later_627 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_line_later_history_627 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_line_later_627, public.pdc_line_later_history_627 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.set_line_later_627(p_booking_id uuid, p_line_identity text, p_reason text, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text; v_uid uuid := auth.uid(); v_email text := public.current_actor_email(); v_b public.workshop_bookings; v_code text; v_line jsonb;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
  v_role := lower(btrim(coalesce(public.current_pdc_user_role()::text, '')));
  IF v_role = 'fitter' THEN
    IF p_booking_id IS NULL OR NOT pdc_fitter_private.assigned(p_booking_id, v_uid) THEN RETURN jsonb_build_object('ok', false, 'error', 'assignment_changed'); END IF;
  ELSIF v_role NOT IN ('operator', 'administrator') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'role_required');
  END IF;
  IF p_line_identity IS NULL OR btrim(p_line_identity) = '' OR (p_reason IS NOT NULL AND p_reason NOT IN ('parts', 'time', 'other_trade', 'other'))
     OR length(coalesce(v_note, '')) > 300 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_request');
  END IF;
  SELECT * INTO v_b FROM public.workshop_bookings WHERE id = p_booking_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'booking_not_found'); END IF;
  IF v_b.status NOT IN ('queued', 'planned', 'started', 'stoppage') THEN RETURN jsonb_build_object('ok', false, 'error', 'booking_closed'); END IF;
  SELECT s.code INTO v_code FROM public.workshop_stages s WHERE s.id = v_b.stage_id;
  IF p_reason IS NULL THEN
    WITH gone AS (DELETE FROM public.pdc_line_later_627 WHERE booking_id = p_booking_id AND line_identity = p_line_identity RETURNING *)
    INSERT INTO public.pdc_line_later_history_627 (booking_id, line_identity, vehicle_id, stage_code, action, actor_id, actor_email, actor_role)
    SELECT booking_id, line_identity, vehicle_id, stage_code, 'clear', v_uid, v_email, v_role FROM gone;
    UPDATE public.workshop_station_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE stage_code = v_code;
    RETURN jsonb_build_object('ok', true, 'code', 'cleared', 'line_identity', p_line_identity);
  END IF;
  SELECT l INTO v_line FROM jsonb_array_elements(pdc_work_categories_private.line_handoff_annotate_583(v_b.vehicle_id, v_code, pdc_fitter_private.lines(v_b.vehicle_id, v_b.id))) l
  WHERE l->>'line_identity' = p_line_identity
    AND ((l->>'stage_code' = v_code AND coalesce((l->'handoff'->>'sent_away')::boolean, false) = false) OR coalesce((l->'handoff'->>'received_here')::boolean, false))
  LIMIT 1;
  IF v_line IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'line_not_found'); END IF;
  IF coalesce((v_line->>'completed')::boolean, false) THEN RETURN jsonb_build_object('ok', false, 'error', 'line_completed'); END IF;
  INSERT INTO public.pdc_line_later_627 (booking_id, line_identity, vehicle_id, stage_code, reason, note, actor_id, actor_email, actor_role)
  VALUES (p_booking_id, p_line_identity, v_b.vehicle_id, v_code, p_reason, v_note, v_uid, v_email, v_role)
  ON CONFLICT (booking_id, line_identity) DO UPDATE SET reason = EXCLUDED.reason, note = EXCLUDED.note, actor_id = EXCLUDED.actor_id,
    actor_email = EXCLUDED.actor_email, actor_role = EXCLUDED.actor_role, marked_at = clock_timestamp()
  WHERE public.pdc_line_later_627.booking_id = EXCLUDED.booking_id AND public.pdc_line_later_627.line_identity = EXCLUDED.line_identity;
  INSERT INTO public.pdc_line_later_history_627 (booking_id, line_identity, vehicle_id, stage_code, action, reason, note, actor_id, actor_email, actor_role)
  VALUES (p_booking_id, p_line_identity, v_b.vehicle_id, v_code, 'later', p_reason, v_note, v_uid, v_email, v_role);
  -- Other screens (fitter refresh, planner) see the change on their next read.
  UPDATE public.workshop_station_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE stage_code = v_code;
  RETURN jsonb_build_object('ok', true, 'code', 'later', 'line_identity', p_line_identity, 'reason', p_reason);
END $fn$;
REVOKE ALL ON FUNCTION public.set_line_later_627(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_line_later_627(uuid, text, text, text) TO authenticated;

-- Marks Later lines and, only when this booking has any, recounts progress without them (read only).
CREATE FUNCTION pdc_work_categories_private.line_later_627(p_booking uuid, p_stage text, p_lines jsonb, p_progress jsonb, OUT lines jsonb, OUT progress jsonb)
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public AS $fn$
DECLARE v_total integer; v_done integer; v_unknown integer; v_later integer;
BEGIN
  lines := p_lines; progress := p_progress;
  IF p_booking IS NULL OR NOT EXISTS (SELECT 1 FROM public.pdc_line_later_627 WHERE booking_id = p_booking) THEN RETURN; END IF;
  SELECT coalesce(jsonb_agg(CASE WHEN m.line_identity IS NULL OR coalesce((e.l->>'completed')::boolean, false) THEN e.l
      ELSE e.l || jsonb_build_object('later', jsonb_build_object('reason', m.reason, 'note', m.note, 'by', m.actor_email, 'at', m.marked_at)) END ORDER BY e.o), '[]')
  INTO lines
  FROM jsonb_array_elements(p_lines) WITH ORDINALITY e(l, o)
  LEFT JOIN public.pdc_line_later_627 m ON m.booking_id = p_booking AND m.line_identity = e.l->>'line_identity';
  SELECT count(*) FILTER (WHERE NOT later), count(*) FILTER (WHERE NOT later AND done),
         count(*) FILTER (WHERE NOT later AND unknown), count(*) FILTER (WHERE later)
  INTO v_total, v_done, v_unknown, v_later
  FROM (SELECT l ? 'later' AS later, coalesce((l->>'completed')::boolean, false) AS done,
          ((jsonb_typeof(l->'hours') IS DISTINCT FROM 'number' OR (l->>'hours')::numeric <= 0)
            AND l->>'external_work' IS DISTINCT FROM 'true' AND l->>'zero_hour_task' IS DISTINCT FROM 'true') AS unknown
        FROM jsonb_array_elements(lines) l
        WHERE (l->>'stage_code' = p_stage AND coalesce((l->'handoff'->>'sent_away')::boolean, false) = false)
           OR coalesce((l->'handoff'->>'received_here')::boolean, false)) own;
  progress := p_progress || jsonb_build_object('total_lines', v_total, 'completed_lines', v_done, 'unknown_hours', v_unknown, 'later', v_later,
    'can_complete', (v_total > 0 AND v_total = v_done AND v_unknown = 0)
      OR (v_total = 0 AND v_unknown = 0 AND (v_later > 0 OR coalesce((p_progress->>'handed_away')::integer, 0) > 0)));
END $fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.line_later_627(uuid, text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- Completing a booking marks its station's vehicle_work_items row done (for bookings without a work category), which
-- takes the vehicle off that station's "to book" list. While a Later item at that station is still not done, keep the
-- station requirement open so the vehicle stays in that station's list to book the rest.
CREATE FUNCTION pdc_work_categories_private.keep_station_open_627() RETURNS trigger SECURITY DEFINER
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
BEGIN
  IF NEW.completed AND NEW.required AND EXISTS (
    SELECT 1 FROM public.pdc_line_later_627 m
    WHERE m.vehicle_id = NEW.vehicle_id AND m.stage_code = public.workshop_stage_code_for_work_key(NEW.work_key)
      AND NOT EXISTS (SELECT 1 FROM public.pdc_panel_line_completion_565 c WHERE c.vehicle_id = m.vehicle_id AND c.line_identity = m.line_identity AND c.completed)
      AND NOT coalesce((SELECT p.completed FROM pdc_fitter_private.operation_progress p JOIN public.workshop_bookings wb ON wb.id = p.booking_id
            WHERE wb.vehicle_id = m.vehicle_id AND wb.deleted_at IS NULL AND p.line_identity = m.line_identity ORDER BY p.updated_at DESC LIMIT 1), false)) THEN
    NEW.completed := false; NEW.completed_by := NULL; NEW.completed_at := NULL;
  END IF;
  RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.keep_station_open_627() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER keep_station_open_627 BEFORE INSERT OR UPDATE OF completed ON public.vehicle_work_items
FOR EACH ROW WHEN (NEW.completed) EXECUTE FUNCTION pdc_work_categories_private.keep_station_open_627();

CREATE OR REPLACE FUNCTION public.get_fitter_job(p_technician_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text; lines jsonb; progress jsonb; later record;
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
 -- r627 (F242): Later items stay outstanding but do not block completing this booking.
 SELECT * INTO later FROM pdc_work_categories_private.line_later_627(b.id, code, lines, progress);
 lines:=later.lines; progress:=later.progress;
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'version',b.version,
   'work_category',b.work_category,'vehicle_id',b.vehicle_id,'supplier_lines','[]'::jsonb,'status',b.status,'stage_code',code,'stoppage_reason',b.stoppage_reason,'lines',lines,
   'progress',progress,
   'handoff_targets', pdc_work_categories_private.line_handoff_targets_583(),
   'catalog_hash',md5((SELECT coalesce(jsonb_agg(l->>'scope_hash' ORDER BY l->>'line_identity'),'[]'::jsonb)::text
      FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'=code)))
   ||pdc_fitter_private.timing(b.id,statement_timestamp())||pdc_bus_private.team_payload(b.id);
END $function$;

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
END $function$;

DO $check627$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('fitter_later_627', 'F242',
    'Fitter Later: per-booking mark, item stays outstanding (no completion write), only get_fitter_job recounts, fitter gate allows the RPC, Dept 135 untouched.',
    $chk627$
SELECT
  strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.get_fitter_job(uuid,uuid)')), 'line_later_627(b.id, code, lines, progress);') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.pdc_check_fitter_request()')), 'rpc/set_line_later_627') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.pdc_check_fitter_request()')), 'rpc/handoff_operation_line_583') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.set_line_later_627(uuid,text,text,text)')), 'pdc_panel_line_completion') = 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.set_line_later_627(uuid,text,text,text)')), 'complete_workshop_work') = 0
  AND NOT has_function_privilege('anon', 'public.set_line_later_627(uuid,text,text,text)', 'execute')
  AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.pdc_line_later_627'::regclass)
  AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'keep_station_open_627' AND tgrelid = 'public.vehicle_work_items'::regclass AND tgenabled = 'O')
  AND md5((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))) = 'fd05b9eef69498002ac06dd68e01cdff'
 AS ok,
 'fitter Later keeps items outstanding and only unblocks this booking' AS detail
$chk627$,
    true, 380, 'r627');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'fitter_later_627') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r627: check red: %', detail; END IF;
END $check627$;
