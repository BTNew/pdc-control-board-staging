-- Prepared security hardening candidate. Review and test before staging apply.
-- Staging only. No vehicle, booking, parts, import, sales or finance data updates.
-- Internal helpers remain callable by their owner inside the existing authorized wrappers.
DO $staging$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
     WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR current_setting('app.environment',true)='production' THEN
  RAISE EXCEPTION 'Exact staging environment required';
 END IF;
END $staging$;

DO $definitions$
DECLARE target regprocedure; before_sql text; after_sql text; item record;
BEGIN
 FOR item IN SELECT * FROM (VALUES
  ('public.append_vehicle_timeline_event(uuid,text,timestamp with time zone,vehicle_timeline_source_kind,vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)','2947414a5618be50bd1a0a3d0bb64258',$old$if not public.workshop_is_planner_operator() and current_setting('pdc.monitor.v2_canonical_action_capability_20260902',true) NOT LIKE 'pdc-email-ai-v2|%' then$old$,$new$if auth.uid() IS NULL OR NOT coalesce((
    EXISTS (SELECT 1 FROM public.pdc_user_roles r
      WHERE r.auth_user_id=auth.uid()
        AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
        AND r.active AND r.account_status='approved'
        AND r.role::text IN ('operator','importer','administrator'))
    OR (EXISTS (SELECT 1 FROM public.pdc_user_roles r
      WHERE r.auth_user_id=auth.uid()
        AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
        AND r.active AND r.account_status='approved' AND r.role::text='fitter')
      AND coalesce(pdc_fitter_private.authorized_request(true),false))
    OR coalesce(public.pdc_email_ai_v2_canonical_action_capability_20260902(),false)
  ),false) then$new$),
  ('public.record_vehicle_eta_history(uuid,text,date,text,vehicle_timeline_event_state,numeric,text,text,text,timestamp with time zone,uuid,uuid)','69d14065291c7f7e6cb5327aea51e51a',$old$if public.current_pdc_user_role() not in ('importer', 'administrator') and current_setting('pdc.monitor.v2_canonical_action_capability_20260902',true) NOT LIKE 'pdc-email-ai-v2|%' then$old$,$new$if auth.uid() IS NULL OR NOT coalesce((
    EXISTS (SELECT 1 FROM public.pdc_user_roles r
      WHERE r.auth_user_id=auth.uid()
        AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
        AND r.active AND r.account_status='approved'
        AND r.role::text IN ('importer','administrator'))
    OR coalesce(public.pdc_email_ai_v2_canonical_action_capability_20260902(),false)
  ),false) then$new$),
  ('public.rebuild_vehicle_intelligence_summary(uuid)','cf1daa14d53b01be7cada7f28d0fa1ea',$old$if public.current_pdc_user_role() not in ('importer', 'administrator', 'operator') and current_setting('pdc.monitor.v2_canonical_action_capability_20260902',true) NOT LIKE 'pdc-email-ai-v2|%' then$old$,$new$if auth.uid() IS NULL OR NOT coalesce((
    EXISTS (SELECT 1 FROM public.pdc_user_roles r
      WHERE r.auth_user_id=auth.uid()
        AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
        AND r.active AND r.account_status='approved'
        AND r.role::text IN ('operator','importer','administrator'))
    OR (EXISTS (SELECT 1 FROM public.pdc_user_roles r
      WHERE r.auth_user_id=auth.uid()
        AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
        AND r.active AND r.account_status='approved' AND r.role::text='fitter')
      AND coalesce(pdc_fitter_private.authorized_request(true),false))
    OR coalesce(public.pdc_email_ai_v2_canonical_action_capability_20260902(),false)
  ),false) then$new$)
 ) changes(signature,expected_md5,old_guard,new_guard) LOOP
  target:=to_regprocedure(item.signature);
  IF target IS NULL THEN RAISE EXCEPTION 'Missing expected function: %',item.signature; END IF;
  before_sql:=pg_get_functiondef(target);
  IF md5(before_sql)<>item.expected_md5 OR strpos(before_sql,item.old_guard)=0 THEN
   RAISE EXCEPTION 'Function definition changed: %',item.signature;
  END IF;
  after_sql:=replace(before_sql,item.old_guard,item.new_guard);
  after_sql:=replace(after_sql,E'SET search_path TO ''public''\n',E'SET search_path TO ''pg_catalog'', ''public''\n');
  EXECUTE after_sql;
 END LOOP;
END $definitions$;

-- No browser client calls these internals directly; server-owned wrappers retain access.
DO $helpers$
DECLARE item record; target regprocedure;
BEGIN
 FOR item IN SELECT * FROM (VALUES
  ('public.pdc_navision_vehicle_parity_494(uuid)','613108ff05e87d967a745ecfcca36750'),
  ('public.pdc_operation_projection_parity_493(uuid)','62e2389cd6085c83c7eada39d24550b7'),
  ('public.pdc_qc_operation_lines_379(uuid)','6223c1137064a8f1b9c86e512565b4a7'),
  ('public.pdc_vehicle_milestone_json(uuid)','a7aeb69bf4156111d8e8107dfb0d0241'),
  ('public.workshop_require_booking_schedule_eligibility(uuid,text)','478cf21d7bb550a12b7e149c3d454732'),
  ('public.workshop_station_eligibility(text)','2889b5514d53ff346aee63ea7681e5e4'),
  ('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,workshop_booking_status,uuid)','4899d7b0a132cc370b3bb105a9452056'),
  ('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,workshop_booking_status,uuid,boolean)','6aea577f8ce3a3017f5acd1ce7502297')
 ) checked(signature,expected_md5) LOOP
  target:=to_regprocedure(item.signature);
  IF target IS NULL OR md5(pg_get_functiondef(target))<>item.expected_md5 THEN
   RAISE EXCEPTION 'Internal helper changed: %',item.signature;
  END IF;
  EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC,anon,authenticated',target);
 END LOOP;
END $helpers$;

-- Match the existing QC photo receipt's approved operator/admin scope.
ALTER POLICY pdc_qc_evidence_upload_399 ON storage.objects
 WITH CHECK (
  bucket_id='pdc-qc-evidence-staging'
  AND name LIKE ('qc-finalization/'||auth.uid()::text||'/%')
  AND auth.uid() IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.pdc_user_roles r
    WHERE r.auth_user_id=auth.uid()
      AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
      AND r.active AND r.account_status='approved'
      AND r.role::text IN ('operator','administrator'))
 );

NOTIFY pgrst,'reload schema';

