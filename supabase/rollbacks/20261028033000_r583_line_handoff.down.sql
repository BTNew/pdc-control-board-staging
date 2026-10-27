-- Undo r583 (F197) / sort 355. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Restores the fitter job read, the fitter request gate and the r578 station icon.
-- Drops the handoff tables, the audit and the F197 check. Does not rewrite vehicles,
-- bookings, line ticks or pins. Pin count stays 241. Department 135 is not edited.
-- Run between :02 and :45, and only after the up file has been applied.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r583 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r583 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='line_handoff_583' AND fault_id='F197' AND sort_order=355 AND added_in='r583')<>1 THEN RAISE EXCEPTION 'r583 undo: F197 check is not the r583 row'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r583 undo: department 135 changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r583 undo: pin count is not 241'; END IF;
END $g$;

DO $unpatch$
DECLARE def text; patched text;
BEGIN
 def := pg_catalog.pg_get_functiondef('pdc_work_categories_private.station_icon_completion_578(uuid[])'::pg_catalog.regprocedure);
 patched := pg_catalog.replace(def,
$new578$), mapped AS (
 SELECT k.vehicle_id,
  coalesce(pdc_work_categories_private.line_handoff_work_key_583(h.to_stage_code), k.work_key) AS work_key,
  k.line_identity, k.qc_done
 FROM known k
 LEFT JOIN public.pdc_line_handoff_583 h
  ON h.vehicle_id = k.vehicle_id AND h.line_identity = k.line_identity
), uniq AS (
 SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
 FROM mapped
 WHERE work_key IS NOT NULL
 GROUP BY vehicle_id, work_key, line_identity
), panel AS ($new578$,
$old578$), uniq AS (
 SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
 FROM known
 WHERE work_key IS NOT NULL
 GROUP BY vehicle_id, work_key, line_identity
), panel AS ($old578$);
 IF patched IS NOT DISTINCT FROM def THEN RAISE EXCEPTION 'r583 undo: station icon patch did not match'; END IF;
 EXECUTE patched;
 UPDATE pdc_ops.regression_checks
 SET check_sql = pg_catalog.replace(check_sql,
$newchk$), mapped AS (
    SELECT k.vehicle_id,
     coalesce(pdc_work_categories_private.line_handoff_work_key_583(h.to_stage_code), k.work_key) AS work_key,
     k.line_identity, k.qc_done
    FROM known k
    LEFT JOIN public.pdc_line_handoff_583 h
     ON h.vehicle_id = k.vehicle_id AND h.line_identity = k.line_identity
  ), uniq AS (
    SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
    FROM mapped
    WHERE work_key IS NOT NULL
    GROUP BY vehicle_id, work_key, line_identity
  ), panel AS ($newchk$,
$oldchk$), uniq AS (
    SELECT vehicle_id, work_key, line_identity, bool_or(qc_done) AS qc_done
    FROM known
    WHERE work_key IS NOT NULL
    GROUP BY vehicle_id, work_key, line_identity
  ), panel AS ($oldchk$)
 WHERE check_name='station_icon_completion_578' AND fault_id='F196' AND sort_order=354 AND added_in='r578';
 IF NOT FOUND THEN RAISE EXCEPTION 'r583 undo: station check was not restored'; END IF;
END
$unpatch$;

CREATE OR REPLACE FUNCTION public.get_fitter_job(p_technician_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $job583$
DECLARE b public.workshop_bookings; code text; lines jsonb;
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 lines:=pdc_fitter_private.lines(b.vehicle_id,b.id);
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'version',b.version,
   'work_category',b.work_category,'vehicle_id',b.vehicle_id,'supplier_lines','[]'::jsonb,'status',b.status,'stage_code',code,'stoppage_reason',b.stoppage_reason,'lines',lines,
   'progress',pdc_fitter_private.summary(lines,code),
   'catalog_hash',md5((SELECT coalesce(jsonb_agg(l->>'scope_hash' ORDER BY l->>'line_identity'),'[]'::jsonb)::text
      FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'=code)))
   ||pdc_fitter_private.timing(b.id,statement_timestamp())||pdc_bus_private.team_payload(b.id);
END $job583$;

CREATE OR REPLACE FUNCTION public.pdc_check_fitter_request()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $gate583$
DECLARE path text:=ltrim(coalesce(current_setting('request.path',true),''),'/');
BEGIN
 IF EXISTS(SELECT 1 FROM public.pdc_user_roles
   WHERE (auth_user_id=auth.uid() OR email=lower(auth.jwt()->>'email')) AND role::text='fitter') THEN
  IF path='pdc_user_roles' AND current_setting('request.method',true) IN ('GET','HEAD') THEN RETURN; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=auth.uid()
    AND email=lower(auth.jwt()->>'email') AND active AND account_status='approved' AND role::text='fitter')
   OR path NOT IN ('rpc/get_fitter_roster','rpc/get_fitter_jobs','rpc/get_fitter_job','rpc/get_fitter_refresh','rpc/fitter_job_command','rpc/record_pdc_usage_20260914')
   OR current_setting('request.method',true) <> 'POST' THEN
    RAISE EXCEPTION 'This account can access Fitters bay only' USING errcode='42501';
  END IF;
 END IF;
END $gate583$;

DROP FUNCTION IF EXISTS public.list_line_handoffs_583(uuid);
DROP FUNCTION IF EXISTS public.undo_line_handoff_583(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.handoff_operation_line_583(uuid, uuid, text, text, uuid);
DROP FUNCTION IF EXISTS pdc_work_categories_private.line_handoff_targets_583();
DROP FUNCTION IF EXISTS pdc_work_categories_private.line_handoff_annotate_583(uuid, text, jsonb);
DROP FUNCTION IF EXISTS pdc_work_categories_private.line_handoff_progress_583(uuid, text, jsonb, jsonb);
DROP FUNCTION IF EXISTS pdc_work_categories_private.line_handoff_work_key_583(text);
DROP TRIGGER IF EXISTS pdc_line_handoff_history_583_guard ON public.pdc_line_handoff_history_583;
DROP FUNCTION IF EXISTS public.pdc_line_handoff_history_guard_583();
DROP TABLE IF EXISTS public.pdc_line_handoff_583;
DROP TABLE IF EXISTS public.pdc_line_handoff_history_583;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='line_handoff_583' AND fault_id='F197' AND sort_order=355 AND added_in='r583';

DO $post$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='line_handoff_583' OR fault_id='F197' OR added_in='r583' OR sort_order=355) THEN RAISE EXCEPTION 'r583 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_line_handoff_583') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_line_handoff_history_583') IS NOT NULL THEN RAISE EXCEPTION 'r583 undo: table remains'; END IF;
 IF pg_catalog.to_regprocedure('public.handoff_operation_line_583(uuid,uuid,text,text,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r583 undo: send function remains'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_fitter_job(uuid,uuid)'))
    IS DISTINCT FROM '74d1a88dc9b440782904c02682c25ebc' THEN RAISE EXCEPTION 'r583 undo: get_fitter_job was not restored'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_check_fitter_request()'))
    IS DISTINCT FROM '6cdf34218dcacc86fda2cab39bb69025' THEN RAISE EXCEPTION 'r583 undo: fitter gate was not restored'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_work_categories_private.station_icon_completion_578(uuid[])'))
    IS DISTINCT FROM '88d2eed58518a9eb98ef4210610a4dd1' THEN RAISE EXCEPTION 'r583 undo: station icon was not restored'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='station_icon_completion_578')
    IS DISTINCT FROM '0d7536485eb84f94ac177fe2224e9738' THEN RAISE EXCEPTION 'r583 undo: station check was not restored'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r583 undo: fitter command changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r583 undo: department 135 changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r583 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r583') THEN RAISE EXCEPTION 'r583 undo: a pin remains'; END IF;
END $post$;

NOTIFY pgrst, 'reload schema';
