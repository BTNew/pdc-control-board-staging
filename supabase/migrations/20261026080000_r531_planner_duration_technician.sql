-- r531 (F145). PREVIEW ONLY. Do not apply. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- 26 Oct 2026 07:33 AWST: a fitting drop was rejected with operation_estimate_duration_mismatch
-- because the booking insert drops the QC operation-line cache after the duration was read from it.
-- 26 Oct 2026 07:42 AWST: Key 248 stock 13047270 onto Fitting Bay 06 is a real clash with Chelsea Rees # 2
-- on Key 411 stock 12710966 (Fitting Bay 10). The refusal stays. The response names that booking.
-- Pin count stays 241. workshop_validate_booking is not edited. Sort 310 is r529 / F143. Sort 311 is r530 / F144.
-- These checks are sort 312 and 313, both fault F145.
-- Undo: supabase/rollbacks/20261026080000_r531_planner_duration_technician.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r531: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r531: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r531: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM 'c01d82df2e947fbe0b3ecabbe8e7eb70' THEN RAISE EXCEPTION 'r531: workshop_create_booking is not the pre-fix body'; END IF;
 IF to_regprocedure('pdc_cascade_private.technician_overlap_detail_531(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r531: detail function already exists'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order IN (312,313) OR fault_id='F145' OR check_name IN ('planner_duration_cache_531','technician_overlap_names_booking_531') OR added_in='r531') THEN RAISE EXCEPTION 'r531: sort 312/313 or F145 is taken'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,workshop_booking_status,uuid,boolean)'::regprocedure) IS DISTINCT FROM '9efb08f2415c28ac57a14b401cf9f605' THEN RAISE EXCEPTION 'r531: pinned workshop_validate_booking changed'; END IF;
END $g$;

CREATE FUNCTION pdc_cascade_private.technician_overlap_detail_531(p_booking_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO pg_catalog, public
AS $d531$
select case
  when snap.booking is null then
    'That technician is already assigned to another booking during this period. No booking was saved. Drop this vehicle on a bay whose mechanic is free for the whole job, use Best slot, or move that booking first.'
  else format(
    '%s is already booked on Key %s, stock %s, %s, from %s to %s (Perth time). No booking was saved. Drop this vehicle on a bay whose mechanic is free for the whole job, use Best slot, or move that booking first.',
    coalesce(nullif(btrim(snap.booking->'assignment'->>'technician_name'), ''), 'That technician'),
    coalesce(nullif(btrim(v.key_number), ''), 'unknown'),
    coalesce(nullif(btrim(snap.booking->'vehicle'->>'stock_number'), ''), 'unknown'),
    coalesce(nullif(btrim(case
      when coalesce(snap.booking->'bay'->>'display_name','') ilike coalesce(snap.booking->'stage'->>'display_name','') || '%'
        then snap.booking->'bay'->>'display_name'
      else concat_ws(' ', snap.booking->'stage'->>'display_name', snap.booking->'bay'->>'display_name')
    end), ''), 'another bay'),
    to_char((snap.booking->>'scheduled_start_at')::timestamptz at time zone 'Australia/Perth', 'DD Mon HH24:MI'),
    to_char((snap.booking->>'scheduled_end_at')::timestamptz at time zone 'Australia/Perth', 'DD Mon HH24:MI')
  )
end
from (select public.workshop_booking_snapshot(p_booking_id) booking) snap
left join public.vehicles v on v.id = nullif(snap.booking->>'vehicle_id', '')::uuid
$d531$;

REVOKE ALL ON FUNCTION pdc_cascade_private.technician_overlap_detail_531(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.workshop_create_booking(p_vehicle_id uuid, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT 180, p_technician_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $cb531$
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
  -- r531 (F145): the booking insert drops this vehicle's QC operation-line cache.
  -- Read the live minutes first, so the stored length and the later check are the same total.
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
$cb531$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES
('planner_duration_cache_531', 'F145',
 'A new booking reads live operation-line minutes before the insert drops the QC cache, and the duration mismatch guard stays.',
 $chk531a$
SELECT
  del_at > 0 AND est_at > del_at
  AND md5(src) = 'f5375755bbb9c217198c4075e5c125ab'
  AND strpos(val, 'operation_estimate_duration_mismatch') > 0
  AS ok,
  'create '||md5(src)||' delete '||del_at::text||' estimate '||est_at::text AS detail
FROM (
  SELECT prosrc AS src,
    strpos(prosrc, 'DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = p_vehicle_id') AS del_at,
    strpos(prosrc, 'workshop_booking_capacity_duration_minutes(NULL,p_vehicle_id,v_stage_id,v_bay_id)') AS est_at
  FROM pg_proc
  WHERE oid = 'public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure
) c
CROSS JOIN (
  SELECT prosrc AS val FROM pg_proc
  WHERE oid = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,workshop_booking_status,uuid,boolean)'::regprocedure
) v
$chk531a$, true, 312, 'r531'),
('technician_overlap_names_booking_531', 'F145',
 'A technician clash names the mechanic, key, stock and bay, and does not name the customer. Key 411 stock 12710966 stays Chelsea Rees # 2 only while that booking is still hers.',
 $chk531b$
SELECT
  md5(fn.prosrc) = '272901e7cb918ab14dd3419b1bff5d58'
  AND strpos(cb.prosrc, 'pdc_cascade_private.technician_overlap_detail_531(v_conflict_id)') > 0
  AND d.detail LIKE '%No booking was saved%'
  AND d.detail LIKE '%Best slot%'
  AND (coalesce(snap.booking->'vehicle'->>'customer_name','') = ''
    OR length(snap.booking->'vehicle'->>'customer_name') < 8
    OR d.detail NOT LIKE '%' || (snap.booking->'vehicle'->>'customer_name') || '%')
  AND (
    coalesce(snap.booking->'vehicle'->>'stock_number','') <> '12710966'
    OR coalesce(snap.booking->'assignment'->>'technician_name','') <> 'Chelsea Rees # 2'
    OR (
      d.detail LIKE '%Chelsea Rees # 2%'
      AND d.detail LIKE '%Key 411%'
      AND d.detail LIKE '%stock 12710966%'
      AND d.detail LIKE '%Fitting - PMB Bay 10%'
      AND d.detail LIKE '%' || to_char((snap.booking->>'scheduled_start_at')::timestamptz at time zone 'Australia/Perth', 'DD Mon HH24:MI') || '%'
      AND d.detail LIKE '%' || to_char((snap.booking->>'scheduled_end_at')::timestamptz at time zone 'Australia/Perth', 'DD Mon HH24:MI') || '%'
    )
  ) AS ok,
  left(d.detail, 400) AS detail
FROM pg_proc fn
CROSS JOIN pg_proc cb
CROSS JOIN LATERAL (
  SELECT public.workshop_booking_snapshot('1d85ee5c-d1a7-4d63-8be9-c6b8b9bcbec7'::uuid) AS booking
) snap
CROSS JOIN LATERAL (
  SELECT pdc_cascade_private.technician_overlap_detail_531('1d85ee5c-d1a7-4d63-8be9-c6b8b9bcbec7'::uuid) AS detail
) d
WHERE fn.oid = 'pdc_cascade_private.technician_overlap_detail_531(uuid)'::regprocedure
  AND cb.oid = 'public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure
$chk531b$, true, 313, 'r531');

DO $post$
DECLARE r record;
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM 'f5375755bbb9c217198c4075e5c125ab' THEN RAISE EXCEPTION 'r531: create body md5 drifted'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_cascade_private.technician_overlap_detail_531(uuid)'::regprocedure) IS DISTINCT FROM '272901e7cb918ab14dd3419b1bff5d58' THEN RAISE EXCEPTION 'r531: detail body md5 drifted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r531: pin count changed'; END IF;
 FOR r IN SELECT * FROM pdc_ops.regression_checks WHERE check_name IN ('planner_duration_cache_531','technician_overlap_names_booking_531') ORDER BY sort_order LOOP
  EXECUTE r.check_sql INTO r;
  IF coalesce(r.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r531: check % failed: %', r.check_name, r.detail; END IF;
 END LOOP;
END $post$;
