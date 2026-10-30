-- r810 (F370) / sort 490. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 10:22 (Key 322, stock 13047122): "I still can't upload and confirm QC". Photo saved; Sign off stayed grey with
-- "Sublet is still required. The station icon is not green." Cause: the Sublet station icon counted a PIT AND WEIGH line filed
-- under Sublet. Pit lines are optional and never block anything (r401/r405), but station_icon_completion_578 never excluded them.
-- Craig 30 Oct 10:27: "fix it so when we tick sublet done it completes the PO attached to it" (on the board only).
-- This release:
--  1. station_icon_completion_578 skips pit lines (pdc_line_is_pit_401), so a pit line never holds a station icon red.
--     The 578 regression check recomputes the icon, so it gets the same one-line exclusion.
--  2. Ticking a line done (side panel / QC line tick, pdc_panel_line_completion_565 or pdc_qc_operation_completions_379) ticks
--     'sublet done' on every GP PO attached to that line (pdc_sublet_line_ticks_439), with a history row naming the person who
--     ticked the line. Unticking a line never reopens a PO. A PO already ticked is left alone.
--  3. Backfill: PO lines whose job line is already ticked done get the same PO tick, credited to whoever ticked the line.
-- Rollback: supabase/rollbacks/20261030110000_r810_pit_never_blocks_sublet_po_autotick.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $guard810$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r810: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r810: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r810: an import job is running'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 490 OR fault_id = 'F370' OR added_in = 'r810' OR check_name = 'sublet_po_autotick_810')
    THEN RAISE EXCEPTION 'r810: sort 490 or F370 is taken'; END IF;
  IF to_regprocedure('pdc_work_categories_private.sublet_po_autotick_810(uuid,text,uuid,text)') IS NOT NULL THEN RAISE EXCEPTION 'r810: already applied'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_work_categories_private.station_icon_completion_578(uuid[])'::regprocedure))
     IS DISTINCT FROM 'cf57cbb27020c460288ddf11b54c3478' THEN RAISE EXCEPTION 'r810: station_icon_completion_578 is not the expected body'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'station_icon_completion_578'
        AND (length(check_sql) - length(replace(check_sql, $s$AND l->>'line_identity' IS NOT NULL$s$, ''))) = length($s$AND l->>'line_identity' IS NOT NULL$s$)) <> 1
    THEN RAISE EXCEPTION 'r810: the 578 check is not the expected text'; END IF;
END $guard810$;

-- 1. Pit lines never count toward a station icon.
CREATE OR REPLACE FUNCTION pdc_work_categories_private.station_icon_completion_578(p_vehicle_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
   AND NOT public.pdc_line_is_pit_401(raw.vehicle_id, l) -- r810 (F370): pit lines are optional and never hold an icon red
), mapped AS (
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
$function$;

-- The 578 check recomputes the icon independently; it gets the same exclusion.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $s$AND l->>'line_identity' IS NOT NULL$s$,
  $s$AND l->>'line_identity' IS NOT NULL
      AND NOT public.pdc_line_is_pit_401(raw.vehicle_id, l)$s$)
WHERE check_name = 'station_icon_completion_578';

-- 2. A ticked job line ticks its GP PO(s) done. Never unticks.
CREATE FUNCTION pdc_work_categories_private.sublet_po_autotick_810(p_vehicle_id uuid, p_line_identity text, p_actor uuid, p_email text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE
  r record;
  v_n integer := 0;
  v_email text;
  v_actor uuid;
  v_role text;
  v_before public.pdc_sublet_line_ticks_439%ROWTYPE;
  v_after public.pdc_sublet_line_ticks_439%ROWTYPE;
  v_idem uuid;
  v_sha text;
  v_resp jsonb;
BEGIN
  -- r810 (F370): the line was ticked done, so every active GP PO on that line is marked sublet done on the board.
  IF p_vehicle_id IS NULL OR coalesce(p_line_identity, '') = '' THEN RETURN 0; END IF;
  v_actor := coalesce(p_actor, auth.uid());
  v_email := lower(btrim(coalesce(nullif(p_email, ''), (SELECT u.email FROM auth.users u WHERE u.id = v_actor), auth.jwt()->>'email', '')));
  IF v_actor IS NULL OR v_email = '' THEN
    SELECT u.id, lower(u.email) INTO v_actor, v_email
    FROM public.pdc_user_roles ur JOIN auth.users u ON lower(u.email) = ur.email
    WHERE ur.active AND ur.role::text = 'administrator' ORDER BY u.created_at LIMIT 1;
  END IF;
  IF v_actor IS NULL THEN RETURN 0; END IF;
  SELECT CASE WHEN ur.role::text IN ('administrator', 'fitter', 'sublet_provider') THEN ur.role::text ELSE 'operator' END
    INTO v_role FROM public.pdc_user_roles ur WHERE ur.email = v_email AND ur.active LIMIT 1;
  v_role := coalesce(v_role, 'operator');

  FOR r IN
    SELECT DISTINCT ON (ref.line_key) ref.line_key, ref.po_number
    FROM public.pdc_service_line_po_refs_439 ref
    WHERE ref.vehicle_id = p_vehicle_id AND ref.line_identity = p_line_identity AND ref.active
      AND NOT EXISTS (SELECT 1 FROM public.pdc_sublet_line_ticks_439 t
                      WHERE t.vehicle_id = ref.vehicle_id AND t.line_key = ref.line_key AND t.ticked)
    ORDER BY ref.line_key
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-439-line:' || p_vehicle_id::text || ':' || r.line_key, 0));
    SELECT * INTO v_before FROM public.pdc_sublet_line_ticks_439 WHERE vehicle_id = p_vehicle_id AND line_key = r.line_key FOR UPDATE;
    IF FOUND AND v_before.ticked THEN CONTINUE; END IF;
    INSERT INTO public.pdc_sublet_line_ticks_439 AS t (vehicle_id, line_key, line_identity, ticked, ticked_by, ticked_by_email, ticked_role,
      ticked_at, changed_by, changed_by_email, changed_role, version, updated_at)
    VALUES (p_vehicle_id, r.line_key, p_line_identity, true, v_actor, v_email, v_role, clock_timestamp(), v_actor, v_email, v_role, 1, clock_timestamp())
    ON CONFLICT (vehicle_id, line_key) DO UPDATE SET line_identity = excluded.line_identity, ticked = true, ticked_by = excluded.ticked_by,
      ticked_by_email = excluded.ticked_by_email, ticked_role = excluded.ticked_role, ticked_at = excluded.ticked_at,
      changed_by = excluded.changed_by, changed_by_email = excluded.changed_by_email, changed_role = excluded.changed_role,
      version = t.version + 1, updated_at = clock_timestamp()
    WHERE NOT t.ticked
    RETURNING * INTO v_after;
    IF NOT FOUND THEN CONTINUE; END IF;
    v_idem := gen_random_uuid();
    v_sha := encode(extensions.digest(convert_to(jsonb_build_object('contract', 'pdc-sublet-po-autotick-810', 'vehicle_id', p_vehicle_id,
      'line_key', r.line_key, 'line_identity', p_line_identity, 'idempotency_key', v_idem)::text, 'UTF8'), 'sha256'), 'hex');
    v_resp := jsonb_build_object('ok', true, 'code', 'sublet_po_autoticked_810', 'vehicle_id', p_vehicle_id, 'line_key', r.line_key,
      'po_number', r.po_number, 'ticked', true);
    INSERT INTO public.pdc_sublet_line_tick_history_439 (history_id, vehicle_id, line_key, line_identity, actor_id, actor_email, actor_role,
      idempotency_key, request_sha256, before_state, after_state, response, reason, created_at)
    VALUES (gen_random_uuid(), p_vehicle_id, r.line_key, p_line_identity, v_actor, v_email, v_role, v_idem, v_sha,
      CASE WHEN v_before.line_key IS NULL THEN NULL ELSE to_jsonb(v_before) END, to_jsonb(v_after), v_resp,
      'Job line ticked done, so its PO was marked sublet done (r810)', clock_timestamp());
    v_n := v_n + 1;
  END LOOP;
  IF v_n > 0 THEN
    UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;
  END IF;
  RETURN v_n;
END
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.sublet_po_autotick_810(uuid, text, uuid, text) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_work_categories_private.after_line_tick_po_810()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn$
BEGIN
  -- r810 (F370). A failure here never blocks the line tick itself.
  BEGIN
    IF TG_TABLE_NAME = 'pdc_panel_line_completion_565' THEN
      PERFORM pdc_work_categories_private.sublet_po_autotick_810(NEW.vehicle_id, NEW.line_identity, NEW.actor_id, NEW.actor_email);
    ELSE
      PERFORM pdc_work_categories_private.sublet_po_autotick_810(NEW.vehicle_id, NEW.line_identity, NEW.completed_by, NULL);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'r810: PO auto-tick skipped for % %: %', NEW.vehicle_id, NEW.line_identity, SQLERRM;
  END;
  RETURN NULL;
END
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.after_line_tick_po_810() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER zz_sublet_po_autotick_810 AFTER INSERT OR UPDATE OF completed ON public.pdc_panel_line_completion_565
  FOR EACH ROW WHEN (NEW.completed) EXECUTE FUNCTION pdc_work_categories_private.after_line_tick_po_810();
CREATE TRIGGER zz_sublet_po_autotick_810 AFTER INSERT OR UPDATE OF completed ON public.pdc_qc_operation_completions_379
  FOR EACH ROW WHEN (NEW.completed) EXECUTE FUNCTION pdc_work_categories_private.after_line_tick_po_810();

-- 3. Backfill: PO lines whose job line is already ticked done.
DO $backfill810$
DECLARE r record; v_total integer := 0;
BEGIN
  FOR r IN
    SELECT DISTINCT ON (ref.vehicle_id, ref.line_identity) ref.vehicle_id, ref.line_identity,
      coalesce(c.actor_id, q.completed_by) AS actor, c.actor_email
    FROM public.pdc_service_line_po_refs_439 ref
    JOIN public.vehicles v ON v.id = ref.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state::text = 'active'
    LEFT JOIN public.pdc_panel_line_completion_565 c ON c.vehicle_id = ref.vehicle_id AND c.line_identity = ref.line_identity AND c.completed
    LEFT JOIN public.pdc_qc_operation_completions_379 q ON q.vehicle_id = ref.vehicle_id AND q.line_identity = ref.line_identity AND q.completed
    WHERE ref.active AND (c.vehicle_id IS NOT NULL OR q.vehicle_id IS NOT NULL)
      AND NOT EXISTS (SELECT 1 FROM public.pdc_sublet_line_ticks_439 t WHERE t.vehicle_id = ref.vehicle_id AND t.line_key = ref.line_key AND t.ticked)
    ORDER BY ref.vehicle_id, ref.line_identity, c.acted_at DESC NULLS LAST
  LOOP
    v_total := v_total + pdc_work_categories_private.sublet_po_autotick_810(r.vehicle_id, r.line_identity, r.actor, r.actor_email);
  END LOOP;
  RAISE NOTICE 'r810: backfilled % PO line tick(s)', v_total;
END $backfill810$;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('sublet_po_autotick_810', 'F370',
  'Pit lines never hold a station icon red, and a job line ticked done has every active GP PO on it marked sublet done on the board.',
  $chk$
SELECT
  icon.pit_skipped AND trig.n = 2 AND gap.n = 0 AS ok,
  ('po gaps ' || gap.n::pg_catalog.text || ' | triggers ' || trig.n::pg_catalog.text || ' | pit never blocks an icon') AS detail
FROM (
  SELECT pg_catalog.strpos(p.prosrc, 'pdc_line_is_pit_401') > 0 AS pit_skipped
  FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_work_categories_private.station_icon_completion_578(uuid[])')
) icon
CROSS JOIN (
  SELECT count(*) AS n FROM pg_catalog.pg_trigger t WHERE t.tgname = 'zz_sublet_po_autotick_810' AND NOT t.tgisinternal
) trig
CROSS JOIN (
  SELECT count(*) AS n
  FROM public.pdc_service_line_po_refs_439 ref
  JOIN public.vehicles v ON v.id = ref.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state::text = 'active'
  WHERE ref.active
    AND EXISTS (SELECT 1 FROM public.pdc_panel_line_completion_565 c WHERE c.vehicle_id = ref.vehicle_id AND c.line_identity = ref.line_identity AND c.completed)
    AND NOT EXISTS (SELECT 1 FROM public.pdc_sublet_line_ticks_439 t WHERE t.vehicle_id = ref.vehicle_id AND t.line_key = ref.line_key)
) gap
$chk$, true, 490, 'r810');

UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;
