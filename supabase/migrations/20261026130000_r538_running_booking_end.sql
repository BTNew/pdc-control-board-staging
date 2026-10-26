-- r538 (F152). PREVIEW. SQL is not applied. Staging cdsmnqxtyyoeoznmbidd only. Production is not touched.
-- 26 Oct 2026 09:51 AWST: Key 203 (IS60070112, J139125575) is running in Fitting - PMB Bay 06.
-- 7.25 h moved onto that job (r536) and the chip still ended at Now. The row stayed 07:39-07:40.
-- A running chip uses the stored finish, and draws out to Now when that finish is already past.
-- The planner length is the effective duration from the same start (Key 203: 436 minutes, Mon 26 Oct 14:55).
-- This release writes that later finish. The start and the actual start stay where they are.
-- Edit hours and a cross-station tick use the same write. Pin count stays 241. Sort 317.
-- Key 203 itself is not updated here. The go-live repair is supabase/repairs/20261026130000_r538_key203_running_end.sql.
-- Undo: supabase/rollbacks/20261026130000_r538_running_booking_end.down.sql
-- set_vehicle_work_category prosrc md5 240e25e96467490d71744490c7a4d75c. Extender prosrc md5 f0e6e008fa511fcbbe0e87f17f3dd7b3.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r538: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r538: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r538: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) IS DISTINCT FROM 'b1b23383b96acd867c246cf6e57572dc' THEN RAISE EXCEPTION 'r538: set_vehicle_work_category is not the r536 body'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND prosrc_md5='b1b23383b96acd867c246cf6e57572dc' AND release='r536')<>1 THEN RAISE EXCEPTION 'r538: pin is not the r536 pin'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=317 OR fault_id='F152' OR check_name='running_booking_end_538' OR added_in='r538') THEN RAISE EXCEPTION 'r538: sort 317 or F152 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='planner_duration_after_insert_537' AND fault_id='F151' AND sort_order=316 AND added_in='r537') THEN RAISE EXCEPTION 'r538: r537 duration check is not the live row'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='category_unstarted_release_536' AND fault_id='F150' AND sort_order=315 AND check_sql LIKE '%running_job_keeps_its_bay_time%') THEN RAISE EXCEPTION 'r538: r536 category check is not the live text'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450' AND added_in='r450' AND fault_id='F63' AND sort_order=249) IS DISTINCT FROM 'b98ce2ca73337f5fb614eb9f7320f561' THEN RAISE EXCEPTION 'r538: bus_whole_job_450 is not the r536 text'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_extend_running_booking_538(p_booking_id uuid, p_source text, p_added_minutes integer DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $fn$
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
$fn$;

REVOKE ALL ON FUNCTION public.workshop_extend_running_booking_538(uuid,text,integer) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.workshop_extend_running_after_hours_538()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $fn$
DECLARE id uuid;
BEGIN
 IF TG_OP='UPDATE' AND NEW.estimated_hours IS NOT DISTINCT FROM OLD.estimated_hours AND NEW.stage_code IS NOT DISTINCT FROM OLD.stage_code THEN
  RETURN NEW;
 END IF;
 FOR id IN
  SELECT b.id FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=NEW.vehicle_id AND b.deleted_at IS NULL
   AND b.status IN ('started'::public.workshop_booking_status,'stoppage'::public.workshop_booking_status)
   AND s.code IS NOT DISTINCT FROM NEW.stage_code
 LOOP
  PERFORM public.workshop_extend_running_booking_538(id,'edit_hours_538',NULL);
 END LOOP;
 RETURN NEW;
END
$fn$;

REVOKE ALL ON FUNCTION public.workshop_extend_running_after_hours_538() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.workshop_extend_running_after_hours_538() TO authenticated;

CREATE OR REPLACE FUNCTION pdc_fitter_private.extend_after_other_station_538()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $fn$
DECLARE code text; stage text;
BEGIN
 SELECT s.code INTO code
  FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.id=NEW.booking_id AND b.deleted_at IS NULL
   AND b.status IN ('started'::public.workshop_booking_status,'stoppage'::public.workshop_booking_status);
 IF code IS NULL THEN RETURN NEW; END IF;
 SELECT l->>'stage_code' INTO stage
  FROM public.workshop_bookings b
  CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(b.vehicle_id)) l
  WHERE b.id=NEW.booking_id AND l->>'line_identity'=NEW.line_identity
  LIMIT 1;
 IF stage IS NOT NULL AND stage IS DISTINCT FROM code THEN
  PERFORM public.workshop_extend_running_booking_538(NEW.booking_id,'cross_station_538',NULL);
 END IF;
 RETURN NEW;
END
$fn$;

REVOKE ALL ON FUNCTION pdc_fitter_private.extend_after_other_station_538() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION pdc_fitter_private.extend_after_other_station_538() TO authenticated;

DROP TRIGGER IF EXISTS workshop_extend_running_after_hours_538 ON public.vehicle_workshop_line_adjustments;
CREATE TRIGGER workshop_extend_running_after_hours_538
 AFTER INSERT OR UPDATE OF estimated_hours, stage_code ON public.vehicle_workshop_line_adjustments
 FOR EACH ROW EXECUTE FUNCTION public.workshop_extend_running_after_hours_538();

DROP TRIGGER IF EXISTS fitter_extend_other_station_538 ON pdc_fitter_private.operation_progress;
CREATE TRIGGER fitter_extend_other_station_538
 AFTER INSERT OR UPDATE ON pdc_fitter_private.operation_progress
 FOR EACH ROW EXECUTE FUNCTION pdc_fitter_private.extend_after_other_station_538();

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
 -- r536 (F150): an unstarted booking is released or shortened when its lines move.
 -- r538 (F152): a running job keeps its start. Its finish moves out to include hours added from another station.
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
    SELECT b.id, b.status, b.scheduled_start_at, (b.status IN('planned','queued') AND b.actual_start_at IS NULL) AS unstarted,
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
    new_end:=CASE WHEN v_ht IS NULL THEN NULL ELSE public.workshop_add_operational_minutes(rec.scheduled_start_at, coalesce(public.workshop_booking_effective_duration_minutes(rec.id),0)+coalesce(rec.gain_mins,0)) END;
    parts:=parts||format('The running %s job (%s, %s) keeps its start. Its finish moves%s to include %s.', rec.stage_name, rec.bay_name, rec.when_label,
     CASE WHEN new_end IS NULL THEN ' out' ELSE ' to '||to_char(new_end AT TIME ZONE 'Australia/Perth','Dy FMDD Mon HH24:MI') END,
     CASE WHEN v_ht IS NULL THEN 'these lines' ELSE 'these '||v_ht END);
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
   PERFORM public.workshop_extend_running_booking_538(running_id,'category_release_536',added);
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
 SET prosrc_md5='240e25e96467490d71744490c7a4d75c', release='r538', note='r538: a running booking finish includes hours added from another station (F152)', updated_at=clock_timestamp()
 WHERE signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'
  AND prosrc_md5='b1b23383b96acd867c246cf6e57572dc' AND release='r536';

UPDATE pdc_ops.regression_checks
 SET check_sql=replace(check_sql,'running_job_keeps_its_bay_time','workshop_extend_running_booking_538')
 WHERE check_name='category_unstarted_release_536' AND fault_id='F150' AND sort_order=315
  AND check_sql LIKE '%running_job_keeps_its_bay_time%';

UPDATE pdc_ops.regression_checks
 SET check_sql=replace(check_sql,'AND e.release=''r536''','AND e.release=''r538''')
 WHERE check_name='category_unstarted_release_536' AND fault_id='F150' AND sort_order=315
  AND check_sql LIKE '%AND e.release=''r536''%';

UPDATE pdc_ops.regression_checks
 SET check_sql=replace(check_sql,
  'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'')=''r536''',
  'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'')=''r538''')
 WHERE check_name='bus_whole_job_450' AND added_in='r450' AND fault_id='F63' AND sort_order=249
  AND check_sql LIKE '%set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'')=''r536''%';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('running_booking_end_538','F152','A running booking finish includes hours added from another station, and the start stays put (r538)',
  $chk$
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
$chk$,
 true,317,'r538');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r538: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) IS DISTINCT FROM '240e25e96467490d71744490c7a4d75c' THEN RAISE EXCEPTION 'r538: set_vehicle_work_category did not land'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)')) IS DISTINCT FROM 'f0e6e008fa511fcbbe0e87f17f3dd7b3' THEN RAISE EXCEPTION 'r538: extender did not land'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)') IS DISTINCT FROM 'r538' THEN RAISE EXCEPTION 'r538: pin release did not move'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='running_booking_end_538') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r538: running_booking_end_538 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='category_unstarted_release_536') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r538: category_unstarted_release_536 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r538: bus_whole_job_450 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r538: regression_checks_self_test not OK: %', x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
