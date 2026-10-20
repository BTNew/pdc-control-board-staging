-- After the checkbox, Sub Status 80 and 99 must not reopen or complete the item again.
DO $after$
DECLARE result jsonb; line jsonb; snap jsonb; snap_after jsonb; sections jsonb;
 phrase text; n integer; qc_done boolean; dur integer;
BEGIN
 result := pg_temp.tick('coaster-after', true);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Coaster tick failed %', result; END IF;
 SELECT l INTO line FROM jsonb_array_elements(pdc_fitter_private.lines(pg_temp.vid('coaster-after'), pg_temp.bid('coaster-after'))) l;
 IF (line->>'completed')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'ticked line is not complete %', line; END IF;
 IF (line->>'hours')::numeric IS DISTINCT FROM 60 THEN RAISE EXCEPTION 'tick changed operation hours %', line->>'hours'; END IF;
 IF (line#>>'{conversion,total_minutes}')::integer IS DISTINCT FROM 3765 THEN
  RAISE EXCEPTION 'tick changed the Coaster planning allowance';
 END IF;
 IF (line#>>'{conversion,release_blocked}')::boolean IS NOT TRUE THEN
  RAISE EXCEPTION 'section release flag was deleted instead of left unused';
 END IF;
 IF line->>'scope_hash' IS DISTINCT FROM 'scope-coaster-after' THEN
  RAISE EXCEPTION 'tick replaced the source scope hash';
 END IF;
 SELECT to_jsonb(p) INTO snap FROM pdc_fitter_private.operation_progress p WHERE p.booking_id = pg_temp.bid('coaster-after');
 SELECT s.sections INTO sections FROM pdc_fitter_private.conversion_state s WHERE s.vehicle_id = pg_temp.vid('coaster-before');
 IF pg_temp.import80('coaster-after') IS DISTINCT FROM 'applied' THEN RAISE EXCEPTION 'Sub Status 80 did not apply after the tick'; END IF;
 SELECT to_jsonb(p) INTO snap_after FROM pdc_fitter_private.operation_progress p WHERE p.booking_id = pg_temp.bid('coaster-after');
 IF snap IS DISTINCT FROM snap_after THEN RAISE EXCEPTION 'Sub Status 80 rewrote the ticked conversion % %', snap, snap_after; END IF;
 IF pg_temp.import80('coaster-after') IS DISTINCT FROM 'skipped' THEN RAISE EXCEPTION 'second Sub Status 80 was not skipped'; END IF;
 IF (SELECT count(*) FROM pdc_codex_intake_private.tune_pmb_complete_receipts WHERE vehicle_id = pg_temp.vid('coaster-after')) <> 1 THEN
  RAISE EXCEPTION 'Sub Status 80 stored more than one receipt';
 END IF;
 SELECT notes INTO phrase FROM public.vehicle_work_items WHERE vehicle_id = pg_temp.vid('coaster-after') AND work_key = 'bus4x4';
 n := (length(phrase) - length(replace(phrase, 'Sub Status 80', ''))) / length('Sub Status 80');
 IF n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'Sub Status 80 completion note count is %', n; END IF;
 SELECT completed INTO qc_done FROM public.vehicle_work_items WHERE vehicle_id = pg_temp.vid('coaster-after') AND work_key = 'qc';
 IF qc_done THEN RAISE EXCEPTION 'Sub Status 80 completed QC'; END IF;
 SELECT default_duration_minutes INTO dur FROM public.workshop_bookings WHERE id = pg_temp.bid('coaster-after');
 IF dur IS DISTINCT FROM 3600 THEN RAISE EXCEPTION 'Sub Status 80 changed booking hours to %', dur; END IF;
 IF (SELECT count(*) FROM pdc_fitter_private.conversion_state) <> 1
    OR (SELECT count(*) FROM pdc_fitter_private.conversion_audit) <> 0 THEN
  RAISE EXCEPTION 'import fabricated or removed section history';
 END IF;
 IF (SELECT s.sections FROM pdc_fitter_private.conversion_state s WHERE s.vehicle_id = pg_temp.vid('coaster-before')) IS DISTINCT FROM sections THEN
  RAISE EXCEPTION 'section history changed';
 END IF;

 result := pg_temp.tick('hiace-99', true);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'HiAce tick failed %', result; END IF;
 SELECT l INTO line FROM jsonb_array_elements(pdc_fitter_private.lines(pg_temp.vid('hiace-99'), pg_temp.bid('hiace-99'))) l;
 IF (line#>>'{conversion,id}') IS DISTINCT FROM 'hiace_commuter' OR (line#>>'{conversion,total_minutes}')::integer IS DISTINCT FROM 2280 THEN
  RAISE EXCEPTION 'HiAce planning allowance changed %', line;
 END IF;
 IF (line->>'hours')::numeric IS DISTINCT FROM 40 THEN RAISE EXCEPTION 'HiAce operation hours changed'; END IF;
 SELECT to_jsonb(p) INTO snap FROM pdc_fitter_private.operation_progress p WHERE p.booking_id = pg_temp.bid('hiace-99');
 IF pg_temp.import99('hiace-99') IS DISTINCT FROM 'applied' THEN RAISE EXCEPTION 'Sub Status 99 did not apply after the tick'; END IF;
 SELECT to_jsonb(p) INTO snap_after FROM pdc_fitter_private.operation_progress p WHERE p.booking_id = pg_temp.bid('hiace-99');
 IF snap IS DISTINCT FROM snap_after THEN RAISE EXCEPTION 'Sub Status 99 rewrote the ticked conversion'; END IF;
 IF pg_temp.import99('hiace-99') IS DISTINCT FROM 'skipped' THEN RAISE EXCEPTION 'second Sub Status 99 was not skipped'; END IF;
 IF (SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id = pg_temp.vid('hiace-99')) <> 1 THEN
  RAISE EXCEPTION 'Sub Status 99 stored more than one receipt';
 END IF;
 SELECT notes INTO phrase FROM public.vehicle_work_items WHERE vehicle_id = pg_temp.vid('hiace-99') AND work_key = 'bus4x4';
 n := (length(phrase) - length(replace(phrase, 'Sub Status 99', ''))) / length('Sub Status 99');
 IF n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'Sub Status 99 completion note count is %', n; END IF;
 SELECT completed INTO qc_done FROM public.vehicle_work_items WHERE vehicle_id = pg_temp.vid('hiace-99') AND work_key = 'qc';
 IF qc_done THEN RAISE EXCEPTION 'Sub Status 99 completed QC'; END IF;
 IF (SELECT completed FROM public.vehicle_work_items WHERE vehicle_id = pg_temp.vid('hiace-99') AND work_key = 'bus4x4') IS NOT TRUE THEN
  RAISE EXCEPTION 'Sub Status 99 reopened the conversion work item';
 END IF;

 result := pg_temp.tick('review', true);
 IF result->>'error' IS DISTINCT FROM 'conversion_sections_required' THEN
  RAISE EXCEPTION 'review conversion accepted a tick %', result;
 END IF;
 BEGIN
  INSERT INTO pdc_fitter_private.operation_progress(booking_id, line_identity, scope_hash, completed, technician_id, updated_by)
  VALUES (pg_temp.bid('review'), 'source:1', 'scope-review', true, '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1');
  RAISE EXCEPTION 'review progress insert was not blocked';
 EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%conversion_sections_required%' THEN RAISE EXCEPTION 'review insert raised %', SQLERRM; END IF;
 END;
 IF pg_temp.import80('tyres') IS DISTINCT FROM 'applied' THEN RAISE EXCEPTION 'accessory import was blocked'; END IF;
 IF (SELECT completed FROM public.vehicle_work_items WHERE vehicle_id = pg_temp.vid('tyres') AND work_key = 'qc') THEN
  RAISE EXCEPTION 'accessory import completed QC';
 END IF;
END $after$;
