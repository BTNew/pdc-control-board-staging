-- Compact polling reads; existing commands and operation authority are unchanged.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging only'; END IF;
END $guard$;

-- Fitter-only authority is also restricted by the actual PostgREST route.
-- Extend only the read allowlist; the command remains the only write route.
DO $fitter_route$
DECLARE original text; revised text;
BEGIN
 SELECT pg_get_functiondef('pdc_fitter_private.authorized_request(boolean)'::regprocedure) INTO original;
 IF md5(original)<>'f05d7a5a2af97114775efcbf086e24c8' THEN RAISE EXCEPTION 'Fitter authorization changed; reconcile before applying'; END IF;
 IF md5(pg_get_functiondef('public.get_fitter_roster()'::regprocedure))<>'8bc5194eef0648dee4da5790f489d565'
 THEN RAISE EXCEPTION 'Fitter roster changed; reconcile before applying'; END IF;
 revised:=replace(original,
  '''rpc/get_fitter_roster'',''rpc/get_fitter_jobs'',''rpc/get_fitter_job'',''rpc/fitter_job_command''',
  '''rpc/get_fitter_roster'',''rpc/get_fitter_jobs'',''rpc/get_fitter_job'',''rpc/get_fitter_refresh'',''rpc/fitter_job_command''');
 IF revised=original THEN RAISE EXCEPTION 'Fitter read route patch did not match'; END IF;
 EXECUTE revised;
END $fitter_route$;

CREATE OR REPLACE FUNCTION public.get_pdc_review_counts()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE vehicles_count bigint; changes_count bigint;
BEGIN
 -- These queues are intentionally unavailable to fitter-only accounts.
 IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid()
   AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email','')))
   AND r.active AND r.account_status='approved' AND r.role IN('viewer','operator','importer','administrator'))
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 SELECT count(*) INTO vehicles_count
 FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
 WHERE r.status='pending' AND v.deleted_at IS NULL AND v.lifecycle_state::text='active';
 SELECT count(*) INTO changes_count FROM public.pdc_tune_operation_change_reviews WHERE status='pending';
 RETURN jsonb_build_object('ok',true,'data',jsonb_build_object(
  'new_vehicles',vehicles_count,'operation_changes',changes_count));
END $fn$;

CREATE OR REPLACE FUNCTION public.get_fitter_refresh(
 p_technician_id uuid,p_booking_id uuid DEFAULT NULL,p_known_revision text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE revision_base text; revision_key text; queue jsonb; selected_id uuid; detail jsonb;
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT EXISTS(SELECT 1 FROM public.workshop_technicians WHERE id=p_technician_id AND active)
 THEN RETURN jsonb_build_object('ok',false,'error','mechanic_unavailable'); END IF;
 -- Booking/assignment/config triggers advance station revisions. Source lines,
 -- manual estimates, vehicle identity and imported operation approvals advance
 -- the email revision. Do not use booking.version alone: scope can change too.
 -- STABLE keeps the revision, queue, checklist and timer in one read snapshot.
 SELECT md5(jsonb_build_array(p_technician_id,auth.uid(),auth.jwt()->>'session_id',
  (SELECT string_agg(r.role::text,',' ORDER BY r.role::text) FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid()
   AND r.active AND r.account_status='approved' AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email','')))),
  (SELECT revision FROM public.pdc_email_vehicle_revision WHERE singleton),
  (SELECT coalesce(jsonb_object_agg(stage_code,revision),'{}'::jsonb) FROM public.workshop_station_revision))::text)
 INTO revision_base;
 revision_key:=md5(jsonb_build_array(revision_base,p_booking_id)::text);
 IF p_known_revision=revision_key AND (p_booking_id IS NULL OR EXISTS(
  SELECT 1 FROM public.workshop_bookings b JOIN public.vehicles v ON v.id=b.vehicle_id
  WHERE b.id=p_booking_id AND b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND v.deleted_at IS NULL AND v.lifecycle_state='active'
   AND pdc_fitter_private.assigned(b.id,p_technician_id))) THEN
  RETURN jsonb_build_object('ok',true,'unchanged',true,'revision',revision_key,'booking_id',p_booking_id,
   'timing',CASE WHEN p_booking_id IS NOT NULL THEN pdc_fitter_private.timing(p_booking_id,statement_timestamp()) ELSE NULL END);
 END IF;
 queue:=public.get_fitter_jobs(p_technician_id);
 IF (queue->>'ok')::boolean IS DISTINCT FROM true THEN RETURN queue; END IF;
 -- Match fitterJobFlow: retain a selected active job; otherwise first active,
 -- then the planner's first planned/queued job. Never pick a stale next job.
 SELECT (item->>'id')::uuid INTO selected_id
 FROM jsonb_array_elements(queue->'jobs') WITH ORDINALITY jobs(item,position)
 WHERE item->>'status' IN('started','stoppage','planned','queued')
 ORDER BY CASE WHEN item->>'status' IN('started','stoppage') THEN 0 ELSE 1 END,
  CASE WHEN item->>'status' IN('started','stoppage') AND item->>'id'=p_booking_id::text THEN 0 ELSE 1 END,
  position LIMIT 1;
 IF selected_id IS NOT NULL THEN
  detail:=public.get_fitter_job(p_technician_id,selected_id);
  IF (detail->>'ok')::boolean IS DISTINCT FROM true THEN RETURN detail; END IF;
 END IF;
 revision_key:=md5(jsonb_build_array(revision_base,selected_id)::text);
 RETURN queue||jsonb_build_object('revision',revision_key,'unchanged',false,'booking_id',selected_id,'detail',detail);
END $fn$;

-- Capability negotiation lets old clients retain their original reads and lets
-- new clients avoid calling the new endpoint until it is available.
CREATE OR REPLACE FUNCTION public.get_fitter_roster()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
BEGIN
 PERFORM public.require_pdc_role('viewer');
 RETURN jsonb_build_object('ok',true,'refresh_supported',true,'technicians',(
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name,id),'[]'::jsonb)
 FROM public.workshop_technicians WHERE active AND role_type='technician'));
END $fn$;

REVOKE ALL ON FUNCTION public.get_pdc_review_counts(),public.get_fitter_refresh(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_review_counts(),public.get_fitter_refresh(uuid,uuid,text) TO authenticated;
NOTIFY pgrst,'reload schema';
