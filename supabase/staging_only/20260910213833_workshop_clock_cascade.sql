-- STAGING only. Craig requested automatic workshop delay propagation on 11 September 2026.
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING target mismatch'; END IF;
 IF pg_get_functiondef('public.recover_overdue_planned_workshop_bookings(text,timestamptz)'::regprocedure) IS DISTINCT FROM $prior$CREATE OR REPLACE FUNCTION public.recover_overdue_planned_workshop_bookings(p_idempotency_key text, p_as_of timestamp with time zone DEFAULT clock_timestamp())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
END $function$
$prior$ THEN RAISE EXCEPTION 'Recovery routine changed; rebase before deploying'; END IF;
END $guard$;
-- Calendar-aware, forward-only plan for one bay. Pure planning: no operational writes.
CREATE OR REPLACE FUNCTION public.workshop_clock_next_minute(p_at timestamptz)
RETURNS timestamptz LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE t timestamptz:=date_trunc('minute',p_at); limit_at timestamptz:=p_at+interval '90 days';
BEGIN
 IF t<p_at THEN t:=t+interval '1 minute'; END IF;
 WHILE NOT public.workshop_calendar_minute_available(t) LOOP
  t:=t+interval '1 minute';
  IF t>limit_at THEN RAISE EXCEPTION 'No workshop opening within 90 days' USING errcode='22023'; END IF;
 END LOOP;
 RETURN t;
END $$;
REVOKE ALL ON FUNCTION public.workshop_clock_next_minute(timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.workshop_clock_plan(p_rows jsonb,p_blocks jsonb,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE r jsonb; live jsonb; block jsonb; orig timestamptz; proposed timestamptz; finish timestamptz;
 floor_at timestamptz:=public.workshop_clock_next_minute(p_now); cursor_at timestamptz;
 live_end timestamptz; prior_end timestamptz; obstacle_end timestamptz;
 delay_minutes integer:=0; need integer; duration integer; guard integer;
 moves jsonb:='[]'; marks jsonb:='[]';
BEGIN
 IF jsonb_typeof(p_rows)<>'array' OR jsonb_typeof(p_blocks)<>'array' OR p_now IS NULL THEN RAISE EXCEPTION 'Invalid clock plan'; END IF;
 FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage') LOOP
  prior_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'accounted_through')::timestamptz,(live->>'end')::timestamptz));
  live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz),floor_at);
  marks:=marks||jsonb_build_array(jsonb_build_object('id',live->>'id','through',greatest(prior_end,live_end)));
 END LOOP;
 FOR r IN SELECT x FROM jsonb_array_elements(p_rows) x
  WHERE x->>'status'='planned' AND nullif(x->>'actual_start','') IS NULL
  ORDER BY (x->>'start')::timestamptz,x->>'id'
 LOOP
  orig:=(r->>'start')::timestamptz; duration:=(r->>'duration')::integer;
  IF duration IS NULL OR duration<1 THEN RAISE EXCEPTION 'Missing planned duration' USING errcode='22023'; END IF;
  -- Apply only the new live delay since the last successful clock transaction.
  FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage') AND (x->>'start')::timestamptz<=orig LOOP
   prior_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'accounted_through')::timestamptz,(live->>'end')::timestamptz));
   live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz),floor_at);
   delay_minutes:=greatest(delay_minutes,public.workshop_operational_minutes_between(prior_end,live_end));
  END LOOP;
  proposed:=public.workshop_clock_next_minute(greatest(public.workshop_add_operational_minutes(orig,delay_minutes),floor_at,coalesce(cursor_at,orig)));
  guard:=0;
  LOOP
   guard:=guard+1; IF guard>1000 THEN RAISE EXCEPTION 'Clock obstacle limit' USING errcode='22023'; END IF;
   finish:=public.workshop_add_operational_minutes(proposed,duration);
   obstacle_end:=NULL;
   -- Admin reservations and started work retain their real positions.
   FOR block IN SELECT x FROM jsonb_array_elements(p_blocks) x LOOP
    IF (block->>'start')::timestamptz<finish AND (block->>'end')::timestamptz>proposed THEN obstacle_end:=greatest(obstacle_end,(block->>'end')::timestamptz); END IF;
   END LOOP;
   FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage','queued') OR nullif(x->>'actual_start','') IS NOT NULL LOOP
    live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz));
    IF live->>'status' IN ('started','stoppage') THEN live_end:=greatest(live_end,floor_at); END IF;
    IF (live->>'start')::timestamptz<finish AND live_end>proposed THEN obstacle_end:=greatest(obstacle_end,live_end); END IF;
   END LOOP;
   EXIT WHEN obstacle_end IS NULL;
   proposed:=public.workshop_clock_next_minute(obstacle_end);
  END LOOP;
  -- Preserve all future gaps: carry the accumulated working-time delay weeks ahead.
  need:=public.workshop_operational_minutes_between(orig,proposed);
  delay_minutes:=greatest(delay_minutes,need);
  IF proposed IS DISTINCT FROM orig OR finish IS DISTINCT FROM (r->>'end')::timestamptz THEN
   moves:=moves||jsonb_build_array(jsonb_build_object('id',r->>'id','from',orig,'to',proposed,'end',finish,'duration',duration));
  END IF;
  cursor_at:=finish;
 END LOOP;
 RETURN jsonb_build_object('moves',moves,'watermarks',marks,'floor',floor_at);
END $$;
REVOKE ALL ON FUNCTION public.workshop_clock_plan(jsonb,jsonb,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE public.workshop_clock_watermarks(booking_id uuid PRIMARY KEY,accounted_through timestamptz NOT NULL,updated_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE public.workshop_clock_history(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,booking_id uuid NOT NULL,bay_id uuid NOT NULL,clock_at timestamptz NOT NULL,before_data jsonb NOT NULL,after_data jsonb NOT NULL,actor_kind text NOT NULL DEFAULT 'automatic_workshop_clock',created_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE public.workshop_clock_status(bay_id uuid PRIMARY KEY,last_checked_at timestamptz NOT NULL,last_success_at timestamptz,error_code text,error_detail text,moved_count integer NOT NULL DEFAULT 0);
ALTER TABLE public.workshop_clock_watermarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workshop_clock_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workshop_clock_status ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.workshop_clock_watermarks,public.workshop_clock_history,public.workshop_clock_status FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE public.workshop_clock_history_id_seq FROM PUBLIC,anon,authenticated,service_role;

-- Invoker-only private worker: the scheduler and existing authenticated snapshot wrapper
-- execute as their database owner. No new application role or user credential is granted.
CREATE OR REPLACE FUNCTION public.workshop_clock_tick(p_apply boolean DEFAULT true,p_now timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,public SET lock_timeout='3s' SET statement_timeout='50s' AS $$
DECLARE bay record; b record; m jsonb; mark jsonb; rows jsonb; blocks jsonb; plan jsonb; before_row jsonb; after_row jsonb;
 moved integer:=0; bay_moved integer; plans jsonb:='[]'; issues jsonb:='[]'; state_code text; detail text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING only'; END IF;
 IF NOT public.workshop_future_only_schedule_enabled() THEN RETURN jsonb_build_object('ok',true,'disabled',true,'moved_count',0); END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0)) THEN RETURN jsonb_build_object('ok',true,'busy',true,'moved_count',0); END IF;
 FOR bay IN SELECT DISTINCT y.id,y.stage_id,s.code FROM public.workshop_bays y JOIN public.workshop_stages s ON s.id=y.stage_id
  WHERE y.is_active AND s.active AND s.planner_enabled AND EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.bay_id=y.id AND x.deleted_at IS NULL AND
   ((x.status='planned' AND x.actual_start_at IS NULL AND x.scheduled_start_at<p_now)
    OR (x.status IN ('started','stoppage') AND public.workshop_booking_effective_end_at(x.id)>=x.scheduled_end_at)))
  ORDER BY y.id
 LOOP
  BEGIN
   PERFORM public.workshop_lock_resources(bay.id,NULL);
   PERFORM 1 FROM public.workshop_bookings WHERE bay_id=bay.id AND deleted_at IS NULL ORDER BY id FOR UPDATE;
   SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'status',x.status,'start',x.scheduled_start_at,'end',x.scheduled_end_at,
    'effective_end',public.workshop_booking_effective_end_at(x.id),'duration',x.default_duration_minutes,'actual_start',x.actual_start_at,
    'accounted_through',w.accounted_through)),'[]') INTO rows
   FROM public.workshop_bookings x LEFT JOIN public.workshop_clock_watermarks w ON w.booking_id=x.id
   WHERE x.bay_id=bay.id AND x.deleted_at IS NULL AND x.status IN ('planned','queued','started','stoppage');
   SELECT coalesce(jsonb_agg(jsonb_build_object('start',scheduled_start_at,'end',scheduled_end_at)),'[]') INTO blocks
    FROM public.workshop_admin_blocks WHERE bay_id=bay.id AND deleted_at IS NULL AND scheduled_end_at>=p_now;
   plan:=public.workshop_clock_plan(rows,blocks,p_now); bay_moved:=0;
   IF p_apply THEN
    -- Vacate the latest planned rows first. Existing validation/overlap/ETA guards run.
    FOR m IN SELECT x FROM jsonb_array_elements(plan->'moves') x ORDER BY (x->>'from')::timestamptz DESC,x->>'id' DESC LOOP
     SELECT * INTO STRICT b FROM public.workshop_bookings WHERE id=(m->>'id')::uuid FOR UPDATE;
     before_row:=to_jsonb(b);
     IF b.status<>'planned' OR b.actual_start_at IS NOT NULL OR b.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Clock booking changed' USING errcode='40001'; END IF;
     UPDATE public.workshop_bookings SET scheduled_start_at=(m->>'to')::timestamptz,scheduled_end_at=(m->>'end')::timestamptz,
      version=version+1,updated_by=coalesce(auth.uid(),updated_by),updated_at=clock_timestamp()
      WHERE id=b.id AND version=b.version;
     IF NOT FOUND THEN RAISE EXCEPTION 'Clock version conflict' USING errcode='40001'; END IF;
     UPDATE public.workshop_booking_assignments SET scheduled_start_at=(m->>'to')::timestamptz,scheduled_end_at=(m->>'end')::timestamptz,updated_at=clock_timestamp()
      WHERE booking_id=b.id AND released_at IS NULL;
     SELECT to_jsonb(x) INTO after_row FROM public.workshop_bookings x WHERE id=b.id;
     INSERT INTO public.workshop_clock_history(booking_id,bay_id,clock_at,before_data,after_data) VALUES(b.id,bay.id,p_now,before_row,after_row);
     bay_moved:=bay_moved+1;
    END LOOP;
    FOR mark IN SELECT x FROM jsonb_array_elements(plan->'watermarks') x LOOP
     INSERT INTO public.workshop_clock_watermarks(booking_id,accounted_through) VALUES((mark->>'id')::uuid,(mark->>'through')::timestamptz)
     ON CONFLICT(booking_id) DO UPDATE SET accounted_through=greatest(public.workshop_clock_watermarks.accounted_through,excluded.accounted_through),updated_at=clock_timestamp();
    END LOOP;
    INSERT INTO public.workshop_clock_status(bay_id,last_checked_at,last_success_at,moved_count) VALUES(bay.id,p_now,p_now,bay_moved)
     ON CONFLICT(bay_id) DO UPDATE SET last_checked_at=excluded.last_checked_at,last_success_at=excluded.last_success_at,error_code=NULL,error_detail=NULL,moved_count=excluded.moved_count;
   END IF;
   moved:=moved+bay_moved; plans:=plans||jsonb_build_array(jsonb_build_object('bay_id',bay.id,'stage',bay.code,'plan',plan));
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '23514' OR SQLSTATE '23P01' OR SQLSTATE '40001' OR lock_not_available THEN
   GET STACKED DIAGNOSTICS state_code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
   issues:=issues||jsonb_build_array(jsonb_build_object('bay_id',bay.id,'stage',bay.code,'code',state_code,'detail',detail));
   IF p_apply THEN INSERT INTO public.workshop_clock_status(bay_id,last_checked_at,error_code,error_detail) VALUES(bay.id,p_now,state_code,detail)
    ON CONFLICT(bay_id) DO UPDATE SET last_checked_at=excluded.last_checked_at,error_code=excluded.error_code,error_detail=excluded.error_detail,moved_count=0; END IF;
  END;
 END LOOP;
 IF p_apply AND moved>0 THEN PERFORM public.workshop_bump_revision(); END IF;
 RETURN jsonb_build_object('ok',jsonb_array_length(issues)=0,'clock_at',p_now,'applied',p_apply,'moved_count',moved,'plans',plans,'issues',issues);
END $$;
REVOKE ALL ON FUNCTION public.workshop_clock_tick(boolean,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.recover_overdue_planned_workshop_bookings(p_idempotency_key text,p_as_of timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); key text:=nullif(btrim(p_idempotency_key),''); old public.workshop_schedule_recovery_receipts%rowtype;
 hash text; body jsonb; as_of timestamptz:=coalesce(p_as_of,clock_timestamp());
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF actor IS NULL OR key IS NULL OR key!~'^[A-Za-z0-9:_-]{8,160}$' THEN RETURN jsonb_build_object('ok',false,'error','invalid_idempotency_key'); END IF;
 -- Snapshots share the single server clock. Read refreshes do not accumulate empty receipts.
 IF key LIKE 'snapshot-%' THEN RETURN public.workshop_clock_tick(true,clock_timestamp()); END IF;
 hash:=md5(jsonb_build_object('as_of',as_of,'contract_version',3)::text);
 PERFORM pg_advisory_xact_lock(hashtextextended('workshop-recovery-request:'||actor::text||':'||key,0));
 SELECT * INTO old FROM public.workshop_schedule_recovery_receipts WHERE actor_user_id=actor AND idempotency_key=key;
 IF FOUND THEN
  IF old.request_hash NOT IN (hash,md5(jsonb_build_object('as_of',as_of,'contract_version',2)::text)) THEN RETURN jsonb_build_object('ok',false,'error','idempotency_conflict'); END IF;
  RETURN old.response||jsonb_build_object('replay',true);
 END IF;
 -- The current server time, not a caller-supplied future time, controls live movement.
 body:=public.workshop_clock_tick(true,clock_timestamp())||jsonb_build_object('code','workshop_clock_cascaded','replay',false,'notification_delta',0);
 INSERT INTO public.workshop_schedule_recovery_receipts(actor_user_id,idempotency_key,request_hash,response) VALUES(actor,key,hash,body);
 RETURN body;
END $$;
-- Existing function ACL is intentionally preserved by CREATE OR REPLACE.
CREATE INDEX workshop_clock_history_booking_time ON public.workshop_clock_history(booking_id,created_at);
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('staging-workshop-clock-cascade','* * * * *','SELECT public.workshop_clock_tick(true,clock_timestamp());');
