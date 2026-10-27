-- Undo r575 (F189) / sort 346. PREVIEW. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Puts the PMB-only key gate back on the key editor and the vehicle-detail save,
-- drops the active-board trigger, the shadow key and the release history, and
-- removes active_key_unique_575. A key this release already cleared stays
-- cleared: the release history is dropped with the undo, so a later un-archive
-- cannot put it back. No vehicle row is rewritten. Department 135 is not edited.
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
