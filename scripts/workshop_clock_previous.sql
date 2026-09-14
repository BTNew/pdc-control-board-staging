CREATE OR REPLACE FUNCTION public.workshop_clock_tick(p_apply boolean DEFAULT true, p_now timestamp with time zone DEFAULT clock_timestamp())
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
 SET lock_timeout TO '3s'
 SET statement_timeout TO '50s'
AS $function$
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
END $function$

