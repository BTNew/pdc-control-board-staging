-- r803 (F418): Craig 1 Nov 2026 17:48 AWST (13008249, key 238): "this one is showing a ETA for parts into the future, i should be
-- able to unclick parts complete and make it red?" The CW parts import said all parts attached (green), so the r747 tick showed
-- ticked and locked, and a warranty part with a 30/11 ETA could not be shown as outstanding.
-- Now: unticking Parts complete over a green import marks the parts outstanding on the board (red, "Parts outstanding - marked on
-- the board") until someone ticks Parts complete again. Over a non-green import, untick just shows the import again (as before).
-- A confirmation email still wins and stays locked. The import evidence is never changed.
DO $r803$
DECLARE
  sig regprocedure := 'public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure;
  v_old text; v_new text; v_def text; v_con text;
  a1 text := E' IF NOT FOUND THEN RETURN imported; END IF;\n';
  b1 text := E' IF NOT FOUND THEN\n -- r803 (F418): Parts complete unticked over a green import: parts outstanding, red.\n'
          || E' SELECT o.set_at, o.set_by_actor INTO b.set_at, b.set_by_actor FROM public.pdc_parts_board_outstanding_803 o WHERE o.vehicle_id=p_vehicle_id AND o.active;\n'
          || E' IF NOT FOUND THEN RETURN imported; END IF;\n'
          || E' mark:=jsonb_build_object(''colour'',''red'',''label'',''Parts outstanding — marked on the board'',''parts_complete'',false,\n'
          || E' ''override_source'',''board_parts_outstanding'',''person_confirmed'',true,\n'
          || E' ''confirmed_at'',b.set_at,''confirmed_by'',b.set_by_actor,''confirmed_by_name'',b.set_by_actor,''job_label'',''Parts marked outstanding on the board'',\n'
          || E' ''meaning'',''Parts complete was unticked on the board. Parts are outstanding until it is ticked again; original import evidence is retained.'');\n'
          || E' ELSE\n';
  a2 text := E' END IF;\n RETURN coalesce(imported';
  b2 text := E' END IF;\n END IF;\n RETURN coalesce(imported';
  a3 text := $q$'job_label','A person confirmed parts complete for this vehicle'$q$;
  b3 text := $q$'job_label',coalesce(mark->>'job_label','A person confirmed parts complete for this vehicle')$q$;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 583 OR fault_id = 'F418' OR added_in = 'r803') THEN RAISE EXCEPTION 'r803: sort 583 or F418 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r803: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> 'e4968d61d34b3be0e32acb400c69d479' THEN RAISE EXCEPTION 'r803: parts flags is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1
     OR (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1
     OR (length(v_old) - length(replace(v_old, a3, ''))) / length(a3) <> 1 THEN RAISE EXCEPTION 'r803: anchor not found once'; END IF;

  CREATE TABLE public.pdc_parts_board_outstanding_803 (
    vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
    active boolean NOT NULL DEFAULT true,
    set_by uuid,
    set_by_actor text NOT NULL,
    set_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    cleared_by_actor text,
    cleared_at timestamptz
  );
  ALTER TABLE public.pdc_parts_board_outstanding_803 ENABLE ROW LEVEL SECURITY;
  REVOKE ALL ON public.pdc_parts_board_outstanding_803 FROM PUBLIC, anon, authenticated;

  SELECT conname INTO v_con FROM pg_constraint WHERE conrelid = 'public.pdc_parts_board_complete_history_747'::regclass AND contype = 'c';
  EXECUTE format('ALTER TABLE public.pdc_parts_board_complete_history_747 DROP CONSTRAINT %I', v_con);
  ALTER TABLE public.pdc_parts_board_complete_history_747 ADD CONSTRAINT pdc_parts_board_complete_history_747_action_check
    CHECK (action IN ('complete', 'undo', 'outstanding'));

  v_new := replace(replace(replace(v_old, a1, b1), a2, b2), a3, b3);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r803: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
END $r803$;

CREATE OR REPLACE FUNCTION public.set_pdc_parts_board_complete_747(p_vehicle_id uuid, p_complete boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE
  v_role text := public.current_pdc_user_role()::text;
  v_uid uuid := auth.uid();
  v_actor text := coalesce(nullif(btrim(coalesce(auth.jwt()->>'email', '')), ''), v_uid::text, 'unknown');
  v_want boolean := coalesce(p_complete, false);
  v_row public.pdc_parts_board_complete_747%ROWTYPE;
  v_out boolean := false;
  v_changed boolean := false;
BEGIN
  -- r747 (F353): the side-panel Parts complete tick. r803 (F418): unticking over a green import marks parts outstanding (red).
  IF to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'staging_only');
  END IF;
  IF v_role IS DISTINCT FROM 'importer' AND v_role IS DISTINCT FROM 'operator' AND v_role IS DISTINCT FROM 'administrator' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
  END IF;
  IF p_vehicle_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.vehicles v WHERE v.id = p_vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found');
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc_parts_board_complete_747:' || p_vehicle_id::text, 0));
  SELECT * INTO v_row FROM public.pdc_parts_board_complete_747 WHERE vehicle_id = p_vehicle_id FOR UPDATE;

  IF v_want THEN
    UPDATE public.pdc_parts_board_outstanding_803 SET active = false, cleared_by_actor = v_actor, cleared_at = clock_timestamp()
    WHERE vehicle_id = p_vehicle_id AND active;
    v_changed := FOUND;
    IF NOT coalesce(v_row.active, false) THEN
      INSERT INTO public.pdc_parts_board_complete_747 AS t (vehicle_id, active, set_by, set_by_actor, set_at)
      VALUES (p_vehicle_id, true, v_uid, v_actor, clock_timestamp())
      ON CONFLICT (vehicle_id) DO UPDATE SET active = true, set_by = v_uid, set_by_actor = v_actor, set_at = clock_timestamp(),
        cleared_by_actor = NULL, cleared_at = NULL
      WHERE t.vehicle_id = excluded.vehicle_id
      RETURNING * INTO v_row;
      INSERT INTO public.pdc_parts_board_complete_history_747 (vehicle_id, action, actor, actor_email) VALUES (p_vehicle_id, 'complete', v_uid, v_actor);
      v_changed := true;
    END IF;
  ELSE
    IF coalesce(v_row.active, false) THEN
      UPDATE public.pdc_parts_board_complete_747 SET active = false, cleared_by_actor = v_actor, cleared_at = clock_timestamp()
      WHERE vehicle_id = p_vehicle_id;
      INSERT INTO public.pdc_parts_board_complete_history_747 (vehicle_id, action, actor, actor_email) VALUES (p_vehicle_id, 'undo', v_uid, v_actor);
      v_changed := true;
    END IF;
    -- A green import (no confirmation email) would show complete again: mark the parts outstanding instead.
    IF coalesce(public.pdc_imported_parts_flags_vehicle_20260912(p_vehicle_id)->>'colour', '') = 'green'
       AND NOT EXISTS (SELECT 1 FROM public.pdc_parts_completion_email_confirmations c WHERE c.vehicle_id = p_vehicle_id AND c.active) THEN
      v_out := true;
      IF NOT EXISTS (SELECT 1 FROM public.pdc_parts_board_outstanding_803 o WHERE o.vehicle_id = p_vehicle_id AND o.active) THEN
        INSERT INTO public.pdc_parts_board_outstanding_803 AS t (vehicle_id, active, set_by, set_by_actor, set_at)
        VALUES (p_vehicle_id, true, v_uid, v_actor, clock_timestamp())
        ON CONFLICT (vehicle_id) DO UPDATE SET active = true, set_by = v_uid, set_by_actor = v_actor, set_at = clock_timestamp(),
          cleared_by_actor = NULL, cleared_at = NULL
        WHERE t.vehicle_id = excluded.vehicle_id;
        INSERT INTO public.pdc_parts_board_complete_history_747 (vehicle_id, action, actor, actor_email) VALUES (p_vehicle_id, 'outstanding', v_uid, v_actor);
        v_changed := true;
      END IF;
    END IF;
  END IF;
  IF v_changed THEN
    -- The Vehicle Locations snapshot is cached per revision; the next read shows the new colour.
    UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;
  END IF;
  RETURN jsonb_build_object('ok', true, 'changed', v_changed, 'complete', v_want, 'outstanding', v_out, 'vehicle_id', p_vehicle_id,
    'set_by_actor', v_actor, 'set_at', clock_timestamp());
END
$fn$;
REVOKE ALL ON FUNCTION public.set_pdc_parts_board_complete_747(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_parts_board_complete_747(uuid, boolean) TO authenticated;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('parts_outstanding_untick_803', 'F418',
  'Parts (r803): unticking Parts complete over a green import marks the parts outstanding (red) until ticked again; ticking clears it.',
  $chk$
SELECT strpos(f.src, 'board_parts_outstanding') > 0 AND strpos(f.src, 'pdc_parts_board_outstanding_803') > 0
   AND strpos(s.src, 'pdc_parts_board_outstanding_803') > 0 AND strpos(s.src, 'not_authorized') > 0
   AND NOT has_table_privilege('authenticated', 'public.pdc_parts_board_outstanding_803', 'SELECT')
   AND NOT has_function_privilege('anon', 'public.set_pdc_parts_board_complete_747(uuid,boolean)', 'EXECUTE') AS ok,
 'parts outstanding untick reads red and is guarded' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.pdc_parts_flags_vehicle_20260911(uuid)')) f,
     (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.set_pdc_parts_board_complete_747(uuid,boolean)')) s
$chk$, true, 583, 'r803');
