-- STAGING ONLY 411: align Yard Hold Workshop eligibility with the browser
-- contract and remove retained HERMES-TEST fixtures from every website snapshot.
-- Test records, history and receipts are preserved for audit/recovery.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-411-yh-eligibility-hide-test-fleet',0));
DO $guard$
DECLARE v_head text;
BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  OR v_head IS DISTINCT FROM '20260826164500'
  OR (SELECT count(*) FROM public.vehicles WHERE stock_number LIKE 'HERMES-TEST-%' AND deleted_at IS NULL)<>20
  OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN RAISE EXCEPTION 'PDC_411_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_station_eligibility(p_stage_code text)
RETURNS TABLE(vehicle_id uuid,stage_code text,work_key text,current_location text,eta_to_kewdale date,existing_booking boolean,schedule_enabled boolean,disabled_reason text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $eligibility$
 WITH station AS(
  SELECT s.id,s.code,s.work_key FROM public.workshop_stages s
  WHERE s.code=public.workshop_canonical_stage_code(p_stage_code) AND s.active AND s.planner_enabled
 ),outstanding AS(
  SELECT wi.vehicle_id,st.id stage_id,st.code,st.work_key
  FROM public.vehicle_work_items wi CROSS JOIN station st
  WHERE public.workshop_stage_code_for_work_key(wi.work_key)=st.code AND wi.required AND NOT wi.completed
  GROUP BY wi.vehicle_id,st.id,st.code,st.work_key
 ),active_booking AS(
  SELECT DISTINCT b.vehicle_id,st.code FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id JOIN station st ON st.code=s.code
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
 )
 SELECT v.id,o.code,o.work_key,upper(btrim(coalesce(v.current_location,''))),v.eta_to_kewdale,
  (ab.vehicle_id IS NOT NULL),
  (public.workshop_vehicle_stage_estimated_duration_minutes(v.id,o.stage_id) IS NOT NULL),
  CASE WHEN public.workshop_vehicle_stage_estimated_duration_minutes(v.id,o.stage_id) IS NULL THEN 'estimated_duration_missing' ELSE NULL::text END
 FROM outstanding o JOIN public.vehicles v ON v.id=o.vehicle_id
 LEFT JOIN active_booking ab ON ab.vehicle_id=v.id AND ab.code=o.code
 WHERE v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
   AND upper(btrim(coalesce(v.current_location,''))) IN('PMB','YH','IT')
   AND (upper(btrim(coalesce(v.current_location,'')))<>'IT' OR v.eta_to_kewdale IS NOT NULL)
$eligibility$;
REVOKE ALL ON FUNCTION public.workshop_station_eligibility(text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.workshop_station_eligibility(text) TO authenticated;

DO $hide$
DECLARE v_before public.vehicles%rowtype; v_after public.vehicles%rowtype;
BEGIN
 FOR v_before IN SELECT * FROM public.vehicles WHERE stock_number LIKE 'HERMES-TEST-%' AND deleted_at IS NULL ORDER BY id FOR UPDATE LOOP
  IF v_before.visible_on_board THEN
   PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',v_before.id::text,true);
   UPDATE public.vehicles SET visible_on_board=false,version=version+1,updated_at=clock_timestamp()
    WHERE id=v_before.id RETURNING * INTO v_after;
   INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
   VALUES('update','vehicles',v_after.id,v_after.id,NULL,'hermes-staging-migration-411',to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('action','hide_hermes_test_vehicle_from_staging_website_411','stock_number',v_after.stock_number,'records_deleted',false,'history_preserved',true));
  END IF;
 END LOOP;
END $hide$;

DO $post$
DECLARE d text:=pg_get_functiondef('public.workshop_station_eligibility(text)'::regprocedure);
BEGIN
 IF position('IN (''PMB'', ''YH'', ''IT'')' in d)=0 AND position('IN(''PMB'',''YH'',''IT'')' in d)=0 THEN RAISE EXCEPTION 'PDC_411_YH_ELIGIBILITY_POSTCONDITION' USING errcode='55000'; END IF;
 IF (SELECT count(*) FROM public.vehicles WHERE stock_number LIKE 'HERMES-TEST-%' AND deleted_at IS NULL)<>20
  OR EXISTS(SELECT 1 FROM public.vehicles WHERE stock_number LIKE 'HERMES-TEST-%' AND deleted_at IS NULL AND visible_on_board)
  OR (SELECT count(*) FROM public.vehicle_notifications)<>1
  OR has_function_privilege('public','public.workshop_station_eligibility(text)','EXECUTE')
  OR has_function_privilege('anon','public.workshop_station_eligibility(text)','EXECUTE')
  OR has_function_privilege('service_role','public.workshop_station_eligibility(text)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.workshop_station_eligibility(text)','EXECUTE') THEN RAISE EXCEPTION 'PDC_411_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826170000','411_yh_workshop_eligibility_hide_test_fleet',ARRAY['Include visible Yard Hold vehicles in canonical Workshop station eligibility without requiring ETA','Hide all 20 retained HERMES-TEST vehicles from staging website snapshots while preserving rows, history and receipts','Keep hidden test fixtures out of all planner eligibility results']);
NOTIFY pgrst,'reload schema';
COMMIT;
