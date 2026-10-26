-- Undo r531 (F145). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Restores workshop_create_booking body md5 c01d82df2e947fbe0b3ecabbe8e7eb70. Drops the detail helper and both F145 checks.
-- Restores regression_checks_self_test and drops pdc_ops.regression_checks_catalog_guard().
-- Pin count stays 241. workshop_validate_booking is not changed. No booking rows are rewritten.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r531 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r531 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r531 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM 'f5375755bbb9c217198c4075e5c125ab' THEN RAISE EXCEPTION 'r531 undo: create body is not the r531 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_cascade_private.technician_overlap_detail_531(uuid)'::regprocedure) IS DISTINCT FROM '272901e7cb918ab14dd3419b1bff5d58' THEN RAISE EXCEPTION 'r531 undo: detail body is not the r531 body'; END IF;
 IF to_regprocedure('pdc_ops.regression_checks_catalog_guard()') IS NULL THEN RAISE EXCEPTION 'r531 undo: catalog guard missing'; END IF;
END $g$;

UPDATE pdc_ops.regression_checks
SET description = 'Regression checks (r529): each check exposes ok and detail, and none compares the whole pin table to a literal count',
    check_sql = $chk529down$SELECT
 (SELECT count(*) FROM pdc_ops.regression_checks c
   WHERE NOT (
       (c.check_sql ~* $re1$as\s+ok\M$re1$ AND c.check_sql ~* $re2$as\s+detail\M$re2$)
       OR (c.check_sql ~* $re3$\.\s*ok\M$re3$ AND c.check_sql ~* $re4$\.\s*detail\M$re4$)
     )
     OR c.check_sql ~* $re5$expected_function_md5\s*\)\s*(=|<>|!=|is\s+distinct\s+from|is\s+not\s+distinct\s+from)\s*[0-9]+$re5$
     OR c.check_sql ~* $re6$[0-9]+\s*(=|<>|!=)\s*\(\s*select\s+count\(\s*\*\s*\)\s+from\s+pdc_ops\.expected_function_md5\s*\)$re6$
 )=0 AS ok,
 coalesce((SELECT string_agg(c.check_name, ', ' ORDER BY c.sort_order, c.check_name)
   FROM pdc_ops.regression_checks c
   WHERE NOT (
       (c.check_sql ~* $re1$as\s+ok\M$re1$ AND c.check_sql ~* $re2$as\s+detail\M$re2$)
       OR (c.check_sql ~* $re3$\.\s*ok\M$re3$ AND c.check_sql ~* $re4$\.\s*detail\M$re4$)
     )
     OR c.check_sql ~* $re5$expected_function_md5\s*\)\s*(=|<>|!=|is\s+distinct\s+from|is\s+not\s+distinct\s+from)\s*[0-9]+$re5$
     OR c.check_sql ~* $re6$[0-9]+\s*(=|<>|!=)\s*\(\s*select\s+count\(\s*\*\s*\)\s+from\s+pdc_ops\.expected_function_md5\s*\)$re6$
 ), 'checks expose ok and detail, and none lock the pin total') AS detail$chk529down$
WHERE check_name = 'regression_checks_self_test'
  AND fault_id = 'F143'
  AND sort_order = 310
  AND added_in = 'r529'
  AND check_sql LIKE '%pdc_ops.regression_checks_catalog_guard()%';

DROP FUNCTION pdc_ops.regression_checks_catalog_guard();

DELETE FROM pdc_ops.regression_checks
WHERE check_name IN ('planner_duration_cache_531','technician_overlap_names_booking_531')
  AND fault_id = 'F145' AND added_in = 'r531';

DROP FUNCTION pdc_cascade_private.technician_overlap_detail_531(uuid);

CREATE OR REPLACE FUNCTION public.workshop_create_booking(p_vehicle_id uuid, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT 180, p_technician_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $cb531down$
declare
  v_stage_id uuid;
  v_bay_id uuid;
  v_booking_id uuid;
  v_conflict_id uuid;
  v_history_id uuid;
  v_end timestamptz;
  v_after jsonb;
  v_leave_date date;
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  p_duration_minutes := coalesce(public.workshop_booking_capacity_duration_minutes(NULL,p_vehicle_id,v_stage_id,v_bay_id),p_duration_minutes);
  v_end := public.workshop_add_operational_minutes(p_scheduled_start_at, p_duration_minutes);

  if p_technician_id is not null then
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id) then
      return jsonb_build_object('ok', false, 'error', 'technician_not_found', 'technician_id', p_technician_id);
    end if;
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id and active) then
      return jsonb_build_object('ok', false, 'error', 'technician_inactive', 'technician_id', p_technician_id);
    end if;
    select public.workshop_technician_leave_date(p_technician_id, p_scheduled_start_at, v_end) into v_leave_date;
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'technician_id', p_technician_id, 'date', v_leave_date);
    end if;
  end if;

  perform public.workshop_lock_resources(v_bay_id, p_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(null, v_bay_id, p_scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;

  if p_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(null, p_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  insert into public.workshop_bookings (
    vehicle_id,
    stage_id,
    bay_id,
    status,
    scheduled_start_at,
    scheduled_end_at,
    default_duration_minutes,
    created_by,
    updated_by
  ) values (
    p_vehicle_id,
    v_stage_id,
    v_bay_id,
    'planned',
    p_scheduled_start_at,
    v_end,
    p_duration_minutes,
    auth.uid(),
    auth.uid()
  ) returning id into v_booking_id;

  perform public.workshop_upsert_primary_assignment(v_booking_id, p_technician_id, p_scheduled_start_at, v_end, 'created');

  v_after := public.workshop_booking_snapshot(v_booking_id);
  v_history_id := public.workshop_write_history(v_booking_id, 'created', null, v_after, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after, 'history_id', v_history_id);
end;
$cb531down$;

DO $post$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM 'c01d82df2e947fbe0b3ecabbe8e7eb70' THEN RAISE EXCEPTION 'r531 undo: restored body md5 drifted'; END IF;
 IF to_regprocedure('pdc_cascade_private.technician_overlap_detail_531(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r531 undo: detail function still exists'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE fault_id='F145' OR added_in='r531') THEN RAISE EXCEPTION 'r531 undo: F145 check remains'; END IF;
 IF to_regprocedure('pdc_ops.regression_checks_catalog_guard()') IS NOT NULL THEN RAISE EXCEPTION 'r531 undo: catalog guard remains'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test') IS DISTINCT FROM '10a3a6ab8337dfcb6ccf4a93ab78e456' THEN RAISE EXCEPTION 'r531 undo: self-test was not restored'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r531 undo: pin count changed'; END IF;
END $post$;
