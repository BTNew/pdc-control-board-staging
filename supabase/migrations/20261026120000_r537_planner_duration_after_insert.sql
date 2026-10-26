-- r537 (F151). Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- 26 Oct 2026 09:11 AWST: Key 415 stock 13070395 onto Fitting Bay 07 was still rejected with
-- operation_estimate_duration_mismatch expected_minutes 1096 after r531 was live.
-- r531 deletes the QC cache before the first read. That read still happens before the booking
-- exists. The import router then keeps a line on the stage only because the booking exists, so
-- assignment validation expects the longer total. This release writes that post-insert length
-- before the technician is assigned. workshop_validate_booking is not edited. Pin count stays 241.
-- Sort 315 is reserved by r536. This check is sort 316.
-- Undo: supabase/rollbacks/20261026120000_r537_planner_duration_after_insert.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r537: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r537: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r537: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM 'f5375755bbb9c217198c4075e5c125ab' THEN RAISE EXCEPTION 'r537: workshop_create_booking is not the r531 body'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=316 OR fault_id='F151' OR check_name='planner_duration_after_insert_537' OR added_in='r537') THEN RAISE EXCEPTION 'r537: sort 316 or F151 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='planner_duration_cache_531' AND fault_id='F145' AND sort_order=312 AND added_in='r531') THEN RAISE EXCEPTION 'r537: r531 duration check is not the live row'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,workshop_booking_status,uuid,boolean)'::regprocedure) IS DISTINCT FROM '9efb08f2415c28ac57a14b401cf9f605' THEN RAISE EXCEPTION 'r537: pinned workshop_validate_booking changed'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_create_booking(p_vehicle_id uuid, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT 180, p_technician_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $fn$
declare
  v_stage_id uuid;
  v_bay_id uuid;
  v_booking_id uuid;
  v_conflict_id uuid;
  v_history_id uuid;
  v_end timestamptz;
  v_after jsonb;
  v_leave_date date;
  v_live integer;
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  -- r531 (F145): the booking insert drops this vehicle's QC operation-line cache.
  -- Read the live minutes first, so a stale cache is not the stored length.
  DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = p_vehicle_id;
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
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'), 'detail', pdc_cascade_private.technician_overlap_detail_531(v_conflict_id));
    end if;
  end if;

  begin
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

    -- r537 (F151): once this row exists, the import router keeps lines on this stage that it
    -- would otherwise move. Assignment validation reads that longer total. Store it before
    -- the technician is assigned. A length that is not this total is still rejected.
    v_live := public.workshop_booking_capacity_duration_minutes(v_booking_id,p_vehicle_id,v_stage_id,v_bay_id);
    if v_live is not null and v_live is distinct from p_duration_minutes then
      v_end := public.workshop_add_operational_minutes(p_scheduled_start_at, v_live);
      if p_technician_id is not null then
        select public.workshop_technician_leave_date(p_technician_id, p_scheduled_start_at, v_end) into v_leave_date;
        if v_leave_date is not null then
          raise exception 'r537_technician_on_leave:%', v_leave_date using errcode = 'P0001';
        end if;
      end if;
      v_conflict_id := public.workshop_find_bay_conflict(v_booking_id, v_bay_id, p_scheduled_start_at, v_end);
      if v_conflict_id is not null then
        raise exception 'r537_bay_overlap:%', v_conflict_id using errcode = 'P0001';
      end if;
      if p_technician_id is not null then
        v_conflict_id := public.workshop_find_technician_conflict(v_booking_id, p_technician_id, p_scheduled_start_at, v_end);
        if v_conflict_id is not null then
          raise exception 'r537_technician_overlap:%', v_conflict_id using errcode = 'P0001';
        end if;
      end if;
      update public.workshop_bookings
        set default_duration_minutes = v_live,
            scheduled_end_at = v_end
        where id = v_booking_id;
      p_duration_minutes := v_live;
    end if;

    perform public.workshop_upsert_primary_assignment(v_booking_id, p_technician_id, p_scheduled_start_at, v_end, 'created');
  exception
    when sqlstate 'P0001' then
      if SQLERRM like 'r537_bay_overlap:%' then
        return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(split_part(SQLERRM, ':', 2)::uuid, 'bay_overlap'));
      elsif SQLERRM like 'r537_technician_overlap:%' then
        return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(split_part(SQLERRM, ':', 2)::uuid, 'technician_overlap'), 'detail', pdc_cascade_private.technician_overlap_detail_531(split_part(SQLERRM, ':', 2)::uuid));
      elsif SQLERRM like 'r537_technician_on_leave:%' then
        return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'technician_id', p_technician_id, 'date', split_part(SQLERRM, ':', 2)::date);
      else
        raise;
      end if;
  end;

  v_after := public.workshop_booking_snapshot(v_booking_id);
  v_history_id := public.workshop_write_history(v_booking_id, 'created', null, v_after, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after, 'history_id', v_history_id);
end;
$fn$;

UPDATE pdc_ops.regression_checks
SET description = 'A new booking drops the QC cache before the first duration read, then stores the post-insert length before the technician is assigned. A different length is still rejected.',
    check_sql = $chk531$
SELECT
  del_at > 0 AND est_at > del_at
  AND live_at > ins_at AND upd_at > live_at AND assign_at > upd_at
  AND md5(src) = '864e9bdc638bd0003dab0302e9ab2de3'
  AND strpos(val, 'operation_estimate_duration_mismatch') > 0
  AND md5(val) = '9efb08f2415c28ac57a14b401cf9f605'
  AS ok,
  'create '||md5(src)||' delete '||del_at::text||' estimate '||est_at::text||' live '||live_at::text AS detail
FROM (
  SELECT prosrc AS src,
    strpos(prosrc, 'DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = p_vehicle_id') AS del_at,
    strpos(prosrc, 'workshop_booking_capacity_duration_minutes(NULL,p_vehicle_id,v_stage_id,v_bay_id)') AS est_at,
    strpos(prosrc, 'insert into public.workshop_bookings') AS ins_at,
    strpos(prosrc, 'workshop_booking_capacity_duration_minutes(v_booking_id,p_vehicle_id,v_stage_id,v_bay_id)') AS live_at,
    strpos(prosrc, 'set default_duration_minutes = v_live') AS upd_at,
    strpos(prosrc, 'workshop_upsert_primary_assignment') AS assign_at
  FROM pg_proc
  WHERE oid = 'public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure
) c
CROSS JOIN (
  SELECT prosrc AS val FROM pg_proc
  WHERE oid = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure
) v
$chk531$
WHERE check_name = 'planner_duration_cache_531' AND fault_id = 'F145' AND sort_order = 312 AND added_in = 'r531';

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('planner_duration_after_insert_537', 'F151',
 'Key 415 stock 13070395: the length stored on a new booking is the post-insert total, and a different length is still rejected.',
 $chk537$
SELECT
  live_at > ins_at AND upd_at > live_at AND assign_at > upd_at
  AND md5(src) = '864e9bdc638bd0003dab0302e9ab2de3'
  AND strpos(val, 'operation_estimate_duration_mismatch') > 0
  AND md5(val) = '9efb08f2415c28ac57a14b401cf9f605'
  AS ok,
  'create '||md5(src)||' live '||live_at::text||' update '||upd_at::text||' assign '||assign_at::text AS detail
FROM (
  SELECT prosrc AS src,
    strpos(prosrc, 'insert into public.workshop_bookings') AS ins_at,
    strpos(prosrc, 'workshop_booking_capacity_duration_minutes(v_booking_id,p_vehicle_id,v_stage_id,v_bay_id)') AS live_at,
    strpos(prosrc, 'set default_duration_minutes = v_live') AS upd_at,
    strpos(prosrc, 'workshop_upsert_primary_assignment') AS assign_at
  FROM pg_proc
  WHERE oid = 'public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure
) c
CROSS JOIN (
  SELECT prosrc AS val FROM pg_proc
  WHERE oid = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure
) v
$chk537$, true, 316, 'r537');

DO $post$
DECLARE r record;
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM '864e9bdc638bd0003dab0302e9ab2de3' THEN RAISE EXCEPTION 'r537: create body md5 is not 864e9bdc638bd0003dab0302e9ab2de3'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,workshop_booking_status,uuid,boolean)'::regprocedure) IS DISTINCT FROM '9efb08f2415c28ac57a14b401cf9f605' THEN RAISE EXCEPTION 'r537: validate body changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r537: pin count changed'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r537: create booking acl changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='planner_duration_after_insert_537' AND fault_id='F151' AND sort_order=316 AND added_in='r537' AND enabled)<>1 THEN RAISE EXCEPTION 'r537: check missing'; END IF;
 FOR r IN SELECT * FROM pdc_ops.regression_checks WHERE check_name IN ('planner_duration_cache_531','planner_duration_after_insert_537') ORDER BY sort_order LOOP
  EXECUTE r.check_sql INTO r;
  IF coalesce(r.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r537: check % failed: %', r.check_name, r.detail; END IF;
 END LOOP;
END $post$;
