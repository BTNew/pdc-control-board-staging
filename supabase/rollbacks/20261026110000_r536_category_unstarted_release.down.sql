-- r536 (F150) undo. PREVIEW. SQL is not applied. Staging cdsmnqxtyyoeoznmbidd only.
-- Restores set_vehicle_work_category to the r450 body (prosrc md5 1c0424ad5da9a534ea4ae7b0ebae5c29).
-- Does not put a released booking back and does not rewind a shortened or lengthened booking.
-- Department 135 is not edited. Pin count stays 241.
-- bus_whole_job_450 returns to the r529 text (md5 820f02d2b352ba28ff610fe48bd45f3c): 16 r450 pins, including the 5-arg category function.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r536 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r536 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) IS DISTINCT FROM 'b1b23383b96acd867c246cf6e57572dc' THEN RAISE EXCEPTION 'r536 undo: category function is not the r536 body'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r536 undo: pin count is not 241'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='category_unstarted_release_536' AND fault_id='F150' AND added_in='r536' AND sort_order=315)<>1 THEN RAISE EXCEPTION 'r536 undo: F150 check is not the r536 row'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450' AND sort_order=249 AND fault_id='F63'
   AND check_sql LIKE '%(SELECT n FROM pins)=15 AND (SELECT ok FROM pins)=15%'
   AND check_sql LIKE '%public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)%')<>1 THEN RAISE EXCEPTION 'r536 undo: whole-job check is not the r536 text'; END IF;
END $g$;

DROP FUNCTION public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb);

CREATE FUNCTION public.set_vehicle_work_category(p_vehicle_id uuid, p_vehicle_expected_version integer, p_line_identity text, p_category text, p_category_expected_version integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v public.vehicles; l jsonb; old pdc_work_categories_private.line_overrides;
 target text:=pdc_work_categories_private.stage(p_category); before_line jsonb;
BEGIN
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
 IF coalesce((l->>'completed')::boolean,false) OR EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND s.code IN(l->>'stage_code',target)
  AND (b.status IN('queued','planned','started','stoppage') OR (b.status='completed' AND (b.work_category IS NULL OR b.work_category_scope ? p_line_identity)))
  AND (b.work_category IS NULL OR b.work_category IN(l->>'work_category',p_category)
   -- r450 (F63): a line held by a whole-job booking keeps its category too.
   OR (b.work_category='BUS_WHOLE_JOB' AND b.work_category_scope ? p_line_identity))) THEN
  RETURN jsonb_build_object('ok',false,'error','category_booking_exists','message','Split or cancel the affected unstarted booking before changing its work category. Started and completed work stays protected.');
 END IF;
 SELECT * INTO old FROM pdc_work_categories_private.line_overrides WHERE vehicle_id=v.id AND line_identity=p_line_identity FOR UPDATE;
 IF coalesce(old.version,0) IS DISTINCT FROM p_category_expected_version THEN RETURN jsonb_build_object('ok',false,'error','category_version_conflict'); END IF;
 INSERT INTO pdc_work_categories_private.line_overrides(vehicle_id,line_identity,category,updated_by)
 VALUES(v.id,p_line_identity,p_category,auth.uid()) ON CONFLICT(vehicle_id,line_identity) DO UPDATE
 SET category=excluded.category,version=line_overrides.version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
 WHERE line_overrides.vehicle_id=excluded.vehicle_id; -- r450: explicit WHERE (safeupdate lint); same row as the conflict
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v.id]);
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed)
 SELECT v.id,work_key,true,false FROM public.workshop_stages WHERE code=target
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true WHERE NOT public.vehicle_work_items.completed;
 UPDATE public.vehicles SET version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid() WHERE id=v.id;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','vehicle_work_category',v.id,v.id,auth.uid(),public.current_actor_email(),to_jsonb(old),jsonb_build_object('line_identity',p_line_identity,'category',p_category),
 jsonb_build_object('source','jobcard_work_categories_20261015','source_hours_preserved',true));
 RETURN jsonb_build_object('ok',true,'revision',public.workshop_bump_revision());
END $function$;

REVOKE ALL ON FUNCTION public.set_vehicle_work_category(uuid,integer,text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_vehicle_work_category(uuid,integer,text,text,integer) TO authenticated;

UPDATE pdc_ops.expected_function_md5
 SET signature='public.set_vehicle_work_category(uuid,integer,text,text,integer)', prosrc_md5='1c0424ad5da9a534ea4ae7b0ebae5c29', release='r450', note='r450: line held by a whole job keeps its category (F63)', updated_at=clock_timestamp()
 WHERE signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND prosrc_md5='b1b23383b96acd867c246cf6e57572dc' AND release='r536';

DELETE FROM pdc_ops.regression_checks
 WHERE check_name='category_unstarted_release_536' AND fault_id='F150' AND added_in='r536' AND sort_order=315;

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
 $new450$(SELECT n FROM pins)=15 AND (SELECT ok FROM pins)=15 AND (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')='r523' AND (SELECT e.prosrc_md5 IS NOT DISTINCT FROM md5(p.prosrc) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.signature='pdc_work_categories_private.before_import_rules_20261017(uuid)') AND (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')='r536' AND (SELECT e.prosrc_md5 IS NOT DISTINCT FROM md5(p.prosrc) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)') AND NOT EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.set_vehicle_work_category(uuid,integer,text,text,integer)')$new450$,
 $old450$(SELECT n FROM pins)=16 AND (SELECT ok FROM pins)=16 AND (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')='r523' AND (SELECT e.prosrc_md5 IS NOT DISTINCT FROM md5(p.prosrc) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.signature='pdc_work_categories_private.before_import_rules_20261017(uuid)')$old450$)
WHERE check_name='bus_whole_job_450'
  AND sort_order=249
  AND fault_id='F63'
  AND added_in='r450'
  AND check_sql LIKE '%(SELECT n FROM pins)=15 AND (SELECT ok FROM pins)=15%';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
 $new450d$ ||'; r450 pins matching: '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins) ||'; category pin '||coalesce((SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'),'missing')$new450d$,
 $old450d$ ||'; r450 pins matching: '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)$old450d$)
WHERE check_name='bus_whole_job_450'
  AND sort_order=249
  AND fault_id='F63'
  AND added_in='r450'
  AND check_sql LIKE '%category pin%';

DO $g$ DECLARE x record; y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer)')) IS DISTINCT FROM '1c0424ad5da9a534ea4ae7b0ebae5c29' THEN RAISE EXCEPTION 'r536 undo: r450 body did not land'; END IF;
 IF to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r536 undo: r536 signature still exists'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.set_vehicle_work_category(uuid,integer,text,text,integer)' AND prosrc_md5='1c0424ad5da9a534ea4ae7b0ebae5c29' AND release='r450')<>1 THEN RAISE EXCEPTION 'r536 undo: pin did not return to r450'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r536 undo: pin count is not 241'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='category_unstarted_release_536' OR fault_id='F150' OR added_in='r536' OR sort_order=315) THEN RAISE EXCEPTION 'r536 undo: F150 check remains'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450' AND added_in='r450' AND fault_id='F63' AND sort_order=249) IS DISTINCT FROM '820f02d2b352ba28ff610fe48bd45f3c' THEN RAISE EXCEPTION 'r536 undo: whole-job check did not return to the r529 text'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450') INTO x;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test') INTO y;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r536 undo: bus_whole_job_450 not OK: %', x.detail; END IF;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r536 undo: regression_checks_self_test not OK: %', y.detail; END IF;
END $g$;
