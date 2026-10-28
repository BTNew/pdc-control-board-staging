-- r592 (F206) undo. Staging cdsmnqxtyyoeoznmbidd only. Restores the live-job refusal and drops the place-after helper.
-- Does not rewrite booking rows. Pin count stays 241. Department 135 and Kajel's functions stay as they are.

SET LOCAL lock_timeout = '2s';
DO $g$
DECLARE
  awst time;
  def text;
  old text := $old$
  if exists (
    select 1 from public.workshop_bookings b
    where b.bay_id=v_bay.id and b.deleted_at is null
      and b.status in('started','stoppage')
      and b.scheduled_start_at<v_target_end
      and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at
  ) then return jsonb_build_object('ok',false,'error','live_booking_conflict'); end if;$old$;
  new text := $new$
  declare v592 jsonb;
  begin
    v592 := pdc_ops.place_after_live_bay_592(p_booking_id, v_bay.id, p_scheduled_start_at, v_target_end, v_target_duration, p_metadata);
    if v592->>'action' = 'warn' or v592->>'action' = 'fail' then
      return v592->'body';
    elsif v592->>'action' = 'snap' then
      p_scheduled_start_at := (v592->>'start_at')::timestamptz;
      v_target_end := (v592->>'end_at')::timestamptz;
    elsif coalesce(v592->>'action','') <> 'none' then
      return jsonb_build_object('ok',false,'error','calendar_unavailable');
    end if;
  end;$new$;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF (awst >= time '06:50' AND awst < time '07:30')
     OR (awst >= time '12:20' AND awst < time '12:40')
     OR (awst >= time '17:50' AND awst < time '18:10') THEN
    RAISE EXCEPTION 'r592 undo: Kajel import window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r592 undo: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r592 undo: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r592 undo: pin count is not 241'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r592 undo: department 135 changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r592 undo: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r592 undo: Kajel apply changed'; END IF;
  SELECT pg_get_functiondef('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure) INTO def;
  IF (length(def) - length(replace(def, new, ''))) / length(new) <> 2 THEN
    RAISE EXCEPTION 'r592 undo: place-after block was not found twice';
  END IF;
  EXECUTE replace(def, new, old);
  DROP FUNCTION pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb);
  DELETE FROM pdc_ops.regression_checks WHERE check_name='hoist_place_after_592' AND fault_id='F206' AND sort_order=360 AND added_in='r592';
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)')) IS DISTINCT FROM 'fa78dfb941af8fd86ca705890d4bf798' THEN RAISE EXCEPTION 'r592 undo: cascade mover was not restored'; END IF;
  IF to_regprocedure('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r592 undo: helper still exists'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='hoist_place_after_592') THEN RAISE EXCEPTION 'r592 undo: check still exists'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r592 undo: pin count moved'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '6a02115d30578e8eb3807a283b1d60ea' THEN RAISE EXCEPTION 'r592 undo: administrator move changed'; END IF;
END $g$;
