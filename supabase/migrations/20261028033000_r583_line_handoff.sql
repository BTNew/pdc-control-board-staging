-- r583 (F197) / sort 355. PREVIEW. SQL is not applied. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
--
-- Ledger at this preview: sort 353 is bodybuilder_new_to_pmb_574 (r582 / F195).
-- sort 354 is station_icon_completion_578 (r578 / F196). Sort 351, F193 and r580
-- stay unused. This release is the next free triple after that tip: r583 / F197 / sort 355.
--
-- A fitter can send one operation line to another department, and optionally a bay.
-- The line stays outstanding. It does not count as done, and it does not block
-- the fitter completing the rest of this bay. The workshop controller sees it as
-- an unbooked line for the target department (New to PMB strip and the vehicle's
-- operation list) and books it with the existing bay booking. Undo puts it back.
-- The station icon (r578) counts the line on the target department, still outstanding
-- until the line itself is done. Department 135 is not edited. Pin count stays 241.
-- No pinned function is replaced. public.fitter_job_command stays
-- 626ca8b23a2e5f02e2ca8f96a4533d6f. Department 135 stays fd05b9eef69498002ac06dd68e01cdff.
-- Undo: supabase/rollbacks/20261028033000_r583_line_handoff.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r583: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r583: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r583: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bodybuilder_new_to_pmb_574' AND fault_id='F195' AND sort_order=353 AND added_in='r582') THEN RAISE EXCEPTION 'r583: r582 / F195 sort 353 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='station_icon_completion_578' AND fault_id='F196' AND sort_order=354 AND added_in='r578') THEN RAISE EXCEPTION 'r583: r578 / F196 sort 354 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=355 OR fault_id='F197' OR check_name='line_handoff_583' OR added_in='r583') THEN RAISE EXCEPTION 'r583: sort 355 or F197 is taken'; END IF;
 IF pg_catalog.to_regclass('public.pdc_line_handoff_583') IS NOT NULL THEN RAISE EXCEPTION 'r583: already applied'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r583: department 135 changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r583: fitter command changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_fitter_job(uuid,uuid)'))
    IS DISTINCT FROM '74d1a88dc9b440782904c02682c25ebc' THEN RAISE EXCEPTION 'r583: get_fitter_job is not the live body'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_check_fitter_request()'))
    IS DISTINCT FROM '6cdf34218dcacc86fda2cab39bb69025' THEN RAISE EXCEPTION 'r583: fitter request gate changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_work_categories_private.station_icon_completion_578(uuid[])'))
    IS DISTINCT FROM '88d2eed58518a9eb98ef4210610a4dd1' THEN RAISE EXCEPTION 'r583: station icon read changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_fitter_private.summary(jsonb,text)'))
    IS DISTINCT FROM 'c481664c82eb64487b1085edd67b9045' THEN RAISE EXCEPTION 'r583: fitter summary changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_fitter_private.lines(uuid,uuid)'))
    IS DISTINCT FROM '6773b7cf4e6bc040f14fc39548f77797' THEN RAISE EXCEPTION 'r583: fitter lines changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_fitter_private.progress(uuid)'))
    IS DISTINCT FROM '2eccf8ad296d2ae89f873d1eb5050ca5' THEN RAISE EXCEPTION 'r583: fitter progress changed'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='station_icon_completion_578')
    IS DISTINCT FROM '0d7536485eb84f94ac177fe2224e9738' THEN RAISE EXCEPTION 'r583: station icon check changed'; END IF;
 PERFORM set_config('pdc.r583_job_acl', (SELECT proacl::text FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.get_fitter_job(uuid,uuid)')), true);
 PERFORM set_config('pdc.r583_gate_acl', (SELECT proacl::text FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_check_fitter_request()')), true);
 PERFORM set_config('pdc.r583_k135_refresh', (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('karratha135_pdc.get_fitter_refresh(uuid,uuid,text)')), true);
END $g$;

CREATE TABLE public.pdc_line_handoff_583 (
 vehicle_id uuid NOT NULL,
 line_identity text NOT NULL,
 from_stage_code text NOT NULL,
 to_stage_code text NOT NULL,
 from_bay_id uuid,
 to_bay_id uuid,
 source_booking_id uuid,
 actor_id uuid,
 actor_email text,
 actor_role text,
 handed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 PRIMARY KEY (vehicle_id, line_identity),
 CONSTRAINT pdc_line_handoff_583_stage CHECK (
  from_stage_code IN ('TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','BUS_4X4','SUBLET')
  AND to_stage_code IN ('TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','BUS_4X4','SUBLET')
 ),
 CONSTRAINT pdc_line_handoff_583_role CHECK (actor_role IS NULL OR actor_role IN ('fitter','operator','administrator')),
 CONSTRAINT pdc_line_handoff_583_line CHECK (pg_catalog.length(pg_catalog.btrim(line_identity)) > 0),
 CONSTRAINT pdc_line_handoff_583_move CHECK (from_stage_code <> to_stage_code OR to_bay_id IS NOT NULL)
);
ALTER TABLE public.pdc_line_handoff_583 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_line_handoff_583 FROM PUBLIC, anon, authenticated;

CREATE TABLE public.pdc_line_handoff_history_583 (
 history_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 vehicle_id uuid NOT NULL,
 line_identity text NOT NULL,
 action text NOT NULL,
 from_stage_code text,
 to_stage_code text,
 from_bay_id uuid,
 to_bay_id uuid,
 source_booking_id uuid,
 actor_id uuid,
 actor_email text,
 actor_role text,
 acted_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 CONSTRAINT pdc_line_handoff_history_583_action CHECK (action IN ('handoff','undo')),
 CONSTRAINT pdc_line_handoff_history_583_role CHECK (actor_role IS NULL OR actor_role IN ('fitter','operator','administrator'))
);
ALTER TABLE public.pdc_line_handoff_history_583 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_line_handoff_history_583 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.pdc_line_handoff_history_guard_583()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog
AS $guard583$
BEGIN
 RAISE EXCEPTION 'pdc_line_handoff_history_583 is append-only';
END
$guard583$;

CREATE TRIGGER pdc_line_handoff_history_583_guard
BEFORE UPDATE OR DELETE ON public.pdc_line_handoff_history_583
FOR EACH ROW EXECUTE FUNCTION public.pdc_line_handoff_history_guard_583();

REVOKE ALL ON FUNCTION public.pdc_line_handoff_history_guard_583() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_work_categories_private.line_handoff_work_key_583(p_stage text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO pg_catalog
AS $key583$
SELECT CASE pg_catalog.upper(pg_catalog.btrim(coalesce(p_stage, '')))
 WHEN 'BUS_4X4' THEN 'bus4x4'
 WHEN 'BUS_MECHANICAL' THEN 'bus4x4'
 WHEN 'BUS_ACCESSORIES' THEN 'bus4x4'
 WHEN 'BUS_ELECTRICAL' THEN 'bus4x4'
 WHEN 'BUS_QA' THEN 'bus4x4'
 WHEN 'TINT' THEN 'tint'
 WHEN 'HOIST' THEN 'hoist'
 WHEN 'FITTING' THEN 'fitting'
 WHEN 'FABRICATION' THEN 'fabrication'
 WHEN 'ELECTRICAL' THEN 'electrical'
 WHEN 'TYRE' THEN 'tyre'
 WHEN 'SUBLET' THEN 'sublet'
 WHEN 'PARTS' THEN 'parts'
 ELSE NULL
END
$key583$;

REVOKE ALL ON FUNCTION pdc_work_categories_private.line_handoff_work_key_583(text) FROM PUBLIC, anon, authenticated;

-- A handed-off line counts for the department it was sent to, and only as done
-- when that line is actually done. An empty handoff table leaves every station
-- exactly as r578 calculated it.
DO $patch578$
DECLARE def text; patched text;
BEGIN
 def := pg_catalog.pg_get_functiondef('pdc_work_categories_private.station_icon_completion_578(uuid[])'::pg_catalog.regprocedure);
 patched := pg_catalog.replace(def,
$old578$), uniq AS (
 SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
 FROM known
 WHERE work_key IS NOT NULL
 GROUP BY vehicle_id, work_key, line_identity
), panel AS ($old578$,
$new578$), mapped AS (
 SELECT k.vehicle_id,
  coalesce(pdc_work_categories_private.line_handoff_work_key_583(h.to_stage_code), k.work_key) AS work_key,
  k.line_identity, k.qc_done
 FROM known k
 LEFT JOIN public.pdc_line_handoff_583 h
  ON h.vehicle_id = k.vehicle_id AND h.line_identity = k.line_identity
), uniq AS (
 SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
 FROM mapped
 WHERE work_key IS NOT NULL
 GROUP BY vehicle_id, work_key, line_identity
), panel AS ($new578$);
 IF patched IS NOT DISTINCT FROM def THEN RAISE EXCEPTION 'r583: station icon patch did not match'; END IF;
 EXECUTE patched;
END
$patch578$;

UPDATE pdc_ops.regression_checks
SET check_sql = pg_catalog.replace(check_sql,
$oldchk$), uniq AS (
    SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
    FROM known
    WHERE work_key IS NOT NULL
    GROUP BY vehicle_id, work_key, line_identity
  ), panel AS ($oldchk$,
$newchk$), mapped AS (
    SELECT k.vehicle_id,
     coalesce(pdc_work_categories_private.line_handoff_work_key_583(h.to_stage_code), k.work_key) AS work_key,
     k.line_identity, k.qc_done
    FROM known k
    LEFT JOIN public.pdc_line_handoff_583 h
     ON h.vehicle_id = k.vehicle_id AND h.line_identity = k.line_identity
  ), uniq AS (
    SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
    FROM mapped
    WHERE work_key IS NOT NULL
    GROUP BY vehicle_id, work_key, line_identity
  ), panel AS ($newchk$)
WHERE check_name='station_icon_completion_578' AND fault_id='F196' AND sort_order=354 AND added_in='r578'
  AND pg_catalog.strpos(check_sql, 'FROM known') > 0;

CREATE FUNCTION pdc_work_categories_private.line_handoff_progress_583(p_vehicle uuid, p_stage text, p_lines jsonb, p_progress jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog
AS $prog583$
DECLARE
 v_total integer;
 v_done integer;
 v_unknown integer;
 v_hours numeric;
 v_done_hours numeric;
 v_away integer;
BEGIN
 IF p_vehicle IS NULL OR NOT EXISTS (
   SELECT 1
   FROM public.pdc_line_handoff_583 h
   WHERE h.vehicle_id = p_vehicle
     AND EXISTS (
       SELECT 1 FROM pg_catalog.jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l
       WHERE l->>'line_identity' = h.line_identity
     )
 ) THEN
  RETURN p_progress;
 END IF;
 SELECT
  count(*) FILTER (WHERE effective_stage = p_stage),
  count(*) FILTER (WHERE effective_stage = p_stage AND (l->>'completed')::boolean),
  count(*) FILTER (WHERE effective_stage = p_stage AND (hours IS NULL OR hours <= 0) AND l->>'external_work' IS DISTINCT FROM 'true' AND l->>'zero_hour_task' IS DISTINCT FROM 'true'),
  coalesce(sum(greatest(hours, 0)) FILTER (WHERE effective_stage = p_stage), 0),
  coalesce(sum(greatest(hours, 0) * CASE WHEN (l->>'completed')::boolean THEN 1 ELSE coalesce((l->>'completed_fraction')::numeric, 0) END) FILTER (WHERE effective_stage = p_stage), 0),
  count(*) FILTER (WHERE stage_code = p_stage AND effective_stage IS DISTINCT FROM p_stage)
 INTO v_total, v_done, v_unknown, v_hours, v_done_hours, v_away
 FROM (
  SELECT s.l, s.stage_code, s.hours,
   coalesce(
    (SELECT h.to_stage_code FROM public.pdc_line_handoff_583 h
     WHERE h.vehicle_id = p_vehicle AND h.line_identity = s.line_identity),
    s.stage_code
   ) AS effective_stage
  FROM (
   SELECT l,
    l->>'line_identity' AS line_identity,
    l->>'stage_code' AS stage_code,
    CASE WHEN l->>'external_work' = 'true' THEN 0
         WHEN pg_catalog.jsonb_typeof(l->'hours') = 'number' THEN (l->>'hours')::numeric END AS hours
   FROM pg_catalog.jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l
  ) s
 ) eff;
 RETURN pg_catalog.jsonb_build_object(
  'total_lines', v_total,
  'completed_lines', v_done,
  'unknown_hours', v_unknown,
  'total_hours', v_hours,
  'completed_hours', v_done_hours,
  'percent', CASE
    WHEN v_total > 0 AND v_total = v_done AND v_unknown = 0 THEN 100
    WHEN v_hours > 0 THEN least(99, pg_catalog.floor(100 * v_done_hours / v_hours))
    ELSE 0 END,
  'can_complete', (v_total > 0 AND v_total = v_done AND v_unknown = 0)
    OR (v_total = 0 AND v_away > 0 AND v_unknown = 0),
  'handed_away', v_away
 );
END
$prog583$;

REVOKE ALL ON FUNCTION pdc_work_categories_private.line_handoff_progress_583(uuid, text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_work_categories_private.line_handoff_annotate_583(p_vehicle uuid, p_stage text, p_lines jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog
AS $ann583$
SELECT CASE WHEN p_vehicle IS NULL OR NOT EXISTS (
  SELECT 1 FROM public.pdc_line_handoff_583 h
  WHERE h.vehicle_id = p_vehicle
    AND EXISTS (
      SELECT 1 FROM pg_catalog.jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l
      WHERE l->>'line_identity' = h.line_identity
    )
) THEN p_lines
ELSE (
  SELECT coalesce(pg_catalog.jsonb_agg(
    CASE WHEN h.line_identity IS NULL THEN elem.l
    ELSE elem.l || pg_catalog.jsonb_build_object('handoff', pg_catalog.jsonb_build_object(
      'from_stage_code', h.from_stage_code,
      'to_stage_code', h.to_stage_code,
      'to_bay_id', h.to_bay_id,
      'to_bay_number', b.bay_number,
      'to_bay_name', coalesce(nullif(pg_catalog.btrim(b.display_name), ''), 'Bay ' || pg_catalog.lpad(b.bay_number::text, 2, '0')),
      'actor_email', h.actor_email,
      'actor_role', h.actor_role,
      'handed_at', h.handed_at,
      'sent_away', h.to_stage_code IS DISTINCT FROM p_stage,
      'received_here', h.to_stage_code IS NOT DISTINCT FROM p_stage AND elem.l->>'stage_code' IS DISTINCT FROM p_stage
    ))
    END
    ORDER BY elem.ord
  ), '[]'::jsonb)
  FROM pg_catalog.jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) WITH ORDINALITY AS elem(l, ord)
  LEFT JOIN public.pdc_line_handoff_583 h
    ON h.vehicle_id = p_vehicle AND h.line_identity = elem.l->>'line_identity'
  LEFT JOIN public.workshop_bays b ON b.id = h.to_bay_id
)
END
$ann583$;

REVOKE ALL ON FUNCTION pdc_work_categories_private.line_handoff_annotate_583(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_work_categories_private.line_handoff_targets_583()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog
AS $tgt583$
SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 'stage_code', s.code,
 'label', CASE s.code
   WHEN 'ELECTRICAL' THEN 'Electrical'
   WHEN 'FITTING' THEN 'Fitting'
   WHEN 'FABRICATION' THEN 'Fabrication'
   WHEN 'HOIST' THEN 'Hoist'
   WHEN 'TYRE' THEN 'Tyres'
   WHEN 'TINT' THEN 'Tint'
   WHEN 'SUBLET' THEN 'Sublet'
   WHEN 'BUS_4X4' THEN 'Bus 4x4'
   ELSE s.display_name END,
 'bays', coalesce((
   SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
     'id', b.id,
     'number', b.bay_number,
     'label', coalesce(nullif(pg_catalog.btrim(b.display_name), ''), 'Bay ' || pg_catalog.lpad(b.bay_number::text, 2, '0'))
   ) ORDER BY b.bay_number)
   FROM public.workshop_bays b
   WHERE b.stage_id = s.id AND b.is_active
 ), '[]'::jsonb)
) ORDER BY s.sort_order, s.code), '[]'::jsonb)
FROM public.workshop_stages s
WHERE s.active AND s.code IN ('TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','BUS_4X4','SUBLET')
$tgt583$;

REVOKE ALL ON FUNCTION pdc_work_categories_private.line_handoff_targets_583() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_fitter_job(p_technician_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
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
   OR path NOT IN ('rpc/get_fitter_roster','rpc/get_fitter_jobs','rpc/get_fitter_job','rpc/get_fitter_refresh','rpc/fitter_job_command','rpc/record_pdc_usage_20260914','rpc/handoff_operation_line_583','rpc/undo_line_handoff_583','rpc/list_line_handoffs_583')
   OR current_setting('request.method',true) <> 'POST' THEN
    RAISE EXCEPTION 'This account can access Fitters bay only' USING errcode='42501';
  END IF;
 END IF;
END $function$;

CREATE FUNCTION public.handoff_operation_line_583(p_booking_id uuid, p_vehicle_id uuid, p_line_identity text, p_to_stage text, p_to_bay_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog
AS $hand583$
DECLARE
 v_role text;
 v_email text;
 v_uid uuid;
 v_vehicle uuid;
 v_booking public.workshop_bookings;
 v_line_stage text;
 v_from_stage text;
 v_from_bay uuid;
 v_prev public.pdc_line_handoff_583;
 v_had boolean := false;
 v_origin_stage text;
 v_leaving_stage text;
 v_leaving_bay uuid;
 v_now timestamptz;
 v_bay_stage text;
BEGIN
 v_role := pg_catalog.lower(pg_catalog.btrim(coalesce(public.current_pdc_user_role()::text, '')));
 v_uid := auth.uid();
 v_email := public.current_actor_email();
 v_now := pg_catalog.clock_timestamp();
 IF v_role IN ('operator','administrator') THEN
  NULL;
 ELSIF v_role = 'fitter' THEN
  IF p_booking_id IS NULL OR NOT pdc_fitter_private.assigned(p_booking_id, v_uid) THEN
   RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'assignment_changed');
  END IF;
 ELSE
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'role_required');
 END IF;
 IF p_line_identity IS NULL OR pg_catalog.btrim(p_line_identity) = '' OR p_to_stage IS NULL THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'invalid_line');
 END IF;
 p_to_stage := pg_catalog.upper(pg_catalog.btrim(p_to_stage));
 IF p_to_stage NOT IN ('TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','BUS_4X4','SUBLET') THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'invalid_department');
 END IF;
 IF p_booking_id IS NOT NULL THEN
  SELECT * INTO v_booking FROM public.workshop_bookings WHERE id = p_booking_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'booking_not_found'); END IF;
  IF p_vehicle_id IS NOT NULL AND p_vehicle_id IS DISTINCT FROM v_booking.vehicle_id THEN
   RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'vehicle_mismatch');
  END IF;
  v_vehicle := v_booking.vehicle_id;
 ELSE
  v_vehicle := p_vehicle_id;
 END IF;
 IF v_vehicle IS NULL OR NOT EXISTS (SELECT 1 FROM public.vehicles WHERE id = v_vehicle) THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'vehicle_not_found');
 END IF;
 SELECT l->>'stage_code' INTO v_line_stage
 FROM pg_catalog.jsonb_array_elements(coalesce(public.pdc_qc_operation_lines_379(v_vehicle), '[]'::jsonb)) l
 WHERE l->>'line_identity' = p_line_identity
   AND coalesce((l->>'active')::boolean, true)
   AND coalesce((l->>'rejected')::boolean, false) = false
 LIMIT 1;
 IF v_line_stage IS NULL THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'line_not_found');
 END IF;
 IF p_to_bay_id IS NOT NULL THEN
  SELECT s.code INTO v_bay_stage
  FROM public.workshop_bays b
  JOIN public.workshop_stages s ON s.id = b.stage_id
  WHERE b.id = p_to_bay_id AND b.is_active;
  IF v_bay_stage IS DISTINCT FROM p_to_stage THEN
   RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'invalid_bay');
  END IF;
 END IF;
 v_line_stage := pg_catalog.upper(pg_catalog.btrim(v_line_stage));
 SELECT * INTO v_prev FROM public.pdc_line_handoff_583
 WHERE vehicle_id = v_vehicle AND line_identity = p_line_identity;
 v_had := FOUND;
 IF v_had THEN
  v_origin_stage := v_prev.from_stage_code;
  v_from_bay := v_prev.from_bay_id;
  v_leaving_stage := v_prev.to_stage_code;
  v_leaving_bay := v_prev.to_bay_id;
 ELSE
  v_origin_stage := v_line_stage;
  v_leaving_stage := v_line_stage;
  v_from_bay := NULL;
  v_leaving_bay := NULL;
  IF p_booking_id IS NOT NULL THEN
   SELECT b.bay_id INTO v_leaving_bay
   FROM public.workshop_bookings b
   JOIN public.workshop_stages s ON s.id = b.stage_id
   WHERE b.id = v_booking.id AND s.code = v_origin_stage;
   v_from_bay := v_leaving_bay;
  END IF;
 END IF;
 IF p_to_stage = v_leaving_stage AND p_to_bay_id IS NOT DISTINCT FROM v_leaving_bay THEN
  IF v_had THEN
   RETURN pg_catalog.jsonb_build_object('ok', true, 'code', 'unchanged', 'line_identity', p_line_identity, 'to_stage_code', p_to_stage);
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'same_department');
 END IF;
 IF p_to_stage = v_origin_stage AND p_to_bay_id IS NULL THEN
  IF NOT v_had THEN
   RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'same_department');
  END IF;
  INSERT INTO public.pdc_line_handoff_history_583 (
   vehicle_id, line_identity, action, from_stage_code, to_stage_code, from_bay_id, to_bay_id,
   source_booking_id, actor_id, actor_email, actor_role, acted_at)
  VALUES (
   v_vehicle, p_line_identity, 'undo', v_leaving_stage, v_origin_stage, v_leaving_bay, NULL,
   p_booking_id, v_uid, v_email, v_role, v_now);
  DELETE FROM public.pdc_line_handoff_583
  WHERE vehicle_id = v_vehicle AND line_identity = p_line_identity;
  RETURN pg_catalog.jsonb_build_object(
   'ok', true, 'code', 'undone', 'vehicle_id', v_vehicle, 'line_identity', p_line_identity,
   'from_stage_code', v_leaving_stage, 'to_stage_code', v_origin_stage,
   'actor_email', v_email, 'actor_role', v_role, 'acted_at', v_now);
 END IF;
 v_from_stage := v_origin_stage;
 INSERT INTO public.pdc_line_handoff_history_583 (
  vehicle_id, line_identity, action, from_stage_code, to_stage_code, from_bay_id, to_bay_id,
  source_booking_id, actor_id, actor_email, actor_role, acted_at)
 VALUES (
  v_vehicle, p_line_identity, 'handoff', v_leaving_stage, p_to_stage, v_leaving_bay, p_to_bay_id,
  p_booking_id, v_uid, v_email, v_role, v_now);
 INSERT INTO public.pdc_line_handoff_583 (
  vehicle_id, line_identity, from_stage_code, to_stage_code, from_bay_id, to_bay_id,
  source_booking_id, actor_id, actor_email, actor_role, handed_at)
 VALUES (
  v_vehicle, p_line_identity, v_from_stage, p_to_stage, v_from_bay, p_to_bay_id,
  p_booking_id, v_uid, v_email, v_role, v_now)
 ON CONFLICT (vehicle_id, line_identity) DO UPDATE
 SET to_stage_code = EXCLUDED.to_stage_code,
     to_bay_id = EXCLUDED.to_bay_id,
     source_booking_id = EXCLUDED.source_booking_id,
     actor_id = EXCLUDED.actor_id,
     actor_email = EXCLUDED.actor_email,
     actor_role = EXCLUDED.actor_role,
     handed_at = EXCLUDED.handed_at
 WHERE public.pdc_line_handoff_583.vehicle_id = EXCLUDED.vehicle_id
   AND public.pdc_line_handoff_583.line_identity = EXCLUDED.line_identity;
 RETURN pg_catalog.jsonb_build_object(
  'ok', true, 'code', 'sent', 'vehicle_id', v_vehicle, 'line_identity', p_line_identity,
  'from_stage_code', v_leaving_stage, 'to_stage_code', p_to_stage, 'to_bay_id', p_to_bay_id,
  'actor_email', v_email, 'actor_role', v_role, 'handed_at', v_now);
END
$hand583$;

REVOKE ALL ON FUNCTION public.handoff_operation_line_583(uuid, uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.handoff_operation_line_583(uuid, uuid, text, text, uuid) TO authenticated;

CREATE FUNCTION public.undo_line_handoff_583(p_vehicle_id uuid, p_line_identity text, p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog
AS $undo583$
DECLARE
 v_role text;
 v_email text;
 v_uid uuid;
 v_row public.pdc_line_handoff_583;
 v_now timestamptz;
BEGIN
 v_role := pg_catalog.lower(pg_catalog.btrim(coalesce(public.current_pdc_user_role()::text, '')));
 v_uid := auth.uid();
 v_email := public.current_actor_email();
 v_now := pg_catalog.clock_timestamp();
 IF p_vehicle_id IS NULL OR p_line_identity IS NULL OR pg_catalog.btrim(p_line_identity) = '' THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'invalid_line');
 END IF;
 IF v_role IN ('operator','administrator') THEN
  NULL;
 ELSIF v_role = 'fitter' THEN
  IF NOT EXISTS (
    SELECT 1 FROM public.workshop_bookings b
    WHERE b.vehicle_id = p_vehicle_id AND b.deleted_at IS NULL
      AND (p_booking_id IS NULL OR b.id = p_booking_id)
      AND pdc_fitter_private.assigned(b.id, v_uid)
  ) THEN
   RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'assignment_changed');
  END IF;
 ELSE
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'role_required');
 END IF;
 SELECT * INTO v_row FROM public.pdc_line_handoff_583
 WHERE vehicle_id = p_vehicle_id AND line_identity = p_line_identity;
 IF NOT FOUND THEN
  RETURN pg_catalog.jsonb_build_object('ok', true, 'code', 'unchanged', 'line_identity', p_line_identity);
 END IF;
 INSERT INTO public.pdc_line_handoff_history_583 (
  vehicle_id, line_identity, action, from_stage_code, to_stage_code, from_bay_id, to_bay_id,
  source_booking_id, actor_id, actor_email, actor_role, acted_at)
 VALUES (
  v_row.vehicle_id, v_row.line_identity, 'undo', v_row.from_stage_code, v_row.to_stage_code,
  v_row.from_bay_id, v_row.to_bay_id, coalesce(p_booking_id, v_row.source_booking_id),
  v_uid, v_email, v_role, v_now);
 DELETE FROM public.pdc_line_handoff_583
 WHERE vehicle_id = p_vehicle_id AND line_identity = p_line_identity;
 RETURN pg_catalog.jsonb_build_object(
  'ok', true, 'code', 'undone', 'vehicle_id', p_vehicle_id, 'line_identity', p_line_identity,
  'from_stage_code', v_row.from_stage_code, 'to_stage_code', v_row.to_stage_code,
  'actor_email', v_email, 'acted_at', v_now);
END
$undo583$;

REVOKE ALL ON FUNCTION public.undo_line_handoff_583(uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.undo_line_handoff_583(uuid, text, uuid) TO authenticated;

CREATE FUNCTION public.list_line_handoffs_583(p_vehicle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog
AS $list583$
DECLARE
 v_role text;
 v_lines jsonb;
BEGIN
 v_role := pg_catalog.lower(pg_catalog.btrim(coalesce(public.current_pdc_user_role()::text, '')));
 IF v_role NOT IN ('viewer','operator','administrator','importer','salesperson','fitter') THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'role_required');
 END IF;
 SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
  'vehicle_id', h.vehicle_id,
  'stock_number', v.stock_number,
  'key_number', v.key_number,
  'line_identity', h.line_identity,
  'description', CASE WHEN v.id IS NULL THEN NULL ELSE (
    SELECT l->>'description'
    FROM pg_catalog.jsonb_array_elements(coalesce(public.pdc_qc_operation_lines_379(h.vehicle_id), '[]'::jsonb)) l
    WHERE l->>'line_identity' = h.line_identity
    LIMIT 1
  ) END,
  'from_stage_code', h.from_stage_code,
  'to_stage_code', h.to_stage_code,
  'to_bay_id', h.to_bay_id,
  'to_bay_name', coalesce(nullif(pg_catalog.btrim(b.display_name), ''), CASE WHEN b.bay_number IS NULL THEN NULL ELSE 'Bay ' || pg_catalog.lpad(b.bay_number::text, 2, '0') END),
  'actor_email', h.actor_email,
  'actor_role', h.actor_role,
  'handed_at', h.handed_at,
  'booked', EXISTS (
    SELECT 1 FROM public.workshop_bookings wb
    JOIN public.workshop_stages s ON s.id = wb.stage_id
    WHERE wb.vehicle_id = h.vehicle_id AND wb.deleted_at IS NULL
      AND wb.status IN ('queued','planned','started','stoppage')
      AND s.code = h.to_stage_code
  )
 ) ORDER BY h.handed_at DESC, h.line_identity), '[]'::jsonb)
 INTO v_lines
 FROM (
  SELECT h.vehicle_id, h.line_identity, h.from_stage_code, h.to_stage_code, h.to_bay_id,
         h.actor_email, h.actor_role, h.handed_at
  FROM public.pdc_line_handoff_583 h
  WHERE (p_vehicle_id IS NULL OR h.vehicle_id = p_vehicle_id)
    AND (v_role <> 'fitter' OR EXISTS (
      SELECT 1 FROM public.workshop_bookings fb
      WHERE fb.vehicle_id = h.vehicle_id AND fb.deleted_at IS NULL
        AND pdc_fitter_private.assigned(fb.id, auth.uid())
    ))
  ORDER BY h.handed_at DESC, h.line_identity
  LIMIT 200
 ) h
 LEFT JOIN public.vehicles v ON v.id = h.vehicle_id
 LEFT JOIN public.workshop_bays b ON b.id = h.to_bay_id;
 RETURN pg_catalog.jsonb_build_object('ok', true, 'lines', v_lines);
END
$list583$;

REVOKE ALL ON FUNCTION public.list_line_handoffs_583(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_line_handoffs_583(uuid) TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('line_handoff_583', 'F197',
 'A handed-off operation line stays outstanding for the target department. It does not complete a station, it does not block the source bay once the fitter''s own lines are done, and the audit records who, when, from and to. Pin count stays 241. Department 135 is unchanged.',
$chk583$
SELECT
  pins.n = 241
  AND added.n = 0
  AND current_row.relrowsecurity
  AND history_row.relrowsecurity
  AND guard.present
  AND key_map.electrical
  AND key_map.fitting
  AND key_map.unknown
  AND sender.present
  AND sender.no_complete
  AND sender.no_vehicle_update
  AND sender.no_work_item
  AND sender.no_user_metadata
  AND sender.auth_exec
  AND sender.anon_blocked
  AND undoer.present
  AND lister.present
  AND lister.anon_blocked
  AND progress.present
  AND progress.keeps_outstanding
  AND progress.no_update
  AND station.remaps
  AND station.no_complete_write
  AND gate.allows
  AND frozen.same
  AND icon_check.patched
  AS ok,
  ('pins ' || pins.n::pg_catalog.text || ' | line handoff') AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r583') added
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_line_handoff_583'
) current_row
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_line_handoff_history_583'
) history_row
CROSS JOIN (
  SELECT count(*) = 1 AS present
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_proc p ON p.oid = t.tgfoid
  WHERE n.nspname = 'public' AND c.relname = 'pdc_line_handoff_history_583'
    AND t.tgname = 'pdc_line_handoff_history_583_guard' AND NOT t.tgisinternal
    AND pg_catalog.strpos(p.prosrc, 'append-only') > 0
) guard
CROSS JOIN (
  SELECT
    pdc_work_categories_private.line_handoff_work_key_583('ELECTRICAL') = 'electrical' AS electrical,
    pdc_work_categories_private.line_handoff_work_key_583('FITTING') = 'fitting' AS fitting,
    pdc_work_categories_private.line_handoff_work_key_583('NOPE') IS NULL AS unknown
) key_map
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'complete_workshop_work') = 0 AND pg_catalog.strpos(p.prosrc, 'operation_progress') = 0), false) AS no_complete,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'vehicle_work_items') = 0), false) AS no_work_item,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'user_metadata') = 0), false) AS no_user_metadata,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'handoff_operation_line_583'
) sender
CROSS JOIN (
  SELECT count(*) = 1 AS present
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'undo_line_handoff_583'
    AND pg_catalog.strpos(p.prosrc, 'undo') > 0
    AND pg_catalog.strpos(p.prosrc, 'user_metadata') = 0
) undoer
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'list_line_handoffs_583'
    AND pg_catalog.strpos(p.prosrc, 'booked') > 0
) lister
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'handed_away') > 0 AND pg_catalog.strpos(p.prosrc, 'can_complete') > 0), false) AS keeps_outstanding,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE') = 0 AND pg_catalog.strpos(p.prosrc, 'INSERT') = 0), false) AS no_update
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'line_handoff_progress_583'
) progress
CROSS JOIN (
  SELECT
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'pdc_line_handoff_583') > 0 AND pg_catalog.strpos(p.prosrc, 'line_handoff_work_key_583') > 0), false) AS remaps,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0 AND pg_catalog.strpos(p.prosrc, 'vehicle_work_items') = 0), false) AS no_complete_write
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('pdc_work_categories_private.station_icon_completion_578(uuid[])')
) station
CROSS JOIN (
  SELECT pg_catalog.strpos(p.prosrc, 'rpc/handoff_operation_line_583') > 0
     AND pg_catalog.strpos(p.prosrc, 'rpc/undo_line_handoff_583') > 0 AS allows
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_check_fitter_request()')
) gate
CROSS JOIN (
  SELECT
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff'
    AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = '626ca8b23a2e5f02e2ca8f96a4533d6f'
    AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_fitter_private.summary(jsonb,text)')) = 'c481664c82eb64487b1085edd67b9045'
    AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_fitter_private.lines(uuid,uuid)')) = '6773b7cf4e6bc040f14fc39548f77797'
    AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_fitter_private.progress(uuid)')) = '2eccf8ad296d2ae89f873d1eb5050ca5'
    AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.get_fitter_refresh(uuid,uuid,text)')) = '5491ec1c48e8d7f2e0f36bdfd18befe1'
    AS same
) frozen
CROSS JOIN (
  SELECT pg_catalog.strpos(c.check_sql, 'pdc_line_handoff_583') > 0 AS patched
  FROM pdc_ops.regression_checks c
  WHERE c.check_name = 'station_icon_completion_578' AND c.fault_id = 'F196' AND c.sort_order = 354 AND c.added_in = 'r578'
) icon_check
$chk583$, true, 355, 'r583');

DO $proof$
DECLARE
 v_id uuid := '00000000-0000-4000-8000-000000000583';
 v_lines jsonb;
 v_base jsonb;
 v_same jsonb;
 v_fit jsonb;
 v_elec jsonb;
 v_empty jsonb;
BEGIN
 v_lines := pg_catalog.jsonb_build_array(
  pg_catalog.jsonb_build_object('line_identity','source:poly-583','description','POLY WATER TANK WITH 12V PUMP','stage_code','FITTING','completed',false),
  pg_catalog.jsonb_build_object('line_identity','source:bar-583','description','STEEL BULL BAR','stage_code','FITTING','hours',1,'completed',true)
 );
 v_base := pdc_fitter_private.summary(v_lines, 'FITTING');
 v_same := pdc_work_categories_private.line_handoff_progress_583(v_id, 'FITTING', v_lines, v_base);
 IF v_same IS DISTINCT FROM v_base THEN RAISE EXCEPTION 'r583: empty handoff changed fitting progress'; END IF;
 IF coalesce((v_base->>'can_complete')::boolean, true) THEN RAISE EXCEPTION 'r583: sample fitting job was already completable'; END IF;
 INSERT INTO public.pdc_line_handoff_583 (vehicle_id, line_identity, from_stage_code, to_stage_code, actor_role)
 VALUES (v_id, 'source:poly-583', 'FITTING', 'ELECTRICAL', 'fitter');
 v_fit := pdc_work_categories_private.line_handoff_progress_583(v_id, 'FITTING', v_lines, v_base);
 v_elec := pdc_work_categories_private.line_handoff_progress_583(v_id, 'ELECTRICAL', v_lines, pdc_fitter_private.summary(v_lines, 'ELECTRICAL'));
 IF coalesce((v_fit->>'can_complete')::boolean, false) IS NOT TRUE THEN RAISE EXCEPTION 'r583: handed-off line still blocks the fitter'; END IF;
 IF coalesce((v_fit->>'handed_away')::integer, 0) <> 1 THEN RAISE EXCEPTION 'r583: handed-off line was not counted away'; END IF;
 IF coalesce((v_fit->>'total_lines')::integer, -1) <> 1 OR coalesce((v_fit->>'completed_lines')::integer, -1) <> 1 THEN RAISE EXCEPTION 'r583: fitting totals changed the wrong lines'; END IF;
 IF coalesce((v_elec->>'can_complete')::boolean, true) THEN RAISE EXCEPTION 'r583: target department treated the line as complete'; END IF;
 IF coalesce((v_elec->>'total_lines')::integer, 0) <> 1 OR coalesce((v_elec->>'completed_lines')::integer, 1) <> 0 THEN RAISE EXCEPTION 'r583: target department did not keep the line outstanding'; END IF;
 v_empty := pdc_work_categories_private.station_icon_completion_578(ARRAY[v_id]::uuid[]);
 IF v_empty IS DISTINCT FROM '[]'::jsonb THEN RAISE EXCEPTION 'r583: a handoff with no job line became a station'; END IF;
 DELETE FROM public.pdc_line_handoff_583 WHERE vehicle_id = v_id AND line_identity = 'source:poly-583';
 IF EXISTS (SELECT 1 FROM public.pdc_line_handoff_583 WHERE vehicle_id = v_id) THEN RAISE EXCEPTION 'r583: proof row remains'; END IF;
END $proof$;

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r583: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r583') THEN RAISE EXCEPTION 'r583: a pin was inserted'; END IF;
 IF (SELECT proacl::text FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.get_fitter_job(uuid,uuid)')) IS DISTINCT FROM current_setting('pdc.r583_job_acl') THEN RAISE EXCEPTION 'r583: get_fitter_job grants changed'; END IF;
 IF (SELECT proacl::text FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pdc_check_fitter_request()')) IS DISTINCT FROM current_setting('pdc.r583_gate_acl') THEN RAISE EXCEPTION 'r583: fitter gate grants changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('karratha135_pdc.get_fitter_refresh(uuid,uuid,text)')) IS DISTINCT FROM current_setting('pdc.r583_k135_refresh') THEN RAISE EXCEPTION 'r583: department 135 refresh changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r583: department 135 command changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r583: fitter command changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='line_handoff_583' AND fault_id='F197' AND sort_order=355 AND added_in='r583' AND enabled)<>1 THEN RAISE EXCEPTION 'r583: check missing'; END IF;
 IF pg_catalog.strpos((SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='station_icon_completion_578'), 'pdc_line_handoff_583') = 0 THEN RAISE EXCEPTION 'r583: station check was not patched'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name IN ('line_handoff_583','station_icon_completion_578') LOOP
  EXECUTE r.check_sql INTO probe;
  IF probe.ok IS NOT TRUE THEN RAISE EXCEPTION 'r583: % not ok: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;

NOTIFY pgrst, 'reload schema';
