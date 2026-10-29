-- r730 rollback: puts the sublet_rule_20261029 + r721 body of set_vehicle_work_category back (md5
-- b2de35bd65bd1021b4dfc14410244dc4), moves the pin and the r568 literal back, removes the F341 check.
-- Staging cdsmnqxtyyoeoznmbidd only. No vehicle, booking, line or tick changes.
DO $down730$
DECLARE v_oid oid; v_src text; v_new text; v_def text; v_live text;
  c_new_len text := $n$    mins:=coalesce(public.workshop_booking_capacity_duration_minutes(rec.id,v.id,rec.stage_id,rec.bay_id),pdc_work_categories_private.minutes(rec.id,v.id,rec.stage_id));
    IF mins IS NOT NULL AND mins>=1 THEN
     -- r730 (F341): the validator's minutes, no 60 minute clamp (r372 accepts a shorter booking that equals the estimate).
     new_end:=public.workshop_add_operational_minutes(rec.scheduled_start_at,mins);
     -- r680 (F290): a start that has passed cannot be resized (planner past_start); keep its length.
     IF rec.scheduled_start_at >= clock_timestamp() AND (mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at) THEN
      BEGIN
       UPDATE public.workshop_bookings SET default_duration_minutes=mins, scheduled_end_at=new_end, version=version+1, updated_by=auth.uid(), updated_at=clock_timestamp()
        WHERE id=rec.id AND vehicle_id=v.id AND deleted_at IS NULL AND status IN('planned','queued') AND actual_start_at IS NULL AND version=rec.version;
       GET DIAGNOSTICS n=ROW_COUNT;
       IF n<>1 THEN RAISE EXCEPTION 'resize_missed'; END IF;
      EXCEPTION WHEN OTHERS THEN
       -- r730 (F341): the bay is full behind this job. Push the later jobs in the bay (and this vehicle's later
       -- stations) with the planner cascade, the same push-later Schedule uses, then lengthen. Started jobs never move.
       BEGIN
        IF rec.bay_id IS NULL THEN RAISE EXCEPTION 'no_bay'; END IF;
        r:=pdc_bay_seq_private.plan_for_move(rec.id,rec.bay_id,rec.scheduled_start_at);
        IF coalesce((r->>'ok')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'plan: %', coalesce(r->>'error','refused'); END IF;
        IF coalesce((r->>'count')::integer,0)>0 THEN
         r:=pdc_bay_seq_private.p_apply(jsonb_build_object('source','category_release_536','release','r730','line_identity',p_line_identity,'category',p_category,'pushed_for_booking_id',rec.id),'pushed_for_earlier_stage');
         IF coalesce((r->>'ok')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'push: %', coalesce(r->>'error','refused'); END IF;
        END IF;
        UPDATE public.workshop_bookings SET default_duration_minutes=mins, scheduled_end_at=new_end, version=version+1, updated_by=auth.uid(), updated_at=clock_timestamp()
         WHERE id=rec.id AND vehicle_id=v.id AND deleted_at IS NULL AND status IN('planned','queued') AND actual_start_at IS NULL;
        GET DIAGNOSTICS n=ROW_COUNT;
        IF n<>1 THEN RAISE EXCEPTION 'resize_missed'; END IF;
       EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'The category was not saved. The % booking (%) could not be lengthened: the bay is full behind it and the later jobs could not be pushed (%). Move a job in that bay first.', target, rec.bay_name, left(SQLERRM,120);
       END;
      END;$n$;
  c_old_len text := $o$    mins:=pdc_work_categories_private.minutes(rec.id,v.id,rec.stage_id);
    IF mins IS NOT NULL AND mins>=1 THEN
     IF mins<60 THEN mins:=60; END IF; -- r680 (F290): bookings are never under 60 minutes (r372 guard)
     new_end:=public.workshop_add_operational_minutes(rec.scheduled_start_at,mins);
     -- r680 (F290): a start that has passed cannot be resized (planner past_start); keep its length.
     IF rec.scheduled_start_at >= clock_timestamp() AND (mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at) THEN
      BEGIN
       UPDATE public.workshop_bookings SET default_duration_minutes=mins, scheduled_end_at=new_end, version=version+1, updated_by=auth.uid(), updated_at=clock_timestamp()
        WHERE id=rec.id AND vehicle_id=v.id AND deleted_at IS NULL AND status IN('planned','queued') AND actual_start_at IS NULL AND version=rec.version;
       GET DIAGNOSTICS n=ROW_COUNT;
       IF n<>1 THEN RAISE EXCEPTION 'resize_missed'; END IF;
      EXCEPTION WHEN OTHERS THEN
       RAISE EXCEPTION 'The category was not saved. The unstarted booking could not be lengthened.';
      END;$o$;
  c_new_short text := $n$    mins:=coalesce(public.workshop_booking_capacity_duration_minutes(rec.id,v.id,rec.stage_id,rec.bay_id),pdc_work_categories_private.minutes(rec.id,v.id,rec.stage_id));
    IF mins IS NULL OR mins<1 THEN$n$;
  c_old_short text := $o$    mins:=pdc_work_categories_private.minutes(rec.id,v.id,rec.stage_id);
    IF mins IS NULL OR mins<1 THEN$o$;
  c_new_clamp text := $n$     -- r730 (F341): the validator's minutes, no 60 minute clamp (r372 accepts a shorter booking that equals the estimate).
     new_end:=public.workshop_add_operational_minutes(rec.scheduled_start_at,mins);
     -- r680 (F290): a start that has passed cannot be resized (planner past_start); keep its length.
     IF rec.scheduled_start_at >= clock_timestamp() AND (mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at) THEN
      BEGIN
       UPDATE public.workshop_bookings SET default_duration_minutes=mins, scheduled_end_at=new_end, version=version+1, updated_by=auth.uid(), updated_at=clock_timestamp()
        WHERE id=rec.id AND vehicle_id=v.id AND deleted_at IS NULL AND status IN('planned','queued') AND actual_start_at IS NULL AND version=rec.version;
       GET DIAGNOSTICS n=ROW_COUNT;
       IF n<>1 THEN RAISE EXCEPTION 'resize_missed'; END IF;
      EXCEPTION WHEN OTHERS THEN
       RAISE EXCEPTION 'The category was not saved. The % booking (%) could not be shortened (%).', src_stage, rec.bay_name, left(SQLERRM,120);
      END;$n$;
  c_old_clamp text := $o$     IF mins<60 THEN mins:=60; END IF; -- r680 (F290): bookings are never under 60 minutes (r372 guard)
     new_end:=public.workshop_add_operational_minutes(rec.scheduled_start_at,mins);
     -- r680 (F290): a start that has passed cannot be resized (planner past_start); keep its length.
     IF rec.scheduled_start_at >= clock_timestamp() AND (mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at) THEN
      BEGIN
       UPDATE public.workshop_bookings SET default_duration_minutes=mins, scheduled_end_at=new_end, version=version+1, updated_by=auth.uid(), updated_at=clock_timestamp()
        WHERE id=rec.id AND vehicle_id=v.id AND deleted_at IS NULL AND status IN('planned','queued') AND actual_start_at IS NULL AND version=rec.version;
       GET DIAGNOSTICS n=ROW_COUNT;
       IF n<>1 THEN RAISE EXCEPTION 'resize_missed'; END IF;
      EXCEPTION WHEN OTHERS THEN
       RAISE EXCEPTION 'The category was not saved. The unstarted booking could not be shortened.';
      END;$o$;
  c_new_loop1 text := $n$  FOR rec IN SELECT b.id, b.version, b.stage_id, b.bay_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, b.work_category, s.code AS stage_code,
    coalesce(bay.display_name,'no bay') AS bay_name$n$;
  c_old_loop1 text := $o$  FOR rec IN SELECT b.id, b.version, b.stage_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, b.work_category, s.code AS stage_code,
    coalesce(bay.display_name,'no bay') AS bay_name$o$;
  c_new_loop2 text := $n$   FOR rec IN SELECT b.id, b.version, b.stage_id, b.bay_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, coalesce(bay.display_name,'no bay') AS bay_name$n$;
  c_old_loop2 text := $o$   FOR rec IN SELECT b.id, b.version, b.stage_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, coalesce(bay.display_name,'no bay') AS bay_name$o$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r730 down: staging only'; END IF;
  v_oid := to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)');
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  v_live := md5(v_src);
  IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND release = 'sublet_rule_20261029') IS DISTINCT FROM v_live THEN
    RAISE EXCEPTION 'r730 down: the live body is not the pinned r730 body';
  END IF;
  v_new := replace(v_src, c_new_len, c_old_len);
  v_new := replace(v_new, c_new_short, c_old_short);
  v_new := replace(v_new, c_new_clamp, c_old_clamp);
  v_new := replace(v_new, c_new_loop1, c_old_loop1);
  v_new := replace(v_new, c_new_loop2, c_old_loop2);
  IF md5(v_new) IS DISTINCT FROM 'b2de35bd65bd1021b4dfc14410244dc4' THEN RAISE EXCEPTION 'r730 down: restored body is not b2de35bd65bd1021b4dfc14410244dc4 (%)', md5(v_new); END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  EXECUTE replace(v_def, v_src, v_new);
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = 'b2de35bd65bd1021b4dfc14410244dc4', note = regexp_replace(coalesce(note,''),'; r730 \(F341\).*$',''), updated_at = clock_timestamp()
  WHERE signature = 'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND release = 'sublet_rule_20261029';
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_live, 'b2de35bd65bd1021b4dfc14410244dc4') WHERE check_name = 'bus_component_split_568';
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'category_move_full_bay_730';
END $down730$;
