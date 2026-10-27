-- r578 (F192) / sort 350. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
--
-- Live before this apply: sort 347 is cross_station_drop_576 (r576 / F190).
-- sort 348 is electrical_bays_7_566 (r566 / F180). sort 349 is
-- bay_manager_hours_570 (r577 / F191), taken while this preview was open.
-- This release is r578 / F192 / sort 350. pdc_ops.fault_regression_check() runs the row below.
--
-- The side-panel tick (r565) stores who ticked a line. The station icon reads
-- vehicle_work_items.completed only, so a ticked Tint line stays Required.
-- This release adds one read: a station is complete when every active line of
-- that station is done (QC flag, panel tick, or the latest fitter Done), or a
-- workshop controller has overridden the station. It does not update a vehicle,
-- a work item, a booking, or a job card. Status 80 and the QC line function
-- stay as they are. Department 135 stays as it is. Pin count stays 241.
-- Controllers are operator and administrator. The JWT user_metadata claim is not read.
-- Undo: supabase/rollbacks/20261028010000_r578_station_icon_completion.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r578: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r578: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r578: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='cross_station_drop_576' AND fault_id='F190' AND sort_order=347 AND added_in='r576') THEN RAISE EXCEPTION 'r578: r576 / F190 sort 347 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='electrical_bays_7_566' AND fault_id='F180' AND sort_order=348 AND added_in='r566') THEN RAISE EXCEPTION 'r578: r566 / F180 sort 348 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_manager_hours_570' AND fault_id='F191' AND sort_order=349 AND added_in='r577') THEN RAISE EXCEPTION 'r578: r577 / F191 sort 349 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=350 OR fault_id='F192' OR check_name='station_icon_completion_578' OR added_in='r578') THEN RAISE EXCEPTION 'r578: sort 350 or F192 is taken'; END IF;
 IF pg_catalog.to_regclass('public.pdc_station_completion_override_578') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_station_completion_history_578') IS NOT NULL THEN RAISE EXCEPTION 'r578: already applied'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r578: department 135 changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r578: fitter command changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_codex_intake_private.apply_service_pmb_complete(uuid)'))
    IS DISTINCT FROM '9808feb2a0a93a79b0d67aebdca0a4aa' THEN RAISE EXCEPTION 'r578: status 80 changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_qc_operation_lines_379(uuid)'))
    IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r578: QC lines changed'; END IF;
END $g$;

CREATE TABLE public.pdc_station_completion_override_578 (
 vehicle_id uuid NOT NULL,
 work_key text NOT NULL,
 completed boolean NOT NULL,
 actor_id uuid,
 actor_email text,
 actor_role text,
 acted_at timestamptz,
 version integer NOT NULL DEFAULT 1,
 PRIMARY KEY (vehicle_id, work_key),
 CONSTRAINT pdc_station_completion_override_578_key CHECK (work_key IN ('parts', 'tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet')),
 CONSTRAINT pdc_station_completion_override_578_role CHECK (actor_role IS NULL OR actor_role IN ('operator', 'administrator')),
 CONSTRAINT pdc_station_completion_override_578_version CHECK (version > 0)
);
ALTER TABLE public.pdc_station_completion_override_578 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_station_completion_override_578 FROM PUBLIC, anon, authenticated;

CREATE TABLE public.pdc_station_completion_history_578 (
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vehicle_id uuid NOT NULL,
 work_key text NOT NULL,
 completed boolean NOT NULL,
 actor_id uuid,
 actor_email text,
 actor_role text,
 acted_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_station_completion_history_578 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_station_completion_history_578 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.pdc_station_completion_history_guard_578()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $guard578$
BEGIN
 RAISE EXCEPTION 'pdc_station_completion_history_578 is append-only';
END
$guard578$;

CREATE TRIGGER pdc_station_completion_history_578_guard
BEFORE UPDATE OR DELETE ON public.pdc_station_completion_history_578
FOR EACH ROW EXECUTE FUNCTION public.pdc_station_completion_history_guard_578();

REVOKE ALL ON FUNCTION public.pdc_station_completion_history_guard_578() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_work_categories_private.station_icon_completion_578(p_vehicle_ids uuid[])
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $fn578$
WITH ids AS (
 SELECT DISTINCT id
 FROM pg_catalog.unnest(coalesce(p_vehicle_ids, '{}'::uuid[])) AS id
 WHERE id IS NOT NULL
 LIMIT 1000
), raw AS (
 SELECT ids.id AS vehicle_id, l
 FROM ids
 CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(coalesce(public.pdc_qc_operation_lines_379(ids.id), '[]'::jsonb)) l
), known AS (
 SELECT vehicle_id,
  l->>'line_identity' AS line_identity,
  CASE pg_catalog.upper(pg_catalog.btrim(coalesce(l->>'stage_code', '')))
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
  END AS work_key,
  coalesce((l->>'completed')::boolean, false) AS qc_done
 FROM raw
 WHERE coalesce((l->>'active')::boolean, true)
   AND coalesce((l->>'rejected')::boolean, false) = false
   AND l->>'line_identity' IS NOT NULL
), uniq AS (
 SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
 FROM known
 WHERE work_key IS NOT NULL
 GROUP BY vehicle_id, work_key, line_identity
), panel AS (
 SELECT c.vehicle_id, c.line_identity, c.completed
 FROM public.pdc_panel_line_completion_565 c
 JOIN ids ON ids.id = c.vehicle_id
), fitter AS (
 SELECT DISTINCT ON (wb.vehicle_id, p.line_identity)
  wb.vehicle_id, p.line_identity, p.completed
 FROM pdc_fitter_private.operation_progress p
 JOIN public.workshop_bookings wb ON wb.id = p.booking_id
 JOIN ids ON ids.id = wb.vehicle_id
 WHERE wb.deleted_at IS NULL
 ORDER BY wb.vehicle_id, p.line_identity, p.updated_at DESC, p.booking_id
), tallied AS (
 SELECT u.vehicle_id, u.work_key,
  count(*) AS total,
  count(*) FILTER (WHERE u.qc_done OR coalesce(panel.completed, false) OR coalesce(fitter.completed, false)) AS done
 FROM uniq u
 LEFT JOIN panel ON panel.vehicle_id = u.vehicle_id AND panel.line_identity = u.line_identity
 LEFT JOIN fitter ON fitter.vehicle_id = u.vehicle_id AND fitter.line_identity = u.line_identity
 GROUP BY u.vehicle_id, u.work_key
), ovr AS (
 SELECT o.vehicle_id, o.work_key, o.completed, o.actor_email, o.acted_at
 FROM public.pdc_station_completion_override_578 o
 JOIN ids ON ids.id = o.vehicle_id
)
SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 'vehicle_id', coalesce(t.vehicle_id, o.vehicle_id),
 'work_key', coalesce(t.work_key, o.work_key),
 'complete', coalesce(o.completed, false) OR (coalesce(t.total, 0) > 0 AND coalesce(t.done, 0) = coalesce(t.total, 0)),
 'total', coalesce(t.total, 0),
 'done', coalesce(t.done, 0),
 'override', coalesce(o.completed, false),
 'override_email', o.actor_email,
 'acted_at', o.acted_at
) ORDER BY coalesce(t.vehicle_id, o.vehicle_id), coalesce(t.work_key, o.work_key)), '[]'::jsonb)
FROM tallied t
FULL OUTER JOIN ovr o ON o.vehicle_id = t.vehicle_id AND o.work_key = t.work_key
WHERE coalesce(t.total, 0) > 0 OR o.vehicle_id IS NOT NULL
$fn578$;

REVOKE ALL ON FUNCTION pdc_work_categories_private.station_icon_completion_578(uuid[]) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.list_station_icon_completion_578(p_vehicle_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $list578$
DECLARE
 v_role text;
 v_ids uuid[];
BEGIN
 v_role := pg_catalog.lower(pg_catalog.btrim(coalesce(public.current_pdc_user_role()::text, '')));
 IF v_role NOT IN ('viewer', 'operator', 'importer', 'administrator', 'fitter', 'salesperson') THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'role_required');
 END IF;
 v_ids := ARRAY(
  SELECT DISTINCT id
  FROM pg_catalog.unnest(coalesce(p_vehicle_ids, '{}'::uuid[])) AS id
  WHERE id IS NOT NULL
  LIMIT 1000
 );
 IF coalesce(pg_catalog.cardinality(v_ids), 0) = 0 THEN
  RETURN pg_catalog.jsonb_build_object('ok', true, 'stations', '[]'::jsonb);
 END IF;
 RETURN pg_catalog.jsonb_build_object('ok', true, 'stations', pdc_work_categories_private.station_icon_completion_578(v_ids));
END
$list578$;

REVOKE ALL ON FUNCTION public.list_station_icon_completion_578(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_station_icon_completion_578(uuid[]) TO authenticated;

CREATE FUNCTION public.set_station_completion_override_578(p_vehicle_id uuid, p_work_key text, p_completed boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $set578$
DECLARE
 v_role text;
 v_email text;
 v_uid uuid;
 v_now timestamptz;
 v_prev boolean;
 v_version integer;
BEGIN
 v_role := pg_catalog.lower(pg_catalog.btrim(coalesce(public.current_pdc_user_role()::text, '')));
 IF v_role NOT IN ('operator', 'administrator') THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'controller_required');
 END IF;
 IF p_vehicle_id IS NULL OR p_completed IS NULL
    OR p_work_key IS NULL
    OR p_work_key NOT IN ('parts', 'tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet') THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'invalid_station');
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.vehicles WHERE id = p_vehicle_id) THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'vehicle_not_found');
 END IF;
 v_uid := auth.uid();
 v_email := public.current_actor_email();
 v_now := pg_catalog.clock_timestamp();
 SELECT completed, version INTO v_prev, v_version
 FROM public.pdc_station_completion_override_578
 WHERE vehicle_id = p_vehicle_id AND work_key = p_work_key;
 IF FOUND AND v_prev IS NOT DISTINCT FROM p_completed THEN
  RETURN pg_catalog.jsonb_build_object('ok', true, 'code', 'unchanged', 'work_key', p_work_key, 'completed', p_completed, 'actor_email', v_email, 'acted_at', v_now);
 END IF;
 INSERT INTO public.pdc_station_completion_history_578 (vehicle_id, work_key, completed, actor_id, actor_email, actor_role, acted_at)
 VALUES (p_vehicle_id, p_work_key, p_completed, v_uid, v_email, v_role, v_now);
 INSERT INTO public.pdc_station_completion_override_578 (vehicle_id, work_key, completed, actor_id, actor_email, actor_role, acted_at, version)
 VALUES (p_vehicle_id, p_work_key, p_completed, v_uid, v_email, v_role, v_now, 1)
 ON CONFLICT (vehicle_id, work_key) DO UPDATE
 SET completed = EXCLUDED.completed,
     actor_id = EXCLUDED.actor_id,
     actor_email = EXCLUDED.actor_email,
     actor_role = EXCLUDED.actor_role,
     acted_at = EXCLUDED.acted_at,
     version = public.pdc_station_completion_override_578.version + 1
 WHERE public.pdc_station_completion_override_578.vehicle_id = EXCLUDED.vehicle_id
   AND public.pdc_station_completion_override_578.work_key = EXCLUDED.work_key;
 RETURN pg_catalog.jsonb_build_object(
  'ok', true, 'code', 'saved', 'work_key', p_work_key, 'completed', p_completed,
  'actor_email', v_email, 'actor_role', v_role, 'acted_at', v_now, 'version', coalesce(v_version, 0) + 1);
END
$set578$;

REVOKE ALL ON FUNCTION public.set_station_completion_override_578(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_station_completion_override_578(uuid, text, boolean) TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('station_icon_completion_578', 'F192',
 'A station icon is complete exactly when every active line of that station is done, or a workshop controller has overridden it. Partial lines stay incomplete. The pin count stays 241. The override does not rewrite a vehicle.',
 $chk578$
SELECT
  pins.n = 241
  AND added.n = 0
  AND current_row.relrowsecurity
  AND history_row.relrowsecurity
  AND guard.present
  AND setter.present
  AND setter.controller
  AND setter.no_vehicle_update
  AND setter.no_work_item
  AND setter.no_booking
  AND setter.no_job_close
  AND setter.no_user_metadata
  AND setter.auth_exec
  AND setter.anon_blocked
  AND reader.present
  AND reader.reads_sales
  AND reader.auth_exec
  AND reader.anon_blocked
  AND frozen.same
  AND sample.n <= 1000
  AND mismatch.n = 0
  AS ok,
  ('pins ' || pins.n::pg_catalog.text || ' | sample ' || sample.n::pg_catalog.text || ' | mismatches ' || mismatch.n::pg_catalog.text || ' | station icon completion') AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r578') added
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_station_completion_override_578'
) current_row
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_station_completion_history_578'
) history_row
CROSS JOIN (
  SELECT count(*) = 1 AS present
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_proc p ON p.oid = t.tgfoid
  WHERE n.nspname = 'public' AND c.relname = 'pdc_station_completion_history_578'
    AND t.tgname = 'pdc_station_completion_history_578_guard' AND NOT t.tgisinternal
    AND pg_catalog.strpos(p.prosrc, 'append-only') > 0
) guard
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'controller_required') > 0 AND pg_catalog.strpos(p.prosrc, 'operator') > 0 AND pg_catalog.strpos(p.prosrc, 'administrator') > 0), false) AS controller,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'vehicle_work_items') = 0), false) AS no_work_item,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'workshop_bookings') = 0), false) AS no_booking,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'complete_workshop_work') = 0), false) AS no_job_close,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'user_metadata') = 0), false) AS no_user_metadata,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'set_station_completion_override_578'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid, p_work_key text, p_completed boolean'
) setter
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'salesperson') > 0 AND pg_catalog.strpos(p.prosrc, 'fitter') > 0), false) AS reads_sales,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'list_station_icon_completion_578'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_ids uuid[]'
) reader
CROSS JOIN (
  SELECT
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff'
    AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = '626ca8b23a2e5f02e2ca8f96a4533d6f'
    AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.apply_service_pmb_complete(uuid)')) = '9808feb2a0a93a79b0d67aebdca0a4aa'
    AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) = 'b7f90bff12643229ff80f8ca552663a2'
    AS same
) frozen
CROSS JOIN (
  SELECT count(*) AS n FROM (
    SELECT vehicle_id FROM public.pdc_panel_line_completion_565
    UNION
    SELECT vehicle_id FROM public.pdc_station_completion_override_578
  ) u
) sample
CROSS JOIN (
  WITH ids AS (
    SELECT id FROM (
      SELECT vehicle_id AS id FROM public.pdc_panel_line_completion_565
      UNION
      SELECT vehicle_id FROM public.pdc_station_completion_override_578
    ) u
    WHERE id IS NOT NULL
    LIMIT 1000
  ), raw AS (
    SELECT ids.id AS vehicle_id, l
    FROM ids
    CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(coalesce(public.pdc_qc_operation_lines_379(ids.id), '[]'::jsonb)) l
  ), known AS (
    SELECT vehicle_id,
     l->>'line_identity' AS line_identity,
     CASE pg_catalog.upper(pg_catalog.btrim(coalesce(l->>'stage_code', '')))
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
     END AS work_key,
     coalesce((l->>'completed')::boolean, false) AS qc_done
    FROM raw
    WHERE coalesce((l->>'active')::boolean, true)
      AND coalesce((l->>'rejected')::boolean, false) = false
      AND l->>'line_identity' IS NOT NULL
  ), uniq AS (
    SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
    FROM known
    WHERE work_key IS NOT NULL
    GROUP BY vehicle_id, work_key, line_identity
  ), panel AS (
    SELECT c.vehicle_id, c.line_identity, c.completed
    FROM public.pdc_panel_line_completion_565 c
    JOIN ids ON ids.id = c.vehicle_id
  ), fitter AS (
    SELECT DISTINCT ON (wb.vehicle_id, p.line_identity)
     wb.vehicle_id, p.line_identity, p.completed
    FROM pdc_fitter_private.operation_progress p
    JOIN public.workshop_bookings wb ON wb.id = p.booking_id
    JOIN ids ON ids.id = wb.vehicle_id
    WHERE wb.deleted_at IS NULL
    ORDER BY wb.vehicle_id, p.line_identity, p.updated_at DESC, p.booking_id
  ), tallied AS (
    SELECT u.vehicle_id, u.work_key,
     count(*) AS total,
     count(*) FILTER (WHERE u.qc_done OR coalesce(panel.completed, false) OR coalesce(fitter.completed, false)) AS done
    FROM uniq u
    LEFT JOIN panel ON panel.vehicle_id = u.vehicle_id AND panel.line_identity = u.line_identity
    LEFT JOIN fitter ON fitter.vehicle_id = u.vehicle_id AND fitter.line_identity = u.line_identity
    GROUP BY u.vehicle_id, u.work_key
  ), ovr AS (
    SELECT o.vehicle_id, o.work_key, o.completed
    FROM public.pdc_station_completion_override_578 o
    JOIN ids ON ids.id = o.vehicle_id
  ), expected AS (
    SELECT coalesce(t.vehicle_id, o.vehicle_id) AS vehicle_id,
     coalesce(t.work_key, o.work_key) AS work_key,
     (coalesce(o.completed, false) OR (coalesce(t.total, 0) > 0 AND coalesce(t.done, 0) = coalesce(t.total, 0))) AS complete
    FROM tallied t
    FULL OUTER JOIN ovr o ON o.vehicle_id = t.vehicle_id AND o.work_key = t.work_key
    WHERE coalesce(t.total, 0) > 0 OR o.vehicle_id IS NOT NULL
  ), actual AS (
    SELECT r.vehicle_id, r.work_key, r.complete
    FROM pg_catalog.jsonb_to_recordset(pdc_work_categories_private.station_icon_completion_578(coalesce((SELECT pg_catalog.array_agg(id) FROM ids), '{}'::uuid[])))
      AS r(vehicle_id uuid, work_key text, complete boolean)
  )
  SELECT count(*) AS n
  FROM expected e
  FULL OUTER JOIN actual a ON a.vehicle_id = e.vehicle_id AND a.work_key = e.work_key
  WHERE a.complete IS DISTINCT FROM e.complete
) mismatch
$chk578$, true, 350, 'r578');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r578: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r578') THEN RAISE EXCEPTION 'r578: a pin was inserted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='station_icon_completion_578' AND fault_id='F192' AND sort_order=350 AND added_in='r578' AND enabled)<>1 THEN RAISE EXCEPTION 'r578: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='station_icon_completion_578' LOOP
  EXECUTE r.check_sql INTO probe;
  IF probe.ok IS NOT TRUE THEN RAISE EXCEPTION 'r578: check not ok: %', probe.detail; END IF;
 END LOOP;
END $post$;
