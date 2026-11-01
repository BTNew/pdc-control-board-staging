-- r802 (F417): Craig 1 Nov 2026 12:04 AWST. "noones working today ... why is it showing me theres alot of changings and new vehicles
-- to the board etc... Shouldnt it just tell me whats changing?"
-- 1. Seven cars were back on the board (visible, active) with a stale board_purged_at from an earlier archive. The importer refuses a
--    purged car (historical_identity_requires_restore), so their service lines were frozen and every preview showed them as new.
--    Fix the seven, and clear board_purged_at whenever a car comes back onto the board.
-- 2. CW parts and BT / KTA deal-items dry runs compare each RO / stock with the rows of the last good apply of that report.
DO $r802$
DECLARE
  n int;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order IN (581, 582) OR fault_id = 'F417' OR added_in = 'r802') THEN RAISE EXCEPTION 'r802: sort 581/582 or F417 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r802: an import job is running'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.other_uploads_781 WHERE status NOT IN ('done', 'failed')) THEN RAISE EXCEPTION 'r802: an upload is running'; END IF;

  CREATE OR REPLACE FUNCTION public.vehicles_back_on_board_unpurge_802()
  RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'public' AS $f$
  BEGIN
    -- r802 (F417): a car that comes back onto the board is not purged any more.
    IF NEW.board_purged_at IS NOT NULL AND NEW.visible_on_board IS TRUE AND NEW.deleted_at IS NULL
       AND NEW.lifecycle_state::text = 'active' AND OLD.visible_on_board IS NOT TRUE THEN
      NEW.board_purged_at := NULL; NEW.board_purge_reason := NULL; NEW.board_purged_by := NULL;
    END IF;
    RETURN NEW;
  END $f$;
  REVOKE ALL ON FUNCTION public.vehicles_back_on_board_unpurge_802() FROM PUBLIC, anon, authenticated;
  CREATE TRIGGER vehicles_back_on_board_unpurge_802 BEFORE UPDATE OF visible_on_board ON public.vehicles
    FOR EACH ROW EXECUTE FUNCTION public.vehicles_back_on_board_unpurge_802();

  UPDATE public.vehicles SET board_purged_at = NULL, board_purge_reason = NULL, board_purged_by = NULL,
         version = version + 1, updated_at = clock_timestamp()
  WHERE deleted_at IS NULL AND board_purged_at IS NOT NULL AND visible_on_board IS TRUE AND lifecycle_state::text = 'active';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 7 THEN RAISE EXCEPTION 'r802: expected at most 7 cars, found %', n; END IF;

  CREATE OR REPLACE FUNCTION public.revolution_upload_other_delta_802(p_kind text, p_rows jsonb)
  RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path TO 'pg_catalog', 'public' SET statement_timeout TO '30s' AS $f$
  DECLARE
    v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, '')));
    v_kind text := lower(btrim(coalesce(p_kind, '')));
    v_key text;
    v_last record;
    v_out jsonb;
  BEGIN
    -- r802 (F417): which ROs (CW parts) or stocks (deal items) differ from the last good apply of the same report. Read only.
    IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
    IF v_kind NOT IN ('cw_parts', 'bt_deal_items', 'kta_deal_items') OR jsonb_typeof(p_rows) <> 'array' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'bad_input');
    END IF;
    v_key := CASE WHEN v_kind = 'cw_parts' THEN 'R/O #' ELSE 'Stock #' END;
    SELECT u.rows, u.result, u.created_at INTO v_last FROM pdc_import_620.other_uploads_781 u
    WHERE u.kind = v_kind AND u.status = 'done' AND (u.result->>'ok') = 'true' AND jsonb_typeof(u.rows) = 'array'
    ORDER BY u.created_at DESC LIMIT 1;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', true, 'since', NULL, 'unchanged', '[]'::jsonb, 'changed', '[]'::jsonb, 'first_time', '[]'::jsonb, 'skipped_last', '[]'::jsonb); END IF;
    WITH cur AS (
      SELECT upper(btrim(r->>v_key)) k, md5(string_agg((r - 'row' - 'source_row_numbers')::text, '|' ORDER BY (r - 'row' - 'source_row_numbers')::text)) h
      FROM jsonb_array_elements(p_rows) r WHERE nullif(btrim(r->>v_key), '') IS NOT NULL GROUP BY 1
    ), prev AS (
      SELECT upper(btrim(r->>v_key)) k, md5(string_agg((r - 'row' - 'source_row_numbers')::text, '|' ORDER BY (r - 'row' - 'source_row_numbers')::text)) h
      FROM jsonb_array_elements(v_last.rows) r WHERE nullif(btrim(r->>v_key), '') IS NOT NULL GROUP BY 1
    )
    SELECT jsonb_build_object(
      'unchanged', coalesce(jsonb_agg(c.k ORDER BY c.k) FILTER (WHERE p.h = c.h), '[]'::jsonb),
      'changed', coalesce(jsonb_agg(c.k ORDER BY c.k) FILTER (WHERE p.h IS NOT NULL AND p.h <> c.h), '[]'::jsonb),
      'first_time', coalesce(jsonb_agg(c.k ORDER BY c.k) FILTER (WHERE p.h IS NULL), '[]'::jsonb))
    INTO v_out FROM cur c LEFT JOIN prev p ON p.k = c.k;
    RETURN jsonb_build_object('ok', true, 'since', v_last.created_at,
      'skipped_last', coalesce((SELECT jsonb_agg(DISTINCT upper(btrim(s->>'stock'))) FROM jsonb_array_elements(coalesce(v_last.result->'result'->'unmatched_stocks', '[]'::jsonb)) s), '[]'::jsonb))
      || coalesce(v_out, '{}'::jsonb);
  END $f$;
  REVOKE ALL ON FUNCTION public.revolution_upload_other_delta_802(text, jsonb) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.revolution_upload_other_delta_802(text, jsonb) TO authenticated;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('board_car_not_purged_802', 'F417',
    'Upload (r802): no car on the board (visible, active) carries a stale board_purged_at, so the importer never freezes its lines.',
    $chk$
SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'vehicles_back_on_board_unpurge_802' AND tgrelid = 'public.vehicles'::regclass AND tgenabled <> 'D')
   AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.board_purged_at IS NOT NULL AND v.visible_on_board IS TRUE AND v.lifecycle_state::text = 'active')
 AS ok, 'board cars are not purged' AS detail
$chk$, true, 581, 'r802'),
  ('other_upload_delta_802', 'F417',
    'Upload (r802): CW parts and deal-items previews compare with the last good apply (admin-only, read-only RPC).',
    $chk$
SELECT to_regprocedure('public.revolution_upload_other_delta_802(text,jsonb)') IS NOT NULL
   AND (SELECT p.prosecdef AND p.provolatile = 's' FROM pg_proc p WHERE p.oid = to_regprocedure('public.revolution_upload_other_delta_802(text,jsonb)'))
   AND NOT has_function_privilege('anon', 'public.revolution_upload_other_delta_802(text,jsonb)', 'EXECUTE')
 AS ok, 'other-upload delta present' AS detail
$chk$, true, 582, 'r802');
  RAISE NOTICE 'r802: % board cars un-purged', n;
END $r802$;
