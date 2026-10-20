-- r414 (F30): a stored QC completion photo is found again after a refresh, so "Sign off QC -> RFT" shows.
-- Staging cdsmnqxtyyoeoznmbidd only. Adds one read function; no existing function, table, policy or row changes.
-- Cause (Key 208 / 13017935 and Key 454 / 13017936): the QC page keeps the photo receipt only in browser memory.
-- Key 208's photo was stored at 18:50 AWST on 20 Oct (receipt a435b36a). After a refresh the page had no way to read it
-- back, so it showed no photo. Re-uploading the same picture (18:57, 21:54, 21:55) uploaded a new file each time and
-- record_pdc_qc_photo_evidence_399 answered qc_photo_already_recorded (one receipt per QC inspection), a code the page did
-- not know: the preview stayed on "Selected image; receipt validation is pending" and the Sign off button never showed.
-- Key 454 (receipt 16 Oct 13:09, re-uploads 16 Oct 13:14 and 20 Oct 22:00) is the same. No other QC vehicle has a receipt.
-- Fix: public.get_pdc_qc_photo_receipt_414(vehicle) returns the stored receipt for the vehicle's current QC inspection
-- (same role rule as the upload: active approved operator or administrator), with a check that the stored file exists.
-- The page (PR) loads it when a QC vehicle opens, and on qc_photo_already_recorded; it blocks a second upload while a
-- receipt is stored. Sign-off (finalize_pdc_qc_to_rft_700) is unchanged and already accepts the stored receipt.
-- Health: check qc_photo_receipt_readable (F30).
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r414: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r414: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r414: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r414: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)'::regprocedure)<>'aca6f38ffba657e5828aeb81f56d1b7a'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)'::regprocedure)<>'e4c7271b2efe49ed45117f600b6fe954'
 THEN RAISE EXCEPTION 'r414: the QC photo upload or sign-off function is not the expected version'; END IF;
 IF to_regprocedure('public.get_pdc_qc_photo_receipt_414(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r414: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='qc_photo_receipt_readable') THEN RAISE EXCEPTION 'r414: check already present'; END IF;
END $g$;

CREATE FUNCTION public.get_pdc_qc_photo_receipt_414(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_vehicle public.vehicles%rowtype; inspection_key uuid; r public.pdc_qc_finalization_photo_evidence_399%rowtype; v_present boolean;
BEGIN
  -- r414 (F30): read back the stored completion photo receipt so a refreshed QC page can sign off with it.
  IF v_actor IS NULL OR p_vehicle_id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_invalid_input'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles u WHERE u.auth_user_id=v_actor AND lower(u.email)=v_email
    AND u.role IN('operator','administrator') AND u.active AND u.account_status='approved') THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id;
  IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' OR upper(btrim(coalesce(v_vehicle.current_location,'')))<>'QC' THEN
    RETURN jsonb_build_object('ok',false,'code','qc_photo_vehicle_not_in_qc');
  END IF;
  inspection_key:=(public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>'inspection_key')::uuid;
  SELECT * INTO r FROM public.pdc_qc_finalization_photo_evidence_399 e
  WHERE e.vehicle_id=p_vehicle_id AND e.qc_inspection_key IS NOT DISTINCT FROM inspection_key
  ORDER BY e.created_at DESC, e.photo_receipt_id LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',true,'code','qc_photo_none','data',jsonb_build_object('vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle.version,'qc_inspection_key',inspection_key));
  END IF;
  SELECT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id=r.bucket_id AND o.name=r.storage_path) INTO v_present;
  RETURN jsonb_build_object('ok',true,'code',CASE WHEN v_present THEN 'qc_photo_stored' ELSE 'qc_photo_storage_missing' END,
    'data',(r.response->'data')||jsonb_build_object('photo_receipt_id',r.photo_receipt_id,'vehicle_id',r.vehicle_id,'vehicle_version',v_vehicle.version,
      'qc_inspection_key',r.qc_inspection_key,'bucket_id',r.bucket_id,'storage_path',r.storage_path,'content_type',r.content_type,
      'byte_length',r.byte_length,'original_byte_length',r.original_byte_length,'image_width',r.image_width,'image_height',r.image_height,
      'sha256',r.sha256,'original_filename',r.original_filename,'stored_at',r.created_at,'storage_object_present',v_present,'replay',true));
END $function$;
REVOKE ALL ON FUNCTION public.get_pdc_qc_photo_receipt_414(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_qc_photo_receipt_414(uuid) TO authenticated, service_role;
COMMENT ON FUNCTION public.get_pdc_qc_photo_receipt_414(uuid) IS 'r414 (F30): stored QC completion photo receipt for the current QC inspection, so a refreshed QC page can sign off. Read only.';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in)
VALUES('qc_photo_receipt_readable','F30',
 'A stored QC completion photo can be read back after a refresh (get_pdc_qc_photo_receipt_414: security definer, authenticated only), every QC vehicle with a receipt has its stored file, and no QC photo upload has been left without a receipt since r414 (re-uploads refused as qc_photo_already_recorded were the 20 Oct fault).',
$chk$WITH f AS (
  SELECT p.prosecdef, has_function_privilege('authenticated',p.oid,'EXECUTE') auth_ok, has_function_privilege('anon',p.oid,'EXECUTE') anon_ok
  FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.get_pdc_qc_photo_receipt_414(uuid)')
), q AS (
  SELECT v.id, v.key_number, e.storage_path, EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id=e.bucket_id AND o.name=e.storage_path) present
  FROM public.vehicles v JOIN public.pdc_qc_finalization_photo_evidence_399 e ON e.vehicle_id=v.id
   AND e.qc_inspection_key IS NOT DISTINCT FROM (public.pdc_qc_rework_scope_20260909(v.id)->>'inspection_key')::uuid
  WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND upper(btrim(coalesce(v.current_location,'')))='QC'
), o AS (
  SELECT count(*) n, string_agg(DISTINCT coalesce(v.key_number,left(split_part(x.name,'/',3),8)),', ') keys
  FROM storage.objects x LEFT JOIN public.vehicles v ON v.id::text=split_part(x.name,'/',3)
  WHERE x.bucket_id='pdc-qc-evidence-staging' AND x.name LIKE 'qc-finalization/%'
    AND x.created_at > greatest(now()-interval '24 hours', timestamptz '2026-10-21 12:00:00+08')
    AND x.created_at < now()-interval '2 minutes'
    AND NOT EXISTS(SELECT 1 FROM public.pdc_qc_finalization_photo_evidence_399 e WHERE e.storage_path=x.name)
)
SELECT (SELECT count(*) FROM f WHERE prosecdef AND auth_ok AND NOT anon_ok)=1
   AND (SELECT count(*) FROM q WHERE NOT present)=0 AND (SELECT n FROM o)=0 AS ok,
 'receipt read-back ' || CASE WHEN (SELECT count(*) FROM f WHERE prosecdef AND auth_ok AND NOT anon_ok)=1 THEN 'available' ELSE 'MISSING or wrong grants' END
 || '; QC vehicles with a stored photo: ' || (SELECT count(*) FROM q) || coalesce(' (keys '||(SELECT string_agg(coalesce(key_number,'-'),', ' ORDER BY key_number) FROM q)||')','')
 || CASE WHEN (SELECT count(*) FROM q WHERE NOT present)>0 THEN ', '||(SELECT count(*) FROM q WHERE NOT present)||' with the file MISSING' ELSE '' END
 || '; uploads without a receipt in 24 h (after 21 Oct 12:00): ' || (SELECT n FROM o) || coalesce(' (keys '||(SELECT keys FROM o)||')','') AS detail$chk$,
 true,215,'r414');
