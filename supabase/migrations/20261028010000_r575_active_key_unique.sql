-- r575 (F189) / sort 346. PREVIEW. Do not apply while active board vehicles share a key.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
--
-- Craig, 27 Oct 2026 13:25 AWST: no two vehicles may have the same key number.
-- The two stocks that looked the same are not a duplicate. Read 27 Oct 2026 on
-- staging: 13008249 is key 238 and 13070395 is key 415. Both sit at location IT
-- because Navision says OD / Despatched - From TWA. Both have date_to_pmb
-- 6 Oct 2026 and live fitting work, so they are physically at PMB. That
-- location mismatch is a separate finding. This release does not clear a key
-- because the board location is IT, QC, Other, or PMB.
--
-- The same read found 10 keys on two active board vehicles each:
--   105  13073068 and 13070896
--   126  13073094 and 13070891
--   144  13092054 and 13070886
--   146  13073086 and 13070887
--   214  13019220 and 13047384
--   320  13072026 and 13070889
--   338  IS60353006 and 13041213
--   348  13073074 and 13070897
--   349  13073075 and 13073090
--   414  IS60069640 and 13018221
-- The old rule only refused a key when both vehicles were at location PMB.
-- A service import never clears a key when a vehicle leaves the sheet, so the
-- off-sheet holder keeps a stale key. Five of those stale holders are dealer
-- 14450 vehicles still on the PMB board: 13070896, 13070886, 13070887,
-- 13070889, 13070897. 13070891 is also 14450 and is still on the sheet (126).
-- #544's archive of the 91 had not committed on this read (last board_purged_at
-- 19 Oct 2026, zero r569 purge reasons). Archive alone would take the off-sheet
-- holders out of the active set. 126, 214 and 338 would remain, because both
-- stocks are on the sheet. 214 is the staff double-up: Craig put 214 on
-- 13047384 at 09:40 AWST while 13019220, at QC, already had the file key 214.
-- This file does not choose a keeper and does not update a vehicle row.
--
-- Active board means: not deleted, not archived, visible, lifecycle active,
-- a department 138 or 139 service row, and no department 135 row. Blank and
-- all-zero keys are not keys. The token is the r460 form: trimmed, spaces
-- removed, upper case.
--
-- On archive or leave (board_purged_at, deleted_at, or lifecycle leaving
-- active) a vehicle that is not the current Broome 37047 / Karratha 14450
-- Navision record stores the old key and the column is cleared. Un-archive
-- puts that key back only when it is still free. If it is taken, the vehicle
-- returns without a key and the reason is stored. A sales-linked vehicle keeps
-- the column, so the Broome and Karratha sales screens do not go blank. Once
-- archived it leaves the unique set. Putting it back onto the board while
-- another active vehicle has that key raises the plain sentence and the
-- un-archive rolls back. Hiding a vehicle without archiving it keeps the key
-- and drops it from the unique set. Showing it again into a clash raises the
-- same sentence.
--
-- A service import applies the file key before it archives the old holder.
-- If the off-sheet vehicle is still active, the import stops with the plain
-- sentence and the archive in that same import does not commit. That is the
-- rule. Archive the old holder first, or clear the stale key, then import.
--
-- Staff see "Key 214 is already on stock 13047384", never SQLSTATE 23505.
-- The key editor and the vehicle-detail save return that sentence as
-- key_number_in_use. Every other writer, including the service import, hits
-- the trigger. Department 135 is not edited. Broome 37047 and Karratha 14450
-- sales functions are not edited. The as-a-Whole key fill and the archive
-- function are not edited. Pin count stays 241. The apply pin moves in place.
--
-- Release ledger when this file was written:
--   Staging head is pmb_dept_ack_book_574, F188, sort 345, added_in r574
--   (ledger 20261027054124, open preview #556).
--   origin/main parent of that is hours_description_fits_573, F187, sort 344.
--   r571 / F185 / sort 343 stays unused for #559.
--   Next free triple is r575 / F189 / sort 346.
-- Undo: supabase/rollbacks/20261028010000_r575_active_key_unique.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$
BEGIN
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r575: run between :02 and :45 (release-test window; the clock tick runs at :00)';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r575: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
    RAISE EXCEPTION 'r575: pin count is not 241';
  END IF;
  IF pg_catalog.to_regnamespace('pdc_key_number_private') IS NULL THEN
    RAISE EXCEPTION 'r575: key schema is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pdc_ops.regression_checks
    WHERE check_name = 'hours_description_fits_573' AND fault_id = 'F187' AND sort_order = 344 AND added_in = 'r573'
  ) THEN RAISE EXCEPTION 'r575: r573 / F187 sort 344 is not present'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pdc_ops.regression_checks
    WHERE check_name = 'pmb_dept_ack_book_574' AND fault_id = 'F188' AND sort_order = 345 AND added_in = 'r574'
  ) THEN RAISE EXCEPTION 'r575: parent r574 / F188 sort 345 is not applied'; END IF;
  IF EXISTS (
    SELECT 1 FROM pdc_ops.regression_checks
    WHERE sort_order = 346 OR fault_id = 'F189' OR check_name = 'active_key_unique_575' OR added_in = 'r575'
  ) THEN RAISE EXCEPTION 'r575: sort 346 or F189 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'))
     IS DISTINCT FROM '8e46bf785c2118d58a8cebf2bd1888d1' THEN
    RAISE EXCEPTION 'r575: apply_key_number_460 is not the r460 body';
  END IF;
  IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5
      WHERE signature = 'pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)')
     IS DISTINCT FROM '8e46bf785c2118d58a8cebf2bd1888d1' THEN
    RAISE EXCEPTION 'r575: apply_key_number_460 pin is not the r460 md5';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM 'eabd64cea227ce91a1f3005569c16439' THEN
    RAISE EXCEPTION 'r575: public vehicle detail body changed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pdc_ops.expected_function_md5
    WHERE signature = 'public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'
  ) THEN RAISE EXCEPTION 'r575: public vehicle detail is pinned'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM '69decdbde44cf15f481ff7ba6e1bcfbd' THEN
    RAISE EXCEPTION 'r575: department 135 vehicle detail changed';
  END IF;
  PERFORM 1
  FROM public.vehicles v
  WHERE v.deleted_at IS NULL
    AND v.board_purged_at IS NULL
    AND v.visible_on_board
    AND v.lifecycle_state::text = 'active'
    AND EXISTS (
      SELECT 1 FROM public.pdc_pilbara_service_operations o
      WHERE o.vehicle_id = v.id AND o.department IN ('138', '139')
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.pdc_pilbara_service_operations o
      WHERE o.vehicle_id = v.id AND o.department = '135'
    )
  FOR UPDATE;
END $g$;

CREATE FUNCTION pdc_key_number_private.key_token_575(p_key text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO pg_catalog
AS $fn$
  SELECT CASE WHEN t IS NULL OR t ~ '^0+$' THEN NULL ELSE t END
  FROM (
    SELECT nullif(upper(regexp_replace(btrim(coalesce(p_key, '')), '\s+', '', 'g')), '') AS t
  ) s;
$fn$;

CREATE FUNCTION pdc_key_number_private.board_scope_575(
  p_id uuid,
  p_deleted timestamp with time zone,
  p_purged timestamp with time zone,
  p_visible boolean,
  p_life text
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $fn$
  SELECT p_id IS NOT NULL
    AND p_deleted IS NULL
    AND p_purged IS NULL
    AND coalesce(p_visible, false)
    AND p_life = 'active'
    AND EXISTS (
      SELECT 1 FROM public.pdc_pilbara_service_operations o
      WHERE o.vehicle_id = p_id AND o.department IN ('138', '139')
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.pdc_pilbara_service_operations o
      WHERE o.vehicle_id = p_id AND o.department = '135'
    );
$fn$;

CREATE FUNCTION pdc_key_number_private.sales_key_holder_575(p_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.navision_backend_records n
    WHERE n.canonical_vehicle_id = p_id
      AND n.source_system = 'microsoft_navision'
      AND n.is_current
      AND n.record_status::text = 'current'
      AND n.dealer_code IN ('37047', '037047', '14450', '014450')
  );
$fn$;

CREATE FUNCTION pdc_key_number_private.key_clash_message_575(p_vehicle uuid, p_key text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $fn$
DECLARE
  v_token text := pdc_key_number_private.key_token_575(p_key);
  v_stock text;
BEGIN
  IF v_token IS NULL OR p_vehicle IS NULL THEN RETURN NULL; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.vehicles v
    WHERE v.id = p_vehicle
      AND pdc_key_number_private.board_scope_575(v.id, v.deleted_at, v.board_purged_at, v.visible_on_board, v.lifecycle_state::text)
  ) THEN RETURN NULL; END IF;
  SELECT coalesce(nullif(btrim(v.stock_number), ''), '(no stock)')
    INTO v_stock
  FROM public.vehicles v
  WHERE v.id <> p_vehicle
    AND pdc_key_number_private.board_scope_575(v.id, v.deleted_at, v.board_purged_at, v.visible_on_board, v.lifecycle_state::text)
    AND pdc_key_number_private.key_token_575(v.key_number) = v_token
  ORDER BY v.stock_number
  LIMIT 1;
  IF v_stock IS NULL THEN RETURN NULL; END IF;
  RETURN 'Key ' || v_token || ' is already on stock ' || v_stock;
END
$fn$;

REVOKE ALL ON FUNCTION pdc_key_number_private.key_token_575(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_key_number_private.board_scope_575(uuid, timestamp with time zone, timestamp with time zone, boolean, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_key_number_private.sales_key_holder_575(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_key_number_private.key_clash_message_575(uuid, text) FROM PUBLIC, anon, authenticated, service_role;

DO $refuse$
DECLARE
  v_list text;
BEGIN
  SELECT string_agg('Key ' || d.token || ' is on ' || d.stocks, '; ' ORDER BY d.token)
    INTO v_list
  FROM (
    SELECT pdc_key_number_private.key_token_575(v.key_number) AS token,
           string_agg(coalesce(nullif(btrim(v.stock_number), ''), '(no stock)'), ' and ' ORDER BY v.stock_number) AS stocks
    FROM public.vehicles v
    WHERE pdc_key_number_private.board_scope_575(v.id, v.deleted_at, v.board_purged_at, v.visible_on_board, v.lifecycle_state::text)
    GROUP BY 1
    HAVING count(*) > 1
  ) d
  WHERE d.token IS NOT NULL;
  IF v_list IS NOT NULL THEN
    RAISE EXCEPTION 'r575: active board vehicles still share a key. Fix the data first. %', v_list;
  END IF;
END $refuse$;

CREATE TABLE pdc_key_number_private.active_key_575 (
  token text PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  stock_number text,
  CONSTRAINT active_key_575_vehicle UNIQUE (vehicle_id)
);
CREATE TABLE pdc_key_number_private.key_release_575 (
  release_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL,
  token text NOT NULL,
  stock_number text,
  reason text NOT NULL,
  released_at timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  restored_at timestamp with time zone,
  note text,
  CONSTRAINT key_release_575_reason CHECK (reason IN ('archive', 'leave', 'not_restored'))
);
ALTER TABLE pdc_key_number_private.active_key_575 ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_key_number_private.key_release_575 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_key_number_private.active_key_575 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE pdc_key_number_private.key_release_575 FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION pdc_key_number_private.guard_active_key_575()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $fn$
DECLARE
  v_old_active boolean := false;
  v_new_active boolean;
  v_token text;
  v_held text;
  v_other text;
  v_sales boolean;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    v_old_active := pdc_key_number_private.board_scope_575(OLD.id, OLD.deleted_at, OLD.board_purged_at, OLD.visible_on_board, OLD.lifecycle_state::text);
  END IF;
  v_new_active := pdc_key_number_private.board_scope_575(NEW.id, NEW.deleted_at, NEW.board_purged_at, NEW.visible_on_board, NEW.lifecycle_state::text);
  v_sales := pdc_key_number_private.sales_key_holder_575(NEW.id);
  v_token := pdc_key_number_private.key_token_575(NEW.key_number);
  IF TG_OP = 'UPDATE' AND v_old_active AND NOT v_new_active
     AND v_token IS NOT NULL AND NOT v_sales
     AND (NEW.board_purged_at IS NOT NULL OR NEW.deleted_at IS NOT NULL OR NEW.lifecycle_state::text IS DISTINCT FROM 'active') THEN
    INSERT INTO pdc_key_number_private.key_release_575(vehicle_id, token, stock_number, reason)
    VALUES (NEW.id, v_token, NEW.stock_number,
      CASE WHEN NEW.board_purged_at IS NOT NULL AND OLD.board_purged_at IS NULL THEN 'archive' ELSE 'leave' END);
    NEW.key_number := NULL;
    v_token := NULL;
  END IF;
  IF v_new_active AND NOT v_old_active AND v_token IS NULL AND NOT v_sales THEN
    SELECT r.token INTO v_held
    FROM pdc_key_number_private.key_release_575 r
    WHERE r.vehicle_id = NEW.id AND r.restored_at IS NULL AND r.reason IN ('archive', 'leave')
    ORDER BY r.released_at DESC
    LIMIT 1;
    IF v_held IS NOT NULL THEN
      PERFORM pg_advisory_xact_lock(hashtextextended('pdc-575-key:' || v_held, 0));
      IF EXISTS (
        SELECT 1 FROM pdc_key_number_private.active_key_575 a
        WHERE a.token = v_held AND a.vehicle_id <> NEW.id
      ) OR EXISTS (
        SELECT 1 FROM public.vehicles v
        WHERE v.id <> NEW.id
          AND pdc_key_number_private.board_scope_575(v.id, v.deleted_at, v.board_purged_at, v.visible_on_board, v.lifecycle_state::text)
          AND pdc_key_number_private.key_token_575(v.key_number) = v_held
      ) THEN
        INSERT INTO pdc_key_number_private.key_release_575(vehicle_id, token, stock_number, reason, note)
        VALUES (NEW.id, v_held, NEW.stock_number, 'not_restored',
          'Key ' || v_held || ' was already on another active board vehicle, so it was not put back.');
        UPDATE pdc_key_number_private.key_release_575
           SET restored_at = clock_timestamp()
         WHERE vehicle_id = NEW.id AND token = v_held AND restored_at IS NULL AND reason IN ('archive', 'leave');
      ELSE
        NEW.key_number := v_held;
        v_token := v_held;
        UPDATE pdc_key_number_private.key_release_575
           SET restored_at = clock_timestamp()
         WHERE vehicle_id = NEW.id AND token = v_held AND restored_at IS NULL AND reason IN ('archive', 'leave');
      END IF;
    END IF;
  END IF;
  IF v_new_active AND v_token IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('pdc-575-key:' || v_token, 0));
    SELECT coalesce(nullif(btrim(v.stock_number), ''), '(no stock)') INTO v_other
    FROM public.vehicles v
    WHERE v.id <> NEW.id
      AND pdc_key_number_private.board_scope_575(v.id, v.deleted_at, v.board_purged_at, v.visible_on_board, v.lifecycle_state::text)
      AND pdc_key_number_private.key_token_575(v.key_number) = v_token
    ORDER BY v.stock_number
    LIMIT 1;
    IF v_other IS NULL THEN
      SELECT coalesce(nullif(btrim(a.stock_number), ''), '(no stock)') INTO v_other
      FROM pdc_key_number_private.active_key_575 a
      WHERE a.token = v_token AND a.vehicle_id <> NEW.id;
    END IF;
    IF v_other IS NOT NULL THEN
      RAISE EXCEPTION 'Key % is already on stock %', v_token, v_other USING ERRCODE = 'P0001';
    END IF;
  END IF;
  DELETE FROM pdc_key_number_private.active_key_575 WHERE vehicle_id = NEW.id;
  IF v_new_active AND v_token IS NOT NULL THEN
    BEGIN
      INSERT INTO pdc_key_number_private.active_key_575(token, vehicle_id, stock_number)
      VALUES (v_token, NEW.id, NEW.stock_number);
    EXCEPTION WHEN unique_violation THEN
      SELECT coalesce(nullif(btrim(stock_number), ''), '(no stock)') INTO v_other
      FROM pdc_key_number_private.active_key_575 WHERE token = v_token;
      RAISE EXCEPTION 'Key % is already on stock %', v_token, coalesce(v_other, '(no stock)') USING ERRCODE = 'P0001';
    END;
  END IF;
  RETURN NEW;
END
$fn$;

CREATE FUNCTION pdc_key_number_private.drop_active_key_575()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $fn$
DECLARE
  v_token text := pdc_key_number_private.key_token_575(OLD.key_number);
BEGIN
  IF v_token IS NOT NULL
     AND NOT pdc_key_number_private.sales_key_holder_575(OLD.id)
     AND pdc_key_number_private.board_scope_575(OLD.id, OLD.deleted_at, OLD.board_purged_at, OLD.visible_on_board, OLD.lifecycle_state::text) THEN
    INSERT INTO pdc_key_number_private.key_release_575(vehicle_id, token, stock_number, reason)
    VALUES (OLD.id, v_token, OLD.stock_number, 'leave');
  END IF;
  DELETE FROM pdc_key_number_private.active_key_575 WHERE vehicle_id = OLD.id;
  RETURN OLD;
END
$fn$;

REVOKE ALL ON FUNCTION pdc_key_number_private.guard_active_key_575() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_key_number_private.drop_active_key_575() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER zzz_pdc_active_key_575
  BEFORE INSERT OR UPDATE OF key_number, visible_on_board, board_purged_at, deleted_at, lifecycle_state
  ON public.vehicles
  FOR EACH ROW
  EXECUTE FUNCTION pdc_key_number_private.guard_active_key_575();

CREATE TRIGGER zzz_pdc_active_key_575_del
  AFTER DELETE ON public.vehicles
  FOR EACH ROW
  EXECUTE FUNCTION pdc_key_number_private.drop_active_key_575();

INSERT INTO pdc_key_number_private.active_key_575(token, vehicle_id, stock_number)
SELECT pdc_key_number_private.key_token_575(v.key_number), v.id, v.stock_number
FROM public.vehicles v
WHERE pdc_key_number_private.board_scope_575(v.id, v.deleted_at, v.board_purged_at, v.visible_on_board, v.lifecycle_state::text)
  AND pdc_key_number_private.key_token_575(v.key_number) IS NOT NULL;

DO $apply$
DECLARE
  def text;
  old text := $old$ IF v_key IS NOT NULL THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-388-key:'||v_key,0));
  IF upper(btrim(coalesce(v_before.current_location,'')))='PMB' AND EXISTS(SELECT 1 FROM public.vehicles x WHERE x.id<>v_before.id AND x.deleted_at IS NULL
     AND x.lifecycle_state='active' AND upper(btrim(coalesce(x.current_location,'')))='PMB' AND upper(btrim(coalesce(x.key_number,'')))=v_key) THEN
   RETURN jsonb_build_object('ok',false,'code','key_number_in_use','message','Another active PMB vehicle already has this key tag.');
  END IF;$old$;
  new text := $new$ IF v_key IS NOT NULL THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-388-key:'||v_key,0));
  IF pdc_key_number_private.key_clash_message_575(v_before.id, v_key) IS NOT NULL THEN
   RETURN jsonb_build_object('ok',false,'code','key_number_in_use','message',pdc_key_number_private.key_clash_message_575(v_before.id, v_key));
  END IF;$new$;
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'))
     IS DISTINCT FROM '8e46bf785c2118d58a8cebf2bd1888d1' THEN
    RAISE EXCEPTION 'r575: apply_key_number_460 changed before the patch';
  END IF;
  def := pg_get_functiondef(pg_catalog.to_regprocedure('pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'));
  IF length(old) = 0 OR (length(def) - length(replace(def, old, ''))) / length(old) <> 1 THEN
    RAISE EXCEPTION 'r575: apply key gate was not found once';
  END IF;
  EXECUTE replace(def, old, new);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'))
     IS DISTINCT FROM '59b676f8a7efac59876e0d36a61730a0' THEN
    RAISE EXCEPTION 'r575: apply_key_number_460 md5 is not 59b676f8a7efac59876e0d36a61730a0';
  END IF;
  UPDATE pdc_ops.expected_function_md5
     SET prosrc_md5 = '59b676f8a7efac59876e0d36a61730a0',
         release = 'r575',
         note = 'r575 (F189): an active board key names the other stock (was 8e46bf785c2118d58a8cebf2bd1888d1)',
         updated_at = clock_timestamp()
   WHERE signature = 'pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'
     AND prosrc_md5 = '8e46bf785c2118d58a8cebf2bd1888d1';
  IF NOT FOUND THEN RAISE EXCEPTION 'r575: apply_key_number_460 pin was not updated in place'; END IF;
END $apply$;

DO $detail$
DECLARE
  def text;
  old text := $old$       IF EXISTS(SELECT 1 FROM public.vehicles x WHERE x.id<>v_before.id AND x.deleted_at IS NULL AND x.lifecycle_state='active' AND upper(btrim(coalesce(x.current_location,'')))='PMB' AND upper(btrim(coalesce(x.key_number,'')))=v_key) THEN
         RETURN jsonb_build_object('ok',false,'code','key_number_in_use');
       END IF;$old$;
  new text := $new$       IF pdc_key_number_private.key_clash_message_575(v_before.id, v_key) IS NOT NULL THEN
         RETURN jsonb_build_object('ok',false,'code','key_number_in_use','message',pdc_key_number_private.key_clash_message_575(v_before.id, v_key));
       END IF;$new$;
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM 'eabd64cea227ce91a1f3005569c16439' THEN
    RAISE EXCEPTION 'r575: vehicle detail changed before the patch';
  END IF;
  def := pg_get_functiondef(pg_catalog.to_regprocedure('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'));
  IF length(old) = 0 OR (length(def) - length(replace(def, old, ''))) / length(old) <> 1 THEN
    RAISE EXCEPTION 'r575: vehicle detail key gate was not found once';
  END IF;
  EXECUTE replace(def, old, new);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM '747aedfaa0ea8f109f7a7d9c6d625327' THEN
    RAISE EXCEPTION 'r575: vehicle detail md5 is not 747aedfaa0ea8f109f7a7d9c6d625327';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM '69decdbde44cf15f481ff7ba6e1bcfbd' THEN
    RAISE EXCEPTION 'r575: department 135 vehicle detail changed during the patch';
  END IF;
END $detail$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES (
  'active_key_unique_575',
  'F189',
  'r575: one active department 138/139 board vehicle per key. Archived, hidden, deleted and department 135 vehicles are outside the set. A clash is the plain sentence, not 23505. Leaving the board stores a non-sales key and clears it. Pin count stays 241.',
$chk575$
SELECT
  dup.n = 0
  AND pins.n = 241
  AND apply.md5 = '59b676f8a7efac59876e0d36a61730a0'
  AND apply.pin = '59b676f8a7efac59876e0d36a61730a0'
  AND apply.release = 'r575'
  AND pg_catalog.strpos(apply.prosrc, 'key_clash_message_575') > 0
  AND pg_catalog.strpos(apply.prosrc, 'Another active PMB vehicle already has this key tag.') = 0
  AND detail.md5 = '747aedfaa0ea8f109f7a7d9c6d625327'
  AND pg_catalog.strpos(detail.prosrc, 'key_clash_message_575') > 0
  AND pg_catalog.strpos(detail.prosrc, 'key_not_editable_outside_pmb') > 0
  AND k135.md5 = '69decdbde44cf15f481ff7ba6e1bcfbd'
  AND NOT EXISTS (
    SELECT 1 FROM pdc_ops.expected_function_md5 e
    WHERE e.signature = 'public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'
  )
  AND pg_catalog.to_regclass('pdc_key_number_private.active_key_575') IS NOT NULL
  AND pg_catalog.to_regclass('pdc_key_number_private.key_release_575') IS NOT NULL
  AND guard.prosecdef
  AND pg_catalog.strpos(guard.prosrc, 'Key % is already on stock %') > 0
  AND pg_catalog.strpos(guard.prosrc, 'P0001') > 0
  AND pg_catalog.strpos(guard.prosrc, 'unique_violation') > 0
  AND pg_catalog.strpos(guard.prosrc, 'not_restored') > 0
  AND shadow.bad = 0
  AS ok,
  'duplicates ' || dup.n::text || ' ' || coalesce(nullif(dup.keys, ''), '(none)')
    || ' apply ' || apply.md5 AS detail
FROM (
  SELECT count(*)::integer AS n,
         coalesce(string_agg(d.token, ', ' ORDER BY d.token), '') AS keys
  FROM (
    SELECT pdc_key_number_private.key_token_575(v.key_number) AS token
    FROM public.vehicles v
    WHERE pdc_key_number_private.board_scope_575(v.id, v.deleted_at, v.board_purged_at, v.visible_on_board, v.lifecycle_state::text)
    GROUP BY 1
    HAVING count(*) > 1
  ) d
  WHERE d.token IS NOT NULL
) dup
CROSS JOIN (SELECT count(*)::integer AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (
  SELECT p.prosrc, md5(p.prosrc) AS md5, pin.prosrc_md5 AS pin, pin.release
  FROM pg_catalog.pg_proc p
  JOIN pdc_ops.expected_function_md5 pin
    ON pin.signature = 'pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'
  WHERE p.oid = pg_catalog.to_regprocedure('pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)')
) apply
CROSS JOIN (
  SELECT p.prosrc, md5(p.prosrc) AS md5
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)')
) detail
CROSS JOIN (
  SELECT md5(p.prosrc) AS md5
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)')
) k135
CROSS JOIN (
  SELECT p.prosrc, p.prosecdef
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('pdc_key_number_private.guard_active_key_575()')
) guard
CROSS JOIN (
  SELECT count(*)::integer AS bad
  FROM (
    SELECT token FROM pdc_key_number_private.active_key_575 GROUP BY token HAVING count(*) > 1
  ) s
) shadow
$chk575$,
  true,
  346,
  'r575'
);

DO $post$
DECLARE
  r record;
  probe record;
BEGIN
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
    RAISE EXCEPTION 'r575: pin count changed';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release = 'r575') <> 1 THEN
    RAISE EXCEPTION 'r575: pin release count is not 1';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks
      WHERE check_name = 'active_key_unique_575' AND fault_id = 'F189' AND sort_order = 346 AND added_in = 'r575' AND enabled) <> 1 THEN
    RAISE EXCEPTION 'r575: check missing';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM '69decdbde44cf15f481ff7ba6e1bcfbd' THEN
    RAISE EXCEPTION 'r575: department 135 vehicle detail changed';
  END IF;
  PERFORM set_config('search_path', 'pg_catalog', true);
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name = 'active_key_unique_575' LOOP
    EXECUTE r.check_sql INTO probe;
    IF coalesce(probe.ok, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'r575: % failed: %', r.check_name, probe.detail;
    END IF;
  END LOOP;
END $post$;
