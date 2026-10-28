-- r601 (F215) undo. Staging only. Puts the validator refusal back and removes the check.
-- It does not rewrite booking rows and it does not turn the cross-bay guard on.

SET LOCAL lock_timeout = '4s';

DO $undo601$
DECLARE def text; n integer;
  old_line text := $old$if v_conflict is not null then return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_conflict); end if;$old$;
  new_line text := $new$if v_conflict is not null and pdc_ops.cross_bay_vehicle_guard_on() then return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_conflict); end if; -- r601 (F215)$new$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'r601 undo: staging only'; END IF;
  def := pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure);
  def := replace(def, new_line, old_line);
  EXECUTE def;
  UPDATE pdc_ops.expected_function_md5 SET
    prosrc_md5 = '4e8dfda7795a8a547358554c5720a174',
    note = 'r577: per-bay hours when an override exists. Release stays r548 so unallocated_bay_rechain_548 still sees r548 (was ae08aa9b0dc99e7c93b1710efdcb5070).',
    updated_at = now()
  WHERE signature = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'
    AND release = 'r548';
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'validate_cross_bay_off_601' AND added_in = 'r601';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r601 undo: check'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'))
     IS DISTINCT FROM '4e8dfda7795a8a547358554c5720a174' THEN
    RAISE EXCEPTION 'r601 undo: validator checksum';
  END IF;
END $undo601$;
