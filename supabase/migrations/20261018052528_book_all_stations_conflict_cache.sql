-- Cache canonical booking ends once per station, preserving the mutation lock and all checks.
DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL OR NOT pdc_codex_intake_private.management_connection() THEN RAISE EXCEPTION 'staging_management_required'; END IF; END $guard$;
DO $version$ BEGIN IF md5(replace(pg_get_functiondef('public.book_all_vehicle_stations(uuid,integer)'::regprocedure),chr(13),'')) <> 'd0174fab5eb09fb81a534ed1f4f8098f' THEN RAISE EXCEPTION 'reviewed_booking_function_changed'; END IF; END $version$;
CREATE OR REPLACE FUNCTION public.book_all_vehicle_stations(p_vehicle_id uuid, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v public.vehicles%rowtype; st record; bay record; item jsonb; result jsonb;
 pending jsonb:='[]'; booked jsonb:='[]'; skipped jsonb:='[]';
 minutes integer; best_minutes integer; increment integer; current_version integer;
 earliest timestamptz; horizon timestamptz; candidate timestamptz; finish timestamptz;
 blocked_until timestamptz; away_date date; best_start timestamptz; best_end timestamptz; best_bay integer;
 calendar_bay uuid;
 failure text; failure_code text;
 busy_rows jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'This action is available on staging only.'; END IF;
 PERFORM public.workshop_require_planner_operator();
 PERFORM public.workshop_require_version(p_expected_version);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state<>'active' OR NOT v.visible_on_board THEN
  RAISE EXCEPTION 'This vehicle is not available for workshop booking.' USING DETAIL='vehicle_inactive_or_missing';
 END IF;
 IF v.version<>p_expected_version THEN RAISE EXCEPTION 'This vehicle changed. Refresh and try again.' USING DETAIL='vehicle_version_conflict'; END IF;
 IF public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) NOT IN('PMB','YH','IT') OR coalesce(nullif(v.location_override,''),v.current_location) IS NULL THEN
  RAISE EXCEPTION 'Workshop booking requires PMB, Yard Hold or In Transit with an ETA.' USING DETAIL='location_ineligible';
 END IF;
 IF public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))='IT' AND v.eta_to_kewdale IS NULL THEN
  RAISE EXCEPTION 'Enter an ETA to Kewdale before booking this vehicle.' USING DETAIL='it_eta_missing';
 END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='pending') THEN
  RAISE EXCEPTION 'Approve the New Vehicles review before booking.' USING DETAIL='new_vehicle_review_required';
 END IF;
 -- Preflight every requirement before making any booking.
 FOR st IN SELECT s.*,cat->>'work_category' work_category FROM public.workshop_stages s
 CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN s.code='BUS_4X4'
 THEN pdc_work_categories_private.vehicle_categories(v.id) ELSE '[{}]'::jsonb END) cat
  WHERE s.active AND s.planner_enabled AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET'
   AND EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND wi.required AND NOT wi.completed AND public.workshop_stage_code_for_work_key(wi.work_key)=s.code)
  ORDER BY s.sort_order,s.code
 LOOP
  IF st.work_category IS NOT NULL AND pdc_work_categories_private.completed(v.id,st.work_category) THEN CONTINUE; END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.stage_id=st.id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND (st.work_category IS NULL OR b.work_category IS NULL OR b.work_category=st.work_category) AND b.bay_id IS NULL) THEN
   RAISE EXCEPTION '% has an existing booking without a bay. Allocate or cancel that booking first.',st.display_name USING DETAIL='existing_booking_without_bay';
  END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.stage_id=st.id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND (st.work_category IS NULL OR b.work_category IS NULL OR b.work_category=st.work_category)) THEN
   skipped:=skipped||jsonb_build_array(jsonb_build_object('stage',st.display_name,'reason','Already booked')); CONTINUE;
  END IF;
  minutes:=CASE WHEN st.work_category IS NULL THEN public.workshop_vehicle_stage_estimated_duration_minutes(v.id,st.id) ELSE round(pdc_work_categories_private.hours(v.id,st.work_category)*60)::integer END;
  IF minutes IS NULL OR minutes<1 THEN RAISE EXCEPTION 'Confirm the hours for % before booking all stations.',st.display_name USING DETAIL='estimated_duration_missing'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.workshop_bays b WHERE b.stage_id=st.id AND b.is_active) THEN RAISE EXCEPTION 'No active bay is configured for %.',st.display_name USING DETAIL='no_active_bay'; END IF;
  pending:=pending||jsonb_build_array(jsonb_build_object('id',st.id,'code',st.code,'name',coalesce(st.work_category,st.display_name),'minutes',minutes,'work_category',st.work_category));
 END LOOP;
 IF jsonb_array_length(pending)=0 THEN RETURN jsonb_build_object('ok',true,'bookings',booked,'skipped',skipped,'message','No unbooked workshop stations remain.'); END IF;
 SELECT greatest(1,coalesce((value#>>'{}')::integer,15)) INTO increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
 increment:=coalesce(increment,15);
 earliest:=date_trunc('minute',clock_timestamp())+interval '1 minute';
 IF public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))='IT' THEN earliest:=greatest(earliest,(v.eta_to_kewdale+7)::timestamp AT TIME ZONE 'Australia/Perth'); END IF;
 horizon:=earliest+interval '300 days';
 FOR item IN SELECT value FROM jsonb_array_elements(pending) LOOP
  minutes:=(item->>'minutes')::integer; best_start:=NULL; best_end:=NULL; best_bay:=NULL;
  -- Freeze relevant conflicts once per station under the existing mutation lock.
  -- Rebuild after each saved station so all canonical effects remain visible.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
   'vehicle_id',b.vehicle_id,'bay_id',b.bay_id,'starts',b.scheduled_start_at,
   'ends',greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id),
    CASE WHEN b.status IN('started','stoppage') THEN now() ELSE b.scheduled_end_at END))),'[]')
   INTO busy_rows
   FROM public.workshop_bookings b
   WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
    AND (b.vehicle_id=v.id OR b.stage_id=(item->>'id')::uuid);
  FOR bay IN SELECT * FROM public.workshop_bays WHERE stage_id=(item->>'id')::uuid AND is_active AND (item->>'work_category' IS NULL OR pdc_work_categories_private.preferred_bay(item->>'work_category',bay_number)) ORDER BY bay_number LOOP
   -- Preferred category bays still have vehicle compatibility requirements.
   IF item->>'code'='BUS_4X4' AND (pdc_bus_private.booking_rule(v.id,bay.id,NULL)->>'ok') IS DISTINCT FROM 'true' THEN CONTINUE; END IF;
   calendar_bay:=CASE WHEN item->>'code'='BUS_4X4' AND pdc_bus_private.active_vehicle(v.id) THEN bay.id END;
   minutes:=public.workshop_capacity_duration_minutes((item->>'minutes')::numeric,bay.id);
   candidate:=to_timestamp(ceil(extract(epoch FROM earliest)/(increment*60))*(increment*60));
   WHILE candidate<horizon AND (best_start IS NULL OR candidate<best_start) LOOP
    IF NOT (CASE WHEN calendar_bay IS NULL THEN public.workshop_calendar_minute_available(candidate) ELSE pdc_bus_private.minute_available(candidate,calendar_bay) END) THEN candidate:=candidate+make_interval(mins=>increment); CONTINUE; END IF;
    finish:=pdc_bus_private.clock_add_minutes(candidate,minutes,calendar_bay);
    IF finish>horizon THEN EXIT; END IF;
    -- A vehicle cannot work in a bay while it is away with a Sublet provider.
    SELECT d::date INTO away_date FROM generate_series((candidate AT TIME ZONE 'Australia/Perth')::date::timestamp,((finish-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
     WHERE public.pdc_sublet_away_on_date(v.id,d::date) ORDER BY d DESC LIMIT 1;
    IF FOUND THEN candidate:=(away_date+1)::timestamp AT TIME ZONE 'Australia/Perth'; CONTINUE; END IF;
    SELECT max(x.next_at) INTO blocked_until FROM (
     SELECT CASE WHEN b.vehicle_id=v.id THEN e.ends+interval '1 hour' ELSE e.ends END next_at
     FROM jsonb_to_recordset(busy_rows) b(vehicle_id uuid,bay_id uuid,starts timestamptz,ends timestamptz)
     CROSS JOIN LATERAL(SELECT b.ends) e
     WHERE (b.vehicle_id=v.id OR b.bay_id=bay.id)
      AND ((b.vehicle_id=v.id AND b.starts<finish+interval '1 hour' AND e.ends+interval '1 hour'>candidate)
        OR (b.bay_id=bay.id AND b.starts<finish AND e.ends>candidate))
     UNION ALL
     SELECT a.scheduled_end_at FROM public.workshop_admin_blocks a WHERE a.deleted_at IS NULL AND a.bay_id=bay.id AND a.scheduled_start_at<finish AND a.scheduled_end_at>candidate
    ) x;
    IF blocked_until IS NOT NULL THEN
     candidate:=to_timestamp(ceil(extract(epoch FROM greatest(blocked_until,candidate+make_interval(mins=>increment)))/(increment*60))*(increment*60)); CONTINUE;
    END IF;
    best_start:=candidate; best_end:=finish; best_bay:=bay.bay_number; best_minutes:=minutes; EXIT;
   END LOOP;
  END LOOP;
  IF best_start IS NULL THEN RAISE EXCEPTION 'No available bay was found for % within the next 300 days.',item->>'name' USING DETAIL='no_available_slot'; END IF;
  SELECT version INTO current_version FROM public.vehicles WHERE id=v.id;
  result:=public.schedule_vehicle_work(v.id,current_version,item->>'code',best_bay,best_start,best_minutes,NULL,NULL,jsonb_build_object('source','book_all_stations','buffer_minutes',60,'work_category',item->>'work_category'));
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Could not book % (%). Refresh and try again.',item->>'name',coalesce(result->>'error','schedule rejected') USING DETAIL='booking_rejected'; END IF;
  booked:=booked||jsonb_build_array(jsonb_build_object('stage',item->>'name','bay',best_bay,'start_at',best_start,'end_at',best_end,'booking_id',coalesce(result#>>'{booking,booking_id}',result#>>'{booking,id}')));
 END LOOP;
 RETURN jsonb_build_object('ok',true,'bookings',booked,'skipped',skipped,'buffer_minutes',60);
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS failure=MESSAGE_TEXT,failure_code=PG_EXCEPTION_DETAIL;
 RETURN jsonb_build_object('ok',false,'error',coalesce(nullif(failure_code,''),SQLSTATE),'message',failure||' No new bookings were saved.');
END $function$;

