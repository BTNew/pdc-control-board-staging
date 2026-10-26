-- Undo r538 (F152). Staging cdsmnqxtyyoeoznmbidd only. Production is not touched.
-- Restores the r536 category function. Does not move a running booking's finish back.
-- Key 203 is not rewritten here.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r538 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r538 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r538 undo: pin count is not 241'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.set_vehicle_work_category(p_vehicle_id uuid, p_vehicle_expected_version integer, p_line_identity text, p_category text, p_category_expected_version integer DEFAULT 0, p_release_unstarted boolean DEFAULT false, p_batch jsonb DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v public.vehicles; l jsonb; old pdc_work_categories_private.line_overrides;
 target text:=pdc_work_categories_private.stage(p_category); src_stage text; old_cat text;
 msg text; parts text[]:=ARRAY[]::text[]; rec record; n integer; mins integer; added integer;
 new_end timestamptz; r jsonb; v_ht text; running_id uuid;
BEGIN
 -- r536 (F150): an unstarted booking is released or shortened when its lines move. A running job keeps its bay time.
 PERFORM public.workshop_require_planner_operator();
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL AND lifecycle_state='active' FOR UPDATE;
 IF NOT FOUND OR v.version IS DISTINCT FROM p_vehicle_expected_version THEN RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict'); END IF;
 SELECT x INTO l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) x
  WHERE x->>'line_identity'=p_line_identity AND coalesce((x->>'active')::boolean,true);
 IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'error','operation_not_found'); END IF;
 IF p_category NOT IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','HOIST','FABRICATION','FITTING','ELECTRICAL','TINT','TYRE','SUBLET')
 OR ((l->>'department'='138' OR l->>'stage_code'='BUS_4X4') AND p_category IN('HOIST','FABRICATION','FITTING','ELECTRICAL'))
 OR (l->>'department'='139' AND p_category LIKE 'BUS_%') THEN RETURN jsonb_build_object('ok',false,'error','wrong_department_category'); END IF;
 src_stage:=l->>'stage_code'; old_cat:=l->>'work_category'; target:=pdc_work_categories_private.stage(p_category);
 IF coalesce((l->>'completed')::boolean,false) OR EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND (
   (s.code=src_stage AND b.status IN('started','stoppage') AND (b.work_category IS NULL OR b.work_category IS NOT DISTINCT FROM old_cat OR (b.work_category='BUS_WHOLE_JOB' AND b.work_category_scope ? p_line_identity)))
   OR (s.code=src_stage AND b.status IN('queued','planned') AND b.actual_start_at IS NOT NULL AND (b.work_category IS NULL OR b.work_category IS NOT DISTINCT FROM old_cat OR (b.work_category='BUS_WHOLE_JOB' AND b.work_category_scope ? p_line_identity)))
   OR (b.status='completed' AND s.code IN(src_stage,target) AND (b.work_category IS NULL OR b.work_category_scope ? p_line_identity OR (b.work_category='BUS_WHOLE_JOB' AND b.work_category_scope ? p_line_identity)))
   OR (b.work_category='BUS_WHOLE_JOB' AND b.work_category_scope ? p_line_identity AND b.status IN('queued','planned','started','stoppage','completed')))) THEN
  RETURN jsonb_build_object('ok',false,'error','category_booking_exists','message','Split or cancel the affected unstarted booking before changing its work category. Started and completed work stays protected.');
 END IF;
 IF coalesce(p_release_unstarted,false) IS NOT TRUE THEN
  IF jsonb_typeof(p_batch) IS DISTINCT FROM 'array' THEN p_batch:='[]'::jsonb; END IF;
  FOR rec IN
   WITH moves AS (
    SELECT DISTINCT ON (line_identity) line_identity, category FROM (
     SELECT p_line_identity AS line_identity, p_category AS category, 0 AS ord
     UNION ALL
     SELECT e->>'line_identity', e->>'category', 1 FROM jsonb_array_elements(p_batch) e
     WHERE e->>'category' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','HOIST','FABRICATION','FITTING','ELECTRICAL','TINT','TYRE','SUBLET')
    ) s WHERE line_identity IS NOT NULL ORDER BY line_identity, ord),
   projected AS (
    SELECT x->>'line_identity' AS line_identity, x->>'work_category' AS old_category, x->>'stage_code' AS old_stage,
     coalesce(m.category, x->>'work_category') AS category,
     pdc_work_categories_private.stage(coalesce(m.category, x->>'work_category')) AS stage,
     CASE WHEN jsonb_typeof(x->'estimated_hours')='number' THEN (x->>'estimated_hours')::numeric ELSE NULL END AS hours
    FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) x
    LEFT JOIN moves m ON m.line_identity=x->>'line_identity'
    WHERE coalesce((x->>'active')::boolean,true)),
   bookings AS (
    SELECT b.id, b.status, (b.status IN('planned','queued') AND b.actual_start_at IS NULL) AS unstarted,
     (b.status IN('started','stoppage')) AS running, b.work_category, st.code AS stage_code,
     coalesce((SELECT s2.display_name FROM public.workshop_stages s2 WHERE s2.code=b.work_category), st.display_name) AS stage_name,
     coalesce(bay.display_name,'no bay') AS bay_name,
     to_char(b.scheduled_start_at AT TIME ZONE 'Australia/Perth','Dy FMDD Mon') AS when_label,
     (SELECT count(*) FROM projected p WHERE p.old_stage=st.code AND (b.work_category IS NULL OR p.old_category=b.work_category)
       AND NOT (p.stage=st.code AND (b.work_category IS NULL OR p.category=b.work_category))) AS leaving,
     (SELECT count(*) FROM projected p WHERE p.stage=st.code AND (b.work_category IS NULL OR p.category=b.work_category)) AS staying,
     (SELECT count(*) FROM projected p WHERE p.category IS DISTINCT FROM p.old_category AND p.stage=st.code
       AND (b.work_category IS NULL OR p.category=b.work_category)
       AND NOT (p.old_stage=st.code AND (b.work_category IS NULL OR p.old_category=b.work_category))) AS gaining,
     (SELECT coalesce(sum(round(p.hours*60)),0)::integer FROM projected p WHERE p.category IS DISTINCT FROM p.old_category AND p.stage=st.code
       AND (b.work_category IS NULL OR p.category=b.work_category)
       AND NOT (p.old_stage=st.code AND (b.work_category IS NULL OR p.old_category=b.work_category))
       AND p.hours IS NOT NULL) AS gain_mins,
     (SELECT count(*) FROM projected p WHERE p.category IS DISTINCT FROM p.old_category AND p.stage=st.code
       AND (b.work_category IS NULL OR p.category=b.work_category)
       AND NOT (p.old_stage=st.code AND (b.work_category IS NULL OR p.old_category=b.work_category))
       AND p.hours IS NULL) AS gain_unknown
    FROM public.workshop_bookings b JOIN public.workshop_stages st ON st.id=b.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
    WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND b.work_category IS DISTINCT FROM 'BUS_WHOLE_JOB'
     AND b.status IN('planned','queued','started','stoppage'))
   SELECT * FROM bookings
   WHERE (unstarted AND leaving>0) OR (gaining>0 AND (running OR unstarted))
   ORDER BY unstarted DESC, stage_code, when_label, id
  LOOP
   IF rec.unstarted AND rec.leaving>0 AND rec.staying=0 THEN
    parts:=parts||format('This will release the unstarted %s booking (%s, %s).', rec.stage_name, rec.bay_name, rec.when_label);
   ELSIF rec.unstarted AND rec.leaving>0 THEN
    parts:=parts||format('This will shorten the unstarted %s booking (%s, %s).', rec.stage_name, rec.bay_name, rec.when_label);
   ELSIF rec.running AND rec.gaining>0 AND NOT (rec.stage_code=src_stage AND (rec.work_category IS NULL OR rec.work_category IS NOT DISTINCT FROM old_cat)) THEN
    IF rec.gain_unknown>0 OR rec.gain_mins IS NULL OR rec.gain_mins<=0 THEN v_ht:=NULL;
    ELSIF rec.gain_mins % 60=0 THEN v_ht:=(rec.gain_mins/60)::text||' h';
    ELSE v_ht:=regexp_replace(trim(to_char(round(rec.gain_mins/60.0,2),'FM999990.00')),'^\.','0.')||' h'; END IF;
    parts:=parts||format('The running %s job (%s, %s) stays on the bay. %s', rec.stage_name, rec.bay_name, rec.when_label,
     CASE WHEN v_ht IS NULL THEN 'These lines move onto that job.' ELSE 'These '||v_ht||' move onto that job.' END);
   ELSIF rec.unstarted AND rec.gaining>0 AND rec.leaving=0 THEN
    IF rec.gain_unknown>0 OR rec.gain_mins IS NULL OR rec.gain_mins<=0 THEN v_ht:=NULL;
    ELSIF rec.gain_mins % 60=0 THEN v_ht:=(rec.gain_mins/60)::text||' h';
    ELSE v_ht:=regexp_replace(trim(to_char(round(rec.gain_mins/60.0,2),'FM999990.00')),'^\.','0.')||' h'; END IF;
    parts:=parts||format('This will lengthen the unstarted %s booking (%s, %s)%s.', rec.stage_name, rec.bay_name, rec.when_label,
     CASE WHEN v_ht IS NULL THEN '' ELSE ' by '||v_ht END);
   END IF;
  END LOOP;
  IF cardinality(parts)>0 THEN
   RETURN jsonb_build_object('ok',false,'error','confirm_release','message',array_to_string(parts,' '));
  END IF;
 END IF;
 SELECT * INTO old FROM pdc_work_categories_private.line_overrides WHERE vehicle_id=v.id AND line_identity=p_line_identity FOR UPDATE;
 IF coalesce(old.version,0) IS DISTINCT FROM p_category_expected_version THEN RETURN jsonb_build_object('ok',false,'error','category_version_conflict'); END IF;
 INSERT INTO pdc_work_categories_private.line_overrides(vehicle_id,line_identity,category,updated_by)
 VALUES(v.id,p_line_identity,p_category,auth.uid()) ON CONFLICT(vehicle_id,line_identity) DO UPDATE
 SET category=excluded.category,version=line_overrides.version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
 WHERE line_overrides.vehicle_id=excluded.vehicle_id;
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v.id]);
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed)
 SELECT v.id,work_key,true,false FROM public.workshop_stages WHERE code=target
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true WHERE NOT public.vehicle_work_items.completed;
 UPDATE public.vehicles SET version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid() WHERE id=v.id;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','vehicle_work_category',v.id,v.id,auth.uid(),public.current_actor_email(),to_jsonb(old),jsonb_build_object('line_identity',p_line_identity,'category',p_category),
 jsonb_build_object('source','jobcard_work_categories_20261015','source_hours_preserved',true));
 IF coalesce(p_release_unstarted,false) THEN
  FOR rec IN SELECT b.id, b.version, b.stage_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, b.work_category, s.code AS stage_code,
    coalesce(bay.display_name,'no bay') AS bay_name
   FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
   WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND s.code=src_stage
    AND b.status IN('planned','queued') AND b.actual_start_at IS NULL
    AND b.work_category IS DISTINCT FROM 'BUS_WHOLE_JOB'
    AND (b.work_category IS NULL OR b.work_category IS NOT DISTINCT FROM old_cat)
   FOR UPDATE OF b
  LOOP
   SELECT count(*) INTO n FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) x
    WHERE coalesce((x->>'active')::boolean,true) AND x->>'stage_code'=rec.stage_code
     AND (rec.work_category IS NULL OR x->>'work_category'=rec.work_category);
   IF n=0 THEN
    BEGIN
     r:=public.cancel_workshop_booking(rec.id,rec.version,'Work moved to another station.',
      jsonb_build_object('source','category_release_536','line_identity',p_line_identity,'category',p_category,'actor_id',auth.uid()));
     IF coalesce((r->>'ok')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'release_failed'; END IF;
    EXCEPTION WHEN OTHERS THEN
     RAISE EXCEPTION 'The category was not saved. The unstarted booking could not be released.';
    END;
   ELSE
    mins:=pdc_work_categories_private.minutes(rec.id,v.id,rec.stage_id);
    IF mins IS NULL OR mins<1 THEN
     INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
     VALUES('update','workshop_bookings',rec.id,v.id,auth.uid(),public.current_actor_email(),
      jsonb_build_object('default_duration_minutes',rec.default_duration_minutes,'scheduled_end_at',rec.scheduled_end_at),
      jsonb_build_object('accounted','hours_unknown'),
      jsonb_build_object('source','category_release_536','line_identity',p_line_identity));
    ELSE
     new_end:=public.workshop_add_operational_minutes(rec.scheduled_start_at,mins);
     IF mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at THEN
      BEGIN
       UPDATE public.workshop_bookings SET default_duration_minutes=mins, scheduled_end_at=new_end, version=version+1, updated_by=auth.uid(), updated_at=clock_timestamp()
        WHERE id=rec.id AND vehicle_id=v.id AND deleted_at IS NULL AND status IN('planned','queued') AND actual_start_at IS NULL AND version=rec.version;
       GET DIAGNOSTICS n=ROW_COUNT;
       IF n<>1 THEN RAISE EXCEPTION 'resize_missed'; END IF;
      EXCEPTION WHEN OTHERS THEN
       RAISE EXCEPTION 'The category was not saved. The unstarted booking could not be shortened.';
      END;
      INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      VALUES('update','workshop_bookings',rec.id,v.id,auth.uid(),public.current_actor_email(),
       jsonb_build_object('default_duration_minutes',rec.default_duration_minutes,'scheduled_end_at',rec.scheduled_end_at,'bay',rec.bay_name),
       jsonb_build_object('default_duration_minutes',mins,'scheduled_end_at',new_end,'accounted','shorten_unstarted'),
       jsonb_build_object('source','category_release_536','line_identity',p_line_identity,'category',p_category));
     END IF;
    END IF;
   END IF;
  END LOOP;
  SELECT b.id INTO running_id FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND s.code=target AND b.status IN('started','stoppage')
    AND (b.work_category IS NULL OR b.work_category=p_category)
    AND NOT (s.code=src_stage AND (b.work_category IS NULL OR b.work_category IS NOT DISTINCT FROM old_cat))
   ORDER BY b.actual_start_at DESC NULLS LAST, b.id LIMIT 1;
  IF running_id IS NOT NULL THEN
   added:=CASE WHEN jsonb_typeof(l->'estimated_hours')='number' THEN greatest(0,round((l->>'estimated_hours')::numeric*60)::integer) ELSE 0 END;
   INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
   SELECT 'update','workshop_bookings',b.id,v.id,auth.uid(),public.current_actor_email(),
    jsonb_build_object('status',b.status,'default_duration_minutes',b.default_duration_minutes,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,'bay',coalesce(bay.display_name,'no bay')),
    jsonb_build_object('added_minutes',added,'accounted','running_job_keeps_its_bay_time'),
    jsonb_build_object('source','category_release_536','line_identity',p_line_identity,'category',p_category)
   FROM public.workshop_bookings b LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
   WHERE b.id=running_id AND b.vehicle_id=v.id;
  ELSE
   FOR rec IN SELECT b.id, b.version, b.stage_id, b.default_duration_minutes, b.scheduled_start_at, b.scheduled_end_at, coalesce(bay.display_name,'no bay') AS bay_name
    FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
    WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND s.code=target
     AND b.status IN('planned','queued') AND b.actual_start_at IS NULL
     AND b.work_category IS DISTINCT FROM 'BUS_WHOLE_JOB'
     AND (b.work_category IS NULL OR b.work_category=p_category)
     AND NOT (s.code=src_stage AND (b.work_category IS NULL OR b.work_category IS NOT DISTINCT FROM old_cat))
    FOR UPDATE OF b
   LOOP
    mins:=pdc_work_categories_private.minutes(rec.id,v.id,rec.stage_id);
    IF mins IS NOT NULL AND mins>=1 THEN
     new_end:=public.workshop_add_operational_minutes(rec.scheduled_start_at,mins);
     IF mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at THEN
      BEGIN
       UPDATE public.workshop_bookings SET default_duration_minutes=mins, scheduled_end_at=new_end, version=version+1, updated_by=auth.uid(), updated_at=clock_timestamp()
        WHERE id=rec.id AND vehicle_id=v.id AND deleted_at IS NULL AND status IN('planned','queued') AND actual_start_at IS NULL AND version=rec.version;
       GET DIAGNOSTICS n=ROW_COUNT;
       IF n<>1 THEN RAISE EXCEPTION 'resize_missed'; END IF;
      EXCEPTION WHEN OTHERS THEN
       RAISE EXCEPTION 'The category was not saved. The unstarted booking could not be lengthened.';
      END;
      INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      VALUES('update','workshop_bookings',rec.id,v.id,auth.uid(),public.current_actor_email(),
       jsonb_build_object('default_duration_minutes',rec.default_duration_minutes,'scheduled_end_at',rec.scheduled_end_at,'bay',rec.bay_name),
       jsonb_build_object('default_duration_minutes',mins,'scheduled_end_at',new_end,'accounted','lengthen_unstarted'),
       jsonb_build_object('source','category_release_536','line_identity',p_line_identity,'category',p_category));
     END IF;
    END IF;
   END LOOP;
  END IF;
 END IF;
 RETURN jsonb_build_object('ok',true,'revision',public.workshop_bump_revision());
END $function$;

REVOKE ALL ON FUNCTION public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb) TO authenticated;

UPDATE pdc_ops.expected_function_md5
 SET prosrc_md5='b1b23383b96acd867c246cf6e57572dc', release='r536', note='r536: release an unstarted booking when its lines move (F150)', updated_at=clock_timestamp()
 WHERE signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'
  AND prosrc_md5='240e25e96467490d71744490c7a4d75c' AND release='r538';

UPDATE pdc_ops.regression_checks
 SET check_sql=replace(check_sql,'workshop_extend_running_booking_538','running_job_keeps_its_bay_time')
 WHERE check_name='category_unstarted_release_536' AND fault_id='F150' AND sort_order=315
  AND check_sql LIKE '%workshop_extend_running_booking_538%';

UPDATE pdc_ops.regression_checks
 SET check_sql=replace(check_sql,'AND e.release=''r538''','AND e.release=''r536''')
 WHERE check_name='category_unstarted_release_536' AND fault_id='F150' AND sort_order=315
  AND check_sql LIKE '%AND e.release=''r538''%';

UPDATE pdc_ops.regression_checks
 SET check_sql=replace(check_sql,
  'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'')=''r538''',
  'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'')=''r536''')
 WHERE check_name='bus_whole_job_450' AND added_in='r450' AND fault_id='F63' AND sort_order=249
  AND check_sql LIKE '%set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'')=''r538''%';

DELETE FROM pdc_ops.regression_checks
 WHERE check_name='running_booking_end_538' AND fault_id='F152' AND sort_order=317 AND added_in='r538';

DROP TRIGGER IF EXISTS workshop_extend_running_after_hours_538 ON public.vehicle_workshop_line_adjustments;
DROP TRIGGER IF EXISTS fitter_extend_other_station_538 ON pdc_fitter_private.operation_progress;
DROP FUNCTION IF EXISTS public.workshop_extend_running_after_hours_538();
DROP FUNCTION IF EXISTS pdc_fitter_private.extend_after_other_station_538();
DROP FUNCTION IF EXISTS public.workshop_extend_running_booking_538(uuid,text,integer);

DO $g$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r538 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) IS DISTINCT FROM 'b1b23383b96acd867c246cf6e57572dc' THEN RAISE EXCEPTION 'r538 undo: r536 body was not restored'; END IF;
 IF to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)') IS NOT NULL THEN RAISE EXCEPTION 'r538 undo: extender still exists'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450') IS DISTINCT FROM 'b98ce2ca73337f5fb614eb9f7320f561' THEN RAISE EXCEPTION 'r538 undo: bus_whole_job_450 text was not restored'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='category_unstarted_release_536') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r538 undo: category check not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r538 undo: bus_whole_job_450 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r538 undo: regression_checks_self_test not OK: %', x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
