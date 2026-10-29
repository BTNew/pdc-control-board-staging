-- r730 (F341): moving a category between jobs on a full board.
-- Craig Watson, 29 Oct 2026 20:14 AWST: moving categories between jobs must work tomorrow, with the bays booked out.
--
-- Fault. set_vehicle_work_category resizes the unstarted booking of the old station and of the new station with a
-- direct UPDATE. Two things made that UPDATE fail on tonight's board (6 of 15 category saves since 28 Oct, and 3 of 6
-- in a rolled-back trial at 20:30 AWST):
--  1. r680 clamped every resized booking to at least 60 minutes. The planner validation (r537) requires the booking
--     length to equal the live estimate, and the r372 guard already accepts a shorter booking when it equals that
--     estimate. A job card line under an hour (16 min, 53 min) therefore failed with
--     "The category was not saved. The unstarted booking could not be shortened."
--  2. Lengthening the new station's booking in place overlapped the next job in that bay, so it failed with
--     "The category was not saved. The unstarted booking could not be lengthened." The planner's own cascade
--     (r424 plan_for_move / p_apply, the push-later used by Schedule) was not tried.
--
-- Fix, in place, same signature and pins kept: the resize uses the validator's own minutes
-- (workshop_booking_capacity_duration_minutes) with no clamp, and when a lengthen overlaps the bay it pushes the later
-- jobs in that bay (and this vehicle's later stations) with the planner cascade, then lengthens. A started or stopped
-- job is never moved; if the cascade cannot make room the category save still refuses, naming the bay.
-- Nothing else in the function changes. The sublet_rule_20261029 pin row moves to the new body; pin count stays 241.
--
-- Staging cdsmnqxtyyoeoznmbidd only. Production never touched. No vehicle, booking, line or tick changes.
-- Rollback: supabase/rollbacks/20261029220000_r730_category_move_on_full_bay.down.sql

DO $r730$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  v_oid oid; v_src text; v_new text; v_def text; v_n integer;
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
  c_old_short text := $o$    mins:=pdc_work_categories_private.minutes(rec.id,v.id,rec.stage_id);
    IF mins IS NULL OR mins<1 THEN$o$;
  c_new_short text := $n$    mins:=coalesce(public.workshop_booking_capacity_duration_minutes(rec.id,v.id,rec.stage_id,rec.bay_id),pdc_work_categories_private.minutes(rec.id,v.id,rec.stage_id));
    IF mins IS NULL OR mins<1 THEN$n$;
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
  c_old_loop1 text := $o$  FOR rec IN SELECT b.id, b.version, b.stage_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, b.work_category, s.code AS stage_code,
    coalesce(bay.display_name,'no bay') AS bay_name$o$;
  c_new_loop1 text := $n$  FOR rec IN SELECT b.id, b.version, b.stage_id, b.bay_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, b.work_category, s.code AS stage_code,
    coalesce(bay.display_name,'no bay') AS bay_name$n$;
  c_old_loop2 text := $o$   FOR rec IN SELECT b.id, b.version, b.stage_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, coalesce(bay.display_name,'no bay') AS bay_name$o$;
  c_new_loop2 text := $n$   FOR rec IN SELECT b.id, b.version, b.stage_id, b.bay_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, coalesce(bay.display_name,'no bay') AS bay_name$n$;
BEGIN
  IF awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r730: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r730: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r730: an import job is running'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r730: pin count is not 241'; END IF;
  v_oid := to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)');
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF md5(v_src) IS DISTINCT FROM 'b2de35bd65bd1021b4dfc14410244dc4' THEN RAISE EXCEPTION 'r730: set_vehicle_work_category is not the sublet_rule_20261029 + r721 body (%)', md5(v_src); END IF;
  IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND release = 'sublet_rule_20261029') IS DISTINCT FROM 'b2de35bd65bd1021b4dfc14410244dc4' THEN
    RAISE EXCEPTION 'r730: the category pin is not where r729 left it';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'bus_component_split_568' AND strpos(check_sql, 'b2de35bd65bd1021b4dfc14410244dc4') > 0) <> 1 THEN RAISE EXCEPTION 'r730: run r729 first (bus_component_split_568 literal)'; END IF;
  -- each anchor exactly once, and the two resize blocks are where this file expects them
  IF (SELECT count(*) FROM regexp_matches(v_src, '\mmins:=pdc_work_categories_private\.minutes\(rec\.id,v\.id,rec\.stage_id\);', 'g')) <> 2 THEN RAISE EXCEPTION 'r730: anchor minutes'; END IF;
  IF (length(v_src) - length(replace(v_src, c_old_len, ''))) / length(c_old_len) <> 1 THEN RAISE EXCEPTION 'r730: anchor lengthen block'; END IF;
  IF (length(v_src) - length(replace(v_src, c_old_short, ''))) / length(c_old_short) <> 1 THEN RAISE EXCEPTION 'r730: anchor shorten minutes'; END IF;
  IF (length(v_src) - length(replace(v_src, c_old_clamp, ''))) / length(c_old_clamp) <> 1 THEN RAISE EXCEPTION 'r730: anchor shorten block'; END IF;
  IF (length(v_src) - length(replace(v_src, c_old_loop1, ''))) / length(c_old_loop1) <> 1 THEN RAISE EXCEPTION 'r730: anchor loop 1'; END IF;
  IF (length(v_src) - length(replace(v_src, c_old_loop2, ''))) / length(c_old_loop2) <> 1 THEN RAISE EXCEPTION 'r730: anchor loop 2'; END IF;
  v_new := replace(v_src, c_old_len, c_new_len);
  v_new := replace(v_new, c_old_short, c_new_short);
  v_new := replace(v_new, c_old_clamp, c_new_clamp);
  v_new := replace(v_new, c_old_loop1, c_new_loop1);
  v_new := replace(v_new, c_old_loop2, c_new_loop2);
  IF strpos(v_new, 'IF mins<60 THEN mins:=60; END IF;') > 0 THEN RAISE EXCEPTION 'r730: a clamp survived'; END IF;
  IF (SELECT count(*) FROM regexp_matches(v_new, 'workshop_booking_capacity_duration_minutes\(rec\.id,v\.id,rec\.stage_id,rec\.bay_id\)', 'g')) <> 2 THEN RAISE EXCEPTION 'r730: minutes not replaced twice'; END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_def := replace(v_def, v_src, v_new);
  IF v_def = pg_get_functiondef(v_oid) THEN RAISE EXCEPTION 'r730: definition unchanged'; END IF;
  EXECUTE v_def;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF v_src <> v_new THEN RAISE EXCEPTION 'r730: body readback differs'; END IF;
  UPDATE pdc_ops.expected_function_md5
  SET prosrc_md5 = md5(v_new), note = coalesce(note,'') || '; r730 (F341): resize uses the validator minutes, lengthen on a full bay cascades; was b2de35bd65bd1021b4dfc14410244dc4', updated_at = clock_timestamp()
  WHERE signature = 'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND release = 'sublet_rule_20261029';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r730: pin not moved'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'b2de35bd65bd1021b4dfc14410244dc4', md5(v_new)) WHERE check_name = 'bus_component_split_568';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r730: check literal not moved'; END IF;
  RAISE NOTICE 'r730: set_vehicle_work_category now %', md5(v_new);
END $r730$;

INSERT INTO pdc_ops.regression_checks(check_name, sort_order, fault_id, added_in, enabled, description, check_sql)
VALUES ('category_move_full_bay_730', 453, 'F341', 'r730', true,
  'set_vehicle_work_category resizes with the validator minutes (no 60 minute clamp) and pushes the bay with the planner cascade before refusing a lengthen; the pin and the r536/r538 checks follow it.',
  $chk$
WITH f AS (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')),
pin AS (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature = 'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND e.release = 'sublet_rule_20261029')
SELECT (SELECT pg_catalog.strpos(prosrc, 'IF mins<60 THEN mins:=60; END IF;') FROM f) = 0
   AND (SELECT pg_catalog.strpos(prosrc, 'r730 (F341)') FROM f) > 0
   AND (SELECT pg_catalog.strpos(prosrc, 'pdc_bay_seq_private.plan_for_move(rec.id,rec.bay_id,rec.scheduled_start_at)') FROM f) > 0
   AND (SELECT pg_catalog.strpos(prosrc, 'pdc_bay_seq_private.p_apply(') FROM f) > 0
   AND (SELECT pg_catalog.strpos(prosrc, 'workshop_booking_capacity_duration_minutes(rec.id,v.id,rec.stage_id,rec.bay_id)') FROM f) > 0
   AND (SELECT pg_catalog.md5(prosrc) FROM f) = (SELECT prosrc_md5 FROM pin) AS ok,
  'category move r730, pin '||coalesce((SELECT pg_catalog.left(prosrc_md5,8) FROM pin),'missing') AS detail
$chk$);

DO $post730$
DECLARE r record; v_red text := ''; v_n integer := 0;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x
   WHERE x.check_name IN ('category_move_full_bay_730','category_unstarted_release_536','running_booking_end_538','bus_component_split_568','bus_whole_job_450','protected_function_md5s','regression_checks_self_test')
  LOOP
    v_n := v_n + 1;
    IF NOT r.ok THEN v_red := v_red || r.check_name || ' (' || left(r.detail, 160) || '); '; END IF;
  END LOOP;
  IF v_n <> 7 THEN RAISE EXCEPTION 'r730: expected 7 checks, saw %', v_n; END IF;
  IF v_red <> '' THEN RAISE EXCEPTION 'r730: red after apply, rolled back: %', v_red; END IF;
  RAISE NOTICE 'r730: 7 checks green';
END $post730$;
