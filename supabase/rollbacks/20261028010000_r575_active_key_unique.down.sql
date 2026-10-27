-- Undo r575 (F189) / sort 346. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Drops the active-board trigger first, then puts each approved_clear key back
-- onto that same vehicle id. The stock must still match and the key must still
-- be empty. If that id already has a key, this stops and does not overwrite it.
-- Archive and leave history is dropped with the undo and is not put back, so a
-- later un-archive cannot restore those. Puts the PMB-only key gate back on the
-- key editor and the vehicle-detail save, drops the shadow key and the release
-- history, and removes active_key_unique_575. Department 135 is not edited.
-- Pin count stays 241. The apply pin moves back in place.

SET LOCAL lock_timeout = '2s';
DO $g$
BEGIN
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r575 down: run between :02 and :45 (release-test window; the clock tick runs at :00)';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r575 down: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
    RAISE EXCEPTION 'r575 down: pin count is not 241';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'))
     IS DISTINCT FROM '59b676f8a7efac59876e0d36a61730a0' THEN
    RAISE EXCEPTION 'r575 down: apply_key_number_460 is not the r575 body';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM '747aedfaa0ea8f109f7a7d9c6d625327' THEN
    RAISE EXCEPTION 'r575 down: vehicle detail is not the r575 body';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM '69decdbde44cf15f481ff7ba6e1bcfbd' THEN
    RAISE EXCEPTION 'r575 down: department 135 vehicle detail changed';
  END IF;
END $g$;

DROP TRIGGER IF EXISTS zzz_pdc_active_key_575 ON public.vehicles;
DROP TRIGGER IF EXISTS zzz_pdc_active_key_575_del ON public.vehicles;

-- The unique trigger is gone, so writing the key back is not blocked.
-- Only Craig's approved clears, and only the ten named ids.
DO $restore$
DECLARE
  r record;
  v_vehicle public.vehicles%rowtype;
BEGIN
  IF pg_catalog.to_regclass('pdc_key_number_private.key_release_575') IS NULL THEN
    RAISE EXCEPTION 'r575 down: key history is missing. Nothing was put back.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pdc_key_number_private.key_release_575
    WHERE reason = 'approved_clear'
      AND restored_at IS NULL
      AND vehicle_id NOT IN (
        'ca02d68f-6d53-4519-9678-f2b31ca7e3a1'::uuid,
        '835f365f-17fc-4f56-908c-27963f276da0'::uuid,
        '1c1ca4f0-7ed2-4194-8376-e7aacc4a5e77'::uuid,
        '861cac9d-087d-466b-86c3-4c95d86dce2c'::uuid,
        'd602c80a-8511-4359-8931-67d87facd0f2'::uuid,
        '057eb94c-2433-45c1-8a61-a841da0b1e29'::uuid,
        '84502339-d4fd-4e2a-beee-1a504672978c'::uuid,
        '1b18c826-e226-43e9-b4a0-6079c55853cc'::uuid,
        '3e3eb9b0-89d2-4778-bb73-d06cf2bb0ad0'::uuid,
        '6da9c8e1-9c9f-4fea-992e-57cc991f4d5f'::uuid
      )
  ) THEN
    RAISE EXCEPTION 'r575 down: an approved clear is not one of the ten holders. Nothing was put back.';
  END IF;
  FOR r IN
    SELECT release_id, vehicle_id, token, stock_number
    FROM pdc_key_number_private.key_release_575
    WHERE reason = 'approved_clear'
      AND restored_at IS NULL
      AND vehicle_id IN (
        'ca02d68f-6d53-4519-9678-f2b31ca7e3a1'::uuid,
        '835f365f-17fc-4f56-908c-27963f276da0'::uuid,
        '1c1ca4f0-7ed2-4194-8376-e7aacc4a5e77'::uuid,
        '861cac9d-087d-466b-86c3-4c95d86dce2c'::uuid,
        'd602c80a-8511-4359-8931-67d87facd0f2'::uuid,
        '057eb94c-2433-45c1-8a61-a841da0b1e29'::uuid,
        '84502339-d4fd-4e2a-beee-1a504672978c'::uuid,
        '1b18c826-e226-43e9-b4a0-6079c55853cc'::uuid,
        '3e3eb9b0-89d2-4778-bb73-d06cf2bb0ad0'::uuid,
        '6da9c8e1-9c9f-4fea-992e-57cc991f4d5f'::uuid
      )
    ORDER BY stock_number
    FOR UPDATE
  LOOP
    SELECT * INTO v_vehicle FROM public.vehicles WHERE id = r.vehicle_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'r575 down: id % is not a vehicle. The key was not put back.', r.vehicle_id;
    END IF;
    IF v_vehicle.stock_number IS DISTINCT FROM r.stock_number THEN
      RAISE EXCEPTION 'r575 down: id % is stock %, not %. The key was not put back.',
        r.vehicle_id, coalesce(v_vehicle.stock_number, '(no stock)'), coalesce(r.stock_number, '(no stock)');
    END IF;
    IF v_vehicle.key_number IS NOT NULL THEN
      RAISE EXCEPTION 'r575 down: stock % (%) already has key %. The approved key % was not written over it.',
        coalesce(v_vehicle.stock_number, '(no stock)'), r.vehicle_id, v_vehicle.key_number, r.token;
    END IF;
    UPDATE public.vehicles
       SET key_number = r.token, version = version + 1, updated_at = clock_timestamp()
     WHERE id = r.vehicle_id
       AND key_number IS NULL
       AND stock_number IS NOT DISTINCT FROM r.stock_number;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'r575 down: stock % (%) was not restored.', coalesce(r.stock_number, '(no stock)'), r.vehicle_id;
    END IF;
    UPDATE pdc_key_number_private.key_release_575
       SET restored_at = clock_timestamp()
     WHERE release_id = r.release_id
       AND restored_at IS NULL
       AND reason = 'approved_clear';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'r575 down: history for % was not marked restored.', r.vehicle_id;
    END IF;
  END LOOP;
END $restore$;

DO $apply$
DECLARE
  def text;
  new text := $old$ IF v_key IS NOT NULL THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-388-key:'||v_key,0));
  IF upper(btrim(coalesce(v_before.current_location,'')))='PMB' AND EXISTS(SELECT 1 FROM public.vehicles x WHERE x.id<>v_before.id AND x.deleted_at IS NULL
     AND x.lifecycle_state='active' AND upper(btrim(coalesce(x.current_location,'')))='PMB' AND upper(btrim(coalesce(x.key_number,'')))=v_key) THEN
   RETURN jsonb_build_object('ok',false,'code','key_number_in_use','message','Another active PMB vehicle already has this key tag.');
  END IF;$old$;
  old text := $new$ IF v_key IS NOT NULL THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-388-key:'||v_key,0));
  IF pdc_key_number_private.key_clash_message_575(v_before.id, v_key) IS NOT NULL THEN
   RETURN jsonb_build_object('ok',false,'code','key_number_in_use','message',pdc_key_number_private.key_clash_message_575(v_before.id, v_key));
  END IF;$new$;
BEGIN
  def := pg_get_functiondef(pg_catalog.to_regprocedure('pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'));
  IF length(old) = 0 OR (length(def) - length(replace(def, old, ''))) / length(old) <> 1 THEN
    RAISE EXCEPTION 'r575 down: apply key gate was not found once';
  END IF;
  EXECUTE replace(def, old, new);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'))
     IS DISTINCT FROM '8e46bf785c2118d58a8cebf2bd1888d1' THEN
    RAISE EXCEPTION 'r575 down: apply_key_number_460 did not return to the r460 body';
  END IF;
  UPDATE pdc_ops.expected_function_md5
     SET prosrc_md5 = '8e46bf785c2118d58a8cebf2bd1888d1',
         release = 'r460',
         note = 'r460 (F73) vehicle key number edit + audit',
         updated_at = clock_timestamp()
   WHERE signature = 'pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'
     AND prosrc_md5 = '59b676f8a7efac59876e0d36a61730a0';
  IF NOT FOUND THEN RAISE EXCEPTION 'r575 down: apply pin was not restored in place'; END IF;
END $apply$;

DO $detail$
DECLARE
  def text;
  new text := $old$       IF EXISTS(SELECT 1 FROM public.vehicles x WHERE x.id<>v_before.id AND x.deleted_at IS NULL AND x.lifecycle_state='active' AND upper(btrim(coalesce(x.current_location,'')))='PMB' AND upper(btrim(coalesce(x.key_number,'')))=v_key) THEN
         RETURN jsonb_build_object('ok',false,'code','key_number_in_use');
       END IF;$old$;
  old text := $new$       IF pdc_key_number_private.key_clash_message_575(v_before.id, v_key) IS NOT NULL THEN
         RETURN jsonb_build_object('ok',false,'code','key_number_in_use','message',pdc_key_number_private.key_clash_message_575(v_before.id, v_key));
       END IF;$new$;
BEGIN
  def := pg_get_functiondef(pg_catalog.to_regprocedure('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'));
  IF length(old) = 0 OR (length(def) - length(replace(def, old, ''))) / length(old) <> 1 THEN
    RAISE EXCEPTION 'r575 down: vehicle detail key gate was not found once';
  END IF;
  EXECUTE replace(def, old, new);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM 'eabd64cea227ce91a1f3005569c16439' THEN
    RAISE EXCEPTION 'r575 down: vehicle detail did not return to the previous body';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'))
     IS DISTINCT FROM '69decdbde44cf15f481ff7ba6e1bcfbd' THEN
    RAISE EXCEPTION 'r575 down: department 135 vehicle detail changed';
  END IF;
END $detail$;

DROP FUNCTION IF EXISTS pdc_key_number_private.guard_active_key_575();
DROP FUNCTION IF EXISTS pdc_key_number_private.drop_active_key_575();
DROP FUNCTION IF EXISTS pdc_key_number_private.key_clash_message_575(uuid, text);
DROP FUNCTION IF EXISTS pdc_key_number_private.sales_key_holder_575(uuid);
DROP FUNCTION IF EXISTS pdc_key_number_private.board_scope_575(uuid, timestamp with time zone, timestamp with time zone, boolean, text);
DROP FUNCTION IF EXISTS pdc_key_number_private.key_token_575(text);
DROP TABLE IF EXISTS pdc_key_number_private.key_release_575;
DROP TABLE IF EXISTS pdc_key_number_private.active_key_575;

DELETE FROM pdc_ops.regression_checks
WHERE check_name = 'active_key_unique_575' AND fault_id = 'F189' AND sort_order = 346 AND added_in = 'r575';

DO $post$
BEGIN
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
    RAISE EXCEPTION 'r575 down: pin count changed';
  END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name = 'active_key_unique_575' OR fault_id = 'F189' OR added_in = 'r575') THEN
    RAISE EXCEPTION 'r575 down: check still present';
  END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release = 'r575') THEN
    RAISE EXCEPTION 'r575 down: an r575 pin remains';
  END IF;
END $post$;
