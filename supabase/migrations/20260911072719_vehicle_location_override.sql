ALTER TABLE public.vehicles
 ADD COLUMN location_override text CHECK(location_override IN('PMB','YH','IT','PIT','QC','RFT','Other')),
 ADD COLUMN location_override_reason text CHECK(length(location_override_reason)<=500),
 ADD COLUMN location_override_at timestamptz,
 ADD COLUMN location_override_by uuid REFERENCES auth.users(id);

CREATE FUNCTION public.set_pdc_vehicle_location_override(p_vehicle_id uuid,p_expected_version bigint,p_location text DEFAULT NULL,p_reason text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $function$
DECLARE actor uuid:=auth.uid(); before_row public.vehicles%rowtype; after_row public.vehicles%rowtype;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
 IF auth.role() IS DISTINCT FROM 'authenticated' OR actor IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=actor AND lower(r.email)=lower(auth.jwt()->>'email')
   AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator'))
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_location IS NOT NULL AND (p_location NOT IN('PMB','YH','IT','PIT','QC','RFT','Other') OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 1 AND 500)
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_location_or_reason'); END IF;
 SELECT * INTO before_row FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 IF before_row.version IS DISTINCT FROM p_expected_version THEN RETURN jsonb_build_object('ok',false,'code','version_conflict'); END IF;
 UPDATE public.vehicles SET location_override=p_location,
  location_override_reason=CASE WHEN p_location IS NULL THEN NULL ELSE btrim(p_reason) END,
  location_override_at=CASE WHEN p_location IS NULL THEN NULL ELSE clock_timestamp() END,
  location_override_by=CASE WHEN p_location IS NULL THEN NULL ELSE actor END,
  version=version+1,updated_at=clock_timestamp(),updated_by=actor
 WHERE id=p_vehicle_id RETURNING * INTO after_row;
 PERFORM public.audit_pdc_event('update','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(before_row),to_jsonb(after_row),
  jsonb_build_object('action',CASE WHEN p_location IS NULL THEN 'clear_location_override' ELSE 'set_location_override' END,'reason',p_reason));
 RETURN jsonb_build_object('ok',true,'code','location_override_saved','vehicle_version',after_row.version);
END $function$;
REVOKE ALL ON FUNCTION public.set_pdc_vehicle_location_override(uuid,bigint,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_vehicle_location_override(uuid,bigint,text,text) TO authenticated;

DO $migration$
DECLARE original text; revised text;
BEGIN
 original:=pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure);
 revised:=replace(original,'''qc_completed_at'',canonical.qc_completed_at,',
 '''location_override'',canonical.location_override,''location_override_reason'',canonical.location_override_reason,''location_override_at'',canonical.location_override_at,''location_override_by'',canonical.location_override_by,''automatic_location'',canonical.current_location,''qc_completed_at'',canonical.qc_completed_at,');
 IF revised=original THEN RAISE EXCEPTION 'snapshot_contract_changed'; END IF;
 EXECUTE revised;
END $migration$;
