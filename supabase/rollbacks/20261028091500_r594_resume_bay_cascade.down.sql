-- r594 (F208) undo. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Puts resume back to the refusal path and drops the bay push helper.
SET LOCAL lock_timeout = '8s';

CREATE OR REPLACE FUNCTION public.resume_workshop_work_pre345(p_booking_id uuid, p_expected_version integer, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $old345$
declare v_booking public.workshop_bookings%rowtype; v_technician_id uuid; v_conflict_id uuid; v_now timestamptz:=now();
 v_new_start timestamptz; v_new_end timestamptz; v_remaining_minutes integer; v_elapsed_minutes integer; v_result jsonb; v_revision bigint;
begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 if v_booking.status<>'stoppage' then return jsonb_build_object('ok',false,'error','not_stopped'); end if;
 v_elapsed_minutes:=greatest(0,public.workshop_operational_minutes_between(v_booking.scheduled_start_at,coalesce(v_booking.stoppage_started_at,v_now))-coalesce(v_booking.stoppage_accumulated_minutes,0));
 v_remaining_minutes:=greatest(60,v_booking.default_duration_minutes-greatest(0,v_elapsed_minutes));
 v_new_start:=public.workshop_next_calendar_window(v_now,v_remaining_minutes); v_new_end:=public.workshop_add_operational_minutes(v_new_start,v_remaining_minutes);
 select technician_id into v_technician_id from public.workshop_booking_assignments where booking_id=p_booking_id and released_at is null
 order by case when assignment_type='primary' then 0 else 1 end,assigned_at desc limit 1;
 perform public.workshop_lock_resources(v_booking.bay_id,v_technician_id);
 v_conflict_id:=public.workshop_find_bay_conflict(p_booking_id,v_booking.bay_id,v_new_start,v_new_end);
 if v_conflict_id is not null then return jsonb_build_object('ok',false,'error','bay_overlap','conflict',public.workshop_conflict_payload(v_conflict_id,'bay_overlap')); end if;
 if v_technician_id is not null then
  v_conflict_id:=public.workshop_find_technician_conflict(p_booking_id,v_technician_id,v_new_start,v_new_end);
  if v_conflict_id is not null then return jsonb_build_object('ok',false,'error','technician_overlap','conflict',public.workshop_conflict_payload(v_conflict_id,'technician_overlap')); end if;
 end if;
 update public.workshop_bookings set scheduled_start_at=v_new_start,scheduled_end_at=v_new_end,
  default_duration_minutes=v_remaining_minutes,updated_by=auth.uid(),version=version+1 where id=p_booking_id;
 perform public.workshop_upsert_primary_assignment(p_booking_id,v_technician_id,v_new_start,v_new_end,'resume_rescheduled');
 v_result:=public.workshop_resume_booking(p_booking_id,v_booking.version+1,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision);
end $old345$;

DO $u$
BEGIN
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'resume_cascade_594' AND fault_id = 'F208' AND sort_order = 364 AND added_in = 'r594') <> 1 THEN
    RAISE EXCEPTION 'r594 undo: F208 check is not the one row';
  END IF;
  IF to_regprocedure('pdc_ops.push_later_planned_in_bay_594(uuid,uuid,timestamptz,timestamptz,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'r594 undo: push helper is missing';
  END IF;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'resume_cascade_594' AND fault_id = 'F208' AND sort_order = 364 AND added_in = 'r594';
  DROP FUNCTION pdc_ops.push_later_planned_in_bay_594(uuid, uuid, timestamptz, timestamptz, jsonb);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.resume_workshop_work_pre345(uuid,integer,jsonb)')) IS DISTINCT FROM '336941bde80a3511cc6ebd54eb00c716' THEN
    RAISE EXCEPTION 'r594 undo: resume body was not restored';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r594 undo: pin count changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
    RAISE EXCEPTION 'r594 undo: department 135 changed';
  END IF;
END $u$;
