-- REVIEWED INVERSE CANDIDATE ONLY. Reverts code/check text, never staff data.
-- Safe after successful use: normal booking/assignment/history rows remain as saved.
-- Restore the old helper before dropping the exact private routine; no CASCADE.
-- Complete staging-management inverse transaction; do not split.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $running_growth_deployment_gate$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR auth.uid() IS NOT NULL
  OR NOT pdc_codex_intake_private.management_connection()
  OR current_setting('app.environment',true)='production'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'running_growth_deployment_staging_management_required'; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0))
 THEN RAISE EXCEPTION 'running_growth_deployment_clock_busy'; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0))
 THEN RAISE EXCEPTION 'running_growth_deployment_mutation_busy'; END IF;
END
$running_growth_deployment_gate$;
DO $running_growth_down$
DECLARE helper_metadata jsonb; pins_before jsonb; check_before jsonb;
 helper_sql text:=$helper_sql$CREATE OR REPLACE FUNCTION public.workshop_extend_running_booking_538(p_booking_id uuid, p_source text, p_added_minutes integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE b public.workshop_bookings; planned integer; extra integer; new_end timestamptz; n integer;
BEGIN
 -- A running booking keeps the start already recorded. The finish moves later to the planner length,
 -- including hours added from another station. It is never pulled earlier.
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND OR b.deleted_at IS NOT NULL OR b.status NOT IN ('started'::public.workshop_booking_status,'stoppage'::public.workshop_booking_status) THEN
  RETURN jsonb_build_object('ok',true,'extended',false,'reason','not_running');
 END IF;
 planned:=public.workshop_booking_effective_duration_minutes(b.id);
 SELECT coalesce(sum(round((l->>'estimated_hours')::numeric*60)),0)::integer INTO extra
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(b.vehicle_id)) l
  JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE coalesce((l->>'active')::boolean,true)
   AND l->>'stage_code' IS DISTINCT FROM s.code
   AND jsonb_typeof(l->'estimated_hours')='number'
   AND EXISTS (SELECT 1 FROM pdc_fitter_private.operation_progress p WHERE p.booking_id=b.id AND p.line_identity=l->>'line_identity');
 planned:=greatest(coalesce(planned,0),0)+greatest(coalesce(extra,0),0);
 IF planned<1 OR b.scheduled_start_at IS NULL THEN
  RETURN jsonb_build_object('ok',true,'extended',false,'reason','hours_unknown','planned_minutes',planned);
 END IF;
 new_end:=public.workshop_add_operational_minutes(b.scheduled_start_at, planned);
 IF new_end IS NULL OR new_end<=b.scheduled_end_at THEN
  RETURN jsonb_build_object('ok',true,'extended',false,'reason','already_covers','scheduled_end_at',b.scheduled_end_at,'planned_minutes',planned);
 END IF;
 BEGIN
  UPDATE public.workshop_bookings
   SET default_duration_minutes=planned, scheduled_end_at=new_end, version=version+1, updated_by=auth.uid(), updated_at=clock_timestamp()
   WHERE id=b.id AND vehicle_id=b.vehicle_id AND deleted_at IS NULL
    AND status IN ('started'::public.workshop_booking_status,'stoppage'::public.workshop_booking_status)
    AND scheduled_start_at IS NOT DISTINCT FROM b.scheduled_start_at
    AND actual_start_at IS NOT DISTINCT FROM b.actual_start_at
    AND version=b.version;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>1 THEN RAISE EXCEPTION 'extend_missed'; END IF;
 EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'The running job could not be extended. Its start was left where it is.';
 END;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','workshop_bookings',b.id,b.vehicle_id,auth.uid(),public.current_actor_email(),
  jsonb_build_object('status',b.status,'default_duration_minutes',b.default_duration_minutes,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,'actual_start_at',b.actual_start_at),
  jsonb_build_object('default_duration_minutes',planned,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',new_end,'actual_start_at',b.actual_start_at,'accounted','running_job_end_extended','planned_minutes',planned,'other_station_minutes',extra,'added_minutes',p_added_minutes),
  jsonb_build_object('source',coalesce(p_source,'running_booking_end_538')));
 RETURN jsonb_build_object('ok',true,'extended',true,'scheduled_end_at',new_end,'planned_minutes',planned,'other_station_minutes',extra);
END
$function$
$helper_sql$;
 old_check text:=$old_check$
SELECT
 (SELECT md5(p.prosrc)='f0e6e008fa511fcbbe0e87f17f3dd7b3'
   AND p.prosrc LIKE '%running_job_end_extended%'
   AND p.prosrc LIKE '%scheduled_start_at IS NOT DISTINCT FROM%'
   AND p.prosrc LIKE '%actual_start_at IS NOT DISTINCT FROM%'
   AND strpos(p.prosrc, '::public.workshop_booking_status')>0
   AND p.proconfig::text LIKE '%search_path=pg_catalog%'
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)'))
 AND (SELECT md5(p.prosrc)=(SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e
    WHERE e.signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND e.release='r538')
   AND p.prosrc LIKE '%workshop_extend_running_booking_538%'
   AND p.prosrc LIKE '%keeps its start%'
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
 AND EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE t.tgname='workshop_extend_running_after_hours_538' AND n.nspname='public' AND c.relname='vehicle_workshop_line_adjustments' AND NOT t.tgisinternal)
 AND EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE t.tgname='fitter_extend_other_station_538' AND n.nspname='pdc_fitter_private' AND c.relname='operation_progress' AND NOT t.tgisinternal)
 AND (
  pg_catalog.to_regprocedure('karratha135_pdc.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)') IS NULL
  OR (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('karratha135_pdc.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
   IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
 ) AS ok,
 'running booking finish includes hours added from another station' AS detail
$old_check$;
 new_check text:=$new_check$
SELECT
 (SELECT md5(p.prosrc)='37a4c927372e9df884f5d187ab51d1c7'
   AND p.prosrc LIKE '%running_job_end_extended%'
   AND p.prosrc LIKE '%saved.scheduled_start_at IS DISTINCT FROM b.scheduled_start_at%'
   AND p.prosrc LIKE '%saved.actual_start_at IS DISTINCT FROM b.actual_start_at%'
   AND strpos(p.prosrc, '::public.workshop_booking_status')>0
   AND p.proconfig::text LIKE '%search_path=pg_catalog%'
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)'))
 AND (SELECT md5(p.prosrc)=(SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e
    WHERE e.signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND e.release='r538')
   AND p.prosrc LIKE '%workshop_extend_running_booking_538%'
   AND p.prosrc LIKE '%keeps its start%'
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
 AND EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE t.tgname='workshop_extend_running_after_hours_538' AND n.nspname='public' AND c.relname='vehicle_workshop_line_adjustments' AND NOT t.tgisinternal)
 AND EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE t.tgname='fitter_extend_other_station_538' AND n.nspname='pdc_fitter_private' AND c.relname='operation_progress' AND NOT t.tgisinternal)
 AND (
  pg_catalog.to_regprocedure('karratha135_pdc.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)') IS NULL
  OR (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('karratha135_pdc.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
   IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
 )
 AND (SELECT md5(prosrc)='079644c4c29195a9262582547a57d276' AND NOT prosecdef
   FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)'))
 AND NOT has_function_privilege('authenticated','pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)','EXECUTE')
 AND NOT has_function_privilege('anon','pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)','EXECUTE')
 AS ok,
 'running booking finish includes hours added from another station' AS detail
$new_check$;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 IF md5(pg_get_functiondef(to_regprocedure('pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid)'))) IS DISTINCT FROM 'a338ae78a36b80bf9474bab846e1f851' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid)'; END IF;
 IF md5(pg_get_functiondef(to_regprocedure('public.workshop_capacity_plan(text,uuid,integer,timestamptz)'))) IS DISTINCT FROM '89c6e721f0715ec435ec538c334838f0' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_capacity_plan(text,uuid,integer,timestamptz)'; END IF;
 IF md5(pg_get_functiondef(to_regprocedure('public.workshop_extend_running_after_hours_538()'))) IS DISTINCT FROM '1b2c507e05f0247bec9d41446e2cb5eb' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_extend_running_after_hours_538()'; END IF;
 IF md5(pg_get_functiondef(to_regprocedure('public.workshop_reconcile_adjustment_booking_duration()'))) IS DISTINCT FROM 'ef3116918cfb1d1c44cc45ef6e425bab' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_reconcile_adjustment_booking_duration()'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.clock_add_minutes(timestamptz,integer,uuid)')) IS DISTINCT FROM 'd0a395e6739423c1e4f5f2329fa5cd75' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.clock_add_minutes(timestamptz,integer,uuid)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.clock_next_minute(timestamptz,uuid)')) IS DISTINCT FROM '734b6fc0d468b8a8a9cee2b955f9b21b' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.clock_next_minute(timestamptz,uuid)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.add_minutes(timestamptz,integer,uuid)')) IS DISTINCT FROM 'c43afa5c1312392aa5d3666a8aa7cf65' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.add_minutes(timestamptz,integer,uuid)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.active_vehicle(uuid)')) IS DISTINCT FROM '7b033ee2e646cc4411b17876df3b279d' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.active_vehicle(uuid)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.booking_shift_guard()')) IS DISTINCT FROM '245d4bf9a0324bc65563f48c1a62c619' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.booking_shift_guard()'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')) IS DISTINCT FROM 'ae08aa9b0dc99e7c93b1710efdcb5070' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_enforce_assignment_validation()')) IS DISTINCT FROM 'e270480a19b571c79e960fca2d1a2fb2' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_enforce_assignment_validation()'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_find_technician_conflict(uuid,uuid,timestamptz,timestamptz)')) IS DISTINCT FROM 'daea24a73f5e571bfd8cf5e3fac856f9' THEN RAISE EXCEPTION 'running_growth_dependency_changed: workshop_find_technician_conflict'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.audit_pdc_event(public.audit_action,text,uuid,uuid,jsonb,jsonb,jsonb)')) IS DISTINCT FROM '8abc0d10dc601bcdbbb195502856cf13' THEN RAISE EXCEPTION 'running_growth_dependency_changed: audit_pdc_event'; END IF;
 SELECT to_jsonb(p)-'prosrc' INTO STRICT helper_metadata FROM pg_proc p WHERE oid=to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)');
 SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY signature),'[]') INTO pins_before FROM pdc_ops.expected_function_md5 e;
 SELECT to_jsonb(c) INTO STRICT check_before FROM pdc_ops.regression_checks c WHERE check_name='running_booking_end_538' AND fault_id='F152' AND sort_order=317;

 IF md5(pg_get_functiondef(to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)'))) IS DISTINCT FROM '876704abdee272bb2724cb640c895c33'
 OR md5(pg_get_functiondef(to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)'))) IS DISTINCT FROM 'a53b5d76a81b6a42aef826d8d433170f' THEN RAISE EXCEPTION 'Running growth source changed; inverse refused'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.prosrc LIKE '%reconcile_running_growth_20261026%'
  AND p.oid<>to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)')) THEN RAISE EXCEPTION 'New running growth callers exist; inverse refused'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE to_regprocedure(signature)=to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)')) THEN RAISE EXCEPTION 'New running growth pin exists; inverse refused'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 WHERE p.oid=to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)') AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Private function grants changed; inverse refused'; END IF;
 IF (SELECT p.prosecdef OR p.proowner<>e.proowner OR p.proconfig IS DISTINCT FROM e.proconfig FROM pg_proc p,pg_proc e
 WHERE p.oid=to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)') AND e.oid=to_regprocedure('pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid)')) THEN RAISE EXCEPTION 'Private function metadata changed; inverse refused'; END IF;
 helper_sql:=replace(helper_sql,chr(13),''); old_check:=replace(old_check,chr(13),''); new_check:=replace(new_check,chr(13),'');
 IF check_before->>'check_sql' IS DISTINCT FROM new_check THEN RAISE EXCEPTION 'r538 regression check changed; inverse refused'; END IF;
 IF md5(helper_sql)<>'f70d2eb94c4825f8ec61efb4354a3dbe' THEN RAISE EXCEPTION 'Inverse literal changed'; END IF;
 EXECUTE helper_sql;
 UPDATE pdc_ops.regression_checks SET check_sql=old_check WHERE check_name='running_booking_end_538' AND fault_id='F152' AND sort_order=317 AND check_sql=new_check;
 IF NOT FOUND THEN RAISE EXCEPTION 'r538 inverse check update missed'; END IF;
 DROP FUNCTION pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text);
 IF md5(pg_get_functiondef(to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)'))) IS DISTINCT FROM 'f70d2eb94c4825f8ec61efb4354a3dbe'
 OR to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)') IS NOT NULL THEN RAISE EXCEPTION 'Running growth inverse readback mismatch'; END IF;
 IF (SELECT to_jsonb(p)-'prosrc' FROM pg_proc p WHERE oid=to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)')) IS DISTINCT FROM helper_metadata THEN RAISE EXCEPTION 'Running helper metadata changed'; END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY signature),'[]') FROM pdc_ops.expected_function_md5 e) IS DISTINCT FROM pins_before THEN RAISE EXCEPTION 'Function pins changed'; END IF;
 IF (SELECT to_jsonb(c)-'check_sql' FROM pdc_ops.regression_checks c WHERE check_name='running_booking_end_538' AND fault_id='F152' AND sort_order=317) IS DISTINCT FROM check_before-'check_sql' THEN RAISE EXCEPTION 'Regression check metadata changed'; END IF;
END $running_growth_down$;
COMMIT;

