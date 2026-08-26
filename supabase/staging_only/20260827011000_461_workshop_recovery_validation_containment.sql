-- STAGING ONLY 461: contain every booking-validation conflict to its own unchanged bay.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-461-workshop-recovery-validation-containment',0));
DO $pre$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827010000' AND name='460_workshop_recovery_future_start')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827010000')
 OR encode(extensions.digest(convert_to(pg_get_functiondef('public.recover_overdue_planned_workshop_bookings(text,timestamptz)'::regprocedure),'UTF8'),'sha256'),'hex')<>'b4dd1eec2b0dce044f01a2f6c4355572b43dbec8a9f1438a56dd3739d42d5f99'
 THEN RAISE EXCEPTION 'PDC_461_STAGING_HEAD_OR_FUNCTION_MISMATCH' USING errcode='55000';END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.recover_overdue_planned_workshop_bookings(p_idempotency_key text,p_as_of timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $function$
DECLARE
 v_actor uuid:=auth.uid();v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');v_as_of timestamptz:=coalesce(p_as_of,clock_timestamp());
 v_start timestamptz;v_increment integer;v_bay record;v_stage text;v_repack jsonb;
 v_moved jsonb:='[]'::jsonb;v_skipped jsonb:='[]'::jsonb;v_count integer:=0;v_skipped_count integer:=0;v_error text;v_reason text;
 v_hash text;v_existing public.workshop_schedule_recovery_receipts%rowtype;v_response jsonb;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF v_actor IS NULL OR v_key IS NULL OR v_key!~'^[A-Za-z0-9:_-]{8,160}$' THEN RETURN jsonb_build_object('ok',false,'error','invalid_idempotency_key','no_partial_save',true);END IF;
 IF NOT public.workshop_future_only_schedule_enabled() THEN RETURN jsonb_build_object('ok',true,'code','future_only_disabled','moved_count',0,'notification_delta',0);END IF;
 v_hash:=md5(jsonb_build_object('as_of',v_as_of,'contract_version',2)::text);
 PERFORM pg_advisory_xact_lock(hashtextextended('workshop-recovery-request:'||v_actor::text||':'||v_key,0));
 SELECT * INTO v_existing FROM public.workshop_schedule_recovery_receipts WHERE actor_user_id=v_actor AND idempotency_key=v_key;
 IF FOUND THEN IF v_existing.request_hash IS DISTINCT FROM v_hash THEN RETURN jsonb_build_object('ok',false,'error','idempotency_conflict','no_partial_save',true);END IF;RETURN v_existing.response||jsonb_build_object('replay',true);END IF;
 SELECT coalesce((value#>>'{}')::integer,15) INTO v_increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';v_increment:=greatest(1,coalesce(v_increment,15));
 v_start:=date_trunc('minute',greatest(v_as_of,clock_timestamp()))+((v_increment::text||' minutes')::interval);
 WHILE NOT public.workshop_calendar_minute_available(v_start) LOOP v_start:=v_start+((v_increment::text||' minutes')::interval);IF v_start>v_as_of+interval '14 days' THEN RETURN jsonb_build_object('ok',false,'error','no_future_operational_minute','no_partial_save',true);END IF;END LOOP;
 PERFORM pg_advisory_xact_lock(hashtextextended('workshop-future-only-recovery',0));
 FOR v_bay IN SELECT DISTINCT b.bay_id FROM public.workshop_bookings b WHERE b.bay_id IS NOT NULL AND b.deleted_at IS NULL AND b.status::text='planned' AND b.scheduled_start_at<v_as_of ORDER BY b.bay_id LOOP
  PERFORM public.workshop_lock_resources(v_bay.bay_id,NULL);
  BEGIN
   v_repack:=public.workshop_admin_repack_planned(v_bay.bay_id,v_start,jsonb_build_object('source','future_only_recovery','recover_overdue',true,'recovery_as_of',v_as_of,'request_id',v_key));
  EXCEPTION WHEN SQLSTATE '22023' THEN
   v_error:=SQLERRM;v_reason:=coalesce(substring(v_error from '"error": "([a-z0-9_]+)"'),'validation_conflict');
   v_skipped_count:=v_skipped_count+1;v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object('bay_id',v_bay.bay_id,'reason',v_reason));
   CONTINUE;
  END;
  v_count:=v_count+coalesce((v_repack->>'shifted_count')::integer,0);v_moved:=v_moved||coalesce(v_repack->'shifted_items','[]'::jsonb);
  SELECT s.code INTO v_stage FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=v_bay.bay_id;IF v_stage IS NOT NULL THEN PERFORM public.workshop_bump_station_revision(v_stage);END IF;
 END LOOP;
 IF v_count>0 THEN PERFORM public.workshop_bump_revision();END IF;
 v_response:=jsonb_build_object('ok',true,'code',CASE WHEN v_skipped_count>0 THEN 'overdue_planned_recovered_with_conflicts' ELSE 'overdue_planned_recovered' END,'replay',false,'as_of',v_as_of,'recovery_start',v_start,'moved_count',v_count,'moved_items',v_moved,'skipped_bay_count',v_skipped_count,'skipped_bays',v_skipped,'notification_delta',0,'no_partial_save',false);
 INSERT INTO public.workshop_schedule_recovery_receipts(actor_user_id,idempotency_key,request_hash,response) VALUES(v_actor,v_key,v_hash,v_response);RETURN v_response;
END $function$;
REVOKE ALL ON FUNCTION public.recover_overdue_planned_workshop_bookings(text,timestamptz) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.recover_overdue_planned_workshop_bookings(text,timestamptz) TO authenticated;
DO $post$ BEGIN
 IF pg_get_functiondef('public.recover_overdue_planned_workshop_bookings(text,timestamptz)'::regprocedure) NOT LIKE '%v_reason:=coalesce(substring%'
 OR pg_get_functiondef('public.recover_overdue_planned_workshop_bookings(text,timestamptz)'::regprocedure) NOT LIKE '%overdue_planned_recovered_with_conflicts%'
 THEN RAISE EXCEPTION 'PDC_461_POSTCONDITION_FAILED' USING errcode='55000';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827011000','461_workshop_recovery_validation_containment',ARRAY['Each SQLSTATE 22023 booking-validation conflict leaves only its own bay unchanged and is reported in the recovery receipt','Security, identity, permission and non-validation failures still raise; other bays continue future-only recovery','Production untouched']);
NOTIFY pgrst,'reload schema';COMMIT;
